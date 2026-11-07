"""Regression tests for flip_guard.sh, on synthetic images. Needs FLIP_VENV (see flip_guard.sh):

    "$FLIP_VENV/bin/python" -I proof/texture-rig/test_flip_guard.py

Each refusal case below is a hole an adversarial review found and reproduced.
"""
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest

from PIL import Image, ImageCms, PngImagePlugin

GUARD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "flip_guard.sh")
VENV = os.environ.get("FLIP_VENV") or sys.exit("set FLIP_VENV to the guard's venv")


def png(path, colour=(128, 128, 128), square=None, mode="RGB", alpha=255, gamma=None, srgb=False, icc=False):
    """256 x 256 flat image, optionally with a 64 x 64 square of another colour and colour tags."""
    im = Image.new(mode, (256, 256), colour + ((alpha,) if mode == "RGBA" else ()))
    if square:
        im.paste(square + ((alpha,) if mode == "RGBA" else ()), (96, 96, 160, 160))
    info = PngImagePlugin.PngInfo()
    if gamma is not None:
        info.add(b"gAMA", struct.pack(">I", round(gamma * 100000)))
    if srgb:
        info.add(b"sRGB", b"\x00")
    kw = {"icc_profile": ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()} if icc else {}
    im.save(path, pnginfo=info, **kw)
    return path


class FlipGuard(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.out = os.path.join(self.dir, "out")
        self.golden = png(os.path.join(self.dir, "golden.png"))

    def tearDown(self):
        self.tmp.cleanup()

    def guard(self, candidate, golden=None, **env):
        e = {k: v for k, v in os.environ.items() if k not in ("FLIP_MAX_MEAN", "FLIP_MAX_WMEDIAN")}
        e["FLIP_VENV"] = VENV
        e.update(env)
        e = {k: v for k, v in e.items() if v is not None}
        return subprocess.run(["bash", GUARD, golden or self.golden, candidate, self.out], env=e,
                              capture_output=True, text=True).returncode

    def manifest(self, stem="candidate"):
        with open(os.path.join(self.out, f"{stem}-flip.json")) as f:
            return json.load(f)

    def golden_bytes(self):
        with open(self.golden, "rb") as f:
            return f.read()

    def outputs(self):
        return sorted(os.listdir(self.out)) if os.path.isdir(self.out) else []

    def test_identical_passes_and_records_hashes(self):
        cand = png(os.path.join(self.dir, "candidate.png"))
        self.assertEqual(self.guard(cand), 0)
        m = self.manifest()
        self.assertTrue(m["pass"])
        self.assertEqual(m["flip"]["mean"], 0.0)
        self.assertEqual(m["golden"]["sha256"], m["candidate"]["sha256"])
        self.assertEqual(self.outputs(), ["candidate-flip.json", "candidate-flip.png"])

    def test_visible_change_fails(self):
        cand = png(os.path.join(self.dir, "candidate.png"), square=(160, 128, 96))
        self.assertEqual(self.guard(cand), 1)
        self.assertFalse(self.manifest()["pass"])
        self.assertIn("weightedMedian", self.manifest()["failed"])

    def test_threshold_is_configurable(self):
        cand = png(os.path.join(self.dir, "candidate.png"), square=(160, 128, 96))
        self.assertEqual(self.guard(cand, FLIP_MAX_MEAN="1", FLIP_MAX_WMEDIAN="1"), 0)

    def test_cant_judge(self):
        cases = {
            "size": lambda p: Image.new("RGB", (128, 128), (128, 128, 128)).save(p),
            "transparent pixel": lambda p: png(p, mode="RGBA", alpha=254),
            "grey": lambda p: Image.new("L", (256, 256), 128).save(p),
            "16-bit": lambda p: Image.new("I;16", (256, 256), 128 * 257).save(p),
            "linear gAMA": lambda p: png(p, gamma=1.0),
            "ICC profile": lambda p: png(p, icc=True),
        }
        for name, make in cases.items():
            with self.subTest(name):
                path = os.path.join(self.dir, f"{name}.png")
                make(path)
                self.assertEqual(self.guard(path), 2)

    def test_matching_non_srgb_tags_are_still_refused(self):
        # Both sides linear (gAMA 1.0): FLIP would read them as sRGB and pass a change that fails once converted.
        golden = png(os.path.join(self.dir, "lin-golden.png"), colour=(0, 0, 0), gamma=1.0)
        cand = png(os.path.join(self.dir, "candidate.png"), colour=(0, 0, 0), square=(1, 1, 1), gamma=1.0)
        self.assertEqual(self.guard(cand, golden=golden), 2)

    def test_srgb_chunk_compares_with_untagged(self):
        cand = png(os.path.join(self.dir, "candidate.png"), srgb=True)
        self.assertEqual(self.guard(cand), 0)

    def test_refusal_removes_an_earlier_verdict(self):
        cand = png(os.path.join(self.dir, "candidate.png"))
        for env in ({"FLIP_MAX_MEAN": "nan"}, {"FLIP_VENV": None}, {"FLIP_VENV": "/nonexistent"}):
            with self.subTest(env):
                self.assertEqual(self.guard(cand), 0)
                self.assertEqual(len(self.outputs()), 2)
                self.assertEqual(self.guard(cand, **env), 2)
                self.assertEqual(self.outputs(), [])

    def test_planted_symlink_never_reaches_the_golden(self):
        before = self.golden_bytes()
        cand = png(os.path.join(self.dir, "candidate.png"), square=(160, 128, 96))
        os.makedirs(self.out)
        os.symlink(self.golden, os.path.join(self.out, "candidate-flip.json.tmp"))  # the old temp name
        self.assertEqual(self.guard(cand), 1)
        self.assertEqual(self.golden_bytes(), before)
        os.symlink(self.golden, os.path.join(self.out, "candidate-flip.png.lnk"))
        os.replace(os.path.join(self.out, "candidate-flip.png.lnk"), os.path.join(self.out, "candidate-flip.png"))
        self.assertEqual(self.guard(cand), 2)  # an output name that resolves to an input: refuse, touch nothing
        self.assertEqual(self.golden_bytes(), before)

    def test_output_that_is_an_input_is_refused(self):
        os.makedirs(self.out)
        golden = png(os.path.join(self.out, "candidate-flip.png"))
        cand = png(os.path.join(self.dir, "candidate.png"))
        self.assertEqual(self.guard(cand, golden=golden), 2)
        self.assertTrue(os.path.isfile(golden))


if __name__ == "__main__":
    unittest.main(verbosity=2)
