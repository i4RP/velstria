"""H028 ザイルの待機・歩行・走行・通常攻撃・スキルの仕上げ（Blender 5.2、VELSTRIA/ で実行）。

blender -b -P tools/blender/author_h028_motion.py [-- --out App/Resources/Heroes/H028MotionClips.json]

元: Meshy prime（tools/motion/h028-prime-source-clips.json、extract_h028_prime.py が SMPL-H から変換したもの）。
H028 の実際のリグ（Hero_H028.usdz、指付き 65 骨）の寸法で次を仕上げる（メッシュ・バインドは変えない）:
  - 時間の切り出し・圧縮（ゲームの命中・発射・到着の時刻へ合わせる）、ループの継ぎ目の誤差を 1 周に配る
  - 移動は前進を除いてその場にし、支持脚の足首を移動速度と逆向きに等速で流す（groundSpeed と一致 = 足滑りなし）
  - 足の接地: 元の接地区間の足首を地面の高さに固定し（その場の動作は位置も固定）、遊脚は補正量を滑らかにつなぐ（二関節 IK）
  - 剣（右手の区間の -Z = Prop の +Y）の向き: 待機・移動は胴に対する向きを指定、攻撃・スキルは元の手の向きを手首の可動域で制限
  - 右手は柄を握る指、左手は動作ごとの指（待機は小さな指先の動き）。肩・つま先は元の局所回転
書き出しは実行時の 15 区間 + detailJoints（肩 2・つま先 2・指 30 の局所差分）。
"""
import argparse
import json
import math
import sys
from pathlib import Path

from mathutils import Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clip_math as cm  # noqa: E402
import preview_clip as preview  # noqa: E402
from author_h025_motion import DETAILS, axis, bind_usd_axes, local_delta, pack, smooth, solve  # noqa: E402

FPS = 30
V = Vector
HERO = 'App/Resources/Heroes/Hero_H028.usdz'
SOURCE = 'tools/motion/h028-prime-source-clips.json'
# 設計図の拡縮（HeroBlueprints の H028 scale）。groundSpeed はワールドの m/s
BP_SCALE = 1.02
FOOT_ROLES = {'R': 'rightfoot', 'L': 'leftfoot'}
SEG = cm.SEG_INDEX


# MARK: - 元クリップ

class Source:
    def __init__(self, c):
        self.name = c['name']
        self.n = c['frames']
        self.q = [[Quaternion((c['rot'][(f * 15 + s) * 4 + 3], *c['rot'][(f * 15 + s) * 4:(f * 15 + s) * 4 + 3]))
                   for s in range(15)] for f in range(self.n)]
        self.root = [V(c['root'][f * 3:f * 3 + 3]) for f in range(self.n)]
        roles = c['points']['roles']
        k = len(roles)
        self.pts = [{r: V(c['points']['pos'][(f * k + i) * 3:(f * k + i) * 3 + 3]) for i, r in enumerate(roles)}
                    for f in range(self.n)]
        droles = c['details']['roles']
        dk = len(droles)
        d = c['details']['rot']
        self.det = [{r: Quaternion((d[(f * dk + i) * 4 + 3], *d[(f * dk + i) * 4:(f * dk + i) * 4 + 3]))
                     for i, r in enumerate(droles)} for f in range(self.n)]
        self.rest = {r: V(v) for r, v in c['restPoints'].items()}

    def at(self, f):
        """小数フレーム f（範囲外は端で止める）の (区間 15, 腰 [脚の長さ単位], 関節位置, 局所回転)。"""
        f = max(0.0, min(self.n - 1.0, f))
        a = int(math.floor(f))
        b = min(a + 1, self.n - 1)
        t = f - a
        qs = [cm.slerp(x, y, t) for x, y in zip(self.q[a], self.q[b])]
        root = self.root[a].lerp(self.root[b], t)
        pts = {r: self.pts[a][r].lerp(self.pts[b][r], t) for r in self.pts[a]}
        det = {r: cm.slerp(self.det[a][r], self.det[b][r], t) for r in self.det[a]}
        return qs, root, pts, det


def warp(keys, t):
    """区分線形の時間対応（出力の秒 → 元のフレーム）。"""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, f0), (t1, f1) in zip(keys, keys[1:]):
        if t <= t1:
            return f0 + (f1 - f0) * (t - t0) / max(1e-9, t1 - t0)
    return keys[-1][1]


def warp_smooth(keys, t):
    """区分の間を smoothstep でつなぐ値の補間。"""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            return v0 + (v1 - v0) * smooth((t - t0) / max(1e-9, t1 - t0))
    return keys[-1][1]


def yaw_of(q):
    f = q @ V((0, 0, -1))
    return math.atan2(-f.x, -f.z)


def ry(rad):
    return Quaternion((0, 1, 0), rad)


# MARK: - 1 フレームの姿勢

class Frame:
    __slots__ = ('qs', 'off', 'det', 'pts', 'contact', 'foot', 'blade')

    def __init__(self, qs, off, det, pts):
        self.qs = qs        # 15 区間（ヒーロー空間）
        self.off = off      # 腰のずれ（m、ヒーロー空間）
        self.det = det      # 役割 → 局所回転（肩・つま先は元の親に対する ΔR、後で USD の軸へ直す）
        self.pts = pts      # 元の関節位置（m に換算・向き補正済み。接地の判定用）
        self.contact = {}
        self.foot = {}
        self.blade = None


