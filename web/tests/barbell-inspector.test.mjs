// Shared 3D inspector model: physical bar/plate layout with an explode
// fraction, two authored cameras, and lathe profiles. Mirrored in
// CadenceCore/BarbellInspector.swift; the fixture pins both clients.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as C from '../app/js/core.js';
import { barbellLayout, inspectorCamera, inspectorFrame, cameraOrbitPosition, plateProfile }
  from '../app/js/barbell-inspector.js';
import * as Inspector from '../app/js/barbell-inspector.js';

const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-9, `${msg}: ${a} vs ${b}`);
const counts = [{ plate: { value: 45, unit: 'lb' }, count: 2 }, { plate: { value: 10, unit: 'lb' }, count: 1 }];
const solution = C.enteredPlateSolution(C.BARS.bar45lb, counts, 5);

// Layout is physical millimetres from the bar's centre, mirrored on both sides.
const closed = barbellLayout(solution, 'steel', 0);
assert.equal(closed.discs.length, 6);
assert.equal(closed.bar.shaftHalfLength, 685);
assert.equal(closed.bar.sleeveLength, 415);
assert.equal(closed.bar.shaftRadius, 14);
assert.equal(closed.bar.sleeveRadius, 25);
const right = closed.discs.filter((d) => d.side > 0).sort((a, b) => a.index - b.index);
const first = right[0];
near(first.centerX, closed.bar.shoulderEnd + first.thickness / 2, 'first plate sits against the shoulder');
near(right[1].centerX, first.centerX + first.thickness / 2 + right[1].thickness / 2, 'assembled plates touch');
for (const d of closed.discs) {
  const mirror = closed.discs.find((m) => m.index === d.index && m.side === -d.side);
  near(mirror.centerX, -d.centerX, 'mirrored stack');
  assert.equal(mirror.radius, d.radius);
  assert.equal(d.family, 'steel');
}
near(closed.collar.right, right[2].centerX + right[2].thickness / 2, 'lock collar follows the outer plate');
assert.equal(closed.collar.length, 50);

// Explode fraction spreads plates outward by index and carries the collar.
const open = barbellLayout(solution, 'steel', 1);
const openRight = open.discs.filter((d) => d.side > 0).sort((a, b) => a.index - b.index);
near(openRight[0].centerX, first.centerX, 'the first plate stays against the shoulder');
near(openRight[2].centerX, right[2].centerX + 2 * (2 * closed.maxRadius * 1.3 + 24), 'the third plate moves two gaps');
const half = barbellLayout(solution, 'steel', 0.5);
near(half.discs.find((d) => d.side > 0 && d.index === 2).centerX, right[2].centerX + (2 * closed.maxRadius * 1.3 + 24), 'the fraction interpolates');
near(open.collar.right, openRight[2].centerX + openRight[2].thickness / 2 + 80, 'the collar separates only enough to be visible');
const halfOuter = half.discs.find((d) => d.side > 0 && d.index === 2);
near(half.collar.right, halfOuter.centerX + halfOuter.thickness / 2 + 40, 'collar separation interpolates continuously');
assert.ok(open.collar.right > closed.collar.right && open.extent >= closed.extent, 'exploding never shrinks the scene');
assert.equal(closed.extent, 685 + 415, 'a stack that fits the sleeve keeps the bar length as the extent');
assert.equal(barbellLayout(C.enteredPlateSolution(C.BARS.bar15kg, [], 5), 'bumper', 0).bar.sleeveLength, 320);
assert.equal(barbellLayout(C.enteredPlateSolution(C.BARS.bar35lb, [], 5), 'bumper', 0).bar.shaftRadius, 12.5);
assert.equal(JSON.stringify(solution), JSON.stringify(C.enteredPlateSolution(C.BARS.bar45lb, counts, 5)), 'layout never mutates the solution');

// Only two authored camera endpoints; no user-controlled camera state.
assert.deepEqual(inspectorCamera(true), { yaw: 50, pitch: 10, zoom: 1 });
assert.deepEqual(inspectorCamera(false), { yaw: 8, pitch: 6, zoom: 1 });
const eye = cameraOrbitPosition(inspectorCamera(false), 1000);
near(Math.hypot(eye.x, eye.y, eye.z), 1000, 'eye sits on the camera sphere');
assert.ok(eye.x < 0 && eye.z > 0 && eye.y > 0, 'default eye is at the −x end, in front, above');
near(cameraOrbitPosition({ yaw: 90, pitch: 0, zoom: 1 }, 10).x, -10, 'yaw 90 looks straight down the bar');
near(cameraOrbitPosition({ yaw: 0, pitch: 0, zoom: 1 }, 10).z, 10, 'yaw 0 is side-on');

