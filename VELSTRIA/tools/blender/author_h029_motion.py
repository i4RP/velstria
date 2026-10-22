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
SCALE = 1.32  # HeroBlueprints の H029（motion.scale）。groundSpeed はゲームの m/s
HERO = 'App/Resources/Heroes/Hero_H029.usdz'
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
        a.x = (-0.265 if side == 'left' else 0.265) + dx
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
        # 握りの分（手首 → 握り）を 1 回だけ補正する
        arm_ik(rig, qs, offset, details, 'right', target, qt @ p.pole_r, shaft)
        _, P1 = solve(rig, qs, offset, details)
        target = target + (head - maul_head(rig, qs, P1)) * w
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
    errors.append(arm_ik(rig, qs, offset, details, 'left', sl + qt @ p.hand_l, qt @ p.pole_l, qt @ p.shield_up,
                         dev=(60, 120)))
    build.last = errors
    return qs, offset, details, max(errors)


# MARK: - 各クリップ

def guard_texture(prime, t, w=0.35):
    h, tt, hd, _ = prime.cycle('h029_idle_prime', 0, 119, t)
    h0, t0, hd0, _ = prime.body('h029_idle_prime', 0)
    return relative(h, h0, w), relative(tt, t0, w), relative(hd, hd0, w)


def idle(rest, prime, u):
    """4 秒の待機（ループ）。重い呼吸 1 回、頭をゆっくり上げて戻す、柄の握り直し。盾と槌は動かさない。"""
    p = Pose(rest)
    breath = math.sin(u * math.tau)            # 0 → 吸う → 0 → 吐く
    lift = 0.5 - 0.5 * math.cos(u * math.tau)  # 頭・胸を上げる（周期の中ほどで最大）
    p.offset.y += 0.006 * breath - 0.004 * lift
    p.hips = (GUARD['hips'][0], GUARD['hips'][1] + 0.6 * breath, 0.4 * math.sin(u * math.tau + 0.6))
    p.torso = (GUARD['torso'][0] + 1.2 * math.sin(u * math.tau + 1.1), GUARD['torso'][1] - 2.0 * breath - 1.5 * lift, 0)
    p.head = (GUARD['head'][0] - 2.5 * lift, GUARD['head'][1] - 6.0 * lift + 1.0 * breath)
    for side in ('left', 'right'):
        p.shrug[side] = (1.8 * max(0.0, breath) + 0.6 * lift, p.shrug[side][1])
    # 握り直し: 0.55〜0.75 の間だけ指を緩めて握り直す（柄の向きは変えない）
    p.regrip = 0.28 * math.sin(math.pi * smooth((u - 0.55) / 0.2)) ** 2 if 0.55 < u < 0.75 else 0.0
    p.hand_r = GUARD['hand_r'] + V((0, 0.006 * breath, 0))
    p.hand_l = GUARD['hand_l'] + V((0, 0.008 * breath, -0.004 * breath))
    p.texture = guard_texture(prime, u, 0.25)
    return p