def sample_frames(rig, src, times, keys, yaw, travel=None, travel_origin=None):
    """出力の時刻の列 → Frame の列。yaw: 全体の向きの補正（rad）。travel: 1 元フレームあたりの前進（脚の長さ単位）。"""
    L = rig.leg_length
    Y = ry(yaw)
    out = []
    for t in times:
        f = warp(keys, t)
        qs, root, pts, det = src.at(f)
        if travel is not None:
            shift = travel_origin + travel * (f - keys[0][1])
            root = root - shift
            pts = {r: p - shift for r, p in pts.items()}
        qs = [(Y @ q).normalized() for q in qs]
        root = Y @ root
        pts = {r: (Y @ p) * L for r, p in pts.items()}
        out.append(Frame(qs, root * L, det, pts))
    return out


# MARK: - 足の接地

def contacts(src, lo, hi, step, rel_speed=None):
    """元の接地（足首が低く、ワールドの速さが小さい）を元フレーム [lo, hi] の step ごとに。戻り値 side → [bool]。"""
    out = {}
    feet = {'R': 'rightfoot', 'L': 'leftfoot'}
    n = int(round((hi - lo) / step))
    for side, role in feet.items():
        ys = [src.at(lo + i * step)[2][role].y for i in range(n + 1)]
        floor = min(ys)
        flags = []
        for i in range(n + 1):
            f = lo + i * step
            p0 = src.at(f - 1)[2][role]
            p1 = src.at(f + 1)[2][role]
            sp = (V((p1.x, 0, p1.z)) - V((p0.x, 0, p0.z))).length * FPS / 2
            limit = (rel_speed if rel_speed is not None else 0.45)
            flags.append(ys[i] - floor < 0.07 and sp < limit)
        out[side] = clean(flags)
    return out


def clean(flags, loop=False):
    """3 フレーム未満の接地・遊脚の区間を均す。"""
    f = list(flags)
    n = len(f)
    for _ in range(2):
        i = 0
        while i < n:
            j = i
            while j + 1 < n and f[j + 1] == f[i]:
                j += 1
            if j - i + 1 < 3 and not (i == 0 and not loop) and not (j == n - 1 and not loop):
                for k in range(i, j + 1):
                    f[k] = not f[k]
            i = j + 1
    return f


def plant_feet(rig, frames, flags, loop, ground, back=None, pin_pos=None):
    """接地の区間の足首の目標（地面の高さ・位置固定、移動は等速で後ろへ）と、遊脚の補正量の補間を決めて IK で解く。
    back: 1 出力フレームあたりの支持脚の後退（m、ヒーロー空間のベクトル）。pin_pos: side → 固定する位置（待機）。"""
    n = len(frames)
    for side, role in FOOT_ROLES.items():
        j = rig.index[role]
        solved = []
        for fr in frames:
            _, P = solve(rig, fr.qs, fr.off, {})
            solved.append(P[j].copy())
        fl = flags[side]
        delta = [None] * n
        # 接地の区間ごとの目標
        i = 0
        while i < n:
            if not fl[i]:
                i += 1
                continue
            k = i
            while k + 1 < n and fl[k + 1]:
                k += 1
            mid = (i + k) // 2
            if pin_pos is not None:
                anchor = pin_pos[side]
            else:
                xs = [solved[m] for m in range(i, k + 1)]
                if back is None:
                    anchor = sum(xs, V((0, 0, 0))) / len(xs)
                else:
                    # 等速で後ろへ流れる直線に最も近い位置（区間の中央を基準）
                    anchor = sum((solved[m] - back * (m - mid) for m in range(i, k + 1)), V((0, 0, 0))) / (k - i + 1)
            for m in range(i, k + 1):
                target = anchor + (back * (m - mid) if back is not None else V((0, 0, 0)))
                target.y = ground
                delta[m] = target - solved[m]
            i = k + 1
        # 遊脚: 前後の接地の補正量を滑らかにつなぐ（ループは周回）
        idx = [m for m in range(n) if delta[m] is not None]
        if not idx:
            delta = [V((0, 0, 0))] * n
        else:
            for m in range(n):
                if delta[m] is not None:
                    continue
                prev = max([x for x in idx if x < m], default=None)
                nxt = min([x for x in idx if x > m], default=None)
                if loop:
                    if prev is None:
                        prev = idx[-1] - n
                    if nxt is None:
                        nxt = idx[0] + n
                if prev is None:
                    delta[m] = delta[nxt].copy()
                elif nxt is None:
                    delta[m] = delta[prev % n].copy()
                else:
                    w = smooth((m - prev) / (nxt - prev))
                    delta[m] = delta[prev % n].lerp(delta[nxt % n], w)
        for m, fr in enumerate(frames):
            target = solved[m] + delta[m]
            target.y = max(target.y, ground)
            fr.foot[side] = target
            fr.contact[side] = fl[m]


def solve_legs(rig, fr, ground):
    """足首の目標へ脚を解く。届かない時は腰を下げる。足は接地中は平らに（向きは元の足の水平の向き）。"""
    err = 0.0
    for _ in range(3):
        err = 0.0
        for side in ('R', 'L'):
            role = FOOT_ROLES[side]
            suffix = side
            seg_f = SEG['foot' + suffix]
            if fr.contact.get(side):
                h = yaw_of(fr.qs[seg_f] @ rig.seg_C('foot' + suffix))
                fr.qs[seg_f] = (ry(h) @ rig.seg_C('foot' + suffix).inverted()).normalized()
            pole = knee_pole(rig, fr, side)
            err = max(err, ik2(rig, fr, [('right' if side == 'R' else 'left') + r for r in ('upleg', 'leg', 'foot')],
                               ['thigh' + suffix, 'shin' + suffix], fr.foot[side], pole))
        # つま先が地面へ潜るなら足首の目標を上げる（遊脚で足先が下がった時）
        _, P = solve(rig, fr.qs, fr.off, {})
        raised = False
        for side in ('R', 'L'):
            pre = 'right' if side == 'R' else 'left'
            low = min((P[rig.index[r]].y - rig.P0[rig.index[r]].y) for r in (pre + 'toebase', pre + 'toe_end') if r in rig.index)
            if low < -0.004:
                fr.foot[side] = fr.foot[side] + V((0, -low, 0))
                raised = True
        if err < 0.002 and not raised:
            break
        if err >= 0.002:
            fr.off = fr.off - V((0, err, 0))
    return err


