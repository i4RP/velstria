"""H034 Gorm (chain hook) motion finishing on the shipped 65-joint rig (Blender 5.2).

Sources (build/h034-motion, tools/h034_motion_api.mjs → extract_h034_prime.py / extract_clips.py):
  Meshy prime  attack / hook / slam / ult  → body, arm and wrist rotations (time-remapped to KitTimes)
  Tripo v3     walk / run presets          → torso and head texture of the gait
  Meshy prime  idle                         → reference only (too restless for a loop; idle is authored)
Constraints applied on top: planted wide feet (IK), in-place gait whose support foot cancels the
ground speed, steady right-hand grip on the hook, left hand at the belly / on the chain, finger fists,
clavicle and toe roll. Writes 15 world segments + sparse local detail tracks (HeroDetailRotations).
Run from VELSTRIA: Blender -b --factory-startup -P tools/blender/author_h034_motion.py
"""
import json
import math
import sys
from pathlib import Path

from mathutils import Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clip_math as cm  # noqa: E402
import preview_clip as preview  # noqa: E402
from author_h025_motion import bind_usd_axes, curve, ik, local_delta, pack, smooth  # noqa: E402

V = Vector
FPS = 30
HERO = 'App/Resources/Heroes/Hero_H034.usdz'
DETAILS = ['leftshoulder', 'rightshoulder', 'lefttoebase', 'righttoebase']
DETAILS += [s+'hand'+f+str(n) for s in ('left', 'right') for f in ('thumb', 'index', 'middle', 'ring', 'pinky') for n in (1, 2, 3)]
SEG = cm.SEG_INDEX

# Gait: ground speed (m/s) at which the clip plays at 1x; the runtime scales rate = speed / groundSpeed,
# so the planted foot never slides at any (passive-boosted) speed.
GAIT = {'walk': dict(frames=27, speed=1.3, contact=.62, lift=.07, drop=.075, bob=.018),
        'run': dict(frames=19, speed=2.6, contact=.44, lift=.12, drop=.115, bob=.035)}
STANCE_X, STANCE_Z = .265, (.06, -.05)     # wide planted stance: |x| and z of right / left ankle
GAIT_X = .215                               # feet still land wide while moving


def ax(a, t):
    return Quaternion(a, t)


def yaw(t):
    return ax((0, 1, 0), t)


def fingers(rig, side, curl, thumb):
    """Local post-rest finger deltas: curl 0 = rest (straight), 1 = closed fist around a handle."""
    sign = 1 if side == 'right' else -1
    out = {}
    for finger in ('thumb', 'index', 'middle', 'ring', 'pinky'):
        for n in (1, 2, 3):
            role = side+'hand'+finger+str(n)
            if role not in rig.index:
                continue
            if finger == 'thumb':
                deg = [28, 30, 22][n-1]*thumb
            else:
                deg = [62, 88, 58][n-1]*curl + (8 if finger == 'pinky' else 0)*curl
            out[role] = local_delta(rig, role, ax((0, 0, -sign), math.radians(deg)))
    return out


def shoulders(rig, raise_r, raise_l, fwd_r=0., fwd_l=0.):
    return {'rightshoulder': local_delta(rig, 'rightshoulder', ax((0, 1, 0), fwd_r) @ ax((0, 0, 1), raise_r)),
            'leftshoulder': local_delta(rig, 'leftshoulder', ax((0, 1, 0), -fwd_l) @ ax((0, 0, 1), -raise_l))}


def plant_feet(rig, qs, offset, details, targets, rolls=(0, 0), toe_out=.22):
    errors = []
    for (side, suffix), target, roll in zip((('right', 'R'), ('left', 'L')), targets, rolls):
        s = 1 if side == 'right' else -1
        qs[SEG['foot'+suffix]] = yaw(-s*toe_out) @ ax((1, 0, 0), roll) @ rig.seg_C('foot'+suffix).inverted()
        details[side+'toebase'] = local_delta(rig, side+'toebase', ax((1, 0, 0), -max(0, roll)*.7))
        errors.append(ik(rig, qs, offset, details, [side+'upleg', side+'leg', side+'foot'],
                         ['thigh'+suffix, 'shin'+suffix], target, V((s*.45, 0, -1))))
    return errors


