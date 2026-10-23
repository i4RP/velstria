import sys, math, json
from pathlib import Path
import bpy
from mathutils import Quaternion
sys.path.insert(0,str(Path('tools/blender').resolve()))
import author_h025_motion as a
import preview_clip as p
import preview_h025_motion as h
import clip_math as cm
rig,meshes,_,_=p.load_hero(str(Path('App/Resources/Heroes/Hero_H025.usdz').resolve()))
a.bind_usd_axes(rig,'App/Resources/Heroes/Hero_H025.usdz')
clip=p.load_clips('App/Resources/Heroes/H025MotionClips.json')['h025_death']
print('SECONDARY_ROLES',[(i,r) for i,r in enumerate(rig.roles) if 'cape' in (r or '') or 'hair' in (r or '')])
x=[0.0]*9; v=[0.0]*9; minima=[]
for f in range(91):
    t=f/60; blend=a.smooth((t-.25)/.5)
    d=h.details_at(clip,min(72,f))
    for i,name in enumerate(['capel1','capel2','capel3','caper1','caper2','caper3','hair1','hair2','hair3']):
        dep=i%3
        base=-.035 if i<6 else -.025
        if dep>0: base+=x[i-1]*.18
        goal=(.58 if dep==0 else .04) if i<6 else (.85 if dep==0 else .04)
        target=base+(goal-base)*blend
        omega=[16,12,9][dep]; decay=.72*omega; damp=omega*math.sqrt(1-.72**2); dt=1/60
        e=math.exp(-decay*dt); c=math.cos(damp*dt); s=math.sin(damp*dt); err=x[i]-target
        x[i],v[i]=target+e*(err*c+(v[i]+decay*err)*s/damp), e*(v[i]*c-(decay*v[i]+omega*omega*err)*s/damp)
        # The USD-added bones have identity world bind rotation.
        d[name]=Quaternion((1,0,0),x[i])
    q,root=cm.interp_clip(clip,min(72,f))
    dr,pos=a.solve(rig,q,root*rig.leg_length,d)
    rig.apply_pose(dr,pos);bpy.context.view_layer.update()
    minima.append(p.lowest_highest(meshes,rig.M)[0])
print('DEATH_SECONDARY_MIN',min(minima),'FINAL',minima[-1])
Path('build/h025-quality/death-secondary-audit.json').write_text(json.dumps({'minMeshY':min(minima),'endMeshY':minima[-1],'note':'Offline approximation of the runtime death springs; no body collision solver.'},indent=2))
