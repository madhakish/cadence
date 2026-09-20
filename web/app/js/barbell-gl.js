// WebGL2 twin of Cadence/Views/BarbellSceneView.swift: the loaded bar as a
// real-time solid built from the shared BarbellInspector model — lathe
// plates from the family profiles, chrome hub inserts, knurled shaft,
// sleeves and collars — lit by a key light with a shadow map and an analytic
// studio environment, with orbit, zoom, animated explode, and backdrops.
// Colours come from the shared plate palette; backdrops from CSS tokens.
// Where WebGL2 is unavailable (jsdom, old browsers) `supported` is false and
// barbell.js keeps the sprite SVG.
import * as C from './core.js';
import { barbellLayout, plateProfile, cameraOrbitPosition, inspectorCamera, orbitCamera, zoomCamera, BORE_RADIUS }
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

export const FIELD_OF_VIEW = 22;   // degrees, vertical: a long lens keeps the bar close to the sprites' look

/// Camera distance at zoom 1 that fits the bar for a viewport aspect and the
/// camera's yaw, the same rule as the SceneKit view. A yawed bar reaches
/// toward the eye by extent·sin(yaw), so the near end must still fit the
/// frame and clear the lens.
export function fitDistance(layout, aspect, yawDeg = 0, verticalFovDeg = FIELD_OF_VIEW) {
  const vertical = verticalFovDeg * Math.PI / 180;
  const horizontal = 2 * Math.atan(Math.tan(vertical / 2) * Math.max(0.5, aspect));
  const yaw = yawDeg * Math.PI / 180, reach = layout.extent * Math.abs(Math.sin(yaw)), across = layout.extent * Math.abs(Math.cos(yaw));
  return reach + Math.max(across * 1.12 / Math.tan(horizontal / 2), layout.maxRadius * 1.7 / Math.tan(vertical / 2));
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
out vec3 vWorld; out vec3 vNormal; out vec2 vUV; out vec4 vLight;
void main() {
  vec4 world = uModel * vec4(aPos, 1.0);
  vWorld = world.xyz; vNormal = mat3(uModel) * aNormal; vUV = aUV; vLight = uLightVP * world;
  gl_Position = uProj * uView * world;
}`;

const FRAG = `#version 300 es
precision highp float; precision highp sampler2DShadow;
in vec3 vWorld; in vec3 vNormal; in vec2 vUV; in vec4 vLight;
uniform vec3 uColor; uniform float uMetal, uRough, uEnv, uShadowAlpha;
uniform vec3 uEye, uLightDir;
uniform int uMode;            // 0 lit, 1 floor shadow catcher, 2 unlit texture, 3 lit + knurl normal map
uniform sampler2DShadow uShadow; uniform sampler2D uTex; uniform vec2 uKnurlTile;
out vec4 fragColor;
const float PI = 3.14159265;
// The studio: dark floor, mid horizon, bright ceiling with an overhead
// softbox band and two side softboxes, the rig the sprites were lit with.
float studio(vec3 d, float rough) {
  float y = d.y;
  float base = y < 0.0 ? mix(0.10, 0.34, y + 1.0) : mix(0.34, 0.82, y);
  float band = smoothstep(0.70, 0.74, y) * (1.0 - smoothstep(0.86, 0.90, y));
  float az = atan(d.z, d.x);
  float side = (1.0 - smoothstep(0.30, 0.45, abs(abs(az) - 2.0))) * smoothstep(0.05, 0.12, y) * (1.0 - smoothstep(0.48, 0.55, y));
  float sharp = 1.0 - rough * 0.7;
  return base + band * 0.9 * sharp + side * 0.8 * sharp;
}
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
  vec3 N = normalize(vNormal);
  if (uMode == 3) {
    vec3 T = normalize(cross(vec3(1.0, 0.0, 0.0), N)); vec3 B = cross(N, T);
    vec3 nm = texture(uTex, vUV * uKnurlTile).xyz * 2.0 - 1.0;
    N = normalize(T * nm.x + B * nm.y + N * nm.z);
  }
  vec3 V = normalize(uEye - vWorld); vec3 L = normalize(uLightDir); vec3 H = normalize(L + V);
  float NdotL = max(dot(N, L), 0.0), NdotV = max(dot(N, V), 1e-3), NdotH = max(dot(N, H), 0.0), VdotH = max(dot(V, H), 0.0);
  vec3 F0 = mix(vec3(0.04), uColor, uMetal); vec3 albedo = uColor * (1.0 - uMetal);
  float a = max(uRough * uRough, 0.002), a2 = a * a;
  float D = a2 / (PI * pow(NdotH * NdotH * (a2 - 1.0) + 1.0, 2.0));
  float k = (uRough + 1.0) * (uRough + 1.0) / 8.0;
  float G = (NdotV / (NdotV * (1.0 - k) + k)) * (NdotL / (NdotL * (1.0 - k) + k));
  vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
  vec3 spec = D * G * F / max(4.0 * NdotL * NdotV, 1e-3);
  float visibility = shadowAt(vLight);
  vec3 key = (albedo / PI + spec) * NdotL * 3.0 * visibility;
  vec3 R = reflect(-V, N);
  vec3 Fr = F0 + (max(vec3(1.0 - uRough), F0) - F0) * pow(1.0 - NdotV, 5.0);
  vec3 ambient = albedo * studio(N, 1.0) * uEnv + Fr * studio(R, uRough) * uEnv;
  vec3 colour = key + ambient;
  colour = colour / (colour + 1.0);
  fragColor = vec4(pow(colour, vec3(1.0 / 2.2)), 1.0);
}`;

const DEPTH_VERT = `#version 300 es
in vec3 aPos; uniform mat4 uLightVP, uModel;
void main() { gl_Position = uLightVP * uModel * vec4(aPos, 1.0); }`;
const DEPTH_FRAG = `#version 300 es
precision highp float; void main() {}`;

// ---------------------------------------------------------------- textures

const hexToRGB = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
const BACKDROP_FALLBACK = { studio: '#1b1d21', dark: '#0a0b0d', paper: '#e6e2da' };
export const BACKDROPS = Object.freeze({
  studio: { label: 'Studio', env: 1.15, shadow: 0.6 },
  dark: { label: 'Dark', env: 0.85, shadow: 0.6 },
  paper: { label: 'Paper', env: 1.35, shadow: 0.35 },
});

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
    const dx = (h(x + 1, y) - h(x - 1, y)) * 1.6, dy = (h(x, y + 1) - h(x, y - 1)) * 1.6;
    const l = Math.hypot(dx, dy, 1), i = (y * n + x) * 4;
    out[i] = (-dx / l * 0.5 + 0.5) * 255; out[i + 1] = (-dy / l * 0.5 + 0.5) * 255; out[i + 2] = (1 / l * 0.5 + 0.5) * 255; out[i + 3] = 255;
  }
  return { data: out, size: n };
}

/// The denomination as an alpha texture, printed on the outward face.
function labelTexture(text) {
  const cv = document.createElement('canvas'); cv.width = 256; cv.height = 128;
  const ctx = cv.getContext('2d');
  ctx.clearRect(0, 0, cv.width, cv.height);
  ctx.fillStyle = '#fff'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.font = '900 96px system-ui, -apple-system, "Segoe UI", sans-serif';
  ctx.fillText(text, cv.width / 2, cv.height / 2 + 4);
  return cv;
}

// ---------------------------------------------------------------- renderer

export function barbellGL(solution, style = 'steel', { exploded = true, backdrop = 'studio' } = {}) {
  const canvas = document.createElement('canvas');
  canvas.className = 'barbell-gl';
  // jsdom and old browsers have no WebGL2 at all; asking would only log.
  const gl = typeof WebGL2RenderingContext === 'function'
    ? canvas.getContext('webgl2', { antialias: true, alpha: false, premultipliedAlpha: true }) : null;
  if (!gl) return { canvas, supported: false };

  const program = link(gl, VERT, FRAG), depthProgram = link(gl, DEPTH_VERT, DEPTH_FRAG);
  const U = (name) => gl.getUniformLocation(program, name);
  const meshes = [];      // { vao, model, parts: [{ offset, count, material }] }
  const layouts = { closed: barbellLayout(solution, style, 0), open: barbellLayout(solution, style, 1) };

  const plateColour = (plate) => C.plateColour(C.plateColorToken(plate, style));
  const M = {
    chrome: { colour: [0.92, 0.92, 0.92], metal: 1, rough: 0.22 },
    shaft: { colour: [0.78, 0.78, 0.78], metal: 1, rough: 0.4 },
    knurl: { colour: [0.7, 0.7, 0.7], metal: 1, rough: 0.58, knurl: true },
    collar: { colour: [0.16, 0.16, 0.16], metal: 0.4, rough: 0.55 },
    plate: (family, fill) => family === 'bumper' ? { colour: hexToRGB(fill), metal: 0, rough: 0.62 }
      : family === 'change' ? { colour: hexToRGB(fill), metal: 0.75, rough: 0.38 } : { colour: hexToRGB(fill), metal: 0.35, rough: 0.5 },
  };

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
  add(cylinderMesh(bar.shaftRadius, bar.shaftHalfLength * 2), 0, M.shaft);
  for (const side of [-1, 1]) {
    add(cylinderMesh(bar.shaftRadius + 0.15, 310), side * (bar.shaftHalfLength - 190), M.knurl);
    add(cylinderMesh(bar.sleeveRadius, bar.sleeveLength), side * (bar.shaftHalfLength + bar.sleeveLength / 2), M.chrome);
    add(cylinderMesh(bar.shoulderRadius, bar.shoulderLength), side * (bar.shaftHalfLength + bar.shoulderLength / 2), M.chrome);
  }
  // Plates: lathe per disc, hub as its own range, denomination quad on the outward face.
  const discEntries = [], labelEntries = [];
  for (const disc of layouts.closed.discs) {
    const profile = plateProfile(disc.family, disc.radius * 2, disc.thickness);
    const mesh = latheMesh(profile, 96, 2);
    const colour = plateColour(disc.plate);
    const entry = add(mesh, disc.centerX, null, [
      { offset: 0, count: mesh.hubCount, material: M.chrome },
      { offset: mesh.hubCount, count: mesh.bodyCount, material: M.plate(disc.family, colour.fill) },
    ]);
    discEntries.push({ disc, entry });
    const R = disc.radius;
    const hub = disc.family === 'bumper' ? 0.235 * R : disc.family === 'steel' ? 0.2 * R : Math.max(BORE_RADIUS + 8, 0.25 * R);
    const rim = disc.family === 'bumper' ? 0.9 * R : disc.family === 'steel' ? 0.86 * R : R;
    const cap = (rim - hub) * 0.32, w = cap * 2.2;
    const faceOffset = disc.family === 'bumper' ? disc.thickness / 2 - 0.14 * disc.thickness : disc.thickness / 2;
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
    const label = add(quad, disc.centerX, { colour: hexToRGB(colour.ink), unlit: labelTexture(C.trim(disc.plate.value, 2)) });
    labelEntries.push({ disc, entry: label });
  }
  const collarEntries = [];
  if (solution.collarLb > 0) {
    const half = layouts.closed.collar.length / 2;
    for (const x of [layouts.closed.collar.left - half, layouts.closed.collar.right + half]) {
      collarEntries.push(add(cylinderMesh(layouts.closed.collar.radius, layouts.closed.collar.length), x, M.collar));
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
    explode: exploded ? 1 : 0, target: exploded ? 1 : 0, camera: inspectorCamera(exploded), backdrop,
    width: 1, height: 1, animating: null, disposed: false,
  };
  const lightDir = norm3([-0.55, 1, 0.7]);
  const reduceMotion = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  // Backdrop colours are theme tokens (--scene-studio/-dark/-paper in
  // styles.css, mirrored by Theme.swift); the fallbacks are the same values.
  const backdropColour = (name) => {
    const css = canvas.isConnected ? getComputedStyle(canvas).getPropertyValue(`--scene-${name}`).trim() : '';
    return hexToRGB(/^#[0-9a-f]{6}$/i.test(css) ? css : BACKDROP_FALLBACK[name] || BACKDROP_FALLBACK.studio);
  };

  function placeStack(fraction) {
    const layout = barbellLayout(solution, style, fraction);
    for (const { disc, entry } of discEntries) {
      const target = layout.discs.find((d) => d.side === disc.side && d.index === disc.index);
      entry.model = mat4.translation(target.centerX, 0, 0);
    }
    for (const { disc, entry } of labelEntries) {
      const target = layout.discs.find((d) => d.side === disc.side && d.index === disc.index);
      entry.model = mat4.translation(target.centerX, 0, 0);
    }
    if (collarEntries.length === 2) {
      const half = layout.collar.length / 2;
      collarEntries[0].model = mat4.translation(layout.collar.left - half, 0, 0);
      collarEntries[1].model = mat4.translation(layout.collar.right + half, 0, 0);
    }
    return layout;
  }

  function render() {
    if (state.disposed) return;
    const layout = placeStack(state.explode);
    const aspect = state.width / state.height;
    const eye = cameraOrbitPosition(state.camera, fitDistance(layout, aspect, state.camera.yaw));
    const eyeV = [eye.x, eye.y, eye.z];
    const view = mat4.lookAt(eyeV, [0, 0, 0], [0, 1, 0]);
    const proj = mat4.perspective(FIELD_OF_VIEW * Math.PI / 180, aspect, 20, 60000);
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
      if (m === floor || m.parts[0].material.unlit) continue;
      gl.uniformMatrix4fv(gl.getUniformLocation(depthProgram, 'uModel'), false, m.model);
      gl.bindVertexArray(m.vao);
      for (const part of m.parts) gl.drawElements(gl.TRIANGLES, part.count, gl.UNSIGNED_INT, part.offset * 4);
    }

    // Pass 2: the scene.
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, canvas.width, canvas.height);
    const bg = backdropColour(state.backdrop), preset = BACKDROPS[state.backdrop] || BACKDROPS.studio;
    gl.clearColor(bg[0], bg[1], bg[2], 1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.useProgram(program);
    gl.uniformMatrix4fv(U('uProj'), false, proj); gl.uniformMatrix4fv(U('uView'), false, view); gl.uniformMatrix4fv(U('uLightVP'), false, lightVP);
    gl.uniform3fv(U('uEye'), eyeV); gl.uniform3fv(U('uLightDir'), lightDir);
    gl.uniform1f(U('uEnv'), preset.env); gl.uniform1f(U('uShadowAlpha'), preset.shadow);
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, shadowTex); gl.uniform1i(U('uShadow'), 0);
    gl.uniform1i(U('uTex'), 1); gl.uniform2f(U('uKnurlTile'), 28, 3);
    const draw = (m) => {
      gl.uniformMatrix4fv(U('uModel'), false, m.model);
      gl.bindVertexArray(m.vao);
      for (const part of m.parts) {
        const mat = part.material;
        gl.uniform3fv(U('uColor'), mat.colour || [0, 0, 0]);
        gl.uniform1f(U('uMetal'), mat.metal || 0); gl.uniform1f(U('uRough'), mat.rough || 0.5);
        gl.uniform1i(U('uMode'), mat.floor ? 1 : mat.unlit ? 2 : mat.knurl ? 3 : 0);
        gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, mat.knurl ? knurlTex : mat.texture || knurlTex);
        gl.drawElements(gl.TRIANGLES, part.count, gl.UNSIGNED_INT, part.offset * 4);
      }
    };
    for (const m of meshes) if (m !== floor && !m.parts[0].material.unlit) draw(m);
    gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    draw(floor);
    gl.depthMask(false);
    for (const m of meshes) if (m.parts[0].material.unlit) draw(m);
    gl.depthMask(true); gl.disable(gl.BLEND);
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
  function setExploded(value) {
    state.target = value ? 1 : 0;
    if (state.explode === state.target) { request(); return; }
    if (reduceMotion()) { state.explode = state.target; request(); return; }
    const from = state.explode, to = state.target, start = performance.now(), duration = 420;
    const step = (now) => {
      if (state.disposed || state.target !== to) return;
      const t = Math.min(1, (now - start) / duration), eased = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      state.explode = from + (to - from) * eased;
      frame();
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  // Pointer interaction: drag orbits, wheel and pinch zoom, double click
  // resets. A drag swallows the click that would otherwise flip the stage.
  let drag = null, pinch = null, moved = false;
  const pointers = new Map();
  canvas.addEventListener('pointerdown', (event) => {
    canvas.setPointerCapture(event.pointerId);
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.size === 1) { drag = { x: event.clientX, y: event.clientY, camera: state.camera }; moved = false; }
    else if (pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      pinch = { distance: Math.hypot(a.x - b.x, a.y - b.y), camera: state.camera }; drag = null;
    }
  });
  canvas.addEventListener('pointermove', (event) => {
    if (!pointers.has(event.pointerId)) return;
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pinch && pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      const factor = Math.hypot(a.x - b.x, a.y - b.y) / (pinch.distance || 1);
      state.camera = zoomCamera(pinch.camera, factor); moved = true; request();
    } else if (drag) {
      const dx = event.clientX - drag.x, dy = event.clientY - drag.y;
      if (Math.hypot(dx, dy) > 6) moved = true;
      if (moved) { state.camera = orbitCamera(drag.camera, dx * 0.35, -dy * 0.3); request(); }
    }
  });
  const release = (event) => {
    pointers.delete(event.pointerId);
    if (pointers.size < 2) pinch = null;
    if (pointers.size === 0) drag = null;
  };
  canvas.addEventListener('pointerup', release); canvas.addEventListener('pointercancel', release);
  canvas.addEventListener('click', (event) => { if (moved) { event.stopPropagation(); moved = false; } }, true);
  canvas.addEventListener('dblclick', (event) => { event.preventDefault(); reset(); });
  canvas.addEventListener('wheel', (event) => {
    event.preventDefault();
    state.camera = zoomCamera(state.camera, Math.exp(-event.deltaY * 0.0015)); request();
  }, { passive: false });

  function reset() { state.camera = inspectorCamera(state.target === 1); request(); }
  function setBackdrop(name) { if (BACKDROPS[name]) { state.backdrop = name; request(); } }
  function dispose() {
    state.disposed = true; observer?.disconnect();
    gl.getExtension('WEBGL_lose_context')?.loseContext();
  }
  request();
  return { canvas, supported: true, setExploded, setBackdrop, reset, render: request, dispose,
    getCamera: () => state.camera, setCamera: (camera) => { state.camera = camera; request(); } };
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
