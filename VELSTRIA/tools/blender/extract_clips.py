# 担当: hero-motion。Meshy のアニメーション GLB からモーションクリップ（区間回転、docs/HERO_MOTION.md）を抜き出し、
# App/Resources/Heroes/HeroMotionClips.json を書く（Blender 5.2 headless）。
# 使い方（VELSTRIA/ で）:
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
#     --python tools/blender/extract_clips.py -- --spec tools/heroref/clips.json --anim-dir build/meshy/anim \
#     --out App/Resources/Heroes/HeroMotionClips.json --report build/heroref/clips_report.json [--only run_basic,walk_basic]
#   --only を付けると出力の既存の JSON のうち指定したクリップだけを差し替える（他のクリップは残す）。
#   付けなければ仕様のクリップだけで書き直す。検証に落ちたクリップが 1 つでもあれば出力を書かずに終了コード 1。
#
# 仕様ファイル（tools/heroref/clips.json）:
#   { "version": 1, "clips": [ { ... }, ... ] }   （"$comment" などの "$" で始まるキーは無視）
#   クリップ（出力の順 = 仕様の順）:
#     name     必須。英数字と "_"。出力のクリップ名（実行時はこの名前で引く）。重複不可。
#     source   必須。次のどれか:
#                {"rig": "H002", "action_id": 97}   build/meshy/anim/<rig>/manifest.json（tools/meshy.mjs anim が書く
#                                                   {"<action_id>": {"file", "clip_index", "name", ...}}）で GLB とクリップを引く
#                {"rig": "H002", "file": "basic_running.glb"[, "clip_index": 0]}   <anim-dir>/<rig>/ の GLB を直接
#                {"file": "App/Resources/Heroes/Hero_H001.usdz", "rest": true}       "/" を含む file はカレントからのパス
#              "rest": true はアニメーションを使わず、レスト（バインド）姿勢 1 フレームのクリップにする（検証用。USD はこれだけ）。
#              "clip_index" は GLB の animations の添字（省略時はクリップが 1 つだけの GLB に限る）。
#     start, end  元のフレーム = アニメーションの最初のキーを 1 とし、キーの間隔（fps、Meshy は 30）ごとに +1（Meshy の
#              表示と同じ 1 始まり）。最初のキーの glTF の時刻は GLB で違う（自動リグの basic_*.glb は 1/30 秒、animations
#              API の batch_*.glb は 0 秒）ので、Blender のフレームではなく最初のキーからの番号にそろえる
#              （レポートの sourceFrameRange = [1, 最後のキー]、actionFrameRange は Blender のフレーム）。
#              loop: [start, end) の半開区間（end は 1 周後 = start と同じ姿勢のフレーム。Meshy のループは多くが最後のキーが
#              最初のキーと同じなので、既定の end = 最後のキー でちょうど 1 周。違うものはレポートの loopSeamDegrees で分かる）。
#              loop でない: [start, end] の閉区間（既定は最初のキー〜最後のキー）。
#              小数可（キーの間は Blender の補間で評価する）。キーの外（start < 1、end > 最後のキー。loop は最後のキー + 1 まで可）
#              は姿勢が止まるので警告する。
#     loop     既定 false。出力の "loop"。
#     mirror   既定 false。左右反転（R/L の区間を入れ替え、回転を YZ 平面で鏡映、root の x を反転）。
#     yaw      既定 0（度）。全区間に ry(yaw) を左から掛け、root も回す（反転の後）。正で正面 -Z が左手 -X 側へ回る
#              （上から見て反時計回り）。打撃の向きを正面へ合わせる。
#     rootXZ   既定 0（0〜1）。出力の "rootXZ"（実行時に腰の水平のずれへ掛ける）。
#     inPlace  既定 = loop。区間の始め → 終わりの腰の水平のずれ（root motion）を線形に差し引く（ループの継ぎ目で腰が飛ばない）。
#     events   既定 {}。{"impact": 元のフレーム, ...}。出力ではクリップ先頭からの出力フレーム（30 fps、小数 2 桁）。
#     note     任意のメモ（出力しない）。
#   出力は 30 fps に再標本化する（loop: N = round((end - start)·30/fps) 個を [start, end) に等間隔、
#   それ以外: N = round((end - start)·30/fps) + 1 個を [start, end] に等間隔）。
#
# 処理: GLB をアニメーション付きで取り込み（glTF の時刻 × fps が Blender のフレームになるよう先にシーンの fps を合わせる）、
#   Meshy の骨は norm_common.MESHY_TO_MIXAMO で Mixamo 名として読む（骨そのものは改名しない。アクションの経路を壊さない）。
#   レスト = アーマチュアのバインド姿勢（glTF の inverse bind matrices。edit bone の matrix_local）で、アクションの
#   フレーム 0 ではない。前向きはレストのつま先（無ければ腕・脚の左右）から決める（clip_math.detect_facing）。
#   フレームごとに Q_s = ΔR_j·C_j⁻¹、root = (P_Hips - P0_Hips)/L を求め、inPlace → mirror → yaw → 符号の連続化 → 小数 4 桁。
# 検証（毎回・全クリップ）: 書き出す値（丸めた後）から yaw・mirror・inPlace を戻し、元リグに実行時と同じ計算
#   （clip_math.Rig.solve = HeroSkeletonPoser.solve）で載せ、四肢（上腕・前腕・手・腿・脛・足）の向き（次の関節へのベクトル）が
#   元のアニメーションと 1° 以内で一致することを確かめる。区間の骨の回転そのもの・腰の位置の誤差もレポートに書く。
#   反転・回転は戻してから比べる（反転したクリップを元リグの反対側へ載せると、左右のレスト補正の「ほぼ平行なら単位」の
#   丸め（Swift の rotationBetween、最大 0.81°）が誤差に混ざり、抽出の誤りと区別できないため）。
# レストの往復の確認（座標変換・C・丸め・表示側の解き方をまとめて確かめる）:
#   仕様 {"clips": [{"name": "rest_h001", "source": {"file": "App/Resources/Heroes/Hero_H001.usdz", "rest": true}}]} を
#   build/ の別ファイルへ抜き出し、preview_clip.py --clips <それ> --clip rest_h001 --hero H001 --frames 1 --check-rest
#   （四肢の向きが H001 自身のレストと 0.05° 以内で一致すれば合格）。

