"""10/26 Saber reference: dual grip, low dash, airborne three-strike cast.

Uses the shipped rig and the existing grounded walk/run/normal attacks. Root XZ,
combat hit times and dash distance remain owned by simulation. 30 Hz clips only;
no runtime IK allocation, physics or per-hero update loop.
Run from VELSTRIA: blender -b -t 4 -P tools/blender/author_h028_quality_motion.py
"""
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Quaternion, Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_h028_motion as h
import author_h025_motion as a
import clip_math as cm
import preview_clip as preview
V=Vector
S=cm.SEG_INDEX
FPS=30


def curve(t,keys): return a.curve(t,keys)


def vec(t,keys):
    return V(tuple(curve(t,[(x,p[i]) for x,p in keys]) for i in range(3)))


def left_blade(rig,fr,direction):
    _,p=h.solve(rig,fr.qs,fr.off,{})
    wrist=p[rig.index['lefthand']]
    fore=wrist-p[rig.index['leftforearm']]
    d=h.clamp_wrist(direction,fore)
    if h.body_clearance(rig,p,wrist,d,length=.82)<.035:
        choices=[Quaternion(fore.normalized(),math.radians(x))@d for x in (20,-20,40,-40,70,-70,100,-100)]
        d=max([d]+choices,key=lambda x:h.body_clearance(rig,p,wrist,x,length=.82))
    q=fr.qs[S['handL']]
    fr.qs[S['handL']]=(cm.rotation_between(q@V((0,0,-1)),d)@q).normalized()


def hands(rig,fr,right,left,bladeR,bladeL):
    _,p=h.solve(rig,fr.qs,fr.off,{})
    Y=h.ry(h.yaw_of(fr.qs[S['torso']]))
    # Project the reference reach onto this rig's arm length before solving.
    def reach(side,delta):
        chain=[rig.P0[rig.index[side+x]] for x in ('arm','forearm','hand')]
        span=(chain[1]-chain[0]).length+(chain[2]-chain[1]).length-.006
        return p[rig.index[side+'arm']]+Y@(delta*min(1,span/max(.001,delta.length)))
    er=h.arm_ik(rig,fr,'R',reach('right',right),Y@V((1,-.2,.4)))
    el=h.arm_ik(rig,fr,'L',reach('left',left),Y@V((-1,-.1,.4)))
    h.set_blade(rig,fr,Y@bladeR.normalized())
    left_blade(rig,fr,Y@bladeL.normalized())
    return max(er,el)


