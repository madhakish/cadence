# Compositor plan: #374's studio over a photographic plate

How the app turns a generated empty platform ([ASSET-SPEC.md](ASSET-SPEC.md))
and #374's SceneKit equipment into one picture of the solver's exact load.
Nothing here is implemented yet. It assumes #374 (`feat/photoreal-barbell-revive`,
`BarbellStudio.swift`) has merged and extends that file rather than replacing
it.

In one line: lock a SceneKit camera to the photograph, render only the
equipment and its shadows over a transparent background, lay that over the
photo. SceneKit keeps doing what it does well (geometry, occlusion, chrome,
printed faces from the theme tables); the photo supplies the room.

**Phase 1 is one shot**: the HERO plate behind the current-set stage and the
plate calculator, honey oak and blue bumpers. Rows, the overhead view and
wood variants wait until phase 1 has passed the owner's side-by-side.

```
 calibration pack (SceneKit: camera, lights, landmarks, empty/loaded/landmark renders)
        │ reference                                   │ locked camera, tolerances
        ▼                                             ▼
 Codex plate (PNG, empty) ──► measure landmarks ──► solve plate camera ──► pass? ──no──► keep #374's 3D platform
                                                                      │ yes
                                                                      ▼
                                              bake canonical burn ──► PlatformHero + PlatformCameras
                                                                      │ crop to view
 PlateSolution ─► BarbellInspector.layout ─► BarbellStudio (composited) ─► RGBA equipment ─► over ─► stage view
```

## 1. Coordinates

The plate is described in **platform coordinates** (ASSET-SPEC section 1:
origin on the platform's top centre, x along the bar, y up, z toward the
front). #374 builds everything in **bar coordinates** (origin on the bar
axis, floor at `y = −floorDrop`, `floorDrop = layout.maxRadius`). The bridge
is one node:

- `equipmentRoot` at platform position `(0, restHeight, −500)` holds the
  shaft, shoulders, sleeves, plates and collars exactly as #374 builds them.
- `restHeight = layout.maxRadius`, as #374 already does: the bar rests on its
  largest plate and smaller plates hang. One fix while here: with no plates,
  `maxRadius` falls back to the collar radius (40 mm) even without collars,
  so an empty bar hovers a few millimetres. Use
  `max(bar.shoulderRadius, largest plate radius, collar radius if collars)`.
- #374's deterministic platform moves with it: the platform is centred at
  z = 0 and the bar at z = −500 in **both** modes. The inspector hands over
  between the two (section 8), so they must agree on where the bar stands.

The camera is fixed to the platform, so a heavier load never moves it; the
bar rises with bigger plates, as a real one does.

## 2. Camera

### 2.1 Locked first, then solved per plate

1. **Calibration pack.** The Cadence side fixes the hero camera, lights and
   crops in #374's scene and exports `calibration.json` with the empty,
   loaded and landmark renders (ASSET-SPEC section 3). That camera is the
   design intent and the reference Codex generates against.
2. **Measure.** Image generation does not hit exact pixels, so the plate's
   landmarks are measured on the plate itself: the visible platform and oak
   corners, plus two well-separated points on each visible edge. A small
   DEBUG overlay or script snaps them to the edges; Codex's `landmarksSeen`
   values are a starting point, not the answer.
3. **Solve** (`docs/design-pass/codex/solve_plate_camera.py`, numpy, written
   in the implementation PR):
   - The platform top is the plane y = 0, so landmarks map (X, Z) → (u, v)
     through a homography H. Solve it by DLT from points and lines (a line
     maps through H⁻ᵀ), at least four independent constraints.
   - Assume square pixels, no skew, principal point at the image centre
     (generators do not shift lenses). With pixels shifted so the principal
     point is the origin, the first two columns of K⁻¹H are orthogonal, so
     `f² = −(h11·h12 + h21·h22) / (h31·h32)`.
   - Pose: `r_x = λK⁻¹h1`, `r_z = λK⁻¹h2` (the plane's axes are world x and
     world z), `t = λK⁻¹h3`, `λ = 1/‖K⁻¹h1‖`, `r_y = r_z × r_x`, snapped to
     the nearest rotation by SVD; pick the sign that puts the platform in
     front of the camera.
   - Refine (f, R, t) with Levenberg–Marquardt on point reprojection error
     plus point-to-line distance, seeded from the calibration camera.
