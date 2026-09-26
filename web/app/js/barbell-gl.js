// WebGL2 twin of Cadence/Views/BarbellSceneView.swift: the loaded bar as a
// real-time solid built from the shared BarbellInspector model — lathe
// plates from the family profiles, chrome hub inserts, knurled shaft,
// sleeves and collars — lit by a key light with a shadow map and an analytic
// studio environment and two authored inspection states. Page gestures never
// move the camera. Colours come from the shared plate palette.
// Where WebGL2 is unavailable (jsdom, old browsers) `supported` is false and
// barbell.js keeps the sprite SVG.
import * as C from './core.js';
import { plateThemeColour, plateThemeDescription, plateThemeMaterial, plateThemeRatios } from './plate-theme.js';
import { barbellLayout, plateProfile, cameraOrbitPosition, inspectorCamera, inspectorFrame, BORE_RADIUS }
  from './barbell-inspector.js';

// ---------------------------------------------------------------- geometry

/// Revolve a [radius, axial] profile around x. Each edge gets its own ring
/// pair with the edge normal so rims stay crisp; the first/last `hubEdges`
/// edges are returned as a separate index range for the hub material.
export function latheMesh(profile, segments = 72, hubEdges = 0) {
  const positions = [], normals = [], uvs = [], hub = [], body = [];
  const edges = [];
  for (let i = 0; i + 1 < profile.length; i++) edges.push([profile[i], profile[i + 1]]);
  const total = edges.reduce((s, [a, b]) => s + Math.hypot(b[0] - a[0], b[1] - a[1]), 0) || 1;
  let travelled = 0;
  edges.forEach(([a, b], k) => {
    const dr = b[0] - a[0], dx = b[1] - a[1];
    const length = Math.hypot(dr, dx);
    if (!length) return;
    const nr = dx / length, nx = -dr / length;
    const base = positions.length / 3;
    for (const [point, v] of [[a, travelled / total], [b, (travelled + length) / total]]) {
      for (let j = 0; j <= segments; j++) {
        const theta = j / segments * 2 * Math.PI, c = Math.cos(theta), s = Math.sin(theta);
        positions.push(point[1], point[0] * c, point[0] * s);
        normals.push(nx, nr * c, nr * s);
        uvs.push(j / segments, v);
      }
    }
    const ring = segments + 1;
    const target = (k < hubEdges || k >= edges.length - hubEdges) ? hub : body;
    for (let j = 0; j < segments; j++) {
      const i0 = base + j, i1 = i0 + 1, i2 = base + ring + j, i3 = i2 + 1;
      target.push(i0, i2, i1, i1, i2, i3);
    }
    travelled += length;
  });
  return { positions: new Float32Array(positions), normals: new Float32Array(normals), uvs: new Float32Array(uvs),
    indices: new Uint32Array([...hub, ...body]), hubCount: hub.length, bodyCount: body.length };
}

/// A closed cylinder along x as a lathe of its rectangle.
export const cylinderMesh = (radius, length, segments = 72) =>
  latheMesh([[0, -length / 2], [radius, -length / 2], [radius, length / 2], [0, length / 2]], segments);

export const FIELD_OF_VIEW = 8;    // product-photo lens: keeps far plates and captions legible in a long stack

/// Camera distance at zoom 1 that fits a frame (half-width along the bar and
/// the tallest plate) for a viewport aspect and the camera's yaw, the same
/// rule as the SceneKit view. A yawed span reaches toward the eye by
/// halfWidth·sin(yaw), so its near end must still fit and clear the lens.
export function fitDistance({ halfWidth, maxRadius }, aspect, yawDeg = 0, verticalFovDeg = FIELD_OF_VIEW, padding = 1.7) {
  const vertical = verticalFovDeg * Math.PI / 180;
  const horizontal = 2 * Math.atan(Math.tan(vertical / 2) * Math.max(0.5, aspect));
  const yaw = yawDeg * Math.PI / 180, reach = halfWidth * Math.abs(Math.sin(yaw)), across = halfWidth * Math.abs(Math.cos(yaw));
  return reach + Math.max(across * 1.12 / Math.tan(horizontal / 2), maxRadius * padding / Math.tan(vertical / 2));
}

// ---------------------------------------------------------------- matrices (column-major)

