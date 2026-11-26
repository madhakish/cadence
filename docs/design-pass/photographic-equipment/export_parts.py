#!/usr/bin/env python3
"""Extract the runtime photo layers. Requires Pillow and NumPy.

Run from any directory. --masters can point at a sibling worktree during art
production. Use --check to compare the committed assets to a fresh extraction.
"""

import argparse
from dataclasses import dataclass
from io import BytesIO
import json
from pathlib import Path

import numpy as np
from PIL import Image


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
CATALOG = PROJECT / "Cadence/Assets.xcassets"
ASTRA = HERE.parent / "astra-2026-11-01"
FACE_SIZE = 512


@dataclass(frozen=True)
class Plane:
    """Measured front face ellipse in the uncropped photographic master."""

    cx: float
    cy: float
    rx: float
    ry: float
    skew: float

    def source(self, u, v):
        return self.cx + self.rx * u + self.skew * v, self.cy + self.ry * v


@dataclass(frozen=True)
class Surface:
    master: str
    plane: Plane
    pigment: tuple
    insert: float


# The insert radius includes a safety band so original metallic pixels never
# migrate into the tintable body of a plate with different physical dimensions.
RUBBER = Surface("bumper", Plane(541.67, 616.04, 439.35, 572.69, 20.93), (34, 76, 157), .49)
BLACK = Surface("black", Plane(551.37, 639.14, 419.69, 569.50, 29.96), (34, 34, 36), .52)
COATED = Surface("coated", Plane(567.55, 621.61, 374.44, 567.65, 20.20), (34, 70, 147), .56)
IRON = Surface("iron", Plane(563.56, 593.50, 382.21, 543.54, 28.98), (50, 49, 48), .42)
# These two orthographic front masters are centred on their measured bore.
# The outer trim is inset 2–3 pixels to discard the alpha matte fringe.
HAMMERED = Surface("hammertone", Plane(650, 591, 562, 573, 0), (80, 77, 74), .35)
MACHINED = Surface("machined", Plane(622, 631, 593, 602, 0), (143, 143, 143), .38)
HUB = Plane(622, 625, 213, 220, 0)


def sample(source, x, y):
    """Bilinear lookup at source pixel centres."""
    height, width = source.shape[:2]
    x = np.clip(x, 0, width - 1)
    y = np.clip(y, 0, height - 1)
    x0, y0 = x.astype(int), y.astype(int)
    x1, y1 = np.minimum(x0 + 1, width - 1), np.minimum(y0 + 1, height - 1)
    dx, dy = (x - x0)[..., None], (y - y0)[..., None]
    top = source[y0, x0] * (1 - dx) + source[y0, x1] * dx
    bottom = source[y1, x0] * (1 - dx) + source[y1, x1] * dx
    return top * (1 - dy) + bottom * dy


def grid(size):
    axis = (np.arange(size) + .5) * (2 / size) - 1
    u, v = np.meshgrid(axis, axis)
    return u, v, np.hypot(u, v)


def radial_sample(source, plane, u, v, radius, mapped):
    scale = mapped / np.maximum(radius, 1e-6)
    return sample(source, *plane.source(u * scale, v * scale))


def neutral_light(pixels, pigment):
    """Invert the hard-light tint used in both clients, keeping real highlights.

    Find the nearest RGB value on the two segments for this photographed
    pigment. A neutral pixel at 128 reproduces the nominal pigment, and 255
    reproduces an untinted white highlight.
    """
    pigment = np.array(pigment, dtype=float)
    dark = np.clip(np.sum(pixels * pigment, axis=-1) / np.dot(pigment, pigment), 0, 1)
    white = 255 - pigment
    light = np.clip(np.sum((pixels - pigment) * white, axis=-1) / np.dot(white, white), 0, 1)
    dark_error = np.sum((pixels - dark[..., None] * pigment) ** 2, axis=-1)
    light_error = np.sum((pixels - (pigment + light[..., None] * white)) ** 2, axis=-1)
    return np.where(dark_error <= light_error, dark * 127.5, 127.5 + light * 127.5)


