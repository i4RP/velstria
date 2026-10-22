#!/usr/bin/env python3
"""Read-only camera survey of the 2026-10-19 screenshots.

uv run --with numpy --with scipy --with opencv-python-headless python tools/map_proto/calibrate_field.py
Ground correspondences exclude HUD, moving heroes and foliage. Measurements and
source screenshots stay under build; no reference artwork is shipped in the app.
"""
from pathlib import Path
import json
import cv2
import numpy as np
from scipy.optimize import least_squares

root = Path(__file__).resolve().parents[2]
work = root / 'build/stage/reference-20261019'
files = sorted(work.glob('IMG*.png'))
features = []
sift = cv2.SIFT_create(nfeatures=4500)
centers = []
for f in files:
    im = cv2.imread(str(f))
    hsv = cv2.cvtColor(im[:200,70:271], cv2.COLOR_BGR2HSV)
    ring = cv2.inRange(hsv, np.array([38,120,150]), np.array([88,255,255]))
    count, _, stats, pts = cv2.connectedComponentsWithStats(ring)
    candidates = [c + [70,0] for s,c in zip(stats[1:],pts[1:]) if s[2]>12 and s[3]>12 and s[4]>40]
    centers.append(candidates[0].tolist() if candidates else None)
    mask = np.full(im.shape[:2],255,np.uint8)
    mask[:205,:320]=0; mask[:45,:]=0; mask[480:,:]=0
    mask[330:,940:]=0; mask[:,1250:]=0; mask[:,:80]=0
    mask[210:395,610:800]=0; mask[395:,:350]=0
    key, desc = sift.detectAndCompute(cv2.cvtColor(im, cv2.COLOR_BGR2GRAY), mask)
    features.append((key,desc))
    print(f.stem, centers[-1], len(key), flush=True)

matches=[]
bf=cv2.BFMatcher()
for i in range(len(files)):
    for j in range(i+1,len(files)):
        a,da=features[i]; b,db=features[j]
        pairs=bf.knnMatch(da,db,k=2)
        good=[p for p,q in pairs if p.distance<0.75*q.distance]
        if len(good)<20: continue
        aa=np.float32([a[m.queryIdx].pt for m in good]);bb=np.float32([b[m.trainIdx].pt for m in good])
        h,ok=cv2.findHomography(aa,bb,cv2.RANSAC,3.0)
        if h is None: continue
        ok=ok.ravel()!=0
        aa=aa[ok];bb=bb[ok]
        if len(aa)<15: continue
        if np.median(np.linalg.norm(aa-bb,axis=1))<8: continue
        # Sample across the image, rather than weighting one detailed stone heavily.
        used=set(); selected=[]
        for n,p in enumerate(aa):
            cell=tuple((p/35).astype(int))
            if cell not in used: used.add(cell); selected.append(n)
        aa=aa[selected];bb=bb[selected]
        if len(aa)<10: continue
        matches.append(dict(i=i,j=j,a=aa.tolist(),b=bb.tolist()))
        print(files[i].stem,files[j].stem,len(aa),flush=True)
(work/'matches.json').write_text(json.dumps(dict(files=[f.stem for f in files],minimap=centers,matches=matches)))
