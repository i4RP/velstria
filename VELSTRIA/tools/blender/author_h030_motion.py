"""H030 Raina (star cannon) idle / walk / run / basic attack on the shipped 65-joint rig.

Meshy prime takes supply the body texture (walk bounce, attack/ult recoil shape);
cannon grip, the free hand, planted feet and the shot timing are explicit constraints.
Writes App/Resources/Heroes/H030MotionClips.json (15 segments + sparse local details).
Run from VELSTRIA: blender -b -P tools/blender/author_h030_motion.py [-- --preview [--video]]
"""
import argparse
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_h025_motion as base
import clip_math as cm
import preview_clip as preview

V = Vector
FPS = 30
HERO = 'App/Resources/Heroes/Hero_H030.usdz'
OUT = Path('build/h030-motion')
DETAILS = base.DETAILS
axis, curve, smooth = base.axis, base.curve, base.smooth

# Runtime contract (HeroMotionSets "H030"): weapon = handR * GRIP, then shifted by
# WEAPON_OFFSET along the cannon's own axes, so the palm rests on top of the barrel.
GRIP = Quaternion((1, 0, 0), -math.pi/2)
WEAPON_OFFSET = V((0, 0, -.16))
CANNON_SCALE = 1.08
MUZZLE = 1.0*CANNON_SCALE
# Attack: 36 frames, shot at frame 11 (runtime retimes pre/post to the simulation).
ATTACK_FRAMES, SHOT = 36, 11
WALK = dict(speed=1.0, duration=.96, contact=.60, lift=.075, bounce=.026, drop=-.055)
RUN = dict(speed=2.4, duration=.62, contact=.44, lift=.13, bounce=.045, drop=-.105)


def cannon_quat(d, u):
    d = d.normalized()
    u = (u - d*u.dot(d)).normalized()
    x = d.cross(u)
    return Matrix((x, d, u)).transposed().to_quaternion()


def wave(t, k=1, phase=0):
    return math.sin(math.tau*(k*t+phase))


def sources():
    clips = {}
    for name in ('h030_cannon_attack_prime', 'h030_ult_beam_prime', 'h030_cannon_walk_prime'):
        path = Path(f'tools/motion/{name}.json')
        if not path.is_file():
            raise SystemExit(f'missing {path}; extract the saved Meshy task first (docs/H030_MOTION.md)')
        clips.update(preview.load_clips(str(path)))
    return clips


def prime_body(src, frame, ref_frame, limits, weight):
    """Rotation of hips/torso/head relative to the take's first frame, bounded."""
    q, _ = cm.interp_clip(src, frame)
    q0, _ = cm.interp_clip(src, ref_frame)
    out = []
    for i, limit in enumerate(limits):
        delta = q[i] @ q0[i].inverted()
        w = min(1, math.radians(limit)/max(1e-6, delta.angle))*weight
        out.append(cm.slerp(Quaternion(), delta, w))
    return out


