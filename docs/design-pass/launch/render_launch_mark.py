#!/usr/bin/env python3
"""Export the Astra Foundry master for Cadence's static and animated launch.

Pass --install to update LaunchMark, or a preview directory to inspect the
220 pt mark against its launch canvas. Both outputs use the same RGBA pixels.
Requires Pillow.
"""

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "docs/design-pass/astra-2026-11-01/10-icon-foundry-master.png"
MARK_SET = ROOT / "Cadence/Assets.xcassets/LaunchMark.imageset"
MARK_PT = 220
LAUNCH_CANVAS = (12, 13, 14, 255)


def launch_mark():
    with Image.open(SOURCE) as image:
        mark = image.convert("RGBA")

    # Both the warm engraving and the oxide ring separate from the charcoal
    # field in red. Keep their RGB, feathering only the join to the flat canvas.
    # The master has 8-bit RGB; background samples span roughly 16–60 in red.
    alpha = mark.getchannel("R").point(
        [round(255 * max(0, min(1, (red - 60) / 24))) for red in range(256)]
    )
    mark.putalpha(alpha)
    return mark


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("preview", nargs="?", type=Path)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    if not args.install and args.preview is None:
        parser.error("give a preview directory, --install, or both")

    original = launch_mark()
    for scale in (2, 3):
        side = MARK_PT * scale
        mark = original.resize((side, side), Image.Resampling.LANCZOS)
        if args.install:
            mark.save(MARK_SET / f"launch-mark@{scale}x.png", optimize=True)
        if args.preview:
            args.preview.mkdir(exist_ok=True, parents=True)
            canvas = Image.new("RGBA", mark.size, LAUNCH_CANVAS)
            canvas.alpha_composite(mark)
            canvas.convert("RGB").save(args.preview / f"launch-mark-{scale}x.png")


if __name__ == "__main__":
    main()