const mat4 = {
  perspective(fovY, aspect, near, far) {
    const f = 1 / Math.tan(fovY / 2), nf = 1 / (near - far);
    return new Float32Array([f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) * nf, -1, 0, 0, 2 * far * near * nf, 0]);
  },
  ortho(l, r, b, t, n, f) {
    return new Float32Array([2 / (r - l), 0, 0, 0, 0, 2 / (t - b), 0, 0, 0, 0, -2 / (f - n), 0,
      -(r + l) / (r - l), -(t + b) / (t - b), -(f + n) / (f - n), 1]);
  },
  lookAt(eye, target, up) {
    const z = norm3(sub3(eye, target)), x = norm3(cross3(up, z)), y = cross3(z, x);
    return new Float32Array([x[0], y[0], z[0], 0, x[1], y[1], z[1], 0, x[2], y[2], z[2], 0,
      -dot3(x, eye), -dot3(y, eye), -dot3(z, eye), 1]);
  },
  multiply(a, b) {
    const out = new Float32Array(16);
    for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) {
      let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k];
      out[c * 4 + r] = s;
    }
    return out;
  },
  translation(x, y, z) { return new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]); },
};
const sub3 = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const dot3 = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross3 = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm3 = (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };

// ---------------------------------------------------------------- shaders

const VERT = `#version 300 es
in vec3 aPos; in vec3 aNormal; in vec2 aUV;
uniform mat4 uProj, uView, uModel, uLightVP;
out vec3 vWorld; out vec3 vLocal; out vec3 vNormal; out vec2 vUV; out vec4 vLight;
void main() {
  vec4 world = uModel * vec4(aPos, 1.0);
  vWorld = world.xyz; vLocal = aPos; vNormal = mat3(uModel) * aNormal; vUV = aUV; vLight = uLightVP * world;
  gl_Position = uProj * uView * world;
}`;

const FRAG = `#version 300 es
precision highp float; precision highp sampler2DShadow;
in vec3 vWorld; in vec3 vLocal; in vec3 vNormal; in vec2 vUV; in vec4 vLight;
uniform vec3 uColor; uniform float uMetal, uRough, uEnv, uShadowAlpha;
uniform int uFinish; // 0 smooth, 1 rubber, 2 powder coat, 3 brushed steel
uniform float uHubRatio, uBoreRatio;
uniform vec3 uEye, uLightDir;
uniform int uMode;            // 0 lit, 1 shadow catcher, 2 stamp, 3 knurl, 4 photographic face
uniform sampler2DShadow uShadow; uniform sampler2D uTex; uniform vec2 uKnurlTile;
out vec4 fragColor;
const float PI = 3.14159265;
// The studio: dark floor, mid horizon, bright ceiling with an overhead
// softbox band and two side softboxes, the rig the sprites were lit with.
float studio(vec3 d, float rough) {
  float base = mix(0.07, 0.30, smoothstep(-0.35, 0.9, d.y));
  float blur = 0.035 + rough * 0.25;
  float roof = smoothstep(0.53 - blur, 0.53 + blur, d.y)
    * (1.0 - smoothstep(0.84 - blur, 0.84 + blur, d.y));
  float strip = 1.0 - smoothstep(0.08, 0.17 + blur, abs(d.z - 0.62));
  float rim = pow(max(dot(d, normalize(vec3(0.8, 0.35, -0.6))), 0.0), mix(180.0, 8.0, rough));
  return base + roof * 1.9 + strip * 0.65 + rim * 1.6;
}
float grain(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float shadowAt(vec4 lightPos) {
  vec3 p = lightPos.xyz / lightPos.w * 0.5 + 0.5;
  if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) return 1.0;
  float sum = 0.0; float texel = 1.0 / 2048.0;
  for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++)
    sum += texture(uShadow, vec3(p.xy + vec2(float(i), float(j)) * texel * 1.5, p.z - 0.0015));
  return sum / 9.0;
}
void main() {
  if (uMode == 1) { fragColor = vec4(0.0, 0.0, 0.0, (1.0 - shadowAt(vLight)) * uShadowAlpha); return; }
  if (uMode == 2) { vec4 t = texture(uTex, vUV); fragColor = vec4(uColor * t.a, t.a); return; }
  if (uMode == 4) {
    vec4 t = texture(uTex, vUV);
    float radius = length(vUV - 0.5) / 0.485;
    if (radius < uBoreRatio || t.a < 0.02) discard;
    float luminance = dot(t.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 tinted = mix(uColor * luminance / 0.50, t.rgb, 0.07);
    vec3 colour = mix(t.rgb, tinted, smoothstep(uHubRatio - 0.008, uHubRatio + 0.008, radius));
    fragColor = vec4(clamp(colour, 0.0, 1.0) * t.a, t.a);
    return;
  }
  vec3 N = normalize(vNormal);
  float rough = uRough;
  vec3 baseColor = uColor;
  float fine = grain(floor(vLocal * 2.4));
  if (uFinish == 1 || uFinish == 2) {
    float strength = uFinish == 1 ? 0.04 : 0.018;
    N = normalize(N + (vec3(fine, grain(floor(vLocal * 2.4) + 7.0), grain(floor(vLocal * 2.4) + 13.0)) - 0.5) * strength);
    rough = clamp(rough + (fine - 0.5) * 0.08, 0.05, 0.95);
    baseColor *= 0.985 + fine * 0.03;
  }
  if (uFinish == 3) {
    float radial = length(vLocal.yz);
    float ring = sin(radial * 3.5 + vLocal.x * 0.65) * clamp(1.0 - fwidth(radial) * 0.8, 0.0, 1.0);
    rough = clamp(rough + ring * 0.035, 0.05, 0.9);
    baseColor *= 0.96 + fine * 0.05;
  }
  if (uMode == 3) {
    vec3 T = normalize(cross(vec3(1.0, 0.0, 0.0), N)); vec3 B = cross(N, T);
    vec3 nm = texture(uTex, vUV * uKnurlTile).xyz * 2.0 - 1.0;
    N = normalize(T * nm.x + B * nm.y + N * nm.z);
  }
  vec3 V = normalize(uEye - vWorld); vec3 L = normalize(uLightDir); vec3 H = normalize(L + V);
  float NdotL = max(dot(N, L), 0.0), NdotV = max(dot(N, V), 1e-3), NdotH = max(dot(N, H), 0.0), VdotH = max(dot(V, H), 0.0);
  vec3 F0 = mix(vec3(0.04), baseColor, uMetal); vec3 albedo = baseColor * (1.0 - uMetal);
  float a = max(rough * rough, 0.002), a2 = a * a;
  float D = a2 / (PI * pow(NdotH * NdotH * (a2 - 1.0) + 1.0, 2.0));
  float k = (rough + 1.0) * (rough + 1.0) / 8.0;
  float G = (NdotV / (NdotV * (1.0 - k) + k)) * (NdotL / (NdotL * (1.0 - k) + k));
  vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
  vec3 spec = D * G * F / max(4.0 * NdotL * NdotV, 1e-3);
  float visibility = shadowAt(vLight);
  vec3 key = (albedo / PI + spec) * NdotL * 2.6 * visibility;
  vec3 R = reflect(-V, N);
  vec3 Fr = F0 + (max(vec3(1.0 - rough), F0) - F0) * pow(1.0 - NdotV, 5.0);
  vec3 ambient = albedo * (0.42 + 0.24 * max(N.y, 0.0)) * uEnv + Fr * studio(R, rough) * uEnv;
  vec3 colour = key + ambient;
  colour = clamp((colour * (2.51 * colour + 0.03)) / (colour * (2.43 * colour + 0.59) + 0.14), 0.0, 1.0);
  fragColor = vec4(pow(colour, vec3(1.0 / 2.2)), 1.0);
}`;

