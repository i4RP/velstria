# 担当: battle-renderer（スキル演出の素材）。コマ送り（爆炎・煙・光の棘・岩片・土煙の輪）と、1 枚の模様（地割れ・焦げ跡・
# 四芒星・斬撃の帯・渦の刃）、継ぎ目の無い流れる模様（溶岩の網・炎の筋）を Blender の Cycles で描く。
# 使い方: blender -b --factory-startup --python-exit-code 1 -P fx_render.py -- --out <frames_dir> [--only name ...]
#   [--samples N] [--scale 0.5]（確認用に小さく速く）
# 出力: <frames_dir>/<name>/0000.png …（16 bit PNG）。並べてシートにするのは pack.py（Blender の外の Python）。
# 描き方の約束:
#   mode "add"   黒地に発光だけで描く（不透明）。pack.py が明るさ → アルファ（白 + アルファ）か、色をそのまま（色付き）にする
#   mode "alpha" 透明な地に光を当てて描く（煙・岩）。アルファは Cycles の透過、色は陰影
# 乱数・ノイズの種は固定で、同じ版の Blender なら同じ画になる。

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fx_common as fc  # noqa: E402


# --- 場面 ------------------------------------------------------------------------------------------

def setup(res, samples, mode, ortho=2.5, view="side"):
    scene = fc.reset_scene()
    r = scene.render
    r.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.cycles.volume_bounces = 1
    scene.cycles.volume_step_rate = 1.0
    scene.cycles.volume_max_steps = 256
    r.resolution_x = res
    r.resolution_y = res
    r.resolution_percentage = 100
    r.film_transparent = mode == "alpha"
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    r.image_settings.color_depth = "16"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0, 0, 0, 1)
    bg.inputs["Strength"].default_value = 0.0 if mode == "add" else 0.35
    if mode == "alpha":
        bg.inputs["Color"].default_value = (0.55, 0.6, 0.7, 1)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cam_data)
    fc.link(cam)
    if view == "top":
        cam.location = (0, 0, 10)
        cam.rotation_euler = (0, 0, 0)
    else:
        cam.location = (0, -10, 0)
        cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    return scene


def sun(direction=(-0.45, -0.6, 0.65), energy=3.2):
    d = bpy.data.lights.new("sun", "SUN")
    d.energy = energy
    d.angle = math.radians(8)
    o = bpy.data.objects.new("sun", d)
    fc.link(o)
    v = Vector(direction).normalized()
    o.rotation_euler = (-v).to_track_quat("-Z", "Y").to_euler()
    return o


class G:
    """シェーダーのノードを短く組む。"""

    def __init__(self, mat):
        mat.use_nodes = True
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.values = {}

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def link(self, out, inp):
        self.nt.links.new(out, inp)

    def feed(self, sock, x):
        if isinstance(x, (int, float)):
            sock.default_value = x
        elif isinstance(x, tuple):
            sock.default_value = x
        else:
            self.link(x, sock)

    def value(self, name, v=0.0):
        n = self.node("ShaderNodeValue")
        n.outputs[0].default_value = v
        self.values[name] = n
        return n.outputs[0]

    def math(self, op, a, b=0.0, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.feed(n.inputs[0], a)
        self.feed(n.inputs[1], b)
        return n.outputs[0]

    def vmath(self, op, a, b=None, scale=None):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self.feed(n.inputs[0], a)
        if b is not None:
            self.feed(n.inputs[1], b)
        if scale is not None:
            self.feed(n.inputs["Scale"], scale)
        return n.outputs["Value"] if op in ("LENGTH", "DOT_PRODUCT", "DISTANCE") else n.outputs["Vector"]

    def coords(self, kind="Object"):
        return self.node("ShaderNodeTexCoord").outputs[kind]

    def noise(self, vec, w, scale=2.0, detail=6.0, rough=0.55, distortion=0.0):
        n = self.node("ShaderNodeTexNoise", noise_dimensions="4D")
        self.feed(n.inputs["Vector"], vec)
        self.feed(n.inputs["W"], w)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = distortion
        return n.outputs["Fac"]

    def voronoi_edge(self, vec, w, scale=4.0):
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature="DISTANCE_TO_EDGE")
        self.feed(n.inputs["Vector"], vec)
        self.feed(n.inputs["W"], w)
        n.inputs["Scale"].default_value = scale
        return n.outputs["Distance"]

    def smooth(self, x, lo, hi):
        n = self.node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP", clamp=True)
        self.feed(n.inputs["Value"], x)
        self.feed(n.inputs["From Min"], lo)
        self.feed(n.inputs["From Max"], hi)
        return n.outputs["Result"]

    def ramp(self, x, stops):
        n = self.node("ShaderNodeValToRGB")
        el = n.color_ramp.elements
        el[0].position, el[0].color = stops[0][0], stops[0][1]
        el[1].position, el[1].color = stops[-1][0], stops[-1][1]
        for pos, col in stops[1:-1]:
            e = el.new(pos)
            e.color = col
        self.feed(n.inputs["Fac"], x)
        return n.outputs["Color"]

    def emission(self, color, strength):
        n = self.node("ShaderNodeEmission")
        self.feed(n.inputs["Color"], color)
        self.feed(n.inputs["Strength"], strength)
        return n.outputs[0]

    def see_through(self, shader):
        """発光 + 透過（下の物を隠さない光の板）。"""
        t = self.node("ShaderNodeBsdfTransparent")
        a = self.node("ShaderNodeAddShader")
        self.link(shader, a.inputs[0])
        self.link(t.outputs[0], a.inputs[1])
        return a.outputs[0]

    def output(self, surface=None, volume=None):
        o = self.node("ShaderNodeOutputMaterial")
        if surface is not None:
            self.link(surface, o.inputs["Surface"])
        if volume is not None:
            self.link(volume, o.inputs["Volume"])


