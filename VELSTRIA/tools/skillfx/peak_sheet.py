# 録画から「直前のコマとの差」が最大のコマ（効果の山）を見つけ、その前後を 4 列のシートに並べる（Pillow が必要）。
# usage: peak_sheet.py <mp4> <out.png> [pre秒] [post秒] [コマ数]
import sys,subprocess,glob,os
from PIL import Image, ImageChops, ImageStat
mp4,out=sys.argv[1],sys.argv[2]
pre=float(sys.argv[3]) if len(sys.argv)>3 else 0.3
post=float(sys.argv[4]) if len(sys.argv)>4 else 1.3
N=int(sys.argv[5]) if len(sys.argv)>5 else 16
d=mp4+'.frames'; os.makedirs(d,exist_ok=True)
for f in glob.glob(d+'/*.png'): os.remove(f)
fps=20
subprocess.run(['ffmpeg','-loglevel','error','-i',mp4,'-vf',f'fps={fps},transpose=2,crop=1000:720:811:160',d+'/%04d.png'],check=True)
fs=sorted(glob.glob(d+'/*.png'))
small=[Image.open(f).convert('L').resize((100,72)) for f in fs]
# 背景 = 後半のコマの中央値の代わりに、最後の方のコマ
import statistics
scores=[]
for i,im in enumerate(small):
    j=max(0,i-6)
    diff=ImageChops.difference(im,small[j])
    scores.append(ImageStat.Stat(diff).mean[0])
# 最初の 1/4 は歩きなどで動くので重みを下げる
skip=len(fs)//4
peak=max(range(skip,len(fs)),key=lambda i:scores[i])
a=max(0,peak-int(pre*fps)); b=min(len(fs),peak+int(post*fps))
sel=fs[a:b]; step=max(1,len(sel)//N); sel=sel[::step][:N]
ims=[Image.open(f) for f in sel]
w,h=ims[0].size; sw,sh=int(w*0.5),int(h*0.5)
sheet=Image.new('RGB',(sw*4,sh*((len(ims)+3)//4)))
for k,im in enumerate(ims): sheet.paste(im.resize((sw,sh)),((k%4)*sw,(k//4)*sh))
sheet.save(out); print(out, 'peak', peak/fps, 's')