def knee_pole(rig, fr, side):
    pre = 'right' if side == 'R' else 'left'
    _, P = solve(rig, fr.qs, fr.off, {})
    hip, knee, foot = P[rig.index[pre + 'upleg']], P[rig.index[pre + 'leg']], P[rig.index[pre + 'foot']]
    line = (foot - hip)
    if line.length < 1e-6:
        return V((0, 0, -1))
    d = line.normalized()
    v = knee - hip
    perp = v - d * d.dot(v)
    if perp.length < 0.01:
        return (fr.qs[SEG['hips']] @ V((0, 0, -1)))
    return perp.normalized()


def ik2(rig, fr, roles, segs, target, pole):
    """二関節 IK（author_h025_motion.ik と同じ式。fr.qs を書き換える）。戻り値 = 届かなかった距離（m）。"""
    _, P = solve(rig, fr.qs, fr.off, {})
    a, b, c = [rig.index[r] for r in roles]
    base = P[a]
    l1, l2 = (rig.P0[b] - rig.P0[a]).length, (rig.P0[c] - rig.P0[b]).length
    toward = target - base
    dist = min(l1 + l2 - .001, max(abs(l1 - l2) + .001, toward.length))
    direction = toward.normalized()
    bend = pole - direction * direction.dot(pole)
    if bend.length < .001:
        bend = V((1, 0, 0))
    bend.normalize()
    along = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    joint = base + direction * along + bend * math.sqrt(max(0, l1 * l1 - along * along))
    end = base + direction * dist
    for seg, vec in zip(segs, [joint - base, end - joint]):
        i = SEG[seg]
        fr.qs[i] = (cm.rotation_between(fr.qs[i] @ cm.DOWN, vec) @ fr.qs[i]).normalized()
    return max(0.0, toward.length - (l1 + l2 - .001))


# MARK: - 剣と手

def clamp_wrist(blade, forearm, lo=25.0, hi=125.0):
    """剣の向き（柄 → 切っ先）を前腕の向き（肘 → 手首）に対する角の範囲へ（手首の可動域。槌握り）。"""
    b, f = blade.normalized(), forearm.normalized()
    ang = math.degrees(math.acos(max(-1, min(1, b.dot(f)))))
    want = min(hi, max(lo, ang))
    if abs(want - ang) < 1e-3:
        return b
    axis_v = f.cross(b)
    if axis_v.length < 1e-6:
        axis_v = f.orthogonal()
    return (Quaternion(axis_v.normalized(), math.radians(want)) @ f).normalized()


def set_blade(rig, fr, direction, clearance=0.06):
    """右手の区間を最小の回転で回し、剣（区間の -Z）を direction へ向ける（手首の可動域で制限）。
    剣が胴・頭・脚を貫く向きなら、前腕のまわりに回して（手首の角は保つ）最も近い抜ける向きへ。"""
    _, P = solve(rig, fr.qs, fr.off, {})
    forearm = P[rig.index['righthand']] - P[rig.index['rightforearm']]
    d = clamp_wrist(direction, forearm)
    grip = P[rig.index['righthand']]
    if body_clearance(rig, P, grip, d) < clearance:
        f = forearm.normalized()
        best = (body_clearance(rig, P, grip, d), d)
        for deg in (12, -12, 24, -24, 36, -36, 50, -50, 65, -65, 80, -80, 100, -100, 125, -125, 150, -150):
            c = (Quaternion(f, math.radians(deg)) @ d).normalized()
            cl = body_clearance(rig, P, grip, c)
            if cl >= clearance:
                best = (cl, c)
                break
            if cl > best[0]:
                best = (cl, c)
        d = best[1]
    q = fr.qs[SEG['handR']]
    fr.qs[SEG['handR']] = (cm.rotation_between(q @ V((0, 0, -1)), d) @ q).normalized()
    fr.blade = d


BODY = (('hips', 'spine2', 0.13), ('spine2', 'neck', 0.12), ('neck', 'head', 0.07), ('rightupleg', 'rightleg', 0.085),
        ('rightleg', 'rightfoot', 0.065), ('leftupleg', 'leftleg', 0.085), ('leftleg', 'leftfoot', 0.065))


def body_clearance(rig, P, grip, d, length=1.05):
    """剣（握りの少し先から切っ先）と胴・頭・脚（太さ込み）の最短距離（m。負 = 貫通）。"""
    a, b = grip + d * 0.14, grip + d * length
    best = 9.0
    for r0, r1, rad in BODY:
        if r0 in rig.index and r1 in rig.index:
            best = min(best, seg_dist(a, b, P[rig.index[r0]], P[rig.index[r1]]) - rad)
    if 'head' in rig.index:
        h = P[rig.index['head']] + V((0, 0.1, 0))
        best = min(best, seg_dist(a, b, h, h) - 0.13)
    return best


