import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import * as C from '../app/js/core.js';
import { photographicBar, stagePoint, stageForTheme } from '../app/js/barbell-photo.js';

globalThis.document = new JSDOM('<!doctype html><body>').window.document;
const near = stagePoint(-765), far = stagePoint(705);
assert.deepEqual([near.x, near.y, near.scale * 450], [357, 446, 409]);
assert.deepEqual([far.x, far.y, Math.round(far.scale * 450)], [1351, 332, 321]);
assert.deepEqual([stagePoint(-1120).x, stagePoint(-1120).y], [66, 480]);
assert.deepEqual([stagePoint(1120).x, stagePoint(1120).y], [1550, 315]);
for (const [theme, wood] of [['ipfCalibrated', 'Walnut'], ['blackBumpersBand', 'WhiteOak'], ['iwfTraining', 'Maple'], ['custom', '']])
  assert.equal(stageForTheme(theme), 'AstraPhotoStage' + wood);

const load = C.enteredPlateSolution(C.BARS.bar45lb, [
  { plate: { value: 45, unit: 'lb' }, count: 2 }, { plate: { value: 1.125, unit: 'kg' }, count: 1 },
], 5);
for (const explode of [false, true]) {
  const { svg, scene } = photographicBar(load, 'bumper', explode);
  assert.deepEqual(scene.discs.filter(d => d.side < 0).map(d => C.plateLabel(d.plate)), ['45 lb','45 lb','1.125 kg']);
  for (const selector of ['.barbell-plate-rim','.barbell-plate-face','.barbell-plate-hub'])
    assert.equal(svg.querySelectorAll(selector).length, explode ? 3 : 6);
  assert.equal(svg.querySelectorAll('.barbell-endcap').length, 1);
  assert.equal(svg.querySelectorAll('.barbell-collar-near').length, 1);
  assert.ok(svg.querySelector('.barbell-collar-near').getAttribute('href').endsWith(explode ? '/PhotoCollar.png' : '/PhotoLock.png'));
  assert.equal(svg.querySelectorAll('.barbell-collar').length, explode ? 0 : 1);
  assert.ok([...svg.querySelectorAll('image')].every(n => n.getAttribute('href').includes('/assets/photo/')));
  const near = scene.discs.filter(d => d.side < 0);
  if (explode) {
    for (let i=1; i < near.length; i++)
      assert.ok(near[i].back.x + near[i].rx < near[i-1].x - near[i-1].rx, 'adjacent exploded rims have visible air');
  } else {
    assert.ok(near[1].ry > near[0].ry, 'the closer of two identical bumpers appears larger');
    const art = [...svg.querySelectorAll('image')];
    const order = selector => art.findIndex(n => n.matches(selector));
    assert.ok(order('.barbell-sleeve') < order('.barbell-plate-face'));
    const sleeve = svg.querySelector('.barbell-exposed-sleeve');
    assert.ok(order('.barbell-exposed-sleeve') > order('.barbell-collar-near'), 'chrome passes through the lock opening');
    assert.ok(order('.barbell-exposed-sleeve') > art.findLastIndex(n => n.matches('.barbell-plate-face')));
    assert.equal(sleeve.getAttribute('transform'), svg.querySelector('.barbell-sleeve-near').getAttribute('transform'), 'reflections remain continuous');
    assert.ok(sleeve.parentElement.hasAttribute('clip-path'));
  }
}
const bare = C.enteredPlateSolution(C.BARS.bar15kg, []);
const view = photographicBar(bare, 'steel');
assert.equal(view.scene.discs.length, 0);
assert.equal(view.svg.querySelectorAll('.barbell-collar, .barbell-collar-near').length, 0);
assert.ok(view.scene.point(0).y > stagePoint(0).y, 'the bare bar rests on the platform');
console.log('Photographic camera registration, per-disc photographic materials, hardware occlusion and exact exploded ordering passed');