const DEPTH_VERT = `#version 300 es
in vec3 aPos; uniform mat4 uLightVP, uModel;
void main() { gl_Position = uLightVP * uModel * vec4(aPos, 1.0); }`;
const DEPTH_FRAG = `#version 300 es
precision highp float; void main() {}`;

// ---------------------------------------------------------------- textures

const hexToRGB = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
const linearRGB = (hex) => hexToRGB(hex).map(c => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);

/// A tileable diamond-knurl normal map from a drawn height field.
function knurlNormalMap() {
  const n = 64, cv = document.createElement('canvas'); cv.width = cv.height = n;
  const ctx = cv.getContext('2d');
  ctx.fillStyle = '#000'; ctx.fillRect(0, 0, n, n);
  ctx.strokeStyle = '#fff'; ctx.lineWidth = 2.2;
  for (let k = -n; k <= 2 * n; k += 8) {
    ctx.moveTo(k, 0); ctx.lineTo(k + n, n); ctx.moveTo(k + n, 0); ctx.lineTo(k, n);
  }
  ctx.stroke();
  const px = ctx.getImageData(0, 0, n, n).data;
  const h = (x, y) => px[(((y + n) % n) * n + ((x + n) % n)) * 4] / 255;
  const out = new Uint8Array(n * n * 4);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    const dx = (h(x + 1, y) - h(x - 1, y)) * .16, dy = (h(x, y + 1) - h(x, y - 1)) * .16;
    const l = Math.hypot(dx, dy, 1), i = (y * n + x) * 4;
    out[i] = (-dx / l * 0.5 + 0.5) * 255; out[i + 1] = (-dy / l * 0.5 + 0.5) * 255; out[i + 2] = (1 / l * 0.5 + 0.5) * 255; out[i + 3] = 255;
  }
  return { data: out, size: n };
}