def stance_targets(rig, spread=0.):
    out = []
    for side, z in (('right', STANCE_Z[0]), ('left', STANCE_Z[1])):
        s = 1 if side == 'right' else -1
        p = rig.P0[rig.index[side+'foot']].copy()
        p.x = s*(STANCE_X+spread)
        p.z = z
        out.append(p)
    return out


def arm_ik(rig, qs, offset, details, side, target, pole):
    suffix = 'R' if side == 'right' else 'L'
    return ik(rig, qs, offset, details, [side+'arm', side+'forearm', side+'hand'], ['arm'+suffix, 'foreArm'+suffix], target, pole)


# MARK: - poses

def ready_pose(rig, t, breath_amp=1.):
    """The heavy guard: wide knees-out stance, chest forward, hook steady at the right hip, left hand at the belly.
    t in [0, 1) is the breath phase (one breath per idle loop)."""
    b = math.sin(t*math.tau)*breath_amp            # inhale > 0
    b2 = math.sin(t*math.tau*2+.6)*breath_amp      # small secondary settle (still periodic in t)
    qs = [Quaternion() for _ in range(15)]
    qs[0] = yaw(-.10) @ ax((1, 0, 0), -.06) @ ax((0, 0, 1), .012*b2)
    qs[1] = yaw(-.06) @ ax((1, 0, 0), -.13+.035*b) @ ax((0, 0, 1), -.01*b2)
    qs[2] = yaw(.12) @ ax((1, 0, 0), .10-.04*b)
    offset = V((.008*b2, -.085+.006*b, 0))
    details = {r: Quaternion() for r in DETAILS if r in rig.index}
    details.update(shoulders(rig, .05+.045*b, .05+.045*b, .03, .03))
    details.update(fingers(rig, 'right', 1, 1))
    details.update(fingers(rig, 'left', .55, .6))
    errors = plant_feet(rig, qs, offset, details, stance_targets(rig))
    # Right fist rests forward of the hip: hook hangs forward-down, steady (moves only with the chest).
    hip_r = rig.P0[rig.index['rightupleg']]
    right = V((hip_r.x+.235, .80+.012*b, -.20))
    left = V((-.07, .93+.016*b, -.36))
    qs[SEG['handR']] = yaw(-.25) @ ax((1, 0, 0), -.75)
    qs[SEG['handL']] = yaw(.9) @ ax((0, 0, 1), -1.15) @ ax((1, 0, 0), .35)
    errors.append(arm_ik(rig, qs, offset, details, 'right', right, V((1, .2, .7))))
    errors.append(arm_ik(rig, qs, offset, details, 'left', left, V((-1, -.3, .6))))
    return qs, offset, details, max(errors)


def detect_period(clip, seg='thighR'):
    """Frames of one full gait cycle (autocorrelation of the thigh direction)."""
    n, i = clip['frames'], SEG[seg]
    dirs = [cm.interp_clip(clip, f)[0][i] @ cm.DOWN for f in range(n)]
    best, period = -1e9, n
    for p in range(12, n):
        score = sum(dirs[f].dot(dirs[(f+p) % n]) for f in range(n)) / n
        if score > best + 1e-4:
            best, period = score, p
        if score > .995:
            return p
    return period