import argparse
import json
import math
import os
import re
import struct
import sys

import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clip_math as cm  # noqa: E402
import norm_common as nc  # noqa: E402

OUT_FPS = 30
LIMB_MAX_DEG = 1.0
LOOP_SEAM_WARN_DEG = 5.0
CLIP_KEYS = {"name", "source", "start", "end", "loop", "mirror", "yaw", "rootXZ", "inPlace", "events", "note"}
SOURCE_KEYS = {"rig", "action_id", "file", "clip_index", "rest"}
WARNINGS = []


def log(msg):
    print(f"[clips] {msg}", flush=True)


def warn(msg):
    log("WARNING: " + msg)
    WARNINGS.append(msg)


def parse():
    p = argparse.ArgumentParser(prog="extract_clips.py")
    p.add_argument("--spec", required=True)
    p.add_argument("--anim-dir", default="build/meshy/anim")
    p.add_argument("--out", required=True)
    p.add_argument("--report", default="")
    p.add_argument("--only", default="")
    return p.parse_args(nc.script_args())


# MARK: - 仕様

def is_num(v):
    """数値か（bool は int の派生なので除く。true が 1 として通らないように）。"""
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def load_spec(path):
    with open(path) as f:
        spec = json.load(f)
    clips = spec.get("clips") if isinstance(spec, dict) else None
    if not isinstance(clips, list) or not clips:
        raise SystemExit(f"{path}: 'clips' must be a non-empty array")
    errs, seen = [], set()
    for i, c in enumerate(clips):
        where = f"clips[{i}]" + (f" ({c.get('name')})" if isinstance(c, dict) and c.get("name") else "")
        if not isinstance(c, dict):
            errs.append(f"{where}: not an object")
            continue
        unknown = [k for k in c if k not in CLIP_KEYS and not k.startswith("$")]
        if unknown:
            errs.append(f"{where}: unknown keys {unknown}")
        name = c.get("name")
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_]+", name):
            errs.append(f"{where}: name must match [A-Za-z0-9_]+")
        elif name in seen:
            errs.append(f"{where}: duplicate name")
        seen.add(name)
        src = c.get("source")
        if not isinstance(src, dict):
            errs.append(f"{where}: source must be an object")
        else:
            bad = [k for k in src if k not in SOURCE_KEYS]
            if bad:
                errs.append(f"{where}: unknown source keys {bad}")
            if ("action_id" in src) == ("file" in src):
                errs.append(f"{where}: source needs exactly one of action_id / file")
            if "action_id" in src and "rig" not in src:
                errs.append(f"{where}: source.action_id needs source.rig")
            if "file" in src and "/" not in src["file"] and "rig" not in src:
                errs.append(f"{where}: source.file without '/' needs source.rig")
        for k in ("start", "end", "yaw", "rootXZ"):
            if k in c and not is_num(c[k]):
                errs.append(f"{where}: {k} must be a number")
        for k in ("loop", "mirror", "inPlace"):
            if k in c and not isinstance(c[k], bool):
                errs.append(f"{where}: {k} must be a boolean")
        if is_num(c.get("rootXZ", 0.0)) and not 0.0 <= float(c.get("rootXZ", 0.0)) <= 1.0:
            errs.append(f"{where}: rootXZ must be within 0..1")
        ev = c.get("events", {})
        if not isinstance(ev, dict) or any(not is_num(v) for v in ev.values()):
            errs.append(f"{where}: events must be {{name: source frame}}")
    if errs:
        raise SystemExit("invalid spec:\n  " + "\n  ".join(errs))
    return clips