def arm_ik(rig, fr, side, target, pole):
    pre = 'right' if side == 'R' else 'left'
    suf = 'R' if side == 'R' else 'L'
    # 手の区間（剣の向き）は保つ
    keep = fr.qs[SEG['hand' + suf]].copy()
    e = ik2(rig, fr, [pre + 'arm', pre + 'forearm', pre + 'hand'], ['arm' + suf, 'foreArm' + suf], target, pole)
    fr.qs[SEG['hand' + suf]] = keep
    return e


def blade_clearance(rig, fr, length=1.05):
    """剣（握りから切っ先）と脚・胴の最短距離（m）。"""
    _, P = solve(rig, fr.qs, fr.off, {})
    grip = P[rig.index['righthand']] + fr.qs[SEG['handR']] @ V((0, -rig_grip(rig), 0))
    tip = grip + fr.blade * length if fr.blade is not None else grip + (fr.qs[SEG['handR']] @ V((0, 0, -1))) * length
    best = 9.0
    for a, b in (('rightupleg', 'rightleg'), ('rightleg', 'rightfoot'), ('leftupleg', 'leftleg'), ('leftleg', 'leftfoot'),
                 ('hips', 'spine2')):
        best = min(best, seg_dist(grip + (tip - grip) * 0.12, tip, P[rig.index[a]], P[rig.index[b]]))
    return best


def rig_grip(rig):
    h, f = rig.index['righthand'], rig.index.get('righthandindex1')
    return 0.6 * (rig.P0[f] - rig.P0[h]).length if f is not None else 0.06


def seg_dist(p1, q1, p2, q2):
    best = 9.0
    for i in range(9):
        a = p1.lerp(q1, i / 8)
        d = q2 - p2
        t = max(0, min(1, (a - p2).dot(d) / max(1e-9, d.dot(d))))
        best = min(best, (a - (p2 + d * t)).length)
    return best


# MARK: - 指・肩・つま先

GRIP_R = {'thumb': (28, 30, 22), 'index': (62, 78, 48), 'middle': (70, 82, 50), 'ring': (74, 84, 50), 'pinky': (78, 84, 48)}


def finger_details(rig, side, curl, spread=0.0):
    """curl: 指 → (第 1, 2, 3 関節の度)。spread: 開き（度、人差し指 + / 小指 −）。"""
    sign = 1 if side == 'right' else -1
    out = {}
    for finger, degs in curl.items():
        for n in (1, 2, 3):
            role = side + 'hand' + finger + str(n)
            if role not in rig.index:
                continue
            q = axis((0, 0, -sign), math.radians(degs[n - 1]))
            if n == 1 and spread:
                s = {'index': 1, 'middle': .3, 'ring': -.3, 'pinky': -1, 'thumb': 0}[finger] * spread
                q = axis((0, 1, 0), math.radians(s) * sign) @ q
            out[role] = local_delta(rig, role, q)
    return out


def relaxed(k):
    """左手の指の曲げ（k = 0 開き〜1 握り）。"""
    open_ = {'thumb': (6, 8, 6), 'index': (6, 10, 8), 'middle': (8, 12, 8), 'ring': (10, 14, 10), 'pinky': (12, 16, 10)}
    fist = {'thumb': (26, 30, 22), 'index': (70, 85, 55), 'middle': (75, 88, 55), 'ring': (78, 88, 55), 'pinky': (80, 88, 52)}
    return {f: tuple(a + (b - a) * k for a, b in zip(open_[f], fist[f])) for f in open_}


def details_for(rig, fr, left_curl, left_spread=0.0, toe=True):
    det = {}
    for role in ('leftshoulder', 'rightshoulder') + (('lefttoebase', 'righttoebase') if toe else ()):
        if role in fr.det and role in rig.index:
            det[role] = local_delta(rig, role, fr.det[role])
    det.update(finger_details(rig, 'right', GRIP_R))
    det.update(finger_details(rig, 'left', left_curl, left_spread))
    return det


# MARK: - 平滑化・ブレンド

def smooth_segments(frames, segs, radius, loop):
    """区間回転の移動平均（ループは周回）。頭・剣の周期的な震えを除く。"""
    n = len(frames)
    for s in segs:
        orig = [fr.qs[s].copy() for fr in frames]
        for i, fr in enumerate(frames):
            acc = Quaternion((0, 0, 0, 0))
            wsum = 0.0
            ref = orig[i]
            for k in range(-radius, radius + 1):
                j = (i + k) % n if loop else max(0, min(n - 1, i + k))
                q = orig[j]
                if q.dot(ref) < 0:
                    q = cm.neg(q)
                w = math.exp(-0.5 * (k / max(1, radius / 2)) ** 2)
                acc = Quaternion((acc.w + q.w * w, acc.x + q.x * w, acc.y + q.y * w, acc.z + q.z * w))
                wsum += w
            fr.qs[s] = acc.normalized()


def blend_pose(fr, other, w, segs=range(15), off=True):
    for s in segs:
        fr.qs[s] = cm.slerp(fr.qs[s], other.qs[s], w).normalized()
    if off:
        fr.off = fr.off.lerp(other.off, w)
    for r, q in other.det.items():
        if r in fr.det:
            fr.det[r] = cm.slerp(fr.det[r], q, w)


def copy_frame(fr):
    c = Frame([q.copy() for q in fr.qs], fr.off.copy(), {r: q.copy() for r, q in fr.det.items()}, dict(fr.pts))
    c.contact = dict(fr.contact)
    c.foot = {k: v.copy() for k, v in fr.foot.items()}
    c.blade = fr.blade.copy() if fr.blade is not None else None
    return c


