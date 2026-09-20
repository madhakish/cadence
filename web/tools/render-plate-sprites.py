#!/usr/bin/env python3
"""Render the loaded-bar sprite family: plates per denomination at the scene's
two angles, plus shaft, sleeve, and collar. A small signed-distance ray
marcher with a studio light rig; deterministic (no random sampling), so a
re-run reproduces every byte. Plates render greyscale and are colourised at
runtime by the shared luminance matrix; hubs and bar parts stay untinted.

  python3 web/tools/render-plate-sprites.py --prototype <dir>   # a few sprites for review
  python3 web/tools/render-plate-sprites.py <dir>               # the full family + manifest
"""
import json, math, os, sys
import numpy as np
from PIL import Image

# ---------- geometry ---------------------------------------------------------
# Plate diameters / thicknesses in millimetres, mirrored from BarbellScene
# reference profiles (PlateGeometry.reference). Rendering scales everything by
# the plate radius, so the sprite frame is the same for every denomination.
BUMPER = {"25-kg": (450, 70), "20-kg": (450, 60), "15-kg": (450, 48), "10-kg": (450, 35), "5-kg": (450, 25),
          "55-lb": (450, 75), "45-lb": (450, 65), "35-lb": (450, 52), "25-lb": (450, 40), "10-lb": (450, 25)}
STEEL = {"25-kg": (450, 27), "20-kg": (450, 22), "15-kg": (400, 21), "10-kg": (325, 20), "5-kg": (230, 20),
         "55-lb": (450, 30), "45-lb": (450, 27), "35-lb": (400, 25), "25-lb": (325, 23), "10-lb": (230, 20)}
CHANGE = {"2.5-kg": (210, 19), "2-kg": (190, 19), "1.5-kg": (175, 18), "1.25-kg": (160, 16), "1-kg": (160, 16),
          "0.5-kg": (135, 12), "5-lb": (190, 19), "2.5-lb": (160, 16), "1.25-lb": (135, 12)}
ANGLES = {"assembled": 18.0, "exploded": 38.0}   # BarbellScene's two projections
ELEVATION = math.degrees(math.asin(0.24))      # BarbellScene skews the axis by 0.24·tan(yaw): the same slope
UNIT = 450 * 0.18                                # scene units per plate radius (BarbellScene: radius = diameter × 0.18)
BAR_RADIUS = 28 / 450                            # 28 mm shaft on a 450 mm plate → in plate-radius units
SLEEVE_RADIUS = 50 / 450

# ---------- SDF helpers ----------------------------------------------------------
def length(v):
    return np.sqrt((v * v).sum(-1))

def sd_cyl_x(p, r, h):
    """Cylinder along x: radius r, half-length h (exact SDF)."""
    d = np.stack([np.hypot(p[..., 1], p[..., 2]) - r, np.abs(p[..., 0]) - h], -1)
    return np.minimum(np.maximum(d[..., 0], d[..., 1]), 0) + length(np.maximum(d, 0))

def sd_round_cyl_x(p, r, h, e):
    return sd_cyl_x(p, r - e, h - e) - e

def plate_sdf(family, d_mm, t_mm):
    """Returns (distance, material) for a plate of radius 1 with proportional
    thickness. `d_mm` is the plate DIAMETER (the shape key is diameter×thickness);
    every proportion below is in plate radii. Materials: 0 body (rubber or
    steel), 1 chrome hub, 2 bore."""
    R = 1.0
    r_mm = d_mm / 2
    h = (t_mm / 2) / r_mm            # half thickness in plate radii
    bore_r = 25.25 / r_mm            # 50.5 mm Olympic bore → radius
    hub_r = 0.235 if family == "bumper" else 0.2
    edge = 0.06 if family == "bumper" else 0.018

    def f(p):
        rho = np.hypot(p[..., 1], p[..., 2])
        body = sd_round_cyl_x(p, R, h, min(edge, h * 0.9))
        if family == "bumper":
            # raised outer rim: recess the face between the hub collar and 0.9R
            depth = h * 0.14
            recess = np.maximum(np.maximum(rho - 0.88, -(rho - 0.3)), (h - depth) - np.abs(p[..., 0]))
            body = np.maximum(body, -recess)
        else:
            # machined step just inside the rim and a shallow face dish
            depth = h * 0.12
            recess = np.maximum(np.maximum(rho - 0.86, -(rho - 0.34)), (h - depth) - np.abs(p[..., 0]))
            body = np.maximum(body, -recess)
        body = np.maximum(body, -(rho - bore_r))                       # bore
        hub = np.maximum(np.maximum(rho - hub_r, -(rho - bore_r)), np.abs(p[..., 0]) - (h + 0.006))
        hub = hub - 0.004                                               # tiny edge round
        d = np.minimum(body, hub)
        mat = np.where(hub < body, 1, 0)
        return d, mat
    return f, h

