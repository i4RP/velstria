"""H027 の比較用の静止画: MLBB の画面収録と同じ時刻・同じ向きで、仕上げたクリップを Blender で描く（ゲームや FPS の撮影ではない）。

ショットの一覧（JSON）の 1 件 = {"out": "a.png", "clip": "h027_sweep", "frame": 10, "heading": 60, "el": 43}
  heading: 画面上のヒーローの向き（度、画面の上 = 0、時計回り。MLBB のコマで読んだ値）。el: 見下ろしの角度（度）。
  "view": "side" なら右手側の真横の拡大（heading・el は使わない）。
MLBB のコマとの並べ方は tools/h027_compare_sheet.py（Blender の外）。docs/H027_QUALITY.md の「比較の手順」。

Run from VELSTRIA: Blender -b -P tools/blender/compare_h027_mlbb.py -- --shots shots.json [--clips ...] [--tile 360x360]
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_h027_motion as author
import preview_clip as preview
import preview_h027_motion as p27

V = Vector


def camera_matrix(d, height, distance=6.0):
    up = V((0, 1, 0))
    x = up.cross(d).normalized()
    y = d.cross(x).normalized()
    target = V((0, height * 0.42, 0))
    loc = target + d * distance
    return Matrix(((x.x, y.x, d.x, loc.x), (x.y, y.y, d.y, loc.y), (x.z, y.z, d.z, loc.z), (0, 0, 0, 1)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--clips', default='App/Resources/Heroes/H027MotionClips.json')
    parser.add_argument('--shots', required=True)
    parser.add_argument('--tile', default='360x360')
    parser.add_argument('--prop', default='App/Resources/Heroes/Prop_dragonSpear.usdz')
    parser.add_argument('--frame-height', type=float, default=3.6)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    tile = tuple(int(v) for v in args.tile.split('x'))
    shots = json.loads(Path(args.shots).read_text(encoding='utf-8'))
    clips = preview.load_clips(args.clips)
    hr, meshes, label, spear = p27.setup('34', tile=tile, prop=args.prop or None, frame_height=args.frame_height)
    label.hide_render = True
    report = json.loads((p27.OUT / 'finish-report.json').read_text())
    g = report['grip']['quaternion_xyzw']
    grip = Quaternion((g[3], g[0], g[1], g[2]))
    cam = bpy.context.scene.camera
    rig = hr.rig
    for shot in shots:
        clip = clips[shot['clip']]
        if shot.get('view') == 'side':
            d = V((1.0, 0.06, 0.0)).normalized()
            cam.data.ortho_scale = shot.get('scale', 2.6)
        else:
            phi, el = math.radians(shot.get('heading', 0)), math.radians(shot.get('el', 43))
            d = V((math.sin(phi) * math.cos(el), math.sin(el), math.cos(phi) * math.cos(el)))
            cam.data.ortho_scale = shot.get('scale', args.frame_height)
        cam.matrix_world = preview.hero_to_world(rig, camera_matrix(d, 1.7))
        p27.apply(hr, clip, shot['frame'], spear, grip)
        p27.render(Path(shot['out']))
    print(json.dumps(dict(rendered=len(shots))), flush=True)


if __name__ == '__main__':
    main()
