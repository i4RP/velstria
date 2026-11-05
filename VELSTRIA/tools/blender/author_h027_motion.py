"""H027 竜槍のジャルド: motion finishing on the shipped (finger re-rigged) model, Blender 5.2 (4.5.10 on Windows gives the same values).

Meshy prime clips supply body mechanics (hips/torso/head rotation and hips height, time-warped to the
game timing); the spear itself is choreographed explicitly (grip point + shaft direction in hero space),
and both hands are solved onto the shaft with two-bone IK, a hinge-aligned elbow and a split forearm
twist. Feet are planted (or follow a stride that cancels the ground speed). Output is the runtime's
15 segments plus local shoulder / toe / finger deltas (docs/HERO_MOTION.md, docs/H027_MOTION.md).

Run from VELSTRIA:
  Blender -b -P tools/blender/author_h027_motion.py -- [--only h027_idle,...] [--preview] [--video]
"""
import argparse
import json
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_h025_motion as h25
import clip_math as cm
import preview_clip as preview

V = Vector
FPS = 30
HERO = 'App/Resources/Heroes/Hero_H027.usdz'
OUT = Path('build/h027-motion')
DETAILS = h25.DETAILS
# Dragon spear (HeroGear .dragonSpear): grip at the origin, +Y to the tip, entity scale 1.08 (weaponScale) x 0.7 (SkinnedHeroModel
# gearScale: MLBB's spear is 1.5-1.7x the standing height, docs/H027_QUALITY.md).
SPEAR_SCALE = 1.08 * 0.7
# MLBB holds the spear near the middle (training idle: hand to blade ~ hand to butt). The prop origin is 29 % from the butt, so the
# fist grips GRIP_SHIFT m further toward the tip (HeroMotionSets "H027" weaponOffset = (0, -GRIP_SHIFT, 0)).
GRIP_SHIFT = 0.25
SPEAR_BUTT = -0.84 * SPEAR_SCALE - GRIP_SHIFT
SPEAR_TIP = 2.04 * SPEAR_SCALE - GRIP_SHIFT
# HeroBlueprints H027 scale: the clip's feet travel x 1.06 in the game, so groundSpeed is exported in game metres.
BP_SCALE = 1.06
SHAFT_R = 0.03 * SPEAR_SCALE
# Weapon orientation while clips play = q.handR * GRIP (HeroMotionSets "H027" weaponGrip). +Y (shaft) leaves the
# fist on the thumb side (canonical -Z); the roll puts the blade face up in the guard (solved in main, see report).
GRIP_ROLL = None


def rad(d):
    return math.radians(d)


def ry(d):
    return Quaternion((0, 1, 0), rad(d))


def rx(d):
    return Quaternion((1, 0, 0), rad(d))


def rz(d):
    return Quaternion((0, 0, 1), rad(d))


def spear_dir(yaw, pitch):
    """Shaft direction: yaw 0 = forward (-Z), + turns toward the left (-X, same sense as cm.ry); pitch + = up."""
    cy, sy, cp, sp = math.cos(rad(yaw)), math.sin(rad(yaw)), math.cos(rad(pitch)), math.sin(rad(pitch))
    return V((-sy * cp, sp, -cy * cp))


def grip_quat(roll):
    """GRIP = rx(-90°) * ry(roll): weapon +Y -> canonical -Z (thumb side), weapon +Z -> canonical (sin, cos, 0)."""
    return (Quaternion((1, 0, 0), -math.pi / 2) @ Quaternion((0, 1, 0), roll)).normalized()


# MARK: - Keyframe tracks (monotone cubic Hermite; loops wrap with periodic tangents)

def catmull(t, pts):
    """Catmull-Rom through (t, value) knots (clamped ends): smooth through every knot without stopping at it."""
    for i in range(len(pts) - 1):
        (t1, p1), (t2, p2) = pts[i], pts[i + 1]
        if t <= t2 or i == len(pts) - 2:
            p0 = pts[i - 1][1] if i > 0 else p1 - (p2 - p1)
            p3 = pts[i + 2][1] if i + 2 < len(pts) else p2 + (p2 - p1)
            u = max(0.0, min(1.0, (t - t1) / max(1e-6, t2 - t1)))
            return 0.5 * (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3)
    return pts[-1][1]


def track_value(keys, t, loop, period):
    if not keys:
        return None
    if len(keys) == 1:
        return keys[0][1]
    ks = list(keys)
    if loop:
        t = t % period
        ks = [(ks[-1][0] - period, ks[-1][1])] + ks + [(ks[0][0] + period, ks[0][1])]
    else:
        if t <= ks[0][0]:
            return ks[0][1]
        if t >= ks[-1][0]:
            return ks[-1][1]
    i = max(k for k in range(len(ks) - 1) if ks[k][0] <= t)
    i = min(i, len(ks) - 2)
    (t0, v0), (t1, v1) = ks[i], ks[i + 1]
    h = max(1e-6, t1 - t0)

    def slope(a, b):
        return (ks[b][1] - ks[a][1]) / max(1e-6, ks[b][0] - ks[a][0])

    def tangent(k):
        if k <= 0 or k >= len(ks) - 1:
            return 0.0
        d0, d1 = slope(k - 1, k), slope(k, k + 1)
        if d0 * d1 <= 0:
            return 0.0
        # Fritsch-Carlson style harmonic mean: no overshoot between keys
        return 2.0 / (1.0 / d0 + 1.0 / d1)
    m0, m1 = tangent(i), tangent(i + 1)
    s = (t - t0) / h
    h00, h10, h01, h11 = 2 * s**3 - 3 * s**2 + 1, s**3 - 2 * s**2 + s, -2 * s**3 + 3 * s**2, s**3 - s**2
    return h00 * v0 + h10 * h * m0 + h01 * v1 + h11 * h * m1


# MARK: - Poses (MLBB 子龍の画面収録に合わせる: docs/H027_QUALITY.md)

# 構え（三連突き・詠唱の基準）: left foot forward, torso turned right, right fist in front of the right hip, left fist 0.22 m up
# the shaft, tip aimed at chest height of a target ahead. Arms are short on this model (shoulder→fist 0.41 m), so the body
# (hips/torso turn, lunge) carries most of the spear travel.
GUARD = dict(hy=-0.055, hx=0.0, hz=0.0, hyaw=-30, hpitch=2, hroll=0, tyaw=-46, tpitch=4, troll=0,
             dyaw=-4, dpitch=2, droll=0,
             lx=-0.11, lz=-0.17, lyaw=6, llift=0, lroll=0, rx=0.135, rz=0.15, ryaw=-30, rlift=0, rroll=0,
             ox=0.165, oy=1.0, oz=-0.03, syaw=9, spitch=8, lgrip=1, ld=0.22, lfx=-0.2, lfy=0.98, lfz=-0.05,
             rcurl=1, lcurl=1, lflex=0, rpx=0.9, rpy=-0.4, rpz=0.5, lpx=-0.9, lpy=-0.5, lpz=0.3, shR=0, shL=0)