# Scene proportions (BarbellScene, 20 kg / 45 lb bar): shoulders at ±165,
# sleeve to ±315, knurl from ±42 to ±141 — expressed in plate radii here.
SHOULDER = 165 / UNIT
SLEEVE_END = 315 / UNIT
KNURL_IN, KNURL_OUT = 42 / UNIT, 141 / UNIT

def bar_sdf(kind):
    """Shaft between the shoulders (radius BAR_RADIUS, along x, knurled),
    sleeve from shoulder to end, or a collar ring. Material 3 = bar steel,
    4 = knurl."""
    def f(p):
        x = p[..., 0]
        if kind == "shaft":
            d = sd_cyl_x(p, BAR_RADIUS, SHOULDER)
            knurl = (np.abs(x) > KNURL_IN) & (np.abs(x) < KNURL_OUT)
            return d, np.where(knurl, 4, 3)
        if kind in ("sleeve", "sleeve-near"):
            q = p if kind == "sleeve" else p * np.array([-1, 1, 1])   # mirror for the near sleeve
            half = (SLEEVE_END - SHOULDER) / 2
            sleeve = sd_round_cyl_x(q - np.array([half, 0, 0]), SLEEVE_RADIUS, half, 0.012)
            shoulder = sd_round_cyl_x(q - np.array([0.03, 0, 0]), SLEEVE_RADIUS * 1.3, 0.06, 0.015)
            shaft = sd_cyl_x(q + np.array([0.4, 0, 0]), BAR_RADIUS, 0.45)
            d = np.minimum(np.minimum(sleeve, shoulder), shaft)
            return d, np.full(d.shape, 3)
        if kind in ("collar", "collar-near"):
            rho = np.hypot(p[..., 1], p[..., 2])
            ring = np.maximum(np.maximum(rho - SLEEVE_RADIUS * 1.55, -(rho - SLEEVE_RADIUS * 0.98)), np.abs(x) - 0.075) - 0.01
            lever = sd_round_cyl_x(np.stack([p[..., 0], p[..., 1] - SLEEVE_RADIUS * 1.9, p[..., 2]], -1), 0.03, 0.03, 0.01)
            d = np.minimum(ring, lever)
            return d, np.full(d.shape, 3)
        raise ValueError(kind)
    return f

# ---------- camera + shading -------------------------------------------------------
def camera(yaw_deg, elev_deg, distance, width, height, fov_deg):
    yaw, elev = math.radians(yaw_deg), math.radians(elev_deg)
    eye = np.array([-distance * math.cos(elev) * math.sin(yaw), distance * math.sin(elev), distance * math.cos(elev) * math.cos(yaw)])
    fwd = -eye / np.linalg.norm(eye)
    right = np.cross(fwd, np.array([0, 1.0, 0])); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    aspect = width / height
    tan = math.tan(math.radians(fov_deg) / 2)
    ys, xs = np.mgrid[0:height, 0:width]
    u = (xs + 0.5) / width * 2 - 1
    v = 1 - (ys + 0.5) / height * 2
    dirs = fwd[None, None] + (u * tan * aspect)[..., None] * right[None, None] + (v * tan)[..., None] * up[None, None]
    dirs /= length(dirs)[..., None]
    return eye, dirs, (fwd, right, up, tan, aspect)

def project(point, eye, basis, width, height):
    fwd, right, up, tan, aspect = basis
    rel = point - eye
    z = rel @ fwd
    x = (rel @ right) / (z * tan * aspect)
    y = (rel @ up) / (z * tan)
    return ((x + 1) / 2 * width, (1 - y) / 2 * height)

def march(sdf, eye, dirs, steps=160, tmax=12.0, eps=6e-4):
    t = np.zeros(dirs.shape[:-1])
    hit = np.zeros_like(t, dtype=bool)
    mat = np.zeros_like(t, dtype=int)
    active = np.ones_like(hit)
    for _ in range(steps):
        p = eye + dirs * t[..., None]
        d, m = sdf(p)
        newly = active & (d < eps)
        hit |= newly; mat = np.where(newly, m, mat)
        active &= ~newly & (t < tmax)
        t = np.where(active, t + np.maximum(d, eps) * 0.85, t)
        if not active.any():
            break
    return t, hit, mat

