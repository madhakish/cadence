# Equipment imagery inventory — 1 October 2026

This records the equipment artwork already shipped on main at `20058600` and
consumed by the #177 candidate. PR #271 also adds the three original category
cutouts documented in [EQUIPMENT-CONTEXT.md](EQUIPMENT-CONTEXT.md). Screenshot
proof files are application captures, not runtime assets.

## Provenance and license

The two original face details were generated for Cadence on 20 September;
[PLATE-FACE-TEXTURES.md](PLATE-FACE-TEXTURES.md) records their briefs and installed
hashes. They are illustrative material textures, not copied manufacturer
photographs or certification marks. All remaining files are deterministic PNG
sprites rendered from the repository's geometry and studio lighting by
[`render-plate-sprites.py`](../../web/tools/render-plate-sprites.py) and installed
by [`install-plate-sprites.mjs`](../../web/tools/install-plate-sprites.mjs).
[PLATE-REFERENCE.md](PLATE-REFERENCE.md) distinguishes verified dimensions from
unverified reference values. Theme names and colors do not imply certification.

The repository [LICENSE](../../LICENSE) reserves all rights to madhakish.
This inventory does not designate these assets as public-domain or add a
third-party license. The generated details and procedural source are original
Cadence artwork. No stock imagery or manufacturer photo is included in this
family.

## Purposeful surface map

| Surface | Image and purpose | Native / web consumer |
| --- | --- | --- |
| Current workout set | The athlete's exact mirrored loadout explains what to put on the bar; the achieved load and next action remain dominant. | `ActiveSessionView` / `views/session.js` |
| Exercise information in a workout | The contextual set's actual stack accompanies the resolved prescription and opens inspection; it is not a generic exercise thumbnail. | `LibraryView` / `views/settings.js` |
| Calculator | The solved or entered loadout is the central visual; the inspector separates physical plates without changing their identity or mass. | `PlateCalculatorView` / `views/plates.js` |
| Workout preview | Equipment illustrates the planned load before starting, using the same renderer and authoritative solution. | `WorkoutPreviewView` / `views/home.js` |
| Library and empty states | Search, filters, Favorites/Recent and category counts lead; three original implement cutouts support category labels and unlogged-detail states. Empty Program uses the unloaded rack/platform. | `ExerciseBrowser`, `LibraryView`, `ProgramOverviewView` / shared `exerciseBrowser`, exercise detail, `views/program.js` |
| Settings | Task groups and the gym's actual plate-theme choice give equipment context; no image sits behind essential controls. | `SettingsView` / `views/settings.js` |
| Today and History | Training state, resume/start action and performed work lead; no decorative plate collection competes with them. | `HomeView`, `HistoryView` / `views/home.js`, `views/history.js` |

The first three are distinct non-gorilla surfaces with equipment imagery.
The original front/back gorilla JPEGs remain unchanged; registered anatomy
masks are a separate, previously approved asset family. These decisions follow
the existing [material decision record](DECISIONS.md). The new category family
extends this map without repeating the gorilla or placing images behind text.

## Size, availability and layout

The 158 web PNGs total **9,594,989 bytes**; every native twin is byte-identical.
The face details are 768 × 768 RGBA. Sprite shapes share compact, fixed-size
canvases and placement metadata; the largest sprite is listed below. All files
ship locally and are precached for offline use. The inspector retains fixed
geometry and procedural faces while detail textures decode; fallback sprites
retain the same solution. `plate-sprites.test.mjs`, renderer/inspection tests,
and browser offline acceptance check pairing, assets and behavior. These
checks do not substitute for inspecting the actual captures.

Web paths below map to native
`Cadence/Assets.xcassets/PlateSprites/<file-stem>.imageset/<file>` except the two
face details, which map to `PlateBumperFaceDetail` and `PlateSteelFaceDetail`.