def locomotion(rest, prime, u, run):
    """歩行（prime f12→54、1.4 秒）・走行（prime f9→42、1.1 秒）。支持脚は移動速度を打ち消す一定速度で地面に固定。"""
    p = Pose(rest)
    name, f0, f1 = ('h029_run_prime', 9, 42) if run else ('h029_walk_prime', 12, 54)
    period = (f1 - f0) / FPS
    speed = (2.10 if run else 1.0)  # ヒーロー空間の m/s（走行は prime の歩幅 / 周期、歩行は巨体に合わせて歩幅を詰める）
    contact = 0.36 if run else 0.56
    h, t, hd, _ = prime.cycle(name, f0, f1, u)
    h0, t0, hd0, _ = prime.cycle(name, f0, f1, 0)
    # prime の揺れ（腰の左右のひねり・胴の反動）は半分だけ使い、前傾と盾の構えは手付け
    p.texture = (relative(h, h0, 0.55), relative(t, t0, 0.45), relative(hd, hd0, 0.3))
    lean = 16 if run else 4
    p.hips = (-4, lean * 0.55, 0)
    p.torso = (-3, lean * 0.6 + 2, 0)
    p.head = (2, -lean * 0.5 - 2)
    reach = speed * period * contact / 2
    w2 = math.cos(u * math.tau * 2)
    # 接地のたびに腰が沈み、蹴り出しで上がる（走行は浮きを大きく）
    p.offset = V((0, -(0.13 if run else 0.11) - (0.03 if run else 0.016) * (0.5 + 0.5 * w2), 0))
    for side, phase in (('right', u), ('left', u + 0.5)):
        x = 0.20 if side == 'right' else -0.20
        ph = phase % 1
        foot = rest.ankle[side].copy()
        foot.x = x
        if ph < contact:
            v = ph / contact
            foot.z = -reach + 2 * reach * v
            roll = 22 * smooth((v - 0.78) / 0.22)   # 蹴り出しでかかとを上げる
            heel = -8 * (1 - smooth(v / 0.18))      # 着地はかかとから
            p.roll[side] = roll + heel
            p.toe[side] = -roll * 0.7
            foot.y += 0.06 * math.sin(D(max(0.0, roll)))
        else:
            v = (ph - contact) / (1 - contact)
            tangent = 2 * reach * (1 - contact) / contact
            foot.z = reach - 2 * reach * smooth(v) + tangent * (2 * v ** 3 - 3 * v * v + v)
            foot.y += (0.15 if run else 0.075) * math.sin(math.pi * v) ** 1.5
            p.roll[side] = 22 * (1 - smooth(v / 0.35)) - 10 * math.sin(math.pi * v) - 8 * smooth((v - 0.8) / 0.2)
            p.toe[side] = 0
        p.feet[side] = foot
    sway = math.sin(u * math.tau)
    # 盾は胸の前で保ち、槌は体の横で立てて持つ（走行は盾を前へ出して前傾）
    if run:
        p.hand_l = V((0.24, -0.20, -0.42)) + V((0, 0.012 * w2, 0))
        p.shield_up = V((0.0, 1.0, 0.25))
        p.hand_r = V((0.15, -0.40, -0.10)) + V((0, 0.02 * w2, 0.05 * sway))
        p.shaft = V((0.12, 0.80, -0.58))
    else:
        p.hand_l = GUARD['hand_l'] + V((0, 0.008 * w2, 0))
        p.hand_r = GUARD['hand_r'] + V((0, 0.012 * w2, 0.035 * sway))
        p.shaft = GUARD['shaft'] + V((0, 0, -0.04 * sway))
    p.knee_out = 0.25
    return p, speed * SCALE, period