def normal(sdf, p, e=1.5e-3):
    n = np.zeros_like(p)
    for i in range(3):
        o = np.zeros(3); o[i] = e
        n[..., i] = sdf(p + o)[0] - sdf(p - o)[0]
    return n / np.maximum(length(n), 1e-9)[..., None]

def soft_shadow(sdf, p, light_dir, k=10.0, steps=18, tmax=2.5):
    res = np.ones(p.shape[:-1])
    t = np.full(p.shape[:-1], 0.02)
    for _ in range(steps):
        d = sdf(p + light_dir * t[..., None])[0]
        res = np.minimum(res, k * d / t)
        t = t + np.clip(d, 0.01, 0.2)
        if (t > tmax).all():
            break
    return np.clip(res, 0, 1)

def ambient_occlusion(sdf, p, n):
    occ = 0.0
    for i, s in enumerate([0.02, 0.05, 0.1, 0.18]):
        d = sdf(p + n * s)[0]
        occ += (s - d) * (0.55 ** i)
    return np.clip(1 - 3.0 * occ, 0, 1)

def ggx(n, v, l, roughness, f0):
    h = v + l; h /= np.maximum(length(h), 1e-9)[..., None]
    ndl = np.clip((n * l).sum(-1), 0, 1); ndv = np.clip((n * v).sum(-1), 1e-4, 1)
    ndh = np.clip((n * h).sum(-1), 0, 1); vdh = np.clip((v * h).sum(-1), 0, 1)
    a2 = roughness ** 4
    D = a2 / (math.pi * (ndh * ndh * (a2 - 1) + 1) ** 2)
    k = (roughness + 1) ** 2 / 8
    G = (ndv / (ndv * (1 - k) + k)) * (ndl / (ndl * (1 - k) + k))
    F = f0 + (1 - f0) * (1 - vdh) ** 5
    return D * G * F / np.maximum(4 * ndv * ndl, 1e-4) * ndl, ndl

LIGHTS = [  # softbox position (plate radii), intensity at 3 radii — close lights give a flat face its gradient
    (np.array([-2.4, 2.8, 2.6]), 3.6),   # key: high, left, in front
    (np.array([3.2, 0.4, 2.4]), 0.55),   # fill: low right
    (np.array([0.8, 2.2, -2.8]), 1.4),   # rim: behind, above
]

MATERIALS = {  # albedo, roughness, f0 (specular at normal incidence), metallic
    0: dict(albedo=0.56, rough=0.48, f0=0.05, metal=0.0),    # rubber (greyscale; colourised at runtime)
    1: dict(albedo=0.92, rough=0.16, f0=0.92, metal=1.0),    # chrome hub
    3: dict(albedo=0.88, rough=0.2, f0=0.9, metal=1.0),      # bar steel
    4: dict(albedo=0.84, rough=0.3, f0=0.85, metal=1.0),     # knurled shaft
}

def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def environment(n):
    """Studio: a wide overhead softbox band (what chrome reflects as its bright
    stripe), a faint front fill, and a near-black floor."""
    up = np.clip(n[..., 1], -1, 1)
    front = np.clip(n[..., 2], -1, 1)
    band = smoothstep(0.18, 0.55, up) * (1 - smoothstep(0.82, 0.98, up)) * smoothstep(-0.35, 0.15, front)
    return 0.035 + 0.85 * band + 0.06 * np.clip(front, 0, 1) ** 2 + 0.10 * np.clip(up, 0, 1) ** 3

def shade(sdf, eye, dirs, t, hit, mat, family_bump=None):
    # Shade only the pixels that hit geometry: bar frames are mostly empty,
    # and every light's shadow march was being paid for the background too.
    full = np.zeros(t.shape)
    if not hit.any():
        return full
    dirs, t, mat = dirs[hit], t[hit], mat[hit]
    p = eye + dirs * t[..., None]
    n = normal(sdf, p)
    if family_bump is not None:
        n = family_bump(p, n, mat)
        n /= np.maximum(length(n), 1e-9)[..., None]
    v = -dirs
    ao = ambient_occlusion(sdf, p, n)
    out = np.zeros(t.shape)
    for mid, props in MATERIALS.items():
        m = mat == mid
        if not m.any():
            continue
        albedo, rough, f0, metal = props["albedo"], props["rough"], props["f0"], props["metal"]
        colour = environment(n) * albedo * ao * (0.25 if metal else 0.9)
        # metals reflect the environment: sample it along the mirror direction,
        # blurred by roughness through a small cone of samples
        if metal:
            refl = dirs - 2 * (dirs * n).sum(-1)[..., None] * n
            refl /= np.maximum(length(refl), 1e-9)[..., None]
            gathered = 0.0
            for dy, dz in ((0, 0), (rough * 0.5, 0), (-rough * 0.5, 0), (0, rough * 0.5), (0, -rough * 0.5)):
                sample = refl + np.array([0, dy, dz])
                gathered = gathered + environment(sample / np.maximum(length(sample), 1e-9)[..., None])
            colour = colour + gathered / 5 * albedo * ao
        for lpos, intensity in LIGHTS:
            to_light = lpos - p
            dist = np.maximum(length(to_light), 1e-6)
            l = to_light / dist[..., None]
            spec, ndl = ggx(n, v, l, rough, f0)
            shadow = soft_shadow(sdf, p + n * 0.01, l)
            falloff = intensity * 9.0 / (dist * dist)
            diffuse = 0 if metal else albedo / math.pi * ndl
            colour = colour + falloff * shadow * (diffuse + spec * (0.9 if metal else 0.6))
        out = np.where(m, colour, out)
    full[hit] = out
    return full

