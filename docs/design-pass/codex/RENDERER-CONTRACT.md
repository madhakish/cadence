# Renderer contract: #374's barbell studio

This is what visual-design work (the `design/astra-native-ui` PR and anything after it) may rely on from the native barbell renderer, and what it must not touch. It is written for #374 (`feat/photoreal-barbell-revive`). Every statement below describes the code at the head named in "Dependency heads". [COMPOSITOR.md](COMPOSITOR.md) and [ASSET-SPEC.md](ASSET-SPEC.md) on main describe the planned photographic-plate compositor; this document says which parts of today's renderer stay put when that lands.

Each section is marked **Stable** or **May change**:

- **Stable:** presentation code can build on it. Changing it needs a PR that updates this file and gets the owner's side-by-side sign-off (AGENTS.md product priority).
- **May change:** expected to move when the composite lands or during look development. Don't hard-code around it.

## Dependency heads

| What | Head | Notes |
| --- | --- | --- |
| #374 renderer | `8a3301a173a19defa57d24f48aefe3deca39b609` | The renderer described here. This file is a docs-only commit on top of it. |
| #374's base | `583bad8c9` (main, 2026-11-01) | Main has moved since then (#372, #375 tokens and type, …). #374 needs a merge of main before landing. The only overlap in bar files is `LoadoutSummaryView` and the calculator header fonts from #375, which are presentation-only. |
| CadenceCore types used | `PlateSolution`, `Loadout`, `Plate`, `PlateVisualStyle`, `PlateThemeID`, `PlateTheme`, `BarbellInspector`, `PlateMath` | Solver and theme tables. No visual PR changes these. |
| Calibration pack | `proof/calibration/` (local, from 8a3301a) | Hero camera, landmarks and light rig. Mirrored in COMPOSITOR.md. |

## 1. Public API presentation code may call (Stable)

All of these are in `Cadence/Views/BarbellView.swift` unless noted. The loaded bar is always a `PlateSolution`, never a weight or a hand-built stack.

```swift
// The only way native code resolves a target into plates. Station units,
// mixed inventory, collars and loading policy all live here.
func authoritativePlateSolution(targetLb: Double, fallbackUnit: WeightUnit, bar: Bar, gym: Gym?,
                                stationDenomination: WeightUnit? = nil) -> PlateSolution

struct BarbellView: View {
    enum Presentation { case compactSide, fullBar }      // compactSide = row shot, fullBar = hero shot
    enum Emphasis { case current, standard, muted }       // opacity only, never geometry
    init(solution: PlateSolution, plateStyle: PlateVisualStyle = .steel, plateTheme: PlateThemeID = .custom,
         presentation: Presentation = .compactSide, emphasis: Emphasis = .standard, showsReadout: Bool = true)
}

struct BarbellStageView: View {      // hero render + "Tap to inspect" + deviation/policy notes
    init(solution: PlateSolution, unit: WeightUnit, plateStyle: PlateVisualStyle = .steel,
         plateTheme: PlateThemeID = .custom, caption: String = "Mirrored stack · counts are per side",
         onExpand: (() -> Void)? = nil)
}

struct BarbellInspectionView: View { // live 3D inspector sheet content
    init(solution: PlateSolution, plateStyle: PlateVisualStyle = .steel, plateTheme: PlateThemeID = .custom)
}

struct LoadoutSummaryView: View {    // achieved total, deviation, per-side, family cells (presentation; restyle freely)
    init(requestedLb: Double?, loadout: Loadout, plateStyle: PlateVisualStyle = .steel, plateTheme: PlateThemeID = .custom)
}

struct PlateFaceBadge: View { ... }  // flat colour key for a denomination (decorative, accessibilityHidden)
```

Lower-level entry points are in `Cadence/Views/BarbellStudio.swift`. Presentation code shouldn't need them, but they are stable for the DEBUG tooling:

```swift
enum StudioShot { case row, hero, blowup }
struct StudioImage: View { init(loadout: Loadout, style: PlateVisualStyle, theme: PlateThemeID, shot: StudioShot) }
final class StudioRenderer {
    static let shared: StudioRenderer
    struct Request: Hashable { loadout, style, theme, shot, width, height, scale }   // pt size x scale
    func cached(_: Request) -> UIImage?          // memory only, main-thread safe
    func render(_: Request) async -> UIImage?    // memory -> disk -> offscreen render on the studio queue
    func prewarm()                               // called once at launch from CadenceApp
}
```

**What presentation code may do:**
- Choose `presentation` and `emphasis`.
- Place and size the views. Hero surfaces are 16:9, so give them width and let `aspectRatio` set the height.
- Restyle captions, readouts, `LoadoutSummaryView` and `PlateFaceBadge` (colours and type through `Theme`).
- Wrap them in cards.

**What it must not do:**
- Pass anything but an `authoritativePlateSolution` result, or a `PlateSolution` built from what the lifter says is on the bar (calculator reverse mode).
- Change the readout's content or order.
- Remove or rename an accessibility element. The identifiers are `barbell-plate-left-N` / `barbell-plate-right-N`, `barbell-plate-readout`, `expand-loaded-bar`, `barbell-inspection-artwork` and `barbell-explode-toggle`. The children order is each side from the collar outward, then the bar-only or collars note.
- Overlay anything on the render that a plate number could hide.
- Crop or stretch a hero render (see section 2).

## 2. Surfaces: size, crop and camera

Sizes are measured on the iPhone 18 Pro simulator (402 pt wide, @3x). Every render is requested at the view's exact pt size × display scale and drawn `scaledToFill`, so nothing is cropped.

| Surface | View | Shot | Size | Camera | Status |
| --- | --- | --- | --- | --- | --- |
| Session, current set | `ActiveSessionView` → `BarbellStageView` → `BarbellView(.fullBar)` | `hero` | 16:9, `maxHeight 220`; about 370 × 208 pt (1110 × 624 px) | hero, wide branch (aspect ≥ 1.5) | Stable framing |
| Plate calculator, target and reverse | `PlateCalculatorView` → `BarbellStageView` | `hero` | about 370 × 208 pt | hero, wide branch | Stable framing |
| Workout preview | `WorkoutPreviewView` → `BarbellStageView` | `hero` | about 330 × 186 pt, inside a card | hero, wide branch | Stable framing |
| Library exercise pane | `LibraryView` → `BarbellStageView` | `hero` | row width, 16:9 | hero, wide branch | Stable framing |
| Session set rows and exercise pane | `BarbellView(.compactSide)` | `row` | row width × 84 pt | row: eye (−120, 25, 3100) mm, look-at (0, −0.12·drop, 0), hFOV 2·atan((extent+70)/3100) | May change (no plate yet) |
| Inspector sheet | `BarbellInspectionView` → `BarbellSceneView` (live `SCNView`) | `hero` ↔ `blowup`, animated | sheet width × 300 pt (aspect about 1.23) | hero, tall branch: hFOV 41°, look-at y −0.1·drop; blowup frames the near sleeve | May change |
| Today | none in #374 | none | none | none | Not a bar surface today. If Today adds one, use `BarbellStageView` (16:9 hero) so it reuses the hero plate. |

**Hero camera, wide branch** (the calibration pack and COMPOSITOR.md):
- Eye (−2000, 330, 2250) mm, looking at (−200, −0.27·drop, 0), with world up +y.
- Horizontal FOV 43.6°; zNear 40 mm, zFar 40 m.
- Depth of field focuses at the look-at distance, f/5.6 (stored as 5.6/1000 because the scene is in millimetres).

Here `drop` is the largest plate radius, 225 mm for any load with a 450 mm plate. The framing is locked to the horizontal FOV, so any 16:9 size frames identically. **Stable**, with one exception that **may change**: when the composite lands, the platform and look-at are expected to be pinned at y = −225 for every load, and the bar lowered onto small plates (COMPOSITOR.md section 1).

## 3. Fallbacks (Stable behaviour)

