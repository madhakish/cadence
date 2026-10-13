# Loaded-bar sprites

Rendered by `web/tools/render-plate-sprites.py` (a deterministic signed-distance
ray marcher with a studio light rig) and installed here and into
`Cadence/Assets.xcassets/PlateSprites` by `web/tools/install-plate-sprites.mjs`;
the two copies are byte-identical and tested. Every sprite is procedural and
saved as grey+alpha PNG. Plates are greyscale and are colourised at runtime
from the shared luminance matrix; hubs, hub bolts and bar parts stay
untinted (cast-iron plates have no separate hub, so only the bore does).

Families, one sprite per shape (diameter × thickness) at each scene angle
(assembled 18°, exploded 38°), plus shaft, sleeves, and collars:

- `bumper`: rubber with a raised rim, chrome hub with six bolt heads
- `steel`: dished steel (custom sets)
- `ipf`: calibrated painted disc, raised outer lip, recessed face, small
  chrome hub, two calibration plugs
- `iron`: cast iron, raised rim lip and centre boss, cast skin
- `machined`: turned steel face with a shallow rim step, chrome hub
- `change`: flat fractional plates

Shapes come from the custom tables plus the plate-theme sets; dimensions are
from `docs/design-pass/PLATE-REFERENCE.md`. Names spell millimetres with
integers bare and fractions with "p" for the point (`plate-ipf-450x22p5-assembled`),
so no asset name contains a dot; the manifests' `shapes` list and each plate
sprite carry the numeric diameter and thickness, so never parse a name.
`plates` maps `<family>:<plate id>` to a
shape (the custom tables win for a plate listed twice); any rendered shape is
also addressable as `plate-<family>-<D>x<T>-<angle>`. Placement metadata is
generated into `web/app/js/plate-sprites.js` and
`Cadence/Views/PlateSprites.swift`.

`bumper-face-detail.png` and `steel-face-detail.png` are PR #263's
face-detail textures. The renderer reads them as grain references for the
bumper, steel and change faces; the installer never writes or deletes them.
Regenerate the sprites rather than edit them.

Renderer source SHA-256: `c6b6e3b59eee519c694cfb6912ff75d41e00672778f37dc94f95bb8fb856739b`.


## Reviewing asset changes

Verify the current branch's consumers and installer before regeneration; native
renderer work may change which assets are shared. Keep dimension/denomination
metadata authoritative rather than parsing file names. A regenerated sprite or
browser screenshot is not native acceptance. Use the repository's
[native proof guide](../../../../.agents/skills/cadence-native-proof/SKILL.md)
for math, geometry and actual simulator/device evidence, and keep captures out
of this production asset directory.
