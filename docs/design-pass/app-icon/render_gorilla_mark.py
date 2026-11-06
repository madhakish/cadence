#!/usr/bin/env python3
"""Derive the Today tab's gorilla mark from the Vitruvian engraving.

A tab-bar glyph is one colour at about 30 pt, so the engraving's hatching
cannot survive as lines. Each candidate is instead the figure's own
silhouette (the fur outline traced by render_app_icon.silhouette) with the
darkest ink of the face knocked out as negative space. Nothing is redrawn;
the shapes are thresholds of the artwork.

  python3 docs/design-pass/app-icon/render_gorilla_mark.py <proof-dir>
      # candidates and a contact sheet at real tab-bar size
  python3 docs/design-pass/app-icon/render_gorilla_mark.py --install
      # write the chosen mark as a template image set (GorillaMark)

Needs Pillow and numpy. Deterministic.
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_app_icon as icon  # noqa: E402  (sibling script, not a package)

MARK_SET = os.path.join(icon.ROOT, "Cadence/Assets.xcassets/GorillaMark.imageset")

# Point size of the image canvas. SF Symbols in a tab bar draw roughly
# 25-27 pt tall; the owner asked for the Today mark 10-15% larger.
POINTS = 30

# Crops in source pixels: (cx, cy, side). The artwork is 1254 px square.
CROPS = {
    "head": (623, 335, 300),       # crest, face and yoke, round-bottomed
    "bust": (623, 372, 600),       # head, shoulders and upper arms
    "vitruvian": (623.3, 615.4, 1210),  # the whole figure inside its circle
}
# The head reads as a gorilla at 30 pt; the bust becomes a winged blob and
# the full Vitruvian figure a star with no face.
CHOSEN = "head"
FACE_BLUR, FACE_FLOOR, FACE_GAIN = 2.5, 0.28, 3.5


def masks():
    fig, circ, _ = icon.separate()
    body = icon.silhouette(fig)
    # The face as a stencil: inside it the engraving's own ink decides, so
    # brow shadow, eyes, nostrils and mouth stay solid and the light skin of
    # the muzzle and cheeks opens up. Outside the face the silhouette is solid,
    # so fur shading never perforates the body.
    ink = np.clip((icon.blur(fig, FACE_BLUR) - FACE_FLOOR) * FACE_GAIN, 0, 1)
    yy, xx = np.mgrid[0:fig.shape[0], 0:fig.shape[1]]
    d = np.hypot((xx - 623) / 78, (yy - 352) / 92)
    face = np.clip((1.0 - d) * 6, 0, 1)  # soft-edged ellipse over the face
    solid = body * (1 - face) + body * ink * face
    ring = icon.rule(circ, 6.0, 4.0)  # a stroke that survives at 1 pt
    # The head's yoke runs off the crop; a round bottom (the plate's circle
    # in miniature) ends it instead of a hard rectangle.
    medallion = np.clip((165 - np.hypot(xx - 623, yy - 335)) / 2, 0, 1)
    return {"head": solid * medallion, "bust": solid, "vitruvian": np.maximum(solid, ring)}


def render(alpha, crop, px):
    cx, cy, side = crop
    half = side / 2
    img = Image.fromarray(np.float32(alpha), mode="F")
    big = img.transform((px * 4, px * 4), Image.Transform.EXTENT,
                        (cx - half, cy - half, cx + half, cy + half),
                        Image.Resampling.BICUBIC, fillcolor=0)
    a = np.clip(np.asarray(big, float), 0, 1)
    # Fill the canvas: trim to the shape's bounds, then pad back to square.
    rows, cols = np.where(a > 0.5)
    if rows.size:
        a = a[rows.min():rows.max() + 1, cols.min():cols.max() + 1]
    h, w = a.shape
    s = max(h, w)
    canvas = np.zeros((s, s))
    canvas[(s - h) // 2:(s - h) // 2 + h, (s - w) // 2:(s - w) // 2 + w] = a
    out = Image.fromarray(np.uint8(canvas * 255)).resize((px, px), Image.Resampling.LANCZOS)
    return out


def template_png(mask):
    """Black ink with the mask as alpha: what a template image wants."""
    rgba = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    rgba.putalpha(mask)
    return rgba


def tab_bar(marks, scale, dark, accent, selected):
    """A plain stand-in for the system tab bar, with generic square glyphs
    standing in for SF Symbols (Pillow cannot draw them)."""
    pt = scale
    w, h = 402 * pt, 70 * pt
    bg = (24, 25, 27) if dark else (246, 246, 248)
    gray = (142, 142, 147) if dark else (128, 128, 133)
    bar = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(bar)
    slot = w // 5
    sym = 25 * pt  # an SF Symbol's drawn height in a tab bar
    for i in range(5):
        cx = slot * i + slot // 2
        color = accent if (i == 2 and selected) else gray
        if i == 2:
            m = marks
            tint = Image.new("RGB", m.size, color)
            bar.paste(tint, (cx - m.width // 2, 8 * pt + (sym - m.height) // 2 + 2 * pt), m)
        else:
            d.rounded_rectangle((cx - sym // 2 + 3 * pt, 8 * pt + 3 * pt, cx + sym // 2 - 3 * pt, 8 * pt + sym - 3 * pt),
                                radius=4 * pt, outline=gray, width=max(2, int(1.7 * pt)))
        d.text((cx, 8 * pt + sym + 14 * pt), ["Program", "History", "Today", "Body", "Settings"][i],
               fill=color, anchor="mm", font=ImageFont.load_default(10 * pt))
    return bar


def contact_sheet(alphas, path):
    rows = []
    accents = [(0xFF, 0x5A, 0x5F), (0xF0, 0x4A, 0x3E)]
    for name in CROPS:
        for size in (28, 30, 33):
            mark = render(alphas[name], CROPS[name], size * 3)
            label = Image.new("RGB", (240, 70 * 3), (0, 0, 0))
            ImageDraw.Draw(label).text((10, 95), f"{name} {size}pt", fill=(220, 220, 220),
                                       font=ImageFont.load_default(26))
            panels = [label]
            for dark in (True, False):
                for selected in (True, False):
                    panels.append(tab_bar(mark, 3, dark, accents[0], selected))
            row = Image.new("RGB", (sum(p.width for p in panels) + 8 * len(panels), panels[1].height), (0, 0, 0))
            x = 0
            for p in panels:
                row.paste(p, (x, 0))
                x += p.width + 8
            rows.append(row)
    sheet = Image.new("RGB", (rows[0].width, sum(r.height + 8 for r in rows)), (0, 0, 0))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height + 8
    sheet.save(path, optimize=True)


def install(alphas):
    os.makedirs(MARK_SET, exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        name = f"gorilla-mark@{scale}x.png" if scale > 1 else "gorilla-mark.png"
        template_png(render(alphas[CHOSEN], CROPS[CHOSEN], POINTS * scale)).save(
            os.path.join(MARK_SET, name), optimize=True)
        images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})
    contents = {"images": images, "info": {"author": "xcode", "version": 1},
                "properties": {"template-rendering-intent": "template"}}
    with open(os.path.join(MARK_SET, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2, separators=(",", " : "))
        f.write("\n")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("proof", nargs="?", help="directory for candidates and the tab-bar contact sheet")
    ap.add_argument("--install", action="store_true", help="write the chosen mark into GorillaMark.imageset")
    args = ap.parse_args(argv)
    if not args.proof and not args.install:
        ap.error("give a proof directory, --install, or both")
    alphas = masks()
    if args.proof:
        os.makedirs(args.proof, exist_ok=True)
        for name, crop in CROPS.items():
            template_png(render(alphas[name], crop, 512)).save(os.path.join(args.proof, f"mark-{name}-512.png"))
        contact_sheet(alphas, os.path.join(args.proof, "mark-contact-sheet.png"))
    if args.install:
        install(alphas)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
