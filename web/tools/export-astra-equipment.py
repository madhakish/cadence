"""Export the web renderer's inputs from Cadence's native Astra asset catalog."""
from pathlib import Path
import json
import shutil

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Cadence/Assets.xcassets"
OUTPUT = ROOT / "web/app/assets/astra"
SAMPLE = Image.Resampling.LANCZOS


def source(asset):
    folder = CATALOG / (asset + ".imageset")
    images = json.loads((folder / "Contents.json").read_text())["images"]
    return folder / next(entry["filename"] for entry in images if "filename" in entry)


def platform(panel, filename):
    # One top-down material map for the physical 8 ft square. The engraving
    # appears once in the 4 ft oak center. Both cameras project the same map.
    oak = Image.open(source(panel)).convert("RGB").resize((512, 1024), SAMPLE)
    mask = Image.open(source("AstraHeritageBurn")).getchannel("A")
    side = round(512 * 950 / 1219.2)
    alpha = Image.new("L", oak.size)
    alpha.paste(mask.resize((side, side), SAMPLE), ((512 - side) // 2, (1024 - side) // 2))
    ink = np.asarray(alpha, dtype=float)[:, :, None] * (0.88 / 255)
    linear = (np.asarray(oak, dtype=float) / 255) ** 2.2
    burned = linear * (1 - ink) + np.array([0.028, 0.014, 0.007]) * ink
    top = Image.new("RGB", (1024, 1024))
    top.paste(Image.fromarray(np.rint(255 * burned ** (1 / 2.2)).astype("uint8")), (256, 0))
    mat = Image.open(source("PlatformMat")).convert("RGB").resize((128, 128), SAMPLE)
    for x in (0, 128, 768, 896):
        for y in range(0, 1024, 128):
            top.paste(mat, (x, y))
    top.save(OUTPUT / filename, quality=91, method=6)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for panel, finish in [("Oak", "oak"), ("Walnut", "walnut"), ("WhiteOak", "white-oak"), ("Maple", "maple")]:
        platform("Platform" + panel, f"platform-{finish}.webp")
    room = Image.open(source("AstraStudioRoom"))
    room.crop((0, 343, room.width, 532)).save(OUTPUT / "room-band.webp", quality=88, method=6)
    for value in [10, 25, 35, 45, 55]:
        shutil.copyfile(source(f"AstraBumper{value}lb"), OUTPUT / f"bumper-{value}lb.png")
    for name, asset in {"room.jpg": "AstraStudioRoom", "sleeve.png": "AstraSleeve",
                        "chrome-roughness.png": "AstraChromeRoughness", "hub.png": "AstraPlateHub",
                        "main-context.jpg": "AstraMainEquipmentContext", "dumbbell.png": "AstraDumbbell",
                        "rubber.png": "AstraPlateRubber", "black-rubber.png": "AstraPlateBlackRubber",
                        "powder.png": "AstraPlatePowder", "gloss.png": "AstraPlateGloss",
                        "cast-iron.png": "AstraPlateCastIron", "machined.png": "AstraPlateMachined",
                        "hammertone.png": "AstraPlateHammertone"}.items():
        shutil.copyfile(source(asset), OUTPUT / name)


if __name__ == "__main__":
    main()
