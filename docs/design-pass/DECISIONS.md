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