def bumps(family):
    """Surface grain: rubber pebble on bumpers, fine turning marks on steel,
    knurl on the shaft. Deterministic hash noise, no random state."""
    def noise(p, scale):
        q = p * scale
        i = np.floor(q); f = q - i
        def h(o):
            v = (i + o) @ np.array([127.1, 311.7, 74.7])
            return np.modf(np.sin(v) * 43758.5453)[0]
        f = f * f * (3 - 2 * f)
        a = h([0, 0, 0]); b = h([1, 0, 0]); c = h([0, 1, 0]); d = h([1, 1, 0])
        e = h([0, 0, 1]); g = h([1, 0, 1]); k = h([0, 1, 1]); l = h([1, 1, 1])
        x1 = a + (b - a) * f[..., 0]; x2 = c + (d - c) * f[..., 0]; y1 = x1 + (x2 - x1) * f[..., 1]
        x3 = e + (g - e) * f[..., 0]; x4 = k + (l - k) * f[..., 0]; y2 = x3 + (x4 - x3) * f[..., 1]
        return y1 + (y2 - y1) * f[..., 2]
    def apply(p, n, mat):
        body = (mat == 0)[..., None]
        if family == "bumper":
            g = noise(p, 90.0) - 0.5
            grad = np.stack([noise(p + [1e-3, 0, 0], 90.0) - g - 0.5, noise(p + [0, 1e-3, 0], 90.0) - g - 0.5, noise(p + [0, 0, 1e-3], 90.0) - g - 0.5], -1)
            return np.where(body, n + grad * 0.35, n)
        if family in ("steel", "change"):
            rho = np.hypot(p[..., 1], p[..., 2])
            ring = np.sin(rho * 260.0) * 0.06
            radial = np.stack([np.zeros_like(rho), p[..., 1] / np.maximum(rho, 1e-6), p[..., 2] / np.maximum(rho, 1e-6)], -1)
            face = body & (np.abs(n[..., 0]) > 0.8)[..., None]
            return np.where(face, n + radial * ring[..., None], n)
        if family == "shaft":
            phi = np.arctan2(p[..., 2], p[..., 1])
            x = p[..., 0]
            k = np.sin(x * 260 + phi * 14) * np.sin(x * 260 - phi * 14)
            tangent = np.stack([np.ones_like(x), np.zeros_like(x), np.zeros_like(x)], -1)
            around = np.stack([np.zeros_like(x), -np.sin(phi), np.cos(phi)], -1)
            knurl = (mat == 4)[..., None]
            ripple = tangent * np.cos(x * 260)[..., None] + around * np.sin(phi * 14)[..., None]
            return np.where(knurl, n + ripple * 0.22 * k[..., None], n)
        return n
    return apply

QUICK = False

def render(sdf, bump, yaw, size, fov, distance, ss=2, centre=None):
    """`size` is (width, height) in output pixels."""
    width, height = size
    if QUICK:
        width, height, ss = width // 2, height // 2, 1
    W, H = width * ss, height * ss
    eye, dirs, basis = camera(yaw, ELEVATION, distance, W, H, fov)
    if centre is not None:
        eye = eye + centre
    t, hit, mat = march(sdf, eye, dirs, tmax=distance + 6.0)
    colour = shade(sdf, eye, dirs, t, hit, mat, bump)
    grey = np.clip(colour, 0, 1) ** (1 / 2.2)
    rgba = np.zeros((H, W, 4))
    rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = np.where(hit, grey, 0)
    rgba[..., 3] = hit
    img = Image.fromarray((rgba * 255).astype(np.uint8)).resize((width, height), Image.LANCZOS)
    return img, (eye, basis, width, height)

