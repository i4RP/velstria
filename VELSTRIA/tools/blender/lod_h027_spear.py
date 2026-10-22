"""Region-weighted reduction of the regenerated dragon spear (Tripo P1, face_limit 20000) before the standard import.

Blender -b -P tools/blender/lod_h027_spear.py -- --input build/tripo/props/dragonSpear/model_highpoly.glb
  --out build/tripo/props/dragonSpear/model.glb [--head 3500] [--shaft 700] [--head-fraction 0.4]
The hero budget (HeroModelTests: body + weapon < 14,000 triangles; H027's body is 9,342) leaves ~4,600 for the spear.
A uniform reduction spends most of that on the long plain shaft, so the dragon head + blade (top of the long axis)
and the shaft are reduced separately, then re-joined (seam vertices merged). Materials/UVs/textures are kept.
"""
import argparse
import sys

import bmesh
import bpy
from mathutils import Vector


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def decimate_to(obj, target):
    n = tri_count(obj)
    if n <= target:
        return n
    bpy.context.view_layer.objects.active = obj
    m = obj.modifiers.new('dec', 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.use_collapse_triangulate = True
    m.ratio = target / n
    bpy.ops.object.modifier_apply(modifier=m.name)
    # collapse can land a little over; trim once more
    n = tri_count(obj)
    if n > target:
        m = obj.modifiers.new('dec2', 'DECIMATE')
        m.decimate_type = 'COLLAPSE'
        m.use_collapse_triangulate = True
        m.ratio = target / n * 0.995
        bpy.ops.object.modifier_apply(modifier=m.name)
    return tri_count(obj)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--input', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--head', type=int, default=3900)
    p.add_argument('--shaft', type=int, default=300)
    p.add_argument('--head-fraction', type=float, default=0.4)
    a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=a.input)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    before = tri_count(obj)
    # Tripo splits vertices along every UV seam; collapsing the split copies separately opens cracks. Weld first
    # (UVs are per face corner in Blender, so the texture mapping is kept).
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=1e-5)
    bpy.ops.object.mode_set(mode='OBJECT')
    co = [obj.matrix_world @ v.co for v in obj.data.vertices]
    ext = [max(c[i] for c in co) - min(c[i] for c in co) for i in range(3)]
    axis = ext.index(max(ext))
    lo, hi = min(c[axis] for c in co), max(c[axis] for c in co)
    # head end = the end with the wider cross-section (dragon head + blade), measured over the outer 30 %
    def width(a0, a1):
        sel = [c for c in co if a0 <= c[axis] <= a1]
        others = [i for i in range(3) if i != axis]
        return max((max(c[i] for c in sel) - min(c[i] for c in sel)) for i in others) if sel else 0
    L = hi - lo
    top_is_head = width(hi - 0.3 * L, hi) >= width(lo, lo + 0.3 * L)
    cut = hi - a.head_fraction * L if top_is_head else lo + a.head_fraction * L
    # split faces by centre along the long axis
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    for f in bm.faces:
        c = obj.matrix_world @ f.calc_center_median()
        f.select = (c[axis] >= cut) if top_is_head else (c[axis] <= cut)
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    parts = [o for o in bpy.data.objects if o.type == 'MESH']
    head = max(parts, key=lambda o: tri_count(o) if o != obj else -1) if len(parts) > 1 else obj
    head = [o for o in parts if o != obj][0]
    shaft = obj
    nh = decimate_to(head, a.head)
    ns = decimate_to(shaft, a.shaft)
    bpy.ops.object.select_all(action='DESELECT')
    head.select_set(True)
    shaft.select_set(True)
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=1e-5)
    bpy.ops.object.mode_set(mode='OBJECT')
    after = tri_count(obj)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=a.out, export_format='GLB', use_selection=True)
    print(f'[spear-lod] {before} -> {after} triangles (head {nh}, shaft {ns}), axis {axis}, head at {"max" if top_is_head else "min"}', flush=True)


if __name__ == '__main__':
    main()
