#!/usr/bin/env python3
"""Export the three supplied Astra brand candidates without redrawing them."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCES = ROOT / "docs/design-pass/astra-2026-11-01"
CANDIDATES = {
    "heritage": "09-icon-heritage-master.png",
    "foundry": "10-icon-foundry-master.png",
    "focus": "11-icon-focus-master.png",
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export(proof_dir=None):
    output = HERE / "icons"
    output.mkdir(exist_ok=True)
    profile = (HERE / "sRGB.icc").read_bytes()
    records = []
    previews = []
    for name, filename in CANDIDATES.items():
        source = SOURCES / filename
        with Image.open(source) as image:
            if image.mode != "RGB" or image.width != image.height:
                raise ValueError(f"Expected an opaque square RGB source: {source}")
            master = image.resize((1024, 1024), Image.Resampling.LANCZOS)
        target = output / f"{name}.png"
        master.save(target, icc_profile=profile)
        records.append({
            "candidate": name,
            "source": str(source.relative_to(ROOT)),
            "sourceSha256": sha256(source),
            "file": str(target.relative_to(ROOT)),
            "sha256": sha256(target),
            "size": [1024, 1024],
            "mode": "RGB",
            "colorSpace": "sRGB (assigned; source RGB interpreted as sRGB)",
            "operation": "Lanczos resize only; no crop, redraw, recolor or masking",
        })
        previews.append((name, master))
    manifest = {
        "selection": None,
        "status": "Candidates for owner review; no runtime asset catalog changed",
        "brandDecision": "https://github.com/madhakish/cadence/issues/177#issuecomment-6563484754",
        "profileSha256": sha256(HERE / "sRGB.icc"),
        "candidates": records,
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if proof_dir:
        proof_dir.mkdir(parents=True, exist_ok=True)
        board = Image.new("RGB", (820, 410), "#17191c")
        draw = ImageDraw.Draw(board)
        draw.text((20, 15), "Scale previews: square masters, not OS screenshots", fill="white")
        for row, (name, master) in enumerate(previews):
            y = 55 + row * 115
            draw.text((20, y + 25), name.title(), fill="white")
            for size, x in [(40, 170), (60, 300), (120, 480)]:
                thumb = master.resize((size, size), Image.Resampling.LANCZOS)
                thumb.save(proof_dir / f"{name}-{size}px.png", icc_profile=profile)
                board.paste(thumb, (x, y))
                draw.text((x + size + 8, y + 10), f"{size}px", fill="#aaaaaa")
        board.save(proof_dir / "scale-previews.png", icc_profile=profile)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proof-dir", type=Path, help="Write optional scale previews outside the source assets")
    export(parser.parse_args().proof_dir)
