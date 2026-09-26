#!/usr/bin/env python3
"""Render the loaded-bar sprite family: plates per denomination at the scene's
two angles, plus shaft, sleeve, and collar. A small signed-distance ray
marcher with a studio light rig; deterministic (no random sampling), so a
re-run reproduces every byte. Plates render greyscale and are colourised at
runtime by the shared luminance matrix; hubs and bar parts stay untinted.
Bumper and steel/change plate faces sample PR #263's generated photographic
face-detail textures (read-only material references) for grain and tone
under the renderer's own studio lighting.

  python3 web/tools/render-plate-sprites.py --prototype <dir>   # a few sprites for review
  python3 web/tools/render-plate-sprites.py <dir>               # the full family + manifest
  python3 web/tools/render-plate-sprites.py --jobs 8 <dir>      # parallel processes (default: cpu_count)
  python3 web/tools/render-plate-sprites.py --shapes shapes.json <dir>
      # render only these [{family, diameter, thickness[, plates]}] (JSON or a path)
  python3 web/tools/render-plate-sprites.py --quick <dir>       # half size, no supersampling

Families: bumper (rubber, bolted chrome hub), steel (dished, custom sets),
ipf (calibrated painted disc, raised lip, plugs), iron (cast, rim + boss),
machined (turned face, chrome hub), change (flat fractional plates).
"""

import json
import math
import os
import sys
from concurrent.futures import ProcessPoolExecutor
from collections.abc import Mapping
from typing import Any

import numpy as np
from numpy.typing import NDArray
from PIL import Image

# ---------- geometry ---------------------------------------------------------
# Plate diameters / thicknesses in millimetres, mirrored from BarbellScene
# reference profiles (PlateGeometry.reference). Rendering scales everything by
# the plate radius, so the sprite frame is the same for every denomination.
BUMPER = {
    "25-kg": (450, 70),
    "20-kg": (450, 60),
    "15-kg": (450, 48),
    "10-kg": (450, 35),
    "5-kg": (450, 25),
    "55-lb": (450, 75),
    "45-lb": (450, 65),
    "35-lb": (450, 52),
    "25-lb": (450, 40),
    "10-lb": (450, 25),
}
STEEL = {
    "25-kg": (450, 27),
    "20-kg": (450, 22),
    "15-kg": (400, 21),
    "10-kg": (325, 20),
    "5-kg": (230, 20),
    "55-lb": (450, 30),
    "45-lb": (450, 27),
    "35-lb": (400, 25),
    "25-lb": (325, 23),
    "10-lb": (230, 20),
}
CHANGE = {
    "2.5-kg": (210, 19),
    "2-kg": (190, 19),
    "1.5-kg": (175, 18),
    "1.25-kg": (160, 16),
    "1-kg": (160, 16),
    "0.5-kg": (135, 12),
    "5-lb": (190, 19),
    "2.5-lb": (160, 16),
    "1.25-lb": (135, 12),
}
# Plate-theme sets (issue #55): real-equipment dimensions per construction,
# from docs/design-pass/PLATE-REFERENCE.md via the approved theme mock.
IWF_BUMPER = {
    "25-kg": (450, 66),
    "20-kg": (450, 55),
    "15-kg": (450, 42),
    "10-kg": (450, 29),
}
IWF_CHANGE = {
    "5-kg": (230, 26),
    "2.5-kg": (210, 19),
    "2-kg": (190, 19),
    "1.5-kg": (175, 18),
    "1-kg": (160, 15),
    "0.5-kg": (135, 12.5),
    "1.25-kg": (160, 12),
}
IPF_STEEL = {
    "25-kg": (450, 27),
    "20-kg": (450, 22.5),
    "15-kg": (400, 21),
    "10-kg": (325, 21),
    "5-kg": (228, 21.5),
    "2.5-kg": (190, 16),
    "1.25-kg": (160, 12),
}
LB_BUMPER = {
    "55-lb": (450, 70),
    "45-lb": (450, 60),
    "35-lb": (450, 49),
    "25-lb": (450, 38),
    "10-lb": (450, 21),
}
LB_CHANGE_RUBBER = {"5-lb": (190, 19), "2.5-lb": (162, 15), "1.25-lb": (133, 10)}
LB_IRON = {
    "45-lb": (450, 50),
    "35-lb": (360, 34.5),
    "25-lb": (276, 34.5),
    "10-lb": (229, 20),
    "5-lb": (190, 14.5),
    "2.5-lb": (162, 12),
}
LB_MACHINED = {
    "45-lb": (448, 38),
    "35-lb": (360, 38),
    "25-lb": (300, 38),
    "10-lb": (228, 31),
    "5-lb": (195, 21),
    "2.5-lb": (162, 16),
}
KG_IRON = {
    "20-kg": (450, 36),
    "15-kg": (400, 32),
    "10-kg": (345, 29),
    "5-kg": (275, 22),
    "2.5-kg": (225, 18),
    "1.25-kg": (170, 14),
}
# Default render list: today's custom tables first (so their `<family>:<plate>`
# keys keep their shapes), then every theme set. Duplicated shapes render once.
SHAPE_TABLES: list[tuple[str, Mapping[str, tuple[float, float]]]] = [
    ("bumper", BUMPER),
    ("steel", STEEL),
    ("change", CHANGE),
    ("bumper", IWF_BUMPER),
    ("bumper", LB_BUMPER),
    ("change", IWF_CHANGE),
    ("change", LB_CHANGE_RUBBER),
    ("ipf", IPF_STEEL),
    ("ipf", LB_MACHINED),
    ("iron", LB_IRON),
    ("iron", KG_IRON),
    ("machined", LB_MACHINED),
    ("machined", IPF_STEEL),
]
FAMILIES = ("bumper", "steel", "ipf", "iron", "machined", "change")


