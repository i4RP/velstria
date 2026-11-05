"""H034 ゴルムの待機・移動・通常攻撃・スキルの仕上げ（Blender 4.5 / 5.x、実行時と同じリグの計算）。

2026-11-05 から MLBB のフランコの画面収録（%TEMP%\\mlbb_ref の 10-15 11-08-11、docs/H034_QUALITY.md）に合わせた手付けの姿勢 + IK。
10-23 の初版（Meshy prime / Tripo の収録を時間だけ合わせた物。git の履歴）は、通常攻撃が頭上からの叩きつけ・S1 が頭上へ振り上げてから
投げる形で、MLBB（かがんで鉤を横に振る・体を横へひねって溜めてから投げる）と違っていた。
  - 足: 接地中は地面に固定（移動は移動速度を打ち消す一定速度）、離地は弧。膝は外。
  - 右手: 鎖鉤の柄の向き（手の区間の -Z = 親指の側 = fistGrip で Prop の +Y）を指定し、手首の曲がりを 55〜130° に収める。
    打撃の間は鉤の頭の位置を目標にして、届くまで手の目標を寄せ直す（H029 の聖槌と同じ）。
  - 左手: 何も持たない拳（MLBB は鎖の先の爪を持つ。Velstria の鎖鉤は右手の 1 本だけ）。
  - 肩（鎖骨）・指・つま先は detailJoints（局所のレスト後差分）。
打撃の時刻は KitTimes（Kit_H034.Tune）と同じ値に置く: S1 0.33 / 引き寄せ 0.45〜0.70 / S2 0.27 / 奥義 0.25 + 0.32 × k。
VELSTRIA/ で: blender -b --factory-startup -P tools/blender/author_h034_motion.py
"""
import json
import math
import sys
from pathlib import Path

import bpy  # noqa: F401  (Blender の mathutils と USD 読み込みのため)
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clip_math as cm
import preview_clip as preview
from author_h025_motion import bind_usd_axes, ik, local_delta, pack, solve

FPS = 30
SCALE = 1.12   # HeroBlueprints の H034（motion.scale。2026-11-05 に 1.36 → 1.12）。groundSpeed はゲームの m/s
# Blender 4.5 は揺れ物の骨（finish_h034_mane.py）を足した USD の取り込みで落ちるので、骨を足す前の元（finish が書き出す）を使う。
# クリップが動かす骨は同じ（揺れ物の骨は実行時の HeroSecondaryMotion だけが動かす）
_BASE = 'build/h034-motion/Hero_H034_base.usdz'
HERO = _BASE if Path(_BASE).exists() else 'App/Resources/Heroes/Hero_H034.usdz'
FINGERS = ('thumb', 'index', 'middle', 'ring', 'pinky')
DETAILS = ['leftshoulder', 'rightshoulder', 'lefttoebase', 'righttoebase']
DETAILS += [s + 'hand' + f + str(n) for s in ('left', 'right') for f in FINGERS for n in (1, 2, 3)]
V = Vector


# MARK: - 補間

def smooth(u):
    u = max(0.0, min(1.0, u))
    return u * u * (3 - 2 * u)


EASE = {
    'l': lambda u: u,
    'io': smooth,
    'i': lambda u: u * u * u,             # 溜めから一気に（打ち下ろし）
    'o': lambda u: 1 - (1 - u) ** 3,      # 素早く出て止まる（反動・戻り）
    'o2': lambda u: 1 - (1 - u) ** 2,
    'i2': lambda u: u * u,
}


def seg(keys, t):
    """keys = [(time, value, ease?)]。ease は前のキーからこのキーまでの区間の緩急。返り値 (i, u)。"""
    if t <= keys[0][0]:
        return 0, 0.0
    for i in range(1, len(keys)):
        if t <= keys[i][0]:
            a, b = keys[i - 1][0], keys[i][0]
            ease = keys[i][2] if len(keys[i]) > 2 else 'io'
            return i, EASE[ease]((t - a) / max(1e-6, b - a))
    return len(keys) - 1, 1.0


def val(keys, t):
    i, u = seg(keys, t)
    if i == 0:
        return keys[0][1]
    a, b = keys[i - 1][1], keys[i][1]
    if isinstance(a, (int, float)):
        return a + (b - a) * u
    return V(a).lerp(V(b), u)


def arc(keys, t):
    """肩からの向き（slerp）と長さ（線形）を別に補間する手の位置（直線でなく弧を描く）。"""
    i, u = seg(keys, t)
    if i == 0:
        return V(keys[0][1])
    a, b = V(keys[i - 1][1]), V(keys[i][1])
    la, lb = a.length, b.length
    qa = cm.rotation_between(V((0, 0, -1)), a)
    qb = cm.rotation_between(V((0, 0, -1)), b)
    d = cm.slerp(qa, qb, u) @ V((0, 0, -1))
    return d * (la + (lb - la) * u)


def dirs(keys, t):
    i, u = seg(keys, t)
    if i == 0:
        return V(keys[0][1]).normalized()
    a, b = V(keys[i - 1][1]).normalized(), V(keys[i][1]).normalized()
    return cm.slerp(Quaternion(), cm.rotation_between(a, b), u) @ a


def ry(rad):
    return Quaternion((0, 1, 0), rad)


def rx(rad):
    return Quaternion((1, 0, 0), rad)


def rz(rad):
    return Quaternion((0, 0, 1), rad)


def D(deg):
    return math.radians(deg)


def body_q(yaw, lean, roll):
    """yaw + = 左へ回る（上から見て反時計回り）、lean + = 前へ倒す、roll + = 左へ傾ける。"""
    return ry(D(yaw)) @ rx(D(-lean)) @ rz(D(roll))


def frame(bone, thumb):
    """区間回転 Q（Q·(0,-1,0) = 骨の向き、Q·(0,0,-1) = 親指の側）。"""
    b = bone.normalized()
    t = thumb - b * thumb.dot(b)
    if t.length < 1e-5:
        t = V((0, 0, -1)) - b * (-b.z)
    t.normalize()
    y, z = -b, -t
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_quaternion().normalized()


# MARK: - 腕と脚

def arm_ik(rig, qs, offset, details, side, target, pole, thumb, dev=(55, 130), fore_twist=0.6):
    """二骨 IK + 手首。thumb = 手の区間の -Z（右手は鎖鉤の柄の向き）。前腕のひねりは fore_twist の割合だけ持たせ、
    上腕は前腕から肘の蝶番で起こした向き。返り値: 目標に届かなかった距離（m）。"""
    _, P = solve(rig, qs, offset, details)
    a, b, c = [rig.index[side + r] for r in ('arm', 'forearm', 'hand')]
    base = P[a]
    l1, l2 = (rig.P0[b] - rig.P0[a]).length, (rig.P0[c] - rig.P0[b]).length
    toward = target - base
    dist = min(l1 + l2 - 0.002, max(abs(l1 - l2) + 0.002, toward.length))
    d = toward.normalized()
    bend = pole - d * d.dot(pole)
    if bend.length < 1e-3:
        bend = V((1, 0, 0))
    bend.normalize()
    along = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    elbow = base + d * along + bend * math.sqrt(max(0.0, l1 * l1 - along * along))
    end = base + d * dist
    U, F = (elbow - base).normalized(), (end - elbow).normalized()
    S = thumb.normalized()
    ang = math.degrees(F.angle(S)) if S.length > 0 else 90
    lo, hi = dev
    if ang < lo or ang > hi:
        axis = F.cross(S)
        if axis.length < 1e-5:
            axis = V((1, 0, 0))
        axis.normalize()
        S = Quaternion(axis, D(min(hi, max(lo, ang)))) @ F
    H = F - S * F.dot(S)
    hand = frame(H, S)
    hinge = frame(F, U.cross(F).cross(F) if U.cross(F).length > 1e-4 else S)
    full = frame(F, S)
    fore = cm.slerp(hinge, full, fore_twist)
    upper = cm.rotation_between(F, U) @ fore
    k = 'R' if side == 'right' else 'L'
    qs[cm.SEG_INDEX['arm' + k]] = upper.normalized()
    qs[cm.SEG_INDEX['foreArm' + k]] = fore.normalized()
    qs[cm.SEG_INDEX['hand' + k]] = hand
    return (end - target).length


def leg(rig, qs, offset, details, side, target, roll, toe, pole):
    k = 'R' if side == 'right' else 'L'
    details[side + 'toebase'] = local_delta(rig, side + 'toebase', rx(D(-toe)))
    qs[cm.SEG_INDEX['foot' + k]] = rx(D(roll)) @ rig.seg_C('foot' + k).inverted()
    return ik(rig, qs, offset, details, [side + 'upleg', side + 'leg', side + 'foot'],
              ['thigh' + k, 'shin' + k], target, pole)


def grip_fingers(rig, details, side, amount, spread=0.0):
    """握り（0 = 開き、1 = 柄を握った拳）。spread は握り直しで指を少し緩める量。"""
    sign = -1 if side == 'left' else 1
    for f in FINGERS:
        for n in (1, 2, 3):
            role = side + 'hand' + f + str(n)
            if role not in rig.index:
                continue
            if f == 'thumb':
                deg = [28, 30, 22][n - 1]
            else:
                deg = [62, 78, 52][n - 1] + (6 if f == 'pinky' else 0)
            deg *= amount * (1 - spread)
            details[role] = local_delta(rig, role, Quaternion((0, 0, -sign), D(deg)))