def gait_pose(rig, src, period, state, t):
    g = GAIT[state]
    run = state == 'run'
    wave = math.sin(t*math.tau)                  # +: right foot forward half
    step = math.cos(t*math.tau*2)                # twice per cycle (each foot strike)
    sq, _ = cm.interp_clip(src, (t*period) % src['frames'])
    qs = [Quaternion() for _ in range(15)]
    lean = .30 if run else .08
    # Weight carried side to side over the stance foot; the source torso adds texture only.
    roll = (.055 if run else .075)*wave
    qs[0] = yaw(-.10*wave) @ ax((0, 0, 1), -.6*roll) @ ax((1, 0, 0), -.4*lean)
    qs[1] = cm.slerp(Quaternion(), sq[1], .25) @ yaw(.12*wave-.04) @ ax((1, 0, 0), -lean) @ ax((0, 0, 1), roll)
    qs[2] = yaw(-.05*wave+.06) @ ax((1, 0, 0), .55*lean+.04) @ ax((0, 0, 1), -.6*roll)
    offset = V((.022*wave, -g['drop']-g['bob']*(1-step)/2, 0))
    details = {r: Quaternion() for r in DETAILS if r in rig.index}
    errors = []
    contact, speed, duration = g['contact'], g['speed'], g['frames']/FPS
    reach = speed*duration*contact/2
    targets, rolls = [], []
    for side, phase in (('right', t), ('left', t+.5)):
        s = 1 if side == 'right' else -1
        target = rig.P0[rig.index[side+'foot']].copy()
        target.x = s*GAIT_X
        u = phase % 1
        if u < contact:
            v = u/contact
            target.z = -reach+2*reach*v
            r = .18*smooth((v-.75)/.25)
        else:
            v = (u-contact)/(1-contact)
            tangent = 2*reach*(1-contact)/contact
            target.z = reach-2*reach*smooth(v)+tangent*(2*v**3-3*v*v+v)
            target.y += g['lift']*math.sin(math.pi*v)**2
            target.x += s*.03*math.sin(math.pi*v)   # swing foot arcs out around the belly
            r = .18*(1-smooth(v))-.10*math.sin(math.pi*v)
        if r > 0:
            target.y += .06*math.sin(r)
        targets.append(target)
        rolls.append(r)
    errors += plant_feet(rig, qs, offset, details, targets, rolls, toe_out=.16)
    details.update(fingers(rig, 'right', 1, 1))
    details.update(fingers(rig, 'left', .5 if not run else .8, .6))
    hip_r = rig.P0[rig.index['rightupleg']]
    if run:
        # Hook pulled in against the right ribs, left fist pumping against the stride.
        right = V((hip_r.x+.20, .90+.01*step, -.17-.02*wave))
        left = V((-.30, .96-.03*wave, -.20+.17*wave))
        qs[SEG['handL']] = ax((1, 0, 0), .9+.3*wave)
        details.update(shoulders(rig, .07, .05+.03*wave, .06, .05*wave))
    else:
        right = V((hip_r.x+.24, .79+.008*step, -.19-.015*wave))
        left = V((-.33, .80+.02*max(0, wave), -.04+.13*wave))
        qs[SEG['handR']] = yaw(-.25) @ ax((1, 0, 0), -.45)
        qs[SEG['handL']] = ax((1, 0, 0), .25+.25*wave)
        details.update(shoulders(rig, .04, .03, .03, .03*wave))
    errors.append(arm_ik(rig, qs, offset, details, 'right', right, V((1, .2, .7))))
    errors.append(arm_ik(rig, qs, offset, details, 'left', left, V((-1, -.2, .3))))
    if run:
        # Hook hauled up against the body, its head resting back by the right shoulder (clear of legs and belly).
        from author_h025_motion import solve
        _, P = solve(rig, qs, offset, details)
        forearm = (P[rig.index['righthand']]-P[rig.index['rightforearm']]).normalized()
        qs[SEG['handR']] = weapon_hand(V((.32, .78, .55+.05*wave)), forearm)
    return qs, offset, details, max(errors)


# MARK: - actions from Meshy prime

def solve_hand(rig, qs, root_m, side='right'):
    from author_h025_motion import solve
    _, P = solve(rig, qs, root_m, {})
    return P[rig.index[side+'hand']]


