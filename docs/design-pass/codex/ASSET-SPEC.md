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
| Camera, lights, platform dimensions, landmarks | **Cadence side**: a SceneKit calibration pack, fixed before any generation | No |
| Vitruvian gorilla burn on the oak | The app: the canonical `VitruvianFront` artwork, warped onto the oak with the solved camera, never redrawn | No |
| Bar, plates, collars, their shadows | The app: #374's SceneKit scene, transparent background, shadow catcher | Yes |

[COMPOSITOR.md](COMPOSITOR.md) is how the app puts these together.
Per-plate photographic cutouts were considered and rejected; the reasons and
the asset count are at the end.

## Phase 1: one matched hero shot

Phase 1 proves the hybrid on a single shot before anything else gets a plate:
the three-quarter **HERO** used by the current-set stage and the plate
calculator, look target **honey oak with blue bumpers** (your
`03-platform-oak-blue.png`). The session-row SIDE shot and an OVERHEAD shot
are later phases and are sketched in section 9 only so the coordinate system
does not have to change when they come.

The order of work is fixed:

1. **Cadence locks the camera first.** The calibration pack (section 3)
   comes from #374's SceneKit scene: camera, field of view, pose, lights,
   platform dimensions, landmarks and output crops, plus three renders.
   Nothing is generated before it exists.
2. **Codex generates the plate against those renders** (section 4). You use
   them as the composition and perspective reference; you do not invent a
   focal length, light temperature or any other metadata after the fact.
3. **Cadence verifies and solves** the plate's actual camera from the
   landmarks it can see (COMPOSITOR section 2), against explicit tolerances.
4. **Fallback:** a plate that will not register within tolerance after a
   correction pass is not used. The app keeps #374's deterministic platform
   and decal, which is what ships today. Nothing degrades if phase 1 fails.

## 1. World coordinates

All positions are millimetres in **platform coordinates**:

- Origin at the centre of the platform's top surface.
- **x** along the bar, positive to the image right (the far sleeve).
- **y** up.
- **z** toward the front of the platform (the camera side).

The platform is the one #374 models (`StudioPlatform`), a standard 8 × 8 ft
Olympic platform:

| Part | Extent (mm) |
| --- | --- |
| Whole platform | x −1219.2 … +1219.2, z −1219.2 … +1219.2 |
| Oak centre strip, 4 ft wide, running front to back | x −609.6 … +609.6, full depth |
| Black rubber stall mats, left and right | x ±609.6 … ±1219.2, full depth |
| Top surface | y = 0 (oak and mats flush) |
| Base | two 19.05 mm plywood layers under everything; plies visible at the edges |
| Bar axis (where the app puts it) | z = −500, y = radius of the largest plate (225 for full-size plates) |
| Gorilla burn (added by the app, not by you) | 950 mm square, centred at x = 0, z = +150 |

The bar runs across the oak and both stacks land on the mats. It sits 500 mm
behind the platform's centre line so the burn shows between the bar and the
front edge, as in the owner's references and your `03`. #374 currently
centres the bar over the platform; the calibration pack moves it to z = −500
so the pack, the plate and the app agree.

## 2. The look, in words

The owner's references (generated stills he supplied on 2026-11-01, kept out
of this public repository) and your concept pack
(`docs/design-pass/astra-2026-11-01/`, published by your own PR from
`docs/astra-visual-handoff`) agree on this:

- **Subject.** A competition lifting platform in a dark, serious gym. Warm
  honey oak centre with real grain running front to back, satin finish, a
  little wear where lifters stand. Black stall mats either side, fine pebble
  texture, slightly lighter scuffs where plates land. Plywood plies visible
  on the platform edge. An optional thin black steel frame around it (your
  `08`), straight and in plane if present.
- **Room.** Dark rubber gym floor around the platform. Behind it, out of
  focus: power racks, a plate tree with coloured bumpers, a block or concrete
  wall. Everything behind the platform at least two stops darker than the oak.
  No windows, people, signage, readable text or brand marks.
- **Mood.** Catalogue product photography in a real gym, not a render and not
  a moody poster. Controlled light, deep but not crushed shadows, frame edges
  falling off into near-black (about `#111316`) so the app's charcoal UI can
  meet it.
- **Light.** Whatever the calibration pack specifies (section 3); in words,
  one large soft key from high front-left, a soft overhead fill, two tall
  strip lights behind the platform for rim highlights, warm bounce off the
  oak.
- **Materials the app will put on top** (for your loaded look target only):
  tight bright chrome reflections, smooth sleeves against a zoned shaft
  knurl, matte to satin rubber with moulded edges, both stacks on rubber.