def shrug(rig, details, side, up, fwd):
    sign = -1 if side == 'left' else 1
    details[side + 'shoulder'] = local_delta(rig, side + 'shoulder', rz(D(sign * up)) @ ry(D(-sign * fwd)))


# MARK: - 構え

class Rest:
    def __init__(self, rig):
        self.rig = rig
        P0 = rig.P0
        self.ankle = {s: P0[rig.index[s + 'foot']].copy() for s in ('left', 'right')}
        self.leg = rig.leg_length
        self.hipY = P0[rig.index['hips']].y

    def foot(self, side, dx=0.0, dz=0.0, dy=0.0):
        """足首の目標。MLBB のフランコは肩幅より広く足を開き、つま先を外へ向けて立つ（樽の胴を短い脚で支える）。"""
        a = self.ankle[side].copy()
        a.x = (-0.25 if side == 'left' else 0.25) + dx
        a.z = (-0.06 if side == 'left' else 0.07) + dz
        a.y += dy
        return a


# MLBB のフランコの構え（10-15 の画面収録 16.0〜16.5 秒・カメラへ歩くコマ、0〜1.8 秒の立ち姿）: 右腕を体の横へ張り出して肘を曲げ、
# 拳は腹の高さで体の外。重い鉄の塊（Velstria は鎖鉤の鉤）は拳から下へ下がって膝の横。左腕は腰の横に下げ、拳は腰の前。
# 胸を張った猫背（背は前へ少し倒し、頭は起こす）、膝を外へ曲げた幅の広い構え。
CARRY = dict(hips=(-4, 6, 0), torso=(-2, 8, 0), head=(2, -9), drop=0.06,
             hand_r=V((0.27, -0.21, -0.10)), shaft=V((0.16, -1.0, -0.02)), pole_r=V((1.0, 0.3, 0.7)),
             hand_l=V((-0.20, -0.29, -0.12)), thumb_l=V((0.25, 0.1, -1.0)), pole_l=V((-1.0, 0.0, 0.6)))


class Pose:
    """1 フレームの手付けの値（体の角度・腰・手足の目標）。"""

    def __init__(self, rest):
        self.rest = rest
        self.hips, self.torso, self.head = CARRY['hips'], CARRY['torso'], CARRY['head']
        self.offset = V((0, -CARRY['drop'], 0))
        self.hand_r = CARRY['hand_r'].copy()     # 右肩からの手（胴の向きで回す）
        self.shaft = CARRY['shaft'].copy()       # 鎖鉤の柄（握り → 鉤の頭。胴の向きで回す）
        self.hand_l = CARRY['hand_l'].copy()     # 左肩からの手
        self.thumb_l = CARRY['thumb_l'].copy()   # 左の拳の親指の側（胴の向きで回す）
        self.feet = {'left': rest.foot('left'), 'right': rest.foot('right')}
        self.roll = {'left': 0.0, 'right': 0.0}
        self.toe = {'left': 0.0, 'right': 0.0}
        self.shrug = {'left': (4.0, 0.0), 'right': (6.0, 0.0)}
        self.grip = {'left': 0.85, 'right': 1.0}
        self.regrip = 0.0
        self.pole_r = CARRY['pole_r'].copy()
        self.pole_l = CARRY['pole_l'].copy()
        self.knee_out = 0.55
        # 打撃の間だけ、鉤の頭（ヒーロー空間）と柄の向きで右手を決める: (頭, 柄, 重み)
        self.strike = None
        # 打撃の間の手の出る側（胴の向き。肩 → 頭の線に直交する成分だけ使う）: 既定は下・外（拳を頭より低く、柄を斜め上へ）
        self.bend = V((0.3, -1.0, 0.2))


# 打撃の間の手首の範囲（柄と前腕の角度）。構えの 55〜130° より広げて、振りの途中・地を打つ所で柄を腕の延長に近づける
# （MLBB は鎖の先の錘なので腕と一直線に振れる。拳の握りのままでは鉤の頭が 0.2〜0.6 m 届かなかった）
STRIKE_WRIST = (40, 140)
STRIKE_ARM = 0.37  # 打撃の間の肩 → 手の長さ（腕をほぼ伸ばす）。柄と腕の角度はここから決まる（40〜140°）
HOOK_HEAD = 0.68   # 握りから鉤の頭まで（手続きの hookChain の鉤の中心 0.62 × weaponScale 1.1。Prop はこの高さに合わせて拡縮）
HEAD_R = 0.22      # 鉤の頭の半分の大きさ（地面より下へ入れない）


def strike_hand(rig, S, H, bend):
    """鉤の頭の目標 H へ届く右手の位置と柄の向き。肩 S・手 X・頭 H の三角形を、腕（S → X）を STRIKE_ARM に伸ばして解く
    （柄と腕の角度が 40〜140° に収まらなければ角度を端に止めて腕の長さを解き直す。遠すぎれば腕を伸ばし切って頭は手前で止まる）。
    手は bend（S → H に直交する成分）の側へ出る。"""
    a0, b0, c0 = [rig.index['right' + r] for r in ('arm', 'forearm', 'hand')]
    L = (rig.P0[b0] - rig.P0[a0]).length + (rig.P0[c0] - rig.P0[b0]).length - 0.01
    j = rig.index['righthand']
    r = HOOK_HEAD + (0.6 * (rig.P0[rig.index['righthandindex1']] - rig.P0[j]).length if 'righthandindex1' in rig.index else 0.06)
    toward = H - S
    D = max(1e-3, toward.length)
    d = toward / D
    side = bend - d * bend.dot(d)
    if side.length < 1e-3:
        side = V((0, -1, 0)) - d * (-d.y)
        if side.length < 1e-3:
            side = V((1, 0, 0))
    side.normalize()

    # 腕（肩 → 手）を a_pref に伸ばした時の柄と腕の角度（余弦定理 D² = a² + r² + 2ar cos α）。40〜140° に収め、収まらなければ a を解き直す
    a_pref = min(L, STRIKE_ARM)

    def arm_len(alpha):
        c = math.cos(math.radians(alpha))
        return -r * c + math.sqrt(max(0.0, r * r * c * c - r * r + D * D))
    c = (D * D - a_pref * a_pref - r * r) / (2 * a_pref * r)
    alpha = math.degrees(math.acos(max(-1.0, min(1.0, c))))
    if 40 <= alpha <= 140:
        a = a_pref
    else:
        alpha = max(40.0, min(140.0, alpha))
        a = max(0.12, min(L, arm_len(alpha)))
    # 肩での角度（正弦定理）。届かない時は腕と柄の角度 alpha のまま腕を伸ばし切る
    sb = max(-1.0, min(1.0, r * math.sin(math.radians(alpha)) / max(D, a)))
    beta = math.asin(sb)
    X = S + (d * math.cos(beta) + side * math.sin(beta)) * a
    u = (H - X).normalized()
    return X, u


def hook_head(rig, qs, P):
    q = qs[cm.SEG_INDEX['handR']]
    j = rig.index['righthand']
    grip = 0.6 * (rig.P0[rig.index['righthandindex1']] - rig.P0[j]).length if 'righthandindex1' in rig.index else 0.06
    return P[j] + q @ V((0, -grip, 0)) + q @ V((0, 0, -HOOK_HEAD))


