#!/usr/bin/env python3
"""Capture the actual iPhone simulator drawable for the isolated FPS mesh review.

Usage: python3 tools/fps_visibility_review.py --udid EXPLICIT_SIMULATOR_UUID \
  --app build/FPSDerived/Build/Products/Debug-iphonesimulator/VELSTRIA.app

Merge completed batches without accessing a simulator:
  python3 tools/fps_visibility_review.py --summarize-only \
    --inputs build/fps-visibility-a build/fps-visibility-b build/fps-visibility-c \
    --out build/fps-visibility-final

Never chooses or alters another simulator. One hero per process; normal games do
not load the whole roster. Requires Pillow and numpy. Masks count every covered
pixel, not alpha-weighted area. Occupancy is descriptive; there is no area limit.
Only unclipped schema 3 captures can be resumed or summarized. Historical clipped
reports remain separate. The output is simulator evidence, not device FPS.
"""
import argparse
import csv
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

import numpy as np
from PIL import Image, ImageDraw

BUNDLE = "com.bitcoinpay.velstria"
RENDERING_MODE = "unclippedHalfOpacity"
MASTER_PATH = Path(__file__).resolve().parents[1] / "Packages/VelstriaCore/Sources/VelstriaCore/Resources/master_runtime.json"


def all_hero_ids():
    # Mirrors MasterData.allHeroes. MasterData.heroes is the smaller currently
    # playable roster, and was recorded as masterRoster by the review driver.
    master = json.loads(MASTER_PATH.read_text())
    return sorted(hero["hero_id"] for hero in master["heroes"])


def current_playable_roster(report):
    return report.get("currentPlayableRoster")


def require_current_capture(report):
    if report.get("schemaVersion", 1) < 3 or report.get("renderingMode") != RENDERING_MODE:
        raise ValueError("Historical clipped captures cannot verify the current unclipped model; keep them separately and use a new output directory")


def command(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True)


def atomic_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True))
    temporary.replace(path)


def frame_for_request(raw_path, request):
    image = Image.open(raw_path).convert("RGB")
    if image.height > image.width:
        # Match the existing capture scripts' `sips -r 270` (clockwise).
        image = image.transpose(Image.Transpose.ROTATE_90)
    x, y, w, h = request["viewport"]
    if not all(math.isfinite(v) for v in (x, y, w, h)) or w <= 0 or h <= 0:
        raise ValueError("Invalid ARView viewport")
    box = (round(image.width * x), round(image.height * y),
           round(image.width * (x + w)), round(image.height * (y + h)))
    return image.crop(box)