- **Clean oak.** No burn, logo or engraving on the oak. The app burns the
  canonical gorilla in itself so the artwork is never redrawn, and the photo's
  grain runs through the burn.

## 3. The calibration pack (Cadence delivers this to you)

Produced from #374's SceneKit scene by the Cadence side before generation,
and handed over with its location noted in the PR or the design thread. It
is the single source of truth for every number; where it disagrees with this
document, the pack wins.

| File | Contents |
| --- | --- |
| `calibration.json` | Image size and aspect; camera pose (eye, aim, up), field of view and focal length; principal point; platform dimensions (section 1); landmark list with world and pixel coordinates; lights (direction, colour temperature, intensity, softness); output crops per presentation |
| `empty.png` | The SceneKit platform and room from the locked camera, no equipment. Your composition and perspective reference. |
| `loaded.png` | The same frame with one 45 lb blue bumper a side (`lbColourBumpers`), spring collars, men's bar. Where the equipment will sit, and how big. |
| `landmarks.png` | The same frame with every landmark marked and labelled, for checking your plate by eye |

### Proposed hero camera for the pack

The pack's author picks the final numbers; this is the starting proposal and
why. It is more elevated and longer than #374's approved 45 mm `hero` (eye
330 mm above the bar axis), to match the owner's new references.

| Parameter | Value |
| --- | --- |
| Frame | 2400 × 1800 (4:3). The extra height is overscan: the app crops 1.53:1 for stages and 1.2:1 for the inspector. |
| Focal length | 60 mm full-frame equivalent (horizontal FOV 33.4°, f ≈ 4000 px at 2400 wide) |
| Eye | x −2100, y +1250, z +2700 |
| Aim point | x −120, y +170, z −350 |
| Pitch / heading / roll | 16.5° down / 33° left of straight on / 0 |
| Focus | the bar centre, about 3.96 m from the eye |

A perfect pinhole camera with those values, principal point at the image
centre, puts the landmarks here:

| Landmark | Platform coordinates | Pixel (x, y) in 2400 × 1800 |
| --- | --- | --- |
| Near / far sleeve end, men's bar | (∓1100, 225, −500) | (133, 975) / (2031, 655) |
| Near / far sleeve end, women's bar | (∓1005, 225, −500) | (241, 957) / (1969, 666) |
| Bar centre | (0, 225, −500) | (1219, 792) |
| Near / far inner shoulder face | (∓705, 225, −500) | (563, 902) / (1764, 700) |
| 450 mm plate, first near slot, top / bottom | x −735 | y 662 / 1144 (482 px tall) |
| 450 mm plate, first far slot, top / bottom | x +735 | y 492 / 895 (403 px tall) |
| **P2** platform back-right corner | (+1219.2, 0, −1219.2) | (1696, 707) |
| **O1** oak back-left corner | (−609.6, 0, −1219.2) | (375, 929) |
| **O2** oak back-right corner | (+609.6, 0, −1219.2) | (1313, 772) |
| **P1** platform back-left (off frame) | (−1219.2, 0, −1219.2) | (−207, 1027) |
| **P4** platform front-left (off frame) | (−1219.2, 0, +1219.2) | (1065, 2312) |
| **P3** platform front-right (off frame) | (+1219.2, 0, +1219.2) | (3613, 1303) |
| **O4** oak front-left (off frame) | (−609.6, 0, +1219.2) | (1964, 1956) |
| **O3** oak front-right (off frame) | (+609.6, 0, +1219.2) | (3181, 1474) |
| Burn square, back-left / back-right (keep clean) | (−475, 0, −325) / (+475, 0, −325) | (887, 1146) / (1696, 974) |
| Burn square, front-right / front-left (keep clean) | (+475, 0, +625) / (−475, 0, +625) | (2423, 1260) just off frame / (1525, 1528) |

Only three platform corners are in frame, so the solve also uses edges: the
back edge (through P1, O1, O2, P2), both oak edges running toward the viewer,
the platform's left edge (enters at about (0, 1236)), the right edge from P2
to the frame side, and the front edge, which grazes the bottom-right corner.
Those edges must stay visible, unobstructed and straight in your plate.

Proposed light rig, matching the key #374 already uses (directional,
rotated −54° in pitch and −36° in yaw, colour 1.0 / 0.985 / 0.96):

