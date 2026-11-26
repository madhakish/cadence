"""Extract the five labeled pound bumpers from the Astra plate-loading master."""

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[3]
MASTER = ROOT / "docs/design-pass/astra-2026-11-01/01-screen-plate-loading.png"
CATALOG = ROOT / "Cadence/Assets.xcassets"
# Boundaries between the five upright plates in the original 853 × 1844 image.
PLATES = [(55, 28, 190), (45, 190, 351), (35, 352, 513), (25, 514, 674), (10, 675, 837)]


def isolate_plate(master, pounds, left, right):
    crop = master.crop((left, 1377, right, 1571))
    mask = Image.new("L", crop.size)
    outline = ImageDraw.Draw(mask)
    for y in range(crop.height):
        edges = []
        for x in range(crop.width):
            rgb = crop.getpixel((x, y))
            # Colored rubber separates by chroma; white rubber by brightness.
            foreground = min(rgb) > 50 if pounds == 10 else max(rgb) - min(rgb) > 14
            if foreground:
                edges.append(x)
        if edges:
            outline.line((edges[0], y, edges[-1], y), fill=255)
    crop.putalpha(mask.filter(ImageFilter.GaussianBlur(0.55)))
    return crop


def main():
    if hashlib.sha256(MASTER.read_bytes()).hexdigest() != "a2ae3010d44568e055f6b0e203846f51c96011bd593d7bf8db0a4df1f03c7069":
        raise ValueError("The source composition changed. Check the crop coordinates against the new master.")
    with Image.open(MASTER) as master:
        for pounds, left, right in PLATES:
            plate = isolate_plate(master, pounds, left, right)
            plate.thumbnail((156, 156), Image.Resampling.LANCZOS)
            export = Image.new("RGBA", (156, 156))
            export.alpha_composite(plate, ((156 - plate.width) // 2, (156 - plate.height) // 2))
            target = CATALOG / f"AstraBumper{pounds}lb.imageset"
            target.mkdir(exist_ok=True)
            export.save(target / "plate.png", optimize=True)
            contents = {
                "images": [{"filename": "plate.png", "idiom": "universal", "scale": "3x"}],
                "info": {"author": "xcode", "version": 1},
            }
            (target / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


if __name__ == "__main__":
    main()
