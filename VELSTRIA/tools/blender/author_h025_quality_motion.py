"""H025 authored movement/combat set; gait rebuilt from contacts, not preset scaling.

60Hz authoring, explicit heel/ball pivots, asymmetric swing and body weight transfer.
Uses the existing rig solver/clip schema. Game displacement and hit times stay in sim.
Run: blender -b -t 4 -P tools/blender/author_h025_quality_motion.py
"""
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_h025_motion as a
import clip_math as cm
import preview_clip as preview

V=Vector
FPS=60
OUT=Path('build/h025-quality')


def spline(t,keys):
    """Cubic Hermite with explicit endpoint velocities; interior centred tangents."""
    for i in range(len(keys)-1):
        x,y,*dy=keys[i]; nx,ny,*ndy=keys[i+1]
        if t>nx: continue
        u=max(0,min(1,(t-x)/(nx-x))); d=nx-x
        m=dy[0] if dy else (ny-keys[max(0,i-1)][1])/(nx-keys[max(0,i-1)][0])
        n=ndy[0] if ndy else (keys[min(len(keys)-1,i+2)][1]-y)/(keys[min(len(keys)-1,i+2)][0]-x)
        return (2*u**3-3*u*u+1)*y+(u**3-2*u*u+u)*d*m+(-2*u**3+3*u*u)*ny+(u**3-u*u)*d*n
    return keys[-1][1]


def foot(rig,side,phase,running):
    """Ankle + foot orientation. Stance pivots are fixed in world travel space."""
    base=rig.P0[rig.index[side+'foot']].copy()
    duty=.38 if running else .62
    period=.60 if running else 1.0
    speed=3.375 if running else 1.25
    reach=speed*period*duty/2
    u=phase%1
    heel=.13 if running else .18
    push=-.48 if running else -.35
    heelPivot=V((0,-base.y,.045))
    ballPivot=V((0,-base.y,-.105))
    def plant(v):
        roll=heel*(1-a.smooth(v/.20))+push*a.smooth((v-.68)/.32)
        pivot=heelPivot if v<.5 else ballPivot
        compensation=pivot-a.axis((1,0,0),roll)@pivot
        return compensation,roll
    if u<duty:
        comp,roll=plant(u/duty)
        base.z=-reach+speed*period*u
        base+=comp
        contact=1
    else:
        v=(u-duty)/(1-duty)
        start,sr=plant(1); end,er=plant(0)
        tangent=speed*period*(1-duty)
        base.z=spline(v,[(0,reach+start.z,tangent),(.18,reach+.035),(.48,.025),
                         (.77,-reach*.86), (1,-reach+end.z,tangent)])
        peak=.28 if running else .085
        base.y+=spline(v,[(0,start.y,.10),(.24,peak,0),(.48,peak*.91),(.78,.055),
                          (1,end.y,-.03)])
        roll=spline(v,[(0,sr,0),(.25,-.90 if running else -.48),(.62,-.22),(.86,.17),(1,er,0)])
        contact=0
    base.x=(.095 if side=='right' else -.095)
    return base,roll,contact,duty


def idle(rig,sources,t):
    q,root,d,_=a.reference_pose(rig,sources,'idle',t)
    wave=math.sin(t*math.tau)
    offset=V((.009*wave,-.055+.003*math.cos(t*math.tau),0))
    q[0]=a.axis((0,1,0),-.045)@a.axis((0,0,1),.012*wave)
    q[1]=a.axis((0,1,0),-.16)@a.axis((1,0,0),-.025+.006*wave)
    return q,offset/rig.leg_length,d


def movement(rig,sources,state,t):
    q,_,d=idle(rig,sources,0)
    run=state=='run'
    wave=math.sin(t*math.tau)
    offset=V((.010*wave if run else .016*wave,
              -.106-.027*math.cos((t-.12)*math.tau*2) if run else -.067-.012*math.cos(t*math.tau*2),
              -.018 if run else 0))
    q[0]=a.axis((0,1,0),-.075*wave)@a.axis((1,0,0),-.055 if run else -.015)@a.axis((0,0,1),.022*wave)
    q[1]=a.axis((0,1,0),-.11+.075*wave)@a.axis((1,0,0),-.21 if run else -.055)@a.axis((0,0,1),-.014*wave)
    q[2]=a.axis((0,1,0),-.015)@a.axis((1,0,0),-.025)
    errors=[]
    for side,suffix,phase in [('right','R',t),('left','L',t+.5)]:
        target,roll,contact,duty=foot(rig,side,phase,run)
        q[cm.SEG_INDEX['foot'+suffix]]=a.axis((1,0,0),roll)@rig.seg_C('foot'+suffix).inverted()
        d[side+'toebase']=a.local_delta(rig,side+'toebase',a.axis((1,0,0),max(0,-roll)*(.85 if contact else .25)))
        errors.append(a.ik(rig,q,offset,d,[side+'upleg',side+'leg',side+'foot'],
                           ['thigh'+suffix,'shin'+suffix],target,V((0,.06,-1))))
    left=V((-.245,1.025+.018*wave,-.035+.065*wave))
    right=V((.17,1.095-.035*wave,-.12-.145*wave))
    if not run: right=V((.17,1.08-.020*wave,-.10-.08*wave))
    bow=a.axis((1,0,0),.32+.08*wave)@a.axis((0,0,1),-.12)
    q[8]=bow@a.axis((1,0,0),math.pi/2)
    q[5]=a.axis((1,0,0),1.1-.15*wave)
    errors.append(a.ik(rig,q,offset,d,['leftarm','leftforearm','lefthand'],['armL','foreArmL'],left,V((-.8,-.4,.15))))
    errors.append(a.ik(rig,q,offset,d,['rightarm','rightforearm','righthand'],['armR','foreArmR'],right,V((1,-.2,.35))))
    return q,offset/rig.leg_length,d,max(errors)