def attack(rest, prime, t):
    """通常攻撃 0.867 秒: 構え → 槌を右肩の上へ振りかぶる（0.24）→ 小さく溜める（〜0.30）→ 体重を乗せて打ち下ろす
    （0.40 = 命中）→ 反動を肩と膝で受ける → 0.87 で構えへ。盾は胸の前のまま。prime（f0→39 振りかぶり、f45→60 打ち下ろし、
    f60→72 反動）の体の流れを圧縮して重ねる。"""
    p = Pose(rest)
    imp = 0.40
    K = lambda *pts: [(a, b, c) if c else (a, b) for a, b, c in pts]
    p.hips = (val(K((0, GUARD['hips'][0], None), (0.24, -14, 'o2'), (0.30, -15, 'l'), (imp, 8, 'i'), (0.55, 6, 'o'), (0.867, GUARD['hips'][0], 'io')), t),
              val(K((0, GUARD['hips'][1], None), (0.24, -2, 'o2'), (0.30, -3, 'l'), (imp, 14, 'i'), (0.55, 12, 'o'), (0.867, GUARD['hips'][1], 'io')), t), 0)
    p.torso = (val(K((0, GUARD['torso'][0], None), (0.24, -16, 'o2'), (0.30, -18, 'l'), (imp, 10, 'i'), (0.55, 7, 'o'), (0.867, GUARD['torso'][0], 'io')), t),
               val(K((0, GUARD['torso'][1], None), (0.24, -12, 'o2'), (0.30, -14, 'l'), (imp, 26, 'i'), (0.52, 22, 'o'), (0.867, GUARD['torso'][1], 'io')), t),
               val(K((0, 0, None), (0.24, 6, 'o2'), (imp, -4, 'i'), (0.867, 0, 'io')), t))
    p.head = (val([(0, 4), (0.24, 10, 'o2'), (imp, -2, 'i'), (0.867, 4)], t),
              val([(0, -3), (0.24, -14, 'o2'), (0.30, -15, 'l'), (imp, 10, 'i'), (0.6, 6, 'o'), (0.867, -3)], t))
    p.offset = V((val([(0, 0), (0.24, 0.02, 'o2'), (imp, -0.05, 'i'), (0.55, -0.04, 'o'), (0.867, 0)], t),
                  -GUARD['drop'] + val([(0, 0), (0.24, 0.025, 'o2'), (0.30, 0.02, 'l'), (imp, -0.075, 'i'), (0.50, -0.065, 'o'), (0.867, 0)], t),
                  val([(0, 0), (0.24, 0.04, 'o2'), (imp, -0.09, 'i'), (0.55, -0.07, 'o'), (0.867, 0)], t)))
    # 槌の手: 体の横 → 右肩の上・後ろ（振りかぶり）→ 前の低い所（命中）→ 反動で少し上がる → 構え
    p.hand_r = arc([(0, GUARD['hand_r']), (0.24, V((0.06, 0.33, 0.10)), 'o2'), (0.30, V((0.05, 0.36, 0.13)), 'l'),
                    (0.36, V((0.06, 0.22, -0.34)), 'i2'), (imp, V((0.02, -0.18, -0.46)), 'l'), (0.52, V((0.04, -0.12, -0.44)), 'o'),
                    (0.867, GUARD['hand_r'], 'io')], t)
    p.shaft = dirs([(0, GUARD['shaft']), (0.24, V((-0.05, 0.25, 1.0)), 'o2'), (0.30, V((-0.05, 0.10, 1.0)), 'l'),
                    (0.36, V((0.0, 0.7, -0.7)), 'i2'), (imp, V((0.0, -0.45, -0.89)), 'l'), (0.52, V((0.0, -0.30, -0.95)), 'o'),
                    (0.867, GUARD['shaft'], 'io')], t)
    p.pole_r = dirs([(0, V((1, -0.6, 0.6))), (0.24, V((1, 0.3, 0.2))), (imp, V((1, -0.8, 0.3))), (0.867, V((1, -0.6, 0.6)))], t)
    p.hand_l = arc([(0, GUARD['hand_l']), (0.24, V((0.20, -0.22, -0.40))), (imp, V((0.18, -0.34, -0.38)), 'i2'),
                    (0.867, GUARD['hand_l'])], t)
    p.shrug['right'] = (val([(0, 0), (0.24, 14, 'o2'), (0.30, 15, 'l'), (imp, -2, 'i'), (0.55, 2, 'o'), (0.867, 0)], t),
                        val([(0, 0), (0.24, -6), (imp, 10, 'i'), (0.867, 0)], t))
    # 足: 左足を前へ踏み込み（0.24〜0.40）、右足は固定。戻りで左足を構えの位置へ引く
    p.feet['left'] = val([(0, rest.foot('left')), (0.20, rest.foot('left', dz=0.02, dy=0.0)), (0.32, rest.foot('left', dz=-0.10, dy=0.07), 'o2'),
                          (imp, rest.foot('left', dz=-0.16), 'i2'), (0.62, rest.foot('left', dz=-0.16)),
                          (0.76, rest.foot('left', dz=-0.06, dy=0.04), 'io'), (0.867, rest.foot('left'), 'o')], t)
    p.roll['left'] = val([(0, 0), (0.20, 0), (0.32, -14), (imp, 0, 'i2'), (0.62, 0), (0.76, 8), (0.867, 0)], t)
    p.strike = (val([(0.34, V((0.10, 1.2, -0.9))), (imp, V((0.10, HEAD_HALF, -1.18)), 'i2'), (0.47, V((0.10, HEAD_HALF + 0.09, -1.14)), 'o'),
                     (0.56, V((0.10, HEAD_HALF + 0.05, -1.12)))], t),
                val([(0.34, V((0, 0.4, -0.92))), (imp, V((0, -0.45, -0.89)), 'i2'), (0.47, V((0, -0.36, -0.93)), 'o'), (0.56, V((0, -0.38, -0.92)))], t),
                val([(0.30, 0.0), (0.37, 0.6, 'i2'), (imp, 1.0, 'o'), (0.56, 1.0), (0.70, 0.0, 'io')], t))
    p.regrip = 0
    return p


