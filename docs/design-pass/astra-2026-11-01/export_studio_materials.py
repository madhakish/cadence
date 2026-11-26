"""Export the native studio's surface maps from the original Astra artwork.

Run from any directory with Python 3, Pillow and NumPy. Crops are left, top,
right, bottom in original pixels. The runtime owns the light, denomination,
theme colour, bar, plates and the single centred platform engraving.
"""
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageFilter, ImageOps

SOURCES = Path(__file__).resolve().parent
ASSETS = SOURCES.parents[2] / "Cadence/Assets.xcassets"
SAMPLE = Image.Resampling.LANCZOS


def save(image, asset, filename):
    folder = ASSETS / (asset + ".imageset")
    folder.mkdir(exist_ok=True)
    if not (folder / "Contents.json").exists():
        catalog = {"images": [{"filename": filename, "idiom": "universal", "scale": "1x"}],
                   "info": {"author": "xcode", "version": 1}}
        (folder / "Contents.json").write_text(json.dumps(catalog, indent=2) + "\n")
    options = {"quality": 93, "subsampling": 0} if filename.endswith(".jpg") else {}
    image.save(folder / filename, **options)


def mirror_tile(sample):
    # All four outside edges meet their reflected neighbour continuously.
    w, h = sample.size
    tile = Image.new(sample.mode, (w * 2, h * 2))
    tile.paste(sample, (0, 0))
    tile.paste(ImageOps.mirror(sample), (w, 0))
    tile.paste(ImageOps.flip(tile.crop((0, 0, w * 2, h))), (0, h))
    return tile


def surface_normal(image, size, strength):
    height = np.asarray(image.convert("L").resize(size, SAMPLE), dtype=float) / 255
    dy, dx = np.gradient(height)
    # Image Y points down; the OpenGL tangent-space green axis points up.
    normals = np.stack((-dx * strength, dy * strength, np.ones_like(dx)), axis=-1)
    normals /= np.linalg.norm(normals, axis=-1, keepdims=True)
    return Image.fromarray(np.rint(127.5 * (normals + 1)).astype("uint8"))


def oak_panel(photo):
    # The overhead master contains a bar and brand. Only clean timber is sampled:
    # full-width boards behind the bar, and two long strips outside the engraving.
    # Join those samples along the grain at different distances on each board.
    # That gives the 4 x 8 foot panel material without projecting the old scene.
    donors = [photo.crop((522 + i * 78, 64, 600 + i * 78, 252)) for i in range(8)]
    for x in (523, 1089):
        donors.extend(photo.crop((x, y, x + 58, y + 190)) for y in (315, 483, 653))
    panel = Image.new("RGB", (640, 1280))
    rng = np.random.default_rng(385)
    overlap = 34
    ramp = np.linspace(0, 255, overlap).round().astype("uint8")[:, None]
    mask = Image.fromarray(np.repeat(ramp, 80, axis=1))
    for i in range(8):
        board = Image.new("RGB", (80, panel.height + 270))
        # Each panel keeps its own tint and the swatches lose their original
        # exposure. Feathering joins along the grain avoids a repeating knot.
        tint = np.median(np.asarray(donors[i]), axis=(0, 1))
        end = 0
        for j in rng.permutation(len(donors)):
            pixels = np.asarray(donors[j], dtype=float)
            pixels = np.clip(pixels * tint / np.median(pixels, axis=(0, 1)), 0, 255)
            strip = Image.fromarray(pixels.round().astype("uint8"))
            if rng.integers(2):
                strip = ImageOps.flip(strip)
            if rng.integers(2):
                strip = ImageOps.mirror(strip)
            strip = strip.resize((80, int(rng.integers(176, 242))), SAMPLE)
            start = max(0, end - overlap)
            if end:
                board.paste(strip.crop((0, 0, 80, overlap)), (0, start), mask)
                board.paste(strip.crop((0, overlap, 80, strip.height)), (0, end))
            else:
                board.paste(strip)
            end = start + strip.height
            if end >= panel.height + 100:
                break
        offset = int(rng.integers(100))
        panel.paste(board.crop((0, offset, 80, offset + panel.height)), (i * 80, 0))
    return panel.resize((1024, 2048), SAMPLE)


def plate_detail(photo, crop):
    # The small swatches contain only surface tooth. Discard exposure and
    # colour before the renderer combines the sample with its own theme.
    sample = photo.crop(crop).convert("L")
    grain = np.asarray(sample, dtype=float)
    mean = np.asarray(sample.filter(ImageFilter.GaussianBlur(5)), dtype=float)
    neutral = np.clip(128 + 96 * (grain / np.maximum(mean, 1) - 1), 96, 160)
    # Overlap small, rotated pieces of the photographed face. Its pits keep
    # their actual shape without stamping the same scratch around every disc.
    rng = np.random.default_rng(385)
    n, patch = 1024, 16
    step = patch // 2
    total = np.zeros((n + patch, n + patch))
    weight = np.zeros_like(total)
    window = np.outer(np.hanning(patch + 2)[1:-1], np.hanning(patch + 2)[1:-1])
    for y in range(0, n + step, step):
        for x in range(0, n + step, step):
            u = int(rng.integers(neutral.shape[1] - patch + 1))
            v = int(rng.integers(neutral.shape[0] - patch + 1))
            fragment = np.rot90(neutral[v:v + patch, u:u + patch], int(rng.integers(4)))
            total[y:y + patch, x:x + patch] += fragment * window
            weight[y:y + patch, x:x + patch] += window
    window_slice = np.s_[step:step + n, step:step + n]
    field = total[window_slice] / weight[window_slice]
    return Image.fromarray(np.rint(field).astype("uint8"))


