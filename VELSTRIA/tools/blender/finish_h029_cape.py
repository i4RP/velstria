"""H029 ボルグのマントに揺れ物の骨を足す（H025 の finish_h025_model.py と同じ作り。形・UV・テクスチャ・材質は変えない）。

blender -b -P tools/blender/finish_h029_cape.py -- [--source old.usdz] [--inspect]
既定の元は git の SOURCE_GIT（揺れ物の骨の無い 10-23 の指付きのモデル）。同じ元から何度でも作り直せる（2 回掛けない）。
骨: CapeL1〜3・CapeR1〜3（Spine2 の子の鎖。HeroSecondaryPose.names の capel1〜caper3）。実行時の揺れは HeroSecondaryMotion。
マントの頂点（背中の赤い布）は、上の縁を体に残したまま、下ほど鎖の骨へ重みを移す（4 重みのまま、合計 1）。
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

import bpy  # noqa: F401  (Blender 同梱の pxr を使う)
import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdSkel, UsdUtils, Vt

SOURCE_GIT = '1994dde:VELSTRIA/App/Resources/Heroes/Hero_H029.usdz'
# Blender 4.5 の USD の取り込みは、足した骨（H025 と同じ作り）で落ちる（set_rest_pose）。author / preview は元の骨のモデルを使う
BASE = Path('build/h029-motion/Hero_H029_base.usdz')
OUT = Path('build/h029-motion')
# 鎖の骨の位置（USD = ヒーロー空間。後ろ = +Z）。マントの付け根（肩の後ろ）から裾へ、布の面に沿って後ろへ開く
CHAIN = [(1.40, 0.17), (1.08, 0.24), (0.76, 0.33)]
CHAIN_X = 0.15
TOP, SPAN = 1.42, 0.32    # 付け根の高さ・骨の間隔（重みの鎖の上の位置 u = (TOP - y) / SPAN）


def smooth(x):
    x = max(0.0, min(1.0, float(x)))
    return x * x * (3 - 2 * x)


def refine(sel, faces, centers, min_island=30, grow=4):
    """色で選んだマントの面から、小さな島（鎧の赤い小片）を外し、隣の面へ広げて縁取り（金・灰の裾）も入れる。"""
    sel = sel.copy()
    by_vertex = {}
    for i, f in enumerate(faces):
        for v in f:
            by_vertex.setdefault(int(v), []).append(i)

    def neighbors(i):
        return {k for v in faces[i] for k in by_vertex[int(v)] if k != i}
    seen = np.zeros(len(faces), dtype=bool)
    for i in np.where(sel)[0]:
        if seen[i]:
            continue
        island, stack = [], [i]
        seen[i] = True
        while stack:
            k = stack.pop()
            island.append(k)
            for n in neighbors(k):
                if sel[n] and not seen[n]:
                    seen[n] = True
                    stack.append(n)
        if len(island) < min_island:
            sel[island] = False
    for _ in range(grow):
        add = [n for i in np.where(sel)[0] for n in neighbors(i)
               if not sel[n] and centers[n][2] > 0.12 and abs(centers[n][0]) < 0.50 and 0.25 < centers[n][1] < 1.44]
        sel[add] = True
    return sel


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source')
    ap.add_argument('--out', default='App/Resources/Heroes/Hero_H029.usdz')
    ap.add_argument('--inspect', action='store_true')
    a = ap.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    OUT.mkdir(parents=True, exist_ok=True)
    data = Path(a.source).read_bytes() if a.source else subprocess.check_output(['git', 'show', SOURCE_GIT])
    src_sha = hashlib.sha256(data).hexdigest()
    with tempfile.TemporaryDirectory(prefix='h029_cape_') as temp:
        temp = Path(temp)
        source = temp / 'source.usdz'
        source.write_bytes(data)
        BASE.write_bytes(data)
        with zipfile.ZipFile(source) as z:
            z.extractall(temp / 'usd')
            root = temp / 'usd' / next(n for n in z.namelist() if n.endswith('.usdc'))
        stage = Usd.Stage.Open(str(root))
        mesh = next(UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh))
        skeleton = next(UsdSkel.Skeleton(p) for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton))
        binding = UsdSkel.BindingAPI(mesh.GetPrim())
        points = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
        faces = np.array(mesh.GetFaceVertexIndicesAttr().Get()).reshape(-1, 3)
        indices = np.array(binding.GetJointIndicesPrimvar().Get(), dtype=int).reshape(-1, 4)
        weights = np.array(binding.GetJointWeightsPrimvar().Get(), dtype=np.float64).reshape(-1, 4)
        joints = list(skeleton.GetJointsAttr().Get())
        binds = list(skeleton.GetBindTransformsAttr().Get())
        rests = list(skeleton.GetRestTransformsAttr().Get())
        short = [n.rsplit('/', 1)[-1].replace('mixamorig_', '') for n in joints]
        assert 'CapeL1' not in short, '揺れ物の骨は付いている（元のモデルから作り直す）'
        before = len(joints)

        # 面の色（テクスチャの UV の中心）
        uv = np.array(UsdGeom.PrimvarsAPI(mesh.GetPrim()).GetPrimvar('st').ComputeFlattened())
        uv = uv.reshape(-1, 3, 2).mean(axis=1) if len(uv) == len(faces) * 3 else uv[faces].mean(axis=1)
        colorpath = next((temp / 'usd' / 'textures').glob('Color_*'))
        im = bpy.data.images.load(str(colorpath))
        px = np.empty(len(im.pixels), dtype=np.float32)
        im.pixels.foreach_get(px)
        px = px.reshape(im.size[1], im.size[0], 4)
        rgb = px[(uv[:, 1] * im.size[1]).astype(int) % im.size[1], (uv[:, 0] * im.size[0]).astype(int) % im.size[0], :3]
        centers = points[faces].mean(axis=1)
        # マント: 背中より後ろ・肩より下・赤い布（裏の暗い赤も）。腕・脚の前は入れない
        cape_face = np.array([(0.30 < y < 1.46 and z > 0.10 + 0.10 * smooth((y - 1.30) / 0.16) and abs(x) < 0.42
                               and r > g * 1.35 and r > b * 1.05)
                              for (x, y, z), (r, g, b) in zip(centers, rgb)])
        cape_face = refine(cape_face, faces, centers)
        votes = np.zeros(len(points))
        total = np.zeros(len(points))
        for f, c in zip(faces, cape_face):
            for v in f:
                votes[v] += c
                total[v] += 1
        votes /= np.maximum(total, 1)

        def bone(name, parent, pos):
            j = len(joints)
            pi = short.index(parent)
            joints.append(joints[pi] + '/' + name)
            short.append(name)
            bind = Gf.Matrix4d(1)
            bind.SetTranslate(Gf.Vec3d(*pos))
            binds.append(bind)
            rests.append(bind * binds[pi].GetInverse())
            return j

        chains = {}
        for side, sign in (('L', -1), ('R', 1)):
            parent, chain = 'Spine2', []
            for k, (y, z) in enumerate(CHAIN):
                name = f'Cape{side}{k + 1}'
                chain.append(bone(name, parent, (sign * CHAIN_X, y, z)))
                parent = name
            chains[side] = chain

        def along(chain, u):
            u = max(0.0, min(len(chain) - 1, float(u)))
            k = min(len(chain) - 1, int(u))
            f = u - k
            return {chain[k]: 1 - f, chain[min(len(chain) - 1, k + 1)]: f} if f > 0 else {chain[k]: 1.0}

        changed = 0
        for v, (x, y, z) in enumerate(points):
            member = votes[v]
            if member < 0.35:
                continue
            amount = member * smooth((TOP - y) / 0.18)
            if amount <= 0.01:
                continue
            right = smooth((x + 0.10) / 0.20)
            repl = {}
            for side, w in (('L', 1 - right), ('R', right)):
                for j, vw in along(chains[side], (TOP - y) / SPAN).items():
                    repl[j] = repl.get(j, 0) + w * vw
            old = {int(j): float(w) for j, w in zip(indices[v], weights[v]) if w > 1e-6}
            new = {j: w * (1 - amount) for j, w in old.items()}
            for j, w in repl.items():
                new[j] = new.get(j, 0) + amount * w
            best = sorted(new.items(), key=lambda p: -p[1])[:4]
            norm = sum(w for _, w in best)
            best += [(0, 0.0)] * (4 - len(best))
            indices[v] = [j for j, _ in best]
            weights[v] = [w / norm for _, w in best]
            changed += 1
        skeleton.GetJointsAttr().Set(Vt.TokenArray(joints))
        skeleton.GetBindTransformsAttr().Set(Vt.Matrix4dArray(binds))
        skeleton.GetRestTransformsAttr().Set(Vt.Matrix4dArray(rests))
        binding.GetJointIndicesPrimvar().Set(Vt.IntArray(indices.ravel().tolist()))
        binding.GetJointWeightsPrimvar().Set(Vt.FloatArray(weights.ravel().tolist()))
        for prim in list(stage.Traverse()):
            if prim.IsA(UsdSkel.Animation):
                stage.RemovePrim(prim.GetPath())
        UsdSkel.BindingAPI(skeleton.GetPrim()).GetAnimationSourceRel().ClearTargets(True)
        stage.GetRootLayer().Save()
        out = Path(a.out).resolve()
        if out.exists():
            out.unlink()
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(root)), str(out))
        report = {'source': SOURCE_GIT, 'sourceSHA256': src_sha, 'outputSHA256': hashlib.sha256(out.read_bytes()).hexdigest(),
                  'triangles': len(faces), 'vertices': len(points), 'bonesBefore': before, 'bonesAfter': len(joints),
                  'capeFaces': int(cape_face.sum()), 'capeWeightedVertices': changed,
                  'weightSumError': float(np.max(abs(weights.sum(axis=1) - 1)))}
        (OUT / 'cape-report.json').write_text(json.dumps(report, indent=2))
        print('CAPE', json.dumps(report), flush=True)
    if a.inspect:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import preview_clip as p
        from mathutils import Vector
        r, meshes, h, w = p.load_hero(str(out))
        p.VIEWS['back'] = Vector((0, .12, 1))
        for view in ['side', 'back']:
            label = p.setup_scene(r, h, view, (600, 720))
            label.data.body = 'H029 cape / ' + view
            bpy.context.scene.render.filepath = str((OUT / ('cape-' + view + '.png')).resolve())
            bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    main()
