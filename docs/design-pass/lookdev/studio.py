"""Cadence equipment look-dev: path-traced barbell and plate mockups.

Requires: pip install bpy (Blender 5.2 as a Python module).
Run: python3 studio.py <shot> <out.png> [samples] [width] [height]
Units are metres. The bar axis is X, Z is up, the camera looks toward +Y.
"""
import math
import os
import sys

import bpy  # noqa: E402  (bmesh/mathutils load with bpy)
import bmesh
from mathutils import Vector

FONT_NUM = "/mnt/skills/examples/canvas-design/canvas-fonts/BigShoulders-Bold.ttf"
FONT_BRAND = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"

# ---------------------------------------------------------------- equipment data
BORE = 0.02525
BAR = dict(shaft_r=0.014, shaft_half=0.655, shoulder_len=0.030, shoulder_r=0.0335,
           sleeve_r=0.025, sleeve_len=0.415)
SLEEVE_START = BAR["shaft_half"] + BAR["shoulder_len"]          # 0.685
SLEEVE_END = SLEEVE_START + BAR["sleeve_len"]                   # 1.100

# lb colour bumpers (diameter, thickness in mm) and federation-style colours.
BUMPER = {45: (450, 60), 35: (450, 49), 25: (450, 38), 10: (450, 21), 5: (190, 19), 2.5: (162, 15)}
BUMPER_COLOUR = {45: (0.035, 0.11, 0.42), 35: (0.62, 0.42, 0.012), 25: (0.016, 0.22, 0.06),
                 10: (0.72, 0.70, 0.66), 5: (0.012, 0.012, 0.013), 2.5: (0.012, 0.012, 0.013)}
# Cast iron (York-style deep dish).
IRON = {45: (450, 50), 35: (360, 34.5), 25: (276, 34.5), 10: (229, 20), 5: (190, 14.5), 2.5: (162, 12)}


def label(w):
    return f"{w:g}"


# ---------------------------------------------------------------- scene basics
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.use_denoising = True
    try:
        s.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    s.cycles.use_adaptive_sampling = True
    s.cycles.max_bounces = 8
    s.cycles.glossy_bounces = 6
    s.cycles.diffuse_bounces = 4
    s.cycles.transmission_bounces = 2
    s.cycles.caustics_reflective = False
    s.cycles.caustics_refractive = False
    s.view_settings.view_transform = os.environ.get("VIEW", "AgX")
    for look in ((os.environ.get("LOOK"),) if os.environ.get("LOOK") else ("AgX - Punchy", "Punchy")):
        try:
            s.view_settings.look = look
            break
        except Exception:
            continue
    s.render.film_transparent = False
    s.view_settings.exposure = float(os.environ.get("EXPOSURE", "0"))
    w = bpy.data.worlds.new("world")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.009, 0.0095, 0.0105, 1)
    bg.inputs["Strength"].default_value = 1.0
    s.world = w
    return s


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def smooth(mesh):
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))


def lathe(name, profile, segments=192, material=None):
    """Revolve (radius, axial) points around X. Each profile edge owns its ring
    pair so creases stay crisp while the circumference shades smoothly."""
    bm = bmesh.new()
    for (r0, x0), (r1, x1) in zip(profile, profile[1:]):
        if abs(r0 - r1) < 1e-9 and abs(x0 - x1) < 1e-9:
            continue
        ring0, ring1 = [], []
        for j in range(segments):
            t = 2 * math.pi * j / segments
            c, sn = math.cos(t), math.sin(t)
            ring0.append(bm.verts.new((x0, r0 * c, r0 * sn)))
            ring1.append(bm.verts.new((x1, r1 * c, r1 * sn)))
        for j in range(segments):
            k = (j + 1) % segments
            try:
                bm.faces.new((ring0[j], ring0[k], ring1[k], ring1[j]))
            except ValueError:
                pass
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    smooth(me)
    obj = bpy.data.objects.new(name, me)
    if material:
        me.materials.append(material)
    link(obj)
    # Outward normals: recalc via bmesh on the object mesh.
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return obj


