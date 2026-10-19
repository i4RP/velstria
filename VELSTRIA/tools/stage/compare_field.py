#!/usr/bin/env python3
"""All-image visual review: actual simulator captures, uniform scale, no warping.
uv run --with pillow python tools/stage/compare_field.py [work-directory]
Reference art stays under ignored build/. The HTML shows every pair and overlay.
"""
import json, sys, hashlib, html
from pathlib import Path
from PIL import Image, ImageOps, ImageChops, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
work=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'build/stage/reference-20261019'
out=work/'review';out.mkdir(exist_ok=True)
poses=json.loads((ROOT/'tools/map_proto/field_camera.json').read_text())['frames']
cards=[];manifest=[];thumbs=[]
for name,pose in poses.items():
    source=work/(name+'.png');capture=work/'captures'/(name+'.png')
    if not capture.exists(): raise SystemExit(f'Missing actual capture: {name}')
    ref=Image.open(source).convert('RGB');actual=Image.open(capture).convert('RGB')
    if actual.height>actual.width:actual=actual.transpose(Image.Transpose.ROTATE_90)
    actual=ImageOps.fit(actual,ref.size,method=Image.Resampling.LANCZOS)
    ref.save(out/(name+'-reference.jpg'),quality=92);actual.save(out/(name+'-actual.jpg'),quality=92)
    overlay=Image.blend(ref,actual,.5);overlay.save(out/(name+'-overlay.jpg'),quality=94)
    ImageChops.difference(ref,actual).save(out/(name+'-difference.png'))
    pair=Image.new('RGB',(ref.width*2,ref.height));pair.paste(ref,(0,0));pair.paste(actual,(ref.width,0))
    pair.save(out/(name+'-pair.jpg'),quality=92)
    thumb=pair.resize((912,210));thumbs.append((name,thumb))
    cards.append(f'<article><h2>{name}</h2><div class="compare"><img src="{name}-reference.jpg"><img class="actual" src="{name}-actual.jpg"></div><input type="range" min="0" max="100" value="50" oninput="this.previousElementSibling.lastElementChild.style.opacity=this.value/100"><p><a href="{name}-pair.jpg">並列</a> · <a href="{name}-overlay.jpg">50%重ね合わせ</a> · <a href="{name}-difference.png">差分</a></p></article>')
    manifest.append(dict(name=name,referenceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),
                         captureSHA256=hashlib.sha256(capture.read_bytes()).hexdigest(),heroMeters=pose['hero']))
for page in range(0,len(thumbs),6):
    sheet=Image.new('RGB',(912,6*236),'#152226');draw=ImageDraw.Draw(sheet)
    for i,(name,im) in enumerate(thumbs[page:page+6]):
        draw.text((8,i*236+5),name+'  | reference / actual',fill='white');sheet.paste(im,(0,i*236+24))
    sheet.save(out/f'contact-{page//6+1}.jpg',quality=92)
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(out/'index.html').write_text('''<!doctype html><html lang="ja"><meta charset="utf-8"><title>ステージ全画像比較</title>
<style>body{font:16px system-ui;background:#101a1d;color:#e2efed;margin:24px auto;max-width:1380px}article{padding:16px 0;border-bottom:1px solid #385052}.compare{position:relative;aspect-ratio:1368/630}.compare img{width:100%;display:block}.actual{position:absolute;inset:0;opacity:.5}input{width:100%}a{color:#8fe3cb}h2{font-size:18px}</style>
<h1>参照26枚と実際のゲーム表示</h1><p>左端=参照、右端=実際の表示。スライダーは透明度。画像を局所変形せず、同じ画角で中央切り出ししています。HUD・キャラクター・生成モデルの質感は画素一致の対象外です。</p>
'''+''.join(cards)+'</html>')
print(out/'index.html')
