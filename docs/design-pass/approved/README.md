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

## Barbell studio references

The four `studio-*.jpg` files are the bar renderer's references since #316:
SceneKit renders from #318's render lab (source commit `6fbb0e3`, iPhone
simulator), built from the path-traced look-dev the owner approved on
2026-10-11 ("Start building"). Unlike the mockups above they are app
captures, downscaled to 660 px JPEG. A change to the bar's technique or look
is judged side by side against these and the current renderer, and needs the
owner's sign-off in the PR (see `AGENTS.md`).

| File | Shot | What it fixes |
| --- | --- | --- |
| `studio-hero.jpg` | `hero`, colour bumpers | Three-quarter bar on the oak platform, printed faces, gym light |
| `studio-hero-calibrated.jpg` | `hero`, IPF calibrated | Stacked thin calibrated plates, knurl and chalk, chrome sleeves |
| `studio-blowup.jpg` | `blowup`, mixed lb bumpers | Inspector with the near sleeve's plates slid out |
| `studio-row.jpg` | `row`, default theme | Straight-ahead set-row framing |

Decisions taken while implementing them are recorded in `../DECISIONS.md`.
