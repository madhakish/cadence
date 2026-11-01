# Platform plate: asset spec for Codex

**Reader: Codex (image generation).** This is the brief for the photographic
background behind Cadence's loaded barbell, written to be checked off line by
line. Where it says "must", a delivery that misses it goes back.

## The split, and why

Cadence draws the solver's exact loadout: bar type, every plate in stack
order, collars, any theme, any imported denomination. That geometry has to be
deterministic, and it already is: #374's SceneKit studio
(`Cadence/Views/BarbellStudio.swift` on `feat/photoreal-barbell-revive`)
builds the bar, plates and collars from `BarbellInspector.layout` and the
`PlateTheme` tables. What it cannot do in real time is look like a photograph
of a room. Generated images can, but they redraw details every time, as your
concept pack's README says itself.

So the work splits where the load stops mattering:

| Layer | Who makes it | Changes with the load? |
| --- | --- | --- |
| Platform, mats, gym floor, gym backdrop | **Codex**: one generated photographic *plate* per shot, empty | No |
| Camera, lights, tone, platform dimensions, landmarks | **Cadence side**: the hero calibration pack, already rendered from #374 | No |
| Vitruvian gorilla burn on the oak | The app: the canonical `VitruvianFront` artwork, warped onto the oak with the solved camera, never redrawn | No |
| Bar, plates, collars, their shadows | The app: #374's SceneKit scene, transparent background, shadow catcher | Yes |

[COMPOSITOR.md](COMPOSITOR.md) is how the app puts these together. Two
alternatives were considered and rejected (section 10): a per-plate cutout
kit, and an earlier draft of this spec that proposed its own hero camera.

## Phase 1: one matched hero shot

Phase 1 proves the hybrid on one shot before anything else gets a plate: the
three-quarter `hero` that #374 renders for the current-set stage, the plate
calculator, the workout preview and the library. Look target: **honey oak
with blue bumpers** (your `03-platform-oak-blue.png`).

The order of work:

1. **The camera is locked.** The hero calibration pack (section 3) was
   rendered from #374 at `8a3301a` by the production renderer. Its camera,
   lights, tone mapping, platform and landmarks are fixed; you have it.
2. **Codex generates the plate against the pack's renders** (section 4),
   using them as the composition and perspective reference. You do not invent
   a focal length, light temperature or other metadata after the fact.
3. **Cadence verifies and solves** the plate's actual camera from the
   landmarks it can see (COMPOSITOR section 2), against explicit tolerances
   (section 6).
4. **Fallback:** a plate that will not register within tolerance after one
   correction pass is not used, and the app keeps #374's deterministic
   platform and decal, which is what ships today. Nothing degrades if phase 1
   fails.

## 1. World coordinates

The pack's coordinates, unchanged (`calibration.json` `units`):

- Millimetres. Right-handed.
- Origin at the **bar centre**: the bar axis is y = 0, z = 0.
- **+x** along the bar to the image right (the far sleeve), **+y** up,
  **+z** toward the camera side.
- The platform top is at y = −225 mm (`platform.top_surface_y_mm`), the
  radius of a 450 mm plate (`platform.bar_axis_height_above_platform_m`
  = 0.225).

The platform (`calibration.json` `platform`), which is #374's
`StudioPlatform`, an 8 × 8 ft Olympic platform centred under the bar:

| Part | Field | Value |
| --- | --- | --- |
| Whole platform | `size_m` | 2.4384 × 2.4384 m: x and z −1219.2 … +1219.2 mm |
| Oak centre strip, running front to back | `oak_centre_width_m` × `oak_centre_length_m` | 1.2192 × 2.4384 m: x −609.6 … +609.6 mm |
| Stall mats, left and right | `mats_each_width_m` | 0.6086 m each, x ±610.6 … ±1219.2 mm |
| Base | `layer_thickness_m`, `stack` | two 19.05 mm plywood layers; plies visible at the edges |
| Gorilla burn | `logo` | `VitruvianFront`, 950 mm square, centred under the bar, top of the art toward −z (added by the app, not by you) |
| Room | `room` | gym floor plane 2 × 19.05 mm below the platform base; block wall at z = −4300 mm; rack uprights at x = ±620, z = −2600 / −3650 mm |

The bar crosses the oak and both plate stacks land on the mats.

## 2. The look, in words

The owner's references (generated stills he supplied on 2026-11-01, kept out
of this public repository) and your concept pack
(`docs/design-pass/astra-2026-11-01/`, published by your own PR from
`docs/astra-visual-handoff`) agree on this:

