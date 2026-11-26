"""Make unlettered plate faces from the Astra masters. Requires NumPy and Pillow.

In original pixels each sample gives the centre of the front face, the end
of its horizontal radius and the end of its tilted vertical radius. Only the
listed unprinted angular sector is projected; collars and stamped weights
are absent by construction. The runtime supplies the theme paint and label.
"""
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
MASTERS = ROOT / "docs/design-pass/astra-2026-11-01"
CATALOG = ROOT / "Cadence/Assets.xcassets"
SIZE = 312
Y, X = np.mgrid[0:SIZE, 0:SIZE]
X = (X + 0.5 - SIZE / 2) / (SIZE * 0.468)
Y = (Y + 0.5 - SIZE / 2) / (SIZE * 0.468)
R = np.hypot(X, Y)
THETA = np.arctan2(Y, X)


@dataclass(frozen=True)
class Specimen:
    filename: str
    centre: tuple
    horizontal: tuple
    vertical: tuple
    sector: tuple


RUBBER = Specimen("03-platform-oak-blue.png", (359, 445), (109, 10), (10, 201), (-27, -5))
COATING = Specimen("04-platform-walnut-calibrated.png", (264, 366), (66, 8), (15, 188), (64, 109))
BLACK = Specimen("05-platform-white-oak-black.png", (266, 484), (95, 14), (20, 220), (22, 53))
CAST = Specimen("06-platform-oak-iron.png", (249, 398), (78, 9), (16, 205), (19, 42))


def sample(image, x, y):
    """Bilinear sample of a grayscale source in its original coordinates."""
    ix, iy = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x-ix, y-iy
    return ((1-fx)*(1-fy)*image[iy, ix] + fx*(1-fy)*image[iy, ix+1]
            + (1-fx)*fy*image[iy+1, ix] + fx*fy*image[iy+1, ix+1])


def photo_field(photo, radius=R):
    source = np.asarray(Image.open(MASTERS / photo.filename).convert("L"), dtype=float)
    lo, hi = np.deg2rad(photo.sector)
    angle = lo + (hi-lo) * (0.5 + 0.5*np.sin(THETA + 0.4))
    u, v = np.cos(angle)*np.clip(radius, 0.34, 0.995), np.sin(angle)*np.clip(radius, 0.34, 0.995)
    sx = photo.centre[0] + photo.horizontal[0]*u + photo.vertical[0]*v
    sy = photo.centre[1] + photo.horizontal[1]*u + photo.vertical[1]*v
    field = sample(source, sx, sy)
    return np.log(np.maximum(field, 4) / np.median(field[(R>.5) & (R<.85)]))


def relief(radius, width):
    return np.exp(-((R-radius)/width)**2)


def export(name, array, filename):
    dest = CATALOG / f"AstraPlate{name}.imageset"
    dest.mkdir(exist_ok=True)
    image = Image.fromarray(np.round(np.clip(array, 0, 255)).astype("uint8"))
    image = image.resize((156, 156), Image.Resampling.LANCZOS)
    image.save(dest/filename, optimize=True)
    catalog = {"images": [{"filename": filename, "idiom": "universal", "scale": "3x"}],
               "info": {"author": "xcode", "version": 1}}
    (dest/"Contents.json").write_text(json.dumps(catalog, indent=2)+"\n")


def main():
    # Use the source samples' own ridges, grain and specular breakup. The
    # neutral 50% field accepts any rack colour through a hard-light blend.
    faces = {"Rubber": RUBBER, "BlackRubber": BLACK, "Powder": COATING,
             "Gloss": COATING, "CastIron": CAST, "Hammertone": CAST, "Machined": COATING}
    records = json.loads((MASTERS/"image-manifest.json").read_text())
    records = records if isinstance(records, list) else records["images"]
    # Original archive calls this field 'file'.
    source_hashes = {entry["file"]: entry["sha256"] for entry in records}
    for photo in set(faces.values()):
        if hashlib.sha256((MASTERS/photo.filename).read_bytes()).hexdigest() != source_hashes[photo.filename]:
            raise ValueError(f"Changed master: {photo.filename}")
    light = -0.5*X - 0.86*Y
    alpha = np.clip((1-R)*SIZE, 0, 1)*np.clip((R-.175)*SIZE, 0, 1)
    for name, specimen in faces.items():
        field = photo_field(specimen)
        detail_asset = {RUBBER: "Bumper", BLACK: "BlackRubber", COATING: "CalibratedCoating", CAST: "CastIron"}[specimen]
        detail_path = next((CATALOG/f"Astra{detail_asset}Detail.imageset").glob("*.png"))
        detail = Image.open(detail_path).convert("L").resize((SIZE*2,SIZE*2), Image.Resampling.LANCZOS)
        grain = np.asarray(detail.crop((SIZE//2,SIZE//2,3*SIZE//2,3*SIZE//2)), dtype=float)
        grain -= np.median(grain)
        response = {"Rubber": .63, "BlackRubber": .56, "Powder": .5, "Gloss": .25,
                    "CastIron": 1.30, "Hammertone": .9, "Machined": .1}[name]
        tone = 127 + 26*np.tanh(field*1.4) + 11*light + grain*response
        bevel = relief(0.974, .022)*(48*light-11) - 45*relief(.999, .018)
        if name in ["Rubber", "BlackRubber"]:
            tone += 17*relief(.841,.020)*light - 16*relief(.818,.017)
        elif name in ["Powder", "Gloss"]:
            tone += 20*relief(.866,.022)*light - 15*relief(.836,.015)
            if name=="Gloss":
                tone += 28*np.exp(-((X*.75+Y*.36+.38)/.19)**2)
        elif name=="CastIron":
            tone += 38*relief(.787,.025)*light - 33*relief(.754,.035)
        elif name=="Hammertone":
            # Hammered enamel uses the 06 cast texture in a tighter relief.
            small = photo_field(CAST, .40 + .50*np.mod(R*3, 1))
            tone += 8*np.tanh(small*2) + 16*relief(.87,.028)*light
        elif name=="Machined":
            # Turned tooling lines and anisotropic steel reflections over 04.
            tone = (122 + 12*np.tanh(field) + 31*np.cos(2*THETA+1)
                    + 9*np.cos(THETA-1.8) + 6*np.sin(2*np.pi*R*42)
                    + 29*relief(.86,.025)*light)
        gray = np.clip(tone+bevel, 0, 255)
        export(name, np.stack([gray,gray,gray,255*alpha],axis=-1), "face.png")

    # The unobstructed metal insert is the 45 lb reference plate from 01.
    # The engraved words and digits lie entirely outside this crop.
    face = np.asarray(Image.open(CATALOG/"AstraBumper45lb.imageset/plate.png").convert("L"),dtype=float)
    ring_radius=.347
    hub = sample(face, 87 + 17.5*np.clip(X/ring_radius,-1,1), 81 + 27.4*np.clip(Y/ring_radius,-1,1))
    hub_alpha = np.clip((ring_radius-R)*SIZE,0,1) * np.clip((R-.14)*SIZE,0,1)
    export("Hub", np.stack([hub,hub,hub,255*hub_alpha],axis=-1), "hub.png")


if __name__=="__main__":
    main()