def hips_yaw(q):
    """Heading from the left-right axis (stays defined when the chest bows forward into the slam)."""
    r = q @ V((1, 0, 0))
    return math.atan2(-r.z, r.x)


def stabilized(src, f, keep=.25):
    """Source segments with most of the whole-body yaw removed: prime takes spin the hips to throw/slam;
    the game turns the hero itself, so only `keep` of that turn stays (twist above the hips is kept)."""
    sq, root = cm.interp_clip(src, f)
    turn = yaw(-(1-keep)*hips_yaw(sq[0]))
    return [turn @ q for q in sq], root


def weapon_hand(w, forearm):
    """Hand segment rotation whose fist grip (+Y prop → hand -Z) points the hook along w,
    with the knuckle axis (hand DOWN) as close to the forearm as the grip allows."""
    from mathutils import Matrix
    z = -w.normalized()
    y = -forearm + z*forearm.dot(z)
    if y.length < 1e-4:
        y = V((0, 1, 0)) - z*z.y
    y.normalize()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_quaternion()


def slam_weapon(f, armline):
    """Hook direction during the slam (output frames: peak 9, impact 13): it trails back-down behind the
    shoulder in the wind-up, whips in line with the arm, and points into the ground at the impact."""
    trail = curve(f, [(0, 0), (5, .6), (9, 1.1), (11, .4), (13, 0), (36, 0)])
    dig = curve(f, [(0, 0), (11, 0), (13, .9), (18, .7), (28, .2), (36, 0)])
    return (armline + V((0, -.8, .9))*trail + V((0, -1, -.5))*dig).normalized()


def keyed_weapon(trail_keys, dig_keys):
    """slam_weapon with per-clip keys: trail = hook hanging back-down behind the shoulder (wind-up),
    dig = hook driven down-forward into the ground (impact)."""
    def weapon(f, armline):
        trail = curve(f, trail_keys)
        dig = curve(f, dig_keys)
        return (armline + V((0, -.8, .9))*trail + V((0, -1, -.5))*dig).normalized()
    return weapon


def analyse_slam(rig, src):
    """Wind-up peak (right hand highest) and impact (lowest right hand after the peak) of a prime take."""
    n = src['frames']
    hands = [solve_hand(rig, stabilized(src, f)[0], V((0, 0, 0))) for f in range(n)]
    peak = max(range(int(n*.15), int(n*.75)), key=lambda f: hands[f].y)
    impact = min(range(peak, min(n, peak+30)), key=lambda f: hands[f].y)
    # The hook lands in front, a little right of the centre line (the right hand's slam).
    d = hands[impact]
    return peak, impact, math.atan2(-d.x, -d.z) + math.atan2(.12, .55)


def action_pose(rig, src, keys, out_keys, f, face, blend_in, blend_out, n_out, extra=None, weapon=None):
    """Prime body/arms remapped so out_keys[i] lands on source keys[i]; wide planted feet; edges blend to ready."""
    sf = curve(f, list(zip(out_keys, keys)))
    sq, sroot = stabilized(src, sf)
    ready, roff, rdet, _ = ready_pose(rig, 0)
    w = smooth(f/blend_in)*(1-smooth((f-(n_out-1-blend_out))/blend_out))
    qs = [Quaternion() for _ in range(15)]
    turn = yaw(-face)
    for i in range(9):
        qs[i] = cm.slerp(ready[i], turn @ sq[i], w)
    base_root = cm.interp_clip(src, keys[0])[1]
    offset = roff.copy()
    offset.y += w*min(.0, (sroot.y-base_root.y)*rig.leg_length)
    details = {r: Quaternion() for r in DETAILS if r in rig.index}
    details.update(rdet)
    if extra:
        extra(qs, offset, details, f)
    errors = plant_feet(rig, qs, offset, details, stance_targets(rig, .03*w))
    if weapon:
        from author_h025_motion import solve
        _, P = solve(rig, qs, offset, details)
        sh, el, ha = (P[rig.index['right'+j]] for j in ('arm', 'forearm', 'hand'))
        aim = weapon(f, (ha-sh).normalized())
        qs[SEG['handR']] = cm.slerp(ready[SEG['handR']], weapon_hand(aim, (ha-el).normalized()), w)
    details.update(fingers(rig, 'right', 1, 1))
    return qs, offset, details, max(errors)


