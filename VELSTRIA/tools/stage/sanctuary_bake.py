"""Bake the Tripo sanctuary to bounded VSP1 + 1024px atlas (uv run --with numpy --with pillow)."""
import json
import math
import pathlib
import struct
import subprocess
import sys
import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORK = ROOT / 'build/stage/sanctuary'
OUT = ROOT / 'App/Resources/Stage'
BLENDER = '/Applications/Blender.app/Contents/MacOS/Blender'

def extract():
    data = (WORK / 'model.glb').read_bytes()
    offset = 12
    while offset < len(data):
        length, kind = struct.unpack_from('<II', data, offset)
        chunk = data[offset + 8:offset + 8 + length]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        elif kind == 0x004E4942:
            blob = chunk
        offset += 8 + length
    tex = doc['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index']
    img = doc['images'][doc['textures'][tex]['source']]
    view = doc['bufferViews'][img['bufferView']]
    begin = view.get('byteOffset', 0)
    (WORK / 'base_color.png').write_bytes(blob[begin:begin + view['byteLength']])

def bake():
    extract()
    subprocess.run([BLENDER, '-b', '--factory-startup', '--python-exit-code', '1', '--python',
                    str(ROOT / 'tools/stage/stage_props_blender.py'), '--', 'bake',
                    '--glb', str(WORK / 'model.glb'), '--tris', '12000', '--out', str(WORK / 'mesh.npz'),
                    '--base-color', str(WORK / 'base_color.png'), '--bake-out', str(WORK / 'baked.png'),
                    '--bake-size', '1024'], check=True)

def export():
    source = np.load(WORK / 'mesh.npz')
    loops = source['tri_loops'].reshape(-1)
    pos = source['co'][source['corner_vert'][loops]].copy()
    normals = source['corner_normal'][loops].copy()
    uv = source['corner_uv'][loops]
    lo, hi = pos.min(axis=0), pos.max(axis=0)
    pos[:, :2] -= (lo[:2] + hi[:2]) / 2
    pos[:, 2] -= lo[2]
    # Detect the open sector in the source, then align it to the shared collision outline.
    angles = np.arctan2(pos[:, 1], pos[:, 0]) % (2 * np.pi)
    counts, _ = np.histogram(angles, bins=120, range=(0, 2 * np.pi))
    empty = counts < 3
    best = (0, 0)
    for start in range(120):
        length = 0
        while length < 120 and empty[(start + length) % 120]:
            length += 1
        if length > best[1]: best = (start, length)
    gap = (best[0] + best[1] / 2) * 2 * np.pi / 120
    rotation = math.radians(-25) - gap
    half_gap = best[1] * np.pi / 120
    delta = (angles - gap + np.pi) % (2 * np.pi) - np.pi
    mapped = np.sign(delta) * (math.radians(43) +
              np.maximum(0, np.abs(delta) - half_gap) * math.radians(137) / (np.pi - half_gap))
    turn = mapped - delta + rotation
    def rotate_xy(values):
        x, y = values[:, 0].copy(), values[:, 1].copy()
        values[:, 0] = x * np.cos(turn) - y * np.sin(turn)
        values[:, 1] = x * np.sin(turn) + y * np.cos(turn)
    rotate_xy(pos)
    rotate_xy(normals)
    # Plan footprint 8.2m; the source remains open and has no center floor.
    lo, hi = pos.min(axis=0), pos.max(axis=0)
    pos[:, :2] -= (lo[:2] + hi[:2]) / 2
    scale = np.array([8.2 / (hi[0] - lo[0]), 8.2 / (hi[1] - lo[1]), 2.65 / hi[2]])
    pos *= scale
    normals /= scale
    # Foreground is a low sill, not a second high wall hiding the combatants.
    t = np.clip((pos[:, 1] + 0.6) / 3.6, 0, 1)
    height_scale = 0.62 + 0.38 * t * t * (3 - 2 * t)
    pos[:, 2] *= height_scale
    normals[:, 2] /= height_scale
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-8)
    # Blender Z-up -> RealityKit Y-up, determinant +1.
    pos = np.stack([pos[:, 0], pos[:, 2], -pos[:, 1]], axis=1)
    normals = np.stack([normals[:, 0], normals[:, 2], -normals[:, 1]], axis=1)
    vertices = np.concatenate([pos, normals, uv], axis=1).astype('<f4')
    vertices, indices = np.unique(vertices, axis=0, return_inverse=True)
    indices = indices.astype('<u4')
    vertex_bytes = vertices.tobytes()
    header = json.dumps({'atlas': {'width':1024, 'height':1024}, 'props': [{
        'id':'sanctuary', 'vertexCount':len(vertices), 'indexCount':len(indices),
        'vertexOffset':0, 'indexOffset':len(vertex_bytes),
        'boundsMin':pos.min(axis=0).tolist(), 'boundsMax':pos.max(axis=0).tolist()
    }]}, separators=(',', ':')).encode()
    prefix = b'VSP1' + struct.pack('<II', 1, len(header)) + header
    prefix += b'\0' * (-len(prefix) % 16)
    (OUT / 'StageSanctuary.bin').write_bytes(prefix + vertex_bytes + indices.tobytes())
    Image.open(WORK / 'baked.png').convert('RGB').save(OUT / 'StageSanctuaryAtlas.jpg', quality=95, subsampling=0)
    print(json.dumps({'triangles':len(indices)//3, 'rotationDegrees':math.degrees(rotation), 'sourceGapBins':best,
                      'boundsMin':pos.min(axis=0).tolist(), 'boundsMax':pos.max(axis=0).tolist()}))

if __name__ == '__main__':
    if '--export-only' not in sys.argv: bake()
    export()