def distribute_seam(frames, end_frame):
    """ループ: 最後の次（= 1 周後）の姿勢と先頭の差を 1 周に配る（継ぎ目を 0 に）。"""
    n = len(frames)
    first = frames[0]
    for s in range(15):
        d = (first.qs[s] @ end_frame.qs[s].inverted()).normalized()
        if d.w < 0:
            d = cm.neg(d)
        for i, fr in enumerate(frames):
            fr.qs[s] = (cm.slerp(Quaternion(), d, i / n) @ fr.qs[s]).normalized()
    dv = first.off - end_frame.off
    for i, fr in enumerate(frames):
        fr.off = fr.off + dv * (i / n)
    for r in first.det:
        if r not in end_frame.det:
            continue
        d = (first.det[r] @ end_frame.det[r].inverted()).normalized()
        for i, fr in enumerate(frames):
            fr.det[r] = (cm.slerp(Quaternion(), d, i / n) @ fr.det[r]).normalized()


def find_cycle(src, lo, hi, pmin, pmax):
    """[lo, hi] の中で 1 周（2 歩）の長さと始まり（脚の区間の差が最小）。"""
    legs = [SEG[s] for s in ('thighR', 'shinR', 'thighL', 'shinL', 'hips')]

    def dist(a, b):
        qa, qb = src.at(a)[0], src.at(b)[0]
        return sum(cm.quat_angle_deg(qa[s], qb[s]) for s in legs)
    best = None
    for p in range(pmin, pmax + 1):
        score = sum(dist(f, f + p) for f in range(lo, hi - p, 2)) / max(1, len(range(lo, hi - p, 2)))
        if best is None or score < best[0]:
            best = (score, p)
    p = best[1]
    start = min(range(lo, hi - p + 1), key=lambda f: dist(f, f + p))
    return start, p, dist(start, start + p)


# MARK: - クリップごとの仕上げ

def build_idle(rig, srcs, ground):
    src = srcs['idle2']
    N, B = 96, 24
    times = [i / FPS for i in range(N + 1)]
    keys = [(0, 0), (N / FPS, N)]
    frames = sample_frames(rig, src, times, keys, yaw=-math.radians(4))
    # 元の 96〜119 フレームを先頭の 24 フレームへ重ね、継ぎ目を無くす
    extra = sample_frames(rig, src, [i / FPS for i in range(B)], [(0, N), (B / FPS, N + B)], yaw=-math.radians(4))
    for i in range(B):
        blend_pose(frames[i], extra[i], 1 - smooth(i / B))
    end = frames[N]
    frames = frames[:N]
    distribute_seam(frames, end)
    # 頭（バイザー）・胴・剣の手の周期的な震えを除く。視線を先行させ、左肩・左腕を遅れて追従させる
    smooth_segments(frames, [SEG['head'], SEG['torso'], SEG['hips']], 6, True)
    smooth_segments(frames, [SEG['armR'], SEG['foreArmR'], SEG['handR']], 10, True)
    lag = 8
    orig = [copy_frame(fr) for fr in frames]
    for i, fr in enumerate(frames):
        lagged = orig[(i - lag) % N]
        for s in (SEG['armL'], SEG['foreArmL'], SEG['handL']):
            fr.qs[s] = lagged.qs[s].copy()
        if 'leftshoulder' in lagged.det:
            fr.det['leftshoulder'] = lagged.det['leftshoulder']
        # 視線: 頭は胴より 6 フレーム先の向き
        fr.qs[SEG['head']] = orig[(i + 6) % N].qs[SEG['head']].copy()
    smooth_segments(frames, [SEG['armL'], SEG['foreArmL'], SEG['handL']], 5, True)
    # 堂々とした直立の構え: 腰・胴・頭を起こし（元の揺れは 1 割だけ残す）、膝はわずかに曲げる程度へ腰を上げる
    for fr in frames:
        for s, k in (('hips', 0.85), ('torso', 0.9), ('head', 0.92)):
            q = fr.qs[SEG[s]]
            up = q @ V((0, 1, 0))
            fr.qs[SEG[s]] = (cm.rotation_between(up, up.lerp(V((0, 1, 0)), k).normalized()) @ q).normalized()
    cx = sum((fr.off.x for fr in frames), 0.0) / N
    cz = sum((fr.off.z for fr in frames), 0.0) / N
    y0 = sum((yaw_of(fr.qs[SEG['torso']]) for fr in frames), 0.0) / N
    for i, fr in enumerate(frames):
        fr.off = V((cx, -0.025 + 0.006 * math.sin(math.tau * i / N), cz))
    # 足は肩幅、右足をわずかに前へ（剣の側）
    pins = {'R': V((cx, 0, cz)) + ry(y0) @ V((0.15, 0, -0.06)), 'L': V((cx, 0, cz)) + ry(y0) @ V((-0.14, 0, 0.07))}
    flags = {s: [True] * N for s in FOOT_ROLES}
    plant_feet(rig, frames, flags, True, ground, pin_pos=pins)
    errs = [solve_legs(rig, fr, ground) for fr in frames]
    # 右手: 柄を腰の前でしっかり握り、剣は右前下へ斜めに下ろす。左手は拳を体の脇へ
    for i, fr in enumerate(frames):
        y = yaw_of(fr.qs[SEG['torso']])
        Y = ry(y)
        _, P = solve(rig, fr.qs, fr.off, {})
        sway = 0.008 * math.sin(math.tau * i / N + 0.6)
        arm_ik(rig, fr, 'R', P[rig.index['rightarm']] + Y @ V((0.1, -0.4 + sway, -0.2)), Y @ V((0.7, -0.1, 0.7)).normalized())
        arm_ik(rig, fr, 'L', P[rig.index['leftarm']] + Y @ V((-0.07, -0.5 + sway, 0.03)), Y @ V((-0.5, 0, 0.85)).normalized())
        fr.qs[SEG['handL']] = fr.qs[SEG['foreArmL']].copy()
        set_blade(rig, fr, Y @ V((0.32, -0.62, -0.72)).normalized())
    # 左手の指先: ゆっくり開閉（2 回/周）
    dets = []
    for i, fr in enumerate(frames):
        k = 0.72 + 0.05 * math.sin(2 * math.tau * i / N)
        dets.append(details_for(rig, fr, relaxed(k), left_spread=0.0))
    return dict(name='idle_h028', frames=frames, dets=dets, loop=True, events={}, melee=False,
                ik=max(errs), source=f'idle2_prime')