| Web file | Bytes | Pixels | SHA-256 | Source |
| --- | ---: | --- | --- | --- |
| [bar-collar-assembled.png](../../web/app/assets/plates/bar-collar-assembled.png) | 9,434 | 320 × 320 | `a7e906c03b0ca13c1e550620c6c1c84b693133610371f097b65eed246ac4f12b` | Procedural sprite |
| [bar-collar-exploded.png](../../web/app/assets/plates/bar-collar-exploded.png) | 10,995 | 320 × 320 | `70b727132d95a7161e7748dcc560cee0e860c84952a459b5c3f1c9e5bc3c21d0` | Procedural sprite |
| [bar-collar-near-assembled.png](../../web/app/assets/plates/bar-collar-near-assembled.png) | 9,434 | 320 × 320 | `a7e906c03b0ca13c1e550620c6c1c84b693133610371f097b65eed246ac4f12b` | Procedural sprite |
| [bar-collar-near-exploded.png](../../web/app/assets/plates/bar-collar-near-exploded.png) | 10,995 | 320 × 320 | `70b727132d95a7161e7748dcc560cee0e860c84952a459b5c3f1c9e5bc3c21d0` | Procedural sprite |
| [bar-shaft-assembled.png](../../web/app/assets/plates/bar-shaft-assembled.png) | 51,406 | 1600 × 320 | `3dce7683827c388d1f1b1aa517f839828771a9259943c0f7acb59751a45c27ac` | Procedural sprite |
| [bar-shaft-exploded.png](../../web/app/assets/plates/bar-shaft-exploded.png) | 49,125 | 1600 × 320 | `17484887511491d53df88411cbbf1b00f73d5c77a257b739873df64eecd460e4` | Procedural sprite |
| [bar-sleeve-assembled.png](../../web/app/assets/plates/bar-sleeve-assembled.png) | 19,074 | 900 × 300 | `2d238b244754a3ae03805ca27499fd39dc6cc327999dc34493fd73be99e78c20` | Procedural sprite |
| [bar-sleeve-exploded.png](../../web/app/assets/plates/bar-sleeve-exploded.png) | 23,787 | 900 × 300 | `35842a6557908be41d3c3660abe264ce07c593044b155b8659f8079bd88d73fa` | Procedural sprite |
| [bar-sleeve-near-assembled.png](../../web/app/assets/plates/bar-sleeve-near-assembled.png) | 19,401 | 900 × 300 | `30c3a7f60694eec0b36d247e21de9a78be5f5e149c43d0a0edd425ada12c8dbc` | Procedural sprite |
| [bar-sleeve-near-exploded.png](../../web/app/assets/plates/bar-sleeve-near-exploded.png) | 24,210 | 900 × 300 | `cfe35d52a7d28492d1c77ba91ac890d32c0b394d76f1d2d96306a9281066b731` | Procedural sprite |
| [bumper-face-detail.png](../../web/app/assets/plates/bumper-face-detail.png) | 718,902 | 768 × 768 | `0ce12faad0e4773683a96db4b3764505e54f8e8f01c69310cf84ae5f1b7776c5` | Generated face detail (2026-09-20) |
| [plate-bumper-450x21-assembled.png](../../web/app/assets/plates/plate-bumper-450x21-assembled.png) | 43,937 | 512 × 512 | `3c8bf16eea8b1a1b244790640e5791d338418684b32492ebc4b6b7a87c5285b2` | Procedural sprite |
| [plate-bumper-450x21-exploded.png](../../web/app/assets/plates/plate-bumper-450x21-exploded.png) | 68,131 | 512 × 512 | `50d95c5e197083c67bed2a9bb2357561657e974c6401430f58a816b159122dc3` | Procedural sprite |
| [plate-bumper-450x25-assembled.png](../../web/app/assets/plates/plate-bumper-450x25-assembled.png) | 45,224 | 512 × 512 | `80bf723b485d562c06302fa26f011783b22af6fc8a7f38cd0286e9f535abe975` | Procedural sprite |
| [plate-bumper-450x25-exploded.png](../../web/app/assets/plates/plate-bumper-450x25-exploded.png) | 68,610 | 512 × 512 | `9108c08fdaf0a8076eb45d56a6d2d622c0237aad002990716139b9e8906082bd` | Procedural sprite |
| [plate-bumper-450x29-assembled.png](../../web/app/assets/plates/plate-bumper-450x29-assembled.png) | 46,957 | 512 × 512 | `b9ad83a4ff039570d6c4f406e382228174d7f5c201864ec4b2c52a0b80b88024` | Procedural sprite |
| [plate-bumper-450x29-exploded.png](../../web/app/assets/plates/plate-bumper-450x29-exploded.png) | 70,929 | 512 × 512 | `33f3f9a8713885d60974f7e6d39834c991257f2c78e747c80586ef5cac457dd8` | Procedural sprite |
| [plate-bumper-450x35-assembled.png](../../web/app/assets/plates/plate-bumper-450x35-assembled.png) | 49,294 | 512 × 512 | `0a669f68bc30d4c60dee8ea1c2df3f898b44fb1ed757d109a053182cb2937f52` | Procedural sprite |
| [plate-bumper-450x35-exploded.png](../../web/app/assets/plates/plate-bumper-450x35-exploded.png) | 72,683 | 512 × 512 | `3f84229867bdb56d2ce1ab410e3ac9474c65bdd8e602af6c1cb6dafc822a8307` | Procedural sprite |
| [plate-bumper-450x38-assembled.png](../../web/app/assets/plates/plate-bumper-450x38-assembled.png) | 49,353 | 512 × 512 | `26a75a494df7161971b36e96fb0633f6feb1e1f82ee63ae07b2fbc9270f05e04` | Procedural sprite |
| [plate-bumper-450x38-exploded.png](../../web/app/assets/plates/plate-bumper-450x38-exploded.png) | 71,726 | 512 × 512 | `65d0638149e167b4abb4d955a5a12b255fa5150a081142cd28a59c5d2b9833c5` | Procedural sprite |
| [plate-bumper-450x40-assembled.png](../../web/app/assets/plates/plate-bumper-450x40-assembled.png) | 51,186 | 512 × 512 | `d6f213f57117af1d5718cdee96703d3280367ab887ec78c63e8a514438603610` | Procedural sprite |
| [plate-bumper-450x40-exploded.png](../../web/app/assets/plates/plate-bumper-450x40-exploded.png) | 74,146 | 512 × 512 | `8e28833b74e891c18bf385a4dec1ca7d12466f61f9ab95af0581a4a6a3705501` | Procedural sprite |
| [plate-bumper-450x42-assembled.png](../../web/app/assets/plates/plate-bumper-450x42-assembled.png) | 51,206 | 512 × 512 | `e4999c50590f347389fe5fb8d4026044c5d8672db1cc1b8090a1543b80b0c358` | Procedural sprite |
| [plate-bumper-450x42-exploded.png](../../web/app/assets/plates/plate-bumper-450x42-exploded.png) | 73,428 | 512 × 512 | `904fc9c5dc928e504c14a43e300d2538685ffaff5ffedb2a04eeff21b13b8d72` | Procedural sprite |
| [plate-bumper-450x48-assembled.png](../../web/app/assets/plates/plate-bumper-450x48-assembled.png) | 53,611 | 512 × 512 | `08174613691c95042a879f28aac588bafa81740485f011912c5255fc5ffe3e8d` | Procedural sprite |
| [plate-bumper-450x48-exploded.png](../../web/app/assets/plates/plate-bumper-450x48-exploded.png) | 75,256 | 512 × 512 | `f6e1d170792c53abcdf3a055dc2e6051d8d8587b0a222f57e11bd98311784067` | Procedural sprite |
| [plate-bumper-450x49-assembled.png](../../web/app/assets/plates/plate-bumper-450x49-assembled.png) | 53,594 | 512 × 512 | `455c119141978ace0d40fe4de71bc820e8c046b35abe985289a0a43e00cce795` | Procedural sprite |
| [plate-bumper-450x49-exploded.png](../../web/app/assets/plates/plate-bumper-450x49-exploded.png) | 74,806 | 512 × 512 | `23d5b6d5cb7f127d63a408b7d6f76834c5ffbf88067caf449b686c18a6b320c3` | Procedural sprite |
| [plate-bumper-450x52-assembled.png](../../web/app/assets/plates/plate-bumper-450x52-assembled.png) | 55,647 | 512 × 512 | `6289213617fd6719a0a0b00f400a9dfac5281a8ba787e7430b8d41991b341f15` | Procedural sprite |
| [plate-bumper-450x52-exploded.png](../../web/app/assets/plates/plate-bumper-450x52-exploded.png) | 77,697 | 512 × 512 | `c96fee9d3e3eb94fd64bc93acb9699c8147619f0f99a938fd2c4641a2dcc80fb` | Procedural sprite |
| [plate-bumper-450x55-assembled.png](../../web/app/assets/plates/plate-bumper-450x55-assembled.png) | 55,913 | 512 × 512 | `24b0c62c374f8cef1bfd9ba637cbaf3d7cd4836cc10470bbec6242fd570bb548` | Procedural sprite |
| [plate-bumper-450x55-exploded.png](../../web/app/assets/plates/plate-bumper-450x55-exploded.png) | 76,846 | 512 × 512 | `20aa41f37663dd23006212b2fe77857b4e289967c621d10bf3e3580ab51ea442` | Procedural sprite |
| [plate-bumper-450x60-assembled.png](../../web/app/assets/plates/plate-bumper-450x60-assembled.png) | 58,070 | 512 × 512 | `86aa6914fe4f671dd7b79b2252c8e4a1d5887615fe978242febeea1e9189890c` | Procedural sprite |
| [plate-bumper-450x60-exploded.png](../../web/app/assets/plates/plate-bumper-450x60-exploded.png) | 78,666 | 512 × 512 | `db1612abe99e0d1a9ca4b2d59f790082b142ca2d017ea41755541215a5b77909` | Procedural sprite |
| [plate-bumper-450x65-assembled.png](../../web/app/assets/plates/plate-bumper-450x65-assembled.png) | 60,160 | 512 × 512 | `98b865fbce14457e9be0a54b4e75a2752260c4e217577a347fc449f4af8d4809` | Procedural sprite |
| [plate-bumper-450x65-exploded.png](../../web/app/assets/plates/plate-bumper-450x65-exploded.png) | 80,961 | 512 × 512 | `9d042bce5c4ed9dfd42443730017d17e64c2c335510bb0497d8b4f3f0d302d3b` | Procedural sprite |
| [plate-bumper-450x66-assembled.png](../../web/app/assets/plates/plate-bumper-450x66-assembled.png) | 59,962 | 512 × 512 | `59556b7d8536375e6ea8d86cbc1360368bffd2b980c4773920256f26194ad2aa` | Procedural sprite |
| [plate-bumper-450x66-exploded.png](../../web/app/assets/plates/plate-bumper-450x66-exploded.png) | 80,402 | 512 × 512 | `a1be0aa7ec4dfc1f3518523bb89e313c07e13adf88bb582ac0288c8b282f828b` | Procedural sprite |
| [plate-bumper-450x70-assembled.png](../../web/app/assets/plates/plate-bumper-450x70-assembled.png) | 62,329 | 512 × 512 | `78d79797acc9952f63fe6b4aade1dc1b506cdac44dcd2484ff551b36b276cc3d` | Procedural sprite |
| [plate-bumper-450x70-exploded.png](../../web/app/assets/plates/plate-bumper-450x70-exploded.png) | 82,898 | 512 × 512 | `ada25cbdff1530f2784140e968abd58d3085a418e54de8f7cd522d41277ae925` | Procedural sprite |
| [plate-bumper-450x75-assembled.png](../../web/app/assets/plates/plate-bumper-450x75-assembled.png) | 64,074 | 512 × 512 | `58026d23da4032973e6e0369a47ae133e4aefb0deeab5678bd2b9c5b50c9bba0` | Procedural sprite |
| [plate-bumper-450x75-exploded.png](../../web/app/assets/plates/plate-bumper-450x75-exploded.png) | 84,381 | 512 × 512 | `53739bf0757fa03a9077453e8d73373a2885090b32a791673a57dc8bd8af570c` | Procedural sprite |
| [plate-change-133x10-assembled.png](../../web/app/assets/plates/plate-change-133x10-assembled.png) | 40,829 | 512 × 512 | `d5e70bb2d49244d843705431b883a57fec77881f3b5e2da67c7920f81bc008fd` | Procedural sprite |
| [plate-change-133x10-exploded.png](../../web/app/assets/plates/plate-change-133x10-exploded.png) | 65,866 | 512 × 512 | `e7d6739420745eb6b6874805796c65b66e6b3e1c9775bb0429fe1ba244862ce2` | Procedural sprite |
| [plate-change-135x12-assembled.png](../../web/app/assets/plates/plate-change-135x12-assembled.png) | 41,224 | 512 × 512 | `0d47b9af3e5e815a9daaaed8e06fef9fa9b3191f293285713f4be9543eb820c9` | Procedural sprite |
| [plate-change-135x12-exploded.png](../../web/app/assets/plates/plate-change-135x12-exploded.png) | 66,530 | 512 × 512 | `1aa12ad3772ee769d19af81c7e17ca006ad79e90aa49b0938e2a36b7c01ac050` | Procedural sprite |
| [plate-change-135x12p5-assembled.png](../../web/app/assets/plates/plate-change-135x12p5-assembled.png) | 41,294 | 512 × 512 | `1dcbee5ae2bb1a982f0d6018593cc49e27f4f7f504fa69abd23ffb7353e08d32` | Procedural sprite |
| [plate-change-135x12p5-exploded.png](../../web/app/assets/plates/plate-change-135x12p5-exploded.png) | 66,728 | 512 × 512 | `e196b229591661f1f2e6dc322e34a9afefc0880652f3bc867fddfa908c5d42e1` | Procedural sprite |
| [plate-change-160x12-assembled.png](../../web/app/assets/plates/plate-change-160x12-assembled.png) | 41,434 | 512 × 512 | `8fa42d4031386d726d6c875664e4544b742920a1297eee977b1a262106d37200` | Procedural sprite |
| [plate-change-160x12-exploded.png](../../web/app/assets/plates/plate-change-160x12-exploded.png) | 68,334 | 512 × 512 | `54f75f242754305dad1f5a2f1e014146acc61794a3b2fabb3cf2c8b11851d549` | Procedural sprite |
| [plate-change-160x15-assembled.png](../../web/app/assets/plates/plate-change-160x15-assembled.png) | 41,771 | 512 × 512 | `7e9f2035a305948ec09af1b80be3d65fe61acc3f9a5e30e681bd59381be32cc7` | Procedural sprite |
| [plate-change-160x15-exploded.png](../../web/app/assets/plates/plate-change-160x15-exploded.png) | 69,082 | 512 × 512 | `e8d1103d434dd59c53bfafaad6e805549e055aa616dc4a94951bed6703ab939e` | Procedural sprite |
| [plate-change-160x16-assembled.png](../../web/app/assets/plates/plate-change-160x16-assembled.png) | 41,841 | 512 × 512 | `262a7fa2397cf8e7844ac6de4d6ba3fa610d6c421fc63a7159ab3c715dffc5d9` | Procedural sprite |
| [plate-change-160x16-exploded.png](../../web/app/assets/plates/plate-change-160x16-exploded.png) | 69,428 | 512 × 512 | `dfc6c0a2eaea83ef55f60f33fa0925ad12571da4314e18a28ff3227dac86e2f6` | Procedural sprite |
| [plate-change-162x15-assembled.png](../../web/app/assets/plates/plate-change-162x15-assembled.png) | 41,646 | 512 × 512 | `c369c817dfa0962351af4a67da1ae00c3a40ca8fb8838688549a03eff50599bc` | Procedural sprite |
| [plate-change-162x15-exploded.png](../../web/app/assets/plates/plate-change-162x15-exploded.png) | 69,055 | 512 × 512 | `48be088164a2d87a6478f07fb6724dbd6a39926d53d24e38bf148323adfe5e5a` | Procedural sprite |
| [plate-change-175x18-assembled.png](../../web/app/assets/plates/plate-change-175x18-assembled.png) | 42,054 | 512 × 512 | `b5e30f04b93e9cc90be70d9d36e9dc02016d03baa93ddeaf950d1d9d9490f6c9` | Procedural sprite |
| [plate-change-175x18-exploded.png](../../web/app/assets/plates/plate-change-175x18-exploded.png) | 69,753 | 512 × 512 | `07433e4c9e844370b51f8a146855ffbb35e060b42d8373b0ffab9a0540a58a9d` | Procedural sprite |
| [plate-change-190x19-assembled.png](../../web/app/assets/plates/plate-change-190x19-assembled.png) | 42,250 | 512 × 512 | `816821551371e0f737e6358f703506336f50b34754131d228ae7fb7f2af02a55` | Procedural sprite |
| [plate-change-190x19-exploded.png](../../web/app/assets/plates/plate-change-190x19-exploded.png) | 70,194 | 512 × 512 | `84e620c6272b447e0cf941e80f9c169ece1adce7a0d0bb5da5d8a74dfdb434c3` | Procedural sprite |
| [plate-change-210x19-assembled.png](../../web/app/assets/plates/plate-change-210x19-assembled.png) | 42,064 | 512 × 512 | `50afbef636a7e3f05ea4a2761f72b024f13a66a296ee38d5cbcb54e45d699453` | Procedural sprite |
| [plate-change-210x19-exploded.png](../../web/app/assets/plates/plate-change-210x19-exploded.png) | 70,372 | 512 × 512 | `6e1433a959b75871b444e4f0816335e00f2eaf8aaa08a72bf981030069c7e735` | Procedural sprite |
| [plate-change-230x26-assembled.png](../../web/app/assets/plates/plate-change-230x26-assembled.png) | 42,963 | 512 × 512 | `6a363b5528b1dabcb4729702935dca2eed554ccc4cafad6b3bc8a8c2d47239a0` | Procedural sprite |
| [plate-change-230x26-exploded.png](../../web/app/assets/plates/plate-change-230x26-exploded.png) | 71,386 | 512 × 512 | `c36e91b5f73c0529f49435388c3a149a1e3266519a22fcb4c3d3b13fb6db4755` | Procedural sprite |
| [plate-ipf-160x12-assembled.png](../../web/app/assets/plates/plate-ipf-160x12-assembled.png) | 33,033 | 512 × 512 | `d3ee45f1aba64f06341b2e6d927841691f8e266b8f7d8be6d1d1f28cb39f8e1f` | Procedural sprite |
| [plate-ipf-160x12-exploded.png](../../web/app/assets/plates/plate-ipf-160x12-exploded.png) | 46,648 | 512 × 512 | `3866d70613f4f49fce6fdec368fe023dc37200918c43a9627a92e27551cb2e05` | Procedural sprite |
| [plate-ipf-162x16-assembled.png](../../web/app/assets/plates/plate-ipf-162x16-assembled.png) | 34,789 | 512 × 512 | `e48bdcde2ced179ce8fe32325aed8f4fe05328228be570111460f504507ebd72` | Procedural sprite |
| [plate-ipf-162x16-exploded.png](../../web/app/assets/plates/plate-ipf-162x16-exploded.png) | 49,411 | 512 × 512 | `c1c5c14aa4247ba9d94510d2ba7f6ec5f207721328b7dd134687e6d2de4d3d7c` | Procedural sprite |
| [plate-ipf-190x16-assembled.png](../../web/app/assets/plates/plate-ipf-190x16-assembled.png) | 33,345 | 512 × 512 | `b514d7d1a3b39bcae30e7dc81bbe1cb44e420be05afa3e7eb08e3da2977b134b` | Procedural sprite |
| [plate-ipf-190x16-exploded.png](../../web/app/assets/plates/plate-ipf-190x16-exploded.png) | 47,300 | 512 × 512 | `91bd4f288e41b9a8320150ea6d7068f07408ab986827da183adce65997df933e` | Procedural sprite |
| [plate-ipf-195x21-assembled.png](../../web/app/assets/plates/plate-ipf-195x21-assembled.png) | 34,870 | 512 × 512 | `8ef426c93cd78d038293e462730fd2b4ecbc7ad1420ec8d82bc7d08947f8d61b` | Procedural sprite |
| [plate-ipf-195x21-exploded.png](../../web/app/assets/plates/plate-ipf-195x21-exploded.png) | 48,634 | 512 × 512 | `6bc1cb290713e858e3fd236e0033848e0b102e065777dcc5a6bde2a9105ef68f` | Procedural sprite |
| [plate-ipf-228x21p5-assembled.png](../../web/app/assets/plates/plate-ipf-228x21p5-assembled.png) | 33,797 | 512 × 512 | `42c8d5bf4722845ebddbf4fa970182685138298d8708ccf78240ee6686b49d37` | Procedural sprite |
| [plate-ipf-228x21p5-exploded.png](../../web/app/assets/plates/plate-ipf-228x21p5-exploded.png) | 47,682 | 512 × 512 | `0da34387aa6e9514e5086aa09d197e787bf249522033dec89744915202bc5eb5` | Procedural sprite |
| [plate-ipf-228x31-assembled.png](../../web/app/assets/plates/plate-ipf-228x31-assembled.png) | 35,837 | 512 × 512 | `ae5cab7750386315eb42729c88bd462587d82ed8bc5427e46fc2b382152b38db` | Procedural sprite |
| [plate-ipf-228x31-exploded.png](../../web/app/assets/plates/plate-ipf-228x31-exploded.png) | 49,128 | 512 × 512 | `44aca7f056595f80202d1fdbd9d9415cbf3cc267bea597ded9899714369f8350` | Procedural sprite |
| [plate-ipf-300x38-assembled.png](../../web/app/assets/plates/plate-ipf-300x38-assembled.png) | 33,372 | 512 × 512 | `7e42def8754a5bda2e03db823927001904b384bd6d9f623bfc1588d432563934` | Procedural sprite |
| [plate-ipf-300x38-exploded.png](../../web/app/assets/plates/plate-ipf-300x38-exploded.png) | 45,174 | 512 × 512 | `c11e335449be6a9ed7db17b8fa61fd6a171ced4b57ce87c6fe339f77794b98d1` | Procedural sprite |
| [plate-ipf-325x21-assembled.png](../../web/app/assets/plates/plate-ipf-325x21-assembled.png) | 30,821 | 512 × 512 | `ba1439f996514e800c2416c3f26288e553feb4d16c6d531b6f239b78be499a26` | Procedural sprite |
| [plate-ipf-325x21-exploded.png](../../web/app/assets/plates/plate-ipf-325x21-exploded.png) | 43,860 | 512 × 512 | `e0e7b001f5068ad4e0f02017cd9a6e2221057c77cd907ec5e00d28eed5d4dd0e` | Procedural sprite |
| [plate-ipf-360x38-assembled.png](../../web/app/assets/plates/plate-ipf-360x38-assembled.png) | 32,866 | 512 × 512 | `e514a682ea52ff84b03eed92a6a42ac9a0e2764bdf442dedbbf993d382bf72ca` | Procedural sprite |
| [plate-ipf-360x38-exploded.png](../../web/app/assets/plates/plate-ipf-360x38-exploded.png) | 45,342 | 512 × 512 | `0c312b7da04fa6b5af4362ba71e3b79a8b774942e38c1dff6bbe62d5966dded4` | Procedural sprite |
| [plate-ipf-400x21-assembled.png](../../web/app/assets/plates/plate-ipf-400x21-assembled.png) | 28,753 | 512 × 512 | `3ea026bd8acc3293294770dcfcd04c2e92380bc5e2cc4f1289c81793afbba450` | Procedural sprite |
| [plate-ipf-400x21-exploded.png](../../web/app/assets/plates/plate-ipf-400x21-exploded.png) | 40,799 | 512 × 512 | `4699066ab8468e30fa1c525a1f2ff1ca03197c65b4f3104b612991165146d846` | Procedural sprite |
| [plate-ipf-448x38-assembled.png](../../web/app/assets/plates/plate-ipf-448x38-assembled.png) | 30,329 | 512 × 512 | `fd033da4ec6a66f953abed53a0a04440ef8d0c7b8540106c5f3566b7434043f2` | Procedural sprite |
| [plate-ipf-448x38-exploded.png](../../web/app/assets/plates/plate-ipf-448x38-exploded.png) | 41,523 | 512 × 512 | `eca743726cad008712422f9d1178b276921b8f5e2f07d6db12e40c77337ec38f` | Procedural sprite |
| [plate-ipf-450x22p5-assembled.png](../../web/app/assets/plates/plate-ipf-450x22p5-assembled.png) | 28,654 | 512 × 512 | `cb39c6e5c61f1cf1fa1674aa607bf46bcbed193584292060aa8de8e4a691dbdc` | Procedural sprite |
| [plate-ipf-450x22p5-exploded.png](../../web/app/assets/plates/plate-ipf-450x22p5-exploded.png) | 41,302 | 512 × 512 | `f7d5f16a5214d7c5d8c1c49295871a90de6fb3a46ea5135729a2b2ef885459a1` | Procedural sprite |
| [plate-ipf-450x27-assembled.png](../../web/app/assets/plates/plate-ipf-450x27-assembled.png) | 29,614 | 512 × 512 | `f9e07ab0f0a3cca975d973f4ac37e1c044200852cb0901a9afda108505523fe8` | Procedural sprite |
| [plate-ipf-450x27-exploded.png](../../web/app/assets/plates/plate-ipf-450x27-exploded.png) | 42,656 | 512 × 512 | `47ecfeffb53d0122fc78eef9be37792165af0a0ff9559335aee792d650a39504` | Procedural sprite |
| [plate-iron-162x12-assembled.png](../../web/app/assets/plates/plate-iron-162x12-assembled.png) | 44,989 | 512 × 512 | `ca5e7e024aa185c0606a3ec4733f7558da7d084ba7a7b4ec778ff9e137b5ea26` | Procedural sprite |
| [plate-iron-162x12-exploded.png](../../web/app/assets/plates/plate-iron-162x12-exploded.png) | 67,186 | 512 × 512 | `a671f6c9d3b3210b653ffa72a21ec039007daae62c5a934eb18e5d53e10e2bf9` | Procedural sprite |
| [plate-iron-170x14-assembled.png](../../web/app/assets/plates/plate-iron-170x14-assembled.png) | 46,274 | 512 × 512 | `b3d3f36731630088d0af7243599eeae8b3bbd76e7125f3b34fe31d01d69bd5c0` | Procedural sprite |
| [plate-iron-170x14-exploded.png](../../web/app/assets/plates/plate-iron-170x14-exploded.png) | 69,638 | 512 × 512 | `5104ba05620b56cb8556aaa86291aae0c0ee5394242159a7aa0c68d26d5c78d4` | Procedural sprite |
| [plate-iron-190x14p5-assembled.png](../../web/app/assets/plates/plate-iron-190x14p5-assembled.png) | 44,768 | 512 × 512 | `e9e490fa044c30456e151de81bfab797514f2811be7b6e0aeb564988184ed0ed` | Procedural sprite |
| [plate-iron-190x14p5-exploded.png](../../web/app/assets/plates/plate-iron-190x14p5-exploded.png) | 67,621 | 512 × 512 | `e5ad7fbd3b5940df537c54220f490fb18091b877d087e3580b9c82f5f029d8ee` | Procedural sprite |
| [plate-iron-225x18-assembled.png](../../web/app/assets/plates/plate-iron-225x18-assembled.png) | 45,698 | 512 × 512 | `06f4e6f3df7f436e4874aed55319644429a30e88668c026df5b7560ab34a79bf` | Procedural sprite |
| [plate-iron-225x18-exploded.png](../../web/app/assets/plates/plate-iron-225x18-exploded.png) | 69,197 | 512 × 512 | `0a6a06d69fdc71102983bac1bc5dbc7bf5a03846f35dd54204a6dcbb891b6c51` | Procedural sprite |
| [plate-iron-229x20-assembled.png](../../web/app/assets/plates/plate-iron-229x20-assembled.png) | 45,220 | 512 × 512 | `cafaf8b0fc5c0c86a93926ab04c3ddff88c156280de9d1a74a44a21b01d30999` | Procedural sprite |
| [plate-iron-229x20-exploded.png](../../web/app/assets/plates/plate-iron-229x20-exploded.png) | 66,690 | 512 × 512 | `4f6dd66c74da175617c93e2396f5dbbab14783a08fbdb34f0e6895bdb05999ec` | Procedural sprite |
| [plate-iron-275x22-assembled.png](../../web/app/assets/plates/plate-iron-275x22-assembled.png) | 45,590 | 512 × 512 | `f0ba8028524918d0c0ad719e66e5ada2aaf8d08b3cf1301e56eb264434713a18` | Procedural sprite |
| [plate-iron-275x22-exploded.png](../../web/app/assets/plates/plate-iron-275x22-exploded.png) | 68,672 | 512 × 512 | `25f1e5391f9b42b6c81cabb81878ae24ab7fcda7381cd994ffd143ccbe285632` | Procedural sprite |
| [plate-iron-276x34p5-assembled.png](../../web/app/assets/plates/plate-iron-276x34p5-assembled.png) | 48,967 | 512 × 512 | `d3180f584a30d477b6e09576c692ddaeb3e5175c6f958a3e15a435cd3d6f366e` | Procedural sprite |
| [plate-iron-276x34p5-exploded.png](../../web/app/assets/plates/plate-iron-276x34p5-exploded.png) | 69,979 | 512 × 512 | `393f2b6a67877fef5495aff9ec271fe6ef73e57887d17e8273d8c0d1c00355f0` | Procedural sprite |
| [plate-iron-345x29-assembled.png](../../web/app/assets/plates/plate-iron-345x29-assembled.png) | 45,910 | 512 × 512 | `1571d41181daceeb0f6cbbc9cb1e9e957422f9b868dedab61785c3ab46070f1d` | Procedural sprite |
| [plate-iron-345x29-exploded.png](../../web/app/assets/plates/plate-iron-345x29-exploded.png) | 69,030 | 512 × 512 | `ef68ab083cd25d0d58a64e8266a032828a727170daeec33f73009c03abc8e8c7` | Procedural sprite |
| [plate-iron-360x34p5-assembled.png](../../web/app/assets/plates/plate-iron-360x34p5-assembled.png) | 45,619 | 512 × 512 | `57f22f60078d98448bca2faf3856d88419e5e329bd79004cb286efdbe0e87ac3` | Procedural sprite |
| [plate-iron-360x34p5-exploded.png](../../web/app/assets/plates/plate-iron-360x34p5-exploded.png) | 66,070 | 512 × 512 | `71be2c6f7b733cf1125480088a46f663556c86b46d65c2c1afae7f3294ed41b8` | Procedural sprite |
| [plate-iron-400x32-assembled.png](../../web/app/assets/plates/plate-iron-400x32-assembled.png) | 44,966 | 512 × 512 | `50f2e670325d8ec6ad093f3f436a3ff9b0f5974f3e85dbfcbf527f0c806b8c35` | Procedural sprite |
| [plate-iron-400x32-exploded.png](../../web/app/assets/plates/plate-iron-400x32-exploded.png) | 67,169 | 512 × 512 | `a8b362618a2960c0b146806c7356afef2f8834facac1c87ccd60b62169185530` | Procedural sprite |
| [plate-iron-450x36-assembled.png](../../web/app/assets/plates/plate-iron-450x36-assembled.png) | 45,146 | 512 × 512 | `4a0afbcb37e538400c8a7bd89336f504efb4e64d56b32d20526f69e79fbdbf08` | Procedural sprite |
| [plate-iron-450x36-exploded.png](../../web/app/assets/plates/plate-iron-450x36-exploded.png) | 67,536 | 512 × 512 | `1169c6bf0ae87c5f5e59b76aa638edbdaad657eaa55737de1baad4ab8b640726` | Procedural sprite |
| [plate-iron-450x50-assembled.png](../../web/app/assets/plates/plate-iron-450x50-assembled.png) | 47,796 | 512 × 512 | `5c6b1666a2867caeb74a9f19999b97418cbf309c3aece0ad2b5c9bd7a92ca782` | Procedural sprite |
| [plate-iron-450x50-exploded.png](../../web/app/assets/plates/plate-iron-450x50-exploded.png) | 69,208 | 512 × 512 | `49a1b1af8d46a78dfbf5ea35ccb58b460efe9534b67f87fe094ead2e8de0eb55` | Procedural sprite |
| [plate-machined-160x12-assembled.png](../../web/app/assets/plates/plate-machined-160x12-assembled.png) | 37,835 | 512 × 512 | `90099d32f6f3ff31e1a8907758e5bff55e0161a1bd5f8cd6e8443445e56b4ed8` | Procedural sprite |
| [plate-machined-160x12-exploded.png](../../web/app/assets/plates/plate-machined-160x12-exploded.png) | 55,377 | 512 × 512 | `1f7ac59969192410e770c3a1c6743f83138498a4d68c34b9cabc4650dce470d5` | Procedural sprite |
| [plate-machined-162x16-assembled.png](../../web/app/assets/plates/plate-machined-162x16-assembled.png) | 38,298 | 512 × 512 | `9c6d7699ac356431580763c06fe7d7a48675d9864d2aa0171751b6b91f86cd44` | Procedural sprite |
| [plate-machined-162x16-exploded.png](../../web/app/assets/plates/plate-machined-162x16-exploded.png) | 56,399 | 512 × 512 | `4d9354b0ae4f16c02a57a1ed5e54867b68f20b39b9e21ac5a1fa5640455d67e4` | Procedural sprite |
| [plate-machined-190x16-assembled.png](../../web/app/assets/plates/plate-machined-190x16-assembled.png) | 38,109 | 512 × 512 | `33283bbe73ebc7eab2f53d736a70d25c4e69e6bd49241a4a0f4658719905170b` | Procedural sprite |
| [plate-machined-190x16-exploded.png](../../web/app/assets/plates/plate-machined-190x16-exploded.png) | 55,564 | 512 × 512 | `912f660496b5bd95ede3eb7834dce22383310f85f03fb80b176aa8bd2197cf07` | Procedural sprite |
| [plate-machined-195x21-assembled.png](../../web/app/assets/plates/plate-machined-195x21-assembled.png) | 38,822 | 512 × 512 | `484391bd27a30d00b355835a118e2df3291f7ec9ce117ea86a5738646a824d43` | Procedural sprite |
| [plate-machined-195x21-exploded.png](../../web/app/assets/plates/plate-machined-195x21-exploded.png) | 56,316 | 512 × 512 | `e544674ad59b12c9764507b40a1cadf7fc6ec72cb1d1ec577238e40dc59b57ce` | Procedural sprite |
| [plate-machined-228x21p5-assembled.png](../../web/app/assets/plates/plate-machined-228x21p5-assembled.png) | 38,851 | 512 × 512 | `b06245deaa6f15023a3fa1ce19def85a64667ffd27c10b4882ea1a01bf3d57fd` | Procedural sprite |
| [plate-machined-228x21p5-exploded.png](../../web/app/assets/plates/plate-machined-228x21p5-exploded.png) | 56,736 | 512 × 512 | `03e4179b2433c15d8a37192cb0195762b1412aa5346900bf6fe7cf035307ed12` | Procedural sprite |
| [plate-machined-228x31-assembled.png](../../web/app/assets/plates/plate-machined-228x31-assembled.png) | 39,433 | 512 × 512 | `06d5633ec8cbc253d353180621452b5e1c8a8ba76c523b0a40ee64eda76d16b7` | Procedural sprite |
| [plate-machined-228x31-exploded.png](../../web/app/assets/plates/plate-machined-228x31-exploded.png) | 56,854 | 512 × 512 | `671faa8bb7d3ea07e9d54b2b1651adbf7e6355b44c35babe4dc1c0de64ea4b53` | Procedural sprite |
| [plate-machined-300x38-assembled.png](../../web/app/assets/plates/plate-machined-300x38-assembled.png) | 40,091 | 512 × 512 | `56dd536edf55db7be2c21cb18d3ed3052ba722e4528337a454ae6fcb436baa51` | Procedural sprite |
| [plate-machined-300x38-exploded.png](../../web/app/assets/plates/plate-machined-300x38-exploded.png) | 57,222 | 512 × 512 | `1462746130b99e5cf12d7c05bfb1e0ecc57d2eaa1506ea3cd5af77e30f9ba3cb` | Procedural sprite |
| [plate-machined-325x21-assembled.png](../../web/app/assets/plates/plate-machined-325x21-assembled.png) | 37,917 | 512 × 512 | `8c4de4ea41375c7b5bcbcca19dcf92cd13b466e4a97c39348c44d11b22e2ee29` | Procedural sprite |
| [plate-machined-325x21-exploded.png](../../web/app/assets/plates/plate-machined-325x21-exploded.png) | 54,099 | 512 × 512 | `4dee8bd5f08611f011e34fb084d50f4b279d5c53738d6d336597d15733970dbd` | Procedural sprite |
| [plate-machined-360x38-assembled.png](../../web/app/assets/plates/plate-machined-360x38-assembled.png) | 39,055 | 512 × 512 | `83ec7ebf7f92b54b2e122b6e01e6c3b7b5e56bf8cb345688950d74165c35602e` | Procedural sprite |
| [plate-machined-360x38-exploded.png](../../web/app/assets/plates/plate-machined-360x38-exploded.png) | 55,834 | 512 × 512 | `322b04dc605897bd1bca626828871de91b80715d4cbd67b7192871ba9eeb605e` | Procedural sprite |
| [plate-machined-400x21-assembled.png](../../web/app/assets/plates/plate-machined-400x21-assembled.png) | 37,507 | 512 × 512 | `e9b2d88249bfef6ce39d1c9366a8caf514564cfbea6c15237a08b1842b8b9ed9` | Procedural sprite |
| [plate-machined-400x21-exploded.png](../../web/app/assets/plates/plate-machined-400x21-exploded.png) | 54,503 | 512 × 512 | `e94818cde92dccd30eb79848fceb7852ccfbfd69ef37acc1aa68128202edb73b` | Procedural sprite |
| [plate-machined-448x38-assembled.png](../../web/app/assets/plates/plate-machined-448x38-assembled.png) | 38,349 | 512 × 512 | `c9c879c1c1b3a4992ca36b92663cef05e2d87abea78efd4fc7d7ac4cdb5fa3c0` | Procedural sprite |
| [plate-machined-448x38-exploded.png](../../web/app/assets/plates/plate-machined-448x38-exploded.png) | 53,788 | 512 × 512 | `4a69a2d11f2c9927ee626860ad2fb7ec4bf16e5d283754bc179329effea2454c` | Procedural sprite |
| [plate-machined-450x22p5-assembled.png](../../web/app/assets/plates/plate-machined-450x22p5-assembled.png) | 37,408 | 512 × 512 | `a5cf223ebfae5b4c2e249f88770e902d06137d077cb662165349167803caa13d` | Procedural sprite |
| [plate-machined-450x22p5-exploded.png](../../web/app/assets/plates/plate-machined-450x22p5-exploded.png) | 54,278 | 512 × 512 | `616226e863bdca24032c8cbcb6efcd8f09d882e62f9be6c6d492ece8250fa6d7` | Procedural sprite |
| [plate-machined-450x27-assembled.png](../../web/app/assets/plates/plate-machined-450x27-assembled.png) | 37,271 | 512 × 512 | `191dcd9c941d224f29bcda45245f38f39245a1cf45202d78e3102261e45f5fad` | Procedural sprite |
| [plate-machined-450x27-exploded.png](../../web/app/assets/plates/plate-machined-450x27-exploded.png) | 53,074 | 512 × 512 | `54ebef0dadd58f8539286a97957bc110f1c8396a3d01911bcd1768c4ac4fee11` | Procedural sprite |
| [plate-steel-230x20-assembled.png](../../web/app/assets/plates/plate-steel-230x20-assembled.png) | 42,281 | 512 × 512 | `5e5b2c310ecf550b21df75cf6bdf7b7683d420554ca388945d9a459813088b5d` | Procedural sprite |
| [plate-steel-230x20-exploded.png](../../web/app/assets/plates/plate-steel-230x20-exploded.png) | 70,628 | 512 × 512 | `45dcefe995e87533c53350a6add18ba1d9fe770050f47629531f61c54df12b04` | Procedural sprite |
| [plate-steel-325x20-assembled.png](../../web/app/assets/plates/plate-steel-325x20-assembled.png) | 41,805 | 512 × 512 | `6250f92fd97f12a948e8119a81e0a896507001b96e4323995ccd508d8b2ccd0e` | Procedural sprite |
| [plate-steel-325x20-exploded.png](../../web/app/assets/plates/plate-steel-325x20-exploded.png) | 69,977 | 512 × 512 | `7ca39e7566f100519702d9a5b88fb84361afe6d59ce720621faaf109ceea5eae` | Procedural sprite |
| [plate-steel-325x23-assembled.png](../../web/app/assets/plates/plate-steel-325x23-assembled.png) | 41,960 | 512 × 512 | `37c40c9fbc98d40ea285309e6526a09eaad02203107eb79ec9ce1b7df66b9129` | Procedural sprite |
| [plate-steel-325x23-exploded.png](../../web/app/assets/plates/plate-steel-325x23-exploded.png) | 70,070 | 512 × 512 | `ff690cf401fe9cc17f0de0290246766aa8b7bb2a1220698565940813588c5f1f` | Procedural sprite |
| [plate-steel-400x21-assembled.png](../../web/app/assets/plates/plate-steel-400x21-assembled.png) | 41,440 | 512 × 512 | `237ad6f550d97f9a1e48e7c21f6ed0eb11f75abec338c4fa9e813b20cd10035c` | Procedural sprite |
| [plate-steel-400x21-exploded.png](../../web/app/assets/plates/plate-steel-400x21-exploded.png) | 69,015 | 512 × 512 | `7bd43f80bc55d7681598687345794e3868765bf38bf157c74e12ee1c31213aea` | Procedural sprite |
| [plate-steel-400x25-assembled.png](../../web/app/assets/plates/plate-steel-400x25-assembled.png) | 41,667 | 512 × 512 | `cf71a0ae9c8dd51933bb3e2715e989f973064bde2fb0721efe9ed0ca2981e03f` | Procedural sprite |
| [plate-steel-400x25-exploded.png](../../web/app/assets/plates/plate-steel-400x25-exploded.png) | 69,520 | 512 × 512 | `5b647c49743caef2a18eb458bb5898a4d62f0dd79013625d4452a2ac6c569b4a` | Procedural sprite |
| [plate-steel-450x22-assembled.png](../../web/app/assets/plates/plate-steel-450x22-assembled.png) | 41,176 | 512 × 512 | `450e7bf103c45db8b29e493c241e5a116d5688f2d4e25909ac3416ebf4bbb5bc` | Procedural sprite |
| [plate-steel-450x22-exploded.png](../../web/app/assets/plates/plate-steel-450x22-exploded.png) | 68,950 | 512 × 512 | `e36b0ad0496917c3a3e5918a02715ce12a9e399b8a9cf1454ee160235fd81ea9` | Procedural sprite |
| [plate-steel-450x27-assembled.png](../../web/app/assets/plates/plate-steel-450x27-assembled.png) | 41,583 | 512 × 512 | `ee4d2e0aba1782f9fee563b5ed405d06b3f3758e14b77b01c36738b3ef22edff` | Procedural sprite |
| [plate-steel-450x27-exploded.png](../../web/app/assets/plates/plate-steel-450x27-exploded.png) | 69,040 | 512 × 512 | `bfcb33cfe5c4431e94df38249e6b0b8435736ae477485e0fa36fc494d45e15bb` | Procedural sprite |
| [plate-steel-450x30-assembled.png](../../web/app/assets/plates/plate-steel-450x30-assembled.png) | 41,797 | 512 × 512 | `7d8f0a75ad7ae4327c30f67c07ff6cfc395ca5009984535db81a869f01f02b08` | Procedural sprite |
| [plate-steel-450x30-exploded.png](../../web/app/assets/plates/plate-steel-450x30-exploded.png) | 69,248 | 512 × 512 | `b67b34ef429cdb500c23a08951f77d10cbd5b4634c894a2e18187f9dcb79570e` | Procedural sprite |
| [steel-face-detail.png](../../web/app/assets/plates/steel-face-detail.png) | 872,420 | 768 × 768 | `d5700b9e1079d2fecd7ea03cbf54707e3fc4003e748b284e9c46e5fb734be733` | Generated face detail (2026-09-20) |
