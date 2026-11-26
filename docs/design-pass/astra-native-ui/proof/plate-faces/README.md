# Native plate faces and Today sleeve

The same native SwiftUI view renders the calculator badge, inspector key and the faces in Today’s per-side miniature. The five complete Astra pound bumper photographs remain confined to the matching weight, unit and equipment family. The other rows composite a neutral material over the rack’s actual colour. The label comes from the stored denomination and unit.

The [dark matrix](dark-matrix.jpg) and [light matrix](light-matrix.jpg) show all eleven themes with 45 lb, 20 kg and a custom 1.125 kg plate. The [accessibility sample](accessibility.jpg) shows a mixed stack of two 45 lb plates and one 1.125 kg plate, plus its companion text, with the accessibility5 SwiftUI environment. These are component captures from the shipping SwiftUI views on a macOS host using the same PNG pixels. The iPhone UI test exercises the real calculator at Large and Accessibility XXXL.

Reference 03 supplies the colour rubber profile, 04 supplies coated and gloss steel, 05 supplies black rubber and 06 supplies cast iron. Hammertone samples 06 at a tighter scale. Machined steel combines the coating profile with a directional brushed treatment. The generator projects clean radial sectors of those photographs into front faces and reuses the same source-material relief as the studio. The metal hub comes from the upright 45 lb plate in 01. Runtime overlays add the actual denomination, optional colour band and the selected hub finish. The projected sidewall depth follows the plate geometry. The mini repeats every physical plate in sleeve order and uses the shared chrome photograph from 03.

To regenerate the neutral assets from the repository root, run the following with Pillow and NumPy installed.

```sh
python3 docs/design-pass/astra-native-ui/export_plate_faces.py
```

The component probe checked all 374 combinations of 11 themes, two styles, standard plates and four precision-sensitive custom inputs. It verified source-photo eligibility, asset availability, complete per-side counts and exact 1.125 kg / lb labels. The iPhone catalog compiled with all eight new neutral images. The [iPhone proof test](../../../../../CadenceVisualProofUITests/PlateFaceProofTests.swift) verifies that both 1.125 kg and 1.125 lb reverse-rack entries are reachable and fit horizontally at each supported capture size.
