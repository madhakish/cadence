# Plate face texture provenance

Created September 20, 2026 with the built-in image generation tool for the
two-view barbell inspection. These are original generated material details,
not photographs of certified equipment or copied manufacturer artwork.

## Generation briefs

Both prompts requested an orthographic, centered, circular plate face on actual
transparency, neutral medium gray material suitable for runtime tinting, soft
product-studio illumination, realistic fine texture, and no lettering, numbers,
logos, certification marks, watermark, floor, or cast shadow.

- **Bumper:** dense molded rubber, recessed annular face, detailed rolled rim,
  broad machined steel hub with six recessed bolts, physically open center bore.
  Construction references were competition bumpers from Eleiko and Rogue.
- **Steel:** thin calibrated powerlifting disc, fine gray powder coating,
  recessed face, crisp machined rim, small bright steel hub, and two subtle
  calibration plugs. Construction reference was calibrated competition steel.

The generator supplied photographic shading; the application supplies every
denomination, unit, color and CADENCE stamp. These illustrative details are not
manufacturer-specific dimensions or an assertion of IWF/IPF certification.

## Installed assets

Each original was downsampled to 768 × 768 RGBA with ImageMagick, preserving
transparency. The same PNG bytes ship in the web bundle and iOS asset catalog.

| Web file under `web/app/assets/plates/` | Native imageset | Bytes |
| --- | --- | ---: |
| `bumper-face-detail.png` | `PlateBumperFaceDetail` | 718902 |
| `steel-face-detail.png` | `PlateSteelFaceDetail` | 872420 |

SHA-256:

```text
0ce12faad0e4773683a96db4b3764505e54f8e8f01c69310cf84ae5f1b7776c5  bumper-face-detail.png
d5700b9e1079d2fecd7ea03cbf54707e3fc4003e748b284e9c46e5fb734be733  steel-face-detail.png
```

Original generation files are retained locally under
`~/.codex/generated_images/01a0778b-c74c-7243-8f53-6420abe8c7d7/`:

- `exec-618f4a8c-2a9d-4748-9e7f-e2009105d7a5.png` — bumper
- `exec-262d9ae0-aa86-4f68-9550-d0d98a66eb88.png` — steel

## Runtime treatment

Both solid renderers tint the gray body from the canonical palette using
luminance coefficients 0.2126 / 0.7152 / 0.0722, gray reference 0.50 and a 7%
original-image contribution. Chrome stays untinted within the photographed
hub (0.57 of face radius for bumper; 0.245 for steel). The face plane uses the
photograph's measured circle radius of 0.485 canvas widths, and a bore mask
retains the existing physical sleeve opening. Face textures retain their own
soft lighting; surrounding solid rims, sleeve, shaft and collar are lit in 3D.

Only two source images are decoded per web inspector. Native caches tinted
faces within each renderer. The service worker precaches both files; procedural
faces remain visible while web textures load or if an image fails. The existing
54 sprite assets remain the compact-row and no-3D fallback artwork, unchanged.

`node web/tests/plate-sprites.test.mjs` checks native/web byte identity and
offline inclusion. No anatomy or previously approved plate artwork was replaced.

## Construction and color references

- [IWF equipment color rules](https://iwf.sport/weightlifting_/equipment/)
- [IPF technical rules](https://www.powerlifting.sport/rules/codes/info/technical-rules)
- [Eleiko calibrated competition steel](https://eleiko.com/en-us/equipment/plates/powerlifting/3060350-25-eleiko-ipf-powerlifting-competition-plate-25-kg)
- [Rogue IWF competition bumpers](https://www.roguefitness.com/rogue-kg-competition-plates-iwf)

Kilogram colors retain the existing IWF-aware palette. IPF specifies red 25 kg,
blue 20 kg and yellow 15 kg; plates 10 kg and below may be any color. Pound plate
colors are manufacturer conventions, not IPF requirements.