/// The denomination as an alpha texture, printed on the outward face.
function labelTexture(plate) {
  const cv = document.createElement('canvas'); cv.width = 512; cv.height = 256;
  const ctx = cv.getContext('2d');
  ctx.clearRect(0, 0, cv.width, cv.height);
  ctx.fillStyle = '#fff'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.font = '750 112px system-ui, -apple-system, "Segoe UI", sans-serif';
  ctx.fillText(String(plate.value), cv.width / 2, 98, 490);
  ctx.font = '650 52px system-ui, -apple-system, "Segoe UI", sans-serif';
  ctx.fillText(plate.unit, cv.width / 2, 193);
  return cv;
}

// ---------------------------------------------------------------- renderer

export function barbellGL(solution, style = 'steel', { exploded = false, onProject = () => {}, plateTheme = 'custom' } = {}) {
  const canvas = document.createElement('canvas');
  canvas.className = 'barbell-gl';
  // jsdom and old browsers have no WebGL2 at all; asking would only log.
  const gl = typeof WebGL2RenderingContext === 'function'
    ? canvas.getContext('webgl2', { antialias: true, alpha: false, premultipliedAlpha: true }) : null;
  if (!gl) return { canvas, supported: false };

  const program = link(gl, VERT, FRAG), depthProgram = link(gl, DEPTH_VERT, DEPTH_FRAG);
  const U = (name) => gl.getUniformLocation(program, name);
  const meshes = [];      // { vao, model, parts: [{ offset, count, material }] }
  const layouts = { closed: barbellLayout(solution, style, 0, {}, plateTheme), open: barbellLayout(solution, style, 1, {}, plateTheme) };

  // Theme: colour, material, hub/rim ratios and construction details per
  // disc; custom reproduces today's token-driven look exactly.
  const theme = plateThemeDescription(plateTheme);
  const plateColour = (plate) => plateThemeColour(plate, plateTheme, style);
  const FINISH = { rubber: 1, powder: 2, gloss: 0, castIron: 1, hammertone: 2, machined: 3 };
  const blackOxide = theme.barFinish === 'blackOxide';
  const M = {
    chrome: { colour: [0.72, 0.76, 0.80], metal: 1, rough: 0.23, finish: 3 },
    blackSteel: { colour: [0.11, 0.11, 0.12], metal: 0.6, rough: 0.5, finish: 2 },
    shaft: blackOxide ? { colour: [0.2, 0.21, 0.23], metal: 1, rough: 0.42, finish: 3 } : { colour: [0.52, 0.56, 0.60], metal: 1, rough: 0.31, finish: 3 },
    knurl: blackOxide ? { colour: [0.19, 0.2, 0.22], metal: 1, rough: 0.5, knurl: true } : { colour: [0.50, 0.54, 0.58], metal: 1, rough: 0.44, knurl: true },
    collar: { colour: [0.16, 0.16, 0.16], metal: 0.4, rough: 0.55 },
    plate: (plate, fill) => {
      const m = plateThemeMaterial(plate, plateTheme, style);
      return { colour: linearRGB(fill), metal: m.metal, rough: m.roughness, finish: FINISH[m.finish] ?? 0 };
    },
  };
  const hubMaterial = (plate, fill) => {
    const m = plateThemeMaterial(plate, plateTheme, style);
    if (theme.hubFinish === 'blackSteel') return M.blackSteel;
    if (theme.hubFinish === 'castIron' || theme.hubFinish === 'hammertone') return { ...M.plate(plate, fill) };
    return M.chrome;
  };
  const details = new Set(theme.details || []);

  function upload(mesh) {
    const vao = gl.createVertexArray(); gl.bindVertexArray(vao);
    for (const [name, data, size] of [['aPos', mesh.positions, 3], ['aNormal', mesh.normals, 3], ['aUV', mesh.uvs, 2]]) {
      const buffer = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buffer); gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
      const loc = gl.getAttribLocation(program, name);
      if (loc >= 0) { gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, size, gl.FLOAT, false, 0, 0); }
      const dloc = gl.getAttribLocation(depthProgram, name);
      if (dloc >= 0 && name === 'aPos') { gl.enableVertexAttribArray(dloc); gl.vertexAttribPointer(dloc, size, gl.FLOAT, false, 0, 0); }
    }
    const index = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, index); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, mesh.indices, gl.STATIC_DRAW);
    gl.bindVertexArray(null);
    return vao;
  }
  function add(mesh, x, material, ranges = null) {
    const vao = upload(mesh);
    const entry = { vao, model: mat4.translation(x, 0, 0), x, parts: ranges || [{ offset: 0, count: mesh.indices.length, material }] };
    meshes.push(entry);
    return entry;
  }

  // Bar: shaft, knurl bands, sleeves, shoulders.
  const bar = layouts.closed.bar;
  add(cylinderMesh(bar.shaftRadius, bar.shaftHalfLength), -bar.shaftHalfLength / 2, M.shaft);
  for (const side of [-1]) {
    add(cylinderMesh(bar.shaftRadius + 0.15, 310), side * (bar.shaftHalfLength - 190), M.knurl);
    const sleeveProfile = [[0, -bar.sleeveLength / 2], [bar.sleeveRadius - 1.2, -bar.sleeveLength / 2],
      [bar.sleeveRadius, -bar.sleeveLength / 2 + 1.2], [bar.sleeveRadius, bar.sleeveLength / 2 - 1.2],
      [bar.sleeveRadius - 1.2, bar.sleeveLength / 2], [0, bar.sleeveLength / 2]];
    add(latheMesh(sleeveProfile, 96), side * (bar.shaftHalfLength + bar.sleeveLength / 2), M.chrome);
    add(latheMesh([[bar.shaftRadius, -10], [bar.shoulderRadius - 2, -10], [bar.shoulderRadius, -8],
      [bar.shoulderRadius, 8], [bar.shoulderRadius - 2, 10], [bar.shaftRadius, 10]], 96),
    side * (bar.shaftHalfLength + bar.shoulderLength / 2), M.chrome);
    // Sleeve grooves and end-cap recess catch a thin highlight, not a painted stripe.
    for (let offset = 8; offset < bar.sleeveLength - 24; offset += 5) {
      add(latheMesh([[24.92, -.14], [25.04, 0], [24.92, .14]], 64), side * (bar.shaftHalfLength + offset), M.shaft);
    }
    add(cylinderMesh(20, .8), side * (bar.shaftHalfLength + bar.sleeveLength + .5), M.collar);
    add(cylinderMesh(12, 1), side * (bar.shaftHalfLength + bar.sleeveLength + 1), M.shaft);
  }
  // Plates: lathe per disc, hub as its own range, denomination quad on the outward face.
  const discEntries = [], labelEntries = [], photoEntries = [];
  for (const disc of layouts.closed.discs.filter(d => d.side < 0)) {
    const profile = plateProfile(disc.family, disc.radius * 2, disc.thickness);
    const mesh = latheMesh(profile, 96, 2);
    const colour = plateColour(disc.plate);
    const material = plateThemeMaterial(disc.plate, plateTheme, style);
    const ratios = plateThemeRatios(disc.plate, plateTheme, style);
    const entry = add(mesh, disc.centerX, null, [
      { offset: 0, count: mesh.hubCount, material: hubMaterial(disc.plate, colour.fill) },
      { offset: mesh.hubCount, count: mesh.bodyCount, material: M.plate(disc.plate, colour.fill) },
    ]);
    discEntries.push({ disc, entry });
    const R = disc.radius;
    const faceX = -disc.thickness / 2 - 1.2, extent = R / .97;
    const photo = add({
      positions: new Float32Array([faceX, -extent, -extent, faceX, -extent, extent, faceX, extent, extent, faceX, extent, -extent]),
      normals: new Float32Array([-1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0]),
      uvs: new Float32Array([0, 1, 1, 1, 1, 0, 0, 0]), indices: new Uint32Array([0, 1, 2, 0, 2, 3]),
    }, disc.centerX, { colour: hexToRGB(colour.fill), photo: true, family: disc.family, photoFamily: material.photoFamily,
      hubRatio: ratios.photoHub, boreRatio: BORE_RADIUS / R });
    photoEntries.push({ disc, entry: photo });
    const hub = Math.max(BORE_RADIUS + 8, ratios.hub * R);
    const rim = ratios.rim * R;
    // Construction details follow the disc through explode (localOffset).
    const detail = (mesh, offset, mat) => { const e = add(mesh, disc.centerX, mat); e.localOffset = offset; discEntries.push({ disc, entry: e }); };
    if (details.has('boltedHub')) for (let i = 0; i < 6; i++) { const a = (i + .5) / 6 * Math.PI * 2, orbit = hub * .72; for (const s of [-1, 1]) detail(cylinderMesh(5, 2.8), [s * (disc.thickness / 2 + .2), Math.cos(a) * orbit, Math.sin(a) * orbit], { colour: [0.55, 0.57, 0.6], metal: 1, rough: 0.45 }); }
    if (details.has('chromeBoreRing')) detail(cylinderMesh(BORE_RADIUS + 6, disc.thickness + 2.4), [0, 0, 0], M.chrome);
    if (details.has('calibrationPlugs')) for (const a of [Math.PI / 4, Math.PI * 5 / 4]) detail(cylinderMesh(7, 2), [-(disc.thickness / 2 + .2), Math.cos(a) * .62 * R, Math.sin(a) * .62 * R], { colour: [0.7, 0.72, 0.75], metal: 1, rough: 0.3 });
    if (details.has('machinedRimRing')) detail(cylinderMesh(R + .3, Math.max(2, disc.thickness * .35)), [0, 0, 0], { colour: [0.78, 0.8, 0.83], metal: 1, rough: 0.2, finish: 3 });
    if (details.has('colourBand') && colour.band) detail(cylinderMesh(R + .6, Math.max(6, disc.thickness * .34)), [0, 0, 0], { colour: linearRGB(colour.band), metal: 0, rough: 0.7, finish: 1 });
    if (details.has('hubRing')) detail(cylinderMesh(hub + 4, disc.thickness + 1.6), [0, 0, 0], { colour: linearRGB(colour.ink), metal: 0, rough: 0.5, finish: 2 });
    const cap = (rim - hub) * 0.5, w = cap * 2.2;
    const faceOffset = disc.thickness / 2 + 1.6;
    const y = (hub + rim) / 2;
    // Real plates are marked on both faces: one quad per face at the top of
    // the annulus, each oriented for reading from its own side.
    const positions = [], normals = [], uvs = [], indices = [];
    for (const s of [-1, 1]) {
      const x = s * (faceOffset + 0.4), base = positions.length / 3;
      // u runs along the viewer's right for that face (+z seen from −x, −z seen from +x).
      positions.push(x, y - cap / 2, s * w / 2, x, y - cap / 2, -s * w / 2, x, y + cap / 2, -s * w / 2, x, y + cap / 2, s * w / 2);
      normals.push(s, 0, 0, s, 0, 0, s, 0, 0, s, 0, 0);
      uvs.push(0, 1, 1, 1, 1, 0, 0, 0);
      indices.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }
    const quad = { positions: new Float32Array(positions), normals: new Float32Array(normals), uvs: new Float32Array(uvs), indices: new Uint32Array(indices) };
    const label = add(quad, disc.centerX, { colour: hexToRGB(colour.ink), unlit: labelTexture(disc.plate) });
    labelEntries.push({ disc, entry: label });
    const brandPositions = new Float32Array(positions);
    for (let i = 1; i < brandPositions.length; i += 3) brandPositions[i] -= y * 2;
    const brand = add({ ...quad, positions: brandPositions }, disc.centerX,
      { colour: hexToRGB(colour.ink), unlit: labelTexture({ value: theme.brand ?? 'CADENCE', unit: '' }) });
    labelEntries.push({ disc, entry: brand });
  }
  const collarEntries = [];
  if (solution.collarLb > 0) {
    const half = layouts.closed.collar.length / 2;
    for (const x of [layouts.closed.collar.left - half]) {
      const radius = layouts.closed.collar.radius;
      const profile = [[BORE_RADIUS, -half], [radius - 2, -half], [radius, -half + 2],
        [radius, half - 2], [radius - 2, half], [BORE_RADIUS, half], [BORE_RADIUS, -half]];
      collarEntries.push(add(latheMesh(profile, 72), x, M.chrome));
    }
  }
  // The floor catches the shadow only.
  const floorY = -layouts.closed.maxRadius - 2;
  const floor = add({
    positions: new Float32Array([-9000, floorY, -9000, 9000, floorY, -9000, 9000, floorY, 9000, -9000, floorY, 9000]),
    normals: new Float32Array([0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]), uvs: new Float32Array(8), indices: new Uint32Array([0, 2, 1, 0, 3, 2]),
  }, 0, { floor: true });

  // Textures: knurl normal map and per-label alpha textures.
  const knurl = knurlNormalMap();
  const knurlTex = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, knurlTex);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, knurl.size, knurl.size, 0, gl.RGBA, gl.UNSIGNED_BYTE, knurl.data);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  for (const { entry } of labelEntries) {
    const material = entry.parts[0].material;
    const tex = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, material.unlit);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    material.texture = tex;
  }
  // Two original photographic face details, reused for every denomination.
  // Counts, silhouette, tint and exact stamps remain renderer-owned. The
  // procedural solid stays visible while an image loads or if it fails.
  for (const family of ['bumper', 'steel']) {
    const source = new Image();
    source.onload = () => {
      if (state.disposed) return;
      const texture = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      for (const { entry } of photoEntries) {
        const material = entry.parts[0].material;
        const wanted = material.photoFamily === null ? null : (material.photoFamily || (material.family === 'bumper' ? 'bumper' : 'steel'));
        if (wanted === family) material.texture = texture;
      }
      request();
    };
    source.src = new URL(`../assets/plates/${family}-face-detail.png`, import.meta.url).href;
  }
  // Shadow map.
  const SHADOW = 2048;
  const shadowTex = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, shadowTex);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT24, SHADOW, SHADOW, 0, gl.DEPTH_COMPONENT, gl.UNSIGNED_INT, null);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_COMPARE_MODE, gl.COMPARE_REF_TO_TEXTURE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_COMPARE_FUNC, gl.LEQUAL);
  const shadowFB = gl.createFramebuffer(); gl.bindFramebuffer(gl.FRAMEBUFFER, shadowFB);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, shadowTex, 0);
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);

  // State.
  const state = {
    explode: exploded ? 1 : 0, target: exploded ? 1 : 0, camera: inspectorCamera(exploded),
    width: 1, height: 1, disposed: false,
  };
  const lightDir = norm3([-0.75, 1, 0.9]);
  const reduceMotion = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  // Backdrop colours are theme tokens (--scene-studio/-dark/-paper in
  // styles.css, mirrored by Theme.swift); the fallbacks are the same values.
  const backdropColour = () => {
    const css = canvas.isConnected ? getComputedStyle(canvas).getPropertyValue('--scene-studio').trim() : '';
    return hexToRGB(/^#[0-9a-f]{6}$/i.test(css) ? css : '#1b1d21');
  };

  function placeStack(fraction) {
    const layout = barbellLayout(solution, style, fraction);
    for (const { disc, entry } of discEntries) {
      const target = layout.discs.find((d) => d.side === disc.side && d.index === disc.index);
      const [dx, dy, dz] = entry.localOffset || [0, 0, 0];
      entry.model = mat4.translation(target.centerX + dx, dy, dz);
    }
    for (const { disc, entry } of [...photoEntries, ...labelEntries]) {
      const target = layout.discs.find((d) => d.side === disc.side && d.index === disc.index);
      entry.model = mat4.translation(target.centerX, 0, 0);
    }
    if (collarEntries.length) {
      const half = layout.collar.length / 2;
      collarEntries[0].model = mat4.translation(layout.collar.left - half, 0, 0);
    }
    return layout;
  }

  function render() {
    if (state.disposed) return;
    const layout = placeStack(state.explode);
    const aspect = state.width / state.height;
    const frame = inspectorFrame(layout, state.explode);
    const distance = fitDistance({ halfWidth: frame.halfWidth, maxRadius: layout.maxRadius }, aspect, state.camera.yaw,
      FIELD_OF_VIEW, 1.7 - state.explode * .35);
    const eye = cameraOrbitPosition(state.camera, distance);
    const target = [frame.target.x, frame.target.y, frame.target.z];
    const eyeV = [eye.x + target[0], eye.y + target[1], eye.z + target[2]];
    const view = mat4.lookAt(eyeV, target, [0, 1, 0]);
    // Keep depth precision at product-photo distances: the face detail sits
    // just above the machined hub and must not fight it in a long stack.
    const proj = mat4.perspective(FIELD_OF_VIEW * Math.PI / 180, aspect, Math.max(20, distance * .1), 60000);
    // Light: orthographic from the key direction, covering the whole bar.
    const span = Math.max(layout.extent * 1.2, layout.maxRadius * 3);
    const lightView = mat4.lookAt([lightDir[0] * span * 2, lightDir[1] * span * 2, lightDir[2] * span * 2], [0, 0, 0], [0, 1, 0]);
    const lightVP = mat4.multiply(mat4.ortho(-span, span, -span, span, span * 0.2, span * 4.5), lightView);

    // Pass 1: depth from the light.
    gl.bindFramebuffer(gl.FRAMEBUFFER, shadowFB);
    gl.viewport(0, 0, SHADOW, SHADOW);
    gl.clear(gl.DEPTH_BUFFER_BIT);
    gl.enable(gl.DEPTH_TEST); gl.disable(gl.BLEND);
    gl.useProgram(depthProgram);
    gl.uniformMatrix4fv(gl.getUniformLocation(depthProgram, 'uLightVP'), false, lightVP);
    for (const m of meshes) {
      if (m === floor || m.parts[0].material.unlit || m.parts[0].material.photo) continue;
      gl.uniformMatrix4fv(gl.getUniformLocation(depthProgram, 'uModel'), false, m.model);
      gl.bindVertexArray(m.vao);
      for (const part of m.parts) gl.drawElements(gl.TRIANGLES, part.count, gl.UNSIGNED_INT, part.offset * 4);
    }

    // Pass 2: the scene.
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, canvas.width, canvas.height);
    const bg = backdropColour();
    gl.clearColor(bg[0], bg[1], bg[2], 1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.useProgram(program);
    gl.uniformMatrix4fv(U('uProj'), false, proj); gl.uniformMatrix4fv(U('uView'), false, view); gl.uniformMatrix4fv(U('uLightVP'), false, lightVP);
    gl.uniform3fv(U('uEye'), eyeV); gl.uniform3fv(U('uLightDir'), lightDir);
    gl.uniform1f(U('uEnv'), 0.9); gl.uniform1f(U('uShadowAlpha'), 0.22);
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, shadowTex); gl.uniform1i(U('uShadow'), 0);
    gl.uniform1i(U('uTex'), 1); gl.uniform2f(U('uKnurlTile'), 28, 3);
    const draw = (m) => {
      gl.uniformMatrix4fv(U('uModel'), false, m.model);
      gl.bindVertexArray(m.vao);
      for (const part of m.parts) {
        const mat = part.material;
        if (mat.photo && !mat.texture) continue;
        gl.uniform3fv(U('uColor'), mat.colour || [0, 0, 0]);
        gl.uniform1f(U('uMetal'), mat.metal || 0); gl.uniform1f(U('uRough'), mat.rough || 0.5);
        gl.uniform1i(U('uFinish'), mat.finish || 0);
        gl.uniform1i(U('uMode'), mat.floor ? 1 : mat.unlit ? 2 : mat.photo ? 4 : mat.knurl ? 3 : 0);
        gl.uniform1f(U('uHubRatio'), mat.hubRatio || 0); gl.uniform1f(U('uBoreRatio'), mat.boreRatio || 0);
        gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, mat.knurl ? knurlTex : mat.texture || knurlTex);
        gl.drawElements(gl.TRIANGLES, part.count, gl.UNSIGNED_INT, part.offset * 4);
      }
    };
    for (const m of meshes) if (m !== floor && !m.parts[0].material.unlit && !m.parts[0].material.photo) draw(m);
    gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    draw(floor);
    for (const { entry } of photoEntries) draw(entry);
    gl.depthMask(false);
    for (const m of meshes) if (m.parts[0].material.unlit) draw(m);
    gl.depthMask(true); gl.disable(gl.BLEND);
    const vp = mat4.multiply(proj, view);
    onProject(layout.discs.filter(d => d.side < 0).map(d => {
      const point = [d.centerX, -layout.maxRadius - 36, 0, 1];
      const clip = [0, 1, 2, 3].map(row => point.reduce((sum, n, col) => sum + vp[col * 4 + row] * n, 0));
      return { index: d.index, x: (clip[0] / clip[3] + 1) * 50, y: (1 - clip[1] / clip[3]) * 50 };
    }), state.explode === 1);
  }

  function resize() {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.max(1, Math.round(canvas.clientWidth * dpr)), h = Math.max(1, Math.round(canvas.clientHeight * dpr));
    if (w !== canvas.width || h !== canvas.height) { canvas.width = w; canvas.height = h; }
    state.width = w; state.height = h;
  }
  function frame() { resize(); render(); }
  let queued = false;
  const request = () => { if (queued || state.disposed) return; queued = true; requestAnimationFrame(() => { queued = false; frame(); }); };
  const observer = typeof ResizeObserver === 'function' ? new ResizeObserver(request) : null;
  observer?.observe(canvas);

  // Explode/assemble: an animated cut of the explode fraction, instant under
  // Reduce Motion, driven by the same shared layout at every step.
  // The cut moves plates, camera angle, and framing together: straight ahead
  // on the sleeve when assembled, angled and separated when exploded.
  let animationGeneration = 0;
  function setExploded(value) {
    const generation = ++animationGeneration;
    state.target = value ? 1 : 0;
    const camTo = inspectorCamera(value);
    if (state.explode === state.target) { state.camera = camTo; request(); return; }
    if (reduceMotion()) { state.explode = state.target; state.camera = camTo; request(); return; }
    const from = state.explode, to = state.target, camFrom = state.camera, start = performance.now(), duration = 260;
    const step = (now) => {
      if (state.disposed || generation !== animationGeneration) return;
      const t = Math.min(1, (now - start) / duration), eased = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      state.explode = from + (to - from) * eased;
      state.camera = { yaw: camFrom.yaw + (camTo.yaw - camFrom.yaw) * eased, pitch: camFrom.pitch + (camTo.pitch - camFrom.pitch) * eased,
        zoom: camFrom.zoom + (camTo.zoom - camFrom.zoom) * eased };
      frame();
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  function dispose() {
    state.disposed = true; observer?.disconnect();
    gl.getExtension('WEBGL_lose_context')?.loseContext();
  }
  request();
  return { canvas, supported: true, setExploded, render: request, dispose };
}

function link(gl, vertSrc, fragSrc) {
  const compile = (type, src) => {
    const shader = gl.createShader(type); gl.shaderSource(shader, src); gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(`barbell-gl shader: ${gl.getShaderInfoLog(shader)}`);
    return shader;
  };
  const program = gl.createProgram();
  gl.attachShader(program, compile(gl.VERTEX_SHADER, vertSrc)); gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragSrc));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(`barbell-gl link: ${gl.getProgramInfoLog(program)}`);
  return program;
}
