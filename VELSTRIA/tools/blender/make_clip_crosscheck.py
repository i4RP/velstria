# 担当: hero-motion。抽出（extract_clips.py / clip_math.py）と実行時（HeroMotionClips.swift / HeroSkeletonRig.swift）の
# 約束（docs/HERO_MOTION.md）を突き合わせる検査用フィクスチャを作る（Blender 5.2 headless）。
# 使い方（VELSTRIA/ で）:
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
#     --python tools/blender/make_clip_crosscheck.py [-- --out AppTests/Fixtures/MotionClips/crosscheck.json]
#   同梱のヒーローでも作れる（コミットしない一時的な確認用。ヒーローの USDZ を作り直すと古くなるため）:
#     ... make_clip_crosscheck.py -- --fixture App/Resources/Heroes/Hero_H001.usdz --out /tmp/crosscheck_H001.json
#   Swift 側は環境変数 VELSTRIA_CROSSCHECK_EXTRA（":" 区切りのパス）の分も確かめる。xcodebuild には
#   TEST_RUNNER_VELSTRIA_CROSSCHECK_EXTRA=/tmp/crosscheck_H001.json として渡す（rig = 同梱の Hero_<ID>）。
# 処理:
#   1. AppTests/Fixtures/SkinnedTestHero.usdz を preview_clip.py と同じ取り込みで表示側のリグにする（Rig.solve 用）。
#   2. 同じ USDZ を extract_clips.py と同じ取り込みで元リグにし、既知の動き（5 フレーム）のキーを打つ。動きは実行時の
#      骨の駆動で表せるものだけにする（背骨 3 本は同じ軸・同じ角度ずつ、首と頭も同じ回転、肩・指・つま先は回さない）。
#      そうすれば解き直した姿勢は元の姿勢と丸め（小数 4 桁）の分しか違わない。
#   3. extract_clips.extract（実際の抽出）で 2 本のクリップにする:
#      xc_basic       そのまま（非ループ・rootXZ 1・impact あり）
#      xc_mirror_yaw  左右反転 + yaw 30° + ループ（inPlace なし・rootXZ 0.5）
#      xc_signs       xc_basic の四元数をフレーム・区間ごとに市松に反転したもの（q と -q は同じ回転。フレーム間・
#                     背骨と首の slerp が最短経路をとれば xc_basic と同じ姿勢 = 「w ≥ 0 に揃えない」でよいことの確認）
#   4. 書き出した（丸めた）値を clip_math.interp_clip（HeroMotionLibrary.sample と同じ補間）と Rig.solve
#      （HeroSkeletonPoser.solve と同じ解き方）で表示側のリグに載せ、関節のヒーロー空間の位置・回転（ΔR = R·R0⁻¹）を
#      期待値として書く。元のアニメーション（Blender の評価）の位置・ΔR、レストの位置・補正 C・駆動、
#      rotationBetween（反平行の扱いを含む）の表も書く。
# 生成時の自己検査（外れたら書かずに終了コード 1）:
#   - 抽出の検証（四肢の向き 1° 以内）に通る。表示側と元リグのレストが一致する。
#   - xc_basic を解いた姿勢が元の姿勢と 0.5 mm / 0.1° 以内（抽出 → 実行時の往復）。
#   - xc_mirror_yaw を解いた姿勢が、元の姿勢を鏡映（x → -x、左右の骨を入れ替え）して腰のレスト位置の縦軸回りに
#     ry(30°) 回したものと 0.5 mm / 0.1° 以内（反転・yaw の約束。フィクスチャのリグは左右対称）。
# Swift 側: AppTests/HeroMotionClipTests.swift の testCrossCheckFixtureMatchesPythonSolve が、このファイルを
#   HeroMotionLibrary.decode → HeroClipLayer（rootXZ）→ HeroSkeletonPoser.solve で解き、1 mm 以内で一致することを確かめる。

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clip_math as cm  # noqa: E402
import extract_clips as ec  # noqa: E402
import norm_common as nc  # noqa: E402
import preview_clip as pc  # noqa: E402

FIXTURE = "AppTests/Fixtures/SkinnedTestHero.usdz"
OUT = "AppTests/Fixtures/MotionClips/crosscheck.json"
FRAMES = 5
SELF_TOL_MM = 0.5
SELF_TOL_DEG = 0.1