# 待機（MLBB の訓練場 0.3〜2.0 秒・スキルプレビュー 41.5〜43.7 秒）: 足を左右へ広く開いて正面を向き、槍は右手で右腰に持ち、
# 穂先を右前の足元へ下ろす（石突は左肩の後ろへ上がる）。空いた左手は拳にして左腰の横。
STAND = dict(GUARD, hy=-0.25, hyaw=-10, hpitch=6, tyaw=-6, tpitch=4, dyaw=2, dpitch=-8,
             lx=-0.35, lz=-0.09, lyaw=24, rx=0.36, rz=0.08, ryaw=-28,
             ox=0.23, oy=0.86, oz=-0.02, syaw=-42, spitch=-38, lgrip=0, lfx=-0.25, lfy=1.0, lfz=-0.03,
             lcurl=0.9, rpx=1, rpy=-0.3, rpz=0.2, lpx=-1, lpy=-0.2, lpz=0.2)
# 槍を引きずる持ち方（走り・払いの前・振り下ろしの後。スキルプレビュー 31.1〜31.7 秒・44.7〜45.3 秒・51.0〜51.4 秒）: 右手を右腰に
# 置いたまま穂先を右後ろの足元へ寝かせ（真後ろから右へ 30°）、石突は前の肩の高さへ。左の拳は胸の前へ出す。上体は少し前へ傾ける。
TRAIL = dict(STAND, hy=-0.035, hyaw=-4, hpitch=5, tyaw=-8, tpitch=11, dyaw=6, dpitch=-10,
             lx=-0.10, lz=0.0, lyaw=4, rx=0.12, rz=0.0, ryaw=-6,
             ox=0.26, oy=0.99, oz=0.08, syaw=-150, spitch=-40, lgrip=0, lfx=-0.2, lfy=1.1, lfz=-0.18,
             lcurl=1, rpx=1, rpy=-0.3, rpz=-0.2, lpx=-1, lpy=-0.4, lpz=0.3)
# 払いの決め（スキルプレビュー 24.33〜24.80 秒）: 相手の方へ深く踏み込んだ低く広い構え（左足を 0.44 m 前、右足を後ろへ開き、腰を 0.2 m
# 落として上体を相手へ倒す）で、穂先を左後ろへ水平に残す（柄は背の後ろ、右手は右腰）。
REAR = dict(TRAIL, hy=-0.2, hz=-0.17, hyaw=-4, hpitch=8, tyaw=8, tpitch=16, dyaw=-2, dpitch=-10,
            lx=-0.22, lz=-0.44, lyaw=10, rx=0.2, rz=0.24, ryaw=-36,
            ox=0.225, oy=0.86, oz=0.02, syaw=150, spitch=-8, lfx=-0.22, lfy=0.96, lfz=-0.26, rpx=1, rpy=-0.4, rpz=0.1)
# 振り下ろしの決め（スキルプレビュー 25.20〜25.47 秒）: 振り抜いた勢いで体ごと右へ 90° 回り（胸がカメラの側）、低く広い構えで、
# 穂先を体の右前の足元へ下ろす（ヒーローの向きでは右後ろ = 引きずる持ち方と同じ向き）。左の拳は体の左（ヒーローの前）へ張る。
TURN = dict(TRAIL, hy=-0.17, hz=-0.04, hyaw=-80, hpitch=4, tyaw=-96, tpitch=10, dyaw=-70, dpitch=-6,
            lx=-0.12, lz=-0.3, lyaw=-30, rx=0.2, rz=0.22, ryaw=-80,
            ox=0.06, oy=0.85, oz=0.3, syaw=-140, spitch=-36, lfx=0.0, lfy=1.08, lfz=-0.46, rpx=0.3, rpy=-0.4, rpz=1,
            lpx=-0.4, lpy=-0.3, lpz=-1)


def keys_of(spec, name, base):
    ks = spec.get('keys', [])
    out = []
    for frame, values in ks:
        # an empty key = the whole base pose at that frame (attack start / end = guard)
        if not values:
            out.append((frame, base[name]))
        elif name in values:
            out.append((frame, values[name]))
    if not out:
        return [(0, base[name])]
    return out