def mm(value: float) -> str:
    """A millimetre value as sprite and asset names spell it: integers bare
    (55), fractions with "p" for the point (22.5 → 22p5), since a dot in an
    asset-catalog name can read as a file extension. Consumers resolve names
    through the manifest's numeric `shapes`, never by building this text."""
    return (
        str(int(value))
        if float(value).is_integer()
        else repr(float(value)).replace(".", "p")
    )


def shape_key(diameter: float, thickness: float) -> str:
    return f"{mm(diameter)}x{mm(thickness)}"


def default_shapes() -> list[dict[str, Any]]:
    """Every table's shapes. Plate keys come from the custom tables and the
    theme-only families; theme bumper/change sets add sprites, not keys (their
    plates already have custom shapes, or none, as the 5 kg change plate)."""
    custom = (BUMPER, STEEL, CHANGE)
    return [
        {
            "family": family,
            "diameter": d,
            "thickness": t,
            "plates": [plate]
            if any(table is c for c in custom) or family not in ("bumper", "change")
            else [],
        }
        for family, table in SHAPE_TABLES
        for plate, (d, t) in table.items()
    ]


ANGLES = {"assembled": 18.0, "exploded": 38.0}  # BarbellScene's two projections
ELEVATION = math.degrees(
    math.asin(0.24)
)  # BarbellScene skews the axis by 0.24·tan(yaw): the same slope
UNIT = (
    450 * 0.18
)  # scene units per plate radius (BarbellScene: radius = diameter × 0.18)
BAR_RADIUS = 28 / 450  # 28 mm shaft on a 450 mm plate → in plate-radius units
SLEEVE_RADIUS = 50 / 450

# Faces are sampled from PR #263's generated material photographs. The
# inspector shader (barbell-gl.js) measures the photographed circle at 0.485
# of the canvas: `radius = length(vUV - 0.5) / 0.485`. Reused here so the
# rendered grain lines up with the same physical material reference.
FACE_TEXTURE_UV_SCALE = 0.485
FACE_TEXTURE_FAMILIES = {
    "bumper": "bumper-face-detail.png",
    "steel": "steel-face-detail.png",
    "change": "steel-face-detail.png",
}
FACE_TEXTURE_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "app", "assets", "plates"
)
_FACE_TEXTURE_CACHE: dict[str, NDArray[np.float64]] = {}


def face_texture(family: str) -> NDArray[np.float64] | None:
    """Zero-mean greyscale detail signal for a plate family's face photo, or
    None for families with no photographic reference (change plates share
    the steel photo). Cached per-process so each render job decodes once."""
    filename = FACE_TEXTURE_FAMILIES.get(family)
    if filename is None:
        return None
    cached = _FACE_TEXTURE_CACHE.get(filename)
    if cached is None:
        arr = (
            np.asarray(
                Image.open(os.path.join(FACE_TEXTURE_DIR, filename)).convert("L"),
                dtype=np.float64,
            )
            / 255.0
        )
        cached = arr - arr.mean()
        _FACE_TEXTURE_CACHE[filename] = cached
    return cached


def sample_texture(
    tex: NDArray[np.float64], u: NDArray[np.float64], v: NDArray[np.float64]
) -> NDArray[np.float64]:
    """Bilinear-sample a 2D greyscale texture at normalised (u, v), edge-clamped."""
    h, w = tex.shape
    x = np.clip(u, 0.0, 1.0) * (w - 1)
    y = np.clip(v, 0.0, 1.0) * (h - 1)
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    x1 = np.minimum(x0 + 1, w - 1)
    y1 = np.minimum(y0 + 1, h - 1)
    fx = x - x0
    fy = y - y0
    top = tex[y0, x0] * (1 - fx) + tex[y0, x1] * fx
    bot = tex[y1, x0] * (1 - fx) + tex[y1, x1] * fx
    return top * (1 - fy) + bot * fy


# ---------- SDF helpers ----------------------------------------------------------
def length(v: NDArray[np.float64]) -> NDArray[np.float64]:
    return np.sqrt((v * v).sum(-1))


def sd_cyl_x(p: NDArray[np.float64], r: float, h: float) -> NDArray[np.float64]:
    """Cylinder along x: radius r, half-length h (exact SDF)."""
    d = np.stack([np.hypot(p[..., 1], p[..., 2]) - r, np.abs(p[..., 0]) - h], -1)
    return np.minimum(np.maximum(d[..., 0], d[..., 1]), 0) + length(np.maximum(d, 0))


def sd_round_cyl_x(
    p: NDArray[np.float64], r: float, h: float, e: float
) -> NDArray[np.float64]:
    return sd_cyl_x(p, r - e, h - e) - e


BORE_MM = 25.25  # 50.5 mm Olympic bore, as a radius


def hub_radius(family: str, d_mm: float) -> float:
    """The untinted hub disc, in plate radii (the runtime redraws this circle
    without the plate tint). Calibrated and machined hubs follow the lathe
    profiles (max(bore + 8 mm, 0.2R / 0.22R)); cast iron has no separate hub,
    so only the bore stays untinted and the boss takes the plate colour."""
    r_mm = d_mm / 2
    if family == "bumper":
        return 0.47  # bolted steel centre disc (barbell-inspector plateProfile)
    if family == "ipf":
        return round(max(BORE_MM + 8, 0.2 * r_mm) / r_mm, 4)
    if family == "machined":
        return round(max(BORE_MM + 8, 0.22 * r_mm) / r_mm, 4)
    if family == "iron":
        return round(BORE_MM / r_mm, 4)
    return 0.2