def build_loco(rig, srcs, ground, kind):
    if kind == 'walk':
        src, lo, hi, pr = srcs['walk2'], 10, 86, (20, 44)
        stride, lift, bounce, upper_twist, blade_dir, lean = 1.0, 0.8, 0.8, 0.55, V((0.42, -0.5, 0.76)), 0.0
    else:
        src, lo, hi, pr = srcs['run'], 12, 62, (16, 26)
        stride, lift, bounce, upper_twist, blade_dir, lean = None, 0.6, 0.55, 0.6, V((0.34, -0.38, 0.86)), 0.06
    start, period, seam = find_cycle(src, lo, hi, *pr)
    # 1 周の前進（元の脚の長さ単位）と向き
    r0, r1 = src.root[start], src.at(start + period)[1]
    travel = V((r1.x - r0.x, 0, r1.z - r0.z))
    yaw = -math.atan2(-travel.x, -travel.z)     # travel を -Z へ回す角
    per_frame = travel / period
    N = int(round(period))
    step = period / N
    times = [i * step / FPS for i in range(N + 1)]
    keys = [(0, start), (period / FPS, start + period)]
    L = rig.leg_length
    frames = sample_frames(rig, src, times, keys, yaw, travel=per_frame, travel_origin=V((r0.x, 0, r0.z)))
    speed_src = per_frame.length * FPS * L      # m/s（モデル空間）
    if stride is None:
        # 走行: ゲームの走る速さ（約 3 m/s）に元の歩調のまま合わせる（歩幅を縮める）
        stride = 3.0 / BP_SCALE / speed_src
    end = frames[N]
    frames = frames[:N]
    # 接地（元のワールドの足の速さで判定）
    fl = contacts(src, start, start + period - step, step, rel_speed=0.35 * per_frame.length * FPS)
    distribute_seam(frames, end)
    # 上体を抑える: 胴・頭のねじれを平均の向きへ寄せ、半身の向きを進む向きへ近づける
    mean_t = sum((yaw_of(fr.qs[SEG['torso']]) for fr in frames)) / N
    mean_h = sum((yaw_of(fr.qs[SEG['hips']]) for fr in frames)) / N
    for fr in frames:
        for s, m, k in ((SEG['torso'], mean_t, upper_twist), (SEG['head'], mean_t, upper_twist * 0.9), (SEG['hips'], mean_h, 0.4)):
            y = yaw_of(fr.qs[s])
            dy = math.atan2(math.sin(y - m), math.cos(y - m))
            fr.qs[s] = (ry(-dy * k) @ fr.qs[s]).normalized()
        # 半身の向き（元は進む向きから外れている）を 60% 戻す
        for s in (SEG['hips'], SEG['torso'], SEG['head']):
            fr.qs[s] = (ry(-mean_h * 0.6) @ fr.qs[s]).normalized()
        if lean:
            for s in (SEG['torso'], SEG['head']):
                fr.qs[s] = (Quaternion((1, 0, 0), -lean) @ fr.qs[s]).normalized()
    smooth_segments(frames, [SEG['head']], 3, True)
    # 歩幅・足の持ち上げ・腰の上下を調整した足首の目標（元の足首の軌跡を腰の真下を中心に縮める）
    hip_y = sum(fr.off.y for fr in frames) / N
    low = 0.07 if kind == 'walk' else 0.035      # 腰を低く保つ
    for fr in frames:
        fr.off = V((fr.off.x * 0.6, hip_y - low + (fr.off.y - hip_y) * bounce, fr.off.z * stride))
    back = V((0, 0, per_frame.length * L * stride * step))   # 1 出力フレームの後退（m）
    for side, role in FOOT_ROLES.items():
        for fr in frames:
            p = fr.pts[role]
            fr.pts[role] = V((p.x, ground + max(0, p.y - ground) * lift, p.z * stride))
    plant_feet_loco(rig, frames, fl, ground, back)
    errs = [solve_legs(rig, fr, ground) for fr in frames]
    for fr in frames:
        y = yaw_of(fr.qs[SEG['hips']])
        set_blade(rig, fr, ry(y) @ blade_dir.normalized())
    # 剣を脚から離す: 近ければ右腕を外へ開く
    clear = []
    for fr in frames:
        c = blade_clearance(rig, fr)
        if c < 0.1:
            _, P = solve(rig, fr.qs, fr.off, {})
            hand = P[rig.index['righthand']]
            arm_ik(rig, fr, 'R', hand + (fr.qs[SEG['hips']] @ V((0.1 - c, 0, 0))), V((1, 0, 0.3)))
            set_blade(rig, fr, ry(yaw_of(fr.qs[SEG['hips']])) @ blade_dir.normalized())
            c = blade_clearance(rig, fr)
        clear.append(c)
    dets = [details_for(rig, fr, relaxed(0.55 if kind == 'run' else 0.3)) for fr in frames]
    gs = per_frame.length * FPS * L * stride * BP_SCALE
    return dict(name=f'{kind}_h028', frames=frames, dets=dets, loop=True, events={}, melee=False, groundSpeed=round(gs, 4),
                ik=max(errs), source=f'{src.name}', cycle=[start, period, round(seam, 2)], clearance=round(min(clear), 3))


