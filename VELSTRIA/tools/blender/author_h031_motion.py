"""H031 オーリアの待機・移動・通常攻撃・スキル詠唱の仕上げ（Blender 5.2、出荷リグの上で）。

Meshy prime（tools/motion/h031-prime-source-clips.json）の体幹・腕の動きを土台に、
足の接地（狭い足幅）・右手の向き（発射の瞬間に敵へ伸ばす）・指の形・ループの継ぎ目・
待機姿勢への復帰をこのヒーローの寸法で補正する。移動は実速度に合わせた接地 IK で作る
（prime の歩行・走行は腰が流れて足が滑るため、足の運びには使わない）。
出力は実行時の 15 区間 + 肩・つま先・指の局所差分（H025 と同じ形式）。
VELSTRIA/ で: Blender -b -P tools/blender/author_h031_motion.py [-- --out App/Resources/Heroes/H031MotionClips.json]
"""
import argparse
import json
import math
import sys
from pathlib import Path

from mathutils import Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clip_math as cm
import preview_clip as preview
from author_h025_motion import bind_usd_axes, ik, local_delta, pack, smooth, curve

FPS = 30
V = Vector
HERO = 'App/Resources/Heroes/Hero_H031.usdz'
SOURCE = 'tools/motion/h031-prime-source-clips.json'
FINGERS = ('thumb', 'index', 'middle', 'ring', 'pinky')
DETAILS = ['leftshoulder', 'rightshoulder', 'lefttoebase', 'righttoebase']
DETAILS += [s+'hand'+f+str(n) for s in ('left', 'right') for f in FINGERS for n in (1, 2, 3)]

# 指の曲げ（度、付け根・中・先）。親指は別。
HAND = {
    'relaxed': ([10, 14, 10], [14, 24, 14]),
    'soft': ([6, 8, 6], [8, 14, 8]),
    'cupped': ([22, 26, 16], [34, 46, 30]),
    'open': ([2, 0, 0], [-6, -2, 0]),
    'point': ([30, 30, 20], None),  # 人差し指だけ伸ばす（下で個別）
    'waist': ([18, 22, 14], [26, 38, 24]),
}


def axis(a, t):
    return Quaternion(a, t)


def lerp(a, b, w):
    return a+(b-a)*w


def finger_angles(shape):
    thumb, rest = HAND[shape]
    out = {}
    for f in FINGERS:
        if f == 'thumb':
            out[f] = thumb
        elif shape == 'point':
            out[f] = [0, 0, 0] if f == 'index' else [62, 84, 52]
        else:
            out[f] = rest
    return out


def mix_hands(a, b, w):
    return {f: [lerp(x, y, w) for x, y in zip(a[f], b[f])] for f in FINGERS}