4. **Accept or fall back** with ASSET-SPEC section 6's two checks:
   consistency (RMS ≤ 1.5 px, worst ≤ 3 px at 2400 px wide) and closeness to
   the locked camera (focal within 10 %, pitch and heading within 2°, roll
   under 0.5°, the pack's loaded bar inside the stage crop). One correction
   pass from Codex; after that, keep #374's platform.
5. **Write** `PlatformCameras.json`: image size, f, principal point,
   camera-to-world transform, residuals, the closeness deltas, and the
   calibration block from section 5.

The solver's test feeds it the pack's synthetic landmarks (rendered from a
known camera, so the answer is known) and requires the camera back within
0.5 % in focal length and 0.1° in angle. ASSET-SPEC section 3's proposal
table serves as that fixture until the pack lands.

Why use the plate's solved camera rather than the locked one: the equipment
has to sit on the floor the photo shows. A plate that passes the closeness
check differs from the pack by a degree or two; rendering with the pack's
camera would leave the bar a few pixels off its own shadow line.

### 2.2 Applying it in SceneKit

- `cameraNode.simdTransform` = the solved camera-to-world. SceneKit cameras
  look down −z with +y up, so convert from the computer-vision frame
  (x right, y down, z forward) by negating the y and z basis vectors.
- **Projection for a crop.** Every view shows a crop of the plate
  (section 4). For a crop rectangle (x₀, y₀, w, h) in plate pixels, focal f,
  principal point (cx, cy), near plane n and far plane F, the off-axis frustum
  is

  ```
  left   = (x₀ − cx)      · n / f      right  = (x₀ + w − cx) · n / f
  top    = (cy − y₀)      · n / f      bottom = (cy − y₀ − h) · n / f
  ```

  Build the standard frustum matrix from those and set
  `camera.projectionTransform`. SceneKit has no lens-shift property, and
  aiming a narrower camera at the crop's centre would keystone the bar; an
  off-axis frustum is exact.
- **Prove it with a test**, because clip-space conventions are easy to get
  backwards: project every landmark with `projectPoint` and compare with its
  measured pixel mapped into the crop, within 1 px.
- **Fallback** if the matrix route misbehaves: render the plate's full frame
  with `fieldOfView = 2·atan(W / 2f)` (horizontal) and crop in 2D. Costs extra
  pixels, gives the same image.

### 2.3 Camera effects in composited mode

| #374 setting | Composited mode | Why |
| --- | --- | --- |
| Depth of field | off | The photo carries the room's defocus; at 60 mm, f/5.6 and about 4 m the equipment's 1.2 m depth range is acceptably sharp. SceneKit's DOF also ignores a custom projection. |
| Vignetting | off | The plate has its own; a doubled vignette darkens the sleeves. |
| SSAO | on | It acts only on rendered equipment, which is what needs it. |
| Bloom | on, threshold 1.1 | As #374; only chrome highlights cross it. |
| HDR, exposure, contrast | on, values from calibration (section 5) | Tone mapping now applies to the equipment alone, so it must match the photo. |

## 3. What SceneKit renders

- **Removed** in composited mode: `StudioPlatform.add` (platform, mats,
  floor, wall, rack) and `scene.background`. Render with `SCNRenderer` into a
  transparent target.
- **Kept:** bar, plates, collars, materials, the light tent environment, the
  key light, and #374's per-plate contact shadows, which ride with their
  plates.
- **Added: a shadow catcher.** One `SCNPlane` (6 × 6 m) at platform y = 0
  with `lightingModel = .shadowOnly`, receiving the key's shadows and casting
  none. `.shadowOnly` needs deferred shadows, which #374's key already uses.
  It renders the bar and plate shadows as black with alpha, so over the photo
  they darken oak and rubber alike. The mats and oak are flush, so one plane
  serves both.
- **Key light:** direction, colour temperature (`SCNLight.temperature`) and
  intensity from `calibration.json`, then trimmed by section 5. Shadow alpha
  and radius are calibrated too.
- **Environment:** #374's light tent for reflections (it is why the chrome
  reads as chrome), with its lower hemisphere tinted to the plate's measured
  lit-oak colour so sleeves and tyres pick up the floor they stand on.