def plant_feet_loco(rig, frames, fl, ground, back):
    """移動: 足首の目標 = 縮めた元の足首（接地中は等速で後ろへ流す）。"""
    n = len(frames)
    for side, role in FOOT_ROLES.items():
        flags = fl[side][:n] + [fl[side][-1]] * max(0, n - len(fl[side]))
        raw = [fr.pts[role].copy() for fr in frames]
        # 接地の区間: 中央の位置から等速で後退する直線へ
        targets = list(raw)
        i = 0
        # ループなので区間が端をまたぐ場合は回して扱う
        shift = next((k for k in range(n) if not flags[k]), 0)
        order = [(shift + k) % n for k in range(n)]
        k = 0
        while k < n:
            m = order[k]
            if not flags[m]:
                k += 1
                continue
            j = k
            while j + 1 < n and flags[order[j + 1]]:
                j += 1
            seg = [order[x] for x in range(k, j + 1)]
            mid = (k + j) / 2
            anchor = sum((raw[s] - back * (x - mid) for x, s in zip(range(k, j + 1), seg)), V((0, 0, 0))) / len(seg)
            for x, s in zip(range(k, j + 1), seg):
                t = anchor + back * (x - mid)
                t.y = ground
                targets[s] = t
            k = j + 1
        delta = [targets[m] - raw[m] for m in range(n)]
        idx = [m for m in range(n) if flags[m]]
        for m in range(n):
            if flags[m] or not idx:
                continue
            prev = max([x for x in idx if x < m], default=idx[-1] - n)
            nxt = min([x for x in idx if x > m], default=idx[0] + n)
            w = smooth((m - prev) / (nxt - prev))
            delta[m] = delta[prev % n].lerp(delta[nxt % n], w)
        sign = 1 if side == 'R' else -1
        for m, fr in enumerate(frames):
            t = raw[m] + delta[m]
            t.y = max(t.y, ground)
            # 足を交差させない（腰の中心から左右へ 8.5cm 以上）
            t.x = fr.off.x + sign * max(0.085, sign * (t.x - fr.off.x))
            fr.foot[side] = t
            fr.contact[side] = flags[m]


