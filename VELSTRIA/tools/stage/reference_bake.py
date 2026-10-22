#!/usr/bin/env python3
"""Bake four Tripo field props into one 2048x1024 atlas; no runtime GLB loading.
Run with uv run --with numpy --with pillow python tools/stage/reference_bake.py.
"""
import json, struct, subprocess
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'build/stage/field'; OUT=ROOT/'App/Resources/Stage'
SPECS=[('root_wall',4000,(5,1.7,2)),('camp_crescent',6000,(7,2.1,5)),
       ('camp_gate',6000,(7,2.8,2.5)),('river_wall',2500,(5,.95,.9))]
BLENDER='/Applications/Blender.app/Contents/MacOS/Blender'
atlas=Image.new('RGB',(2048,1024)); headers=[]; chunks=[]; offset=0
for tile,(name,budget,dimensions) in enumerate(SPECS):
    folder=WORK/name; data=(folder/'model.glb').read_bytes(); cursor=12
    while cursor<len(data):
        n,kind=struct.unpack_from('<II',data,cursor);chunk=data[cursor+8:cursor+8+n];cursor+=8+n
        if kind==0x4e4f534a: doc=json.loads(chunk)
        elif kind==0x004e4942: blob=chunk
    texture=doc['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index']
    view=doc['bufferViews'][doc['images'][doc['textures'][texture]['source']]['bufferView']]
    start=view.get('byteOffset',0);(folder/'base_color.png').write_bytes(blob[start:start+view['byteLength']])
    if not (folder/'mesh.npz').exists():
        with (folder/'bake.log').open('w') as log:
            subprocess.run([BLENDER,'-b','--factory-startup','--python-exit-code','1','--python',
                            str(ROOT/'tools/stage/stage_props_blender.py'),'--','bake',
                            '--glb',str(folder/'model.glb'),'--tris',str(budget),'--out',str(folder/'mesh.npz'),
                            '--base-color',str(folder/'base_color.png'),'--bake-out',str(folder/'baked.png'),
                            '--bake-size','1024'],stdout=log,stderr=subprocess.STDOUT,check=True)
    source=np.load(folder/'mesh.npz'); loops=source['tri_loops'].reshape(-1)
    pos=source['co'][source['corner_vert'][loops]].copy();norm=source['corner_normal'][loops].copy()
    uv=source['corner_uv'][loops].copy()
    # Tripo's long ground axis is not guaranteed to be X (these exports use ~Y).
    # Orient the footprint before fitting dimensions; otherwise a thin parapet is
    # stretched across its thickness and becomes a row of spikes in the game.
    _,axes=np.linalg.eigh(np.cov(pos[:,:2].T));axis=axes[:,-1]
    if axis[0]<0:axis=-axis
    rotation=np.column_stack([axis,[-axis[1],axis[0]]])
    pos[:,:2]=pos[:,:2]@rotation;norm[:,:2]=norm[:,:2]@rotation
    lo,hi=pos.min(0),pos.max(0);pos[:,:2]-=(lo[:2]+hi[:2])/2;pos[:,2]-=lo[2]
    # GLB->Blender conversion gives Z up, with the image-facing side at -Y.
    # Normalize only once; placement rotations are explicit in the shared layout.
    scale=np.array([dimensions[0],dimensions[2],dimensions[1]])/(hi-lo)
    pos*=scale;norm/=scale;norm/=np.maximum(np.linalg.norm(norm,axis=1,keepdims=True),1e-8)
    pos=np.stack([pos[:,0],pos[:,2],-pos[:,1]],1)
    norm=np.stack([norm[:,0],norm[:,2],-norm[:,1]],1)
    col,row=tile%2,tile//2;pad=8;cellw,cellh=1024,512
    im=Image.open(folder/'baked.png').convert('RGB').resize((cellw-pad*2,cellh-pad*2),Image.Resampling.LANCZOS)
    cell=Image.fromarray(np.pad(np.asarray(im),((pad,pad),(pad,pad),(0,0)),mode='edge'))
    atlas.paste(cell,(col*cellw,row*cellh))
    uv[:,0]=(col*cellw+pad+uv[:,0]*(cellw-pad*2))/2048
    uv[:,1]=1-(row*cellh+pad+(1-uv[:,1])*(cellh-pad*2))/1024
    vert=np.concatenate([pos,norm,uv],axis=1).astype('<f4')
    vert,idx=np.unique(vert,axis=0,return_inverse=True);idx=idx.astype('<u4')
    assert len(idx)//3<=budget, (name,len(idx)//3,budget)
    vb=vert.tobytes();ib=idx.tobytes()
    headers.append(dict(id=name,vertexCount=len(vert),indexCount=len(idx),vertexOffset=offset,indexOffset=offset+len(vb),
                        boundsMin=pos.min(0).tolist(),boundsMax=pos.max(0).tolist()))
    chunks.extend([vb,ib]);offset+=len(vb)+len(ib)
    print(name,len(idx)//3,'triangles',flush=True)
header=json.dumps(dict(atlas=dict(width=2048,height=1024),props=headers),separators=(',',':')).encode()
prefix=b'VSP1'+struct.pack('<II',1,len(header))+header;prefix+=b'\0'*(-len(prefix)%16)
(OUT/'StageFieldProps.bin').write_bytes(prefix+b''.join(chunks))
atlas.save(OUT/'StageFieldAtlas.jpg',quality=95,subsampling=0)
print('Saved StageFieldProps.bin and StageFieldAtlas.jpg',flush=True)
