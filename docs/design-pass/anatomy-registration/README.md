# Vitruvian muscle registration — issue 203

These are **static source-art + production-mask registration renders**, not
browser screenshots or native device captures. They verify which pixels the
mask covers. They do not verify SwiftUI layout, CSS filter rendering, Dynamic
Type, VoiceOver, focus contrast, or the outer container feather.

## Material decisions

- Keep both original 1254×1254 JPEGs unchanged. The singlet and engraved ink are
  part of the mascot; nothing is painted into or regenerated from those files.
- Register cubic SVG contours directly in source-image pixels. The front's old
  mirrored control loops and second midpoint-smoothing pass are removed.
- Use byte-identical front/back SVGs in the native asset catalog and web assets.
  The two consumers scale image and overlay together in the same square.
- Separate visible portions of both Vitruvian limb poses: four biceps,
  forearms, quads, triceps, hamstrings, and calves. Stop thighs above the knees;
  do not wash the wrists/hands or the empty space between legs.
- Keep shoulder caps separate from upper-arm bellies, lats separate from the
  lumbar region, and the paired rectus abdominis separate from the obliques.
  The first candidate's segmented abdominal blocks were rejected during render
  inspection in favor of a continuous paired wash; the original ink supplies
  the subdivisions.
- Preserve the garment. Chest, abdomen, lower back and glute highlights over
  fabric are **anatomical projections**, not exposed-muscle tracing. This is a
  stylized exercise guide, not a medical atlas or exact gorilla dissection.
- Reduce the consumer blur from 1.8–2.1 to 0.35 display pixels/points so accurate
  boundaries do not bleed back across neighboring muscles. Existing red and
  steel treatments remain; selected/unselected opacity now matches on both.
- The existing rear-deltoid alias shares one mask. Primary treatment wins and
  legend selection recognizes either ID, avoiding duplicate darkening.

No changes to plates, typography, themes, exercise-to-muscle classifications,
workout programming, timers, history, persistence, imports or backups.
The existing Foundry/theme and plate work remains on its separate local branch.

## Anatomy references

The regional relationships are grounded in OpenStax *Anatomy and Physiology
2e*. The outlines follow this artwork's proportions, not a human silhouette
stretched over the gorilla. Reference illustrations are not copied into assets.

- [§11.4, abdominal wall — Figure 11.16](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-4-axial-muscles-of-the-abdominal-wall-and-thorax): paired rectus and lateral obliques.
- [§11.5, shoulder and upper limbs — Figures 11.23 and 11.25](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-5-muscles-of-the-pectoral-girdle-and-upper-limbs): pectorals, deltoids, lats, upper-arm and forearm relationships.
- [§11.6, pelvic girdle and lower limbs — Figure 11.29](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-6-appendicular-muscles-of-the-pelvic-girdle-and-lower-limbs): gluteal, anterior/medial thigh and posterior thigh relationships.

## Comparable evidence

The before render uses main at `6c317293fbe20043398bb85da9776a6271ad6106`.
Both sides use the same static compositor. It reads `figureSVG`, resolves the
production image/mask assets, and multiplies red/steel washes over the art.
Blur and container feather are intentionally omitted to expose contour errors.
Review JPEGs are encoded identically; production JPEGs are untouched.

| Profile | Before | After | Small after (180 px per figure) |
| --- | --- | --- | --- |
| Front Squat | [large](before/front-squat-626.jpg) | [large](after/front-squat-626.jpg) | [small](after/front-squat-180.jpg) |
| Romanian Deadlift | [large](before/romanian-deadlift-626.jpg) | [large](after/romanian-deadlift-626.jpg) | [small](after/romanian-deadlift-180.jpg) |
| Barbell Bench | [large](before/barbell-bench-626.jpg) | [large](after/barbell-bench-626.jpg) | [small](after/barbell-bench-180.jpg) |
| Overhead Press | [large](before/overhead-press-626.jpg) | [large](after/overhead-press-626.jpg) | [small](after/overhead-press-180.jpg) |
| Face Pulls | [large](before/face-pulls-626.jpg) | [large](after/face-pulls-626.jpg) | [small](after/face-pulls-180.jpg) |

All isolated selections: [front before](before/front-isolated.jpg),
[front after](after/front-isolated.jpg), [back before](before/back-isolated.jpg),
[back after](after/back-isolated.jpg).

## Verification and remaining gates

1. Original source hash/native parity → verified by the regression suite.
2. All 18 mask assets native/web byte parity, asset catalog wiring and offline
   precache → verified. Every visible muscle ID still has a representation.
3. Reviewed source-pixel landmarks inside each muscle and exclusion landmarks
   on knees, hands, face and parchment → verified by cubic-curve sampling tests.
   These guard registration, not medical accuracy or every contour pixel.
4. Legend focus/hover/click/clear and rear-deltoid alias → DOM tests pass.
5. Full `cd web && npm test` → pass: 53 invariants/100 platform assertions;
   core 1699; plate renderer 66; migrations 25+6+7+13; programs 129;
   smoke 1191; registration 4 test groups; site 233; accessibility contracts 25.
6. `git diff --check` → pass. The anatomy parity fixture remains unchanged.
7. Native compilation and Swift tests → GitHub CI required; no Swift/Xcode
   toolchain in this workspace. Check the exact PR head, not a previous commit.
8. **Before merge:** render the real exercise pane at 390 and 1280 CSS pixels;
   capture native iPhone normal/Dynamic Type and selected-muscle views; verify
   actual CSS tint, VoiceOver/keyboard, focus contrast and reduced motion.
   Static registration proof and DOM tests do not satisfy this device/UI gate.

Regenerate the after registration proof with Node, the web test dependencies,
and a locally available Sharp installation:

```sh
node web/tools/render-anatomy-registration.mjs docs/design-pass/anatomy-registration/after
```

Sharp is a proof-rendering tool only; it is not an app/runtime dependency.
For the historical before proof, run this script against the baseline anatomy
module and baseline masks in a separate checkout, keeping the output destination
separate. Do not overwrite the current registered masks.
