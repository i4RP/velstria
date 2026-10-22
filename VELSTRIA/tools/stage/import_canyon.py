#!/usr/bin/env python3
"""Import the supplied 5v5-game-map.zip into bounded, static stage chunks.
uv run --with numpy --with pillow --with shapely --with scipy python tools/stage/import_canyon.py SOURCE.zip
Blender is used offline only. Runtime loads three 2048x1024 atlases and 12m chunks.
"""
import base64,hashlib,json,math,struct,subprocess,sys
from pathlib import Path
from zipfile import ZipFile
from collections import defaultdict
import numpy as np
from PIL import Image,ImageDraw
from shapely.geometry import Polygon,MultiPolygon,Point,box,LineString,MultiPoint
from shapely.ops import unary_union,triangulate
from shapely import contains_xy
ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'build/stage/canyon'; OUT=ROOT/'App/Resources/Stage'
SCALE=97.2/336; CENTER=np.array([12.6,5.0]); ORIGIN=CENTER+168

def sim(p):return (ORIGIN-np.asarray(p)[...,:2])*SCALE*100

def polygons(shape):
 if shape.is_empty:return []
 if shape.geom_type=='Polygon':return [shape]
 return [p for g in getattr(shape,'geoms',[]) for p in polygons(g)]

def footprint(p,z=None):
 tris=p.reshape(-1,3,3)
 if z is not None:tris=tris[np.max(tris[:,:,2],axis=1)>z]
 shapes=[Polygon(t[:,:2]) for t in tris]
 shapes=[p for p in shapes if p.area>1e-5]
 return unary_union(shapes).buffer(.12).buffer(-.12).simplify(.18,preserve_topology=True)

def is_solid_mesh(row):
 # The only walk-through scenery is the floor and designated concealment grass.
 # Includes pillars, rails, statues, trees, camp props, base walls and rock groups.
 name=row['name'];tex=row['texture']
 return not ('Terrain' in name or ('Base' in name and 'Ground' in name)
             or 'JungleGrassGroup' in name or tex.startswith(('PVPMonster','Mst_'))
             or 'Tower' in tex or 'Station' in tex)

def solid_footprint(p):
 # Project the occupied body-height band, not just rock names or mesh origins.
 # Thin upright faces still collide; fill closed shell interiors but retain open arches.
 shapes=[]
 for tri in p.reshape(-1,3,3):
  if tri[:,2].max()<.18/SCALE or tri[:,2].min()>2.1/SCALE:continue
  poly=list(tri)
  for z,gt in [(.18/SCALE,True),(2.1/SCALE,False)]:poly=clip(poly,2,z,gt)
  if len(poly)<2:continue
  shapes.append(MultiPoint(np.array(poly)[:,:2]).convex_hull.buffer(.04/SCALE))
 merged=unary_union(shapes).buffer(.08/SCALE)
 return unary_union([Polygon(p.exterior) for p in polygons(merged)]).simplify(.025/SCALE,preserve_topology=True)

