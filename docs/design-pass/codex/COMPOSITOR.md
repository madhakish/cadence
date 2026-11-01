# Compositor plan: #374's studio over a photographic plate

How the app turns a generated empty platform ([ASSET-SPEC.md](ASSET-SPEC.md))
and #374's SceneKit equipment into one picture of the solver's exact load.
Nothing here is implemented yet. It assumes #374 (`feat/photoreal-barbell-revive`,
`BarbellStudio.swift`) has merged, and extends that file rather than replacing
it.

In one line: lock a SceneKit camera to the photograph, render only the
equipment and its shadows over a transparent background, and lay that over
the photo. SceneKit keeps doing what it does well (geometry, occlusion,
chrome, printed faces from the theme tables); the photo supplies the room.

**Phase 1 is one shot**: the `hero` plate behind the current-set stage, the
plate calculator, the workout preview and the library, honey oak with blue
bumpers. The camera is the hero calibration pack's (`calibration.json`, from
#374 at `8a3301a`), which is #374's owner-approved hero. Rows, the inspector,
an overhead view and wood variants wait until phase 1 has passed the owner's
side-by-side.

```
 hero calibration pack (camera, lights, tone, landmarks, empty/loaded/landmark renders)
        │ reference                                   │ locked camera, tolerances
        ▼                                             ▼
 Codex plate (PNG, empty) ──► measure landmarks ──► solve plate camera ──► pass? ──no──► keep #374's 3D platform
                                                                      │ yes
                                                                      ▼
                                              bake canonical burn ──► PlatformHero + PlatformCameras
                                                                      │ drawn at view size
 PlateSolution ─► BarbellInspector.layout ─► BarbellStudio (composited) ─► RGBA equipment ─► over ─► hero views
```

## 1. Coordinates and the load

World coordinates are the pack's (ASSET-SPEC section 1): millimetres, origin
on the bar axis at the bar centre, +x along the bar, +y up, +z toward the
camera, platform top at y = −225 (`platform.top_surface_y_mm`), the platform
centred under the bar. That is #374's own scene for any load whose largest
plate is 450 mm, so for those loads `BarbellStudio` needs no coordinate
change at all.

**Known limit** (`variability.floor_drop`). #374 puts the platform top at
−(largest plate radius) and the camera's look-at y at −0.27 × that. A plate
photograph cannot follow either, so:

- **Today:** composite only when the loadout's largest plate radius is
  225 mm (every load with a full-size plate, which is what the owner trains
  with). Anything else, including an empty bar, renders on #374's
  deterministic platform exactly as now.
- **Proposed fix, pending the owner's sign-off:** pin the platform at
  y = −225 and the look-at at the pack's `look_at_mm` (−200, −60.75, 0) for
  every load, and lower the bar onto its largest plate instead: an
  `equipmentRoot` node at y = −(225 − restHeight), with
  `restHeight = max(bar.shoulderRadius, largest plate radius, collar radius if
  collars)`. The `max` also fixes a small existing nit: with no plates,
  `layout.maxRadius` falls back to the collar radius (40 mm) even without
  collars, so an empty bar hovers a few millimetres. With this in, every load
  composites, and #374's deterministic platform must adopt the same rule so
  the two modes agree on where the bar stands.

`variability.reach` is 1 for every real bar, so bar length never moves the
eye.

## 2. Camera

### 2.1 Locked, then solved per plate

1. **Locked.** The pack's `camera` block is the design intent and the
   reference Codex generates against: `position_mm` (−2000, 330, 2250),
   `look_at_mm` (−200, −60.75, 0), horizontal `fov_deg` 43.6, no roll,
   16:9. At 1170 px wide that is a focal length of about 1462.6 px.
2. **Measure.** Image generation does not hit exact pixels, so the plate's
   landmarks are measured on the plate itself: the in-frame platform-plane
   `landmarks[]` (the back-right platform corner and three oak corners) plus
   two well-separated points on each visible platform and oak edge. A small
   DEBUG overlay or script snaps them to the edges; Codex's `landmarksSeen`
   values are a starting point, not the answer. The bar landmarks
   (`sleeve_end_*`, `bar_centre`) are not on the plate and are only used
   for checking.
