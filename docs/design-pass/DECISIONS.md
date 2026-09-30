# Material design decisions

- Default surface — Foundry (the `carbon` key) loads before hydration so native and web open on charcoal without a palette flash.
- Elevation — base, card, and raised are the only surface levels; dividers and spacing group content before containers.
- Accent — red is reserved for current, selected, focus, and primary action; warnings and completion keep separate semantic colours.
- Contrast — default Carbon text and semantic tokens clear 4.5:1 on all three web elevations; green, yellow, and white plate labels use dark ink.
- Geometry — 4–5 pt corners keep controls touch-safe without turning the interface into stacked pills.
- Type — heavy rounded numerals are limited to live load and totals; headings use the platform sans hierarchy and supporting copy never drops below readable caption size.
- Touch — 56 pt is the native between-set target; web primary controls retain at least 44 CSS pixels.
- Motion — state transitions use 160 ms, are interruptible, and collapse under Reduce Motion / `prefers-reduced-motion`.
- Plate input — every renderer receives the chosen `PlateSolution`; it has no target or rack input from which it could infer a second stack.
- Plate entry — the decimal pad has an explicit Done action and scroll dismissal, so calculator results never remain hidden behind an input state.
- Full bar — hero diagrams draw shaft, sleeves, collars, and mirrored stacks. Each exact stack derives its own minimum legible width from metadata thickness. A normal two-plate-per-side load fits a 390-point phone; constrained stacks scale only their plate geometry, keep denomination text at 9 points, and expose a focused horizontally scrollable view at natural width.
- Plate geometry — bumper and calibrated-steel presentations use metadata-driven relative diameter and thickness rather than interchangeable rectangles.
- Plate labels — exact metadata labels such as `1.25 kg` are drawn on every disc and repeated as face-on badges in stack lists.
- Totals — achieved weight always leads in pounds then kilograms and always includes the selected bar and collars.
- Mixed units — bar unit and plate denomination are named independently; conversion is confined to the achieved-total explanation.
- Session hierarchy — current exercise, load, current set, plate stack, and next action own the first block; earlier completed exercises remain above it as one disclosure so the authored order is never falsified, and later work follows in order.
- Set states — completed dims, current carries the red boundary, upcoming stays neutral, and warmups reduce emphasis without changing geometry.
- Exercise pane — live prescription and load stay visible; history/programming and anatomy/setup are separate disclosures.
- Gorilla — the exact raster is retained, edge-feathered at the container, and paired with restrained primary/secondary vector overlays.
- Settings — controls are grouped by equipment, loading, training behaviour, appearance/accessibility, programming/library, and data safety; no new setting keys were invented.
- Ad-hoc work — Wood Splitting banks on the all-time timeline through #167's typed record but never advances cycles, sets PRs, or contributes lifting tonnage.
- Ad-hoc facts — duration and optional session RPE are universal; maul weight and wood counts stay user-entered, typed, and never inferred from one another.

## Visual pass, 2026-09-06 (PR #201)

- Themes — Foundry is the default and keeps the `carbon` key; Heritage Gold keeps `memento`; Titanium is the one new value, a light mineral surface with deep teal controls. Slate and System stay so no saved choice is discarded. Keys are identity, labels are presentation.
- Accent foregrounds — every accent-filled control reads a per-theme foreground token (`--on-accent` / `Theme.onAccent`) chosen to clear WCAG AA on that fill; nothing assumes white or hard-codes near-black. The all-theme contrast check also corrected the System light palette's warn and good tokens.
- Focus — one `--focus` token, defined once and following the active accent, is the only focus ring on web.
- Plate and anatomy colours — physical plate colours and muscle role colours never follow the theme; they come from equipment and anatomy metadata.
- Today — the program day states each lift's load as a number. Plate stacks belong to the preview and the logger; no equipment imagery decorates Today, and nothing replaced it to fill the space.
- Library — search first, then Movement and Equipment filters, then categories as collapsed groups that state their counts. A filter reveals only the groups with matches, opened; clearing it returns every group, collapsed, except the ones the user opened.
- Settings — six task-oriented disclosures in one shared order (gym, units, rest & training, appearance, programming, data). Each collapsed face states where the group stands. This supersedes the earlier "no details in Settings" rule; inside a group there are still no nested doors, and no setting keys changed.
- Focused exercise — leads with a set track (resolved quiet, current in the accent, upcoming neutral), then the working set's position, reps, and load, pounds first then kilograms, above the set rows. The load is the set's own value; the diagram under the set row remains the loading truth.
- Plate reference — the calculators carry a reference-only guide (colour, denomination, other-unit conversion) per family. It is never inventory: the 55 lb disc is listed for recognition and is not a solver candidate.
- Material — web cards use a flat ground, a hairline, a one-pixel edge light (`--edge`), and a shadow token that lightens on light themes. The native current-set card renders the matching top-edge treatment (`Theme.edge`) inside its existing accent border.
- Load numeral — the web current-set load and achieved primary total share a tabular display treatment (`.load-numeral`); each surface chooses its size. Web radii are 4 and 2, matching native's 4-point card corner; steppers and the native shelved tag are squared.
- Theme safety — web toasts, shadows, and semantic pill tints use theme tokens. Filled verdict controls retain their contrast-tested foreground/fill pair.
- Out of this pass — the plate renderer's physical-profile geometry (gated on approving persisted equipment dimensions), the HH:MM:SS duration picker (#199), Lock Screen set progression (#200), and the rest-completion bell (#197).