def fillet(cx, cy, r, a0, a1, n=6):
    return [(cx + r * math.cos(a), cy + r * math.sin(a))
            for a in [a0 + (a1 - a0) * i / n for i in range(n + 1)]]


# ---------------------------------------------------------------- materials
def node_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    return m, nt, bsdf


def set_in(bsdf, key, value):
    if key in bsdf.inputs:
        bsdf.inputs[key].default_value = value


def mat_chrome(name="chrome", rough=0.06, tint=(0.92, 0.93, 0.95)):
    m, nt, b = node_mat(name)
    set_in(b, "Base Color", (*tint, 1))
    set_in(b, "Metallic", 1.0)
    set_in(b, "Roughness", rough)
    return m


def mat_brushed_hub(name="hub"):
    """Lathe-turned stainless: concentric machining marks as bump + anisotropy."""
    m, nt, b = node_mat(name)
    set_in(b, "Base Color", (0.62, 0.63, 0.65, 1))
    set_in(b, "Metallic", 1.0)
    set_in(b, "Roughness", 0.28)
    set_in(b, "Anisotropic", 0.6)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    # radius in the plate's YZ plane
    yy = nt.nodes.new("ShaderNodeMath"); yy.operation = "MULTIPLY"
    zz = nt.nodes.new("ShaderNodeMath"); zz.operation = "MULTIPLY"
    nt.links.new(sep.outputs["Y"], yy.inputs[0]); nt.links.new(sep.outputs["Y"], yy.inputs[1])
    nt.links.new(sep.outputs["Z"], zz.inputs[0]); nt.links.new(sep.outputs["Z"], zz.inputs[1])
    add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"
    nt.links.new(yy.outputs[0], add.inputs[0]); nt.links.new(zz.outputs[0], add.inputs[1])
    sq = nt.nodes.new("ShaderNodeMath"); sq.operation = "SQRT"
    nt.links.new(add.outputs[0], sq.inputs[0])
    sc = nt.nodes.new("ShaderNodeMath"); sc.operation = "MULTIPLY"; sc.inputs[1].default_value = 2600.0
    nt.links.new(sq.outputs[0], sc.inputs[0])
    sn = nt.nodes.new("ShaderNodeMath"); sn.operation = "SINE"
    nt.links.new(sc.outputs[0], sn.inputs[0])
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 900
    mix = nt.nodes.new("ShaderNodeMath"); mix.operation = "MULTIPLY_ADD"
    nt.links.new(sn.outputs[0], mix.inputs[0]); mix.inputs[1].default_value = 0.6
    nt.links.new(noise.outputs["Fac"], mix.inputs[2])
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.12
    bump.inputs["Distance"].default_value = 0.00004
    nt.links.new(mix.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    # tangent around the bar axis gives circular anisotropic highlights
    tan = nt.nodes.new("ShaderNodeTangent"); tan.direction_type = "RADIAL"; tan.axis = "X"
    if "Tangent" in b.inputs:
        nt.links.new(tan.outputs["Tangent"], b.inputs["Tangent"])
    return m


def mat_rubber(name, colour, rough=0.58, sheen=0.0):
    """Virgin-rubber competition bumper: satin, micro-texture, faint mottling."""
    m, nt, b = node_mat(name)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 140.0
    noise.inputs["Detail"].default_value = 8.0
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["To Min"].default_value = 0.93
    ramp.inputs["To Max"].default_value = 1.05
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Value"])
    rgb = nt.nodes.new("ShaderNodeRGB"); rgb.outputs[0].default_value = (*colour, 1)
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    a_in = [i for i in mul.inputs if i.name == "A" and i.type == "RGBA"][0]
    b_in = [i for i in mul.inputs if i.name == "B" and i.type == "RGBA"][0]
    res = [o for o in mul.outputs if o.type == "RGBA"][0]
    nt.links.new(rgb.outputs[0], a_in)
    comb = nt.nodes.new("ShaderNodeCombineColor")
    for i in range(3):
        nt.links.new(ramp.outputs[0], comb.inputs[i])
    nt.links.new(comb.outputs[0], b_in)
    nt.links.new(res, b.inputs["Base Color"])
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = rough - 0.08
    rr.inputs["To Max"].default_value = rough + 0.08
    n2 = nt.nodes.new("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = 38.0
    nt.links.new(n2.outputs["Fac"], rr.inputs["Value"])
    nt.links.new(rr.outputs[0], b.inputs["Roughness"])
    grain = nt.nodes.new("ShaderNodeTexNoise"); grain.inputs["Scale"].default_value = 2600.0
    grain.inputs["Detail"].default_value = 2.0
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25
    bump.inputs["Distance"].default_value = 0.00008
    nt.links.new(grain.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    set_in(b, "Specular IOR Level", 0.45)
    if sheen:
        set_in(b, "Sheen Weight", sheen)
    return m


def mat_paint(name, colour, rough=0.28, coat=0.6, metallic=0.0, hammer=0.0):
    m, nt, b = node_mat(name)
    set_in(b, "Base Color", (*colour, 1))
    set_in(b, "Metallic", metallic)
    set_in(b, "Roughness", rough)
    set_in(b, "Coat Weight", coat)
    set_in(b, "Coat Roughness", 0.08)
    if hammer:
        vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 260.0
        bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = hammer
        bump.inputs["Distance"].default_value = 0.0004
        nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
        if "Coat Normal" in b.inputs:
            nt.links.new(bump.outputs["Normal"], b.inputs["Coat Normal"])
    return m


def mat_print(name, colour=(0.86, 0.86, 0.84)):
    m, nt, b = node_mat(name)
    set_in(b, "Base Color", (*colour, 1))
    set_in(b, "Roughness", 0.5)
    set_in(b, "Specular IOR Level", 0.4)
    return m


def mat_knurled_shaft(name="shaft"):
    """Hard-chrome shaft with a true diamond knurl in the authored zones."""
    m, nt, b = node_mat(name)
    set_in(b, "Base Color", (0.9, 0.91, 0.93, 1))
    set_in(b, "Metallic", 1.0)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])

    def op(kind, a, bb=None, value=None):
        n = nt.nodes.new("ShaderNodeMath"); n.operation = kind
        if isinstance(a, (int, float)):
            n.inputs[0].default_value = a
        else:
            nt.links.new(a, n.inputs[0])
        if bb is not None:
            if isinstance(bb, (int, float)):
                n.inputs[1].default_value = bb
            else:
                nt.links.new(bb, n.inputs[1])
        return n.outputs[0]

    theta = op("ARCTAN2", sep.outputs["Z"], sep.outputs["Y"])
    u = op("MULTIPLY", theta, BAR["shaft_r"])          # arc length
    x = sep.outputs["X"]
    pitch = 0.0016

    def tri(v):
        f = op("FRACT", op("DIVIDE", v, pitch))
        return op("SUBTRACT", 0.5, op("ABSOLUTE", op("SUBTRACT", f, 0.5)))

    h = op("MINIMUM", tri(op("ADD", u, x)), tri(op("SUBTRACT", u, x)))
    ax = op("ABSOLUTE", x)
    # zones: centre knurl |x|<0.08, outer 0.215..0.62 minus 0.405/0.455 rings
    centre = op("LESS_THAN", ax, 0.08)
    outer = op("MULTIPLY", op("GREATER_THAN", ax, 0.215), op("LESS_THAN", ax, 0.62))
    ring1 = op("LESS_THAN", op("ABSOLUTE", op("SUBTRACT", ax, 0.405)), 0.0025)
    ring2 = op("LESS_THAN", op("ABSOLUTE", op("SUBTRACT", ax, 0.455)), 0.0025)
    rings = op("MAXIMUM", ring1, ring2)
    zone = op("MULTIPLY", op("MAXIMUM", centre, outer), op("SUBTRACT", 1.0, rings))
    height = op("MULTIPLY", h, zone)
    cam = nt.nodes.new("ShaderNodeCameraData")
    near = op("MINIMUM", 1.0, op("MAXIMUM", 0.0, op("SUBTRACT", 1.6, op("MULTIPLY", cam.outputs["View Distance"], 0.75))))
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Distance"].default_value = 0.00025
    nt.links.new(op("MULTIPLY", near, 0.5), bump.inputs["Strength"])
    nt.links.new(height, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    rough = op("ADD", 0.16, op("MULTIPLY", zone, op("SUBTRACT", 0.34, op("MULTIPLY", near, 0.12))))
    nt.links.new(rough, b.inputs["Roughness"])
    return m


def mat_floor():
    m, nt, b = node_mat("floor")
    set_in(b, "Base Color", (0.0055, 0.0058, 0.0065, 1))
    set_in(b, "Roughness", 0.8)
    set_in(b, "Specular IOR Level", 0.22)
    speck = nt.nodes.new("ShaderNodeTexVoronoi"); speck.inputs["Scale"].default_value = 900.0
    sb = nt.nodes.new("ShaderNodeBump"); sb.inputs["Strength"].default_value = 0.15; sb.inputs["Distance"].default_value = 0.0005
    nt.links.new(speck.outputs["Distance"], sb.inputs["Height"]); nt.links.new(sb.outputs["Normal"], b.inputs["Normal"])
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 8.0
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = 0.72; rr.inputs["To Max"].default_value = 0.9
    nt.links.new(noise.outputs["Fac"], rr.inputs["Value"]); nt.links.new(rr.outputs[0], b.inputs["Roughness"])
    return m


def mat_dark_steel():
    return mat_paint("darksteel", (0.02, 0.02, 0.022), rough=0.35, coat=0.0, metallic=0.8)


# ---------------------------------------------------------------- text on faces
_fonts = {}


def font(path):
    if path not in _fonts:
        _fonts[path] = bpy.data.fonts.load(path)
    return _fonts[path]


def text_mesh(body, path, size, extrude, spacing=1.0):
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = body
    cu.font = font(path)
    cu.size = size
    cu.extrude = extrude
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.space_character = spacing
    cu.bevel_depth = min(extrude * 0.35, 0.0004)
    cu.bevel_resolution = 2
    tmp = bpy.data.objects.new("t", cu)
    link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    return me


def arc_text(body, path, size, extrude, radius, top=True, spacing=1.05):
    """Bend a flat text mesh around the plate centre. Text runs along +X,
    reads upright at the top (top=True) or bottom of the plate face."""
    me = text_mesh(body, path, size, extrude, spacing)
    for v in me.vertices:
        x, y, z = v.co
        if top:
            a = x / radius
            rr = radius + y
            v.co = (rr * math.sin(a), rr * math.cos(a), z)
        else:
            a = -x / radius
            rr = radius - y
            v.co = (-rr * math.sin(a), -rr * math.cos(a), z)
    me.update()
    return me


def place_on_face(me, plate_obj, face_x, outward, material, name):
    """Text meshes are authored in XY with +Z out of the face. Map them onto
    the plate face at local X = face_x whose outward normal is ±X."""
    obj = bpy.data.objects.new(name, me)
    me.materials.append(material)
    smooth(me)
    # Rotate so text +Z → outward (±X), text +Y → world +Z (up), text +X → horizontal.
    from mathutils import Matrix
    if outward < 0:   # text +X→-Y, +Y→+Z, +Z→-X: upright and left-to-right seen from -X
        rot = Matrix(((0, 0, -1), (-1, 0, 0), (0, 1, 0)))
    else:             # text +X→+Y, +Y→+Z, +Z→+X
        rot = Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0)))
    obj.rotation_euler = rot.to_euler()
    obj.location = (face_x, 0, 0)
    obj.parent = plate_obj
    link(obj)
    return obj


