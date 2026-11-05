"""H034 の仕上げクリップを、実際の鎖鉤（Prop_hookChain）を持たせて撮る（Blender 4.5 / 5.x Workbench。preview_h029_motion.py と同じ作り）。
骨は実行時と同じ解き方（15 区間 + detailJoints）、武器は SkinnedHeroModel.apply と同じ置き方（手の位置 + 握りの分だけ手の区間の
向きへずらし、向きは 手の区間 · grip · propFit）。寸法の propFit は手続きの武器の範囲からの近似。
  blender -b -P tools/blender/preview_h034_motion.py -- [--clip a,b] [--frames 8] [--view 34,top] [--video]
出力: build/h034-motion/preview/<clip>_<view>.png、--video は build/h034-motion/preview/<clip>_<view>.mp4（30fps）
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

# Blender 4.5 は揺れ物の骨（finish_h034_mane.py）を足した USD の取り込みで落ちるので、骨を足す前の元（finish が書き出す）を使う。
# クリップが動かす骨は同じ（揺れ物の骨は実行時の HeroSecondaryMotion だけが動かす）
_BASE = 'build/h034-motion/Hero_H034_base.usdz'
HERO = _BASE if Path(_BASE).exists() else 'App/Resources/Heroes/Hero_H034.usdz'
OUT = Path('build/h034-motion/preview')
# HeroMotionSets の H034: 鎖鉤 = fistGrip（+Y → 手の -Z）
FIST = Quaternion((1, 0, 0), -math.pi / 2)
# 手続きの鎖鉤の高さ（HeroGear の hookChain: 柄の端の球 -0.27 〜 鉤の上 0.85）× weaponScale 1.1
HOOK_H = 1.12 * 1.1


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


def scene(a):
    """ヒーローと武器を読み、(rig, height, pose(clip, frame)) を返す。pose は骨と武器を置いて view_layer を更新する。"""
    rig, meshes, height, _ = preview.load_hero(str(Path(HERO).resolve()))
    bind_usd_axes(rig, HERO)
    hook = prop('App/Resources/Heroes/Prop_hookChain.usdz', 'Hook')
    hook_fit, _ = fit(rig, hook, HOOK_H)
    hook_rest = hook.matrix_world.copy()
    hand_r = rig.index['righthand']
    grip_r = 0.6 * (rig.P0[rig.index['righthandindex1']] - rig.P0[hand_r]).length if 'righthandindex1' in rig.index else 0.06

    def pose(clip, f):
        kxz = float(clip.get('rootXZ', 0))
        qs, root = cm.interp_clip(clip, f)
        offset = Vector((root.x * kxz, root.y, root.z * kxz)) * rig.leg_length
        dR, P = solve(rig, qs, offset, details_at(clip, f))
        rig.apply_pose(dR, P)
        qr = qs[cm.SEG_INDEX['handR']]
        pr = P[hand_r] + qr @ Vector((0, -grip_r, 0))
        mr = Matrix.LocRotScale(pr, qr @ FIST, Vector((1, 1, 1))) @ hook_fit
        hook.matrix_world = preview.hero_to_world(rig, mr) @ hook_rest
        bpy.context.view_layer.update()
    return rig, height, pose


# 比較の一覧（tools/mlbb_video/motion_compare.py が MLBB のコマと並べる）: 戦闘の見下ろしは MLBB の縮尺（62.3 px / 単位 × 指定の
# scale。ヒーロー空間は × SCALE）で box の大きさ × scale の正方形。足元が MLBB の (556.6, 295) と同じ所に来るよう、box の上端は
# 295 − (タイルの半分 + 注視点の高さ × cos45° × 縮尺) / scale（h034-mlbb-compare.json の box）。横からの拡大は槌の届く範囲まで。
MLBB_PX_PER_UNIT = 62.3


def shots(a):
    spec = json.loads(Path(a.shots).read_text(encoding='utf-8'))
    rows = spec['stages'][a.stage]
    box, k = spec.get('box', [477, 173, 160, 160]), spec.get('scale', 2.0)
    tile = (int(box[2] * k), int(box[3] * k))
    game_height = tile[1] / (MLBB_PX_PER_UNIT * k * SCALE) / 1.28
    clips = {c['name']: c for c in json.loads(Path(a.clips).read_text())['clips']}
    rig, height, pose = scene(a)
    out = Path('build/h034-motion/compare') / a.stage
    out.mkdir(parents=True, exist_ok=True)
    for view in ['game', 'side']:
        jobs = [(i, r) for i, r in enumerate(rows) if r.get('clip')]
        for i, r in jobs:
            name = f"g{int(r.get('heading', 180))}" if view == 'game' else 'side'
            if name.startswith('g'):
                th = math.radians(float(r.get('heading', 180)))
                preview.VIEWS[name] = Vector((math.sin(th) * 0.7071, 0.7071, math.cos(th) * 0.7071))
            for o in list(bpy.data.objects):
                if o.type in ('CAMERA', 'FONT') or o.name.startswith('Ground'):
                    bpy.data.objects.remove(o, do_unlink=True)
            label = preview.setup_scene(rig, game_height if view == 'game' else height * 1.6, name, tile)
            label.data.body = ''
            clip = clips[r['clip']]
            f = r.get('at', 0.0) * FPS
            f = f % clip['frames'] if clip['loop'] else min(f, clip['frames'] - 1)
            pose(clip, f)
            bpy.context.scene.render.filepath = str((out / f'{i:02d}_{view}.png').resolve())
            bpy.ops.render.render(write_still=True)
    print(f'[h034-shots] {out}', flush=True)


FPS = 30
SCALE = 1.36   # HeroBlueprints の H034（motion.scale）


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clips', default='App/Resources/Heroes/H034MotionClips.json')
    ap.add_argument('--clip', default='all')
    ap.add_argument('--frames', type=int, default=8)
    ap.add_argument('--view', default='34')
    ap.add_argument('--tile', default='300x360')
    ap.add_argument('--video', action='store_true')
    ap.add_argument('--loops', type=int, default=2)
    ap.add_argument('--shots', help='比較の一覧の指定（tools/motion/h034-mlbb-compare.json）。--stage の行を 1 コマずつ撮る')
    ap.add_argument('--stage')
    a = ap.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    if a.shots:
        return shots(a)
    clips = {c['name']: c for c in json.loads(Path(a.clips).read_text())['clips']}
    names = list(clips) if a.clip == 'all' else a.clip.split(',')
    tile = tuple(int(v) for v in a.tile.split('x'))
    OUT.mkdir(parents=True, exist_ok=True)
    rig, height, pose = scene(a)
    report = {}
    for view in a.view.split(','):
        if view.startswith('g') and view[1:].lstrip('-').isdigit():
            # 戦闘の見下ろし（俯角 45°）。数字 = 画面でのヒーローの向き（0 = 奥、90 = 右、180 = 手前、270 = 左）
            th = math.radians(float(view[1:]))
            preview.VIEWS[view] = Vector((math.sin(th) * 0.7071, 0.7071, math.cos(th) * 0.7071))
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
            tmp = tempfile.mkdtemp(prefix='h034_preview_')
            files = []
            for i, f in enumerate(frames):
                pose(clip, f)
                label.data.body = f"H034 {name}  f{f:.1f}/{n}"
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
            print(f'[h034-preview] {out}', flush=True)
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
