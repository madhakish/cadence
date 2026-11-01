# Approved reference mockups

These six images are the review mockups the owner approved as the direction
for the visual pass (parent #177). They were supplied in the design review
on 2026-09-07 and re-supplied on 2026-09-17; they are the reference every
capture in `../after/` is judged against.

They are references, not captures: none was rendered by the app, and none is
a fixture. They are stored at half the supplied resolution (660 px wide) to
keep the repository small; the composition, copy, and hierarchy are what
matter, not the pixels.

| File | Surface | What it fixes |
| --- | --- | --- |
| `plate-loading-front.png` | Plate calculator, front view | "Know your load." header, achieved-with-bar summary, per-side stack |
| `plate-loading-inspection.png` | Plate calculator, 38° inspection | Three-cell summary, plate reference table |
| `exercise-browser.png` | Exercise library | "Find your lift." search, movement and equipment filters, collapsed categories |
| `current-session.png` | Active session | Set track, "WORKING SET 2 OF 3", dominant load numeral |
| `settings.png` | Settings | Six task-oriented disclosures with current values |
| `lock-screen.png` | Live Activity | "Complete set · rest" controls and the current set on the Lock Screen |

Decisions taken while implementing them are recorded in `../DECISIONS.md`.

## Photographic platform direction (2026-11-01)

The owner supplied a further set of generated stills on 2026-11-01: a loaded
bar on an oak platform with the Vitruvian gorilla burned in, rubber side
mats, a dark gym behind, and plate-loading and session screens built around
it. They are kept outside this public repository until he says otherwise.
Codex's concept pack from the same day, recommending honey oak with blue
bumpers, is published separately under `docs/design-pass/astra-2026-11-01/`
by its own PR (`docs/astra-visual-handoff`).

Neither set is approved yet, and neither replaces the references above. The
plan for reaching that look without giving up the deterministic renderer is
in [`../codex/ASSET-SPEC.md`](../codex/ASSET-SPEC.md) and
[`../codex/COMPOSITOR.md`](../codex/COMPOSITOR.md); any renderer change it
leads to still needs a side-by-side against these references and the
owner's sign-off.