# ---------------------------------------------------------------- equipment
def build_bar(mats, collars=False):
    shaft = lathe("shaft", [(0.0, -BAR["shaft_half"] - 0.002), (BAR["shaft_r"], -BAR["shaft_half"] - 0.002),
                            (BAR["shaft_r"], BAR["shaft_half"] + 0.002), (0.0, BAR["shaft_half"] + 0.002)],
                  segments=128, material=mats["shaft"])
    parts = [shaft]
    for side in (-1, 1):
        s = side
        x0, x1 = s * BAR["shaft_half"], s * SLEEVE_START
        sr, cr = BAR["sleeve_r"], BAR["shoulder_r"]
        # Fixed inner collar with a bronze-look bushing gap and chamfers.
        prof = [(BAR["shaft_r"], x0 - s * 0.0005), (cr - 0.0035, x0), (cr, x0 + s * 0.0035), (cr, x1 - s * 0.006),
                (cr - 0.004, x1 - s * 0.003), (cr - 0.004, x1), (sr, x1)]
        if s < 0:
            prof = [(r, x) for r, x in prof]
        parts.append(lathe(f"shoulder{s}", prof, segments=128, material=mats["chrome"]))
        # Sleeve: polished, two machined grooves near the end, chamfered end.
        e = s * SLEEVE_END
        g1, g2 = e - s * 0.040, e - s * 0.055
        sleeve = [(sr * 0.98, x1), (sr, x1 + s * 0.0005), (sr, g2), (sr - 0.0008, g2 + s * 0.001), (sr - 0.0008, g2 + s * 0.0025),
                  (sr, g2 + s * 0.0035), (sr, g1), (sr - 0.0008, g1 + s * 0.001), (sr - 0.0008, g1 + s * 0.0025),
                  (sr, g1 + s * 0.0035), (sr, e - s * 0.0025), (sr - 0.0025, e), (0.017, e), (0.016, e - s * 0.003),
                  (0.0, e - s * 0.003)]
        parts.append(lathe(f"sleeve{s}", sleeve, segments=160, material=mats["sleeve"]))
        cap = [(0.0, e - s * 0.003 + s * 0.0002), (0.010, e - s * 0.0028), (0.0105, e - s * 0.0015), (0.0, e - s * 0.0013)]
        parts.append(lathe(f"cap{s}", cap, segments=64, material=mats["darksteel"]))
    return parts


