"""H027 竜槍のジャルド: motion finishing on the shipped (finger re-rigged) model, Blender 5.2.

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
# Dragon spear (HeroGear .dragonSpear): grip at the origin, +Y to the tip, entity scale 1.08 (weaponScale).
SPEAR_SCALE = 1.08
SPEAR_BUTT = -0.84 * SPEAR_SCALE
SPEAR_TIP = 2.04 * SPEAR_SCALE
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


# MARK: - Poses

# Guard (構え): left foot forward, torso turned right, right fist in front of the right hip, left fist 0.24 m up the shaft,
# tip aimed at chest height of a target 1.8 m ahead. Arms are short on this model (shoulder→fist 0.41 m), so the
# body (hips/torso turn, lunge) carries most of the spear travel.
GUARD = dict(hy=-0.055, hx=0.0, hz=0.0, hyaw=-30, hpitch=2, hroll=0, tyaw=-46, tpitch=4, troll=0,
             dyaw=-4, dpitch=2, droll=0,
             lx=-0.11, lz=-0.17, lyaw=6, llift=0, lroll=0, rx=0.135, rz=0.15, ryaw=-30, rlift=0, rroll=0,
             ox=0.165, oy=1.0, oz=-0.03, syaw=9, spitch=8, lgrip=1, ld=0.22, lfx=-0.2, lfy=0.98, lfz=-0.05,
             rcurl=1, lcurl=1, lflex=0, rpx=0.9, rpy=-0.4, rpz=0.5, lpx=-0.9, lpy=-0.5, lpz=0.3, shR=0, shL=0)
# Standing (待機): chest out, front/back feet, spear in the right hand leaning forward with the butt beside the right
# heel (blade high and forward reads from the top camera), free left hand relaxed at the hip.
STAND = dict(GUARD, hy=-0.02, hyaw=-10, hpitch=0, tyaw=-12, tpitch=-4, dyaw=6, dpitch=-2,
             lx=-0.115, lz=-0.09, lyaw=4, rx=0.125, rz=0.10, ryaw=-24,
             ox=0.225, oy=0.98, oz=-0.035, syaw=10, spitch=58, lgrip=0, lfx=-0.215, lfy=0.985, lfz=-0.035,
             lcurl=0.55, rpx=1, rpy=-0.2, rpz=0.35, lpx=-1, lpy=-0.2, lpz=0.25)


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
    # 待機 6 秒: 呼吸 2 回、前後の小さな重心移動、左 → 右へ見渡す、空いた左手の握り直し。槍の手と穂先は動かさない。
    S.append(dict(name='h027_idle', state='idle', frames=180, loop=True, base=STAND, rootXZ=1,
                  prime=('meshy_h027_idle', [(0, 10), (180, 110)], 0.35),
                  keys=[(0, dict(hz=0.0, dyaw=6, dpitch=-2, tyaw=-12, lflex=0)),
                        (30, dict(hz=-0.012, tyaw=-11)),
                        (55, dict(dyaw=26, dpitch=-1, tyaw=-6)),
                        (75, dict(dyaw=24, lflex=0)),
                        (84, dict(lflex=1)),
                        (96, dict(lflex=0.15)),
                        (90, dict(hz=0.010, tyaw=-12)),
                        (118, dict(dyaw=-14, dpitch=-3, tyaw=-17)),
                        (140, dict(dyaw=-12)),
                        (150, dict(hz=-0.006)),
                        (165, dict(dyaw=4, tyaw=-12, lflex=0))]))
    # 歩行 1.0 秒 = 2 歩（地面の速さ 1.15 m/s）。上体を起こし、槍は右手で前上へ立てたまま、左腕を軽く振る。
    S.append(dict(name='h027_walk', state='walk', frames=30, loop=True, base=dict(STAND, tyaw=-8, hyaw=-4, dyaw=4,
                  lz=0, rz=0, lyaw=2, ryaw=-8, ox=0.215, oz=-0.06, spitch=56, syaw=8),
                  rootXZ=0, groundSpeed=1.15, contact=0.6, hipsDrop=-0.07, bounce=0.018, lift=0.07,
                  prime=('meshy_h027_walk', None, 0.3)))
    # 走行 0.733 秒 = 2 歩（3.0 m/s）。前傾し、槍は右腰に沿わせて穂先を前へ低く寝かせる（石突は外へ逃がす）。
    S.append(dict(name='h027_run', state='run', frames=22, loop=True, base=dict(STAND, tyaw=-10, tpitch=16, hpitch=8,
                  hyaw=-4, dyaw=8, dpitch=-14, lz=0, rz=0, lyaw=0, ryaw=-6, ox=0.27, oy=0.87, oz=0.0, syaw=3, spitch=-4,
                  lcurl=0.9, rpx=1, rpy=0.1, rpz=0.6),
                  rootXZ=0, groundSpeed=3.0, contact=0.36, hipsDrop=-0.13, bounce=0.03, lift=0.13,
                  prime=('meshy_h027_run', None, 0.3)))
    # 通常攻撃 1: 突き。槍を引いて重心を後ろへ（柄は左手の中を滑る）→ 左足を踏み込み、腰 → 胸 → 肩の順に回して右手で
    # 送り出す（打撃 10）。体は半身のまま、石突は右腰の外へ逃がす → 引き戻し、足を戻して構え。
    S.append(dict(name='h027_thrust', state='attack', frames=28, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=10), melee=True, prime=('meshy_h027_thrust', [(0, 0), (10, 12), (27, 66)], 0.25),
                  keys=[(0, {}),
                        (4, dict(hz=0.05, hy=-0.07, hyaw=-40, tyaw=-58, tpitch=3, ox=0.2, oy=0.97, oz=0.10, syaw=11, spitch=8,
                                 ld=0.30, dyaw=-6, lz=-0.17, llift=0)),
                        (6, dict(lz=-0.22, llift=0.05)),
                        (8, dict(hz=-0.06, hy=-0.09, hyaw=-26, tyaw=-40, tpitch=8, ox=0.17, oy=1.0, oz=-0.12, syaw=7, spitch=5,
                                 ld=0.24, lz=-0.30, llift=0.02)),
                        (9, dict(lz=-0.33, llift=0)),
                        (10, dict(hz=-0.15, hy=-0.115, hyaw=-18, tyaw=-30, tpitch=13, ox=0.14, oy=1.03, oz=-0.30, syaw=5, spitch=3,
                                  ld=0.19, lz=-0.33, llift=0, dyaw=-4, dpitch=-5)),
                        (13, dict(hz=-0.14, hy=-0.11, hyaw=-19, tyaw=-31, tpitch=12, ox=0.145, oy=1.03, oz=-0.28, syaw=5, spitch=3,
                                  ld=0.19, lz=-0.33, llift=0)),
                        (19, dict(hz=-0.05, hy=-0.075, hyaw=-26, tyaw=-40, tpitch=6, ox=0.16, oy=1.0, oz=-0.1, syaw=8, spitch=7,
                                  ld=0.22, lz=-0.25, llift=0.03)),
                        (23, dict(lz=-0.19, llift=0)),
                        (27, {})]))
    # 通常攻撃 2: 払い。腰と胸を右へひねって穂先を右前へ引き（左手は柄を離して均衡を取る）、左足を踏み込みながら腰から左へ
    # 回して穂先を腰の高さで右 → 左へ大きく払う（打撃 10 = 穂先が正面を通る）→ 左手を柄へ戻して構え。
    S.append(dict(name='h027_sweep', state='attack', frames=30, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=10), melee=True, prime=('meshy_h027_sweep', [(0, 0), (10, 13), (29, 60)], 0.25),
                  keys=[(0, {}),
                        (3, dict(lgrip=0.35)),
                        (6, dict(hyaw=-50, tyaw=-72, tpitch=4, hz=0.03, hy=-0.08, ox=0.22, oy=1.02, oz=-0.02, syaw=-50, spitch=2,
                                 lgrip=0, lfx=-0.25, lfy=1.0, lfz=-0.15, dyaw=-8, lz=-0.2, llift=0.04)),
                        (8, dict(hyaw=-32, tyaw=-40, ox=0.22, oy=1.02, oz=-0.16, syaw=-30, lz=-0.28, llift=0.02)),
                        (9, dict(lz=-0.30, llift=0)),
                        (10, dict(hyaw=-10, tyaw=-6, tpitch=6, hz=-0.07, hy=-0.10, ox=0.2, oy=1.03, oz=-0.27, syaw=5, spitch=0,
                                  lgrip=0, lfx=-0.32, lfy=1.05, lfz=0.05, dyaw=0, lz=-0.30, llift=0)),
                        (13, dict(hyaw=14, tyaw=28, ox=0.08, oy=1.02, oz=-0.27, syaw=55, spitch=1, lfx=-0.3, lfy=1.04, lfz=0.12, dyaw=8)),
                        (17, dict(hyaw=4, tyaw=8, tpitch=5, ox=0.12, oy=1.0, oz=-0.18, syaw=38, spitch=4, lgrip=0, lfx=-0.26, lfz=0.0)),
                        (21, dict(lgrip=1, hyaw=-16, tyaw=-24, hz=-0.03, ox=0.15, oy=1.0, oz=-0.08, syaw=18, spitch=6, ld=0.22,
                                  lz=-0.24, llift=0.03)),
                        (24, dict(lz=-0.18, llift=0)),
                        (29, {})]))
    # 通常攻撃 3: 切り上げ。膝を曲げて穂先を前下へ下ろし、左足を踏み込んで脚と腰で伸び上がり、穂先を前下 → 頭上へ縦に
    # 振り上げる（打撃 10 = 穂先が相手の胸の高さを通る）。石突は右脚の外へ → 下ろして構え。
    S.append(dict(name='h027_rising', state='attack', frames=30, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=10), melee=True, prime=('meshy_h027_rising', [(0, 12), (10, 31), (29, 70)], 0.25),
                  keys=[(0, {}),
                        (5, dict(hy=-0.13, hz=0.02, tpitch=14, hyaw=-38, tyaw=-56, ox=0.18, oy=0.87, oz=-0.06, syaw=6, spitch=-14, shL=14,
                                 ld=0.08, dpitch=6, lz=-0.19, llift=0.03)),
                        (8, dict(hy=-0.11, hz=-0.02, tpitch=10, hyaw=-30, tyaw=-46, ox=0.17, oy=0.93, oz=-0.12, spitch=-2, ld=0.1, shL=10,
                                 lz=-0.25, llift=0.02)),
                        (9, dict(lz=-0.26, llift=0)),
                        (10, dict(hy=-0.07, hz=-0.06, tpitch=3, hyaw=-22, tyaw=-32, ox=0.17, oy=1.01, oz=-0.17, syaw=8, spitch=8, shL=6,
                                  ld=0.13, lz=-0.26, llift=0, dpitch=-3)),
                        (12, dict(hy=-0.04, tpitch=-3, ox=0.18, oy=1.1, oz=-0.15, syaw=12, spitch=38, ld=0.17, shL=0, dpitch=-7)),
                        (15, dict(hy=-0.02, hz=-0.04, tpitch=-9, hyaw=-18, tyaw=-26, ox=0.2, oy=1.19, oz=-0.1, syaw=18, spitch=64,
                                  ld=0.2, dpitch=-10)),
                        (20, dict(hy=-0.045, hz=-0.02, tpitch=-1, ox=0.18, oy=1.06, oz=-0.06, syaw=12, spitch=30, ld=0.22,
                                  lz=-0.21, llift=0.02)),
                        (23, dict(lz=-0.18, llift=0)),
                        (29, {})]))
    # パッシブ 竜の三連突き（Motion_H027.empoweredAttack と同じ拍）: 突きの構えから 1 発目（打撃 10 = sim の 1 発目の命中）、
    # 穂先を少し引いては突き直し、2・3 発目を 4 / 8 フレーム後（flurryInterval = 4 tick ≈ 0.133 秒）に突き切る。
    # 1 本ごとに向きが少し変わり、胴が突くたびに前へ入る。打撃の後は等速で再生する（HeroAnimator の専用クリップの経路）。
    S.append(dict(name='h027_flurry', state='attack', frames=34, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=10), melee=True, prime=('meshy_h027_thrust', [(0, 0), (10, 12), (33, 70)], 0.2),
                  keys=[(0, {}),
                        (5, dict(hz=0.05, hy=-0.075, hyaw=-42, tyaw=-60, tpitch=3, ox=0.2, oy=0.97, oz=0.10, syaw=11, spitch=8,
                                 ld=0.28, dyaw=-6, lz=-0.17, llift=0)),
                        (7, dict(lz=-0.23, llift=0.05)),
                        (9, dict(hz=-0.08, hy=-0.1, hyaw=-24, tyaw=-36, tpitch=9, ox=0.16, oy=1.01, oz=-0.18, syaw=7, spitch=5,
                                 ld=0.22, lz=-0.33, llift=0)),
                        (10, dict(hz=-0.15, hy=-0.115, hyaw=-18, tyaw=-30, tpitch=13, ox=0.14, oy=1.03, oz=-0.30, syaw=7, spitch=4,
                                  ld=0.19, lz=-0.33, dyaw=-4, dpitch=-5)),
                        (12, dict(hz=-0.13, hyaw=-21, tyaw=-34, tpitch=11, ox=0.15, oy=1.02, oz=-0.21, syaw=4, spitch=4, ld=0.2)),
                        (14, dict(hz=-0.17, hy=-0.12, hyaw=-15, tyaw=-26, tpitch=15, ox=0.13, oy=1.035, oz=-0.32, syaw=2, spitch=2,
                                  ld=0.18)),
                        (16, dict(hz=-0.15, hyaw=-19, tyaw=-31, tpitch=13, ox=0.145, oy=1.025, oz=-0.23, syaw=6, spitch=3, ld=0.2)),
                        (18, dict(hz=-0.19, hy=-0.125, hyaw=-12, tyaw=-22, tpitch=17, ox=0.125, oy=1.04, oz=-0.34, syaw=5, spitch=3,
                                  ld=0.17, dpitch=-6)),
                        (21, dict(hz=-0.18, hyaw=-13, tyaw=-23, tpitch=16, ox=0.13, oy=1.035, oz=-0.32, ld=0.17)),
                        (27, dict(hz=-0.06, hy=-0.075, hyaw=-26, tyaw=-40, tpitch=6, ox=0.16, oy=1.0, oz=-0.1, syaw=8, spitch=7,
                                  ld=0.22, lz=-0.25, llift=0.03)),
                        (30, dict(lz=-0.19, llift=0)),
                        (33, {})]))
    # スキル1 跳槍撃（詠唱のクリップ: 呼び出しの castLead 0.12 秒後が打撃 = 掬い上げの接触）。低く構えて穂先を対象の下へ
    # 差し入れ（4）、掬い上げて頭上へ持ち上げたまま保ち（4〜12 = sim の持ち上げ 0.4 秒）、腰と背を反らして頭上を越えて
    # 背後へ振り抜く（12〜18 = sim の放り投げ 0.2 秒）。穂先は頭の右を通る → 構えへ戻す。
    S.append(dict(name='h027_flip', state='cast', frames=40, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=4), melee=True, prime=('meshy_h027_flip', [(0, 15), (4, 21), (12, 33), (18, 47), (39, 72)], 0.2),
                  keys=[(0, {}),
                        (3, dict(hy=-0.14, tpitch=20, hyaw=-38, tyaw=-56, ox=0.17, oy=0.87, oz=-0.05, syaw=6, spitch=-18, ld=0.05,
                                 shL=16, shR=6, lz=-0.22, llift=0.03, dpitch=8)),
                        (4, dict(hy=-0.14, tpitch=18, hyaw=-36, tyaw=-52, ox=0.17, oy=0.88, oz=-0.08, spitch=-14, ld=0.06, shL=14,
                                 shR=4, lz=-0.24, llift=0)),
                        (8, dict(hy=-0.08, tpitch=4, ox=0.17, oy=1.05, oz=-0.1, syaw=6, spitch=30, ld=0.12, shL=4, shR=0, dpitch=-4)),
                        (12, dict(hy=-0.03, hz=0.02, tpitch=-10, hyaw=-28, tyaw=-38, ox=0.16, oy=1.25, oz=-0.06, syaw=7, spitch=62,
                                  ld=0.16, shL=0, dpitch=-18)),
                        (15, dict(hy=-0.02, hz=0.04, tpitch=-22, ox=0.24, oy=1.3, oz=0.0, syaw=8, spitch=94, ld=0.15, dpitch=-22)),
                        (18, dict(hy=-0.04, hz=0.03, tpitch=-14, ox=0.28, oy=1.18, oz=0.06, syaw=8, spitch=126, ld=0.15, dpitch=-10)),
                        (23, dict(hy=-0.05, hz=0.0, tpitch=-4, ox=0.26, oy=1.08, oz=-0.03, syaw=8, spitch=62, ld=0.18, dpitch=-4)),
                        (29, dict(ox=0.165, oy=1.0, oz=-0.03, spitch=20, ld=0.2, lz=-0.19, llift=0.02)),
                        (39, {})]))
    # スキル2 竜牙突き: 突進の間の姿勢（詠唱のクリップ、脚もクリップのまま = 突進中に足を回さない）。穂先を前へ構えて
    # 低く前傾し、前足を出した踏み込みの形で飛び込む。到着（sim の命中）で h027_strike_hit が突きを入れる。
    S.append(dict(name='h027_strike', state='cast', frames=14, loop=False, base=GUARD, rootXZ=0,
                  events=dict(impact=4), melee=False, prime=('meshy_h027_strike', [(0, 24), (13, 33)], 0.15),
                  keys=[(0, {}),
                        (3, dict(hy=-0.15, tpitch=26, hpitch=14, hyaw=-18, tyaw=-26, ox=0.15, oy=0.94, oz=-0.18, syaw=4, spitch=2,
                                 ld=0.22, lz=-0.34, rz=0.30, rlift=0.07, rroll=10, dpitch=-14)),
                        (13, dict(hy=-0.16, tpitch=28, hpitch=15, hyaw=-17, tyaw=-25, ox=0.15, oy=0.93, oz=-0.2, syaw=4, spitch=2,
                                  ld=0.22, lz=-0.35, rz=0.31, rlift=0.08, rroll=12, dpitch=-15))]))
    # スキル2 の到着: 突進の姿勢から体重を乗せて突き切り（打撃 3 = 命中の直後）、少し保って構えへ戻す（sim はそのまま
    # 通常攻撃へ移る）。
    S.append(dict(name='h027_strike_hit', state='cast', frames=22, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=3), melee=True, prime=None,
                  keys=[(0, dict(hy=-0.16, tpitch=28, hpitch=15, hyaw=-17, tyaw=-25, ox=0.15, oy=0.93, oz=-0.2, syaw=4, spitch=2,
                                 ld=0.22, lz=-0.35, rz=0.31, rlift=0.08, rroll=12, dpitch=-15)),
                        (3, dict(hz=-0.17, hy=-0.12, tpitch=16, hpitch=6, hyaw=-14, tyaw=-22, ox=0.13, oy=1.03, oz=-0.35, syaw=4,
                                 spitch=3, ld=0.18, lz=-0.35, rz=0.26, rlift=0, rroll=0, dpitch=-6)),
                        (8, dict(hz=-0.16, hy=-0.115, tpitch=14, ox=0.135, oy=1.03, oz=-0.32, ld=0.18)),
                        (15, dict(hz=-0.06, hy=-0.075, tpitch=6, hpitch=2, hyaw=-26, tyaw=-40, ox=0.16, oy=1.0, oz=-0.1, syaw=8,
                                  spitch=7, ld=0.22, lz=-0.24, rz=0.18, llift=0.02)),
                        (21, {})]))
    # アルティメット 至高の武人: 槍を右手で立てて構え直し（左手は柄を離して胸の前で拳を握る）、胸を張って気を高める
    # （打撃 4 = 発動の光）。短く保って構えへ戻す。移動中は上半身だけ（走りを止めない）。
    S.append(dict(name='h027_warrior', state='cast', frames=24, loop=False, base=GUARD, rootXZ=1,
                  events=dict(impact=4), melee=False, prime=('meshy_h027_warrior', [(0, 12), (4, 24), (23, 48)], 0.2),
                  keys=[(0, {}),
                        (2, dict(hy=-0.09, tpitch=8, ox=0.22, oy=0.98, oz=-0.02, syaw=30, spitch=40, lgrip=0.3)),
                        (4, dict(hy=-0.06, tpitch=-6, hyaw=-16, tyaw=-20, ox=0.27, oy=1.0, oz=-0.02, syaw=60, spitch=84, lgrip=0,
                                 lfx=-0.05, lfy=1.13, lfz=-0.2, lflex=1, dpitch=-10, rz=0.17, lz=-0.21)),
                        (10, dict(hy=-0.055, tpitch=-7, ox=0.27, oy=1.0, oz=-0.02, syaw=60, spitch=84, lgrip=0, lfx=-0.05, lfy=1.14, lfz=-0.21,
                                  lflex=1, dpitch=-8)),
                        (15, dict(ox=0.22, oy=1.0, oz=-0.03, syaw=30, spitch=50, lgrip=0.6, lflex=0.5, dpitch=-2)),
                        (23, {})]))
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
        free += V((0, 0.012 * abs(swing), 0.11 * swing if state == 'walk' else 0.16 * swing))
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
            c['groundSpeed'] = spec['groundSpeed']
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
