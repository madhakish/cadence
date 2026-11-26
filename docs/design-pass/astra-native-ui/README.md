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

Focus is the recommended candidate for small-icon review. **No variant has
been selected or installed.** Runtime iPhone/Watch catalogs, the Today glyph
and splash art are unchanged. The five-tab navigation and enlarged centered
Today mark remain requirements for the later integration.

Reproduce with Python 3 and [the pinned Pillow dependency](requirements.txt):

```sh
python3 -m venv /tmp/cadence-brand-export
/tmp/cadence-brand-export/bin/pip install -r docs/design-pass/astra-native-ui/requirements.txt
/tmp/cadence-brand-export/bin/python docs/design-pass/astra-native-ui/export_brand_candidates.py --proof-dir /tmp/cadence-brand-previews
```

The optional 40/60/120 px previews are scale studies. Actual iOS/Watch masks,
home-screen appearances and small-size readability still require native
captures before choosing or installing an icon.

## Implementation order and dependencies

1. Prove the blue-bumper/oak loading stage with static photography and live,
   solver-driven equipment. Milo owns the renderer API, material contract,
   registration, compositing and caching under [#374](https://github.com/madhakish/cadence/pull/374).
   Current local composites remain fixed-hero experiments with a failed
   held-out registration check and no runtime acceptance.
2. Carry that visual language into calculator, session and Today after the
   active feature layouts land. Preserve achieved versus requested load,
   per-set edits, actual rest/RIR data, gym-tag access and one-handed actions.
3. Integrate the selected brand treatment with the existing icon/tab/splash
   work, preserving five tabs and leaving anatomy assets/masks untouched.
4. Capture actual native output on the exact PR head at ordinary and large
   accessibility sizes, with themes, safe areas, VoiceOver and Reduce Motion
   respected. Debug stills and scale boards do not establish runtime quality.

The calculator places the achieved total first, the inspectable bar directly
below it, then the per-side breakdown and inventory cells, following the
[Astra plate-loading screen](../astra-2026-11-01/01-screen-plate-loading.png).
The same order applies to the manually entered stack. The rack name remains
visible above the mode picker. At accessibility text sizes the totals and
deviation stack, and the plate cells occupy one column.

The five 55, 45, 35, 25 and 10 lb colored-rubber photographs come directly
from the reference screen. The calculator uses them for the pound reference
and matching colored bumper equipment, including the individual plates in a
loadout. Kilograms, fractional weights, steel, iron and black bumpers retain
their theme-specific denomination keys. All visible weights and accessible
labels continue to come from the actual plate. Reproduce the transparent
156 px catalog assets with `python3 docs/design-pass/astra-native-ui/export_plate_reference.py`
in the same Pillow environment.

The [inspected calculator captures](proof/calculator-a6b1f09/README.md) record
the exact source, original native screenshots and focused test results at
standard and maximum accessibility text sizes. This is limited proof of the
first hierarchy change; most of the stage remains below the initial viewport.

The calculator layout and the three review exports can ship together. The
renderer in [#374](https://github.com/madhakish/cadence/pull/374) can use the
same summary after integration. The owner’s icon selection, the photographic
stage and the remaining screen work are tracked under
[#177](https://github.com/madhakish/cadence/issues/177). The session, Watch
and launch features have landed on `main` through #376, #373 and #379.