def hold_pose(state, t):
    """Cannon placement (center of the barrel at the grip, muzzle dir, up) + body knobs."""
    p = dict(C=V((.215, 1.10, -.10)), d=V((-.17, -.10, -1)), u=V((0, 1, 0)), twoHands=True,
             yaw=-.10, lean=0., hipsY=-.035, headPitch=-.10, headYaw=-.08, headRoll=.05, recoil=0., brace=0.,
             trigger=0., stance='square')
    if state == 'idle':
        b = wave(t)
        p.update(C=V((.235, 1.035+.006*b, -.075)), d=V((-.13, -.36, -1)), twoHands=False,
                 yaw=-.13+.015*wave(t, 1, .2), hipsY=-.03+.004*b, headPitch=-.16+.02*wave(t, 1, .1),
                 headYaw=-.17+.03*wave(t, 1, .35), headRoll=.10+.02*wave(t, 1, .6), stance='idle')
    elif state == 'walk':
        p.update(C=V((.215, 1.10, -.11)), d=V((-.17, -.13, -1)), yaw=-.09, lean=.04, headPitch=-.06, headYaw=-.04, headRoll=.02)
    elif state == 'run':
        # Pull the cannon in to the body; lean into the run.
        p.update(C=V((.20, 1.14, -.06)), d=V((-.15, -.20, -1)), yaw=-.07, lean=.17, headPitch=.06, headYaw=-.02, headRoll=0)
    elif state == 'attack':
        aim = curve(t*(ATTACK_FRAMES-1), [(0, 0), (8, 1), (24, 1), (35, 0)])
        brace = curve(t*(ATTACK_FRAMES-1), [(0, 0), (7, 0), (10.5, 1), (16, .7), (35, 0)])
        recoil = curve(t*(ATTACK_FRAMES-1), [(0, 0), (SHOT, 0), (SHOT+1.5, 1), (SHOT+6, .3), (28, 0), (35, 0)])
        ready = hold_pose('walk', 0)
        C = ready['C'].lerp(V((.20, 1.15, -.17)), aim) + V((.01, .025, .085))*recoil
        d = ready['d'].normalized().lerp(V((-.13, .02, -1)).normalized(), aim)
        d = d + V((0, .14, 0))*recoil
        p.update(C=C, d=d, yaw=-.09-.06*aim+.03*recoil, lean=.04+.05*aim-.11*recoil, hipsY=-.035-.03*brace-.012*recoil,
                 headPitch=-.06+.05*aim+.04*recoil, headYaw=-.04+.03*aim, headRoll=.02-.02*aim,
                 recoil=recoil, brace=brace, trigger=curve(t*(ATTACK_FRAMES-1), [(0, 0), (SHOT-2, 0), (SHOT, 1), (SHOT+4, 1), (20, 0)]),
                 stance='brace')
    return p


