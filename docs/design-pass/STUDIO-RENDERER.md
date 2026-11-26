# SceneKit barbell studio (historical)

The current native and web implementations are documented in [Photographic equipment](photographic-equipment/README.md). This page records the earlier SceneKit implementation.

Every native bar view renders one SceneKit scene, `BarbellStudio`
(`Cadence/Views/BarbellStudio.swift`): the session row, the current-set stage,
the plate calculator, the workout preview, the exercise library and the
loaded-bar inspector. It replaces the September sprite compositor and the
single-sleeve inspector (#316). Web has separate SVG and WebGL renderers.

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
- **Platform.** The 8 × 8 ft platform has plywood edges, rubber wings and a
  4 ft timber centre. The overhead Astra photograph supplies the grain and
  mat. Calibrated plates use the walnut finish, black banded bumpers use
  white oak, and IWF training uses maple. All other themes use oak. The
  transparent Heritage engraving is burned into each panel at runtime.
- **Light and steel.** An equipment-free strip from the oak/blue study wraps
  around the studio. A neutral softbox environment supplies moving reflections.
  The steel roughness map comes from the polished sleeve in that same study.
  The key casts shadows. Each grounded plate adds a narrow contact shadow.
- **Plate surfaces.** The four Astra equipment studies supply blue bumper,
  black rubber, coating and cast-iron detail. The solver and theme select
  plate dimensions, mass, colour and printed denomination for each load.

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

The exploded camera fits the actual plate bounds in both viewport dimensions
and reserves the measured caption height below them. Its lens and viewing
direction stay fixed; only an insufficient distance increases. At larger text
sizes the inspector grows its canvas height as well as its scrollable width,
so fitting the plates does not squeeze enlarged captions together.

## Assets and provenance

The source artwork, deterministic Pillow/NumPy exporter and SHA-256 manifest
live in [the Astra reference pack](astra-2026-11-01/). Image numbers refer to
the filenames in that directory.

| Runtime surface | Astra source | Use |
| --- | --- | --- |
| Gym and polished sleeve | 03 oak/blue | Equipment-free room strip, neutral sleeve strip and high-pass chrome roughness |
| Platform wood and rubber | 08 overhead | Unmarked timber and mat samples, with corresponding normal maps |
| Timber finishes | 04 walnut, 05 white oak, 07 maple | Photographed finish colour over the overhead grain |
| Engraving | 09 Heritage | Alpha burned into the timber centre |
| Bumper, coated, black rubber and cast surfaces | 03–06 | Neutral surface detail mapped to the live plate family |

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

`VisualProofUITests/test04PlateCalculatorHero` also launches the focused
`--render-lab --studio-framing-proof` mode. It checks five synthetic 45 lb
bumpers through the production camera and SceneKit projection at 592×300,
1184×300 and 1184×600 points, including space for captions, then captures the
real inspector at maximum Dynamic Type. This runs in the existing iPhone
visual-proof selection; it does not require another workflow selector.