- **Antialiasing:** 4× multisampling, premultiplied alpha, source-over.
  Premultiplication keeps a dark fringe off chrome edges against bright oak.

All occlusion stays in SceneKit's depth buffer: the bar through every bore,
mixed stacks, collars outboard, far plates behind the shaft. That is the main
thing the rejected 2D cutout kit would have had to fake.

## 4. Crops and layering

Two layers: the plate crop (burn baked in, section 6), then the equipment.
Phase 1 crops, in plate pixels of the proposed 2400 × 1800 frame (the pack's
`crops` replace these):

| Presentation | Crop | Notes |
| --- | --- | --- |
| Stage: current set, calculator, workout preview, library (`BarbellStageView`, `.fullBar`) | (60, 250, 2160, 1412), 1.53:1 | Both sleeve ends, both stacks, most of the burn |
| Inspector, first frame (`BarbellInspectionView`, 300 pt tall) | (60, 0, 2160, 1800), 1.2:1 | Same width, full overscan height |
| Session row (`.compactSide`) | not in phase 1 | Stays on #374's `row` render until the SIDE plate exists |

For any other aspect: the largest rectangle of that aspect containing the
"must show" box (sleeve ends and the tallest plate positions; x 100 … 2070,
y 450 … 1200 on the proposed frame), centred on the bar. If the box does not
fit inside the plate at that aspect, fit the box and pad with a gradient into
the app background rather than stretch anything.

Render the equipment at the view's pixel size with the crop's projection, so
it is never resampled. Decode the plate with ImageIO straight to the crop's
pixel size, never as a full 2400 × 1800 bitmap per view.

## 5. Matching colour and exposure

Calibrated once per plate in a DEBUG tool, stored in `PlatformCameras.json`,
read at runtime. Nothing is estimated on device.

1. **Exposure and white balance.** With Codex's probe plate: render
   SceneKit's own 18 % grey and chrome balls at the same platform positions
   with the solved camera. Adjust `exposureOffset` until the grey ball's mean
   luminance is within 3 % of the photo's, and the key's temperature until
   its chroma is within ΔE₀₀ 2. Without a probe, match against Codex's loaded
   look target by eye in the render lab, and say so in the PR.
2. **Key direction.** If the probe exists, rotate the key until SceneKit's
   chrome-ball highlight lands within 10 px of the photo's. Either way, check
   the bar's shadow against the look target: back and right across the mats.
3. **Shadow density.** Set the catcher's shadow alpha so shadowed to lit oak
   luminance matches the probe's contact shadow (or the look target's bar
   shadow) within 10 %.
4. **Black level.** The darkest equipment pixels (collars, shaded rubber) may
   not be darker than the plate's darkest shadow; if they are, store a small
   lift for the equipment layer.
5. **Grain and softness.** Generated photos carry noise and are softer than a
   clean render. Measure noise σ on a flat lit patch of mat and the edge width
   of the platform's back edge; add monochrome grain of that σ to the
   equipment layer only (masked by its alpha), and a 0.3–0.7 px Gaussian if
   the photo is softer. Both are calibration constants.

## 6. The burn

The gorilla is the canonical `VitruvianFront` artwork, read unchanged, as in
#374. With the solved camera, the burn square (950 mm, centred at x 0,
z +150) maps to four plate pixels; warp the artwork with that perspective
transform and burn it into the oak with #374's curve
(`StudioTextures.brandedOak`: ink from the artwork's luminance, smoothstepped
between 0.24 and 0.62, blended in linear light toward the char colour
0.028 / 0.014 / 0.007). It multiplies the photo's own grain, so the grain
runs through the burn.

Do it **offline**, in the same run as the camera solve, and ship the burned
plate: deterministic, reviewable as an image in the PR, free at runtime.
Codex's clean plate stays the master, so the burn can be redone whenever the
curve or the artwork changes.

## 7. Loads, collars, odd plates

Unchanged from #374, because SceneKit still builds them from the shared
layout:

- **Mixed stacks** (kg and lb on one sleeve, reverse-order stacks): exact
  order from `PlateSolution.loadout`, geometry from `PlateTheme.geometry`.
- **Collars:** shown when the gym records collar weight; #374's spring-lock
  collar, outboard on both sleeves.
- **Unknown plates** (imported denominations outside every table): the
  `PlateGeometry.reference` profile and the theme's fallback colour, as
  today. No plate depends on an asset that might be missing.