def build(rig, p):
    qs = [Quaternion() for _ in range(15)]
    qh = body_q(*p.hips)
    qt = qh @ body_q(*p.torso)
    qd = qt @ body_q(p.head[0], p.head[1], 0)
    qs[0], qs[1], qs[2] = qh, qt, qd
    offset = p.offset.copy()
    details = {r: Quaternion() for r in DETAILS if r in rig.index}
    for side in ('left', 'right'):
        shrug(rig, details, side, *p.shrug[side])
        grip_fingers(rig, details, side, p.grip[side], p.regrip if side == 'right' else 0)
    errors = []
    for side in ('left', 'right'):
        pole = V(((-1 if side == 'left' else 1) * p.knee_out, 0, -1))
        errors.append(leg(rig, qs, offset, details, side, p.feet[side], p.roll[side], p.toe[side], pole))
    _, P = solve(rig, qs, offset, details)
    sr, sl = P[rig.index['rightarm']], P[rig.index['leftarm']]
    target, shaft = sr + qt @ p.hand_r, qt @ p.shaft
    if p.strike and p.strike[2] > 0:
        head, w = V(p.strike[0]), p.strike[2]
        if len(p.strike) > 3:
            # 肩からの向きで書いた軌道は、見積もりの肩（swing）でなく実際の肩（前傾・沈み・ひねりの後）から置き直す
            head = head + (sr - V(p.strike[3])) * p.strike[4]
            p.strike = (head, p.strike[1], w)
        X, u = strike_hand(rig, sr, head, qt @ p.bend)
        target = target.lerp(X, w)
        shaft = cm.slerp(Quaternion(), cm.rotation_between(shaft.normalized(), u), w) @ shaft.normalized()
    err = arm_ik(rig, qs, offset, details, 'right', target, qt @ p.pole_r, shaft,
                 dev=STRIKE_WRIST if p.strike and p.strike[2] > 0 else (55, 130))
    if p.strike and p.strike[2] > 0.5:
        # 肘の曲がりで前腕の向きが変わった分、頭が目標からずれる。手の目標を 3 回寄せ直す（柄の向きは保つ）
        for _ in range(3):
            _, P1 = solve(rig, qs, offset, details)
            miss = V(p.strike[0]) - hook_head(rig, qs, P1)
            if miss.length < 0.01:
                break
            target = target + miss * p.strike[2]
            err = arm_ik(rig, qs, offset, details, 'right', target, qt @ p.pole_r, shaft, dev=STRIKE_WRIST)
    # 鉤の頭を地面より下へ入れない（握りを支点に柄を起こす）
    _, P1 = solve(rig, qs, offset, details)
    head = hook_head(rig, qs, P1)
    if head.y < HEAD_R:
        q = qs[cm.SEG_INDEX['handR']]
        grip = head - q @ V((0, 0, -HOOK_HEAD))
        dy = max(-0.97, min(0.97, (HEAD_R - grip.y) / HOOK_HEAD))
        flat = V((head.x - grip.x, 0, head.z - grip.z))
        if flat.length < 1e-4:
            flat = qt @ V((0, 0, -1))
            flat.y = 0
        flat.normalize()
        s2 = flat * math.sqrt(1 - dy * dy) + V((0, dy, 0))
        err = arm_ik(rig, qs, offset, details, 'right', P1[rig.index['righthand']], qt @ p.pole_r, s2, dev=(40, 140))
    errors.append(err if not p.strike or p.strike[2] < 0.5 else 0.0)
    errors.append(arm_ik(rig, qs, offset, details, 'left', sl + qt @ p.hand_l, qt @ p.pole_l, qt @ p.thumb_l, dev=(40, 140)))
    build.last = errors
    return qs, offset, details, max(errors)


# MARK: - 待機・移動

def idle(rest, u):
    """4.4 秒の待機（ループ、HeroIdle の chainCaptain の呼吸と同じ周期）。重い呼吸 1 回、鉤を下げた右腕が呼吸に乗って揺れ、
    鉤は拳の下で小さく振り子に揺れる。0.55〜0.75 で柄を握り直す。"""
    p = Pose(rest)
    breath = math.sin(u * math.tau)
    lift = 0.5 - 0.5 * math.cos(u * math.tau)
    p.offset.y += 0.008 * breath - 0.005 * lift
    h0, t0, d0 = CARRY['hips'], CARRY['torso'], CARRY['head']
    p.hips = (h0[0], h0[1] + 0.8 * breath, 0.6 * math.sin(u * math.tau + 0.6))
    p.torso = (t0[0] + 1.5 * math.sin(u * math.tau + 1.1), t0[1] - 2.5 * breath - 1.5 * lift, 0.5 * math.sin(u * math.tau))
    p.head = (d0[0] - 3.0 * lift, d0[1] - 4.0 * lift + 1.2 * breath)
    for side in ('left', 'right'):
        p.shrug[side] = (p.shrug[side][0] + 2.2 * max(0.0, breath) + 0.8 * lift, p.shrug[side][1])
    p.regrip = 0.28 * math.sin(math.pi * smooth((u - 0.55) / 0.2)) ** 2 if 0.55 < u < 0.75 else 0.0
    sway = math.sin(u * math.tau * 2 + 0.4)
    p.hand_r = CARRY['hand_r'] + V((0.006 * breath, 0.010 * breath, 0.0))
    p.shaft = (CARRY['shaft'] + V((0.0, 0.0, 0.06 * sway))).normalized()
    p.hand_l = CARRY['hand_l'] + V((0, 0.008 * breath, -0.004 * breath))
    return p


# 移動（MLBB の画面収録 1.9〜2.5 秒・13.5〜14.0 秒・16.0〜16.6 秒）: 短い脚で小刻みに走る。同じ足が後ろへ蹴り出すコマが 8 コマごと
# （2.00 / 2.27 秒、13.60 / 13.87 秒）→ 1 周 8 コマ（0.267 秒、毎秒 7.5 歩）。MLBB の歩幅は 2.73 / 秒 × 0.267 = 0.73 単位（脚の長さの 1.5 倍）。
# Velstria は mapScale 1.35 倍速く動く（260 × 1.35 = 毎秒 3.51 m）ので、歩調（コマ数）を MLBB に合わせ、歩幅を 1.35 倍にした。
# 上体は直立に近い猫背のまま小さく弾み、鉤を下げた右腕は外へ張ったまま（鉤は拳の下で遅れて前後に揺れる）、左の拳は小さく振る。
GAIT = dict(frames=8, speed=3.51, contact=0.42, lift=0.10, lean=8, bob=0.028, drop=0.085, width=0.22, knee=0.5,
            twist=10, hook=0.22, arm=0.05)


def locomotion(rest, u):
    """支持脚は移動速度を打ち消す一定速度で地面に固定、離地は弧。上半身は構えのまま弾み、腰は小さくひねる。"""
    g = GAIT
    period = g['frames'] / FPS
    stride = g['speed'] * period / SCALE           # 1 周の歩幅（ヒーロー空間）
    contact = g['contact']
    reach = stride * contact / 2
    p = Pose(rest)
    lean = g['lean']
    w = math.tau * u
    bounce = math.cos(2 * (w - math.tau * contact / 2))   # 1 = 支持の中ほど（沈む）
    twist = math.cos(w)                                   # + = 右脚が前
    p.hips = (CARRY['hips'][0] + g['twist'] * twist, CARRY['hips'][1] + lean * 0.5, 4.0 * math.sin(w))
    p.torso = (CARRY['torso'][0] - g['twist'] * 0.6 * twist, CARRY['torso'][1] + lean * 0.6 + 2.0 * bounce, -3.0 * math.sin(w))
    p.head = (CARRY['head'][0] - 2 * twist, CARRY['head'][1] - lean * 0.6 - 1.5 * bounce)
    # 支持の中ほどで沈み、蹴り出しで浮く。体重は支持脚の側へ
    p.offset = V((0.028 * math.cos(w), -g['drop'] - g['bob'] * (0.5 + 0.5 * bounce), 0))
    for side, phase in (('right', u), ('left', u + 0.5)):
        x = g['width'] if side == 'right' else -g['width']
        ph = phase % 1
        foot = rest.ankle[side].copy()
        foot.x = x
        if ph < contact:
            v = ph / contact
            foot.z = -reach + 2 * reach * v
            roll = 18 * smooth((v - 0.7) / 0.3)
            heel = -6 * (1 - smooth(v / 0.2))
            p.roll[side] = roll + heel
            p.toe[side] = -roll * 0.7
            foot.y += 0.05 * math.sin(D(max(0.0, roll)))
        else:
            v = (ph - contact) / (1 - contact)
            tangent = 2 * reach * (1 - contact) / contact
            foot.z = reach - 2 * reach * smooth(v) + tangent * (2 * v ** 3 - 3 * v * v + v)
            foot.y += g['lift'] * math.sin(math.pi * v ** 0.8) ** 1.2
            foot.x += (0.03 if side == 'right' else -0.03) * math.sin(math.pi * v)   # 腹を避けて外を回す
            p.roll[side] = 18 * (1 - smooth(v / 0.35)) - 10 * math.sin(math.pi * v) - 6 * smooth((v - 0.8) / 0.2)
            p.toe[side] = 0
        p.feet[side] = foot
    # 右腕は張ったまま体の上下に遅れて揺れ、鉤は振り子で前後に（脚と逆: 右脚が前 = 鉤が後ろ）。左の拳は左脚と逆に前後
    lag = math.cos(2 * (w - math.tau * contact / 2) - 1.0)
    p.hand_r = CARRY['hand_r'] + V((0.0, -0.012 * lag, 0.03 * twist))
    p.shaft = (CARRY['shaft'] + V((0.0, 0.0, g['hook'] * math.cos(w - 0.8)))).normalized()
    p.hand_l = CARRY['hand_l'] + V((0.0, 0.015 * (1 - abs(twist)) - 0.008 * bounce, -g['arm'] * 2.2 * twist))
    p.knee_out = g['knee']
    return p


# MARK: - 通常攻撃（MLBB の 3 種の繰り返し）
#
# MLBB の画面収録（10-15 11-08-11）の命中（的の頭上の「179」が出たコマ）7.37 / 8.17 / 8.97 / 9.77 秒、間隔 0.80 秒:
#   ① 横なぎ（7.37・9.77 秒）: 命中の 0.17 秒前に体ごと右へ大きくひねり（カメラへ胸が向く）、鉤を右の後ろの肩の高さへ振りかぶる
#      （0.13〜0.10 秒前が頂点）→ ひねり戻しながら前を右から左へ払う（0.03 秒前に前を横切る）→ 命中で背を丸めて深くかがみ、
#      鉤は左の後ろの低い所へ振り抜いて地面に着く（+0.07〜+0.23 秒）。
#   ② 返し（8.17 秒）: ① の振り抜き（左の低い所）から鉤を頭の上へ振り上げ（0.17〜0.13 秒前）、左上から右下へ斜めに返し、
#      体は右へ回り切る（命中でカメラへ胸が向く）。
#   ③ 叩き落とし（8.97 秒）: 振りかぶりは ① と同じ（右の後ろの肩の高さ）。鉤を高い弧で頭の上を越えさせ、前の地面（的の足元）へ
#      斜めに叩き落とす。背を最も深く倒し、鉤を地に付けたまま 0.2 秒止まる。
# 9.77 秒は ① に戻っていた（3 種の繰り返し）。各クリップは構えで始まり構えで終わる。命中 0.20 秒（sim の windup へ伸縮）。
ATTACK_IMPACT = 0.20
ATTACK_END = 0.75
SHOULDER_R = V((0.27, 1.30, 0.03))


