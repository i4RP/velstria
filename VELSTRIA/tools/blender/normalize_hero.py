# 担当: hero-assets。Tripo 自動リグ GLB（Mixamo 仕様）を実行時用 USDZ に正規化する。
#   Meshy 自動リグ（tools/meshy.mjs。骨名は Mixamo に近いが背骨が Spine02/Spine01/Spine）は骨名を Mixamo 名へ付け替えてから扱う。
# 使い方: Blender -b --factory-startup --python-exit-code 1 --python normalize_hero.py -- \
#   --in rigged.glb|rigged.fbx --out Hero_H001.usdz [--height 1.7] [--texture-size 1024] [--max-faces 12000]
#   [--forward auto|+x|-x|+z|-z] [--report report.json]
# 出力: Y-up・メートル・-Z 向き（右手側 +X）・足元 y=0・腰が水平原点・身長 --height の UsdSkel。
#   レストは T ポーズでも A ポーズ（Tripo の Mixamo リグは腕が約 60° 下がる）でもよい。実行時（HeroSkeletonRig）が
#   骨ごとのレスト方向を補正する。腕の下がり角はレポートの armDownDegrees。
# 向き: auto はつま先（ToeBase - Foot）の平均、つま先が無ければ腕・脚の左右（上 × (Right - Left)）。--forward は glTF 軸で指定。
#   つま先が左右そろって水平に近く互いに 45° 以内なら「確か」。確かでないつま先と腕・脚が 45° 超食い違えば失敗。
# 検査（失敗なら終了コード 1、レポートの errors に理由を書き、出力は残さない）:
#   - 必須の骨: 実行時（HeroSkeletonRig の HeroJointRole.required・normalize）と同じ規則で、書き出し前の骨名と
#     書き出し後の USD の joints の両方を調べる
#   - 左右: 正面を -Z へ回した後で Right* の骨が +X 側にある（逆なら左右の名前が入れ替わったリグか鏡像のメッシュ）
#   - 向き: 上記のつま先と腕・脚の食い違い
#   - スキン: HeroPose が曲げる骨（WEIGHT_ROLES）がどれも 1 頂点以上を支配し、1 本の骨が頂点の半分以上を支配しない
#   - 骨の位置: 主要な骨がメッシュの外接箱（5% の余白）の内側、腰・頭・足がメッシュ高さの妥当な割合にある
#   Tripo の GLB は骨とメッシュの軸・縮尺が食い違うものや、全頂点が Hips に 100% 乗るダミーのスキンで届いたことがある。
#   その場合は同じリグの FBX を --in rigged.fbx で渡す。

import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import norm_common as nc  # noqa: E402

# glTF 軸 -> Blender 軸（glTF 取り込みは (x, y, z) -> (x, -z, y)）
GLTF_DIR_TO_BLENDER = {
    "+x": Vector((1, 0, 0)), "-x": Vector((-1, 0, 0)),
    "+z": Vector((0, -1, 0)), "-z": Vector((0, 1, 0)),
}
# USD で -Z を向く = 書き出し前の Blender 空間で +Y を向く（norm_common.BLENDER_TO_USD）
TARGET_FORWARD = Vector((0, 1, 0))
SNAP_DEG = 20.0
HERO_BYTES_WARN = 1_500_000


