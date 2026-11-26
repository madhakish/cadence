"""Hash an explicit PNG capture list; provenance is declared, never inferred."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def inventory(root, names, source_sha, platform):
    if not re.fullmatch(r"[0-9a-fA-F]{40}", source_sha):
        raise ValueError("source SHA must be a complete 40-character Git SHA")
    if platform not in ("native", "web", "mockup"):
        raise ValueError("platform must be native, web or mockup")
    root = Path(root).resolve(strict=True)
    if not root.is_dir() or not names:
        raise ValueError("a capture directory and explicit file list are required")
    files, seen = [], set()
    for name in names:
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("capture paths must be relative and stay inside root")
        path = (root / relative).resolve(strict=True)
        if root not in path.parents or path in seen:
            raise ValueError("capture escapes root or appears more than once")
        seen.add(path)
        if path.suffix.lower() != ".png" or not path.is_file():
            raise ValueError("captures must be PNG files")
        data = path.read_bytes()
        if not data.startswith(b"\x89PNG\r\n\x1a\n") or len(data) <= 8:
            raise ValueError("capture has no PNG signature or payload")
        files.append({"path": relative.as_posix(), "bytes": len(data),
                      "sha256": hashlib.sha256(data).hexdigest()})
    return {"source_sha": source_sha.lower(), "declared_platform": platform,
            "validation": "Byte inventory only; image decoding, origin and visual review not verified.",
            "files": files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--platform", choices=("native", "web", "mockup"), required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("captures", nargs="+")
    args = parser.parse_args()
    try:
        result = inventory(args.root, args.captures, args.source_sha, args.platform)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