## Build review, 2026-09-07

- Approved anatomy — carry PR #205 verbatim; the owner approved these contours. No new gorilla artwork, plate logos, or altered masks.
- Duration entry — one native editor and one web editor serve global defaults, exercise overrides and remaining rest. Staged Save/Cancel prevents partial entries from changing training guidance. Existing integer seconds and the 0–3600 portable range stay unchanged.
- Rest layout — iOS separates countdown text from four compact rest actions to avoid shrinking the countdown; each action has a 44-point target. Its progress transition uses the existing motion token and becomes instant under Reduce Motion. Device layout still needs inspection.
- Override wording — zero explicitly means “Use default from Settings” on an exercise; the effective rest is shown independently. Global zero means Off.
- Loading accessibility — a target input's spoken unit changes in place, retaining its value and node; plate badges defer to one adjacent denomination announcement.
- No-gym loading — the per-set solution falls back to its entered unit, with an explicit station denomination taking precedence, matching native. Configured gym inventory and solver policy stay unchanged.
- Focus — an unresolved warmup keeps its exercise current. Focus cannot silently skip a set; completed/current/upcoming still follow authored order.
- History dates — “yesterday” is a local calendar-date relationship, including midnight and DST. Stored timestamps, tonnage and progression calculations are unchanged.
- Plate guide — add the IWF small denominations using shared plate colour metadata. Explain that IPF fixes colours only for 15/20/25 kg; the guide never adds inventory.
- Compatibility — retain the public SessionPrescription(mainWork:blocks:) initializer; only engine-produced blocks assert a resolved methodology.
- Scope correction — #199's duration implementation is now included; its native/UI validation is still pending. Approved physical plate geometry, Lock Screen set completion and the headphone cue remain unfinished; the earlier “out of this pass” note is historical scope, not completion evidence.
- Completion cue — one bundled tone (the web client's 880 Hz half-second) says "done" for rest and holds alike: through an ambient session on screen, so it follows headphones and mixes with music, and on the background notification, so the phone says the same thing face-down. Foreground plays it once and cancels the alert; a background alert is never replayed on return.

- Workout commands — one service changes a set's status and decides what follows (focus, the next rest's lift, whether to arm it), used by the logger's control, the hold timer, and the Lock Screen. A Lock Screen face names its set structurally and the app re-derives, at the moment the tap runs, whether that set is still the one to act on; a stale face is refused, never redirected. Ending the Live Activity remains distinct from banking the workout.

- Plate colours — one token → colour table (fill, edge, ink) lives in the shared core and every renderer on both clients reads it; no plate hex is spelled outside metadata. Each disc has one spoken name built in core.
- Renderer state — presentation (a set row's compact bar vs the current set's stage) is chosen by the surface; emphasis (current / standard / muted) is a renderer prop that changes only opacity, never geometry, order, or labels.

- Loadout summary — one composition everywhere a bar is explained: "Achieved with bar" in the accent, the load numeral pounds-first with the difference from the request beside it, the bar and the per-side stack on one line, then one cell per plate family (bumpers, steel, change) counting both sleeves, plus a collars cell. The calculator opens on "Know your load." and no longer repeats the stack as a list.

## Session hierarchy, 2026-09-17

