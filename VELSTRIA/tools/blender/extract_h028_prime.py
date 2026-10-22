"""H028 ザイルの Meshy prime（SMPL-H の FBX）を区間回転の元クリップへ変換する（複数ファイルをまとめて）。

blender -b -P tools/blender/extract_h028_prime.py -- [--dir build/h028-motion] [--out tools/motion/h028-prime-source-clips.json]
extract_h025_prime.py と同じ骨名の対応・同じ往復検証（extract_clips.extract）。腰の水平移動は残す（移動の速さを測る）。
肩・つま先は親に対する ΔR（ヒーロー空間の軸）で details に保存（author_h028_motion.py が H028 の USD の軸へ直す）。
"""
import argparse
import json
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clip_math as cm
import extract_clips as ec
from extract_h025_prime import SMPLH_TO_MIXAMO

NAMES = ["idle", "idle2", "walk", "walk2", "run", "attack", "skill1", "skill2", "ult"]
DETAIL_ROLES = ("leftshoulder", "rightshoulder", "lefttoebase", "righttoebase")
POINTS = ("hips", "head", "rightarm", "righthand", "lefthand", "rightfoot", "leftfoot", "righttoebase", "lefttoebase")


def r6(x):
    return round(x, 6) + 0.0


def extract_one(path, name, task_id):
    ec.nc.reset_scene()
    bpy.ops.import_scene.fbx(filepath=os.path.abspath(path))
    arm = max((o for o in bpy.data.objects if o.type == 'ARMATURE'), key=lambda a: len(a.data.bones))
    if "Pelvis" not in arm.data.bones or "L_Wrist" not in arm.data.bones:
        raise SystemExit(f"{path}: Meshy prime の SMPL-H ではない")
    ec.role_names = lambda _: SMPLH_TO_MIXAMO
    rig, facing = ec.source_frame(arm, path)
    action = arm.animation_data.action
    first, last = map(float, action.frame_range)
    fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
    offset = first - 1.0
    clip = {"name": "h028src_" + name, "source": {"file": path}, "_label": f"meshy:text-to-motion:{task_id}",
            "_path": path, "start": 1, "end": last - offset, "loop": False, "inPlace": False, "rootXZ": 0}
    out, report, passed = ec.extract(clip, rig, arm, fps, (1.0, last - offset), offset)
    if not passed:
        raise SystemExit(f"{path}: 往復検証の失敗 {report['verify']}")
    times, _, _, _ = ec.sample_times(clip, 1, last - offset, fps)
    idx = [rig.index[r] for r in DETAIL_ROLES]
    details, points, prev = [], [], {}
    L = rig.leg_length
    for t in times:
        dR, P = ec.eval_at(arm, rig, t + offset)
        for i in idx:
            p = rig.parent[i]
            q = (dR[p].inverted() @ dR[i]) if p >= 0 else dR[i].copy()
            q.normalize()
            if (i in prev and q.dot(prev[i]) < 0) or (i not in prev and q.w < 0):
                q = cm.neg(q)
            prev[i] = q
            details += [r6(q.x), r6(q.y), r6(q.z), r6(q.w)]
        for r in POINTS:
            v = P[rig.index[r]] / L
            points += [r6(v.x), r6(v.y), r6(v.z)]
    # SMPL-H の FBX は腰に固定の持ち上げを持つ。クリップ全体で最も低い足（足首・つま先）がレストの足の高さに来るよう
    # 腰の高さだけをずらす（クリップ内の上下動・跳びはそのまま）
    k = len(POINTS)
    feet = [POINTS.index(r) for r in ("rightfoot", "leftfoot", "righttoebase", "lefttoebase")]
    lowest = min(points[(f * k + i) * 3 + 1] for f in range(len(times)) for i in feet)
    rest_low = min(rig.P0[rig.index[r]].y / L for r in ("rightfoot", "leftfoot", "righttoebase", "lefttoebase"))
    shift = lowest - rest_low
    for f in range(len(times)):
        out["root"][f * 3 + 1] = round(out["root"][f * 3 + 1] - shift, 4)
        for i in range(k):
            points[(f * k + i) * 3 + 1] = r6(points[(f * k + i) * 3 + 1] - shift)
    report["rootRebaseLegUnits"] = shift
    out["details"] = {"roles": list(DETAIL_ROLES), "rot": details}
    out["points"] = {"roles": list(POINTS), "pos": points}
    out["legLength"] = L
    out["restPoints"] = {r: [r6(c / L) for c in rig.P0[rig.index[r]]] for r in POINTS}
    report.update({"bones": len(rig.names), "facing": facing, "sourceFps": fps, "actionFrameRange": [first, last]})
    print(f"[h028] {name}: {len(times)} frames @ {fps} fps, roundtrip {report['verify']['limbMaxDegrees']}°", flush=True)
    return out, report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/h028-motion")
    ap.add_argument("--out", default="tools/motion/h028-prime-source-clips.json")
    a = ap.parse_args(ec.nc.script_args())
    state = json.load(open(os.path.join(a.dir, "api-state.json")))
    clips, reports = [], []
    for n in NAMES:
        task = state["tasks"].get(n + "_prime", {})
        path = os.path.join(a.dir, n + "_prime.fbx")
        if not os.path.isfile(path):
            print(f"[h028] {n}: FBX が無い（飛ばす）", flush=True)
            continue
        out, rep = extract_one(path, n, task.get("task_id", "?"))
        clips.append(out)
        reports.append(rep)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w") as f:
        json.dump({"version": 1, "fps": 30, "segments": cm.SEGMENTS, "clips": clips}, f, separators=(",", ":"))
    with open(os.path.join(a.dir, "prime-extract-report.json"), "w") as f:
        json.dump(reports, f, indent=1)


if __name__ == "__main__":
    main()
