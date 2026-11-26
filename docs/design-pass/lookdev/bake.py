"""Bake the approved look-dev scene into app assets.

python3 bake.py env  <out.png>   gym environment (equirect) seen from the bar centre
python3 bake.py oak  <out.png>   oak centre albedo, top-down, no logo (logo is composited at runtime)
python3 bake.py mat  <out.png>   one stall-mat strip albedo, top-down

Axes match gym.py (metres, bar along X, Z up, lifter/camera side is -Y).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gym as G  # noqa: E402
import studio as S  # noqa: E402
import bpy  # noqa: E402


def to_emission(mat):
    """Show a material's base colour unlit, so a render is its albedo."""
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    out = nt.nodes["Material Output"]
    src = bsdf.inputs["Base Color"].links[0].from_socket if bsdf.inputs["Base Color"].links else None
    em = nt.nodes.new("ShaderNodeEmission")
    if src is not None:
        nt.links.new(src, em.inputs["Color"])
    else:
        em.inputs["Color"].default_value = bsdf.inputs["Base Color"].default_value
    nt.links.new(em.outputs[0], out.inputs["Surface"])


def ortho_top(cx, cy, w, h, res_long=2048):
    cd = bpy.data.cameras.new("ortho")
    cd.type = "ORTHO"
    cd.ortho_scale = max(w, h)
    o = bpy.data.objects.new("ortho", cd)
    o.location = (cx, cy, 3.0)
    o.rotation_euler = (0, 0, 0)          # looking down -Z, image up = +Y
    S.link(o)
    s = bpy.context.scene
    s.camera = o
    if h >= w:
        s.render.resolution_y = res_long
        s.render.resolution_x = int(round(res_long * w / h))
    else:
        s.render.resolution_x = res_long
        s.render.resolution_y = int(round(res_long * h / w))


def bake(kind, out):
    s = S.reset()
    s.view_settings.view_transform = "Standard"
    s.view_settings.exposure = float(os.environ.get("BAKE_EXPOSURE", "0"))
    s.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    s.cycles.use_denoising = False
    if kind in ("oak", "mat"):
        G.LOGO = None
        mats = G.materials()
        top = -0.225
        G.platform(top, mats)
        for m in bpy.data.materials:
            if m.name in ("oak", "stallmat"):
                to_emission(m)
        s.cycles.samples = 16
        if kind == "oak":
            ortho_top(0.0, 0.0, G.CENTRE_W, G.PLAT)
        else:
            x0 = G.CENTRE_W / 2
            ortho_top(x0 + (G.PLAT / 2 - x0) / 2, 0.0, G.PLAT / 2 - x0, G.PLAT, res_long=2048)
    elif kind == "env":
        G.LOGO = None
        mats = G.materials()
        G.platform(-0.225, mats)
        G.gym_lights()
        # The ceiling panels must be visible to camera rays: emissive slabs.
        for x in (-1.6, 0.0, 1.6):
            for y in (-1.2, 0.6, 2.4):
                me = bpy.data.meshes.new("pane")
                me.from_pydata([(-0.6, -0.15, 0), (0.6, -0.15, 0), (0.6, 0.15, 0), (-0.6, 0.15, 0)], [], [(0, 1, 2, 3)])
                m = bpy.data.materials.new("panelem"); m.use_nodes = True
                nt = m.node_tree
                for n in list(nt.nodes):
                    if n.type != "OUTPUT_MATERIAL":
                        nt.nodes.remove(n)
                em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = 18.0
                em.inputs["Color"].default_value = (1.0, 0.97, 0.92, 1)
                nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
                me.materials.append(m)
                o = bpy.data.objects.new("pane", me)
                o.location = (x, y, 3.30)
                o.rotation_euler = (math.pi, 0, 0)
                S.link(o)
        cd = bpy.data.cameras.new("pano")
        cd.type = "PANO"
        try:
            cd.panorama_type = "EQUIRECTANGULAR"
        except Exception:
            cd.cycles.panorama_type = "EQUIRECTANGULAR"
        o = bpy.data.objects.new("pano", cd)
        o.location = (0.0, 0.0, 0.0)
        # Looking toward +Y (the back wall), up = +Z.
        o.rotation_euler = (math.pi / 2, 0, 0)
        S.link(o)
        s.camera = o
        s.cycles.samples = 96
        s.cycles.use_denoising = True
        s.render.resolution_x, s.render.resolution_y = 2048, 1024
    else:
        raise SystemExit(kind)
    s.render.resolution_percentage = 100
    s.render.filepath = os.path.abspath(out)
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_depth = "8"
    bpy.ops.render.render(write_still=True)
    print("WROTE", out)


if __name__ == "__main__":
    bake(sys.argv[1], sys.argv[2])
