# 担当: hero-motion。モーションクリップ（docs/HERO_MOTION.md）の抽出・確認で共有する計算（Blender 5.2 の mathutils）。
# extract_clips.py（元リグ → 区間回転）と preview_clip.py（区間回転 → 表示するヒーローのリグ）が同じ実装を使う。
# 実行時（App/Battle/Heroes/HeroSkeletonRig.swift の HeroSkeletonRig / HeroSkeletonPoser.solve）と同じ規則で骨を駆動する。
#
# 記号（docs/HERO_MOTION.md と同じ）:
#   ヒーロー空間 = Y 上・正面 -Z・右手 +X。Blender のワールド座標 w からヒーロー空間へは h = M·w（M は回転のみ）。
#   ΔR_j(t) = R_j(t)·R0_j⁻¹（ヒーロー空間の、レストからの回転）。骨ローカルの軸の取り方（Blender の骨の Y 軸、
#   USD の関節の軸）は ΔR では打ち消し合うので、元リグと表示するリグで骨の軸の流儀が違ってもよい。
#   区間回転 Q_s = ΔR_j·C_j⁻¹、実行時は ΔR_j = Q_s·C'_j（R_j = Q_s·C'_j·R0'_j と同じ）。

import math

from mathutils import Matrix, Quaternion, Vector

SEGMENTS = ["hips", "torso", "head", "armR", "foreArmR", "handR", "armL", "foreArmL", "handL",
            "thighR", "shinR", "footR", "thighL", "shinL", "footL"]
SEG_INDEX = {s: i for i, s in enumerate(SEGMENTS)}

# 区間 → (骨の役割の候補（先にあるもの）, 補正 C を借りる骨の役割)。役割は norm_common.runtime_role の値
# （Swift の HeroJointRole.normalize と同じ）。胴は最上段の背骨。
SEG_BONE = {
    "hips": (("hips",), None),
    "torso": (("spine2", "spine1", "spine"), None),
    "head": (("head",), None),
    "armR": (("rightarm",), "rightarm"),
    "foreArmR": (("rightforearm",), "rightforearm"),
    "handR": (("righthand",), "rightforearm"),
    "armL": (("leftarm",), "leftarm"),
    "foreArmL": (("leftforearm",), "leftforearm"),
    "handL": (("lefthand",), "leftforearm"),
    "thighR": (("rightupleg",), "rightupleg"),
    "shinR": (("rightleg",), "rightleg"),
    "footR": (("rightfoot",), "rightleg"),
    "thighL": (("leftupleg",), "leftupleg"),
    "shinL": (("leftleg",), "leftleg"),
    "footL": (("leftfoot",), "leftleg"),
}
# 左右反転で入れ替える区間
MIRROR_SWAP = {"armR": "armL", "foreArmR": "foreArmL", "handR": "handL",
               "thighR": "thighL", "shinR": "shinL", "footR": "footL"}
MIRROR_SWAP.update({v: k for k, v in list(MIRROR_SWAP.items())})

# 四肢のレスト補正の向き（次の関節。HeroSkeletonRig.init の limbs と同じ）
LIMB_NEXT = {"rightarm": "rightforearm", "rightforearm": "righthand", "leftarm": "leftforearm", "leftforearm": "lefthand",
             "rightupleg": "rightleg", "rightleg": "rightfoot", "leftupleg": "leftleg", "leftleg": "leftfoot"}
# 検証する四肢の向き: (区間, 骨, 向きの先の骨（None = 最初の子、無ければ親からの向きの延長）)
LIMB_CHECKS = [("armR", "rightarm", "rightforearm"), ("foreArmR", "rightforearm", "righthand"), ("handR", "righthand", None),
               ("armL", "leftarm", "leftforearm"), ("foreArmL", "leftforearm", "lefthand"), ("handL", "lefthand", None),
               ("thighR", "rightupleg", "rightleg"), ("shinR", "rightleg", "rightfoot"), ("footR", "rightfoot", None),
               ("thighL", "leftupleg", "leftleg"), ("shinL", "leftleg", "leftfoot"), ("footL", "leftfoot", None)]