def make_pose(rig, src, state, t):
    move = state in ('walk', 'run')
    g = rig.gripR
    p = hold_pose(state, t)
    # Body (hips/torso/head) — authored, plus bounded Meshy prime texture.
    qs = [Quaternion() for _ in range(15)]
    texture = [Quaternion()]*3
    if state == 'attack':
        f = t*(ATTACK_FRAMES-1)
        # Prime take: fire around source f40; compress to SHOT, follow-through after.
        sf = curve(f, [(0, 8), (SHOT, 40), (24, 60), (35, 89)])
        texture = prime_body(src['meshy_h030_cannon_attack_prime'], sf, 8, (3, 5, 4), math.sin(math.pi*t)**2)
    elif move:
        walk = src['meshy_h030_cannon_walk_prime']
        texture = prime_body(walk, (t % 1)*walk['frames']*.5, 0, (2, 2.5, 2), .6 if state == 'walk' else .35)
    breath = wave(t, 1) if state == 'idle' else 0
    hipsYaw = p['yaw']*.35 + (.03*wave(t, 1) if move else 0)
    qs[0] = texture[0] @ axis((0, 1, 0), hipsYaw) @ axis((0, 0, 1), (.025*wave(t, 1, .25) if state == 'idle' else 0))
    qs[1] = texture[1] @ axis((0, 1, 0), p['yaw']) @ axis((1, 0, 0), -p['lean']-.012*breath)
    qs[2] = texture[2] @ axis((0, 1, 0), p['headYaw']) @ axis((1, 0, 0), p['headPitch']) @ axis((0, 0, 1), -p['headRoll'])
    offset = V((.012*wave(t, 1, .25) if state == 'idle' else 0, p['hipsY'], 0))

    details = {r: Quaternion() for r in DETAILS if r in rig.index}

    # Feet: planted (idle/attack) or in-place stride cancelling the travel speed.
    gait = WALK if state == 'walk' else RUN
    reach = gait['speed']*gait['duration']*gait['contact']/2
    if move:
        offset.y = gait['drop'] - gait['bounce']*(1-math.cos(t*math.tau*2))*.5
    errors = []
    for side, suffix, phase in [('right', 'R', t), ('left', 'L', t+.5)]:
        j = rig.index[side+'foot']
        target = rig.P0[j].copy()
        sx = 1 if side == 'right' else -1
        target.x = sx*.10
        roll = 0
        if p['stance'] == 'idle':
            # weight shifts to the right leg and back; left knee relaxed
            target.x = sx*.115
            target.z += .03 if side == 'right' else -.05
        elif p['stance'] == 'brace':
            target.x = sx*(.115+.02*p['brace'])
            target.z += .07 if side == 'right' else -.09
        elif move:
            u = phase % 1
            c = gait['contact']
            if u < c:
                v = u/c
                target.z = -reach+2*reach*v
                roll = .16*smooth((v-.8)/.2)
            else:
                v = (u-c)/(1-c)
                tangent = 2*reach*(1-c)/c
                target.z = reach-2*reach*smooth(v)+tangent*(2*v**3-3*v*v+v)
                target.y += gait['lift']*math.sin(math.pi*v)**2
                roll = .16*(1-smooth(v))-.08*math.sin(math.pi*v)
            if roll > 0:
                target.y += .06*math.sin(roll)
            details[side+'toebase'] = base.local_delta(rig, side+'toebase', axis((1, 0, 0), -roll*.65))
        qs[cm.SEG_INDEX['foot'+suffix]] = axis((1, 0, 0), roll) @ rig.seg_C('foot'+suffix).inverted()
        errors.append(base.ik(rig, qs, offset, details, [side+'upleg', side+'leg', side+'foot'],
                              ['thigh'+suffix, 'shin'+suffix], target, V((0, 0, -1))))

    # Cannon follows the upper body: author in torso-relative space, then apply the torso yaw/lean.
    torso = qs[1]
    pivot = V((0, 1.05, 0)) + offset
    def body(v):
        return pivot + torso @ (v - V((0, 1.05, 0)))
    bob = V((0, .01*wave(t, 2, .1), 0)) if move else V()
    C = body(p['C']) + bob
    d = (torso @ p['d']).normalized()
    u = torso @ p['u']
    W = cannon_quat(d, u)
    u = W @ V((0, 0, 1))
    side_x = W @ V((1, 0, 0))
    palmR = C - W @ WEAPON_OFFSET
    wristR = palmR + u*g
    qs[5] = (W @ GRIP.inverted()).normalized()
    errors.append(base.ik(rig, qs, offset, details, ['rightarm', 'rightforearm', 'righthand'],
                          ['armR', 'foreArmR'], wristR, V((1, -.2, .6))))
    if p['twoHands']:
        # Left hand on the left flank of the barrel, fingers forward and down.
        palmL = C + d*.10 - side_x*.15 + u*.03
        fingers = (d*.55 - u*.75 + side_x*.2).normalized()
        qs[8] = cm.rotation_between(cm.DOWN, fingers)
        wristL = palmL - fingers*rig.gripL
        pole = V((-1, -.6, .3))
    else:
        # Free hand on the hip; small finger taps.
        wristL = V((-.185, 1.055+.004*breath, .005)) + offset
        qs[8] = cm.rotation_between(cm.DOWN, V((.55, -.8, -.25)).normalized())
        pole = V((-1, .1, .5))
    if move:
        wristL += bob
    errors.append(base.ik(rig, qs, offset, details, ['leftarm', 'leftforearm', 'lefthand'],
                          ['armL', 'foreArmL'], wristL, pole))

    # Shoulders absorb the recoil; slight shrug with breath.
    for side, sign in [('left', -1), ('right', 1)]:
        lift = .02*breath + (.10*p['recoil'] if side == 'right' else .05*p['recoil'])
        details[side+'shoulder'] = base.local_delta(rig, side+'shoulder',
            axis((0, 0, 1), sign*lift) @ axis((0, 1, 0), -sign*.05*p['recoil']))
    # Fingers: right closed on the grip (index squeezes on the shot), left cupped on the barrel
    # or, on the hip, tapping lightly.
    for side, sign in [('left', -1), ('right', 1)]:
        for finger in ('thumb', 'index', 'middle', 'ring', 'pinky'):
            for n in (1, 2, 3):
                role = side+'hand'+finger+str(n)
                if role not in rig.index:
                    continue
                if side == 'right':
                    deg = ([18, 26, 18] if finger == 'thumb' else [52, 70, 45])[n-1]
                    if finger == 'index':
                        deg = [32, 45, 30][n-1] + [16, 24, 16][n-1]*p['trigger']
                elif p['twoHands']:
                    deg = ([10, 15, 10] if finger == 'thumb' else [24, 32, 20])[n-1]
                else:
                    k = {'index': 0, 'middle': .12, 'ring': .24, 'pinky': .36, 'thumb': .5}[finger]
                    tap = max(0, wave(t, 3, k))**3
                    deg = ([12, 16, 10] if finger == 'thumb' else [18, 26, 16])[n-1] + (14 if finger != 'thumb' else 4)*tap
                details[role] = base.local_delta(rig, role, axis((0, 0, -sign), math.radians(deg)))
    return qs, offset/rig.leg_length, details, max(errors), dict(C=C, d=d, u=u, W=W)


