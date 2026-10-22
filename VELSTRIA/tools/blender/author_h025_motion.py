"""H025 motion finishing, on the preserved production rig (Blender 4.5+).

Reuses Meshy prime archery for body/arm roll, then constrains hands
and supporting feet to this character's proportions. No mesh or bind edits.
Writes the runtime's 15 world segments plus sparse local shoulder/toe tracks.
Run from VELSTRIA: blender -b -t 4 -P tools/blender/author_h025_motion.py
"""
import argparse
import json
import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clip_math as cm
import preview_clip as preview

DETAILS = ['leftshoulder', 'rightshoulder', 'lefttoebase', 'righttoebase']
DETAILS += [side+'hand'+finger+str(n) for side in ('left','right')
            for finger in ('thumb','index','middle','ring','pinky') for n in (1,2,3)]
FPS = 30
V = Vector


def axis(a, t):
    return Quaternion(a, t)


def smooth(t):
    t = max(0, min(1, t))
    return t*t*(3-2*t)


def curve(t, points):
    for (a, x), (b, y) in zip(points, points[1:]):
        if t <= b:
            return x + (y-x)*smooth((t-a)/(b-a))
    return points[-1][1]


def sample_loop(clip, t):
    q, root = cm.interp_clip(clip, (t % 1)*clip['frames'])
    # Some library presets include an incomplete last stride. Blend its roll
    # back to the first frame; planted-foot IK below supplies the actual stride.
    if t % 1 > .82:
        first, r0 = cm.interp_clip(clip, 0)
        w = smooth(((t % 1)-.82)/.18)
        q = [cm.slerp(a,b,w) for a,b in zip(q,first)]
        root = root.lerp(r0,w)
    return q, root


def local_delta(rig, role, world_delta):
    j = rig.index[role]
    rest = getattr(rig, 'usd_rest', {}).get(role, rig.qM @ rig.q0w[j])
    return rest.inverted() @ world_delta @ rest


def bind_usd_axes(rig, path):
    """Use the shipped USD joint axes, not Blender's display-bone orientation."""
    from pxr import Usd, UsdGeom, UsdSkel
    stage = Usd.Stage.Open(str(Path(path).resolve()))
    prim = next(p for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton))
    skel = UsdSkel.Skeleton(prim)
    world = UsdGeom.XformCache().GetLocalToWorldTransform(prim)
    rig.usd_rest = {}
    for name, bind in zip(skel.GetJointsAttr().Get(), skel.GetBindTransformsAttr().Get()):
        quat = (bind*world).RemoveScaleShear().ExtractRotationQuat()
        rig.usd_rest[cm.runtime_role(name)] = Quaternion((quat.GetReal(), *quat.GetImaginary()))
    return max(cm.quat_angle_deg(rig.usd_rest[r], rig.qM @ rig.q0w[j])
               for r,j in rig.index.items() if r in rig.usd_rest)


def solve(rig, qs, offset, details):
    """Runtime-compatible solve including LOCAL post-rest detail rotations."""
    dR, P = rig.solve(qs, offset)
    for j in rig.order:
        p = rig.parent[j]
        if p >= 0:
            P[j] = P[p] + dR[p] @ (rig.P0[j]-rig.P0[p])
        else:
            P[j] = rig.P0[j].copy()
        if j == rig.index['hips']:
            P[j] += offset
        role = rig.roles[j]
        if role in details:
            rest = getattr(rig, 'usd_rest', {}).get(role, rig.qM @ rig.q0w[j])
            dR[j] = (dR[p] if p >= 0 else Quaternion()) @ rest @ details[role] @ rest.inverted()
        elif rig.drive[j][0] == 'rest':
            dR[j] = dR[p] if p >= 0 else Quaternion()
    return dR, P


def ik(rig, qs, offset, details, roles, segs, target, pole):
    _, P = solve(rig, qs, offset, details)
    a, b, c = [rig.index[r] for r in roles]
    base = P[a]
    l1, l2 = (rig.P0[b]-rig.P0[a]).length, (rig.P0[c]-rig.P0[b]).length
    toward = target-base
    dist = min(l1+l2-.001, max(abs(l1-l2)+.001, toward.length))
    direction = toward.normalized()
    bend = pole - direction*direction.dot(pole)
    if bend.length < .001:
        bend = V((1, 0, 0))
    bend.normalize()
    along = (l1*l1-l2*l2+dist*dist)/(2*dist)
    elbow = base+direction*along+bend*math.sqrt(max(0, l1*l1-along*along))
    end = base+direction*dist
    for seg, vec in zip(segs, [elbow-base, end-elbow]):
        i = cm.SEG_INDEX[seg]
        qs[i] = (cm.rotation_between(qs[i] @ cm.DOWN, vec) @ qs[i]).normalized()
    return (end-target).length


