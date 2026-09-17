// Presentation-only reference profiles. Never written into exercise/gym data.
const BUMPER = {
  '25-kg': [450, 70], '20-kg': [450, 60], '15-kg': [450, 48], '10-kg': [450, 35], '5-kg': [450, 25],
  '55-lb': [450, 75], '45-lb': [450, 65], '35-lb': [450, 52], '25-lb': [450, 40], '10-lb': [450, 25],
};
const STEEL = {
  '25-kg': [450, 27], '20-kg': [450, 22], '15-kg': [400, 21], '10-kg': [325, 20], '5-kg': [230, 20],
  '55-lb': [450, 30], '45-lb': [450, 27], '35-lb': [400, 25], '25-lb': [325, 23], '10-lb': [230, 20],
};
const CHANGE = {
  '2.5-kg': [210, 19], '2-kg': [190, 19], '1.5-kg': [175, 18], '1.25-kg': [160, 16],
  '1-kg': [160, 16], '0.5-kg': [135, 12], '5-lb': [190, 19], '2.5-lb': [160, 16], '1.25-lb': [135, 12],
};
export function plateGeometry(plate, style = 'steel') {
  const key = `${plate.value}-${plate.unit}`;
  const [diameter, thickness] = (style === 'bumper' ? BUMPER : STEEL)[key] || CHANGE[key] || [200, 20];
  return { diameter, thickness };
}
export function barbellScene(solution, style = 'steel', exploded = false, geometry = {}) {
  const angle = (exploded ? 38 : 18) * Math.PI / 180;
  const axisX = Math.cos(angle), axisY = -Math.sin(angle) * .24, faceScale = Math.sin(angle);
  const shoulder = (solution.bar.unit === 'kg' ? solution.bar.value === 15 : solution.bar.value === 35) ? 145 : 165;
  const plates = solution.perSide.flatMap(c => Array.from({ length: Math.max(0, c.count) }, () => c.plate));
  const discs = [];
  let cursor = shoulder + 8;
  let previousFaceRadius = 0;
  plates.forEach((plate, index) => {
    const shape = geometry[`${plate.value}-${plate.unit}`] || plateGeometry(plate, style);
    const radius = Math.max(1, shape.diameter) * .18, depth = Math.max(1, shape.thickness) * .36;
    const faceRadius = radius * faceScale;
    // Both adjacent faces must fit, especially large plates beside change plates.
    if (exploded) cursor += (previousFaceRadius + faceRadius + 22) / axisX;
    for (const side of [-1, 1]) {
      const center = side * (cursor + depth / 2);
      discs.push({ plate, side, index, x: center * axisX, y: center * axisY,
        radius, faceRadius, depth: depth * axisX });
    }
    cursor += depth + (exploded ? 0 : 2);
    previousFaceRadius = faceRadius;
  });
  const collar = cursor + 8, end = Math.max(shoulder + 150, collar + 28);
  const width = Math.max(end * axisX + 25, ...discs.map(d => Math.abs(d.x) + d.faceRadius + d.depth)) * 2 + 24;
  const height = Math.max(110, ...discs.map(d => Math.abs(d.y) + d.radius)) * 2 + 40;
  discs.sort((a, b) => a.x - b.x);
  return { discs, width, height, shoulder, end, collar, axisX, axisY, faceScale };
}