# Clip specs: frames, loop, base pose, keyframes {frame: {channel: value}}, events, prime source + time warp.
def clip_specs():
    S = []
    # 待機 6 秒: 構えを崩さず呼吸 2 回、小さな重心移動、右 → 左へ見渡す、空いた左の拳を握り直す。穂先は足元のまま動かさない。
    S.append(dict(name='h027_idle', state='idle', frames=180, loop=True, base=STAND, rootXZ=1,
                  prime=('meshy_h027_idle', [(0, 10), (180, 110)], 0.3),
                  keys=[(0, dict(hz=0.0, dyaw=2, dpitch=-2, tyaw=-6, lflex=0)),
                        (30, dict(hz=-0.010, tyaw=-5)),
                        (55, dict(dyaw=20, dpitch=-1, tyaw=-2)),
                        (75, dict(dyaw=18, lflex=0)),
                        (84, dict(lflex=1)),
                        (90, dict(hz=0.008, tyaw=-7)),
                        (96, dict(lflex=0.15)),
                        (118, dict(dyaw=-14, dpitch=-3, tyaw=-11)),
                        (140, dict(dyaw=-12)),
                        (150, dict(hz=-0.005)),
                        (165, dict(dyaw=2, tyaw=-6, lflex=0))]))
    # 走行 0.333 秒 = 2 歩（MLBB の訓練場 75〜92 コマ: 接地が 4.5〜5 コマおき = 1 周 9.5〜10 コマ）。地面の速さ 2.65 m/s（子龍の 265）。
    # 胴を 42°・腰を 18° 前へ倒し（背骨の上だけに掛かるので見た目は 30° 前後）、蹴り出した足のかかとを高く上げて膝を前へ送る小刻みで大きな脚の回し方。槍は後ろへ引きずり、
    # 左の拳を胸の前で振る。
    S.append(dict(name='h027_run', state='run', frames=10, loop=True, base=dict(TRAIL, tpitch=42, hpitch=18, dpitch=-34, ox=0.3, oz=0.06, syaw=-155, spitch=-34, lfx=-0.14, lfy=1.12, lfz=-0.36),
                  rootXZ=0, groundSpeed=2.65, contact=0.36, hipsDrop=-0.1, bounce=0.04, lift=0.11,
                  heel=0.3, knee=0.27, kick=0.08, over=0.14, armSwing=0.2,
                  prime=('meshy_h027_run', None, 0.15)))
    # 歩行: MLBB は鈍足でも同じ走りを遅く再生するだけ（委員会A の 11-05 の監査、H032 の担当の発見）。走りと同じクリップを h027_walk として
    # 書き出す（地面の速さも同じなので、ランタイムは移動の速さに比例して遅く再生する。歩きと走りの切り替えで脚の形が変わらない）。
    S.append(dict(S[-1], name='h027_walk'))
    # 通常攻撃 A: 水平の払い（スキルプレビュー 24.07〜24.80 秒）。引きずる持ち方から腰と胸を右へ 62° ひねって穂先を右後ろへ引き、
    # 左足を持ち上げて（4〜7）前へ 0.44 m 踏み込み（9）、腰を 0.2 m 落としながら右 → 前 → 左へ大きく払う（打撃 10 = 穂先が右前の
    # 相手を通る）。穂先は頭の横へ上げて左後ろへ回し込み、踏み込んだ低い構えのまま水平に残す（決めの姿勢 REAR。次の B はここから）。
    S.append(dict(name='h027_sweep', state='attack', frames=26, loop=False, base=TRAIL, rootXZ=1,
                  events=dict(impact=10), melee=True, prime=('meshy_h027_sweep', [(0, 0), (10, 13), (25, 60)], 0.15),
                  keys=[(0, {}),
                        (4, dict(hyaw=-24, tyaw=-40, tpitch=8, hy=-0.06, ox=0.25, oy=1.0, oz=0.12, syaw=-150, spitch=-12,
                                 lz=-0.12, llift=0.06, lfx=-0.06, lfy=1.12, lfz=-0.26, dyaw=-8)),
                        (7, dict(hyaw=-40, tyaw=-62, hy=-0.09, hz=-0.04, ox=0.26, oy=0.98, oz=0.16, syaw=-168, spitch=-8,
                                 lx=-0.16, lz=-0.3, llift=0.06)),
                        (9, dict(hyaw=-26, tyaw=-34, tpitch=12, hy=-0.15, hz=-0.12, ox=0.28, oy=0.96, oz=-0.16, syaw=-110, spitch=-4,
                                 lx=-0.22, lz=-0.44, llift=0, lyaw=10)),
                        (10, dict(hyaw=-6, tyaw=4, tpitch=18, hpitch=8, hy=-0.2, hz=-0.18, ox=0.26, oy=0.92, oz=-0.3, syaw=-25, spitch=0,
                                  rx=0.2, rz=0.24, ryaw=-36, dyaw=-4, dpitch=-10, lfx=-0.24, lfy=0.98, lfz=-0.1)),
                        (12, dict(hyaw=8, tyaw=24, hy=-0.21, ox=0.1, oy=0.98, oz=-0.34, syaw=40, spitch=6)),
                        (14, dict(hyaw=12, tyaw=30, ox=0.14, oy=1.14, oz=-0.16, syaw=70, spitch=50)),
                        (16, dict(hyaw=6, tyaw=20, tpitch=14, ox=0.2, oy=1.06, oz=-0.02, syaw=140, spitch=28, lfx=-0.22, lfy=0.98, lfz=-0.2)),
                        (19, dict(REAR)),
                        (25, dict(REAR))]))
    # 通常攻撃 B: 頭上からの振り下ろし（スキルプレビュー 24.83〜25.47 秒）。踏み込んだ構えから右足を引き寄せて伸び上がり、穂先を
    # 左後ろへ向けたまま頭の高さへ担いで上体を左へ 34° ひねり（3〜8）、打撃の直前に頭上を越えて左上 → 前 → 右下へ斜めに振り下ろす
    # （打撃 10 = 穂先が相手の胸の前を通る）。振り抜いた勢いで体ごと右へ 90° 回り、低く広い構えで穂先を足元へ下ろす（決めの姿勢 TURN）。
    S.append(dict(name='h027_overhead', state='attack', frames=26, loop=False, base=REAR, rootXZ=1,
                  events=dict(impact=10), melee=True, prime=None,
                  keys=[(0, {}),
                        (3, dict(hy=-0.1, hz=-0.1, tyaw=18, hyaw=6, tpitch=6, hpitch=3, ox=0.2, oy=1.12, oz=0.06, syaw=145, spitch=10,
                                 rx=0.16, rz=0.12, rlift=0.05, lfx=-0.16, lfy=1.15, lfz=-0.22)),
                        (6, dict(hy=-0.04, hz=-0.06, tyaw=30, hyaw=12, tpitch=-4, hpitch=0, ox=0.18, oy=1.3, oz=0.08, syaw=155, spitch=14,
                                 rx=0.14, rz=0.06, rlift=0, lz=-0.32, dpitch=-6, lfx=-0.13, lfy=1.26, lfz=-0.22)),
                        (8, dict(hy=-0.05, tyaw=34, hyaw=16, ox=0.18, oy=1.33, oz=0.08, syaw=155, spitch=14)),
                        (9, dict(hy=-0.1, tyaw=10, hyaw=4, ox=0.2, oy=1.28, oz=-0.16, syaw=70, spitch=10, tpitch=2)),
                        (10, dict(hy=-0.14, hz=-0.08, tyaw=-14, hyaw=-10, tpitch=10, hpitch=4, ox=0.25, oy=1.15, oz=-0.28, syaw=6,
                                  spitch=-6, lz=-0.32, rz=0.12, lfx=-0.24, lfy=1.05, lfz=0.06, dpitch=-4)),
                        (11, dict(ox=0.313, oy=1.066, oz=-0.3)),
                        (12, dict(hy=-0.17, tyaw=-50, hyaw=-40, ox=0.21, oy=1.0, oz=-0.3, syaw=-70, spitch=-28, dyaw=-36)),
                        (14, dict(hy=-0.18, tyaw=-80, hyaw=-66, ox=0.3, oy=0.9, oz=0.14, syaw=-150, spitch=-26, dyaw=-58,
                                  lfx=-0.04, lfy=1.06, lfz=-0.36, rz=0.2, ryaw=-70, lyaw=-20)),
                        (15, dict(ox=0.298, oy=0.876, oz=0.131)),
                        (16, dict(ox=0.028, oy=0.859, oz=0.215)),
                        (17, dict(TURN)),
                        (25, dict(TURN))]))
    # パッシブ 竜の三連突き（スキルプレビュー 26.27〜27.30 秒、打撃 796・800・804 = 4 コマおき）: 構えから 1 発目は前への突き
    # （打撃 10 = sim の 1 発目の命中）、体を左へ回しながら穂先を左から後ろへ回し、後ろへ向けた槍の石突で 2 発目（14）、穂先を右から
    # 前へ回して体を戻し 3 発目の突き（18）。最後は穂先を右から後ろの足元へ流して引きずる持ち方へ戻る（MLBB 806〜817 コマ）。
    # 打撃の後は等速で再生する（HeroAnimator の専用クリップの経路）。
    S.append(dict(name='h027_flurry', state='attack', frames=34, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=10), melee=True, prime=('meshy_h027_thrust', [(0, 0), (10, 12), (33, 70)], 0.15),
                  keys=[(0, {}),
                        (5, dict(hz=0.04, hy=-0.08, hyaw=-46, tyaw=-66, tpitch=3, ox=0.2, oy=0.97, oz=0.10, syaw=11, spitch=8,
                                 ld=0.28, dyaw=-6, lz=-0.17, llift=0)),
                        (7, dict(lz=-0.25, llift=0.05)),
                        (9, dict(hz=-0.08, hy=-0.11, hyaw=-24, tyaw=-36, tpitch=9, ox=0.16, oy=1.01, oz=-0.18, syaw=7, spitch=5,
                                 ld=0.22, lz=-0.35, llift=0)),
                        (10, dict(hz=-0.16, hy=-0.13, hyaw=-18, tyaw=-30, tpitch=14, ox=0.14, oy=1.02, oz=-0.32, syaw=7, spitch=4,
                                  ld=0.19, lz=-0.35, dyaw=-4, dpitch=-5, lgrip=1)),
                        (11, dict(lgrip=0, lfx=-0.2, lfy=1.12, lfz=-0.2)),
                        (12, dict(hz=-0.12, hyaw=22, tyaw=46, tpitch=8, ox=0.06, oy=1.06, oz=-0.36, syaw=120, spitch=4, dyaw=-30)),
                        (13, dict(ox=0.246, oy=1.05, oz=-0.29)),
                        (14, dict(hz=-0.15, hy=-0.14, hyaw=40, tyaw=70, tpitch=10, ox=0.2, oy=1.04, oz=-0.28, syaw=175, spitch=2,
                                  dyaw=-52)),
                        (16, dict(hz=-0.14, hyaw=10, tyaw=20, tpitch=10, ox=0.22, oy=1.06, oz=-0.34, syaw=270, spitch=3, dyaw=-14)),
                        (17, dict(ox=0.226, oy=1.051, oz=-0.3)),
                        (18, dict(hz=-0.2, hy=-0.14, hyaw=-12, tyaw=-22, tpitch=18, ox=0.17, oy=1.04, oz=-0.37, syaw=365, spitch=3,
                                  dyaw=-2, dpitch=-6)),
                        (21, dict(hz=-0.18, hyaw=-13, tyaw=-23, tpitch=16, ox=0.16, oy=1.035, oz=-0.32, syaw=360)),
                        (23, dict(ox=0.247, oy=1.008, oz=-0.2)),
                        (24, dict(ox=0.24, oy=1.0, oz=-0.36, syaw=290, spitch=-16, hz=-0.1, tyaw=-20)),
                        (27, dict(hz=-0.05, hy=-0.07, hyaw=-10, tyaw=-14, tpitch=8, ox=0.25, oy=1.0, oz=-0.12, syaw=235,
                                  spitch=-24, lz=-0.24, llift=0.03, lfx=-0.14, lfy=1.14, lfz=-0.22)),
                        (30, dict(lz=-0.2, llift=0)),
                        (33, dict(TRAIL, hy=-0.05, hz=-0.03, lz=-0.18, rz=0.06, syaw=210))]))
    # スキル1 跳槍撃（詠唱のクリップ: 呼び出しの castLead 0.12 秒後が打撃 = 引っ掛けた瞬間。スキルプレビュー 51.53〜52.27 秒）:
    # 踏み込んで穂先を前へ水平に突き出して対象を引っ掛け（4）、相手へ半身になって両手で穂先を前上へ担ぎ上げたまま保つ（4〜14 = sim の
    # 持ち上げ 0.4 秒。MLBB の訓練場 461〜469・プレビュー 1550〜1558 コマ）、背を大きく反らして両腕を頭上へ伸ばし、穂先で頭上を越える
    # 大きな弧を描いて背後の足元まで振り抜く（14〜22 = sim の放り投げ 0.2 秒、訓練場 471〜475 の弧）。振り抜いた勢いで腰を落とし体を
    # 背後の方へ 30° 回した決めで一瞬止まり（22〜25、訓練場 477）、引きずる持ち方へ戻る。
    S.append(dict(name='h027_flip', state='cast', frames=40, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=4), melee=True, prime=('meshy_h027_flip', [(0, 15), (4, 21), (16, 33), (22, 47), (39, 72)], 0.2),
                  keys=[(0, {}),
                        (2, dict(hy=-0.12, tpitch=16, hyaw=-26, tyaw=-36, ox=0.18, oy=0.96, oz=-0.14, syaw=10, spitch=-12, ld=0.12,
                                 shL=10, shR=4, lz=-0.24, llift=0.03, dpitch=6)),
                        (4, dict(hy=-0.11, tpitch=12, hyaw=-20, tyaw=-28, ox=0.16, oy=1.02, oz=-0.30, syaw=8, spitch=0, ld=0.12, shL=8,
                                 shR=2, lz=-0.3, llift=0, hz=-0.06)),
                        (6, dict(lz=-0.38, llift=0.06, hyaw=-34, tyaw=-50, ld=0.26)),
                        (8, dict(hy=-0.13, hz=-0.12, tpitch=6, hpitch=3, hyaw=-48, tyaw=-66, ox=0.16, oy=1.2, oz=-0.3, syaw=8, spitch=26,
                                 ld=0.3, shL=10, shR=6, dpitch=-10, dyaw=36, lz=-0.44, llift=0, lx=-0.16, rz=0.18, rx=0.2)),
                        (12, dict(hy=-0.12, hz=-0.11, hyaw=-48, tyaw=-66, ox=0.16, oy=1.22, oz=-0.3, syaw=8, spitch=28, ld=0.3,
                                  dyaw=36, lz=-0.44, rz=0.18)),
                        (14, dict(hy=-0.1, hz=-0.08, tpitch=0, hyaw=-36, tyaw=-50, ox=0.15, oy=1.28, oz=-0.26, syaw=8, spitch=42,
                                  ld=0.28, shL=6, dpitch=-14, dyaw=26, lz=-0.38, rz=0.16)),
                        (16, dict(hy=-0.08, hz=-0.04, tpitch=-14, hpitch=-4, hyaw=-24, tyaw=-32, ox=0.15, oy=1.42, oz=-0.12, syaw=8,
                                  spitch=72, ld=0.24, shL=12, shR=10, dpitch=-24, dyaw=14, lz=-0.36)),
                        (17, dict(ox=0.123, oy=1.485, oz=-0.109)),
                        (18, dict(hy=-0.1, hz=-0.02, tpitch=-28, hpitch=-8, hyaw=-14, tyaw=-18, ox=0.16, oy=1.52, oz=0.02, syaw=8,
                                  spitch=112, ld=0.2, shL=14, shR=12, dpitch=-30, dyaw=6, lz=-0.32)),
                        (20, dict(hy=-0.1, hz=0.02, tpitch=-18, hpitch=-4, hyaw=0, tyaw=-4, ox=0.2, oy=1.4, oz=0.14, syaw=10,
                                  spitch=160, ld=0.16, shL=6, shR=6, dpitch=-16, dyaw=0, lgrip=0.5, rz=0.24, lz=-0.3)),
                        (22, dict(hy=-0.15, hz=0.06, tpitch=8, hpitch=6, hyaw=20, tyaw=30, ox=0.24, oy=1.12, oz=0.16, syaw=24,
                                  spitch=205, ld=0.14, shL=0, shR=0, dpitch=-4, dyaw=20, lgrip=0, lfx=-0.22, lfy=1.08, lfz=-0.16,
                                  lz=-0.3, rz=0.32, rx=0.24)),
                        (25, dict(hy=-0.17, hz=0.06, tpitch=10, hyaw=20, tyaw=30, ox=0.24, oy=1.08, oz=0.17, syaw=26, spitch=210,
                                  dyaw=20, lfx=-0.22, lfy=1.06, lfz=-0.16, lz=-0.3, rz=0.32)),
                        (31, dict(TRAIL, hy=-0.06, syaw=30, spitch=218, lz=-0.22, rz=0.06)),
                        (39, dict(TRAIL, syaw=30, spitch=218, lz=-0.16, rz=0.04))]))
    # スキル2 竜牙突き: 突進の間の姿勢（詠唱のクリップ、脚もクリップのまま = 突進中に足を回さない）。MLBB（訓練場 128〜135・プレビュー
    # 1390〜1394）: 槍を腰へ引いて沈み（2）、地面を蹴って宙へ跳び（4）、体をほぼ水平にして槍を先に突き出したまま飛ぶ（4〜13: 腰を
    # 0.32 m 上げ、右脚は後ろへ伸ばし、左脚は膝を畳む。マントは後ろへ流れる）。到着（sim の命中）で h027_strike_hit が着地して突き切る。
    S.append(dict(name='h027_strike', state='cast', frames=14, loop=False, base=GUARD, rootXZ=0,
                  events=dict(impact=4), melee=False, prime=None,
                  keys=[(0, {}),
                        (2, dict(hy=-0.17, hz=0.04, tpitch=24, hpitch=14, hyaw=-26, tyaw=-40, ox=0.2, oy=0.92, oz=0.08, syaw=6, spitch=-4,
                                 ld=0.3, lz=-0.24, rz=0.2, dpitch=-10)),
                        (4, dict(hy=0.2, hz=-0.08, tpitch=58, hpitch=40, hyaw=-10, tyaw=-12, ox=0.14, oy=1.16, oz=-0.6, syaw=4, spitch=2,
                                 lgrip=0, lfx=-0.26, lfy=1.16, lfz=-0.14, lz=-0.2, llift=0.3, lroll=-20, rz=0.42, rlift=0.42, rroll=40,
                                 dpitch=24)),
                        (8, dict(hy=0.32, hz=-0.1, tpitch=64, hpitch=44, ox=0.14, oy=1.26, oz=-0.66, lfy=1.24, lfz=-0.2, syaw=4, spitch=2, lz=-0.16, llift=0.46,
                                 lroll=-26, rz=0.48, rlift=0.56, rroll=46, dpitch=28)),
                        (13, dict(hy=0.3, hz=-0.1, tpitch=64, hpitch=44, ox=0.14, oy=1.24, oz=-0.66, lfy=1.22, lfz=-0.2, syaw=4, spitch=2, lz=-0.17, llift=0.44,
                                  lroll=-26, rz=0.48, rlift=0.54, rroll=46, dpitch=28))]))
    # スキル2 の到着: 宙の飛び込みの姿勢から着地して（2）体を起こしながら突き切り（打撃 3 = 命中の直後。MLBB 1395〜1398）、穂先を右から
    # 後ろの足元へ回して引きずる持ち方へ戻る（MLBB 1401〜1405 と同じ右回り。石突が 1.21 m と長いので、回す間は握りを右肩の後ろ上
    # へ引いて石突を胸の前の高い所に通す。sim はそのまま通常攻撃へ移る）。
    S.append(dict(name='h027_strike_hit', state='cast', frames=22, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=3), melee=True, prime=None,
                  keys=[(0, dict(hy=0.3, hz=-0.1, tpitch=64, hpitch=44, hyaw=-10, tyaw=-12, ox=0.14, oy=1.24, oz=-0.66, syaw=4, spitch=2,
                                 lgrip=0, lfx=-0.26, lfy=1.22, lfz=-0.2, lz=-0.17, llift=0.44, lroll=-26, rz=0.48, rlift=0.54, rroll=46,
                                 dpitch=28)),
                        (2, dict(hy=-0.06, hz=-0.14, tpitch=34, hpitch=18, ox=0.14, oy=1.0, oz=-0.46, lz=-0.34, llift=0.04, lroll=0,
                                 rz=0.34, rlift=0.08, rroll=10, dpitch=4)),
                        (3, dict(hz=-0.16, hy=-0.12, tpitch=18, hpitch=8, hyaw=-12, tyaw=-18, ox=0.15, oy=1.03, oz=-0.38, syaw=8,
                                 spitch=2, lz=-0.35, llift=0, lroll=0, rz=0.26, rlift=0, rroll=0, dpitch=-8, lfx=-0.24, lfy=1.04, lfz=0.0)),
                        (7, dict(hz=-0.12, hy=-0.09, tpitch=8, hpitch=3, ox=0.16, oy=1.06, oz=-0.3)),
                        (10, dict(ox=0.32, oy=1.0, oz=-0.1, syaw=-30, spitch=-5, tyaw=-14, hyaw=-8)),
                        (12, dict(ox=0.32, oy=1.0, oz=0.12, syaw=-60, spitch=-20)),
                        (14, dict(hz=-0.08, hy=-0.08, tpitch=8, hpitch=3, ox=0.28, oy=1.1, oz=0.22, syaw=-90, spitch=-25,
                                  lz=-0.26, rz=0.14, lfx=-0.14, lfy=1.14, lfz=-0.2)),
                        (16, dict(ox=0.32, oy=1.22, oz=0.22, syaw=-115, spitch=-33)),
                        (18, dict(ox=0.32, oy=1.25, oz=0.22, syaw=-135, spitch=-35)),
                        (20, dict(ox=0.3, oy=1.2, oz=0.2, syaw=-148, spitch=-33)),
                        (21, dict(TRAIL, hy=-0.05, hz=-0.04, lz=-0.22, rz=0.08))]))
    # アルティメット 至高の武人: MLBB は Project NEXT の改修で発動時の動作を外した（ONE Esports「Layla and Zilong are up next for
    # reworks」: removed the idle animation when triggered）。スキルプレビュー 31.73〜31.93 秒も発動の光の中で直立のまま。引きずる持ち方
    # のまま胸を小さく張って左の拳を握るだけ（14 フレーム、打撃 4 = 発動の光）。移動中は上半身だけ（走りを止めない）。
    S.append(dict(name='h027_warrior', state='cast', frames=14, loop=False, base=TRAIL, rootXZ=1,
                  events=dict(impact=4), melee=False, prime=None,
                  keys=[(0, {}),
                        (4, dict(hy=-0.04, tpitch=2, dpitch=-10, lfx=-0.07, lfy=1.15, lfz=-0.21, lflex=1)),
                        (8, dict(hy=-0.04, tpitch=3, dpitch=-9, lfx=-0.07, lfy=1.15, lfz=-0.22, lflex=1)),
                        (13, {})]))
    return S