def road_center(road, origin, normal):
 # Infer both paving edges around the socket, ignoring its small notch in the floor.
 # The inner tower sits just inside the base: extend the adjacent lane cross-section.
 direction=np.array([-normal[1],normal[0]]);samples=[]
 for along in [-12,-8,-4,0,4,8,12]:
  p=origin+direction*along
  cut=LineString([p-normal*35,p+normal*35]).intersection(road)
  parts=[cut] if cut.geom_type=='LineString' else list(getattr(cut,'geoms',[]))
  parts=[c for c in parts if c.geom_type=='LineString' and 1.5/SCALE<c.length<18/SCALE]
  if not parts:continue
  c=min(parts,key=lambda c:c.distance(Point(p)))
  if c.distance(Point(p))>5/SCALE:continue
  ends=np.array([c.coords[0],c.coords[-1]])-direction*along
  samples.append((float(((ends.mean(0)-origin)*normal).sum()),ends))
 assert samples,origin
 _,edges=sorted(samples,key=lambda q:q[0])[len(samples)//2]
 return edges.mean(0),edges

def structure_anchor(row):
 # The authored placement origin is independent of asymmetric crowns/banners.
 # Do not fall back to a bounds center: old extracts must be regenerated.
 return sim(row['origin']).tolist()

def bush_footprint(p):
 # Preserve concave edges and gaps between grass clumps. A group-wide convex hull
 # grants concealment to bare paving/water that has no grass in the source scene.
 return footprint(p)

def ground_heights(z, texture):
 # A clamp folds every depressed bank/road onto the same plane and creates Z-fighting.
 # Keep near-ground offsets at full precision; compress only deep banks below 6cm.
 # This keeps the authored 4mm+ plaza/road separation instead of shrinking it away.
 height=np.where(z<-.2,-.2+(z+.2)*.05,z)
 # The source border and rock submeshes also contain genuinely coplanar patches.
 # Put that authored border underlay 16mm below the rock (GroundLayer's >=4mm rule).
 if texture=='PGD_M_20TerrainBorder_01_D.png':height=height-.016/SCALE
 return height


def clip(v,axis,value,greater):
 out=[]
 for a,b in zip(v,v[1:]+v[:1]):
  da=(a[axis]-value)*(1 if greater else -1);db=(b[axis]-value)*(1 if greater else -1)
  if da>=-1e-9:out.append(a)
  if (da>=0)!=(db>=0):out.append(a+(b-a)*(da/(da-db)))
 return out

def tiled_triangles(v):
 # Split in UV space before packing so repeating source UVs never sample neighbours.
 lo=np.floor(v[:,6:8].min(0)+1e-7).astype(int);hi=np.floor(v[:,6:8].max(0)-1e-7).astype(int);hi=np.maximum(lo,hi)
 for x in range(lo[0],hi[0]+1):
  for y in range(lo[1],hi[1]+1):
   poly=list(v)
   for a,value,gt in [(6,x,True),(6,x+1,False),(7,y,True),(7,y+1,False)]:
    poly=clip(poly,a,value,gt)
    if len(poly)<3:break
   for j in range(1,len(poly)-1):
    t=np.array([poly[0],poly[j],poly[j+1]]);t[:,6:8]-=[x,y];yield t

def main():
 source=Path(sys.argv[1]).resolve();WORK.mkdir(parents=True,exist_ok=True)
 if '--reuse' not in sys.argv:
  with ZipFile(source) as z:
   for f in z.infolist():
    if f.is_dir():continue
    name='map.fbx' if f.filename.lower().endswith('.fbx') else 'textures/'+Path(f.filename).name
    target=WORK/'source'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(f))
  subprocess.run(['/Applications/Blender.app/Contents/MacOS/Blender','-b','--factory-startup','-t','4','--python-exit-code','1','--python',str(ROOT/'tools/stage/canyon_extract.py'),'--',str(WORK)],check=True)
 meta=json.loads((WORK/'meshes.json').read_text());objects=[];seen=set();markers=[];structures=[];walls=[];bushes=[];rivers=[];ground=[];roads=[];solidObjects=[]
 for row in meta:
  a=np.load(WORK/'meshes'/f"{row['id']}.npz");p=a['p'];uv=a['uv'];n=a['n'];name=row['name'];tex=row['texture']
  key=hashlib.sha256(np.round(np.column_stack([p,uv]),3).tobytes()+tex.encode()).hexdigest()
  if key in seen:continue
  seen.add(key)
  if 'Tower' in tex or 'Station' in tex:
   markers.append(dict(name=name,texture=tex,point=structure_anchor(row)))
   row=dict(row,structureIndex=len(structures))
   structures.append((row,p,n,uv));continue
  if tex.startswith(('PVPMonster','Mst_')):continue
  if is_solid_mesh(row):
   shape=solid_footprint(p)
   if not shape.is_empty:
    walls.extend(polygons(shape))
    solidObjects.append((name,shape))
  if any(t in tex for t in ['TerrainRock_','TerrainCenter_']):roads.extend(polygons(footprint(p)))
  if 'JungleGrassGroup' in name:
   row=dict(row,brushIndex=len(bushes))
   bushes.append(bush_footprint(p)) # keep the original mesh and this same group's gameplay mask
  if 'TerrainRiver_01_D' in tex:rivers.extend(polygons(footprint(p)))
  if 'Terrain' in name or 'BaseGround' in tex or 'BaseBlueGround' in name or 'BaseRedGround' in name:
   ground.extend(polygons(footprint(p)))
   p=p.copy();p[:,2]=ground_heights(p[:,2],tex)
  objects.append((row,p,n,uv))
 print('Unique static objects',len(objects),'source triangles',sum(len(p)//3 for _,p,_,_ in objects),flush=True)
 # Ground coverage prevents movement into the unmodelled exterior, but preserves the two fountain plazas.
 cover=unary_union(ground).buffer(1.4).buffer(-1.0)
 # Tower sockets leave holes in the floor mesh; they are not impassable terrain.
 cover=unary_union([Polygon(p.exterior) for p in polygons(cover)])
 outer=box(*(CENTER-168),*(CENTER+168)).difference(cover)
 # Split around holes without turning long borders into thousands of tiny triangles.
 def simple_parts(poly):
  if not poly.interiors:return [poly]
  x=Polygon(poly.interiors[0]).representative_point().x
  lo,bot,hi,top=poly.bounds
  return [p for part in [box(lo-1,bot-1,x,top+1),box(x,bot-1,hi+1,top+1)] for g in polygons(poly.intersection(part)) for p in simple_parts(g)]
 boundary=[q for p in polygons(outer) for q in simple_parts(p)]
 # Floors stay walkable; surrounding base props keep their own collision.
 fountains=[np.array([157,149]),np.array([-132,-140])]
 wallUnion=unary_union(walls)
 finalWalls=[]
 for poly in polygons(wallUnion)+boundary:
  poly=poly.simplify(.025/SCALE,preserve_topology=True)
  if poly.area<.01:continue
  finalWalls.extend(simple_parts(poly))
 # Source cores/towers are exported separately for the living/destructible entities.
 def marker(team,token):return [m for m in markers if team in m['texture'] and token in m['texture']]
 core=[marker(team,'Station')[0]['point'] for team in ['Blue','Red']]
 towers=[]
 for team in ['Blue','Red']:
  ts=marker(team,'Tower');pts=[np.array(m['point']) for m in ts]
  base=core[0 if team=='Blue' else 1]
  mid=sorted(range(9),key=lambda i:abs(pts[i][0]-pts[i][1]))[:3]
  sides=[[i for i in range(9) if i not in mid and pts[i][0]<pts[i][1]], [i for i in range(9) if i not in mid and pts[i][0]>=pts[i][1]]]
  for lane,indices in [('mid',mid),('top',sides[0]),('bot',sides[1])]:
   assert len(indices)==3,(team,lane,indices)
   for tier,i in enumerate(sorted(indices,key=lambda i:-np.linalg.norm(pts[i]-base))):towers.append(dict(team=team.lower(),lane=lane,tier=tier,point=pts[i].tolist(),sourceName=ts[i]['name']))
 # Center every lane tower across the actual paving width. Retain FBX facing/scale.
 road=unary_union(roads).buffer(1.5).buffer(-1.5)
 road=unary_union([Polygon(p.exterior) for p in polygons(road)])
 for tower in towers:
  origin=ORIGIN-np.array(tower['point'])/(100*SCALE)
  normal=np.array([1.,-1.])/2**.5 if tower['lane']=='mid' else np.array([1.,0.] if (tower['team']=='blue')==(tower['lane']=='top') else [0.,1.])
  center,edges=road_center(road,origin,normal)
  tower['point']=sim(center).tolist()
  tower['roadEdges']=sim(edges).tolist()
 # Actual circular river arenas: northwest blue sigil, southeast violet sigil.
 camps=[]
 blueCamps=[('blueSentinel',[100,29]),('redSentinel',[13,94]),('hornLizard',[110,-9]),('emberBeetle',[-39,112]),('magmaGolem',[28,62])]
 for kind,p in blueCamps:
  camps.extend([dict(kind=kind,side='blue',point=sim(p).tolist()),dict(kind=kind,side='red',point=sim(2*CENTER-np.array(p)).tolist())])
 camps.extend([dict(kind='ancientColossus',side='neutral',point=sim([60,-55]).tolist()),dict(kind='astralWyrm',side='neutral',point=sim([-37,66]).tolist()),dict(kind='mossWanderer',side='neutral',point=sim([35,-7]).tolist()),dict(kind='treasureCrab',side='neutral',point=sim([120,-105]).tolist()),dict(kind='treasureCrab',side='neutral',point=sim([-95,115]).tolist())])
 # Find a nearby open position that fits both the monster and the blue buff's companion.
 allwalls=unary_union(finalWalls)
 for camp in camps:
  original=np.array(camp['point']);best=None
  radius=260 if camp['kind'] in ['ancientColossus','astralWyrm'] else 145
  offsets=[(np.zeros(2),radius)]
  if camp['kind']=='blueSentinel':offsets.append((np.array([-190,170])*(1 if camp['side']=='blue' else -1),90))
  for dx in range(-650,651,25):
   for dy in range(-650,651,25):
    cost=dx*dx+dy*dy
    if best is not None and cost>=best[0]:continue
    candidate=original+[dx,dy]
    if any(not (80<v<9640) for v in candidate):continue
    valid=True
    for offset,r in offsets:
     sourcePoint=Point(ORIGIN-(candidate+offset)/(100*SCALE))
     if allwalls.contains(sourcePoint) or allwalls.distance(sourcePoint)<r/(100*SCALE):valid=False;break
    if valid:best=(cost,candidate)
  assert best is not None, camp
  camp['point']=np.round(best[1],2).tolist()
 # Full-resolution shared mask; carve only actual wall silhouettes.
 N=600;cell=9720/N;cells=np.zeros((N,N),dtype=np.uint8);yy,xx=np.mgrid[0:N,0:N];px=ORIGIN[0]-(xx+.5)*cell/(100*SCALE);py=ORIGIN[1]-(yy+.5)*cell/(100*SCALE)
 allwalls=unary_union(finalWalls)
 for i,b in enumerate(bushes):cells[contains_xy(b,px,py)&~contains_xy(allwalls,px,py)]=i+1
 # Mesh IDs and concealment IDs must stay aligned; never silently drop a source group.
 assert set(cells.ravel())-{0}==set(range(1,len(bushes)+1))
 encoded=bytearray();flat=cells.ravel();i=0
 while i<len(flat):
  j=i+1
  while j<len(flat) and flat[j]==flat[i]:j+=1
  run=j-i;encoded.append(int(flat[i]))
  while run>=128:encoded.append((run&127)|128);run>>=7
  encoded.append(run);i=j
 def ring(poly):return np.round(sim(np.array(poly.exterior.coords[:-1])),2).tolist()
 riverShape=unary_union(rivers).buffer(1).buffer(-1)
 pools=sorted(polygons(riverShape),key=lambda p:-p.area)
 connector=LineString([p.representative_point() for p in pools[:2]]).buffer(10)
 river=max(polygons(unary_union([riverShape,connector])),key=lambda p:p.area)
 # Outer lanes follow the paving and tower sockets; mid follows all three actual tower positions.
 def lane(name):
  bt=sorted([t for t in towers if t['lane']==name and t['team']=='blue'],key=lambda t:-t['tier'])
  rt=sorted([t for t in towers if t['lane']==name and t['team']=='red'],key=lambda t:t['tier'])
  corners=sim([[146,-100],[115,-130]] if name=='top' else [[-93,140],[-123,110]]).tolist()
  return [core[0]]+[t['point'] for t in bt]+([] if name=='mid' else corners)+[t['point'] for t in rt]+[core[1]]
 layout=dict(sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest() if source.exists() else json.loads((WORK/'layout.json').read_text())['sourceSHA256'],size=9720,cores=core,fountains=[sim(p).tolist() for p in fountains],towers=towers,camps=camps,lanes=[lane('top'),lane('mid'),lane('bot')],solidObjects=[dict(name=name,footprints=[ring(q) for p in polygons(shape) for q in simple_parts(p)]) for name,shape in solidObjects],walls=[ring(p) for p in finalWalls],river=ring(river),bushRLE=base64.b64encode(encoded).decode())
 (ROOT/'Packages/VelstriaCore/Sources/VelstriaCore/Resources/CanyonLayout.json').write_text(json.dumps(layout,separators=(',',':')))
 (WORK/'layout.json').write_text(json.dumps(layout,indent=2))
 if '--layout-only' in sys.argv:
  print('Updated layout',len(finalWalls),'walls',flush=True);return
 # Structures retain authored world transforms, but get independent destructible meshes.
 structureInfo=[]
 for row,p,n,uv in structures:
  base=p[(p[:,2]>=-.5)&(p[:,2]<=4)]
  hull=Polygon(base[:,:2]).convex_hull
  point=next((t['point'] for t in towers if t['sourceName']==row['name']),structure_anchor(row))
  delta=np.array(point)-structure_anchor(row)
  structureInfo.append(dict(point=point,footprint=(np.array(ring(hull))+delta).tolist()))
 (ROOT/'Packages/VelstriaCore/Sources/VelstriaCore/Resources/CanyonStructures.json').write_text(json.dumps(structureInfo,separators=(',',':')))
 objects+=structures
 # Sixteen extruded texels keep neighbouring atlas tiles apart through the useful mip levels.
 pad=16;content=512-pad*2
 # Three 2048x1024 atlases: eight 512px tiles per atlas.
 textures=sorted(set(row['texture'] for row,_,_,_ in objects));assert len(textures)<=24
 atlases=[Image.new('RGBA',(2048,1024)) for _ in range(math.ceil(len(textures)/8))]
 for i,tex in enumerate(textures):
  im=Image.open(WORK/'source/textures'/tex).convert('RGBA').resize((content,content),Image.Resampling.LANCZOS)
  tile=Image.fromarray(np.pad(np.array(im),((pad,pad),(pad,pad),(0,0)),mode='edge'))
  atlases[i//8].paste(tile,((i%4)*512,((i%8)//4)*512))
 for i,a in enumerate(atlases):a.save(OUT/f'StageCanyonAtlas{i}.png')
 chunks=defaultdict(list)
 for row,p,n,uv in objects:
  tid=textures.index(row['texture']);mapped=sim(p)/100
  pos=np.column_stack([mapped[:,0],p[:,2]*SCALE,-mapped[:,1]])
  normal=np.column_stack([-n[:,0],n[:,2],n[:,1]])
  structure=row.get('structureIndex',-1)
  if structure>=0:
   anchor=np.array(structure_anchor(row))/100
   pos-=np.array([anchor[0],0,-anchor[1]])
  v=np.column_stack([pos,normal,uv])
  for tri in v.reshape(-1,3,8):
   for t in tiled_triangles(tri):
    t[:,6]=((tid%4)*512+pad+t[:,6]*content)/2048
    t[:,7]=1-(((tid%8)//4)*512+pad+(1-t[:,7])*content)/1024
    center=t[:,:3].mean(0);cx=int(math.floor((center[0]+20)/12));cy=int(math.floor((-center[2]+20)/12))
    brush=row.get('brushIndex',-1)
    chunks[(brush,structure,tid//8,0 if brush>=0 or structure>=0 else cx,0 if brush>=0 or structure>=0 else cy)].append(t)
 headers=[];payload=[];offset=0;total=0
 for (brush,structure,atlas,x,y),tris in sorted(chunks.items()):
  vert=np.concatenate(tris).astype('<f4');vert,idx=np.unique(vert,axis=0,return_inverse=True);idx=idx.astype('<u4')
  vb=vert.tobytes();ib=idx.tobytes();total+=len(idx)//3
  if structure>=0:assert len(idx)//3 <= (8500 if 'Station' in structures[structure][0]['texture'] else 6000)
  headers.append(dict(structurePoint=structureInfo[structure]['point'] if structure>=0 else None,atlas=atlas,brushIndex=brush if brush>=0 else None,vertexCount=len(vert),indexCount=len(idx),vertexOffset=offset,indexOffset=offset+len(vb)))
  payload.extend([vb,ib]);offset+=len(vb)+len(ib)
 assert total<=600000,total
 header=json.dumps(dict(atlasCount=len(atlases),chunks=headers),separators=(',',':')).encode();prefix=b'VCM1'+struct.pack('<II',1,len(header))+header;prefix+=b'\0'*(-len(prefix)%16)
 (OUT/'StageCanyon.bin').write_bytes(prefix+b''.join(payload))
 print('Baked',total,'triangles;',len(headers),'chunks;',len(atlases),'atlases;',len(finalWalls),'walls;',len(bushes),'grass areas',flush=True)
 # Review geometry in world units. This is generated from simulation shapes, not a screenshot trace.
 im=Image.new('RGB',(1600,1600),'#263d3a');d=ImageDraw.Draw(im)
 def pix(points):return [(x/9720*1600,(1-y/9720)*1600) for x,y in points]
 d.polygon(pix(layout['river']),fill='#427c88')
 for l in layout['lanes']:d.line(pix(l),fill='#67756b',width=70)
 for w in layout['walls']:d.polygon(pix(w),fill='#a4ab98')
 for t in towers:
  x,y=pix([t['point']])[0];d.ellipse((x-9,y-9,x+9,y+9),fill='cyan' if t['team']=='blue' else 'salmon')
 for c in camps:
  x,y=pix([c['point']])[0];d.ellipse((x-10,y-10,x+10,y+10),fill='gold');d.text((x+12,y),c['kind'],fill='white')
 im.save(WORK/'collision-review.png')
if __name__=='__main__':main()