- **Subject.** A competition lifting platform in a dark, serious gym. Warm
  honey oak centre with real grain running front to back, satin finish, a
  little wear where lifters stand. Black stall mats either side, fine pebble
  texture, slightly lighter scuffs where plates land. Plywood plies visible
  on the platform edge.
- **Room.** Dark rubber gym floor around the platform. Behind it, out of
  focus, where the pack has them: a block wall and power racks, optionally a
  plate tree with coloured bumpers. Everything behind the platform at least
  two stops darker than the oak. No windows, people, signage, readable text or
  brand marks.
- **Mood.** Catalogue product photography in a real gym, not a render and not
  a moody poster. Controlled light, deep but not crushed shadows, frame edges
  falling off into near-black (about `#111316`) so the app's charcoal UI can
  meet it.
- **Light.** The pack's (section 3): one high key from the front-left plus a
  soft light tent of overhead softbox, front key, rear strips and side fill,
  with warm bounce off the oak.
- **Materials the app will put on top** (for your loaded look target only):
  tight bright chrome reflections, smooth sleeves against a zoned shaft knurl,
  matte to satin rubber with moulded edges, both stacks on rubber. The pack's
  `02-hero-loaded-135lb.png` shows the load in place.
- **Clean oak.** No burn, logo or engraving. The app burns the canonical
  gorilla in itself so the artwork is never redrawn, and the photo's grain
  runs through the burn.

## 3. The calibration pack

The hero pack, from #374 at `8a3301a` (`calibration.json` `source_commit`),
was rendered on the iPhone 18 Pro simulator through a DEBUG-only capture path
that is not committed. It travels with its README rather than living in this
repository. It is the single source of truth; every value below is quoted
from it, by field name, and where this page and the pack ever disagree the
pack wins.

| File | Contents |
| --- | --- |
| `01-hero-empty-platform.png` | The empty platform at final size, 1170 × 658, with the app's camera, light, depth of field and tone mapping; bar, plates, collars and contact shadows removed. **Your reference.** |
| `01b-hero-empty-platform@2x.png` | The same at 2340 × 1316 |
| `02-hero-loaded-135lb.png` | Look reference: 45 lb men's bar, one 45 lb blue bumper a side (`lbColourBumpers`), 135 lb (`loadout_for_this_camera`) |
| `03-hero-empty-landmarks.png` | Depth of field off; red spheres are the landmarks in 3D, cyan crosshairs the JSON's projected pixels (they coincide), yellow line the bar axis at rest |
| `calibration.json` | Camera, landmarks, lights, tone mapping, surfaces, variability |

### Camera (`camera`, `output`)

| Field | Value |
| --- | --- |
| `projection`, `fov_axis`, `fov_deg` | perspective, horizontal, 43.6° (`fov_vertical_deg_derived` 25.35°) |
| `position_mm` | (−2000, 330, 2250) |
| `look_at_mm` | (−200, −60.75, 0) |
| `forward_world`, `up_world` | (0.61903, −0.13438, −0.77379), (0.08395, 0.99093, −0.10493); no roll |
| `orientation_quaternion_xyzw` | (−0.063547, −0.330256, −0.022292, 0.941486) |
| `zNear_mm`, `zFar_mm` | 40, 40000 |
| `depth_of_field` | on: `focus_distance_mm` 2907.78, `f_stop_physical` 5.6, 12 samples, 7 blades |
| `output.width_px` × `output.height_px` | 1170 × 658 (16:9, `aspect` 1.77812); the @2x render is 2340 × 1316 |
| `output.color_space`, `output.antialiasing` | sRGB 8-bit, 4× multisampling |

The framing is locked to the horizontal FOV, so every 16:9 size frames
identically and only the pixel count changes. At 1170 px wide the focal
length is about 1462.6 px; principal point at the image centre.

### Landmarks (`landmarks[]`)

`pixel` values are in the 1170 × 658 output, origin top-left, continuous
coordinates (`pixel_convention`); double them for the @2x frame. Entries with
`in_frame: false` lie outside the image and are for solving only.

| `name` | `world_mm` | `pixel` | `in_frame` |
| --- | --- | --- | --- |
| `platform_corner_back_left` | (−1219.2, −225, −1219.2) | (−117.58, 383.31) | false |
| `platform_corner_back_right` | (1219.2, −225, −1219.2) | (691.68, 303.05) | true |
| `platform_corner_front_right` | (1219.2, −225, 1219.2) | (1539.57, 416.58) | false |
| `platform_corner_front_left` | (−1219.2, −225, 1219.2) | (548.06, 734.97) | false |
| `oak_corner_back_left` | (−609.6, −224.95, −1219.2) | (148.01, 356.95) | true |
| `oak_corner_back_right` | (609.6, −224.95, −1219.2) | (541.72, 317.90) | true |
| `oak_corner_front_right` | (609.6, −224.95, 1219.2) | (1404.50, 459.93) | false |
| `oak_corner_front_left` | (−609.6, −224.95, 1219.2) | (957.88, 603.33) | true |
| `sleeve_end_left` | (−1120, 0, 0) | (134.06, 339.69) | true |
| `sleeve_end_right` | (1120, 0, 0) | (990.62, 261.70) | true |
| `bar_centre` | (0, 0, 0) | (660.55, 291.76) | true |

