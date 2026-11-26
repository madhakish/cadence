"""Export the category bar photograph and the unlabelled dumbbell for native UI.

The main category uses Astra 07 as an illustrative scene. For the dumbbell,
the existing Cadence accessory photograph supplies the shape and lighting;
Astra 05 supplies rubber, and the knurled shaft in Astra 08 supplies steel.
The view sets the real per-implement weight separately in Dynamic Type.
Run with Pillow and NumPy from any directory.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SOURCE = Path(__file__).resolve().parent
ASSETS = SOURCE.parents[2] / "Cadence/Assets.xcassets"


def install(name, filename, image):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(exist_ok=True)
    catalog = {"images": [{"filename": filename, "idiom": "universal"}],
               "info": {"author": "xcode", "version": 1},
               "properties": {"template-rendering-intent": "original"}}
    (folder / "Contents.json").write_text(json.dumps(catalog, indent=2) + "\n")
    if filename.endswith(".jpg"):
        image.save(folder / filename, quality=90, subsampling=0, optimize=True)
    else:
        image.save(folder / filename, optimize=True)


def dumbbell():
    base = Image.open(ASSETS / "TrainingContextAccessory.imageset/accessory.png").convert("RGBA")
    # Trace the front dumbbell where the other two implements overlap it.
    outline = [
        (213, 329), (216, 305), (224, 284), (236, 268), (250, 255), (269, 246),
        (293, 238), (308, 236), (332, 240), (351, 246), (363, 255), (374, 269),
        (381, 286), (385, 312), (431, 326), (438, 308), (450, 292), (465, 281),
        (484, 274), (497, 273), (548, 282), (564, 287), (579, 301), (588, 319),
        (594, 343), (595, 369), (591, 397), (582, 423), (568, 445), (553, 461),
        (537, 471), (522, 475), (508, 474), (461, 461), (445, 452), (431, 438),
        (425, 419), (421, 395), (421, 376), (371, 362), (364, 382), (352, 401),
        (339, 413), (321, 421), (305, 423), (292, 422), (250, 406), (234, 399),
        (223, 384), (215, 364), (212, 346),
    ]
    matte = Image.new("L", base.size)
    ImageDraw.Draw(matte).polygon(outline, fill=255)
    matte = matte.filter(ImageFilter.GaussianBlur(0.7))
    y, x = np.indices((base.height, base.width))
    luma = np.asarray(base.convert("L"), dtype=float)
    relief = np.asarray(base.convert("L").filter(ImageFilter.GaussianBlur(2.2)), dtype=float)
    # Wrap an unlettered surface sample from the black rubber bumper over both
    # heads. Retain the original curved highlights, rim and recessed end cap.
    black = Image.open(SOURCE / "05-platform-white-oak-black.png")
    patch = np.asarray(black.crop((329, 461, 354, 516)).convert("L"), dtype=float)
    rubber = patch[y % patch.shape[0], x % patch.shape[1]] - np.mean(patch)
    heads = (relief * 0.82 + luma * 0.18 + rubber * 0.63)[:, :, None] * [0.94, 0.98, 1.0]

    # Map the photographed steel shaft along the inclined grip. The collar
    # at its left end and both heads retain their own profiles.
    run = x - 334
    across = y - (311 + 0.265 * run)
    grip = (run >= 0) & (x < 434 - across * 0.28) & (across >= 0) & (across < 40)
    overhead = Image.open(SOURCE / "08-platform-overhead.png")
    metal = np.asarray(overhead.crop((520, 268, 645, 283)), dtype=float)
    reflection = metal[np.clip(across * metal.shape[0] / 40, 0, metal.shape[0] - 1).astype(int),
                       run % metal.shape[1]]
    heads[grip] = (reflection * (0.48 + 0.52 * luma[:, :, None] / 170))[grip]
    result = Image.fromarray(np.clip(heads, 0, 255).astype("uint8"))
    alpha = np.minimum(np.asarray(matte), np.asarray(base.getchannel("A")))
    result.putalpha(Image.fromarray(alpha))
    return result.crop((207, 231, 601, 481))


if __name__ == "__main__":
    bar = Image.open(SOURCE / "07-platform-maple-yellow.png").convert("RGB")
    bar.thumbnail((780, 520), Image.Resampling.LANCZOS)
    install("AstraMainEquipmentContext", "maple-bar.jpg", bar)
    install("AstraDumbbell", "dumbbell.png", dumbbell())