// Both states frame the near sleeve; the assembled frame also shows shaft.
const closedFrame = inspectorFrame(closed, 0), openFrame = inspectorFrame(open, 1), midFrame = inspectorFrame(half, 0.5);
assert.ok(closedFrame.target.x < -closed.bar.shaftHalfLength, 'assembled camera already focuses on the near sleeve');
assert.ok(closedFrame.halfWidth < closed.extent * .6, 'assembled camera does not waste its width on the opposite sleeve');
assert.ok(closedFrame.target.x + closedFrame.halfWidth > -closed.bar.shaftHalfLength + 200, 'assembled view retains enough shaft to read as a barbell');
assert.ok(openFrame.target.x < -closed.bar.shaftHalfLength && openFrame.target.x > -open.extent, 'exploded frames the centre of the near stack');
assert.ok(openFrame.target.x - openFrame.halfWidth < open.collar.left - open.collar.length, 'exploded frame includes the outside collar');
assert.ok(midFrame.target.x < closedFrame.target.x && midFrame.target.x > openFrame.target.x, 'frame follows the plates continuously');
const empty = barbellLayout(C.enteredPlateSolution(C.BARS.bar15kg, [], 0), 'bumper', 0);
const emptyFrame = inspectorFrame(empty, 0);
assert.ok(emptyFrame.target.x - emptyFrame.halfWidth <= -empty.bar.shaftHalfLength - empty.bar.sleeveLength, 'empty sleeve is not clipped');
assert.deepEqual(barbellLayout(solution, 'steel', -1), closed, 'negative explode fractions clamp to assembled');
assert.deepEqual(barbellLayout(solution, 'steel', 2), open, 'overshooting animation clamps to exploded');

// Sparse stacks inspect the actual plates, without reserving an invisible
// collar or moving the first plate off the sleeve into empty space.
for (const count of [1, 2]) {
  const sparse = C.enteredPlateSolution(C.BARS.bar45lb, [{ plate: { value: 45, unit: 'lb' }, count }], 0);
  const shut = barbellLayout(sparse, 'steel', 0), spread = barbellLayout(sparse, 'steel', 1);
  const closedView = inspectorFrame(shut, 0), openView = inspectorFrame(spread, 1);
  const discs = spread.discs.filter((d) => d.side < 0);
  near(discs[0].centerX, shut.discs[0].centerX, 'first sparse plate remains against the shoulder');
  near(spread.collar.left, discs.at(-1).centerX - discs.at(-1).thickness / 2, 'absent collar reserves no additional gap');
  assert.equal(spread.collar.length, 0, 'absent collar has no visible length');
  assert.equal(spread.collar.radius, 0, 'absent collar has no visible radius');
  assert.ok(openView.halfWidth * Math.cos(inspectorCamera(true).yaw * Math.PI / 180)
    < closedView.halfWidth * Math.cos(inspectorCamera(false).yaw * Math.PI / 180), 'sparse inspection has a tighter projected frame');
  if (count === 1) assert.ok(openView.halfWidth < closedView.halfWidth * .5, 'single plate gets a close frame');
}
const emptyOpen = barbellLayout(C.enteredPlateSolution(C.BARS.bar15kg, [], 0), 'bumper', 1);
assert.equal(emptyOpen.collar.left, -emptyOpen.bar.shoulderEnd, 'empty bar does not explode a phantom collar');
assert.ok(inspectorFrame(emptyOpen, 1).target.x - inspectorFrame(emptyOpen, 1).halfWidth <= -emptyOpen.bar.shaftHalfLength - emptyOpen.bar.sleeveLength, 'empty inspection still frames the physical sleeve');