| Light | Direction toward the light (platform coordinates) | Character |
| --- | --- | --- |
| Key | (−0.35, +0.81, +0.48): 54° up, from the front-left | Large soft box; shadows fall back and to the right; about 5400 K |
| Overhead fill | straight down over the bar | Large and soft, about 1.5 stops under the key |
| Rim strips | two tall strips at x ≈ ±1800, z ≈ −2500 | Neutral; long highlights on chrome and plate tyres |
| Room | everything else | Dark; dim, defocused warm practicals allowed |

## 4. What Codex delivers (phase 1)

Name files `platform-hero-honey-oak[-suffix].<ext>`.

1. **`platform-hero-honey-oak.png`** (required). The empty plate.
   - Generated with the pack's `empty.png` (and `loaded.png`, for scale) as
     the reference; same framing, same perspective, same platform position.
   - Opaque RGB PNG, 8 bits per channel, sRGB with the ICC profile embedded.
   - The pack's aspect, at the largest native size your generator produces,
     **at least 1600 px wide**. Not upscaled. 2400 px wide is ideal.
   - No bar, plates, collars, clips, chalk bowls, bags, people, hands, text,
     logos, signage or watermarks. Nothing on the platform.
   - Nothing between the camera and the equipment volume: the box x −1300 …
     +1300, y 0 … 500, z −800 … −200 is empty, and so is everything in front
     of it.
   - Clean oak (section 2).
2. **`platform-hero-honey-oak-loaded.png`** (optional, wanted). A look
   target: the same frame with the pack's load (one 45 lb blue bumper a
   side: 450 mm, 60 mm thick, `#2358B4`, light ink `#F2F1EE`, `CADENCE` on the
   upper arc, `45 LB` on the lower arc, chrome hub; men's bar; spring
   collars). For judging materials against the app's render of the same load.
   Never shipped, composited or used for geometry; when it disagrees with
   `PlateTheme` (`CadenceCore/Sources/CadenceCore/PlateTheme.swift`), the
   table wins.
3. **`platform-hero-honey-oak-probe.png`** (optional). The empty plate edited
   so that only these change: a 100 mm chrome ball and a 100 mm matte 18 %
   grey ball on the left mat at (−900, 0, −150) and (−900, 0, +150). We use
   them to match exposure, white balance and key direction. Skip it if the
   edit changes other pixels.
4. **`platform-hero-honey-oak.json`**: provenance, not camera metadata:

   ```json
   {
     "file": "platform-hero-honey-oak.png",
     "sha256": "…",
     "size": [2400, 1800],
     "colourSpace": "sRGB IEC61966-2.1",
     "reference": { "calibration": "calibration.json", "sha256": "…" },
     "generator": "built-in image generation",
     "date": "2026-11-…",
     "landmarksSeen": [
       { "id": "O1", "px": [376.0, 930.5] },
       { "id": "back-edge", "px": [[12.0, 990.0], [1690.0, 709.0]] }
     ],
     "deviations": "anything you know differs from the reference renders"
   }
   ```

   `landmarksSeen` is optional and only for what you can actually measure on
   your output (pixel centres, origin top-left). We measure them ourselves
   either way. Do not estimate focal length, pose or light values from the
   raster; the pack has them and the solve checks them.
5. **`prompts.json`** entries for every file above, including correction
   passes, in the shape of your concept pack's `prompts.json`.

## 5. Format decisions

- **Colour space: sRGB.** Image generators produce sRGB, and so do SceneKit's
  output and the theme colour tables in `PlateTheme`. Display P3 would add a
  conversion and gain nothing on a dark, low-saturation backdrop. Embed the
  profile so nothing guesses.
- **Master: PNG** from you, because recompression is ours to do once.
- **Shipping: JPEG q 90 or HEIC** in the asset catalog, opaque, no alpha,
  with the canonical burn baked in (COMPOSITOR section 6). Expect 0.8–1.5 MB
  for the hero at 2400 px wide.
- **No alpha anywhere in your delivery.** The only transparency in this
  pipeline is the app's equipment layer.

## 6. Registration tolerance and fallback

We solve the plate's own camera from its landmarks (COMPOSITOR section 2) and
use that camera for the equipment, so the plate does not have to hit the
pack's pixels exactly. It has to pass two checks, measured at 2400 px wide:

| Check | Pass | Meaning of a fail |
| --- | --- | --- |
| **Consistency**: is the image a real perspective view of a rectangular platform? Reprojection error of the solved camera over all landmarks and edges | RMS ≤ 1.5 px, worst ≤ 3 px; edges straight within 2 px | The generator bent the geometry; no camera fits it |
| **Closeness**: is the solved camera near the locked one? | Focal within 10 %; pitch and heading within 2°; roll under 0.5°; the projected loaded bar (pack load) inside the stage crop's must-show box | It registers, but it is a different shot and the crops or composition no longer hold |

