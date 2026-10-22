"""Still images of H030 holding Prop_starCannon.usdz with the shipped clips (Blender, not the game renderer).

blender -b -P tools/blender/render_h030_cannon.py [-- --prop App/Resources/Heroes/Prop_starCannon.usdz --tag new]
Prop placement follows SkinnedHeroModel.propFit (scale = procedural length / prop length, grip at the origin).
"""
import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_h030_motion as author
import preview_clip as preview

# Procedural starCannon extent along +Y (HeroGear: stock sphere -0.6 .. horn tips 1.02), before weaponScale.
PROCEDURAL_LENGTH = 1.62


def load_prop(path):
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=str(Path(path).resolve()))
    objs = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
    for o in objs:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix()
    def ext(i):
        return [min(v.co[i] for o in objs for v in o.data.vertices), max(v.co[i] for o in objs for v in o.data.vertices)]
    if ext(2)[1]-ext(2)[0] > ext(1)[1]-ext(1)[0]:
        # Blender's USD import turned the Y-up stage to Z-up; return to hero space (Y-up).
        for o in objs:
            o.data.transform(Matrix.Rotation(-math.pi/2, 4, 'X'))
    lo, hi = ext(1)
    s = PROCEDURAL_LENGTH/max(1e-4, hi-lo)*author.CANNON_SCALE
    for o in objs:
        o.data.transform(Matrix.Scale(s, 4))
    return objs, sum(len(p.vertices)-2 for o in objs for p in o.data.polygons)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--prop', default='App/Resources/Heroes/Prop_starCannon.usdz')
    ap.add_argument('--tag', default='new')
    args = ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    clips = preview.load_clips(str(Path('App/Resources/Heroes/H030MotionClips.json').resolve()))
    rig, meshes, height, _ = preview.load_hero(str(Path(author.HERO).resolve()))
    author.base.bind_usd_axes(rig, str(Path(author.HERO).resolve()))
    author.grips(rig)
    parts, tris = load_prop(args.prop)
    shots = [('idle_h030', 20), ('walk_h030', 7), ('run_h030', 5), ('gun_cannon_h030', 12),
             ('cast_s2_h030', 4), ('cast_ult_h030', 18)]
    for view in ('34', 'overhead'):
        label = preview.setup_scene(rig, 1.95, view, (480, 600))
        label.data.size *= .6
        files = []
        for name, frame in shots:
            author.apply_clip(rig, clips[name], frame, parts)
            label.data.body = f'{args.tag}: {name} f{frame}\nprop {tris} tris'
            out = author.OUT/'cannon'/f'{args.tag}_{view}_{name}.png'
            out.parent.mkdir(parents=True, exist_ok=True)
            bpy.context.scene.render.filepath = str(out.resolve())
            bpy.ops.render.render(write_still=True)
            files.append(str(out.resolve()))
        preview.tile_images(files, str((author.OUT/f'cannon_{args.tag}_{view}.png').resolve()), (480, 600), 3)
    print('PROP_TRIANGLES', tris, flush=True)


if __name__ == '__main__':
    main()
