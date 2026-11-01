#!/usr/bin/env python3
"""Derive the Cadence app icon from the Vitruvian gorilla engraving.

The figure is never redrawn: every candidate is the shipped artwork
(Cadence/Assets.xcassets/VitruvianFront.imageset/vitruvian-front.jpeg) put
through crop, levels, a grey dilation of the ink so the hatching survives a
40 px home-screen slot, inversion, tinting and a silhouette cut that lifts the
engraving off its paper onto steel. The circle and square of the plate are
traced and separated from the figure so they can be thickened, recoloured or
dropped on their own.

  python3 docs/design-pass/app-icon/render_app_icon.py <proof-dir>
      # three 1024 candidates, appearance variants and a contact sheet
  python3 docs/design-pass/app-icon/render_app_icon.py --install
      # write the chosen icon into the iOS and watch AppIcon sets

Needs Pillow and numpy. Deterministic: a re-run reproduces every byte.
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOURCE = os.path.join(ROOT, "Cadence/Assets.xcassets/VitruvianFront.imageset/vitruvian-front.jpeg")
IOS_SET = os.path.join(ROOT, "Cadence/Assets.xcassets/AppIcon.appiconset")
WATCH_SET = os.path.join(ROOT, "CadenceWatch/Assets.xcassets/AppIcon.appiconset")

SIZE = 1024
PAPER = np.array([249, 240, 225], float)
SEPIA = np.array([52, 32, 18], float)  # the engraving's darkest ink
CHALK = np.array([238, 234, 226], float)
OXIDE = np.array([0xF0, 0x4A, 0x3E], float)
STEEL_CENTER = np.array([44, 45, 48], float)
STEEL_EDGE = np.array([14, 15, 17], float)

# Fitted from the artwork (least squares on the ring's ink pixels).
CIRCLE = (623.3, 615.4, 585.9)  # cx, cy, r
SQUARE = (121.5, 171.5, 1126.5, 1181.5)  # x0, y0, x1, y1
BUST = (623, 380, 545)  # cx, cy, side: head, yoke and upper arms

# The candidate that ships. A full Vitruvian plate turns into a stick figure
# in a circle at 60 pt; the bust keeps a readable face down to 40 px.
CHOSEN = "C-bust"


def box_mean(a, r):
    """Mean over a (2r+1)^2 window via an integral image."""
    p = np.pad(a, r + 1, mode="edge").cumsum(0).cumsum(1)
    n = 2 * r + 1
    s = p[n:, n:] - p[:-n, n:] - p[n:, :-n] + p[:-n, :-n]
    return s[: a.shape[0], : a.shape[1]] / (n * n)


def blur(a, sigma):
    """Separable Gaussian on a float map (PIL only blurs 8-bit images)."""
    r = max(1, int(np.ceil(3 * sigma)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    p = np.pad(a, r, mode="edge")
    h, w = a.shape
    rows = sum(k[i] * p[:, i:i + w] for i in range(2 * r + 1))
    return sum(k[i] * rows[i:i + h, :] for i in range(2 * r + 1))


def thicken(a, sigma, gain):
    """Smooth grey dilation of an ink map: spread each stroke with a Gaussian,
    lift it back to full strength, never lighten what was already there."""
    if sigma <= 0:
        return a
    return np.maximum(a, np.clip(blur(a, sigma) * gain, 0, 1))


def trace(ink, coords, nominal, reach=8):
    """Follow a hand-drawn line: at each sample, the offset of the darkest
    pixel within +-reach of nominal, median-smoothed so a limb crossing the
    line cannot drag it off course. coords(offset) -> (ys, xs) index arrays."""
    offsets = np.arange(-reach, reach + 1)
    stack = np.stack([ink[coords(nominal + o)] for o in offsets])
    best = offsets[stack.argmax(0)].astype(float)
    k = 41
    padded = np.pad(best, k // 2, mode="wrap")
    windows = np.lib.stride_tricks.sliding_window_view(padded, k)
    return nominal + np.median(windows, axis=1)


def separate():
    """Return (figure_ink, circle_ink, square_ink) as 0..1 maps at source size."""
    rgb = np.asarray(Image.open(SOURCE).convert("RGB"), float)
    lum = rgb @ [0.299, 0.587, 0.114]
    paper_l = PAPER @ [0.299, 0.587, 0.114]
    ink = np.clip((paper_l - lum) / (paper_l - 45), 0, 1)
    h, w = ink.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(float)

    # The plate's circle is drawn by hand (it wanders ~5 px off a true
    # circle), so trace its radius per angle instead of trusting the fit.
    cx, cy, r = CIRCLE
    n = 3600
    theta = np.linspace(-np.pi, np.pi, n, endpoint=False)

    def ring_at(rad):
        x = np.clip(np.rint(cx + rad * np.cos(theta)), 0, w - 1).astype(int)
        y = np.clip(np.rint(cy + rad * np.sin(theta)), 0, h - 1).astype(int)
        return y, x

    radius = trace(ink, ring_at, r)
    ang = np.arctan2(yy - cy, xx - cx)
    local_r = radius[np.clip(((ang + np.pi) / (2 * np.pi) * n).astype(int), 0, n - 1)]
    d_circle = np.abs(np.hypot(xx - cx, yy - cy) - local_r)

    x0, y0, x1, y1 = SQUARE
    d_square = np.full_like(ink, 1e9)
    span_x, span_y = np.arange(w), np.arange(h)
    for pos, horizontal in ((y0, True), (y1, True), (x0, False), (x1, False)):
        if horizontal:
            line = trace(ink, lambda o: (np.full(w, int(round(o))), span_x), pos)
            dist = np.abs(yy - line[None, :])
            span = (xx >= x0 - 4) & (xx <= x1 + 4)
        else:
            line = trace(ink, lambda o: (span_y, np.full(h, int(round(o)))), pos)
            dist = np.abs(xx - line[:, None])
            span = (yy >= y0 - 4) & (yy <= y1 + 4)
        d_square = np.where(span, np.minimum(d_square, dist), d_square)

    band_c = d_circle <= 3.0
    band_s = d_square <= 3.0
    band = band_c | band_s
    # A frame pixel is "pure line" when the paper either side of the band is
    # empty; where the ring crosses fur it stays with the figure.
    off = (~band).astype(float)
    density = box_mean(ink * off, 9) / np.maximum(box_mean(off, 9), 1e-6)
    line = band & (density < 0.07)
    figure = np.where(line, 0, ink)
    return figure, np.where(line & band_c, ink, 0), np.where(line & band_s & ~band_c, ink, 0)


def crop(a, cx, cy, side):
    """Square crop centred on (cx, cy), padded with empty paper, resized to SIZE."""
    half = side / 2
    box = (cx - half, cy - half, cx + half, cy + half)
    img = Image.fromarray(np.float32(a), mode="F")
    out = img.transform((SIZE, SIZE), Image.Transform.EXTENT, box, Image.Resampling.BICUBIC, fillcolor=0)
    return np.clip(np.asarray(out, float), 0, 1)


def steel_ground(seed=177, glow=1.0):
    """Near-black forged steel: a soft overhead glow falling off to the edges,
    with a faint horizontal grain that also dithers the gradient."""
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    t = np.clip(np.hypot(xx - SIZE / 2, yy - SIZE * 0.42) / (SIZE * 0.75), 0, 1) ** 1.3
    center = STEEL_EDGE + (STEEL_CENTER - STEEL_EDGE) * glow
    g = center * (1 - t)[..., None] + STEEL_EDGE * t[..., None]
    grain = np.random.default_rng(seed).normal(0, 1, (SIZE, SIZE))
    grain = blur(grain, 0.6)  # soften to fine brushed grain, not TV static
    return g + (grain * 2.2)[..., None]


def paint(ground, layers):
    out = ground.copy()
    for amount, color in layers:
        a = np.clip(amount, 0, 1)[..., None]
        out = out * (1 - a) + np.asarray(color, float) * a
    return Image.fromarray(np.uint8(np.clip(np.rint(out), 0, 255)), "RGB")


def rule(line_ink, sigma, gain):
    """A frame line thickened into a solid, anti-aliased stroke."""
    return np.clip(blur(line_ink, sigma) * gain, 0, 1)


def silhouette(fig):
    """The figure's outline, holes filled: the engraving's own paper inside
    the fur line, so it can be lifted off the plate and set on steel."""
    inked = blur(fig, 1.5) > 0.10
    img = Image.fromarray(np.where(inked, 0, 255).astype(np.uint8)).copy()  # copy: fromarray is read-only
    ImageDraw.floodfill(img, (0, 0), 128)
    sil = (np.asarray(img) != 128).astype(float)
    eroded = (blur(sil, 2.0) > 0.7).astype(float)  # pull the edge back under the fur line
    return blur(eroded, 0.8)


def candidates():
    fig, circ, sq = separate()
    cx, cy, _ = CIRCLE
    plate = 1254  # whole plate; the ring sits inside the rounded mask
    paper = np.broadcast_to(PAPER, (SIZE, SIZE, 3)).astype(float)
    steel = steel_ground()
    white = (255, 255, 255)

    # Figure: thicken the hatching a little in source space so it holds at
    # 120 px, then a mild gamma to firm up the mid-tones.
    body = crop(thicken(fig, 1.1, 1.9), cx, cy, plate) ** 0.85
    ring = crop(rule(circ, 3.2, 5.0), cx, cy, plate)
    square = crop(rule(sq, 1.6, 3.0), cx, cy, plate)

    out = {}
    out["A-parchment"] = paint(paper, [(square * 0.8, SEPIA), (ring, SEPIA), (body, SEPIA)])
    out["B-iron"] = paint(steel, [(square * 0.4, CHALK), (ring, OXIDE), (body, CHALK)])

    # Bust: head, yoke and upper arms at ~2.2x the plate scale, the
    # engraving lifted off its paper and set on steel, ink still dark.
    bx, by, bside = BUST
    bust = crop(thicken(fig, 0.8, 1.6), bx, by, bside) ** 0.9
    lift = crop(silhouette(fig), bx, by, bside)
    out["C-bust"] = paint(steel, [(lift, PAPER), (bust, SEPIA)])
    out["C-bust-parchment"] = paint(paper, [(bust, SEPIA)])
    out["C-bust-inverted"] = paint(steel, [(bust, CHALK)])

    # iOS 18 appearances. Dark: the same art on a dimmer ground with the
    # parchment knocked back so it does not glare on a dark home screen.
    # Tinted: greyscale on black; the system supplies the colour.
    out["B-iron-dark"] = paint(steel_ground(glow=0.55), [(square * 0.35, CHALK), (ring, OXIDE), (body, CHALK)])
    out["B-iron-tinted"] = paint(np.zeros((SIZE, SIZE, 3)), [(square * 0.35, white), (ring * 0.8, white),
                                                              (body, white)])
    out["C-bust-dark"] = paint(steel_ground(glow=0.55), [(lift, PAPER * 0.78), (bust, SEPIA * 0.8)])
    out["C-bust-tinted"] = paint(np.zeros((SIZE, SIZE, 3)), [(lift * 0.85, white), (bust, (0, 0, 0))])
    return out


# --- proof sheet -----------------------------------------------------------

def squircle_mask(px, ss=4):
    n = 5.0
    s = px * ss
    t = (np.arange(s) + 0.5) / s * 2 - 1
    m = (np.abs(t)[None, :] ** n + np.abs(t)[:, None] ** n) <= 1
    return Image.fromarray(np.uint8(m * 255)).resize((px, px), Image.Resampling.LANCZOS)


def gradient(w, h, top, bottom):
    t = np.linspace(0, 1, h)[:, None, None]
    g = np.asarray(top, float) * (1 - t) + np.asarray(bottom, float) * t
    return Image.fromarray(np.uint8(np.broadcast_to(g, (h, w, 3))), "RGB")


def contact_sheet(icons, path):
    sizes = [180, 120, 87, 60, 40]
    pad, row_h = 24, 200
    generic = [(0x34, 0xC7, 0x59), (0x0A, 0x84, 0xFF), (0xFF, 0x9F, 0x0A), (0x8E, 0x8E, 0x93)]
    names = ["A-parchment", "B-iron", "C-bust", "C-bust-parchment", "C-bust-inverted"]
    strip_w = sum(sizes) + pad * (len(sizes) + 1)
    home_w = 4 * 120 + 5 * 28
    width = 2 * strip_w + 2 * home_w
    sheet = Image.new("RGB", (width, row_h * len(names)), (0, 0, 0))
    light = ((0xE4, 0xEA, 0xF1), (0xB9, 0xC6, 0xD6))
    darkbg = ((0x22, 0x26, 0x31), (0x07, 0x08, 0x0C))
    for row, name in enumerate(names):
        src = icons[name]
        y = row * row_h
        for col, bg in enumerate((light, darkbg)):
            x0 = col * strip_w
            panel = gradient(strip_w, row_h, *bg)
            x = pad
            for s in sizes:
                ic = src.resize((s, s), Image.Resampling.LANCZOS)
                panel.paste(ic, (x, (row_h - s) // 2), squircle_mask(s))
                x += s + pad
            sheet.paste(panel, (x0, y))
        for col, bg in enumerate((light, darkbg)):
            x0 = 2 * strip_w + col * home_w
            panel = gradient(home_w, row_h, *bg)
            x = 28
            for i in range(4):
                if i == 1:
                    ic = src.resize((120, 120), Image.Resampling.LANCZOS)
                else:
                    c = generic[i]
                    ic = Image.new("RGB", (120, 120), c)
                panel.paste(ic, (x, 40), squircle_mask(120))
                x += 148
            sheet.paste(panel, (x0, y))
    sheet.save(path, optimize=True)


def appearance_sheet(icons, path):
    names = [CHOSEN, f"{CHOSEN}-dark", f"{CHOSEN}-tinted"]
    tints = [None, None, (0xF0, 0x4A, 0x3E)]
    s, pad = 180, 30
    sheet = gradient(len(names) * (s + pad) + pad, s + 2 * pad, (0x22, 0x26, 0x31), (0x07, 0x08, 0x0C))
    for i, (n, tint) in enumerate(zip(names, tints)):
        ic = icons[n].resize((s, s), Image.Resampling.LANCZOS)
        if tint:  # approximate the system tint: luminance drives the tint colour
            lum = np.asarray(ic.convert("L"), float)[..., None] / 255
            ic = Image.fromarray(np.uint8(np.asarray(tint, float) * lum + 10 * (1 - lum)), "RGB")
        sheet.paste(ic, (pad + i * (s + pad), pad), squircle_mask(s))
    sheet.save(path, optimize=True)


def write_set(path, files):
    for name, img in files.items():
        img.save(os.path.join(path, name), optimize=True)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("proof", nargs="?", help="directory for candidates and contact sheets")
    ap.add_argument("--install", action="store_true", help="write the chosen icon into the AppIcon sets")
    args = ap.parse_args(argv)
    if not args.proof and not args.install:
        ap.error("give a proof directory, --install, or both")
    icons = candidates()
    if args.proof:
        os.makedirs(args.proof, exist_ok=True)
        for name, img in icons.items():
            img.save(os.path.join(args.proof, f"icon-{name}-1024.png"), optimize=True)
        contact_sheet(icons, os.path.join(args.proof, "icon-contact-sheet.png"))
        appearance_sheet(icons, os.path.join(args.proof, "icon-appearances.png"))
    if args.install:
        write_set(IOS_SET, {"AppIcon.png": icons[CHOSEN], "AppIcon-Dark.png": icons[f"{CHOSEN}-dark"],
                            "AppIcon-Tinted.png": icons[f"{CHOSEN}-tinted"]})
        write_set(WATCH_SET, {"AppIcon.png": icons[CHOSEN]})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