# MARK: - Solve

class H027Rig:
    def __init__(self, rig):
        self.rig = rig
        ix, P0 = rig.index, rig.P0
        self.grip = {s: 0.6 * (P0[ix[s + 'handindex1']] - P0[ix[s + 'hand']]).length for s in ('left', 'right')}
        self.upper = (P0[ix['rightforearm']] - P0[ix['rightarm']]).length
        self.fore = (P0[ix['righthand']] - P0[ix['rightforearm']]).length


def hand_frame(a, s):
    """Canonical hand frame (fingers -Y, thumb -Z, both hands) for long axis a and shaft s -> hero quaternion."""
    a = (a - s * a.dot(s))
    if a.length < 1e-4:
        a = V((0, -1, 0)) - s * s.y
    a.normalize()
    y = -a
    z = -s
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed()
    return m.to_quaternion().normalized()


def arm_frame(u, n):
    """Canonical limb frame: -Y along u, +X = elbow hinge n."""
    y = -u.normalized()
    x = (n - y * n.dot(y)).normalized()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed().to_quaternion().normalized()


def twist_about(q, axis):
    """Swing-twist: twist part of q about axis (unit)."""
    v = V((q.x, q.y, q.z))
    p = axis * v.dot(axis)
    t = Quaternion((q.w, p.x, p.y, p.z))
    if t.magnitude < 1e-8:
        return Quaternion()
    return t.normalized()