- **Women's bars:** shorter sleeves, same world position; the frame does not
  move.

Phase 1 uses the one honey-oak plate for every theme. `PlateTheme.backdrop`
can map to wood variants later; the camera file is per plate.

## 8. Inspector and blow-up

A flat plate fixes the camera, and #374's blow-up moves it. So interactive
inspection stays in a coherent deterministic scene, and the hand-over is
explicit:

- **Opening.** The inspector starts as #374's live `SCNView` with the
  deterministic platform and decal, using the plate's solved camera and the
  inspector crop. Its first frame shows the photo plate on top (a static
  image in the same `ZStack`), so opening changes nothing on screen.
- **Hand-over.** Before the camera moves, the photo cross-fades out over the
  deterministic platform underneath (0.25 s). The equipment is the same
  SceneKit content throughout, so only the room changes, and only while
  nothing is moving. Then #374's `hero` → `blowup` motion runs as it does
  today: camera toward the near sleeve, plates sliding out by
  `blowupSpacing`, captions under each plate. Assembling reverses it and the
  photo fades back in once the camera is home.
- **Proof required.** The deterministic platform and the photo will not match
  exactly (wood, mats, light). The implementing PR captures the hand-over as
  a frame sequence in the render lab, side by side, and the owner signs off on
  it. If the jump reads as a glitch, use the fallback below.
- **Fallback, fixed camera over the plate:** keep the photo, never move the
  camera, and run `explode(t)` in place: near plates slide outward along the
  sleeve (at most 95 mm a plate, never past the platform edge), near collar
  fades, far stack stays loaded. Coherent by construction, smaller payoff:
  no close-up, and the faces are seen at the hero's angle.
- **Reduce Motion:** no camera move and no slide. Tapping swaps between the
  assembled composite and the exploded deterministic render with a 0.15 s
  cross-fade (or none); captions appear in place.
- **No orbit.** Neither path rotates freely; the "Drag to inspect" glyph in
  the references becomes drag-to-explode. Rotation would mean living in the
  deterministic scene the whole time, which is a product call (below).

## 9. Caching and performance

- `StudioRenderer.Request` gains the plate id and crop; `version` becomes 3,
  which retires #374's disk renders. The key still includes loadout, theme,
  style, shot, pixel size and scale.
- Cache the **flattened composite**: one opaque image per request, on disk as
  HEIC or JPEG (no alpha needed, unlike #374's PNGs) and in the existing
  `NSCache` with cost = bytes. A 1179 × 770 composite is about 3.6 MB decoded.
- Decode the camera file and the plate crops once per process; #374's launch
  prewarm warms them too.
- Composited renders drop the platform geometry, its textures and the runtime
  burn from the scene, so a fresh render should be at or under #374's
  0.4–1.5 s. The render lab measures it and the PR reports it.

## 10. Fallbacks

- Plate fails registration, or its asset or camera file is missing or
  unreadable: #374's deterministic platform and decal, exactly as today. The
  composited mode is an upgrade over #374, never a dependency of it.
- Metal unavailable (`BarbellSceneView.isSupported == false`): #374's
  fallback, unchanged.
- A failed equipment render shows the plate with the textual readout, never
  a blank card.

## 11. Proving it

- Solver test against synthetic landmarks (section 2.1).
- Projection test: landmarks within 1 px through every crop (section 2.2).
- Render lab: #374's loadout matrix in composited mode beside the
  deterministic renders, plus the pack's load (one 45 lb blue bumper a side,
  `lbColourBumpers`) beside Codex's loaded look target.
- The inspector hand-over sequence (section 8).
- Side-by-side against `docs/design-pass/approved/` and the current
  renderer, with the owner's sign-off in the PR, per #374's renderer rule.
  Captures name the exact head SHA and the synthetic load, so Codex can
  review them.
- Size: phase 1 adds about 1–1.5 MB; the PR states the measured number.

## Owner decisions

1. **Inspector hand-over:** photo-to-3D cross-fade with #374's close-up
   blow-up, or the fixed-camera blow-up over the photo.
2. **Rotation:** none (as above), or a fully deterministic inspector that can
   orbit.
3. **After phase 1:** SIDE plate for rows, per-theme wood variants, overhead.
