# Loaded-bar sprites

Rendered by `web/tools/render-plate-sprites.py` (a deterministic signed-distance
ray marcher with a studio light rig) and installed here and into
`Cadence/Assets.xcassets/PlateSprites` by `web/tools/install-plate-sprites.mjs`;
the two copies are byte-identical and tested. Plates are greyscale and are
colourised at runtime from the shared luminance matrix; hubs and bar parts
stay untinted. One sprite per plate shape (diameter × thickness) at each
scene angle (assembled 18°, exploded 38°), plus shaft, sleeves, and collars.
Placement metadata is generated into `web/app/js/plate-sprites.js` and
`Cadence/Views/PlateSprites.swift`. No photograph or third-party asset is
involved; regenerate rather than edit.
