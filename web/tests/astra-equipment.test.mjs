import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import sharp from 'sharp';
import { equipmentArtKind, faceFinish } from '../app/js/plate-art.js';
import { facePhoto, edgePhoto, stageForTheme } from '../app/js/barbell-photo.js';
import { PLATE_THEME_IDS, plateThemeSet } from '../app/js/plate-theme.js';

const catalog = new URL('../../Cadence/Assets.xcassets/', import.meta.url);
const directory = new URL('../app/assets/photo/', import.meta.url);
const files = readdirSync(directory).sort();
const worker = readFileSync(new URL('../app/sw.js', import.meta.url), 'utf8');
const bytesAt = (dir, file) => readFileSync(new URL(file, dir));
const matchesNative = (bytes, name) => {
  const folder = new URL(name + '.imageset/', catalog);
  const { images } = JSON.parse(bytesAt(folder, 'Contents.json'));
  assert.deepEqual(bytes, bytesAt(folder, images.find(i => i.filename).filename), name + ' shares native original');
};
const required = new Set(['PhotoLock.png', 'PhotoHubWarm.png', 'PhotoBrand.png', 'PhotoMark45lb.png', 'PhotoMark15kg.png', 'PhotoMark20kg.png', 'PhotoHub.png', 'PhotoShaft.png', 'PhotoSleeve.png', 'PhotoShoulder.png', 'PhotoCollar.png', 'PhotoEndcap.png']);
for (const theme of PLATE_THEME_IDS) {
  required.add(stageForTheme(theme) + '.jpg');
  for (const style of ['bumper', 'steel']) for (const unit of ['lb', 'kg'])
    for (const plate of [...plateThemeSet(unit, theme), { value: 1.125, unit }]) {
      const finish = faceFinish(plate, theme, style);
      required.add(facePhoto(finish) + '.png');
      required.add(edgePhoto(finish) + '.png');
    }
}
assert.deepEqual(files, [...required].sort());
for (const file of files) {
  const bytes = bytesAt(directory, file);
  matchesNative(bytes, file.split('.')[0]);
  const meta = await sharp(bytes).metadata();
  assert.ok(meta.width > 0 && meta.height > 0);
  assert.equal(worker.split(`"assets/photo/${file}"`).length - 1, 1, file + ' precaches once');
}
for (const [name, file] of [['AstraMainEquipmentContext', 'main-context.jpg'], ['AstraDumbbell','dumbbell.png']]) {
  matchesNative(bytesAt(new URL('../app/assets/astra/', import.meta.url), file), name);
}
assert.ok(!worker.includes('assets/plates/') && !worker.includes('barbell-gl.js'));
console.log('Shared native photographs for every theme, actual stage, hardware and offline inventory passed');
assert.equal(equipmentArtKind({ type: 'barbell' }), 'barbell');
assert.equal(equipmentArtKind({ type: 'dumbbell' }), 'dumbbell');
assert.equal(equipmentArtKind({ type: 'barbell', loadBasis: 'totalBar' }, { loadBasis: 'perImplement' }), null);
assert.equal(equipmentArtKind({ type: 'barbell', loadBasis: 'bodyweight' }, { loadBasis: 'totalBar' }), 'barbell');
assert.equal(equipmentArtKind({ type: 'dumbbell' }, { loadBasis: 'totalBar' }), null);
assert.equal(equipmentArtKind({ type: 'machine' }, { loadBasis: 'totalBar' }), null);