def slab(
    rho: NDArray[np.float64], x: NDArray[np.float64], r0: float, r1: float, hx: float
) -> NDArray[np.float64]:
    """Annulus r0..r1 of half-thickness hx along x (bound, not exact)."""
    return np.maximum(np.maximum(r0 - rho, rho - r1), np.abs(x) - hx)


def ramp(
    rho: NDArray[np.float64], x: NDArray[np.float64], r0: float, h0: float, k: float
) -> NDArray[np.float64]:
    """Half-space |x| <= h0 + (rho - r0)·k: a lathe chamfer between two faces."""
    return (np.abs(x) - h0 - (rho - r0) * k) / math.sqrt(1 + k * k)


def ring_of(
    p: NDArray[np.float64],
    rho: NDArray[np.float64],
    count: int,
    orbit: float,
    radius: float,
    top: float,
) -> NDArray[np.float64]:
    """`count` studs parallel to x on a circle of `orbit`, at angles
    π/count + i·2π/count (the theme mock's placement), reaching |x| <= top."""
    sector = 2 * math.pi / count
    phi = np.arctan2(p[..., 2], p[..., 1]) - math.pi / count
    local = np.mod(phi + sector / 2, sector) - sector / 2
    q = np.hypot(rho * np.cos(local) - orbit, rho * np.sin(local)) - radius
    return np.maximum(q, np.abs(p[..., 0]) - top)


def plate_sdf(family: str, d_mm: float, t_mm: float):
    """Returns (distance, material) for a plate of radius 1 with proportional
    thickness. `d_mm` is the plate DIAMETER (the shape key is diameter×thickness);
    every proportion below is in plate radii. Materials: 0 body (rubber,
    paint, cast iron or turned steel by family), 1 chrome hub, 5 calibration
    plug, 6 hub stud. Bumper, calibrated (ipf), iron and change proportions
    follow the lathe profiles in barbell-inspector.js and the theme mock."""
    R = 1.0
    r_mm = d_mm / 2
    s = 1 / r_mm  # one millimetre in plate radii
    h = (t_mm / 2) / r_mm  # half thickness in plate radii
    bore_r = BORE_MM / r_mm
    hub_r = hub_radius(family, d_mm)
    edge = 0.06 if family == "bumper" else 0.018

    def hub_disc(rho: NDArray[np.float64], x: NDArray[np.float64], top: float):
        return slab(rho, x, bore_r, hub_r, top) - 0.004  # tiny edge round

    def f(p: NDArray[np.float64]):
        x = p[..., 0]
        rho = np.hypot(p[..., 1], p[..., 2])
        extra = np.full(rho.shape, np.inf)  # plugs / studs
        extra_mat = 0
        hub = np.full(rho.shape, np.inf)
        if family == "ipf":
            # thin painted disc: face 1 mm below nominal, a raised outer lip
            # (ipfProfile), a proud chrome hub and two calibration plugs
            lip = min(2.2, 0.12 * t_mm) * s
            face_h = h - s
            r_a, r_b = R - 0.06 - 4 * s, R - 0.06
            web = sd_round_cyl_x(p, R, face_h, min(edge, face_h * 0.9))
            rim = np.maximum(
                np.maximum(r_a - rho, sd_round_cyl_x(p, R, h + lip, 1.2 * s)),
                ramp(rho, x, r_a, face_h, (h + lip - face_h) / (r_b - r_a)),
            )
            body = np.minimum(web, rim)
            hub = hub_disc(rho, x, h + 0.8 * s)
            extra = ring_of(p, rho, 2, 0.62, 7 * s, h + 1.2 * s) - 0.5 * s
            extra_mat = 5
        elif family == "iron":
            # cast: recessed field between a raised rim lip and a centre boss
            # (ironProfile); the boss is part of the casting, not a hub
            lip = min(3.0, 0.14 * t_mm) * s
            face_h = h - lip
            boss = max(BORE_MM + 10, 0.24 * r_mm) * s
            boss_h = h + 1.2 * s
            r_a = R - 0.09 - 3 * s
            web = sd_round_cyl_x(p, R, face_h, min(edge, face_h * 0.9))
            rim = np.maximum(
                np.maximum(r_a - rho, sd_round_cyl_x(p, R, h, 1.5 * s)),
                ramp(rho, x, r_a, face_h, lip / (3 * s)),
            )
            k = (boss_h - face_h) / (3 * s)
            centre = np.maximum(
                np.maximum(rho - (boss + 3 * s), np.abs(x) - boss_h),
                ramp(rho, x, boss, boss_h, -k),
            )
            body = np.minimum(np.minimum(web, rim), centre - 0.4 * s)
        elif family == "machined":
            # flat turned face stepping down just inside the rim
            step = min(1.5, 0.06 * t_mm) * s
            face = sd_round_cyl_x(p, 0.9, h, 0.6 * s)
            body = np.minimum(face, sd_round_cyl_x(p, R, h - step, 1.0 * s))
            hub = hub_disc(rho, x, h + 0.8 * s)
        else:
            body = sd_round_cyl_x(p, R, h, min(edge, h * 0.9))
            if family == "bumper":
                # raised outer rim: recess the face between the hub collar and 0.9R
                depth = h * 0.14
                recess = np.maximum(
                    np.maximum(rho - 0.88, -(rho - hub_r)), (h - depth) - np.abs(x)
                )
                body = np.maximum(body, -recess)
                # six steel bolts on the hub, like the theme mock's boltedHub
                extra = ring_of(p, rho, 6, 0.72 * hub_r, 5 * s, h + 0.006 + 1.4 * s)
                extra = extra - 0.6 * s
                extra_mat = 6
            else:
                # machined step just inside the rim and a shallow face dish
                depth = h * 0.12
                recess = np.maximum(
                    np.maximum(rho - 0.86, -(rho - 0.34)), (h - depth) - np.abs(x)
                )
                body = np.maximum(body, -recess)
            hub = hub_disc(rho, x, h + 0.006)
        body = np.maximum(body, -(rho - bore_r))  # bore
        extra = np.maximum(extra, -(rho - bore_r))
        d = np.minimum(np.minimum(body, hub), extra)
        mat = np.where(extra <= d, extra_mat, np.where(hub < body, 1, 0))
        return d, mat

    return f, h


