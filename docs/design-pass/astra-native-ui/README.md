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

The first calculator presentation change puts the existing achieved-load
summary before the equipment in target and reverse modes. Requested-target
entry is quieter, and pinned headers have an opaque canvas. Solver results,
reverse-mode stack order and all readout content remain unchanged.

This PR begins with reviewable brand exports and calculator hierarchy.
Selected runtime assets, further screen presentation and native visual proof
are still pending; the draft is not merge-ready.