def log(msg):
    print(f"[crosscheck] {msg}", flush=True)


def parse():
    p = argparse.ArgumentParser(prog="make_clip_crosscheck.py")
    p.add_argument("--fixture", default=FIXTURE)
    p.add_argument("--out", default=OUT)
    return p.parse_args(nc.script_args())


def axis_angle(axis, deg):
    return Quaternion(Vector(axis).normalized(), math.radians(deg))


# 骨の役割 → s（0〜1、フレームの進み）でのヒーロー空間の回転 X（ΔR_j = ΔR_親·X_j）。
# 背骨 3 本は同じ X（実行時の slerp(腰, 胴, k/3) と一致）、首と頭も同じ X（slerp(胴, 頭, 0.5) と一致）。
# 腕は 150° まで上げ（区間回転の w の符号が変わる大きさ）、前腕・手は捻りを含む軸で回す。
MOTION = {
    "hips": ((0.2, 1.0, 0.1), 25.0),
    "spine": ((1.0, 0.3, 0.0), 12.0),
    "spine1": ((1.0, 0.3, 0.0), 12.0),
    "spine2": ((1.0, 0.3, 0.0), 12.0),
    "neck": ((0.3, 1.0, -0.2), 18.0),
    "head": ((0.3, 1.0, -0.2), 18.0),
    "rightarm": ((0.2, 0.3, 1.0), 150.0),
    "rightforearm": ((0.0, 1.0, 0.3), 60.0),
    "righthand": ((1.0, 0.2, 0.0), 40.0),
    "leftarm": ((-0.5, 0.2, 0.8), -50.0),
    "leftforearm": ((0.3, 0.8, 0.2), 45.0),
    "lefthand": ((0.1, 0.3, 1.0), -35.0),
    "rightupleg": ((1.0, 0.1, 0.2), -60.0),
    "rightleg": ((1.0, 0.0, 0.0), 80.0),
    "rightfoot": ((1.0, 0.0, 0.3), -25.0),
    "leftupleg": ((1.0, -0.1, 0.3), 35.0),
    "leftleg": ((1.0, 0.0, 0.0), 45.0),
    "leftfoot": ((0.2, 1.0, 0.1), 30.0),
}
# 腰の移動（ヒーロー空間・m、s = 1 で）
HIPS_MOVE = Vector((0.06, -0.12, 0.05))

CLIPS = [
    {"name": "xc_basic", "start": 1, "end": FRAMES, "rootXZ": 1.0, "events": {"impact": 3.5}},
    {"name": "xc_mirror_yaw", "start": 1, "end": FRAMES, "loop": True, "inPlace": False, "mirror": True, "yaw": 30.0,
     "rootXZ": 0.5, "events": {"impact": 2.0}},
]
# 期待値を書く出力フレーム（範囲外・小数・ループの折り返しを含む）
SAMPLE_FRAMES = {
    "xc_basic": [-1.0, 0.0, 1.0, 1.5, 2.0, 2.25, 3.0, 3.75, 4.0, 6.0],
    "xc_mirror_yaw": [0.0, 1.0, 2.5, 3.0, 3.5, 4.25, 7.0, -0.5],
    "xc_signs": [0.5, 1.0, 1.5, 2.75, 3.5],
}
# rotationBetween の表（反平行・しきい値の前後・一般の向き）
ROTATION_BETWEEN = [
    ((0, 1, 0), (0, -1, 0)),          # 反平行（u × X 軸が使える）
    ((1, 0, 0), (-1, 0, 0)),          # 反平行（u × X 軸が 0 → u × Z 軸）
    ((0.001, -1, 0.0005), (0, 1, 0)),  # ほぼ反平行（c < -0.9999）
    ((0.01, -1, 0), (0, -1, 0)),      # ほぼ平行（c > 0.9999 → 単位）
    ((0.03, -1, 0), (0, -1, 0)),      # しきい値の外（c ≈ 0.99955 → 最小回転）
    ((1, 0, 0), (0, -1, 0)),          # T ポーズの右腕
    ((-0.7, -0.7, 0.1), (0, -1, 0)),  # A ポーズの左腕
    ((0.2, 0.9, -0.4), (0.5, -0.3, 0.8)),
]