# Scene proportions (BarbellScene, 20 kg / 45 lb bar): shoulders at ±165,
# sleeve to ±315, knurl from ±42 to ±141 — expressed in plate radii here.
SHOULDER = 165 / UNIT
SLEEVE_END = 315 / UNIT
KNURL_IN, KNURL_OUT = 42 / UNIT, 141 / UNIT


def bar_sdf(kind: str):
    """Shaft between the shoulders (radius BAR_RADIUS, along x, knurled),
    sleeve from shoulder to end, or a collar ring. Material 3 = bar steel,
    4 = knurl."""

    def f(p: NDArray[np.float64]):
        x = p[..., 0]
        if kind == "shaft":
            d = sd_cyl_x(p, BAR_RADIUS, SHOULDER)
            knurl = (np.abs(x) > KNURL_IN) & (np.abs(x) < KNURL_OUT)
            return d, np.where(knurl, 4, 3)
        if kind in ("sleeve", "sleeve-near"):
            q = (
                p if kind == "sleeve" else p * np.array([-1, 1, 1])
            )  # mirror for the near sleeve
            half = (SLEEVE_END - SHOULDER) / 2
            sleeve = sd_round_cyl_x(
                q - np.array([half, 0, 0]), SLEEVE_RADIUS, half, 0.012
            )
            shoulder = sd_round_cyl_x(
                q - np.array([0.03, 0, 0]), SLEEVE_RADIUS * 1.3, 0.06, 0.015
            )
            shaft = sd_cyl_x(q + np.array([0.4, 0, 0]), BAR_RADIUS, 0.45)
            d = np.minimum(np.minimum(sleeve, shoulder), shaft)
            return d, np.full(d.shape, 3)
        if kind in ("collar", "collar-near"):
            rho = np.hypot(p[..., 1], p[..., 2])
            ring = (
                np.maximum(
                    np.maximum(
                        rho - SLEEVE_RADIUS * 1.55, -(rho - SLEEVE_RADIUS * 0.98)
                    ),
                    np.abs(x) - 0.075,
                )
                - 0.01
            )
            lever = sd_round_cyl_x(
                np.stack([p[..., 0], p[..., 1] - SLEEVE_RADIUS * 1.9, p[..., 2]], -1),
                0.03,
                0.03,
                0.01,
            )
            d = np.minimum(ring, lever)
            return d, np.full(d.shape, 3)
        raise ValueError(kind)

    return f


# ---------- camera + shading -------------------------------------------------------
def camera(
    yaw_deg: float,
    elev_deg: float,
    distance: float,
    width: int,
    height: int,
    fov_deg: float,
):
    yaw, elev = math.radians(yaw_deg), math.radians(elev_deg)
    eye = np.array(
        [
            -distance * math.cos(elev) * math.sin(yaw),
            distance * math.sin(elev),
            distance * math.cos(elev) * math.cos(yaw),
        ]
    )
    fwd = -eye / np.linalg.norm(eye)
    right = np.cross(fwd, np.array([0, 1.0, 0]))
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    aspect = width / height
    tan = math.tan(math.radians(fov_deg) / 2)
    ys, xs = np.mgrid[0:height, 0:width]
    u = (xs + 0.5) / width * 2 - 1
    v = 1 - (ys + 0.5) / height * 2
    dirs = (
        fwd[None, None]
        + (u * tan * aspect)[..., None] * right[None, None]
        + (v * tan)[..., None] * up[None, None]
    )
    dirs /= length(dirs)[..., None]
    return eye, dirs, (fwd, right, up, tan, aspect)


def project(
    point: NDArray[np.float64], eye: NDArray[np.float64], basis, width: int, height: int
):
    fwd, right, up, tan, aspect = basis
    rel = point - eye
    z = rel @ fwd
    x = (rel @ right) / (z * tan * aspect)
    y = (rel @ up) / (z * tan)
    return ((x + 1) / 2 * width, (1 - y) / 2 * height)


def march(
    sdf,
    eye: NDArray[np.float64],
    dirs: NDArray[np.float64],
    steps: int = 160,
    tmax: float = 12.0,
    eps: float = 6e-4,
):
    t = np.zeros(dirs.shape[:-1])
    hit = np.zeros_like(t, dtype=bool)
    mat = np.zeros_like(t, dtype=int)
    active = np.ones_like(hit)
    for _ in range(steps):
        p = eye + dirs * t[..., None]
        d, m = sdf(p)
        newly = active & (d < eps)
        hit |= newly
        mat = np.where(newly, m, mat)
        active &= ~newly & (t < tmax)
        t = np.where(active, t + np.maximum(d, eps) * 0.85, t)
        if not active.any():
            break
    return t, hit, mat


def normal(sdf, p: NDArray[np.float64], e: float = 1.5e-3) -> NDArray[np.float64]:
    n = np.zeros_like(p)
    for i in range(3):
        o = np.zeros(3)
        o[i] = e
        n[..., i] = sdf(p + o)[0] - sdf(p - o)[0]
    return n / np.maximum(length(n), 1e-9)[..., None]