def ray(az, el):
    """右肩から見た向き（az 度: 0 = 前、+ = 左。el 度: + = 上）。"""
    a, e = D(az), D(el)
    return V((-math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)))


def swing(keys, t, yaw, drop=0.0):
    """鉤の頭の軌道 keys = [(t, az, el, ext, ease?)]: 右肩（胴の向き yaw で回す・腰の沈み drop で下げる）から向き (az, el) へ腕を
    ext（m）伸ばし、柄を同じ向きに伸ばした先が鉤の頭。向き・伸びを別に補間する（弧を描く）。返り値 (頭, 柄の向き)。"""
    i, u = seg([(k[0], 0, k[4] if len(k) > 4 else 'io') for k in keys], t)
    if i == 0:
        az, el, ext = keys[0][1:4]
    else:
        a, b = keys[i - 1], keys[i]
        az, el, ext = [x + (y - x) * u for x, y in zip(a[1:4], b[1:4])]
    d = ray(az, el)
    sh = ry(D(yaw)) @ SHOULDER_R - V((0, drop, 0))
    return sh + d * (ext + HOOK_HEAD), d


def shoulder_est(yaw, drop=0.0):
    """swing が軌道の基準にする右肩（胴の向き yaw で回し、腰の沈み drop で下げただけの見積もり）。"""
    return ry(D(yaw)) @ SHOULDER_R - V((0, drop, 0))


def hook_strike(head, yaw, drop=0.0):
    """鉤の頭の位置から (頭, 柄の向き)。柄は右肩から頭への向き。"""
    sh = ry(D(yaw)) @ SHOULDER_R - V((0, drop, 0))
    return head, (head - sh).normalized()


def attack_base(rest, t, hips_yaw, torso_yaw, lean, drop, step, back=None, shift=None):
    """通常攻撃の体（腰と胴のひねり・前傾・沈み・左足の踏み込み）。step は左足の (dz, dy)、back は右足を後ろへ引く量、
    shift は腰の (横, 前後) のずれ = 体重の移り。返り値 (Pose, 胴の向き, 沈み)。"""
    p = Pose(rest)
    hy, ty = val(hips_yaw, t), val(torso_yaw, t)
    ln = val(lean, t)
    dr = val(drop, t)
    p.hips = (CARRY['hips'][0] + hy, CARRY['hips'][1] + ln * 0.45, 0)
    p.torso = (CARRY['torso'][0] + ty, CARRY['torso'][1] + ln * 0.55, 0)
    p.head = (CARRY['head'][0] - ty * 0.45 - hy * 0.3, CARRY['head'][1] - ln * 0.45)
    p.offset = V((0, -CARRY['drop'] - dr, 0))
    st = val([(k[0], V((k[1][0], k[1][1], 0)), *k[2:]) for k in step], t)
    dz, dy = st.x, st.y
    p.feet['left'] = rest.foot('left', dz=dz, dy=dy)
    p.roll['left'] = -30 * dy / 0.06 if dy > 0 else 0
    lift = smooth((-dz - 0.04) / 0.08)
    p.roll['right'] = 10 * lift
    p.toe['right'] = -8 * lift
    if back:
        b = val(back, t)
        p.feet['right'] = rest.foot('right', dx=0.3 * b, dz=b)
        p.roll['right'] = max(p.roll['right'], 16 * smooth(b / 0.12))
        p.toe['right'] = min(p.toe['right'], -14 * smooth(b / 0.12))
        p.feet['left'] = p.feet['left'] + V((-0.2 * max(0.0, -dz), 0, 0))
    if shift:
        sh = val([(k[0], V((k[1][0], 0, k[1][1])), *k[2:]) for k in shift], t)
        p.offset.x += sh.x
        p.offset.z += sh.z
    p.knee_out = 0.6
    return p, hy + ty, CARRY['drop'] + dr


def strike_weight(t, on, full, hold, off):
    return val([(on, 0.0), (full, 1.0, 'o2'), (hold, 1.0), (off, 0.0, 'io')], t)