def pose(rig,ground,guard,kind,t,total):
    fr=h.copy_frame(guard)
    armR=V((.10,-.32,-.04)); armL=V((-.045,-.34,.02))
    bladeR=V((.76,-.62,-.20)); bladeL=V((-.76,-.62,-.20))
    yaw=lean=bank=drop=air=spread=0
    if kind=='skill1':
        spread=curve(t,[(0,0),(.07,.3),(.20,1),(.34,.9),(.60,.35),(total,0)])
        yaw=curve(t,[(0,0),(.08,-.50),(.20,.35),(.38,.10),(total,0)])
        lean=-.09*spread; drop=-.06*spread
        armR=armR.lerp(V((.36,-.12,-.12)),spread)
        armL=armL.lerp(V((-.36,-.08,-.08)),spread)
        bladeR=bladeR.lerp(V((.92,.06,-.28)),spread)
        bladeL=bladeL.lerp(V((-.92,.06,-.28)),spread)
    elif kind=='skill2':
        drive=curve(t,[(0,0),(.06,1),(.20,1),(.30,.30),(.65,.20),(total,0)])
        ready=curve(t,[(0,0),(.20,0),(.29,1),(.62,1),(total,0)])
        yaw=-.15*drive-.38*ready; lean=-.61*drive-.10*ready; drop=-.15*drive-.055*ready
        armR=armR.lerp(V((.10,-.12,-.36)),drive).lerp(V((.16,.04,-.21)),ready)
        armL=armL.lerp(V((-.30,-.13,.27)),drive).lerp(V((-.18,-.23,-.14)),ready)
        bladeR=bladeR.lerp(V((.15,.12,-1)),drive).lerp(V((.1,.85,-.45)),ready)
        bladeL=bladeL.lerp(V((-.3,-.1,.94)),drive)
        spread=drive
    else:
        empowered=kind=='empowered'
        A=.30 if empowered else 10/30
        if empowered:
            drop=curve(t,[(0,0),(.08,-.10),(.21,.16),(.30,.02),(.39,-.15),(.60,-.035),(total,0)])
            air=curve(t,[(0,0),(.10,0),(.20,.27),(.27,.21),(.36,0),(total,0)])
            yaw=curve(t,[(0,0),(.18,-.40),(.30,.45),(.48,.20),(total,0)])
            lean=curve(t,[(0,0),(.18,.10),(.30,-.48),(.42,-.25),(total,0)])
            armR=vec(t,[(0,armR),(.17,(.17,.25,-.04)),(.30,(.10,-.14,-.34)),(.42,(.23,-.35,-.06)),(total,armR)])
            armL=armL.lerp(V((-.30,-.08,.20)),curve(t,[(0,0),(.18,1),(.39,.8),(total,0)]))
            bladeR=vec(t,[(0,bladeR),(.17,(.15,.95,-.25)),(.30,(-.12,-.60,-.85)),(.43,(.8,-.5,-.2)),(total,bladeR)])
        else:
            drop=curve(t,[(0,0),(.12,-.14),(A,.26),(A+.19,.43),(A+.39,.36),(A+.59,.46),(A+.78,.13),(A+.90,-.14),(A+1,-.04),(total,0)])
            air=curve(t,[(0,0),(.16,0),(A,.43),(A+.20,.67),(A+.39,.58),(A+.60,.66),(A+.78,.30),(A+.91,0),(total,0)])
            yaw=curve(t,[(0,0),(A-.08,-.24),(A,.25),(A+.22,.65),(A+.39,-.60),(A+.60,-.40),(A+.78,.40),(A+1,.20),(total,0)])
            lean=curve(t,[(0,0),(.15,-.52),(A,-.16),(A+.39,-.12),(A+.60,.10),(A+.78,-.48),(A+.95,-.27),(total,0)])
            bank=curve(t,[(0,0),(A,-.10),(A+.39,.18),(A+.78,-.07),(total,0)])
            armR=vec(t,[(0,armR),(.18,(.12,-.12,-.32)),(A-.07,(.23,-.26,-.04)),(A,(.10,.03,-.35)),
                        (A+.18,(-.04,.20,-.22)),(A+.39,(.29,-.04,-.23)),(A+.60,(.15,.28,-.02)),
                        (A+.78,(.06,-.10,-.35)),(A+.94,(.26,-.32,-.03)),(total,armR)])
            armL=vec(t,[(0,armL),(.16,(-.28,-.14,.23)),(A,(-.27,.08,.14)),(A+.20,(-.25,.15,-.12)),
                        (A+.39,(-.12,-.03,-.34)),(A+.60,(-.23,.20,.03)),(A+.78,(-.30,-.15,.18)),(total,armL)])
            bladeR=vec(t,[(0,bladeR),(.18,(.1,.2,-1)),(A-.07,(.2,-.45,-.7)),(A,(-.45,.65,-.8)),
                          (A+.18,(.70,.4,-.70)),(A+.39,(1,-.1,-.6)),(A+.60,(.1,1,-.2)),
                          (A+.78,(-.15,-.65,-.8)),(A+.94,(.5,-.5,-.6)),(total,bladeR)])
            bladeL=vec(t,[(0,bladeL),(.18,(-.5,-.15,.8)),(A,(-.8,.4,.2)),(A+.20,(-.8,.3,-.4)),
                          (A+.39,(-.7,.05,-.7)),(A+.60,(-.4,.8,-.4)),(A+.78,(-.6,-.2,.8)),(total,bladeL)])
        spread=curve(t,[(0,0),(.14,.65),(A,1),(total-.22,.55),(total,0)])
    fr.off=guard.off+V((0,drop,0))
    fr.qs[S['hips']]=h.ry(yaw*.55)@a.axis((1,0,0),lean*.30)
    fr.qs[S['torso']]=h.ry(yaw)@a.axis((1,0,0),lean)@a.axis((0,0,1),bank)
    fr.qs[S['head']]=h.ry(yaw*.18)@a.axis((1,0,0),lean*.23)
    for side,sign in [('R',1),('L',-1)]:
        fr.foot[side]=guard.foot[side]+V((sign*.045*spread,air*(1 if side=='R' else 1.12),sign*.10*spread))
        fr.contact[side]=air<.005
        fr.qs[S['foot'+side]]=h.ry(yaw*.20)@a.axis((1,0,0),-.32*min(1,air/.4))@rig.seg_C('foot'+side).inverted()
    err=h.solve_legs(rig,fr,ground)
    err=max(err,hands(rig,fr,armR,armL,bladeR,bladeL))
    # Exact common guard at both ends avoids a last-frame wrist pop.
    edge=min(a.smooth(t/.07),a.smooth((total-t)/.16))
    if edge<1: h.blend_pose(fr,guard,1-edge)
    return fr,err


