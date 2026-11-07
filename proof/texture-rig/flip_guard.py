"""FLIP guard, run by flip_guard.sh with FLIP_VENV's Python: python -I flip_guard.py <golden.png> <candidate.png> <out-dir>

Runs NVIDIA's FLIP tool (LDR-FLIP, flip-evaluator 1.7, 67 pixels per degree) on a golden render and a
candidate, keeps the magma error map, and writes a manifest with FLIP's pooled numbers and the SHA-256
of both inputs. Exit 0 within thresholds, 1 over one, 2 when it can't judge (bad input, broken venv).

Two gates, because one number can't hold both kinds of regression (calibration: RENDERER-CONTRACT.md):
  mean FLIP            <= FLIP_MAX_MEAN    (default 0.001)  a tint or shift spread over the equipment
  weighted median FLIP <= FLIP_MAX_WMEDIAN (default 0.05)   a strong local change, e.g. a shadow that moved,
                                                            which barely dents the mean of a whole frame
Max is recorded, not gated: one stray pixel owns it.
"""
import datetime as dt
import hashlib
import importlib.metadata
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import traceback

FLIP_VERSION = "1.7"
PPD = 67  # FLIP's default observer; passed explicitly so a new default can't move the thresholds
DEFAULTS = {"FLIP_MAX_MEAN": 0.001, "FLIP_MAX_WMEDIAN": 0.05}
POOLED = {"Mean": "mean", "Weighted median": "weightedMedian", "1st weighted quartile": "weightedQuartile1",
          "3rd weighted quartile": "weightedQuartile3", "Min": "min", "Max": "max"}
HERE = os.path.dirname(os.path.abspath(__file__))


class Refuse(Exception):
    """The guard can't give a verdict; exit 2 rather than pass or fail on a guess."""


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def threshold(name):
    raw = os.environ.get(name, "")
    if raw == "":
        return DEFAULTS[name]
    try:
        value = float(raw)
    except ValueError:
        raise Refuse(f"{name}={raw!r} is not a number")
    if not math.isfinite(value) or value < 0:
        raise Refuse(f"{name}={raw!r} must be a finite number >= 0")
    return value


def inspect(path, role):
    """An 8-bit RGB or opaque RGBA PNG, decoded in full. FLIP reads RGB only and treats it as sRGB,
    so transparency or 16-bit data would be compared as something it isn't."""
    from PIL import Image

    if not os.path.isfile(path):
        raise Refuse(f"{role} not found: {path}")
    data = open(path, "rb").read()
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise Refuse(f"{role} is not a PNG: {path}")
    depth, colour = data[24], data[25]
    if depth != 8 or colour not in (2, 6):
        raise Refuse(f"{role} is bit depth {depth}, colour type {colour}; the guard compares 8-bit RGB/RGBA PNGs: {path}")
    try:
        with Image.open(path) as im:
            im.load()
            if "transparency" in im.info:
                raise Refuse(f"{role} has a tRNS transparent colour; FLIP ignores alpha: {path}")
            if im.mode == "RGBA":
                lo = im.getchannel("A").getextrema()[0]
                if lo != 255:
                    raise Refuse(f"{role} has transparent pixels (alpha min {lo}); FLIP ignores alpha, "
                                 f"so flatten it onto the background the app shows first: {path}")
            return {"path": os.path.abspath(path), "sha256": sha256(data), "size": list(im.size), "mode": im.mode,
                    "colour": srgb_or_refuse(im.info, role, path)}
    except Refuse:
        raise
    except Exception as e:  # truncated or corrupt data
        raise Refuse(f"{role} doesn't decode ({e}): {path}")


def srgb_or_refuse(info, role, path):
    """FLIP reads every PNG as sRGB and ignores colour tags, so anything tagged otherwise would be
    judged as the wrong colours, and matching tags on both sides don't make that right (two linear
    gAMA 1.0 renders were scored PASS on a change that FAILs once converted). Untagged and sRGB-chunk
    PNGs are sRGB; an sRGB chunk overrides gAMA/cHRM (PNG spec). Everything else is refused."""
    if info.get("icc_profile"):
        tag = "an ICC profile"
    elif "srgb" in info:
        return "sRGB chunk"
    elif "gamma" in info or "chromaticity" in info:
        tag = f"gAMA {info.get('gamma')} / cHRM {info.get('chromaticity')}"
    else:
        return "untagged (sRGB)"
    raise Refuse(f"{role} carries {tag}; FLIP would read it as sRGB anyway. Convert it to sRGB "
                 f"(or strip the tag if the pixels already are): {path}")