def domain(size=2.4):
    bpy.ops.mesh.primitive_cube_add(size=size)
    return bpy.context.active_object


def plane(size=2.0, z=0.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
    return bpy.context.active_object


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def ease_out(t, p=2.0):
    return 1 - (1 - min(1.0, max(0.0, t))) ** p


# --- コマ送り --------------------------------------------------------------------------------------

def fireball(out, frames, res, samples, seed=0.0):
    """爆炎（色付き・加算）: 白い芯 → 黄 → 橙 → 暗い朱へ冷えながら膨らみ、炎の舌が上へ伸びて千切れる。"""
    scene = setup(res, samples, "add", ortho=2.7)
    mat = bpy.data.materials.new("fire")
    g = G(mat)
    p = g.coords("Object")
    rise = g.value("rise")
    radius = g.value("radius", 0.4)
    heat = g.value("heat", 1.0)
    w = g.value("w")
    lift = g.node("ShaderNodeCombineXYZ")
    g.link(rise, lift.inputs["Z"])
    q = g.vmath("SUBTRACT", p, lift.outputs[0])
    r = g.math("DIVIDE", g.vmath("LENGTH", q), radius)
    n1 = g.noise(q, w, scale=1.9, detail=7, rough=0.6, distortion=0.35)
    n2 = g.noise(g.vmath("SCALE", q, scale=2.7), g.math("ADD", w, 3.7), scale=1.6, detail=4, rough=0.5)
    turb = g.math("ADD", g.math("MULTIPLY", g.math("SUBTRACT", n1, 0.5), 1.7),
                  g.math("MULTIPLY", g.math("SUBTRACT", n2, 0.5), 0.8))
    # 上ほど舌が伸びる（上の半分では半径を甘くする）
    sep = g.node("ShaderNodeSeparateXYZ")
    g.link(q, sep.inputs[0])
    up = g.math("MULTIPLY", g.math("MAXIMUM", sep.outputs["Z"], 0.0), 0.35)
    field = g.math("ADD", g.math("ADD", g.math("SUBTRACT", 1.0, r), turb), up)
    hot = g.math("MULTIPLY", field, heat)
    col = g.ramp(hot, [(0.0, (0, 0, 0, 1)), (0.1, (0.22, 0.03, 0.005, 1)), (0.3, (0.95, 0.28, 0.03, 1)),
                       (0.52, (1.0, 0.68, 0.12, 1)), (0.75, (1.0, 0.93, 0.55, 1)), (1.0, (1, 1, 0.94, 1))])
    dens = g.smooth(field, 0.0, 0.22)
    vol = g.node("ShaderNodeVolumePrincipled")
    vol.inputs["Density"].default_value = 0.0
    g.link(col, vol.inputs["Emission Color"])
    g.link(g.math("MULTIPLY", dens, 2.6), vol.inputs["Emission Strength"])
    g.output(volume=vol.outputs[0])
    d = domain(2.6)
    assign(d, mat)
    for f in range(frames):
        t = f / (frames - 1)
        g.values["radius"].outputs[0].default_value = 0.24 + 0.5 * ease_out(t ** 0.7, 2.2)
        g.values["rise"].outputs[0].default_value = 0.2 * t ** 1.3
        g.values["heat"].outputs[0].default_value = 1.35 * (1 - t) ** 1.25 + 0.05
        g.values["w"].outputs[0].default_value = seed + t * 1.6
        render(scene, os.path.join(out, "%04d.png" % f))


def smoke(out, frames, res, samples, seed=0.0):
    """煙の一吹き（陰影付き・アルファ）: こぶ状に膨らみ、上へ少し昇りながら縁から薄れる。"""
    scene = setup(res, samples, "alpha", ortho=2.5)
    sun()
    mat = bpy.data.materials.new("smoke")
    g = G(mat)
    p = g.coords("Object")
    radius = g.value("radius", 0.4)
    dens_k = g.value("dens", 1.0)
    rise = g.value("rise")
    w = g.value("w")
    lift = g.node("ShaderNodeCombineXYZ")
    g.link(rise, lift.inputs["Z"])
    q = g.vmath("SUBTRACT", p, lift.outputs[0])
    r = g.math("DIVIDE", g.vmath("LENGTH", q), radius)
    n1 = g.noise(q, w, scale=1.6, detail=6, rough=0.58, distortion=0.2)
    field = g.math("ADD", g.math("SUBTRACT", 1.0, r), g.math("MULTIPLY", g.math("SUBTRACT", n1, 0.5), 1.3))
    dens = g.math("MULTIPLY", g.smooth(field, 0.0, 0.35), dens_k)
    vol = g.node("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (0.92, 0.9, 0.86, 1)
    vol.inputs["Anisotropy"].default_value = 0.25
    g.link(g.math("MULTIPLY", dens, 9.0), vol.inputs["Density"])
    g.output(volume=vol.outputs[0])
    d = domain(2.4)
    assign(d, mat)
    for f in range(frames):
        t = f / (frames - 1)
        g.values["radius"].outputs[0].default_value = 0.35 + 0.65 * ease_out(t, 2.0)
        g.values["dens"].outputs[0].default_value = (1 - t) ** 1.6
        g.values["rise"].outputs[0].default_value = 0.18 * t
        g.values["w"].outputs[0].default_value = seed + t * 0.9
        render(scene, os.path.join(out, "%04d.png" % f))


def jagged_strip(points, widths, z=0.0):
    """折れ線と各点の幅 → 帯の頂点・面（xy 平面）。"""
    verts, faces = [], []
    n = len(points)
    for i, (x, y) in enumerate(points):
        if i == 0:
            dx, dy = points[1][0] - x, points[1][1] - y
        elif i == n - 1:
            dx, dy = x - points[i - 1][0], y - points[i - 1][1]
        else:
            dx, dy = points[i + 1][0] - points[i - 1][0], points[i + 1][1] - points[i - 1][1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        w = widths[i] * 0.5
        verts.append((x + nx * w, y + ny * w, z))
        verts.append((x - nx * w, y - ny * w, z))
    for i in range(n - 1):
        a = 2 * i
        faces.append((a, a + 1, a + 3, a + 2))
    return verts, faces


def emission_object(name, parts, strength=1.0, color=(1, 1, 1, 1)):
    verts, faces = [], []
    for pv, pf in parts:
        base = len(verts)
        verts += pv
        faces += [tuple(base + k for k in f) for f in pf]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    obj = bpy.data.objects.new(name, me)
    fc.link(obj)
    mat = bpy.data.materials.new(name)
    g = G(mat)
    g.output(surface=g.emission(color, strength))
    assign(obj, mat)
    return obj, mat


def spikes(out, frames, res, samples):
    """光の棘（白・加算）: 中心から放射状のぎざぎざの炎の舌が一瞬で伸び、細りながら外へ流れて消える。白い芯は先に消える。"""
    scene = setup(res, samples, "add", ortho=2.2, view="top")
    rng = random.Random(7)
    spikes_def = []
    n = 18
    for k in range(n):
        a = 2 * math.pi * k / n + rng.uniform(-0.16, 0.16)
        # 長い棘と、短く太い炎の舌を交互に
        if k % 2 == 0:
            spikes_def.append((a, rng.uniform(0.7, 1.0), rng.uniform(0.13, 0.2), rng.random() * 100))
        else:
            spikes_def.append((a, rng.uniform(0.35, 0.55), rng.uniform(0.18, 0.26), rng.random() * 100))
    core_mat = bpy.data.materials.new("core")
    g = G(core_mat)
    uv = g.coords("Generated")
    # 平らな板の Generated は z が 0.5 に固定される（厚みの無い軸）。中心は (0.5, 0.5, 0.5)
    c = g.vmath("SUBTRACT", uv, (0.5, 0.5, 0.5))
    r = g.math("MULTIPLY", g.vmath("LENGTH", c), 2.0)
    glow = g.math("POWER", g.math("SUBTRACT", 1.0, r, clamp=True), 2.2)
    cs = g.value("core", 1.0)
    # 芯の板は透過させる（不透明だと下の棘の根元を黒く隠す）
    g.output(surface=g.see_through(g.emission((1, 1, 1, 1), g.math("MULTIPLY", glow, cs))))
    core = plane(1.0, z=0.01)
    assign(core, core_mat)
    objs = []
    for f in range(frames):
        t = f / (frames - 1)
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
        objs = []
        grow = 0.35 + 0.65 * ease_out(min(1.0, t / 0.2), 2.5)
        fade = (1 - max(0.0, (t - 0.12) / 0.88)) ** 1.4
        drift = 0.12 * ease_out(t, 2.0)
        parts = []
        for (a, L, W, ph) in spikes_def:
            rr = random.Random(int(ph * 1000))
            pts, ws = [], []
            m = 9
            for i in range(m + 1):
                s = i / m
                d = drift + 0.04 + (L * 0.8 * grow) * s
                jag = (rr.uniform(-1, 1) * 0.06 * s) if 0 < i < m else 0.0
                aa = a + jag / max(0.2, d)
                pts.append((math.cos(aa) * d, math.sin(aa) * d))
                ws.append(W * (1 - s) ** 0.9 * (0.6 + 0.4 * fade) * (1 - 0.6 * t))
            parts.append(jagged_strip(pts, ws))
        o, _ = emission_object("spikes%d" % f, parts, strength=1.4 * fade)
        objs.append(o)
        g.values["core"].outputs[0].default_value = 1.6 * (1 - min(1.0, t / 0.4)) ** 2
        render(scene, os.path.join(out, "%04d.png" % f))


def rock(out, frames, res, samples):
    """岩片（陰影付き・アルファ）: 角張った白っぽい岩が 1 回転する（繰り返す）。"""
    scene = setup(res, samples, "alpha", ortho=2.4)
    sun((-0.4, -0.7, 0.6), 4.0)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.7)
    o = bpy.context.active_object
    tex = bpy.data.textures.new("rock", "CLOUDS")
    tex.noise_scale = 0.6
    disp = o.modifiers.new("d", "DISPLACE")
    disp.texture = tex
    disp.strength = 0.45
    dec = o.modifiers.new("dec", "DECIMATE")
    dec.ratio = 0.35
    o.scale = (1.0, 0.75, 0.55)
    mat = bpy.data.materials.new("rock")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.82, 0.8, 0.76, 1)
    bsdf.inputs["Roughness"].default_value = 0.85
    assign(o, mat)
    for poly in o.data.polygons:
        poly.use_smooth = False
    axis = Vector((0.4, 0.3, 1.0)).normalized()
    for f in range(frames):
        ang = 2 * math.pi * f / frames
        o.rotation_mode = "AXIS_ANGLE"
        o.rotation_axis_angle = (ang, axis.x, axis.y, axis.z)
        render(scene, os.path.join(out, "%04d.png" % f))


def dust_ring(out, frames, res, samples):
    """地面を走る土煙の輪（陰影付き・アルファ、上から見る）: 輪が外へ広がり、内側から薄れる。"""
    scene = setup(res, samples, "alpha", ortho=2.2, view="top")
    sun((-0.3, -0.5, 0.8), 3.5)
    mat = bpy.data.materials.new("dust")
    g = G(mat)
    p = g.coords("Object")
    radius = g.value("radius", 0.3)
    thick = g.value("thick", 0.2)
    dens_k = g.value("dens", 1.0)
    w = g.value("w")
    sep = g.node("ShaderNodeSeparateXYZ")
    g.link(p, sep.inputs[0])
    flat = g.node("ShaderNodeCombineXYZ")
    g.link(sep.outputs["X"], flat.inputs["X"])
    g.link(sep.outputs["Y"], flat.inputs["Y"])
    wob = g.noise(g.vmath("SCALE", p, scale=1.3), g.math("ADD", w, 7.0), scale=1.2, detail=3, rough=0.5)
    rr = g.math("ADD", g.vmath("LENGTH", flat.outputs[0]), g.math("MULTIPLY", g.math("SUBTRACT", wob, 0.5), 0.35))
    ring = g.math("SUBTRACT", 1.0, g.math("DIVIDE", g.math("ABSOLUTE", g.math("SUBTRACT", rr, radius)), thick))
    height = g.math("SUBTRACT", 1.0, g.math("DIVIDE", g.math("ABSOLUTE", sep.outputs["Z"]), 0.35))
    n1 = g.noise(p, w, scale=2.2, detail=7, rough=0.65, distortion=0.6)
    n2 = g.noise(g.vmath("SCALE", p, scale=3.1), g.math("ADD", w, 2.0), scale=2.0, detail=4, rough=0.5)
    clumps = g.math("ADD", g.math("MULTIPLY", g.math("SUBTRACT", n1, 0.5), 2.2), g.math("MULTIPLY", g.math("SUBTRACT", n2, 0.5), 1.1))
    field = g.math("ADD", g.math("MINIMUM", ring, height), clumps)
    dens = g.math("MULTIPLY", g.smooth(field, 0.0, 0.4), dens_k)
    vol = g.node("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (0.9, 0.86, 0.8, 1)
    g.link(g.math("MULTIPLY", dens, 10.0), vol.inputs["Density"])
    g.output(volume=vol.outputs[0])
    d = domain(2.4)
    d.scale = (1, 1, 0.3)
    assign(d, mat)
    for f in range(frames):
        t = f / (frames - 1)
        g.values["radius"].outputs[0].default_value = 0.22 + 0.55 * ease_out(t, 2.2)
        g.values["thick"].outputs[0].default_value = 0.1 + 0.12 * t
        g.values["dens"].outputs[0].default_value = (1 - t) ** 1.3
        g.values["w"].outputs[0].default_value = t * 0.8
        render(scene, os.path.join(out, "%04d.png" % f))


# --- 1 枚の模様（上から見た地面の模様・帯の画像） -------------------------------------------------------

def crack_path(rng, start, angle, length, steps, jag):
    pts = [start]
    a = angle
    x, y = start
    for _ in range(steps):
        a += rng.uniform(-jag, jag)
        seg = length / steps * rng.uniform(0.7, 1.3)
        x += math.cos(a) * seg
        y += math.sin(a) * seg
        pts.append((x, y))
    return pts


def taper(n, w0, w1=0.0, p=1.0):
    return [w0 + (w1 - w0) * (i / (n - 1)) ** p for i in range(n)]


def crack_s(out, res, samples):
    """S 字の太い地割れ（白・アルファ）: MLBB の聖槌波の爆発の下のぎざぎざのひび。主の S 字 + 枝 + 細いひび。"""
    scene = setup(res, samples, "add", ortho=2.0, view="top")
    rng = random.Random(11)
    parts = []
    # 主の S 字（横に寝た S）: 右上の鉤 → 中央 → 左下の鉤を、2 つの円弧（半径 r、中心 (±r, 0)）で描く。ぎざぎざは小さなずれ
    pts = []
    r = 0.3
    for i in range(29):
        s = i / 28
        if s < 0.5:
            k = s / 0.5
            a = math.radians(-60 + 240 * k)  # 右の円: 下 → 右 → 上 → 左（中央）
            x, y = r + math.cos(a) * r, math.sin(a) * r
        else:
            k = (s - 0.5) / 0.5
            a = math.radians(0 + 240 * k)  # 左の円: 右（中央）→ 下 → 左 → 上
            x, y = -r + math.cos(a) * r, -math.sin(a) * r
        pts.append((x * 1.25 + rng.uniform(-0.03, 0.03), y * 1.05 + rng.uniform(-0.035, 0.035)))
    # 外接の中心を画像の中心へ
    cx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2
    cy = (min(p[1] for p in pts) + max(p[1] for p in pts)) / 2
    pts = [(x - cx, y - cy) for (x, y) in pts]
    widths = [0.19 * (0.3 + 0.7 * math.sin(math.pi * i / 28) ** 0.45) * rng.uniform(0.7, 1.25) for i in range(29)]
    parts.append(jagged_strip(pts, widths))
    # 枝
    for k in range(11):
        i = rng.randint(2, 26)
        x, y = pts[i]
        a = rng.uniform(0, 2 * math.pi)
        br = crack_path(rng, (x, y), a, rng.uniform(0.18, 0.42), 6, 0.6)
        parts.append(jagged_strip(br, taper(len(br), widths[i] * 0.45, 0.0, 0.8)))
        # 枝の先の細いひび
        if rng.random() < 0.6:
            j = rng.randint(2, len(br) - 1)
            tw = crack_path(rng, br[j], a + rng.uniform(-1.2, 1.2), rng.uniform(0.1, 0.22), 4, 0.7)
            parts.append(jagged_strip(tw, taper(len(tw), 0.03, 0.0)))
    emission_object("crack", parts, strength=1.0)
    render(scene, os.path.join(out, "0000.png"))


def crack_radial(out, res, samples):
    """放射状の地割れ（白・アルファ）: 中心から 11 本の枝分かれするひびと、途切れ途切れの輪のひび。"""
    scene = setup(res, samples, "add", ortho=2.0, view="top")
    rng = random.Random(23)
    parts = []
    n = 11
    for k in range(n):
        a = 2 * math.pi * k / n + rng.uniform(-0.2, 0.2)
        main = crack_path(rng, (math.cos(a) * 0.08, math.sin(a) * 0.08), a, rng.uniform(0.7, 0.92), 9, 0.32)
        parts.append(jagged_strip(main, taper(len(main), 0.1, 0.008, 0.8)))
        for _ in range(2):
            i = rng.randint(2, len(main) - 2)
            br = crack_path(rng, main[i], a + rng.choice([-1, 1]) * rng.uniform(0.5, 1.1), rng.uniform(0.12, 0.3), 5, 0.5)
            parts.append(jagged_strip(br, taper(len(br), 0.042, 0.0)))
    # 途切れた輪
    for k in range(7):
        a0 = 2 * math.pi * k / 7 + rng.uniform(0, 0.4)
        pts = []
        for i in range(8):
            a = a0 + 0.55 * i / 7
            r = 0.55 + rng.uniform(-0.03, 0.03)
            pts.append((math.cos(a) * r, math.sin(a) * r))
        parts.append(jagged_strip(pts, [0.035 * math.sin(math.pi * i / 7) + 0.006 for i in range(8)]))
    emission_object("crackR", parts, strength=1.0)
    render(scene, os.path.join(out, "0000.png"))


def scorch(out, res, samples):
    """焦げ跡（白・アルファの柔らかい塊）: ノイズで縁が崩れた円。暗い色で敷く。"""
    scene = setup(res, samples, "add", ortho=2.0, view="top")
    mat = bpy.data.materials.new("scorch")
    g = G(mat)
    uv = g.coords("Generated")
    # 平らな板の Generated は z が 0.5 に固定される（厚みの無い軸）。中心は (0.5, 0.5, 0.5)
    c = g.vmath("SUBTRACT", uv, (0.5, 0.5, 0.5))
    r = g.math("MULTIPLY", g.vmath("LENGTH", c), 2.0)
    n1 = g.noise(g.vmath("SCALE", c, scale=3.0), 1.7, scale=1.4, detail=7, rough=0.62)
    field = g.math("ADD", g.math("SUBTRACT", 0.92, r), g.math("MULTIPLY", g.math("SUBTRACT", n1, 0.5), 0.9))
    a = g.math("MULTIPLY", g.smooth(field, 0.0, 0.45), g.math("ADD", 0.55, g.math("MULTIPLY", n1, 0.6)))
    g.output(surface=g.emission((1, 1, 1, 1), a))
    o = plane(2.0)
    assign(o, mat)
    render(scene, os.path.join(out, "0000.png"))


def star4(out, res, samples):
    """四芒星（白・アルファ）: 細く尖る 4 本の腕と、間の短い 4 本、柔らかい芯。"""
    scene = setup(res, samples, "add", ortho=2.0, view="top")
    parts = []
    for k in range(8):
        a = k * math.pi / 4
        L = 0.95 if k % 2 == 0 else 0.42
        W = 0.16 if k % 2 == 0 else 0.07
        d = (math.cos(a), math.sin(a))
        s = (-d[1], d[0])
        tri = [(s[0] * W, s[1] * W, 0.0), (d[0] * L, d[1] * L, 0.0), (-s[0] * W, -s[1] * W, 0.0)]
        parts.append((tri, [(0, 1, 2)]))
    emission_object("star", parts, strength=1.0)
    render(scene, os.path.join(out, "0000.png"))


def swoosh(out, res, samples):
    """斬撃の帯の画像（白・アルファ）: u = 弧に沿う（尾 0 → 頭 1）、v = 内縁 0 → 外縁 1。頭寄りで最も明るく、外縁は白い刃線、
    尾へ筋を引いて薄れる。三日月のメッシュ（crescent）と帯（ribbon）に貼る。"""
    scene = setup(res, samples, "add", ortho=2.0, view="top")
    mat = bpy.data.materials.new("swoosh")
    g = G(mat)
    uv = g.coords("Generated")
    sep = g.node("ShaderNodeSeparateXYZ")
    g.link(uv, sep.inputs[0])
    u, v = sep.outputs["X"], sep.outputs["Y"]
    along = g.math("MULTIPLY", g.smooth(u, 0.0, 0.78), g.math("SUBTRACT", 1.0, g.smooth(u, 0.9, 1.0)))
    edge = g.math("POWER", v, 2.4)
    lip = g.smooth(v, 0.86, 0.97)
    streak_v = g.node("ShaderNodeCombineXYZ")
    g.link(g.math("MULTIPLY", u, 0.6), streak_v.inputs["X"])
    g.link(g.math("MULTIPLY", v, 9.0), streak_v.inputs["Y"])
    streaks = g.noise(streak_v.outputs[0], 2.3, scale=2.2, detail=3, rough=0.5)
    body = g.math("MULTIPLY", g.math("ADD", edge, g.math("MULTIPLY", g.math("SUBTRACT", streaks, 0.35), 0.8)), along)
    a = g.math("ADD", g.math("MAXIMUM", body, 0.0), g.math("MULTIPLY", lip, g.math("MULTIPLY", along, 0.9)))
    g.output(surface=g.emission((1, 1, 1, 1), g.math("MINIMUM", a, 1.0)))
    o = plane(2.0)
    assign(o, mat)
    render(scene, os.path.join(out, "0000.png"))


def blade(out, res, samples):
    """渦の刃の画像（白・アルファ）: u = 刃に沿う（尾 0 → 頭 1）、v = 幅。頭が明るく丸く、尾へ細い筋で消える。"""
    scene = setup(res, samples, "add", ortho=2.0, view="top")
    mat = bpy.data.materials.new("blade")
    g = G(mat)
    uv = g.coords("Generated")
    sep = g.node("ShaderNodeSeparateXYZ")
    g.link(uv, sep.inputs[0])
    u, v = sep.outputs["X"], sep.outputs["Y"]
    across = g.math("SUBTRACT", 1.0, g.math("POWER", g.math("ABSOLUTE", g.math("MULTIPLY", g.math("SUBTRACT", v, 0.5), 2.0)), 1.6))
    along = g.math("MULTIPLY", g.math("POWER", u, 1.3), g.math("SUBTRACT", 1.0, g.smooth(u, 0.93, 1.0)))
    a = g.math("MULTIPLY", g.math("MAXIMUM", across, 0.0), along)
    g.output(surface=g.emission((1, 1, 1, 1), g.math("MINIMUM", g.math("MULTIPLY", a, 1.3), 1.0)))
    o = plane(2.0)
    assign(o, mat)
    render(scene, os.path.join(out, "0000.png"))


# --- 継ぎ目の無い流れる模様（UV のトーラスで 4D のノイズを引く） ---------------------------------------------

def torus_coords(g, ku=1.0, kv=1.0):
    """UV (u, v) → (cos 2πu·ku, sin 2πu·ku, cos 2πv·kv) と W = sin 2πv·kv（u・v の両方で継ぎ目が出ない）。"""
    uv = g.coords("Generated")
    sep = g.node("ShaderNodeSeparateXYZ")
    g.link(uv, sep.inputs[0])
    au = g.math("MULTIPLY", sep.outputs["X"], 2 * math.pi)
    av = g.math("MULTIPLY", sep.outputs["Y"], 2 * math.pi)
    vec = g.node("ShaderNodeCombineXYZ")
    g.link(g.math("MULTIPLY", g.math("COSINE", au), ku), vec.inputs["X"])
    g.link(g.math("MULTIPLY", g.math("SINE", au), ku), vec.inputs["Y"])
    g.link(g.math("MULTIPLY", g.math("COSINE", av), kv), vec.inputs["Z"])
    w = g.math("MULTIPLY", g.math("SINE", av), kv)
    return vec.outputs[0], w


def lava(out, res, samples):
    """溶岩の網（白黒・継ぎ目なし）: 細胞の縁が明るい線、内側はゆらぐ暗さ。光るひび・焦げ跡の流れる模様。"""
    scene = setup(res, samples, "add", ortho=2.0, view="top")
    mat = bpy.data.materials.new("lava")
    g = G(mat)
    vec, w = torus_coords(g, 0.9, 0.9)
    e = g.voronoi_edge(vec, w, scale=2.4)
    lines = g.math("SUBTRACT", 1.0, g.smooth(e, 0.0, 0.06))
    n1 = g.noise(vec, g.math("ADD", w, 4.0), scale=2.0, detail=5, rough=0.6)
    a = g.math("ADD", g.math("MULTIPLY", lines, 0.85), g.math("MULTIPLY", g.math("SUBTRACT", n1, 0.3), 0.4))
    g.output(surface=g.emission((1, 1, 1, 1), g.math("MINIMUM", g.math("MAXIMUM", a, 0.0), 1.0)))
    o = plane(2.0)
    assign(o, mat)
    render(scene, os.path.join(out, "0000.png"))


def flame_noise(out, res, samples):
    """炎の筋（白黒・継ぎ目なし）: 縦に伸びた揺らぐノイズ。炎の帯・光の柱を上へ流す模様。"""
    scene = setup(res, samples, "add", ortho=2.0, view="top")
    mat = bpy.data.materials.new("flame")
    g = G(mat)
    vec, w = torus_coords(g, 1.4, 0.45)
    n1 = g.noise(vec, w, scale=1.6, detail=8, rough=0.62, distortion=0.4)
    a = g.smooth(n1, 0.32, 0.78)
    g.output(surface=g.emission((1, 1, 1, 1), a))
    o = plane(2.0)
    assign(o, mat)
    render(scene, os.path.join(out, "0000.png"))


# name → (関数, 種類, コマ数, 1 コマの画素)。種類: "sheet" = コマ送り、"image" = 1 枚、"tile" = 継ぎ目なし
JOBS = {
    "fireball": (fireball, "sheet", 25, 256),
    "smoke_hd": (smoke, "sheet", 25, 256),
    "spikes": (spikes, "sheet", 16, 256),
    "rock_tumble": (rock, "sheet", 16, 128),
    "dust_ring": (dust_ring, "sheet", 16, 256),
    "crack_s": (crack_s, "image", 1, 1024),
    "crack_radial": (crack_radial, "image", 1, 1024),
    "scorch": (scorch, "image", 1, 512),
    "star4": (star4, "image", 1, 512),
    "swoosh": (swoosh, "image", 1, 512),
    "blade": (blade, "image", 1, 256),
    "lava": (lava, "tile", 1, 512),
    "flame_noise": (flame_noise, "tile", 1, 512),
}


def main():
    ap = argparse.ArgumentParser(prog="fx_render.py")
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--samples", type=int, default=64)
    ap.add_argument("--scale", type=float, default=1.0)
    a = ap.parse_args(fc.script_args())
    for name in (a.only or list(JOBS)):
        fn, kind, frames, res = JOBS[name]
        res = max(32, int(res * a.scale))
        d = os.path.join(a.out, name)
        os.makedirs(d, exist_ok=True)
        for old in os.listdir(d):
            if old.endswith(".png"):
                os.remove(os.path.join(d, old))
        if kind == "sheet":
            fn(d, frames, res, a.samples)
        else:
            fn(d, res, a.samples)
        print("rendered", name, kind, frames, res)


main()