def grips(rig):
    def g(side):
        hand, finger = rig.index[side+'hand'], rig.index.get(side+'handindex1')
        return .06 if finger is None else .6*(rig.P0[finger]-rig.P0[hand]).length
    rig.gripR, rig.gripL = g('right'), g('left')


def author(rig, src, out):
    clips, report = [], {}
    tasks = json.loads(Path('docs/MOTION_H030_API.json').read_text(encoding='utf-8'))['tasks'] if Path('docs/MOTION_H030_API.json').is_file() else []
    ids = {t['name']: t['task_id'] for t in tasks}
    for state, frames, loop in [('idle', 96, True), ('walk', round(WALK['duration']*FPS), True),
                                ('run', round(RUN['duration']*FPS), True), ('attack', ATTACK_FRAMES, False)]:
        name = 'gun_cannon_h030' if state == 'attack' else state+'_h030'
        srcname = {'attack': 'h030_cannon_attack_prime', 'walk': 'h030_cannon_walk_prime', 'run': 'h030_cannon_walk_prime'}.get(state)
        c = dict(name=name, source=(f"meshy:prime:{ids.get(srcname, '?')}+" if srcname else '')+'local:H030-cannon-finish',
                 frames=frames, loop=loop, rootXZ=0, melee=False, events={}, rot=[], root=[],
                 detailJoints=[r for r in DETAILS if r in rig.index], detailRot=[])
        if state == 'attack':
            c['events'] = dict(impact=SHOT, release=SHOT, end=ATTACK_FRAMES-1)
        if state in ('walk', 'run'):
            c['groundSpeed'] = (WALK if state == 'walk' else RUN)['speed']
        prev, pd = [None]*15, [None]*len(c['detailJoints'])
        errors, muzzle = [], []
        for f in range(frames):
            t = f/(frames if loop else frames-1)
            qs, root, details, err, cannon = make_pose(rig, src, state, t)
            for i, q in enumerate(qs):
                vals, prev[i] = base.pack(q, prev[i]); c['rot'] += vals
            c['root'] += [round(x, 6) for x in root]
            for i, role in enumerate(c['detailJoints']):
                vals, pd[i] = base.pack(details[role], pd[i]); c['detailRot'] += vals
            errors.append(err)
            muzzle.append(cannon['C'] + cannon['d']*MUZZLE)
        clips.append(c)
        a = make_pose(rig, src, state, 0)[0]
        b = make_pose(rig, src, state, 1)[0]
        r = dict(frames=frames, maxTargetClampMm=round(max(errors)*1000, 3),
                 loopOrEndpointDegrees=round(max(cm.quat_angle_deg(x, y) for x, y in zip(a, b)), 3))
        if state == 'attack':
            m = muzzle[SHOT]
            r['muzzleAtShot'] = [round(x, 3) for x in m]
            r['muzzleDirAtShot'] = [round(x, 3) for x in make_pose(rig, src, state, SHOT/(frames-1))[4]['d']]
        report[name] = r
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(dict(version=1, fps=FPS, segments=cm.SEGMENTS, clips=clips), separators=(',', ':'))+'\n', encoding='utf-8')
    return clips, report