Four platform-plane landmarks are in frame (the back-right platform corner
and three oak corners). The solve also uses edges, so these must stay
visible, unobstructed and straight in your plate: the platform's back edge,
both oak edges running toward the viewer, the platform's left and right
edges where they cross the frame, and the front edge of the oak.

Where the burn lands (computed with the pack's camera, for keeping that area
of oak clean): its corners at (∓475, −225, ∓475) project to about (346, 393),
(676, 351), (989, 406) and (635, 473).

### Light and tone (`lighting`, `tone_mapping`)

| Field | Value |
| --- | --- |
| `lighting.key` | directional, `intensity_scenekit` 1100, `color_rgb` (1, 0.985, 0.96), `approx_colour_temperature_K` 5900 |
| `lighting.key.direction_travel_world` | (0.3455, −0.809, −0.4755): the direction the light travels, so it comes from high front-left and shadows fall back and to the right |
| `lighting.key.shadow` | deferred, radius 14, 24 samples, 4096 map, `color_alpha` 0.85 |
| `lighting.reflections` | generated 1024 × 512 equirect light tent (overhead softbox, front key, rear strips, side fill), intensity 3.2 |
| `lighting.background` | `StudioGym` equirect, intensity 1 |
| `tone_mapping` | HDR, no exposure adaptation, `exposure_offset_ev` −0.2, `average_gray` 0.18, `white_point` 1, `contrast` 0.12, `saturation` 1, bloom 0.18 (threshold 1.1, radius 6), SSAO 0.7 (40 mm), vignetting 0.35 / 0.6 |

Match the look of the pack's light: brightness falling from front-left to
back-right across the platform, shadows of anything in the room falling back
and right. Don't add light sources the pack doesn't have.

### Surfaces (`surfaces`)

Every hero surface asks for its exact view size, so the plate is never
cropped: `session_current_set` and `plate_calculator` are about 370 × 208 pt
(1110 × 624 px), `workout_preview_and_library` about 330 × 186 pt, all 16:9
with a camera "identical to this calibration". `session_set_rows` (the `row`
shot) and `inspector_sheet` (FOV 41°, different look-at, animating to the
blow-up) use different cameras and are not phase 1.

### Known limit (`variability`)

The platform and look-at currently follow the load (`variability.floor_drop`):
the platform top sits at −(largest plate radius) and the camera's look-at y
at −0.27 × that. Every load that includes a 450 mm plate matches this pack
exactly. A load with only smaller plates, or an empty bar, raises the
platform toward the bar and tilts the camera slightly, which a static plate
cannot follow. The proposed fix is to pin the platform at −225 mm and the
look-at at the pack's value, and lower the bar onto the small plates instead.
That is a renderer change, **pending the owner's sign-off**, and not made in
the pack. Until it lands the app composites only loads that include a 450 mm
plate (COMPOSITOR section 1). `variability.reach` is always 1 in practice, so
bar length never moves the eye.

## 4. What Codex delivers (phase 1)

Name files `platform-hero-honey-oak[-suffix].<ext>`.

1. **`platform-hero-honey-oak.png`** (required). The empty plate.
   - Generated with `01-hero-empty-platform.png` (or the @2x) as the
     reference, and `02-hero-loaded-135lb.png` for scale: same framing, same
     perspective, same platform position.
   - Opaque RGB PNG, 8 bits per channel, sRGB with the ICC profile embedded.
   - **16:9**, at the largest native size your generator produces: at least
     1170 px wide, ideally 2340 × 1316. Not upscaled.
   - Depth of field like the pack's (focus near the bar, f/5.6), or sharp
     throughout; say which in the manifest. Do not add stronger blur than the
     pack's.
   - Vignetting: none, or the pack's (0.35 / 0.6). Say which.
   - No bar, plates, collars, clips, chalk bowls, bags, people, hands, text,
     logos, signage or watermarks. Nothing on the platform.
   - Nothing between the camera and the equipment volume: the box x −1300 …
     +1300, y −225 … +275, z −300 … +300 must be empty, and so must everything
     in front of it.
   - Clean oak (section 2).