def capture(udid, handshake, dest, request):
    if request.get("renderingMode") != RENDERING_MODE:
        raise ValueError("The installed review app predates unclipped rendering; rebuild it before capture")
    if not request.get("shaderReady") or request.get("unsupportedMaterials") != 0:
        raise ValueError("Shader not ready or unsupported material; empty masks are not a pass")
    raw = handshake / "raw.png"
    command("xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(raw))
    image = frame_for_request(raw, request)
    scenario = request["scenario"]
    if request["kind"] == "color":
        image.thumbnail((1108, 1108))
        image.save(dest / f"{scenario}-worst.png")
        atomic_json(dest / f"{scenario}-worst.json", request)
        return {"id": request["id"]}
    pixels = np.asarray(image)
    # sRGB threshold 8/255 excludes black and capture noise; a 50% white model is
    # far above it. Each covered pixel contributes one, never its opacity.
    mask = np.max(pixels, axis=2) > 8
    occupied = int(np.count_nonzero(mask))
    total = int(mask.size)
    coverage = occupied / total
    name = f"{scenario}-{request['sample']:04d}"
    mask_image = Image.fromarray(np.uint8(mask) * 255)
    mask_image.save(dest / "masks" / f"{name}.png", optimize=True)
    response = {"id": request["id"], "coverage": coverage,
                "occupiedPixels": occupied, "totalPixels": total}
    atomic_json(dest / "masks" / f"{name}.json", request | response)
    return response


def run_hero(args, hero, handshake):
    dest = args.out / hero
    (dest / "masks").mkdir(parents=True, exist_ok=True)
    for path in handshake.glob("*.json"):
        path.unlink()
    data = Path(command("xcrun", "simctl", "get_app_container", args.udid, BUNDLE, "data").stdout.strip())
    manifest = data / "Documents" / "fpsvisibility" / hero / "manifest.json"
    if manifest.exists():
        manifest.unlink()
    log = dest / "app.log"
    command("xcrun", "simctl", "launch", "--terminate-running-process", f"--stdout={log}", f"--stderr={log}",
            args.udid, BUNDLE, "-uiTesting", "-skipOnboarding", "-heroGallery", "-fpsVisibilityReview",
            "-fpsVisibilityHero", hero, "-fpsVisibilityHz", str(args.hz),
            "-fpsVisibilityHandshake", str(handshake))
    deadline = time.monotonic() + args.timeout
    last_id = None
    last_scenario = None
    while time.monotonic() < deadline:
        request_file = handshake / "request.json"
        if request_file.exists():
            try:
                request = json.loads(request_file.read_text())
            except (json.JSONDecodeError, FileNotFoundError):
                time.sleep(0.05)
                continue
            if request["id"] != last_id:
                if request["hero"] != hero:
                    raise RuntimeError("Capture request came from another hero")
                if request["scenario"] != last_scenario:
                    print(f"{hero}: {request['scenario']}", flush=True)
                    last_scenario = request["scenario"]
                try:
                    response = capture(args.udid, handshake, dest, request)
                except Exception as error:
                    atomic_json(handshake / "done.json", {"id": request["id"], "error": str(error)})
                    raise
                last_id = request["id"]
                request_file.unlink(missing_ok=True)
                atomic_json(handshake / "done.json", response)
        if manifest.exists():
            report = json.loads(manifest.read_text())
            atomic_json(dest / "manifest.json", report)
            command("xcrun", "simctl", "terminate", args.udid, BUNDLE, check=False)
            if not report.get("completed"):
                raise RuntimeError(report.get("error", "Review did not complete"))
            return report
        time.sleep(0.03)
    raise TimeoutError(f"{hero} did not finish within {args.timeout}s; log: {log}")


def summarize(args, reports, environment):
    rows = []
    failures = []
    roster = all_hero_ids()
    for report in reports:
        require_current_capture(report)
        if not current_playable_roster(report) or report["hero"] not in roster:
            raise ValueError(f"{report['hero']}: missing playable roster metadata or hero absent from the complete source catalog")
        if report.get("allHeroRoster", roster) != roster:
            raise ValueError(f"{report['hero']}: capture's full roster differs from the source catalog")
        required = {"idle", "walk", "run", "attack_0", "passive_empowered", "skill1", "skill2", "ultimate", "look_down"}
        if not required.issubset(report.get("scenarios", [])):
            raise ValueError(f"{report['hero']}: incomplete idle/move/attack/active-skill/down-look scenarios")
        if len(set(report["scenarios"])) != len(report["scenarios"]):
            raise ValueError(f"{report['hero']}: duplicate scenario metadata")
        for scenario in report["scenarios"]:
            samples = [r for r in report["samples"] if r["scenario"] == scenario]
            if not samples:
                raise ValueError(f"{report['hero']}: no captured poses for {scenario}")
            if any(not math.isfinite(r.get("opacity", math.nan)) or abs(r["opacity"] - 0.5) >= 0.0001 for r in samples):
                raise ValueError(f"{report['hero']}: opacity component was not 0.5 in {scenario}")
            if any(not math.isfinite(r.get("coverage", math.nan)) or not 0 <= r["coverage"] <= 1 for r in samples):
                raise ValueError(f"{report['hero']}: invalid pixel coverage in {scenario}")
            if any(not r.get("shaderReady") or r.get("unsupportedMaterials") != 0
                   or r.get("preparedModels", 0) < 1 for r in samples):
                raise ValueError(f"{report['hero']}: shader was not ready in {scenario}")
            worst = max(samples, key=lambda row: row["coverage"])
            # A few noisy pixels cannot count as evidence that the down-look body rendered.
            visible = worst["coverage"] > 0.005 if scenario == "look_down" else True
            row = {"hero": report["hero"], "scenario": scenario, "samples": len(samples),
                   "maxCoverage": worst["coverage"], "timeOfMaximum": worst["time"],
                   "opacity": worst["opacity"], "pitch": worst["pitch"], "pass": visible}
            rows.append(row)
            if not visible:
                failures.append(row)
    forward = [row["maxCoverage"] for row in rows if row["pitch"] == 0]
    playable_roster = current_playable_roster(reports[0]) if reports else []
    if any(current_playable_roster(report) != playable_roster for report in reports):
        raise ValueError("Reports use different currently playable rosters")
    captured = sorted(report["hero"] for report in reports)
    if len(set(captured)) != len(captured):
        raise ValueError("Duplicate hero reports cannot count toward all-roster coverage")
    summary = {"environment": environment, "heroes": len(reports), "sampleHz": args.hz,
               "renderingMode": RENDERING_MODE,
               "allHeroRoster": roster, "capturedHeroes": captured, "rosterComplete": captured == roster,
               "currentPlayableRoster": playable_roster,
               "completeRosterSource": str(MASTER_PATH.relative_to(Path(__file__).resolve().parents[2])),
               "captureSchemaVersions": sorted({report.get("schemaVersion", 1) for report in reports}),
               "samples": sum(row["samples"] for row in rows), "maximumForwardCoverage": max(forward, default=None),
               "coverageIsDescriptive": True, "opacity": 0.5, "pixelThreshold": "max RGB > 8/255; full pixel counts",
               "physicalDeviceVerified": False, "passed": not failures and len(reports) == len(args.heroes),
               "limitations": "Deterministic sampled rendered poses. Coverage has no pass/fail upper limit; inspect color images for visible shape. No claim of full gameplay testing.",
               "failures": failures, "states": rows}
    atomic_json(args.out / "summary.json", summary)
    with (args.out / "coverage.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]) if rows else ["hero"])
        writer.writeheader()
        writer.writerows(rows)
    contact_sheets(args.out, rows)
    return summary


def contact_sheets(out, rows):
    for hero in sorted({row["hero"] for row in rows}):
        selected = [row for row in rows if row["hero"] == hero]
        width, height, columns = 370, 204, 3
        sheet = Image.new("RGB", (width * columns, height * math.ceil(len(selected) / columns)), "#14202b")
        draw = ImageDraw.Draw(sheet)
        for index, row in enumerate(selected):
            x, y = (index % columns) * width, (index // columns) * height
            image_file = out / hero / f"{row['scenario']}-worst.png"
            if image_file.exists():
                image = Image.open(image_file).convert("RGB")
                image.thumbnail((width - 8, height - 35))
                sheet.paste(image, (x + 4, y + 29))
            color = "#7cffa9" if row["pass"] else "#ff6c70"
            label = f"{hero} {row['scenario']} {row['maxCoverage'] * 100:.2f}%"
            draw.text((x + 5, y + 5), label, fill=color)
        sheet.save(out / f"{hero}-contact.png")
    # All-roster strip shows the worst forward pose and the required down-look.
    heroes = sorted({row["hero"] for row in rows})
    sheet = Image.new("RGB", (740, 204 * len(heroes)), "#14202b")
    draw = ImageDraw.Draw(sheet)
    for index, hero in enumerate(heroes):
        states = [row for row in rows if row["hero"] == hero]
        selected = [max((r for r in states if r["pitch"] == 0), key=lambda r: r["maxCoverage"]),
                    next(r for r in states if r["scenario"] == "look_down")]
        for col, row in enumerate(selected):
            image = Image.open(out / hero / f"{row['scenario']}-worst.png").convert("RGB")
            image.thumbnail((362, 169))
            x, y = 370 * col, 204 * index
            sheet.paste(image, (x + 4, y + 29))
            draw.text((x + 5, y + 5), f"{hero} {row['scenario']} {row['maxCoverage'] * 100:.2f}%", fill="white")
    sheet.save(out / "roster-contact.png")


def merge_existing(args):
    """Read completed captures only. No simctl command or app launch is performed."""
    if not args.inputs:
        raise ValueError("--summarize-only requires --inputs with completed capture directories")
    roster = all_hero_ids()
    if len(roster) != 34 or len(set(roster)) != 34:
        raise ValueError("The source catalog must contain the expected 34 distinct heroes")
    found = {}
    sources = []
    for directory in args.inputs:
        directory = directory.resolve()
        source_summary = directory / "summary.json"
        source = {"path": str(directory)}
        if source_summary.exists():
            metadata = json.loads(source_summary.read_text())
            source["environment"] = metadata.get("environment")
        sources.append(source)
        for manifest in sorted(directory.glob("H*/manifest.json")):
            report = json.loads(manifest.read_text())
            require_current_capture(report)
            hero = report.get("hero")
            if hero not in roster or manifest.parent.name != hero:
                raise ValueError(f"Unexpected hero report: {manifest}")
            if not report.get("completed"):
                raise ValueError(f"Incomplete capture: {manifest}")
            if hero in found:
                raise ValueError(f"Duplicate capture for {hero}; pass disjoint input batches")
            found[hero] = (report, manifest.parent.resolve())
    missing = sorted(set(roster) - set(found))
    if missing:
        raise ValueError(f"All-roster summary requires all 34 heroes; missing: {', '.join(missing)}")
    frequencies = {float(report["sampleHz"]) for report, _ in found.values()}
    if len(frequencies) != 1:
        raise ValueError("Capture sample frequencies differ between batches")
    args.hz = frequencies.pop()
    args.heroes = roster
    for hero, (_, source_dir) in found.items():
        target = args.out / hero
        if target.exists() or target.is_symlink():
            if target.resolve() != source_dir:
                raise ValueError(f"Refusing to overwrite existing evidence: {target}")
        else:
            target.symlink_to(source_dir, target_is_directory=True)
        # Keep source masks and raw manifests intact. Individual contact sheets
        # are regenerated in the output, and compact summary/CSV can be committed.
        source_contact = source_dir.parent / f"{hero}-contact.png"
        if source_contact.exists():
            shutil.copy2(source_contact, args.out / f"{hero}-contact.png")
    return summarize(args, [found[hero][0] for hero in roster],
                     {"kind": "simulator", "captureBatches": sources, "captureOnly": True})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", help="Explicit simulator UUID; required for capture, never auto-selected")
    parser.add_argument("--app", type=Path, help="Install this already-built simulator app")
    parser.add_argument("--out", type=Path, default=Path("build/fps-visibility"))
    parser.add_argument("--heroes", nargs="+", default=all_hero_ids())
    parser.add_argument("--hz", type=float, default=3)
    parser.add_argument("--timeout", type=int, default=1500, help="Per-hero deadline")
    parser.add_argument("--resume", action="store_true", help="Keep completed per-hero manifests")
    parser.add_argument("--summarize-only", action="store_true", help="Merge complete existing captures; never access a simulator")
    parser.add_argument("--inputs", nargs="+", type=Path, help="Disjoint completed capture batches for --summarize-only")
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.summarize_only:
        summary = merge_existing(args)
        print(json.dumps({key: summary[key] for key in ("heroes", "samples", "maximumForwardCoverage", "rosterComplete", "passed")}, indent=2))
        return 0 if summary["passed"] and summary["rosterComplete"] else 1
    if not args.udid:
        parser.error("--udid is required for capture")
    if args.inputs:
        parser.error("--inputs is only used with --summarize-only")
    devices = json.loads(command("xcrun", "simctl", "list", "devices", "available", "-j").stdout)["devices"]
    matches = [(runtime, device) for runtime, group in devices.items() for device in group if device["udid"] == args.udid]
    if len(matches) != 1:
        parser.error("--udid must identify an available simulator")
    runtime, device = matches[0]
    if "NC-UGC-A" in device["name"]:
        parser.error("The reserved NC-UGC-A simulator must not be used")
    if device["state"] != "Booted":
        command("xcrun", "simctl", "boot", args.udid)
        command("xcrun", "simctl", "bootstatus", args.udid, "-b")
    if args.app:
        command("xcrun", "simctl", "install", args.udid, str(args.app.resolve()))
    environment = {"device": device["name"], "runtime": runtime, "udid": args.udid, "kind": "simulator"}
    reports = []
    with tempfile.TemporaryDirectory(prefix="velstria-fpsvisibility-") as temp:
        for hero in args.heroes:
            manifest = args.out / hero / "manifest.json"
            report = json.loads(manifest.read_text()) if args.resume and manifest.exists() else None
            if not report or not report.get("completed"):
                report = run_hero(args, hero, Path(temp))
            reports.append(report)
            summary = summarize(args, reports, environment)
            print(f"{hero} complete: maximum forward {report['forwardMaximum'] * 100:.3f}%", flush=True)
    print(json.dumps({key: summary[key] for key in ("heroes", "samples", "maximumForwardCoverage", "passed")}, indent=2))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