def bumper_plate(w, mats, theme="bumper"):
    d, t = BUMPER[w]
    R, T = d / 2000.0, t / 1000.0
    small = R < 0.15
    hub_r = 0.108 if not small else max(BORE + 0.012, R * 0.42)
    ht = T / 2
    col = mats[f"rubber{w}"]
    # Rubber body: flat faces, slight shallow ring groove, rounded tyre edge.
    f = min(0.008, T * 0.22)
    groove_r = R * 0.80
    prof = [(hub_r, -ht + 0.0008), (groove_r - 0.004, -ht), (groove_r - 0.002, -ht + 0.0012),
            (groove_r + 0.002, -ht + 0.0012), (groove_r + 0.004, -ht), (R - f, -ht)]
    prof += fillet(R - f, -ht + f, f, -math.pi / 2, 0, 6)[1:]
    prof += fillet(R - f, ht - f, f, 0, math.pi / 2, 6)
    prof += [(groove_r + 0.004, ht), (groove_r + 0.002, ht - 0.0012), (groove_r - 0.002, ht - 0.0012),
             (groove_r - 0.004, ht), (hub_r, ht - 0.0008)]
    body = lathe(f"plate{w}", [(r, x) for r, x in prof], segments=192, material=col)
    # Hub insert: proud steel flange with bevels, through the bore.
    hp = 0.0012
    hub = [(BORE, -ht - hp + 0.0008), (BORE + 0.0008, -ht - hp), (hub_r - 0.0015, -ht - hp), (hub_r, -ht - hp + 0.0015),
           (hub_r, ht + hp - 0.0015), (hub_r - 0.0015, ht + hp), (BORE + 0.0008, ht + hp), (BORE, ht + hp - 0.0008),
           (BORE, -ht - hp + 0.0008)]
    hubobj = lathe(f"hub{w}", hub, segments=160, material=mats["hub"])
    hubobj.parent = body
    if not small:
        for i in range(6):
            a = 2 * math.pi * i / 6 + math.pi / 6
            for face in (-1, 1):
                bolt = lathe("bolt", [(0.0, 0), (0.0085, 0), (0.0092, face * 0.0008), (0.0092, face * 0.0030),
                                      (0.0080, face * 0.0040), (0.0, face * 0.0040)], segments=48, material=mats["bolt"])
                bolt.location = (face * (ht + hp), 0.079 * math.cos(a), 0.079 * math.sin(a))
                bolt.parent = body
                sock = lathe("sock", [(0.0, face * 0.0041), (0.0040, face * 0.0041), (0.0040, face * 0.0030), (0.0, face * 0.0030)],
                             segments=6, material=mats["darksteel"])
                sock.location = bolt.location
                sock.parent = body
    # Print: white denomination at the bottom, brand at the top, both faces.
    ink = mats["ink_dark"] if w == 10 else mats["ink"]
    num_size = 0.074 if not small else R * 0.30
    for face in (-1, 1):
        fx = face * (ht + 0.00005)
        if not small:
            me = arc_text(f"{label(w)} LB", FONT_NUM, num_size, 0.00025, radius=(hub_r + groove_r) / 2 + 0.002, top=False, spacing=1.08)
            place_on_face(me, body, fx, face, ink, f"num{w}")
            me = arc_text("CADENCE", FONT_BRAND, 0.030, 0.00025, radius=(hub_r + groove_r) / 2 - 0.004, top=True, spacing=1.35)
            place_on_face(me, body, fx, face, ink, f"brand{w}")
            # thin printed ring just inside the groove
        else:
            me = arc_text(f"{label(w)} LB", FONT_NUM, num_size, 0.0002, radius=(hub_r + R) / 2 - 0.004, top=False, spacing=1.05)
            place_on_face(me, body, fx, face, mats["ink"], f"num{w}")
    return body, T, R


