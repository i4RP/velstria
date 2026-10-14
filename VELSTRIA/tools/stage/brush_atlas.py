"""Deterministic painted foliage atlas: four padded RGBA tufts, no external service."""
from PIL import Image, ImageDraw
import random, math
from pathlib import Path
rng = random.Random(613)
S=2
im=Image.new('RGBA',(1024*S,512*S))
for tile in range(4):
    for leaf in range(18):
        # Short understory, broad folded leaves, and narrow upright blades.
        kind=leaf%3
        bx=rng.uniform(30,226); by=rng.uniform(453,486)
        tx=min(235,max(21,bx+rng.uniform(-85,85)))
        ty=rng.uniform(28,180) if kind!=2 else rng.uniform(190,300)
        width=rng.uniform(24,38) if kind==1 else rng.uniform(14,23) if kind==2 else rng.uniform(8,15)
        bend=rng.uniform(-25,25)
        shade=rng.uniform(.86,1.12)
        left=[]; right=[]; centers=[]
        for j in range(25):
            t=j/24; x=bx+(tx-bx)*t+bend*math.sin(t*math.pi); y=by+(ty-by)*t
            w=width*(.48+.65*math.sin(math.pi*t))*(1-t)**.65
            centers.append((x,y)); left.append((x-w,y)); right.append((x+w,y))
        d=ImageDraw.Draw(im)
        def pts(a): return [((x+tile*256)*S,y*S) for x,y in a]
        for j in range(24):
            t=j/24
            palette = (18+44*t, 64+85*t, 55+55*t) if tile%2==0 else (25+87*t, 66+99*t, 44+29*t)
            c=tuple(int(v*shade) for v in palette)
            d.polygon(pts([left[j],centers[j],centers[j+1],left[j+1]]), fill=(*c,255))
            c=tuple(min(255,int(v*1.17)) for v in c)
            d.polygon(pts([centers[j],right[j],right[j+1],centers[j+1]]), fill=(*c,255))
        d.line(pts(right[12:]),fill=((95,175,126,205) if tile%2==0 else (139,187,91,205)),width=S)
        d.line(pts(centers[8:23]),fill=((61,132,97,255) if tile%2==0 else (100,151,79,255)),width=S)
im=im.resize((1024,512),Image.Resampling.LANCZOS)
out=Path(__file__).resolve().parents[2]/'App/Resources/Stage/StageBrushAtlas.png'
im.save(out)
print(out)
