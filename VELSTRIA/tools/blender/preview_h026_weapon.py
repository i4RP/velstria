"""H026 stills: old vs new ball lightning prop, and the hero holding the new prop (idle / walk / skill).

Run from VELSTRIA: blender -b -P tools/blender/preview_h026_weapon.py -- --old <old Prop usdz>
Blender pose preview with the runtime solver (not a game capture). The prop is placed like the runtime
weaponGrip (fistGrip: prop +Y -> hand segment -Z) at an approximate in-game length.
"""
import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_h025_motion as base
import clip_math as cm
import preview_clip as preview
from preview_h025_motion import details_at

OUT = Path('build/h026-motion/weapon')
HERO = str(Path('App/Resources/Heroes/Hero_H026.usdz').resolve())
NEW = str(Path('App/Resources/Heroes/Prop_ballLightning.usdz').resolve())
FIST = Quaternion((1, 0, 0), -1.5707963)
LENGTH = 0.38  # approximate displayed height (m)


def import_prop(path, name):
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = root
        o.matrix_world = mw
    for o in new:
        if o.type != 'MESH':
            bpy.data.objects.remove(o)
    return root


def still(path, label, text):
    label.data.body = text
    bpy.context.scene.render.filepath = str(path.resolve())
    bpy.ops.render.render(write_still=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--old', required=True)
    a = p.parse_args(sys.argv[sys.argv.index('--')+1:])
    OUT.mkdir(parents=True, exist_ok=True)
    rig, meshes, height, _ = preview.load_hero(HERO)
    base.bind_usd_axes(rig, HERO)
    label = preview.setup_scene(rig, max(height, 1.95), '34', (720, 900))
    label.data.size *= .6
    clips = preview.load_clips('App/Resources/Heroes/H026MotionClips.json')
    sword = import_prop(NEW, 'NewSword')
    # Hero files are Y-up in USD; Blender's USD import converts to Z-up. hero_to_world maps hero space.
    for name, clip, frame in [('idle', 'idle_h026', 0), ('walk', 'walk_h026', 10), ('skill_s1_fan', 'cast_fan_h026', 6),
                              ('skill_ult', 'cast_thunder_h026', 8), ('attack', 'cast_bolt_h026', 11)]:
        c = clips[clip]
        qs, root = cm.interp_clip(c, frame)
        k = c.get('rootXZ', 0)
        off = Vector((root.x*k, root.y, root.z*k))*rig.leg_length
        dR, P = base.solve(rig, qs, off, details_at(c, frame))
        rig.apply_pose(dR, P)
        hand = P[rig.index['righthand']] + qs[cm.SEG_INDEX['handR']] @ Vector((0, -.06, 0))
        m = Matrix.LocRotScale(hand + Vector((0, .02, 0)), qs[cm.SEG_INDEX['torso']], Vector((LENGTH,)*3))
        # USD prop is Y-up like hero space; convert through the same hero->world mapping.
        sword.matrix_world = preview.hero_to_world(rig, m) @ Matrix.Rotation(-1.5707963, 4, 'X')
        bpy.context.view_layer.update()
        still(OUT/f'hero_{name}.png', label, f'H026 + new ball lightning / {name}')
    # Sword-only comparison (front of the blade).
    for o in meshes:
        o.hide_render = True
    old = import_prop(str(Path(a.old).resolve()), 'OldSword')
    for ob, other, tag in [(old, sword, 'old'), (sword, old, 'new')]:
        other.hide_render = True
        for ch in other.children:
            ch.hide_render = True
        ob.hide_render = False
        for ch in ob.children:
            ch.hide_render = False
        ob.matrix_world = Matrix.Translation((0, 0, .5)) @ Matrix.Scale(1.4, 4)
        bpy.context.view_layer.update()
        still(OUT/f'sword_{tag}.png', label, f'{tag.upper()} Prop_ballLightning')


if __name__ == '__main__':
    main()
