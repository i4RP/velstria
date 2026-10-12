# 担当: battle-renderer（塔・Star Core の部品分けモデル）。赤チームのテクスチャ（Struct_<id>_red.jpg / _red_emit.jpg）だけを
# 同梱の USDZ のベースカラーから作り直す（メッシュ・USDZ は触らない）。Blender 5.2 headless で実行する:
#   Blender -b --factory-startup -noaudio --python tools/structures/red_textures.py -- \
#       --ids tower_outer,tower_inner,tower_base,star_core --dir App/Resources/Structures
# 色相の付け替えは tower_parts.py の team_textures（TEAM_DEFAULT と structures.json の parts.team）と同じ。
import argparse
import json
import os
import sys
import tempfile
import zipfile

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import structures_bake as sb  # noqa: E402
import tower_parts as tp  # noqa: E402
import norm_common as nc  # noqa: E402  (structures_bake が tools/blender を path に足す)


def main():
    p = argparse.ArgumentParser(prog="red_textures.py")
    p.add_argument("--ids", required=True)
    p.add_argument("--dir", required=True)
    a = p.parse_args(nc.script_args())
    with open(os.path.join(HERE, "structures.json")) as f:
        assets = {s["id"]: s for s in json.load(f)["assets"]}
    for sid in a.ids.split(","):
        usdz = os.path.join(a.dir, f"Struct_{sid}.usdz")
        team = (assets.get(sid, {}).get("parts") or {}).get("team")
        with tempfile.TemporaryDirectory() as tmp, zipfile.ZipFile(usdz) as z:
            name = next(n for n in z.namelist() if n.endswith(f"Struct_{sid}_base.jpg"))
            path = z.extract(name, tmp)
            img = bpy.data.images.load(path)
            img.colorspace_settings.is_data = False
            w, h = img.size
            px = np.empty(w * h * 4, dtype=np.float32)
            img.pixels.foreach_get(px)
            px = px.reshape(h, w, 4)
            _, red, red_emit, glow = tp.team_textures(px, team)
            sb.save_jpeg(red, os.path.join(a.dir, f"Struct_{sid}_red.jpg"))
            sb.save_jpeg(red_emit, os.path.join(a.dir, f"Struct_{sid}_red_emit.jpg"))
            bpy.data.images.remove(img)
            tp.log(f"{sid}: {w}x{h} glow {float(glow.mean()):.4f}")


main()
