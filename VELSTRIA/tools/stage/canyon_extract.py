"""Blender half of import_canyon.py; extracts source geometry, not game entities."""
import bpy,json,sys,numpy as np
from pathlib import Path
root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(root/'source/map.fbx'))
(root/'meshes').mkdir(exist_ok=True)
meta=[]
for o in bpy.data.objects:
 if o.type!='MESH' or not o.data.materials:continue
 m=o.data.materials[0]
 imgs=[n.image for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and '_N.' not in n.image.name] if m and m.use_nodes else []
 if not imgs:continue
 tex=Path(imgs[0].filepath.replace('\\','/')).name
 mesh=o.data;mesh.calc_loop_triangles()
 co=np.empty(len(mesh.vertices)*3,dtype=np.float32);mesh.vertices.foreach_get('co',co);co=co.reshape(-1,3)
 mat=np.array(o.matrix_world);co=co@mat[:3,:3].T+mat[:3,3]
 if np.max(np.abs(co))>1000:continue
 corners=np.array([l.vertex_index for l in mesh.loops]);tri=np.array([t.loops[:] for t in mesh.loop_triangles]).reshape(-1)
 norm=np.array([n.vector[:] for n in mesh.corner_normals]);norm=norm@np.linalg.inv(mat[:3,:3]);norm/=np.maximum(np.linalg.norm(norm,axis=1,keepdims=True),1e-8)
 uv=np.array([u.uv[:] for u in mesh.uv_layers.active.data]) if mesh.uv_layers.active else np.zeros((len(mesh.loops),2))
 idx=len(meta);np.savez(root/'meshes'/f'{idx}.npz',p=co[corners[tri]],n=norm[tri],uv=uv[tri])
 meta.append(dict(id=idx,name=o.name,texture=tex,material=m.name,origin=mat[:3,3].tolist(),lo=co.min(0).tolist(),hi=co.max(0).tolist(),uvlo=uv.min(0).tolist(),uvhi=uv.max(0).tolist()))
(root/'meshes.json').write_text(json.dumps(meta,indent=2))
print('EXTRACTED',len(meta))