def soft_shadow(
    sdf,
    p: NDArray[np.float64],
    light_dir: NDArray[np.float64],
    k: float = 10.0,
    steps: int = 18,
    tmax: float = 2.5,
):
    res = np.ones(p.shape[:-1])
    t = np.full(p.shape[:-1], 0.02)
    for _ in range(steps):
        d = sdf(p + light_dir * t[..., None])[0]
        res = np.minimum(res, k * d / t)
        t = t + np.clip(d, 0.01, 0.2)
        if (t > tmax).all():
            break
    return np.clip(res, 0, 1)


def ambient_occlusion(sdf, p: NDArray[np.float64], n: NDArray[np.float64]):
    occ = 0.0
    for i, s in enumerate([0.02, 0.05, 0.1, 0.18]):
        d = sdf(p + n * s)[0]
        occ += (s - d) * (0.55**i)
    return np.clip(1 - 3.0 * occ, 0, 1)


def ggx(
    n: NDArray[np.float64],
    v: NDArray[np.float64],
    light: NDArray[np.float64],
    roughness: float,
    f0: float,
):
    h = v + light
    h /= np.maximum(length(h), 1e-9)[..., None]
    ndl = np.clip((n * light).sum(-1), 0, 1)
    ndv = np.clip((n * v).sum(-1), 1e-4, 1)
    ndh = np.clip((n * h).sum(-1), 0, 1)
    vdh = np.clip((v * h).sum(-1), 0, 1)
    a2 = roughness**4
    d = a2 / (math.pi * (ndh * ndh * (a2 - 1) + 1) ** 2)
    k = (roughness + 1) ** 2 / 8
    g = (ndv / (ndv * (1 - k) + k)) * (ndl / (ndl * (1 - k) + k))
    fresnel = f0 + (1 - f0) * (1 - vdh) ** 5
    return d * g * fresnel / np.maximum(4 * ndv * ndl, 1e-4) * ndl, ndl


LIGHTS = [  # softbox position (plate radii), intensity at 3 radii — close lights give a flat face its gradient
    (np.array([-2.4, 2.8, 2.6]), 3.6),  # key: high, left, in front
    (np.array([3.2, 0.4, 2.4]), 0.55),  # fill: low right
    (np.array([0.8, 2.2, -2.8]), 1.4),  # rim: behind, above
]

MATERIALS = {  # albedo, roughness, f0 (specular at normal incidence), metallic
    0: dict(
        albedo=0.56, rough=0.5, f0=0.045, metal=0.0
    ),  # rubber (greyscale; colourised at runtime); restrained sheen
    1: dict(albedo=0.92, rough=0.16, f0=0.92, metal=1.0),  # chrome hub
    3: dict(
        albedo=0.9, rough=0.13, f0=0.94, metal=1.0
    ),  # bar steel / chrome sleeve: crisp studio reflections
    4: dict(albedo=0.84, rough=0.3, f0=0.85, metal=1.0),  # knurled shaft
    5: dict(
        albedo=0.8, rough=0.3, f0=0.6, metal=0.0
    ),  # calibration plug (bright insert)
    6: dict(
        albedo=0.5, rough=0.4, f0=0.5, metal=0.0
    ),  # hub bolt head (satin, darker than the disc)
}
# Bumper centre disc (material 1): zinc-bright satin steel rather than mirror chrome.
HUB_MATERIALS = {"bumper": dict(albedo=0.8, rough=0.36, f0=0.55, metal=0.0)}
# Plate body (material 0) per construction; families not listed use MATERIALS[0].
BODY_MATERIALS = {
    "ipf": dict(albedo=0.6, rough=0.34, f0=0.05, metal=0.0),  # gloss-painted steel
    "iron": dict(albedo=0.5, rough=0.62, f0=0.04, metal=0.0),  # cast iron, e-coat
    # turned steel: shaded as a bright dielectric with a strong sheen, since a
    # true mirror metal only reflects the dark studio back at the camera
    "machined": dict(albedo=0.66, rough=0.28, f0=0.6, metal=0.0),
}


def smoothstep(a: float, b: float, x: NDArray[np.float64]) -> NDArray[np.float64]:
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def environment(n: NDArray[np.float64]) -> NDArray[np.float64]:
    """Studio: a wide overhead softbox band (what chrome reflects as its bright
    stripe), a faint front fill, and a near-black floor."""
    up = np.clip(n[..., 1], -1, 1)
    front = np.clip(n[..., 2], -1, 1)
    band = (
        smoothstep(0.18, 0.55, up)
        * (1 - smoothstep(0.82, 0.98, up))
        * smoothstep(-0.35, 0.15, front)
    )
    return (
        0.035
        + 0.85 * band
        + 0.06 * np.clip(front, 0, 1) ** 2
        + 0.10 * np.clip(up, 0, 1) ** 3
    )


def face_albedo_map(
    mat_id: int,
    family: str | None,
    t_shape: tuple[int, ...],
    albedo: float,
    n: NDArray[np.float64],
    p: NDArray[np.float64],
) -> NDArray[np.float64]:
    """Per-pixel albedo for the plate body: flat `albedo` everywhere, except on
    the camera-facing plate face of a family with a photographic reference,
    where PR #263's face-detail photo modulates it for grain and tone."""
    flat = np.full(t_shape, albedo)
    if mat_id != 0 or family is None:
        return flat
    tex = face_texture(family)
    if tex is None:
        return flat
    front = smoothstep(0.55, 0.92, np.clip(-n[..., 0], 0.0, 1.0))
    rho = np.hypot(p[..., 1], p[..., 2])
    on_face = (rho <= 1.02).astype(np.float64)
    u = 0.5 + p[..., 1] * FACE_TEXTURE_UV_SCALE
    v = 0.5 - p[..., 2] * FACE_TEXTURE_UV_SCALE
    detail = sample_texture(tex, u, v)
    grain = 1.0 + 1.1 * detail * front * on_face
    return flat * grain