def studio_room(blue):
    # This narrow band contains the gym behind the platform. Every photographed
    # bar, disc and platform edge lies outside it. Reflect the ends for a closed
    # equirectangular horizon and fade the poles away from the camera.
    swatch = blue.convert("RGB").crop((0, 0, 1200, 222)).resize((1024, 190), SAMPLE)
    band = Image.new("RGB", (2048, 190))
    band.paste(swatch)
    band.paste(ImageOps.mirror(swatch), (1024, 0))
    pixels = np.asarray(band, dtype=float)
    rows = np.arange(1024) - 343
    panorama = pixels[np.clip(rows, 0, 189)].copy()
    for distance, target in [(-rows, [13, 14, 16]), (rows - 189, [25, 26, 27])]:
        fade = np.clip(distance / 160, 0, 1)[:, None, None]
        fade = fade * fade * (3 - 2 * fade)
        panorama = panorama * (1 - fade) + np.array(target) * fade
    return Image.fromarray(panorama.round().astype("uint8"))


def steel_surfaces(blue):
    # Rectify the unobstructed near sleeve, staying inside its chrome edges.
    sleeve = blue.transform((256, 56), Image.Transform.QUAD,
                            (91, 455, 91, 494, 258, 468, 258, 431), Image.Resampling.BICUBIC).convert("L")
    save(sleeve, "AstraSleeve", "astra-sleeve.png")
    # Small-scale tooling marks affect roughness. Broad bands of reflected
    # light belong to the live environment and must turn when the camera does.
    residual = np.asarray(sleeve, dtype=float) - np.asarray(sleeve.filter(ImageFilter.GaussianBlur(4)), dtype=float)
    roughness = Image.fromarray(np.rint(np.clip(40 + 0.85 * residual, 21, 68)).astype("uint8"))
    save(mirror_tile(roughness), "AstraChromeRoughness", "astra-chrome.png")


def timber_finish(panel, source, box):
    # Use the colour of each photographed finish on the full overhead timber
    # grain. The small finish swatches have no letters, plates or cast shadows.
    grain = np.asarray(panel, dtype=float)
    reference = np.median(np.asarray(source.convert("RGB").crop(box)), axis=(0, 1))
    tint = reference / np.maximum(1, np.median(grain, axis=(0, 1)))
    return Image.fromarray(np.rint(np.clip(grain * tint, 0, 255)).astype("uint8"))


def main():
    overhead = Image.open(SOURCES / "08-platform-overhead.png").convert("RGB")
    oak = oak_panel(overhead)
    save(oak, "PlatformOak", "platform-oak.jpg")
    save(surface_normal(oak, (512, 1024), 1.4), "PlatformOakNormal", "platform-oak-normal.png")
    rubber = overhead.crop((119, 548, 375, 804))
    mean = np.asarray(rubber.filter(ImageFilter.GaussianBlur(24)), dtype=float)
    diffuse = np.asarray(rubber) * np.median(mean, axis=(0, 1)) / np.maximum(mean, 1)
    mat = mirror_tile(Image.fromarray(np.clip(diffuse, 0, 255).round().astype("uint8")))
    save(mat, "PlatformMat", "platform-mat.jpg")
    save(surface_normal(mat, mat.size, 1.8), "PlatformMatNormal", "platform-mat-normal.png")

    blue = Image.open(SOURCES / "03-platform-oak-blue.png")
    coated = Image.open(SOURCES / "04-platform-walnut-calibrated.png")
    black = Image.open(SOURCES / "05-platform-white-oak-black.png")
    iron = Image.open(SOURCES / "06-platform-oak-iron.png")
    maple = Image.open(SOURCES / "07-platform-maple-yellow.png")
    save(studio_room(blue), "AstraStudioRoom", "astra-room.jpg")
    steel_surfaces(blue)
    for image, box, name in [(coated, (545, 291, 588, 302), "Walnut"),
                             (black, (575, 314, 630, 330), "WhiteOak"),
                             (maple, (545, 301, 585, 310), "Maple")]:
        save(timber_finish(oak, image, box), "Platform" + name, "platform-" + name.lower() + ".jpg")
    save(plate_detail(blue, (411, 390, 439, 505)), "AstraBumperDetail", "bumper-detail.png")
    save(plate_detail(coated, (267, 464, 294, 496)), "AstraCalibratedCoatingDetail", "calibrated-coating.png")
    save(plate_detail(black, (329, 461, 354, 516)), "AstraBlackRubberDetail", "black-rubber.png")
    save(plate_detail(iron, (402, 369, 424, 451)), "AstraCastIronDetail", "iron-detail.png")

    master = Image.open(SOURCES / "09-icon-heritage-master.png").convert("RGB")
    linear = (np.asarray(master, dtype=float) / 255) ** 2.2
    luminance = linear @ [0.2126, 0.7152, 0.0722]
    ink = np.clip((1 - luminance - 0.24) / (0.62 - 0.24), 0, 1)
    alpha = Image.fromarray(np.rint(255 * ink * ink * (3 - 2 * ink)).astype("uint8"))
    engraving = Image.new("RGBA", master.size, (0, 0, 0, 0))
    engraving.putalpha(alpha)
    save(engraving, "AstraHeritageBurn", "heritage-burn.png")


if __name__ == "__main__":
    main()
