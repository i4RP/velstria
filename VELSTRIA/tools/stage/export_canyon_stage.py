#!/usr/bin/env python3
"""Export the shipped Canyon stage as interchange files: gameplay JSON (sim units and meters),
a glTF 2.0 binary of StageCanyon.bin with the three atlases, and top-down previews.
uv run --with numpy --with pillow python VELSTRIA/tools/stage/export_canyon_stage.py [OUT]
Reads bundled resources only; writes only into OUT (default VELSTRIA/build/stage_export/canyon).
"""
import base64,io,json,shutil,struct,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
RES=ROOT/'Packages/VelstriaCore/Sources/VelstriaCore/Resources'; STAGE=ROOT/'App/Resources/Stage'
OUT=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'build/stage_export/canyon'
SIZE=9720; N=600; CELL=SIZE/N; CUTOFF=.45; GROUPS=('terrain','structures','brushes')

def group_of(c):return 'structures' if c.get('structurePoint') is not None else 'brushes' if c.get('brushIndex') is not None else 'terrain'

def parse_bin(data):
 # Mirrors CanyonStagePlan.parse: header, 16-byte data alignment and every rejection rule.
 # The runtime budget is per quality level; use the importer's 600k ceiling instead.
 assert data[:4]==b'VCM1' and struct.unpack_from('<I',data,4)[0]==1
 length=struct.unpack_from('<I',data,8)[0];assert length<=len(data)-12
 header=json.loads(data[12:12+length]);assert 1<=header['atlasCount']<=3 and 0<len(header['chunks'])<=512
 start=(12+length+15)//16*16;body=len(data)-start;assert body>=0
 out=[];brushes=set();structures=0
 for i,c in enumerate(header['chunks']):
  vc,ic=c['vertexCount'],c['indexCount']
  assert 0<=c['atlas']<header['atlasCount'] and vc>0 and ic>0 and ic%3==0
  assert 0<=c['vertexOffset']<=body and 0<=c['indexOffset']<=body
  assert vc<=(body-c['vertexOffset'])//32 and ic<=(body-c['indexOffset'])//4
  v=np.frombuffer(data,'<f4',vc*8,start+c['vertexOffset']).reshape(vc,8)
  idx=np.frombuffer(data,'<u4',ic,start+c['indexOffset'])
  assert np.isfinite(v).all() and (np.abs(v[:,:3])<500).all() and ((v[:,6:]>=0)&(v[:,6:]<=1)).all() and idx.max()<vc
  sp,bi=c.get('structurePoint'),c.get('brushIndex');group=group_of(c)
  if group=='structures':
   assert len(sp)==2 and all(0<=q<=SIZE for q in sp) and bi is None and structures<20 and ic//3<=8500;structures+=1
  elif group=='brushes':
   assert 0<=bi<255 and bi not in brushes;brushes.add(bi)
  out.append(dict(index=i,group=group,atlas=c['atlas'],brushIndex=bi,structurePoint=sp,v=v,idx=idx))
 assert sorted(brushes)==list(range(len(brushes)))
 assert sum(len(c['idx'])//3 for c in out)<=600000
 # Runtime order: terrain in header order, structures in header order, brushes by brushIndex.
 out.sort(key=lambda c:(GROUPS.index(c['group']),c['brushIndex'] if c['group']=='brushes' else c['index']))
 return header,start,out

def decode_mask(rle):
 # Same RLE as BushMask: value byte + LEB128 run length; row-major, row r covers sim y (r+.5)*CELL.
 b=base64.b64decode(rle);out=bytearray();i=0
 while i<len(b):
  v=b[i];i+=1;n=shift=0
  while True:
   q=b[i];i+=1;n|=(q&127)<<shift
   if not q&128:break
   shift+=7
  out.extend([v]*n)
 assert len(out)==N*N
 return np.frombuffer(bytes(out),np.uint8).reshape(N,N)

def m(x):
 # Sim units -> meters, recursively through coordinate lists.
 return [m(q) for q in x] if isinstance(x,list) else round(x/100,4)

def structure_labels(layout):
 rows=[dict(kind='tower',team=t['team'],lane=t['lane'],tier=t['tier'],point=t['point']) for t in layout['towers']]
 rows+=[dict(kind='core',team=('blue','red')[i],point=p) for i,p in enumerate(layout['cores'])]
 return rows

def label_for(point,labels):
 hit=[r for r in labels if np.hypot(r['point'][0]-point[0],r['point'][1]-point[1])<.01]
 assert len(hit)==1,point
 r=hit[0];return f"tower_{r['team']}_{r['lane']}_t{r['tier']}" if r['kind']=='tower' else f"core_{r['team']}",r

def gameplay_meters(layout,structures,mask):
 labels=structure_labels(layout);groups=sorted(set(mask.ravel())-{0})
 runs=[]
 for r in range(N):
  row=mask[r];cut=np.flatnonzero(np.diff(row))+1
  runs+=[[r,int(a),int(e),int(row[a])] for a,e in zip(np.r_[0,cut],np.r_[cut,N]) if row[a]]
 cells=int((mask>0).sum())
 return dict(
  units='meters (sim units / 100; 100 sim units = 1 m). Source files in gameplay/ keep sim units.',
  axes='Map plane x = east/right, y = north/up in the top-down view, origin at the bottom-left corner, '
       'blue base bottom-left, red base top-right. Render/glTF world: X = x, Y = height (up), Z = -y.',
  size=m(layout['size']),sourceSHA256=layout['sourceSHA256'],
  cores=[dict(team=('blue','red')[i],point=m(p)) for i,p in enumerate(layout['cores'])],
  fountains=[dict(team=('blue','red')[i],point=m(p)) for i,p in enumerate(layout['fountains'])],
  towers=[dict(team=t['team'],lane=t['lane'],tier=t['tier'],point=m(t['point']),sourceName=t.get('sourceName'),
               roadEdges=m(t['roadEdges']) if 'roadEdges' in t else None) for t in layout['towers']],
  towerTierNote='tier 0 = outermost tower of a lane, 2 = nearest its own base',
  camps=[dict(kind=c['kind'],side=c['side'],point=m(c['point'])) for c in layout['camps']],
  lanes=[dict(name=n,waypoints=m(l)) for n,l in zip(('top','mid','bot'),layout['lanes'])],
  laneNote='Authored waypoints. MapCanyon nav-routes each segment at runtime with a 0.75 m radius.',
  walls=m(layout['walls']),river=m(layout['river']),
  solidObjects=[dict(name=o['name'],footprints=m(o['footprints'])) for o in layout['solidObjects']],
  structures=[dict(name=label_for(s['point'],labels)[0],point=m(s['point']),footprint=m(s['footprint'])) for s in structures],
  bushMask=dict(cols=N,rows=N,cell=round(CELL/100,4),groups=len(groups),bushCells=cells,
                areaM2=round(cells*(CELL/100)**2,2),cellsPerGroup={str(g):int((mask==g).sum()) for g in groups},
                order='row-major; row r spans y [r*cell,(r+1)*cell), col c spans x [c*cell,(c+1)*cell)',
                runs=runs,runsFormat='[row, colStart, colEnd (exclusive), group id 1..12]'))

def gl_vertices(v):
 # Bin UVs are bottom-left origin (stageCanyonSurface samples 1-v); glTF is top-left, so flip.
 v=np.array(v,dtype='<f4');v[:,7]=1-v[:,7]
 n=np.linalg.norm(v[:,3:6],axis=1);bad=np.abs(n-1)>1e-3
 v[:,3:6]/=np.where(n>1e-8,n,1)[:,None];v[n<=1e-8,3:6]=(0,1,0)
 return v,int(bad.sum())

def build_glb(chunks,pngs,labels):
 blob=bytearray();views=[];accessors=[];meshes=[];nodes=[];fixed=0
 def view(b,target=None,stride=None):
  blob.extend(b'\0'*(-len(blob)%4));views.append(dict(buffer=0,byteOffset=len(blob),byteLength=len(b)))
  if target:views[-1]['target']=target
  if stride:views[-1]['byteStride']=stride
  blob.extend(b);return len(views)-1
 def acc(bv,offset,ctype,count,typ,**kw):
  accessors.append(dict(bufferView=bv,byteOffset=offset,componentType=ctype,count=count,type=typ,**kw));return len(accessors)-1
 images=[dict(bufferView=view(p),mimeType='image/png',name=f'StageCanyonAtlas{i}') for i,p in enumerate(pngs)]
 # Runtime: unlit, alpha cutout at .45, no face culling (StageScene.buildCanyon / stageCanyonSurface).
 materials=[dict(name=f'canyon_atlas{i}',pbrMetallicRoughness=dict(baseColorTexture=dict(index=i),metallicFactor=0,roughnessFactor=1),
                 alphaMode='MASK',alphaCutoff=CUTOFF,doubleSided=True,extensions=dict(KHR_materials_unlit={})) for i in range(len(pngs))]
 groups={g:[] for g in GROUPS};count={g:0 for g in GROUPS}
 for c in chunks:
  v,bad=gl_vertices(c['v']);fixed+=bad;n=len(v);g=c['group']
  vv=view(v.tobytes(),34962,32);iv=view(np.asarray(c['idx'],'<u4').tobytes(),34963)
  attrs=dict(POSITION=acc(vv,0,5126,n,'VEC3',min=v[:,:3].min(0).tolist(),max=v[:,:3].max(0).tolist()),
             NORMAL=acc(vv,12,5126,n,'VEC3'),TEXCOORD_0=acc(vv,24,5126,n,'VEC2'))
  if g=='structures':name=label_for(c['structurePoint'],labels)[0]
  elif g=='brushes':name=f"brush_{c['brushIndex']:02d}"
  else:name=f"terrain_{count[g]:03d}_atlas{c['atlas']}"
  count[g]+=1
  meshes.append(dict(name=name,primitives=[dict(attributes=attrs,indices=acc(iv,0,5125,len(c['idx']),'SCALAR'),material=c['atlas'],mode=4)]))
  extras=dict(binChunk=c['index'],atlas=c['atlas'],triangles=len(c['idx'])//3)
  node=dict(name=name,mesh=len(meshes)-1,extras=extras)
  if g=='structures':
   # Structure vertices are local; runtime places them at worldPosition(structurePoint), y = 0.
   sp=c['structurePoint'];node['translation']=[sp[0]/100,0.0,-sp[1]/100];extras['structurePointSim']=sp
  if g=='brushes':extras.update(brushIndex=c['brushIndex'],runtimeDrawn=False)
  nodes.append(node);groups[g].append(len(nodes)-1)
 for g in GROUPS:nodes.append(dict(name=g,children=groups[g]))
 nodes.append(dict(name='canyon_stage',children=list(range(len(nodes)-3,len(nodes)))))
 blob.extend(b'\0'*(-len(blob)%4))
 gltf=dict(asset=dict(version='2.0',generator='VELSTRIA tools/stage/export_canyon_stage.py'),
  extensionsUsed=['KHR_materials_unlit'],scene=0,scenes=[dict(name='canyon',nodes=[len(nodes)-1])],nodes=nodes,meshes=meshes,
  materials=materials,textures=[dict(source=i,sampler=0) for i in range(len(pngs))],images=images,
  samplers=[dict(magFilter=9729,minFilter=9987,wrapS=33071,wrapT=33071)],
  accessors=accessors,bufferViews=views,buffers=[dict(byteLength=len(blob))])
 js=json.dumps(gltf,separators=(',',':')).encode();js+=b' '*(-len(js)%4)
 glb=struct.pack('<4sII',b'glTF',2,12+8+len(js)+8+len(blob))+struct.pack('<I4s',len(js),b'JSON')+js+struct.pack('<I4s',len(blob),b'BIN\0')+bytes(blob)
 return glb,fixed

def check_glb(path,chunks):
 # Structural self-check from the written file, plus a byte-exact round trip against the bin.
 b=path.read_bytes();magic,ver,length=struct.unpack_from('<4sII',b);assert magic==b'glTF' and ver==2 and length==len(b)
 jl,jt=struct.unpack_from('<I4s',b,12);assert jt==b'JSON' and jl%4==0
 g=json.loads(b[20:20+jl]);o=20+jl;bl,bt=struct.unpack_from('<I4s',b,o);assert bt==b'BIN\0' and bl%4==0 and o+8+bl==len(b)
 blob=b[o+8:o+8+bl];assert len(g['buffers'])==1 and g['buffers'][0]['byteLength']<=bl
 for v in g['bufferViews']:assert v['buffer']==0 and v['byteOffset']>=0 and v['byteOffset']+v['byteLength']<=g['buffers'][0]['byteLength']
 size={5126:4,5125:4};comps={'SCALAR':1,'VEC2':2,'VEC3':3}
 def read(i):
  a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];cs=size[a['componentType']];k=comps[a['type']];stride=v.get('byteStride',cs*k)
  assert (v['byteOffset']+a['byteOffset'])%cs==0 and a['byteOffset']+stride*(a['count']-1)+cs*k<=v['byteLength']
  return np.ndarray((a['count'],k),'<f4' if a['componentType']==5126 else '<u4',blob,v['byteOffset']+a['byteOffset'],(stride,cs))
 for i in range(len(g['accessors'])):read(i)
 for i,im in enumerate(g['images']):
  v=g['bufferViews'][im['bufferView']];img=Image.open(io.BytesIO(blob[v['byteOffset']:v['byteOffset']+v['byteLength']]))
  assert img.size[0]<=2048 and img.size[1]<=1024,img.size
 assert all(t['source']<len(g['images']) for t in g['textures']) and all(mt['pbrMetallicRoughness']['baseColorTexture']['index']<len(g['textures']) for mt in g['materials'])
 tris={};nodes=g['nodes'];root=nodes[g['scenes'][0]['nodes'][0]]
 seen=0
 for gi in root['children']:
  grp=nodes[gi];tris[grp['name']]=0
  for ni in grp['children']:
   n=nodes[ni];p=g['meshes'][n['mesh']]['primitives'][0];c=chunks[seen];seen+=1
   pos,nor,uv,idx=read(p['attributes']['POSITION']),read(p['attributes']['NORMAL']),read(p['attributes']['TEXCOORD_0']),read(p['indices']).ravel()
   a=g['accessors'][p['attributes']['POSITION']]
   assert p['material']<len(g['materials']) and len(idx)%3==0 and idx.max()<len(pos) and len(pos)==len(nor)==len(uv)
   assert np.allclose(pos.min(0),a['min']) and np.allclose(pos.max(0),a['max'])
   assert np.array_equal(pos,c['v'][:,:3]) and np.array_equal(uv[:,0],c['v'][:,6]) and np.array_equal(uv[:,1],(1-c['v'][:,7]).astype('<f4'))
   assert np.array_equal(idx,c['idx']) and np.allclose(np.linalg.norm(nor,axis=1),1,atol=1e-4)
   tris[grp['name']]+=len(idx)//3
 assert seen==len(chunks)
 return tris,len(g['accessors']),len(g['bufferViews'])

def winding(chunks):
 # Fraction of triangles whose CCW face normal agrees with the vertex normals (runtime draws both sides).
 ok=tot=0
 for c in chunks:
  t=c['v'][c['idx'].reshape(-1,3)];f=np.cross(t[:,1,:3]-t[:,0,:3],t[:,2,:3]-t[:,0,:3]);d=(f*t[:,:,3:6].sum(1)).sum(1)
  ok+=int((d>0).sum());tot+=int((np.abs(d)>0).sum())
 return ok/max(tot,1)

def redundant(chunks):
 # Triangles with a repeated index or the same vertex set as an earlier one; kept, but importers such as Blender drop them.
 n=0
 for c in chunks:
  t=np.sort(c['idx'].reshape(-1,3),1);n+=int(((t[:,0]==t[:,1])|(t[:,1]==t[:,2])).sum())+len(t)-len(np.unique(t,axis=0))
 return n

def font(size):
 for f in ('/System/Library/Fonts/Helvetica.ttc','/System/Library/Fonts/Supplemental/Arial.ttf'):
  try:return ImageFont.truetype(f,size)
  except OSError:pass
 return ImageFont.load_default()

def topdown(layout,structures,mask,path,W=2048):
 # Sim coordinates; blue base bottom-left. Lanes are authored waypoints, not nav-routed paths.
 pad=72;im=Image.new('RGBA',(W,W+pad),'#1f2b27');d=ImageDraw.Draw(im,'RGBA');s=W/SIZE
 def pix(points):return [(x*s,(SIZE-y)*s) for x,y in points]
 def dot(p,r,fill,outline='black'):x,y=pix([p])[0];d.ellipse((x-r,y-r,x+r,y+r),fill=fill,outline=outline,width=2);return x,y
 d.polygon(pix(layout['river']),fill='#3d7686')
 for l in layout['lanes']:d.line(pix(l),fill='#7d7765',width=int(2.5*100*s),joint='curve')
 bush=np.zeros((N,N,4),np.uint8);bush[mask>0]=(70,170,60,190);im.alpha_composite(Image.fromarray(bush[::-1]).resize((W,W),Image.Resampling.NEAREST),(0,0))
 for w in layout['walls']:d.polygon(pix(w),fill='#8f9183',outline='#4d4f45')
 for o in layout['solidObjects']:
  for f in o['footprints']:d.polygon(pix(f),outline='#e0b860')
 labels=structure_labels(layout);f1,f2=font(20),font(26)
 for st in structures:
  _,r=label_for(st['point'],labels);d.polygon(pix(st['footprint']),fill='#2f5f9f' if r['team']=='blue' else '#9f3f3f',outline='white')
 for k in range(0,SIZE+1,1000):
  d.line(pix([(k,0),(k,SIZE)]),fill='#ffffff30',width=1);d.line(pix([(0,k),(SIZE,k)]),fill='#ffffff30',width=1)
  d.text((k*s+3,W-22),f'{k//100}m',fill='#cccccc',font=f1);d.text((3,(SIZE-k)*s+2),f'{k//100}m',fill='#cccccc',font=f1)
 for t in layout['towers']:
  x,y=dot(t['point'],16,'#3b9cff' if t['team']=='blue' else '#ff4d4d');d.text((x+18,y-12),f"{t['lane']}{t['tier']}",fill='white',font=f1)
 for i,p in enumerate(layout['cores']):x,y=dot(p,26,('#1f6fff','#e02020')[i],'white');d.text((x+28,y-14),'core',fill='white',font=f2)
 for i,p in enumerate(layout['fountains']):
  x,y=pix([p])[0];d.rectangle((x-18,y-18,x+18,y+18),fill=('#8fd0ff','#ffb0b0')[i],outline='black',width=2);d.text((x+22,y-14),'fountain',fill='white',font=f1)
 for c in layout['camps']:x,y=dot(c['point'],13,'#ffd23f');d.text((x+15,y+2),f"{c['kind']} ({c['side']})",fill='#ffe9a0',font=f1)
 d.rectangle((0,W,W,W+pad),fill='#111111')
 d.text((16,W+10),'Canyon top-down (sim coords, 1 grid = 10 m, blue base bottom-left). Grey walls, teal river, green bush mask, '
        'tan lanes (authored waypoints), gold outline solid props, filled structure footprints, gold dots camps.',fill='white',font=f1)
 im.convert('RGB').save(path)

def render_topdown(chunks,atlases,path,W=2048):
 # Flat-shaded check of the glTF UV convention: each triangle takes the atlas texel at its centroid.
 # Brushes are skipped (not drawn at runtime). Painter's order by triangle height.
 polys=[];cols=[];heights=[];opaque=[0,0]
 for c in chunks:
  if c['group']=='brushes':continue
  v=c['v'].astype(np.float64);off=np.zeros(3)
  if c['structurePoint']:off=np.array([c['structurePoint'][0]/100,0,-c['structurePoint'][1]/100])
  t=v[c['idx'].reshape(-1,3)];p=t[:,:,:3]+off;uv=t[:,:,6:8].mean(1)
  a=atlases[c['atlas']];h,w=a.shape[:2]
  for k,vv in enumerate((1-uv[:,1],uv[:,1])):
   px=a[np.clip((vv*h).astype(int),0,h-1),np.clip((uv[:,0]*w).astype(int),0,w-1)]
   opaque[k]+=int((px[:,3]>=CUTOFF*255).sum())
   if k==0:rgba=px
  keep=rgba[:,3]>=CUTOFF*255
  polys.append(p[keep]);cols.append(rgba[keep,:3]);heights.append(p[keep][:,:,1].max(1))
 p=np.concatenate(polys);col=np.concatenate(cols);order=np.argsort(np.concatenate(heights))
 im=Image.new('RGB',(W,W),'#000000');d=ImageDraw.Draw(im);s=W/(SIZE/100)
 xy=np.stack([p[:,:,0]*s,(SIZE/100+p[:,:,2])*s],-1)
 for i in order:d.polygon([tuple(q) for q in xy[i]],fill=tuple(int(x) for x in col[i]))
 im.save(path);return opaque

def main():
 for sub in ('gameplay','render','preview'):(OUT/sub).mkdir(parents=True,exist_ok=True)
 for name in ('CanyonLayout.json','CanyonStructures.json'):shutil.copyfile(RES/name,OUT/'gameplay'/name)
 layout=json.loads((RES/'CanyonLayout.json').read_text());structures=json.loads((RES/'CanyonStructures.json').read_text())
 mask=decode_mask(layout['bushRLE']);assert len(structures)==20 and len(layout['towers'])==18
 meters=gameplay_meters(layout,structures,mask)
 (OUT/'gameplay/canyon_gameplay_meters.json').write_text(json.dumps(meters,indent=1))
 Image.fromarray(mask[::-1]).save(OUT/'gameplay/bush_mask_ids.png') # pixel = group id, image top = north
 data=(STAGE/'StageCanyon.bin').read_bytes();header,start,chunks=parse_bin(data)
 expect={g:sum(len(c['idx'])//3 for c in chunks if c['group']==g) for g in GROUPS}
 headerTris={g:sum(c['indexCount']//3 for c in header['chunks'] if group_of(c)==g) for g in GROUPS}
 assert expect==headerTris,(expect,headerTris)
 pngs=[(STAGE/f'StageCanyonAtlas{i}.png').read_bytes() for i in range(header['atlasCount'])]
 for i,p in enumerate(pngs):(OUT/f'render/StageCanyonAtlas{i}.png').write_bytes(p)
 glb,fixed=build_glb(chunks,pngs,structure_labels(layout));(OUT/'render/canyon_stage.glb').write_bytes(glb)
 tris,nacc,nviews=check_glb(OUT/'render/canyon_stage.glb',chunks);assert tris==expect,(tris,expect)
 # Up axis: dominant mean terrain normal. Importer writes (sim x/100, height, -sim y/100).
 tn=np.concatenate([c['v'][:,3:6] for c in chunks if c['group']=='terrain']).mean(0);up='XYZ'[int(np.argmax(np.abs(tn)))]
 assert up=='Y' and tn[1]>0
 bounds={g:(np.concatenate([c['v'][:,:3]+(np.array([c['structurePoint'][0]/100,0,-c['structurePoint'][1]/100]) if c['structurePoint'] else 0) for c in chunks if c['group']==g]))
         for g in GROUPS}
 bounds={g:(b.min(0).astype(float).round(3).tolist(),b.max(0).astype(float).round(3).tolist()) for g,b in bounds.items()}
 wind=winding(chunks)
 topdown(layout,structures,mask,OUT/'preview/topdown.png')
 atl=[np.array(Image.open(OUT/f'render/StageCanyonAtlas{i}.png').convert('RGBA')) for i in range(header['atlasCount'])]
 opaque=render_topdown(chunks,atl,OUT/'preview/render_topdown.png')
 counts={g:sum(c['group']==g for c in chunks) for g in GROUPS}
 verts={g:sum(len(c['v']) for c in chunks if c['group']==g) for g in GROUPS}
 stats=dict(chunks=counts,triangles=expect,vertices=verts,bounds=bounds,up=up,meanTerrainNormal=tn.astype(float).round(3).tolist(),normalsRenormalized=fixed,ccwAgree=round(wind,4),redundantTriangles=redundant(chunks),
            centroidOpaque=dict(chosen=opaque[0],flipped=opaque[1]),accessors=nacc,bufferViews=nviews,dataStart=start,atlasCount=header['atlasCount'],
            towers=len(layout['towers']),cores=len(layout['cores']),camps=len(layout['camps']),walls=len(layout['walls']),
            solidObjects=len(layout['solidObjects']),solidFootprints=sum(len(o['footprints']) for o in layout['solidObjects']),
            riverVertices=len(layout['river']),structureFootprints=len(structures),bushCells=meters['bushMask']['bushCells'],
            bushAreaM2=meters['bushMask']['areaM2'],bushGroups=meters['bushMask']['groups'])
 write_readme(stats)
 print(json.dumps(stats,indent=1))
 for p in sorted(OUT.rglob('*')):
  if p.is_file():print(f'{p.stat().st_size:>10}  {p.relative_to(OUT)}')

def write_readme(st):
 own={'gameplay/CanyonLayout.json','gameplay/CanyonStructures.json','gameplay/canyon_gameplay_meters.json','gameplay/bush_mask_ids.png',
      'render/canyon_stage.glb','preview/topdown.png','preview/render_topdown.png'}|{f'render/StageCanyonAtlas{i}.png' for i in range(st['atlasCount'])}
 files=sorted(p for p in OUT.rglob('*') if p.is_file() and p.name!='README.md')
 # Other tools may share OUT; name the known ones, list the rest as foreign.
 ext={'gameplay/canyon_resolved.json':'`CanyonExportTests` (`VELSTRIA_EXPORT_MAP=<dir> swift test --filter CanyonExportTests`): live `MapDefinition.canyon`, nav-routed lanes',
      'preview/glb_top.png':'Blender import check of the glTF (orthographic top view)'}
 def note(r):return '' if r in own else ' '+ext.get(r,'not written by this script')
 rows='\n'.join(f"| `{p.relative_to(OUT)}` | {p.stat().st_size:,} |{note(str(p.relative_to(OUT)))} |" for p in files)
 t,c,v,b=st['triangles'],st['chunks'],st['vertices'],st['bounds']
 (OUT/'README.md').write_text(f"""# Canyon stage export

Generated by `VELSTRIA/tools/stage/export_canyon_stage.py` from the bundled runtime data
(`Packages/VelstriaCore/Sources/VelstriaCore/Resources/CanyonLayout.json`, `CanyonStructures.json`,
`App/Resources/Stage/StageCanyon.bin`, `StageCanyonAtlas0..2.png`). Original source scene (local only, gitignored):
`VELSTRIA/build/stage/canyon/source/map.fbx` + `textures/` (Blender Z-up; converted by `tools/stage/import_canyon.py`).

| File | Bytes | |
|---|---|---|
{rows}
| `README.md` | | this file |

- `gameplay/CanyonLayout.json`, `gameplay/CanyonStructures.json`: verbatim copies, sim units.
- `gameplay/canyon_gameplay_meters.json`: the same data in meters, plus structure names and the decoded bush mask
  (dimensions, per-group cell counts, row runs `[row, colStart, colEnd, group]`).
- `gameplay/bush_mask_ids.png`: 600x600 8-bit, pixel = bush group id (0 = none), image top = north (max y).
- `render/canyon_stage.glb`: glTF 2.0 binary, atlases embedded; `render/StageCanyonAtlas*.png`: the same atlases.
- `preview/topdown.png`: gameplay data drawn in sim coordinates. `preview/render_topdown.png`: the glTF meshes
  rasterized top-down, one atlas texel per triangle (UV convention check; brushes omitted).

## Counts

| Group (glTF node) | Chunks | Triangles | Vertices | World bounds min / max (m) |
|---|---|---|---|---|
| terrain | {c['terrain']} | {t['terrain']:,} | {v['terrain']:,} | {b['terrain'][0]} / {b['terrain'][1]} |
| structures | {c['structures']} | {t['structures']:,} | {v['structures']:,} | {b['structures'][0]} / {b['structures'][1]} |
| brushes | {c['brushes']} | {t['brushes']:,} | {v['brushes']:,} | {b['brushes'][0]} / {b['brushes'][1]} |
| total | {sum(c.values())} | {sum(t.values()):,} | {sum(v.values()):,} | |

Triangle counts match the bin header (and the glTF re-read). Gameplay: {st['towers']} towers + {st['cores']} cores
({st['structureFootprints']} structure footprints), {st['camps']} camps, {st['walls']} wall polygons, river polygon of
{st['riverVertices']} vertices, {st['solidObjects']} solid objects ({st['solidFootprints']} footprints), bush mask
{st['bushGroups']} groups / {st['bushCells']:,} cells of 0.162 m = {st['bushAreaM2']} m².

## Units and coordinates

- Sim: 100 units = 1 m, map square 0..9720 (97.2 m). x right/east, y up/north in the top-down view; blue base
  bottom-left (core ~(14.9, 14.9) m), red top-right. Tower tier 0 = outer, 2 = nearest its own base.
- Render/glTF (right-handed, Y up, meters): `X = x/100`, `Y = height`, `Z = -y/100`. Same mapping as the app's
  `worldPosition` and RealityKit. Up axis checked from the mean terrain normal {st['meanTerrainNormal']}: {st['up']}.
  Terrain spans below/outside the playable square (cliff skirts and outer scenery), see bounds above.
- Structures (`structures` node): vertices are local to the tower/core; each node has `translation` =
  `worldPosition(structurePoint)` (y = 0), as the app parents them under the structure entity. `extras.structurePointSim` keeps sim units.
- Brushes (`brushes` node): the 12 original grass groups. Not drawn in-game (replaced by the procedural dense
  brush); `extras.runtimeDrawn = false`.
- UV: the bin stores bottom-left-origin V (`stageCanyonSurface` samples `1 - v`, i.e. image top at bin v = 1).
  glTF uses top-left origin, so the glTF stores `v = 1 - v_bin`; U is unchanged. Atlas texels opaque at triangle
  centroids: {st['centroidOpaque']['chosen']:,} with this convention vs {st['centroidOpaque']['flipped']:,} without the flip.
- Materials: 3 (one per atlas), `KHR_materials_unlit`, `alphaMode MASK` cutoff 0.45, double-sided, clamp sampler,
  matching the runtime material. {st['ccwAgree']*100:.1f}% of triangles are CCW relative to their vertex normals
  (the app disables face culling anyway). Normals renormalized for glTF: {st['normalsRenormalized']} (bin lengths 0.98..0.999).

## Caveats

- Lanes are the authored waypoints; the app nav-routes them at runtime (radius 0.75 m), so in-game paths differ.
- Camp timings/ids come from `MapDefinition.relayout`; only positions are in the layout (all 15 camps are listed).
- Walls include the outer boundary polygons, which extend past the 0..97.2 m square.
- {st['redundantTriangles']} bin triangles are degenerate or duplicate another's vertex set; the glTF keeps them, Blender's importer
  drops them ({sum(t.values())-st['redundantTriangles']:,} triangles after import).
""")

if __name__=='__main__':main()
