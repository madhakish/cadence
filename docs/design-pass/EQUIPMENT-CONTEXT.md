# Original equipment context — 1 October 2026

Three transparent product cutouts extend the existing exact-load plate family
for #198. They provide category context; adjacent text retains the category,
count, state and action. No image represents a prescribed mass or teaches an
exercise. Images never sit behind essential text. The original gorilla artwork
was neither an input nor regenerated.

| Asset | Subject | Runtime bytes | Native / web consuming surfaces |
| --- | --- | ---: | --- |
| `main.png` | Unloaded rack, bar, collars and oak platform | 227,515 | Main Library category; empty Program |
| `accessory.png` | Cast-iron dumbbell pair and kettlebell | 445,560 | Accessory Library category; unlogged accessory detail |
| `conditioning.png` | Unloaded push sled and farmer-carry frames | 280,369 | Conditioning Library category; unlogged conditioning detail |

All runtime files are **768 × 512 RGBA**, with byte-identical native and web
copies. Combined web payload is **953,444 bytes**. The generated source
cutouts were 1536 × 1024. The category presentation reserves 96 × 64 logical
points/pixels; empty detail and Program reserve 160 and 200 wide respectively
with the same aspect ratio. Native category artwork yields its space to text
at accessibility sizes. Narrow web categories wrap onto a reserved image row.
The image is decorative for screen readers; category/state text remains the
accessible explanation. No async decode can change its declared geometry.

## Source and rights

Generated specifically for Cadence using the built-in `image_gen` tool on
1 October 2026. The Main cutout established the material/lighting reference;
Accessory and Conditioning referenced that equipment artwork only. Each
received a separate background-extraction edit to remove the studio backdrop
while preserving the implements. No manufacturer photo, stock asset, logo,
weight stamp or gorilla source was used. Equipment geometry is illustrative,
not a certification or manufacturer dimension claim.

The repository [LICENSE](../../LICENSE) reserves all rights to madhakish;
these assets are included under that repository policy. No third-party stock
license or manufacturer endorsement is claimed.

[Generation record](EQUIPMENT-CONTEXT-GENERATION.json) retains the creation
prompts, source/output hashes and the extraction-stage brief summary.
[Runtime manifest](../../web/app/assets/equipment-context/manifest.json) lists
every installed file, native twin, dimensions, size and SHA-256.
[`install-equipment-context.mjs`](../../web/tools/install-equipment-context.mjs)
only resamples/compresses inspected cutouts using Sharp. It preserves alpha
and copies identical bytes into the native catalog. Runtime images and their
module ship locally and are included in the production service-worker shell.

## Verification status

The original cutouts and extracted images were visually inspected before
integration. Runtime screenshot and browser/offline verification are pending
for this implementation. The capture matrix adds category and unlogged-detail
states plus an empty Program; the native DEBUG fixture uses an in-memory
container, and exports the canonical matrix before introducing empty states.
The browser acceptance case delays all three image requests, compares category
geometry before/after decode, exercises edge widths/CSS zoom with reduced
motion, then disconnects the transport and reopens the production worker.
These checks do not establish physical-device or manual zoom acceptance.
