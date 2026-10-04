import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import sharp from 'sharp';

test('original equipment assets retain transparent native/web twins within the offline budget', async () => {
  const root = new URL('../../', import.meta.url);
  const directory = new URL('web/app/assets/equipment-context/', root);
  const manifest = JSON.parse(await readFile(new URL('manifest.json', directory), 'utf8'));
  assert.deepEqual(manifest.assets.map((a) => a.category), ['Main', 'Accessory', 'Conditioning']);
  const worker = await readFile(new URL('web/app/sw.js', root), 'utf8');
  let total = 0;
  for (const asset of manifest.assets) {
    const bytes = await readFile(new URL(asset.file, directory));
    assert.deepEqual(bytes, await readFile(new URL(asset.native, root)));
    assert.equal(bytes.length, asset.bytes);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), asset.sha256);
    const { data, info } = await sharp(bytes).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    assert.deepEqual([info.width, info.height, info.channels], [768, 512, 4]);
    const alpha = data.filter((_, i) => i % 4 === 3);
    assert.ok(alpha.includes(0) && alpha.some((value) => value > 200));
    assert.equal(alpha[0], 0); assert.equal(alpha.at(-1), 0);
    assert.ok(worker.includes(`"assets/equipment-context/${asset.file}"`));
    total += bytes.length;
  }
  assert.ok(total < 1_000_000, `Equipment family is ${total} bytes`);
  assert.ok(worker.includes('"js/equipment-context.js"'));
});