def is_identity(m):
    n = len(m)
    return all(abs(m[i][j] - (1.0 if i == j else 0.0)) < 1e-6 for i in range(n) for j in range(n))


def r6(x):
    return round(float(x), 6) + 0.0


def q_xyzw(q):
    q = q.normalized()
    return [r6(q.x), r6(q.y), r6(q.z), r6(q.w)]


def drive_name(d):
    k = d[0]
    if k == "spine":
        return f"spine:{d[1]:.4f}"
    if k == "seg":
        return cm.SEGMENTS[d[1]]
    return k


# MARK: - 元のアニメーション

def author_motion(arm, rig):
    """MOTION を 5 フレームのキーにする（Blender のフレーム 1〜5、元のフレーム = Blender のフレーム）。
    姿勢は Blender の骨の basis（ローカル）で置き、評価は Blender に任せる（clip_math の解き方を使わない）。"""
    if not is_identity(arm.matrix_world):
        raise SystemExit("the fixture armature is expected at the origin without rotation")
    sc = bpy.context.scene
    sc.render.fps, sc.render.fps_base = 30, 1.0
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = bpy.data.actions.new("crosscheck")
    for f in range(FRAMES):
        s = f / (FRAMES - 1)
        for b in arm.data.bones:
            pb = arm.pose.bones[b.name]
            pb.rotation_mode = 'QUATERNION'
            role = cm.runtime_role(b.name)
            x = axis_angle(MOTION[role][0], MOTION[role][1] * s) if role in MOTION else Quaternion()
            # ΔR_j = ΔR_親·X_j となる basis: B = R0⁻¹·X·R0（R0 = アーマチュア空間のレストの回転）
            r0 = b.matrix_local.to_quaternion()
            pb.rotation_quaternion = r0.inverted() @ x @ r0
            if role == "hips":
                pb.location = r0.inverted() @ (HIPS_MOVE * s)
            else:
                pb.location = Vector((0, 0, 0))
            pb.scale = Vector((1, 1, 1))
            for path in ("rotation_quaternion", "location", "scale"):
                pb.keyframe_insert(path, frame=f + 1)
    sc.frame_start, sc.frame_end = 1, FRAMES


def source_pose(arm, rig, frame):
    """Blender が評価した元の姿勢（ΔR, P）。"""
    return ec.eval_at(arm, rig, float(frame))


# MARK: - 自己検査

def compare(rig, a, b):
    """(ΔR, P) どうしの最大の差（mm, 度）。"""
    mm = max((pa - pb).length for pa, pb in zip(a[1], b[1])) * 1000.0
    deg = max(cm.quat_angle_deg(qa, qb) for qa, qb in zip(a[0], b[0]))
    return mm, deg


def mirrored_yawed(rig, pose, yaw):
    """左右対称なリグで、姿勢を鏡映（x → -x、左右の骨を入れ替え）し、腰のレスト位置の縦軸回りに ry(yaw) 回したもの。"""
    dR, P = pose
    swap = []
    for name in rig.names:
        other = name.replace("Left", "\0").replace("Right", "Left").replace("\0", "Right")
        swap.append(rig.names.index(other))
    y = cm.ry(yaw)
    c = rig.P0[rig.index["hips"]]
    c = Vector((0.0, c.y, 0.0))

    def mirror_v(v):
        return Vector((-v.x, v.y, v.z))
    dR2 = [y @ cm.mirror_q(dR[swap[i]]) for i in range(len(dR))]
    P2 = [c + y @ mirror_v(P[swap[i]] - c) for i in range(len(P))]
    return dR2, P2


def asymmetry(rig):
    """リグが左右対称でなければ理由（鏡映の自己検査の前提。SkinnedTestHero は対称、生成したヒーローは対称でない）。"""
    for i, name in enumerate(rig.names):
        if "Left" not in name:
            continue
        other = name.replace("Left", "Right")
        if other not in rig.names:
            return f"no {other}"
        j = rig.names.index(other)
        a, b = rig.P0[i], rig.P0[j]
        if (Vector((-a.x, a.y, a.z)) - b).length > 1e-5:
            return f"rest positions differ at {name}"
        if cm.quat_angle_deg(cm.mirror_q(rig.C[i]), rig.C[j]) > 1e-3:
            return f"corrections are not mirror images at {name}"
    return None