def shade(
    sdf,
    eye: NDArray[np.float64],
    dirs: NDArray[np.float64],
    t: NDArray[np.float64],
    hit: NDArray[np.bool_],
    mat: NDArray[np.int64],
    family_bump=None,
    family: str | None = None,
) -> NDArray[np.float64]:
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
        if mid == 0 and family in BODY_MATERIALS:
            props = BODY_MATERIALS[family]
        if mid == 1 and family in HUB_MATERIALS:
            props = HUB_MATERIALS[family]
        rough, f0, metal = props["rough"], props["f0"], props["metal"]
        albedo_map = face_albedo_map(mid, family, t.shape, props["albedo"], n, p)
        colour = environment(n) * albedo_map * ao * (0.25 if metal else 0.9)
        # metals reflect the environment: sample it along the mirror direction,
        # blurred by roughness through a small cone of samples
        if metal:
            refl = dirs - 2 * (dirs * n).sum(-1)[..., None] * n
            refl /= np.maximum(length(refl), 1e-9)[..., None]
            gathered = 0.0
            for dy, dz in (
                (0, 0),
                (rough * 0.5, 0),
                (-rough * 0.5, 0),
                (0, rough * 0.5),
                (0, -rough * 0.5),
            ):
                sample = refl + np.array([0, dy, dz])
                gathered = gathered + environment(
                    sample / np.maximum(length(sample), 1e-9)[..., None]
                )
            colour = colour + gathered / 5 * albedo_map * ao
        for lpos, intensity in LIGHTS:
            to_light = lpos - p
            dist = np.maximum(length(to_light), 1e-6)
            light_dir = to_light / dist[..., None]
            spec, ndl = ggx(n, v, light_dir, rough, f0)
            shadow = soft_shadow(sdf, p + n * 0.01, light_dir)
            falloff = intensity * 9.0 / (dist * dist)
            diffuse = 0 if metal else albedo_map / math.pi * ndl
            colour = colour + falloff * shadow * (
                diffuse + spec * (0.9 if metal else 0.45)
            )
        out = np.where(m, colour, out)
    full[hit] = out
    return full


def bumps(family: str):
    """Surface grain: rolled rubber pebble + rim ridging on bumpers, fine
    turning marks and a machined bevel highlight on steel, a real diamond
    knurl on the shaft. Deterministic hash noise, no random state."""

    def noise(p: NDArray[np.float64], scale: float) -> NDArray[np.float64]:
        q = p * scale
        i = np.floor(q)
        f = q - i

        def h(o: list[int]) -> NDArray[np.float64]:
            v = (i + o) @ np.array([127.1, 311.7, 74.7])
            return np.modf(np.sin(v) * 43758.5453)[0]

        f = f * f * (3 - 2 * f)
        a = h([0, 0, 0])
        b = h([1, 0, 0])
        c = h([0, 1, 0])
        d = h([1, 1, 0])
        e = h([0, 0, 1])
        g = h([1, 0, 1])
        k = h([0, 1, 1])
        m = h([1, 1, 1])
        x1 = a + (b - a) * f[..., 0]
        x2 = c + (d - c) * f[..., 0]
        y1 = x1 + (x2 - x1) * f[..., 1]
        x3 = e + (g - e) * f[..., 0]
        x4 = k + (m - k) * f[..., 0]
        y2 = x3 + (x4 - x3) * f[..., 1]
        return y1 + (y2 - y1) * f[..., 2]

    def grad(
        p: NDArray[np.float64], scale: float, g0: NDArray[np.float64]
    ) -> NDArray[np.float64]:
        return np.stack(
            [
                noise(p + [1e-3, 0, 0], scale) - g0 - 0.5,
                noise(p + [0, 1e-3, 0], scale) - g0 - 0.5,
                noise(p + [0, 0, 1e-3], scale) - g0 - 0.5,
            ],
            -1,
        )

    def apply(
        p: NDArray[np.float64], n: NDArray[np.float64], mat: NDArray[np.float64]
    ) -> NDArray[np.float64]:
        body = (mat == 0)[..., None]
        if family == "bumper":
            rho = np.hypot(p[..., 1], p[..., 2])
            pebble = noise(p, 90.0) - 0.5
            pebble_grad = grad(p, 90.0, pebble)
            rim = smoothstep(0.82, 0.97, rho)[..., None]
            rolled = noise(p, 260.0) - 0.5
            rolled_grad = grad(p, 260.0, rolled)
            return np.where(body, n + pebble_grad * 0.42 + rolled_grad * 0.3 * rim, n)
        if family in ("steel", "change"):
            rho = np.hypot(p[..., 1], p[..., 2])
            ring = np.sin(rho * 260.0) * 0.08
            bevel = smoothstep(0.86, 0.99, rho) * 0.05
            radial = np.stack(
                [
                    np.zeros_like(rho),
                    p[..., 1] / np.maximum(rho, 1e-6),
                    p[..., 2] / np.maximum(rho, 1e-6),
                ],
                -1,
            )
            face = body & (np.abs(n[..., 0]) > 0.8)[..., None]
            return np.where(face, n + radial * (ring + bevel)[..., None], n)
        if family == "ipf":
            # sprayed paint: a faint orange-peel over the smooth disc
            peel = noise(p, 70.0) - 0.5
            return np.where(body, n + grad(p, 70.0, peel) * 0.08, n)
        if family == "iron":
            # sand-cast skin: broad undulation plus fine pitting, under e-coat
            coarse = noise(p, 38.0) - 0.5
            fine = noise(p, 120.0) - 0.5
            skin = grad(p, 38.0, coarse) * 0.34 + grad(p, 120.0, fine) * 0.18
            return np.where(body, n + skin, n)
        if family == "machined":
            # lathe-turned faces: tight concentric tool marks with a brushed
            # variation along each groove
            rho = np.hypot(p[..., 1], p[..., 2])
            radial = np.stack(
                [
                    np.zeros_like(rho),
                    p[..., 1] / np.maximum(rho, 1e-6),
                    p[..., 2] / np.maximum(rho, 1e-6),
                ],
                -1,
            )
            phi = np.arctan2(p[..., 2], p[..., 1])
            groove = np.stack([p[..., 0], rho * 8.0, phi * 0.3], -1)
            brush = 0.6 + 0.8 * noise(groove, 40.0)
            ring = (np.sin(rho * 900.0) * 0.07 + np.sin(rho * 310.0) * 0.04) * brush
            face = body & (np.abs(n[..., 0]) > 0.8)[..., None]
            return np.where(face, n + radial * ring[..., None], n)
        if family == "shaft":
            phi = np.arctan2(p[..., 2], p[..., 1])
            x = p[..., 0]
            diamond = np.sin(x * 260 + phi * 14) * np.sin(x * 260 - phi * 14)
            tangent = np.stack(
                [np.ones_like(x), np.zeros_like(x), np.zeros_like(x)], -1
            )
            around = np.stack([np.zeros_like(x), -np.sin(phi), np.cos(phi)], -1)
            knurl = (mat == 4)[..., None]
            ripple = (
                tangent * np.cos(x * 260)[..., None]
                + around * np.sin(phi * 14)[..., None]
            )
            return np.where(knurl, n + ripple * 0.34 * diamond[..., None], n)
        return n

    return apply


