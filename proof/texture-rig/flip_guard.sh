#!/bin/bash
# FLIP guard: bash flip_guard.sh <golden.png> <candidate.png> <out-dir>
# Compares a candidate render with the golden one using NVIDIA FLIP and writes
# <out-dir>/<candidate-stem>-flip.png (magma error map) and -flip.json (FLIP's
# mean, weighted median and max, the thresholds, and both inputs' SHA-256).
#
# Exit: 0 within thresholds; 1 over one (the change is visible: it needs the
#       owner's side-by-side); 2 the guard couldn't judge (usage, venv, inputs).
# Env:  FLIP_VENV (required): a venv holding flip-evaluator==1.7 and pillow,
#       kept outside the repository. One way to make it:
#         uv venv --python 3.12 "$FLIP_VENV"
#         VIRTUAL_ENV="$FLIP_VENV" uv pip install flip-evaluator==1.7 pillow==13.0.0
#       FLIP_MAX_MEAN (default 0.001), FLIP_MAX_WMEDIAN (default 0.05). Why these:
#       docs/design-pass/codex/RENDERER-CONTRACT.md, "Verifying a renderer change".
set -euo pipefail
fail() { echo "flip-guard: CAN'T JUDGE: $*" >&2; exit 2; }
[ $# -eq 3 ] || fail "usage: flip_guard.sh <golden.png> <candidate.png> <out-dir>"
[ -n "${FLIP_VENV:-}" ] || fail "FLIP_VENV is not set; point it at a venv with flip-evaluator==1.7 and pillow (see the header of $0)"
[ -x "$FLIP_VENV/bin/python" ] && [ -x "$FLIP_VENV/bin/flip" ] || fail "FLIP_VENV=$FLIP_VENV has no bin/python and bin/flip"
exec "$FLIP_VENV/bin/python" -I "$(cd "$(dirname "$0")" && pwd)/flip_guard.py" "$@"
