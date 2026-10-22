"""H029 の仕上げクリップを、実際の聖槌・盾（Prop_holyMaul / Prop_heaterShield）を持たせて撮る（Blender 5.x Workbench）。
骨は実行時と同じ解き方（15 区間 + detailJoints）、武器は SkinnedHeroModel.apply と同じ置き方（手の位置 + 握りの分だけ手の区間の
向きへずらし、向きは 手の区間 · grip · propFit）。寸法の propFit は手続きの武器の範囲からの近似。
  blender -b -P tools/blender/preview_h029_motion.py -- [--clip a,b] [--frames 8] [--view 34,top] [--video]
出力: build/h029-motion/preview/<clip>_<view>.png、--video は build/h029-motion/preview/<clip>_<view>.mp4（30fps）
"""
import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clip_math as cm
import preview_clip as preview
from author_h025_motion import bind_usd_axes, solve

HERO = 'App/Resources/Heroes/Hero_H029.usdz'
OUT = Path('build/h029-motion/preview')
# HeroMotionSets の H029: 槌 = fistGrip（+Y → 手の -Z）、盾 = 前腕に付けた盾（+Y → 親指の側、盾の面 -Z → 手の -X）
FIST = Quaternion((1, 0, 0), -math.pi / 2)
SHIELD = Matrix(((0, 0, 1), (-1, 0, 0), (0, -1, 0))).to_quaternion()
# 手続きの武器の範囲（HeroGear）: 聖槌の高さ 1.742、盾の高さ 0.958 と中心・ry(0.3)
MAUL_H, SHIELD_H = 1.742, 0.958
SHIELD_CENTER, SHIELD_YAW = Vector((-0.10, -0.07, -0.12)), 0.3