def iron_plate(w, mats):
    d, t = IRON[w]
    R, T = d / 2000.0, t / 1000.0
    ht = T / 2
    boss = max(BORE + 0.022, R * 0.27)
    lip = max(0.014, R * 0.075)
    dish = ht - min(0.007, T * 0.22)
    f = 0.0035
    prof = [(boss, -ht - 0.0015), (boss + 0.004, -dish), (R - lip - 0.004, -dish), (R - lip, -ht + 0.0005),
            (R - f, -ht)]
    prof += fillet(R - f, -ht + f, f, -math.pi / 2, 0, 4)[1:]
    prof += fillet(R - f, ht - f, f, 0, math.pi / 2, 4)
    prof += [(R - lip, ht - 0.0005), (R - lip - 0.004, dish), (boss + 0.004, dish), (boss, ht + 0.0015)]
    body = lathe(f"iron{w}", prof, segments=192, material=mats["iron"])
    hub = [(BORE, -ht - 0.0015), (boss, -ht - 0.0015), (boss, ht + 0.0015), (BORE, ht + 0.0015), (BORE, -ht - 0.0015)]
    lathe(f"ironhub{w}", hub, segments=160, material=mats["iron"]).parent = body
    for face in (-1, 1):
        fx = face * dish
        me = arc_text(f"{label(w)}", FONT_NUM, 0.09 if R > 0.17 else R * 0.4, 0.0022, radius=(boss + R - lip) / 2, top=False, spacing=1.1)
        place_on_face(me, body, fx, face, mats["iron"], f"inum{w}")
        if R > 0.15:
            me = arc_text("CADENCE  ·  LB", FONT_BRAND, 0.024, 0.0015, radius=(boss + R - lip) / 2, top=True, spacing=1.3)
            place_on_face(me, body, fx, face, mats["iron"], f"ibrand{w}")
    return body, T, R


