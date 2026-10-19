#!/usr/bin/env python3
"""Capture every reference pose using the shipping lens (DEBUG -stageShot).
python tools/stage/field_shots.py UDID APP [IMG_6713 ...]
"""
import json,subprocess,sys,time
from pathlib import Path
from PIL import Image, ImageStat
ROOT=Path(__file__).resolve().parents[2]
device,app=sys.argv[1:3];work=ROOT/'build/stage/reference-20261019/captures';work.mkdir(parents=True,exist_ok=True)
reuse='--reuse' in sys.argv
names=[n for n in sys.argv[3:] if n!='--reuse'] or list(json.loads((ROOT/'tools/map_proto/field_camera.json').read_text())['frames'])
def run(*args,check=True):return subprocess.run(['xcrun','simctl',*args],check=check,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
if not reuse:
    run('install',device,app)
    run('terminate',device,'com.bitcoinpay.velstria',check=False)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.bitcoinpay.velstria','data'],text=True).strip())
control=container/'Documents/stage-review.txt';control.parent.mkdir(parents=True,exist_ok=True)
control.write_text(names[0])
if not reuse:
    run('launch',device,'com.bitcoinpay.velstria','-uiTesting','-skipOnboarding','-battle','practice','-hero','H028',
        '-stageFull','-stageSilent','-stageClean','-graphics','high','-stageShot',names[0],'-stageReview')
# Wait for actual terrain, never accept the loading screen as a comparison.
deadline=time.monotonic()+240
if not reuse:time.sleep(20) # iOS can briefly show the previous launch snapshot.
ready=0
while True:
    time.sleep(5)
    probe=work/'loading-probe.png';run('io',device,'screenshot',str(probe))
    im=Image.open(probe).convert('RGB')
    if im.height>im.width:im=im.transpose(Image.Transpose.ROTATE_90)
    sample=im.crop((im.width*.25,im.height*.2,im.width*.75,im.height*.7))
    stats=ImageStat.Stat(sample)
    ready=ready+1 if max(stats.mean)>28 and max(stats.stddev)>12 else 0
    if ready>=3:break
    if time.monotonic()>deadline:raise RuntimeError('Terrain did not become visible within 240 seconds')
print('Terrain ready',flush=True)
for name in names:
    control.write_text(name)
    time.sleep(3)
    run('io',device,'screenshot',str(work/(name+'.png')))
    shot=Image.open(work/(name+'.png')).convert('RGB')
    if shot.height>shot.width:shot=shot.transpose(Image.Transpose.ROTATE_90)
    check=shot.crop((shot.width*.25,shot.height*.2,shot.width*.75,shot.height*.7))
    if max(ImageStat.Stat(check).mean)<=28:raise RuntimeError(f'{name}: gameplay is not visible')
    print(name,flush=True)
run('terminate',device,'com.bitcoinpay.velstria',check=False)
