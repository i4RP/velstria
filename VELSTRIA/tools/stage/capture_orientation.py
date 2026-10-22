"""Normalize fixed stage-review screenshots, including a simulator orientation change.

simctl writes portrait pixels without an orientation EXIF tag. The known self HP
strip is above the fixed hero in a stage-review frame; use that to choose the
upright quarter turn. This rotates the whole image, never individual content.
"""
from PIL import Image


def landscape_capture(image):
    turns = [(Image.Transpose.ROTATE_90, 90), (Image.Transpose.ROTATE_270, 270)] if image.height > image.width else [(None, 0), (Image.Transpose.ROTATE_180, 180)]
    candidates = []
    for operation, degrees in turns:
        im = image.transpose(operation) if operation is not None else image.copy()
        sample = im.resize((342, 158)).convert('RGB')
        pixels = sample.load()
        score = max(sum(g > 150 and g > r * 1.25 and g > b * 1.2
                        for r, g, b in (pixels[x, y] for x in range(150, 200)))
                    for y in range(48, 74))
        im.info['reviewRotation'] = degrees
        candidates.append((score, im))
    return max(candidates, key=lambda pair: pair[0])[1]
