"""H033 before/after comparison footage in Blender (pose preview, not a game/FPS capture).

Run from VELSTRIA: blender -b -P tools/blender/preview_h033_motion.py
Left: the clips H033 used before (combat_idle + sword_slash_r / sword_combo_3 / sword_slash_l2 from
HeroMotionClips.json; walk/run were the procedural HeroGait, shown as walk_basic/run_basic references).
Right: H033MotionClips.json. Same runtime solver; the red stick is the greatsword axis (1.3 m).
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_h025_motion as base
import clip_math as cm
import preview_clip as preview
from preview_h025_motion import details_at, material

OUT = Path('build/h033-motion')
HERO = str(Path('App/Resources/Heroes/Hero_H033.usdz').resolve())
FPS = 24
TILE = (480, 560)
# (label, seconds, before clips, after clips)
TIMELINE = [
    ('IDLE', 3, ['combat_idle'], ['idle_h033']),
    ('WALK', 2.5, ['walk_basic'], ['walk_h033']),
    ('RUN', 2, ['run_basic'], ['run_h033']),
    ('ATTACK', 5, ['sword_slash_r', 'sword_combo_3', 'sword_slash_l2'], ['sword_slash_h033', 'sword_chop_h033']),
    ('S1 LEAP', 1.5, [], ['leap_slam_h033']),
    ('S2 SPIN', 1.5, [], ['spin_slash_h033']),
    ('ULT ABSORB', 1.5, [], ['ult_absorb_h033']),
    ('ULT WAVE', 1.5, [], ['ult_wave_h033']),
]


def sword():
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.object
    ob.scale = (.05, .02, 1.3)
    bpy.ops.object.transform_apply(scale=True)
    for v in ob.data.vertices:
        v.co.z -= .65  # grip at origin, blade along -Z (hand segment)
    ob.data.materials.append(material('Greatsword', (.85, .15, .15, 1)))
    return ob


def pose(rig, clip, frame, blade):
    qs, root = cm.interp_clip(clip, frame)
    k = clip.get('rootXZ', 0)
    off = Vector((root.x*k, root.y, root.z*k))*rig.leg_length
    dR, P = base.solve(rig, qs, off, details_at(clip, frame) if clip.get('detailJoints') else {})
    rig.apply_pose(dR, P)
    hand = P[rig.index['righthand']]
    blade.matrix_world = preview.hero_to_world(rig, Matrix.LocRotScale(hand, qs[cm.SEG_INDEX['handR']], Vector((1, 1, 1))))
    bpy.context.view_layer.update()


def clip_frame(clip, t):
    """t seconds into the clip; loops wrap, one-shots play once then hold."""
    n = clip['frames']
    f = t*clip.get('fps', 30)
    return f % n if clip.get('loop') else min(n-1, f)


def render(side, clips):
    rig, meshes, height, _ = preview.load_hero(HERO)
    base.bind_usd_axes(rig, HERO)
    label = preview.setup_scene(rig, max(height, 1.95), '34', TILE)
    label.data.size *= .7
    blade = sword()
    folder = OUT/'video_frames'/side
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    n = 0
    for name, seconds, before, after in TIMELINE:
        names = [x for x in (before if side == 'before' else after) if x in clips]
        total = round(seconds*FPS)
        for i in range(total):
            t = i/FPS
            if names:
                # one-shots in sequence (attack chain); loops play continuously
                c = clips[names[0]]
                if not c.get('loop'):
                    span = [clips[x]['frames']/30 for x in names]
                    k, acc = 0, t
                    while acc >= span[k] and k < len(names)-1:
                        acc -= span[k]; k = (k+1) % len(names)
                    c, t = clips[names[k]], acc
                pose(rig, c, clip_frame(c, t), blade)
                text = f"{'BEFORE (old clips / procedural)' if side == 'before' else 'AFTER: Meshy prime + H033 finish'}\n{name}"
            else:
                pose(rig, clips['idle_h033' if 'idle_h033' in clips else 'combat_idle'], 0, blade)
                text = f'BEFORE\n{name}: procedural FX motion (not shown)'
            label.data.body = text
            bpy.context.scene.render.filepath = str((folder/f'{n:04d}.png').resolve())
            bpy.ops.render.render(write_still=True)
            n += 1


def main():
    clips = preview.load_clips('App/Resources/Heroes/HeroMotionClips.json')
    render('before', clips)
    clips.update(preview.load_clips('App/Resources/Heroes/H033MotionClips.json'))
    render('after', {k: v for k, v in clips.items()})
    ff = shutil.which('ffmpeg')
    out = OUT/'H033_motion_comparison.mp4'
    subprocess.run([ff, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', str(FPS),
                    '-i', str(OUT/'video_frames/before/%04d.png'), '-framerate', str(FPS),
                    '-i', str(OUT/'video_frames/after/%04d.png'), '-filter_complex', '[0:v][1:v]hstack=inputs=2[v]',
                    '-map', '[v]', '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p', str(out)], check=True)
    print('COMPARISON_VIDEO='+str(out.resolve()), flush=True)


if __name__ == '__main__':
    main()
