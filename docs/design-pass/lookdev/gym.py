"""Cadence equipment look-dev, pass 2: a real bar on a real platform.

Run: python3 gym.py <shot> <out.png> [samples] [width] [height]
Builds on studio.py (bar, plates, lathe, text). Adds an 8'x8' Olympic
platform (plywood base, oak centre, stall-mat sides), gym lighting, and the
wear that makes equipment read as used: chalk, dust, rim scuffs, smudges.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import studio as S  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

FT = 0.3048
PLAT = 8 * FT                  # 2.438 m square
CENTRE_W = 4 * FT              # oak centre, along the bar axis
LAYER = 0.019                  # 3/4" plywood / stall mat


# ---------------------------------------------------------------- node helpers
class N:
    def __init__(self, nt):
        self.nt = nt

    def new(self, kind, **inputs):
        n = self.nt.nodes.new(kind)
        for k, v in inputs.items():
            n.inputs[k].default_value = v
        return n

    def op(self, kind, a, b=None, c=None):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = kind
        for i, v in enumerate((a, b, c)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                self.nt.links.new(v, n.inputs[i])
        return n.outputs[0]

    def link(self, a, b):
        self.nt.links.new(a, b)

    def mix(self, fac, a, b):
        """Colour mix; a/b are sockets or RGB tuples."""
        m = self.nt.nodes.new("ShaderNodeMix")
        m.data_type = "RGBA"
        ins = [i for i in m.inputs if i.type == "RGBA"]
        fac_in = [i for i in m.inputs if i.name == "Factor" and i.type == "VALUE"][0]
        if isinstance(fac, (int, float)):
            fac_in.default_value = fac
        else:
            self.link(fac, fac_in)
        for sock, v in zip(ins, (a, b)):
            if isinstance(v, tuple):
                sock.default_value = (*v, 1) if len(v) == 3 else v
            else:
                self.link(v, sock)
        return [o for o in m.outputs if o.type == "RGBA"][0]

    def smooth(self, x, lo, hi):
        mr = self.nt.nodes.new("ShaderNodeMapRange")
        mr.interpolation_type = "SMOOTHSTEP"
        mr.inputs["From Min"].default_value = lo
        mr.inputs["From Max"].default_value = hi
        self.link(x, mr.inputs["Value"])
        return mr.outputs[0]

    def noise(self, scale, detail=4.0, rough=0.5, vec=None, dim="3D"):
        n = self.nt.nodes.new("ShaderNodeTexNoise")
        n.noise_dimensions = dim
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        if vec is not None:
            self.link(vec, n.inputs["Vector"])
        return n


def base(name):
    m, nt, b = S.node_mat(name)
    return m, N(nt), b


def obj_coords(n):
    tc = n.nt.nodes.new("ShaderNodeTexCoord")
    sep = n.nt.nodes.new("ShaderNodeSeparateXYZ")
    n.link(tc.outputs["Object"], sep.inputs[0])
    return tc, sep


def bump_into(n, b, height, strength, distance):
    bp = n.new("ShaderNodeBump", Strength=strength, Distance=distance)
    n.link(height, bp.inputs["Height"])
    n.link(bp.outputs["Normal"], b.inputs["Normal"])
    return bp


# ---------------------------------------------------------------- worn materials
def mat_rubber_worn(name, colour, R, flecks=False, rough=0.55):
    """Competition rubber that has been dropped: satin body, rim scuffs where
    it meets the platform, chalk dust that settles on up-facing surfaces."""
    m, n, b = base(name)
    tc, sep = obj_coords(n)
    r = n.op("SQRT", n.op("ADD", n.op("MULTIPLY", sep.outputs["Y"], sep.outputs["Y"]),
                          n.op("MULTIPLY", sep.outputs["Z"], sep.outputs["Z"])))
    mott = n.noise(30.0, 6.0, 0.55, tc.outputs["Object"])
    body = n.mix(n.op("MULTIPLY", n.smooth(mott.outputs["Fac"], 0.35, 0.65), 0.22), colour,
                 tuple(c * 0.82 for c in colour))
    if flecks:
        vor = n.nt.nodes.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 260.0
        n.link(tc.outputs["Object"], vor.inputs["Vector"])
        fleckmask = n.op("LESS_THAN", vor.outputs["Distance"], 0.16)
        body = n.mix(fleckmask, body, vor.outputs["Color"])
    # Rim scuffs: lighter, rougher streaks on the tyre and the outer face band.
    rim = n.smooth(r, R * 0.90, R * 0.985)
    streak = n.noise(9.0, 8.0, 0.7, tc.outputs["Object"])
    scuffmask = n.op("MULTIPLY", rim, n.smooth(streak.outputs["Fac"], 0.52, 0.68))
    scuffcol = tuple(min(1.0, c * 1.25 + 0.045) for c in colour)
    body = n.mix(n.op("MULTIPLY", scuffmask, 0.75), body, scuffcol)
    # Dust settles on faces that look up.
    geo = n.nt.nodes.new("ShaderNodeNewGeometry")
    nsep = n.nt.nodes.new("ShaderNodeSeparateXYZ")
    n.link(geo.outputs["Normal"], nsep.inputs[0])
    up = n.smooth(nsep.outputs["Z"], 0.35, 0.95)
    dustn = n.noise(55.0, 3.0, 0.6, tc.outputs["Object"])
    dust = n.op("MULTIPLY", up, n.op("MULTIPLY", n.smooth(dustn.outputs["Fac"], 0.55, 0.8), 0.07))
    body = n.mix(dust, body, (0.42, 0.41, 0.39))
    n.link(body, b.inputs["Base Color"])
    rr = n.op("ADD", rough, n.op("ADD", n.op("MULTIPLY", scuffmask, 0.25), n.op("MULTIPLY", dust, 0.6)))
    n.link(rr, b.inputs["Roughness"])
    S.set_in(b, "Specular IOR Level", 0.42)
    grain = n.noise(1800.0, 2.0, 0.5, tc.outputs["Object"])
    bump_into(n, b, grain.outputs["Fac"], 0.22, 0.00008)
    return m


def mat_ink_worn(name, colour=(0.80, 0.80, 0.78)):
    m, n, b = base(name)
    tc, _ = obj_coords(n)
    wear = n.noise(70.0, 5.0, 0.6, tc.outputs["Object"])
    col = n.mix(n.op("MULTIPLY", n.smooth(wear.outputs["Fac"], 0.55, 0.7), 0.55), colour,
                tuple(c * 0.55 for c in colour))
    n.link(col, b.inputs["Base Color"])
    S.set_in(b, "Roughness", 0.58)
    S.set_in(b, "Specular IOR Level", 0.4)
    return m


def mat_chrome_used(name="chrome", tint=(0.93, 0.94, 0.95), rough=0.05):
    """Polished chrome with handling smudges: roughness drifts in soft patches."""
    m, n, b = base(name)
    S.set_in(b, "Base Color", (*tint, 1))
    S.set_in(b, "Metallic", 1.0)
    tc, _ = obj_coords(n)
    sm = n.noise(22.0, 3.0, 0.6, tc.outputs["Object"])
    n.link(n.op("ADD", rough, n.op("MULTIPLY", n.smooth(sm.outputs["Fac"], 0.5, 0.8), 0.13)), b.inputs["Roughness"])
    return m


def mat_shaft_chalked():
    """Hard-chrome shaft; knurl zones are satin and carry chalk."""
    m, n, b = base("shaft")
    tc, sep = obj_coords(n)
    theta = n.op("ARCTAN2", sep.outputs["Z"], sep.outputs["Y"])
    u = n.op("MULTIPLY", theta, S.BAR["shaft_r"])
    x = sep.outputs["X"]
    pitch = 0.0016

    def tri(v):
        f = n.op("FRACT", n.op("DIVIDE", v, pitch))
        return n.op("SUBTRACT", 0.5, n.op("ABSOLUTE", n.op("SUBTRACT", f, 0.5)))

    h = n.op("MINIMUM", tri(n.op("ADD", u, x)), tri(n.op("SUBTRACT", u, x)))
    ax = n.op("ABSOLUTE", x)
    centre = n.op("LESS_THAN", ax, 0.06)
    outer = n.op("MULTIPLY", n.op("GREATER_THAN", ax, 0.21), n.op("LESS_THAN", ax, 0.632))
    ring1 = n.op("LESS_THAN", n.op("ABSOLUTE", n.op("SUBTRACT", ax, 0.405)), 0.0025)
    ring2 = n.op("LESS_THAN", n.op("ABSOLUTE", n.op("SUBTRACT", ax, 0.455)), 0.0025)
    zone = n.op("MULTIPLY", n.op("MAXIMUM", centre, outer), n.op("SUBTRACT", 1.0, n.op("MAXIMUM", ring1, ring2)))
    cam = n.nt.nodes.new("ShaderNodeCameraData")
    near = n.op("MINIMUM", 1.0, n.op("MAXIMUM", 0.0, n.op("SUBTRACT", 1.7, n.op("MULTIPLY", cam.outputs["View Distance"], 0.8))))
    bp = n.nt.nodes.new("ShaderNodeBump")
    bp.inputs["Distance"].default_value = 0.00022
    n.link(n.op("MULTIPLY", near, 0.55), bp.inputs["Strength"])
    n.link(n.op("MULTIPLY", h, zone), bp.inputs["Height"])
    n.link(bp.outputs["Normal"], b.inputs["Normal"])
    chalk = n.noise(140.0, 4.0, 0.6, tc.outputs["Object"])
    chalkmask = n.op("MULTIPLY", zone, n.op("MULTIPLY", n.smooth(chalk.outputs["Fac"], 0.58, 0.78), 0.2))
    col = n.mix(chalkmask, (0.88, 0.89, 0.9), (0.78, 0.78, 0.76))
    n.link(col, b.inputs["Base Color"])
    metal = n.op("SUBTRACT", 1.0, chalkmask)
    n.link(metal, b.inputs["Metallic"])
    n.link(n.op("ADD", 0.14, n.op("ADD", n.op("MULTIPLY", zone, 0.16), n.op("MULTIPLY", chalkmask, 0.6))), b.inputs["Roughness"])
    return m


def mat_oak():
    """Sealed oak veneer: wave-band grain along the platform's length, satin
    polyurethane, chalk where feet land, scuffs from bar contact."""
    m, n, b = base("oak")
    tc, sep = obj_coords(n)
    mp = n.nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (5.5, 0.35, 1.0)
    n.link(tc.outputs["Object"], mp.inputs["Vector"])
    wave = n.nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.wave_profile = "SAW"
    wave.inputs["Scale"].default_value = 6.0
    wave.inputs["Distortion"].default_value = 9.0
    wave.inputs["Detail"].default_value = 6.0
    wave.inputs["Detail Scale"].default_value = 1.6
    n.link(mp.outputs["Vector"], wave.inputs["Vector"])
    fine = n.noise(260.0, 3.0, 0.6, mp.outputs["Vector"])
    g = n.op("ADD", n.op("MULTIPLY", wave.outputs["Fac"], 0.75), n.op("MULTIPLY", fine.outputs["Fac"], 0.25))
    light, dark = (0.27, 0.155, 0.075), (0.12, 0.065, 0.03)
    col = n.mix(n.smooth(g, 0.25, 0.85), light, dark)
    big = n.noise(1.3, 3.0, 0.5, tc.outputs["Object"])
    col = n.mix(n.op("MULTIPLY", big.outputs["Fac"], 0.3), col, (0.2, 0.11, 0.045))
    chalk = n.noise(3.2, 6.0, 0.62, tc.outputs["Object"])
    footzone = n.op("SUBTRACT", 1.0, n.smooth(n.op("ABSOLUTE", sep.outputs["Y"]), 0.15, 0.75))
    cm = n.op("MULTIPLY", footzone, n.op("MULTIPLY", n.smooth(chalk.outputs["Fac"], 0.6, 0.8), 0.16))
    col = n.mix(cm, col, (0.62, 0.6, 0.57))
    n.link(col, b.inputs["Base Color"])
    n.link(n.op("ADD", 0.34, n.op("MULTIPLY", cm, 0.5)), b.inputs["Roughness"])
    S.set_in(b, "Coat Weight", 0.25)
    S.set_in(b, "Coat Roughness", 0.3)
    bump_into(n, b, fine.outputs["Fac"], 0.08, 0.0003)
    return m


def mat_stallmat():
    """Horse-stall mat: dense black rubber, faint pebble, chalk and plate marks."""
    m, n, b = base("stallmat")
    tc, sep = obj_coords(n)
    peb = n.nt.nodes.new("ShaderNodeTexVoronoi")
    peb.inputs["Scale"].default_value = 160.0
    n.link(tc.outputs["Object"], peb.inputs["Vector"])
    bump_into(n, b, peb.outputs["Distance"], 0.25, 0.0006)
    blot = n.noise(2.5, 6.0, 0.65, tc.outputs["Object"])
    cm = n.op("MULTIPLY", n.smooth(blot.outputs["Fac"], 0.62, 0.8), 0.12)
    col = n.mix(cm, (0.008, 0.008, 0.009), (0.12, 0.12, 0.115))
    n.link(col, b.inputs["Base Color"])
    n.link(n.op("ADD", 0.78, n.op("MULTIPLY", cm, 0.3)), b.inputs["Roughness"])
    S.set_in(b, "Specular IOR Level", 0.3)
    return m


def mat_plyedge():
    """Plywood edge: alternating veneer plies, sanded."""
    m, n, b = base("plyedge")
    tc, sep = obj_coords(n)
    plies = n.op("FRACT", n.op("DIVIDE", sep.outputs["Z"], 0.0027))
    dark = n.op("LESS_THAN", plies, 0.22)
    col = n.mix(dark, (0.46, 0.33, 0.19), (0.2, 0.13, 0.06))
    n.link(col, b.inputs["Base Color"])
    S.set_in(b, "Roughness", 0.75)
    return m


def mat_gymfloor():
    m, n, b = base("gymfloor")
    tc, sep = obj_coords(n)
    tile = n.op("MAXIMUM", n.op("LESS_THAN", n.op("FRACT", n.op("DIVIDE", sep.outputs["X"], 1.0)), 0.002),
                n.op("LESS_THAN", n.op("FRACT", n.op("DIVIDE", sep.outputs["Y"], 1.0)), 0.002))
    speck = n.nt.nodes.new("ShaderNodeTexVoronoi")
    speck.inputs["Scale"].default_value = 420.0
    n.link(tc.outputs["Object"], speck.inputs["Vector"])
    sp = n.op("LESS_THAN", speck.outputs["Distance"], 0.12)
    col = n.mix(sp, (0.009, 0.009, 0.0095), (0.05, 0.05, 0.05))
    col = n.mix(n.op("MULTIPLY", tile, 0.8), col, (0.004, 0.004, 0.004))
    n.link(col, b.inputs["Base Color"])
    S.set_in(b, "Roughness", 0.82)
    return m


def mat_powdercoat(colour=(0.012, 0.012, 0.013)):
    m, n, b = base("powder")
    S.set_in(b, "Base Color", (*colour, 1))
    S.set_in(b, "Roughness", 0.45)
    S.set_in(b, "Coat Weight", 0.2)
    return m


def mat_wall():
    m, n, b = base("wall")
    tc, sep = obj_coords(n)
    blk = n.op("MAXIMUM", n.op("LESS_THAN", n.op("FRACT", n.op("DIVIDE", sep.outputs["X"], 0.4)), 0.02),
               n.op("LESS_THAN", n.op("FRACT", n.op("DIVIDE", sep.outputs["Z"], 0.2)), 0.04))
    col = n.mix(blk, (0.03, 0.03, 0.032), (0.018, 0.018, 0.019))
    n.link(col, b.inputs["Base Color"])
    S.set_in(b, "Roughness", 0.9)
    return m


# ---------------------------------------------------------------- geometry
def box(name, x0, x1, y0, y1, z0, z1, mat, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=((x1 - x0), (y1 - y0), (z1 - z0)), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    o.location = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    me.materials.append(mat)
    S.link(o)
    if bevel:
        mod = o.modifiers.new("bev", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.use_clamp_overlap = True
        o.modifiers.new("wn", "WEIGHTED_NORMAL")
    return o


def platform(top_z, mats):
    h = PLAT / 2
    base_top = top_z - LAYER
    # Two plywood base layers visible at the edge.
    box("base", -h, h, -h, h, base_top - 2 * LAYER, base_top, mats["plyedge"], bevel=0.002)
    # Oak centre with a sanded edge.
    box("oak", -CENTRE_W / 2, CENTRE_W / 2, -h, h, base_top, top_z, mats["oak"], bevel=0.0025)
    # Stall mats either side, butted against the oak.
    for s in (-1, 1):
        x0, x1 = sorted((s * CENTRE_W / 2 + s * 0.001, s * h))
        box(f"mat{s}", x0, x1, -h, h, base_top, top_z - 0.0004, mats["stallmat"], bevel=0.004)
    # Countersunk screws along the oak edges.
    for s in (-1, 1):
        for i in range(9):
            y = -h + 0.12 + i * (PLAT - 0.24) / 8
            for xx in (s * (CENTRE_W / 2 - 0.035),):
                scr = S.lathe("screw", [(0.0, 0.0), (0.0042, 0.0), (0.0042, -0.0006), (0.0, -0.0006)], segments=24,
                                material=mats["darksteel"])
                scr.rotation_euler = (0, math.pi / 2, 0)
                scr.location = (xx, y, top_z + 0.00005)
    # Gym floor around the platform, a block wall and a rack behind.
    box("floor", -12, 12, -12, 12, base_top - 2 * LAYER - 0.02, base_top - 2 * LAYER, mats["gymfloor"])
    fz = base_top - 2 * LAYER
    box("wall", -12, 12, 4.2, 4.4, fz, fz + 5, mats["wall"])
    for x in (-0.62, 0.62):
        for y in (2.6, 3.65):
            box("upright", x - 0.038, x + 0.038, y - 0.038, y + 0.038, fz, fz + 2.3, mats["powder"])
    for y in (2.6, 3.65):
        box("cross", -0.66, 0.66, y - 0.038, y + 0.038, fz + 2.26, fz + 2.34, mats["powder"])
    for x in (-0.62, 0.62):
        box("side", x - 0.038, x + 0.038, 2.6, 3.65, fz + 2.26, fz + 2.34, mats["powder"])
    return fz


def collar(side, x_inner, mats):
    """Competition-style spring-lock collar: chrome body, knurled grip ring,
    black release lever."""
    s = side
    L = 0.050
    prof = [(S.BAR["sleeve_r"] + 0.0004, 0.0), (0.036, 0.0), (0.040, 0.004), (0.040, 0.020), (0.037, 0.022),
            (0.037, 0.034), (0.040, 0.036), (0.040, L - 0.004), (0.036, L), (S.BAR["sleeve_r"] + 0.0004, L)]
    prof = [(r, s * a) for r, a in prof]
    o = S.lathe(f"collar{s}", prof, segments=128, material=mats["chrome"])
    o.location = (s * x_inner, 0, 0)
    grip = S.lathe(f"grip{s}", [(0.0372, s * 0.022), (0.0385, s * 0.023), (0.0385, s * 0.033), (0.0372, s * 0.034)],
                   segments=96, material=mats["knurlring"])
    grip.location = o.location
    lev = box(f"lever{s}", -0.014, 0.014, -0.006, 0.006, 0.0, 0.034, mats["lever"], bevel=0.003)
    lev.location = (s * (x_inner + 0.012), 0, 0.040 + 0.017)
    lev.rotation_euler = (0, s * 0.35, 0)
    return L


def load(stack, mats, explode=0.0, sides=(-1, 1), collars=True, kind="bumper"):
    maxr = 0.0
    for side in sides:
        cursor = S.SLEEVE_START + 0.0005
        for i, w in enumerate(stack):
            body, T, R = (S.bumper_plate(w, mats) if kind == "bumper" else S.iron_plate(w, mats))
            cx = cursor + T / 2 + explode * i
            body.location = (side * cx, 0, 0)
            if side > 0:
                body.rotation_euler = (0, 0, math.pi)
            cursor += T + 0.0004
            maxr = max(maxr, R)
        if collars and not explode:
            collar(side, cursor + 0.0005, mats)
    return maxr


def materials():
    m = S.materials()
    m["chrome"] = mat_chrome_used("chrome", rough=0.06)
    m["sleeve"] = mat_chrome_used("sleeve", rough=0.035)
    m["shaft"] = mat_shaft_chalked()
    m["ink"] = mat_ink_worn("ink")
    m["ink_dark"] = mat_ink_worn("inkdark", (0.03, 0.03, 0.032))
    for w, c in S.BUMPER_COLOUR.items():
        R = S.BUMPER[w][0] / 2000.0
        m[f"rubber{w}"] = mat_rubber_worn(f"rubber{w}", c, R)
    m["oak"] = mat_oak()
    m["stallmat"] = mat_stallmat()
    m["plyedge"] = mat_plyedge()
    m["gymfloor"] = mat_gymfloor()
    m["powder"] = mat_powdercoat()
    m["wall"] = mat_wall()
    m["knurlring"] = S.mat_paint("knurlring", (0.5, 0.5, 0.52), rough=0.4, coat=0.0, metallic=1.0, hammer=0.6)
    m["lever"] = S.mat_paint("lever", (0.015, 0.015, 0.016), rough=0.38, coat=0.3)
    return m


def gym_lights():
    """Overhead LED panels in rows, like a real gym ceiling: they are what the
    chrome reflects. A dim bounce from the far wall and a soft front fill."""
    for x in (-1.6, 0.0, 1.6):
        for y in (-1.2, 0.6, 2.4):
            S.area(f"panel{x}{y}", 1.2, 260, (x, y, 3.3), (x, y, 0.0), size_y=0.3, colour=(1.0, 0.97, 0.92), spread=110)
    S.area("bounce", 6.0, 160, (0.0, 4.0, 1.4), (0.0, 0.0, 0.0), size_y=2.0, colour=(0.9, 0.93, 1.0), spread=100)
    S.area("fill", 4.0, 70, (0.0, -4.5, 1.2), (0.0, 0.0, 0.0), size_y=1.5, spread=70)
    S.reflector("cardFront", (-0.3, -2.8, 1.9), (-0.2, 0, 0.0), 2.4, 0.5, 0.35)


def shot(name):
    s = S.reset()
    s.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.012, 0.013, 1)
    mats = materials()
    if name != "p_macro":
        S.build_bar(mats)
    R = 0.225
    top = -R
    if name == "p_hero":
        load([45], mats)
        platform(top, mats); gym_lights()
        S.camera((-2.0, -2.25, 0.32), (-0.22, 0.0, -0.06), lens=45, fstop=4.0)
    elif name == "p_straight":
        load([45], mats)
        platform(top, mats); gym_lights()
        S.camera((-0.25, -3.1, 0.02), (0.0, 0.0, -0.06), lens=35, fstop=5.6)
    elif name == "p_lifter":
        load([45, 25], mats)
        platform(top, mats); gym_lights()
        S.camera((0.05, -0.95, 1.38), (0.0, 0.05, -0.18), lens=24, fstop=8.0)
    elif name == "p_close":
        load([45, 25, 10, 2.5], mats)
        platform(top, mats); gym_lights()
        S.camera((-1.78, -0.70, 0.10), (-0.88, 0.0, -0.02), lens=85, fstop=2.8)
    elif name == "p_blowup":
        load([45, 25, 10, 5, 2.5], mats, explode=0.17, sides=(-1,), collars=False)
        platform(top, mats); gym_lights()
        S.camera((-1.55, -1.7, 0.30), (-1.02, 0.0, -0.05), lens=40, fstop=7.1)
    elif name == "p_macro":
        body, T, Rp = S.bumper_plate(45, mats)
        body.rotation_euler = (0, 0, math.radians(-90 + 26))
        body.location = (0.9, 0.2, 0.0)
        platform(top, mats); gym_lights()
        S.camera((0.55, -0.62, 0.06), (0.9, 0.2, -0.01), lens=50, fstop=4.0)
    else:
        raise SystemExit(f"unknown shot {name}")
    return s


if __name__ == "__main__":
    name, out = sys.argv[1], sys.argv[2]
    samples = int(sys.argv[3]) if len(sys.argv) > 3 else 48
    w = int(sys.argv[4]) if len(sys.argv) > 4 else 1280
    h = int(sys.argv[5]) if len(sys.argv) > 5 else 720
    s = shot(name)
    s.cycles.samples = samples
    s.render.resolution_x, s.render.resolution_y = w, h
    s.render.resolution_percentage = 100
    s.render.filepath = os.path.abspath(out)
    s.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("WROTE", out)