def solve_arm(hr, qs, offset, details, side, fist, s, pole, free_axis=None, grip_w=1.0):
    """Place the fist center at `fist`; the shaft (thumb side) along s, or a relaxed hand when s is None."""
    rig = hr.rig
    suf = 'R' if side == 'right' else 'L'
    ia, ie, ih = (rig.index[side + r] for r in ('arm', 'forearm', 'hand'))
    _, P = h25.solve(rig, qs, offset, details)
    shoulder = P[ia]
    l1, l2 = (rig.P0[ie] - rig.P0[ia]).length, (rig.P0[ih] - rig.P0[ie]).length
    hand_q = None
    wrist = fist.copy()
    err = 0.0
    for _ in range(4):
        toward = wrist - shoulder
        dist = min(l1 + l2 - 0.002, max(abs(l1 - l2) + 0.002, toward.length))
        err = max(0.0, toward.length - dist)
        d = toward.normalized()
        bend = pole - d * d.dot(pole)
        if bend.length < 1e-3:
            bend = V((0, -1, 0)) - d * d.y
        bend.normalize()
        along = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
        elbow = shoulder + d * along + bend * math.sqrt(max(0.0, l1 * l1 - along * along))
        end = shoulder + d * dist
        u, f = elbow - shoulder, end - elbow
        n = u.cross(f)
        if n.length < 1e-5:
            n = bend.cross(d)
        n.normalize()
        relaxed = arm_frame(f, n) @ Quaternion((1, 0, 0), rad(free_axis or 8))
        if s is not None and grip_w > 0:
            hand_q = cm.slerp(relaxed, hand_frame(f.normalized(), s), grip_w)
        else:
            # relaxed: hand continues the forearm with a slight flexion
            hand_q = relaxed
        wrist = fist - hand_q @ V((0, -hr.grip[side], 0))
    q_arm = arm_frame(u, n)
    q_fore_hinge = arm_frame(f, n)
    # split the hand's twist about the forearm: 55 % on the forearm, the rest stays in the wrist
    rel = q_fore_hinge.inverted() @ hand_q
    tw = twist_about(rel, V((0, -1, 0)))
    q_fore = q_fore_hinge @ cm.slerp(Quaternion(), tw, 0.55)
    qs[cm.SEG_INDEX['arm' + suf]] = q_arm
    qs[cm.SEG_INDEX['foreArm' + suf]] = q_fore.normalized()
    qs[cm.SEG_INDEX['hand' + suf]] = hand_q
    return err


