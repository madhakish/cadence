# Calculator target Dynamic Type proof

These original iPhone 17 Pro simulator captures were inspected during PR #245 review. They use synthetic visual-test fixtures.

- Source commit: `bb4b07d709b2d77f12e599845a5c061021491632`.
- [Native capture run 35458163575](https://github.com/madhakish/cadence/actions/runs/35458163575), artifact `10588827284` (`cadence-iphone-visual-proof-bb4b07d709b2d77f12e599845a5c061021491632`).
- Artifact ZIP SHA-256: `722be7624298e18842885309cb0c7b9885b6b86c5a9d64c5ad33c02887bd6e35`.
- Test: `VisualProofUITests/test14CalculatorTargetAtAccessibilityTextSize()`; capture run completed successfully on September 19, 2026.

| Capture | Original artifact attachment | Inspection |
| --- | --- | --- |
| [Standard text](target-standard-iphone.png) | `189E71F5-26E5-4F71-944C-6CF88709D7E8.png` | Entered target 139 is legible; lb/kg control sits beside the field. |
| [Maximum accessibility text](target-accessibility-iphone.png) | `E14C0EC6-5229-4C48-9E94-973CFAC717AD.png` | Target 139 grows without clipping; the unit control sits below the number and remains fully visible. |

The native test also verifies input height growth, on-screen controls, and switching units without losing 139. At maximum text size the screenshot is scrolled to the target field; the top heading partially scrolls under the navigation bar. This evidence closes only the calculator target slice. Remaining Today/current-session Dynamic Type advisories in #238 and the broader proof matrix in #187 remain open.