# MARK: - 出力

def dump(top, xc):
    """クリップは HeroMotionClips.json と同じ形（1 クリップ 1 行）、検査の表は 1 行 1 要素。"""
    lines = ["{", f'  "version": {top["version"]},', f'  "fps": {top["fps"]},',
             f'  "segments": {json.dumps(top["segments"])},', '  "clips": [']
    for i, c in enumerate(top["clips"]):
        lines.append("    " + json.dumps(c, separators=(",", ":")) + ("," if i + 1 < len(top["clips"]) else ""))
    lines.append("  ],")
    lines.append('  "crosscheck": {')
    keys = list(xc)
    for k, key in enumerate(keys):
        v = xc[key]
        tail = "," if k + 1 < len(keys) else ""
        if isinstance(v, list):
            lines.append(f'    "{key}": [')
            for i, e in enumerate(v):
                lines.append("      " + json.dumps(e, separators=(",", ":"), ensure_ascii=False) + ("," if i + 1 < len(v) else ""))
            lines.append("    ]" + tail)
        else:
            lines.append(f'    "{key}": ' + json.dumps(v, ensure_ascii=False) + tail)
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(a):
    # 表示側のリグ（preview_clip.py の取り込み = 実行時と同じ USD の座標）
    target, _, _, warnings = pc.load_hero(a.fixture)
    for w in warnings:
        log(f"WARNING target: {w}")
    if not is_identity(target.M):
        raise SystemExit("the fixture is expected to import with Y up (hero space = USD coordinates)")

    # 元リグ（extract_clips.py の取り込み・前向きの判定）。表示側と同じファイルなのでレストが一致するはず
    arm, _, _ = ec.import_source(a.fixture)
    source, facing = ec.source_frame(arm, a.fixture)
    log(f"facing {facing['source']} {facing['forwardWorld']}, leg length {source.leg_length:.5f}")
    if source.names != target.names:
        raise SystemExit("source / target bone order differs")
    rest_mm = max((p - q).length for p, q in zip(source.P0, target.P0)) * 1000.0
    rest_c = max(cm.quat_angle_deg(p, q) for p, q in zip(source.C, target.C))
    if rest_mm > 1e-3 or rest_c > 1e-3 or abs(source.leg_length - target.leg_length) > 1e-6:
        raise SystemExit(f"source / target rest differ ({rest_mm} mm, {rest_c}°)")
    asym = asymmetry(target)
    if asym and os.path.normpath(a.fixture) == os.path.normpath(FIXTURE):
        raise SystemExit(f"the fixture rig must be symmetric: {asym}")

    author_motion(arm, source)
    originals = [source_pose(arm, source, f + 1) for f in range(FRAMES)]

    clips = []
    for spec in CLIPS:
        c = dict(spec)
        c["source"] = {"file": a.fixture}
        c["_label"] = "crosscheck:" + os.path.splitext(os.path.basename(a.fixture))[0]
        c["_path"] = a.fixture
        out, rep, ok = ec.extract(c, source, arm, 30.0, (1.0, float(FRAMES)), 0.0)
        v = rep["verify"]
        log(f"{out['name']}: {out['frames']} frames, limb max {v['limbMaxDegrees']}°, events {out['events']}")
        if not ok:
            raise SystemExit(f"{out['name']}: extraction verification failed {v}")
        clips.append(out)

    clips.append(sign_flipped(clips[0], "xc_signs"))
    L = target.leg_length

    def solve(clip, f, rootXZ=None):
        qs, root = cm.interp_clip(clip, f)
        k = clip["rootXZ"] if rootXZ is None else rootXZ
        return target.solve(qs, Vector((root.x * k, root.y, root.z * k)) * L)

    # 自己検査: 抽出 → 実行時の往復（xc_basic）と、反転 + yaw の約束（xc_mirror_yaw）
    by_name = {c["name"]: c for c in clips}
    worst_rt = (0.0, 0.0)
    for f in range(FRAMES):
        mm, deg = compare(target, solve(by_name["xc_basic"], float(f)), originals[f])
        worst_rt = (max(worst_rt[0], mm), max(worst_rt[1], deg))
    # 反転 + yaw は左右対称なリグでだけ確かめられる（対称でなければ鏡映した姿勢がリグの外になる）
    worst_my = (0.0, 0.0)
    my = by_name["xc_mirror_yaw"]
    if asym:
        log(f"mirror+yaw self-check skipped (rig is not symmetric: {asym})")
    else:
        for f in range(my["frames"]):
            want = mirrored_yawed(target, originals[f], spec_of("xc_mirror_yaw")["yaw"])
            mm, deg = compare(target, solve(my, float(f), rootXZ=1.0), want)
            worst_my = (max(worst_my[0], mm), max(worst_my[1], deg))
    worst_sg = (0.0, 0.0)
    for f in SAMPLE_FRAMES["xc_signs"]:
        mm, deg = compare(target, solve(by_name["xc_signs"], f), solve(by_name["xc_basic"], f))
        worst_sg = (max(worst_sg[0], mm), max(worst_sg[1], deg))
    log(f"self-check: round trip {worst_rt[0]:.4f} mm / {worst_rt[1]:.4f}°, mirror+yaw {worst_my[0]:.4f} mm / "
        f"{worst_my[1]:.4f}°, signs {worst_sg[0]:.4f} mm / {worst_sg[1]:.4f}°")
    if max(worst_rt[0], worst_my[0]) > SELF_TOL_MM or max(worst_rt[1], worst_my[1]) > SELF_TOL_DEG \
            or worst_sg[0] > 0.01 or worst_sg[1] > 0.01:
        raise SystemExit("self-check failed")

    joints = []
    for i, name in enumerate(target.names):
        joints.append({"name": name, "role": target.roles[i], "drive": drive_name(target.drive[i]),
                       "position": [r6(v) for v in target.P0[i]], "correction": q_xyzw(target.C[i])})
    samples = []
    for c in clips:
        for f in SAMPLE_FRAMES[c["name"]]:
            dR, P = solve(c, f)
            samples.append({"clip": c["name"], "frame": f, "time": r6(f / 30.0),
                            "positions": [[r6(v) for v in p] for p in P], "rotations": [q_xyzw(q) for q in dR]})
    src = []
    for f, (dR, P) in enumerate(originals):
        src.append({"clip": "xc_basic", "frame": float(f), "time": r6(f / 30.0),
                    "positions": [[r6(v) for v in p] for p in P], "rotations": [q_xyzw(q) for q in dR]})
    rb = []
    for u, v in ROTATION_BETWEEN:
        rb.append({"a": list(map(float, u)), "b": list(map(float, v)), "q": q_xyzw(cm.rotation_between(Vector(u), Vector(v)))})

    xc = {
        "generator": "tools/blender/make_clip_crosscheck.py",
        "rig": os.path.splitext(os.path.basename(a.fixture))[0],
        "legLength": r6(L),
        "toleranceMeters": 0.001,
        "selfCheck": {"roundTripMm": round(worst_rt[0], 4), "roundTripDegrees": round(worst_rt[1], 4),
                      "mirrorYawMm": None if asym else round(worst_my[0], 4),
                      "mirrorYawDegrees": None if asym else round(worst_my[1], 4)},
        "rotationBetween": rb,
        "joints": joints,
        "samples": samples,
        "source": src,
    }
    top = {"version": 1, "fps": ec.OUT_FPS, "segments": cm.SEGMENTS, "clips": clips}
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    tmp = a.out + ".tmp"
    with open(tmp, "w") as fh:
        fh.write(dump(top, xc))
    os.replace(tmp, a.out)
    log(f"wrote {a.out} ({len(samples)} samples, {len(joints)} joints, {os.path.getsize(a.out)} bytes)")


def sign_flipped(clip, name):
    """clip の四元数を (フレーム + 区間) が奇数のところだけ -q にしたクリップ（腰と胴、胴と頭が毎フレーム逆の符号になる）。"""
    out = dict(clip, name=name)
    rot = list(clip["rot"])
    S = len(cm.SEGMENTS)
    for f in range(clip["frames"]):
        for s in range(S):
            if (f + s) % 2:
                k = (f * S + s) * 4
                rot[k:k + 4] = [-v + 0.0 for v in rot[k:k + 4]]
    out["rot"] = rot
    return out


def spec_of(name):
    return next(c for c in CLIPS if c["name"] == name)


if __name__ == "__main__":
    main(parse())
