"""Extract the H027 Meshy prime SMPL-H FBX clips (one per motion) into source segment clips.

Blender -b -P tools/blender/extract_h027_prime.py
Writes tools/motion/h027-prime-source-clips.json (15 segments, in place, fixed SMPL-H lift removed),
tools/motion/h027-prime-source-details.json (parent-relative shoulder/toe deltas; prime fingers are static)
and build/h027-motion/prime-report.json (round-trip check, root travel and per-frame joint positions).
Uses the same mapping and round-trip math as extract_h025_prime.py / extract_clips.py.
"""
import json
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clip_math as cm
import extract_clips as ec
from extract_h025_prime import SMPLH_TO_MIXAMO, write, xyzw

MOTIONS = ['idle', 'walk', 'run', 'thrust', 'sweep', 'rising', 'flip', 'strike', 'warrior']
DETAIL_ROLES = ('leftshoulder', 'rightshoulder', 'lefttoebase', 'righttoebase')
TRACK = ('hips', 'head', 'leftarm', 'leftforearm', 'lefthand', 'rightarm', 'rightforearm', 'righthand',
         'leftupleg', 'leftleg', 'leftfoot', 'lefttoebase', 'rightupleg', 'rightleg', 'rightfoot', 'righttoebase')


def run():
    state = json.load(open('build/h027-motion/api-state.json'))
    clips, details, reports = [], [], {}
    for motion in MOTIONS:
        name = f'h027_{motion}_prime'
        task = state['tasks'][name]
        path = os.path.abspath(task['file']['file'])
        ec.nc.reset_scene()
        bpy.ops.import_scene.fbx(filepath=path)
        arm = max((o for o in bpy.data.objects if o.type == 'ARMATURE'), key=lambda a: len(a.data.bones))
        if 'Pelvis' not in arm.data.bones or 'L_Wrist' not in arm.data.bones:
            raise SystemExit(f'{name}: expected the Meshy prime SMPL-H skeleton')
        ec.role_names = lambda _: SMPLH_TO_MIXAMO
        rig, facing = ec.source_frame(arm, path)
        action = arm.animation_data.action
        first, last = map(float, action.frame_range)
        fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
        offset = first - 1.0
        clip = {'name': f'meshy_h027_{motion}', 'source': {'file': path}, '_label': f"meshy:text-to-motion:{task['task_id']}",
                '_path': path, 'start': 1, 'end': last - offset, 'loop': False, 'inPlace': motion in ('walk', 'run'), 'rootXZ': 0}
        output, report, passed = ec.extract(clip, rig, arm, fps, (1.0, last - offset), offset)
        if not passed:
            raise SystemExit(f"{name}: source round trip failed: {report['verify']}")
        base_y = output['root'][1]
        for i in range(1, len(output['root']), 3):
            output['root'][i] = round(output['root'][i] - base_y, 4)
        clips.append(output)
        times, *_ = ec.sample_times(clip, 1, last - offset, fps)
        indices = [i for i, r in enumerate(rig.roles) if r in DETAIL_ROLES]
        rot, previous, positions, travel = [], {}, [], []
        for t in times:
            dR, P = ec.eval_at(arm, rig, t + offset)
            for i in indices:
                p = rig.parent[i]
                q = (dR[p].inverted() @ dR[i]) if p >= 0 else dR[i].copy()
                q.normalize()
                if (i in previous and q.dot(previous[i]) < 0) or (i not in previous and q.w < 0):
                    q = cm.neg(q)
                previous[i] = q
                rot.extend(xyzw(q))
            positions.append({r: [round(v, 5) for v in P[rig.index[r]]]
                              for r in TRACK if r in rig.index})
            travel.append([round(v, 5) for v in P[rig.index['hips']]])
        details.append({'name': clip['name'], 'source': clip['_label'], 'frames': len(times), 'sourceDetails': {
            'roles': [rig.roles[i] for i in indices], 'parentRoles': [rig.roles[rig.parent[i]] for i in indices],
            'rot': rot, 'sourceRestGlobalRot': [v for i in indices for v in xyzw(rig.qM @ rig.q0w[i])]}})
        reports[clip['name']] = {'task_id': task['task_id'], 'frames': len(times), 'fps': fps, 'facing': facing,
                                 'legLength': rig.leg_length, 'verify': report['verify'], 'rootRebaseY': base_y,
                                 'hipsTravel': travel, 'positions': positions}
        print(f"[prime] {clip['name']}: {len(times)} frames, limb max {report['verify']['limbMaxDegrees']:.4f} deg", flush=True)
    write('tools/motion/h027-prime-source-clips.json', {'version': 1, 'fps': 30, 'segments': cm.SEGMENTS, 'clips': clips})
    write('tools/motion/h027-prime-source-details.json', {'version': 1, 'fps': 30, 'rotationSpace': 'parentRelativeRestDeltaHeroAxes', 'clips': details})
    write('build/h027-motion/prime-report.json', reports)


if __name__ == '__main__':
    run()