BODY_CHECKS = [("hips", "hips"), ("torso", None), ("head", "head")]

DOWN = Vector((0.0, -1.0, 0.0))
IDENTITY = Quaternion()


def runtime_role(joint_name):
    """HeroJointRole.normalize と同じ（norm_common.runtime_role の複製。mathutils だけで使えるようにここにも置く）。"""
    parts = [p for p in joint_name.split("/") if p]
    s = (parts[-1] if parts else joint_name).lower()
    if s.startswith("mixamorig"):
        s = s[len("mixamorig"):]
        while s and s[0].isnumeric():
            s = s[1:]
        if s and s[0] in ":_":
            s = s[1:]
    return s


def rotation_between(a, b):
    """Swift の rotationBetween と同じ（a を b へ向ける最小回転。ほぼ平行は単位、反平行は x 軸 → z 軸との外積の軸で 180°）。"""
    u = Vector(a).normalized()
    v = Vector(b).normalized()
    c = u.dot(v)
    if c > 0.9999:
        return Quaternion()
    if c < -0.9999:
        axis = u.cross(Vector((1.0, 0.0, 0.0)))
        if axis.length < 1e-3:
            axis = u.cross(Vector((0.0, 0.0, 1.0)))
        return Quaternion(axis.normalized(), math.pi)
    return Quaternion(u.cross(v).normalized(), math.acos(max(-1.0, min(1.0, c))))


def neg(q):
    return Quaternion((-q.w, -q.x, -q.y, -q.z))


def slerp(a, b, t):
    """simd_slerp と同じく最短経路で補間する（内積が負なら b の符号を反転）。"""
    d = a.dot(b)
    if d < 0.0:
        b = neg(b)
        d = -d
    if d > 0.9995:
        q = Quaternion((a.w + (b.w - a.w) * t, a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t))
        return q.normalized()
    th = math.acos(min(1.0, d))
    s = math.sin(th)
    ka = math.sin((1.0 - t) * th) / s
    kb = math.sin(t * th) / s
    return Quaternion((a.w * ka + b.w * kb, a.x * ka + b.x * kb, a.y * ka + b.y * kb, a.z * ka + b.z * kb))


def ry(deg):
    """ヒーロー空間の Y 軸回り（右手系。正の角度で正面 -Z が左手 -X 側へ回る = 上から見て反時計回り）。"""
    return Quaternion((0.0, 1.0, 0.0), math.radians(deg))


def mirror_q(q):
    """YZ 平面での鏡映（x → -x）に対応する回転: (x, y, z, w) → (x, -y, -z, w)。"""
    return Quaternion((q.w, q.x, -q.y, -q.z))


def angle_deg(u, v):
    """2 つの向きの角度（度）。小さい角度でも精度が落ちないよう atan2(|u×v|, u·v)（mathutils は単精度）。"""
    if u.length < 1e-12 or v.length < 1e-12:
        return 0.0
    u = u.normalized()
    v = v.normalized()
    return math.degrees(math.atan2(u.cross(v).length, u.dot(v)))


def quat_angle_deg(a, b):
    """2 つの回転の差の角度（度。符号の違いは同じ回転として扱う）。差の回転のベクトル部から求める（acos より小角で正確）。"""
    d = a.normalized().conjugated() @ b.normalized()
    return math.degrees(2.0 * math.atan2(math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z), abs(d.w)))


def mat_rot_quat(m):
    """拡縮を含む 4x4 / 3x3 から回転だけを取り出す。"""
    return m.to_3x3().normalized().to_quaternion()


# MARK: - 座標（Blender ワールド → ヒーロー空間）