def wave(rest, prime, t):
    """S1 聖槌波 1.0 秒: 槌を右の後ろ下へ引く → 後ろから頭上へ（縦の大きな弧）→ 0.25 で前の地面を打つ（左足の踏み込み）→
    衝撃波の 2・3 回目（0.58 / 0.92）の間は低い構えのまま槌を起こし始め、0.75 で構えへ（術者を余計に止めない）。"""
    p = Pose(rest)
    s = 0.25
    p.hips = (val([(0, -6), (0.08, -16, 'o2'), (0.17, -8, 'io'), (s, 6, 'i'), (0.45, 4), (0.75, -6, 'io'), (1.0, -6)], t),
              val([(0, 4), (0.08, 4), (0.17, -6, 'io'), (s, 18, 'i'), (0.42, 16, 'o'), (0.75, 4, 'io'), (1.0, 4)], t), 0)
    p.torso = (val([(0, -4), (0.08, -20, 'o2'), (0.17, -6, 'io'), (s, 6, 'i'), (0.75, -4, 'io')], t),
               val([(0, 5), (0.08, 8), (0.17, -16, 'io'), (s, 34, 'i'), (0.40, 30, 'o'), (0.75, 5, 'io')], t), 0)
    p.head = (val([(0, 4), (0.08, 10), (s, -2, 'i'), (0.75, 4)], t), val([(0, -3), (0.17, -14), (s, 6, 'i'), (0.5, 0), (0.75, -3, 'io')], t))
    p.offset = V((0, -GUARD['drop'] + val([(0, 0), (0.08, -0.03, 'o2'), (0.17, 0.03, 'io'), (s, -0.11, 'i'), (0.45, -0.10, 'o'), (0.75, 0, 'io')], t),
                  val([(0, 0), (0.08, 0.03), (0.17, 0.0), (s, -0.10, 'i'), (0.45, -0.08), (0.75, 0, 'io')], t)))
    p.hand_r = arc([(0, GUARD['hand_r']), (0.08, V((0.10, -0.38, 0.22)), 'o2'), (0.17, V((0.02, 0.38, 0.06)), 'io'),
                    (0.21, V((0.02, 0.24, -0.34)), 'i2'), (s, V((0.0, -0.26, -0.44)), 'l'), (0.45, V((0.02, -0.25, -0.42))),
                    (0.75, GUARD['hand_r'], 'io')], t)
    p.shaft = dirs([(0, GUARD['shaft']), (0.08, V((0.0, -0.75, 0.66)), 'o2'), (0.17, V((0.0, 0.35, 0.94)), 'io'),
                    (0.21, V((0.0, 0.75, -0.66)), 'i2'), (s, V((0.0, -0.70, -0.72)), 'l'), (0.45, V((0.0, -0.62, -0.78))),
                    (0.75, GUARD['shaft'], 'io')], t)
    p.pole_r = dirs([(0, V((1, -0.6, 0.6))), (0.08, V((1, -0.3, 0.6))), (0.17, V((1, 0.4, 0.2))), (s, V((1, -0.7, 0.2))),
                     (0.75, V((1, -0.6, 0.6)))], t)
    # 盾は打つ間は左の脇へ下げ、戻りで胸の前へ
    p.hand_l = arc([(0, GUARD['hand_l']), (0.17, V((0.10, -0.30, -0.32))), (s, V((0.02, -0.42, -0.24)), 'i2'),
                    (0.45, V((0.02, -0.42, -0.24))), (0.75, GUARD['hand_l'], 'io')], t)
    p.shrug['right'] = (val([(0, 0), (0.17, 16), (s, -2, 'i'), (0.75, 0)], t), val([(0, 0), (s, 10, 'i'), (0.75, 0)], t))
    p.feet['left'] = val([(0, rest.foot('left')), (0.10, rest.foot('left', dz=-0.06, dy=0.09), 'o2'), (s, rest.foot('left', dz=-0.30), 'i2'),
                          (0.55, rest.foot('left', dz=-0.30)), (0.70, rest.foot('left', dz=-0.12, dy=0.05), 'io'), (0.82, rest.foot('left'), 'o')], t)
    p.roll['left'] = val([(0, 0), (0.10, -16), (s, 0, 'i2'), (0.55, 0), (0.70, 8), (0.82, 0)], t)
    p.strike = (val([(0.19, V((0.05, 1.3, -0.7))), (s, V((0.05, HEAD_HALF, -1.20)), 'i2'), (0.31, V((0.05, HEAD_HALF + 0.07, -1.17)), 'o'),
                     (0.45, V((0.05, HEAD_HALF + 0.02, -1.16)))], t),
                val([(0.19, V((0, 0.6, -0.8))), (s, V((0, -0.55, -0.83)), 'i2'), (0.45, V((0, -0.5, -0.86)))], t),
                val([(0.17, 0.0), (0.21, 0.6, 'i2'), (s, 1.0, 'o'), (0.45, 1.0), (0.62, 0.0, 'io')], t))
    p.feet['right'] = val([(0, rest.foot('right')), (s, rest.foot('right', dz=0.04)), (0.75, rest.foot('right'), 'io')], t)
    p.roll['right'] = val([(0, 0), (s, 14), (0.55, 10), (0.75, 0, 'io')], t)
    p.toe['right'] = val([(0, 0), (s, -12), (0.55, -8), (0.75, 0, 'io')], t)
    return p