// Every projected face clears its neighbour at the authored inspection angle,
// including large custom plates; labels retain width instead of shrinking.
for (const geometry of [{}, { '45-lb': { diameter: 600, thickness: 30 } }]) {
  const layout = barbellLayout(solution, 'bumper', 1, geometry);
  const discs = layout.discs.filter((d) => d.side < 0);
  const yaw = inspectorCamera(true).yaw * Math.PI / 180;
  for (let i = 1; i < discs.length; i++) {
    const separation = Math.abs(discs[i].centerX - discs[i - 1].centerX) * Math.cos(yaw);
    const faces = (discs[i].radius + discs[i - 1].radius) * Math.sin(yaw);
    assert.ok(separation > faces + 10, 'exploded faces have visible air between them');
  }
}
assert.equal(typeof Inspector.inspectorWidth, 'function', 'shared stage-width helper is available');
assert.equal(Inspector.inspectorWidth(closed, 390, false), 390, 'assembled stack fits the viewport');
assert.equal(Inspector.inspectorWidth(open, 390, true), 390, 'three labels fit an ordinary phone viewport');
assert.equal(Inspector.inspectorWidth(open, 354, true), 368, 'three plates reserve readable labels without excessive scrolling');
assert.equal(Inspector.inspectorWidth(open, 1280, true), 1280, 'wide viewports do not shrink');
assert.equal(Inspector.inspectorWidth(empty, 320, true), 320, 'empty bars do not scroll');
const heavy = barbellLayout(C.enteredPlateSolution(C.BARS.bar20kg, [{ plate: { value: 20, unit: 'kg' }, count: 8 }], 0), 'bumper', 1);
assert.equal(Inspector.inspectorWidth(heavy, 390, true), 928, 'heavy stacks scroll instead of reducing each label');

// Lathe profiles are closed outlines in (radius, axial) millimetres.
for (const [family, dia, t] of [['bumper', 450, 60], ['steel', 450, 27], ['change', 160, 16]]) {
  const profile = plateProfile(family, dia, t);
  assert.ok(profile.length >= 6, `${family} profile has enough points`);
  assert.ok(profile.every(([r, x]) => r >= 25.25 - 1e-9 && r <= dia / 2 + 1e-9 && Math.abs(x) <= t / 2 + 3 + 1e-9), `${family} profile stays within the plate`);
  assert.ok(profile.some(([r]) => Math.abs(r - dia / 2) < 1e-9), `${family} reaches the rim`);
  assert.ok(profile[0][0] === 25.25 && profile.at(-1)[0] === 25.25, `${family} starts and ends at the bore`);
  const mirrored = profile.map(([r, x]) => [r, -x]).reverse();
  assert.deepEqual(profile, mirrored, `${family} profile is symmetric about the centre plane`);
}
assert.ok(plateProfile('bumper', 450, 60).some(([r, x]) => r > 25.25 && r < 225 && Math.abs(x) < 30 - 1), 'bumper faces are recessed inside the rim');
const bumperProfile = plateProfile('bumper', 450, 60);
assert.ok(bumperProfile[1][0] > 100, 'competition bumper has a broad chrome hub');
assert.ok(bumperProfile[2][1] >= -30 && bumperProfile[2][1] <= -26, 'bumper face is shallowly recessed');
for (const family of ['bumper', 'steel', 'change']) {
  const profile = plateProfile(family, 450, 30);
  assert.ok(profile.some(([r, x]) => r === 225 && Math.abs(x) < 15), `${family} outer edge is chamfered`);
  assert.equal(profile[1][0], profile[2][0], `${family} chrome has exactly a face and a hub wall`);
}
assert.ok(plateProfile('steel', 450, 27).some(([r, x]) => r < 0.3 * 225 && x > -13.5), 'steel faces dish toward the hub');

// Both clients read the same fixture.
const fixture = JSON.parse(readFileSync(new URL('./fixtures/barbell-3d.json', import.meta.url), 'utf8'));
assert.deepEqual(barbellLayout(fixture.solution, fixture.style, fixture.explode), fixture.layout, 'layout matches the shared fixture');
assert.deepEqual(fixture.profiles.map((p) => plateProfile(p.family, p.diameter, p.thickness)), fixture.profiles.map((p) => p.points), 'profiles match the shared fixture');
assert.deepEqual(fixture.cameras.map((c) => cameraOrbitPosition(c.camera, c.distance)), fixture.cameras.map((c) => c.position), 'camera positions match the shared fixture');
assert.deepEqual(fixture.frames.map((f) => inspectorFrame(barbellLayout(fixture.solution, fixture.style, f.explode), f.explode)), fixture.frames.map((f) => f.frame), 'frames match the shared fixture');
console.log('Barbell 3D inspector model: layout, explode fraction, fixed cameras, readable framing, profiles, and fixture passed');
