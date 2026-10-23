"""Remove the disconnected gray disc from Prop_abyssRing.usdz (requires usd-core).

Usage: python tools/usd/remove_abyss_ring_disc.py path/to/Prop_abyssRing.usdz
Preserves the gold ring, textures, material bindings and authored transforms.
"""
import pathlib
import sys
import tempfile
import zipfile

from pxr import Gf, Usd, UsdGeom, UsdUtils, Vt


def remove_disc(path):
    path = pathlib.Path(path).resolve()
    with tempfile.TemporaryDirectory() as work:
        work = pathlib.Path(work)
        with zipfile.ZipFile(path) as archive:
            root_name = archive.namelist()[0]
            archive.extractall(work)
        stage = Usd.Stage.Open(str(work / root_name))
        mesh = UsdGeom.Mesh(stage.GetPrimAtPath('/root/Prop/Prop'))
        points = list(mesh.GetPointsAttr().Get())
        counts = list(mesh.GetFaceVertexCountsAttr().Get())
        indices = list(mesh.GetFaceVertexIndicesAttr().Get())
        assert all(n == 3 for n in counts), 'Expected triangulated prop'
        parents = list(range(len(points)))

        def root(i):
            while parents[i] != i:
                parents[i] = parents[parents[i]]
                i = parents[i]
            return i

        # Weld UV seam duplicates only for component detection.
        seen = {}
        for i, point in enumerate(points):
            key = tuple(round(float(v), 5) for v in point)
            if key in seen:
                parents[root(i)] = root(seen[key])
            seen[key] = i
        for start in range(0, len(indices), 3):
            a, b, c = indices[start:start + 3]
            parents[root(b)] = root(a)
            parents[root(c)] = root(a)
        disc = {root(i) for i, p in enumerate(points) if p[2] < -0.3}
        if not disc:
            print('Gray disc already absent')
            return
        assert len(disc) == 1, 'Unexpected prop components'
        removed = {i for i in range(len(points)) if root(i) in disc}
        assert len(removed) == 130, 'Unexpected disc topology'
        corners = [j for start in range(0, len(indices), 3)
                   if indices[start] not in removed for j in range(start, start + 3)]
        kept = [i for i in range(len(points)) if i not in removed]
        remap = {old: new for new, old in enumerate(kept)}
        mesh.GetPointsAttr().Set(Vt.Vec3fArray([points[i] for i in kept]))
        mesh.GetFaceVertexCountsAttr().Set(Vt.IntArray([3] * (len(corners) // 3)))
        mesh.GetFaceVertexIndicesAttr().Set(Vt.IntArray([remap[indices[j]] for j in corners]))
        assert mesh.GetNormalsInterpolation() == 'faceVarying'
        normals = mesh.GetNormalsAttr().Get()
        mesh.GetNormalsAttr().Set(Vt.Vec3fArray([normals[j] for j in corners]))
        uv = UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st')
        assert uv.IsIndexed() and uv.GetInterpolation() == 'faceVarying'
        uv_indices = uv.GetIndices()
        uv.SetIndices(Vt.IntArray([uv_indices[j] for j in corners]))
        remaining = [points[i] for i in kept]
        mesh.GetExtentAttr().Set(Vt.Vec3fArray([
            Gf.Vec3f(*(min(p[a] for p in remaining) for a in range(3))),
            Gf.Vec3f(*(max(p[a] for p in remaining) for a in range(3))),
        ]))
        stage.GetRootLayer().Save()
        output = work / 'clean.usdz'
        assert UsdUtils.CreateNewUsdzPackage(str(work / root_name), str(output))
        path.write_bytes(output.read_bytes())
        print(f'Removed {len(removed)} vertices, {len(counts) - len(corners) // 3} triangles')


if __name__ == '__main__':
    remove_disc(sys.argv[1])