| Situation | What the user sees |
| --- | --- |
| Render not ready yet (cache miss) | `StudioImage` shows the `Theme.sceneStudio` backdrop at the final size, and the render fades in when it arrives. Order: memory (`NSCache`) → disk (`Caches/StudioRenders/v<version>-<build>/`) → offscreen render on the serial studio queue. A superseded request is skipped. A fresh render takes about 0.4–1.5 s (simulator), a cached one about 40–70 ms. |
| Render fails (no Metal device, GPU refused while backgrounded, flat image) | Nothing is cached. The backdrop stays and the request is retried when the scene phase returns to active. The readout, captions and accessibility children never depend on the image. |
| App in background | No GPU work. The `.task` re-runs on activation. |
| Unknown plate (imported denomination outside every table) | `PlateGeometry.reference` profile, the theme's fallback colour (`0x26272B`), and the exact denomination printed. No asset lookup can fail. |
| Reduce Motion | The inspector's hero ↔ blowup change is instant (no `SCNTransaction` animation), and captions update immediately. Static renders are unaffected. |
| Accessibility | Every bar view is `accessibilityHidden` artwork plus explicit labels and children (section 1). VoiceOver never reads the image. |
| Low memory | Studio caches are `NSCache` with byte-cost limits (96 MB each) and evict under pressure; a miss rebuilds deterministically. |

## 4. What may change when the composite lands

- `StudioImage` hero renders will become: the photographic plate (burn baked in) drawn at view size, then an RGBA equipment layer from the solved camera. The public views in section 1 do not change.
- Platform geometry, the room and `StudioGym` leave hero renders. Rows and the inspector keep #374's 3D platform until they get their own plates.
- Light rig and materials. The registration experiments (`proof/registration-hero-01/pass-2`, `pass-3`) switch the key to forward shadows, drop SSAO on the equipment, add a soft shaft band, add a turned hub and a recessed label field, and grade the equipment by material. None of that is in 8a3301a.
- The render-cache version will bump again, so old renders retire automatically.

## 5. Texture contract

These are the textures a designer can supply, and how the renderer reads them. Colour and printed denominations are **not** supplied: they come from `PlateTheme` and the solver, and stay authoritative. Supplied textures add surface detail only.

**General rules:**
- PNG, 8 bits per channel.
- **Colour space:** albedo is **sRGB**. Roughness, metalness, detail and normal maps are **data**: untagged or linear, with 0–255 mapped linearly to 0–1.
- **Normal maps:** tangent-space, **OpenGL / Y+ (green up)**, RGB = XYZ × 0.5 + 0.5.
- **Packing:** roughness and metalness are single-channel greyscale (R is read). There is no ORM packing.
- **Naming:** `<material>_<channel>.png`, where channel is one of `albedo`, `detail`, `roughness`, `metalness`, `normal`.
- **UV guides:** `docs/design-pass/codex/uv-guides/` has one PNG per mesh, showing the UV rectangle with millimetre ticks and the parts of the mesh each region covers.