def read_manifest(anim_dir, rig):
    path = os.path.join(anim_dir, rig, "manifest.json")
    if not os.path.isfile(path):
        raise SystemExit(f"manifest not found: {path} (run: node tools/meshy.mjs anim --rig {rig} --actions ...)")
    with open(path) as f:
        m = json.load(f)
    # tools/meshy.mjs の形 {"<action_id>": {...}}。配列・"actions" の下に置いた形も読む
    if isinstance(m, dict) and isinstance(m.get("actions"), (list, dict)):
        m = m["actions"]
    if isinstance(m, dict):
        return {str(k): v for k, v in m.items() if isinstance(v, dict)}
    if isinstance(m, list):
        return {str(e.get("action_id", e.get("id"))): e for e in m if isinstance(e, dict)}
    raise SystemExit(f"{path}: unexpected manifest format")


def resolve_source(src, anim_dir):
    """(ファイルのパス, clip_index | None, 出力の source 文字列)。"""
    if "action_id" in src:
        m = read_manifest(anim_dir, src["rig"])
        e = m.get(str(src["action_id"]))
        if e is None:
            raise SystemExit(f"action {src['action_id']} is not in {anim_dir}/{src['rig']}/manifest.json "
                             f"(have {sorted(m, key=lambda s: (len(s), s))[:20]})")
        path = os.path.join(anim_dir, src["rig"], str(e["file"]))
        idx = e.get("clip_index", src.get("clip_index"))
        return path, (None if idx is None else int(idx)), f"meshy:{src['action_id']}"
    f = src["file"]
    path = f if "/" in f else os.path.join(anim_dir, src["rig"], f)
    label = os.path.splitext(os.path.basename(f))[0]
    if src.get("rest"):
        label += ":rest"
    return path, src.get("clip_index"), f"meshy:{src['rig']}/{label}" if "rig" in src else f"file:{label}"