def build_action(rig, srcs, ground, guard, spec):
    """攻撃・スキル: 元の区間を時間の対応で切り出し、打撃の瞬間の胴を正面へ、両端を構えへつなぐ。"""
    src = srcs[spec['src']]
    keys = spec['keys']
    total = keys[-1][0]
    N = int(round(total * FPS)) + 1
    times = [i / FPS for i in range(N)]
    face_f = spec['face']
    qf = src.at(face_f)[0]
    yaw = -yaw_of(qf[SEG['torso']]) + spec.get('yaw_bias', 0.0)
    frames = sample_frames(rig, src, times, keys, yaw)
    # 時間で変える向き（多段の打撃でそれぞれの打撃の胴を対象へ向ける）
    if spec.get('yaw_curve'):
        kc = [(t, math.radians(d)) for t, d in spec['yaw_curve']]
        for i, fr in enumerate(frames):
            Yt = ry(warp_smooth(kc, times[i]))
            fr.qs = [(Yt @ q).normalized() for q in fr.qs]
            fr.off = Yt @ fr.off
            fr.pts = {r: Yt @ p for r, p in fr.pts.items()}
    # 打撃の間の余分な振り（元の動作の打撃の数が多い所）を、前後の姿勢の補間で置き換える
    for t0, t1, segs in spec.get('bridge', []):
        i0, i1 = int(round(t0 * FPS)), int(round(t1 * FPS))
        a, b = copy_frame(frames[i0]), copy_frame(frames[i1])
        for i in range(i0 + 1, i1):
            w = smooth((i - i0) / (i1 - i0))
            for sname in segs:
                frames[i].qs[SEG[sname]] = cm.slerp(a.qs[SEG[sname]], b.qs[SEG[sname]], w).normalized()
    # 腰の水平のずれ: 先頭を 0 に、倍率を掛け、終わりへ向けて 0 へ戻す
    o0 = frames[0].off.copy()
    xz = spec.get('rootXZ', 0.6)
    for i, fr in enumerate(frames):
        d = fr.off - o0
        fr.off = V((o0.x + d.x * xz, fr.off.y, o0.z + d.z * xz))
    # 胴・腰の向きの補正（半身の構えを正面寄りに。区間ごと）
    for s, dy in spec.get('turn', {}).items():
        for i, fr in enumerate(frames):
            w = 1.0 if not callable(dy) else 1.0
            ang = dy(times[i]) if callable(dy) else dy
            fr.qs[SEG[s]] = (ry(ang) @ fr.qs[SEG[s]]).normalized()
    # 接地（元の接地区間）
    lo = keys[0][1]
    fl = {}
    for side, role in FOOT_ROLES.items():
        flags = []
        for i, t in enumerate(times):
            f = warp(keys, t)
            p0, p1 = src.at(f - 1)[2][role], src.at(f + 1)[2][role]
            sp = (V((p1.x, 0, p1.z)) - V((p0.x, 0, p0.z))).length * FPS / 2
            y = src.at(f)[2][role].y
            floor = min(src.at(x)[2][role].y for x in range(int(lo), int(keys[-1][1]) + 1))
            flags.append(y - floor < 0.08 and sp < 0.9)
        fl[side] = clean(flags)
        if spec.get('lock_feet'):
            fl[side] = [True] * N
    plant_feet(rig, frames, fl, False, ground)
    # 両端を構えへ（先頭 blend_in 秒・末尾 blend_out 秒）。足の目標も構えの足へ
    bi, bo = spec.get('blend_in', 0.1), spec.get('blend_out', 0.18)
    for i, fr in enumerate(frames):
        t = times[i]
        w = 0.0
        if bi > 0 and t < bi:
            w = 1 - smooth(t / bi)
        if bo > 0 and t > total - bo:
            w = max(w, smooth((t - (total - bo)) / bo))
        if w > 0:
            blend_pose(fr, guard, w)
            for side in FOOT_ROLES:
                fr.foot[side] = fr.foot[side].lerp(guard.foot[side], w)
                if w > 0.5:
                    fr.contact[side] = True
    errs = [solve_legs(rig, fr, ground) for fr in frames]
    # 剣: 元の手の向き（可動域で制限）。指定の区間は向きを上書き
    for i, fr in enumerate(frames):
        d = fr.qs[SEG['handR']] @ V((0, 0, -1))
        over = spec.get('blade')
        if over:
            w, vec = over(times[i], fr)
            if w > 0:
                d = d.lerp(vec, w)
        set_blade(rig, fr, d)
    # 両端の剣の向きを構えへ
    for i, fr in enumerate(frames):
        t = times[i]
        w = (1 - smooth(t / bi)) if (bi > 0 and t < bi) else 0.0
        if bo > 0 and t > total - bo:
            w = max(w, smooth((t - (total - bo)) / bo))
        if w > 0:
            fr.qs[SEG['handR']] = cm.slerp(fr.qs[SEG['handR']], guard.qs[SEG['handR']], w)
    left = spec.get('left', lambda t: (relaxed(0.45), 0.0))
    dets = []
    for i, fr in enumerate(frames):
        curl, spread = left(times[i])
        dets.append(details_for(rig, fr, curl, spread))
    return dict(name=spec['name'], frames=frames, dets=dets, loop=False, events=spec['events'], melee=spec.get('melee', True),
                ik=max(errs), source=src.name, extra=spec.get('extra', {}))


# MARK: - 書き出し

def to_clip(rig, c):
    joints = [r for r in DETAILS if r in rig.index]
    out = dict(name=c['name'], source=f"meshy:text-to-motion:{c['source']}+local:H028-finish", frames=len(c['frames']),
               loop=c['loop'], rootXZ=1 if not c['loop'] else 0, melee=c['melee'], events=c['events'], rot=[], root=[],
               detailJoints=joints, detailRot=[])
    if 'groundSpeed' in c:
        out['groundSpeed'] = c['groundSpeed']
    out.update(c.get('extra', {}))
    L = rig.leg_length
    prev, pd = [None] * 15, [None] * len(joints)
    for fr, det in zip(c['frames'], c['dets']):
        for i, q in enumerate(fr.qs):
            vals, prev[i] = pack(q, prev[i])
            out['rot'] += [round(v, 5) for v in vals]
        out['root'] += [round(x / L, 5) for x in fr.off]
        for i, role in enumerate(joints):
            vals, pd[i] = pack(det.get(role, Quaternion()), pd[i])
            out['detailRot'] += [round(v, 5) for v in vals]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='App/Resources/Heroes/H028MotionClips.json')
    ap.add_argument('--only', default='')
    a = ap.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    rig, meshes, height, warnings = preview.load_hero(str(Path(HERO).resolve()))
    axis_err = bind_usd_axes(rig, HERO)
    data = json.load(open(SOURCE))
    srcs = {c['name'].replace('h028src_', ''): Source(c) for c in data['clips']}
    ground = rig.P0[rig.index['rightfoot']].y
    ground = min(ground, rig.P0[rig.index['leftfoot']].y)
    report = dict(model=dict(bones=len(rig.names), height=height, legLength=rig.leg_length, usdAxisDegrees=axis_err,
                             fingers='righthandindex1' in rig.index))
    built = []
    idle = build_idle(rig, srcs, ground)
    built.append(idle)
    guard = copy_frame(idle['frames'][0])
    built.append(build_loco(rig, srcs, ground, 'walk'))
    built.append(build_loco(rig, srcs, ground, 'run'))
    from h028_specs import action_specs
    for spec in action_specs(math, V, relaxed):
        built.append(build_action(rig, srcs, ground, guard, spec))
    clips = [to_clip(rig, c) for c in built]
    for c, b in zip(clips, built):
        report[c['name']] = dict(frames=c['frames'], ik_mm=round(b['ik'] * 1000, 2), events=c['events'],
                                 groundSpeed=c.get('groundSpeed'), cycle=b.get('cycle'), clearance=b.get('clearance'))
    Path(a.out).write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=clips), separators=(',', ':')) + '\n')
    Path('build/h028-motion').mkdir(parents=True, exist_ok=True)
    Path('build/h028-motion/finish-report.json').write_text(json.dumps(report, indent=1))
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
