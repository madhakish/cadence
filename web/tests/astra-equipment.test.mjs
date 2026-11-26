// Every shipped surface has a reproducible catalog source and an offline URL.
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import sharp from 'sharp';
import { equipmentArtKind, faceFinish, platformPhoto, printedBumper } from '../app/js/plate-art.js';
import { PLATE_THEME_IDS, plateThemeSet } from '../app/js/plate-theme.js';

const catalog = new URL('../../Cadence/Assets.xcassets/', import.meta.url);
const directory = new URL('../app/assets/astra/', import.meta.url);
const sources = {
  'room.jpg': 'AstraStudioRoom', 'sleeve.png': 'AstraSleeve', 'chrome-roughness.png': 'AstraChromeRoughness',
  'main-context.jpg': 'AstraMainEquipmentContext', 'dumbbell.png': 'AstraDumbbell', 'hub.png': 'AstraPlateHub',
  'rubber.png': 'AstraPlateRubber', 'black-rubber.png': 'AstraPlateBlackRubber', 'powder.png': 'AstraPlatePowder',
  'gloss.png': 'AstraPlateGloss', 'cast-iron.png': 'AstraPlateCastIron', 'hammertone.png': 'AstraPlateHammertone',
  'machined.png': 'AstraPlateMachined',
};
for (const lb of [10, 25, 35, 45, 55]) sources[`bumper-${lb}lb.png`] = `AstraBumper${lb}lb`;
const worker = readFileSync(new URL('../app/sw.js', import.meta.url), 'utf8');
for (const [file, name] of Object.entries(sources)) {
  const folder = new URL(name + '.imageset/', catalog);
  const { images } = JSON.parse(readFileSync(new URL('Contents.json', folder)));
  const native = readFileSync(new URL(images.find(image => image.filename).filename, folder));
  assert.deepEqual(readFileSync(new URL(file, directory)), native, file + ' matches the shared native source');
}
const woods = ['oak', 'walnut', 'white-oak', 'maple'].map(name => 'platform-' + name + '.webp');
const grains = ["rubber", "black-rubber", "coating", "iron"].map(name => "grain-" + name + ".webp");
const files = readdirSync(directory);
assert.deepEqual(files.sort(), [...Object.keys(sources), ...woods, ...grains, 'room-band.webp'].sort());
assert.ok(!worker.includes('assets/plates/') && !worker.includes('plate-sprites.js'));
for (const file of files) assert.equal(worker.split(`"assets/astra/${file}"`).length - 1, 1, file + ' precaches once');
const floorBytes = await Promise.all(woods.map(async file => {
  const bytes = readFileSync(new URL(file, directory));
  const m = await sharp(bytes).metadata();
  assert.deepEqual([m.width, m.height, m.format], [1024, 1024, 'webp']);
  return bytes.toString('base64');
}));
assert.equal(new Set(floorBytes).size, woods.length, 'each panel has its own photograph');
assert.equal(platformPhoto('ipfCalibratedGloss'), 'platform-walnut.webp');
for (const theme of PLATE_THEME_IDS) {
  assert.ok(files.includes(platformPhoto(theme)));
  for (const style of ['bumper', 'steel']) for (const unit of ['lb', 'kg']) {
    for (const plate of [...plateThemeSet(unit, theme), { value: 1.125, unit }]) {
      assert.ok(files.includes(faceFinish(plate, theme, style) + '.png'));
      const printed = printedBumper(plate, theme, style);
      if (printed) {
        assert.equal(unit, 'lb');
        assert.ok(theme === 'lbColourBumpers' || (theme === 'custom' && style === 'bumper'));
        assert.equal(printed, `bumper-${plate.value}lb.png`);
        assert.ok(files.includes(printed));
      }
    }
  }
}
const kg20 = { value: 20, unit: 'kg' };
assert.deepEqual(['iwfTraining', 'ipfCalibrated', 'ipfCalibratedGloss', 'blackBumpersBand', 'lbBlackIron', 'lbGreyHammertone', 'lbMachinedSteel']
  .map(theme => faceFinish(kg20, theme, 'steel')), ['rubber', 'powder', 'gloss', 'black-rubber', 'cast-iron', 'hammertone', 'machined']);
console.log('Astra source twins, all finishes, physical platform maps and offline inventory passed');

assert.equal(equipmentArtKind({ type: 'barbell' }), 'barbell');
assert.equal(equipmentArtKind({ type: 'dumbbell' }), 'dumbbell');
assert.equal(equipmentArtKind({ type: 'barbell', loadBasis: 'totalBar' }, { loadBasis: 'perImplement' }), null);
assert.equal(equipmentArtKind({ type: 'barbell', loadBasis: 'bodyweight' }, { loadBasis: 'totalBar' }), 'barbell');
assert.equal(equipmentArtKind({ type: 'dumbbell' }, { loadBasis: 'totalBar' }), null);
assert.equal(equipmentArtKind({ type: 'machine' }, { loadBasis: 'totalBar' }), null);
