#!/usr/bin/env python3
"""Derive the launch-screen mark from the Vitruvian gorilla engraving.

Same rules as the app icon (epic #177): the figure is the shipped artwork
(Cadence/Assets.xcassets/VitruvianFront.imageset/vitruvian-front.jpeg), never
redrawn. It goes through levels, a grey dilation of the ink, separation of
the plate's circle and square from the figure, and a recolour to chalk. The
result is the "iron" plate from the icon generator on PR #377, but with an
alpha channel instead of a steel ground, so iOS can centre it on the flat
LaunchBackground colour and the SwiftUI cold open can draw the very same
pixels on the very same colour. Frame 0 of the animation is the launch screen.

The separation helpers are copied from docs/design-pass/app-icon/
render_app_icon.py (PR #377), which was not on main when this was written.
When both land, fold them into one module.

  python3 docs/design-pass/launch/render_launch_mark.py --install
      # write LaunchMark@2x/@3x into Cadence/Assets.xcassets
  python3 docs/design-pass/launch/render_launch_mark.py <proof-dir>
      # the mark on its background at 3x, for review

Needs Pillow and numpy. Deterministic: a re-run reproduces every byte.
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOURCE = os.path.join(ROOT, "Cadence/Assets.xcassets/VitruvianFront.imageset/vitruvian-front.jpeg")
MARK_SET = os.path.join(ROOT, "Cadence/Assets.xcassets/LaunchMark.imageset")

# Point size of the mark. LaunchSplashView reads the asset at its natural
# size, so this is the one place the gorilla's on-screen size is decided.
MARK_PT = 220
PAPER = np.array([249, 240, 225], float)
CHALK = np.array([238, 234, 226], float)
BACKGROUND = np.array([0x0C, 0x0D, 0x0E], float)  # LaunchBackground.colorset

CIRCLE = (623.3, 615.4, 585.9)  # cx, cy, r (least squares on the ring's ink)
SQUARE = (121.5, 171.5, 1126.5, 1181.5)  # x0, y0, x1, y1


def box_mean(a, r):
    p = np.pad(a, r + 1, mode="edge").cumsum(0).cumsum(1)
    n = 2 * r + 1
    s = p[n:, n:] - p[:-n, n:] - p[n:, :-n] + p[:-n, :-n]
    return s[: a.shape[0], : a.shape[1]] / (n * n)


def blur(a, sigma):
    r = max(1, int(np.ceil(3 * sigma)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    p = np.pad(a, r, mode="edge")
    h, w = a.shape
    rows = sum(k[i] * p[:, i:i + w] for i in range(2 * r + 1))
    return sum(k[i] * rows[i:i + h, :] for i in range(2 * r + 1))


def thicken(a, sigma, gain):
    return np.maximum(a, np.clip(blur(a, sigma) * gain, 0, 1))


def trace(ink, coords, nominal, reach=8):
    offsets = np.arange(-reach, reach + 1)
    stack = np.stack([ink[coords(nominal + o)] for o in offsets])
    best = offsets[stack.argmax(0)].astype(float)
    k = 41
    padded = np.pad(best, k // 2, mode="wrap")
    windows = np.lib.stride_tricks.sliding_window_view(padded, k)
    return nominal + np.median(windows, axis=1)


def separate():
    """(figure_ink, circle_ink, square_ink) as 0..1 maps at source size."""
    rgb = np.asarray(Image.open(SOURCE).convert("RGB"), float)
    lum = rgb @ [0.299, 0.587, 0.114]
    paper_l = PAPER @ [0.299, 0.587, 0.114]
    ink = np.clip((paper_l - lum) / (paper_l - 45), 0, 1)
    h, w = ink.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(float)

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
    off = (~band).astype(float)
    density = box_mean(ink * off, 9) / np.maximum(box_mean(off, 9), 1e-6)
    line = band & (density < 0.07)
    figure = np.where(line, 0, ink)
    return figure, np.where(line & band_c, ink, 0), np.where(line & band_s & ~band_c, ink, 0)


def crop(a, cx, cy, side, size):
    half = side / 2
    box = (cx - half, cy - half, cx + half, cy + half)
    img = Image.fromarray(np.float32(a), mode="F")
    out = img.transform((size, size), Image.Transform.EXTENT, box, Image.Resampling.BICUBIC, fillcolor=0)
    return np.clip(np.asarray(out, float), 0, 1)


def rule(line_ink, sigma, gain):
    return np.clip(blur(line_ink, sigma) * gain, 0, 1)


def mark(px):
    """The plate in chalk on transparent, px square."""
    fig, circ, sq = separate()
    cx, cy, _ = CIRCLE
    side = 1254  # the whole plate
    # The mark draws at ~0.5x the source, so the hatching gets a slightly
    # heavier dilation than the icon's 1024 render to stay a line, not a haze.
    body = crop(thicken(fig, 1.3, 2.0), cx, cy, side, px) ** 0.85
    ring = crop(rule(circ, 2.6, 4.0), cx, cy, side, px)
    square = crop(rule(sq, 1.6, 3.0), cx, cy, side, px)
    rgb = np.zeros((px, px, 3))
    alpha = np.zeros((px, px))
    # Steel-grey frame, chalk figure. The fuse is the only oxide on screen.
    for amount, color in ((square * 0.35, CHALK), (ring * 0.55, CHALK), (body, CHALK)):
        a = np.clip(amount, 0, 1)
        rgb = rgb * (1 - a[..., None]) + color * a[..., None]  # premultiplied "over"
        alpha = alpha * (1 - a) + a
    straight = np.where(alpha[..., None] > 0, rgb / np.maximum(alpha[..., None], 1e-6), 0)
    out = np.dstack([straight, alpha * 255])
    return Image.fromarray(np.uint8(np.clip(np.rint(out), 0, 255)), "RGBA")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("proof", nargs="?", help="directory for a review render on the background")
    ap.add_argument("--install", action="store_true", help="write LaunchMark@2x/@3x into the asset catalog")
    args = ap.parse_args(argv)
    if not args.proof and not args.install:
        ap.error("give a proof directory, --install, or both")
    marks = {scale: mark(MARK_PT * scale) for scale in (2, 3)}
    if args.install:
        for scale, img in marks.items():
            img.save(os.path.join(MARK_SET, f"launch-mark@{scale}x.png"), optimize=True)
    if args.proof:
        os.makedirs(args.proof, exist_ok=True)
        m = marks[3]
        ground = Image.new("RGBA", m.size, tuple(int(c) for c in BACKGROUND) + (255,))
        Image.alpha_composite(ground, m).convert("RGB").save(os.path.join(args.proof, "launch-mark-3x.png"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