def charge(rest, prime, t):
    """S2 聖槌突撃 1.0 秒: 盾を前に突き出した前傾で 0.67 秒走り抜け（短く重い踏み込みを 4 歩）、0.67 で盾を押し込んで止まる
    → 0.8 から構えへ。sim が術者を動かすので水平の腰は動かさない（下半身もこのクリップで描く: HeroMotionSet.castLocksLegs）。"""
    p = Pose(rest)
    arrive = 0.67
    run = smooth(t / 0.06) * (1 - smooth((t - arrive) / 0.08))
    p.hips = (val([(0, -6), (0.06, -2, 'o'), (arrive, -2), (0.74, 4, 'o'), (1.0, -6, 'io')], t),
              val([(0, 4), (0.06, 20, 'o'), (arrive, 22), (0.72, 12, 'o'), (1.0, 4, 'io')], t), 0)
    p.torso = (val([(0, -4), (0.06, 12, 'o'), (arrive, 12), (0.72, 16, 'o'), (1.0, -4, 'io')], t),
               val([(0, 5), (0.06, 16, 'o'), (arrive, 16), (0.71, 22, 'o'), (1.0, 5, 'io')], t), 0)
    p.head = (val([(0, 4), (0.06, -8), (arrive, -8), (1.0, 4, 'io')], t), val([(0, -3), (0.06, -18), (arrive, -18), (1.0, -3, 'io')], t))
    cyc = (t / 0.335) % 1  # 0.67 秒で 2 周 = 4 歩
    bob = math.cos(cyc * math.tau * 2)
    p.offset = V((0, -GUARD['drop'] + val([(0, 0), (0.06, -0.05, 'o'), (arrive, -0.05), (0.72, -0.08, 'o'), (1.0, 0, 'io')], t)
                  - 0.02 * run * (0.5 + 0.5 * bob), 0))
    # 盾を前へ突き出す（前腕を胸の前で横に、盾の面は前）
    p.hand_l = arc([(0, GUARD['hand_l']), (0.06, V((0.22, -0.14, -0.44)), 'o'), (arrive, V((0.22, -0.14, -0.44))),
                    (0.71, V((0.22, -0.12, -0.47)), 'o'), (1.0, GUARD['hand_l'], 'io')], t)
    p.shield_up = dirs([(0, GUARD['shield_up']), (0.06, V((0.0, 1.0, 0.30))), (arrive, V((0.0, 1.0, 0.30))), (1.0, GUARD['shield_up'])], t)
    # 槌は右の腰の後ろへ流す
    p.hand_r = arc([(0, GUARD['hand_r']), (0.06, V((0.16, -0.40, 0.18)), 'o'), (arrive, V((0.16, -0.40, 0.18))),
                    (0.72, V((0.14, -0.38, 0.06)), 'o'), (1.0, GUARD['hand_r'], 'io')], t)
    p.shaft = dirs([(0, GUARD['shaft']), (0.06, V((0.15, 0.30, 0.94))), (arrive, V((0.15, 0.30, 0.94))), (1.0, GUARD['shaft'], 'io')], t)
    p.shrug['left'] = (val([(0, 0), (0.06, 8), (arrive, 8), (0.71, 12), (1.0, 0)], t), val([(0, 4), (0.06, 14), (0.71, 18), (1.0, 4)], t))
    # 脚: 走り（短い接地の重い踏み込み）→ 終点で左足を前に踏ん張る
    reach = 0.16
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
            y = 0.13 * math.sin(math.pi * v)
        moving = V(((-0.20 if side == 'left' else 0.20), stance.y + y, z))
        stop = rest.foot(side, dz=(-0.22 if side == 'left' else 0.12))
        k = smooth((t - arrive + 0.04) / 0.08)
        back = smooth((t - 0.8) / 0.2)
        target = stance.lerp(moving, smooth(t / 0.10)).lerp(stop, k).lerp(rest.foot(side), back)
        p.feet[side] = target
        p.roll[side] = run * (18 * math.sin(math.tau * ph) if ph > 0.45 else 10 * smooth((v - 0.7) / 0.3))
    p.knee_out = 0.25
    return p