def solve_leg(rig, qs, offset, details, side, target, pole):
    suf = 'R' if side == 'right' else 'L'
    return h25.ik(rig, qs, offset, details, [side + 'upleg', side + 'leg', side + 'foot'], ['thigh' + suf, 'shin' + suf], target, pole)


def body_rot(yaw, pitch, roll):
    # yaw about Y, then pitch forward (+ = lean forward, about -X... forward lean tips the up axis toward -Z), roll
    return (ry(yaw) @ Quaternion((1, 0, 0), -rad(pitch)) @ rz(roll)).normalized()


def prime_delta(sources, prime, frame, frames, loop):
    """Hips/torso/head deltas and hips height delta from the prime clip, relative to its first sampled frame."""
    if not prime:
        return None
    name, warp, gain = prime
    src = sources[name]
    n = src['frames']
    if warp is None:
        # loops: one cycle picked by the caller via frame fraction over the middle of the take
        f0 = n * 0.3
        sf = f0 + (frame / frames) * (n * 0.4)
        ref = f0
    else:
        xs = [w[0] for w in warp]
        ys = [w[1] for w in warp]
        sf = ys[-1]
        for (a, x), (b, y) in zip(warp, warp[1:]):
            if frame <= b:
                sf = x + (y - x) * (frame - a) / max(1e-6, b - a)
                break
        ref = ys[0]
    q, root = cm.interp_clip(src, sf)
    q0, root0 = cm.interp_clip(src, ref)
    out = []
    for i in range(3):
        d = (q[i] @ q0[i].inverted()).normalized()
        # express in the hero's frame: remove the prime's own heading at the reference
        fwd = q0[1] @ V((0, 0, -1))
        heading = math.degrees(math.atan2(-fwd.x, -fwd.z))
        A = ry(-heading)
        d = A @ d @ A.inverted()
        limit = rad((6, 9, 8)[i])
        w = gain
        if d.angle * w > limit:
            w = limit / max(1e-6, d.angle)
        out.append(cm.slerp(Quaternion(), d, w))
    # clips must close (loop seam / attack start = end = guard): fade the texture to identity at both ends
    e = math.sin(math.pi * frame / frames) ** 2 if loop else math.sin(math.pi * frame / max(1, frames - 1)) ** 2
    out = [cm.slerp(Quaternion(), d, e) for d in out]
    dy = (root.y - root0.y) * gain * e
    return out, dy