def disc_alpha(radius, inner=0):
    coverage = np.clip((1 - radius) * FACE_SIZE / 2 + .5, 0, 1)
    if inner:
        coverage *= np.clip((radius - inner) * FACE_SIZE / 2 + .5, 0, 1)
    return coverage


def bitmap(pixels, alpha):
    pixels = np.asarray(pixels)
    if pixels.ndim == 2:
        pixels = np.repeat(pixels[..., None], 3, axis=-1)
    rgba = np.dstack((pixels, alpha * 255)).round().clip(0, 255).astype(np.uint8)
    rgba[rgba[..., 3] == 0, :3] = 0
    return Image.fromarray(rgba)


def face(source, surface):
    u, v, radius = grid(FACE_SIZE)
    # Reflect a narrow, unprinted ring of the same face into the insert area.
    # A physical insert and shaft cover it on large plates. Small change
    # plates can reveal more of this diffuse material around their own hubs.
    mapped = np.where(radius < surface.insert,
                      surface.insert + .14 * np.tanh((surface.insert - radius) / .14), radius)
    rgb = radial_sample(source[..., :3], surface.plane, u, v, radius, mapped)
    return bitmap(neutral_light(rgb, surface.pigment), disc_alpha(radius, .10))


def edge(source, surface):
    # For each scanline sample the real tread between the front bevel and
    # rear silhouette. Clients project this swatch over the physical depth.
    height, width = FACE_SIZE, 96
    v = (np.arange(height) + .5) * (2 / height) - 1
    plane = surface.plane
    front, y = plane.source(np.sqrt(np.maximum(0, 1 - v * v)), v)
    opaque = source[..., 3] > 180
    back = opaque.shape[1] - 1 - opaque[np.rint(y).astype(int), ::-1].argmax(axis=1)
    along = (np.arange(width) + .5) / width
    x = (front + 2)[:, None] + (back - front - 5)[:, None] * along
    rgb = sample(source[..., :3], x, np.broadcast_to(y[:, None], x.shape))
    return bitmap(neutral_light(rgb, surface.pigment), np.ones(x.shape))


ASTRA_BLUE_FACE = Plane(359, 445, 113, 204, 10)


def feather(distance, width=.045):
    return np.clip(distance / width, 0, 1)


def rubber_face(bumper, original):
    # The unobstructed pixels of the approved image carry the actual surface
    # wear and bevel. Its photographed collar, shaft, fixed ink and steel disc
    # are replaced by the clean matching product master so the load stays live.
    result = np.array(face(bumper, RUBBER))
    u, v, radius = grid(FACE_SIZE)
    rgb = sample(original, *ASTRA_BLUE_FACE.source(u, v))
    rubber_chroma = rgb[..., 2] - np.maximum(rgb[..., 0], rgb[..., 1])
    clear = feather(radius - .49) * feather(rubber_chroma - 4, 10)
    for left, right, top, bottom in (
        (-1.2, .24, -.16, .31),       # sleeve and clamp
        (-.54, .58, -.76, -.32),      # CADENCE
        (-.41, .39, .42, .78),        # 45 LB
    ):
        outside = np.maximum.reduce((left - u, u - right, top - v, v - bottom))
        clear *= feather(outside, .10)
    gray = result[..., 0] * (1 - clear) + neutral_light(rgb, RUBBER.pigment) * clear
    return bitmap(gray, result[..., 3] / 255)


