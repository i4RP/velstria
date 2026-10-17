#!/usr/bin/env python3
"""Compare a landscape simulator capture with the supplied reference, without deforming geometry.

Only uniform resize + centre crop is applied. Use -stageCam/-stagePitch to align the actual camera.
Usage: python3 tools/stage/compare_pit.py reference.png screenshot.png output-directory
"""
import argparse
from pathlib import Path
from PIL import Image, ImageChops, ImageEnhance, ImageOps, ImageStat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("capture", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    reference = Image.open(args.reference).convert("RGB")
    capture = Image.open(args.capture).convert("RGB")
    if sum(ImageStat.Stat(capture.resize((64, 64))).mean) / 3 < 20:
        raise SystemExit("Capture is dark/loading; wait for the battlefield before comparing.")
    if capture.height > capture.width:
        capture = capture.transpose(Image.Transpose.ROTATE_270)
    aligned = ImageOps.fit(capture, reference.size, method=Image.Resampling.LANCZOS)
    args.output.mkdir(parents=True, exist_ok=True)
    aligned.save(args.output / "capture.png")
    Image.blend(reference, aligned, 0.5).save(args.output / "overlay.png")
    ImageEnhance.Contrast(ImageChops.difference(reference, aligned)).enhance(2).save(args.output / "difference.png")
    pair = Image.new("RGB", (reference.width * 2, reference.height))
    pair.paste(reference, (0, 0))
    pair.paste(aligned, (reference.width, 0))
    pair.save(args.output / "comparison.png")
    print(args.output / "overlay.png")


if __name__ == "__main__":
    main()