def load_bar(stack, mats, kind="bumper", explode=0.0, sides=(-1, 1), lift=0.0):
    """stack: per-side weights from the shoulder outward. Returns max radius."""
    maxr = 0.0
    for side in sides:
        cursor = SLEEVE_START + 0.0005
        for i, w in enumerate(stack):
            body, T, R = (bumper_plate(w, mats) if kind == "bumper" else iron_plate(w, mats))
            cx = cursor + T / 2 + explode * i
            body.location = (side * cx, 0, lift)
            if side > 0:
                body.rotation_euler = (0, 0, math.pi)
            cursor += T + 0.0004
            maxr = max(maxr, R)
    return maxr


def materials():
    m = {
        "chrome": mat_chrome("chrome", 0.07),
        "sleeve": mat_chrome("sleeve", 0.045, (0.93, 0.94, 0.95)),
        "shaft": mat_knurled_shaft(),
        "darksteel": mat_dark_steel(),
        "hub": mat_brushed_hub(),
        "bolt": mat_chrome("bolt", 0.18, (0.78, 0.79, 0.8)),
        "ink": mat_print("ink"),
        "ink_dark": mat_print("inkdark", (0.02, 0.02, 0.022)),
        "iron": mat_paint("iron", (0.022, 0.022, 0.024), rough=0.38, coat=0.5, metallic=0.3, hammer=0.35),
        "floor": mat_floor(),
    }
    for w, c in BUMPER_COLOUR.items():
        m[f"rubber{w}"] = mat_rubber(f"rubber{w}", c)
    return m