def combat(rig,sources,state,t):
    if state in ('skill2','ultimate'):
        return a.reference_pose(rig,sources,state,t)
    q,root,d=idle(rig,sources,0)
    offset=root*rig.leg_length
    seconds=t*({'attack':.90,'skill1':.50,'hit':.30,'death':1.20}[state])
    if state=='hit':
        bump=a.curve(seconds,[(0,0),(.055,1),(.13,.45),(.30,0)])
        q[1]=a.axis((1,0,0),.16*bump)@q[1]
        q[2]=a.axis((1,0,0),.22*bump)@q[2]
        return q,root,d,0
    if state=='death':
        fall=a.curve(seconds,[(0,0),(.12,.04),(.32,.20),(.68,.90),(.90,1),(1.20,1)])
        sink=a.curve(seconds,[(0,0),(.15,.10),(.38,.48),(.72,1),(1.20,1)])
        offset=V((.025*fall,-.055-.765*sink,.12*fall))
        q[0]=a.axis((1,0,0),-1.43*fall)
        q[1]=a.axis((1,0,0),-1.51*fall)@a.axis((0,1,0),-.16*(1-fall))
        q[2]=a.axis((1,0,0),-1.43*fall)@a.axis((0,1,0),.18*fall)
        for suffix,thigh,shin in [('R',1.35,-1.68),('L',1.50,-1.50)]:
            q[cm.SEG_INDEX['thigh'+suffix]]=cm.slerp(q[cm.SEG_INDEX['thigh'+suffix]],a.axis((1,0,0),thigh),sink)
            q[cm.SEG_INDEX['shin'+suffix]]=cm.slerp(q[cm.SEG_INDEX['shin'+suffix]],a.axis((1,0,0),shin),sink)
            q[cm.SEG_INDEX['foot'+suffix]]=a.axis((1,0,0),-.15*fall)@rig.seg_C('foot'+suffix).inverted()
        left=V((-.245,1.025,-.035)).lerp(V((-.34,.16,-.30)),fall)
        right=V((.17,1.10,-.14)).lerp(V((.29,.13,-.41)),fall)
        bow=cm.slerp(a.axis((1,0,0),.32),a.axis((0,0,1),-math.pi/2)@a.axis((1,0,0),.15),fall)
    else:
        attack=state=='attack'
        lift=a.curve(seconds,[(0,0),(.10,.40),(.22,1),(.35,1),(.55,.62),(.9,0)]) if attack else a.curve(seconds,[(0,0),(.12,1),(.22,1),(.5,0)])
        draw=a.curve(seconds,[(0,0),(.10,.1),(.24,1),(.30,1),(.33,.8),(.55,0),(.9,0)]) if attack else lift*.55
        recoil=a.curve(seconds,[(0,0),(.30,0),(.34,1),(.43,.5),(.60,0),(.9,0)]) if attack else 0
        offset.y-=.02*lift
        q[0]=a.axis((0,1,0),-.045-.10*lift)
        q[1]=a.axis((0,1,0),-.16-.42*lift)@a.axis((1,0,0),-.025-.02*lift)
        q[2]=a.axis((0,1,0),-.025)
        left=V((-.245,1.025,-.035)).lerp(V((-.115,1.275,-.355)),lift)
        right=V((.17,1.10,-.14)).lerp(V((.045,1.29,.055)),draw)+V((.055,.015,.045))*recoil
        if not attack: right=V((.17,1.10,-.14)).lerp(V((-.06,1.22,-.19)),draw)
        bow=cm.slerp(a.axis((1,0,0),.32)@a.axis((0,0,1),-.12),Quaternion(),lift)
        for finger in ('thumb','index','middle','ring','pinky'):
            for n in (1,2,3):
                role='righthand'+finger+str(n)
                if role in d:
                    hook=([18,28,20] if finger=='thumb' else [38,70,44])[n-1]
                    d[role]=a.local_delta(rig,role,a.axis((0,0,-1),math.radians(hook)*(.25+.75*draw)*(1-.88*recoil)))
    q[8]=bow@a.axis((1,0,0),math.pi/2)
    q[5]=a.axis((1,0,0),1.45)@a.axis((0,0,1),-.10)
    errors=[]
    errors.append(a.ik(rig,q,offset,d,['leftarm','leftforearm','lefthand'],['armL','foreArmL'],left,V((-.8,-.3,.12))))
    errors.append(a.ik(rig,q,offset,d,['rightarm','rightforearm','righthand'],['armR','foreArmR'],right,V((1,.12,.45))))
    if state!='death':
        for side,suffix in [('left','L'),('right','R')]:
            target=rig.P0[rig.index[side+'foot']].copy()
            target.x=-.11 if side=='left' else .11
            target.z+=-.065 if side=='left' else .065
            q[cm.SEG_INDEX['foot'+suffix]]=rig.seg_C('foot'+suffix).inverted()
            errors.append(a.ik(rig,q,offset,d,[side+'upleg',side+'leg',side+'foot'],['thigh'+suffix,'shin'+suffix],target,V((0,0,-1))))
    return q,offset/rig.leg_length,d,max(errors)