class Author:
    def __init__(self, rig, src):
        self.rig, self.src = rig, src
        self.L = rig.leg_length
        ix = rig.index
        self.has_fingers = 'righthandindex1' in ix
        self.foot_z = (rig.P0[ix['rightfoot']].z+rig.P0[ix['leftfoot']].z)/2-.02
        self.foot_y = {s: rig.P0[ix[s+'foot']].y for s in ('right', 'left')}
        self.arm_len = ((rig.P0[ix['rightforearm']]-rig.P0[ix['rightarm']]).length
                        + (rig.P0[ix['righthand']]-rig.P0[ix['rightforearm']]).length)
        self.ready = None
        self.ready = self.idle(0.0)

    # ---- 共通 ----
    def details_for(self, right, left, shoulder_r=0.0, shoulder_l=0.0, toe_r=0.0, toe_l=0.0):
        rig = self.rig
        d = {r: Quaternion() for r in DETAILS if r in rig.index}
        for side, sign, elev in (('right', 1, shoulder_r), ('left', -1, shoulder_l)):
            if side+'shoulder' in rig.index:
                d[side+'shoulder'] = local_delta(rig, side+'shoulder', axis((0, 0, sign), elev))
        for side, roll in (('right', toe_r), ('left', toe_l)):
            if side+'toebase' in rig.index:
                d[side+'toebase'] = local_delta(rig, side+'toebase', axis((1, 0, 0), -roll))
        if self.has_fingers:
            for side, sign, hand in (('right', 1, right), ('left', -1, left)):
                for f in FINGERS:
                    for n in (1, 2, 3):
                        role = side+'hand'+f+str(n)
                        if role in rig.index:
                            d[role] = local_delta(rig, role, axis((0, 0, -sign), math.radians(hand[f][n-1])))
        return d

    def plant(self, qs, offset, details, targets, rolls=(0, 0)):
        err = []
        for (side, suffix), target, roll in zip((('right', 'R'), ('left', 'L')), targets, rolls):
            qs[cm.SEG_INDEX['foot'+suffix]] = axis((1, 0, 0), roll) @ self.rig.seg_C('foot'+suffix).inverted()
            err.append(ik(self.rig, qs, offset, details, [side+'upleg', side+'leg', side+'foot'],
                          ['thigh'+suffix, 'shin'+suffix], target, V((0, 0, -1))))
        return max(err)

    def stance(self):
        return [V((.075, self.foot_y['right'], self.foot_z+.06)), V((-.075, self.foot_y['left'], self.foot_z+.14))]

    def joints(self, qs, offset, details):
        from author_h025_motion import solve
        _, P = solve(self.rig, qs, offset, details)
        return P

    def arm_ik(self, qs, offset, details, side, target, pole):
        s = 'R' if side == 'right' else 'L'
        return ik(self.rig, qs, offset, details, [side+'arm', side+'forearm', side+'hand'],
                  ['arm'+s, 'foreArm'+s], target, pole)

    def wrist(self, qs, side, bend, roll=0.0):
        """手の区間を前腕に対して曲げる（bend > 0 で手の甲側へ = 掌が進む向きを向く）。"""
        fi, hi = cm.SEG_INDEX['foreArmR' if side == 'right' else 'foreArmL'], cm.SEG_INDEX['handR' if side == 'right' else 'handL']
        fore = qs[fi] @ cm.DOWN
        side_axis = fore.cross(V((0, 1, 0)))
        if side_axis.length < 1e-4:
            side_axis = V((1, 0, 0))
        side_axis.normalize()
        qs[hi] = (axis(fore.normalized(), roll) @ axis(side_axis, bend) @ qs[fi]).normalized()

    def source(self, name, frame):
        qs, root = cm.interp_clip(self.src['meshy_h031_prime_'+name], frame)
        return [q.copy() for q in qs], root*self.L

    # ---- 待機（4 秒ループ）----
    def idle(self, t):
        clip = self.src['meshy_h031_prime_idle']
        n = clip['frames']
        qs, root = self.source('idle', t*n)
        # 継ぎ目: 終わりの 20% で先頭の姿勢へ戻す（冠・髪・肩が周期的に跳ねない）
        if t > .8:
            q0, r0 = self.source('idle', 0)
            w = smooth((t-.8)/.2)
            qs = [cm.slerp(a, b, w) for a, b in zip(qs, q0)]
            root = root.lerp(r0, w)
        breath = math.sin(t*math.tau*2)
        shift = math.sin(t*math.tau)
        offset = V((.010*shift, .004*breath, 0))
        qs[1] = axis((1, 0, 0), .010*breath) @ qs[1]
        qs[0] = axis((0, 0, 1), -.012*shift) @ qs[0]
        # 高い顎・わずかに肩から頭が呼吸についてくる
        qs[2] = axis((1, 0, 0), .07+.012*breath) @ axis((0, 1, 0), .03*math.sin(t*math.tau+.6)) @ qs[2]
        flick = [.5+.5*math.sin(t*math.tau*2-k*.55) for k in range(5)]
        right = finger_angles('soft')
        for k, f in enumerate(FINGERS):
            right[f] = [a+b*flick[k] for a, b in zip(right[f], [6, 16, 12] if f != 'thumb' else [4, 6, 4])]
        details = self.details_for(right, finger_angles('waist'), .012*breath, .012*breath)
        # 右手: 腰の高さで掌を上に（ゆっくり上下）。左手は体の近く
        P = self.joints(qs, offset, details)
        sh_r, sh_l = P[self.rig.index['rightarm']], P[self.rig.index['leftarm']]
        hr = sh_r+V((.10, -.27+.010*breath, -.12))
        hl = sh_l+V((-.03, -.29, -.08))
        e = [self.arm_ik(qs, offset, details, 'right', hr, V((1, -.4, .4))),
             self.arm_ik(qs, offset, details, 'left', hl, V((-1, -.4, .5)))]
        self.wrist(qs, 'right', .55, .9)
        self.wrist(qs, 'left', .2, -.4)
        e.append(self.plant(qs, offset, details, self.stance()))
        return qs, offset, details, max(e)

    # ---- 歩行・走行（接地 IK、実速度に合わせた歩幅）----
    def locomotion(self, t, run):
        speed, duration, contact = (2.7, .6, .45) if run else (1.25, 1.1, .62)
        reach = speed*duration*contact/2
        wave = math.sin(t*math.tau)
        bounce = 1-math.cos(t*math.tau*2)
        rq = self.ready[0]
        qs = [q.copy() for q in rq]
        offset = V((.008*wave, (-.115 if run else -.11)-(.022 if run else .010)*bounce, 0))
        lean = -.13 if run else -.025
        qs[0] = axis((0, 1, 0), -.05*wave)
        qs[1] = axis((0, 1, 0), .045*wave) @ axis((1, 0, 0), lean-.01*bounce)
        qs[2] = axis((1, 0, 0), .05 if not run else .09) @ axis((0, 1, 0), -.02*wave)
        details = self.details_for(finger_angles('soft' if not run else 'relaxed'), finger_angles('waist'),
                                   -.01*wave, .01*wave)
        targets, rolls, toes = [], [], []
        for side, phase in (('right', t), ('left', t+.5)):
            u = phase % 1
            target = V((.07 if side == 'right' else -.07, self.foot_y[side], self.foot_z))
            roll = 0
            if u < contact:
                v = u/contact
                target.z += -reach+2*reach*v
                roll = .16*smooth((v-.8)/.2)
            else:
                v = (u-contact)/(1-contact)
                tangent = 2*reach*(1-contact)/contact
                target.z += reach-2*reach*smooth(v)+tangent*(2*v**3-3*v*v+v)
                target.y += (.09 if run else .05)*math.sin(math.pi*v)**2
                roll = .16*(1-smooth(v))-.08*math.sin(math.pi*v)
            if roll > 0:
                target.y += .07*math.sin(roll)
            targets.append(target)
            rolls.append(roll)
            toes.append(roll*.65)
        details = self.details_for(finger_angles('soft' if not run else 'relaxed'), finger_angles('waist'),
                                   -.01*wave, .01*wave, toes[0], toes[1])
        err = self.plant(qs, offset, details, targets, rolls)
        P = self.joints(qs, offset, details)
        sh_r, sh_l = P[self.rig.index['rightarm']], P[self.rig.index['leftarm']]
        swing = -wave  # 右腕は左脚と同じ向き
        if run:
            hr = sh_r+V((.07, -.20, -.12+.07*swing))
            hl = sh_l+V((-.07, -.20, -.12-.07*swing))
            pr, pl = V((.6, -.5, .7)), V((-.6, -.5, .7))
        else:
            hr = sh_r+V((.09, -.28, -.07+.04*swing))
            hl = sh_l+V((-.04, -.29, -.08-.02*swing))
            pr, pl = V((1, -.4, .5)), V((-1, -.4, .5))
        err = max(err, self.arm_ik(qs, offset, details, 'right', hr, pr),
                  self.arm_ik(qs, offset, details, 'left', hl, pl))
        self.wrist(qs, 'right', .35 if not run else .15, .6)
        self.wrist(qs, 'left', .2, -.4)
        return qs, offset, details, err

    # ---- 攻撃・詠唱（prime を時間変換 → 補正 → 待機姿勢へ戻す）----
    def action(self, name, ts, spec):
        """ts: 秒。spec: timemap / blend / root / posture / hand / ik / wrist / fingers / extra。"""
        sf = curve(ts, spec['timemap'])
        qs, root = self.source(spec['source'], sf)
        q0 = self.ready[0]
        kx, ky, kz = spec.get('root', (.4, .6, .4))
        root = V((root.x*kx, root.y*ky, root.z*kz))
        for i in (0, 1, 2):
            qs[i] = cm.slerp(q0[i], qs[i], spec.get('posture', 1.0))
        w = smooth(ts/spec['blend_in'])*(1-smooth((ts-spec['out'][0])/(spec['out'][1]-spec['out'][0])))
        qs = [cm.slerp(a, b, w) for a, b in zip(q0, qs)]
        offset = self.ready[1].lerp(root, w)
        qs[2] = axis((1, 0, 0), -.03*w) @ qs[2]
        if 'extra' in spec:
            spec['extra'](qs, offset, ts)
        hand = spec['fingers'](ts)
        details = self.details_for(hand, finger_angles('waist'), spec.get('shoulder', lambda t: 0)(ts))
        err = self.plant(qs, offset, details, self.stance())
        P = self.joints(qs, offset, details)
        sh = P[self.rig.index['rightarm']]
        hr = P[self.rig.index['righthand']]
        for key, pole in spec.get('ik', []):
            wk = key['w'](ts)*w
            if wk > 1e-3:
                target = hr.lerp(sh+key['at'](ts, self.arm_len), wk)
                err = max(err, self.arm_ik(qs, offset, details, 'right', target, pole))
                P = self.joints(qs, offset, details)
                hr = P[self.rig.index['righthand']]
        # 左手は体の近く（腰の前）へ寄せる
        sl = P[self.rig.index['leftarm']]
        hl = P[self.rig.index['lefthand']]
        tl = sl+V((-.03, -.29, -.08))
        lw = spec.get('left_hold', .7)*w
        err = max(err, self.arm_ik(qs, offset, details, 'left', hl.lerp(tl, lw), V((-1, -.4, .5))))
        bend, roll = spec['wrist'](ts)
        self.wrist(qs, 'right', bend*w+.55*(1-w), roll*w+.9*(1-w))
        self.wrist(qs, 'left', .2, -.4)
        return qs, offset, details, err