def pooled(text):
    values = {}
    for line in text.splitlines():
        key, _, value = line.partition(": ")
        if key in POOLED:
            values[POOLED[key]] = float(value)
    missing = sorted(set(POOLED.values()) - set(values))
    if missing or not all(math.isfinite(v) and 0 <= v <= 1 for v in values.values()):
        raise Refuse(f"FLIP's pooled values don't parse (missing {missing}): {text!r}")
    return values


def main(argv):
    if len(argv) != 3:
        raise Refuse("usage: flip_guard.sh <golden.png> <candidate.png> <out-dir>")
    golden_path, candidate_path, out_dir = argv
    stem = os.path.splitext(os.path.basename(candidate_path))[0]
    map_path = os.path.join(os.path.abspath(out_dir), f"{stem}-flip.png")
    manifest_path = os.path.join(os.path.abspath(out_dir), f"{stem}-flip.json")
    for p in (golden_path, candidate_path):
        if os.path.realpath(p) in (os.path.realpath(map_path), os.path.realpath(manifest_path)):
            raise Refuse(f"{p} is where this run writes its output; pick another out-dir")
    # First, before anything can refuse: a verdict from an earlier run must never sit beside
    # inputs it didn't judge. unlink removes a symlink, not what it points at.
    for p in (map_path, manifest_path):
        if os.path.lexists(p):
            os.unlink(p)

    venv = os.environ.get("FLIP_VENV", "")
    if not venv:
        raise Refuse("FLIP_VENV is not set; point it at a venv with flip-evaluator==1.7 and pillow (see flip_guard.sh)")
    if os.path.realpath(sys.prefix) != os.path.realpath(venv):
        raise Refuse(f"FLIP_VENV={venv} has no usable bin/python (this is {sys.executable})")
    try:
        version = importlib.metadata.version("flip-evaluator")
    except importlib.metadata.PackageNotFoundError:
        raise Refuse(f"flip-evaluator is not installed in {sys.prefix}")
    if version != FLIP_VERSION:
        raise Refuse(f"flip-evaluator {version} in {sys.prefix}; the thresholds were calibrated on {FLIP_VERSION}")
    flip = os.path.join(sys.prefix, "bin", "flip")
    if not os.access(flip, os.X_OK):
        raise Refuse(f"no flip executable at {flip}")
    limits = {"mean": threshold("FLIP_MAX_MEAN"), "weightedMedian": threshold("FLIP_MAX_WMEDIAN")}
    guard = {f: sha256(open(os.path.join(HERE, f), "rb").read()) for f in ("flip_guard.sh", "flip_guard.py")}

    golden, candidate = inspect(golden_path, "golden"), inspect(candidate_path, "candidate")
    if golden["size"] != candidate["size"]:
        raise Refuse(f"golden is {golden['size']} but candidate is {candidate['size']}; FLIP compares equal sizes only")

    os.makedirs(out_dir, exist_ok=True)
    work = tempfile.mkdtemp(prefix=".flip-", dir=out_dir)
    try:
        run = subprocess.run([flip, "-r", golden["path"], "-t", candidate["path"], "-d", work, "-b", "flip",
                              "-ppd", str(PPD), "-txt", "-v", "0"], capture_output=True, text=True)
        produced_map, produced_txt = os.path.join(work, "flip.png"), os.path.join(work, "flip.txt")
        if run.returncode != 0 or not os.path.isfile(produced_map) or not os.path.isfile(produced_txt):
            raise Refuse(f"flip exited {run.returncode}: {(run.stdout + run.stderr).strip()}")
        values = pooled(open(produced_txt).read())
        failed = [k for k in ("mean", "weightedMedian") if values[k] > limits[k]]
        manifest = {
            "tool": {"name": "flip-evaluator", "version": version, "mode": "LDR", "ppd": PPD},
            "guard": guard,
            "golden": golden,
            "candidate": candidate,
            "errorMap": {"path": map_path, "sha256": sha256(open(produced_map, "rb").read())},
            "flip": values,
            "thresholds": limits,
            "pass": not failed,
            "failed": failed,
            "evaluatedAt": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        }
        produced_json = os.path.join(work, "flip.json")  # inside the fresh mkdtemp: nothing can be planted there
        with open(produced_json, "x") as f:
            json.dump(manifest, f, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(produced_map, map_path)
        os.replace(produced_json, manifest_path)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    verdict = "PASS" if not failed else "FAIL (" + ", ".join(failed) + ")"
    print(f"flip-guard: {stem} {verdict}: mean {values['mean']:.6f} (max {limits['mean']}), "
          f"weighted median {values['weightedMedian']:.6f} (max {limits['weightedMedian']}), "
          f"peak {values['max']:.6f}; map {map_path}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refuse as e:
        print(f"flip-guard: CAN'T JUDGE: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception:  # an uncaught error would exit 1, which reads as a regression; it isn't one
        traceback.print_exc()
        sys.exit(2)
