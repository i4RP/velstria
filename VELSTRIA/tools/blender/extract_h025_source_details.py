"""Export H025 shoulder/finger/toe detail deltas beside the standard 15-segment source clips.

Run with Blender: --python tools/blender/extract_h025_source_details.py --
  --spec build/h025-motion/tripo-source-spec.json --out build/h025-motion/tripo-source-details.json
Does not alter the generic extractor or a production model. Rotation arrays are xyzw,
frame-major/role-minor in canonical hero axes (Y up, front -Z, right +X).
"""
import argparse
import json
import math
import os
import re
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_clips as ec
import clip_math as cm


def xyzw(q):
    q = q.normalized()
    return [round(q.x, 6), round(q.y, 6), round(q.z, 6), round(q.w, 6)]


def run(args):
    spec = ec.load_spec(args.spec)
    result = {"version": 1, "fps": ec.OUT_FPS, "rotationSpace": "parentRelativeRestDeltaHeroAxes", "clips": []}
    source = None
    for clip in spec:
        filename, index, label = ec.resolve_source(clip["source"], "build/meshy/anim")
        if filename != source:
            arm, gltf, fps = ec.import_source(os.path.abspath(filename))
            rig, facing = ec.source_frame(arm, filename)
            source = filename
        action, _ = ec.pick_action(arm, gltf, index, filename)
        first, last = map(float, action.frame_range)
        offset = first - 1.0
        times, start, end, step = ec.sample_times(clip, 1.0, last-offset, fps)
        indices = [i for i, role in enumerate(rig.roles) if role in ("leftshoulder", "rightshoulder", "lefttoebase", "righttoebase")
                   or re.fullmatch(r"(?:left|right)hand(?:thumb|index|middle|ring|pinky)[123]", role)]
        roles = [rig.roles[i] for i in indices]
        parents = [rig.roles[rig.parent[i]] if rig.parent[i] >= 0 else None for i in indices]
        rotations, previous, samples = [], {}, []
        for time in times:
            deltas, positions = ec.eval_at(arm, rig, time+offset)
            samples.append((deltas, positions))
            for i in indices:
                parent = rig.parent[i]
                delta = (deltas[parent].inverted() @ deltas[i]) if parent >= 0 else deltas[i].copy()
                delta.normalize()
                if (i in previous and delta.dot(previous[i]) < 0) or (i not in previous and delta.w < 0):
                    delta = cm.neg(delta)
                previous[i] = delta
                rotations.extend(xyzw(delta))
        rest_rotation = []
        for i in indices:
            rest_rotation.extend(xyzw(rig.qM @ rig.q0w[i]))
        detail = {"roles": roles, "parentRoles": parents, "rot": rotations, "sourceRestGlobalRot": rest_rotation}
        item = {"name": clip["name"], "source": label, "sourceAction": action.name, "frames": len(times),
                "start": start, "end": end, "step": step, "sourceDetails": detail, "facing": facing}
        if "run" in clip["name"]:
            # Suggest an actual repeated interval; report only, never silently trim.
            qs = [rig.extract(*sample)[0] for sample in samples]
            pairs = []
            for i in range(len(qs)):
                for j in range(i+max(10, int(fps*0.35)), len(qs)):
                    seam = max(cm.quat_angle_deg(a,b) for a,b in zip(qs[i],qs[j]))
                    pairs.append((seam,times[i],times[j]))
            item["bestObservedRunCycle"] = [dict(seamDegrees=round(s,3),start=a,end=b) for s,a,b in sorted(pairs)[:5]]
        result["clips"].append(item)
        print(f"[details] {item['name']}: {len(times)} frames x {len(roles)} roles", flush=True)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out,"w",encoding="utf-8") as handle:
        json.dump(result,handle,separators=(",",":"))
    print(f"[details] wrote {args.out}",flush=True)


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--spec",required=True)
    parser.add_argument("--out",required=True)
    run(parser.parse_args(ec.nc.script_args()))
