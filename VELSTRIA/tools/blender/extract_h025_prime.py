"""Extract the generated Meshy prime SMPL-H FBX without changing the general GLB extractor.

Blender --python tools/blender/extract_h025_prime.py -- --input <clip.fbx>
  --out <15-segment.json> --report <report.json> --details <details.json>
Uses the same source_frame/eval_at/round-trip math as extract_clips.py.
"""
import argparse
import json
import math
import os
import re
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clip_math as cm
import extract_clips as ec


SMPLH_TO_MIXAMO = {"Pelvis":"Hips", "Spine1":"Spine", "Spine2":"Spine1", "Spine3":"Spine2", "Neck":"Neck", "Head":"Head"}
for prefix, side in (("L_","Left"),("R_","Right")):
    for source, target in (("Hip","UpLeg"),("Knee","Leg"),("Ankle","Foot"),("Foot","ToeBase"),
                           ("Collar","Shoulder"),("Shoulder","Arm"),("Elbow","ForeArm"),("Wrist","Hand")):
        SMPLH_TO_MIXAMO[prefix+source] = side+target
    for finger in ("Thumb","Index","Middle","Ring","Pinky"):
        for number in (1,2,3):
            SMPLH_TO_MIXAMO[prefix+finger+str(number)] = side+"Hand"+finger+str(number)


def xyzw(q):
    q=q.normalized()
    return [round(q.x,6),round(q.y,6),round(q.z,6),round(q.w,6)]


def write(filename, value):
    os.makedirs(os.path.dirname(os.path.abspath(filename)),exist_ok=True)
    with open(filename,"w",encoding="utf-8") as handle:
        json.dump(value,handle,separators=(",",":"))


def run(args):
    ec.nc.reset_scene()
    bpy.ops.import_scene.fbx(filepath=os.path.abspath(args.input))
    arm=max((o for o in bpy.data.objects if o.type=='ARMATURE'),key=lambda a:len(a.data.bones))
    if "Pelvis" not in arm.data.bones or "L_Wrist" not in arm.data.bones:
        raise SystemExit("Expected Meshy prime SMPL-H skeleton; inspect the source before remapping")
    ec.role_names=lambda _:SMPLH_TO_MIXAMO
    rig,facing=ec.source_frame(arm,args.input)
    action=arm.animation_data.action
    first,last=map(float,action.frame_range)
    fps=bpy.context.scene.render.fps/bpy.context.scene.render.fps_base
    offset=first-1.0
    clip={"name":args.name, "source":{"file":args.input},"_label":f"meshy:text-to-motion:{args.task_id}",
          "_path":args.input,"start":1,"end":last-offset,"loop":False,"inPlace":True,"rootXZ":0}
    output,report,passed=ec.extract(clip,rig,arm,fps,(1.0,last-offset),offset)
    if not passed:
        raise SystemExit(f"Source roundtrip verification failed: {report['verify']}")
    # SMPL-H FBX animation carries its own bind-origin lift. Keep relative breath/body
    # movement rather than transferring that fixed offset onto the target hero.
    baseline_y=output['root'][1]
    report['sourceRootRange']=dict(report['rootRange'])
    for i in range(1,len(output['root']),3):
        output['root'][i]=round(output['root'][i]-baseline_y,4)
    report['rootRange']={**report['rootRange'],'y':[min(output['root'][1::3]),max(output['root'][1::3])]}
    report['rootRebase']={'axis':'y','baselineLegUnits':baseline_y,'verificationBeforeRebase':True,
                          'reason':'Remove fixed SMPL-H animation bind-origin lift; preserve relative motion.'}
    write(args.out,{"version":1,"fps":30,"segments":cm.SEGMENTS,"clips":[output]})
    times,start,end,step=ec.sample_times(clip,1,last-offset,fps)
    indices=[i for i,r in enumerate(rig.roles) if r in ("leftshoulder","rightshoulder","lefttoebase","righttoebase")
             or re.fullmatch(r"(?:left|right)hand(?:thumb|index|middle|ring|pinky)[123]",r)]
    rotations,previous,features=[],{},[]
    for time in times:
        dR,P=ec.eval_at(arm,rig,time+offset)
        relative={}
        for i in indices:
            parent=rig.parent[i]
            q=(dR[parent].inverted()@dR[i]) if parent>=0 else dR[i].copy()
            q.normalize()
            if (i in previous and q.dot(previous[i])<0) or (i not in previous and q.w<0):q=cm.neg(q)
            previous[i]=q
            rotations.extend(xyzw(q))
            relative[rig.roles[i]]=q
        head=P[rig.index['head']]
        left=P[rig.index['lefthand']]
        right=P[rig.index['righthand']]
        bow_axis=(left-head).normalized() if (left-head).length>1e-6 else left-head
        finger_curl=sum(math.degrees(relative['righthandindex'+str(n)].angle) for n in (1,2,3))
        features.append({"sourceFrame":time,"drawSpan":round((left-right).dot(bow_axis),6),
                         "rightHandHeadDistance":round((right-head).length,6),"rightIndexRestAngleSum":round(finger_curl,4),
                         "positions":{r:[round(v,6) for v in P[rig.index[r]]] for r in ('hips','head','leftarm','leftforearm','lefthand','rightarm','rightforearm','righthand','leftupleg','leftleg','leftfoot','rightupleg','rightleg','rightfoot')}})
    detail={"version":1,"fps":30,"rotationSpace":"parentRelativeRestDeltaHeroAxes","clips":[{
        "name":clip['name'],"source":clip['_label'],"frames":len(times),"sourceDetails":{
            "roles":[rig.roles[i] for i in indices],"parentRoles":[rig.roles[rig.parent[i]] for i in indices],
            "rot":rotations,"sourceRestGlobalRot":[v for i in indices for v in xyzw(rig.qM@rig.q0w[i])]}}]}
    write(args.details,detail)
    report.update({"sourceSkeleton":"SMPL-H","bones":len(rig.names),"boneMapping":SMPLH_TO_MIXAMO,"action":action.name,
                   "actionFrameRange":[first,last],"sourceFps":fps,"facing":facing,"legLength":rig.leg_length,
                   "features":features,"releaseEstimate":({"sourceFrame":args.release_estimate,"uncertaintyFrames":4,
                       "basis":"Visual aim-to-follow-through estimate, not a source animation event; generated fingers are static."} if args.release_estimate else
                       "Inspect the draw/hand/finger feature curves and target-model preview before assigning a release event.")})
    write(args.report,report)
    print(f"[prime] {len(rig.names)} bones, {len(times)} frames, {fps}fps, {len(indices)} detail roles",flush=True)
    print(f"[prime] roundtrip limb max {report['verify']['limbMaxDegrees']} degrees; wrote {args.out}",flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--input',required=True)
    parser.add_argument('--out',required=True)
    parser.add_argument('--report',required=True)
    parser.add_argument('--details',required=True)
    parser.add_argument('--task-id',default='01a1640b-0d5b-7455-b14f-dfc020cdedee')
    parser.add_argument('--release-estimate',type=float)
    parser.add_argument('--name',default='meshy_h025_prime_bow')
    run(parser.parse_args(ec.nc.script_args()))
