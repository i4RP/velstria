"""Extract every saved H033 Meshy prime SMPL-H FBX into the runtime's 15 segments.

Blender -b -P tools/blender/extract_h033_prime.py -- --dir build/h033-motion
  --out tools/motion/h033-prime-source-clips.json --details tools/motion/h033-prime-source-details.json
Same source_frame/eval_at/round-trip math as extract_h025_prime.py (one clip per FBX).
"""
import argparse
import json
import os
import sys
from pathlib import Path

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clip_math as cm
import extract_clips as ec
from extract_h025_prime import SMPLH_TO_MIXAMO, xyzw, write

DETAIL_ROLES = ("leftshoulder", "rightshoulder", "lefttoebase", "righttoebase")


def extract_one(path, name, task_id):
    ec.nc.reset_scene()
    bpy.ops.import_scene.fbx(filepath=os.path.abspath(path))
    arm = max((o for o in bpy.data.objects if o.type == 'ARMATURE'), key=lambda a: len(a.data.bones))
    if "Pelvis" not in arm.data.bones or "L_Wrist" not in arm.data.bones:
        raise SystemExit(f"{path}: expected Meshy prime SMPL-H skeleton")
    ec.role_names = lambda _: SMPLH_TO_MIXAMO
    rig, facing = ec.source_frame(arm, path)
    action = arm.animation_data.action
    first, last = map(float, action.frame_range)
    fps = bpy.context.scene.render.fps/bpy.context.scene.render.fps_base
    offset = first-1.0
    clip = {"name": name, "source": {"file": path}, "_label": f"meshy:text-to-motion:{task_id}", "_path": path,
            "start": 1, "end": last-offset, "loop": False, "inPlace": False, "rootXZ": 0}
    output, report, passed = ec.extract(clip, rig, arm, fps, (1.0, last-offset), offset)
    if not passed:
        raise SystemExit(f"{name}: roundtrip verification failed: {report['verify']}")
    # Remove the fixed SMPL-H bind-origin lift (keep relative bob / jump height) and the
    # starting horizontal position (keep relative travel for the leap / step reference).
    x0, y0, z0 = output['root'][0:3]
    for i in range(0, len(output['root']), 3):
        output['root'][i] = round(output['root'][i]-x0, 4)
        output['root'][i+1] = round(output['root'][i+1]-y0, 4)
        output['root'][i+2] = round(output['root'][i+2]-z0, 4)
    times, _, _, _ = ec.sample_times(clip, 1, last-offset, fps)
    idx = [i for i, r in enumerate(rig.roles) if r in DETAIL_ROLES]
    rot, prev = [], {}
    for t in times:
        dR, _ = ec.eval_at(arm, rig, t+offset)
        for i in idx:
            p = rig.parent[i]
            q = (dR[p].inverted() @ dR[i]) if p >= 0 else dR[i].copy()
            q.normalize()
            if (i in prev and q.dot(prev[i]) < 0) or (i not in prev and q.w < 0):
                q = cm.neg(q)
            prev[i] = q
            rot.extend(xyzw(q))
    detail = {"name": name, "frames": len(times), "roles": [rig.roles[i] for i in idx], "rot": rot}
    summary = {"name": name, "frames": output['frames'], "sourceFps": fps, "facing": facing,
               "verify": report['verify'], "rootRange": report.get('rootRange')}
    return output, detail, summary


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--dir', default='build/h033-motion')
    p.add_argument('--out', default='tools/motion/h033-prime-source-clips.json')
    p.add_argument('--details', default='tools/motion/h033-prime-source-details.json')
    a = p.parse_args(ec.nc.script_args())
    state = json.loads(Path(a.dir, 'api-state.json').read_text(encoding='utf-8'))
    clips, details, summaries = [], [], []
    for name, task in state['tasks'].items():
        f = Path(a.dir, f'{name}.fbx')
        if not f.is_file():
            continue
        c, d, s = extract_one(str(f), 'h033src_'+name, task.get('task_id'))
        clips.append(c); details.append(d); summaries.append(s)
        print(f"[h033] {name}: {c['frames']} frames, limb max {s['verify'].get('limbMaxDegrees')}", flush=True)
    write(a.out, {"version": 1, "fps": 30, "segments": cm.SEGMENTS, "clips": clips})
    write(a.details, {"version": 1, "fps": 30, "rotationSpace": "parentRelativeSourceWorld", "clips": details})
    write(str(Path(a.dir, 'prime-extract-report.json')), summaries)


if __name__ == '__main__':
    main()