# ---------- preview (Blender pose preview with a cannon proxy of the game dimensions) ----------

def cannon_proxy():
    mat = bpy.data.materials.new('CannonWhite'); mat.diffuse_color = (.92, .92, .95, 1)
    gold = bpy.data.materials.new('CannonGold'); gold.diffuse_color = (.8, .62, .2, 1)
    glow = bpy.data.materials.new('CannonGlow'); glow.diffuse_color = (.4, .9, 1, 1)
    parts = []
    def cyl(r, y0, y1, m):
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=r*CANNON_SCALE, depth=(y1-y0)*CANNON_SCALE)
        o = bpy.context.object; o.data.materials.append(m)
        o.data.transform(Matrix.Rotation(-math.pi/2, 4, 'X'))
        o.data.transform(Matrix.Translation(V((0, (y0+y1)/2*CANNON_SCALE, 0))))
        parts.append(o)
    cyl(.155, -.27, .34, mat)
    cyl(.07, -.55, -.27, gold)
    cyl(.03, .34, 1.0, glow)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=.085*CANNON_SCALE, location=(0, .04*CANNON_SCALE, .15*CANNON_SCALE))
    o = bpy.context.object; o.data.materials.append(glow); parts.append(o)
    for s in (-1, 1):
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.object; o.data.materials.append(gold)
        o.data.transform(Matrix.Diagonal(V((.05, .74, .1, 1))*CANNON_SCALE))
        o.data.transform(Matrix.Translation(V((s*.085*CANNON_SCALE, .65*CANNON_SCALE, 0))))
        parts.append(o)
    return parts


def apply_clip(rig, clip, frame, parts):
    from preview_h025_motion import details_at
    qs, root = cm.interp_clip(clip, frame)
    offset = V((0, root.y, 0))*rig.leg_length
    dR, pos = base.solve(rig, qs, offset, details_at(clip, frame))
    rig.apply_pose(dR, pos)
    W = (qs[5] @ GRIP).normalized()
    hand = pos[rig.index['righthand']] + qs[5] @ V((0, -rig.gripR, 0)) + W @ WEAPON_OFFSET
    for o in parts:
        o.matrix_world = preview.hero_to_world(rig, Matrix.LocRotScale(hand, W, V((1, 1, 1))))
    bpy.context.view_layer.update()