| Material key | Mesh and UV layout | Pixel size and texel density | Channels you may supply | Notes |
| --- | --- | --- | --- | --- |
| `bumper_face` | Each flat face is a planar annulus. The texture covers the plate's **full diameter** as a square: centre (0.5, 0.5), u to the reader's right, v down, as seen from that face. Both faces sample the same image. On a 450 mm bumper at 8a3301a: the hub covers r < about 108 mm (depends on the theme's hub ratio), the flat printed face runs to 176 mm, the groove spans 176–184 mm, the outer ring runs to 217 mm, and the tyre fillet is beyond that. The pass-3 candidate recesses the label field to 173 mm. | 1024² for R ≥ 120 mm (2.28 px/mm on a 450 mm plate); 512² below. | `detail` (greyscale, 128 = neutral; see **Detail is coupled** below), `roughness`, `normal` | **Only the label field samples `detail`:** r ≈ 108–173 mm, about the 238–382 px annulus of a 1024² map. The groove and outer ring belong to `bumper_tyre`, so detail outside that annulus is never seen. Colour, denomination, unit and brand are baked at runtime on top. Today the detail comes from the Sep 16 `PlateBumper` photograph. |
| `steel_face` (steel, calibrated, iron, machined) | Same planar full-diameter layout. | Same | `detail`, `roughness`, `normal` | Iron uses cast (raised, unpainted) lettering. Today the detail comes from `PlateSteel`. |
| `bumper_tyre` (rim and recess wall) | Lathe. u goes once around the circumference (0–1); v runs along the profile from the inner groove on one face, over the tyre, to the groove on the other face (0–1 over the profile's total length). The recess chamfer is its own lathe with the same rule. | 256² tiled 3 × 1 | `albedo` (multiplied with the theme colour; keep it near white), `roughness`, `normal` | Today: faint scuffs. |
| `hub` | Lathe over the closed insert profile (bore, boss, flange, rings, lip). u goes once around; v runs 0–1 along the whole profile. | 512 × 128 is enough | `roughness`, `normal` | Albedo is neutral steel and not supplied. The pass-3 profile is a candidate (section 4). |
| `sleeve` | Lathe. u goes once around; v runs 0–1 along the sleeve profile. | 256² tiled 4 × 3 | `roughness` (today 0.11–0.15 smudges), `normal` | Chrome. Keep roughness ≥ 0.11 (below that SceneKit speckles curved chrome). |
| `shaft` and `knurl` | Lathe in physical units: a tile is 24 mm along the bar, and u wraps a whole number of 24 mm tiles around (4 on a 28 mm shaft). | Knurl normal 128² per 24 mm tile (5.3 px/mm). Chalk albedo 256² per 4 tiles. | `normal` (knurl), `albedo` (chalk, sRGB, near white), `roughness` | Polished shaft sections share the UV without the knurl normal. |
| `platform_oak` | `SCNPlane` 1219.2 × 2438.4 mm. u runs across the bar (x); v runs along the platform, with the image top toward the wall (−z). | 1024 × 2048 (0.84 px/mm) | `albedo` (no logo), `normal` | The Vitruvian burn is composited at runtime from the canonical brand artwork (950 mm, centred, top toward −z). Never supply a burned oak. |
| `platform_mat` | Each mat is an `SCNPlane` 608.6 × 2438.4 mm with the same orientation. | Albedo 512 × 2048; normal tiled 2 × 8 | `albedo`, `normal` | |
| `burn_mask` | Not a supplied texture. The mask is computed from the canonical artwork's luminance with #374's curve (smoothstep 0.24–0.62, 0.88 strength) toward char (0.028, 0.014, 0.007) in linear light. | none | none | The burn source is the canonical brand artwork: the Astra Heritage master since the owner's 2026-11-01 decision (#177, #386). Still composited at runtime, never baked into a supplied oak. |

**Detail is coupled, not a plain multiplier** (measured in the 2026-11-01 A/B, `proof/texture-ab-bumper-face-v2/`). With `d` the detail value (grey/128, clamped 0.85–1.25) and `ink` the printed-ink mask, the renderer applies:
- albedo × `d^(0.4·(1 − 0.6·ink))`, so a ±4.4 % map moves albedo by only about ±1.8 %, and less under ink;
- roughness + `0.35·(1 − d)`;
- relief `0.12 mm·(d − 1)`, which feeds the procedural normal.

So a detail map also changes roughness and the normal. Author it as a combined micro-relief signal, not as a colour layer, and change one variable per A/B. Supplied `roughness` and `normal` maps stack on top of these terms.

### Texture preview rig

The rig is a local DEBUG tool on this Mac, not committed. It renders the 135 lb fixture with a folder of textures, and does it without a UI suite: one build plus one app launch under the shared Xcode lock.

```sh
bash /Users/thudak/git/cadence-photoreal/proof/texture-rig/rig.sh <texture-folder> <output-folder>
```

- **Inputs:** a folder of files named as above. Any material that is missing falls back to today's texture.
- **Outputs:**
  - `hero-135.png`: the 1110 × 624 stage crop. It is the equipment composited over the rectified, burned photographic plate with the solved camera, i.e. the pass-3 candidate.
  - `closeup-plate.png`: 1024², the near 45 lb bumper face and hub on #374's own platform.
  - `rig-manifest.json`: which files were picked up.
- **Source:** #374 at 8a3301a plus `proof/texture-rig/rig.patch`. The script applies the patch in a scratch worktree, so #374's branch is never modified.
