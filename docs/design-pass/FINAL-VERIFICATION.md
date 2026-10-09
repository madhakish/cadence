# Epic #177 verification — 1 October 2026

PR [#271](https://github.com/madhakish/cadence/pull/271) completes the remaining
Favorites implementation and collects the combined candidate's evidence.
**The epic stays open until its remaining acceptance checks are met.**
A simulator capture or a green build does not establish headphone routing,
a workout performed while locked, or a manual VoiceOver session.

## Follow-up status

The original source table below is a dated record. Required CI for `3a89d9c`
[run36936687219](https://github.com/madhakish/cadence/actions/runs/36936687219)
passed all gates: 504 core and 81 migration tests, full web suite and all16
Chromium/WebKit cases, production device build and four native interactions
with zero skips. Its exact DP-1 baseline and real OS Dark native palette job
passed. All ten Dark Settings/calculator originals were inspected and retained
with [provenance](proof/review-3a89-dark/provenance.json). At430pt, maximum-text
search, both complete filters and the whole favorite row passed and were
[inspected](proof/review-3a89-430/provenance.json). At375pt, the older Settings
navigation helper failed before that maximum-text proof. Both equipment-category
captures failed when short drags opened rows; the full native capture is still
running. The web pre-art comparison also failed an assertion for a heading the
actual old source never had. These failures and the next measured-navigation,
historical-copy and audit text-size corrections are recorded in the dated
[pixel review](PIXEL-REVIEW.md). Their own new-head verification is required.

Earlier inspected c320 originals confirm correctly reached mobile picker,
unselected anatomy and native audio control, with complete control bounds
above bottom chrome. Earlier70ce originals show two genuinely exploded theme
inspectors, while its hero test failed and other theme captures did not assert
the actual state; the current full run adds bounded state assertions. Historical
186-image evidence remains valid for its own source, with those defects retained.
Epic #177 stays open for current proof and the physical/assistive acceptance below.

## Source and gates

- Original DP-1 application: `11895fb95cde9e4b938831098d00dd0350b45bc2`.
- PR base / actual V14 store producer: `20058600ec2947c1a4f13a855d3b922ae80e1709`.
- Original retained capture source: `78405bf4a12c32e5be65373b7006cb11c355d4e6`.
- [Original source CI](https://github.com/madhakish/cadence/actions/runs/36811839564)
  and [capture run](https://github.com/madhakish/cadence/actions/runs/36811839554).
- Source CI passed: 504 core tests, 81 migration/backup tests, full web suite
  and 14 Chromium/WebKit acceptance cases, unsigned device build, and all four
  native interactions with zero skips on the first attempt.
- Both capture jobs passed. [Pixel review](PIXEL-REVIEW.md) records all 186
  inspected original PNGs and both raw native audit attachments, including
  concrete visual defects and incorrectly reached capture states.
- Captures identify the application source above. The final documentation head
  requires its own green CI; the exact run and immutable evidence links appear
  in PR #271 before it is marked ready for review.

The build-capable core, web, migration, device and screenshot jobs run on
`macos-latest`. The required check name `CadenceCore tests (Linux)` is retained
for branch protection; its execution uses Xcode's Swift toolchain. Metadata
and aggregate jobs can remain on Ubuntu without needing Xcode.

## Native / web parity

| Contract | Native | Web | Evidence boundary |
| --- | --- | --- | --- |
| One canonical catalog, template-independent top-up | `Seeder` / canonical fixture | `SEED_EXERCISES` / same fixture | Full catalog, taxonomy, seed and invariant suites |
| Shared browser in Library and calling pickers | `ExerciseBrowser` | `exerciseBrowser` | Library, native picker and desktop modal captures; original mobile picker setup failed; the later c320 capture reaches the real picker |
| Favorites, Recent, composed search and filters | Persistent exercise Boolean; 44-point independent star | Persistent Boolean; transactional independent star; restored keyboard focus | Native UI, SwiftData tests; both browser engines and IndexedDB migration |
| Favorite cannot reopen a shelved lift or bypass policy | Visible list filtered before favorites | Same | Policy/availability regression suites |
| Failed favorite retains previous state | Shared save-error alert; explicit prior-value restoration | Transaction failure/toast; focus retained | Native read-only store and real IndexedDB/UI regressions |
| Exact mixed-unit loading, bar and collars | Shared authoritative `PlateSolution` | Mirrored core fixture and solution | Pure-lb, mixed, change-plate, unreachable and entered-stack reverse scenarios |
| Real plate profiles and local imagery | Same physical profile/PNG family; SceneKit with sprite fallback | Same profile/PNG family; WebGL2 with sprite fallback | Profile/geometry fixture, byte pairing, offline test and inspected captures |
| Contextual exercise prescription and disclosure | Live set context; history/programming/anatomy tiers | Same | Pane/collapse/expand/anatomy captures |
| Original signature artwork | Original two gorilla JPEGs | Byte-identical JPEGs | SHA-256 below; mask registration tests |
| Muscle names and selection | Wider wrapping legend; one column at accessibility sizes; same anatomical order and masks | Wrapping legend and same order/masks | Native/desktop selected and unselected states; original nominal mobile unselected state was selected; later c320 capture clears it; spoken traversal remains unverified |
| Main set and authored exercise boundaries | Dominant current work; one authoritative mutation path | Same where implemented | Native four-test interaction gate; real browser session progression |
| Exact staged duration entry | Hours/minutes/seconds; Save/Cancel; zero/fallback semantics | Same | Duration/backup regressions and editor capture |
| Settings structure | Six task groups and real capabilities | Same | Root/rest/editor captures; original native audio switch was under chrome; later c320 capture shows its complete control above the band; complete runtime traversal remains required |
| Primary canvas | Each native primary List uses its saved theme's background | Existing `--bg` theme tokens | All five native Settings/calculator palettes inspected under real OS Dark; System follows it and Titanium stays light; browser palette proof is separate |
| Lock Screen and Dynamic Island | Widget/App Intent projection of saved workout | No web OS Live Activity feature | Compiled production widget and command tests; physical acceptance still required |
| Completion cue | Device-local sound preference, foreground tone/background notification ownership | Device-local preference and browser audio | Timer ownership regression; actual headphone/audio route still required |
| Accessibility and motion | Automated labels/audit, 44-point targets, maximum-text captures, Reduce Motion | Keyboard/focus, token contrast, real engines, CSS zoom/edge-width stress and reduced motion | Does not claim manual VoiceOver or actual browser/pinch zoom |

## Protected-code audit

The review base is the actual PR base `20058600`, not an earlier design-pass
commit containing months of intervening feature work. This command produces
**no diff** for this PR:

```sh
git diff --stat 20058600ec2947c1a4f13a855d3b922ae80e1709..HEAD -- \
  CadenceCore/Sources/CadenceCore/PlateMath.swift \
  CadenceCore/Sources/CadenceCore/Plates.swift \
  CadenceCore/Sources/CadenceCore/PlateTheme.swift \
  CadenceCore/Sources/CadenceCore/ProgramEngine.swift \
  CadenceCore/Sources/CadenceCore/ProgramProgression.swift \
  CadenceCore/Sources/CadenceCore/SetLifecycle.swift \
  Cadence/Services/ProgramSession.swift Cadence/Services/SessionCompletion.swift \
  Cadence/Services/WorkoutCommandService.swift web/app/js/core.js \
  web/app/js/views/session.js
```

The literal empty persistence-directory condition from #187 is **not met**:
requested Favorites in #63 needs a durable preference and portable backup.
Those changes are explicit and bounded, rather than hidden in a visual audit:

| Protected area | Change | Safety evidence |
| --- | --- | --- |
| Exercise | Add `isFavorite = false`; stable identity remains the owner | Rename, seed preservation, gate/policy, disk reopen |
| SwiftData schema | Freeze V14; live V15; append lightweight V14→V15 to supported histories | Frozen on-disk V14 and actual predecessor binary; existing shipped-store histories |
| Backup | Required Boolean in version 16; older definitions absent field default false | Native/web legacy import, strict current validation, favorite-only preview/round trip |
| IndexedDB | Version 11 writes defaults and preserves edits during top-up | Actual database upgrade and transaction tests |
| Save failure | Restore the bound favorite explicitly after rollback | The read-only regression first failed on the held object, then passed with the production action |

[`INV-FAVORITE-FAILED-SAVE`](../reference/invariants.md#inv-favorite-failed-save)
records that safety rule and is cited by the native and web regressions.

No frozen V1–V13 snapshot changes. No store deletion/reset. No per-set values,
exercise gates, history, progression, units, solver policy or workout-command
behavior is changed by this PR. Compare to `11895fb` to audit the whole epic's
history separately: that broader range includes previously merged feature and
repair work and does not have an empty protected diff.

This PR is `feat!` because the storage/backup contract advances. Forward upgrade
preserves old data; older builds do not understand a V15 store or backup 16.
Do not use a downgrade as a reverse migration. Pre-upgrade backups remain
importable by the new build; omitted exercise definitions do not erase existing
favorites.

## Artwork and material

[ASSET-INVENTORY.md](ASSET-INVENTORY.md) lists every equipment PNG, source,
license record, byte size, dimensions and SHA-256, its native twin and consumers.
The existing plate family has158 PNGs /9,594,989 bytes and remains unchanged.
PR #271 adds three original transparent equipment cutouts,953,444 bytes per
client, with byte-identical native/web twins and [generation/rights provenance](EQUIPMENT-CONTEXT.md).
They illustrate Main/Accessory/Conditioning categories, unlogged exercise
detail and empty Program, with fixed decode geometry and local offline delivery.
Main workout, contextual exercise detail and calculator each use the athlete's
actual equipment/loadout. Library, Today and History keep their information
hierarchy instead of adding unrelated thumbnails.

The inline diagram shows both loaded sleeves. The separate 3D inspector
deliberately frames the near sleeve: yaw/pitch 8°/6° assembled, 50°/10° exploded,
with an 8° lens. Both clients use those same current endpoints. Printed face
stamps can be occluded in the assembled stack; the exploded captions and the
per-side denomination/count list supply the readable loading record.

Original front JPEG SHA-256:
`ec95ffe80e86263a441f31e01e7e5fcf6b9312d3b2d7a3e6fc3a9ae36bfd1006`.
Original back JPEG SHA-256:
`940bbc7bf72794778d3304d226cf5ca3d265e68985bc0ffa72cb198c743a51f5`.
Both match the original DP-1 commit and the native/web twins exactly.

Essential text and exact plate counts remain outside the equipment artwork on
controlled backgrounds. Token contrast and native audit are automated evidence,
not a claim that every photographed/printed plate face passed a text-contrast
measurement. Native audit advisories and manual assistive-technology limits must
remain visible in the evidence index.

## #187 and #198 acceptance boundaries

| Requirement | Review evidence | Status boundary |
| --- | --- | --- |
| Every original DP-1 capture compared | All 42 new baseline images and all 144 candidate images inspected; native source/manifest and fixed-viewport production browser pairs in `BEFORE-AFTER.md` | Invalid intended states and nonidentical rest navigation are explicit in `PIXEL-REVIEW.md` |
| Every material decision explained concisely | Final one-line decision/reason table in `DECISIONS.md`; dated earlier choices remain historical | No unsupported baseline state is reconstructed |
| Protected semantic diff empty | Solver/program/session paths unchanged from the actual PR base | Durable Favorites intentionally advances persistence and backup; the literal #187 empty-directory gate needs this explicit feature exception |
| Main, Library, detail, calculator, Settings authored | Existing material system plus actual native Lists, shared theme canvas, visible search and readable prescriptions | Current pixel inspection is recorded with its viewport and remaining accessibility limits |
| Three purposeful imagery surfaces and exact gorilla | Workout, contextual detail and calculator; asset inventory and original JPEG hashes | Three new original equipment contexts illustrate category browsing, unlogged detail and empty Program; original gorilla remains byte-identical; current runtime artwork proof remains pending |
| Essential content AA | Shared contrast fixtures and native audit, controlled backgrounds for load/counts | Unassociated audit contrast/hit-region findings and fixed-type advisories are retained; complete AA is not established |
| Optimized, local assets and native/web art direction | 158 unchanged plate PNGs and three new inventoried cutouts with native twins; all16 real-engine checks include decode geometry and offline reopen | Retained captures show the actual platform renderers, not promised pixel identity |
| Edge widths, maximum text, zoom and motion | 402pt native capture and all five palettes under real OS Dark; passing430pt maximum-text whole-row/filter proof; 390/1280 browser matrix; 320/430 CSS zoom1/2 with reduced motion | 375pt maximum-text and both-width category proof failed and need corrected-harness runs; manual200% browser/pinch zoom, spoken VoiceOver and physical acceptance remain |

The old #177 box for #180 is stale: the renderer issue is closed and the
implementation is on the PR base. This record does not edit historical issue
checkboxes or close #187/#198 while their remaining acceptance gates are open.

## Epic acceptance, item by item

| #177 acceptance | Implementation/evidence | Remaining gate |
| --- | --- | --- |
| Authored strength-training product | Material decisions and comparable production captures inspected | Visual defects in `PIXEL-REVIEW.md`; physical acceptance below |
| One restrained material/type/imagery/geometry/motion system | Existing shared tokens, real profiles, local asset family, short two-state inspector cut | Full AA, native widths and physical accessibility remain unproved |
| Three non-gorilla imagery surfaces; exact original gorilla | Workout, contextual exercise pane, calculator inspected; original hashes match | Three original equipment-context cutouts are now integrated; current native category/empty and matched web comparison proof remains pending |
| Search-first, category-navigable discovery | Normal native/browser states and real engine tests; Favorites, Recent and composed filters | 430pt whole-row/filter proof and later correctly reached c320 picker were inspected;375pt proof and spoken VoiceOver remain |
| Direct HH/MM/SS rest editing | Both editor captures show fields, exact preview, Save/Cancel/Off and carry guidance | Actual assistive-technology check; mobile rest-row button overlap |
| Workout can progress while phone stays locked | Shared command path, stale/duplicate identity checks, production widget build | Physical locked workout across set/rest/exercise boundaries |
| Clear, once-only cue through permitted headphone route | Independent preference, audio ownership and quiet-return regressions | Headphones while music plays, background/foreground, mute and route changes |
| Exact plates and mixed units | Solved/reverse variants and inspector captions/counts inspected | Overlapping desktop inline labels; some achieved totals below first viewport; printed-face AA not established |
| Every named surface has inspected proof | 186 original app PNGs inspected, including attempted audio state | Earlier c320 audio/picker/cleared-anatomy captures correct those specific historical setup defects; current equipment/desktop/full inspector proof and physical Lock Screen/Dynamic Island/audio remain |
| Both clients green, compatible data | 504 core / 81 migration tests, both browser engines, device build and four native interactions passed on source head | Exact final documentation-head run is required and linked from PR #271 |

## Remaining acceptance work

Finish the current native375/402/430pt whole-category/empty-state and inspector
proof, and the matched actual-before/current web equipment and full desktop
matrix. Inspect and retain those pixels before marking their visual findings
resolved. The specific older picker, cleared-anatomy and audio-viewport
corrections are already inspected; avoid treating invalid historical states as
current passing evidence. Complete AA, plate-face readability, spoken VoiceOver
and manual zoom remain explicit. A green capture wrapper alone establishes none
of those acceptance checks.

Perform one real iPhone workout while locked: complete/skip, rest start/pause/end,
and transition to the next authored exercise without unlocking. Check stale or
duplicate actions and timed work. Record Lock Screen and Dynamic Island proof.
With headphones and music, verify the cue once in foreground/background,
preference off, silent/DND behavior and route changes without leaving music
interrupted. Run the Library/picker/duration flow with spoken VoiceOver and
actual large text/zoom. These are current product acceptance checks, not
permission to release or merge.

## Inline renderer correction, 2026-10-01

The owner's inline-bar report was reproduced in synthetic preview/calculator pixels and physical geometry assertions. Canvas and SVG now use the existing inspector bar profile, remove assembled air gaps, align front-face bores on the sleeve axis and preserve shaft/sleeve thickness while stretching sprite spans. Native full-bar layout fits the scene ratio within its170pt cap. The full local web suite and photographed-bore regressions pass. Swift/native low-load screenshots at375/402/430pt remain pending on the new source. Original synthetic before-correction pixels and the full3a89 result are retained in [bar provenance](proof/review-3a89-bar/provenance.json); private owner screenshots were not committed. No solver, inventory, progression, store or recorded-load meaning changes.