def rubber_edge(original):
    # Unwrap the near bumper from the actual image. At each elevation its
    # visible blue tread ends on black gym flooring or warm wood. The front
    # boundary is the measured face conic. Inset both limits to avoid pixels
    # from the floor/bar, while keeping the photographed bevel highlight.
    width = 96
    v = (np.arange(FACE_SIZE) + .5) * (2 / FACE_SIZE) - 1
    front, y = ASTRA_BLUE_FACE.source(np.sqrt(np.maximum(0, 1 - v * v)), v)
    strip = original[np.rint(y).astype(int), :575, :].astype(float)
    red, green, blue = np.moveaxis(strip, -1, 0)
    rubber = (blue > red * 1.07 + 5) & (blue > green * 1.03 + 2)
    x = np.arange(strip.shape[1])
    rear = np.max(np.where(rubber, x, 0), axis=1)
    left = front + 2
    right = np.maximum(left + 1, rear - 2)
    along = (np.arange(width) + .5) / width
    sample_x = left[:, None] + (right - left)[:, None] * along
    rgb = sample(original, sample_x, np.broadcast_to(y[:, None], sample_x.shape))
    return bitmap(neutral_light(rgb, RUBBER.pigment), np.ones(sample_x.shape))


def steel_shaft(original):
    # The exposed shaft between the near outer rim and far shoulder of 03.
    # Its receding diameter tapers in the master. Straighten and normalize
    # it once, retaining the two polished sections and the warm reflected oak.
    x = np.arange(541, 1312)
    top = 414.2 - .1096 * (x - 545)
    diameter = 28.5 - .005 * (x - 545)
    across = np.linspace(.025, .948, 30)[:, None]
    y = top + diameter * across
    rgb = sample(original, np.broadcast_to(x, y.shape), y)
    return bitmap(rgb, np.ones(y.shape))


def hub(machined):
    # The machined master is face-on. Its raised insert, the bevel lip and the
    # warm reflection are real, untinted RGB. The physical 50 mm bore is one
    # third of this canonical hub diameter in both clients.
    u, v, radius = grid(FACE_SIZE)
    mapped = .451 + (radius - 1 / 3) * (1 - .451) / (1 - 1 / 3)
    rgb = radial_sample(machined[..., :3], HUB, u, v, radius, mapped)
    return bitmap(rgb, disc_alpha(radius, 1 / 3))


def ink_cutout(rgb, alpha, background):
    background = np.array(background)
    ink = (rgb - background * (1 - alpha[..., None])) / np.maximum(.16, alpha[..., None])
    return bitmap(ink, alpha)


def bumper_stamps(original):
    # Both gold marks come from the original Astra 03 near bumper. Difference-key
    # the warm ink against its blue rubber, retaining the raised ink and wear.
    u, v, radius = grid(FACE_SIZE)
    rgb = sample(original, *Plane(359, 445, 113, 204, 10).source(u, v))
    gold = np.clip((rgb[..., 0] - rgb[..., 2] + 4) / 63, 0, 1)
    brand = (np.abs(u) < .55) & (v > -.73) & (v < -.35) & (radius > .50)
    weight = (np.abs(u) < .41) & (v > .44) & (v < .76)
    yield "PhotoBrand", ink_cutout(rgb, gold * brand, (17, 39, 77))
    yield "PhotoMark45lb", ink_cutout(rgb, gold * weight, (17, 39, 77))


def metric_stamp(original, plane, yellow):
    # Both calibrated plates have a real, stacked mark at three o'clock.
    # Align that block to the same right quadrant after rectifying its face.
    u, v, _ = grid(FACE_SIZE)
    if yellow:
        u, v = u + .16, v + .035
    rgb = sample(original, *plane.source(u, v))
    if yellow:
        value = (153 - .65 * rgb[..., 0] - .35 * rgb[..., 1]) / 115
        region = (u > .63) & (u < 1.04) & (v > .08) & (v < .465)
        background = (225, 165, 5)
    else:
        value = (rgb[..., 0] - .40 * rgb[..., 2] - 16) / 92
        region = (u > .48) & (u < .85) & (v > .025) & (v < .44)
        background = (19, 41, 79)
    return ink_cutout(rgb, np.clip(value, 0, 1) * region, background)