def render_sheets(clips, video=False):
    rig, meshes, height, _ = preview.load_hero(str(Path(HERO).resolve()))
    base.bind_usd_axes(rig, str(Path(HERO).resolve()))
    grips(rig)
    report = {}
    for view in ('34', 'side', 'overhead'):
        label = preview.setup_scene(rig, 1.95, view, (320, 400))
        label.data.size *= .7
        parts = cannon_proxy()
        for name in ('idle_h030', 'walk_h030', 'run_h030', 'gun_cannon_h030'):
            clip = clips[name]
            frames = [0, 6, 9, 11, 12, 13, 15, 20, 26, 35] if name.startswith('gun') else preview.sample_frames(clip, 8)
            files, ground = [], []
            for i, f in enumerate(frames):
                apply_clip(rig, clip, f, parts)
                label.data.body = f'{name} f{f:.1f}'
                path = OUT/'sheets'/f'{name}_{view}_{i:02d}.png'
                path.parent.mkdir(parents=True, exist_ok=True)
                bpy.context.scene.render.filepath = str(path.resolve())
                bpy.ops.render.render(write_still=True)
                files.append(str(path.resolve())); ground.append(round(preview.lowest_highest(meshes, rig.M)[0], 4))
            preview.tile_images(files, str((OUT/f'finished_{name}_{view}.png').resolve()), (320, 400), 5)
            report[f'{name}/{view}'] = dict(ground=ground)
        for o in parts:
            bpy.data.objects.remove(o)
    (OUT/'preview_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)


def render_video(clips, baseline):
    """Side-by-side Blender pose comparison: shipped library clips (before) vs the H030 finish (after)."""
    fps, tile = 24, (420, 520)
    timeline = [('idle', 3, 3.2), ('walk', 2, WALK['duration']), ('run', 2, RUN['duration']),
                ('attack', 3.6, 1.2), ('attack_fast', 2.4, .6)]
    folders = {}
    for side, hero in (('before', OUT/'Hero_H030_original.usdz'), ('after', Path(HERO))):
        rig, meshes, height, _ = preview.load_hero(str(hero.resolve()))
        base.bind_usd_axes(rig, str(hero.resolve()))
        grips(rig)
        label = preview.setup_scene(rig, 1.95, '34', tile)
        label.data.size *= .65
        parts = cannon_proxy()
        folder = OUT/'video_frames'/side
        shutil.rmtree(folder, ignore_errors=True); folder.mkdir(parents=True)
        n = 0
        for state, seconds, cycle in timeline:
            if side == 'before':
                name = {'idle': 'ready_idle', 'walk': 'walk_basic', 'run': 'run_basic'}.get(state, 'gun_fire')
                clip = baseline.get(name)
            else:
                name = 'gun_cannon_h030' if state.startswith('attack') else state+'_h030'
                clip = clips[name]
            for i in range(round(seconds*fps)):
                x = (i/fps/cycle) % 1
                if clip is not None:
                    apply_clip(rig, clip, x*(clip['frames'] if clip.get('loop') else clip['frames']-1), parts)
                label.data.body = (f"BEFORE: shared library clip '{name}'\n(+ procedural gait in game)" if side == 'before'
                                   else f'AFTER: {name}') + f'\n{state} / Blender pose preview'
                bpy.context.scene.render.filepath = str((folder/f'{n:04d}.png').resolve())
                bpy.ops.render.render(write_still=True)
                n += 1
        for o in parts:
            bpy.data.objects.remove(o)
        folders[side] = folder
    ffmpeg = shutil.which('ffmpeg')
    out = OUT/'H030_motion_comparison.mp4'
    subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', str(fps), '-i', str(folders['before']/'%04d.png'),
                    '-framerate', str(fps), '-i', str(folders['after']/'%04d.png'), '-filter_complex', '[0:v][1:v]hstack=inputs=2[v]',
                    '-map', '[v]', '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p', str(out)], check=True)
    print('COMPARISON_VIDEO='+str(out.resolve()), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', default='App/Resources/Heroes/H030MotionClips.json')
    parser.add_argument('--preview', action='store_true')
    parser.add_argument('--video', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    rig, meshes, height, warnings = preview.load_hero(str(Path(HERO).resolve()))
    axis_error = base.bind_usd_axes(rig, HERO)
    grips(rig)
    clips, report = author(rig, sources(), Path(args.out))
    report['model'] = dict(height=height, bones=len(rig.names), gripR=rig.gripR, gripL=rig.gripL,
                           importedVsUSDJointAxesDegrees=axis_error, warnings=warnings)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'finish-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)
    lib = {c['name']: c for c in clips}
    if args.preview:
        render_sheets(lib)
    if args.video:
        render_video(lib, preview.load_clips('App/Resources/Heroes/HeroMotionClips.json'))


if __name__ == '__main__':
    main()
