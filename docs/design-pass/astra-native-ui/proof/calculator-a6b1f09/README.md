# Native calculator review

Captured and visually inspected on source `a6b1f0989704193d808979a6f97210385b97284c`,
whose last app-code change is `6a23e0f`. These are unmodified native screenshot
attachments, with [source IDs and hashes](provenance.json) and the original
[test summary](test-summary.json). Later evidence-only commits do not change
the captured app or tests.

| Capture | Scenario | Inspected result |
| --- | --- | --- |
| [Standard](standard.png) | 139 lb requested, standard text | 138.7 lb achieved, 62.9 kg and −0.3 lb difference are visible before the equipment stage. |
| [Accessibility input](accessibility-entry.png) | 139 lb requested, AX-XXXL | The entire input and both unit choices are below the pinned header; the field grows and units flow beneath it. |
| [Accessibility achieved](accessibility-achieved.png) | Same entered 139, switched to kg through the real picker | 304 lb / 137.9 kg achieved and −2.4 lb from the converted request remain readable together. The total stays larger than its unit. |

The synthetic `--visual-proof` fixture ran in `CadenceVisualProof` on an
iPhone 18 Pro simulator, iOS 27.2, at 402 × 874 pt. Geometry attachments retain
the exact locale and text-size launch arguments. The AX achieved capture is
scrolled to the readout, after changing units; it is a different state from
the input capture.

Native checks during this pass:

- `d44fc56`: tests 04, 14 and 18 passed, zero failures/skips. This includes
  inspector controls, exact/mixed/reverse loading, unavailable-load warnings
  and single-disc cases before the shared-summary accessibility correction.
- `84bc04f`: tests 04 and 14 passed after stacking the accessibility readout.
- `6a23e0f`: test 14 passed after preserving numeral/unit proportions.
- `a6b1f09`: test 14 passed after measuring the pinned header as well as the
  field. All three retained PNGs were inspected from this final run.

The final test checks the whole achieved group's frame, spoken summary,
target growth and picker interaction. It does not run a full accessibility
audit. The native summary retains invalid-frame and QoS runtime warnings.
Other widths, themes, VoiceOver and Reduce Motion still require broader proof.

The achieved load now precedes the stage, but most of the stage remains below
the first viewport in this mixed-unit example. This is the first hierarchy
change, not finished Astra artwork integration. The photographic compositor,
session/Today presentation and brand selection remain in the draft's scope.

Reproduce the focused capture with an available iPhone 18 Pro simulator:

```sh
xcodegen generate --quiet
xcodebuild test -project Cadence.xcodeproj -scheme CadenceVisualProof \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/astra-proof -resultBundlePath build/AstraCalculatorFinalProof.xcresult \
  -jobs 1 -parallel-testing-enabled NO \
  -only-testing:CadenceVisualProofUITests/VisualProofUITests/test14CalculatorTargetAtAccessibilityTextSize
```

Use the shared `/tmp/cadence-xcode.lock` convention before local Xcode work,
and a fresh result-bundle path when repeating a run. The `.xcresult` and build
products are deliberately outside this evidence directory.
