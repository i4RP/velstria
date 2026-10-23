"""Offline deformed-mesh floor/contact evidence; not runtime or visual approval.
blender -b -t 4 -P tools/blender/audit_h025_quality_motion.py
"""
import json
import sys
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_h025_motion as a
import author_h025_quality_motion as quality
import preview_clip as preview
import preview_h025_motion as p
import clip_math as cm

rig, meshes, _, _ = preview.load_hero(str(Path('App/Resources/Heroes/Hero_H025.usdz').resolve()))
a.bind_usd_axes(rig, 'App/Resources/Heroes/Hero_H025.usdz')
clips = preview.load_clips('App/Resources/Heroes/H025MotionClips.json')
report = {}
for name, c in clips.items():
    low, high = float('inf'), -float('inf')
    drift = []
    for f in range(c['frames']):
        q, root = cm.interp_clip(c, f)
        root.x *= c.get('rootXZ', 0); root.z *= c.get('rootXZ', 0)
        dr, pos = a.solve(rig, q, root * rig.leg_length, p.details_at(c, f))
        rig.apply_pose(dr, pos)
        bpy.context.view_layer.update()
        minimum, _ = preview.lowest_highest(meshes, rig.M)
        low, high = min(low, minimum), max(high, minimum)
        if name in ('h025_run', 'h025_walk'):
            speed = c['groundSpeed']; period = c['frames'] / 60
            duty = .38 if name.endswith('run') else .62
            phase = f / c['frames']
            if phase < duty:
                j = rig.index['rightfoot']
                pivot = Vector((0, -rig.P0[j].y, .045 if phase/duty < .5 else -.105))
                world = pos[j] + dr[j] @ pivot + Vector((0,0,-speed*period*phase))
                # Heel/ball use different contact points; compare each to its own
                # authored stationary support location, not to the ankle centre.
                ideal = Vector((.095,0,-speed*period*duty/2+pivot.z))
                drift.append((world-ideal).length)
    report[name] = dict(minMeshY=round(low,6), maxMinimumMeshY=round(high,6))
    if drift: report[name]['maxSupportDriftMeters'] = round(max(drift),6)
out=Path('build/h025-quality/motion-audit.json')
out.parent.mkdir(exist_ok=True,parents=True)
out.write_text(json.dumps(report,indent=2))
print(json.dumps(report),flush=True)