def build(rig,ground,guard,kind):
    total={'skill1':.95,'skill2':.95,'ultimate':(10/30+1.25),'empowered':.80}[kind]
    name={'skill1':'sword_whirl_h028','skill2':'dash_charge_h028','ultimate':'sword_triple_h028','empowered':'sword_dive_h028'}[kind]
    events={'impact':3.6}
    extra={}
    if kind=='skill1': events['release']=6
    elif kind=='skill2': events['arrive']=6; extra['lockLowerUntil']=10
    elif kind=='ultimate': events.update(hit=10,strike2=21.7,strike3=33.4); extra['lockLowerUntil']=40
    else: events=dict(impact=9,release=9,end=24); extra['lockLowerUntil']=13
    count=int(round(total*FPS))+1
    frames=[]; errors=[]
    for i in range(count):
        fr,err=pose(rig,ground,guard,kind,min(total,i/FPS),total)
        frames.append(fr); errors.append(err)
    return dict(name=name,frames=frames,dets=[h.details_for(rig,fr,h.relaxed(.88)) for fr in frames],
                loop=False,events=events,melee=kind=='empowered',source='reference-2026-10-26',extra=extra,ik=max(errors))


def collapse(rig,meshes,guard):
    frames=[];details=[]
    for i in range(37):
        t=i/FPS
        fall=curve(t,[(0,0),(.14,.07),(.34,.25),(.68,.92),(.90,1),(1.2,1)])
        sink=curve(t,[(0,0),(.16,.12),(.38,.5),(.72,1),(1.2,1)])
        fr=h.copy_frame(guard)
        fr.off=guard.off+V((.025*fall,-.73*sink,.11*fall))
        for seg,angle in [('hips',-1.43),('torso',-1.51),('head',-1.43)]:
            fr.qs[S[seg]]=cm.slerp(guard.qs[S[seg]],a.axis((1,0,0),angle),fall)
        for side,thigh,shin in [('R',1.35,-1.68),('L',1.50,-1.50)]:
            fr.qs[S['thigh'+side]]=cm.slerp(guard.qs[S['thigh'+side]],a.axis((1,0,0),thigh),sink)
            fr.qs[S['shin'+side]]=cm.slerp(guard.qs[S['shin'+side]],a.axis((1,0,0),shin),sink)
            fr.qs[S['foot'+side]]=a.axis((1,0,0),-.15*fall)@rig.seg_C('foot'+side).inverted()
        _,p0=h.solve(rig,guard.qs,guard.off,{})
        for side,pre,target,pole in [('R','right',(.32,.15,-.38),(1,.15,.4)),('L','left',(-.34,.18,-.30),(-1,.15,.4))]:
            wrist=p0[rig.index[pre+'hand']].lerp(V(target),fall)
            h.arm_ik(rig,fr,side,wrist,V(pole))
        h.set_blade(rig,fr,(guard.qs[S['handR']]@V((0,0,-1))).lerp(V((.92,.07,-.35)),fall))
        left_blade(rig,fr,(guard.qs[S['handL']]@V((0,0,-1))).lerp(V((-.92,.07,-.35)),fall))
        d=h.details_for(rig,fr,h.relaxed(.75))
        # Check weighted geometry including the final draped cloth/hair. Keep
        # the last pose supported instead of freezing a falling source frame.
        drape=dict(d)
        for chain in ['capel','caper','hair']:
            for depth in range(3):
                role=chain+str(depth+1)
                if role in rig.index:
                    angle=(.85 if chain=='hair' else .58) if depth==0 else .04
                    drape[role]=a.axis((1,0,0),angle*fall)
        dr,points=h.solve(rig,fr.qs,fr.off,drape)
        rig.apply_pose(dr,points);bpy.context.view_layer.update()
        low,_=preview.lowest_highest(meshes,rig.M)
        fr.off.y+=max(0,.006-low)
        frames.append(fr);details.append(d)
    return dict(name='collapse_h028',frames=frames,dets=details,loop=False,events=dict(end=36),
                melee=False,source='reference-finish-2026-10-26',extra={},ik=0)


