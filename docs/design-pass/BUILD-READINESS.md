# Visual build candidate — 7 September 2026

**Status: review candidate; the full visual brief is not finished.**

This candidate combines the Foundry/Heritage Gold/Titanium and screen work
from #201, the session-effort and accessible plate-label fixes from #204,
and the owner-approved anatomy from #205. The source artwork and registered
masks are unchanged from #205. It also adds exact rest-duration entry and
fixes the confirmed #192–195 review defects.

## Brief cross-check

| Requirement | Implemented evidence | Remaining acceptance gate |
| --- | --- | --- |
| Foundry default; other schemes retained | Native `Theme`, web tokens, v13 backup round trips, all-theme web contrast tests | Actual iPhone/desktop captures, Dynamic Type, native contrast inspection |
| Exact gorilla and coherent muscle highlights | #205 masks, source hashes, native/web byte parity, legend interaction tests; owner approved | Actual pane tint/feather, VoiceOver and selected-muscle screenshots |
| Plate metadata, exact solver stack and denominations | Shared `BarbellView`/`barbellSVG`, reverse ordering, exact 1.25, complete-bar and total contracts; #204 removes duplicate announcements | Approved realistic plate look and 38° inspection are **not implemented by this candidate**; profiles still use relative weight-based factors |
| Full-size bumpers versus small change plates | Existing style factors distinguish broad families | #55/#180: explicit physical profiles must distinguish a full-size 5 kg bumper from a 5 kg change plate; unit or weight alone cannot decide it |
| Achieved total: lb then kg, bar/collars included | Existing shared solution/summary contracts, mixed inventory tests; #194 no-gym fallback now follows entered unit | Render dense stacks and expanded view on phone/desktop; confirm denomination legibility |
| Colour/denomination guide | kg/lb table; full IWF small-denomination colour metadata; IPF exception explained | Named IWF/IPF/black/custom equipment profiles remain #55; the reference table never changes inventory |
| Current work dominates | #201 working-set hero and track; #195 retains any unresolved warmup in the active exercise | Native/web session screenshots at exercise boundaries and large text |
| Today has no random plate collection | #201 removes repeated program-lift stacks; loading stays in exercise/calculator context | Updated Today screenshot |
| Useful exercise pane | Existing prescription/history/anatomy disclosures; resolved effort style frozen by #204 | Complete #66/#184's selection-flow and provenance review, including edited/deleted programs |
| Clear Settings and selectors | Six task groups, collapsed summaries, library movement/equipment search and category disclosures | Embedded picker/Recent/Favorites/catalog work in #63; native scrolling and global button overlap #196 |
| Direct rest duration | HH/MM/SS fields on native/web; exact seconds, staged Save/Cancel, one-hour range, explicit fallback, editable active countdown | Device keyboard/VoiceOver, small/large-text captures and cross-process timer changes |
| Lock Screen workout progression | Existing clock/rest controls only | #200 still requires shared authoritative set-completion intents, stale/duplicate action handling and locked-device testing |
| Headphone completion cue | Existing native default notification and web oscillator only | #197's controllable cue, once-only ownership and real audio-route matrix remain unfinished |
| Useful restrained imagery | Approved mascot integration, existing plate rendering | #198's additional intentional material/equipment imagery; do not fill unrelated screens with plates |
| Accessibility and motion | Web focus/token tests, existing keyboard dialogs, single plate announcements; rest progress respects native Reduce Motion | Full keyboard/VoiceOver/200% zoom/large Dynamic Type and interaction-state capture matrix |
| Preserve cycles/history/data | No shipped schema/model, solver, programming prescription or progression changes in these review fixes | Native CI, backup compatibility tests; no release before gates below |

## Confirmed defects fixed in this candidate

- #192: target input's accessible unit updates in place; DOM node, entered value and focus survive.
- #193: native and web history provenance compares local calendar dates. Matching Chicago fixtures cover spring/fall DST and midnight. Timestamps and aggregate history calculations are unchanged.
- #194: with no gym, a stored set uses its entered denomination; an explicit station denomination wins. Configured mixed racks are unchanged.
- #195: shared focus selection counts planned warmups as unresolved. It changes focus only, never set status. A real logger regression completes the final working set and asserts that its warmup remains visible and planned.
- #204 review: preserve the existing public `SessionPrescription(mainWork:blocks:)` initializer. Engine-created sessions still freeze the resolved methodology.

## Verification and screenshot provenance

The full local `npm test` passes: 54 invariants / 103 platform assertions;
1,727 core; 66 plate renderer; 25 + 6 + 7 + 13 migration; 129 program;
1,241 runtime smoke; 4 anatomy-registration groups; duration and build-polish
regressions; 233 site; 48 accessibility contracts. `git diff --check` passes.