def make_pose(hr, sources, spec, frame, details_only=False):
    rig = hr.rig
    loop = spec['loop']
    frames = spec['frames']
    period = frames
    base = spec['base']
    ch = {k: track_value(keys_of(spec, k, base), frame, loop, period) for k in base}
    state = spec['state']
    t = frame / frames if loop else frame / max(1, frames - 1)
    qs = [Quaternion() for _ in range(15)]
    details = {r: Quaternion() for r in DETAILS if r in rig.index}

    # gait (walk/run): bounce and stride phases
    move = state in ('walk', 'run')
    phase = t % 1.0
    offset = V((ch['hx'], ch['hy'], ch['hz']))
    if move:
        offset.y = spec['hipsDrop'] - spec['bounce'] * (0.5 - 0.5 * math.cos(phase * math.tau * 2 - 0.6))
    pd = prime_delta(sources, spec.get('prime'), frame, frames, loop)
    hips_q = body_rot(ch['hyaw'], ch['hpitch'], ch['hroll'])
    torso_q = body_rot(ch['tyaw'], ch['tpitch'], ch['troll'])
    head_q = body_rot(ch['dyaw'], ch['dpitch'], ch['droll'])
    if move:
        swing = math.sin(phase * math.tau)
        hips_q = ry(-7 * swing) @ hips_q
        torso_q = ry(5 * swing) @ torso_q
        head_q = ry(-2 * swing) @ head_q
    if pd:
        (dh, dt, dd), dy = pd
        hips_q, torso_q, head_q = dh @ hips_q, dt @ torso_q, dd @ head_q
        if not move:
            offset.y += dy * rig.leg_length
    qs[0], qs[1], qs[2] = hips_q, torso_q, head_q
    # breathing on the torso and shoulders (idle/walk)
    breath = math.sin(t * math.tau * (2 if state == 'idle' else 1))
    if state == 'idle':
        qs[1] = Quaternion((1, 0, 0), rad(-0.9 * breath)) @ qs[1]
        offset.y += 0.0025 * breath

    # feet
    errors = []
    for side, sgn in (('left', -1), ('right', 1)):
        p = 'l' if side == 'left' else 'r'
        j = rig.index[side + 'foot']
        target = rig.P0[j].copy()
        target.x = ch[p + 'x']
        target.z = ch[p + 'z']
        target.y += ch[p + 'lift']
        roll = ch[p + 'roll']
        yaw = ch[p + 'yaw']
        if move:
            c = spec['contact']
            dur = frames / FPS
            reach = spec['groundSpeed'] * dur * c / 2
            u = (phase + (0.0 if side == 'right' else 0.5)) % 1.0
            if u < c:
                v = u / c
                target.z += -reach + 2 * reach * v
                roll = 18 * h25.smooth((v - 0.78) / 0.22)
            elif spec.get('heel'):
                # MLBB の走り（訓練場 75〜92 コマ）: 蹴り出した足のかかとを尻の方へ高く上げ（後ろへ少し流れる）、膝を前へ送って
                # 足を前へ伸ばし、少し引きながら着地する（着地の直前に足が後ろへ動くので、支持の始まりと速度がつながる）
                v = (u - c) / (1 - c)
                kick, heel, knee, over = spec['kick'], spec['heel'], spec['knee'], spec['over']
                target.z += catmull(v, [(0, reach), (0.22, reach + kick), (0.5, 0.0), (0.8, -reach - over), (1.0, -reach)])
                target.y += max(0.0, catmull(v, [(0, 0.0), (0.28, heel), (0.52, knee), (0.8, 0.09), (1.0, 0.0)]))
                roll = 24 * (1 - h25.smooth(v / 0.4)) - 10 * math.sin(math.pi * v)
            else:
                v = (u - c) / (1 - c)
                tangent = 2 * reach * (1 - c) / c
                target.z += reach - 2 * reach * h25.smooth(v) + tangent * (2 * v**3 - 3 * v * v + v)
                target.y += spec['lift'] * math.sin(math.pi * v) ** 2
                roll = 18 * (1 - h25.smooth(v)) - 12 * math.sin(math.pi * v)
            if roll > 0:
                target.y += 0.06 * math.sin(rad(roll))
        details[side + 'toebase'] = h25.local_delta(rig, side + 'toebase', rx(-roll * 0.7)) if side + 'toebase' in rig.index else None
        qs[cm.SEG_INDEX['foot' + ('L' if side == 'left' else 'R')]] = (ry(yaw) @ rx(roll) @ rig.seg_C('foot' + ('L' if side == 'left' else 'R')).inverted()).normalized()
        pole = ry(yaw) @ V((0.12 * sgn, 0, -1))
        errors.append(solve_leg(rig, qs, offset, details, side, target, pole))
    details = {k: v for k, v in details.items() if v is not None}

    # spear: grip point + shaft direction. Walk/run bob with the hips; torso twist follows slightly.
    s = spear_dir(ch['syaw'], ch['spitch'])
    O = V((ch['ox'], ch['oy'], ch['oz']))
    if move:
        O.y += offset.y - spec['hipsDrop']
    # shoulders reach toward the fists when extended (clavicle protraction), before the arm IK
    for side in ('left', 'right'):
        amt = ch['shR' if side == 'right' else 'shL']
        if side + 'shoulder' in rig.index:
            sgn = 1 if side == 'right' else -1
            details[side + 'shoulder'] = h25.local_delta(rig, side + 'shoulder', ry(sgn * amt) @ rz(sgn * 0.3 * amt))
    # auto protraction: as the right fist goes forward of the chest
    fwd_reach = max(0.0, -(O.z) - 0.05)
    for side, sgn in (('right', 1), ('left', -1)):
        if side + 'shoulder' in rig.index:
            extra = min(14.0, fwd_reach * 45)
            details[side + 'shoulder'] = details[side + 'shoulder'] @ h25.local_delta(rig, side + 'shoulder', ry(sgn * extra))
    errors.append(solve_arm(hr, qs, offset, details, 'right', O, s, V((ch['rpx'], ch['rpy'], ch['rpz']))))
    shaft = O + s * ch['ld']
    free = V((ch['lfx'], ch['lfy'], ch['lfz']))
    if move:
        swing = math.sin(phase * math.tau)
        free += V((0, 0.012 * abs(swing), 0.11 * swing if state == 'walk' else spec.get('armSwing', 0.16) * swing))
        free.y += offset.y - spec['hipsDrop']
    w = ch['lgrip']
    left_target = free.lerp(shaft, w)
    left_err = solve_arm(hr, qs, offset, details, 'left', left_target, s, V((ch['lpx'], ch['lpy'], ch['lpz'])),
                         free_axis=10 + 20 * ch['lcurl'], grip_w=h25.smooth(w))
    errors.append(left_err)

    # fingers: fists on the shaft; the free hand relaxes / regrips
    for side, sgn in (('left', -1), ('right', 1)):
        curl = ch['rcurl'] if side == 'right' else ch['lcurl']
        if side == 'left':
            free_curl = 0.45 + 0.5 * ch['lflex']
            curl = free_curl + (curl - free_curl) * h25.smooth(w)
        for finger in ('thumb', 'index', 'middle', 'ring', 'pinky'):
            for n in (1, 2, 3):
                role = side + 'hand' + finger + str(n)
                if role not in rig.index:
                    continue
                if finger == 'thumb':
                    deg = [18, 30, 24][n - 1] * curl
                    q = Quaternion(V((0, 0.35, -sgn)).normalized(), rad(deg)) if False else Quaternion(V((0.25 * sgn, 0, -sgn)).normalized(), rad(deg))
                else:
                    spread = {'index': 0, 'middle': 4, 'ring': 8, 'pinky': 14}[finger]
                    deg = ([62, 86, 58][n - 1] + (spread if n == 1 else 0)) * curl
                    q = Quaternion(V((0, 0, -sgn)), rad(deg))
                details[role] = h25.local_delta(rig, role, q)
    root = offset / rig.leg_length
    return qs, root, details, max(errors), dict(O=O, s=s, offset=offset, errs=[round(e * 1000) for e in errors])


# MARK: - Checks

def seg_dist(p1, q1, p2, q2):
    """Closest distance between segments p1q1 and p2q2."""
    d1, d2, r = q1 - p1, q2 - p2, p1 - p2
    a, e, f = d1.dot(d1), d2.dot(d2), d2.dot(r)
    if a <= 1e-9 and e <= 1e-9:
        return r.length
    if a <= 1e-9:
        s, t = 0.0, max(0.0, min(1.0, f / e))
    else:
        c = d1.dot(r)
        if e <= 1e-9:
            t, s = 0.0, max(0.0, min(1.0, -c / a))
        else:
            b = d1.dot(d2)
            den = a * e - b * b
            s = max(0.0, min(1.0, (b * f - c * e) / den)) if den > 1e-9 else 0.0
            t = (b * s + f) / e
            if t < 0:
                t, s = 0.0, max(0.0, min(1.0, -c / a))
            elif t > 1:
                t, s = 1.0, max(0.0, min(1.0, (b - c) / a))
    return ((p1 + d1 * s) - (p2 + d2 * t)).length


def spear_points(rig, hr, qs, P, grip):
    hand = P[rig.index['righthand']]
    q = qs[5] @ grip
    O = hand + qs[5] @ V((0, -hr.grip['right'], 0))
    ax = q @ V((0, 1, 0))
    return O, O + ax * SPEAR_BUTT, O + ax * SPEAR_TIP, q


