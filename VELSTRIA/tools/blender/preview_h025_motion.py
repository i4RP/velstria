"""H025 contact sheets and Blender comparison footage (not a game/FPS capture).

Run from VELSTRIA with Blender -b -P tools/blender/preview_h025_motion.py --
  --hero App/Resources/Heroes/Hero_H025.usdz [--video] [--only attack]
The bow is a geometry approximation using the game's dimensions and grip math.
The pose solver, sparse local details and clip samples match the runtime format.
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
import author_h025_motion as author
import clip_math as cm
import preview_clip as preview

V = Vector
OUT = Path('build/h025-motion')
GOLD = (.54, .38, .12, 1)
LIGHT = (.48, .84, 1, 1)


def qaxis(axis, angle):
    return Quaternion(axis, angle)


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    return mat


def make_bow():
    # YZ crescent; runtime bakes yaw +0.6 into the mesh itself.
    verts, faces = [], []
    yaw = qaxis((0, 1, 0), .6)
    for i in range(33):
        a = -.95 + 1.9*i/32
        for x, r in [(-.0275, .78), (.0275, .78), (.0275, .72), (-.0275, .72)]:
            verts.append(yaw @ V((x, math.sin(a)*r, .76-math.cos(a)*r)))
    for i in range(32):
        for k in range(4):
            faces.append((i*4+k, i*4+(k+1)%4, (i+1)*4+(k+1)%4, (i+1)*4+k))
    mesh = bpy.data.meshes.new('CrescentBowApproximation')
    mesh.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new('CrescentBowApproximation', mesh)
    bpy.context.collection.objects.link(ob)
    mesh.materials.append(material('MoonSilverGold', GOLD))
    strings = []
    for i in range(2):
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=.0035, depth=1)
        string = bpy.context.object
        string.name = 'Bowstring'+str(i)
        string.data.materials.append(material('MoonString'+str(i), LIGHT))
        strings.append(string)
    return ob, strings


def details_at(clip, frame):
    names = clip.get('detailJoints', [])
    data = clip.get('detailRot', [])
    count = clip['frames']
    f = frame % count if clip.get('loop') else min(count-1, max(0, frame))
    a = int(f); b = (a+1) % count if clip.get('loop') else min(count-1, a+1)
    def get(f, i):
        x, y, z, w = data[(f*len(names)+i)*4:(f*len(names)+i+1)*4]
        return Quaternion((w, x, y, z)).normalized()
    return {name: cm.slerp(get(a, i), get(b, i), f-a) for i, name in enumerate(names)}


def apply(rig, clip, frame, bow, strings, before=False):
    qs, root = cm.interp_clip(clip, frame)
    kxz = clip.get('rootXZ', 0)
    offset = V((root.x*kxz, root.y, root.z*kxz))*rig.leg_length
    dR, pos = author.solve(rig, qs, offset, details_at(clip, frame))
    rig.apply_pose(dR, pos)
    def grip(side):
        hand = rig.index[side+'hand']
        finger = rig.index.get(side+'handindex1')
        return .06 if finger is None else .6*(rig.P0[finger]-rig.P0[hand]).length
    left = pos[rig.index['lefthand']] + qs[8] @ V((0, -grip('left'), 0))
    right = pos[rig.index['righthand']] + qs[5] @ V((0, -grip('right'), 0))
    index = rig.index.get('righthandindex3')
    middle = rig.index.get('righthandmiddle3')
    if not before and index is not None and middle is not None:
        right = (pos[index]+pos[middle])*.5
    rot = qs[1] if before else qs[8] @ qaxis((1, 0, 0), -math.pi/2) @ qaxis((0, 1, 0), -.6)
    bow.matrix_world = preview.hero_to_world(rig, Matrix.LocRotScale(left, rot, V((1, 1, 1))))
    yaw = qaxis((0, 1, 0), .6)
    top = yaw @ V((0, math.sin(.9405)*.78, .76-math.cos(.9405)*.78))
    bottom = yaw @ V((0, -math.sin(.9405)*.78, .76-math.cos(.9405)*.78))
    rest = left + rot @ ((top+bottom)*.5)
    release = clip.get('events', {}).get('release')
    draw = clip.get('events', {}).get('drawStart', 5)
    contact = author.smooth(frame/max(.001, draw)) if not before and release is not None and frame < release else 0
    nock = rest+(right-rest)*contact
    for string, local in zip(strings, [top, bottom]):
        end = left+rot@local
        delta = end-nock
        orient = V((0, 0, 1)).rotation_difference(delta.normalized())
        string.matrix_world = preview.hero_to_world(rig, Matrix.LocRotScale((end+nock)*.5, orient, V((1, 1, delta.length))))
    bpy.context.view_layer.update()
    return pos


def setup(hero, tile=(384, 480), view='34'):
    rig, meshes, height, warnings = preview.load_hero(str(Path(hero).resolve()))
    author.bind_usd_axes(rig, str(Path(hero).resolve()))
    label = preview.setup_scene(rig, max(height, 1.95), view, tile)
    label.data.size *= .7
    bow, strings = make_bow()
    return rig, meshes, label, bow, strings


def sheets(hero, clips, only=None):
    rig, meshes, label, bow, strings = setup(hero)
    report = {}
    for state in ['idle', 'walk', 'run', 'attack']:
        if only and state != only:
            continue
        name = 'h025_bow_attack' if state == 'attack' else 'h025_'+state
        clip = clips[name]
        frames = [0, 5, 13, 20, 24, 25, 28, 35, clip['frames']-1] if state == 'attack' else preview.sample_frames(clip, 8 if state != 'idle' else 4)
        files, ground = [], []
        for i, frame in enumerate(frames):
            apply(rig, clip, frame, bow, strings)
            label.data.body = f'H025 {state} / frame {frame:.1f}\nBlender pose preview'
            path = OUT/'sheets'/f'{state}_{i:02d}.png'
            path.parent.mkdir(parents=True, exist_ok=True)
            bpy.context.scene.render.filepath = str(path.resolve())
            bpy.ops.render.render(write_still=True)
            files.append(str(path.resolve())); ground.append(preview.lowest_highest(meshes, rig.M)[0])
        output = OUT/f'finished_{state}.png'
        preview.tile_images(files, str(output), (384, 480), 3 if state == 'attack' else 4)
        report[state] = {'sheet':str(output),'frames':frames,'groundMinMeters':min(ground),'groundMaxMeters':max(ground),'groundPerFrameMeters':ground}
    (OUT/'preview_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)


def video(hero, clips, baseline):
    # Equal cycle lengths aid pose comparison; no simulator timing is implied.
    timeline = [('idle', 2), ('attack', 4.5)]
    fps, tile = 24, (480, 560)
    for before in [True, False]:
        side = 'before' if before else 'after'
        model = OUT/'Hero_H025_original.usdz' if before and (OUT/'Hero_H025_original.usdz').exists() else hero
        rig, meshes, label, bow, strings = setup(model, tile)
        folder = OUT/'video_frames'/side
        folder.mkdir(parents=True, exist_ok=True)
        number = 0
        for state, seconds in timeline:
            name = {'idle':'ready_idle','walk':'walk_basic','run':'run_basic','attack':'bow_shot_b'}[state] if before else ('h025_bow_attack' if state == 'attack' else 'h025_'+state)
            clip = (baseline if before else clips)[name]
            cycle = 1.5 if state == 'attack' else 2 if state == 'idle' else 1.1 if state == 'walk' else .8
            for i in range(round(seconds*fps)):
                fraction = (i/fps/cycle) % 1
                frame = fraction*(clip['frames'] if clip.get('loop') else clip['frames']-1)
                apply(rig, clip, frame, bow, strings, before)
                label.data.body = f'{side.upper()}: {"library source" if before else "H025 finish"}\n{state.upper()} / Blender preview'
                if before and state in ('walk', 'run'):
                    label.data.body += '\nReference clip, not old procedural gait'
                path = folder/f'{number:04d}.png'
                bpy.context.scene.render.filepath = str(path.resolve())
                bpy.ops.render.render(write_still=True)
                number += 1
    output = OUT/'H025_motion_comparison.mp4'
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        raise SystemExit('ffmpeg not found; rendered PNG sequences are retained')
    subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', str(fps),
        '-i', str(OUT/'video_frames/before/%04d.png'), '-framerate', str(fps),
        '-i', str(OUT/'video_frames/after/%04d.png'), '-filter_complex', '[0:v][1:v]hstack=inputs=2[v]',
        '-map', '[v]', '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(output)], check=True)
    print('COMPARISON_VIDEO='+str(output.resolve()), flush=True)
    # The old H025 gait was procedural and is not reproducible from the clip
    # library. Show new locomotion separately instead of inventing a baseline.
    rig, meshes, label, bow, strings = setup(hero, tile, 'side')
    folder = OUT/'video_frames/locomotion'
    folder.mkdir(parents=True, exist_ok=True)
    number = 0
    for state, cycle in [('walk', 1.1), ('run', .8)]:
        clip = clips['h025_'+state]
        for i in range(2*fps):
            frame = ((i/fps/cycle)%1)*clip['frames']
            apply(rig, clip, frame, bow, strings)
            label.data.body = f'H025 {state.upper()} / side view\nBlender pose preview'
            bpy.context.scene.render.filepath = str((folder/f'{number:04d}.png').resolve())
            bpy.ops.render.render(write_still=True)
            number += 1
    subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', str(fps),
        '-i', str(folder/'%04d.png'), '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart', str(OUT/'H025_locomotion.mp4')], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--hero', default='App/Resources/Heroes/Hero_H025.usdz')
    parser.add_argument('--clips', default='App/Resources/Heroes/H025MotionClips.json')
    parser.add_argument('--only', choices=['idle','walk','run','attack'])
    parser.add_argument('--video', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    OUT.mkdir(parents=True, exist_ok=True)
    clips = preview.load_clips(args.clips)
    sheets(args.hero, clips, args.only)
    if args.video:
        video(args.hero, clips, preview.load_clips('App/Resources/Heroes/HeroMotionClips.json'))


if __name__ == '__main__':
    main()