def hit(rig,guard):
    frames=[]
    for i in range(10):
        bump=curve(i/FPS,[(0,0),(.055,1),(.13,.45),(.30,0)])
        fr=h.copy_frame(guard)
        fr.qs[S['torso']]=a.axis((1,0,0),.15*bump)@fr.qs[S['torso']]
        fr.qs[S['head']]=a.axis((1,0,0),.20*bump)@fr.qs[S['head']]
        frames.append(fr)
    return dict(name='hit_h028',frames=frames,dets=[h.details_for(rig,fr,h.relaxed(.88)) for fr in frames],
                loop=False,events={},melee=False,source='reference-finish-2026-10-26',extra={},ik=0)


def main():
    rig,meshes,height,_=preview.load_hero(str(Path(h.HERO).resolve()))
    h.bind_usd_axes(rig,h.HERO)
    data=json.loads(Path(h.SOURCE).read_text())
    srcs={c['name'].replace('h028src_',''):h.Source(c) for c in data['clips']}
    ground=min(rig.P0[rig.index[s+'foot']].y for s in ('left','right'))
    idle=h.build_idle(rig,srcs,ground)
    built=[idle,h.build_loco(rig,srcs,ground,'walk'),h.build_loco(rig,srcs,ground,'run')]
    # The left blade shares the authored hand grip and follows the free arm.
    for c in built:
        for fr in c['frames']:
            Y=h.ry(h.yaw_of(fr.qs[S['torso']]))
            left_blade(rig,fr,Y@V((-.76,-.62,-.20) if c is idle else (-.4,-.4,.8)))
        c['dets']=[h.details_for(rig,fr,h.relaxed(.88)) for fr in c['frames']]
    guard=h.copy_frame(idle['frames'][0])
    from h028_specs import action_specs
    for spec in action_specs(math,V,h.relaxed)[:3]:
        c=h.build_action(rig,srcs,ground,guard,spec)
        for fr in c['frames']:
            left_blade(rig,fr,h.ry(h.yaw_of(fr.qs[S['torso']]))@V((-.75,-.40,.40)))
        c['dets']=[h.details_for(rig,fr,h.relaxed(.88)) for fr in c['frames']]
        built.append(c)
    for kind in ('skill1','skill2','ultimate','empowered'): built.append(build(rig,ground,guard,kind))
    built.extend([hit(rig,guard),collapse(rig,meshes,guard)])
    clips=[h.to_clip(rig,c) for c in built]
    Path('App/Resources/Heroes/H028MotionClips.json').write_text(json.dumps(dict(version=1,fps=FPS,segments=cm.SEGMENTS,clips=clips),separators=(',',':'))+'\n')
    report={c['name']:dict(frames=len(c['frames']),maxTargetClampMm=round(c['ik']*1000,3),events=c['events']) for c in built}
    Path('build/hero-reference-1026/saber-motion-report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report),flush=True)


if __name__=='__main__': main()