def prop(path, name):
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=str(Path(path).resolve()))
    new = [o for o in set(bpy.data.objects) - before if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.name = name
    for o in set(bpy.data.objects) - before:
        if o is not ob and o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    return ob


def bbox_hero(rig, ob):
    pts = [rig.M @ (ob.matrix_world @ v.co) for v in ob.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return lo, hi


def fit(rig, ob, height, yaw=0.0, center=None):
    """propFit: 高さを手続きの武器へ合わせ、yaw を掛け、center なら範囲の中心を合わせる（ヒーロー空間の 4x4）。"""
    lo, hi = bbox_hero(rig, ob)
    s = height / max(1e-4, hi.y - lo.y)
    rot = Quaternion((0, 1, 0), yaw)
    t = Vector((0, 0, 0))
    if center is not None:
        t = center - rot @ (((lo + hi) * 0.5) * s)
    base = rig.M.inverted().to_4x4()   # 取り込んだ頂点（ワールド）→ ヒーロー空間の行列は M
    return Matrix.LocRotScale(t, rot, Vector((s, s, s))) @ rig.M.to_4x4(), base


def details_at(clip, f):
    joints = clip.get('detailJoints') or []
    if not joints:
        return {}
    n = clip['frames']
    vals = clip['detailRot']
    if clip['loop']:
        i0 = int(math.floor(f)) % n
        i1 = (i0 + 1) % n
    else:
        f = min(max(f, 0), n - 1)
        i0 = int(math.floor(f))
        i1 = min(n - 1, i0 + 1)
    a = f - math.floor(f)
    out = {}
    for k, role in enumerate(joints):
        def q(i):
            o = (i * len(joints) + k) * 4
            return Quaternion((vals[o + 3], vals[o], vals[o + 1], vals[o + 2]))
        out[role] = cm.slerp(q(i0), q(i1), a)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clips', default='App/Resources/Heroes/H029MotionClips.json')
    ap.add_argument('--clip', default='all')
    ap.add_argument('--frames', type=int, default=8)
    ap.add_argument('--view', default='34')
    ap.add_argument('--tile', default='300x360')
    ap.add_argument('--video', action='store_true')
    ap.add_argument('--loops', type=int, default=2)
    a = ap.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    clips = {c['name']: c for c in json.loads(Path(a.clips).read_text())['clips']}
    names = list(clips) if a.clip == 'all' else a.clip.split(',')
    tile = tuple(int(v) for v in a.tile.split('x'))
    OUT.mkdir(parents=True, exist_ok=True)
    rig, meshes, height, _ = preview.load_hero(str(Path(HERO).resolve()))
    bind_usd_axes(rig, HERO)
    maul = prop('App/Resources/Heroes/Prop_holyMaul.usdz', 'Maul')
    shield = prop('App/Resources/Heroes/Prop_heaterShield.usdz', 'Shield')
    maul_fit, _ = fit(rig, maul, MAUL_H)
    shield_fit, _ = fit(rig, shield, SHIELD_H, SHIELD_YAW, SHIELD_CENTER)
    maul_rest, shield_rest = maul.matrix_world.copy(), shield.matrix_world.copy()
    hand_r, hand_l = rig.index['righthand'], rig.index['lefthand']
    grip_r = 0.6 * (rig.P0[rig.index['righthandindex1']] - rig.P0[hand_r]).length if 'righthandindex1' in rig.index else 0.06
    grip_l = 0.6 * (rig.P0[rig.index['lefthandindex1']] - rig.P0[hand_l]).length if 'lefthandindex1' in rig.index else 0.06
    report = {}
    for view in a.view.split(','):
        for o in list(bpy.data.objects):
            if o.type in ('CAMERA', 'FONT') or o.name.startswith('Ground'):
                bpy.data.objects.remove(o, do_unlink=True)
        label = preview.setup_scene(rig, height * 1.25, view, tile)
        for name in names:
            clip = clips[name]
            n = clip['frames']
            kxz = float(clip.get('rootXZ', 0))
            if a.video:
                count = n * (a.loops if clip['loop'] else 1)
                frames = [f % n if clip['loop'] else f for f in range(count)]
            else:
                frames = [i * (n if clip['loop'] else n - 1) / (a.frames if clip['loop'] else max(1, a.frames - 1)) for i in range(a.frames)]
            tmp = tempfile.mkdtemp(prefix='h029_preview_')
            files = []
            for i, f in enumerate(frames):
                qs, root = cm.interp_clip(clip, f)
                offset = Vector((root.x * kxz, root.y, root.z * kxz)) * rig.leg_length
                dR, P = solve(rig, qs, offset, details_at(clip, f))
                rig.apply_pose(dR, P)
                qr, ql = qs[cm.SEG_INDEX['handR']], qs[cm.SEG_INDEX['handL']]
                pr = P[hand_r] + qr @ Vector((0, -grip_r, 0))
                pl = P[hand_l] + ql @ Vector((0, -grip_l, 0))
                mr = Matrix.LocRotScale(pr, qr @ FIST, Vector((1, 1, 1))) @ maul_fit
                ml = Matrix.LocRotScale(pl, ql @ SHIELD, Vector((1, 1, 1))) @ shield_fit
                maul.matrix_world = preview.hero_to_world(rig, mr) @ maul_rest
                shield.matrix_world = preview.hero_to_world(rig, ml) @ shield_rest
                bpy.context.view_layer.update()
                label.data.body = f"H029 {name}  f{f:.1f}/{n}"
                p = os.path.join(tmp, f'f{i:04d}.png')
                bpy.context.scene.render.filepath = p
                bpy.ops.render.render(write_still=True)
                files.append(p)
            if a.video:
                out = OUT / f'{name}_{view}.mp4'
                subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', '30', '-i', os.path.join(tmp, 'f%04d.png'),
                                '-pix_fmt', 'yuv420p', '-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2', str(out)], check=True)
            else:
                out = OUT / f'{name}_{view}.png'
                preview.tile_images(files, str(out), tile, len(files))
            shutil.rmtree(tmp, ignore_errors=True)
            report[f'{name}_{view}'] = str(out)
            print(f'[h029-preview] {out}', flush=True)
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
