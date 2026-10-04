// Build optimized native/web twins from the inspected original Cadence artwork.
// Inputs are generated cutouts; this only resamples/compresses runtime assets.
import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve, join } from 'node:path';
import sharp from 'sharp';

const sources = process.argv.slice(2);
if (sources.length !== 3) throw new Error('Usage: install-equipment-context.mjs main.png accessory.png conditioning.png');
const root = fileURLToPath(new URL('../../', import.meta.url));
const web = join(root, 'web/app/assets/equipment-context');
await mkdir(web, { recursive: true });
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const assets = [];
for (const [index, category] of ['Main', 'Accessory', 'Conditioning'].entries()) {
  const source = await readFile(resolve(sources[index]));
  const metadata = await sharp(source).metadata();
  if (!metadata.hasAlpha) throw new Error(`${category} must retain transparency`);
  const name = category.toLowerCase();
  const path = join(web, `${name}.png`);
  await sharp(source).resize({ width: 768, height: 512, fit: 'inside', withoutEnlargement: true })
    .png({ compressionLevel: 9, adaptiveFiltering: true }).toFile(path);
  const bytes = await readFile(path);
  const native = `Cadence/Assets.xcassets/TrainingContext${category}.imageset`;
  await mkdir(join(root, native), { recursive: true });
  await copyFile(path, join(root, native, `${name}.png`));
  await writeFile(join(root, native, 'Contents.json'), JSON.stringify({
    images: [{ filename: `${name}.png`, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 }, properties: { 'template-rendering-intent': 'original' },
  }, null, 2) + '\n');
  const output = await sharp(bytes).metadata();
  assets.push({ category, file: `${name}.png`, native: `${native}/${name}.png`,
    width: output.width, height: output.height, bytes: bytes.length, sha256: sha256(bytes),
    sourceSHA256: sha256(source) });
}
await writeFile(join(web, 'manifest.json'), JSON.stringify({
  provenance: 'docs/design-pass/EQUIPMENT-CONTEXT.md', assets,
}, null, 2) + '\n');
console.log(JSON.stringify(assets));
