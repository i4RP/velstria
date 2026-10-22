"""H026 エウリア motion finishing on the shipped 23-joint rig (Blender 4.5+).

Sources: Meshy prime text-to-motion takes (tools/motion/h026-prime-source-clips.json, one per action).
Per clip: loop window + seam blend, planted-foot / ground contact, upper-body posture (sword shoulder
forward, run lean), greatsword direction (handR), timing retarget to gameplay events, start/end blend to
the idle stance. Writes App/Resources/Heroes/H026MotionClips.json (15 segments + shoulder/toe details).
Run from VELSTRIA: blender -b -P tools/blender/author_h026_motion.py
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy  # noqa: F401  (Blender runtime; rig solving uses bpy-backed armature data)
from mathutils import Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clip_math as cm
import preview_clip as preview
import author_h025_motion as base

V = Vector
FPS = 30
HERO = 'App/Resources/Heroes/Hero_H026.usdz'
SRC = 'tools/motion/h026-prime-source-clips.json'
OUT_DIR = Path('build/h026-motion')
DETAILS = ['leftshoulder', 'rightshoulder', 'lefttoebase', 'righttoebase']
UPPER = [cm.SEG_INDEX[s] for s in ('torso', 'head', 'armR', 'foreArmR', 'handR', 'armL', 'foreArmL', 'handL')]
LEGS = [('R', 'right'), ('L', 'left')]
# Greatsword: grip at the hand, blade along handR @ (0,0,-1) (HeroMotionSet.fistGrip). ~1.3 m to the tip.
BLADE = 1.3
GROUND_CLEAR = 0.06


def axis(a, t):
    return Quaternion(a, t)


def smooth(t):
    return base.smooth(t)


def blade_dir(qs):
    return qs[cm.SEG_INDEX['handR']] @ V((0, 0, -1))


def set_blade(qs, d):
    return  # H026 has no blade (ball lightning above the right palm keeps the source wrist)
    i = cm.SEG_INDEX['handR']
    qs[i] = (cm.rotation_between(blade_dir(qs), d.normalized()) @ qs[i]).normalized()


def rotate_upper(qs, q, hips_too=0.0):
    for i in UPPER:
        qs[i] = (q @ qs[i]).normalized()
    if hips_too:
        h = cm.SEG_INDEX['hips']
        qs[h] = (cm.slerp(Quaternion(), q, hips_too) @ qs[h]).normalized()


def mix(a, b, w):
    return [cm.slerp(x, y, w) for x, y in zip(a, b)]


class Source:
    def __init__(self, clips):
        self.clips = clips

    ALIAS = {}

    def at(self, name, f):
        q, r = cm.interp_clip(self.clips['h026src_'+self.ALIAS.get(name, name)], f)
        return [x.copy() for x in q], r.copy()

    def frames(self, name):
        return self.clips['h026src_'+self.ALIAS.get(name, name)]['frames']


def pose_distance(a, b, idx):
    return sum(cm.quat_angle_deg(a[i], b[i]) for i in idx)


def find_loop(src, name, lo, hi):
    """Best (start, period) so pose(start) ~ pose(start+period) (legs+torso), leaving lead-in frames."""
    n = src.frames(name)
    idx = [cm.SEG_INDEX[s] for s in ('thighR', 'shinR', 'thighL', 'shinL', 'torso', 'armL', 'foreArmL')]
    best = None
    for p in range(lo, min(hi, n-2)+1):
        for s in range(int(.25*p), n-1-p):
            d = pose_distance(src.at(name, s)[0], src.at(name, s+p)[0], idx)
            if best is None or d < best[0]:
                best = (d, s, p)
    return best


def foot_heights(rig, qs, offset):
    dR, P = base.solve(rig, qs, offset, {})
    out = {}
    for suffix, side in LEGS:
        ankle = P[rig.index[side+'foot']].y - rig.P0[rig.index[side+'foot']].y
        toe = P[rig.index[side+'toebase']].y - rig.P0[rig.index[side+'toebase']].y
        out[side] = (min(ankle, toe), P[rig.index[side+'foot']].copy(), P[rig.index[side+'toebase']].copy())
    return out, P


def toe_details(rig, qs, offset, details):
    """Bend the toe joint so the toe tip stays on the ground when the heel lifts (no extra toe-tip joint: use foot pitch)."""
    for suffix, side in LEGS:
        f = qs[cm.SEG_INDEX['foot'+suffix]] @ rig.seg_C('foot'+suffix).inverted() if False else None
        _, P = base.solve(rig, qs, offset, details)
        ankle = P[rig.index[side+'foot']]
        toe = P[rig.index[side+'toebase']]
        rest_a = rig.P0[rig.index[side+'foot']]
        rest_t = rig.P0[rig.index[side+'toebase']]
        rest_drop = rest_a.y - rest_t.y
        drop = ankle.y - toe.y
        # Heel up (ankle much higher above the toe than at rest) with the toe near the ground: curl the toe up.
        pitch = math.atan2(max(0.0, drop-rest_drop), max(1e-3, (V((toe.x, 0, toe.z))-V((ankle.x, 0, ankle.z))).length))
        near = 1-smooth((toe.y-rest_t.y-.02)/.06)
        bend = min(.75, pitch*1.1)*near
        details[side+'toebase'] = base.local_delta(rig, side+'toebase', axis((1, 0, 0), bend))
        del f


def plant(rig, qs, offset, details, targets):
    errs = []
    for suffix, side in LEGS:
        if targets.get(side) is None:
            continue
        errs.append(base.ik(rig, qs, offset, details, [side+'upleg', side+'leg', side+'foot'],
                            ['thigh'+suffix, 'shin'+suffix], targets[side], V((0, 0, -1))))
    return max(errs) if errs else 0.0


def clamp_blade(rig, qs, offset, details, extra_clear=0.0):
    """No blade on H026."""
    return
    _, P = base.solve(rig, qs, offset, details)
    hand = P[rig.index['righthand']]
    d = blade_dir(qs)
    tip = hand.y + BLADE*d.y
    floor = GROUND_CLEAR+extra_clear
    if tip < floor:
        need = (floor-hand.y)/BLADE
        need = max(-1.0, min(1.0, need))
        horiz = V((d.x, 0, d.z))
        if horiz.length < 1e-4:
            horiz = V((0, 0, -1))
        horiz.normalize()
        set_blade(qs, horiz*math.sqrt(max(0, 1-need*need)) + V((0, need, 0)))


# Ready stance: right (sword) shoulder slightly forward; blade low, forward and out.
STANCE_YAW = .10
IDLE_BLADE = V((.42, -.42, -.80))
WALK_BLADE = V((.38, -.40, .83))
RUN_BLADE = V((.30, -.30, .90))


def shoulders(rig, details, fwd_r, breath=0.0):
    details['rightshoulder'] = base.local_delta(rig, 'rightshoulder', axis((0, 1, 0), fwd_r) @ axis((0, 0, 1), .015*breath))
    details['leftshoulder'] = base.local_delta(rig, 'leftshoulder', axis((0, 1, 0), .02) @ axis((0, 0, 1), -.015*breath))


def ground_offset(rig, qs, root, per_frame=True, rest_floor=0.0):
    off = V((root.x, root.y, root.z))*rig.leg_length
    h, _ = foot_heights(rig, qs, off)
    low = min(h['left'][0], h['right'][0])
    if per_frame:
        off.y -= low - rest_floor
    elif low < rest_floor:
        off.y += rest_floor-low
    return off


# ---------------------------------------------------------------- idle

def idle_pose(rig, src, t, ctx):
    n = src.frames('idle')
    f = t*(n-1)
    qs, r = src.at('idle', f)
    # Seam: blend the last 25% toward the first frame's pose so the loop has no pop.
    w = smooth((t-.75)/.25)
    if w > 0:
        q0, r0 = src.at('idle', 0)
        qs = mix(qs, q0, w)
        r = r.lerp(r0, w)
    breath = math.sin(t*math.tau)
    rotate_upper(qs, axis((0, 1, 0), STANCE_YAW), hips_too=.45)
    off = V((r.x*.6, r.y, r.z*.6))*rig.leg_length
    details = {k: Quaternion() for k in DETAILS}
    shoulders(rig, details, .04, breath)
    # Feet stay on their averaged stance positions; knees soften with the breath.
    off.y = ctx['idle_y'] - .006*(1+breath)
    err = plant(rig, qs, off, details, ctx['idle_feet'])
    # Sword weight: steady low forward blade, tiny settle with the breath (no periodic bounce).
    set_blade(qs, IDLE_BLADE + V((0, .012*breath, 0)))
    clamp_blade(rig, qs, off, details)
    return qs, off, details, err


def idle_context(rig, src):
    q0, r0 = src.at('idle', 0)
    rotate_upper(q0, axis((0, 1, 0), STANCE_YAW), hips_too=.45)
    off = ground_offset(rig, q0, r0)
    _, P = base.solve(rig, q0, off, {})
    feet = {}
    for _, side in LEGS:
        p = P[rig.index[side+'foot']].copy()
        p.y = rig.P0[rig.index[side+'foot']].y
        feet[side] = p
    # Widen to a grounded stance with the sword-side foot ahead.
    feet['right'].x = max(feet['right'].x, .09); feet['right'].z = min(feet['right'].z, -.03)
    feet['left'].x = min(feet['left'].x, -.09); feet['left'].z = max(feet['left'].z, .05)
    return {'idle_feet': feet, 'idle_y': min(off.y, -.035)}


# ---------------------------------------------------------------- walk / run

def loco_pose(rig, src, t, ctx, state):
    s, p = ctx[state+'_loop']
    u = t % 1
    qs, r = src.at(state, s+u*p)
    w = smooth((u-.8)/.2)
    if w > 0:
        qb, rb = src.at(state, s+u*p-p)
        qs = mix(qs, qb, w)
        r = r.lerp(rb + (ctx[state+'_drift']), w)
    wave = math.sin(u*math.tau*2)
    # Posture: walk upright and calm; run leans forward (capped), sword hugging the body.
    torso_up = qs[cm.SEG_INDEX['torso']] @ V((0, 1, 0))
    lean = math.atan2(-torso_up.z, torso_up.y)
    target = .04 if state == 'walk' else .16
    rotate_upper(qs, axis((1, 0, 0), lean-target), hips_too=.6)
    rotate_upper(qs, axis((0, 1, 0), STANCE_YAW*.5))
    # Lateral sway relative to the loop's linear drift (the hero's travel belongs to the simulation).
    _, rs = src.at(state, s)
    lateral = (r.x-rs.x) - ctx[state+'_drift'].x*-u
    root = V((max(-.05, min(.05, lateral*.5)), r.y, 0))
    off = ground_offset(rig, qs, root, per_frame=True)
    if state == 'run':
        off.y += .02*max(0.0, math.sin(u*math.tau*2))
    details = {k: Quaternion() for k in DETAILS}
    shoulders(rig, details, .05 if state == 'walk' else .03)
    toe_details(rig, qs, off, details)
    set_blade(qs, (WALK_BLADE if state == 'walk' else RUN_BLADE) + V((0, .02*wave, 0)))
    clamp_blade(rig, qs, off, details, .05)
    return qs, off, details, 0.0


def loco_context(rig, src, state):
    lo, hi = (26, 48) if state == 'walk' else (14, 30)
    d, s, p = find_loop(src, state, lo, hi)
    _, ra = src.at(state, s)
    _, rb = src.at(state, s+p)
    drift = ra-rb
    # Ground speed from the in-place support foot: while a foot is the lower one, its hero-space
    # backward velocity equals the speed the body must travel for that foot not to skate.
    samples = []
    for f in range(p):
        a, r0 = src.at(state, s+f)
        b, r1 = src.at(state, s+f+1)
        ha, _ = foot_heights(rig, a, V((0, r0.y, 0))*rig.leg_length)
        hb, _ = foot_heights(rig, b, V((0, r1.y, 0))*rig.leg_length)
        side = 'left' if ha['left'][0] < ha['right'][0] else 'right'
        if min(ha['left'][0], ha['right'][0]) - min(ha['left'][0], ha['right'][0]) < .03:
            samples.append((ha[side][1].z-hb[side][1].z)*-FPS)
    samples.sort()
    speed = abs(samples[len(samples)//2]) if samples else 1.2
    # Run: global floor so flight phases stay airborne but no frame sinks below ground.
    floor = 0.0
    return {state+'_loop': (s, p), state+'_drift': V((drift.x, 0, drift.z)), state+'_speed': speed,
            state+'_floor': floor, state+'_seam': d}


# ---------------------------------------------------------------- attacks / casts

def hand_speed_peak(rig, src, name, lo, hi):
    best = (0, lo)
    for f in range(lo, hi):
        a, _ = src.at(name, f-1)
        b, _ = src.at(name, f+1)
        da = blade_dir(a); db = blade_dir(b)
        fa = a[cm.SEG_INDEX['foreArmR']] @ cm.DOWN; fb = b[cm.SEG_INDEX['foreArmR']] @ cm.DOWN
        v = math.degrees(fa.angle(fb)) + .3*math.degrees(da.angle(db))
        if v > best[0]:
            best = (v, f)
    return best[1]


def retime(t_out, keys):
    """Piecewise-smooth map from output frame to source frame. keys: [(out, src)...]."""
    for (a, x), (b, y) in zip(keys, keys[1:]):
        if t_out <= b:
            u = (t_out-a)/max(1e-6, b-a)
            return x+(y-x)*u
    return keys[-1][1]


def action_root(r, spec):
    """Attacks keep a reduced lunge (the hero's position belongs to the simulation)."""
    k = spec.get('travel', .35)
    h = V((r.x*k, 0, r.z*k))
    y = r.y*spec.get('airScale', 1.0) if r.y > 0 else r.y
    limit = spec.get('maxTravel', .22)  # leg units
    if h.length > limit:
        h *= limit/h.length
    return V((h.x, y, h.z))


def deyaw(qs):
    """Remove the body's own turn (the procedural cast yaw spins the whole model instead)."""
    fwd = qs[cm.SEG_INDEX['hips']] @ V((0, 0, -1))
    psi = math.atan2(-fwd.x, -fwd.z)
    q = axis((0, 1, 0), -psi)
    return [(q @ x).normalized() for x in qs]


def action_pose(rig, src, name, f_out, spec, ctx):
    sf = retime(f_out, spec['keys'])
    qs, r = src.at(name, sf)
    if spec.get('deyaw'):
        qs = deyaw(qs)
    r = action_root(r, spec)
    n_out = spec['frames']
    # Blade follows the forearm (the sword extends the arm through the swing) blended with the source wrist.
    fore = qs[cm.SEG_INDEX['foreArmR']] @ cm.DOWN
    set_blade(qs, (blade_dir(qs)*(1-spec.get('follow', .55)) + fore*spec.get('follow', .55)))
    off = V((r.x, r.y, r.z))*rig.leg_length
    details = {k: Quaternion() for k in DETAILS}
    shoulders(rig, details, .10)
    # Feet: source contact positions, locked while planted (no skating); ground the lowest foot.
    h, P = foot_heights(rig, qs, off)
    low = min(h['left'][0], h['right'][0])
    if spec.get('airborne') is None or not (spec['airborne'][0] <= f_out <= spec['airborne'][1]):
        off.y -= low
    elif low < 0:
        off.y -= low
    targets = {}
    for _, side in LEGS:
        lock = ctx['locks'][side](f_out)
        if lock is not None:
            targets[side] = lock
    err = plant(rig, qs, off, details, targets) if targets else 0.0
    if spec.get('bladeUp'):
        w = base.curve(f_out, spec['bladeUp'])
        if w > 0:
            set_blade(qs, blade_dir(qs).lerp(V((.12, 1, .15)).normalized(), w))
    toe_details(rig, qs, off, details)
    clamp_blade(rig, qs, off, details)
    # Start/end: blend into the idle stance (frame 0) so attacks chain from/into the ready pose.
    lead, tail = spec.get('blendIn', 4), spec.get('blendOut', 8)
    wi = 1-smooth(f_out/lead) if lead else 0
    wo = smooth((f_out-(n_out-1-tail))/tail) if tail else 0
    w = max(wi, wo)
    if w > 0:
        iq, ioff, idet, _ = ctx['idle0']
        qs = mix(qs, iq, w)
        off = off.lerp(ioff, w)
        details = {k: cm.slerp(details[k], idet[k], w) for k in DETAILS}
    return qs, off, details, err


def foot_locks(rig, src, name, spec):
    """Per foot: frames where the source foot is low and slow are planted at the position where contact began."""
    n = spec['frames']
    raw = {'left': [], 'right': []}
    for f in range(n):
        sf = retime(f, spec['keys'])
        qs, r = src.at(name, sf)
        if spec.get('deyaw'):
            qs = deyaw(qs)
        r = action_root(r, spec)
        off = V((r.x, r.y, r.z))*rig.leg_length
        h, _ = foot_heights(rig, qs, off)
        low = min(h['left'][0], h['right'][0])
        for _, side in LEGS:
            p = h[side][1].copy(); p.y -= low
            raw[side].append((h[side][0]-low, p))
    locks = {}
    for _, side in LEGS:
        seq = raw[side]
        out = [None]*n
        anchor = None
        for f in range(n):
            height, p = seq[f]
            prev = seq[max(0, f-1)][1]
            speed = (p-prev).length*FPS
            if spec.get('airborne') and spec['airborne'][0] <= f <= spec['airborne'][1]:
                anchor = None
                continue
            if height < .05 and speed < .9:
                if anchor is None:
                    anchor = p.copy(); anchor.y = rig.P0[rig.index[side+'foot']].y
                out[f] = anchor
            else:
                anchor = None
        locks[side] = (lambda o: (lambda f: o[min(len(o)-1, max(0, int(round(f))))]))(out)
    return locks


ATTACKS = {
    # name head "cast" -> not melee (no weapon trail); impact = the palm release (hand speed peak).
    'cast_bolt_h026': dict(src='attack1', frames=30, impact=11),
    'cast_flick_h026': dict(src='attack2', frames=30, impact=11),
}


def attack_spec(rig, src, name, cfg):
    n = src.frames(cfg['src'])
    peak = hand_speed_peak(rig, src, cfg['src'], 8, n-10)
    # Source windup begins ~0.6 s before the peak; recovery settles ~0.9 s after.
    s0 = max(0, peak-20)
    s_end = min(n-1, peak+28)
    keys = [(0, s0), (cfg['impact']-4, peak-5), (cfg['impact'], peak), (cfg['impact']+5, peak+6), (cfg['frames']-1, s_end)]
    return dict(frames=cfg['frames'], keys=keys, impact=cfg['impact'], sourcePeak=peak, follow=0,
                blendIn=4, blendOut=9)


def author(rig, src):
    clips, report = [], {}

    def emit(name, frames, loop, fn, extra):
        c = dict(name=name, frames=frames, loop=loop, rootXZ=1 if not name.endswith(('walk_h026', 'run_h026')) else 0,
                 events={}, rot=[], root=[], detailJoints=DETAILS, detailRot=[], **extra)
        prev, pd, errs = [None]*15, [None]*len(DETAILS), []
        for f in range(frames):
            qs, off, details, err = fn(f)
            for i, q in enumerate(qs):
                vals, prev[i] = base.pack(q, prev[i]); c['rot'] += vals
            c['root'] += [round(x/rig.leg_length, 5) for x in off]
            for i, role in enumerate(DETAILS):
                vals, pd[i] = base.pack(details[role], pd[i]); c['detailRot'] += vals
            errs.append(err)
        clips.append(c)
        first, _, _, _ = fn(0)
        last, _, _, _ = fn(frames if loop else frames-1)
        report[name] = dict(frames=frames, maxIKClampMm=round(max(errs)*1000, 2),
                            endToStartDegrees=round(max(cm.quat_angle_deg(a, b) for a, b in zip(first, last)), 3))
        return c

    ctx = idle_context(rig, src)
    idle_frames = 120
    emit('idle_h026', idle_frames, True, lambda f: idle_pose(rig, src, f/idle_frames, ctx), {})
    ctx['idle0'] = idle_pose(rig, src, 0, ctx)
    for state in ('walk', 'run'):
        ctx.update(loco_context(rig, src, state))
        s, p = ctx[state+'_loop']
        emit(f'{state}_h026', p, True, lambda f, st=state, pp=p: loco_pose(rig, src, f/pp, ctx, st),
             {'groundSpeed': round(ctx[state+'_speed'], 3)})
        report[f'{state}_h026'].update(loopStart=s, period=p, seamScore=round(ctx[state+'_seam'], 2),
                                       groundSpeed=ctx[state+'_speed'])
    for name, cfg in ATTACKS.items():
        spec = attack_spec(rig, src, name, cfg)
        actx = dict(ctx, locks=foot_locks(rig, src, cfg['src'], spec))
        c = emit(name, spec['frames'], False, lambda f, sp=spec, cf=cfg, a=actx: action_pose(rig, src, cf['src'], f, sp, a),
                 {'melee': False})
        c['events'] = {'impact': spec['impact'], 'end': spec['frames']-1}
        report[name].update(sourcePeak=spec['sourcePeak'], keys=spec['keys'])
    peaks = {'s1_fan_push': hand_speed_peak(rig, src, 's1_fan', 8, src.frames('s1_fan')-12),
             's2_throw_push': hand_speed_peak(rig, src, 's2_throw', 8, src.frames('s2_throw')-12),
             'ult_push': hand_speed_peak(rig, src, 'ult', 30, src.frames('ult')-12),
             'ult_raise': max(5, hand_speed_peak(rig, src, 'ult', 4, 28)+6)}
    report['castPeaks'] = peaks
    for name, spec in CASTS.items():
        spec = dict(spec)
        spec['keys'] = spec['keys_fn'](peaks)
        actx = dict(ctx, locks=foot_locks(rig, src, spec['src'], spec))
        c = emit(name, spec['frames'], False, lambda f, sp=spec, a=actx: action_pose(rig, src, sp['src'], f, sp, a),
                 {'melee': False})
        c['events'] = {'impact': spec['impact'], 'end': spec['frames']-1}
        report[name].update(keys=spec['keys'])
    return clips, report


# Skill casts (full body). impact = the gameplay effect moment (cast clip starts castLead before it).
# Cast clips start castLead (0.12 s) before `impact`, so impact=4 starts them at ~frame 0.4 (= the cast tick).
CASTS = {
    # S1 forked lightning: both palms push forward at impact (cast tick + castLead).
    'cast_fan_h026': dict(src='s1_fan', frames=24, impact=4, travel=0, follow=0, blendIn=2, blendOut=8,
                          keys_fn=lambda s: [(0, s['s1_fan_push']-6), (4, s['s1_fan_push']), (10, s['s1_fan_push']+8), (23, 55)]),
    # S2 ball lightning: overhand throw, release at impact (the projectile leaves at the cast).
    'cast_ball_h026': dict(src='s2_throw', frames=24, impact=4, travel=.3, follow=0, blendIn=2, blendOut=8,
                           keys_fn=lambda s: [(0, s['s2_throw_push']-5), (4, s['s2_throw_push']), (10, s['s2_throw_push']+8), (23, 55)]),
    # ULT: raise the palm to the sky (charging), strike down at +0.45 s = clip frame 4 + 10 = 14.
    'cast_thunder_h026': dict(src='ult', frames=30, impact=4, travel=0, follow=0, blendIn=2, blendOut=8,
                              keys_fn=lambda s: [(0, 4), (5, s['ult_raise']), (11, s['ult_push']-4), (14, s['ult_push']), (20, s['ult_push']+8), (29, 72)]),
}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', default='App/Resources/Heroes/H026MotionClips.json')
    a = p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    hero = str(Path(HERO).resolve())
    rig, meshes, height, warnings = preview.load_hero(hero)
    axis_err = base.bind_usd_axes(rig, hero)
    src = Source(preview.load_clips(SRC))
    clips, report = author(rig, src)
    Path(a.out).write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=clips), separators=(',', ':'))+'\n',
                           encoding='utf-8')
    report['model'] = dict(height=height, bones=len(rig.names), legLength=rig.leg_length, usdAxisDegrees=axis_err, warnings=warnings)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR/'finish-report.json').write_text(json.dumps(report, indent=2, default=str), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'model'}, default=str), flush=True)


if __name__ == '__main__':
    main()
