#!/usr/bin/env python3
"""Reference/actual unit crops and overlays. Images remain in ignored build/.
Usage: uv run --with pillow python tools/stage/compare_units.py WORK [capture-directory]
Uses uniform full-frame resizing; no per-unit warping or resizing.
"""
import json,sys
from pathlib import Path
from PIL import Image,ImageOps,ImageDraw
from capture_orientation import landscape_capture
ROOT=Path(__file__).resolve().parents[2]
work=Path(sys.argv[1]);captures=Path(sys.argv[2]) if len(sys.argv)>2 else work/'captures'
source=ROOT/'build/stage/reference-20261019'
out=work/'units';out.mkdir(parents=True,exist_ok=True)
regions={
'IMG_6713':(380,15,800,415),
'IMG_6722':(480,50,880,400),
'IMG_6688':(600,225,1030,465),
'IMG_6694':(320,195,780,470),
'IMG_6712':(360,0,840,405),
'IMG_6697':(595,180,1080,430),
'IMG_6721':(355,200,780,410),
'IMG_6689':(585,190,940,420),
}
rows=[];cards=[]
measurements=[]
def capture_image(path):
    im=landscape_capture(Image.open(path).convert('RGB'))
    return ImageOps.fit(im,(1368,630),method=Image.Resampling.LANCZOS)

def bar_size(im,rect,color):
    # Full-health render fixtures: the colored strip determines width and thickness,
    # including gaps for HP ticks. Source partial health is never treated as full width.
    x0,y0,x1,y1=rect;pixels=im.load();rows=[]
    for y in range(y0,y1):
        xs=[]
        for x in range(x0,x1):
            r,g,b=pixels[x,y]
            good={'self':g>180 and g>r*1.25 and g>b*1.2,
                  'ally':b>180 and b>r*1.3 and g>100,
                  'enemy':r>180 and r>g*1.25 and r>b*1.1}[color]
            if good:xs.append(x)
        if len(xs)>75 and xs[-1]-xs[0]<130:rows.append((y,xs[0],xs[-1]+1))
    if not rows:return None
    y,left,right=rows[len(rows)//2]
    return {'width':right-left,'height':rows[-1][0]-rows[0][0]+1,'rect':[left,rows[0][0],right,rows[-1][0]+1]}

for path in sorted(captures.glob('IMG_*.png')):
    if '-landscape' in path.stem:continue
    result=bar_size(capture_image(path),(600,215,800,285),'self')
    if result:measurements.append({'frame':path.stem,'team':'self',**result})
teams=captures/'UNIT_TEAMS.png'
if teams.exists():
    im=capture_image(teams);im.save(out/'UNIT_TEAMS.png')
    for team,rect in [('ally',(300,220,450,290)),('enemy',(900,220,1050,290))]:
        result=bar_size(im,rect,team)
        if result:measurements.append({'frame':'UNIT_TEAMS','team':team,**result})
for name,rect in regions.items():
    capture=captures/(name+'.png')
    if not capture.exists():continue
    ref=Image.open(source/(name+'.png')).convert('RGB')
    actual=capture_image(capture)
    actual.save(out/(name+'-actual.png'))
    refcrop=ref.crop(rect);actualcrop=actual.crop(rect)
    overlay=Image.blend(refcrop,actualcrop,.5)
    w,h=refcrop.size
    row=Image.new('RGB',(w*3,h+24),'#152226');d=ImageDraw.Draw(row)
    for i,(im,label) in enumerate([(refcrop,'reference'),(actualcrop,'actual'),(overlay,'50% overlay')]):
        d.text((w*i+5,5),name+' '+label,fill='white');row.paste(im,(w*i,24))
    row.save(out/(name+'-units.jpg'),quality=95)
    row.thumbnail((1200,420));rows.append(row)
    cards.append(f'<article><h2>{name}</h2><img src="{name}-units.jpg"></article>')
for page in range(0,len(rows),4):
    group=rows[page:page+4];sheet=Image.new('RGB',(1200,sum(im.height for im in group)),'#152226');y=0
    for im in group:sheet.paste(im,(0,y));y+=im.height
    sheet.save(out/f'units-{page//4+1}.jpg',quality=94)
(out/'measurements.json').write_text(json.dumps({'canonicalSize':[1368,630],'referenceHeroHP':[104,9],'measurements':measurements},indent=2)+'\n')
table='<table><tr><th>画像</th><th>陣営</th><th>HP幅px</th><th>厚みpx</th></tr>'+''.join(f'<tr><td>{m["frame"]}</td><td>{m["team"]}</td><td>{m["width"]}</td><td>{m["height"]}</td></tr>' for m in measurements)+'</table>'
(out/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>ユニット寸法比較</title><style>body{background:#152226;color:white;font:16px system-ui}img{max-width:100%}article{margin:24px 0}td,th{padding:4px 12px;text-align:left}</style><h1>参照 / 実画面 / 50%重ね合わせ</h1><p>全画面を1368×630に揃えた後、同じ矩形で切り出し。敵の種類・位置・向きは撮影用に固定。モデル・ゲージの寸法は通常プレイと共通。モデル固有の形状と動作の差は残ります。</p><h2>HP色面の実測（参照幅約104〜106px・厚み約9px）</h2>'+table+('<h2>自分・味方・敵の共通寸法</h2><img src="UNIT_TEAMS.png">' if teams.exists() else '')+''.join(cards))
print(out/'index.html')
