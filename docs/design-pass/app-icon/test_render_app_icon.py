"""Icon-choice regression tests; needs the generator's Pillow/numpy dependencies.

Run: python3 -B -m unittest discover -s docs/design-pass/app-icon -p 'test_*.py'
"""

import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import render_app_icon as icon


def png_bytes(image):
    output = io.BytesIO()
    image.save(output, format="PNG", optimize=True)
    return output.getvalue()


class IconCandidateTests(unittest.TestCase):
    def test_each_advertised_choice_supports_proof_and_install(self):
        source_hash = hashlib.sha256(Path(icon.SOURCE).read_bytes()).digest()
        icons = icon.candidates()
        appearances = {
            "A-parchment": ("B-iron-dark", "B-iron-tinted"),
            "B-iron": ("B-iron-dark", "B-iron-tinted"),
            "C-bust": ("C-bust-dark", "C-bust-tinted"),
        }
        for chosen, (dark, tinted) in appearances.items():
            with self.subTest(chosen=chosen):
                self.check_choice(icons, chosen, dark, tinted)
        self.assertEqual(hashlib.sha256(Path(icon.SOURCE).read_bytes()).digest(), source_hash)

    def check_choice(self, icons, chosen, dark, tinted):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ios, watch, proof = root / "ios", root / "watch", root / "proof"
            ios.mkdir()
            watch.mkdir()
            with mock.patch.multiple(icon, CHOSEN=chosen, IOS_SET=str(ios), WATCH_SET=str(watch)), \
                    mock.patch.object(icon, "candidates", return_value=icons):
                self.assertEqual(icon.main([str(proof), "--install"]), 0)
            expected = {"AppIcon.png": chosen, "AppIcon-Dark.png": dark, "AppIcon-Tinted.png": tinted}
            for filename, candidate in expected.items():
                self.assertEqual((ios / filename).read_bytes(), png_bytes(icons[candidate]))
            self.assertEqual((watch / "AppIcon.png").read_bytes(), (ios / "AppIcon.png").read_bytes())
            for name in ("icon-contact-sheet.png", "icon-appearances.png"):
                with icon.Image.open(proof / name) as image:
                    image.verify()

    def test_repeated_render_is_byte_identical(self):
        first = icon.candidates()
        second = icon.candidates()
        self.assertEqual(first.keys(), second.keys())
        for name in first:
            with self.subTest(candidate=name):
                self.assertEqual(png_bytes(first[name]), png_bytes(second[name]))


if __name__ == "__main__":
    unittest.main()
