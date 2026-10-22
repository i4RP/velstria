"""H027 contact sheets / Blender comparison footage of the finished clips (not a game or FPS capture).

Run from VELSTRIA: Blender -b -P tools/blender/preview_h027_motion.py -- [--only h027_thrust,...] [--view 34|top|side|front]
  [--video]
The spear is a proxy with the game's dimensions (HeroGear .dragonSpear × 1.08) placed with the runtime rule
weapon.position = hand + q.handR·(0, -grip, 0), orientation = q.handR · weaponGrip (HeroMotionSets "H027").
"""
import argparse
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_h025_motion as h25
import author_h027_motion as author
import clip_math as cm
import preview_clip as preview
import preview_h025_motion as p25

V = Vector
OUT = Path('build/h027-motion')
FRAMES = []


def make_spear():
    parts = []
    def mat(name, color):
        m = bpy.data.materials.new(name)
        m.diffuse_color = color
        return m
    dark, gold, teal = mat('Shaft', (0.12, 0.08, 0.06, 1)), mat('Gold', (0.85, 0.62, 0.18, 1)), mat('Teal', (0.1, 0.55, 0.5, 1))
    # built in weapon space under one empty
    root = bpy.data.objects.new('Spear', None)
    bpy.context.collection.objects.link(root)
    def cyl(y0, y1, r, m, verts=10):
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=abs(y1 - y0))
        o = bpy.context.object
        o.data.materials.append(m)
        o.matrix_world = Matrix.Translation(V((0, (y0 + y1) / 2, 0))) @ Matrix.Rotation(-math.pi / 2, 4, 'X')
        o.parent = root
        return o
    s = 1.08
    cyl(-0.84 * s, 1.1 * s, 0.03 * s, dark)
    cyl(-0.84 * s, -0.56 * s, 0.044 * s, gold)
    cyl(1.04 * s, 1.42 * s, 0.09 * s, teal)
    # blade: flat (face normal +Z), widest near the base
    bm = bpy.data.meshes.new('Blade')
    pts = [(-0.085, 0.12), (0.085, 0.12), (0.06, 0.3), (0.0, 0.62), (-0.06, 0.3)]
    verts = [(x * s, (1.42 + y) * s, z) for x, y in pts for z in (-0.02, 0.02)]
    faces = [(0, 2, 4, 6, 8), (1, 9, 7, 5, 3)] + [(2 * i, 2 * ((i + 1) % 5), 2 * ((i + 1) % 5) + 1, 2 * i + 1) for i in range(5)]
    bm.from_pydata(verts, [], faces)
    blade = bpy.data.objects.new('Blade', bm)
    bpy.context.collection.objects.link(blade)
    bm.materials.append(gold)
    blade.parent = root
    # red tassel marker on the dragon head top (+Z) so the roll is visible
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(0, 1.3 * s, 0.09))
    tassel = bpy.context.object
    tassel.data.materials.append(mat('Tassel', (0.7, 0.05, 0.08, 1)))
    tassel.parent = root
    return root


def apply(hr, clip, frame, spear, grip):
    rig = hr.rig
    qs, root = cm.interp_clip(clip, frame)
    kxz = clip.get('rootXZ', 0)
    offset = V((root.x * kxz, root.y, root.z * kxz)) * rig.leg_length
    dR, P = h25.solve(rig, qs, offset, p25.details_at(clip, frame))
    rig.apply_pose(dR, P)
    O, butt, tip, q = author.spear_points(rig, hr, qs, P, grip)
    spear.matrix_world = preview.hero_to_world(rig, Matrix.LocRotScale(O, q, V((1, 1, 1))))
    bpy.context.view_layer.update()
    return O, tip


def attach_prop(rig, root, path):
    """The shipped Prop USDZ in place of the proxy: propFit scale = procedural length 2.88 / prop length, × weaponScale 1.08."""
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=str(Path(path).resolve()))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    prop = bpy.context.view_layer.objects.active
    prop.parent = None
    prop.data.transform(prop.matrix_world)
    prop.matrix_world = Matrix.Identity(4)
    prop.data.transform(rig.M.to_4x4())  # Blender world -> USD/hero axes (same mapping as the hero import)
    ys = [v.co.y for v in prop.data.vertices]
    length = max(ys) - min(ys)
    for o in new:
        if o != prop:
            bpy.data.objects.remove(o)
    for c in list(root.children):
        c.hide_render = True
    prop.parent = root
    prop.matrix_parent_inverse = Matrix.Identity(4)
    prop.matrix_basis = Matrix.Scale(2.88 / length * 1.08, 4)
    return prop


def setup(view, tile=(400, 480), prop=None, frame_height=2.4):
    hr, meshes, height, warnings, axis = author.setup_rig()
    label = preview.setup_scene(hr.rig, frame_height, view, tile)
    label.data.size *= 0.6
    spear = make_spear()
    if prop:
        attach_prop(hr.rig, spear, prop)
    return hr, meshes, label, spear


def render(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path.resolve())
    bpy.ops.render.render(write_still=True)
    return str(path.resolve())


def sheets(clips, grip, only, view, prop=None, tag='', frame_height=2.4, tile=(400, 480)):
    hr, meshes, label, spear = setup(view, tile=tile, prop=prop, frame_height=frame_height)
    out = {}
    for name, clip in clips.items():
        if only and name not in only:
            continue
        n = clip['frames']
        if FRAMES:
            frames = FRAMES
        elif clip.get('loop'):
            frames = [round(i * n / 8, 1) for i in range(8)]
        else:
            imp = clip.get('events', {}).get('impact', n // 3)
            frames = sorted(set([0, max(0, imp - 5), max(0, imp - 2), imp, min(n - 1, imp + 3), min(n - 1, imp + 8), n - 1]))
        files = []
        for i, f in enumerate(frames):
            O, tip = apply(hr, clip, f, spear, grip)
            label.data.body = f'{name} f{f}'
            files.append(render(OUT / 'sheets' / f'{name}_{view}{tag}_{i:02d}.png'))
        sheet = OUT / f'sheet_{name}_{view}{tag}.png'
        preview.tile_images(files, str(sheet), tile, 4)
        out[name] = str(sheet)
    print(json.dumps(out), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--clips', default='App/Resources/Heroes/H027MotionClips.json')
    parser.add_argument('--only', default='')
    parser.add_argument('--view', default='34')
    parser.add_argument('--prop', default='', help='Prop USDZ to show instead of the proxy (e.g. App/Resources/Heroes/Prop_dragonSpear.usdz)')
    parser.add_argument('--tag', default='')
    parser.add_argument('--frame-height', type=float, default=2.4)
    parser.add_argument('--tile', default='400x480')
    parser.add_argument('--frames', default='', help='explicit frames, comma separated')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    report = json.loads((OUT / 'finish-report.json').read_text())
    g = report['grip']['quaternion_xyzw']
    grip = Quaternion((g[3], g[0], g[1], g[2]))
    clips = preview.load_clips(args.clips)
    only = set(x for x in args.only.split(',') if x)
    global FRAMES
    FRAMES = [float(x) for x in args.frames.split(',') if x]
    sheets(clips, grip, only, args.view, args.prop or None, args.tag, args.frame_height, tuple(int(x) for x in args.tile.split('x')))


if __name__ == '__main__':
    main()