# ---------------------------------------------------------------- studio
LIGHT_SCALE = float(os.environ.get("LIGHT", "0.25"))


def area(name, size, energy, loc, target, shape="RECTANGLE", size_y=None, colour=(1, 1, 1), spread=None):
    ld = bpy.data.lights.new(name, "AREA")
    if spread is not None:
        ld.spread = math.radians(spread)
    ld.shape = shape
    ld.size = size
    if size_y is not None:
        ld.size_y = size_y
    ld.energy = energy * LIGHT_SCALE
    ld.color = colour
    o = bpy.data.objects.new(name, ld)
    o.location = loc
    d = Vector(target) - Vector(loc)
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    link(o)
    return o


def reflector(name, loc, target, w, h, strength):
    """A softbox seen only in reflections: chrome needs bright shapes to mirror."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-w / 2, -h / 2, 0), (w / 2, -h / 2, 0), (w / 2, h / 2, 0), (-w / 2, h / 2, 0)], [], [(0, 1, 2, 3)])
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    o.location = loc
    d = Vector(target) - Vector(loc)
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    o.visible_camera = False
    o.visible_diffuse = False
    o.visible_shadow = False
    o.visible_transmission = False
    link(o)


def studio(mats, floor_z=0.0):
    # Seamless sweep: floor curving into a back wall.
    bm = bmesh.new()
    prof = [(-6.0, floor_z)]
    y0, rad = 2.2, 1.6
    for i in range(0, 13):
        a = -math.pi / 2 + (math.pi / 2) * i / 12
        prof.append((y0 + rad * math.cos(a), floor_z + rad + rad * math.sin(a)))
    prof.append((y0 + rad, floor_z + 6.0))
    rows = []
    for x in (-8, 8):
        rows.append([bm.verts.new((x, y, z)) for (y, z) in prof])
    for i in range(len(prof) - 1):
        bm.faces.new((rows[0][i], rows[1][i], rows[1][i + 1], rows[0][i + 1]))
    me = bpy.data.meshes.new("sweep"); bm.to_mesh(me); bm.free(); smooth(me)
    me.materials.append(mats["floor"])
    link(bpy.data.objects.new("sweep", me))
    # Key: big overhead-front softbox. Strip rims behind. Low front fill card.
    area("key", 1.6, 240, (-0.9, -1.9, 2.1), (-0.1, 0.0, 0.0), size_y=1.1, spread=70)
    area("strip", 4.2, 120, (0.0, -0.35, 2.4), (0.0, 0.0, 0.0), size_y=0.22, spread=90)
    area("rimL", 0.3, 150, (-1.9, 2.2, 1.7), (-0.7, 0, 0.1), size_y=1.6, colour=(0.93, 0.96, 1.0), spread=35)
    area("rimR", 0.3, 130, (1.9, 2.2, 1.7), (0.7, 0, 0.1), size_y=1.6, colour=(1.0, 0.96, 0.92), spread=35)
    reflector("cardFront", (-0.3, -2.8, 1.5), (-0.2, 0, 0.0), 3.6, 1.4, 1.6)
    reflector("cardTop", (0.0, 0.3, 2.6), (0.0, 0.0, 0.0), 5.0, 1.2, 1.2)
    area("fill", 3.0, 14, (0.6, -3.4, 0.6), (0, 0, 0.1), size_y=0.7, spread=40)


def camera(loc, target, lens=50, fstop=None, focus=None, shift=(0, 0)):
    cd = bpy.data.cameras.new("cam")
    cd.lens = lens
    cd.sensor_width = 36
    cd.shift_x, cd.shift_y = shift
    if fstop:
        cd.dof.use_dof = True
        cd.dof.aperture_fstop = fstop
        cd.dof.focus_distance = focus if focus else (Vector(target) - Vector(loc)).length
    o = bpy.data.objects.new("cam", cd)
    o.location = loc
    d = Vector(target) - Vector(loc)
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    link(o)
    bpy.context.scene.camera = o
    return o


# ---------------------------------------------------------------- shots
def shot(name):
    s = reset()
    mats = materials()
    if name in ("squat115_front", "squat115_hero", "press100_front"):
        stack = [35] if name.startswith("squat") else [25, 2.5]
        build_bar(mats)
        maxr = load_bar(stack, mats)
        studio(mats, floor_z=-maxr)
        if name.endswith("front"):
            camera((-0.45, -3.9, 0.30), (-0.03, 0.0, -0.03), lens=56)
        else:
            camera((-2.05, -2.55, 0.62), (-0.18, 0.0, -0.02), lens=45, fstop=5.6)
    elif name == "heavy_hero":
        build_bar(mats)
        maxr = load_bar([45, 45, 25, 10, 5, 2.5], mats)
        studio(mats, floor_z=-maxr)
        camera((-2.15, -2.45, 0.70), (-0.12, 0.0, -0.03), lens=42, fstop=5.6)
    elif name == "sleeve_close":
        build_bar(mats)
        maxr = load_bar([45, 25, 10, 5, 2.5], mats)
        studio(mats, floor_z=-maxr)
        camera((-1.85, -0.78, 0.30), (-0.86, 0.0, -0.01), lens=70, fstop=3.2)
    elif name == "exploded":
        build_bar(mats)
        maxr = load_bar([45, 25, 10, 5, 2.5], mats, explode=0.16, sides=(-1,))
        studio(mats, floor_z=-maxr - 0.0)
        camera((-1.55, -1.65, 0.36), (-1.02, 0.0, -0.03), lens=40, fstop=8.0)
    elif name == "plate_macro":
        body, T, R = bumper_plate(45, mats)
        body.location = (0, 0, 0)
        body.rotation_euler = (0, 0, math.radians(-90 + 28))
        studio(mats, floor_z=-R)
        camera((-0.20, -1.05, 0.10), (0.0, 0.0, 0.0), lens=58, fstop=4.0)
    elif name == "debug_plate":
        build_bar(mats)
        maxr = load_bar([35], mats)
        studio(mats, floor_z=-maxr)
        camera((-1.75, -0.95, 0.18), (-0.71, 0.0, 0.0), lens=50)
    elif name == "lineup":
        studio(mats, floor_z=-0.225)
        x = -0.75
        for w in [45, 35, 25, 10, 5, 2.5]:
            body, T, R = bumper_plate(w, mats)
            body.rotation_euler = (0, 0, math.radians(-62))
            body.location = (x, 0.0, -0.225 + R)
            x += 0.19 if R > 0.2 else 0.15
        camera((-0.05, -2.35, 0.28), (-0.12, 0.0, -0.02), lens=50, fstop=5.6)
    elif name == "iron_front":
        build_bar(mats)
        maxr = load_bar([45, 25, 10], mats, kind="iron")
        studio(mats, floor_z=-maxr)
        camera((-2.05, -2.55, 0.62), (-0.18, 0.0, -0.02), lens=45, fstop=5.6)
    else:
        raise SystemExit(f"unknown shot {name}")
    return s


if __name__ == "__main__":
    name, out = sys.argv[1], sys.argv[2]
    samples = int(sys.argv[3]) if len(sys.argv) > 3 else 96
    w = int(sys.argv[4]) if len(sys.argv) > 4 else 1600
    h = int(sys.argv[5]) if len(sys.argv) > 5 else 900
    s = shot(name)
    s.cycles.samples = samples
    s.render.resolution_x, s.render.resolution_y = w, h
    s.render.resolution_percentage = 100
    s.render.filepath = os.path.abspath(out)
    s.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("WROTE", out)
