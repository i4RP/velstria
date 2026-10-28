#!/usr/bin/env python3
"""Bake Meshy/Tripo Seaside props into a bounded VSP1 resource and 1024px atlas.

uv run --with numpy --with pillow python tools/stage/seaside_bake.py
Inputs: build/stage/seaside/{limestone_arch,palm_cluster}/model.glb
Outputs: App/Resources/Stage/StageSeaside.bin and StageSeasideAtlas.jpg
Use --export-only to repack an existing bake, or --preview to render the result.
"""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "build/stage/seaside"
OUT = ROOT / "App/Resources/Stage"
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
ATLAS_SIZE = 1024
PAD = 8
TRIANGLE_BUDGET = 2500
# Keep a margin beneath the hard limit: Blender's decimator allows +/-3%.
BAKE_TARGET = 2400
# Runtime identifiers deliberately reuse the existing StagePropKind/VSP1 reader.
SPECS = [("limestone_arch", "ruin_arch", "width", 12.0),
         ("palm_cluster", "tree_tall", "height", 6.0)]


def blender_bake(folder):
    """Use the common decimation pipeline while retaining all GLB base materials."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import stage_props_blender as shared
    import bpy

    def bake_source_materials(high, low, _base_color, out_png, size, margin_px):
        # A GLB can contain several materials/textures. Bake its original base colors
        # to one texture instead of applying material zero's image to every surface.
        for material in high.data.materials:
            if material is None:
                continue
            material.use_nodes = True
            nodes = material.node_tree.nodes
            links = material.node_tree.links
            principled = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
            output = next((n for n in nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
            output = output or nodes.new("ShaderNodeOutputMaterial")
            emission = nodes.new("ShaderNodeEmission")
            if principled is not None:
                color = principled.inputs["Base Color"]
                if color.is_linked:
                    links.new(color.links[0].from_socket, emission.inputs["Color"])
                else:
                    emission.inputs["Color"].default_value = color.default_value
            else:
                emission.inputs["Color"].default_value = material.diffuse_color
            links.new(emission.outputs["Emission"], output.inputs["Surface"])

        target = bpy.data.images.new("seaside_bake", size, size, alpha=False)
        target.generated_color = (1.0, 0.0, 1.0, 1.0)
        material = bpy.data.materials.new("seaside_bake_target")
        material.use_nodes = True
        node = material.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = target
        material.node_tree.nodes.active = node
        low.data.materials.clear()
        low.data.materials.append(material)
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 4
        scene.view_settings.view_transform = "Standard"
        settings = scene.render.bake
        diagonal = shared.bbox_diag(high)
        settings.use_selected_to_active = True
        settings.cage_extrusion = diagonal * 0.03
        settings.max_ray_distance = diagonal * 0.08
        settings.margin = margin_px
        settings.margin_type = "EXTEND"
        settings.target = "IMAGE_TEXTURES"
        settings.use_clear = False
        shared.select_only([high, low], active=low)
        bpy.ops.object.bake(type="EMIT")
        target.filepath_raw = out_png
        target.file_format = "PNG"
        target.save()

    shared.bake_base_color = bake_source_materials
    shared.bake({"glb": str(folder / "model.glb"), "out": str(folder / "mesh.npz"),
                 "tris": str(BAKE_TARGET), "mode": "rebake", "angle": "55",
                 "base-color": "embedded GLB materials", "bake-out": str(folder / "baked.png"),
                 "bake-size": str(ATLAS_SIZE)})


def bake():
    for source_id, _, _, _ in SPECS:
        folder = WORK / source_id
        if not (folder / "model.glb").is_file():
            raise SystemExit(f"Missing input: {folder / 'model.glb'}")
        print(f"Baking {source_id} (maximum {TRIANGLE_BUDGET} triangles)", flush=True)
        with (folder / "bake.log").open("w") as log:
            subprocess.run([BLENDER, "-b", "--factory-startup", "--python-exit-code", "1",
                            "--python", str(Path(__file__).resolve()), "--", "--blender-bake", str(folder)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)


def prop_mesh(folder, tile, kind, meters):
    source = np.load(folder / "mesh.npz")
    loops = source["tri_loops"].reshape(-1)
    position = source["co"][source["corner_vert"][loops]].astype(np.float64)
    normal = source["corner_normal"][loops].astype(np.float64)
    uv = source["corner_uv"][loops].astype(np.float64)
    # Align the long ground axis to X, then scale uniformly to retain the silhouette.
    _, axes = np.linalg.eigh(np.cov(position[:, :2].T))
    axis = axes[:, -1]
    if axis[0] < 0:
        axis = -axis
    rotation = np.column_stack([axis, [-axis[1], axis[0]]])
    position[:, :2] = position[:, :2] @ rotation
    normal[:, :2] = normal[:, :2] @ rotation
    lo, hi = position.min(0), position.max(0)
    extent = hi - lo
    if np.any(extent <= 1e-6):
        raise ValueError(f"Degenerate source bounds: {folder.name}")
    position[:, :2] -= (lo[:2] + hi[:2]) / 2
    position[:, 2] -= lo[2]
    position *= meters / extent[0 if kind == "width" else 2]
    # Blender Z-up -> RealityKit Y-up is a rotation, preserving triangle winding.
    position = position[:, [0, 2, 1]] * [1, 1, -1]
    normal = normal[:, [0, 2, 1]] * [1, 1, -1]
    triangle = position.reshape(-1, 3, 3)
    face_normal = np.cross(triangle[:, 1] - triangle[:, 0], triangle[:, 2] - triangle[:, 0])
    keep = np.linalg.norm(face_normal, axis=1) > 1e-9
    weak = np.linalg.norm(normal, axis=1) < 1e-6
    normal[weak] = np.repeat(face_normal, 3, axis=0)[weak]
    length = np.linalg.norm(normal, axis=1, keepdims=True)
    normal = np.divide(normal, np.maximum(length, 1e-12))
    # Two 512x1024 padded cells. V is bottom-up in both Blender and RealityKit.
    uv = np.clip(uv, 0, 1)
    uv[:, 0] = (tile * 512 + PAD + uv[:, 0] * (512 - PAD * 2)) / ATLAS_SIZE
    uv[:, 1] = (PAD + uv[:, 1] * (ATLAS_SIZE - PAD * 2)) / ATLAS_SIZE
    vertices = np.concatenate([position, normal, uv], axis=1)[np.repeat(keep, 3)].astype("<f4")
    vertices, indices = np.unique(vertices, axis=0, return_inverse=True)
    indices = indices.astype("<u4").reshape(-1)
    if not len(indices) or len(indices) // 3 > TRIANGLE_BUDGET:
        raise ValueError(f"{folder.name}: {len(indices) // 3} triangles exceeds {TRIANGLE_BUDGET}")
    if not np.isfinite(vertices).all():
        raise ValueError(f"{folder.name}: non-finite mesh values")
    return vertices, indices, float(math.degrees(math.atan2(axis[1], axis[0])))


def export():
    from PIL import Image
    from stage_bake import pull_push_fill

    atlas = Image.new("RGB", (ATLAS_SIZE, ATLAS_SIZE))
    records, blobs, report = [], [], []
    offset = 0

    def push(data):
        nonlocal offset
        start = offset
        blobs.append(data)
        offset += len(data)
        padding = -offset % 16
        blobs.append(b"\0" * padding)
        offset += padding
        return start

    for tile, (source_id, runtime_id, kind, meters) in enumerate(SPECS):
        folder = WORK / source_id
        vertices, indices, rotation = prop_mesh(folder, tile, kind, meters)
        pixels = np.asarray(Image.open(folder / "baked.png").convert("RGB"))
        unbaked = (pixels[:, :, 0] > 250) & (pixels[:, :, 1] < 5) & (pixels[:, :, 2] > 250)
        if unbaked.all():
            raise ValueError(f"{source_id}: no baked pixels")
        image = Image.fromarray(pull_push_fill(pixels, ~unbaked))
        image = image.resize((512 - PAD * 2, ATLAS_SIZE - PAD * 2), Image.Resampling.LANCZOS)
        cell = Image.fromarray(np.pad(np.asarray(image), ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge"))
        atlas.paste(cell, (tile * 512, 0))
        record = {"id": runtime_id, "vertexCount": len(vertices), "indexCount": len(indices),
                  "vertexOffset": push(vertices.tobytes()), "indexOffset": push(indices.tobytes()),
                  "boundsMin": vertices[:, :3].min(0).tolist(), "boundsMax": vertices[:, :3].max(0).tolist(),
                  "tris": len(indices) // 3}
        records.append(record)
        report.append({**record, "source": source_id, "sourceSHA256": hashlib.sha256((folder / "model.glb").read_bytes()).hexdigest(),
                       "rotationDegrees": round(rotation, 3), "triangleBudget": TRIANGLE_BUDGET})
        print(f"{source_id} -> {runtime_id}: {record['tris']} triangles", flush=True)
    header = json.dumps({"atlas": {"width": ATLAS_SIZE, "height": ATLAS_SIZE}, "props": records},
                        separators=(",", ":")).encode()
    prefix = b"VSP1" + struct.pack("<II", 1, len(header)) + header
    prefix += b"\0" * (-len(prefix) % 16)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "StageSeaside.bin").write_bytes(prefix + b"".join(blobs))
    atlas.save(OUT / "StageSeasideAtlas.jpg", quality=95, subsampling=0)
    (WORK / "bake-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Saved StageSeaside.bin and StageSeasideAtlas.jpg (1024x1024)", flush=True)


def preview():
    subprocess.run([BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "--python",
                    str(ROOT / "tools/stage/stage_props_blender.py"), "--", "render", "--bin",
                    str(OUT / "StageSeaside.bin"), "--atlas", str(OUT / "StageSeasideAtlas.jpg"),
                    "--outdir", str(WORK / "preview"), "--res", "768", "--azimuths", "25,205"], check=True)


if __name__ == "__main__":
    if "--blender-bake" in sys.argv:
        blender_bake(Path(sys.argv[sys.argv.index("--blender-bake") + 1]))
    else:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("--export-only", action="store_true")
        parser.add_argument("--preview", action="store_true")
        args = parser.parse_args()
        if not args.export_only:
            bake()
        export()
        if args.preview:
            preview()
