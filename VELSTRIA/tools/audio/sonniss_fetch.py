"""Sonniss GDC Game Audio Bundle（無料・商用可・帰属不要。AI の学習への利用は禁止）から、スキルの音に使う素材だけを落とす。

公式の配布（gdc.sonniss.com）はスクリプトから落とせない（Cloudflare）ので、同じ素材の archive.org の写し
（sonniss-gdc-<年>-game-audio-bundle-normalized。素材ごとのファイルに分かれていて、必要な分だけ落とせる）を使う。
落とした原本は tools/audio/.cache/sonniss に置く（リポジトリに入れない）。加工した完成品だけを App/Resources/Audio に書く。
ライセンス: https://sonniss.com/gdc-bundle-license/
"""
import json
import os
import sys
import urllib.parse
import urllib.request

CACHE = os.path.join(os.path.dirname(__file__), ".cache", "sonniss")

# 年 → 使う素材集（フォルダ名の先頭一致）
PACKS = {
    "2026": [
        "Cinematic Sound Design - Colossal Impacts", "344 Audio - Cinematic Fight Vol. 1", "344 Audio - Historical Weapons Vol. 2",
        "David Dumais Audio - Melee Weapons Sound Effects Pack 2", "Alexander Kopeikin - 100 kHz Designed Ice",
        "Alexander Kopeikin - Emotion and Magic", "344 Audio - Elemental Palette Designed Vol. 1", "344 Audio - Air Designed",
        "InMotionAudio - Arc", "Federico Soler - Effective Trailer Booms Vol. 2", "Jake Fielding - Cinematic Horn Braams",
        "Cinematic Sound Design - Ultra Transitions & Impacts", "Ivo Vicic - Fireworks FX",
    ],
    "2024": [
        "Justsoundeffects - Melee Weapons", "Pole Position - The Metal Hit Sweeteners Library",
        "Jake Fielding - Haunted Metal Vol.1 - Cinematic Hits & Impacts", "InMotionAudio - Electromagnesis", "Mechanical Wave - Glass",
        "Rescopic Sound - Distinct Whooshes", "Rescopic Sound - Sci-Fi Energy Weapons", "DavidDumais - Explosion SFX Pack",
        "BluezoneCorp - Modern Cinematic Impact", "BluezoneCorp - Stone Impact", "BluezoneCorp - Sci Fi Weapon",
    ],
    "2020": [
        "Conor Bradley - Metal Chains", "PMSFX - Lethal Blow", "Shapeforms - Hit & Punch", "SmartSoundFX - Impacts, Hits & Whooshes",
        "SmartSoundFX – Medieval", "344 Audio - Trailer Instruments Designed", "David Dumais Audio - Weapon Sounds - Weapon Swings",
        "Blond Panda - Decaying Factory",
    ],
    "2023": [
        "InspectorJ - Essentials 04 Chains", "344 Audio - Flesh, Bones & Gore", "David Dumais Audio - Melee Weapons Sound Effects Pack 1",
    ],
    "2019": [
        "Rock The Speakerbox - Melee", "Sound Spark LLC – Magic Spells, Buffs and Attacks", "Sound Spark LLC – Metal Hits, Scrapes and Squeaks",
        "Articulated Sounds - Magic Elements vol.1", "Airborne Sound - Electric-Magnetic", "Airborne Sound - Elements Glass",
        "Airborne Sound - Elements Metal", "Airborne Sound - Airy Whooshes", "Airborne Sound - Eclectic Whooshes 2",
        "Airborne Sound - Organic Whooshes", "Federico Soler Fernández - Effective Trailer Hits & Impacts",
        "Federico Soler Fernández - Effective Trailer Booms", "Federico Soler Fernández - Effective Trailer Whooshes",
        "3maze - FINAL IMPACT", "3maze - IMPACTUS", "BlueZone - Heavy Metal Impact Sound Effects", "Soundholder - Swipes And Whooshes",
        "Invisible - Storm, gale and thunderstorm", "Sound Spark LLC – GLITCH FACTORY 1- BOOM, CRACKLE AND SCREAM", "PMSFX - Cinenergy",
        "Articulated Sounds - Ghosts Return", "Sound Spark LLC – Gore", "Red Libraries - Bodyfall", "Baxter Audio - IMPACT",
        "344 Audio - Low Frequency Elements",
    ],
}


def item(year):
    return f"sonniss-gdc-{year}-game-audio-bundle-normalized"


def main(years):
    os.makedirs(CACHE, exist_ok=True)
    index = {}
    total = 0
    for year in years:
        meta = json.load(urllib.request.urlopen(f"https://archive.org/metadata/{item(year)}", timeout=120))
        files = meta.get("files", [])
        for pack in PACKS[year]:
            names = [f for f in files if f["name"].startswith(pack + "/") and f["name"].lower().endswith((".flac", ".wav"))]
            # 同じ音の flac と wav があれば flac（小さい）
            stems = {}
            for f in names:
                stem = f["name"].rsplit(".", 1)[0]
                if stem not in stems or f["name"].lower().endswith(".flac"):
                    stems[stem] = f
            for stem, f in sorted(stems.items()):
                dst = os.path.join(CACHE, year, f["name"])
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                if not os.path.exists(dst):
                    url = f"https://archive.org/download/{item(year)}/" + urllib.parse.quote(f["name"])
                    urllib.request.urlretrieve(url, dst)
                total += os.path.getsize(dst)
                index.setdefault(year, {}).setdefault(pack, []).append(f["name"])
            print(f"{year} {pack}: {len(stems)} files")
    json.dump(index, open(os.path.join(CACHE, "index.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"total {total / 1e6:.0f} MB")


if __name__ == "__main__":
    main(sys.argv[1:] or ["2026", "2024", "2023", "2020", "2019"])