def upswing(rest, prime, t):
    """S2 再使用 0.85 秒: 槌を右の後ろ下へ引いて腰を落とし（〜0.12）、左足を踏み込んで下から前へ振り上げる（0.2 = 打ち上げ）→
    頭上へ抜けて（0.32）→ 0.85 で構えへ。"""
    p = Pose(rest)
    s = 0.20
    p.hips = (val([(0, -6), (0.12, -18, 'o2'), (s, 4, 'i2'), (0.32, 10, 'o'), (0.85, -6, 'io')], t),
              val([(0, 4), (0.12, 12, 'o2'), (s, 6, 'i2'), (0.32, -4, 'o'), (0.85, 4, 'io')], t), 0)
    p.torso = (val([(0, -4), (0.12, -20, 'o2'), (s, 6, 'i2'), (0.32, 12, 'o'), (0.85, -4, 'io')], t),
               val([(0, 5), (0.12, 18, 'o2'), (s, 4, 'i2'), (0.32, -14, 'o'), (0.5, -10), (0.85, 5, 'io')], t),
               val([(0, 0), (0.12, 6), (s, -4), (0.85, 0)], t))
    p.head = (val([(0, 4), (0.12, 10), (s, 0), (0.85, 4)], t), val([(0, -3), (0.12, 4), (0.32, -16, 'o'), (0.55, -10), (0.85, -3, 'io')], t))
    p.offset = V((0, -GUARD['drop'] + val([(0, 0), (0.12, -0.08, 'o2'), (s, -0.03, 'i2'), (0.32, 0.03, 'o'), (0.55, 0.02), (0.85, 0, 'io')], t),
                  val([(0, 0), (0.12, 0.04), (s, -0.06, 'i2'), (0.32, -0.04), (0.85, 0, 'io')], t)))
    p.hand_r = arc([(0, GUARD['hand_r']), (0.12, V((0.14, -0.40, 0.22)), 'o2'), (0.16, V((0.06, -0.44, -0.12)), 'i2'),
                    (s, V((0.02, -0.18, -0.46)), 'l'), (0.32, V((0.02, 0.38, -0.16)), 'o'), (0.55, V((0.04, 0.36, -0.10))),
                    (0.85, GUARD['hand_r'], 'io')], t)
    p.shaft = dirs([(0, GUARD['shaft']), (0.12, V((0.0, -0.55, 0.83)), 'o2'), (0.16, V((0.0, -0.95, -0.30)), 'i2'),
                    (s, V((0.0, 0.10, -0.99)), 'l'), (0.32, V((0.0, 0.92, -0.38)), 'o'), (0.55, V((0.0, 0.95, 0.30))),
                    (0.85, GUARD['shaft'], 'io')], t)
    p.pole_r = dirs([(0, V((1, -0.6, 0.6))), (0.12, V((1, -0.3, 0.6))), (s, V((1, -0.8, 0.2))), (0.32, V((1, 0.2, 0.3))),
                     (0.85, V((1, -0.6, 0.6)))], t)
    p.hand_l = arc([(0, GUARD['hand_l']), (0.12, V((0.20, -0.30, -0.36))), (0.32, V((0.16, -0.24, -0.40))), (0.85, GUARD['hand_l'])], t)
    p.shrug['right'] = (val([(0, 0), (0.12, -4), (0.32, 16, 'o'), (0.55, 14), (0.85, 0, 'io')], t), val([(0, 0), (s, 10), (0.85, 0)], t))
    p.feet['left'] = val([(0, rest.foot('left')), (0.08, rest.foot('left', dz=-0.04, dy=0.08), 'o2'), (s, rest.foot('left', dz=-0.24), 'i2'),
                          (0.55, rest.foot('left', dz=-0.24)), (0.72, rest.foot('left', dz=-0.10, dy=0.05), 'io'), (0.85, rest.foot('left'), 'o')], t)
    p.roll['left'] = val([(0, 0), (0.08, -14), (s, 0, 'i2'), (0.55, 0), (0.72, 8), (0.85, 0)], t)
    p.roll['right'] = val([(0, 0), (s, 10), (0.32, 16), (0.55, 6), (0.85, 0, 'io')], t)
    p.toe['right'] = val([(0, 0), (s, -8), (0.32, -12), (0.55, -4), (0.85, 0, 'io')], t)
    # 打ち上げ: 槌頭が前の低い所を下から上へ抜ける（0.2 秒で胸の高さ）
    p.strike = (val([(0.13, V((0.10, HEAD_HALF + 0.08, -0.80))), (s, V((0.06, 0.80, -1.05)), 'l'), (0.26, V((0.04, 1.5, -0.80)), 'o')], t),
                val([(0.13, V((0, -0.85, -0.52))), (s, V((0, 0.05, -1.0)), 'l'), (0.26, V((0, 0.7, -0.72)))], t),
                val([(0.10, 0.0), (0.14, 1.0, 'i2'), (0.24, 1.0), (0.32, 0.0, 'o')], t))
    return p


