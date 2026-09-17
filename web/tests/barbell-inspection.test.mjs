import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { plateGeometry, barbellScene, plateTintGains } from '../app/js/barbell-scene.js';
const dom = new JSDOM('<html><body></body></html>', { url:'http://localhost/' });
global.document = dom.window.document;
const C = await import('../app/js/core.js');
const B = await import('../app/js/barbell.js');
const fixtures = JSON.parse(readFileSync(new URL('./fixtures/barbell-scene.json', import.meta.url), 'utf8'));
for (const fixture of fixtures) {
  assert.deepEqual(barbellScene(fixture.loadout, fixture.style, fixture.exploded), fixture.scene,
    'production web geometry matches the fixture consumed by Swift');
}
const counts = [45, 10, 25, 2.5].map(value => ({ plate:{ value,unit:'lb' }, count:1 }));
const solution = C.enteredPlateSolution(C.BARS.bar45lb, counts, 5);
const before = JSON.stringify(solution);
const closed = barbellScene(solution, 'bumper', false);
const open = barbellScene(solution, 'bumper', true);
const compact = B.barbellSVG(solution, 'compact', 'bumper');
assert.deepEqual(compact.scene, closed, 'compact and full presentations use identical physical geometry');
assert.equal(compact.svg.querySelectorAll('image.barbell-plate-face').length, closed.discs.length);
assert.equal(compact.svg.querySelectorAll('[data-side="left"]').length, counts.length);
assert.equal(compact.svg.getAttribute('role'), 'group', 'the SVG does not hide its plate accessibility children');
assert.match(compact.svg.getAttribute('aria-label'), /Assembled loaded bar,.*per side/);
for (const plate of compact.svg.querySelectorAll('.barbell-plate-body')) {
  assert.equal(plate.getAttribute('tabindex'), '0');
  assert.equal(plate.getAttribute('role'), 'img');
  assert.equal(plate.getAttribute('aria-label'),
    `${plate.dataset.plateDenomination} plate, ${Number(plate.dataset.stackIndex)+1} from inside, ${plate.dataset.side} side`);
}
const tints = JSON.parse(readFileSync(new URL('./fixtures/plate-tints.json', import.meta.url), 'utf8'));
for (const {token, gains} of tints) assert.deepEqual(plateTintGains(token), gains);
for (const matrix of compact.svg.querySelectorAll('feColorMatrix')) {
  const token = matrix.parentNode.id.split('-').at(-1);
  const values = matrix.getAttribute('values').split(' ').map(Number);
  assert.deepEqual([values[0],values[6],values[12]], plateTintGains(token));
}
assert.ok([...compact.svg.querySelectorAll('.barbell-plate-hub')].every(hub=>!hub.hasAttribute('filter')),
  'the photographic hub keeps its original metal color');
assert.deepEqual(open.discs.filter(d=>d.side===1).map(d=>d.plate.value), [45,10,25,2.5]);
assert.deepEqual(open.discs.map(d=>d.radius), closed.discs.map(d=>d.radius));
assert.ok(open.width > closed.width);
for (let i = 1; i < open.discs.length; i++) {
  const left = open.discs[i-1], right = open.discs[i];
  assert.ok(right.x - right.faceRadius - right.depth/2 - (left.x + left.faceRadius + left.depth/2) >= 22 - 1e-8,
    'exploded change plates remain visible beside larger plates on either side');
}
for (const d of open.discs) {
  const mirror = open.discs.find(m => m.side === -d.side && m.index === d.index);
  assert.equal(mirror.x, -d.x);
  assert.equal(mirror.radius, d.radius);
  assert.ok(Math.abs(d.x)+d.faceRadius+d.depth < open.width/2);
}
const five = { value:5, unit:'kg' };
assert.equal(plateGeometry(five,'bumper').diameter,450);
assert.equal(plateGeometry(five,'steel').diameter,230);
const mixed = barbellScene(C.enteredPlateSolution(C.BARS.bar20kg,[{plate:five,count:1}]), 'bumper', true,
  { '5-kg': { diameter:230, thickness:20 } });
assert.equal(mixed.discs[0].radius,230*.18);
let calls=0;
const stage = B.barbellStage(B.barbellSVG(solution,'full','bumper'), {onExpand:()=>calls++,containerWidth:390});
assert.equal(stage.querySelector('.barbell-stage-footer .sub').textContent, 'Tap to inspect');
assert.equal(stage.querySelector('.barbell-expand').textContent, 'Larger view ↗');
stage.querySelector('.barbell-expand').click();
assert.equal(calls,1);
const inspector = B.barbellStage(B.barbellSVG(solution,'full','bumper'), {emphasis:'expanded'});
assert.equal(inspector.querySelector('svg.realistic').dataset.exploded,'true');
assert.equal(inspector.querySelector('.barbell-stage-track').style.getPropertyValue('--barbell-natural-width'), `${open.width}px`);
for (const label of inspector.querySelectorAll('.barbell-plate-label')) {
  assert.equal(label.getAttribute('font-size'), '14');
  assert.equal(label.hasAttribute('textLength'), false);
}
assert.equal(inspector.querySelectorAll('.barbell-stack-list li').length,4);
const toggle = inspector.querySelector('.barbell-explode');
toggle.click();
assert.equal(inspector.querySelector('svg.realistic').dataset.exploded,'false');
assert.equal(toggle.getAttribute('aria-pressed'),'false');
toggle.click();
assert.equal(inspector.querySelector('svg.realistic').dataset.exploded,'true');
assert.equal(JSON.stringify(solution), before);
const firstIDs=[...inspector.querySelectorAll('[id]')].map(x=>x.id);
const secondIDs=[...B.barbellSVG(solution,'full').svg.querySelectorAll('[id]')].map(x=>x.id);
assert.ok(!secondIDs.some(id=>firstIDs.includes(id)), 'multiple views never collide in SVG paint-server IDs');
assert.equal(inspector.querySelectorAll('.barbell-lock-collar').length,2);
const worker=readFileSync(new URL('../app/sw.js',import.meta.url),'utf8');
for (const asset of ['js/barbell-scene.js','assets/plate-steel.png','assets/plate-bumper.png']) assert.ok(worker.includes(`"${asset}"`));
console.log('Barbell inspection geometry, identity, controls, and offline assets passed');