# MARK: - 取り込み

def gltf_json(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] == b"glTF":
        n = struct.unpack("<I", data[12:16])[0]
        return json.loads(data[20:20 + n])
    return json.loads(data)


def gltf_key_fps(g):
    """アニメーションごとのキーの間隔から求めた fps（時刻の accessor の min/max と個数。glTF では min/max が必須）。"""
    out = []
    for an in g.get("animations", []):
        best = None
        for s in an.get("samplers", []):
            acc = g["accessors"][s["input"]]
            if acc.get("count", 0) > 1 and "min" in acc and "max" in acc:
                cand = (acc["count"], acc["min"][0], acc["max"][0])
                best = cand if best is None or cand[0] > best[0] else best
        if best and best[2] > best[1]:
            out.append((best[0] - 1) / (best[2] - best[1]))
        else:
            out.append(None)
    return out


def set_scene_fps(fps):
    sc = bpy.context.scene
    r = round(fps)
    if abs(fps - r) < 0.05:
        sc.render.fps, sc.render.fps_base = int(r), 1.0
    else:
        sc.render.fps = int(math.ceil(fps))
        sc.render.fps_base = sc.render.fps / fps


def import_source(path):
    """シーンを空にして取り込む。(アーマチュア, glTF の JSON | None, ファイルの fps | None)。"""
    if not os.path.isfile(path):
        raise SystemExit(f"source not found: {path}")
    nc.reset_scene()
    g = None
    fps = None
    if path.lower().endswith((".glb", ".gltf")):
        g = gltf_json(path)
        rates = [r for r in gltf_key_fps(g) if r]
        if rates:
            fps = sorted(rates)[len(rates) // 2]
            if max(rates) - min(rates) > 0.05:
                warn(f"{os.path.basename(path)}: animations have different key rates {sorted(set(round(r, 3) for r in rates))}; "
                     f"source frames use {fps:.3f} fps")
            set_scene_fps(fps)
            # 元のフレーム = 時刻 × シーンの fps（取り込み器の変換と同じ値を使う）
            fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
        bpy.ops.import_scene.gltf(filepath=path, guess_original_bind_pose=True, merge_vertices=False)
    elif path.lower().endswith((".usd", ".usda", ".usdc", ".usdz")):
        bpy.ops.wm.usd_import(filepath=path, import_materials=False)
    else:
        raise SystemExit(f"unsupported source: {path}")
    arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
    if not arms:
        raise SystemExit(f"{path}: no armature")
    arm = max(arms, key=lambda a: len(a.data.bones))
    return arm, g, fps


def role_names(arm):
    """骨名 → 役割を決める名前（Meshy 方言なら Mixamo 名。norm_common.rename_meshy_bones と同じ対応で、改名はしない）。"""
    names = [b.name for b in arm.data.bones]
    if not nc.is_meshy_rig(names):
        return {}
    return {n: nc.MESHY_TO_MIXAMO[nc.runtime_role(n)] for n in names if nc.runtime_role(n) in nc.MESHY_TO_MIXAMO}


def source_frame(arm, path):
    """元リグのヒーロー空間（M）と前向きの報告。"""
    names = role_names(arm)
    A = arm.matrix_world
    pos = {}
    for b in arm.data.bones:
        pos.setdefault(cm.runtime_role(names.get(b.name, b.name)), A @ b.head_local)
    if "hips" not in pos or "head" not in pos:
        raise SystemExit(f"{path}: hips/head bones not found")
    up = cm.up_axis(pos["head"], pos["hips"])
    fwd, info, errors = cm.detect_facing(pos, up)
    if errors:
        raise SystemExit(f"{path}: " + "; ".join(errors))
    M = cm.frame_matrix(fwd, up)
    info["upWorld"] = [round(v, 3) for v in up]
    info["forwardWorld"] = [round(v, 4) for v in fwd]
    rig = cm.Rig(arm, M, names)
    # 正面を -Z にした後で Right* の骨が +X 側にあるか（逆なら左右の名前が入れ替わったリグ）
    rx = [rig.P0[rig.index[k]].x for k in ("rightarm", "rightupleg") if k in rig.index]
    lx = [rig.P0[rig.index[k]].x for k in ("leftarm", "leftupleg") if k in rig.index]
    if not (rx and lx and sum(rx) / len(rx) > sum(lx) / len(lx)):
        raise SystemExit(f"{path}: after facing -Z the Right* bones are not on +X (mirrored rig or wrong facing)")
    missing = [s for s in rig.missing_segments() if s not in ("handR", "handL", "footR", "footL")]
    if missing:
        raise SystemExit(f"{path}: bones for segments {missing} not found (bones: {[b.name for b in arm.data.bones]})")
    if not rig.leg_length or rig.leg_length <= 1e-6:
        raise SystemExit(f"{path}: cannot measure the leg length (Hips / Foot bones)")
    return rig, info


def pick_action(arm, g, clip_index, path):
    acts = list(bpy.data.actions)
    if not acts:
        raise SystemExit(f"{path}: no animation")
    if clip_index is None:
        if len(g.get("animations", [])) != 1:
            raise SystemExit(f"{path}: {len(g.get('animations', []))} animations; set source.clip_index "
                             f"({[a.get('name') for a in g.get('animations', [])]})")
        clip_index = 0
    anims = g.get("animations", [])
    if not 0 <= clip_index < len(anims):
        raise SystemExit(f"{path}: clip_index {clip_index} out of range (0..{len(anims) - 1})")
    want = anims[clip_index].get("name") or f"Animation_{clip_index}"
    act = bpy.data.actions.get(want) or next((a for a in acts if a.name.startswith(want)), None)
    if act is None:
        raise SystemExit(f"{path}: action for animation {clip_index} '{want}' not found (have {[a.name for a in acts]})")
    ad = arm.animation_data or arm.animation_data_create()
    for t in ad.nla_tracks:
        t.mute = True
    ad.action = act
    if hasattr(ad, "action_slot") and len(getattr(act, "slots", [])):
        slot = next((s for s in act.slots if s.identifier == "OB" + arm.name), None) or \
            next((s for s in act.slots if s.target_id_type == 'OBJECT'), act.slots[0])
        ad.action_slot = slot
    return act, clip_index


def eval_at(arm, rig, t):
    """元のフレーム t（小数可）の (ΔR, P)。"""
    sc = bpy.context.scene
    f = math.floor(t)
    sc.frame_set(int(f), subframe=float(t - f))
    dg = bpy.context.evaluated_depsgraph_get()
    ev = arm.evaluated_get(dg)
    return rig.sample(ev.pose.bones, ev.matrix_world)


# MARK: - 抽出

def sample_times(clip, first, last, fps):
    """(元のフレームの列, start, end, 1 出力フレームあたりの元のフレーム数)。"""
    loop = bool(clip.get("loop", False))
    start = float(clip.get("start", first))
    end = float(clip.get("end", last))
    if end <= start:
        raise SystemExit(f"{clip['name']}: end ({end}) must be after start ({start})")
    # 四捨五入（Python の round は偶数丸めなので使わない）
    span = int(math.floor((end - start) * OUT_FPS / fps + 0.5))
    if loop:
        n = max(1, span)
        step = (end - start) / n
    else:
        n = max(1, span) + 1
        step = (end - start) / (n - 1)
    return [start + i * step for i in range(n)], start, end, step


def transform(qs, root, mirror, yaw):
    if mirror:
        qs = [cm.mirror_q(qs[cm.SEG_INDEX[cm.MIRROR_SWAP.get(s, s)]]) for s in cm.SEGMENTS]
        root = Vector((-root.x, root.y, root.z))
    if yaw:
        y = cm.ry(yaw)
        qs = [y @ q for q in qs]
        root = y @ root
    return qs, root


def untransform(qs, root, mirror, yaw):
    if yaw:
        y = cm.ry(-yaw)
        qs = [y @ q for q in qs]
        root = y @ root
    if mirror:
        qs = [cm.mirror_q(qs[cm.SEG_INDEX[cm.MIRROR_SWAP.get(s, s)]]) for s in cm.SEGMENTS]
        root = Vector((-root.x, root.y, root.z))
    return qs, root


def r4(x):
    return round(x, 4) + 0.0   # -0.0 を 0.0 に


def extract(clip, rig, arm, fps, frange, off=0.0):
    """1 クリップ分。(出力の dict, レポートの dict, 検証に通ったか)。
    frange: キーの範囲（元のフレーム = 最初のキーが 1）。off: 元のフレーム → Blender のフレームの差（Blender = 元 + off）。"""
    name = clip["name"]
    rest = bool(clip["source"].get("rest"))
    loop = bool(clip.get("loop", False))
    mirror = bool(clip.get("mirror", False))
    yaw = float(clip.get("yaw", 0.0))
    if rest:
        times, start, end, step = [0.0], 0.0, 0.0, 1.0
        n = len(rig.names)
        originals = [([Quaternion()] * n, [p.copy() for p in rig.P0])]
    else:
        times, start, end, step = sample_times(clip, frange[0], frange[1], fps)
        # キーの外は Blender が最後（最初）のキーの姿勢で止める。loop の end は 1 周後のフレームなので最後のキー + 1 まで可
        # （最後のキーが最初のキーと同じでないループ）
        if start < frange[0] - 1e-3 or end > frange[1] + (1.0 if loop else 0.0) + 1e-3:
            warn(f"{name}: [{start}, {end}] is outside the keys [{frange[0]}, {frange[1]}] (source frames, first key = 1); "
                 f"the pose is held beyond the keys")
        originals = [eval_at(arm, rig, t + off) for t in times]
    L = rig.leg_length
    frames = [rig.extract(dR, P) for dR, P in originals]

    # 腰の水平のずれ（root motion）を差し引く
    in_place = bool(clip.get("inPlace", loop)) and not rest
    drift = Vector((0, 0, 0))
    if in_place:
        _, r_start = rig.extract(*eval_at(arm, rig, start + off))
        _, r_end = rig.extract(*eval_at(arm, rig, end + off))
        drift = Vector((r_end.x - r_start.x, 0.0, r_end.z - r_start.z))
    span = (end - start) or 1.0

    def drift_at(t):
        return drift * ((t - start) / span)

    # 継ぎ目（loop の末尾 → 先頭）
    seam = None
    if loop and not rest:
        q_end, _ = rig.extract(*eval_at(arm, rig, end + off))
        seam = max(cm.quat_angle_deg(a, b) for a, b in zip(frames[0][0], q_end))
        if seam > LOOP_SEAM_WARN_DEG:
            warn(f"{name}: loop seam {seam:.1f}° (pose at end={end} differs from start={start}); adjust start/end")

    rot, root_out, prev = [], [], None
    out_q_frames, out_root_frames = [], []
    for t, (qs, root) in zip(times, frames):
        root = root - drift_at(t)
        qs, root = transform(qs, root, mirror, yaw)
        # 符号の連続化（先頭は w ≥ 0、以降は前フレームとの内積が正）
        fixed = []
        for s, q in enumerate(qs):
            q = q.normalized()
            if prev is None:
                if q.w < 0:
                    q = cm.neg(q)
            elif q.dot(prev[s]) < 0:
                q = cm.neg(q)
            fixed.append(q)
        prev = fixed
        # 書き出す値は Python の倍精度で丸めたもの（mathutils は単精度なので、丸めた後に Quaternion を通すと桁が崩れる）
        xyzw = [[r4(q.x), r4(q.y), r4(q.z), r4(q.w)] for q in fixed]
        rxyz = [r4(root.x), r4(root.y), r4(root.z)]
        out_q_frames.append([Quaternion((w, x, y, z)) for x, y, z, w in xyzw])
        out_root_frames.append(Vector(rxyz))
        for v in xyzw:
            rot += v
        root_out += rxyz

    # 検証: 丸めた値 → yaw・mirror・inPlace を戻す → 元リグへ実行時の計算で載せる → 元のアニメーションと比べる
    limb_err = {}
    seg_err = {}
    root_err = 0.0
    for t, qr, rr, (dR0, P0) in zip(times, out_q_frames, out_root_frames, originals):
        qs, root = untransform([q.normalized() for q in qr], rr, mirror, yaw)
        root = root + drift_at(t)
        dR1, P1 = rig.solve(qs, root * L)
        d0 = rig.limb_dirs(dR0, P0)
        d1 = rig.limb_dirs(dR1, P1)
        for k in d0:
            limb_err[k] = max(limb_err.get(k, 0.0), cm.angle_deg(d0[k], d1[k]))
        for seg in cm.SEGMENTS:
            j = rig.seg_joint(seg)
            if j is not None and rig.drive[j][0] != "rest":
                seg_err[seg] = max(seg_err.get(seg, 0.0), cm.quat_angle_deg(dR0[j], dR1[j]))
        h = rig.index["hips"]
        root_err = max(root_err, (P1[h] - P0[h]).length / L)
    limb_max = max(limb_err.values()) if limb_err else 0.0
    passed = limb_max < LIMB_MAX_DEG

    events = {}
    for k, v in clip.get("events", {}).items():
        fr = (float(v) - start) / step if not rest else 0.0
        # 実行時（HeroMotionLibrary.decode）は events を [0, frames - 1] へ切り詰める（loop の末尾 → 先頭の間も含めない）
        if not -1e-6 <= fr <= len(times) - 1 + 1e-6:
            warn(f"{name}: event {k}={v} (source frame) is outside the output frames [0, {len(times) - 1}] "
                 f"(the runtime clamps it)")
        events[k] = round(fr, 2)
    out = {
        "name": name,
        "source": clip["_label"],
        "frames": len(times),
        "loop": loop,
        "rootXZ": float(clip.get("rootXZ", 0.0)),
        "events": events,
        "rot": rot,
        "root": root_out,
    }
    report = {
        "name": name,
        "source": clip["_label"],
        "file": clip["_path"],
        "frames": len(times),
        "sourceFps": None if rest else round(fps, 4),
        "start": start, "end": end, "step": round(step, 6),
        "loop": loop, "mirror": mirror, "yaw": yaw, "inPlace": in_place,
        "driftRemoved": [round(drift.x, 4), round(drift.z, 4)],
        "loopSeamDegrees": None if seam is None else round(seam, 3),
        "rootRange": {ax: [r4(min(root_out[i::3])), r4(max(root_out[i::3]))] for i, ax in enumerate("xyz")},
        "events": events,
        "verify": {
            "passed": passed,
            "limbMaxDegrees": round(limb_max, 4),
            "limbDegrees": {k: round(v, 4) for k, v in limb_err.items()},
            "segmentRotationDegrees": {k: round(v, 4) for k, v in seg_err.items()},
            "hipsPositionError": round(root_err, 6),
        },
    }
    return out, report, passed


# MARK: - 出力

def dump_clips(clips):
    """1 クリップ 1 行の JSON（区間回転の配列が長いので、行単位で差分が読めるようにする）。"""
    head = {"version": 1, "fps": OUT_FPS, "segments": cm.SEGMENTS}
    lines = ["{"]
    lines.append(f'  "version": {head["version"]},')
    lines.append(f'  "fps": {head["fps"]},')
    lines.append(f'  "segments": {json.dumps(head["segments"])},')
    lines.append('  "clips": [')
    for i, c in enumerate(clips):
        lines.append("    " + json.dumps(c, separators=(",", ":"), ensure_ascii=False) + ("," if i + 1 < len(clips) else ""))
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(a):
    spec = load_spec(a.spec)
    only = [s for s in a.only.split(",") if s] if a.only else []
    unknown = [s for s in only if s not in {c["name"] for c in spec}]
    if unknown:
        raise SystemExit(f"--only: not in the spec: {unknown}")
    todo = [c for c in spec if not only or c["name"] in only]
    for c in todo:
        c["_path"], c["_clip_index"], c["_label"] = resolve_source(c["source"], a.anim_dir)
        if c["source"].get("rest") is not True and not c["_path"].lower().endswith((".glb", ".gltf")):
            raise SystemExit(f"{c['name']}: only glTF sources can be animated (use \"rest\": true for {c['_path']})")

    results, reports, failed = {}, [], []
    by_file = {}
    for c in todo:
        by_file.setdefault(c["_path"], []).append(c)
    for path, clips in by_file.items():
        arm, g, fps = import_source(path)
        rig, facing = source_frame(arm, path)
        log(f"{path}: {len(arm.data.bones)} bones, facing {facing['source']} {facing['forwardWorld']}, "
            f"leg length {rig.leg_length:.4f}, fps {fps}")
        for c in clips:
            frange = (0.0, 0.0)
            off = 0.0
            if not c["source"].get("rest"):
                act, idx = pick_action(arm, g, c["_clip_index"], path)
                frange = (float(act.frame_range[0]), float(act.frame_range[1]))
                # 元のフレーム 1 = アクションの最初のキー（basic_*.glb は Blender のフレーム 1、batch_*.glb は 0）
                off = frange[0] - 1.0
            out, rep, ok = extract(c, rig, arm, fps, (frange[0] - off, frange[1] - off), off)
            rep["facing"] = facing
            rep["legLength"] = round(rig.leg_length, 5)
            if not c["source"].get("rest"):
                rep["action"] = act.name
                rep["actionFrameRange"] = list(frange)
                rep["sourceFrameRange"] = [frange[0] - off, round(frange[1] - off, 4)]
            results[c["name"]] = out
            reports.append(rep)
            v = rep["verify"]
            log(f"{c['name']}: {out['frames']} frames, limb max {v['limbMaxDegrees']:.4f}°, segment rot max "
                f"{max(v['segmentRotationDegrees'].values()):.4f}°, hips err {v['hipsPositionError']:.6f} L"
                + ("" if ok else "  FAILED"))
            if not ok:
                failed.append(c["name"])

    errors = [f"{n}: limb direction error ≥ {LIMB_MAX_DEG}° after re-applying the clip to the source rig" for n in failed]
    report = {"spec": os.path.abspath(a.spec), "output": None if errors else os.path.abspath(a.out),
              "clips": reports, "errors": errors, "warnings": WARNINGS}
    if not errors:
        # 出力（--only は既存の出力のクリップを差し替える。順は仕様の順、仕様に無い既存のクリップは末尾に残す）
        existing = []
        if only and os.path.isfile(a.out):
            with open(a.out) as f:
                existing = json.load(f).get("clips", [])
        by_name = {c["name"]: c for c in existing}
        by_name.update(results)
        names = [c["name"] for c in spec if c["name"] in by_name]
        extra = [c["name"] for c in existing if c["name"] not in {s["name"] for s in spec}]
        if extra:
            warn(f"keeping clips not in the spec: {extra}")
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        tmp = a.out + ".tmp"
        with open(tmp, "w") as f:
            f.write(dump_clips([by_name[n] for n in names + extra]))
        os.replace(tmp, a.out)
        log(f"wrote {a.out} ({len(names) + len(extra)} clips, {os.path.getsize(a.out)} bytes)")
    if a.report:
        os.makedirs(os.path.dirname(os.path.abspath(a.report)), exist_ok=True)
        with open(a.report, "w") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
    if errors:
        raise SystemExit("verification failed: " + "; ".join(errors))


if __name__ == "__main__":
    main(parse())
