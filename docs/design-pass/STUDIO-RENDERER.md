# Barbell studio renderer (iOS)

Every native bar view renders one SceneKit scene, `BarbellStudio`
(`Cadence/Views/BarbellStudio.swift`): the session row, the current-set stage,
the plate calculator, the workout preview, the exercise library and the
loaded-bar inspector. It replaces the September sprite compositor and the
single-sleeve inspector (#316). Web keeps its sprite and WebGL renderers; it
has no users and is out of scope for this change.

## What is in the scene

- **Bar.** Physical dimensions from `BarbellInspector.BarDimensions` (men's and
  women's). The shaft has polished sections, a centre knurl, outer knurl zones
  broken by the 810/910 mm marks, and chalk in the knurl. The knurl normal map
  tiles at 24 mm (`StudioLathe` `uvMillimetres`), about a 1.5 mm diamond.
  Bronze bushings sit at the inner collars; the sleeves are polished chrome with
  two machined grooves and a recessed end cap. Spring-lock collars appear when
  the gym records collar weight.
- **Plates.** Built by lathe from the solver's loadout and the theme tables in
  `PlateTheme` (diameter, thickness, family, colour, finish, hub finish, bands).
  Rubber bumpers have a shallow ring groove, a rounded tyre and a bolted steel
  hub. Steel and calibrated plates have a painted face recessed inside a raised
  lip. Iron and machined plates have a sunken dish between a boss and a rim.
  Each flat face is a separate annulus with planar UVs and a baked texture:
  body colour with fine mottling, the denomination and unit on the lower arc,
  the brand on the upper arc, and a normal map that raises the print (cast
  lettering for iron). Denominations come from `Plate.denomination` and are
  never rounded.
- **Platform.** 8 × 8 ft: two plywood base layers with plies at the edge, a
  4 ft oak centre and ¾" stall mats. The existing Vitruvian artwork
  (`VitruvianFront`, read unchanged) is burned into the oak at runtime. Dark
  engraving lines char the wood and the paper ground leaves it bare.
- **Light.** The gym environment (`StudioGym`) is the visible background.
  What the bar and plates reflect is a product-photography light tent
  generated at launch (`StudioTextures.studioLight`): a dark neutral room
  with an overhead softbox, a wide front key and two tall rear strips. The
  gym alone made the chrome orange (it is mostly oak floor) and the plates
  dull. A front-left key light casts the shadows, and each plate standing on
  the platform gets a soft contact shadow.
- **Surface tooth.** Plate faces borrow their micro-texture from the
  September photographs the owner approved (`PlateBumper`, `PlateSteel`,
  5d2b150): the high-passed luminance of the real rubber and cast steel
  modulates the baked face colour and relief. Colour still comes only from
  the theme tables.

## Shots

| Shot | Used by | Camera |
| --- | --- | --- |
| `row` | each set row in the session | straight ahead at bar height; the bar fills the width |
| `hero` | current-set stage, calculator, preview, library, inspector (assembled) | three-quarter from the front left, 45 mm-equivalent |
| `blowup` | inspector (exploded) | the near sleeve's plates slid out along the sleeve |

Static views use `StudioRenderer` offscreen renders, cached by loadout, theme,
shot, size and scale, in memory and under `Caches/StudioRenders`, in a folder
named for the renderer version and the app build. Launch deletes other builds'
folders. The inspector is a live `SCNView` (`StudioInspector`)
that animates between `hero` and `blowup`, with screen-space captions under
each slid-out plate. Accessibility labels, plate children, captions and
identifiers are unchanged from the previous inspector.

## Assets and provenance

All renderer assets are original. They are produced by the look-dev scripts in
[`lookdev/`](lookdev/), which run in Blender 5.2 as a Python module
(`pip install bpy`):

| Asset | Source | Notes |
| --- | --- | --- |
| `StudioGym` | `bake.py env` (exposure −1) | 2048 × 1024 equirect, JPEG |
| `PlatformOak` | `bake.py oak` | 1024 × 2048 albedo, JPEG; logo composited at runtime |
| `PlatformMat` | `bake.py mat` | 512 × 2048 albedo, JPEG |
| `PlatformOakNormal`, `PlatformMatNormal` | `maps.py` | grain and pebble relief |

`studio.py` and `gym.py` are the owner-approved mockup scenes (pass 4, 10–11
October 2026). Plate lettering, wear and noise maps are generated at runtime
from deterministic seeds. No manufacturer marks are used. The brand line is
the theme's own (`CADENCE` by default).

## Visual QA

`--render-lab` (DEBUG only) renders a fixed matrix of loadouts, themes and
shots with the production renderer, plus an environment probe. It clears the
render cache first, so every image comes from the build under test, and a
failed render fails the test. It writes each PNG and a timing log to the
app's `tmp/render-lab`; run it on a simulator
with `CadenceVisualProofUITests/RenderLabUITests/testRenderLab`. During #316 a
branch-scoped workflow ran it and published the PNGs to
`render-proof/photoreal-316`. That workflow needed `contents: write` and a
force-push, so it was removed before merge rather than kept on main.
