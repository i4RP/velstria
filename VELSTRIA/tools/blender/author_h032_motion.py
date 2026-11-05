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

RUN = dict(lean=math.radians(4), hips_share=.3, head_follow=.4, drop=.02, abduct=0.0, elbow=0.0, low=.85, out=1.5)
WALK = dict(lean=math.radians(14), hips_share=.35, head_follow=.6, drop=.02, abduct=0.0, elbow=0.0, low=.8, out=1.3)


def loco_pose(rig, clip, f, cfg):
    qs, root = cm.interp_clip(clip, f)
    qs = [q.copy() for q in qs]
    off = V(root)*rig.leg_length
    feet = foot_targets(rig, qs, off)
    add_lean(qs, cfg['lean'], cfg['hips_share'], cfg['head_follow'])
    for side, other in (('R', 'L'), ('L', 'R')):
        if cfg['abduct']:
            abduct(qs, side, cfg['abduct'])
        if cfg['elbow']:
            open_elbow(qs, side, cfg['elbow'])
        if cfg['low']:
            # 腕は反対の脚と同じ向きに振る（腿の前後の向き × 0.6）
            th = limb(qs, 'thigh'+other)
            swing = max(-.35, min(.35, -th.z*.6))
            low_arms(qs, side, swing, w=cfg['low'], out=cfg['out'])
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
        else:
            n, r = dict(c), dict(frames=c['frames'], copied=True)
        n['source'] = 'h032' if r.get('copied') else 'h032+mlbb-finish'
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
