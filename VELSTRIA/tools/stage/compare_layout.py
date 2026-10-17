#!/usr/bin/env python3
"""Compare a -stageLayoutReference capture with the 1080x592 user reference.

Usage: python compare_layout.py reference.png simulator.png output-directory
Uniform scale and centre crop only. Traced ground footprints are overlaid on both
images so position/size can be reviewed independently of materials and lighting.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageOps

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('reference', type=Path)
parser.add_argument('capture', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
ref = Image.open(args.reference).convert('RGB')
if ref.size != (1080, 592):
    parser.error('The traced reference must be 1080x592.')
actual = Image.open(args.capture).convert('RGB')
if actual.height > actual.width:
    actual = actual.transpose(Image.Transpose.ROTATE_270)
actual = ImageOps.fit(actual, ref.size, method=Image.Resampling.LANCZOS)
args.output.mkdir(parents=True, exist_ok=True)
actual.save(args.output / 'capture.png')
Image.blend(ref, actual, 0.5).save(args.output / 'overlay.png')
ImageChops.difference(ref, actual).save(args.output / 'difference.png')
pair = Image.new('RGB', (2160, 592))
pair.paste(ref, (0, 0)); pair.paste(actual, (1080, 0))
pair.save(args.output / 'comparison.png')
layout = json.loads((Path(__file__).parents[1] / 'map_proto/reference_layout.json').read_text())
for name, im in [('reference-footprints', ref.copy()), ('capture-footprints', actual.copy())]:
    draw = ImageDraw.Draw(im)
    for key, color in [('walls', '#ffce65'), ('bushes', '#39edb2')]:
        for i, polygon in enumerate(layout[key]):
            points = [tuple(p) for p in polygon]
            draw.line(points + points[:1], fill=color, width=2)
            draw.text(points[0], str(i), fill=color)
    for x, y in layout['walkable']:
        draw.ellipse((x-6, y-6, x+6, y+6), outline='#ff38e0', width=2)
    im.save(args.output / f'{name}.png')
print(args.output / 'comparison.png')