def main():
    rig,meshes,height,warnings=preview.load_hero(str(Path('App/Resources/Heroes/Hero_H025.usdz').resolve()))
    a.bind_usd_axes(rig,'App/Resources/Heroes/Hero_H025.usdz')
    sources=preview.load_clips('App/Resources/Heroes/HeroMotionClips.json')
    sources.update(preview.load_clips('tools/motion/h025-source-clips.json'))
    specs=[('idle',180,True),('walk',60,True),('run',36,True),('attack',55,False),
           ('skill1',31,False),('skill2',37,False),('ultimate',43,False),('hit',19,False),('death',73,False)]
    clips=[]; report={}
    for state,frames,loop in specs:
        names=[r for r in a.DETAILS if r in rig.index]
        c=dict(name='h025_bow_attack' if state=='attack' else 'h025_'+state,source='local:H025-quality-2026-10-23',
               frames=frames,loop=loop,rootXZ=0,melee=False,rot=[],root=[],detailJoints=names,detailRot=[],events={})
        if state=='attack': c['events']=dict(drawStart=9,release=18,impact=18,end=54); c['blend']=.055
        if state=='skill1': c['events']=dict(impact=0,end=30); c['blend']=.06
        if state=='skill2': c['events']=dict(drawStart=6,release=16,impact=16,end=36); c['blend']=.06
        if state=='ultimate': c['events']=dict(impact=6,end=42); c['lockLowerUntil']=32; c['blend']=.06
        if state in ('walk','run'): c['groundSpeed']=1.25 if state=='walk' else 3.375
        if state in ('idle','walk','run','death'): c['rootXZ']=1
        prev=[None]*15; pd=[None]*len(names); errors=[]
        for f in range(frames):
            t=f/(frames if loop else frames-1)
            if state in ('walk','run'): q,root,d,error=movement(rig,sources,state,t)
            elif state=='idle': q,root,d=idle(rig,sources,t); error=0
            else: q,root,d,error=combat(rig,sources,state,t)
            if state=='death':
                # Validate the actual weighted mesh, not just ankle pivots. The
                # collapse changes support from feet to knees and fingertips.
                dr,pos=a.solve(rig,q,root*rig.leg_length,d)
                rig.apply_pose(dr,pos)
                bpy.context.view_layer.update()
                low,_=preview.lowest_highest(meshes,rig.M)
                root.y+=max(0,.004-low)/rig.leg_length
            for i,quat in enumerate(q): vals,prev[i]=a.pack(quat,prev[i]); c['rot']+=vals
            c['root'] += [round(x,6) for x in root]
            for i,name in enumerate(names): vals,pd[i]=a.pack(d[name],pd[i]); c['detailRot']+=vals
            errors.append(error)
        clips.append(c)
        report[state]=dict(frames=frames,maxTargetClampMm=round(max(errors)*1000,3))
    Path('App/Resources/Heroes/H025MotionClips.json').write_text(json.dumps(dict(version=1,fps=FPS,segments=cm.SEGMENTS,clips=clips),separators=(',',':'))+'\n')
    OUT.mkdir(exist_ok=True,parents=True)
    (OUT/'motion-report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report),flush=True)


if __name__=='__main__': main()
