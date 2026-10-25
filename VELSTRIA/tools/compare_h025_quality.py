"""Join equal review sequences; offsets are read from the on-screen review clock.
python3 tools/compare_h025_quality.py before.mp4 after.mp4 output.mp4 --before-start .67 --after-start .70
This keeps each original camera frame intact, at 1280px per panel. No camera crop.
"""
import argparse
import subprocess
import tempfile
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('before'); p.add_argument('after'); p.add_argument('output')
p.add_argument('--before-start',type=float,required=True)
p.add_argument('--after-start',type=float,required=True)
p.add_argument('--label',default='FINAL')
p.add_argument('--before-label',default='BEFORE 95d3b7fe')
a=p.parse_args()
def panel(index,offset,title,label):
    return (f'[{index}:v]trim=start={offset}:duration=38,setpts=PTS-STARTPTS,fps=30,scale=1280:-2,'
            f'pad=1280:640:0:40:black[{label}]')
filters=panel(0,a.before_start,'BEFORE 95d3b7fe','l')+';'+panel(1,a.after_start,a.label,'r')+';[l][r]hstack=inputs=2:shortest=1[joined];[joined][2:v]overlay=0:0:shortest=1[v]'
with tempfile.TemporaryDirectory() as folder:
    header=Path(folder)/'header.png'
    swift=Path(folder)/'header.swift'
    swift.write_text('''import AppKit
let image = NSImage(size: NSSize(width: 2560, height: 40))
image.lockFocus()
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: 2560, height: 40).fill()
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 25), .foregroundColor: NSColor.white]
(CommandLine.arguments[3] as NSString).draw(at: NSPoint(x: 30, y: 5), withAttributes: attributes)
(CommandLine.arguments[2] as NSString).draw(at: NSPoint(x: 1310, y: 5), withAttributes: attributes)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
''')
    subprocess.run(['swift',str(swift),str(header),a.label,a.before_label],check=True)
    subprocess.run(['ffmpeg','-y','-v','error','-i',a.before,'-i',a.after,'-loop','1','-i',str(header),'-filter_complex',filters,
                    '-map','[v]','-an','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p',
                    '-movflags','+faststart',a.output],check=True)