On a fail we send the residual plot and the landmark overlay back for one
correction pass. If the second plate fails too, phase 1 ships nothing new and
the app keeps #374's deterministic platform and decal.

## 7. Acceptance checks you run before delivering

- [ ] Generated against the pack's `empty.png`; `reference.sha256` filled in.
- [ ] Empty: no equipment, people, text, logos or watermarks; oak clean.
- [ ] Equipment volume and the space in front of it clear.
- [ ] Every platform edge in section 3 visible, unobstructed and straight to
      within 2 px over its visible length (generators bend long edges).
- [ ] The two oak edges and the two platform side edges converge to one
      vanishing point.
- [ ] Laid over `landmarks.png` at 50 % opacity, the platform's back edge and
      oak corners sit within about 2 % of the frame width of the markers.
- [ ] Light reads as the pack's: key high front-left, room shadows falling
      back and right, no coloured gels.
- [ ] Tone: lit oak around sRGB 150–205 in red, never clipped; lit mats
      25–55; back of the room under 40; nothing on the platform clipped to 255
      or crushed to 0.
- [ ] Platform sharp from back edge to front edge at 100 %; room behind soft.
- [ ] At least 1600 px wide, the pack's aspect, not upscaled, sRGB profile
      embedded, sha256 in the manifest matches the file.
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
  solved camera plus calibration as `StudioPlates/PlatformCameras.dataset`.

App-size impact of phase 1: about 1–1.5 MB, against an asset catalog that is
already 17 MB.

## 9. Later phases (not phase 1)

Same coordinate system, same light rig, same process: pack first, then plate,
then solve.

- **SIDE**, for session rows (84 pt tall, about 4.7:1). #374's `row` framing
  pinned to the platform: 2400 × 1350, 47.6 mm equivalent (41.4° horizontal),
  eye (−120, 250, 2600), aim (0, 198, −500). From bar height the platform is a
  thin band; the back edge (y ≈ 830) and the two converging oak edges carry
  the registration, which makes this solve weaker than the hero's.
- **OVERHEAD**, like your `08`: 2400 × 1350, 50 mm, eye (0, 6500, 0) looking
  straight down, the platform's back edge at the top of the frame; platform
  corners at x 575 / 1825, y 50 / 1300. No screen uses it yet.
- **Wood variants** (walnut, white oak, maple, as in your `04`, `05`, `07`) if
  the owner wants per-theme platforms; one plate and one solve each.

## 10. Rejected alternative: a photographic cutout kit

The first draft of this spec asked for a layered kit: an empty platform plus
every bar, collar and plate as an alpha cutout from one camera, translated
and scaled along the bar axis by the app. Counting what the app can show
killed it.

- Plates: the 10 named themes carry 136 theme × denomination looks (kg and lb
  sets each, 12 for the iron and steel themes up to 17 for IWF Competition);
  `custom` adds 38 (19 per visual style). Two hero views (near and far sleeve)
  plus one side view is **522 plate cutouts**. With 24 bar segments (men's and
  women's, chrome and black oxide, 3 segments, 2 shots) and the collars, about
  **550 files and 35 MB as HEIC**, before any overhead shot.
- All of them would have to share one camera and one light to the pixel.
  Generated images do not hold registration across one correction pass, let
  alone 550 frames.
- Sliding a pre-rendered plate along a perspective axis is only approximately
  right, and stacks would need occlusion, contact shadows and sleeve slicing
  rebuilt in 2D.
- Imported denominations (`ImportService` accepts any value) would have no
  cutout and fall back to something that looks different.
- #374 already produces that geometry correctly from the tables, so the kit
  would swap deterministic work for nondeterministic pixels.

The platform is the only part that is both load-independent and hard to fake
in real time, so it is the only part we ask you to photograph.

## Owner decisions

1. **Publishing.** The plate ships inside the app, so accepting it publishes
   it. Say whether the full-size masters may also live in this public
   repository.
2. **Hero camera.** The proposed 60 mm camera, 1.25 m up, is higher and longer
   than #374's approved 45 mm `hero`. Changing the approved framing needs the
   side-by-side and sign-off that #374's renderer rule asks for.
3. **Wood.** Honey oak for every theme, or per-theme variants later.
4. **Generated burn.** The default is the canonical artwork burned in by the
   app. Accepting a generator's burn instead would break the "never redrawn"
   rule and is the owner's call alone.