# MARK: - authoring

def bake(rig, name, source, frames, loop, pose_at, events=None, extra=None):
    c = dict(name=name, source=source, frames=frames, loop=loop, rootXZ=0, events=events or {}, rot=[], root=[],
             detailJoints=[r for r in DETAILS if r in rig.index], detailRot=[])
    c.update(extra or {})
    prev, pd, errors = [None]*15, [None]*len(c['detailJoints']), []
    for f in range(frames):
        qs, offset, details, err = pose_at(f)
        for i, q in enumerate(qs):
            vals, prev[i] = pack(q, prev[i])
            c['rot'] += vals
        c['root'] += [round(x/rig.leg_length, 6) for x in offset]
        for i, role in enumerate(c['detailJoints']):
            vals, pd[i] = pack(details.get(role, Quaternion()), pd[i])
            c['detailRot'] += vals
        errors.append(err)
    a = pose_at(0)[0]
    b = pose_at(frames)[0] if loop else pose_at(frames-1)[0]
    return c, dict(frames=frames, maxTargetClampMm=round(max(errors)*1000, 2),
                   seamDegrees=round(max(cm.quat_angle_deg(x, y) for x, y in zip(a, b)), 3))


def main():
    rig, _, height, warnings = preview.load_hero(str(Path(HERO).resolve()))
    axis_error = bind_usd_axes(rig, HERO)
    prime = preview.load_clips('tools/motion/h034-prime-source-clips.json')
    tripo = preview.load_clips('tools/motion/h034-tripo-source-clips.json')
    ids = json.load(open('build/h034-motion/api-state.json'))['tasks']
    pid = {k: ids['prime_'+k]['task_id'] for k in ('attack', 'hook', 'slam', 'ult')}
    tid = ids['H034_idle_walk_run']['task_id']
    clips, report = [], {}

    def add(item):
        c, r = item
        clips.append(c)
        report[c['name']] = r

    idle_frames = 132     # 4.4 s, one breath (HeroIdle's chainCaptain period)
    add(bake(rig, 'idle_h034', 'local:H034-authored-guard (meshy prime idle reference)', idle_frames, True,
             lambda f: ready_pose(rig, f/idle_frames)))
    for state in ('walk', 'run'):
        src = tripo['tripo_h034_'+state]
        period = detect_period(src)
        g = GAIT[state]
        report['period_'+state] = period
        add(bake(rig, state+'_h034', f'tripo:{tid}:{state}+local:H034-contact-finish', g['frames'], True,
                 lambda f, s=state, src=src, p=period: gait_pose(rig, src, p, s, f/g['frames']),
                 extra=dict(groundSpeed=g['speed'])))

    # Normal attack: wind-up → slam on frame 13 → hand-over-hand recovery, back to the guard by frame 36.
    src = prime['prime_attack_h034']
    peak, impact, face = analyse_slam(rig, src)
    start, end = max(0, peak-24), min(src['frames']-1, impact+34)
    report['attack_source'] = dict(peak=peak, impact=impact, faceDeg=round(math.degrees(face), 1), start=start, end=end)
    n = 37
    add(bake(rig, 'chain_slam_h034', f'meshy:prime:{pid["attack"]}+local:H034-contact-finish', n, False,
             lambda f: action_pose(rig, src, [start, peak-6, peak, impact, impact+12, end], [0, 5, 9, 13, 21, 36],
                                   f, face, 3, 9, n, weapon=slam_weapon),
             events=dict(impact=13, end=36)))

    # Skills: frame 0 = the cast (castFromStart), the impact event sits on the KitTimes delay at 30 fps.
    # S1 鎖鉤: wind-up behind → overhead throw, the hook leaves the hand at hookDelay 0.33 s (frame 10) →
    # arm held out along the chain → hand-over-hand haul back (miss). A hit restarts on hook_pull_h034.
    src = prime['prime_hook_h034']
    face = analyse_slam(rig, src)[2]
    add(bake(rig, 'hook_throw_h034', f'meshy:prime:{pid["hook"]}+local:H034-contact-finish', 46, False,
             lambda f: action_pose(rig, src, [18, 30, 39, 42, 50, 62, 81, 87], [0, 5, 8, 10, 16, 27, 40, 45], f, face, 2, 8, 46,
                                   weapon=keyed_weapon([(0, 0), (5, 1), (8, .6), (10, 0), (45, 0)], [(0, 0), (45, 0)])),
             events=dict(impact=10, end=45)))
    # Hit: chain held taut for hookHold 0.45 s (13.5 frames), yanked during hookPull 0.25 s (to frame 21), back to guard.
    add(bake(rig, 'hook_pull_h034', f'meshy:prime:{pid["hook"]}+local:H034-contact-finish', 34, False,
             lambda f: action_pose(rig, src, [54, 63, 66, 81, 87], [0, 12, 14, 21, 33], f, face, 1, 8, 34,
                                   weapon=keyed_weapon([(0, 0), (33, 0)], [(0, 0), (33, 0)])),
             events=dict(impact=21, end=33)))
    # S2 鉄鎖旋: crouch, both hands up over the head, slam on shockDelay 0.27 s (frame 8).
    src = prime['prime_slam_h034']
    face = analyse_slam(rig, src)[2]
    add(bake(rig, 'chain_smash_h034', f'meshy:prime:{pid["slam"]}+local:H034-contact-finish', 31, False,
             lambda f: action_pose(rig, src, [3, 18, 27, 32, 50, 72], [0, 4, 6, 8, 18, 30], f, face, 2, 9, 31,
                                   weapon=keyed_weapon([(0, 0), (4, .8), (6, 1.1), (7, .3), (8, 0), (30, 0)],
                                                       [(0, 0), (7, 0), (8, 1), (16, .7), (30, 0)])),
             events=dict(impact=8, end=30)))
    # 奥義 狩猟鎖獄: grab on ultDelay 0.25 s, then a blow every ultInterval 0.32 s (6 hits: frames 7.5 … 55.5);
    # two source blows alternate (retract between), the last one is the big overhead smash; quick recovery.
    src = prime['prime_ult_h034']
    face = analyse_slam(rig, src)[2]
    beats = [7.5 + 9.6*k for k in range(6)]
    out_keys = [0, beats[0]]
    src_keys = [3, 18]
    for k, b in enumerate(beats[1:5]):
        out_keys += [b - 4.6, b]
        src_keys += [(38, 45), (55, 60)][k % 2]
    out_keys += [beats[5] - 5, beats[5], 63, 69]
    src_keys += [72, 84, 92, 102]
    dips = sorted(set([(0, 0)] + [(b - 2.5, 0) for b in beats] + [(b, .8 if i < 5 else 1.2) for i, b in enumerate(beats)] + [(69, 0)]))
    add(bake(rig, 'chain_frenzy_h034', f'meshy:prime:{pid["ult"]}+local:H034-contact-finish', 70, False,
             lambda f: action_pose(rig, src, src_keys, out_keys, f, face, 2, 8, 70,
                                   weapon=keyed_weapon([(0, 0), (69, 0)], dips)),
             events=dict(impact=7.5, end=69)))

    out = Path('App/Resources/Heroes/H034MotionClips.json')
    out.write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=clips), separators=(',', ':'))+'\n')
    report['model'] = dict(height=height, bones=len(rig.names), axisErrorDeg=axis_error, warnings=warnings)
    Path('build/h034-motion/finish-report.json').write_text(json.dumps(report, indent=1))
    print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