2. **`platform-hero-honey-oak-loaded.png`** (optional, wanted). A look target
   with the pack's load (one 45 lb blue bumper a side: 450 mm, 60 mm thick,
   `#2358B4`, light ink `#F2F1EE`, `CADENCE` on the upper arc, `45 LB` on the
   lower arc, chrome hub; men's bar; spring collars). For judging materials
   against `02-hero-loaded-135lb.png`. Never shipped, composited or used for
   geometry; when it disagrees with `PlateTheme`
   (`CadenceCore/Sources/CadenceCore/PlateTheme.swift`), the table wins.
3. **`platform-hero-honey-oak-probe.png`** (optional). The empty plate edited
   so that only these change: a 100 mm chrome ball and a 100 mm matte 18 %
   grey ball resting on the left mat in front of the near stack, centres at
   (−900, −175, +350) and (−900, −175, +650), which project to about
   (369, 467) and (482, 506) in the 1170 × 658 frame. We use them to match
   exposure, white balance and key direction. Skip it if the edit changes
   other pixels.
4. **`platform-hero-honey-oak.json`**: provenance, not camera metadata:

   ```json
   {
     "file": "platform-hero-honey-oak.png",
     "sha256": "…",
     "size": [2340, 1316],
     "colourSpace": "sRGB IEC61966-2.1",
     "reference": { "file": "01b-hero-empty-platform@2x.png", "sha256": "…" },
     "generator": "built-in image generation",
     "date": "2026-11-…",
     "depthOfField": "pack-like | sharp",
     "vignette": "none | pack",
     "landmarksSeen": [
       { "name": "oak_corner_back_left", "pixel": [296.5, 714.0] }
     ],
     "deviations": "anything you know differs from the reference renders"
   }
   ```

   `landmarksSeen` is optional, uses the pack's landmark `name`s and only
   lists what you can actually measure on your output, in your output's
   pixels. We measure them ourselves either way. Do not estimate focal
   length, pose or light values from the raster; the pack has them and the
   solve checks them.
5. **`prompts.json`** entries for every file above, including correction
   passes, in the shape of your concept pack's `prompts.json`.

## 5. Format decisions

- **Colour space: sRGB.** It is the pack's `output.color_space`, image
  generators produce it, and the theme colour tables in `PlateTheme` are sRGB.
  Display P3 would add a conversion and gain nothing on a dark,
  low-saturation backdrop. Embed the profile so nothing guesses.
- **Master: PNG** from you, because recompression is ours to do once.
- **Shipping: JPEG q 90 or HEIC** in the asset catalog, opaque, no alpha,
  with the canonical burn baked in (COMPOSITOR section 6). Expect under 1 MB
  at 2340 × 1316.
- **No alpha anywhere in your delivery.** The only transparency in this
  pipeline is the app's equipment layer.

## 6. Registration tolerance and fallback

We solve the plate's own camera from its landmarks (COMPOSITOR section 2) and
render the equipment with that camera, so the plate does not have to hit the
pack's pixels exactly. It has to pass two checks, measured in the 2340 × 1316
frame (halve the pixel limits at 1170 wide):

| Check | Pass | Meaning of a fail |
| --- | --- | --- |
| **Consistency**: is the image a real perspective view of a rectangular platform? Reprojection error of the solved camera over all platform landmarks and edges | RMS ≤ 1.5 px, worst ≤ 3 px; edges straight within 2 px | The generator bent the geometry; no camera fits it |
| **Closeness**: is the solved camera near the pack's? | Horizontal FOV within 10 % of 43.6°; pitch and heading within 2°; roll under 0.5°; both sleeve ends of the pack's load project inside the frame | It registers, but it is a different shot from the approved hero |

On a fail we send the residual plot and the landmark overlay back for one
correction pass. If the second plate fails too, phase 1 ships nothing new and
the app keeps #374's deterministic platform and decal.

## 7. Acceptance checks you run before delivering

- [ ] Generated against the pack's empty render; `reference.sha256` filled in.
- [ ] Empty: no equipment, people, text, logos or watermarks; oak clean.
- [ ] Equipment volume and the space in front of it clear.
- [ ] Every platform edge in section 3 visible, unobstructed and straight to
      within 2 px over its visible length (generators bend long edges).
- [ ] The two oak edges and the two platform side edges converge to one
      vanishing point.
- [ ] Laid over `03-hero-empty-landmarks.png` at 50 % opacity, the platform
      back-right corner and the three in-frame oak corners sit within about 2 %
      of the frame width of their crosshairs.
