// Shared 3D inspector model: physical bar/plate layout with an explode
// fraction, orbit camera limits, and lathe profiles. Mirrored in
// CadenceCore/BarbellInspector.swift; the fixture pins both clients.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as C from '../app/js/core.js';
import { barbellLayout, inspectorCamera, orbitCamera, zoomCamera, cameraOrbitPosition, plateProfile, INSPECTOR_LIMITS }
  from '../app/js/barbell-inspector.js';

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
near(openRight[0].centerX, first.centerX + INSPECTOR_LIMITS.explodeGap, 'the first plate moves one gap');
near(openRight[2].centerX, right[2].centerX + 3 * INSPECTOR_LIMITS.explodeGap, 'the third plate moves three gaps');
const half = barbellLayout(solution, 'steel', 0.5);
near(half.discs.find((d) => d.side > 0 && d.index === 2).centerX, right[2].centerX + 1.5 * INSPECTOR_LIMITS.explodeGap, 'the fraction interpolates');
near(open.collar.right, openRight[2].centerX + openRight[2].thickness / 2 + INSPECTOR_LIMITS.explodeGap, 'the collar explodes one more gap');
assert.ok(open.collar.right > closed.collar.right && open.extent >= closed.extent, 'exploding never shrinks the scene');
assert.equal(closed.extent, 685 + 415, 'a stack that fits the sleeve keeps the bar length as the extent');
assert.equal(barbellLayout(C.enteredPlateSolution(C.BARS.bar15kg, [], 5), 'bumper', 0).bar.sleeveLength, 320);
assert.equal(barbellLayout(C.enteredPlateSolution(C.BARS.bar35lb, [], 5), 'bumper', 0).bar.shaftRadius, 12.5);
assert.equal(JSON.stringify(solution), JSON.stringify(C.enteredPlateSolution(C.BARS.bar45lb, counts, 5)), 'layout never mutates the solution');

// Camera: yaw is the angle between the bar axis and the screen, matching the sprite views.
assert.deepEqual(inspectorCamera(true), { yaw: 38, pitch: 14, zoom: 1 });
assert.deepEqual(inspectorCamera(false), { yaw: 18, pitch: 14, zoom: 1 });
assert.deepEqual(orbitCamera(inspectorCamera(true), 10, -5), { yaw: 48, pitch: 9, zoom: 1 });
assert.equal(orbitCamera(inspectorCamera(true), 0, 200).pitch, INSPECTOR_LIMITS.pitchMax);
assert.equal(orbitCamera(inspectorCamera(true), 0, -200).pitch, INSPECTOR_LIMITS.pitchMin);
assert.equal(orbitCamera(inspectorCamera(true), 170, 0).yaw, -152, 'yaw wraps into (-180, 180]');
assert.equal(orbitCamera(inspectorCamera(false), -198, 0).yaw, 180);
assert.equal(zoomCamera(inspectorCamera(true), 100).zoom, INSPECTOR_LIMITS.zoomMax);
assert.equal(zoomCamera(inspectorCamera(true), 0).zoom, INSPECTOR_LIMITS.zoomMin);
near(zoomCamera(inspectorCamera(true), 1.5).zoom, 1.5, 'zoom multiplies');
const eye = cameraOrbitPosition(inspectorCamera(false), 1000);
near(Math.hypot(eye.x, eye.y, eye.z), 1000, 'eye sits on the orbit sphere');
assert.ok(eye.x < 0 && eye.z > 0 && eye.y > 0, 'default eye is at the −x end, in front, above');
near(cameraOrbitPosition({ yaw: 90, pitch: 0, zoom: 1 }, 10).x, -10, 'yaw 90 looks straight down the bar');
near(cameraOrbitPosition({ yaw: 0, pitch: 0, zoom: 1 }, 10).z, 10, 'yaw 0 is side-on');
near(cameraOrbitPosition({ yaw: 0, pitch: 0, zoom: 2 }, 10).z, 5, 'zoom shortens the distance');

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
assert.ok(plateProfile('steel', 450, 27).some(([r, x]) => r < 0.3 * 225 && x > -13.5), 'steel faces dish toward the hub');

// Both clients read the same fixture.
const fixture = JSON.parse(readFileSync(new URL('./fixtures/barbell-3d.json', import.meta.url), 'utf8'));
assert.deepEqual(barbellLayout(fixture.solution, fixture.style, fixture.explode), fixture.layout, 'layout matches the shared fixture');
assert.deepEqual(fixture.profiles.map((p) => plateProfile(p.family, p.diameter, p.thickness)), fixture.profiles.map((p) => p.points), 'profiles match the shared fixture');
assert.deepEqual(fixture.cameras.map((c) => cameraOrbitPosition(c.camera, c.distance)), fixture.cameras.map((c) => c.position), 'camera positions match the shared fixture');
console.log('Barbell 3D inspector model: layout, explode fraction, camera limits, profiles, and fixture passed');