def make_pose(rig, sources, state, t):
    attack = state == 'attack'
    move = state in ('walk', 'run')
    # A complete preparation/draw/aim/release/recovery, with release on frame 25.
    draw = curve(t, [(0, 0), (.17, .18), (.43, 1), (.5556, 1), (.64, 1), (1, 0)]) if attack else 0
    lift = curve(t, [(0, 0), (.26, 1), (.68, 1), (1, 0)]) if attack else 0
    recoil = curve(t, [(0, 0), (.5556, 0), (.60, 1), (.74, .35), (1, 0)]) if attack else 0
    src = sources['meshy_h025_prime_bow'] if attack else sources.get('tripo_h025_'+state, sources['ready_idle'])
    # Compress the generated 3s take to the game's 1.5s cycle. Its long aim
    # is shortened and source follow-through (f66) meets authored release f25.
    sf = curve(t, [(0,0),(.17,10),(.43,30),(.5556,65),(.64,74),(1,89)]) if attack else t*src['frames']
    sq, _ = cm.interp_clip(src, sf) if attack else sample_loop(src, t)
    body_motion = [Quaternion() for _ in range(3)]
    if attack:
        initial, _ = cm.interp_clip(src, 0)
        aim = cm.ry(-73)
        envelope = math.sin(math.pi*t)**2
        for i, limit in enumerate((6, 12, 5)):
            delta = aim @ (sq[i] @ initial[i].inverted()) @ aim.inverted()
            weight = min(.7, math.radians(limit)/max(1e-6, delta.angle)) * envelope
            body_motion[i] = cm.slerp(Quaternion(), delta, weight)
        sq = [aim @ q for q in sq]
        ready, _ = cm.interp_clip(sources.get('tripo_h025_idle', sources['ready_idle']), 0)
        sq = [cm.slerp(a, b, .65*envelope) for a,b in zip(ready,sq)]
    qs = [q.copy() for q in sq]
    wave = math.sin(t*math.tau)
    breath = math.sin(t*math.tau) if not attack else math.sin(t*math.pi)
    yaw = -.15-.48*lift
    qs[0] = body_motion[0] @ axis((0, 1, 0), yaw*.26)
    qs[1] = body_motion[1] @ axis((0, 1, 0), yaw) @ axis((1, 0, 0), -.018*breath)
    # Keep a little of the captured torso texture without disturbing aim.
    qs[1] = cm.slerp(qs[1], ready[1] if attack else sq[1], .025)
    qs[2] = body_motion[2] @ axis((0, 1, 0), -.035-.10*lift)
    offset = V((.006*wave, -.070+.004*breath, 0))
    details = {r: Quaternion() for r in DETAILS if r in rig.index}
    for side, sign in [('left', -1), ('right', 1)]:
        details[side+'shoulder'] = local_delta(rig, side+'shoulder',
            axis((0, 1, 0), sign*(.015+.055*draw)) @ axis((0, 0, 1), sign*.015*breath))
        # The original 23-bone model cannot close its hands. These channels are
        # applied only on the shape-preserving Tripo finger repair (65 bones).
        for finger in ('thumb','index','middle','ring','pinky'):
            for n in (1,2,3):
                role = side+'hand'+finger+str(n)
                if role not in rig.index:
                    continue
                if side == 'left':
                    degrees = ([20,40,28] if finger=='thumb' else [55,80,55])[n-1]
                else:
                    opening = curve(t, [(0,0),(.5556,0),(.59,1),(.75,1),(1,0)]) if attack else 0
                    base = ([12,20,16] if finger=='thumb' else [15,32,22])[n-1]
                    hook = ([12,25,18] if finger=='thumb' else [35,72,45])[n-1]
                    degrees = (base+(hook-base)*draw)*(1-.85*opening)
                    if finger=='pinky':
                        degrees += 18
                details[role] = local_delta(rig, role, axis((0,0,-sign), math.radians(degrees)))

    # Foot targets are in hero space. During support their world velocity cancels
    # the character's speed. Horizontal root displacement is never exported.
    contact, duration, speed = (.60, 1.1, 1.0) if state != 'run' else (.49, .8, 2.1)
    if move:
        reach = speed*duration*contact/2
        offset.y = (-.230 if state == 'run' else -.130) - (.040 if state == 'run' else .014)*(1-math.cos(t*math.tau*2))
        qs[0] = axis((0, 1, 0), -.035*wave)
        qs[1] = axis((0, 1, 0), -.15+.035*wave) @ axis((1, 0, 0), -.04 if state == 'run' else -.015)
    errors = []
    for side, suffix, phase in [('right', 'R', t), ('left', 'L', t+.5)]:
        j = rig.index[side+'foot']
        target = rig.P0[j].copy()
        target.x = .105 if side == 'right' else -.105
        target.z += .045 if side == 'right' else -.045
        roll = 0
        if move:
            u = phase % 1
            if u < contact:
                v = u/contact
                target.z = -reach+2*reach*v
                roll = .14*smooth((v-.82)/.18)
            else:
                v = (u-contact)/(1-contact)
                tangent = 2*reach*(1-contact)/contact
                target.z = reach-2*reach*smooth(v)+tangent*(2*v**3-3*v*v+v)
                target.y += (.11 if state == 'run' else .055)*math.sin(math.pi*v)**2
                roll = .14*(1-smooth(v))-.07*math.sin(math.pi*v)
            if roll > 0:
                target.y += .07*math.sin(roll)
            details[side+'toebase'] = local_delta(rig, side+'toebase', axis((1, 0, 0), -roll*.65))
        # Flat shoes retain the bind foot orientation, not a shin-locked ankle.
        qs[cm.SEG_INDEX['foot'+suffix]] = axis((1, 0, 0), roll) @ rig.seg_C('foot'+suffix).inverted()
        errors.append(ik(rig, qs, offset, details,
            [side+'upleg', side+'leg', side+'foot'], ['thigh'+suffix, 'shin'+suffix], target, V((0, 0, -1))))

    sway = .002*breath if not move else .004*wave
    left = V((-.145+.065*lift, 1.075+.205*lift+sway, -.235-.15*lift))
    # Pull along the arrow axis; a small rearward recoil reads the release.
    right = V((-.105+.025*lift+.045*recoil, 1.08+.20*lift+sway+.008*recoil, .005+.055*draw+.025*recoil))
    if move:
        left.y += .008*wave
        right.y += .008*wave
    qs[8] = axis((1, 0, 0), math.pi/2)
    qs[5] = axis((1, 0, 0), math.pi/2) @ axis((0, 0, 1), -.10*recoil)
    errors.append(ik(rig, qs, offset, details, ['leftarm', 'leftforearm', 'lefthand'],
                     ['armL', 'foreArmL'], left, V((-.65, -.6, .05))))
    errors.append(ik(rig, qs, offset, details, ['rightarm', 'rightforearm', 'righthand'],
                     ['armR', 'foreArmR'], right, V((1, .1, .45))))
    return qs, offset/rig.leg_length, details, max(errors)