def sanctuary(rest, prime, t):
    """ULT 崩落聖域 1.7 秒: 0〜0.28 足を開いて踏ん張り、槌を頭上へ・盾を上げる → 0.28〜0.84 掲げたまま反って力を溜める
    （引き寄せ 0.67 秒）→ 0.84〜0.92 頂点 → 1.0 で槌を前の地面へ叩き落とす（崩落）→ 1.3 まで沈む → 1.7 で構えへ。"""
    p = Pose(rest)
    s = 1.0
    p.hips = (val([(0, -6), (0.28, -4), (0.92, -10, 'io'), (s, 6, 'i'), (1.3, 4), (1.7, -6, 'io')], t),
              val([(0, 4), (0.28, -4, 'o2'), (0.84, -6), (0.92, -8, 'io'), (s, 20, 'i'), (1.3, 18), (1.7, 4, 'io')], t), 0)
    p.torso = (val([(0, -4), (0.28, 2), (0.92, -8, 'io'), (s, 6, 'i'), (1.7, -4, 'io')], t),
               val([(0, 5), (0.28, -14, 'o2'), (0.84, -18, 'l'), (0.92, -20, 'io'), (s, 36, 'i'), (1.28, 32), (1.7, 5, 'io')], t), 0)
    p.head = (val([(0, 4), (0.28, 0), (s, 0), (1.7, 4)], t), val([(0, -3), (0.28, -22, 'o2'), (0.92, -26), (s, 8, 'i'), (1.3, 4), (1.7, -3, 'io')], t))
    p.offset = V((0, -GUARD['drop'] + val([(0, 0), (0.12, -0.05, 'o2'), (0.28, 0.0, 'io'), (0.84, -0.01), (0.92, 0.02, 'io'),
                                          (s, -0.14, 'i'), (1.3, -0.13), (1.7, 0, 'io')], t),
                  val([(0, 0), (0.28, 0.05), (0.92, 0.07), (s, -0.10, 'i'), (1.3, -0.08), (1.7, 0, 'io')], t)))
    hold = 0.012 * math.sin(max(0.0, t - 0.28) * 22) * (1 if 0.28 < t < 0.84 else 0)  # 溜めの震え
    p.hand_r = arc([(0, GUARD['hand_r']), (0.28, V((0.02, 0.50, 0.04)), 'o2'), (0.84, V((0.0, 0.52, 0.08))),
                    (0.92, V((0.0, 0.50, 0.14)), 'io'), (0.96, V((0.02, 0.26, -0.36)), 'i2'), (s, V((0.0, -0.26, -0.44)), 'l'),
                    (1.3, V((0.02, -0.25, -0.43))), (1.7, GUARD['hand_r'], 'io')], t) + V((0, hold, 0))
    p.shaft = dirs([(0, GUARD['shaft']), (0.28, V((-0.10, 0.98, 0.15)), 'o2'), (0.84, V((-0.08, 0.98, 0.20))),
                    (0.92, V((0.0, 0.55, 0.84)), 'io'), (0.96, V((0.0, 0.70, -0.72)), 'i2'), (s, V((0.0, -0.72, -0.70)), 'l'),
                    (1.3, V((0.0, -0.66, -0.75))), (1.7, GUARD['shaft'], 'io')], t)
    p.pole_r = dirs([(0, V((1, -0.6, 0.6))), (0.28, V((1, 0.5, 0.2))), (0.92, V((1, 0.4, 0.3))), (s, V((1, -0.7, 0.2))),
                     (1.7, V((1, -0.6, 0.6)))], t)
    # 盾は顔の前の高さへ掲げ（頭上は表示に隠れる）、叩き落としで前の低い所へ
    p.hand_l = arc([(0, GUARD['hand_l']), (0.28, V((0.18, 0.02, -0.42)), 'o2'), (0.84, V((0.18, 0.05, -0.42))),
                    (s, V((0.16, -0.36, -0.40)), 'i'), (1.3, V((0.16, -0.36, -0.40))), (1.7, GUARD['hand_l'], 'io')], t)
    p.shield_up = dirs([(0, GUARD['shield_up']), (0.28, V((0.0, 1.0, 0.35))), (0.84, V((0.0, 1.0, 0.4))), (s, V((0.0, 1.0, -0.3))),
                        (1.7, GUARD['shield_up'])], t)
    p.shrug['right'] = (val([(0, 0), (0.28, 18, 'o2'), (0.92, 20), (s, -2, 'i'), (1.7, 0)], t), val([(0, 0), (s, 10, 'i'), (1.7, 0)], t))
    p.shrug['left'] = (val([(0, 0), (0.28, 10), (0.92, 12), (s, 0), (1.7, 0)], t), val([(0, 4), (0.28, 10), (1.7, 4)], t))
    p.feet['left'] = val([(0, rest.foot('left')), (0.10, rest.foot('left', dx=-0.03, dz=-0.02, dy=0.06), 'o2'),
                          (0.22, rest.foot('left', dx=-0.05, dz=-0.04), 'io'), (0.86, rest.foot('left', dx=-0.05, dz=-0.04)),
                          (0.93, rest.foot('left', dx=-0.05, dz=-0.18, dy=0.09), 'o2'), (s, rest.foot('left', dx=-0.05, dz=-0.32), 'i2'),
                          (1.35, rest.foot('left', dx=-0.05, dz=-0.32)), (1.55, rest.foot('left', dz=-0.12, dy=0.05), 'io'),
                          (1.7, rest.foot('left'), 'o')], t)
    p.roll['left'] = val([(0, 0), (0.10, -10), (0.22, 0), (0.86, 0), (0.93, -16), (s, 0, 'i2'), (1.35, 0), (1.55, 8), (1.7, 0)], t)
    p.feet['right'] = val([(0, rest.foot('right')), (0.14, rest.foot('right', dx=0.03, dz=0.02, dy=0.06), 'o2'),
                           (0.26, rest.foot('right', dx=0.05, dz=0.04), 'io'), (1.35, rest.foot('right', dx=0.05, dz=0.04)),
                           (1.6, rest.foot('right'), 'io')], t)
    p.roll['right'] = val([(0, 0), (0.14, -10), (0.26, 0), (0.95, 0), (s, 14, 'i'), (1.3, 10), (1.6, 0, 'io')], t)
    p.toe['right'] = val([(0, 0), (0.95, 0), (s, -12, 'i'), (1.3, -8), (1.6, 0, 'io')], t)
    p.strike = (val([(0.94, V((0.05, 1.4, -0.6))), (s, V((0.05, HEAD_HALF, -1.25)), 'i2'), (1.07, V((0.05, HEAD_HALF + 0.08, -1.22)), 'o'),
                     (1.3, V((0.05, HEAD_HALF + 0.02, -1.21)))], t),
                val([(0.94, V((0, 0.7, -0.7))), (s, V((0, -0.5, -0.87)), 'i2'), (1.3, V((0, -0.48, -0.88)))], t),
                val([(0.92, 0.0), (0.96, 0.6, 'i2'), (s, 1.0, 'o'), (1.3, 1.0), (1.48, 0.0, 'io')], t))
    return p


