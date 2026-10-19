#!/usr/bin/env python3
"""Fit a common ground projection; minimap positions constrain world scale.
Raised scenery is not an exact ground correspondence, so retain robust residuals
and record them instead of claiming pixel-perfect reconstruction.
"""
from pathlib import Path
import json
import numpy as np
from scipy.optimize import least_squares

work=Path(__file__).resolve().parents[2]/'build/stage/reference-20261019'
data=json.loads((work/'matches.json').read_text())
manual={'6695':[184,166], '6697':[224,153], '6701':[165,158], '6713':[126,110],
        '6714':[106,127], '6715':[99,95], '6716':[110,70], '6717':[126,81],
        '6718':[143,70], '6719':[179,137], '6720':[229,163], '6721':[204,165]}
mini=np.array([manual.get(name[-4:],pos) for name,pos in zip(data['files'],data['minimap'])],float)
centers=np.column_stack([(mini[:,0]-66.2)*0.4614,(203.8-mini[:,1])*0.4614])
def offsets(points,parameters):
    pitch,fov,d=parameters[:3];p=np.radians(pitch);f=315/np.tan(np.radians(fov)/2)
    u,v=np.asarray(points).T;dy=(315-v)*d/(f*np.sin(p)-(315-v)*np.cos(p))
    return np.column_stack([(u-684)*(d+dy*np.cos(p))/f,dy])

initial=np.r_[50.,40.,19.,centers.ravel()]
ma=[];mb=[];ii=[];jj=[]
for match in data['matches']:
    i,j=match['i'],match['j'];a=np.array(match['a']);b=np.array(match['b'])
    error=np.linalg.norm(offsets(a,initial)+centers[i]-offsets(b,initial)-centers[j],axis=1)
    ok=error<2.5
    if ok.sum()<8:continue
    ma.extend(a[ok]);mb.extend(b[ok]);ii.extend([i]*ok.sum());jj.extend([j]*ok.sum())
ma=np.array(ma);mb=np.array(mb);ii=np.array(ii);jj=np.array(jj)
def residual(par):
    c=par[3:].reshape(-1,2)
    e=offsets(ma,par)+c[ii]-offsets(mb,par)-c[jj]
    return np.r_[e.ravel(),((c-centers)*2).ravel(),(par[0]-50)/15]
fit=least_squares(residual, initial,loss='soft_l1',f_scale=.2,
                  bounds=(np.r_[35,12,8,(centers-1.6).ravel()],np.r_[65,65,65,(centers+1.6).ravel()]),max_nfev=200)
par=fit.x;error=np.linalg.norm(offsets(ma,par)+par[3:].reshape(-1,2)[ii]-offsets(mb,par)-par[3:].reshape(-1,2)[jj],axis=1)
print('camera pitch,fov,distance',par[:3], 'ground median error(m)',np.median(error), 'samples',len(ma))
result=dict(camera=par[:3].tolist(),groundResidualMedianMeters=float(np.median(error)),groundCorrespondences=len(ma),
            frames={name:{'minimap':m.tolist(),'hero':c.tolist()} for name,m,c in zip(data['files'],mini,par[3:].reshape(-1,2))})
(work/'camera-fit.json').write_text(json.dumps(result,indent=2)+'\n')