def render(
    sdf,
    bump,
    yaw: float,
    size: tuple[int, int],
    fov: float,
    distance: float,
    ss: int = 2,
    centre: NDArray[np.float64] | None = None,
    family: str | None = None,
    quick: bool = False,
):
    """`size` is (width, height) in output pixels."""
    width, height = size
    if quick:
        width, height, ss = width // 2, height // 2, 1
    w, h = width * ss, height * ss
    eye, dirs, basis = camera(yaw, ELEVATION, distance, w, h, fov)
    if centre is not None:
        eye = eye + centre
    t, hit, mat = march(sdf, eye, dirs, tmax=distance + 6.0)
    colour = shade(sdf, eye, dirs, t, hit, mat, bump, family)
    grey = np.clip(colour, 0, 1) ** (1 / 2.2)
    rgba = np.zeros((h, w, 4))
    rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = np.where(hit, grey, 0)
    rgba[..., 3] = hit
    img = Image.fromarray((rgba * 255).astype(np.uint8)).resize(
        (width, height), Image.Resampling.LANCZOS
    )
    return img, (eye, basis, width, height)


def framing(extent: float, distance: float) -> float:
    """FOV that fits `extent` (plate radii, half-size) at `distance` with 8% margin."""
    return math.degrees(2 * math.atan(extent * 1.08 / distance))


def render_plate(
    family: str,
    d_mm: float,
    t_mm: float,
    angle_name: str,
    size: int = 512,
    quick: bool = False,
):
    sdf, h = plate_sdf(family, d_mm, t_mm)
    yaw = ANGLES[angle_name]
    distance = 16.0
    fov = framing(1.05, distance)
    img, (eye, basis, w, ht) = render(
        sdf, bumps(family), yaw, (size, size), fov, distance, family=family, quick=quick
    )
    # metadata: where the front face centre and its vertical radius land, in sprite pixels
    front = np.array(
        [-h, 0, 0]
    )  # the face turned toward the camera (camera sits at negative x)
    cx, cy = project(front, eye, basis, w, ht)
    _, top = project(front + np.array([0, 1, 0]), eye, basis, w, ht)
    return img, dict(
        family=family,
        shape=shape_key(d_mm, t_mm),
        diameter=d_mm,
        thickness=t_mm,
        angle=angle_name,
        faceCenter=[round(float(cx), 2), round(float(cy), 2)],
        faceRadius=round(float(cy - top), 2),
        hubRadius=hub_radius(family, d_mm),
        size=[w, ht],
    )


def render_bar(kind: str, angle_name: str, quick: bool = False):
    sdf = bar_sdf(kind)
    yaw = ANGLES[angle_name]
    span = {
        "shaft": (-SHOULDER, SHOULDER),
        "sleeve": (0.0, SLEEVE_END - SHOULDER),
        "sleeve-near": (-(SLEEVE_END - SHOULDER), 0.0),
        "collar": (-0.09, 0.09),
        "collar-near": (-0.09, 0.09),
    }[kind]
    # wide frames: a shaft in a square frame would waste most of its pixels
    size = {
        "shaft": (1600, 320),
        "sleeve": (900, 300),
        "sleeve-near": (900, 300),
        "collar": (320, 320),
        "collar-near": (320, 320),
    }[kind]
    centre = np.array([(span[0] + span[1]) / 2, 0, 0])
    extent = max(span[1] - span[0], 0.6)
    distance = max(16.0, extent * 8.0)
    # frame the span across the wide axis; the height follows the aspect ratio
    fov = framing(extent / 2 / (size[0] / size[1]) * 1.05, distance)
    img, (eye, basis, w, ht) = render(
        sdf,
        bumps("shaft") if kind == "shaft" else None,
        yaw,
        size,
        fov,
        distance,
        centre=centre,
        quick=quick,
    )
    a = project(np.array([span[0], 0, 0]), eye, basis, w, ht)
    b = project(np.array([span[1], 0, 0]), eye, basis, w, ht)
    return img, dict(
        kind=kind,
        angle=angle_name,
        size=[w, ht],
        axisStart=[round(float(a[0]), 2), round(float(a[1]), 2)],
        axisEnd=[round(float(b[0]), 2), round(float(b[1]), 2)],
        spanUnits=round(float((span[1] - span[0]) * UNIT), 2),
    )