SNAP_DEG = 20.0
FACING_AGREE_DEG = 45.0
TOE_MIN_HORIZONTAL = 0.5
AXES = [Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))]


def up_axis(head, hips):
    """腰 → 頭のベクトルに最も近い座標軸（±X/±Y/±Z）。glTF の取り込みは Z 上、Blender の USD 取り込みはステージの Y 上のまま。"""
    v = head - hips
    i = max(range(3), key=lambda k: abs(v[k]))
    return AXES[i] * (1.0 if v[i] > 0 else -1.0)


def frame_matrix(fwd, up):
    """前向き fwd・上 up（ワールド）からヒーロー空間への回転 M（行 = 右、上、後ろ）。右 = 前 × 上。"""
    right = fwd.cross(up).normalized()
    return Matrix((right, up, -fwd))


def flat(v, up):
    return v - up * v.dot(up)


def detect_facing(pos, up):
    """レストの骨の位置（役割 → ワールド位置）から前向きを決める（normalize_hero.py の detect_forward と同じ考え方）。
    つま先（Foot → ToeBase）が左右とも水平に近く互いに 45° 以内なら「確か」でその平均、そうでなければ腕・脚の左右
    （上 × (Right - Left)）。確かでないつま先と腕・脚が 45° 超食い違えば errors に理由を入れる。
    90° 単位から 20° 以内ならスナップする（正規化済みのヒーローと同じ扱い）。(fwd, info, errors)。"""
    toes = {}
    for side in ("left", "right"):
        foot = pos.get(side + "foot")
        toe = pos.get(side + "toebase") or pos.get(side + "toe")
        if foot is None or toe is None:
            continue
        d = toe - foot
        full = d.length
        h = flat(d, up)
        toes[side] = h.normalized() if full > 1e-9 and h.length >= TOE_MIN_HORIZONTAL * full else None
    dirs = [d for d in toes.values() if d is not None]
    acc = sum(dirs, Vector((0, 0, 0)))
    spread = angle_deg(dirs[0], dirs[1]) if len(dirs) == 2 else None
    reliable = len(dirs) == 2 and spread <= FACING_AGREE_DEG
    lr = Vector((0, 0, 0))
    for r, l in (("rightarm", "leftarm"), ("rightupleg", "leftupleg"), ("rightshoulder", "leftshoulder")):
        if r in pos and l in pos:
            lr += pos[r] - pos[l]
    lr = flat(lr, up)
    arms = up.cross(lr.normalized()).normalized() if lr.length > 1e-9 else None
    info = {"toes": len(toes), "toesSpreadDegrees": None if spread is None else round(spread, 1),
            "armsVsToesDegrees": None if (arms is None or acc.length < 1e-6) else round(angle_deg(acc, arms), 1),
            "reliable": reliable}
    errors = []
    if reliable or (dirs and acc.length > 1e-6 and arms is not None and info["armsVsToesDegrees"] <= FACING_AGREE_DEG):
        fwd, info["source"] = acc.normalized(), "toes"
    elif arms is not None and not dirs:
        fwd, info["source"] = arms, "arms"
    elif arms is not None:
        fwd, info["source"] = arms, "arms"
        errors.append(f"facing is ambiguous: toes unreliable ({len(dirs)} horizontal, spread {spread}) and the arms/legs "
                      f"disagree by {info['armsVsToesDegrees']}°")
    else:
        # 腕・脚の左右が無く、つま先も確かでない
        fwd, info["source"] = (acc.normalized() if acc.length > 1e-6 else None), "toes"
        if fwd is None:
            errors.append("facing could not be established (no toe, arm or leg bones)")
            fwd = flat(Vector((0, -1, 0)) if abs(up.y) < 0.9 else Vector((0, 0, 1)), up).normalized()
        else:
            errors.append(f"facing is ambiguous: toes unreliable ({len(dirs)} horizontal, spread {spread}) "
                          f"and the arm/leg bones are missing")
    # 90° 単位へのスナップ（上に垂直なワールド軸 2 本で角度を測る）
    e1 = next(a for a in AXES if abs(a.dot(up)) < 0.5)
    e2 = up.cross(e1)
    deg = math.degrees(math.atan2(fwd.dot(e2), fwd.dot(e1)))
    snapped = round(deg / 90.0) * 90.0
    if abs(deg - snapped) <= SNAP_DEG:
        deg = snapped
    info["yawInWorldDegrees"] = round(deg, 3)
    r = math.radians(deg)
    fwd = (e1 * math.cos(r) + e2 * math.sin(r)).normalized()
    return fwd, info, errors