3. **Solve** (`docs/design-pass/codex/solve_plate_camera.py`, numpy, written
   in the implementation PR):
   - Every platform landmark lies in the plane y = −225, so they map
     (X, Z) → (u, v) through a homography H. Solve H by DLT from the points
     and lines (a line maps through H⁻ᵀ), at least four independent
     constraints. (The oak corners sit at y = −224.95; the 0.05 mm is below
     any pixel and is ignored.)
   - Assume square pixels, no skew and the principal point at the image
     centre (generators do not shift lenses). With pixels shifted so the
     principal point is the origin, the first two columns of K⁻¹H are
     orthogonal, so `f² = −(h11·h12 + h21·h22) / (h31·h32)`.
   - Pose: `r_x = λK⁻¹h1`, `r_z = λK⁻¹h2` (the plane's axes are world x and
     world z), `t = λK⁻¹h3`, `λ = 1/‖K⁻¹h1‖`, `r_y = r_z × r_x`, snapped to
     the nearest rotation by SVD, then the plane offset y = −225 restored;
     pick the sign that puts the platform in front of the camera.
   - Refine (f, R, t) with Levenberg–Marquardt on point reprojection error
     plus point-to-line distance, seeded from the pack's camera.
4. **Accept or fall back** with ASSET-SPEC section 6's checks: consistency
   (RMS ≤ 1.5 px, worst ≤ 3 px at 2340 px wide) and closeness to the pack
   (FOV within 10 % of 43.6°, pitch and heading within 2°, roll under 0.5°,
   both sleeve ends of the pack's load in frame). One correction pass from
   Codex; after that, keep #374's platform.
5. **Write** `PlatformCameras.json`: plate size, f, principal point,
   camera-to-world transform, residuals, the deltas from the pack, and the
   colour calibration from section 5.

The solver's test is the pack itself: feed it the pack's platform landmarks
(`world_mm`, `pixel`) and it must return the pack's `camera` within 0.5 % in
FOV, 0.1° in angle and 2 mm in position. The pack's own render of those
landmarks (`03-hero-empty-landmarks.png`) already shows its projection maths
agrees with SceneKit's.

Why render with the plate's solved camera rather than the pack's: the
equipment has to stand on the floor the photo actually shows. A plate that
passes the closeness check differs by a degree or two; rendering with the
pack's camera would leave the bar a few pixels off its own shadow line.

### 2.2 Applying it in SceneKit

- `cameraNode.simdTransform` = the solved camera-to-world. SceneKit cameras
  look down −z with +y up, so convert from the computer-vision frame
  (x right, y down, z forward) by negating the y and z basis vectors.
- `projectionDirection = .horizontal`, `fieldOfView = 2·atan(W / 2f)` from
  the solved f, `zNear` 40 and `zFar` 40000 as in the pack. Every hero
  surface asks `StudioRenderer` for its exact 16:9 size and the framing is
  FOV-locked (`surfaces.note`), so there are no crops and no off-axis
  projection in phase 1. If a later surface does crop, use an off-axis
  frustum built from f and the principal point and set it as
  `camera.projectionTransform`, rather than aiming a narrower camera at the
  crop (which keystones the bar).
- **Prove it with a test**: project every landmark with `projectPoint` at a
  couple of output sizes and compare with its measured plate pixel scaled to
  that size, within 1 px.

### 2.3 Camera effects in composited mode

Start from the pack's `camera.depth_of_field` and `tone_mapping`, which are
the app's current values:

| Setting | Composited mode | Why |
| --- | --- | --- |
| Depth of field (focus 2907.78 mm, f/5.6) | on for the equipment | The far sleeve should soften as it does in the pack. Check the transparent edges in the render lab; if SceneKit blurs equipment against the empty background into a halo, turn it off (the equipment sits 2.3–3.7 m from the eye, close to focus). |
| Vignetting (0.35 / 0.6) | off on the equipment layer | Applied once to the composite if the plate has none, never twice. |
| SSAO, bloom | as the pack | They act only on rendered equipment. |
| HDR, exposure −0.2 EV, contrast 0.12 | the pack's, then trimmed by section 5 | Tone mapping now applies to the equipment alone, so it must match the photo. |

## 3. What SceneKit renders

- **Removed** in composited mode: `StudioPlatform.add` (platform, mats,
  floor, wall, rack) and `scene.background` (`StudioGym`). Render with
  `SCNRenderer` into a transparent target.
- **Kept:** bar, plates, collars, materials, the light tent in
  `scene.lightingEnvironment` (`lighting.reflections`, intensity 3.2), the
  key light (`lighting.key`), and #374's per-plate contact shadows
  (`lighting.contact_shadows`), which ride with their plates.
- **Added: a shadow catcher.** One `SCNPlane` (6 × 6 m) at y = −225 with
  `lightingModel = .shadowOnly`, receiving the key's shadows and casting
  none. `.shadowOnly` needs deferred shadows, which the key already uses
  (`lighting.key.shadow.mode`). It renders the bar and plate shadows as black
  with alpha, so over the photo they darken oak and rubber alike. Mats and
  oak are flush, so one plane serves both.
- **Key light:** the pack's direction (`direction_travel_world`), colour and
  intensity, then trimmed against the plate by section 5. Shadow alpha
  (`color_alpha` 0.85) and radius (14) are calibrated too.
- **Environment:** keep the light tent for reflections (it is why the chrome
  reads as chrome), with its lower hemisphere tinted to the plate's measured
  lit-oak colour so sleeves and tyres pick up the floor they stand on.
- **Antialiasing:** 4× multisampling as in the pack, premultiplied alpha,
  source-over. Premultiplication keeps a dark fringe off chrome edges against
  bright oak.

All occlusion stays in SceneKit's depth buffer: the bar through every bore,
mixed stacks, collars outboard, far plates behind the shaft. That is the main
thing the rejected 2D cutout kit would have had to fake.

## 4. Surfaces and layering

Two layers: the plate (burn baked in, section 6), then the equipment. Per
`calibration.json` `surfaces`:

| Surface | Phase 1 | Size |
| --- | --- | --- |
| `session_current_set` (`BarbellStageView` → `BarbellView(.fullBar)`) | composited | about 370 × 208 pt, 1110 × 624 px |
| `plate_calculator` | composited | about 370 × 208 pt |
| `workout_preview_and_library` | composited | about 330 × 186 pt, in a card |
| `session_set_rows` (`row` shot) | #374 as today | different camera; needs its own plate later |
| `inspector_sheet` | #374 as today | different camera, animated (section 8) |

All composited surfaces are the same 16:9 frame at different sizes, so both
layers are drawn whole, never cropped or stretched. Render the equipment at
the view's pixel size; decode the plate with ImageIO straight to that size
(`CGImageSourceCreateThumbnailAtIndex`), never as a full-resolution bitmap per
view.

## 5. Matching colour and exposure

Calibrated once per plate in a DEBUG tool, stored in `PlatformCameras.json`,
read at runtime. Nothing is estimated on device.

1. **Exposure and white balance.** With Codex's probe plate: render
   SceneKit's own 18 % grey and chrome balls at the same positions
   ((−900, −175, +350) and (−900, −175, +650)) with the solved camera. Adjust
   `exposureOffset` from the pack's −0.2 EV until the grey ball's mean
   luminance is within 3 % of the photo's, and the key's colour until its
   chroma is within ΔE₀₀ 2. Without a probe, match against Codex's loaded
   look target and the pack's `02-hero-loaded-135lb.png` by eye in the render
   lab, and say so in the PR.
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
#374 and the pack (`platform.logo`: 950 mm square, centred under the bar, top
of the art toward −z). With the solved camera, the burn square's corners on
the plane y = −225 map to four plate pixels; warp the artwork with that
perspective transform and burn it into the oak with #374's curve
(`StudioTextures.brandedOak`: ink from the artwork's luminance, smoothstepped
between 0.24 and 0.62, blended in linear light toward the char colour
0.028 / 0.014 / 0.007). It multiplies the photo's own grain, so the grain runs
through the burn.

