"""Reproducible H028 material/secondary-rig finish, retaining UVs and texture bytes.

blender -b -P tools/blender/finish_h028_model.py -- [--source old.usdz] [--inspect]
Default source is the immutable 68889332 asset, not the already processed output.
USD is edited directly so existing bind axes, face-varying normals and skinning
are preserved. No cloud generation, texture repaint, geometry edits or subdivision. Original 9,723 triangles remain.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

import bpy
import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, UsdUtils, Vt

SOURCE_SHA = '050c47452515d48c1f7b5d77df0d08faa37aac4990e55d0f2a8fe7c80e8c4242'
SOURCE_GIT = '68889332:VELSTRIA/App/Resources/Heroes/Hero_H028.usdz'
OUT = Path('build/h028-quality')
SURFACES = {
    'cloth': dict(roughness=.86, metallic=0, tint=(1.04, .95, .96, 1)),
    'skin': dict(roughness=.57, metallic=0, tint=(1.02, 1.00, .98, 1)),
    'hair': dict(roughness=.43, metallic=0, tint=(1.06, 1.08, 1.12, 1)),
    'metal': dict(roughness=.34, metallic=.72, tint=(.95, 1.06, 1.18, 1)),
    'leather': dict(roughness=.72, metallic=.03, tint=(.90, .95, 1.02, 1)),
}


def smooth(x):
    x=max(0,min(1,float(x)))
    return x*x*(3-2*x)


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--source')
    ap.add_argument('--out',default='App/Resources/Heroes/Hero_H028.usdz')
    ap.add_argument('--inspect',action='store_true')
    a=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    OUT.mkdir(parents=True,exist_ok=True)
    data=Path(a.source).read_bytes() if a.source else subprocess.check_output(['git','show',SOURCE_GIT])
    assert hashlib.sha256(data).hexdigest()==SOURCE_SHA, 'Use the documented original; refusing to apply twice.'
    with tempfile.TemporaryDirectory(prefix='h028_finish_') as temp:
        temp=Path(temp)
        source=temp/'source.usdz'; source.write_bytes(data)
        with zipfile.ZipFile(source) as z:
            z.extractall(temp/'usd')
            root=temp/'usd'/z.namelist()[0]
        stage=Usd.Stage.Open(str(root))
        mesh=next(UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh))
        skeleton=next(UsdSkel.Skeleton(p) for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton))
        binding=UsdSkel.BindingAPI(mesh.GetPrim())
        points=np.array(mesh.GetPointsAttr().Get(),dtype=np.float64)
        faces=np.array(mesh.GetFaceVertexIndicesAttr().Get()).reshape(-1,3)
        assert set(mesh.GetFaceVertexCountsAttr().Get())=={3}
        indices=np.array(binding.GetJointIndicesPrimvar().Get(),dtype=int).reshape(-1,4)
        weights=np.array(binding.GetJointWeightsPrimvar().Get(),dtype=np.float64).reshape(-1,4)
        joints=list(skeleton.GetJointsAttr().Get())
        binds=list(skeleton.GetBindTransformsAttr().Get())
        rests=list(skeleton.GetRestTransformsAttr().Get())
        original_bones=len(joints)
        short=[n.rsplit('/',1)[-1].replace('mixamorig_','') for n in joints]
        uv=np.array(UsdGeom.PrimvarsAPI(mesh.GetPrim()).GetPrimvar('st').ComputeFlattened())
        uv=uv.reshape(-1,3,2).mean(axis=1) if len(uv)==len(faces)*3 else uv[faces].mean(axis=1)
        colorpath=next((temp/'usd'/'textures').glob('Color_*'))
        im=bpy.data.images.load(str(colorpath))
        pixels=np.empty(len(im.pixels),dtype=np.float32); im.pixels.foreach_get(pixels)
        pixels=pixels.reshape(im.size[1],im.size[0],4)
        rgb=pixels[(uv[:,1]*im.size[1]).astype(int)%im.size[1],(uv[:,0]*im.size[0]).astype(int)%im.size[0],:3]
        centers=points[faces].mean(axis=1)
        bone_weight=np.zeros((len(points),len(joints)))
        for v in range(len(points)):
            for j,w in zip(indices[v],weights[v]): bone_weight[v,j]+=w
        headweight=bone_weight[:,short.index('Head')][faces].mean(axis=1)
        labels=[]; regions=[]
        for (x,y,z),(r,g,b),hw in zip(centers,rgb,headweight):
            red = r>g*1.45 and r>b*1.35
            skin = y>1.38 and z<.055 and .12<b<.65 and r>b*1.12 and r<g*1.65
            hair = max(r,g,b)-min(r,g,b)<.21 and max(r,g,b)>.45 and y>1.40 and (hw>.3 or z>.10)
            cape = .85<y<1.53 and z>.075 and red
            if hair: label='hair'
            elif cape: label='cloth'
            elif skin: label='skin'
            elif max(r,g,b)<.22: label='leather'
            else: label='metal'
            labels.append(label)
            regions.append('hair' if hair else 'cape' if cape else 'body')
        # Vertex membership is shared by all adjacent triangles, preventing cracks.
        votes={r:np.zeros(len(points)) for r in ['hair','cape','body']}
        total=np.zeros(len(points))
        for f,region in zip(faces,regions):
            for v in f: votes[region][v]+=1; total[v]+=1
        for region in votes: votes[region]/=np.maximum(total,1)

        def bone(name,parent,pos):
            j=len(joints); pi=short.index(parent)
            joints.append(joints[pi]+'/'+name); short.append(name)
            bind=Gf.Matrix4d(1); bind.SetTranslate(Gf.Vec3d(*pos))
            binds.append(bind); rests.append(bind*binds[pi].GetInverse())
            return j
        chains={}
        for side,sign in [('L',-1),('R',1)]:
            parent='Spine2'; chain=[]
            for k,(y,z) in enumerate([(1.45,.10),(1.32,.32),(1.22,.55)]):
                name=f'Cape{side}{k+1}'; chain.append(bone(name,parent,(sign*.10,y,z))); parent=name
            chains['cape'+side]=chain
        parent='Head'; chain=[]
        for k,pos in enumerate([(0,1.65,.07),(0,1.70,.23),(0,1.68,.48)]):
            name=f'Hair{k+1}'; chain.append(bone(name,parent,pos)); parent=name
        chains['hair']=chain
        def along(chain,u):
            u=max(0,min(len(chain)-1,float(u))); k=min(len(chain)-1,int(u)); f=u-k
            return {chain[k]:1-f, chain[min(len(chain)-1,k+1)]:f} if f>0 else {chain[k]:1}
        changed={r:0 for r in ['cape','hair']}
        for v,(x,y,z) in enumerate(points):
            old={int(j):float(w) for j,w in zip(indices[v],weights[v]) if w>1e-6}
            replacement={}; amount=0
            for region in ['cape','hair']:
                member=votes[region][v]
                if member<.35: continue
                if region=='cape':
                    amount=member*smooth((z-.075)/.16)
                    right=smooth((x+.10)/.20)
                    for side,w in [('L',1-right),('R',right)]:
                        for j,vw in along(chains['cape'+side],(z-.10)/.22).items(): replacement[j]=replacement.get(j,0)+w*vw
                elif region=='hair':
                    amount=member*smooth((z-.075)/.15)
                    replacement=along(chains['hair'],(z-.07)/.20)
                if amount>.01: changed[region]+=1
                break
            new={j:w*(1-amount) for j,w in old.items()}
            for j,w in replacement.items(): new[j]=new.get(j,0)+amount*w
            best=sorted(new.items(),key=lambda p:-p[1])[:4]
            norm=sum(w for _,w in best)
            best += [(0,0)]*(4-len(best))
            indices[v]=[j for j,_ in best]; weights[v]=[w/norm for _,w in best]
        skeleton.GetJointsAttr().Set(Vt.TokenArray(joints))
        skeleton.GetBindTransformsAttr().Set(Vt.Matrix4dArray(binds))
        skeleton.GetRestTransformsAttr().Set(Vt.Matrix4dArray(rests))
        binding.GetJointIndicesPrimvar().Set(Vt.IntArray(indices.ravel().tolist()))
        binding.GetJointWeightsPrimvar().Set(Vt.FloatArray(weights.ravel().tolist()))
        # Any bound rest animation must agree with the extended skeleton.
        for prim in stage.Traverse():
            if prim.IsA(UsdSkel.Animation): stage.RemovePrim(prim.GetPath())
        UsdSkel.BindingAPI(skeleton.GetPrim()).GetAnimationSourceRel().ClearTargets(True)

        base=next(p.GetPath() for p in stage.Traverse() if p.IsA(UsdShade.Material))
        counts={}
        for label,settings in SURFACES.items():
            path=base.GetParentPath().AppendChild('H028_'+label)
            Sdf.CopySpec(stage.GetRootLayer(),base,stage.GetRootLayer(),path)
            # CopySpec does not retarget connections inside the copied network.
            for prim in Usd.PrimRange(stage.GetPrimAtPath(path)):
                for attr in prim.GetAttributes():
                    connections=attr.GetConnections()
                    if connections: attr.SetConnections([Sdf.Path(str(c).replace(str(base),str(path))) for c in connections])
            shader=UsdShade.Shader(stage.GetPrimAtPath(path.AppendChild('Principled_BSDF')))
            for prop in ['roughness','metallic']:
                i=shader.GetInput(prop); i.DisconnectSource(); i.Set(settings[prop])
            tex=UsdShade.Shader(stage.GetPrimAtPath(path.AppendChild('Image_Texture')))
            tex.CreateInput('scale',Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(*settings['tint']))
            selected=[i for i,l in enumerate(labels) if l==label]; counts[label]=len(selected)
            subset=UsdGeom.Subset.CreateGeomSubset(mesh,'surface_'+label,UsdGeom.Tokens.face,Vt.IntArray(selected),
                                                   'materialBind',UsdGeom.Tokens.partition)
            UsdShade.MaterialBindingAPI.Apply(subset.GetPrim()).Bind(UsdShade.Material(stage.GetPrimAtPath(path)))
        stage.GetRootLayer().Save()
        out=Path(a.out).resolve(); out.parent.mkdir(parents=True,exist_ok=True)
        if out.exists(): out.unlink()
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(root)),str(out))
        report={'sourceSHA256':SOURCE_SHA,'outputSHA256':hashlib.sha256(out.read_bytes()).hexdigest(),
                'triangles':len(faces),'vertices':len(points),'bonesBefore':original_bones,'bonesAfter':len(joints),
                'surfaceTriangles':counts,'secondaryWeightedVertices':changed,'weightSumError':float(np.max(abs(weights.sum(axis=1)-1))),
                'textures':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (temp/'usd'/'textures').iterdir()},
                'note':'No new raster assets; UVs and original texture bytes retained. Surface tint is a material parameter.'}
        (OUT/'model-report.json').write_text(json.dumps(report,indent=2))
        print(json.dumps(report),flush=True)
    if a.inspect:
        sys.path.insert(0,str(Path(__file__).resolve().parent))
        import preview_clip as p
        from mathutils import Vector
        r,meshes,h,w=p.load_hero(str(out))
        p.VIEWS['back']=Vector((0,.12,1))
        for view in ['front','side','back']:
            label=p.setup_scene(r,h,view,(600,720)); label.data.body='H028 model / '+view
            bpy.context.scene.render.filepath=str((OUT/('model-'+view+'.png')).resolve())
            bpy.ops.render.render(write_still=True)
        print('Inspection renders use Blender Workbench (shape only, not PBR).',flush=True)


if __name__=='__main__': main()
