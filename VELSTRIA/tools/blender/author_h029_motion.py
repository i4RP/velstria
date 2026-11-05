"""H029 ボルグの待機・移動・通常攻撃・スキルの仕上げ（Blender 5.x、実行時と同じリグの計算）。

Meshy prime（tools/motion/h029-prime-source-clips.json）から、移動の腰・胴の揺れ（周期を切り出して継ぎ目を混ぜる）と、
攻撃・スキルの体の流れ（振りかぶり → 溜め → 打ち下ろし → 反動）の時間配分を取り、手足は H029 の実寸で拘束して仕上げる:
  - 足: 接地中は地面に固定（移動は移動速度を打ち消す一定速度）、離地は弧。膝は前・やや外。
  - 右手: 聖槌の柄の向き（手の区間の -Z = 親指の側）を指定し、手首の曲がり（尺屈・橈屈）を 55〜130° に収める。
  - 左手: 盾の前腕を胸の前で横に構える（offhandGrip = 手の区間に対する盾、HeroMotionSets の H029）。
  - 肩（鎖骨）・指・つま先は detailJoints（局所のレスト後差分）。
打撃の時刻は KitTimes（Kit_H029.Tune）と同じ値に置く: S1 0.25 / S2 突進 0.67 / S2 再使用 0.2 / ULT 1.0 秒。
実行時は Motion_H029.clipStrike（KitTimes）からクリップの開始位置を決め直すので、ここは見た目の基準。
VELSTRIA/ で: /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/author_h029_motion.py
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
SCALE = 1.0   # HeroBlueprints の H029（motion.scale。2026-11-05 に 1.32 → 1.0）。groundSpeed はゲームの m/s
# Blender 4.5 は揺れ物の骨（finish_h029_cape.py）を足した USD の取り込みで落ちるので、骨を足す前の元（finish が書き出す）を使う。
# クリップが動かす骨は同じ（揺れ物の骨は実行時の HeroSecondaryMotion だけが動かす）
_BASE = 'build/h029-motion/Hero_H029_base.usdz'
HERO = _BASE if Path(_BASE).exists() else 'App/Resources/Heroes/Hero_H029.usdz'
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
    """keys = [(time, value, ease?)]。ease は前のキーからこのキーまでの区間の緩急。返り値 (i, u, ease)。"""
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
    """二骨 IK + 手首。thumb = 手の区間の -Z（右手は聖槌の柄、左手は盾の上）。前腕のひねりは fore_twist の割合だけ持たせ、
    上腕は前腕から肘の蝶番で起こした向き（ひねりは肩の球関節）。返り値: 目標に届かなかった距離（m）。"""
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
    # 前腕: 骨は F、ひねりは手の親指の向きへ fore_twist だけ寄せる（残りは手首）
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


# 盾の持ち方（HeroMotionSets.borgShieldGrip と同じ）: 盾の上 +Y = 手の区間の肘の側 +Y を親指の側 -Z へ SHIELD_TILT だけ倒した向き、
# 盾の外の面 -Z = 手の甲の側 -X。前腕を SHIELD_TILT だけ前へ出して下げた腕（MLBB の左脇に縦に下げた盾）で盾が鉛直に立つ。
SHIELD_TILT = math.radians(15)


def shield_hand(U, N):
    """盾の上 U と外の面の向き N（ヒーロー空間）になる左手の区間回転（borgShieldGrip の逆）。"""
    U = U.normalized()
    X = -(N - U * N.dot(U)).normalized()
    W = X.cross(U)
    c, s = math.cos(SHIELD_TILT), math.sin(SHIELD_TILT)
    Y = U * c + W * s
    Z = -U * s + W * c
    return frame(-Y, -Z)


# MARK: - prime の素材

class Prime:
    def __init__(self, clips):
        self.clips = clips

    def body(self, name, f):
        """腰・胴・頭（ヒーロー空間の区間回転）と腰の位置（m 換算前、脚の長さ単位）。"""
        q, root = cm.interp_clip(self.clips[name], f)
        return q[0], q[1], q[2], root

    def cycle(self, name, f0, f1, u):
        """f0〜f1 の 1 周を u（0〜1）で引く。終わりの 15% は先頭へ混ぜて継ぎ目を消す。"""
        f = f0 + (f1 - f0) * (u % 1)
        h, t, hd, root = self.body(name, f)
        w = smooth(((u % 1) - 0.85) / 0.15)
        if w > 0:
            h0, t0, hd0, r0 = self.body(name, f0)
            h, t, hd = cm.slerp(h, h0, w), cm.slerp(t, t0, w), cm.slerp(hd, hd0, w)
            root = root.lerp(r0, w)
        return h, t, hd, root


def relative(q, q0, weight):
    """q0 からの差分を weight 倍（揺れの量を抑えて手付けの姿勢へ重ねる）。"""
    return cm.slerp(Quaternion(), (q @ q0.inverted()).normalized(), weight)


# MARK: - 構え（待機・攻撃・スキルの始まりと終わり）

class Rest:
    def __init__(self, rig):
        self.rig = rig
        P0 = rig.P0
        self.ankle = {s: P0[rig.index[s + 'foot']].copy() for s in ('left', 'right')}
        self.leg = rig.leg_length
        self.hipY = P0[rig.index['hips']].y

    def foot(self, side, dx=0.0, dz=0.0, dy=0.0):
        a = self.ankle[side].copy()
        a.x = (-0.235 if side == 'left' else 0.235) + dx
        a.z = (-0.10 if side == 'left' else 0.11) + dz
        a.y += dy
        return a


GUARD = dict(hips=(-6, 4, 0), torso=(-4, 5, 0), head=(4, -3), drop=0.115,
             hand_r=V((0.17, -0.42, -0.10)), shaft=V((0.28, 0.92, -0.28)),
             hand_l=V((0.22, -0.26, -0.37)), shield_up=V((0.05, 1.0, 0.0)))


class Pose:
    """1 フレームの手付けの値（体の角度・腰・手足の目標）。"""

    def __init__(self, rest):
        self.rest = rest
        self.hips = GUARD['hips']
        self.torso = GUARD['torso']
        self.head = GUARD['head']
        self.offset = V((0, -GUARD['drop'], 0))
        self.hand_r = GUARD['hand_r'].copy()     # 右肩からの手（胴の向きで回す）
        self.shaft = GUARD['shaft'].copy()       # 聖槌の柄（胴の向きで回す）
        self.hand_l = GUARD['hand_l'].copy()     # 左肩からの手
        self.shield_up = GUARD['shield_up'].copy()
        self.feet = {'left': rest.foot('left'), 'right': rest.foot('right')}
        self.roll = {'left': 0.0, 'right': 0.0}
        self.toe = {'left': 0.0, 'right': 0.0}
        self.shrug = {'left': (0.0, 4.0), 'right': (0.0, 0.0)}
        self.grip = {'left': 0.9, 'right': 1.0}
        self.regrip = 0.0
        self.texture = None   # prime の (hips, torso, head) 差分
        self.pole_r = V((1.0, -0.6, 0.6))
        self.pole_l = V((-1.0, -0.8, 0.2))
        self.knee_out = 0.35
        # 打撃の間だけ、聖槌の頭（ヒーロー空間）と柄の向きで右手を決める: (頭, 柄, 重み)
        self.strike = None
        # 盾の向き（胴の座標の (上, 外の面)）。None = 旧来の shield_up（左手の親指の側 = 盾の上の旧い持ち方）から決める
        self.shield = None


# MLBB のティグラルの構え（2026-10-15 / 10-18 の画面収録）: 聖槌は右肩に担ぐ（右手は胸の前で柄を握り、柄は右肩の上を通って
# 槌頭は肩の後ろ上。石突きは手の前下へ出る）。盾は左腕に下げて左脇に縦に立てる（上の縁が肩、下の縁が膝の上。外の面は外・やや後ろ）。
CARRY = dict(hips=(-3, 2, 0), torso=(-2, 3, 0), head=(2, -2), drop=0.05,
             hand_r=V((-0.16, -0.05, -0.29)), shaft=V((0.20, 0.46, 0.86)), pole_r=V((0.9, -1.0, 0.2)),
             hand_l=V((-0.07, -0.46, -0.11)), pole_l=V((-0.5, -0.2, 1.0)),
             shield=(V((0.0, 1.0, 0.0)), V((-1.0, 0.0, 0.45))))


def carry_pose(rest):
    p = Pose(rest)
    p.hips, p.torso, p.head = CARRY['hips'], CARRY['torso'], CARRY['head']
    p.offset = V((0, -CARRY['drop'], 0))
    p.hand_r, p.shaft, p.pole_r = CARRY['hand_r'].copy(), CARRY['shaft'].copy(), CARRY['pole_r'].copy()
    p.hand_l, p.pole_l = CARRY['hand_l'].copy(), CARRY['pole_l'].copy()
    p.shield = (CARRY['shield'][0].copy(), CARRY['shield'][1].copy())
    p.shrug = {'left': (0.0, 0.0), 'right': (4.0, 0.0)}
    return p


MAUL_HEAD = 1.08   # 握りから槌頭の中心まで（HeroGear の holyMaul、Prop はこの高さに合わせて拡縮）
HEAD_HALF = 0.23   # 槌頭の半分の高さ（打撃面の当て金 0.46）


def maul_head(rig, qs, P):
    q = qs[cm.SEG_INDEX['handR']]
    j = rig.index['righthand']
    grip = 0.6 * (rig.P0[rig.index['righthandindex1']] - rig.P0[j]).length if 'righthandindex1' in rig.index else 0.06
    return P[j] + q @ V((0, -grip, 0)) + q @ V((0, 0, -MAUL_HEAD))


def build(rig, p):
    qs = [Quaternion() for _ in range(15)]
    qh = body_q(*p.hips)
    qt = qh @ body_q(*p.torso)
    qd = qt @ body_q(p.head[0], p.head[1], 0)
    if p.texture:
        th, tt, td = p.texture
        qh, qt, qd = th @ qh, tt @ qt, td @ qd
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
        head, sw, w = V(p.strike[0]), V(p.strike[1]).normalized(), p.strike[2]
        shaft = cm.slerp(Quaternion(), cm.rotation_between(shaft.normalized(), sw), w) @ shaft.normalized()
        target = target.lerp(head - shaft * MAUL_HEAD, w)
        # 手首の曲がりの制限（柄と前腕 55〜130°）と握りの分で槌頭がずれるので、槌頭が目標へ来るまで手の目標を寄せ直す
        for _ in range(6):
            arm_ik(rig, qs, offset, details, 'right', target, qt @ p.pole_r, shaft)
            _, P1 = solve(rig, qs, offset, details)
            miss = head - maul_head(rig, qs, P1)
            if miss.length < 0.004:
                break
            target = target + miss * w
            want = head - P1[rig.index['righthand']]
            if want.length > 1e-3:
                shaft = cm.slerp(Quaternion(), cm.rotation_between(shaft, want.normalized()), w) @ shaft
    err = arm_ik(rig, qs, offset, details, 'right', target, qt @ p.pole_r, shaft)
    # 槌頭を地面より下へ入れない・打撃では手が届かない分を柄の傾きで地面まで届かせる（握りを支点に柄を起こす / 倒す）
    _, P1 = solve(rig, qs, offset, details)
    head = maul_head(rig, qs, P1)
    want = None
    if p.strike and p.strike[2] > 0.5 and head.y > V(p.strike[0]).y + 0.01:
        want = V(p.strike[0]).y
    if head.y < HEAD_HALF:
        want = HEAD_HALF
    if want is not None:
        q = qs[cm.SEG_INDEX['handR']]
        grip = head - q @ V((0, 0, -MAUL_HEAD))
        dy = max(-0.97, min(0.97, (want - grip.y) / MAUL_HEAD))
        flat = V((head.x - grip.x, 0, head.z - grip.z))
        if flat.length < 1e-4:
            flat = qt @ V((0, 0, -1))
            flat.y = 0
        flat.normalize()
        s2 = flat * math.sqrt(1 - dy * dy) + V((0, dy, 0))
        err = arm_ik(rig, qs, offset, details, 'right', P1[rig.index['righthand']], qt @ p.pole_r, s2, dev=(40, 140))
    errors.append(err if not p.strike or p.strike[2] < 0.5 else 0.0)
    hl = cm.SEG_INDEX['handL']
    if p.shield:
        want = shield_hand(qt @ p.shield[0], qt @ p.shield[1])
        errors.append(arm_ik(rig, qs, offset, details, 'left', sl + qt @ p.hand_l, qt @ p.pole_l, want @ V((0, 0, -1)),
                             dev=(0, 180)))
    else:
        errors.append(arm_ik(rig, qs, offset, details, 'left', sl + qt @ p.hand_l, qt @ p.pole_l, qt @ p.shield_up,
                             dev=(60, 120)))
        # 旧い持ち方（盾の上 = 親指の側、外の面 = 手の甲）の盾の向きを保って、今の持ち方の手へ直す
        old = qs[hl]
        want = shield_hand(old @ V((0, 0, -1)), old @ V((-1, 0, 0)))
    qs[hl] = want
    fore = qs[cm.SEG_INDEX['foreArmL']] @ V((0, -1, 0))
    build.wrist = math.degrees(fore.angle(want @ V((0, -1, 0))))
    build.last = errors
    return qs, offset, details, max(errors)


# MARK: - 各クリップ

def guard_texture(prime, t, w=0.35):
    h, tt, hd, _ = prime.cycle('h029_idle_prime', 0, 119, t)
    h0, t0, hd0, _ = prime.body('h029_idle_prime', 0)
    return relative(h, h0, w), relative(tt, t0, w), relative(hd, hd0, w)


def idle(rest, prime, u):
    """4 秒の待機（ループ）。槌を右肩に担ぎ、盾を左脇に下げた MLBB の立ち姿。重い呼吸 1 回、頭をゆっくり上げて戻す、
    柄の握り直し（0.55〜0.75）。槌と盾は呼吸に乗って僅かに上下するだけ。"""
    p = carry_pose(rest)
    breath = math.sin(u * math.tau)            # 0 → 吸う → 0 → 吐く
    lift = 0.5 - 0.5 * math.cos(u * math.tau)  # 頭・胸を上げる（周期の中ほどで最大）
    p.offset.y += 0.006 * breath - 0.004 * lift
    h0, t0, d0 = CARRY['hips'], CARRY['torso'], CARRY['head']
    p.hips = (h0[0], h0[1] + 0.6 * breath, 0.4 * math.sin(u * math.tau + 0.6))
    p.torso = (t0[0] + 1.2 * math.sin(u * math.tau + 1.1), t0[1] - 2.0 * breath - 1.5 * lift, 0)
    p.head = (d0[0] - 2.5 * lift, d0[1] - 6.0 * lift + 1.0 * breath)
    for side in ('left', 'right'):
        p.shrug[side] = (p.shrug[side][0] + 1.8 * max(0.0, breath) + 0.6 * lift, p.shrug[side][1])
    p.regrip = 0.28 * math.sin(math.pi * smooth((u - 0.55) / 0.2)) ** 2 if 0.55 < u < 0.75 else 0.0
    p.hand_r = CARRY['hand_r'] + V((0, 0.008 * breath, 0))
    p.hand_l = CARRY['hand_l'] + V((0, 0.006 * breath, -0.004 * breath))
    p.texture = guard_texture(prime, u, 0.25)
    return p


# 移動（MLBB の画面収録 10-18 の 35.7〜36.3 秒・28.5〜29.0 秒、10-15 の 3.3〜4.2 秒）: 槌を肩に担ぎ盾を脇に下げたまま
# 重く小走りする。脚の開きの山が 約 7 コマごと = 1 周 14 コマ（0.467 秒、毎秒 4.3 歩）。MLBB の歩幅は 2.6 / 秒 × 0.467 = 1.21 単位。
# Velstria のヒーローは mapScale 1.35 倍速く動く（260 × 1.35 = 毎秒 3.51 m）ので、歩調（コマ数）を MLBB に合わせ、
# 歩幅を 1.35 倍（1.64 m = ヒーロー空間 1.24）にした。減速中など遅い時は walk（1 周 0.733 秒）。
GAITS = {
    'run': dict(frames=14, speed=3.51, contact=0.44, lift=0.17, lean=10, bob=0.045, drop=0.075, width=0.21, knee=0.24,
                twist=9, hammer=0.03, shield=0.09),
    'walk': dict(frames=18, speed=1.80, contact=0.62, lift=0.10, lean=4, bob=0.022, drop=0.06, width=0.22, knee=0.24,
                 twist=6, hammer=0.018, shield=0.06),
}


def locomotion(rest, prime, u, run):
    """支持脚は移動速度を打ち消す一定速度で地面に固定、離地は弧。かかと接地 → つま先の蹴り出し。上半身は担いだ構えのまま、
    腰の上下（支持の中ほどで沈む）・腰のひねりと胴の打ち消し・盾の小さな前後の揺れ・槌の遅れた上下。"""
    g = GAITS['run' if run else 'walk']
    period = g['frames'] / FPS
    stride = g['speed'] * period / SCALE           # 1 周の歩幅（ヒーロー空間）
    contact = g['contact']
    reach = stride * contact / 2
    p = carry_pose(rest)
    lean = g['lean']
    w = math.tau * u
    bounce = math.cos(2 * (w - math.tau * contact / 2))   # 1 = 支持の中ほど（沈む）
    twist = math.cos(w)                                   # + = 右脚が前（腰は左へ回り、胴は打ち消す）
    p.hips = (CARRY['hips'][0] + g['twist'] * twist, CARRY['hips'][1] + lean * 0.5, 3.0 * math.sin(w))
    p.torso = (CARRY['torso'][0] - g['twist'] * 0.65 * twist, CARRY['torso'][1] + lean * 0.6 + 2.0 * bounce, -2.0 * math.sin(w))
    p.head = (CARRY['head'][0] - 2 * twist, CARRY['head'][1] - lean * 0.6 - 1.0 * bounce)
    # 重装の重い上下（支持の中ほどで沈み、蹴り出しで浮く）と、支持脚の側への腰の横の揺れ
    p.offset = V((0.022 * math.cos(w), -g['drop'] - g['bob'] * (0.5 + 0.5 * bounce), 0))
    for side, phase in (('right', u), ('left', u + 0.5)):
        x = g['width'] if side == 'right' else -g['width']
        ph = phase % 1
        foot = rest.ankle[side].copy()
        foot.x = x
        if ph < contact:
            v = ph / contact
            foot.z = -reach + 2 * reach * v
            roll = 24 * smooth((v - 0.74) / 0.26)   # 蹴り出しでかかとを上げる
            heel = -9 * (1 - smooth(v / 0.18))      # 着地はかかとから
            p.roll[side] = roll + heel
            p.toe[side] = -roll * 0.7
            foot.y += 0.06 * math.sin(D(max(0.0, roll)))
        else:
            v = (ph - contact) / (1 - contact)
            tangent = 2 * reach * (1 - contact) / contact
            foot.z = reach - 2 * reach * smooth(v) + tangent * (2 * v ** 3 - 3 * v * v + v)
            # 蹴り出した足は後ろで高く上がり（踵を蹴り上げ）、前へ振り出して下ろす
            foot.y += g['lift'] * math.sin(math.pi * v ** 0.75) ** 1.3
            p.roll[side] = 24 * (1 - smooth(v / 0.35)) - 12 * math.sin(math.pi * v) - 9 * smooth((v - 0.8) / 0.2)
            p.toe[side] = 0
        p.feet[side] = foot
    # 槌は肩に乗ったまま、体の上下に少し遅れて揺れる。盾の腕は左脚と逆に小さく前後する（右脚が前 = 盾が前）
    lag = math.cos(2 * (w - math.tau * contact / 2) - 0.9)
    p.hand_r = CARRY['hand_r'] + V((0.0, -g['hammer'] * lag, 0.0))
    p.shaft = (CARRY['shaft'] + V((0.0, 0.0, 2.0 * g['hammer'] * lag))).normalized()
    p.hand_l = CARRY['hand_l'] + V((0.012, 0.015 * (1 - abs(math.cos(w))), -g['shield'] * math.cos(w)))
    p.shield = (V((0.0, 1.0, 2.2 * g['shield'] * math.cos(w))).normalized(), CARRY['shield'][1].copy())
    p.knee_out = g['knee']
    return p, g['speed'], period


# MARK: - 通常攻撃（MLBB の 3 種の繰り返し）
#
# MLBB の画面収録 b（10-18）の 5.50 / 6.57 / 7.50 / 8.47 秒の命中（どれも「99」= 物理攻撃 × 防御）と a の 13.30 秒:
#   ① 横振り（右 → 左）: 肩から槌を外し（命中の 0.23 秒前）、右の後ろへ引いて（0.13 秒前）前を横に払い、左の後ろ下へ振り抜く
#   ② 返し（左 → 右）: 槌を頭の上から左肩の後ろへ回し（0.17 秒前）、前を左から右へ払い、右の後ろ下へ振り抜く
#   ③ 叩きつけ: 槌を右肩の上・後ろへ振りかぶり（0.23 秒前）、頭の上から前の地面へ縦に叩きつけ、槌頭を地面に置いて止まる
# 8.47 秒は ① に戻っていた（3 種の繰り返し）。命中の間隔は 約 1.0 秒。各クリップは構え（肩に担ぐ）で始まり構えで終わり、
# 続けて振る時は前の振り抜きの姿勢から次の振りかぶりへ混ぜる（HeroClipLayer の 0.12 秒）。命中は 0.27 秒（sim の windup へ合わせて伸縮）。
ATTACK_IMPACT = 0.27
ATTACK_END = 0.90
SHOULDER_R = V((0.22, 1.45, 0.03))


def ray(az, el):
    """右肩から見た向き（az 度: 0 = 前、+ = 左。el 度: + = 上）。"""
    a, e = D(az), D(el)
    return V((-math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)))


def swing(keys, t, yaw):
    """槌頭の軌道 keys = [(t, az, el, ext, ease?)]: 右肩（胴の向き yaw で回す）から向き (az, el) へ腕を ext（m）伸ばし、柄を
    同じ向きに伸ばした先が槌頭（腕と柄を一直線に払う）。向き・伸びを別に補間する（弧を描く）。返り値 (槌頭, 柄の向き)。"""
    i, u = seg([(k[0], 0, k[4] if len(k) > 4 else 'io') for k in keys], t)
    if i == 0:
        az, el, ext = keys[0][1:4]
    else:
        a, b = keys[i - 1], keys[i]
        az, el, ext = [x + (y - x) * u for x, y in zip(a[1:4], b[1:4])]
    d = ray(az, el)
    sh = ry(D(yaw)) @ SHOULDER_R
    return sh + d * (ext + MAUL_HEAD), d


def maul_strike(head, yaw):
    """槌頭の位置から (槌頭, 柄の向き)。柄は右肩（胴の向き yaw で回す）から槌頭への向き。"""
    sh = ry(D(yaw)) @ SHOULDER_R
    return head, (head - sh).normalized()


def attack_base(rest, t, hips_yaw, torso_yaw, lean, drop, step, back=None, shift=None):
    """通常攻撃の体（腰と胴のひねり・前傾・沈み・左足の踏み込み）。各引数は val の keys（step は左足の (dz, dy)、back は右足を
    後ろへ引く量、shift は腰の (横, 前後) のずれ = 体重の移り）。"""
    p = carry_pose(rest)
    hy, ty = val(hips_yaw, t), val(torso_yaw, t)
    ln = val(lean, t)
    p.hips = (CARRY['hips'][0] + hy, CARRY['hips'][1] + ln * 0.45, 0)
    p.torso = (CARRY['torso'][0] + ty, CARRY['torso'][1] + ln * 0.55, 0)
    p.head = (CARRY['head'][0] - ty * 0.5 - hy * 0.3, CARRY['head'][1] - ln * 0.4)
    p.offset = V((0, -CARRY['drop'] - val(drop, t), 0))
    st = val([(k[0], V((k[1][0], k[1][1], 0)), *k[2:]) for k in step], t)
    dz, dy = st.x, st.y
    p.feet['left'] = rest.foot('left', dz=dz, dy=dy)
    p.roll['left'] = -30 * dy / 0.06 if dy > 0 else 0
    lift = smooth((-dz - 0.04) / 0.08)
    p.roll['right'] = 10 * lift
    p.toe['right'] = -8 * lift
    if back:
        b = val(back, t)
        p.feet['right'] = rest.foot('right', dx=0.4 * b, dz=b)
        p.roll['right'] = max(p.roll['right'], 16 * smooth(b / 0.12))
        p.toe['right'] = min(p.toe['right'], -14 * smooth(b / 0.12))
        p.feet['left'] = p.feet['left'] + V((-0.25 * max(0.0, -dz), 0, 0))
    if shift:
        sh = val([(k[0], V((k[1][0], 0, k[1][1])), *k[2:]) for k in shift], t)
        p.offset.x += sh.x
        p.offset.z += sh.z
    p.knee_out = 0.45
    return p, hy + ty


def strike_weight(t, on, full, hold, off):
    return val([(on, 0.0), (full, 1.0, 'o2'), (hold, 1.0), (off, 0.0, 'io')], t)


def attack_sweep(rest, prime, t):
    """① 横振り（右 → 左）。"""
    imp = ATTACK_IMPACT
    p, yaw = attack_base(rest, t,
                         [(0, 0), (0.15, -22, 'o2'), (imp, 10, 'i2'), (0.42, 32, 'o'), (0.64, 30), (ATTACK_END, 0, 'io')],
                         [(0, 0), (0.15, -40, 'o2'), (imp, 14, 'i2'), (0.42, 48, 'o'), (0.64, 44), (ATTACK_END, 0, 'io')],
                         [(0, 0), (0.15, 4, 'o2'), (imp, 26, 'i2'), (0.42, 34, 'o'), (0.64, 30), (ATTACK_END, 0, 'io')],
                         [(0, 0), (0.15, 0.05, 'o2'), (imp, 0.15, 'i2'), (0.45, 0.19, 'o'), (0.64, 0.17), (ATTACK_END, 0, 'io')],
                         [(0, (0, 0)), (0.08, (0.0, 0.0)), (0.17, (-0.12, 0.07), 'o2'), (imp, (-0.36, 0.0), 'i2'), (0.66, (-0.36, 0.0)),
                          (0.80, (-0.12, 0.05), 'io'), (ATTACK_END, (0, 0), 'o')],
                         back=[(0, 0), (0.17, 0.02), (imp, 0.14, 'i2'), (0.66, 0.14), (ATTACK_END, 0, 'io')],
                         shift=[(0, (0, 0)), (0.15, (0.03, 0.03), 'o2'), (imp, (-0.01, -0.10), 'i2'), (0.45, (-0.06, -0.10), 'o'),
                                (0.64, (-0.05, -0.09)), (ATTACK_END, (0, 0), 'io')])
    p.hand_r = arc([(0, CARRY['hand_r']), (0.08, V((-0.10, -0.08, -0.32)), 'o2'), (0.62, V((-0.30, -0.36, -0.18))),
                    (0.75, V((-0.20, 0.05, -0.36)), 'io'), (ATTACK_END, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (0.08, V((0.15, 0.45, 0.88)), 'o2'), (0.62, V((-0.6, -0.6, 0.3))),
                    (0.75, V((0.1, 0.95, 0.25)), 'io'), (ATTACK_END, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.15, V((0.5, -1.0, 0.6))), (imp, V((0.6, -1.0, 0.0))), (0.6, V((0.2, -1.0, -0.4))),
                     (ATTACK_END, CARRY['pole_r'])], t)
    # 肩から外した槌頭を左の後ろの肩の高さへ回し（命中の 0.13 秒前、柄は背中を横切る）→ 背中の後ろ（0.07 秒前）→ 右 → 前の右（命中）
    # → 左の下へ。上から見て左回りの一続きの弧（MLBB の 5.30〜5.77 秒）
    p.strike = (*swing([(0.06, 185, 45, 0.06), (0.14, 140, 22, 0.08, 'o2'), (0.20, 190, 22, 0.14, 'i2'), (0.235, 262, 8, 0.24, 'l'),
                        (imp, 338, -20, 0.30, 'l'), (0.34, 400, -38, 0.28, 'o'), (0.45, 450, -50, 0.25, 'o'), (0.6, 456, -52, 0.24)], t, yaw),
                strike_weight(t, 0.04, 0.12, 0.56, 0.70))
    p.shrug['right'] = (val([(0, 4), (0.15, 12), (imp, 0, 'i2'), (0.6, -2), (ATTACK_END, 4)], t), 0.0)
    return p


def attack_backhand(rest, prime, t):
    """② 返し（左 → 右）。振りかぶりで盾は体の前へ来る（MLBB の 6.13〜6.43 秒）。"""
    imp = ATTACK_IMPACT
    p, yaw = attack_base(rest, t,
                         [(0, 0), (0.17, 24, 'o2'), (imp, -8, 'i2'), (0.43, -30, 'o'), (0.64, -28), (ATTACK_END, 0, 'io')],
                         [(0, 0), (0.17, 46, 'o2'), (imp, -12, 'i2'), (0.43, -46, 'o'), (0.64, -42), (ATTACK_END, 0, 'io')],
                         [(0, 0), (0.17, 6, 'o2'), (imp, 26, 'i2'), (0.43, 32, 'o'), (0.64, 28), (ATTACK_END, 0, 'io')],
                         [(0, 0), (0.17, 0.05, 'o2'), (imp, 0.15, 'i2'), (0.45, 0.19, 'o'), (0.64, 0.17), (ATTACK_END, 0, 'io')],
                         [(0, (0, 0)), (0.10, (0.0, 0.0)), (0.19, (-0.12, 0.07), 'o2'), (imp, (-0.34, 0.0), 'i2'), (0.66, (-0.34, 0.0)),
                          (0.80, (-0.11, 0.05), 'io'), (ATTACK_END, (0, 0), 'o')],
                         back=[(0, 0), (0.17, 0.02), (imp, 0.14, 'i2'), (0.66, 0.14), (ATTACK_END, 0, 'io')],
                         shift=[(0, (0, 0)), (0.17, (-0.04, 0.03), 'o2'), (imp, (0.01, -0.09), 'i2'), (0.45, (0.06, -0.09), 'o'),
                                (0.64, (0.05, -0.08)), (ATTACK_END, (0, 0), 'io')])
    p.hand_r = arc([(0, CARRY['hand_r']), (0.10, V((-0.22, 0.20, -0.22)), 'o2'), (0.17, V((-0.42, -0.02, -0.02)), 'io'),
                    (0.62, V((0.26, -0.42, -0.08))), (0.76, V((0.08, -0.20, -0.30)), 'io'), (ATTACK_END, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (0.10, V((0.0, 1.0, 0.15)), 'o2'), (0.17, V((-0.55, 0.35, 0.75)), 'io'),
                    (0.62, V((0.6, -0.6, 0.45))), (0.76, V((0.3, 0.5, 0.8)), 'io'), (ATTACK_END, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.17, V((0.3, -0.6, -1.0))), (imp, V((0.6, -1.0, 0.0))), (0.6, V((1.0, -0.6, 0.4))),
                     (ATTACK_END, CARRY['pole_r'])], t)
    # 左肩の後ろ上（振りかぶり）→ 左の前の上 → 前を左上から右下へ斜めに払い → 右の後ろ下へ振り抜く（MLBB の 6.37〜6.90 秒）
    p.strike = (*swing([(0.06, 185, 45, 0.06), (0.10, 90, 62, 0.10, 'o2'), (0.15, 125, 25, 0.10, 'io'), (0.21, 85, 12, 0.22, 'i2'),
                        (0.24, 45, 0, 0.27, 'l'), (imp, 2, -22, 0.30, 'l'), (0.34, -46, -38, 0.28, 'o'), (0.45, -100, -50, 0.26, 'o'),
                        (0.6, -108, -52, 0.25)], t, yaw),
                strike_weight(t, 0.04, 0.10, 0.56, 0.70))
    # 盾: 振りかぶりで体の前（胸の高さ）へ、払う間に脇へ戻す
    p.hand_l = arc([(0, CARRY['hand_l']), (0.17, V((0.16, -0.30, -0.30)), 'o2'), (0.34, V((0.04, -0.40, -0.22))),
                    (0.6, CARRY['hand_l'], 'io')], t)
    p.shield = (V((0, 1, 0)), dirs([(0, CARRY['shield'][1]), (0.17, V((-0.35, 0.0, -1.0)), 'o2'), (0.6, CARRY['shield'][1], 'io')], t))
    p.shrug['left'] = (val([(0, 0), (0.17, 8), (0.6, 0)], t), val([(0, 0), (0.17, 12), (0.6, 0)], t))
    return p


def attack_smash(rest, prime, t):
    """③ 叩きつけ。振りかぶりで盾を左の頭の高さへ上げ（MLBB の 7.27〜7.40 秒）、命中で槌頭を前の地面に置いて止まる。"""
    imp = ATTACK_IMPACT
    p, yaw = attack_base(rest, t,
                         [(0, 0), (0.18, -10, 'o2'), (imp, 6, 'i'), (0.64, 6), (ATTACK_END, 0, 'io')],
                         [(0, 0), (0.18, -16, 'o2'), (imp, 8, 'i'), (0.64, 6), (ATTACK_END, 0, 'io')],
                         [(0, 0), (0.18, -16, 'o2'), (imp, 44, 'i'), (0.64, 40), (ATTACK_END, 0, 'io')],
                         [(0, 0), (0.18, -0.01, 'o2'), (imp, 0.20, 'i'), (0.64, 0.19), (ATTACK_END, 0, 'io')],
                         [(0, (0, 0)), (0.10, (0.0, 0.0)), (0.2, (-0.14, 0.08), 'o2'), (imp, (-0.40, 0.0), 'i2'), (0.66, (-0.40, 0.0)),
                          (0.80, (-0.13, 0.05), 'io'), (ATTACK_END, (0, 0), 'o')],
                         back=[(0, 0), (0.18, 0.03), (imp, 0.15, 'i2'), (0.66, 0.15), (ATTACK_END, 0, 'io')],
                         shift=[(0, (0, 0)), (0.18, (0.0, 0.05), 'o2'), (imp, (0.02, -0.14), 'i'), (0.64, (0.02, -0.13)), (ATTACK_END, (0, 0), 'io')])
    p.hand_r = arc([(0, CARRY['hand_r']), (0.12, V((0.0, 0.38, 0.02)), 'o2'), (0.19, V((0.02, 0.45, 0.06)), 'io'),
                    (0.62, V((-0.05, -0.36, -0.36))), (0.77, V((-0.10, -0.15, -0.40)), 'io'), (ATTACK_END, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (0.12, V((0.15, 0.55, 0.82)), 'o2'), (0.19, V((0.05, 0.22, 0.97)), 'io'),
                    (0.62, V((0.0, -0.45, -0.89))), (0.77, V((0.05, 0.92, -0.35)), 'io'), (ATTACK_END, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.19, V((1.0, 0.3, 0.2))), (imp, V((1.0, -0.8, 0.3))), (ATTACK_END, CARRY['pole_r'])], t)
    up, _ = swing([(0.04, 185, 45, 0.06), (0.11, 140, 22, 0.08, 'o2'), (0.17, 140, 26, 0.10), (0.205, 150, 58, 0.14, 'i2'),
                   (0.235, 40, 82, 0.20, 'l'), (0.25, -10, 30, 0.28, 'l')], t, yaw)
    down = val([(0.235, V((0.15, 2.0, -0.6))), (0.25, V((0.18, 1.45, -1.05)), 'l'), (imp, V((0.20, HEAD_HALF, -1.25)), 'i2'),
                (0.36, V((0.20, HEAD_HALF + 0.06, -1.23)), 'o'), (0.6, V((0.20, HEAD_HALF + 0.02, -1.22)))], t)
    head = up.lerp(down, smooth((t - 0.235) / 0.02))
    _, sw = maul_strike(head, yaw)
    p.strike = (head, sw, strike_weight(t, 0.02, 0.09, 0.58, 0.70))
    p.hand_l = arc([(0, CARRY['hand_l']), (0.12, V((0.10, -0.02, -0.28)), 'o2'), (0.2, V((0.10, -0.04, -0.28))), (imp, V((0.02, -0.40, -0.18)), 'i2'),
                    (0.62, CARRY['hand_l'], 'io')], t)
    p.shield = (V((0, 1, 0)), dirs([(0, CARRY['shield'][1]), (0.18, V((-0.5, 0.0, -1.0)), 'o2'), (0.62, CARRY['shield'][1], 'io')], t))
    p.shrug['right'] = (val([(0, 4), (0.19, 16, 'o2'), (imp, -2, 'i'), (0.62, 0), (ATTACK_END, 4)], t), 0.0)
    return p


# MARK: - スキル（MLBB の画面収録 a 10-15 / b 10-18。コマの時刻は発動 = 指を離したコマから）
#
#   S1 聖槌波（a 6.52 秒・b 27.0 秒）: 0.05 秒で槌を肩から真後ろの下へ振り下ろし（腕を後ろへ伸ばす）→ 後ろから頭上へ（0.21 秒）→
#      0.25 秒で前の地面へ叩きつけ（左足の深い踏み込み、背を大きく倒す。盾は体の左前に縦）→ 衝撃波の間は沈んだまま（〜0.95 秒）→
#      1.1 秒で槌を体の右前に立て → 1.35 秒で肩へ戻す
#   S2 聖槌突撃（a 10.2 秒・b 24.6 秒）: 槌は肩に担いだまま、盾を体の前に構えて前傾で走る（0.67 秒）→ 終点で盾を押し込み、
#      起き上がって 1.0 秒で盾を脇へ戻す
#   S2 の再使用（a 11.25 秒・b 25.8 秒）: 槌を肩から右前の低い所へ下ろし（0.1 秒）→ 下から前を振り上げて 0.2 秒で打ち上げ →
#      0.35 秒で頭の真上に立て → 0.6 秒で肩へ戻す
#   奥義 崩落聖域（a 1.40 秒・b 21.6 秒）: 槌は肩に担いだまま、盾を水平に頭の上へ掲げ（0.22 秒、外の面が上）→ 0.87 秒まで掲げて
#      引き寄せ → 1.0 秒で盾を前の地面へ叩きつける（崩落）→ 1.75 秒まで盾を地に付けて沈んだまま → 2.0 秒で起き上がる

def skill_base(rest, t, hips_yaw, torso_yaw, lean, drop, step, back=None, forward=None):
    """スキルの体（attack_base と同じ。back = 右足を後ろへ引く量、forward = 腰を前へ出す量の keys）。"""
    p, yaw = attack_base(rest, t, hips_yaw, torso_yaw, lean, drop, step)
    if back:
        b = val(back, t)
        p.feet['right'] = rest.foot('right', dz=b)
        p.roll['right'] = 14 * smooth(b / 0.15)
        p.toe['right'] = -12 * smooth(b / 0.15)
    if forward:
        p.offset.z = -val(forward, t)
    return p, yaw


# S1 の槌頭が地を打つ所の目標（ヒーロー空間の前 -Z）。MLBB は足元から 1.83〜1.88 単位。腕と柄の届く所で 1.77 m に止まる（docs/H029_QUALITY.md）
S1_HIT = -1.87 / SCALE


def skill_wave(rest, prime, t):
    """S1 聖槌波 1.45 秒（打撃 0.25 = 1 回目の衝撃波）。"""
    s = 0.25
    p, yaw = skill_base(rest, t,
                        [(0, 0), (0.06, -10, 'o2'), (0.2, -4), (s, 4, 'i'), (0.95, 4), (1.2, 0, 'io')],
                        [(0, 0), (0.06, -18, 'o2'), (0.2, -6), (s, 6, 'i'), (0.95, 4), (1.2, 0, 'io')],
                        [(0, 0), (0.06, 4, 'o2'), (0.17, -12, 'io'), (s, 46, 'i'), (0.4, 50, 'o'), (0.95, 48), (1.12, 14, 'io'), (1.3, 0, 'io')],
                        [(0, 0), (0.06, 0.02), (0.17, -0.01), (s, 0.17, 'i'), (0.4, 0.19, 'o'), (0.95, 0.18), (1.12, 0.06, 'io'), (1.3, 0, 'io')],
                        [(0, (0, 0)), (0.10, (-0.10, 0.08), 'o2'), (s, (-0.60, 0.0), 'i2'), (0.97, (-0.60, 0.0)), (1.14, (-0.22, 0.06), 'io'),
                         (1.3, (0, 0), 'o')],
                        back=[(0, 0), (0.12, 0.0), (s, 0.14, 'i2'), (0.97, 0.14), (1.2, 0, 'io')],
                        forward=[(0, 0), (0.17, -0.02), (s, 0.28, 'i'), (0.97, 0.28), (1.2, 0, 'io')])
    # 槌: 肩 → 真後ろの下（腕を後ろへ伸ばす）→ 後ろから頭上 → 前の地面。戻りは体の右前に立ててから肩へ
    p.hand_r = arc([(0, CARRY['hand_r']), (0.05, V((0.12, -0.42, 0.20)), 'o2'), (0.97, V((0.0, -0.40, -0.30))),
                    (1.12, V((0.02, -0.30, -0.32)), 'io'), (1.35, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (0.05, V((0.0, -0.75, 0.66)), 'o2'), (0.97, V((0.05, -0.3, -0.95))),
                    (1.12, V((0.10, 1.0, -0.10)), 'io'), (1.35, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.05, V((1, -0.3, 0.6))), (0.17, V((1, 0.4, 0.2))), (s, V((1, -0.8, 0.2))),
                     (1.12, V((1, -0.8, 0.0))), (1.35, CARRY['pole_r'])], t)
    up, _ = swing([(0.04, 185, -20, 0.22), (0.07, 182, -28, 0.26, 'o2'), (0.15, 180, 25, 0.22, 'io'), (0.205, 178, 72, 0.16, 'i2')], t, yaw)
    down = val([(0.205, V((0.10, 2.35, 0.25))), (0.225, V((0.12, 1.95, -0.92)), 'l'), (s, V((0.16, HEAD_HALF, S1_HIT)), 'i2'),
                (0.32, V((0.16, HEAD_HALF + 0.07, S1_HIT + 0.02)), 'o'), (0.45, V((0.16, HEAD_HALF + 0.02, S1_HIT + 0.02))),
                (0.97, V((0.16, HEAD_HALF + 0.02, S1_HIT + 0.02)))], t)
    head = up.lerp(down, smooth((t - 0.205) / 0.02))
    _, sw = maul_strike(head, yaw)
    p.strike = (head, sw, strike_weight(t, 0.02, 0.06, 0.95, 1.06))
    p.shrug['right'] = (val([(0, 4), (0.17, 16), (s, -2, 'i'), (0.97, 0), (1.35, 4)], t), val([(0, 0), (s, 10, 'i'), (1.2, 0)], t))
    # 盾: 叩きつけの間は体の左前に縦（MLBB の 7.0〜7.5 秒）
    p.hand_l = arc([(0, CARRY['hand_l']), (s, V((0.14, -0.34, -0.30)), 'i2'), (0.97, V((0.14, -0.34, -0.30))),
                    (1.25, CARRY['hand_l'], 'io')], t)
    p.shield = (V((0, 1, 0)), dirs([(0, CARRY['shield'][1]), (s, V((-0.6, 0.0, -1.0)), 'i2'), (0.97, V((-0.6, 0.0, -1.0))),
                                    (1.25, CARRY['shield'][1], 'io')], t))
    p.head = (p.head[0], p.head[1] + val([(0, 0), (s, -18, 'i'), (0.97, -16), (1.2, 0, 'io')], t))
    return p


def skill_charge(rest, prime, t):
    """S2 聖槌突撃 1.0 秒: 槌は肩のまま、盾を体の前に構えた前傾で 0.67 秒走り抜け（短く重い踏み込み 4 歩）→ 0.67 で盾を押し込んで
    止まる → 1.0 で構えへ。sim が術者を動かすので水平の腰は動かさない（脚もこのクリップ: HeroMotionSet.castLocksLegs）。"""
    arrive = 0.67
    run = smooth(t / 0.06) * (1 - smooth((t - arrive) / 0.08))
    p, yaw = attack_base(rest, t,
                         [(0, 0), (0.06, 6, 'o'), (arrive, 6), (0.74, 4, 'o'), (1.0, 0, 'io')],
                         [(0, 0), (0.06, 8, 'o'), (arrive, 8), (0.74, 6, 'o'), (1.0, 0, 'io')],
                         [(0, 0), (0.06, 20, 'o'), (arrive, 20), (0.72, 26, 'o'), (0.82, 12), (1.0, 0, 'io')],
                         [(0, 0), (0.06, 0.04, 'o'), (arrive, 0.04), (0.72, 0.07, 'o'), (1.0, 0, 'io')],
                         [(0, (0, 0)), (1.0, (0, 0))])
    cyc = (t / 0.335) % 1  # 0.67 秒で 2 周 = 4 歩
    p.offset.y -= 0.02 * run * (0.5 + 0.5 * math.cos(cyc * math.tau * 2))
    # 盾を体の前（胸の前に縦、外の面が前）。終点で押し込む
    p.hand_l = arc([(0, CARRY['hand_l']), (0.07, V((0.20, -0.22, -0.38)), 'o'), (arrive, V((0.20, -0.22, -0.38))),
                    (0.71, V((0.20, -0.20, -0.45)), 'o'), (0.85, V((0.16, -0.28, -0.34))), (1.0, CARRY['hand_l'], 'io')], t)
    p.shield = (dirs([(0, CARRY['shield'][0]), (0.07, V((0.0, 1.0, 0.2)), 'o'), (0.85, V((0.0, 1.0, 0.2))), (1.0, CARRY['shield'][0], 'io')], t),
                dirs([(0, CARRY['shield'][1]), (0.07, V((0.25, 0.0, -1.0)), 'o'), (0.85, V((0.2, 0.0, -1.0))), (1.0, CARRY['shield'][1], 'io')], t))
    p.pole_l = dirs([(0, CARRY['pole_l']), (0.07, V((-1.0, -0.6, 0.3))), (0.85, V((-1.0, -0.6, 0.3))), (1.0, CARRY['pole_l'])], t)
    p.shrug['left'] = (val([(0, 0), (0.06, 8), (arrive, 8), (0.71, 12), (1.0, 0)], t), val([(0, 0), (0.06, 14), (0.71, 18), (1.0, 0)], t))
    # 脚: 走り（短い接地の重い踏み込み）→ 終点で左足を前に踏ん張る
    reach = 0.27   # MLBB の突進は大股（b 24.87・25.30 秒で両足が大きく開く）
    for side, ph0 in (('right', 0.0), ('left', 0.5)):
        stance = rest.foot(side)
        ph = (cyc + ph0) % 1
        if ph < 0.45:
            v = ph / 0.45
            z = -reach + 2 * reach * v
            y = 0.0
        else:
            v = (ph - 0.45) / 0.55
            z = reach - 2 * reach * smooth(v)
            y = 0.17 * math.sin(math.pi * v)
        moving = V(((-0.20 if side == 'left' else 0.20), stance.y + y, z))
        stop = rest.foot(side, dz=(-0.22 if side == 'left' else 0.12))
        k = smooth((t - arrive + 0.04) / 0.08)
        back = smooth((t - 0.8) / 0.2)
        p.feet[side] = stance.lerp(moving, smooth(t / 0.10)).lerp(stop, k).lerp(rest.foot(side), back)
        p.roll[side] = run * (18 * math.sin(math.tau * ph) if ph > 0.45 else 10 * smooth((v - 0.7) / 0.3))
        p.toe[side] = 0
    p.knee_out = 0.25
    return p


def skill_upswing(rest, prime, t):
    """S2 の再使用 0.7 秒（打ち上げ 0.2）。"""
    s = 0.20
    p, yaw = skill_base(rest, t,
                        [(0, 0), (0.10, -12, 'o2'), (s, 4, 'i2'), (0.62, 0, 'io')],
                        [(0, 0), (0.10, -18, 'o2'), (s, 8, 'i2'), (0.62, 0, 'io')],
                        [(0, 0), (0.10, 16, 'o2'), (s, 4, 'i2'), (0.30, -10, 'o'), (0.45, -6), (0.62, 0, 'io')],
                        [(0, 0), (0.10, 0.10, 'o2'), (s, 0.03, 'i2'), (0.30, -0.01, 'o'), (0.62, 0, 'io')],
                        [(0, (0, 0)), (0.06, (-0.06, 0.07), 'o2'), (s, (-0.22, 0.0), 'i2'), (0.42, (-0.22, 0.0)), (0.56, (-0.08, 0.04), 'io'),
                         (0.66, (0, 0), 'o')])
    p.hand_r = arc([(0, CARRY['hand_r']), (0.10, V((0.05, -0.44, -0.18)), 'o2'), (0.36, V((0.0, 0.45, -0.05))),
                    (0.62, CARRY['hand_r'], 'io')], t)
    p.shaft = dirs([(0, CARRY['shaft']), (0.10, V((0.15, -0.85, -0.50)), 'o2'), (0.36, V((0.05, 1.0, 0.05))),
                    (0.62, CARRY['shaft'], 'io')], t)
    p.pole_r = dirs([(0, CARRY['pole_r']), (0.10, V((1, -0.8, 0.4))), (s, V((1, -0.8, 0.2))), (0.32, V((1, 0.2, 0.3))),
                     (0.62, CARRY['pole_r'])], t)
    # 打ち上げ: 槌頭が右前の地面の近く → 前を下から上へ抜け（0.2 秒で胸の高さ）→ 頭の真上
    head = val([(0.10, V((0.30, HEAD_HALF + 0.06, -0.95))), (s, V((0.12, 1.0, -1.15)), 'i2'), (0.27, V((0.05, 2.0, -0.55)), 'o'),
                (0.35, V((0.10, 2.62, 0.05)), 'o'), (0.40, V((0.10, 2.64, 0.06)))], t)
    _, sw = maul_strike(head, yaw)
    p.strike = (head, sw, val([(0.06, 0.0), (0.10, 1.0, 'o2'), (0.36, 1.0), (0.44, 0.0, 'io')], t))
    p.shrug['right'] = (val([(0, 4), (0.10, -4), (0.32, 16, 'o'), (0.45, 14), (0.62, 4, 'io')], t), val([(0, 0), (s, 10), (0.62, 0)], t))
    return p


def skill_sanctuary(rest, prime, t):
    """奥義 崩落聖域 2.05 秒（崩落 1.0）。槌は肩に担いだまま、盾を頭の上へ掲げてから前の地面へ叩きつける。"""
    s = 1.0
    p, yaw = skill_base(rest, t,
                        [(0, 0), (2.0, 0)],
                        [(0, 0), (0.22, 4, 'o2'), (0.86, 4), (s, -4, 'i'), (1.75, -4), (2.0, 0, 'io')],
                        [(0, 0), (0.08, 6, 'o2'), (0.22, -8, 'io'), (0.86, -10), (0.93, -14, 'io'), (s, 40, 'i'), (1.1, 42, 'o'), (1.75, 38),
                         (2.0, 0, 'io')],
                        [(0, 0), (0.08, 0.05, 'o2'), (0.22, 0.0, 'io'), (0.86, 0.0), (0.93, -0.02), (s, 0.20, 'i'), (1.75, 0.18), (2.0, 0, 'io')],
                        [(0, (0, 0)), (0.9, (0, 0)), (0.95, (-0.14, 0.09), 'o2'), (s, (-0.42, 0.0), 'i2'), (1.75, (-0.42, 0.0)),
                         (1.9, (-0.10, 0.05), 'io'), (2.0, (0, 0), 'o')],
                        back=[(0, 0), (0.95, 0), (s, 0.16, 'i2'), (1.75, 0.16), (2.0, 0, 'io')],
                        forward=[(0, 0), (0.93, -0.02), (s, 0.12, 'i'), (1.75, 0.12), (2.0, 0, 'io')])
    hold = 0.010 * math.sin(max(0.0, t - 0.25) * 24) * (1 if 0.25 < t < 0.86 else 0)  # 掲げている間の震え
    p.hand_l = arc([(0, CARRY['hand_l']), (0.10, V((-0.02, 0.05, -0.20)), 'o2'), (0.22, V((0.08, 0.50, -0.06)), 'io'),
                    (0.86, V((0.08, 0.50, -0.06))), (0.93, V((0.08, 0.54, -0.02)), 'io'), (s, V((0.20, -0.36, -0.40)), 'i'),
                    (1.75, V((0.20, -0.36, -0.40))), (2.0, CARRY['hand_l'], 'io')], t) + V((0, hold, 0))
    p.shield = (dirs([(0, CARRY['shield'][0]), (0.22, V((-1.0, 0.0, 0.25)), 'io'), (0.93, V((-1.0, 0.0, 0.25))), (s, V((0.0, 0.55, 0.85)), 'i'),
                      (1.75, V((0.0, 0.55, 0.85))), (2.0, CARRY['shield'][0], 'io')], t),
                dirs([(0, CARRY['shield'][1]), (0.22, V((0.0, 1.0, -0.3)), 'io'), (0.93, V((0.0, 1.0, -0.3))), (s, V((0.15, -0.35, -1.0)), 'i'),
                      (1.75, V((0.15, -0.35, -1.0))), (2.0, CARRY['shield'][1], 'io')], t))
    p.pole_l = dirs([(0, CARRY['pole_l']), (0.22, V((-1.0, 0.2, 0.2))), (0.93, V((-1.0, 0.2, 0.2))), (s, V((-0.6, -0.4, 0.5))),
                     (1.75, V((-0.6, -0.4, 0.5))), (2.0, CARRY['pole_l'])], t)
    p.shrug['left'] = (val([(0, 0), (0.22, 22, 'io'), (0.93, 24), (s, 2, 'i'), (1.75, 2), (2.0, 0)], t), val([(0, 0), (0.22, 6), (s, 10), (2.0, 0)], t))
    p.head = (p.head[0], p.head[1] + val([(0, 0), (0.22, -20, 'io'), (0.86, -22), (s, 6, 'i'), (1.75, 4), (2.0, 0, 'io')], t))
    return p


# MARK: - 書き出し

def author(rig, prime, out):
    rest = Rest(rig)
    specs = [
        # name, frames, loop, events, builder(t or u)
        dict(name='idle_h029', frames=120, loop=True, make=lambda u: idle(rest, prime, u), blend=0.25),
        dict(name='walk_h029', frames=GAITS['walk']['frames'], loop=True, make=lambda u: locomotion(rest, prime, u, False)[0],
             blend=0.2, groundSpeed=GAITS['walk']['speed'], local='H029-mlbb-gait'),
        dict(name='run_h029', frames=GAITS['run']['frames'], loop=True, make=lambda u: locomotion(rest, prime, u, True)[0],
             blend=0.15, groundSpeed=GAITS['run']['speed'], local='H029-mlbb-gait'),
        *[dict(name=n, frames=28, loop=False, events=dict(impact=round(ATTACK_IMPACT * FPS, 2), end=27), make=f, blend=0.12, rootXZ=1,
               local='H029-mlbb-attack')
          for n, f in (('maul_sweep_h029', lambda t: attack_sweep(rest, prime, t)),
                       ('maul_backhand_h029', lambda t: attack_backhand(rest, prime, t)),
                       ('maul_smash_h029', lambda t: attack_smash(rest, prime, t)))],
        dict(name='maul_wave_h029', frames=44, loop=False, events=dict(impact=7.5, end=43), make=lambda t: skill_wave(rest, prime, t),
             blend=0.06, rootXZ=1, local='H029-mlbb-skill'),
        dict(name='shield_charge_h029', frames=35, loop=False, events=dict(impact=20.1, end=34), make=lambda t: skill_charge(rest, prime, t),
             blend=0.06, rootXZ=1, local='H029-mlbb-skill'),
        dict(name='maul_upswing_h029', frames=30, loop=False, events=dict(impact=6, end=29), make=lambda t: skill_upswing(rest, prime, t),
             blend=0.06, rootXZ=1, local='H029-mlbb-skill'),
        dict(name='maul_sanctuary_h029', frames=62, loop=False, events=dict(impact=30, end=61), make=lambda t: skill_sanctuary(rest, prime, t),
             blend=0.08, rootXZ=1, local='H029-mlbb-skill'),
    ]
    # 出所: 以前の書き出しの source（Meshy prime のタスク）を保ち、手付けの段の名前だけ替える（api-state.json が無くても回る）
    before = {c['name']: c.get('source', '') for c in json.loads(out.read_text())['clips']} if out.exists() else {}
    clips, report = [], {}
    for sp in specs:
        loop, n = sp['loop'], sp['frames']
        base = before.get(sp['name'], '').split('+local:')[0]
        base = '' if base.startswith('local') else base
        c = dict(name=sp['name'], source=(f"{base}+" if base else '') + f"local:{sp.get('local', 'H029-contact-finish')}",
                 frames=n, loop=loop, rootXZ=sp.get('rootXZ', 0), melee=not loop, events=sp.get('events', {}), rot=[], root=[],
                 detailJoints=[r for r in DETAILS if r in rig.index], detailRot=[], blend=sp['blend'])
        if 'groundSpeed' in sp:
            c['groundSpeed'] = sp['groundSpeed']
        prev, pd = [None] * 15, [None] * len(c['detailJoints'])
        errors, ground, limbs, heads, wrists = [], [], [], [], []
        for f in range(n):
            t = f / n if loop else f / FPS
            qs, offset, details, err = build(rig, sp['make'](t))
            wrists.append(build.wrist)
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
            heads.append(maul_head(rig, qs, P).y - HEAD_HALF)
            ground.append(min(P[rig.index['leftfoot']].y - rig.P0[rig.index['leftfoot']].y,
                              P[rig.index['rightfoot']].y - rig.P0[rig.index['rightfoot']].y))
        clips.append(c)
        end = 1.0 if loop else (n - 1) / FPS
        a, _, _, _ = build(rig, sp['make'](0))
        b, _, _, _ = build(rig, sp['make'](end))
        report[c['name']] = dict(frames=n, maxTargetMissMm=round(max(errors) * 1000, 2),
                                 boundaryDegrees=round(max(cm.quat_angle_deg(x, y) for x, y in zip(a, b)), 3),
                                 lowestAnkleVsRestMm=round(min(ground) * 1000, 1),
                                 maulHeadClearanceMm=round(min(heads) * 1000, 1),
                                 shieldWristMaxDegrees=round(max(wrists), 1),
                                 missMm=dict(zip(('footL', 'footR', 'handR', 'handL'), [round(x * 1000, 1) for x in limbs])))
    out.write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=clips), separators=(',', ':')) + '\n')
    return report


def main():
    rig, _, height, warnings = preview.load_hero(str(Path(HERO).resolve()))
    axis_error = bind_usd_axes(rig, HERO)
    src = {c['name']: c for c in json.loads(Path('tools/motion/h029-prime-source-clips.json').read_text())['clips']}
    report = author(rig, Prime(src), Path('App/Resources/Heroes/H029MotionClips.json'))
    report['model'] = dict(height=height, bones=len(rig.names), fingers='righthandindex1' in rig.index,
                           importedVsUSDJointAxesDegrees=axis_error, warnings=warnings)
    Path('build/h029-motion/finish-report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