Do it **offline**, in the same run as the camera solve, and ship the burned
plate: deterministic, reviewable as an image in the PR, free at runtime.
Codex's clean plate stays the master, so the burn can be redone whenever the
curve or the artwork changes.

## 7. Loads, collars, odd plates

Unchanged from #374, because SceneKit still builds them from the shared
layout (subject to the largest-plate rule in section 1):

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

The inspector sheet (`surfaces.inspector_sheet`) is a live `SCNView` with its
own camera (same eye, look-at y −0.1 × floor drop, FOV 41°, about
370 × 300 pt) that animates to the blow-up. A flat plate fixes the camera, so
interactive inspection stays in #374's coherent deterministic scene:

- **Phase 1: unchanged.** Tapping a composited hero opens the sheet exactly
  as today, with the deterministic platform and decal. The sheet's
  presentation, a different view with a different camera, already separates
  the two pictures; nothing has to morph.
- **Later, if the jump between the photo and the 3D room reads badly:** give
  the sheet's first frame its own plate (calibrated from
  `surfaces.inspector_sheet.camera`) and cross-fade it out over the
  deterministic platform before the camera starts moving, back in once it has
  returned. Only the room changes, only while nothing moves. That needs a
  render-lab frame sequence of the hand-over and the owner's sign-off.
