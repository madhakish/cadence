# Astra native visual pass

The visual work starts with the supplied [Astra references](../astra-2026-11-01/README.md).
The [recorded brand decision](https://github.com/madhakish/cadence/issues/177#issuecomment-6563484754)
allows the Astra gorilla for brand marks. The anatomy images and functional
region masks remain separate and unchanged.

## Brand candidates

[Heritage](icons/heritage.png), [Foundry](icons/foundry.png) and [Focus](icons/focus.png)
are opaque, unmasked 1024 px RGB exports of the supplied 1254 px square
masters. The only pixel operation is a Lanczos resize. The exporter assigns
the bundled sRGB profile; it does not redraw, crop, recolor or sharpen the art.
[The manifest](manifest.json) records source/export hashes and profile identity.

The combined candidate installs Focus in the iPhone and Watch catalogs and derives the centered Today glyph from the same master. Foundry supplies LaunchMark to the system screen and SwiftUI splash. Heritage supplies the wood engraving in the equipment renderer. The owner reviews these assignments in [the landing PR](https://github.com/madhakish/cadence/pull/401).

Reproduce with Python 3 and [the pinned Pillow dependency](requirements.txt):

```sh
python3 -m venv /tmp/cadence-brand-export
/tmp/cadence-brand-export/bin/pip install -r docs/design-pass/astra-native-ui/requirements.txt
/tmp/cadence-brand-export/bin/python docs/design-pass/astra-native-ui/export_brand_candidates.py --proof-dir /tmp/cadence-brand-previews
```

The optional 40/60/120 px previews are scale studies. Actual iOS/Watch masks,
home-screen appearances and small-size readability still require native
captures before choosing or installing an icon.

## Runtime integration

The current equipment compositor assembles the rack-selected bar from photographed faces, treads, steel and collars on a registered empty platform. See the [photographic equipment and native captures](../photographic-equipment/README.md).

The calculator places the achieved total first, the inspectable bar directly
below it, then the per-side breakdown and inventory cells, following the
[Astra plate-loading screen](../astra-2026-11-01/01-screen-plate-loading.png).
The same order applies to the manually entered stack. The rack name remains
visible above the mode picker. At accessibility text sizes the totals and
deviation stack, and the plate cells occupy one column.

The calculator reference, inventory and workout views use the same equipment components and the plate record’s exact weight and unit. The CADENCE imprint and matching 45 lb, 20 kg and 15 kg stamps come from the original Astra studies.

The [inspected calculator captures](proof/calculator-a6b1f09/README.md) record
the exact source, original native screenshots and focused test results at
standard and maximum accessibility text sizes. This is limited proof of the
first hierarchy change; most of the stage remains below the initial viewport.

The [native splash frame](proof/integration-4f98f98/launch.png) was captured from the combined app at `4f98f9841d770397f0855453138f37838a5a3205` using the iPhone 18 Pro simulator (iOS 27.2), the synthetic visual-proof fixture and the frozen animated launch test. A local Xcode 27.2 build-for-testing succeeded. The local UI run was interrupted under disk pressure after this frame. The original PNG SHA-256 is `6461c13870e354f977d4942a683da827d866bd7481d738c6de93e4420ec1e2c4`. The landing PR tracks the complete native review and the merge order.

The [studio comparison](proof/integration-7c40b5a/studio-comparison.jpg) shows reference 03 beside three frames from the native renderer at `7c40b5a`. The simulator produced all 15 load, camera and finish combinations. The engraving, oak grain and actual plate order are visible. The rubber faces and floor contact still look flatter than the photographic reference. [Capture provenance](proof/integration-7c40b5a/provenance.json) records the original PNG hashes. [Cold-cache timings](proof/integration-7c40b5a/timings.txt) are simulator measurements.

The [earlier native equipment comparison](proof/studio-f3785401/README.md) records the SceneKit version. The [current native comparison](../photographic-equipment/README.md) and [web equipment notes](WEB-EQUIPMENT.md) cover the photographic implementation.