# MARK: - 書き出し

def author(rig, prime, out):
    rest = Rest(rig)
    specs = [
        # name, frames, loop, events, builder(t or u)
        dict(name='idle_h029', frames=120, loop=True, make=lambda u: idle(rest, prime, u), blend=0.25),
        dict(name='walk_h029', frames=42, loop=True, make=lambda u: locomotion(rest, prime, u, False)[0], blend=0.2,
             groundSpeed=round(1.0 * SCALE, 3)),
        dict(name='run_h029', frames=33, loop=True, make=lambda u: locomotion(rest, prime, u, True)[0], blend=0.18,
             groundSpeed=round(2.10 * SCALE, 3)),
        dict(name='maul_smash_h029', frames=27, loop=False, events=dict(impact=12, end=26), make=lambda t: attack(rest, prime, t),
             blend=0.12, rootXZ=1, source='h029_attack_prime'),
        dict(name='maul_wave_h029', frames=31, loop=False, events=dict(impact=7.5, end=30), make=lambda t: wave(rest, prime, t),
             blend=0.06, rootXZ=1, source='h029_slam_prime'),
        dict(name='shield_charge_h029', frames=31, loop=False, events=dict(impact=20.1, end=30), make=lambda t: charge(rest, prime, t),
             blend=0.06, rootXZ=1, source='h029_charge_prime'),
        dict(name='maul_upswing_h029', frames=26, loop=False, events=dict(impact=6, end=25), make=lambda t: upswing(rest, prime, t),
             blend=0.06, rootXZ=1, source='h029_upswing_prime'),
        dict(name='maul_sanctuary_h029', frames=52, loop=False, events=dict(impact=30, end=51), make=lambda t: sanctuary(rest, prime, t),
             blend=0.08, rootXZ=1, source='h029_ult_prime'),
    ]
    state = json.loads(Path('build/h029-motion/api-state.json').read_text())['tasks']
    clips, report = [], {}
    for sp in specs:
        loop, n = sp['loop'], sp['frames']
        src = sp.get('source') or {'idle_h029': 'h029_idle_prime', 'walk_h029': 'h029_walk_prime', 'run_h029': 'h029_run_prime'}[sp['name']]
        c = dict(name=sp['name'], source=f"meshy:text-to-motion:{state[src]['task_id']}+local:H029-contact-finish",
                 frames=n, loop=loop, rootXZ=sp.get('rootXZ', 0), melee=not loop, events=sp.get('events', {}), rot=[], root=[],
                 detailJoints=[r for r in DETAILS if r in rig.index], detailRot=[], blend=sp['blend'])
        if 'groundSpeed' in sp:
            c['groundSpeed'] = sp['groundSpeed']
        prev, pd = [None] * 15, [None] * len(c['detailJoints'])
        errors, ground, limbs, heads = [], [], [], []
        for f in range(n):
            t = f / n if loop else f / FPS
            qs, offset, details, err = build(rig, sp['make'](t))
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
