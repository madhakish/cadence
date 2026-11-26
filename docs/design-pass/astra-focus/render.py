"""Derive the native Focus assets from Astra's 1254 px master. Requires Pillow 13."""
import argparse
import hashlib
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MASTER = ROOT / "docs/design-pass/astra-2026-11-01/11-icon-focus-master.png"
MASTER_SHA = "05cd5901ff65939deb490dd3c1f354877b70d916184cd954eb3d2cd52987f632"
PHONE = ROOT / "Cadence/Assets.xcassets/AppIcon.appiconset"
WATCH = ROOT / "CadenceWatch/Assets.xcassets/AppIcon.appiconset"
TAB = ROOT / "Cadence/Assets.xcassets/FocusTab.imageset"
LANCZOS = Image.Resampling.LANCZOS


def dark_icon(icon):
    # The ring separates the outside field from the backdrop behind the head.
    # Flood only those two regions. The dark ink inside the face stays opaque.
    field = icon.getchannel("R").point(lambda level: 255 if level > 44 else 0)
    for seed in [(0, 0), (256, 205), (768, 205)]:
        if field.getpixel(seed) == 0:
            ImageDraw.floodfill(field, seed, 128)
    alpha = field.point(lambda level: 0 if level == 128 else 255)
    result = icon.convert("RGBA")
    result.putalpha(alpha.filter(ImageFilter.GaussianBlur(0.65)))
    return result


def tab_silhouette(master):
    # Coordinates are on a 600 px study of the supplied master. Stop at the
    # head's fur line and jaw so the singlet, ring and shoulders drop away.
    study = master.resize((600, 600), LANCZOS)
    left = [(300, 45), (270, 48), (240, 63), (216, 85), (199, 133),
            (190, 184), (184, 191), (179, 203), (181, 225), (172, 247),
            (168, 255), (172, 259), (166, 275), (157, 292), (167, 287),
            (158, 309), (179, 332), (200, 351), (224, 363), (245, 379),
            (258, 392), (277, 405), (300, 416)]
    outline = Image.new("L", study.size)
    ImageDraw.Draw(outline).polygon(left + [(600-x, y) for x, y in left[-2:0:-1]], fill=255)
    # Suppress fine engraving but keep the master’s actual brow, nostrils,
    # cheeks and mouth. Clip the ink response to leave mostly hard counters.
    tone = ImageOps.grayscale(study).filter(ImageFilter.GaussianBlur(4))
    ink = tone.point(lambda value: (152 - value) * 255 / (152 - 68))
    mask = Image.new("L", study.size)
    ImageDraw.Draw(mask).ellipse((194, 78, 407, 408), fill=255)
    face = Image.composite(ink, Image.new("L", study.size, 255),
                           mask.filter(ImageFilter.GaussianBlur(15)))
    alpha = ImageChops.multiply(outline, face).point(lambda value: (value - 45) * 4)
    # The engraved eye highlights disappear before 30 pt. Open a short slit
    # on each existing eyelid so the eyes stay separate from the brow at 1x.
    eyes = ImageDraw.Draw(alpha)
    for x in [261, 338]:
        eyes.ellipse((x-7, 221, x+7, 226), fill=0)
    return alpha.crop((103, 34, 497, 428))


def template(mask, size):
    result = Image.new("RGBA", (size, size))
    result.putalpha(mask.resize(result.size, LANCZOS))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proof-dir", type=Path)
    args = parser.parse_args()
    if hashlib.sha256(MASTER.read_bytes()).hexdigest() != MASTER_SHA:
        raise ValueError("Focus master does not match the Astra handoff")
    profile = (HERE / "sRGB.icc").read_bytes()
    with Image.open(MASTER) as source:
        master = source.convert("RGB")
    icon = master.resize((1024, 1024), LANCZOS)
    dark = dark_icon(icon)
    tinted = ImageOps.grayscale(icon)
    mark = tab_silhouette(master)
    for target in [PHONE, WATCH]:
        icon.save(target / "AppIcon.png", icc_profile=profile)
    dark.save(PHONE / "AppIcon-Dark.png", icc_profile=profile)
    tinted.save(PHONE / "AppIcon-Tinted.png")
    for scale in [1, 2, 3]:
        suffix = "" if scale == 1 else f"@{scale}x"
        template(mark, 30 * scale).save(TAB / f"focus-tab{suffix}.png")
    if args.proof_dir:
        write_proof(args.proof_dir, icon, dark, tinted, mark, master)


def write_proof(directory, icon, dark, tinted, mark, master):
    directory.mkdir(parents=True, exist_ok=True)
    paper, graphite, accent = "#f5f2ed", "#17191c", "#eb493b"
    proof = Image.new("RGB", (682, 310), paper)
    draw = ImageDraw.Draw(proof)
    for index, (title, artwork, circular) in enumerate([
            ("iPhone / default", icon, False),
            ("iPhone / dark", dark, False),
            ("iPhone / tinted input", tinted, False),
            ("Watch / circle", icon, True)]):
        x = 12 + index * 170
        draw.text((x, 10), title, fill=graphite)
        for size, y in [(60, 35), (40, 110)]:
            tile = Image.new("RGB", (size, size), "#252529")
            sample = artwork.resize(tile.size, LANCZOS)
            tile.paste(sample, (0, 0), sample if artwork.mode == "RGBA" else None)
            edge = Image.new("L", (size*4, size*4))
            path = ImageDraw.Draw(edge)
            if circular:
                path.ellipse((0, 0, edge.width-1, edge.height-1), fill=255)
            else:
                path.rounded_rectangle((0, 0, edge.width-1, edge.height-1),
                                       radius=round(size*4*0.22), fill=255)
            proof.paste(tile, (x, y), edge.resize(tile.size, LANCZOS))
            draw.text((x+size+7, y+size//2-5), f"{size} px", fill=graphite)
    # Compare the whole composition and the face stencil at identical size.
    draw.line((12, 167, 667, 167), fill="#ccc6bd")
    for col, label in enumerate(["Focus master", "Today / selected", "Today / inactive", "Today / dark"]):
        x = 12 + col*170
        draw.text((x, 183), label, fill=graphite)
        for size, y in [(30, 210), (24, 258)]:
            if col == 0:
                proof.paste(master.resize((size, size), LANCZOS), (x, y))
            else:
                ink = [None, accent, "#707277", paper][col]
                swatch = Image.new("RGB", (size+8, size+8), graphite if col == 3 else paper)
                swatch.paste(ink, (4, 4, size+4, size+4), template(mark, size).getchannel("A"))
                proof.paste(swatch, (x-4, y-4))
            draw.text((x+size+10, y+size//2-5), f"{size} px", fill=graphite)
    proof.save(directory / "focus-scale.png")


if __name__ == "__main__":
    main()