def spear_origin(O, q):
    """Prop origin (weapon space 0) for the grip point O: the runtime's weaponOffset (0, -GRIP_SHIFT, 0)."""
    return O + q @ V((0, -GRIP_SHIFT, 0))


def clearance(rig, hr, qs, offset, details, grip):
    _, P = h25.solve(rig, qs, offset, details)
    O, butt, tip, q = spear_points(rig, hr, qs, P, grip)
    ix = rig.index
    # skip the part of the shaft inside the fists (0.08 m around each grip)
    ax = (tip - butt).normalized()
    lo, hi = O + ax * 0.10, tip
    rear = O - ax * 0.08
    res = {}
    res['ground'] = min(butt.y, tip.y) - SHAFT_R
    limbs = {'thighL': ('leftupleg', 'leftleg', 0.085), 'shinL': ('leftleg', 'leftfoot', 0.06),
             'thighR': ('rightupleg', 'rightleg', 0.085), 'shinR': ('rightleg', 'rightfoot', 0.06)}
    worst = 9.0
    for k, (a, b, r) in limbs.items():
        dd = min(seg_dist(butt, rear, P[ix[a]], P[ix[b]]), seg_dist(lo, hi, P[ix[a]], P[ix[b]])) - r - SHAFT_R
        res[k] = round(dd, 4)
        worst = min(worst, dd)
    # cape: a slab behind the back from the neck to the knees
    neck, hips = P[ix['neck']], P[ix['hips']]
    back = (qs[1] @ V((0, 0, 1)))
    capeTop, capeBot = neck + back * 0.12, (P[ix['leftleg']] + P[ix['rightleg']]) * 0.5 + back * 0.2
    res['cape'] = round(min(seg_dist(butt, rear, capeTop, capeBot), seg_dist(lo, hi, capeTop, capeBot)) - 0.14 - SHAFT_R, 4)
    torso = min(seg_dist(butt, rear, hips, neck), seg_dist(lo, hi, hips, neck)) - 0.13 - SHAFT_R
    res['torso'] = round(torso, 4)
    res['legs'] = round(worst, 4)
    face = q @ V((0, 0, 1))
    return res, dict(O=O, butt=butt, tip=tip, face=face, P=P)


# MARK: - Export

def solve_grip_roll(hr, sources):
    """Roll so the blade face points up (+Y) in the guard: weapon +Z = q.handR * grip * Z."""
    spec = dict(name='g', state='attack', frames=2, loop=False, base=GUARD, keys=[])
    qs, root, details, err, info = make_pose(hr, sources, spec, 0)
    qh = qs[5]
    s = info['s']
    up = V((0, 1, 0))
    want = (up - s * up.dot(s)).normalized()
    best, best_dot = 0.0, -2
    for i in range(720):
        roll = -math.pi + i * math.pi / 360
        z = qh @ grip_quat(roll) @ V((0, 0, 1))
        if z.dot(want) > best_dot:
            best, best_dot = roll, z.dot(want)
    return best


def author(hr, sources, only=None):
    clips, report = [], {}
    grip = grip_quat(GRIP_ROLL)
    rig = hr.rig
    for spec in clip_specs():
        if only and spec['name'] not in only:
            continue
        frames, loop = spec['frames'], spec['loop']
        c = dict(name=spec['name'], source='', frames=frames, loop=loop, rootXZ=spec.get('rootXZ', 0),
                 events=spec.get('events', {}), rot=[], root=[], detailJoints=[r for r in DETAILS if r in rig.index], detailRot=[])
        prime = spec.get('prime')
        task = sources.get('_tasks', {}).get(prime[0]) if prime else None
        c['source'] = (f"meshy:prime:{task or prime[0]}" if prime else 'local') + '+local:H027-spear-finish'
        if spec.get('melee'):
            c['melee'] = True
        if spec.get('groundSpeed'):
            c['groundSpeed'] = round(spec['groundSpeed'] * BP_SCALE, 4)
        prev, pd = [None] * 15, [None] * len(c['detailJoints'])
        errs, worst = [], {}
        faces = []
        for f in range(frames):
            qs, root, details, err, info = make_pose(hr, sources, spec, f)
            for i, q in enumerate(qs):
                vals, prev[i] = h25.pack(q, prev[i])
                c['rot'] += vals
            c['root'] += [round(x, 6) for x in root]
            for i, role in enumerate(c['detailJoints']):
                vals, pd[i] = h25.pack(details.get(role, Quaternion()), pd[i])
                c['detailRot'] += vals
            errs.append(err)
            cl, geo = clearance(rig, hr, qs, root * rig.leg_length, details, grip)
            for k, v in cl.items():
                if k not in worst or v < worst[k][0]:
                    worst[k] = (round(v, 4), f)
            faces.append(round(geo['face'].y, 3))
        clips.append(c)
        a = make_pose(hr, sources, spec, 0)[0]
        b = make_pose(hr, sources, spec, frames if loop else frames - 1)[0]
        report[spec['name']] = dict(frames=frames, maxTargetClampMm=round(max(errs) * 1000, 2),
                                    seamDegrees=round(max(cm.quat_angle_deg(x, y) for x, y in zip(a, b)), 3),
                                    clearanceMin=worst, bladeFaceUpMin=min(faces))
    return clips, report


def load_sources():
    sources = preview.load_clips('tools/motion/h027-prime-source-clips.json')
    sources.update(preview.load_clips('tools/motion/h027-source-clips.json'))
    try:
        state = json.load(open(OUT / 'api-state.json'))
        sources['_tasks'] = {f"meshy_h027_{k[5:-6]}": v.get('task_id') for k, v in state['tasks'].items() if k.endswith('_prime')}
    except OSError:
        sources['_tasks'] = {}
    return sources


def setup_rig():
    rig, meshes, height, warnings = preview.load_hero(str(Path(HERO).resolve()))
    axis_error = h25.bind_usd_axes(rig, HERO)
    return H027Rig(rig), meshes, height, warnings, axis_error


def main():
    global GRIP_ROLL
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', default='App/Resources/Heroes/H027MotionClips.json')
    parser.add_argument('--only', default='')
    parser.add_argument('--preview', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    hr, meshes, height, warnings, axis_error = setup_rig()
    sources = load_sources()
    GRIP_ROLL = solve_grip_roll(hr, sources)
    only = set(x for x in args.only.split(',') if x)
    clips, report = author(hr, sources, only)
    out = Path(args.out)
    if only and out.is_file():
        existing = {c['name']: c for c in json.loads(out.read_text())['clips']}
        existing.update({c['name']: c for c in clips})
        order = [s['name'] for s in clip_specs() if s['name'] in existing]
        clips = [existing[n] for n in order]
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=clips), separators=(',', ':')) + '\n')
    g = grip_quat(GRIP_ROLL)
    report['grip'] = dict(roll=GRIP_ROLL, quaternion_xyzw=[round(g.x, 6), round(g.y, 6), round(g.z, 6), round(g.w, 6)])
    report['model'] = dict(height=height, bones=len(hr.rig.names), armReach=hr.upper + hr.fore + hr.grip['right'],
                           axisErrorDegrees=axis_error, warnings=warnings)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'finish-report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