def specs(A):
    L = A.arm_len

    def env(points):
        return lambda t: curve(t, points)

    def hands(points):
        """points: [(秒, 形, 重み)] を順に補間する。"""
        def f(t):
            for (a, x), (b, y) in zip(points, points[1:]):
                if t <= b:
                    return mix_hands(finger_angles(x), finger_angles(y), smooth((t-a)/max(1e-6, b-a)))
            return finger_angles(points[-1][1])
        return f

    def recoil(qs, offset, t):
        k = curve(t, [(0, 0), (.40, 0), (.46, 1), (.62, .25), (.8, 0)])
        qs[1] = axis((1, 0, 0), .06*k) @ axis((0, 1, 0), -.05*k) @ qs[1]
        offset.z += .012*k

    def coil(qs, offset, t):
        # 引き寄せで腰・胸を右へわずかにひねり、放つ瞬間に前へ戻す（腕だけの動きにしない）
        k = curve(t, [(0, 0), (.12, .4), (.30, 1), (.40, -.35), (.55, 0)])
        qs[0] = axis((0, 1, 0), -.06*k) @ qs[0]
        qs[1] = axis((0, 1, 0), -.14*k) @ qs[1]
        recoil(qs, offset, t)

    attack = dict(
        source='attack', frames=31, events=dict(impact=12, release=12, end=30),
        timemap=[(0, 0), (.28, 30), (.40, 47), (.55, 57), (.80, 70), (1.0, 74)],
        blend_in=.06, out=(.52, 1.0), root=(.3, .5, .3), posture=.85,
        extra=coil,
        ik=[(dict(w=env([(0, 0), (.10, .55), (.30, .8), (.37, .9), (.40, 1), (.55, 1), (.78, 0)]),
                  at=lambda t, L: V((0, 0, 0)).lerp(V((.03, .02, -.96*L)), smooth((t-.31)/.09)) +
                  V((-.10, -.16, -.18)).lerp(V((0, 0, 0)), smooth((t-.31)/.09))), V((1, -.6, .2)))],
        wrist=lambda t: (curve(t, [(0, .3), (.28, -.35), (.36, .2), (.40, .95), (.55, .85), (.8, .55)]),
                         curve(t, [(0, .9), (.28, 1.6), (.40, .2), (.6, .3), (.9, .9)])),
        fingers=hands([(0, 'soft'), (.12, 'cupped'), (.33, 'cupped'), (.40, 'open'), (.58, 'open'), (.85, 'soft')]),
        shoulder=env([(0, 0), (.30, .04), (.40, .14), (.55, .10), (.8, 0)]),
    )
    s1 = dict(
        source='s1', frames=27, events=dict(impact=3.6, end=26),
        timemap=[(0, 0), (.20, 11), (.45, 32), (.70, 62), (.9, 74)],
        blend_in=.05, out=(.45, .88), root=(.3, .5, .3), posture=.9,
        ik=[(dict(w=env([(0, 0), (.08, .4), (.18, 1), (.45, 1), (.7, 0)]),
                  at=lambda t, L: V((.05, .24, -.5*L)).lerp(V((.02, -.08, -.94*L)), smooth((t-.10)/.12))),
             V((1, -.3, .3)))],
        wrist=lambda t: (curve(t, [(0, .3), (.15, .1), (.22, -.15), (.45, -.15), (.7, .4)]), curve(t, [(0, .9), (.2, 1.4), (.6, 1.2), (.9, .9)])),
        fingers=hands([(0, 'soft'), (.12, 'open'), (.2, 'point'), (.48, 'point'), (.75, 'soft')]),
        shoulder=env([(0, 0), (.15, .16), (.45, .12), (.75, 0)]),
    )
    s2 = dict(
        source='s2', frames=31, events=dict(impact=3.6, end=30),
        timemap=[(0, 0), (.20, 6), (.30, 15), (.45, 26), (.6, 30), (1.0, 32)],
        blend_in=.05, out=(.55, 1.0), root=(.3, .45, .3), posture=.85,
        extra=lambda qs, o, t: qs.__setitem__(1, axis((0, 1, 0), curve(t, [(0, 0), (.2, -.16), (.36, .10), (.48, .02), (.7, 0)])) @ qs[1]),
        ik=[(dict(w=env([(0, 0), (.12, .9), (.2, 1), (.52, 1), (.8, 0)]),
                  at=lambda t, L: (V((.28, -.06, -.10)) if t < .22 else
                                   V((.22, -.03, -.24)).lerp(V((-.14, -.03, -.28)), smooth((t-.22)/.14)) if t < .38 else
                                   V((-.14, -.03, -.28)).lerp(V((-.02, -.01, -.92*L)), smooth((t-.38)/.10)))
                  if t >= .2 else V((.28, -.06, -.10))), V((1, -.4, .2)))],
        wrist=lambda t: (curve(t, [(0, .3), (.2, -.2), (.24, .6), (.38, .8), (.48, .95), (.6, .8), (.9, .55)]),
                         curve(t, [(0, .9), (.2, 2.2), (.26, .6), (.38, .4), (.48, .2), (.9, .9)])),
        fingers=hands([(0, 'soft'), (.12, 'cupped'), (.21, 'cupped'), (.26, 'open'), (.6, 'open'), (.9, 'soft')]),
        shoulder=env([(0, 0), (.2, .08), (.45, .12), (.7, 0)]),
    )
    ult = dict(
        source='ult', frames=34, events=dict(impact=3.6, end=33),
        timemap=[(0, 0), (.15, 14), (.27, 27), (.45, 38), (.85, 70), (1.1, 89)],
        blend_in=.05, out=(.5, 1.1), root=(.3, .35, .3), posture=.42,
        ik=[(dict(w=env([(0, 0), (.06, .5), (.13, 1), (.17, 1), (.27, 1), (.45, 1), (.75, 0)]),
                  at=lambda t, L: V((.06, .30, -.10)).lerp(V((.05, -.26, -.18)), smooth((t-.15)/.12))),
             V((1, .2, .4)))],
        wrist=lambda t: (curve(t, [(0, .3), (.13, .4), (.27, .9), (.45, .8), (.8, .55)]), curve(t, [(0, .9), (.13, 1.5), (.27, 1.5), (.8, .9)])),
        fingers=hands([(0, 'soft'), (.12, 'open'), (.5, 'open'), (.85, 'soft')]),
        shoulder=env([(0, 0), (.13, .22), (.27, .02), (.7, 0)]),
    )
    return dict(attack=attack, s1=s1, s2=s2, ult=ult)