def bar_crop(bar, box):
    rgb = np.array(bar.crop(box))
    # Remove the detached matte halo above the steel. Starting at the axis
    # retains the antialiased one-pixel boundary of the actual silhouette.
    alpha = rgb[:, :, 3]
    middle = alpha.shape[0] // 2
    for x in range(alpha.shape[1]):
        if alpha[middle, x] < 64:
            alpha[:, x] = 0
            continue
        for step in (-1, 1):
            y = middle
            while 0 <= y < len(alpha) and alpha[y, x] > 150:
                y += step
            if step < 0:
                alpha[:max(0, y), x] = 0
            else:
                alpha[min(len(alpha), y + 1):, x] = 0
    rgb[alpha == 0, :3] = 0
    result = Image.fromarray(rgb)
    return result.crop(result.getchannel("A").getbbox())


def cutout(master, size):
    master = master.crop(master.getchannel("A").point(lambda a: 255 if a > 36 else 0).getbbox())
    master.thumbnail((size, size), Image.Resampling.LANCZOS)
    return master


def product_layers(masters):
    def source(name):
        with Image.open(masters / (name + ".png")) as im:
            return np.array(im.convert("RGBA"))

    materials = {surface.master: source(surface.master)
                 for surface in (RUBBER, BLACK, COATED, IRON, HAMMERED, MACHINED)}
    for name, surface in (("BlackRubber", BLACK), ("Coated", COATED),
                          ("Gloss", COATED), ("Iron", IRON), ("Hammertone", HAMMERED),
                          ("Machined", MACHINED)):
        yield "PhotoFace" + name, face(materials[surface.master], surface)
    for name, surface in (("Coated", COATED), ("Iron", IRON)):
        yield "PhotoEdge" + name, edge(materials[surface.master], surface)
    yield "PhotoHub", hub(materials["machined"])
    with Image.open(masters / "bar.png") as bar:
        for name, box in (("Sleeve", (25, 323, 383, 397)),
                          ("Shoulder", (382, 312, 420, 409))):
            yield "Photo" + name, bar_crop(bar.convert("RGBA"), box)
    with Image.open(masters / "collar.png") as collar:
        yield "PhotoCollar", cutout(collar.convert("RGBA"), 384)
    # The recessed end and threaded bore are both visible in Astra reference 03.
    # Its outer ellipse is measured in original, full resolution pixels.
    with Image.open(ASTRA / "03-platform-oak-blue.png") as original:
        u, v, radius = grid(FACE_SIZE)
        rgb_source = np.array(original.convert("RGB"))
        yield "PhotoFaceRubber", rubber_face(materials["bumper"], rgb_source)
        yield "PhotoEdgeRubber", rubber_edge(rgb_source)
        yield "PhotoShaft", steel_shaft(rgb_source)
        yield from bumper_stamps(rgb_source)
        rgb = sample(rgb_source, *Plane(65.8, 480.2, 12.0, 25.7, 2.1).source(u, v))
        cap = bitmap(rgb, disc_alpha(radius))
        yield "PhotoEndcap", cap.resize((128, 128), Image.Resampling.LANCZOS)
    for name, file, plane, yellow in (
        ("PhotoMark20kg", "04-platform-walnut-calibrated.png", Plane(264, 366, 66, 188, 15), False),
        ("PhotoMark15kg", "07-platform-maple-yellow.png", Plane(239, 435, 70, 190, 19), True),
    ):
        with Image.open(ASTRA / file) as original:
            yield name, metric_stamp(np.array(original.convert("RGB")), plane, yellow)


CONTENTS = json.dumps({
    "images": [{"filename": "photo.png", "idiom": "universal", "scale": "1x"}],
    "info": {"author": "xcode", "version": 1},
}, indent=2) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--masters", type=Path, default=HERE / "masters")
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name, image in product_layers(args.masters):
        path = args.catalog / (name + ".imageset")
        png = BytesIO()
        image.save(png, format="PNG", optimize=True)
        for filename, data in (("photo.png", png.getvalue()), ("Contents.json", CONTENTS.encode())):
            destination = path / filename
            if args.check:
                if not destination.is_file() or destination.read_bytes() != data:
                    raise SystemExit("Out of date: " + str(destination))
            else:
                path.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
        print(name, image.size, flush=True)


if __name__ == "__main__":
    main()
