# H032 の取得クリップの解析（向き・拳の伸び・腰の移動）。python3 tools/motion/h032_analyze.py <clips.json> [names]
import json, math, sys
def qmul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return (aw*bx+ax*bw+ay*bz-az*by, aw*by-ax*bz+ay*bw+az*bx, aw*bz+ax*by-ay*bx+az*bw, aw*bw-ax*bx-ay*by-az*bz)
def act(q, v):
    x, y, z, w = q; vx, vy, vz = v
    t = (2*(y*vz-z*vy), 2*(z*vx-x*vz), 2*(x*vy-y*vx))
    return (vx+w*t[0]+y*t[2]-z*t[1], vy+w*t[1]+z*t[0]-x*t[2], vz+w*t[2]+x*t[1]-y*t[0])
d = json.load(open(sys.argv[1])); segs = d['segments']; S = len(segs)
only = sys.argv[2].split(',') if len(sys.argv) > 2 else None
for c in d['clips']:
    if only and c['name'] not in only: continue
    n = c['frames']; R = c['rot']; P = c['root']
    def q(f, s): i = (f*S + segs.index(s))*4; return tuple(R[i:i+4])
    print(f"== {c['name']} {n}f")
    for f in range(n):
        fw = act(q(f, 'torso'), (0, 0, -1)); yaw = math.degrees(math.atan2(-fw[0], -fw[2]))
        def reach(side):
            a = act(q(f, 'arm'+side), (0, -1, 0)); b = act(q(f, 'foreArm'+side), (0, -1, 0))
            sh = act(q(f, 'torso'), (0.18 if side == 'R' else -0.18, 0.45, 0))
            return tuple(sh[i] + 0.28*a[i] + 0.26*b[i] for i in range(3))
        rr, rl = reach('R'), reach('L')
        # 世界の正面 -Z への拳の伸び（腰から）と高さ
        def ext(side):
            a = act(q(f, 'arm'+side), (0, -1, 0)); b = act(q(f, 'foreArm'+side), (0, -1, 0))
            v = [0.28*a[i] + 0.26*b[i] for i in range(3)]
            return math.sqrt(sum(x*x for x in v)) / 0.54, math.degrees(math.atan2(-v[0], -v[2]))
        (pr, ar), (pl, al) = ext('R'), ext('L')
        root = P[f*3:f*3+3]
        if f % int(sys.argv[3] if len(sys.argv) > 3 else 2) == 0:
            print(f"{f:3d} yaw{yaw:6.0f} R{pr:5.2f}@{ar:4.0f} L{pl:5.2f}@{al:4.0f} hY R{rr[1]:5.2f} L{rl[1]:5.2f} root({root[0]:5.2f},{root[1]:5.2f},{root[2]:5.2f})")
