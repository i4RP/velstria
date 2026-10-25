"""Reduce the shared Saber blade so two copies cost less than the old single prop.

Edit only mesh topology/UVs/normals inside the original USD. Materials, textures,
transforms and the grip origin stay intact. Run in Blender from VELSTRIA/.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile
import bpy
from pxr import Gf,Sdf,Usd,UsdGeom,UsdUtils,Vt

OUT=Path('App/Resources/Heroes/Prop_photonBlade.usdz')
source=subprocess.check_output(['git','show','68889332:VELSTRIA/'+str(OUT)])
with tempfile.TemporaryDirectory(prefix='h028_blade_') as folder:
    folder=Path(folder)
    archive=folder/'source.usdz';archive.write_bytes(source)
    with zipfile.ZipFile(archive) as z:
        z.extractall(folder/'usd');root=folder/'usd'/z.namelist()[0]
    stage=Usd.Stage.Open(str(root)); report=[]
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):continue
        mesh=UsdGeom.Mesh(prim)
        points=list(mesh.GetPointsAttr().Get());indices=list(mesh.GetFaceVertexIndicesAttr().Get());counts=list(mesh.GetFaceVertexCountsAttr().Get())
        faces=[];cursor=0
        for count in counts:faces.append(indices[cursor:cursor+count]);cursor+=count
        data=bpy.data.meshes.new('saber.blade');data.from_pydata(points,[],faces);data.update()
        uv=UsdGeom.PrimvarsAPI(prim).GetPrimvar('st');coords=list(uv.ComputeFlattened())
        layer=data.uv_layers.new(name='st')
        for loop in data.loops:
            i=loop.index if uv.GetInterpolation()=='faceVarying' else loop.vertex_index
            layer.data[loop.index].uv=coords[i]
        ob=bpy.data.objects.new('saber.blade',data);bpy.context.collection.objects.link(ob)
        bpy.context.view_layer.objects.active=ob;ob.select_set(True)
        dec=ob.modifiers.new('preserve silhouette budget','DECIMATE');dec.ratio=.42
        bpy.ops.object.modifier_apply(modifier=dec.name)
        tri=ob.modifiers.new('triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
        data=ob.data
        for poly in data.polygons:poly.use_smooth=True
        mesh.GetPointsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(*v.co) for v in data.vertices]))
        mesh.GetFaceVertexCountsAttr().Set(Vt.IntArray([len(p.vertices) for p in data.polygons]))
        mesh.GetFaceVertexIndicesAttr().Set(Vt.IntArray([v for p in data.polygons for v in p.vertices]))
        mesh.GetNormalsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(*n.vector) for n in data.corner_normals]))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.faceVarying)
        uv.Set(Vt.Vec2fArray([Gf.Vec2f(*v.uv) for v in data.uv_layers.active.data]))
        uv.SetInterpolation(UsdGeom.Tokens.faceVarying)
        uv.BlockIndices()
        # Extents remain authored by the exact original prop bounds (conservative).
        before=[(min(p[k] for p in points),max(p[k] for p in points)) for k in range(3)]
        after=[(min(v.co[k] for v in data.vertices),max(v.co[k] for v in data.vertices)) for k in range(3)]
        deviation=max(abs(a-b) for x,y in zip(before,after) for a,b in zip(x,y))
        assert deviation<.01,(before,after)
        assert len(data.polygons)<=2400
        report.append(dict(beforeTriangles=len(faces),afterTriangles=len(data.polygons),maxBoundsChange=deviation))
    stage.GetRootLayer().Save()
    output=OUT.resolve();output.unlink()
    assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(root)),str(output))
    result=dict(meshes=report,sha256=hashlib.sha256(output.read_bytes()).hexdigest(),note='Textures/materials/transforms retained; no runtime decimation.')
    Path('build/hero-reference-1026/saber-blade-report.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result),flush=True)
