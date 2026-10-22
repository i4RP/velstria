"""Extract the H034 Meshy prime SMPL-H FBX takes into 15-segment source clips.

Blender -b --python tools/blender/extract_h034_prime.py
Reads build/h034-motion/prime_<name>.fbx (tools/h034_motion_api.mjs) and writes
tools/motion/h034-prime-source-clips.json + build/h034-motion/prime-report.json.
Same source_frame/eval_at/round-trip math as extract_clips.py / extract_h025_prime.py.
Horizontal root travel is removed (in place); the fixed SMPL-H bind-origin lift is rebased to 0.
"""
import json
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clip_math as cm  # noqa: E402
import extract_clips as ec  # noqa: E402
from extract_h025_prime import SMPLH_TO_MIXAMO  # noqa: E402

MOTIONS = ['idle', 'walk', 'run', 'attack', 'hook', 'slam', 'ult']
LOOPS = {'idle', 'walk', 'run'}


def main():
    state = json.load(open('build/h034-motion/api-state.json'))
    clips, reports = [], []
    for name in MOTIONS:
        path = f'build/h034-motion/prime_{name}.fbx'
        if not os.path.exists(path):
            print(f'[h034] skip {name}: no FBX', flush=True)
            continue
        ec.nc.reset_scene()
        bpy.ops.import_scene.fbx(filepath=os.path.abspath(path))
        arm = max((o for o in bpy.data.objects if o.type == 'ARMATURE'), key=lambda a: len(a.data.bones))
        if 'Pelvis' not in arm.data.bones:
            raise SystemExit(f'{path}: expected SMPL-H skeleton')
        ec.role_names = lambda _: SMPLH_TO_MIXAMO
        rig, facing = ec.source_frame(arm, path)
        action = arm.animation_data.action
        first, last = map(float, action.frame_range)
        fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
        offset = first - 1.0
        task = state['tasks'][f'prime_{name}']['task_id']
        clip = {'name': f'prime_{name}_h034', 'source': {'file': path}, '_label': f'meshy:text-to-motion:prime:{task}',
                '_path': path, 'start': 1, 'end': last - offset, 'loop': name in LOOPS, 'inPlace': True, 'rootXZ': 0}
        out, report, passed = ec.extract(clip, rig, arm, fps, (1.0, last - offset), offset)
        if not passed:
            raise SystemExit(f'{name}: roundtrip failed {report["verify"]}')
        base = min(out['root'][1::3]) if name in LOOPS else out['root'][1]
        for i in range(1, len(out['root']), 3):
            out['root'][i] = round(out['root'][i] - base, 4)
        report.update(facing=facing, bones=len(rig.names), rootBaseline=base)
        clips.append(out)
        reports.append(report)
        print(f'[h034] {name}: {out["frames"]} frames, seam {report["loopSeamDegrees"]}, '
              f'limb {report["verify"]["limbMaxDegrees"]}°, drift {report["driftRemoved"]}', flush=True)
    with open('tools/motion/h034-prime-source-clips.json', 'w') as f:
        json.dump({'version': 1, 'fps': 30, 'segments': cm.SEGMENTS, 'clips': clips}, f, separators=(',', ':'))
    with open('build/h034-motion/prime-report.json', 'w') as f:
        json.dump(reports, f, indent=1)


main()