def framing(extent, distance):
    """FOV that fits `extent` (plate radii, half-size) at `distance` with 8% margin."""
    return math.degrees(2 * math.atan(extent * 1.08 / distance))

def render_plate(family, key, angle_name, size=512):
    d_mm, t_mm = (int(v) for v in key.split("x"))
    sdf, h = plate_sdf(family, d_mm, t_mm)
    yaw = ANGLES[angle_name]
    distance = 16.0
    fov = framing(1.05, distance)
    img, (eye, basis, W, H) = render(sdf, bumps(family), yaw, (size, size), fov, distance)
    # metadata: where the front face centre and its vertical radius land, in sprite pixels
    front = np.array([-h, 0, 0])   # the face turned toward the camera (camera sits at negative x)
    cx, cy = project(front, eye, basis, W, H)
    _, top = project(front + np.array([0, 1, 0]), eye, basis, W, H)
    return img, dict(family=family, shape=key, angle=angle_name, faceCenter=[round(cx, 2), round(cy, 2)],
                     faceRadius=round(cy - top, 2), hubRadius=0.235 if family == "bumper" else 0.2, size=[W, H])

def render_bar(kind, angle_name):
    sdf = bar_sdf(kind)
    yaw = ANGLES[angle_name]
    span = {"shaft": (-SHOULDER, SHOULDER), "sleeve": (0.0, SLEEVE_END - SHOULDER),
            "sleeve-near": (-(SLEEVE_END - SHOULDER), 0.0), "collar": (-0.09, 0.09), "collar-near": (-0.09, 0.09)}[kind]
    # wide frames: a shaft in a square frame would waste most of its pixels
    size = {"shaft": (1600, 320), "sleeve": (900, 300), "sleeve-near": (900, 300), "collar": (320, 320), "collar-near": (320, 320)}[kind]
    centre = np.array([(span[0] + span[1]) / 2, 0, 0])
    extent = max(span[1] - span[0], 0.6)
    distance = max(16.0, extent * 8.0)
    # frame the span across the wide axis; the height follows the aspect ratio
    fov = framing(extent / 2 / (size[0] / size[1]) * 1.05, distance)
    img, (eye, basis, W, H) = render(sdf, bumps("shaft") if kind == "shaft" else None, yaw, size, fov, distance, centre=centre)
    a = project(np.array([span[0], 0, 0]), eye, basis, W, H)
    b = project(np.array([span[1], 0, 0]), eye, basis, W, H)
    return img, dict(kind=kind, angle=angle_name, size=[W, H],
                     axisStart=[round(a[0], 2), round(a[1], 2)], axisEnd=[round(b[0], 2), round(b[1], 2)],
                     spanUnits=round((span[1] - span[0]) * UNIT, 2))

def hub_only(img_pair):
    pass

if __name__ == "__main__":
    args = sys.argv[1:]
    prototype = "--prototype" in args
    QUICK = "--quick" in args
    bars_only = "--bars-only" in args
    plates_only = "--plates-only" in args
    out = [a for a in args if not a.startswith("--")][0]
    os.makedirs(out, exist_ok=True)
    manifest = []
    shapes = {}
    for family, table in (("bumper", BUMPER), ("steel", STEEL), ("change", CHANGE)):
        for plate, (dia, thick) in table.items():
            shapes.setdefault((family, f"{dia}x{thick}"), []).append(plate)
    if prototype:
        jobs = [("bumper", "450x60"), ("steel", "450x27"), ("change", "160x16")]
    else:
        jobs = sorted(shapes)
    angles = list(ANGLES)
    for family, key in ([] if bars_only else jobs):
        for angle in angles:
            img, meta = render_plate(family, key, angle)
            name = f"plate-{family}-{key}-{angle}.png"
            img.save(os.path.join(out, name), optimize=True)
            manifest.append(dict(file=name, **meta)); print("rendered", name, flush=True)
    kinds = () if plates_only else ("sleeve-near", "collar-near") if "--near-only" in args else ("shaft", "sleeve", "collar", "sleeve-near", "collar-near")
    for kind in kinds:
        for angle in angles:
            img, meta = render_bar(kind, angle)
            name = f"bar-{kind}-{angle}.png"
            img.save(os.path.join(out, name), optimize=True)
            manifest.append(dict(file=name, **meta)); print("rendered", name, flush=True)
    plates = {f"{family}:{plate}": f"{family}-{shape}" for (family, shape), ids in shapes.items() for plate in ids}
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump({"unit": UNIT, "angles": ANGLES, "elevation": round(ELEVATION, 4),
                   "plates": plates, "sprites": manifest}, f, indent=2)