- [ ] Light reads as the pack's: key high front-left, room shadows falling
      back and right, no coloured gels, no extra sources.
- [ ] Tone: lit oak around sRGB 150–205 in red, never clipped; lit mats
      25–55; back of the room under 40; nothing on the platform clipped to 255
      or crushed to 0. Compare with `01-hero-empty-platform.png`, which went
      through the app's tone mapping.
- [ ] Depth of field and vignette as declared in the manifest.
- [ ] 16:9, at least 1170 px wide, not upscaled, sRGB profile embedded,
      sha256 in the manifest matches the file.
- [ ] Probe (if delivered): pixel diff against the empty plate is zero outside
      the two balls and their contact shadows.
- [ ] `prompts.json` covers every delivered file, including correction passes.

## 8. Where the files go

- Your delivery, for review: `docs/design-pass/codex/plates/` in a PR of its
  own: manifest, `prompts.json` and a 660 px wide JPEG preview of each image.
  The full-size masters join that PR once the owner has agreed to publish
  them (the plate ships inside the app, so shipping it publishes it anyway).
- Shipping, done by the implementing agent: the burned plate as
  `Cadence/Assets.xcassets/StudioPlates/PlatformHero.imageset`, and the
  solved camera plus colour calibration as
  `StudioPlates/PlatformCameras.dataset`.

App-size impact of phase 1: under 1 MB, against an asset catalog that is
already 17 MB.

## 9. Later phases (not phase 1)

Same coordinates, same light rig, same order: calibration pack first, then
plate, then solve.

- **Session rows**: the `row` shot (`surfaces.session_set_rows.camera`:
  `position_mm` (−120, 25, 3100), look-at y −0.12 × floor drop, horizontal
  FOV 41.355°, f/8), 84 pt tall. From bar height the platform is a thin
  band, so the back edge and the converging oak edges carry the registration
  and the solve is weaker than the hero's.
- **Inspector**: `surfaces.inspector_sheet` (same eye, look-at y −0.1 × floor
  drop, FOV 41°, 370 × 300 pt). It animates to the blow-up, so it stays a
  deterministic scene (COMPOSITOR section 8); a plate would cover only its
  first frame.
- **Overhead**, like your `08`: no screen uses it yet.
- **Wood variants** (walnut, white oak, maple, as in your `04`, `05`, `07`) if
  the owner wants per-theme platforms; one plate and one solve each.

## 10. Rejected alternatives

### A photographic cutout kit

The first draft of this spec asked for a layered kit: an empty platform plus
every bar, collar and plate as an alpha cutout from one camera, translated
and scaled along the bar axis by the app. Counting what the app can show
killed it.

- Plates: the 10 named themes carry 136 theme × denomination looks (kg and lb
  sets each, 12 for the iron and steel themes up to 17 for IWF Competition);
  `custom` adds 38 (19 per visual style). Two hero views (near and far sleeve)
  plus one side view is **522 plate cutouts**. With 24 bar segments (men's and
  women's, chrome and black oxide, 3 segments, 2 shots) and the collars, about
  **550 files and 35 MB as HEIC**.
- All of them would have to share one camera and one light to the pixel.
  Generated images do not hold registration across one correction pass, let
  alone 550 frames.
- Sliding a pre-rendered plate along a perspective axis is only approximately
  right, and stacks would need occlusion, contact shadows and sleeve slicing
  rebuilt in 2D.
- Imported denominations (`ImportService` accepts any value) would have no
  cutout and fall back to something that looks different.
- #374 already produces that geometry correctly from the tables.

### This spec's own hero camera

An earlier revision of this PR proposed a new hero camera: 60 mm equivalent,
a 4:3 overscan frame cropped per surface, eye at (−2100, 1250, 2700) with the
bar 500 mm behind the platform centre. It was written before the calibration
pack existed. The pack locks #374's owner-approved `hero` instead, which
every surface already uses uncropped at 16:9. A different camera would have
needed new crops, moved the burn relative to the approved renders, and gone
through the renderer rule's side-by-side for no gain the plate needs.

## Owner decisions

1. **Pinned platform.** Approve the renderer change that pins the platform
   at −225 mm and lowers the bar onto smaller plates (section 3, known
   limit). Without it, loads with no 450 mm plate stay on the deterministic
   platform.
2. **Publishing.** The plate ships inside the app, so accepting it publishes
   it. Say whether the full-size masters may also live in this public
   repository.
3. **Wood.** Honey oak for every theme, or per-theme variants later.
4. **Generated burn.** The default is the canonical artwork burned in by the
   app. Accepting a generator's burn instead would break the "never redrawn"
   rule and is the owner's call alone.
