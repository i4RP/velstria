"""H032 ディアス: MLBB のディロス（Dyrroth）の画面収録に合わせた仕上げ（Blender 4.5+、docs/H032_QUALITY.md）。

元: 10-23 の初版のクリップ（tools/motion/h032-v1-clips.json = Meshy の prime・ライブラリを h032_compose.py で合成した物）。
初版を区間回転のまま読み、MLBB の姿勢・型・時刻へ直して App/Resources/Heroes/H032MotionClips.json を書く。
直さないクリップは初版のまま通す。判定・数値（Kit_H032）は変えない。クリップの impact は KitTimes / 攻撃の windup に合わせる。

Run from VELSTRIA:
  blender -b --factory-startup --python-exit-code 1 --python tools/blender/author_h032_motion.py -- [--analyze]
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy  # noqa: F401
from mathutils import Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clip_math as cm  # noqa: E402
import preview_clip as preview  # noqa: E402
import author_h025_motion as base  # noqa: E402

V = Vector
FPS = 30
ROOT = Path(__file__).resolve().parents[2]
HERO = ROOT/'App/Resources/Heroes/Hero_H032.usdz'
SRC = ROOT/'tools/motion/h032-v1-clips.json'
OUT = ROOT/'App/Resources/Heroes/H032MotionClips.json'
REPORT = ROOT/'build/h032-motion/finish-report.json'
S = cm.SEG_INDEX
UPPER = [S[s] for s in ('torso', 'head', 'armR', 'foreArmR', 'handR', 'armL', 'foreArmL', 'handL')]
ARM = {'R': [S['armR'], S['foreArmR'], S['handR']], 'L': [S['armL'], S['foreArmL'], S['handL']]}
LEGS = [('R', 'right'), ('L', 'left')]
FWD = V((0, 0, -1))
UP = V((0, 1, 0))


def axis(a, t):
    return Quaternion(V(a), t)


def smooth(t):
    return base.smooth(t)


def curve(t, pts):
    return base.curve(t, pts)


# ---------------------------------------------------------------- 計測

def lean_of(q):
    """区間の上向きの前傾（rad、前 = 正）。"""
    u = q @ UP
    return math.atan2(-u.z, u.y)


def limb(qs, seg):
    return qs[S[seg]] @ cm.DOWN


def joints(rig, qs, off):
    _, P = base.solve(rig, qs, off, {})
    return {r: P[rig.index[r]].copy() for r in rig.index}


def analyze(rig, clips):
    out = {}
    for name, c in clips.items():
        rows = []
        for f in range(c['frames']):
            qs, root = cm.interp_clip(c, f)
            off = V(root)*rig.leg_length
            J = joints(rig, qs, off)
            rows.append(dict(torso=math.degrees(lean_of(qs[S['torso']])), hips=math.degrees(lean_of(qs[S['hips']])),
                             head=math.degrees(lean_of(qs[S['head']])),
                             handR=[round(x, 2) for x in J['righthand']], handL=[round(x, 2) for x in J['lefthand']],
                             hipY=round(J['hips'].y, 3),
                             footR=[round(x, 2) for x in J['rightfoot']], footL=[round(x, 2) for x in J['leftfoot']]))
        mean = {k: round(sum(r[k] for r in rows)/len(rows), 1) for k in ('torso', 'hips', 'head', 'hipY')}
        out[name] = dict(mean=mean, frames=c['frames'], events=c.get('events'),
                         sample=[rows[i] for i in range(0, len(rows), max(1, len(rows)//6))])
    return out


# ---------------------------------------------------------------- 姿勢の道具

def rotate_upper(qs, q, hips_too=0.0):
    for i in UPPER:
        qs[i] = (q @ qs[i]).normalized()
    if hips_too:
        h = S['hips']
        qs[h] = (cm.slerp(Quaternion(), q, hips_too) @ qs[h]).normalized()


def rotate_chain(qs, idx, q):
    for i in idx:
        qs[i] = (q @ qs[i]).normalized()


def add_lean(qs, d, hips_share=0.4, head_follow=0.5):
    """胴の前傾を d（rad、前 = 正）だけ足す（腰も hips_share）。頭は d の head_follow だけ付いていく（前を見る）。"""
    head = qs[S['head']].copy()
    rotate_upper(qs, axis((1, 0, 0), -d), hips_too=hips_share)
    qs[S['head']] = (axis((1, 0, 0), -d*head_follow) @ head).normalized()


def low_arms(qs, side, swing=0.0, breath=0.0, w=1.0, out=1.0):
    """MLBB の構え: 上腕は下・外・少し前、前腕は前下へ（刃の輪が腰の前の外）。swing = 前後の振り（rad、前 = 正）。"""
    sgn = 1 if side == 'R' else -1
    tq = qs[S['torso']]
    fwd = tq @ FWD
    fwd = V((fwd.x, 0, fwd.z)).normalized()
    right = (UP.cross(fwd)*-1).normalized()
    up = (V((0, -1, 0)) + right*sgn*.5*out + fwd*(.12+swing)).normalized()
    fo = (V((0, -1, 0))*.42 + right*sgn*.22*out + fwd*(.78+swing*.8) + V((0, breath, 0))).normalized()
    aim_limb(qs, side, up, fo, w)


def abduct(qs, side, ang):
    """肩から腕全体を外へ開く（正 = 体から離す）。"""
    sgn = 1 if side == 'R' else -1
    # 胴の正面の軸まわり（胴に対して横へ開く）
    ax = qs[S['torso']] @ V((0, 0, 1))
    rotate_chain(qs, ARM[side], axis(ax, sgn*ang))


def open_elbow(qs, side, frac):
    """肘を frac だけ伸ばす（前腕を上腕の向きへ寄せる）。"""
    u = qs[ARM[side][0]] @ cm.DOWN
    f = qs[ARM[side][1]] @ cm.DOWN
    full = cm.rotation_between(f, u)
    rotate_chain(qs, ARM[side][1:], cm.slerp(Quaternion(), full, frac))


def aim_limb(qs, side, upper_dir, fore_dir, w=1.0):
    """上腕・前腕の向きを指定（ヒーロー空間の単位ベクトル）。手は前腕に付いて回る。w で元と混ぜる。"""
    a, f, h = ARM[side]
    r = cm.rotation_between(qs[a] @ cm.DOWN, upper_dir.normalized())
    r = cm.slerp(Quaternion(), r, w)
    rotate_chain(qs, [a, f, h], r)
    r2 = cm.rotation_between(qs[f] @ cm.DOWN, fore_dir.normalized())
    r2 = cm.slerp(Quaternion(), r2, w)
    rotate_chain(qs, [f, h], r2)


def run_arms(qs, side, sw, amp=1.0, w=1.0):
    """MLBB の走りの腕（vid6 コマ 143〜154 の横からの全コマ）: 前へ振る側は輪を顔の前まで振り上げ（前腕が立つ）、後ろへ振る側は
    輪を腰の横へ下ろす（前腕が下を向く）。手は体の近く・横へ開く（正面 vid7 で輪の外縁が体の中心から ±0.36）。sw = -1（後ろ）〜 1（前）。"""
    sgn = 1 if side == 'R' else -1
    fwd = qs[S['torso']] @ FWD
    fwd = V((fwd.x, 0, fwd.z)).normalized()
    right = fwd.cross(UP).normalized()
    t = .5+.5*max(-1.0, min(1.0, sw))*amp

    def d(f, o, u):
        return (fwd*f + right*sgn*o + UP*u).normalized()
    hi_u, hi_f = d(.36, .42, -.83), d(.6, .1, .78)
    lo_u, lo_f = d(-.28, .42, -.86), d(.38, .22, -.9)
    u = lo_u.lerp(hi_u, smooth(t)).normalized()
    f = lo_f.lerp(hi_f, smooth(t)).normalized()
    aim_limb(qs, side, u, f, w)


def plant(rig, qs, off, targets):
    errs = []
    for suf, side in LEGS:
        t = targets.get(side)
        if t is None:
            continue
        errs.append(base.ik(rig, qs, off, {}, [side+'upleg', side+'leg', side+'foot'],
                            ['thigh'+suf, 'shin'+suf], t, V((0, 0, -1))))
    return max(errs) if errs else 0.0


def foot_targets(rig, qs, off):
    J = joints(rig, qs, off)
    return {'right': J['rightfoot'], 'left': J['leftfoot']}


def lowest_contact(rig, qs, off):
    J = joints(rig, qs, off)
    return min(J[r].y - rig.P0[rig.index[r]].y for r in ('leftfoot', 'rightfoot', 'lefttoebase', 'righttoebase')
               if r in J)


# ---------------------------------------------------------------- 移動（段 1）
# MLBB（vid6 4.6〜8.0 秒・vid7 3.5〜6.4 秒・14 秒）: 移動は 1 種類の走り（歩きの別の型は無い。鈍足でも同じ走りが遅くなる）。
# 1 周 ≒ 23 コマ（0.77 秒、片足 11.5 コマ）。胴は深く前傾（35〜45°）、頭は前へ突き出して前を見る。刃の輪は腰〜胸の高さで
# 体の横・やや前に構え、肘を曲げたまま脚と逆に前後へ振る。マント・尾は後ろへ流れる。

RUN = dict(lean=math.radians(-8), hips_share=.3, head_follow=.5, drop=.02, abduct=0.0, elbow=0.0, low=0.0, out=1.5, arms=1.0,
           steady=.6, mean=math.radians(64.2))
WALK = dict(lean=math.radians(10), hips_share=.35, head_follow=.6, drop=.02, abduct=0.0, elbow=0.0, low=0.0, out=1.3, arms=.6)


def loco_pose(rig, clip, f, cfg):
    qs, root = cm.interp_clip(clip, f)
    qs = [q.copy() for q in qs]
    off = V(root)*rig.leg_length
    feet = foot_targets(rig, qs, off)
    lean = cfg['lean']
    if cfg.get('steady'):
        # 初版の前傾の揺れ（胸の区間で 57〜72°）を ならす: 周の平均（cfg['mean']）との差の steady 倍を戻す
        lean += cfg['steady']*(cfg['mean']-lean_of(qs[S['torso']]))
    add_lean(qs, lean, cfg['hips_share'], cfg['head_follow'])
    for side, other in (('R', 'L'), ('L', 'R')):
        if cfg['abduct']:
            abduct(qs, side, cfg['abduct'])
        if cfg['elbow']:
            open_elbow(qs, side, cfg['elbow'])
        th = limb(qs, 'thigh'+other)
        if cfg['low']:
            # 腕は反対の脚と同じ向きに振る（腿の前後の向き × 0.6）
            swing = max(-.35, min(.35, -th.z*.6))
            low_arms(qs, side, swing, w=cfg['low'], out=cfg['out'])
        if cfg.get('arms'):
            run_arms(qs, side, -th.z/.45, amp=cfg['arms'])
    off = off.copy()
    off.y -= cfg['drop']
    err = plant(rig, qs, off, feet)
    return qs, off, err


# ---------------------------------------------------------------- 待機
# MLBB（vid6 7.3 秒の正面・vid12 0〜1.5 秒・7.8 秒）: 脚を開いた低い構え。腕は下ろして体の横へ開き、刃の輪は腰の高さ。
# 胴はやや前傾。拳を顎の前に上げるボクシングの構えではない。

IDLE = dict(lean=math.radians(-4), drop=.04)


def idle_pose(rig, clip, f):
    qs, root = cm.interp_clip(clip, f)
    qs = [q.copy() for q in qs]
    off = V(root)*rig.leg_length
    feet = foot_targets(rig, qs, off)
    add_lean(qs, IDLE['lean'], .35, .5)
    t = f/clip['frames']
    breath = .03*math.sin(t*math.tau*2)
    for side in 'RL':
        low_arms(qs, side, 0.0, breath)
    off = off.copy()
    off.y -= IDLE['drop']
    err = plant(rig, qs, off, feet)
    return qs, off, err


# ---------------------------------------------------------------- キー姿勢（通常攻撃・スキル）
# 姿勢は待機（段 1）の 0 フレームの脚・腰から作り、胴のひねり（twist、正 = 左へ回す）・前傾（lean）・腰（drop・fwd）と
# 両腕の上腕・前腕の向き（胴のひねった水平の向きで: f = 前、o = 外（右腕は右・左腕は左）、u = 上）をキーで置く。
# キーの間は区間ごとの slerp。足は毎フレーム待機の位置へ IK（plant=False のキーの間は元の足の位置を補間して置く）。

GUARD = {'R': ((.3, .5, -.8), (.8, -.1, .55)), 'L': ((.3, .5, -.8), (.8, -.1, .55))}


class Base:
    def __init__(self, rig, clips):
        qs, off, _ = idle_pose(rig, clips['idle_h032'], 0)
        self.qs, self.off = qs, off
        self.feet = foot_targets(rig, qs, off)


def key_pose(rig, base, k):
    qs = [q.copy() for q in base.qs]
    tw = k.get('twist', 0.0)
    rotate_upper(qs, axis(UP, tw), hips_too=k.get('hipsTwist', .35))
    if k.get('yaw'):
        # 体ごと回す（脚も。円撃の踏み込みの向き）
        for i in range(15):
            qs[i] = (axis(UP, k['yaw']) @ qs[i]).normalized()
    add_lean(qs, k.get('lean', 0.0), .35, k.get('headFollow', .45))
    fwd = axis(UP, tw+k.get('yaw', 0.0)) @ FWD
    right = fwd.cross(UP)
    for side, sgn in (('R', 1), ('L', -1)):
        ua, fa = k.get(side, GUARD[side])
        u = (fwd*ua[0] + right*sgn*ua[1] + UP*ua[2])
        f = (fwd*fa[0] + right*sgn*fa[1] + UP*fa[2])
        aim_limb(qs, side, u, f)
    off = base.off + axis(UP, k.get('yaw', 0.0)) @ FWD*k.get('fwd', 0.0) + V((0, -k.get('drop', 0.0), 0)) \
        + V((0, k.get('lift', 0.0), 0))
    return qs, off


def keyed(rig, base, keys, frames, feet_fn=None):
    """keys: [(frame, key)]。フレームごとの (qs, off, IK の誤差) を返す関数。"""
    poses = [(f, *key_pose(rig, base, k), k) for f, k in keys]

    def at(fr):
        for (fa, qa, oa, ka), (fb, qb, ob, kb) in zip(poses, poses[1:]):
            if fr <= fb:
                t = (fr-fa)/max(1e-6, fb-fa)
                e = kb.get('ease', 'smooth')
                w = t if e == 'linear' else (1-(1-t)**2 if e == 'out' else (t*t if e == 'in' else smooth(t)))
                qs = [cm.slerp(a, b, w) for a, b in zip(qa, qb)]
                off = oa.lerp(ob, w)
                break
        else:
            qs, off = [q.copy() for q in poses[-1][1]], poses[-1][2].copy()
        feet = feet_fn(fr) if feet_fn else base.feet
        err = plant(rig, qs, off, feet)
        return qs, off, err
    return at


# 段 2: 通常攻撃（MLBB vid12 コマ 245〜253・269〜278・vid6 コマ 72〜98）。どちらも刃の輪で大きな弧を描く斬撃で、腕を振り上げて
# 引く 4 コマ → 振り抜き 4 コマ → 命中（1 撃目は上から斜めに振り下ろす、2 撃目は逆の腕で横から薙ぐ）→ 低い前傾で振り抜いたまま
# 2〜3 コマ → 輪を胸の前に構えた立ち姿へ。命中はクリップの 8 フレーム（0.27 秒）。試合では sim の windup（攻撃間隔の 25%）へ伸縮する。
# 3 回目の円撃（コマ 296〜302・112〜118）: 体を光らせて両腕を胸の前で交差して沈む（溜め 4 コマ）→ 踏み込みながら両腕を外へ
# 大きく開いて周りを薙ぐ（2 コマ）→ 命中 → 腕を開いたまま起き上がる。360° の回転はしない。

SLASH_L = [  # 左腕の大きな斬撃（左の後ろ・肩の高さ → 上を回って前の的へ → 右下へ振り抜く）
    (0, {}),
    (4, dict(twist=.4, lean=math.radians(-4), lift=.01, L=((-.45, .75, .4), (-.55, .5, .62)),
             R=((.15, .55, -.8), (.75, .1, .4)), ease='out')),
    (6, dict(twist=.15, lean=math.radians(6), L=((.35, .75, .45), (.8, .4, .45)), ease='in')),
    (8, dict(twist=-.35, lean=math.radians(14), drop=.06, fwd=.1, L=((.92, 0, .1), (.88, -.35, .12)),
             R=((-.2, .6, -.75), (.2, .3, -.9)), ease='linear')),
    (11, dict(twist=-.5, lean=math.radians(18), drop=.07, fwd=.1, L=((.5, -.4, -.45), (.3, -.75, -.4)),
              R=((-.25, .6, -.75), (.2, .35, -.88)), ease='out')),
    (23, {}),
]
SLASH_R = [  # 右腕の横薙ぎ（右の後ろ → 前の左）
    (0, {}),
    (4, dict(twist=-.5, lean=math.radians(2), R=((-.35, .78, .3), (-.5, .6, .45)), L=((.35, .45, -.7), (.85, -.2, .35)),
             ease='out')),
    (6, dict(twist=-.12, lean=math.radians(10), R=((.35, .88, .1), (.8, .55, .05)), ease='in')),
    (8, dict(twist=.42, lean=math.radians(22), drop=.07, fwd=.1, R=((.9, .1, -.1), (.75, -.6, -.05)),
             L=((-.2, .6, -.7), (.2, .4, -.85)), ease='linear')),
    (11, dict(twist=.55, lean=math.radians(24), drop=.08, fwd=.1, R=((.55, -.35, -.5), (.25, -.85, -.35)),
              L=((-.25, .6, -.72), (.2, .4, -.85)), ease='out')),
    (23, {}),
]
CIRCLE = [  # 円撃: 交差して溜め → 両腕を外へ開いて薙ぐ
    (0, {}),
    (4, dict(lean=math.radians(16), drop=.1, R=((.55, -.1, -.75), (.55, -.75, .1)), L=((.55, -.1, -.75), (.55, -.75, .1)),
             ease='out')),
    (6, dict(lean=math.radians(12), drop=.06, fwd=.08, twist=.15, R=((.75, .45, -.35), (.55, .8, .05)),
             L=((.75, .45, -.35), (.55, .8, .05)), ease='in')),
    (8, dict(lean=math.radians(18), drop=.08, fwd=.14, twist=-.2, R=((-.05, 1, -.2), (-.35, .9, -.1)),
             L=((-.05, 1, -.2), (-.35, .9, -.1)), ease='linear')),
    (12, dict(lean=math.radians(8), drop=.03, fwd=.12, twist=-.3, R=((-.25, .9, -.45), (-.45, .7, -.45)),
              L=((-.25, .9, -.45), (-.45, .7, -.45)), ease='out')),
    (25, {}),
]
ATTACKS = {'slash_l_h032': (SLASH_L, 24), 'slash_r_h032': (SLASH_R, 24), 'slash_circle_h032': (CIRCLE, 26)}

# 段 3: スキル（発動の瞬間から再生 = castsFromStart。impact は KitTimes の判定の時刻）。
# S1（vid6 コマ 359〜395、強化。指を離したのが 359）: 両腕を大きく広げて振り上げ（2〜3 コマ）→ 前へ両腕を振り下ろす（4 コマ）→
# 1 つ目の衝撃（8 コマ = 0.27 秒。sim の burstFirstDelay 0.26）→ 低くかがんで腕を前に出したまま衝撃が前へ走る（強化の 5 つ目まで約 1 秒）→ 起き上がる。
# 初版の右・左・右の 3 連打ではない。
SLAM_S1 = [
    (0, {}),
    (3, dict(lean=math.radians(-8), lift=.02, R=((-.1, .75, .65), (-.2, .45, .87)), L=((-.1, .75, .65), (-.2, .45, .87)),
             ease='out')),
    (6, dict(lean=math.radians(18), drop=.05, R=((.75, .45, .3), (.9, .1, .1)), L=((.75, .45, .3), (.9, .1, .1)), ease='in')),
    (8, dict(lean=math.radians(32), drop=.13, fwd=.1, R=((.8, .2, -.55), (.6, 0, -.8)), L=((.8, .2, -.55), (.6, 0, -.8)),
             ease='linear')),
    (22, dict(lean=math.radians(30), drop=.12, fwd=.1, R=((.82, .25, -.5), (.65, .05, -.75)),
              L=((.82, .25, -.5), (.65, .05, -.75)), ease='out')),
    (39, {}),
]
# 奥義（vid6 コマ 696〜726。指を離したのが 696、命中 719 = 0.77 秒）: 紫の帯が体を巻く間、両腕を頭の横まで上げて輪を掲げる（0.1〜0.45 秒）→
# 少し沈んで右腕を後ろへ引き絞り、体を反らす（0.45〜0.7 秒）→ 0.76 秒に右腕を前へ突き出して前へ倒れ込む（赤い刃が前へ飛ぶ）→ 低く振り抜いたまま →
# 構え。足は動かさない（sim も溜めの間・撃った後は動かない）。
STRIKE_ULT = [
    (0, {}),
    (5, dict(lean=math.radians(-6), R=((.05, .75, .66), (.15, .1, .99)), L=((.05, .75, .66), (.15, .1, .99)), ease='out')),
    (13, dict(lean=math.radians(-4), drop=.03, R=((.1, .78, .62), (.2, .05, .98)), L=((.1, .78, .62), (.2, .05, .98)))),
    (20, dict(twist=-.55, lean=math.radians(-10), drop=.08, R=((-.55, .55, -.2), (-.7, .2, .2)), L=((.55, .3, .2), (.9, -.2, .3)),
              ease='smooth')),
    (23, dict(twist=.3, lean=math.radians(24), drop=.1, fwd=.15, R=((.95, .05, .05), (.98, -.1, .05)),
              L=((-.3, .6, -.6), (.1, .5, -.85)), ease='in')),
    (30, dict(twist=.35, lean=math.radians(26), drop=.1, fwd=.15, R=((.9, .05, -.1), (.95, -.12, -.05)),
              L=((-.3, .6, -.6), (.1, .5, -.85)), ease='out')),
    (54, {}),
]
CASTS = {'slam_s1_h032': (SLAM_S1, 40, .26*FPS), 'strike_ult_h032': (STRIKE_ULT, 55, .76*FPS)}


# ---------------------------------------------------------------- 書き出し

def emit(rig, src, name, frames, fn, extra=None):
    c = {k: v for k, v in src.items() if k not in ('rot', 'root')}
    c.update(extra or {})
    c['frames'] = frames
    c['rot'], c['root'] = [], []
    prev, errs = [None]*15, []
    for f in range(frames):
        qs, off, err = fn(f)
        for i, q in enumerate(qs):
            vals, prev[i] = base.pack(q, prev[i])
            c['rot'] += vals
        c['root'] += [round(x/rig.leg_length, 5) for x in off]
        errs.append(err)
    return c, dict(frames=frames, maxIKClampMm=round(max(errs)*1000, 2))


def author(rig, clips):
    out, report = [], {}
    for name, c in clips.items():
        if name == 'run_h032':
            n, r = emit(rig, c, name, c['frames'], lambda f, c=c: loco_pose(rig, c, f, RUN))
        elif name == 'walk_h032':
            n, r = emit(rig, c, name, c['frames'], lambda f, c=c: loco_pose(rig, c, f, WALK))
        elif name == 'idle_h032':
            n, r = emit(rig, c, name, c['frames'], lambda f, c=c: idle_pose(rig, c, f))
        elif name in ('punch_jab_l_h032', 'punch_cross_r_h032', 'punch_s1_h032', 'punch_ult_h032'):
            continue
        else:
            n, r = dict(c), dict(frames=c['frames'], copied=True)
        n['source'] = 'h032' if r.get('copied') else 'h032+mlbb-finish'
        out.append(n)
        report[name] = r
    base = Base(rig, clips)
    tmpl = clips['punch_jab_l_h032']
    for name, (keys, frames) in ATTACKS.items():
        n, r = emit(rig, tmpl, name, frames, keyed(rig, base, keys, frames))
        n.update(name=name, source='h032+mlbb-keyed', events={'impact': 8.0}, melee=True)
        out.append(n)
        report[name] = r
    for name, (keys, frames, impact) in CASTS.items():
        n, r = emit(rig, tmpl, name, frames, keyed(rig, base, keys, frames))
        n.update(name=name, source='h032+mlbb-keyed', events={'impact': round(impact, 3)}, melee=True)
        out.append(n)
        report[name] = r
    return out, report


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--analyze', action='store_true')
    p.add_argument('--src', default=str(SRC))
    p.add_argument('--out', default=str(OUT))
    a = p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    rig, meshes, height, warnings = preview.load_hero(str(HERO))
    base.bind_usd_axes(rig, str(HERO))
    clips = preview.load_clips(a.src)
    if a.analyze:
        print(json.dumps(analyze(rig, clips)), flush=True)
        return
    out, report = author(rig, clips)
    Path(a.out).write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=out), separators=(',', ':'))+'\n',
                           encoding='utf-8')
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