def _render_job(job: tuple[Any, ...]) -> dict[str, Any]:
    """A single plate or bar render, dispatched to a worker process. Jobs are
    tagged so a shared pool can interleave both kinds instead of finishing
    every plate before starting the (slower, wide-frame) bar renders."""
    if job[0] == "plate":
        _, family, d_mm, t_mm, angle, out, quick = job
        img, meta = render_plate(family, d_mm, t_mm, angle, quick=bool(quick))
        name = f"plate-{family}-{shape_key(d_mm, t_mm)}-{angle}.png"
    else:
        _, kind, angle, out, quick = job
        img, meta = render_bar(kind, angle, quick=bool(quick))
        name = f"bar-{kind}-{angle}.png"
    # Every sprite is greyscale (plates tint at runtime, hubs and bars are
    # neutral metal): grey+alpha PNGs carry the same pixels in ~70% the bytes.
    img.convert("LA").save(os.path.join(out, name), optimize=True)
    print("rendered", name, flush=True)
    return dict(file=name, **meta)


if __name__ == "__main__":
    args = sys.argv[1:]
    prototype = "--prototype" in args
    quick_flag = "--quick" in args
    bars_only = "--bars-only" in args
    plates_only = "--plates-only" in args

    def option(name: str) -> str | None:
        """`--name=value` or `--name value`."""
        for i, a in enumerate(args):
            if a.startswith(f"{name}="):
                return a.split("=", 1)[1]
            if a == name and i + 1 < len(args):
                return args[i + 1]
        return None

    jobs_value = option("--jobs")
    n_jobs = max(1, int(jobs_value)) if jobs_value else (os.cpu_count() or 1)
    shapes_value = option("--shapes")
    option_values = {v for v in (jobs_value, shapes_value) if v is not None}
    positional = [a for a in args if not a.startswith("--") and a not in option_values]
    out_dir = positional[0]
    os.makedirs(out_dir, exist_ok=True)
    # --shapes takes a JSON array (inline, or a path to a .json file) of
    # {family, diameter, thickness[, plates]}; the default is every table above.
    if shapes_value is None:
        shape_list = default_shapes()
    else:
        text = shapes_value
        if not text.lstrip().startswith("["):
            with open(text) as fh:
                text = fh.read()
        shape_list = json.loads(text)
    # Deduplicate by family + D×T. "<family>:<plate id>" → shape key: the
    # first shape listed for a plate wins, so today's custom tables keep their
    # keys; a theme set whose plate differs (e.g. the IWF 20 kg bumper, 450x55)
    # is reached by its sprite name, plate-<family>-<D>x<T>-<angle>.
    shapes: dict[tuple[str, float, float], None] = {}
    plates: dict[str, str] = {}
    for entry in shape_list:
        family_name = entry["family"]
        if family_name not in FAMILIES:
            raise SystemExit(f"unknown plate family {family_name!r}")
        dia, thick = float(entry["diameter"]), float(entry["thickness"])
        shapes.setdefault((family_name, dia, thick), None)
        for plate_name in entry.get("plates", []):
            plates.setdefault(
                f"{family_name}:{plate_name}", f"{family_name}-{shape_key(dia, thick)}"
            )
    if prototype:
        wanted = {("bumper", "450x60"), ("steel", "450x27"), ("change", "160x16")}
        wanted |= {("ipf", "450x22.5"), ("iron", "450x50"), ("machined", "448x38")}
        plate_jobs = [s for s in shapes if (s[0], shape_key(s[1], s[2])) in wanted]
    else:
        plate_jobs = sorted(shapes)
    angle_names = list(ANGLES)
    plate_tasks = (
        []
        if bars_only
        else [
            ("plate", family_name, dia, thick, angle, out_dir, quick_flag)
            for family_name, dia, thick in plate_jobs
            for angle in angle_names
        ]
    )
    if plates_only:
        bar_kinds: tuple[str, ...] = ()
    elif "--near-only" in args:
        bar_kinds = ("sleeve-near", "collar-near")
    else:
        bar_kinds = ("shaft", "sleeve", "collar", "sleeve-near", "collar-near")
    bar_tasks = [
        ("bar", kind, angle, out_dir, quick_flag)
        for kind in bar_kinds
        for angle in angle_names
    ]
    # Bar jobs (the wide shaft/sleeve frames) are the slowest; submit them
    # first so they start alongside the plates instead of after every plate.
    tasks = bar_tasks + plate_tasks

    manifest_sprites: list[dict[str, Any]] = []
    if n_jobs == 1 or len(tasks) <= 1:
        manifest_sprites.extend(_render_job(job) for job in tasks)
    else:
        with ProcessPoolExecutor(max_workers=n_jobs) as pool:
            manifest_sprites.extend(pool.map(_render_job, tasks, chunksize=1))
    # Deterministic manifest order regardless of process completion timing.
    manifest_sprites.sort(key=lambda entry: entry["file"])

    with open(os.path.join(out_dir, "manifest.json"), "w") as f:
        json.dump(
            {
                "unit": UNIT,
                "angles": ANGLES,
                "elevation": round(ELEVATION, 4),
                "plates": plates,
                "shapes": [
                    {
                        "family": family_name,
                        "diameter": dia,
                        "thickness": thick,
                        "key": f"{family_name}-{shape_key(dia, thick)}",
                    }
                    for family_name, dia, thick in sorted(shapes)
                ],
                "sprites": manifest_sprites,
            },
            f,
            indent=2,
        )