# MARK: - リグ（骨対応・レスト・駆動。HeroSkeletonRig と同じ規則）

class Rig:
    """アーマチュアのレスト（= バインド。edit bone の matrix_local）から作る、実行時と同じ骨の駆動表。
    arm: Blender のアーマチュア。M: ワールド → ヒーロー空間の回転（3x3）。role_names: 骨名 → 役割を決める名前
    （Meshy の骨を Mixamo 名で読む等。無ければ骨名のまま）。"""

    def __init__(self, arm, M, role_names=None):
        role_names = role_names or {}
        A = arm.matrix_world.copy()
        bones = list(arm.data.bones)
        self.arm = arm
        self.M = M.to_3x3()
        self.qM = self.M.to_quaternion()
        self.Minv = self.M.inverted()
        self.names = [b.name for b in bones]
        self.roles = [runtime_role(role_names.get(b.name, b.name)) for b in bones]
        at = {b.name: i for i, b in enumerate(bones)}
        self.parent = [at[b.parent.name] if b.parent else -1 for b in bones]
        n = len(bones)
        order, done = [], [False] * n

        def visit(i, depth):
            if done[i] or depth > n:
                return
            if self.parent[i] >= 0:
                visit(self.parent[i], depth + 1)
            if not done[i]:
                done[i] = True
                order.append(i)
        for i in range(n):
            visit(i, 0)
        self.order = order
        self.rest_world = [A @ b.matrix_local for b in bones]
        self.q0w = [mat_rot_quat(m) for m in self.rest_world]
        self.P0 = [self.M @ m.translation for m in self.rest_world]
        self.index = {}
        for i, r in enumerate(self.roles):
            self.index.setdefault(r, i)
        self.children = [[] for _ in range(n)]
        for i, p in enumerate(self.parent):
            if p >= 0:
                self.children[p].append(i)

        # 四肢のレスト補正（HeroSkeletonRig.init と同じ: 次の関節 → 最初の子 → 親からの向き）
        self.C = [Quaternion() for _ in range(n)]
        for role, nxt in LIMB_NEXT.items():
            j = self.index.get(role)
            if j is None:
                continue
            d = None
            if nxt in self.index:
                d = self.P0[self.index[nxt]] - self.P0[j]
            elif self.children[j]:
                d = self.P0[self.children[j][0]] - self.P0[j]
            if (d.length if d is not None else 0.0) < 1e-5 and self.parent[j] >= 0:
                d = self.P0[j] - self.P0[self.parent[j]]
            if d is not None and d.length > 1e-5:
                self.C[j] = rotation_between(d, DOWN)

        # 駆動（HeroSkeletonRig の Drive）: ("rest",) / ("hips",) / ("spine", t) / ("neck",) / ("head",) / ("seg", 区間, C の骨)
        self.drive = [("rest",)] * n
        if "hips" in self.index:
            self.drive[self.index["hips"]] = ("hips",)
        spines = [self.index[r] for r in ("spine", "spine1", "spine2") if r in self.index]
        for k, i in enumerate(spines):
            self.drive[i] = ("spine", (k + 1) / len(spines))
        if "neck" in self.index:
            self.drive[self.index["neck"]] = ("neck",)
        if "head" in self.index:
            self.drive[self.index["head"]] = ("head",)
        for seg in ("armR", "foreArmR", "armL", "foreArmL", "thighR", "shinR", "thighL", "shinL"):
            j = self.index.get(SEG_BONE[seg][0][0])
            if j is not None:
                self.drive[j] = ("seg", SEG_INDEX[seg], j)
        # 手・足: 前腕・脛の子孫で、間の骨がすべてレストのときだけ（HeroSkeletonRig の setEnd）。C は前腕・脛のもの
        for seg in ("handR", "handL", "footR", "footL"):
            role, limb = SEG_BONE[seg][0][0], SEG_BONE[seg][1]
            j, l = self.index.get(role), self.index.get(limb)
            if j is None or l is None:
                continue
            p = self.parent[j]
            ok = True
            while p >= 0 and p != l:
                if self.drive[p][0] != "rest":
                    ok = False
                    break
                p = self.parent[p]
            if ok and p == l:
                self.drive[j] = ("seg", SEG_INDEX[seg], l)
                self.C[j] = self.C[l]

        hips = self.index.get("hips")
        feet = [self.P0[self.index[f]].y for f in ("leftfoot", "rightfoot") if f in self.index]
        self.leg_length = (self.P0[hips].y - sum(feet) / len(feet)) if (hips is not None and feet) else None

    # 区間の骨（無ければ None）と区間の C
    def seg_joint(self, seg):
        for r in SEG_BONE[seg][0]:
            if r in self.index:
                return self.index[r]
        return None

    def seg_C(self, seg):
        c = SEG_BONE[seg][1]
        return self.C[self.index[c]] if (c and c in self.index) else Quaternion()

    def missing_segments(self):
        return [s for s in SEGMENTS if self.seg_joint(s) is None]

    # ワールド ↔ ヒーロー空間
    def to_hero_q(self, q_world):
        return self.qM @ q_world @ self.qM.inverted()

    def to_world_q(self, q_hero):
        return self.qM.inverted() @ q_hero @ self.qM

    def sample(self, pose_bones, A):
        """評価済みの pose bones（名前で引ける）から (ΔR, P) をヒーロー空間で。A = アーマチュアのワールド行列。"""
        dR, P = [], []
        for i, name in enumerate(self.names):
            m = A @ pose_bones[name].matrix
            dR.append(self.to_hero_q(mat_rot_quat(m) @ self.q0w[i].inverted()))
            P.append(self.M @ m.translation)
        return dR, P

    def extract(self, dR, P):
        """(ΔR, P) → (区間回転 15 個, 腰の位置 (P - P0)/L)。欠けた区間は親側の区間に追従（手 = 前腕、足 = 脛）。"""
        qs = []
        for seg in SEGMENTS:
            j = self.seg_joint(seg)
            if j is None:
                fallback = {"handR": "foreArmR", "handL": "foreArmL", "footR": "shinR", "footL": "shinL"}.get(seg)
                qs.append(qs[SEG_INDEX[fallback]].copy() if fallback else Quaternion())
                continue
            qs.append((dR[j] @ self.seg_C(seg).inverted()).normalized())
        hips = self.index["hips"]
        root = (P[hips] - self.P0[hips]) / self.leg_length
        return qs, root

    def solve(self, qs, offset):
        """HeroSkeletonPoser.solve をヒーロー空間の ΔR と位置で行う。qs: 区間回転 15 個、offset: 腰のずれ（m）。"""
        n = len(self.names)
        dR = [None] * n
        P = [None] * n
        hips = self.index.get("hips", -1)
        qh, qt, qd = qs[SEG_INDEX["hips"]], qs[SEG_INDEX["torso"]], qs[SEG_INDEX["head"]]
        for j in self.order:
            p = self.parent[j]
            pos = self.P0[j].copy() if p < 0 else P[p] + dR[p] @ (self.P0[j] - self.P0[p])
            if j == hips:
                pos = pos + offset
            d = self.drive[j]
            k = d[0]
            if k == "rest":
                r = dR[p] if p >= 0 else Quaternion()
            elif k == "hips":
                r = qh
            elif k == "spine":
                r = slerp(qh, qt, d[1])
            elif k == "neck":
                r = slerp(qt, qd, 0.5)
            elif k == "head":
                r = qd
            else:
                r = qs[d[1]] @ self.C[d[2]]
            dR[j] = r
            P[j] = pos
        return dR, P

    def limb_dir(self, dR, P, j, nxt):
        """骨 j の向き（次の関節へ）。次が無ければ最初の子、子も無ければ親からの向きを ΔR で回したもの。"""
        if nxt is not None and nxt in self.index:
            return P[self.index[nxt]] - P[j]
        if self.children[j]:
            c = self.children[j][0]
            return P[c] - P[j]
        p = self.parent[j]
        return dR[j] @ (self.P0[j] - self.P0[p]) if p >= 0 else dR[j] @ Vector((0, 1, 0))

    def limb_dirs(self, dR, P):
        """LIMB_CHECKS の向き（区間名 → ベクトル）。骨が無いものは含めない。"""
        out = {}
        for seg, role, nxt in LIMB_CHECKS:
            j = self.index.get(role)
            if j is not None:
                if nxt is None and role.endswith("foot"):
                    nxt = role.replace("foot", "toebase")
                out[seg] = self.limb_dir(dR, P, j, nxt)
        return out

    def pose_world_matrices(self, dR, P):
        """ヒーロー空間の (ΔR, P) → 骨ごとのワールド行列（レストの拡縮・骨ローカルの軸を保つ）。"""
        out = []
        for i in range(len(self.names)):
            rs0 = self.rest_world[i].to_3x3()
            rot = self.to_world_q(dR[i]).to_matrix() @ rs0
            m = rot.to_4x4()
            m.translation = self.Minv @ P[i]
            out.append(m)
        return out

    def apply_pose(self, dR, P):
        """解いた姿勢を Blender のポーズへ書く（matrix_basis。親 → 子の式を逆に解くので depsgraph の更新は 1 回でよい）。"""
        arm = self.arm
        Ainv = arm.matrix_world.inverted()
        world = self.pose_world_matrices(dR, P)
        arm_space = [Ainv @ m for m in world]
        bones = arm.data.bones
        for j in self.order:
            b = bones[self.names[j]]
            pb = arm.pose.bones[self.names[j]]
            p = self.parent[j]
            if p < 0:
                basis = b.matrix_local.inverted() @ arm_space[j]
            else:
                pb_rest = bones[self.names[p]].matrix_local
                local_rest = pb_rest.inverted() @ b.matrix_local
                basis = local_rest.inverted() @ arm_space[p].inverted() @ arm_space[j]
            pb.matrix_basis = basis


def interp_clip(clip, f):
    """クリップの小数フレーム f の (区間回転 15 個, root)。loop は末尾 → 先頭へつなぐ（実行時と同じく slerp / 線形）。"""
    n = clip["frames"]
    rot = clip["rot"]
    root = clip["root"]
    S = len(SEGMENTS)
    if clip.get("loop"):
        f = f % n
        a = int(math.floor(f))
        b = (a + 1) % n
    else:
        f = max(0.0, min(float(n - 1), f))
        a = int(math.floor(f))
        b = min(a + 1, n - 1)
    t = f - a

    def q_at(fr, s):
        k = (fr * S + s) * 4
        x, y, z, w = rot[k:k + 4]
        return Quaternion((w, x, y, z)).normalized()
    qs = [slerp(q_at(a, s), q_at(b, s), t) for s in range(S)]
    ra = Vector(root[a * 3:a * 3 + 3])
    rb = Vector(root[b * 3:b * 3 + 3])
    return qs, ra.lerp(rb, t)