def parse():
    p = argparse.ArgumentParser(prog="normalize_hero.py")
    p.add_argument("--in", dest="inp", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--height", type=float, default=1.7)
    p.add_argument("--texture-size", type=int, default=1024)
    p.add_argument("--max-faces", type=int, default=12000)
    p.add_argument("--forward", default="auto", choices=["auto", "+x", "-x", "+z", "-z"])
    p.add_argument("--report", default="")
    return p.parse_args(nc.script_args())


def find_rig():
    arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
    if not arms:
        raise SystemExit("no armature in input")

    def skinned_by(arm):
        out = []
        for o in bpy.data.objects:
            if o.type != 'MESH':
                continue
            if any(m.type == 'ARMATURE' and m.object == arm for m in o.modifiers):
                out.append(o)
        return out

    arm = max(arms, key=lambda a: (len(skinned_by(a)), len(a.data.bones)))
    meshes = skinned_by(arm)
    if not meshes:
        raise SystemExit("no skinned mesh bound to the armature")
    return arm, meshes


def bone_lookup(arm):
    return {nc.canonical_bone(b.name): b for b in arm.data.bones}


def bone_head(arm, bones, key):
    b = bones.get(key)
    return arm.matrix_world @ b.head_local if b else None


FACING_AGREE_DEG = 45.0
TOE_MIN_HORIZONTAL = 0.5   # つま先の骨（Foot -> ToeBase）の水平成分 / 長さ の下限


def angle_deg(u, v):
    return math.degrees(math.acos(max(-1.0, min(1.0, u.normalized().dot(v.normalized())))))


def toe_dirs(arm, bones):
    """左右それぞれの Foot -> ToeBase の水平方向（水平成分が小さい骨は None）。骨が無い側は含めない。"""
    out = {}
    for side in ("left", "right"):
        foot = bone_head(arm, bones, side + "foot")
        toe = bone_head(arm, bones, side + "toebase") or bone_head(arm, bones, side + "toe")
        if foot is None or toe is None:
            continue
        d = toe - foot
        full = d.length
        d.z = 0
        out[side] = d.normalized() if full > 1e-6 and d.length >= TOE_MIN_HORIZONTAL * full else None
    return out


def detect_forward(arm, flag):
    """(前向き（Blender 空間の水平ベクトル）, 取得元, 報告用の dict, エラー文の配列)。"""
    bones = bone_lookup(arm)
    arms = arms_forward(bones)
    toes = toe_dirs(arm, bones)
    dirs = [d for d in toes.values() if d is not None]
    acc = sum(dirs, Vector((0, 0, 0)))
    spread = angle_deg(dirs[0], dirs[1]) if len(dirs) == 2 else None
    reliable = len(dirs) == 2 and spread <= FACING_AGREE_DEG
    info = {"toes": len(toes), "toesSpreadDegrees": None if spread is None else round(spread, 1),
            "armsVsToesDegrees": None, "reliable": reliable}
    if acc.length > 1e-3 and arms is not None:
        info["armsVsToesDegrees"] = round(angle_deg(acc, arms), 1)
    if flag != "auto":
        info["reliable"] = True
        return GLTF_DIR_TO_BLENDER[flag].copy(), "flag", info, []
    if dirs:
        disagree = arms is not None and (acc.length <= 1e-3 or info["armsVsToesDegrees"] > FACING_AGREE_DEG)
        if not reliable and (disagree or arms is None):
            why = (f"{len(toes)} toe bone(s), {len(dirs)} horizontal" + (f", {spread:.0f}° apart" if spread is not None else ""))
            off = info["armsVsToesDegrees"]
            if arms is None:
                vs = "the arm/leg bones are missing"
            elif off is None:
                vs = "the toes point in opposite directions"
            else:
                vs = f"the arms/legs disagree by {off:.0f}°"
            return (arms if arms is not None else Vector((1, 0, 0))), "ambiguous", info, [
                f"facing is ambiguous: the toes are unreliable ({why}) and {vs}; "
                f"check the rig or pass --forward +x|-x|+z|-z"]
        if acc.length > 1e-3:
            acc.z = 0
            if disagree:
                nc.warn(f"toes and arms disagree on the facing direction ({info['armsVsToesDegrees']:.0f}°): using toes")
            return acc.normalized(), "toes", info, []
    if arms is not None:
        return arms, "arms", info, []
    return GLTF_DIR_TO_BLENDER["+x"].copy(), "default", info, ["facing could not be established (no toe, arm or leg bones)"]


def arms_forward(bones_by_role):
    """つま先の骨が無いときの前向き: 上 × 右（Right* の骨が体の右側にある Mixamo の規約から）。"""
    acc = Vector((0, 0, 0))
    for r, l in (("rightarm", "leftarm"), ("rightupleg", "leftupleg"), ("rightshoulder", "leftshoulder")):
        br, bl = bones_by_role.get(r), bones_by_role.get(l)
        if br is not None and bl is not None:
            acc += br.head_local - bl.head_local
    acc.z = 0
    if acc.length < 1e-6:
        return None
    return Vector((0, 0, 1)).cross(acc.normalized()).normalized()


def yaw_to_target(fwd):
    """fwd を TARGET_FORWARD へ回す Z 軸回りの角度（90° 単位に近ければスナップ）。"""
    ang = math.atan2(TARGET_FORWARD.y, TARGET_FORWARD.x) - math.atan2(fwd.y, fwd.x)
    deg = math.degrees(ang)
    snapped = round(deg / 90.0) * 90.0
    if abs(deg - snapped) <= SNAP_DEG:
        deg = snapped
    return math.radians(deg), deg


def rest_deviation(mesh):
    """レストポーズでアーマチュア評価後の頂点とバインド頂点の最大ずれ。"""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    em = ev.to_mesh()
    orig = mesh.data.vertices
    dev = 0.0
    if len(em.vertices) == len(orig):
        mw = mesh.matrix_world
        for a, b in zip(em.vertices, orig):
            dev = max(dev, ((mw @ a.co) - (mw @ b.co)).length)
    else:
        dev = float("inf")
    ev.to_mesh_clear()
    return dev


def rebind(mesh, arm):
    """バインドとレストが食い違う入力: 現在の変形結果を新しいバインド形状として焼き直す。"""
    mod = next(m for m in mesh.modifiers if m.type == 'ARMATURE')
    nc.select_only([mesh])
    bpy.ops.object.modifier_copy(modifier=mod.name)
    bpy.ops.object.modifier_move_to_index(modifier=mesh.modifiers[-1].name, index=0)
    bpy.ops.object.modifier_apply(modifier=mesh.modifiers[0].name)


# HeroPose が曲げる骨。どれかが 1 頂点も支配していなければダミーのスキン（全頂点 Hips 100% など）とみなす。
WEIGHT_ROLES = ("head", "leftarm", "leftforearm", "rightarm", "rightforearm",
                "leftupleg", "leftleg", "rightupleg", "rightleg")
MAX_DOMINANT_SHARE = 0.5
# メッシュの外接箱の内側にあるべき骨（余白はメッシュ高さの BOUND_PAD）
BOUND_ROLES = ("hips", "spine", "head", "leftarm", "leftforearm", "lefthand", "rightarm", "rightforearm",
               "righthand", "leftupleg", "leftleg", "leftfoot", "rightupleg", "rightleg", "rightfoot")
BOUND_PAD = 0.05
# (骨, 足元からの高さ / メッシュ高さ の下限, 上限)
HEIGHT_FRACTIONS = (("hips", 0.3, 0.75), ("head", 0.55, 1.0), ("leftfoot", -0.05, 0.25), ("rightfoot", -0.05, 0.25))
ARM_DOWN_RANGE = (-5.0, 70.0)


def weight_coverage(mesh, arm):
    """頂点ごとに最大ウェイトの変形骨を数える。(骨名 -> 頂点数, ウェイト無し頂点数)。"""
    deform = {b.name for b in arm.data.bones if b.use_deform}
    names = {g.index: g.name for g in mesh.vertex_groups if g.name in deform}
    hist, unweighted = {}, 0
    for v in mesh.data.vertices:
        best, bw = None, 0.0
        for g in v.groups:
            if g.weight > bw and g.group in names:
                best, bw = names[g.group], g.weight
        if best is None:
            unweighted += 1
        else:
            hist[best] = hist.get(best, 0) + 1
    return hist, unweighted


def check_weights(mesh, arm):
    """(報告用の dict, エラー文の配列)。"""
    hist, unweighted = weight_coverage(mesh, arm)
    total = max(1, len(mesh.data.vertices))
    by_role = {}
    for name, n in hist.items():
        key = nc.canonical_bone(name)
        by_role[key] = by_role.get(key, 0) + n
    present = {nc.canonical_bone(b.name) for b in arm.data.bones}
    dead = [r for r in WEIGHT_ROLES if r in present and by_role.get(r, 0) == 0]
    top_name, top = max(hist.items(), key=lambda kv: kv[1]) if hist else ("", 0)
    nc.log(f"weights: {len(hist)} dominant bones, top {top_name} {top}/{total}, unweighted {unweighted}")
    errs = []
    if dead or top > MAX_DOMINANT_SHARE * total:
        errs.append(f"skin weights look like a dummy bind: top {top_name} {top}/{total} vertices, "
                    f"no vertices dominated by {dead}")
    if unweighted:
        nc.warn(f"{unweighted}/{total} vertices have no deform weight (they will not follow the skeleton)")
    top10 = dict(sorted(hist.items(), key=lambda kv: -kv[1])[:10])
    return {"dominantBones": len(hist), "top": top10, "unweighted": unweighted, "vertices": total}, errs


def check_bone_placement(arm, mesh):
    """骨とメッシュの食い違い（軸・縮尺のずれたスキン）。正規化後（Z 上・足元 0）に呼ぶ。エラー文の配列。"""
    errs = []
    lo, hi = nc.bbox(nc.world_verts(mesh))
    h = hi.z - lo.z
    pad = BOUND_PAD * h
    bones = bone_lookup(arm)
    for k in BOUND_ROLES:
        p = bone_head(arm, bones, k)
        if p is not None and any(p[i] < lo[i] - pad or p[i] > hi[i] + pad for i in range(3)):
            # Blender -> USD の (x, z, -y) で表示
            errs.append(f"bone {k} at ({p.x:.3f}, {p.z:.3f}, {-p.y:.3f}) is outside the mesh bounds "
                        f"({lo.x:.3f}..{hi.x:.3f}, {lo.z:.3f}..{hi.z:.3f}, {-hi.y:.3f}..{-lo.y:.3f})")
    for k, a, b in HEIGHT_FRACTIONS:
        p = bone_head(arm, bones, k)
        if p is not None and not (a <= (p.z - lo.z) / h <= b):
            errs.append(f"bone {k} at {(p.z - lo.z) / h:.2f} of the mesh height (expected {a}..{b})")
    return errs


def arm_down_degrees(arm):
    """肩（Arm）から手首（Hand、無ければ ForeArm）への向きの、水平からの下がり角（度）。T ポーズ ≈ 0、Tripo ≈ 60。"""
    bones = bone_lookup(arm)
    out = {}
    for side, key in (("left", "L"), ("right", "R")):
        s = bone_head(arm, bones, side + "arm")
        e = bone_head(arm, bones, side + "hand") or bone_head(arm, bones, side + "forearm")
        if s is None or e is None or (e - s).length < 1e-6:
            continue
        d = e - s
        out[key] = round(math.degrees(math.atan2(-d.z, math.hypot(d.x, d.y))), 2)
    return out


def missing_text(missing, names):
    leaves = sorted({n.split("/")[-1] for n in names})
    return (f"missing required joint(s) for the runtime (HeroSkeletonRig): {missing}; joint names are matched by the last "
            f"path component, case-insensitive, after an optional 'mixamorig[N]:' / 'mixamorig[N]_' prefix "
            f"(have {len(leaves)}: {', '.join(leaves[:12])}{' ...' if len(leaves) > 12 else ''})")


REPORTED = False


def reject(a, errors, **fields):
    """errors をログとレポートに書き、終了コード 1 で終わる（出力ファイルは書かない・消す）。"""
    global REPORTED
    REPORTED = True
    for e in errors:
        nc.log("ERROR: " + e)
    if a.report:
        nc.write_report({"input": os.path.abspath(a.inp), "output": None, "errors": errors, **fields}, a.report)
    skin = any(("dummy bind" in e) or ("outside the mesh bounds" in e) or ("of the mesh height" in e) for e in errors)
    hint = " (skeleton and mesh disagree: re-rig, or pass the FBX of the same rig with --in rigged.fbx)" if skin else ""
    raise SystemExit("rejected: " + "; ".join(errors[:3]) + (f" (+{len(errors) - 3} more)" if len(errors) > 3 else "") + hint)


def main(a):
    nc.reset_scene()
    nc.import_glb(a.inp)
    arm, meshes = find_rig()
    nc.log(f"armature={arm.name} bones={len(arm.data.bones)} skinned={[m.name for m in meshes]}")
    # Meshy の自動リグは背骨の名前の付き方が Mixamo と逆向き（norm_common.MESHY_TO_MIXAMO）→ Mixamo 名へ付け替える
    renames = nc.rename_meshy_bones(arm)
    if renames:
        nc.log(f"Meshy rig: renamed joints {renames}")
    # 実行時の骨名の規則で必須の骨を確かめる（書き出し時の名前の置換を見込む。書き出し後にも USD の joints で再確認）
    missing = nc.missing_runtime_joints([nc.usd_safe_name(b.name) for b in arm.data.bones])
    if missing:
        reject(a, [missing_text(missing, [b.name for b in arm.data.bones])])

    # レストポーズに戻し、親（scale 0.01 のルート等）を外して不要物を消す
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    arm.data.pose_position = 'POSE'
    nc.unparent_keep(arm)
    for m in meshes:
        nc.unparent_keep(m)
        for mod in m.modifiers:
            if mod.type == 'ARMATURE':
                mod.object = arm
    nc.delete_except([arm] + meshes)
    nc.apply_transforms([arm] + meshes)
    mesh = nc.join_meshes(meshes)
    mesh.name = "Body"
    mesh.data.name = "Body"
    arm_mods = [m for m in mesh.modifiers if m.type == 'ARMATURE']
    for extra in arm_mods[1:]:
        mesh.modifiers.remove(extra)
    for m in list(mesh.modifiers):
        if m.type != 'ARMATURE':
            mesh.modifiers.remove(m)
    if mesh.data.shape_keys:
        nc.select_only([mesh])
        bpy.ops.object.shape_key_remove(all=True, apply_mix=False)

    dev_import = rest_deviation(mesh)
    rebound = False
    if dev_import > 1e-4 * max(1.0, max(arm.dimensions)):
        nc.log(f"rest/bind mismatch {dev_import:.5f}: rebinding")
        rebind(mesh, arm)
        rebound = True

    # 向き
    fwd, src, facing, errors = detect_forward(arm, a.forward)
    yaw, yaw_deg = yaw_to_target(fwd)
    rot = Matrix.Rotation(yaw, 4, 'Z')
    for o in (arm, mesh):
        o.matrix_world = rot @ o.matrix_world
    nc.apply_transforms([arm, mesh])

    # 身長・足元・腰の水平原点
    lo, hi = nc.bbox(nc.world_verts(mesh))
    src_height = hi.z - lo.z
    if src_height <= 1e-6:
        raise SystemExit("degenerate mesh height")
    s = a.height / src_height
    bones = bone_lookup(arm)
    hips = bone_head(arm, bones, "hips")
    if hips is None:
        hips = (lo + hi) * 0.5
        nc.log("hips bone not found: using bbox center")
    xf = Matrix.Diagonal((s, s, s, 1.0))
    xf = Matrix.Translation((-hips.x * s, -hips.y * s, -lo.z * s)) @ xf
    for o in (arm, mesh):
        o.matrix_world = xf @ o.matrix_world
    nc.apply_transforms([arm, mesh])

    # 再親子付け（両方単位行列なので親逆行列も単位）
    mesh.parent = arm
    mesh.matrix_parent_inverse = Matrix.Identity(4)

    open_before = nc.boundary_edges(mesh)
    decimated = nc.decimate(mesh, a.max_faces)
    open_after = nc.boundary_edges(mesh) if decimated else open_before
    if open_after > max(64, 2 * open_before):
        nc.warn(f"decimation opened seams: boundary edges {open_before} -> {open_after}")
    # 左右: 正面を -Z へ回した後で Right* の骨が +X 側にあるか（書き出しの軸変換は X を変えない）
    bones = bone_lookup(arm)
    rx = [bone_head(arm, bones, k).x for k in ("rightarm", "rightupleg", "righthand") if k in bones]
    lx = [bone_head(arm, bones, k).x for k in ("leftarm", "leftupleg", "lefthand") if k in bones]
    right_ok = bool(rx and lx and sum(rx) / len(rx) > sum(lx) / len(lx))
    if not right_ok:
        errors.append(f"mirrored rig: after facing -Z (from {src}) the Right* bones are not on +X "
                      f"(mean x right={sum(rx) / max(1, len(rx)):.3f} left={sum(lx) / max(1, len(lx)):.3f}); "
                      f"the left/right bone names are swapped or the mesh is mirrored (or pass --forward if the facing is wrong)")
    weight_cov, more = check_weights(mesh, arm)
    errors += more
    errors += check_bone_placement(arm, mesh)
    arm_down = arm_down_degrees(arm)
    for k, v in arm_down.items():
        if not ARM_DOWN_RANGE[0] <= v <= ARM_DOWN_RANGE[1]:
            nc.warn(f"arm {k} rests {v}° below horizontal (expected T/A pose {ARM_DOWN_RANGE[0]}..{ARM_DOWN_RANGE[1]})")
    if errors:
        reject(a, errors, weightCoverage=weight_cov, armDownDegrees=arm_down, facing=facing, forwardSource=src,
               rightSideAtPlusX=right_ok, sourceHeight=round(src_height, 5), scale=round(s, 6))
    dev_final = rest_deviation(mesh)

    lo, hi = nc.bbox(nc.world_verts(mesh))
    hips = bone_head(arm, bones, "hips") or Vector((0, 0, 0))
    joints = [b.name for b in arm.data.bones]
    faces = nc.tri_count(mesh)
    verts = len(mesh.data.vertices)

    textures = nc.export_usdz([arm, mesh], a.out, skinned=True, texture_size=a.texture_size)
    # 書き出し後の USD の joints（RealityKit の jointNames）を実行時の規則で再確認する
    skels = nc.usd_skeleton_joints(a.out)
    usd_missing = nc.missing_runtime_joints(skels[0]) if len(skels) == 1 else list(nc.RUNTIME_REQUIRED)
    if len(skels) != 1 or usd_missing:
        os.remove(a.out)
        reject(a, [f"exported USD has {len(skels)} skeleton(s) (expected 1)" if len(skels) != 1
                   else missing_text(usd_missing, skels[0])], forwardSource=src, rightSideAtPlusX=right_ok)
    report = {
        "input": os.path.abspath(a.inp),
        "output": os.path.abspath(a.out),
        "faces": faces,
        "vertices": verts,
        "jointRenames": renames,
        "joints": joints,
        "jointCount": len(joints),
        "height": round(hi.z - lo.z, 5),
        "minHeight": round(lo.z, 5),
        "hipsHorizontal": [round(hips.x, 5), round(-hips.y, 5)],
        "sourceHeight": round(src_height, 5),
        "scale": round(s, 6),
        "forwardSource": src,
        "forwardDetectedGltf": [round(fwd.x, 4), round(fwd.z, 4), round(-fwd.y, 4)],
        "yawDegrees": round(yaw_deg, 3),
        "rightSideAtPlusX": right_ok,
        "facing": facing,
        "requiredJoints": list(nc.RUNTIME_REQUIRED),
        "restDeviationImport": round(dev_import, 6),
        "restDeviationFinal": round(dev_final, 6),
        "rebound": rebound,
        "weightCoverage": weight_cov,
        "armDownDegrees": arm_down,
        "boundaryEdges": {"beforeDecimate": open_before, "after": open_after},
        "textures": textures,
        "materials": [m.name for m in mesh.data.materials if m],
        "bytes": os.path.getsize(a.out),
    }
    if report["bytes"] > HERO_BYTES_WARN:
        nc.warn(f"USDZ is {report['bytes']} bytes (budget about {HERO_BYTES_WARN}); try --texture-size 512")
    nc.write_report(report, a.report)


if __name__ == "__main__":
    args = parse()
    try:
        main(args)
    except BaseException as e:
        # reject() を通らない失敗（入力が読めない・アーマチュアが無い・想定外の例外）もレポートの errors に残す
        if not REPORTED and args.report and not (isinstance(e, SystemExit) and e.code in (None, 0)):
            nc.write_report({"input": os.path.abspath(args.inp), "output": None,
                             "errors": [str(e) or type(e).__name__]}, args.report)
        raise
