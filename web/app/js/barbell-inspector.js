// Shared model for the interactive 3D plate inspector. Mirrored 1:1 in
// CadenceCore/Sources/CadenceCore/BarbellInspector.swift; both clients render
// this layout with their own real-time renderer (SceneKit / WebGL) and prove
// parity through web/tests/fixtures/barbell-3d.json.
//
// Everything is physical millimetres from the bar's centre: x runs along the
// bar (right side positive), y is up, z is toward the viewer. BarbellScene
// stays the orthographic sprite model for compact rows; this is the solid.
import { plateGeometry, plateFamily } from './barbell-scene.js';

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
  const shapes = plates.map((plate) => geometry[`${plate.value}-${plate.unit}`] || plateGeometry(plate, style));
  const maxRadius = Math.max(bar.collarRadius, ...shapes.map((shape) => shape.diameter / 2));
  // At 50° yaw, a face projects radius*sin(yaw) along the stack. The gap
  // exceeds diameter*tan(50°), with air between even the largest faces.
  const fraction = Math.min(1, Math.max(0, explode));
  const gap = fraction * (2 * maxRadius * 1.3 + 24);
  const discs = [];
  let stackEnd = bar.shoulderEnd;
  for (const side of [-1, 1]) {
    let cursor = bar.shoulderEnd;
    plates.forEach((plate, index) => {
      const shape = shapes[index];
      const centerX = cursor + shape.thickness / 2 + gap * index;
      discs.push({ plate, side, index, family: plateFamily(plate, style),
        centerX: side * centerX, radius: shape.diameter / 2, thickness: shape.thickness });
      cursor += shape.thickness;
    });
    stackEnd = cursor;
  }
  const hasCollar = solution.collarLb > 0;
  const collarStart = stackEnd + gap * Math.max(0, plates.length - 1) + (hasCollar && plates.length ? Math.min(gap, 80 * fraction) : 0);
  const collar = { left: -collarStart, right: collarStart, length: hasCollar ? bar.collarLength : 0, radius: hasCollar ? bar.collarRadius : 0 };
  const extent = Math.max(bar.shaftHalfLength + bar.sleeveLength, collarStart + collar.length);
  return { bar, discs, collar, extent, maxRadius };
}

// Two authored views. Yaw is the angle between the bar and screen plane
// (0 = side-on, 90 = looking down the bar from −x); pitch is elevation.
export const inspectorCamera = (exploded) => exploded ? { yaw: 50, pitch: 10, zoom: 1 } : { yaw: 8, pitch: 6, zoom: 1 };

// Retain the sleeve and a short shaft section assembled; inspection frames
// the actual plates and any visible collar. Empty bars keep their full sleeve.
export function inspectorFrame(layout, explode = 0) {
  const t = Math.min(1, Math.max(0, explode));
  const stackOuter = layout.collar.left - layout.collar.length;
  const sleeveOuter = Math.min(-layout.bar.shaftHalfLength - layout.bar.sleeveLength, stackOuter);
  const outer = sleeveOuter * (1 - t) + (layout.discs.length ? stackOuter : sleeveOuter) * t;
  const inner = -layout.bar.shaftHalfLength + 260 * (1 - t) + 20 * t;
  return { target: { x: (outer + inner) / 2, y: 0, z: 0 }, halfWidth: (inner - outer) / 2 + layout.maxRadius * 0.6 };
}

// Each exploded disc keeps room for its exact value and unit. The viewport
// scrolls horizontally for a large stack; its camera never becomes draggable.
export function inspectorWidth(layout, viewportWidth, exploded) {
  return exploded ? Math.max(viewportWidth, layout.discs.filter((disc) => disc.side < 0).length * 112 + 32) : viewportWidth;
}
export function cameraOrbitPosition(camera, distance) {
  const d = distance / camera.zoom;
  const yaw = camera.yaw * Math.PI / 180, pitch = camera.pitch * Math.PI / 180;
  return { x: -d * Math.cos(pitch) * Math.sin(yaw), y: d * Math.sin(pitch), z: d * Math.cos(pitch) * Math.cos(yaw) };
}

// Lathe profiles: closed outlines as [radius, axial] millimetre pairs from the
// bore on the −x face, over the rim, back to the bore on the +x face. The
// renderers revolve them around the bar axis. The first and last two edges
// form the chrome hub; all remaining edges belong to the coated plate.
export function plateProfile(family, diameter, thickness) {
  const R = diameter / 2, ht = thickness / 2;
  let half;
  if (family === 'bumper') {
    const hub = Math.max(BORE_RADIUS + 8, 0.47 * R), proud = 1, recess = Math.min(4, 0.1 * thickness), bevel = Math.min(3, 0.15 * thickness);
    half = [[BORE_RADIUS, -(ht + proud)], [hub, -(ht + proud)], [hub, -(ht - recess)],
      [0.86 * R, -(ht - recess)], [0.91 * R, -ht], [R - bevel, -ht], [R, -(ht - bevel)]];
  } else if (family === 'steel') {
    const hub = Math.max(BORE_RADIUS + 8, 0.2 * R), proud = 0.8, dish = Math.min(2.4, 0.12 * thickness), bevel = Math.min(1.2, 0.15 * thickness);
    half = [[BORE_RADIUS, -(ht + proud)], [hub, -(ht + proud)], [hub, -(ht - dish)],
      [0.82 * R, -(ht - dish)], [0.89 * R, -ht], [R - bevel, -ht], [R, -(ht - bevel)]];
  } else {
    const hub = Math.max(BORE_RADIUS + 8, 0.25 * R), proud = 0.7, bevel = Math.min(1.5, 0.15 * thickness);
    half = [[BORE_RADIUS, -(ht + proud)], [hub, -(ht + proud)], [hub, -ht], [R - bevel, -ht], [R, -(ht - bevel)]];
  }
  return half.concat(half.map(([r, x]) => [r, -x]).reverse());
}
