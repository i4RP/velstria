"""Extract the H029 Meshy prime SMPL-H FBX takes into 15-segment source clips.

Blender -b -P tools/blender/extract_h029_prime.py
Reads build/h029-motion/<name>.fbx (tools/motion/h029-prime-spec.json) and writes
tools/motion/h029-prime-source-clips.json + h029-prime-source-details.json
(shoulder/toe local deltas) + build/h029-motion/prime-report.json.
Same source_frame/eval_at/round-trip math as extract_clips.py / extract_h025_prime.py.
"""
import json
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clip_math as cm
import extract_clips as ec
from extract_h025_prime import SMPLH_TO_MIXAMO, xyzw, write

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DETAIL_ROLES = ("leftshoulder", "rightshoulder", "lefttoebase", "righttoebase")


def run():
    spec = json.load(open(os.path.join(ROOT, 'tools/motion/h029-prime-spec.json')))['motions']
    state = json.load(open(os.path.join(ROOT, 'build/h029-motion/api-state.json')))['tasks']
    clips, details, reports = [], [], {}
    for name in spec:
        path = os.path.join(ROOT, 'build/h029-motion', name + '.fbx')
        if not os.path.isfile(path):
            print(f'[prime] skip {name} (not downloaded)', flush=True)
            continue
        ec.nc.reset_scene()
        bpy.ops.import_scene.fbx(filepath=path)
        arm = max((o for o in bpy.data.objects if o.type == 'ARMATURE'), key=lambda a: len(a.data.bones))
        if "Pelvis" not in arm.data.bones or "L_Wrist" not in arm.data.bones:
            raise SystemExit(f"{name}: expected Meshy prime SMPL-H skeleton")
        ec.role_names = lambda _: SMPLH_TO_MIXAMO
        rig, facing = ec.source_frame(arm, path)
        action = arm.animation_data.action
        first, last = map(float, action.frame_range)
        fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
        offset = first - 1.0
        task = state.get(name, {}).get('task_id')
        clip = {"name": name, "source": {"file": path}, "_label": f"meshy:text-to-motion:{task}",
                "_path": path, "start": 1, "end": last - offset, "loop": False, "inPlace": True, "rootXZ": 0}
        output, report, passed = ec.extract(clip, rig, arm, fps, (1.0, last - offset), offset)
        if not passed:
            raise SystemExit(f"{name}: source roundtrip verification failed: {report['verify']}")
        # SMPL-H の FBX はバインド原点の持ち上げを持つ。最初のフレームの高さを 0 に（相対の上下動は残す）
        base_y = output['root'][1]
        for i in range(1, len(output['root']), 3):
            output['root'][i] = round(output['root'][i] - base_y, 4)
        output['source'] = clip['_label']
        clips.append(output)
        times, _, _, _ = ec.sample_times(clip, 1, last - offset, fps)
        idx = [i for i, r in enumerate(rig.roles) if r in DETAIL_ROLES]
        rot, prev, track = [], {}, []
        for time in times:
            dR, P = ec.eval_at(arm, rig, time + offset)
            for i in idx:
                p = rig.parent[i]
                q = (dR[p].inverted() @ dR[i]) if p >= 0 else dR[i].copy()
                q.normalize()
                if (i in prev and q.dot(prev[i]) < 0) or (i not in prev and q.w < 0):
                    q = cm.neg(q)
                prev[i] = q
                rot.extend(xyzw(q))
            track.append({r: [round(v, 4) for v in P[rig.index[r]]] for r in
                          ('hips', 'head', 'lefthand', 'righthand', 'leftfoot', 'rightfoot')})
        details.append({"name": name, "frames": len(times), "roles": [rig.roles[i] for i in idx], "rot": rot})
        reports[name] = {"frames": len(times), "sourceFps": fps, "actionFrameRange": [first, last], "facing": facing,
                         "legLength": rig.leg_length, "verify": report['verify'], "rootBaseY": base_y,
                         "rootRange": report.get('rootRange'), "positions": track}
        print(f"[prime] {name}: {len(rig.names)} bones, {len(times)} frames @ {fps}, limb max {report['verify']['limbMaxDegrees']} deg", flush=True)
    write(os.path.join(ROOT, 'tools/motion/h029-prime-source-clips.json'),
          {"version": 1, "fps": 30, "segments": cm.SEGMENTS, "clips": clips})
    write(os.path.join(ROOT, 'tools/motion/h029-prime-source-details.json'),
          {"version": 1, "fps": 30, "rotationSpace": "parentRelativeRestDeltaHeroAxes", "clips": details})
    write(os.path.join(ROOT, 'build/h029-motion/prime-report.json'), reports)


if __name__ == '__main__':
    run()