def pack(q, previous):
    q = q.normalized()
    if previous is not None and q.dot(previous) < 0:
        q = cm.neg(q)
    return [round(q.x, 6), round(q.y, 6), round(q.z, 6), round(q.w, 6)], q


def author(rig, sources, out):
    clips, report = [], {}
    for state, frames, loop in [('idle', 90, True), ('walk', 33, True), ('run', 24, True), ('attack', 46, False)]:
        c = dict(name='h025_bow_attack' if state == 'attack' else 'h025_'+state,
                 source='meshy:prime:01a1640b-0d5b-7455-b14f-dfc020cdedee+local:H025-contact-finish' if state == 'attack' else 'tripo:40f57d2f-640f-4c4a-899e-f4d15d50c52a:'+state+'+local:H025-contact-finish',
                 frames=frames, loop=loop, rootXZ=0, melee=False, events={}, rot=[], root=[],
                 detailJoints=[r for r in DETAILS if r in rig.index], detailRot=[])
        if state == 'attack':
            c['events'] = dict(drawStart=5, impact=25, release=25, end=45)
        if state in ('walk', 'run'):
            c['groundSpeed'] = 1.0 if state == 'walk' else 2.1
        prev, pd = [None]*15, [None]*len(c['detailJoints'])
        errors = []
        for f in range(frames):
            t = f/(frames if loop else frames-1)
            qs, root, details, err = make_pose(rig, sources, state, t)
            for i, q in enumerate(qs):
                vals, prev[i] = pack(q, prev[i]); c['rot'] += vals
            c['root'] += [round(x, 6) for x in root]
            for i, role in enumerate(c['detailJoints']):
                vals, pd[i] = pack(details[role], pd[i]); c['detailRot'] += vals
            errors.append(err)
        clips.append(c)
        a, _, _, _ = make_pose(rig, sources, state, 0)
        b, _, _, _ = make_pose(rig, sources, state, 1)
        report[c['name']] = dict(frames=frames, maxTargetClampMm=round(max(errors)*1000, 3),
                                  loopBoundaryDegrees=round(max(cm.quat_angle_deg(x,y) for x,y in zip(a,b)), 3))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=clips), separators=(',', ':'))+'\n', encoding='utf-8')
    return clips, report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', default='App/Resources/Heroes/H025MotionClips.json')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    rig, meshes, height, warnings = preview.load_hero(str(Path('App/Resources/Heroes/Hero_H025.usdz').resolve()))
    axis_error = bind_usd_axes(rig, 'App/Resources/Heroes/Hero_H025.usdz')
    sources = preview.load_clips('App/Resources/Heroes/HeroMotionClips.json')
    tripo = Path('tools/motion/h025-source-clips.json')
    if not tripo.is_file():
        raise SystemExit('Extract the saved Tripo motion task before authoring; see docs/H025_MOTION.md')
    sources.update(preview.load_clips(str(tripo)))
    sources.update(preview.load_clips('tools/motion/h025-prime-source-clips.json'))
    clips, report = author(rig, sources, Path(args.out))
    report['model'] = dict(height=height, bones=len(rig.names), missingFingers='lefthandindex1' not in rig.index,
                           importedVsUSDJointAxesDegrees=axis_error, warnings=warnings)
    Path('build/h025-motion').mkdir(parents=True, exist_ok=True)
    Path('build/h025-motion/finish-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
