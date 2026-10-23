"""Retiming fallback for the checked-in mix when original recording cache is absent.
Keeps release transient samples at their original rate; impact/split from 0.65s
onward are byte-identical PCM. Quiet draw/tail intervals absorb the 53.3ms shift.
The layered h025.py recipe has the same release time for future source rebuilds.
Run from VELSTRIA: python3 tools/audio/retime_h025_s2.py
"""
from array import array
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ASSET='App/Resources/Audio/skill_H025_s2_cast.caf'
source=subprocess.check_output(['git','show','95d3b7fe:VELSTRIA/'+ASSET])
with tempfile.TemporaryDirectory() as folder:
    old=Path(folder)/'old.caf'; old.write_bytes(source)
    raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(old),'-f','s16le','-ac','1','-ar','48000','-'])
    samples=array('h'); samples.frombytes(raw)
    result=array('h')
    # (new time, original time); unity slope over the release and its attack.
    keys=[(0,0),(.14,.14),(.213333333333,.266666666667),(.50,.553333333333),(.65,.65)]
    for frame in range(len(samples)):
        t=frame/48000
        if t>=.65:
            result.append(samples[frame]); continue
        for (x,y),(nx,ny) in zip(keys,keys[1:]):
            if t<=nx:
                sourceFrame=(y+(ny-y)*(t-x)/(nx-x))*48000
                i=int(sourceFrame); fraction=sourceFrame-i
                result.append(round(samples[i]*(1-fraction)+samples[min(i+1,len(samples)-1)]*fraction))
                break
    pcm=Path(folder)/'retimed.pcm'; pcm.write_bytes(result.tobytes())
    subprocess.run(['ffmpeg','-y','-v','error','-f','s16le','-ac','1','-ar','48000','-i',str(pcm),
                    '-c:a','pcm_s16le',ASSET],check=True)
    assert samples[31200:]==result[31200:]
    report=dict(sourceSHA256=hashlib.sha256(source).hexdigest(),releaseBefore=.32,releaseAfter=8/30,
                impact=.65,split=.98,impactPCMIdentical=True,frames=len(result),mapping=keys)
    out=Path('build/h025-quality/audio-retime.json'); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,indent=2))
    print(json.dumps(report))