- Dominant block — the focused lift owns the top of the session: movement eyebrow, set track, current set (position, reps, load), then its set rows. Nothing above it changes when a set is completed; the iPhone capture suite asserts the set track and current-set hero keep their frames (`test13SetCompletionKeepsDominantBlockStill`).
- Session progress — "Exercise N of M · S of T work sets · date" is supporting information. It rides as the focused section's footer on native and as the focused card's footer on web, never as a card of its own.
- One supporting section — the gym picker ("Training at"), "Add exercise", and session notes share one "Session" section beneath the exercises on both clients. For the proof fixture (three lifts, none passed) the session list holds 5 sections where the design-pass baseline held 8.
- Unchanged — set completion, focus advance, rest, gym-switch bar restamping, notes persistence, and the cycle model. History and program filtering are untouched.

## Exercise pane tiers, 2026-09-17

- Tier 1, always visible — classification eyebrow, current prescription (load × reps, set position, effort cue, rest), the loaded bar, and the achieved-with-bar summary. Nothing in it is recomputed; it is the logger's own entry and solver path.
- Tier 2, one expand — "Previous performance & programming": last done, the top-set sparkline, program membership, cycle and rotation context, deload phase. Its collapsed face states last-done and the assignment count.
- Tier 3, one expand — "Muscles & relationship": the complementary/main relationship and its originating focus exactly as the engine labelled it, then the anatomy figure with its primary/supporting legend. The relationship left the prescription block; it is context, not the work in hand.
- Default state — the library opens on the anatomy; between sets both tiers start collapsed so the work in hand is above the fold. Expanding either tier never moves tier 1; the iPhone suite asserts the prescription's frame after both open.
- Set history (#66) — below the sparkline, "Recent sessions" lists the last five completed sessions containing the exercise, newest first. Each row is the date (and program name when tagged) over its working sets as stored, comma-separated, each set in the History row's performed form — "225 lb × 5 · 2 left, 225 lb × 4" — with the RIR flag under the same label History uses; timed and conditioning sets show duration/distance, never a synthetic load. Warmups and skipped sets are excluded, units follow the display preference, and an exercise with no completed session says "No sessions yet." Five is the browsable window; the full log stays in History.

## Gorilla integration, 2026-09-17

- Artwork — untouched. Every gorilla source and mask stays byte-identical (the registration test pins the digests); the edge is feathered by a container mask on both clients, never in the raster.
- Selection — the legend is the region control. The masks are raster images whose hit box is the whole figure, so making them tappable would select whichever mask is painted last wherever the finger lands; tapping the figure is deliberately not offered rather than offered wrong. Hover/focus/tap on a legend entry lights the region; native announces the selected value, web announces it in a live region.
- Order — legends and VoiceOver walk the body head to toe (`anatomicalOrder` in CadenceCore, `ANATOMICAL_ORDER` on web, fixture-checked), not the map's importance order.
- Names — one spoken name on both clients: "Quads, primary muscle" / "Traps, supporting muscle".
- Treatment — primary movers carry the warm tint at higher opacity, supporting work the steel wash at lower opacity, both multiplied over the ink so the figure stays legible. Neither colour is a plate colour. The legend's muted labels keep at least 4.5:1 on the card in every theme (tested from the stylesheet tokens).

## Exercise pickers, 2026-09-17

- One surface — every exercise picker is the library browser with a selection closure: native `ExerciseBrowser` (`onSelect`) and web `exerciseBrowser` (`onSelect`). The logger's "Add exercise" sheet and the program editor's lift/accessory pickers are thin wrappers that add the equipment policy, the programmable-only restriction where it applies, and the sheet's title; the library is the same view with rows that navigate to detail. Search, the Movement and Equipment filters, the collapsed category groups with counts, the filter-reveals-matches rule, the shelved badge, and the ⓘ detail-over-the-picker path are shared, not duplicated.
- Recent — a compact "Recent" group sits above the categories when non-empty: the distinct exercise names from the most recent completed sessions, newest session first and in performed order within a session, capped at six (`ExerciseSearch.recentNames` / `recentExerciseNames`). It is an entry point, not a category: the same search, filters, policy, and availability apply to it, and it never changes what the category groups hold. Nothing is persisted for it.
- Empty state — when nothing matches, both clients say exactly: "No exercises match. Clear the filters or search by movement, equipment, or alias — or add a custom exercise." with the clear-filters and new-exercise actions beside the copy, and the toolbar's copies of those actions step aside so each appears once.

## Review fixes, 2026-09-19

- Lock Screen identity — a set command carries a versioned fingerprint of the ordered exercise-entry and set identities, plus the displayed names and warmup/work pattern. SwiftData's existing persisted identifiers are encoded canonically, so equal-shaped replacements and reorders invalidate the face while unchanged stores survive relaunch. This requires no schema change. Pre-hotfix fingerprints and unavailable identities are refused as "moved on" and the face refreshes from saved state.
- Face after a verdict — every in-app verdict republishes the current set to the Live Activity, a refused command re-projects the saved state (or ends a banked session's activity), and the expanded island keeps Rest/Pause/End beside Complete/Skip.
- Timed work on the face — timed and conditioning sets read as a duration ("0:30"), never as reps.
- One cue — the display timer is suspended while the app is in the background and a rest that expired meanwhile ends quietly on return; the notification fires one second after the deadline so a foreground cancellation always wins.
- Sound preference — the completion tone has a device-local switch (UserDefaults, like the Health read opt-in); haptics and the announcement are independent of it. The cue releases its audio session when the half second is over.
- Scaled display sizes — the current-set numeral, the achieved total, and the calculator hero use `@ScaledMetric` so they keep their proportion and still follow Dynamic Type, with a minimum scale factor as the floor.
- Pushed lists — the library browser, the exercise pane, and the signals timeline reserve the plate-button band like the tab roots.

## Calculator Dynamic Type, 2026-09-19

- The requested target keeps its existing 40-point rounded display at the default text size and scales with the large-title curve. At accessibility sizes, the native unit selector flows below the input within the same section; the input keeps its focus and binding through the layout change.
- `test14CalculatorTargetAtAccessibilityTextSize` checks standard versus maximum accessibility text size, visible controls, growth of the editable number, and unit switching without losing the entered number. A Dynamic Type audit finding on `plate-target` is now a failure; the other #238 advisories remain tracked separately.
- The standard and maximum-accessibility captures from source `bb4b07d` were inspected and retained with [artifact provenance](proof/calculator-dynamic-type/README.md). The target and unit control remain legible, and the control sits below the enlarged number. The larger #187 matrix remains open.

## Plate material, 2026-09-19

- Colourisation — a plate face is rebuilt from the approved texture's luminance (a 5×4 matrix shared by both clients), so its photographed shading survives and its hue comes from the palette fill. The earlier per-channel gains clamped the dark textures into one flat colour, which is what made a 35 lb steel plate read as a mustard disc. The median texel of each texture lands at 85% of the fill; highlights whiten slightly rather than saturate. Black iron stays untouched. Colour tokens are unchanged: 35 lb is still yellow by the colour-bumper convention.
- Shaft — chrome, knurl, and sleeve shading are baked into the shared rendered bar sprites on both clients. Geometry, the solver, and the textures' pixels are unchanged.

## Loaded-bar composition, 2026-09-19

- Rendered, not drawn — the bar diagram is composed from rendered sprites: one greyscale plate per shape (diameter × thickness) at each scene angle, plus shaft, far and near sleeves, and collars, produced offline by a deterministic signed-distance ray marcher with a studio rig (`web/tools/render-plate-sprites.py`). Vector strokes and the two tinted photographs are retired from the diagram; the approved photographs stay in the repository untouched.
- One camera — sprites are rendered from the −x end of the bar at the scene's yaw (18° assembled, 38° exploded) with the elevation that reproduces `BarbellScene`'s axis slope, so the shared geometry places them without a second model; far parts paint first, near parts last, and plate bores are open in the sprites — the shaft shows through wherever the viewing angle clears the plate's own thickness (thin plates and the exploded view), and a full-size plate hides it behind its rim, as a real plate would.
- Colour at runtime — plate faces are colourised by the shared luminance matrix; hubs and bar parts stay untinted. Colour tokens, geometry, and the solver are unchanged; badges remain vector text.
- Both clients — the same PNGs ship in the web assets and the asset catalog (byte-identical, tested), with placement metadata generated into `plate-sprites.js` and `PlateSprites.swift` from one manifest.

## Sprite geometry, 2026-09-19 (later)

- Diameter is not a radius — the sprite tool's plate solid took the shape key's diameter as a radius, halving every plate's rendered thickness and bore. The plate family is re-rendered at true proportions (bars unchanged); rims now stack contiguously and the luminance lifts are re-measured on the new faces (bumper 0.459, steel 0.453). Found by the third code review's bore measurement.

## 3D plate inspector, 2026-09-19 (later)

- A solid, not a picture — the inspection sheet shows the loaded bar as a real-time solid: SceneKit on iOS, WebGL2 on web. Drag orbits, pinch (and wheel) zooms, a tap explodes or assembles with an animated cut, double tap or **Reset view** returns to the front view, and Studio / Dark / Paper backdrops change the lighting mood. Compact rows and hero bars keep the sprites; the sprites are also the fallback wherever Metal or WebGL2 is missing (audits, jsdom, old browsers).
- One model, two renderers — `BarbellInspector` (CadenceCore) and `barbell-inspector.js` share the physical millimetre layout (shaft, shoulders, sleeves, plates, lock collar), the explode fraction that spreads the stack outward, the orbit camera's yaw wrap and pitch/zoom limits, and the lathe profiles per family (bumper rim recess, steel dish, change flat). `web/tests/fixtures/barbell-3d.json` pins all three on both clients. Rendering is platform code and is not pixel-matched; the numbers are.
- Camera — the brief: a straight-ahead view that explodes to a ~35° blow-up close enough to read plates and numbers. Assembled is yaw 8° / pitch 10° framing the whole bar; the tap animates plates, angle, and framing together to yaw 35° / pitch 12° on the near stack (`BarbellInspector.frame`). A 22° lens keeps the near-orthographic look, and the fit distance accounts for the span's reach toward the eye when yawed so the near end always clears the frame. Numerals are printed on both faces at half the annulus height.
- Lighting — physically based materials (rubber, painted iron, chrome), a procedural studio environment for reflections (the same rig the sprites were lit with), one shadow-casting key light, and a floor that only receives the shadow. Backdrop colours are theme tokens (`Theme.sceneStudio/-Dark/-Paper`, `--scene-studio/-dark/-paper`); plate colours are the shared palette. The sprite tint matrix is not used by the solid — it colourises greyscale pixels, and the solid is lit in colour.
- Accessibility stays in the DOM and the accessibility tree — native reuses the per-plate accessibility children (each side collar-outward, then the collar note); web keeps the sprite SVG over the canvas as an invisible, focusable plate layer, and a focus note names the focused plate for sighted keyboard users. Backdrop and Reset view are the keyboard/VoiceOver path for the gestures. Reduce Motion makes the explode cut instant on both clients.

## Plate themes, 2026-09-26

- Real equipment, chosen per gym — the bar shows one of ten plate themes (IWF Competition, IWF Training, IPF Calibrated, IPF Calibrated · gloss, lb Colour Bumpers, lb Black Iron, lb Grey Hammertone, lb Machined Steel, Black Bumpers · colour band, Cadence House) plus Custom, which keeps the earlier value-coloured behaviour. Each theme carries real per-denomination diameter and thickness, a construction profile (bolted bumper hub, calibrated lip and plugs, cast iron lip and boss, machined face), a finish, and its colour rule. Dimensions trace to [PLATE-REFERENCE.md](PLATE-REFERENCE.md): the IWF TCRR 2025 and IPF 2026 rulebooks and verified Rogue product pages; Eleiko/York figures and every colour value remain marked unverified there until sampled.
- Chosen from renders, not paintings — the ten were rendered with the app's own WebGL inspector under headless Chromium ([themes/](themes/)) and the owner approved all ten as selectable. The earlier "approved" plate-loading mockups were generated during the design pass and are not an equipment reference.
- Theme on the gym — the choice is equipment, so it lives on the gym record on both clients (schema V14, IndexedDB v10, backup schema 15) and migrates from the inventory: all-lb → lb Black Iron, all-kg → IWF Competition, mixed → Custom. Inventory toggles, load semantics, recorded mass and the solver are unchanged.
- Unit follows the exercise — an exercise set to kg on an lb gym shows the theme's kg sibling set and vice versa; toggles apply within the set.
- Printed on the face — the denomination is printed on the plate face beside the hub, value over unit, condensed heavy type scaled with the plate and foreshortened with the face. The exact per-side list under the bar stays the readable record; #262's floating labels are not adopted.
- IPF colours — the rulebook fixes only 25 red, 20 blue, 15 yellow; the green/white/black/chrome scheme below 15 kg is manufacturer convention and is presented as such.