def attack_sweep(rest, t):
    """① 横なぎ（右 → 左）。"""
    imp, end = ATTACK_IMPACT, ATTACK_END
    p, yaw, dr = attack_base(rest, t,
                             [(0, 0), (0.06, -40, 'o2'), (0.09, -42), (imp, 14, 'i2'), (0.30, 36, 'o'), (0.50, 32), (end, 0, 'io')],
                             [(0, 0), (0.06, -66, 'o2'), (0.09, -70), (imp, 16, 'i2'), (0.30, 54, 'o'), (0.50, 48), (end, 0, 'io')],
                             [(0, 0), (0.06, -6, 'o2'), (0.09, -6), (imp, 36, 'i2'), (0.30, 44, 'o'), (0.50, 40), (end, 0, 'io')],
                             [(0, 0), (0.06, 0.02, 'o2'), (0.09, 0.03), (imp, 0.14, 'i2'), (0.30, 0.18, 'o'), (0.50, 0.16), (end, 0, 'io')],
                             [(0, (0, 0)), (0.04, (0.0, 0.0)), (0.11, (-0.10, 0.06), 'o2'), (imp, (-0.28, 0.0), 'i2'), (0.52, (-0.28, 0.0)),
                              (0.64, (-0.10, 0.04), 'io'), (end, (0, 0), 'o')],
                             back=[(0, 0), (0.10, 0.02), (imp, 0.10, 'i2'), (0.52, 0.10), (end, 0, 'io')],
                             shift=[(0, (0, 0)), (0.06, (0.05, 0.03), 'o2'), (imp, (-0.02, -0.08), 'i2'), (0.30, (-0.07, -0.09), 'o'),
                                    (0.50, (-0.06, -0.08)), (end, (0, 0), 'io')])
    # 鉤: 右の腰（構え）→ 右の後ろの肩の高さ（0.05〜0.09 秒 = MLBB の命中の 0.13〜0.10 秒前）→ 右（0.15）→ 前（命中）→ 左 →
    # 左の後ろの低い所（地面）。上から見て左回りの一続きの弧
    p.strike = (*swing([(0.01, -95, -60, 0.30), (0.045, -125, 0, 0.32, 'o2'), (0.075, -140, 18, 0.36, 'o'), (0.095, -136, 16, 0.37),
                        (0.14, -62, 4, 0.38, 'i2'), (imp, 0, -16, 0.36, 'l'), (0.24, 55, -36, 0.26, 'o'), (0.32, 105, -50, 0.18, 'o'),
                        (0.46, 125, -58, 0.16)], t, yaw, dr),
                strike_weight(t, 0.0, 0.035, 0.46, 0.62), shoulder_est(yaw, dr), 1.0)
    p.hand_r = arc([(0, CARRY['hand_r']), (0.5, V((-0.30, -0.30, -0.10))), (0.62, V((-0.10, -0.25, -0.30)), 'io'), (end, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (0.5, V((-0.5, -0.8, 0.4))), (0.62, V((0.0, -1.0, -0.2)), 'io'), (end, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.10, V((0.3, -1.0, 0.8))), (imp, V((0.6, -1.0, 0.0))), (0.4, V((0.2, -1.0, -0.4))),
                     (end, CARRY['pole_r'])], t)
    # 左腕: 振りかぶりで体の前へ（釣り合い）、振り抜きで左の後ろへ引く
    p.hand_l = arc([(0, CARRY['hand_l']), (0.12, V((0.10, -0.28, -0.30)), 'o2'), (imp, V((-0.05, -0.30, -0.22)), 'i2'),
                    (0.35, V((-0.20, -0.30, 0.05)), 'o'), (0.55, V((-0.16, -0.32, -0.02))), (end, CARRY['hand_l'], 'io')], t)
    p.shrug['right'] = (val([(0, 6), (0.12, 16), (imp, 2, 'i2'), (0.5, 0), (end, 6)], t), val([(0, 0), (0.12, -8), (imp, 10), (end, 0)], t))
    return p


def attack_backhand(rest, t):
    """② 返し（左 → 右、頭の上から斜めに）。"""
    imp, end = ATTACK_IMPACT, ATTACK_END
    p, yaw, dr = attack_base(rest, t,
                             [(0, 0), (0.07, 28, 'o2'), (0.10, 26), (imp, -20, 'i2'), (0.30, -40, 'o'), (0.50, -34), (end, 0, 'io')],
                             [(0, 0), (0.07, 46, 'o2'), (0.10, 44), (imp, -30, 'i2'), (0.30, -62, 'o'), (0.50, -54), (end, 0, 'io')],
                             [(0, 0), (0.07, 10, 'o2'), (0.10, 8), (imp, 30, 'i2'), (0.30, 36, 'o'), (0.50, 32), (end, 0, 'io')],
                             [(0, 0), (0.07, 0.05, 'o2'), (imp, 0.12, 'i2'), (0.30, 0.15, 'o'), (0.50, 0.13), (end, 0, 'io')],
                             [(0, (0, 0)), (0.05, (0.0, 0.0)), (0.12, (-0.10, 0.06), 'o2'), (imp, (-0.24, 0.0), 'i2'), (0.52, (-0.24, 0.0)),
                              (0.64, (-0.08, 0.04), 'io'), (end, (0, 0), 'o')],
                             back=[(0, 0), (0.13, 0.02), (imp, 0.10, 'i2'), (0.52, 0.10), (end, 0, 'io')],
                             shift=[(0, (0, 0)), (0.12, (-0.04, 0.03), 'o2'), (imp, (0.01, -0.07), 'i2'), (0.30, (0.06, -0.08), 'o'),
                                    (0.50, (0.05, -0.07)), (end, (0, 0), 'io')])
    # 鉤: 構え → 左の後ろの低い所（① の振り抜きと同じ所）→ 頭の上（左前の高い所）→ 前を左上から右下へ → 右の後ろの低い所
    p.strike = (*swing([(0.01, -95, -60, 0.30), (0.035, 70, -40, 0.24, 'o2'), (0.07, 100, 50, 0.24, 'io'), (0.11, 50, 70, 0.30, 'io'),
                        (0.16, 20, 25, 0.36, 'i2'), (imp, -10, -12, 0.36, 'l'), (0.24, -60, -34, 0.28, 'o'), (0.32, -105, -48, 0.22, 'o'),
                        (0.46, -116, -56, 0.20)], t, yaw, dr),
                strike_weight(t, 0.0, 0.03, 0.46, 0.62), shoulder_est(yaw, dr), 1.0)
    p.hand_r = arc([(0, CARRY['hand_r']), (0.5, V((0.24, -0.30, 0.06))), (end, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (0.5, V((0.4, -0.8, 0.45))), (end, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.07, V((0.2, 0.2, -1.0))), (0.12, V((1.0, 0.4, 0.2))), (imp, V((0.8, -1.0, 0.0))),
                     (0.4, V((1.0, -0.6, 0.4))), (end, CARRY['pole_r'])], t)
    p.hand_l = arc([(0, CARRY['hand_l']), (0.12, V((-0.22, -0.26, 0.04)), 'o2'), (imp, V((0.02, -0.30, -0.26)), 'i2'),
                    (0.35, V((0.08, -0.28, -0.30)), 'o'), (0.55, V((0.02, -0.30, -0.24))), (end, CARRY['hand_l'], 'io')], t)
    p.shrug['right'] = (val([(0, 6), (0.13, 18, 'o2'), (imp, 0, 'i2'), (0.5, 0), (end, 6)], t), 0.0)
    return p


def attack_chop(rest, t):
    """③ 叩き落とし（右の後ろから頭の上を越えて前の地面へ）。命中で鉤を地に付けて止まる。"""
    imp, end = ATTACK_IMPACT, ATTACK_END
    p, yaw, dr = attack_base(rest, t,
                             [(0, 0), (0.06, -36, 'o2'), (0.10, -36), (0.15, -18), (imp, 6, 'i'), (0.45, 6), (end, 0, 'io')],
                             [(0, 0), (0.06, -60, 'o2'), (0.10, -60), (0.15, -30), (imp, 10, 'i'), (0.45, 8), (end, 0, 'io')],
                             [(0, 0), (0.06, -6, 'o2'), (0.15, -12), (imp, 50, 'i'), (0.45, 46), (end, 0, 'io')],
                             [(0, 0), (0.06, 0.0, 'o2'), (0.12, 0.02), (imp, 0.19, 'i2'), (0.45, 0.18), (end, 0, 'io')],
                             [(0, (0, 0)), (0.04, (0.0, 0.0)), (0.13, (-0.12, 0.07), 'o2'), (imp, (-0.32, 0.0), 'i2'), (0.52, (-0.32, 0.0)),
                              (0.64, (-0.10, 0.04), 'io'), (end, (0, 0), 'o')],
                             back=[(0, 0), (0.14, 0.03), (imp, 0.12, 'i2'), (0.52, 0.12), (end, 0, 'io')],
                             shift=[(0, (0, 0)), (0.10, (0.04, 0.05), 'o2'), (imp, (0.02, -0.12), 'i'), (0.45, (0.02, -0.11)), (end, (0, 0), 'io')])
    # 振りかぶり（① と同じ右の後ろの肩の高さ）→ 右の後ろの高い所 → 頭の上 → 前の地面
    up, _ = swing([(0.01, -95, -60, 0.30), (0.045, -125, 0, 0.32, 'o2'), (0.08, -140, 18, 0.36, 'o'), (0.13, -150, 58, 0.30, 'io'),
                   (0.165, -60, 84, 0.32, 'i2'), (0.185, -10, 50, 0.38, 'l')], t, yaw, dr)
    down = val([(0.175, V((0.20, 2.10, -0.40))), (0.185, V((0.24, 1.50, -0.85)), 'l'), (imp, V((0.24, HEAD_R, -0.88)), 'i2'),
                (0.28, V((0.24, HEAD_R + 0.05, -0.86)), 'o'), (0.46, V((0.24, HEAD_R + 0.01, -0.85)))], t)
    k = smooth((t - 0.175) / 0.015)
    head = up.lerp(down, k)
    _, sw = hook_strike(head, yaw, dr)
    p.strike = (head, sw, strike_weight(t, 0.0, 0.035, 0.48, 0.62), shoulder_est(yaw, dr), 1 - k)
    p.hand_r = arc([(0, CARRY['hand_r']), (0.5, V((-0.02, -0.32, -0.32))), (0.62, V((0.08, -0.26, -0.30)), 'io'), (end, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (0.5, V((0.05, -0.6, -0.8))), (0.62, V((0.05, -1.0, -0.3)), 'io'), (end, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.15, V((1.0, 0.3, 0.3))), (imp, V((1.0, -0.8, 0.3))), (end, CARRY['pole_r'])], t)
    p.hand_l = arc([(0, CARRY['hand_l']), (0.12, V((0.08, -0.24, -0.30)), 'o2'), (imp, V((0.10, -0.40, -0.18)), 'i2'),
                    (0.55, V((0.08, -0.38, -0.18))), (end, CARRY['hand_l'], 'io')], t)
    p.shrug['right'] = (val([(0, 6), (0.16, 20, 'o2'), (imp, 0, 'i'), (0.5, 0), (end, 6)], t), 0.0)
    p.head = (p.head[0], p.head[1] + val([(0, 0), (0.15, 6), (imp, -14, 'i'), (0.45, -12), (end, 0, 'io')], t))
    return p


# MARK: - スキル（MLBB の画面収録 10-15 11-08-11。コマの時刻は発動 = 指を離したコマから）
#
#   S1 鎖鉤（3.17 秒に指を離す）: 0.06〜0.13 秒で深くかがみ、背を前へ倒したまま体を左へひねる（上から見て肩の線が狙いに対して斜め）。
#      鉤を持つ右腕は右の後ろの高い所へ振りかぶり、左腕は左下へ伸ばす → 0.16〜0.23 秒は溜め（鉤が右上で止まる）→
#      0.26〜0.30 秒でひねり戻しながら右腕を前へ振り抜き → 0.33 秒（3.50 秒）に鉤が手を離れる。腕を狙いへ伸ばしたまま鎖を張って立つ
#      （〜1.1 秒）。外れたら鎖を手繰って構えへ。
#   S1 の命中（3.93 秒）: 鎖を張ったまま待ち（+0.45 秒まで）、+0.45〜0.70 秒で体を右へ回して深くかがみ、両腕で鎖を右の後ろの低い所へ
#      引き寄せる。+0.7〜1.0 秒はかがんだまま、構えへ戻る。
#   S2 鉄鎖旋（6.17 秒）: 0.13〜0.17 秒で伸び上がって鉤を頭の上へ振り上げ → 0.27 秒（6.43 秒）に右前の地面へ叩きつけて深くかがむ →
#      0.6 秒まで沈んだまま → 1.0 秒で構え。
#   奥義 狩猟鎖獄（9.97 秒）: 0.03〜0.17 秒で低く前へ掴みかかり（左手を前へ）→ 0.23 秒（10.20 秒）に掴む（1 撃目）→ 0.32 秒おきに
#      鉤で横なぎ（右 → 左）と返し（左 → 右）を交互に（胸がカメラへ向く振りかぶりと、背を見せる振り抜き）→ 6 撃目（1.85 秒）は頭の上から
#      前の地面へ叩きつけて深くかがむ（11.63〜11.83 秒に地面の光の輪）→ 2.05 秒まで沈み、2.3 秒で構え。

def skill_base(rest, t, hips_yaw, torso_yaw, lean, drop, step, back=None, forward=None):
    p, yaw, dr = attack_base(rest, t, hips_yaw, torso_yaw, lean, drop, step)
    if back:
        b = val(back, t)
        p.feet['right'] = rest.foot('right', dx=0.3 * b, dz=b)
        p.roll['right'] = 14 * smooth(b / 0.15)
        p.toe['right'] = -12 * smooth(b / 0.15)
    if forward:
        p.offset.z = -val(forward, t)
    return p, yaw, dr


S1_RELEASE = 0.33   # Kit_H034.hookDelay（鉤が手を離れる）


def skill_hook(rest, t):
    """S1 の投げ 1.53 秒（鉤が手を離れる 0.33）。外れた時の手繰りまで。"""
    s = S1_RELEASE
    p, yaw, dr = skill_base(rest, t,
                            [(0, 0), (0.10, 26, 'o2'), (0.24, 28), (s, -12, 'i2'), (0.95, -10), (1.3, 0, 'io')],
                            [(0, 0), (0.10, 40, 'o2'), (0.24, 44), (s, -16, 'i2'), (0.95, -12), (1.3, 0, 'io')],
                            [(0, 0), (0.10, 68, 'io'), (0.24, 70), (s, 22, 'o'), (0.5, 10), (0.95, 8), (1.3, 0, 'io')],
                            [(0, 0), (0.10, 0.27, 'io'), (0.24, 0.28), (s, 0.10, 'o'), (0.5, 0.05), (0.95, 0.05), (1.3, 0, 'io')],
                            [(0, (0, 0)), (0.12, (0.0, 0.0)), (0.26, (-0.12, 0.07), 'o2'), (s, (-0.32, 0.0), 'i2'), (0.95, (-0.32, 0.0)),
                             (1.15, (-0.10, 0.04), 'io'), (1.3, (0, 0), 'o')],
                            back=[(0, 0), (0.12, 0.04), (s, 0.12, 'i2'), (0.95, 0.12), (1.3, 0, 'io')])
    # 鉤: 構え → 右の後ろの高い所（溜め）→ 頭の右を前へ振り抜く → 狙いへ腕を伸ばして止まる（鎖を張る）
    p.strike = (*swing([(0.02, -95, -60, 0.30), (0.10, -112, 42, 0.30, 'o2'), (0.24, -118, 48, 0.31), (0.29, -60, 36, 0.36, 'i2'),
                        (s, -4, 8, 0.42, 'l'), (0.42, 0, 2, 0.42, 'o'), (0.95, 0, 0, 0.42)], t, yaw, dr),
                strike_weight(t, 0.0, 0.06, 0.95, 1.12), shoulder_est(yaw, dr), 1.0)
    # 外れ: 鎖を手繰って（手を 2 回引く）構えへ
    tug = 0.05 * math.sin(math.pi * smooth((t - 0.95) / 0.18)) + 0.05 * math.sin(math.pi * smooth((t - 1.13) / 0.18))
    p.hand_r = arc([(0, CARRY['hand_r']), (0.95, V((-0.02, -0.06, -0.40))), (1.12, V((0.08, -0.14, -0.30)), 'io'),
                    (1.45, CARRY['hand_r'], 'io')], t) + V((0, 0, tug))
    p.shaft = dirs([(0, CARRY['shaft']), (0.95, V((0.0, 0.1, -1.0))), (1.12, V((0.1, -0.5, -0.8)), 'io'), (1.45, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.10, V((0.6, -0.3, 0.8))), (0.24, V((0.8, 0.0, 0.6))), (s, V((1.0, -0.8, 0.1))),
                     (1.45, CARRY['pole_r'])], t)
    # 左腕: 溜めで左下へ伸ばし（釣り合い）、投げで体の前の低い所（MLBB は左手の爪を腰の前に構える）
    p.hand_l = arc([(0, CARRY['hand_l']), (0.10, V((-0.36, -0.26, -0.06)), 'o2'), (0.24, V((-0.37, -0.24, -0.04))),
                    (s, V((0.06, -0.34, -0.24)), 'i2'), (0.95, V((0.06, -0.34, -0.24))), (1.3, CARRY['hand_l'], 'io')], t)
    p.shrug['right'] = (val([(0, 6), (0.10, 22, 'o2'), (0.24, 24), (s, 6, 'i2'), (0.95, 4), (1.3, 6)], t),
                        val([(0, 0), (0.10, -10), (s, 14, 'i2'), (0.95, 10), (1.3, 0)], t))
    p.head = (p.head[0] + val([(0, 0), (0.10, -30), (0.24, -32), (s, 6, 'i2'), (0.95, 4), (1.3, 0)], t),
              p.head[1] + val([(0, 0), (0.10, -14), (s, -6), (1.3, 0, 'io')], t))
    return p


def skill_pull(rest, t):
    """S1 の命中 1.13 秒: 鎖を張って待つ（〜0.45）→ 引き寄せ（0.45〜0.70、体を右へ回して深くかがみ、鎖を右の後ろの低い所へ）→ 構え。"""
    a, b = 0.45, 0.70
    p, yaw, dr = skill_base(rest, t,
                            [(0, -12), (a, -14), (0.55, -30, 'i2'), (b, -40, 'o'), (0.9, -36), (1.1, 0, 'io')],
                            [(0, -16), (a, -18), (0.55, -40, 'i2'), (b, -56, 'o'), (0.9, -50), (1.1, 0, 'io')],
                            [(0, 8), (a, -4, 'io'), (0.55, 22, 'i2'), (b, 46, 'o'), (0.9, 42), (1.1, 0, 'io')],
                            [(0, 0.05), (a, 0.04), (0.55, 0.12, 'i2'), (b, 0.25, 'o'), (0.9, 0.23), (1.1, 0, 'io')],
                            [(0, (-0.32, 0.0)), (a, (-0.32, 0.0)), (0.52, (-0.30, 0.05)), (b, (-0.20, 0.0), 'io'), (0.95, (-0.18, 0.0)),
                             (1.1, (0, 0), 'io')],
                            back=[(0, 0.12), (a, 0.14), (b, 0.18, 'o'), (0.95, 0.16), (1.1, 0, 'io')])
    # 待つ間は腕を狙いへ伸ばし、鎖が張って少し後ろへ反る。引き寄せは右の後ろの低い所へ両腕で引く
    hold = 0.012 * math.sin(t * 40) * (1 if t < a else 0)
    head, sw = swing([(0, 0, 0, 0.42), (a, 2, 4, 0.40), (0.56, -40, -10, 0.34, 'i2'), (b, -120, -40, 0.30, 'o'), (0.9, -130, -50, 0.28),
                      (1.0, -110, -55, 0.28)], t, yaw, dr)
    p.strike = (head + V((0, hold, 0)), sw, val([(0, 1.0), (0.9, 1.0), (1.05, 0.0, 'io')], t), shoulder_est(yaw, dr), 1.0)
    p.hand_r = arc([(0, V((-0.02, -0.06, -0.40))), (0.9, V((0.12, -0.36, 0.10))), (1.12, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, V((0.0, 0.1, -1.0))), (0.9, V((0.3, -0.9, 0.3))), (1.12, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, V((1.0, -0.8, 0.1))), (b, V((0.6, -1.0, -0.2))), (1.12, CARRY['pole_r'])], t)
    # 左手は鎖を掴んで右手と一緒に引く（体の前 → 右の腰）
    p.hand_l = arc([(0, V((0.06, -0.34, -0.24))), (a, V((0.10, -0.30, -0.30))), (0.58, V((0.30, -0.28, -0.20)), 'i2'),
                    (b, V((0.38, -0.36, 0.02)), 'o'), (0.9, V((0.34, -0.36, 0.0))), (1.12, CARRY['hand_l'], 'io')], t)
    p.thumb_l = dirs([(0, CARRY['thumb_l']), (a, V((0.6, 0.0, -0.8))), (b, V((0.9, -0.2, 0.3))), (1.12, CARRY['thumb_l'])], t)
    p.shrug['right'] = (val([(0, 6), (a, 6), (b, 18, 'o'), (0.9, 14), (1.12, 6)], t), val([(0, 10), (b, -12, 'o'), (1.12, 0)], t))
    p.shrug['left'] = (val([(0, 4), (b, 14, 'o'), (1.12, 4)], t), val([(0, 0), (b, 16, 'o'), (1.12, 0)], t))
    return p


S2_HIT = 0.27   # Kit_H034.shockDelay


def skill_shock(rest, t):
    """S2 1.03 秒: 伸び上がって鉤を頭の上へ → 0.27 秒に右前の地面へ叩きつけ、深くかがんで 0.6 秒まで → 構え。"""
    s = S2_HIT
    p, yaw, dr = skill_base(rest, t,
                            [(0, 0), (0.12, -14, 'o2'), (0.20, -18), (s, 4, 'i'), (0.6, 2), (0.95, 0, 'io')],
                            [(0, 0), (0.12, -22, 'o2'), (0.20, -28), (s, 6, 'i'), (0.6, 4), (0.95, 0, 'io')],
                            [(0, 0), (0.12, -12, 'o2'), (0.21, -14), (s, 52, 'i'), (0.38, 56, 'o'), (0.6, 52), (0.95, 0, 'io')],
                            [(0, 0), (0.06, 0.04, 'o2'), (0.15, -0.05, 'io'), (0.19, -0.04), (s, 0.22, 'i2'), (0.38, 0.24, 'o'), (0.6, 0.22),
                             (0.95, 0, 'io')],
                            [(0, (0, 0)), (0.10, (0.0, 0.0)), (0.18, (-0.12, 0.07), 'o2'), (s, (-0.34, 0.0), 'io'), (0.62, (-0.34, 0.0)),
                             (0.8, (-0.12, 0.04), 'io'), (0.95, (0, 0), 'o')],
                            back=[(0, 0), (0.15, 0.02), (s, 0.14, 'i2'), (0.62, 0.14), (0.95, 0, 'io')],
                            forward=[(0, 0), (0.18, -0.02), (s, 0.10, 'i'), (0.62, 0.10), (0.95, 0, 'io')])
    up, _ = swing([(0.02, -95, -60, 0.30), (0.08, -130, 20, 0.30, 'o2'), (0.14, -150, 70, 0.30, 'io'), (0.21, -90, 86, 0.34),
                   (0.235, -20, 60, 0.38, 'i2')], t, yaw, dr)
    down = val([(0.235, V((0.25, 2.15, -0.45))), (0.25, V((0.32, 1.50, -0.82)), 'l'), (s, V((0.34, HEAD_R, -0.88)), 'i2'),
                (0.34, V((0.34, HEAD_R + 0.07, -0.86)), 'o'), (0.46, V((0.34, HEAD_R + 0.01, -0.85))), (0.62, V((0.34, HEAD_R + 0.01, -0.85)))], t)
    k = smooth((t - 0.235) / 0.015)
    head = up.lerp(down, k)
    _, sw = hook_strike(head, yaw, dr)
    p.strike = (head, sw, strike_weight(t, 0.0, 0.05, 0.62, 0.80), shoulder_est(yaw, dr), 1 - k)
    p.hand_r = arc([(0, CARRY['hand_r']), (0.62, V((0.02, -0.34, -0.30))), (0.80, V((0.10, -0.28, -0.26)), 'io'), (0.97, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (0.62, V((0.1, -0.7, -0.7))), (0.80, V((0.1, -1.0, -0.2)), 'io'), (0.97, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.14, V((1.0, 0.4, 0.4))), (s, V((1.0, -0.8, 0.3))), (0.97, CARRY['pole_r'])], t)
    # 左腕: 振り上げで左の外へ広げ、叩きつけで左膝の前へ（体を支える）
    p.hand_l = arc([(0, CARRY['hand_l']), (0.16, V((-0.30, -0.18, -0.10)), 'o2'), (s, V((0.02, -0.40, -0.18)), 'i2'),
                    (0.62, V((0.02, -0.40, -0.18))), (0.95, CARRY['hand_l'], 'io')], t)
    p.shrug['right'] = (val([(0, 6), (0.16, 24, 'o2'), (s, 0, 'i'), (0.62, 2), (0.95, 6)], t), 0.0)
    p.head = (p.head[0], p.head[1] + val([(0, 0), (0.16, 10), (s, -18, 'i'), (0.62, -16), (0.95, 0, 'io')], t))
    return p


ULT_GRAB = 0.25     # Kit_H034.ultDelay（掴む = 1 撃目）
ULT_GAP = 0.32      # Kit_H034.ultInterval
ULT_END = ULT_GRAB + 1.8   # 拘束の終わり（ultDelay + ultSuppress）
# 6 撃目の叩きつけが地を打つ時刻（MLBB は 11.63〜11.67 秒 = 発動 + 1.66〜1.70 秒に地面の光の輪。判定の 6 撃目 1.85 秒で最も深く沈む）
ULT_SLAM = 1.68


def skill_hunt(rest, t):
    """奥義 2.33 秒: 掴みかかり（0.25）→ 横なぎ・返しを 4 回（0.57 / 0.89 / 1.21 / 1.53）→ 頭の上から叩きつけ（1.68 に地を打ち、
    判定の 1.85 で最も深く）→ 2.05 まで沈む。"""
    g = ULT_GRAB
    beats = [g + ULT_GAP * k for k in range(6)]
    last = beats[5]
    # 体: 掴みかかりで低く前へ倒れ込み、2〜5 撃は振りかぶり（右へひねる / 左へひねる）と振り抜きを交互に。6 撃目は最も深く
    hy = [(0, 0), (0.12, -6, 'o2'), (g, -4)]
    ty = [(0, 0), (0.12, -10, 'o2'), (g, -6)]
    ln = [(0, 0), (0.12, 30, 'o2'), (g, 26)]
    dr = [(0, 0), (0.12, 0.12, 'o2'), (g, 0.10)]
    keys = [(0.02, -95, -60, 0.30), (0.12, -60, -10, 0.34, 'o2'), (g, -30, -6, 0.36, 'io')]
    for k, b in enumerate(beats[1:5]):
        right = k % 2 == 0        # 2・4 撃 = 右 → 左の横なぎ、3・5 撃 = 左 → 右の返し
        s = -1 if right else 1
        wind = b - 0.13
        hy += [(wind, 26 * s, 'o2'), (b, -14 * s, 'i2')]
        ty += [(wind, 42 * s, 'o2'), (b, -20 * s, 'i2')]
        ln += [(wind, 6, 'o2'), (b, 32, 'i2')]
        dr += [(wind, 0.04, 'o2'), (b, 0.13, 'i2')]
        if right:
            keys += [(wind, -130, 14, 0.34, 'o2'), (b - 0.04, -70, 2, 0.40, 'i2'), (b, -10, -12, 0.41, 'l'), (b + 0.08, 70, -32, 0.36, 'o')]
        else:
            keys += [(wind, 110, 30, 0.30, 'o2'), (b - 0.04, 60, 30, 0.38, 'i2'), (b, 5, -8, 0.41, 'l'), (b + 0.08, -70, -32, 0.36, 'o')]
    # 6 撃目: 右の後ろの高い所 → 頭の上 → 前の地面
    wind = ULT_SLAM - 0.11
    hy += [(wind, -24, 'o2'), (ULT_SLAM, 4, 'i'), (last, 6, 'o'), (ULT_END, 4), (2.3, 0, 'io')]
    ty += [(wind, -38, 'o2'), (ULT_SLAM, 8, 'i'), (last, 10, 'o'), (ULT_END, 8), (2.3, 0, 'io')]
    ln += [(wind, 14, 'io'), (ULT_SLAM, 46, 'i2'), (last, 56, 'o'), (ULT_END, 52), (2.3, 0, 'io')]
    dr += [(wind, 0.08, 'io'), (ULT_SLAM, 0.20, 'i2'), (last, 0.26, 'o'), (ULT_END, 0.24), (2.3, 0, 'io')]
    keys += [(wind, -150, 60, 0.30, 'o2'), (ULT_SLAM - 0.025, -40, 84, 0.34, 'i2')]
    p, yaw, drop = skill_base(rest, t, hy, ty, ln, dr,
                              [(0, (0, 0)), (0.05, (-0.10, 0.07), 'o2'), (0.14, (-0.34, 0.0), 'i2'), (ULT_SLAM - 0.1, (-0.34, 0.0)),
                               (ULT_SLAM, (-0.38, 0.0), 'i2'), (ULT_END, (-0.38, 0.0)), (2.25, (-0.10, 0.04), 'io'), (2.32, (0, 0), 'o')],
                              back=[(0, 0), (0.14, 0.10, 'i2'), (ULT_SLAM, 0.14), (ULT_END, 0.14), (2.3, 0, 'io')],
                              forward=[(0, 0), (0.14, 0.14, 'o'), (g, 0.10), (ULT_SLAM - 0.1, 0.06), (ULT_SLAM, 0.14, 'i'), (ULT_END, 0.14),
                                       (2.3, 0, 'io')])
    up, _ = swing(keys, t, yaw, drop)
    down = val([(ULT_SLAM - 0.025, V((0.20, 2.10, -0.40))), (ULT_SLAM - 0.01, V((0.26, 1.45, -0.85)), 'l'),
                (ULT_SLAM, V((0.28, HEAD_R, -0.90)), 'i2'), (ULT_SLAM + 0.08, V((0.28, HEAD_R + 0.06, -0.88)), 'o'),
                (last, V((0.28, HEAD_R + 0.01, -0.87))), (ULT_END, V((0.28, HEAD_R + 0.01, -0.87)))], t)
    k = smooth((t - (ULT_SLAM - 0.025)) / 0.015)
    head = up.lerp(down, k)
    _, sw = hook_strike(head, yaw, drop)
    if t < ULT_SLAM - 0.03:
        sw = swing(keys, t, yaw, drop)[1]
    p.strike = (head, sw, val([(0, 0.0), (0.05, 1.0, 'o2'), (ULT_END, 1.0), (2.22, 0.0, 'io')], t), shoulder_est(yaw, drop), 1 - k)
    p.hand_r = arc([(0, CARRY['hand_r']), (ULT_END, V((0.0, -0.34, -0.32))), (2.33, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (ULT_END, V((0.1, -0.6, -0.8))), (2.33, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.12, V((1.0, -0.6, 0.4))), (ULT_SLAM - 0.1, V((1.0, -0.2, 0.3))), (ULT_SLAM, V((1.0, -0.8, 0.3))),
                     (2.33, CARRY['pole_r'])], t)
    # 左手: 掴みかかりで前へ伸ばして相手を掴み（0.25）、掴んだまま胸の前に保つ（6 撃目で離して膝の前へ）
    p.hand_l = arc([(0, CARRY['hand_l']), (0.12, V((0.12, -0.10, -0.42)), 'o2'), (g, V((0.14, -0.14, -0.40))),
                    (ULT_SLAM - 0.12, V((0.14, -0.16, -0.38))), (ULT_SLAM, V((0.04, -0.40, -0.18)), 'i2'), (ULT_END, V((0.04, -0.40, -0.18))),
                    (2.3, CARRY['hand_l'], 'io')], t)
    p.thumb_l = dirs([(0, CARRY['thumb_l']), (0.12, V((0.3, 1.0, -0.2))), (ULT_SLAM - 0.12, V((0.3, 1.0, -0.2))), (ULT_SLAM, CARRY['thumb_l'])], t)
    p.grip['left'] = val([(0, 0.85), (0.10, 0.2), (g, 1.0, 'o2'), (ULT_SLAM - 0.1, 1.0), (ULT_SLAM, 0.85)], t)
    p.shrug['left'] = (val([(0, 4), (0.12, 12), (ULT_SLAM, 4), (2.3, 4)], t), val([(0, 0), (0.12, 14), (ULT_SLAM, 0)], t))
    p.shrug['right'] = (val([(0, 6), (ULT_SLAM - 0.11, 22, 'o2'), (ULT_SLAM, 0, 'i'), (2.3, 6)], t), 0.0)
    return p


# MARK: - 書き出し

def ankle_low(rig, P):
    return min(P[rig.index['leftfoot']].y - rig.P0[rig.index['leftfoot']].y,
               P[rig.index['rightfoot']].y - rig.P0[rig.index['rightfoot']].y)


def lifted(p, lift):
    if lift > 0:
        for side in ('left', 'right'):
            p.feet[side] = p.feet[side] + V((0, lift, 0))
    return p


def settle_lifts(rig, make, n, loop, limit=-0.004, rounds=3):
    """実行時はフレームの間を区間の回転の補間で引くので、腰が 1 フレームで大きく沈む所（叩きつけ）では接地した足が弧を描いて
    地面へ沈む（HeroFullBodyMotionTests の 1 cm を越えた: S2 0.25 秒 −2.4 cm）。沈む区間の前後のフレームの足首の目標を沈みの分だけ上げる
    （上げるのは最大 2 フレーム・速い動きの最中だけで、目では見えない）。返り値: フレームごとの持ち上げ（m）。"""
    lifts = [0.0] * n
    for _ in range(rounds):
        frames = []
        for f in range(n):
            t = f / n if loop else f / FPS
            qs, offset, details, _ = build(rig, lifted(make(t), lifts[f]))
            frames.append((qs, offset, details))
        worst = 0.0
        for f in range(1, n):
            a, b = frames[f - 1], frames[f]
            low = 0.0
            for k in (0.25, 0.5, 0.75):
                qm = [cm.slerp(x, y, k) for x, y in zip(a[0], b[0])]
                dm = {r: cm.slerp(a[2][r], b[2][r], k) for r in a[2]}
                _, Pm = solve(rig, qm, a[1].lerp(b[1], k), dm)
                low = min(low, ankle_low(rig, Pm))
            if low < limit:
                for g in (f - 1, f):
                    lifts[g] = min(0.03, lifts[g] + (-low + 0.002))
            worst = min(worst, low)
        if worst >= limit:
            break
    return lifts

def author(rig, out):
    rest = Rest(rig)
    attack = dict(frames=23, loop=False, events=dict(impact=round(ATTACK_IMPACT * FPS, 2), end=22), blend=0.10, rootXZ=1,
                  local='H034-mlbb-attack')
    skill = dict(loop=False, rootXZ=1, local='H034-mlbb-skill')
    specs = [
        dict(name='idle_h034', frames=132, loop=True, make=lambda u: idle(rest, u), blend=0.25, local='H034-mlbb-guard'),
        dict(name='run_h034', frames=GAIT['frames'], loop=True, make=lambda u: locomotion(rest, u),
             blend=0.12, groundSpeed=GAIT['speed'], local='H034-mlbb-gait'),
        dict(name='chain_sweep_h034', make=lambda t: attack_sweep(rest, t), **attack),
        dict(name='chain_backhand_h034', make=lambda t: attack_backhand(rest, t), **attack),
        dict(name='chain_chop_h034', make=lambda t: attack_chop(rest, t), **attack),
        dict(name='hook_throw_h034', frames=46, events=dict(impact=round(S1_RELEASE * FPS, 2), end=45), make=lambda t: skill_hook(rest, t),
             blend=0.06, **skill),
        dict(name='hook_pull_h034', frames=34, events=dict(impact=21, end=33), make=lambda t: skill_pull(rest, t), blend=0.05, **skill),
        dict(name='chain_smash_h034', frames=31, events=dict(impact=round(S2_HIT * FPS, 2), end=30), make=lambda t: skill_shock(rest, t),
             blend=0.06, **skill),
        dict(name='chain_frenzy_h034', frames=70, events=dict(impact=round(ULT_GRAB * FPS, 2), end=69), make=lambda t: skill_hunt(rest, t),
             blend=0.06, **skill),
    ]
    clips, report = [], {}
    for sp in specs:
        loop, n = sp['loop'], sp['frames']
        c = dict(name=sp['name'], source=f"local:{sp['local']}", frames=n, loop=loop, rootXZ=sp.get('rootXZ', 0), melee=not loop,
                 events=sp.get('events', {}), rot=[], root=[], detailJoints=[r for r in DETAILS if r in rig.index], detailRot=[],
                 blend=sp['blend'])
        if 'groundSpeed' in sp:
            c['groundSpeed'] = sp['groundSpeed']
        prev, pd = [None] * 15, [None] * len(c['detailJoints'])
        lifts = settle_lifts(rig, sp['make'], n, loop)
        errors, ground, limbs, heads, mids = [], [], [], [], []
        last = None
        for f in range(n):
            t = f / n if loop else f / FPS
            qs, offset, details, err = build(rig, lifted(sp['make'](t), lifts[f]))
            for i, q in enumerate(qs):
                vals, prev[i] = pack(q, prev[i])
                c['rot'] += vals
            c['root'] += [round(x / rig.leg_length, 5) for x in offset]
            for i, role in enumerate(c['detailJoints']):
                vals, pd[i] = pack(details[role], pd[i])
                c['detailRot'] += vals
            errors.append(err)
            limbs = [max(x, y) for x, y in zip(limbs, build.last)] if f else list(build.last)
            _, P = solve(rig, qs, offset, details)
            heads.append(hook_head(rig, qs, P).y - HEAD_R)
            ground.append(ankle_low(rig, P))
            # 実行時はフレームの間を回転の補間で引くので、接地した足がフレームの間で沈まないかも測る（HeroFullBodyMotionTests の 1 cm）
            if last is not None:
                for k in (0.25, 0.5, 0.75):
                    qm = [cm.slerp(a, b, k) for a, b in zip(last[0], qs)]
                    om = last[1].lerp(offset, k)
                    dm = {r: cm.slerp(last[2][r], details[r], k) for r in details}
                    _, Pm = solve(rig, qm, om, dm)
                    mids.append((ankle_low(rig, Pm), f - 1 + k))
            last = (qs, offset, details)
        clips.append(c)
        end = 1.0 if loop else (n - 1) / FPS
        a, _, _, _ = build(rig, sp['make'](0))
        b, _, _, _ = build(rig, sp['make'](end))
        report[c['name']] = dict(frames=n, maxTargetMissMm=round(max(errors) * 1000, 2),
                                 boundaryDegrees=round(max(cm.quat_angle_deg(x, y) for x, y in zip(a, b)), 3),
                                 lowestAnkleVsRestMm=round(min(ground) * 1000, 1),
                                 lowestBetweenFramesMm=round(min(mids)[0] * 1000, 1) if mids else 0.0,
                                 lowestBetweenFramesAt=round(min(mids)[1], 2) if mids else 0.0,
                                 maxFootLiftMm=round(max(lifts) * 1000, 1),
                                 hookHeadClearanceMm=round(min(heads) * 1000, 1),
                                 missMm=dict(zip(('footL', 'footR', 'handR', 'handL'), [round(x * 1000, 1) for x in limbs])))
    out.write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=clips), separators=(',', ':')) + '\n')
    return report


def main():
    rig, _, height, warnings = preview.load_hero(str(Path(HERO).resolve()))
    axis_error = bind_usd_axes(rig, HERO)
    report = author(rig, Path('App/Resources/Heroes/H034MotionClips.json'))
    report['model'] = dict(height=height, bones=len(rig.names), fingers='righthandindex1' in rig.index,
                           importedVsUSDJointAxesDegrees=axis_error, warnings=warnings)
    Path('build/h034-motion').mkdir(parents=True, exist_ok=True)
    Path('build/h034-motion/finish-report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