def author(A, out):
    sp = specs(A)
    defs = [
        ('idle_h031', 'idle', 120, True, None),
        ('walk_h031', 'walk', 33, True, 1.25),
        ('run_h031', 'run', 18, True, 2.7),
        ('cast_frost_h031', 'attack', None, False, None),
        ('cast_s1_h031', 's1', None, False, None),
        ('cast_s2_h031', 's2', None, False, None),
        ('cast_ult_h031', 'ult', None, False, None),
    ]
    clips, report = [], {}
    for name, kind, frames, loop, gspeed in defs:
        spec = sp.get(kind)
        frames = frames or spec['frames']
        src = 'meshy:prime:'+A.task_ids.get('idle' if kind in ('walk', 'run') else kind, '')
        c = dict(name=name, source=src+'+local:H031-finish' if kind not in ('walk', 'run') else 'local:H031-contact-gait',
                 frames=frames, loop=loop, rootXZ=0, melee=False, events=dict(spec['events']) if spec else {},
                 rot=[], root=[], detailJoints=[r for r in DETAILS if r in A.rig.index], detailRot=[])
        if gspeed:
            c['groundSpeed'] = gspeed
        prev, pd, errs = [None]*15, [None]*len(c['detailJoints']), []
        for f in range(frames):
            if kind == 'idle':
                pose = A.idle(f/frames)
            elif kind in ('walk', 'run'):
                pose = A.locomotion(f/frames, kind == 'run')
            else:
                pose = A.action(name, f/FPS, spec)
            qs, offset, details, err = pose
            for i, q in enumerate(qs):
                vals, prev[i] = pack(q, prev[i])
                c['rot'] += vals
            c['root'] += [round(x/A.L, 6) for x in offset]
            for i, role in enumerate(c['detailJoints']):
                vals, pd[i] = pack(details[role], pd[i])
                c['detailRot'] += vals
            errs.append(err)
        clips.append(c)
        if loop:
            a = A.idle(0)[0] if kind == 'idle' else A.locomotion(0, kind == 'run')[0]
            b = A.idle(1)[0] if kind == 'idle' else A.locomotion(1, kind == 'run')[0]
        else:
            a, b = A.ready[0], A.action(name, (frames-1)/FPS, spec)[0]
        report[name] = dict(frames=frames, maxTargetClampMm=round(max(errs)*1000, 2),
                            seamOrReturnDegrees=round(max(cm.quat_angle_deg(x, y) for x, y in zip(a, b)), 3))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=clips), separators=(',', ':'))+'\n')
    return report


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', default='App/Resources/Heroes/H031MotionClips.json')
    p.add_argument('--hero', default=HERO)
    a = p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    rig, meshes, height, warnings = preview.load_hero(str(Path(a.hero).resolve()))
    axis_err = bind_usd_axes(rig, a.hero)
    src = preview.load_clips(SOURCE)
    A = Author(rig, src)
    meta = json.loads(Path(SOURCE).read_text()).get('taskIds', {})
    A.task_ids = meta
    report = author(A, Path(a.out))
    report['model'] = dict(height=height, bones=len(rig.names), fingers=A.has_fingers, axisErrorDegrees=axis_err, warnings=warnings)
    Path('build/h031-motion').mkdir(parents=True, exist_ok=True)
    Path('build/h031-motion/finish-report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
