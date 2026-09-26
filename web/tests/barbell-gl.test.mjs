// The WebGL inspector's pure parts: lathe meshes from the shared profiles,
// the camera fit rule, and the graceful no-WebGL path the DOM tests take.
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!doctype html><html><body></body></html>');
globalThis.window = dom.window; globalThis.document = dom.window.document;
const C = await import('../app/js/core.js');
const { latheMesh, cylinderMesh, fitDistance, barbellGL, FIELD_OF_VIEW } = await import('../app/js/barbell-gl.js');
const { plateProfile, barbellLayout } = await import('../app/js/barbell-inspector.js');

const profile = plateProfile('bumper', 450, 60);
const mesh = latheMesh(profile, 24, 2);
const edges = profile.length - 1;
assert.equal(mesh.positions.length / 3, edges * 2 * 25, 'two rings of segments+1 vertices per profile edge');
assert.equal(mesh.indices.length, edges * 24 * 6, 'two triangles per segment per edge');
assert.equal(mesh.hubCount, 4 * 24 * 6, 'the first and last two edges are the hub insert');
assert.equal(mesh.hubCount + mesh.bodyCount, mesh.indices.length);
for (let i = 0; i < mesh.normals.length; i += 3) {
  const l = Math.hypot(mesh.normals[i], mesh.normals[i + 1], mesh.normals[i + 2]);
  assert.ok(Math.abs(l - 1) < 1e-6, 'unit normals');
}
// The −x face ring points −x; the rim points radially outward.
assert.ok(mesh.normals[0] < -0.99, 'front face normal faces the viewer side');
const rimEdge = profile.findIndex(([r], i) => i > 0 && Math.abs(r - 225) < 1e-9 && Math.abs(profile[i + 1]?.[0] - 225) < 1e-9);
const rimVertex = rimEdge * 2 * 25 * 3;
assert.ok(Math.abs(mesh.normals[rimVertex]) < 1e-6 && mesh.normals[rimVertex + 1] > 0.99, 'rim normal is radial at theta 0');
assert.ok(Math.max(...mesh.indices) < mesh.positions.length / 3, 'indices stay inside the vertex buffer');

const cyl = cylinderMesh(14, 1370, 12);
assert.equal(cyl.hubCount, 0);
assert.equal(cyl.positions.length / 3, 3 * 2 * 13);

const counts = [{ plate: { value: 45, unit: 'lb' }, count: 1 }];
const solution = C.enteredPlateSolution(C.BARS.bar45lb, counts, 5);
const layout = barbellLayout(solution, 'steel', 0);
const whole = { halfWidth: layout.extent, maxRadius: layout.maxRadius };
const phone = fitDistance(whole, 390 / 300), wide = fitDistance(whole, 1280 / 300);
assert.ok(phone > wide, 'a narrower viewport needs a farther camera to fit the bar');
assert.ok(phone > layout.extent, 'the eye sits outside the bar');
const yawed = fitDistance(whole, 1280 / 300, 38), endOn = fitDistance(whole, 1280 / 300, 90);
assert.ok(yawed > wide && yawed > layout.extent * Math.sin(38 * Math.PI / 180) + layout.maxRadius, 'a yawed bar backs the camera off by its reach toward the eye');
assert.ok(endOn - layout.extent > layout.maxRadius * 1.7 / Math.tan(FIELD_OF_VIEW / 2 * Math.PI / 180) - 1e-9, 'looking down the bar, the near plate still fits the frame');

const gl = barbellGL(solution, 'steel', { exploded: true });
assert.equal(gl.supported, false, 'jsdom has no WebGL2, so the stage keeps the sprite SVG');
assert.ok(gl.canvas instanceof dom.window.HTMLCanvasElement);
console.log('Barbell WebGL inspector: lathe meshes, camera fit, and no-WebGL fallback passed');
