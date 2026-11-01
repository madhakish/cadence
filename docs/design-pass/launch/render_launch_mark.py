#!/usr/bin/env python3
"""Derive the launch-screen mark from the owner's "Foundry" brand plate.

Source: docs/design-pass/launch/foundry-plate.jpeg, the owner-supplied
artwork (chalk Vitruvian gorilla, oxide circle, steel square on charcoal;
the "Foundry" column of the icon study sheet). It is not redrawn here, only
lifted off its mottled charcoal ground with a soft luminance key, so iOS can
centre it on the flat LaunchBackground colour and the SwiftUI cold open can
draw the very same pixels on the very same colour. Frame 0 of the animation
is the launch screen.

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

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SOURCE = os.path.join(HERE, "foundry-plate.jpeg")
MARK_SET = os.path.join(ROOT, "Cadence/Assets.xcassets/LaunchMark.imageset")

# Point size of the mark. LaunchSplashView reads the asset at its natural
# size, so this is the one place the gorilla's on-screen size is decided.
MARK_PT = 220
BACKGROUND = np.array([0x0C, 0x0D, 0x0E], float)  # LaunchBackground.colorset

# The plate's charcoal ground (mean of its border) and where the key opens:
# the ground's texture stays under KEY_LO on the brightest channel, and the
# steel square, oxide ring and chalk figure all clear KEY_HI.
GROUND = np.array([27.5, 24.6, 22.9])
KEY_LO, KEY_HI = 46.0, 118.0


def blur(a, sigma):
    """Separable Gaussian on a float map."""
    r = max(1, int(np.ceil(3 * sigma)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    p = np.pad(a, r, mode="edge")
    h, w = a.shape
    rows = sum(k[i] * p[:, i:i + w] for i in range(2 * r + 1))
    return sum(k[i] * rows[i:i + h, :] for i in range(2 * r + 1))


def lift():
    """The plate as straight RGB + alpha at source size, ground removed."""
    rgb = np.asarray(Image.open(SOURCE).convert("RGB"), float)
    v = blur(rgb.max(axis=2), 0.7)
    t = np.clip((v - KEY_LO) / (KEY_HI - KEY_LO), 0, 1)
    alpha = t * t * (3 - 2 * t)
    # The ground's brightest grain can poke over KEY_LO on its own; keep
    # only alpha that sits near real artwork (within ~6 px of a solid line).
    near_art = blur((alpha > 0.6).astype(float), 3.0) > 0.02
    alpha = np.where(near_art, alpha, 0)
    # Un-mix the ground so that alpha * colour + (1 - alpha) * ground gives
    # back the source pixel: the art keeps its colour on any backdrop.
    a = alpha[..., None]
    color = np.where(a > 1e-3, (rgb - (1 - a) * GROUND) / np.maximum(a, 1e-3), 0)
    return np.clip(color, 0, 255), alpha


def mark(px, color, alpha):
    """Resize in premultiplied space so edges never pick up a dark fringe."""
    def resize(ch):
        img = Image.fromarray(np.float32(ch), mode="F")
        return np.asarray(img.resize((px, px), Image.Resampling.LANCZOS), float)
    a = np.clip(resize(alpha), 0, 1)
    pre = np.dstack([resize(color[..., i] * alpha) for i in range(3)])
    straight = np.where(a[..., None] > 1e-4, pre / np.maximum(a[..., None], 1e-4), 0)
    out = np.dstack([np.clip(straight, 0, 255), a * 255])
    return Image.fromarray(np.uint8(np.clip(np.rint(out), 0, 255)), "RGBA")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("proof", nargs="?", help="directory for a review render on the background")
    ap.add_argument("--install", action="store_true", help="write LaunchMark@2x/@3x into the asset catalog")
    args = ap.parse_args(argv)
    if not args.proof and not args.install:
        ap.error("give a proof directory, --install, or both")
    color, alpha = lift()
    marks = {scale: mark(MARK_PT * scale, color, alpha) for scale in (2, 3)}
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