The new duration regression covers 0, 1, 97, 3599 and 3600 seconds through
real web settings/exercise persistence and export/import. Native XCTest
coverage tests the same entry/clock cases and the actual backup codecs.
The smoke test now waits for the history editor's saved state rather than
assuming its milestone rebuild finishes inside a fixed 60 ms delay.

This Linux workspace has no Swift/Xcode compiler. Native parse/core, Darwin,
production unsigned iOS and migration results must be taken from the exact
combined PR head's GitHub Actions run; green checks on its ingredients do not
prove the integration. The PR body carries the latest head and run links.

The cloud browser rejected opening the local app under its URL security
policy and explicitly prohibited alternate routes around that action.
No local-server, tunnel, alternate browser, or fabricated screenshot was used.
Actual new web/iPhone screen captures are **not available for this candidate**.

- [Historical iPhone before/after pairs](BEFORE-AFTER.md) name their original commits and are not evidence for this head.
- [Approved anatomy before/after registration renders](anatomy-registration/README.md) show production masks against the exact art; they are not full app screenshots.
- [Material decisions](DECISIONS.md) distinguish the prior pass from this integration.

Required current captures: Today, active session/warmups/current/next set,
calculator target/reverse/mixed-unit/expanded, exercise pane, anatomy selected
and unselected, Settings, duration editor/validation, library categories/search,
and History. Use representative 390-wide phone and 1280-wide web viewports,
iPhone normal/accessibility text, all three approved themes, keyboard focus
and reduced motion. #196 needs explicit no-overlap checks on Settings,
History and Program before claiming native layout acceptance.

## Open PR review

| PR | Disposition |
| --- | --- |
| #201 | Combined application candidate; keep draft until its remaining implementation and UI/device gates are met. Includes #204/#205; their focused discussions remain useful review boundaries. |
| #204 | Source-compatible initializer restored in `bc44d056aacf38297a551d219f600258dc6f6158`; compile regression added. Included here. |
| #205 | Owner approved contours on 7 September. Included unchanged; full pane/VoiceOver validation remains. |
| #202 | Independent `deploy-pages` 5.0.1 action pin. The official tag resolves to `368f82528645a54fb793d4d04e342629a3f51346`; two workflow references change, permissions/application sources do not. Its head CI is green. Kept separate from the visual changes. |

No PR has been merged and no release/TestFlight upload has been requested by
this preparation pass. The Titanium backup enum addition already makes #201
a breaking release (`feat!`, portable contract v13); rest entry needs no new
stored field or contract version. Semantic-release remains the version owner.

## Open issue disposition

| Issues | Review disposition |
| --- | --- |
| #177 | Epic remains open; use the requirement table above rather than treating green CI as completed visual acceptance. |
| #179, #183, #185, #186 | Substantial implementation exists; keep open for the remaining visual/device checks and #196 overlap. |
| #180, #181, #182, #65 | Shared loading/data contracts exist; approved realistic geometry/inspection and legibility still block completion. |
| #55 | Physical/named equipment profiles remain separate unfinished work; no new inventory or persisted profile is invented here. |
| #63, #66, #184 | Browser/detail improvements are partial; broader catalog, favorites and cross-workflow acceptance remain. |
| #187 | Final screenshot/verification gate remains open. Historical screenshots cannot close it. |
| #192, #193, #194, #195 | Fixed with regressions in this candidate; keep open until merged and required UI verification is attached. |
| #196 | Global native floating plate-button overlap remains an explicit layout blocker; only its theme foreground contrast is corrected here. |
| #199 | Duration implementation included; remaining actual UI/device validation prevents closing the issue. |
| #197, #198, #200 | Headphone cue, additional intentional imagery and full Lock Screen progression remain unfinished. |
| #203 | Approved geometry carried unchanged from #205; merge/UI evidence still tracked on that focused PR. |
| #61 | Broader accessibility and lifecycle acceptance remains open; this pass supplies specific regression evidence only. |
| #58, #64, #94, #95, #103, #104, #152, #155 | Triaged outside this visual candidate. Do not close broader programming, coaching, invariant or history work based on incidental coverage here. |

## Equipment references checked

- [IPF 2026 Technical Rulebook, effective 1 March, v3](https://www.powerlifting.sport/fileadmin/ipf/data/rules/technical-rules/english/2026_IPF_Technical_Rulebook__effective_01_March_2026__v3.pdf): 15/20/25 kg colour requirements, lower weights any colour, heavier plates innermost.
- [Rogue IWF-approved kilogram change plates](https://www.roguefitness.com/rogue-kg-change-plates): 0.5 white, 1 green, 1.5 yellow, 2 blue, 2.5 red, 5 white; product-specific dimensions distinguish change plates from full-size bumpers. These dimensions are reference evidence, not silently inferred geometry in this patch.
- The direct IWF rules endpoint returned 403 during this review. This pass does not claim to have checked a newer IWF rulebook; the small-plate mapping is supported by the manufacturer's IWF-approved specification.
