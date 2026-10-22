"""H029: graft the Tripo v3 finger chains onto the production v1 rig (Blender 5.x).

The production H029 skin (Tripo v1 rig, 23 joints) drapes the cape and armor well but has
no fingers, so the hand cannot close on the maul handle. The v3 repair (65 joints) has fingers
but reweights the whole body (the cape flares in deep bends). This keeps every v1 joint and
weight, adds only the 30 finger joints at the v3 positions (children of the v1 hands), and
moves only the finger share of the v3 weights onto vertices the v3 skin binds to fingers.
Same mesh, UVs and textures (no regeneration).

blender -b -P tools/blender/graft_h029_fingers.py -- <v1.glb> <v3.glb> <out.glb>
"""
import sys

import bpy
from mathutils.kdtree import KDTree

v1_path, v3_path, out_path = sys.argv[sys.argv.index('--') + 1:][:3]
bpy.ops.wm.read_factory_settings(use_empty=True)


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path, import_pack_images=True, guess_original_bind_pose=True, merge_vertices=True)
    new = set(bpy.data.objects) - before
    arm = next(o for o in new if o.type == 'ARMATURE')
    meshes = [o for o in new if o.type == 'MESH']
    body = max(meshes, key=lambda o: len(o.data.polygons))
    return arm, body, [o for o in meshes if o is not body], new


a1, m1, junk1, _ = load(v1_path)
a3, m3, junk3, objs3 = load(v3_path)
finger = lambda n: any(f in n for f in ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky'))
fingers = [b for b in a3.data.bones if finger(b.name)]
assert len(fingers) == 40, len(fingers)

# v3 は同じメッシュを幅 1 へ拡縮し直している（約 0.2%）。外接箱の対応で v3 → v1 の空間へ写す
assert a1.matrix_world == a3.matrix_world


def bounds(o):
    ws = [o.matrix_world @ v.co for v in o.data.vertices]
    return [min(p[i] for p in ws) for i in range(3)], [max(p[i] for p in ws) for i in range(3)]


(lo1, hi1), (lo3, hi3) = bounds(m1), bounds(m3)
to1 = lambda p: p.__class__([lo1[i] + (p[i] - lo3[i]) * (hi1[i] - lo1[i]) / (hi3[i] - lo3[i]) for i in range(3)])
to3 = lambda p: p.__class__([lo3[i] + (p[i] - lo1[i]) * (hi3[i] - lo3[i]) / (hi1[i] - lo1[i]) for i in range(3)])

# 1) 骨: v3 の指を v1 の手の子として同じ位置・向きで足す（アーマチュアの空間はどちらも単位行列）
spec = {b.name: (to1(b.head_local), to1(b.tail_local), b.parent.name, b.matrix_local.copy()) for b in fingers}
bpy.context.view_layer.objects.active = a1
bpy.ops.object.mode_set(mode='EDIT')
eb = a1.data.edit_bones
for b in fingers:  # 親から順（v3 の並びは親が先）
    head, tail, parent, mat = spec[b.name]
    e = eb.new(b.name)
    e.head, e.tail = head, tail
    e.align_roll(mat.to_3x3().col[2])
    e.parent = eb[parent]
    e.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')

# 2) 重み: v3 が指へ割り当てた分だけを移し、残りは v1 の重みを比例で縮める
dg = bpy.context.evaluated_depsgraph_get()
w3 = [m3.matrix_world @ v.co for v in m3.data.vertices]
tree = KDTree(len(w3))
for i, p in enumerate(w3):
    tree.insert(p, i)
tree.balance()
g3 = {g.index: g.name for g in m3.vertex_groups}
for name in spec:
    if name not in m1.vertex_groups:
        m1.vertex_groups.new(name=name)
changed, far = 0, 0
for v in m1.data.vertices:
    p = to3(m1.matrix_world @ v.co)
    _, j, d = tree.find(p)
    if d > 1e-4:
        far += 1
        continue
    share = {g3[g.group]: g.weight for g in m3.data.vertices[j].groups if finger(g3[g.group]) and g.weight > 1e-4}
    total = sum(share.values())
    if total <= 1e-3:
        continue
    k = max(0.0, 1.0 - total)
    for g in v.groups:
        g.weight *= k
    for name, w in share.items():
        m1.vertex_groups[name].add([v.index], w, 'REPLACE')
    changed += 1
print(f'[graft] fingers {len(fingers)} bones, reweighted {changed} vertices, unmatched {far}', flush=True)

# 3) v3 の一式と付属の球を消して書き出す
for o in list(objs3) + junk1:
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', export_skins=True, export_animations=False,
                          export_yup=True, export_apply=False)
print(f'[graft] wrote {out_path}', flush=True)
