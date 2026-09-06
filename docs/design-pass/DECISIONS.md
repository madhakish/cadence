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
- Out of this pass — the plate renderer's physical-profile geometry (gated on approving persisted equipment dimensions), the HH:MM:SS duration picker (#199), Lock Screen set progression (#200), and the rest-completion bell (#197).
