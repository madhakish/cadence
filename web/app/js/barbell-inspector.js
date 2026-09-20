// Shared model for the interactive 3D plate inspector. Mirrored 1:1 in
// CadenceCore/Sources/CadenceCore/BarbellInspector.swift; both clients render
// this layout with their own real-time renderer (SceneKit / WebGL) and prove
// parity through web/tests/fixtures/barbell-3d.json.
//
// Everything is physical millimetres from the bar's centre: x runs along the
// bar (right side positive), y is up, z is toward the viewer. BarbellScene
// stays the orthographic sprite model for compact rows; this is the solid.
import { plateGeometry, plateFamily } from './barbell-scene.js';

export const INSPECTOR_LIMITS = Object.freeze({
  pitchMin: -20, pitchMax: 70,       // degrees above the bar
  zoomMin: 0.55, zoomMax: 3,
  explodeGap: 65,                    // mm between plates at explode = 1
});
export const BORE_RADIUS = 25.25;    // 50.5 mm Olympic bore

// Men's (20 kg / 45 lb) and women's (15 kg / 35 lb) bars: the sleeves differ,
// the shaft length is the same.
const MENS = Object.freeze({ shaftHalfLength: 685, sleeveLength: 415, shaftRadius: 14, sleeveRadius: 25,
  shoulderRadius: 36, shoulderLength: 20, collarLength: 50, collarRadius: 40 });
const WOMENS = Object.freeze({ ...MENS, sleeveLength: 320, shaftRadius: 12.5 });

export const isWomensBar = (bar) => bar.unit === 'kg' ? bar.value === 15 : bar.value === 35;

export function barbellLayout(solution, style = 'steel', explode = 0, geometry = {}) {
  const base = isWomensBar(solution.bar) ? WOMENS : MENS;
  const bar = { ...base, shoulderEnd: base.shaftHalfLength + base.shoulderLength };
  const plates = solution.perSide.flatMap((c) => Array.from({ length: Math.max(0, c.count) }, () => c.plate));
  const gap = explode * INSPECTOR_LIMITS.explodeGap;
  const discs = [];
  let stackEnd = bar.shoulderEnd;
  for (const side of [-1, 1]) {
    let cursor = bar.shoulderEnd;
    plates.forEach((plate, index) => {
      const shape = geometry[`${plate.value}-${plate.unit}`] || plateGeometry(plate, style);
      const centerX = cursor + shape.thickness / 2 + gap * (index + 1);
      discs.push({ plate, side, index, family: plateFamily(plate, style),
        centerX: side * centerX, radius: shape.diameter / 2, thickness: shape.thickness });
      cursor += shape.thickness;
    });
    stackEnd = cursor;
  }
  const collarStart = stackEnd + gap * (plates.length + 1);
  const collar = { left: -collarStart, right: collarStart, length: bar.collarLength, radius: bar.collarRadius };
  const extent = Math.max(bar.shaftHalfLength + bar.sleeveLength, collarStart + bar.collarLength);
  const maxRadius = Math.max(bar.collarRadius, ...discs.map((d) => d.radius));
  return { bar, discs, collar, extent, maxRadius };
}

// Camera: yaw is the angle between the bar axis and the screen plane (0 =
// side-on, 90 = looking down the bar from the −x end), the same convention
// as the sprite views' 18° / 38°. Pitch is elevation above the bar.
export const inspectorCamera = (exploded) => ({ yaw: exploded ? 38 : 18, pitch: 14, zoom: 1 });
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const wrapDegrees = (deg) => { const d = ((deg + 180) % 360 + 360) % 360 - 180; return d === -180 ? 180 : d; };
export const orbitCamera = (camera, dYaw, dPitch) => ({
  yaw: wrapDegrees(camera.yaw + dYaw),
  pitch: clamp(camera.pitch + dPitch, INSPECTOR_LIMITS.pitchMin, INSPECTOR_LIMITS.pitchMax),
  zoom: camera.zoom,
});
export const zoomCamera = (camera, factor) => ({ ...camera, zoom: clamp(camera.zoom * factor, INSPECTOR_LIMITS.zoomMin, INSPECTOR_LIMITS.zoomMax) });
export function cameraOrbitPosition(camera, distance) {
  const d = distance / camera.zoom;
  const yaw = camera.yaw * Math.PI / 180, pitch = camera.pitch * Math.PI / 180;
  return { x: -d * Math.cos(pitch) * Math.sin(yaw), y: d * Math.sin(pitch), z: d * Math.cos(pitch) * Math.cos(yaw) };
}

// Lathe profiles: closed outlines as [radius, axial] millimetre pairs from the
// bore on the −x face, over the rim, back to the bore on the +x face. The
// renderers revolve them around the bar axis.
export function plateProfile(family, diameter, thickness) {
  const R = diameter / 2, ht = thickness / 2;
  let half;
  if (family === 'bumper') {
    const hub = 0.235 * R, proud = 1.5, recess = 0.14 * thickness, rim = 0.9 * R;
    half = [[BORE_RADIUS, -(ht + proud)], [hub, -(ht + proud)], [hub, -(ht - recess)], [rim, -(ht - recess)], [rim, -ht], [R, -ht]];
  } else if (family === 'steel') {
    const hub = 0.2 * R, proud = 1.5, dish = 0.18 * thickness, lip = 0.86 * R;
    half = [[BORE_RADIUS, -(ht + proud)], [hub, -(ht + proud)], [hub, -(ht - dish)], [lip, -ht], [R, -ht]];
  } else {
    const hub = Math.max(BORE_RADIUS + 8, 0.25 * R), proud = 1;
    half = [[BORE_RADIUS, -(ht + proud)], [hub, -(ht + proud)], [hub, -ht], [R, -ht]];
  }
  return half.concat(half.map(([r, x]) => [r, -x]).reverse());
}