- **Reduce Motion:** as #374.

## 9. Caching and performance

- `StudioRenderer.Request` gains the plate id; `version` becomes 3, which
  retires #374's disk renders. The key still includes loadout, theme, style,
  shot, pixel size and scale.
- Cache the **flattened composite**: one opaque image per request, on disk as
  HEIC or JPEG (no alpha needed, unlike #374's PNGs) and in the existing
  `NSCache` with cost = bytes. A 1110 × 624 composite is about 2.8 MB decoded.
- Decode the camera file and the plate once per size per process; #374's
  launch prewarm warms them too.
- Composited renders drop the platform geometry, its textures and the runtime
  burn from the scene, so a fresh render should be at or under #374's
  0.4–1.5 s. The render lab measures it and the PR reports it.

## 10. Fallbacks

- Plate fails registration, or its asset or camera file is missing or
  unreadable: #374's deterministic platform and decal, exactly as today. The
  composited mode is an upgrade over #374, never a dependency of it.
- A load whose largest plate is not 450 mm, until the pinned-platform fix
  lands: the same.
- Metal unavailable (`BarbellSceneView.isSupported == false`): #374's
  fallback, unchanged.
- A failed equipment render shows the plate with the textual readout, never
  a blank card.

## 11. Proving it

- Solver test against the pack's landmarks (section 2.1).
- Projection test: landmarks within 1 px at several output sizes
  (section 2.2).
- Render lab: #374's loadout matrix in composited mode beside the
  deterministic renders, plus the pack's load (one 45 lb blue bumper a side,
  `lbColourBumpers`) beside `02-hero-loaded-135lb.png` and Codex's look target.
- Side-by-side against `docs/design-pass/approved/` and the current renderer,
  with the owner's sign-off in the PR, per #374's renderer rule. Captures
  name the exact head SHA and the synthetic load, so Codex can review them.
- Size: phase 1 adds under 1 MB; the PR states the measured number.

## Owner decisions

1. **Pinned platform:** approve pinning the platform at −225 mm and lowering
   the bar onto smaller plates (section 1). Without it, loads with no 450 mm
   plate stay on the deterministic platform.
2. **Inspector:** keep phase 1's plain switch to the 3D room, or later add a
   first-frame inspector plate and cross-fade.
3. **After phase 1:** a plate for session rows, per-theme wood variants,
   overhead.
