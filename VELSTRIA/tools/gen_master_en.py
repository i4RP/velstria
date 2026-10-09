#!/usr/bin/env python3
"""マスターデータの英語オーバーレイ（App/Resources/master_en.json）を生成・検証する。

usage（リポジトリの VELSTRIA/ で）:
    python3 tools/gen_master_en.py           # 生成してから検証
    python3 tools/gen_master_en.py --check   # 検証のみ（ファイルが最新か・全 ID を網羅しているか）

入力: Packages/VelstriaCore/Sources/VelstriaCore/Resources/master_runtime.json
出力: App/Resources/master_en.json（フラットな {id: 英語テキスト}）

キー（アプリ側は App/Core/Localization.swift の MasterText が参照する）:
    <hero_id>                      "Alden, Gate Warden"
    <hero_id>.epithet              "Gate Warden"
    <hero_id>.lore / .strengths / .weaknesses / .counterplay
    <skill_id> / <skill_id>.desc   スキル名と説明（パッシブ含む）
    <item_id> / <item_id>.desc / <item_id>.passive
    <spell_id> / <spell_id>.desc
    <rune_id> / <rune_id>.desc
    <cosmetic_id>                  コスメ名
    <sku>                          ストア商品名
    <effect_id>                    演出名 "Alden - Unbreakable Oath"（デバッグ・クレジット表示用）

翻訳は日本語名をキーにした表で行う。マスターの文言が変わって表に無い日本語が現れた場合は
生成を失敗させる（未翻訳のまま出荷しないため）。説明文の数値は docs/DESIGN.md §6〜§8 と一致させる。
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
from decimal import ROUND_HALF_UP, Decimal

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "Packages" / "VelstriaCore" / "Sources" / "VelstriaCore" / "Resources" / "master_runtime.json"
DST = ROOT / "App" / "Resources" / "master_en.json"

# 表示名の最大長（カード・リストで 2 行に収まる目安）
MAX_NAME_LEN = 40
MAX_DESC_LEN = 400

# ---------------------------------------------------------------------------
# ヒーロー: 日本語表示名 → (英語名, 二つ名, コスメのテーマ語)
# 二つ名は日本語の「〜の」部分を訳したもの。テーマ語はヒーロー専用でないコスメ（帰還演出など）の命名に使う。
# ---------------------------------------------------------------------------
HEROES: dict[str, tuple[str, str, str]] = {
    "城門の誓衛アルデン": ("Alden", "Gate Warden", "Gatewarden"),
    "星弦のリラ": ("Lyra", "Starstring", "Starstring"),
    "月弓のフィリエル": ("Firiel", "Moonbow", "Moonbow"),
    "潮祈のミレア": ("Mirea", "Tidecaller", "Tidecaller"),
    "黒雷のヴォス": ("Voss", "Blackthunder", "Blackthunder"),
    "月灯のセレン": ("Seren", "Moonlantern", "Moonlantern"),
    "岩脈のガルク": ("Garruk", "Stonevein", "Stonevein"),
    "風標のニア": ("Nia", "Windvane", "Windvane"),
    "機巧士オリン": ("Orin", "the Artificer", "Clockwork"),
    "焔冠のテッサ": ("Thessa", "Flamecrown", "Flamecrown"),
    "鉄翼のルーク": ("Rook", "Ironwing", "Ironwing"),
    "玻璃歌のエリネ": ("Elyne", "Crystalsong", "Crystalsong"),
    "獣刻のダガン": ("Dagan", "Beastbrand", "Beastbrand"),
    "霧歩のシオ": ("Sio", "Mistwalker", "Mistwalker"),
    "戦鐘のヴァルカ": ("Valka", "Warbell", "Warbell"),
    "白環のイリス": ("Iris", "White Halo", "White Halo"),
    "深淵鎖のモルド": ("Mord", "Abysschain", "Abysschain"),
    "花星のセリア": ("Celia", "Blossomstar", "Blossomstar"),
    "砦砕のブラム": ("Bram", "Fortbreaker", "Fortbreaker"),
    "光矢のユナ": ("Yuna", "Lightarrow", "Lightarrow"),
    "時砂のキロス": ("Kiros", "Timesand", "Timesand"),
    "蒼爪のレア": ("Rhea", "Azureclaw", "Azureclaw"),
    "雷槍のトレン": ("Toren", "Thunderspear", "Thunderspear"),
    "夢織のノア": ("Noa", "Dreamweaver", "Dreamweaver"),
    "月弦のルミナ": ("Lumina", "Moonstring", "Moonstring"),
    "紫電のエウリア": ("Euria", "Violetbolt", "Violetbolt"),
    "竜槍のジャルド": ("Jarld", "Dragonspear", "Dragonspear"),
    "断空のザイル": ("Zail", "Skycleaver", "Skycleaver"),
    "聖槌のボルグ": ("Borg", "Holyhammer", "Holyhammer"),
    "星砲のライナ": ("Raina", "Starcannon", "Starcannon"),
    "氷嵐のオーリア": ("Oria", "Icestorm", "Icestorm"),
    "赤拳のディアス": ("Dias", "Redfist", "Redfist"),
    "紅牙のヴァルド": ("Vald", "Crimsonfang", "Crimsonfang"),
    "鎖鉤のゴルム": ("Gorm", "Chainhook", "Chainhook"),
}

LORE_PATTERN = re.compile(r"^星環崩壊後のベルシアで、(?P<name>.+)は失われた星核の断片を巡る戦いに身を投じる。$")
LORE_EN = "In a Velsia left shattered by the fall of the Star Ring, {full}, joins the battle for the lost shards of the Star Core."

STRENGTHS = {
    "集団戦の起点と役割遂行に優れる": "Excels at starting teamfights and fulfilling a team role",
    "局所的な火力と位置取りに優れる": "Excels at concentrated burst damage and positioning",
}
WEAKNESSES = {
    "継続的な遠距離圧力に弱い": "Vulnerable to sustained long-range pressure",
    "接近されると選択肢が減る": "Has fewer options once enemies close the distance",
}
COUNTERPLAY = {
    "主要スキルの再使用待ちを見て距離を詰める。視界外からの奇襲を避ける。":
        "Close the distance while key skills are on cooldown. Avoid ambushes from outside your vision.",
}

# ---------------------------------------------------------------------------
# スキル
# ---------------------------------------------------------------------------
# パッシブ・アルティメットの固有名（日本語名 → 英語名）
SKILL_NAMES = {
    "不落の誓い": "Unbreakable Oath",
    "第七門・閉鎖令": "Seventh Gate: Sealing Decree",
    "星屑の調律": "Stardust Attunement",
    "天穹星弦": "Celestial Starstring",
    "月影の刻印": "Moonshadow Brand",
    "月光断界": "Moonlight Worldsplitter",
    "潮騒の加護": "Blessing of the Surf",
    "大潮祈祷": "Spring Tide Invocation",
    "雷脈充填": "Thunder Vein Charge",
    "黒雷天墜": "Black Thunderfall",
    "月影の灯": "Moonshadow Lantern",
    "満月灯界": "Full Moon Lightfield",
    "岩心": "Stoneheart",
    "地脈隆起": "Leyline Upheaval",
    "追い風": "Tailwind",
    "風界標定": "Windrealm Beacon",
    "過給機構": "Supercharger",
    "零式過給": "Type-Zero Overdrive",
    "燃焼冠": "Burning Crown",
    "焔冠戴天": "Crown of Heaven's Flame",
    "翼装展開": "Wingframe Deploy",
    "鉄翼急襲": "Ironwing Raid",
    "共鳴硝子": "Resonant Glass",
    "玻璃大合唱": "Crystal Grand Chorus",
    "獣性解放": "Feral Release",
    "獣王刻印": "Beast King's Brand",
    "薄霧": "Veil of Mist",
    "霧界歩法": "Mistrealm Stride",
    "戦意共鳴": "Battle Resonance",
    "終戦の鐘": "Bell of War's End",
    "白環結界": "White Halo Ward",
    "白環再生": "White Halo Renewal",
    "深鎖": "Deep Chains",
    "深淵拘束": "Abyssal Binding",
    "花星循環": "Blossomstar Cycle",
    "花星満開": "Blossomstar Full Bloom",
    "破城衝動": "Siegebreaker's Urge",
    "城壁崩し": "Rampart Breaker",
    "光標": "Lightmark",
    "光矢流星": "Lightarrow Meteor",
    "時砂残響": "Timesand Echo",
    "時砂逆転": "Timesand Reversal",
    "蒼爪連舞": "Azureclaw Dance",
    "蒼爪月輪": "Azureclaw Moonwheel",
    "帯電槍": "Charged Spear",
    "雷槍天穿": "Thunderspear: Skypiercer",
    "夢糸": "Dreamthread",
    "夢界縫合": "Dreamrealm Suture",
    "月環の導き": "Moonring Guidance",
    "隠れ月光": "Hidden Moonlight",
    "超伝導": "Superconductor",
    "九天雷鳴": "Nine Heavens Thunder",
    "竜の三連突き": "Dragon Flurry",
    "至高の武人": "Supreme Warrior",
    "空断の理": "Principle of the Severed Sky",
    "三連断空": "Triple Skycleave",
    "聖鎚の誓い": "Oath of the Holy Hammer",
    "崩落聖域": "Collapsing Sanctuary",
    "遠星の照準": "Distant Star Aim",
    "星砕の大砲": "Starshatter Cannon",
    "氷の誇り": "Pride of Ice",
    "絶界凍獄": "Realmfreeze Prison",
    "紅血の拳": "Crimson Fist",
    "奈落の一撃": "Abysm Strike",
    "吸血の渇き": "Crimson Thirst",
    "核分裂波": "Fission Wave",
    "鉄鎖の執念": "Ironchain Tenacity",
    "狩猟鎖獄": "Hunting Chain Gaol",
    "月弦分矢": "Moonstring Split Shot",
    "月蝕の矢": "Eclipse Arrow",
    "分岐雷": "Forked Bolt",
    "雷球": "Thunder Orb",
    "跳槍撃": "Spear Flip",
    "竜牙突き": "Dragonfang Thrust",
    "環剣": "Ring of Blades",
    "断空突進": "Skycleave Charge",
    "聖槌波": "Holy Hammer Wave",
    "聖槌突撃": "Hammer Charge",
    "遠星弾": "Farstar Shot",
    "星爆弾": "Starburst Shell",
    "雹撃": "Hailstrike",
    "霜風": "Frostwind",
    "赤拳連斬": "Redfist Flurry",
    "紅蓮の踏込": "Crimson Lunge",
    "裂地撃": "Earthrend",
    "旋回斬": "Whirling Slash",
    "鎖鉤": "Chain Hook",
    "鉄鎖旋": "Iron Chain Sweep",
}
# 共通アーキタイプ名（末尾の番号はヒーロー番号なので英語では付けない）
SKILL1_PATTERN = re.compile(r"^(?P<code>[A-Za-z]+)式・一閃$")
SKILL2_PATTERN = re.compile(r"^星環シフト\d+$")
SKILL3_PATTERN = re.compile(r"^境界制圧\d+$")
SKILL1_EN = "{code} Style: Flashstrike"
SKILL2_EN = "Star Ring Shift"
SKILL3_EN = "Boundary Lockdown"

DAMAGE_TYPE_EN = {"Physical": "physical", "Magic": "magic", "True": "true"}
# 複数の敵が主語の CC 句 / 単体が主語の CC 句
CC_PLURAL = {"None": "", "Slow": " and are slowed", "Root": " and are rooted", "Stun": " and are stunned",
             "Knockback": " and are knocked back"}
CC_SINGLE = {"None": "", "Slow": " and slows the target", "Root": " and roots the target",
             "Stun": " and stuns the target", "Knockback": " and knocks the target back"}
CC_NEARBY = {"None": "", "Slow": " Nearby enemies are slowed.", "Root": " Nearby enemies are rooted.",
             "Stun": " Nearby enemies are stunned.", "Knockback": " Nearby enemies are knocked back."}

RANGED_THRESHOLD = 300  # MasterData.HeroDef.isRanged と同じ


def num(x: float, places: int = 2) -> str:
    """小数を四捨五入して末尾の 0 を落とす（15.30 → 15.3、1.750 → 1.75）。"""
    q = Decimal(str(x)).quantize(Decimal(1).scaleb(-places), rounding=ROUND_HALF_UP)
    s = format(q, "f")
    return s.rstrip("0").rstrip(".") if "." in s else s


def passive_desc(role: str, name: str, hero_number: int) -> str:
    """DESIGN §6 のロール別パッシブ（ヒーロー固有係数 k = 1.0 + 0.02×(番号 mod 5)）。"""
    k = 1.0 + 0.02 * (hero_number % 5)
    if role == "Vanguard":
        return (f"When HP falls below 40%, {name} gains a shield equal to {num(15 * k)}% of max HP "
                f"(20s cooldown).")
    if role == "Duelist":
        return (f"Each basic attack hit grants +{num(6 * k)}% attack speed for 3 seconds, "
                f"stacking up to 5 times.")
    if role == "Ranger":
        return f"Every 4th basic attack is a guaranteed critical strike that deals {num(1.75 * k)}× damage."
    if role == "Arcanist":
        return (f"Hitting an enemy with a skill reduces {name}'s other skill cooldowns by {num(0.6 * k)}s "
                f"(once per cast).")
    if role == "Support":
        return (f"Casting a skill heals the ally with the lowest HP% within 800 units "
                f"for 40 + {num(10 * k)} × level HP.")
    if role == "Assassin":
        return (f"The first damage dealt within 3 seconds of leaving brush or stealth is increased by "
                f"{num(30 * k)}%. Takedowns reduce all of {name}'s cooldowns by 30%.")
    raise ValueError(f"unknown role {role}")


def active_desc(skill: dict, hero: dict, name: str) -> str:
    """DESIGN §6 のアーキタイプ（スロット × 近接/遠隔 × ロール）に沿った説明。"""
    slot = skill["slot"]
    role = hero["role"]
    ranged = hero["attack_range"] >= RANGED_THRESHOLD
    dmg = int(skill["base_damage"])
    dtype = DAMAGE_TYPE_EN[skill["damage_type"]]
    cc = skill["cc"]
    if cc not in CC_PLURAL:
        raise ValueError(f"{skill['skill_id']}: unknown cc {cc}")
    plural, single, nearby = CC_PLURAL[cc], CC_SINGLE[cc], CC_NEARBY[cc]
    rng = int(skill["range"])

    if slot == "Skill1":
        if ranged:
            return (f"Fires a skillshot in the target direction. The first enemy hit takes "
                    f"{dmg} base {dtype} damage{plural.replace('are', 'is')}.")
        return f"Slashes in a 90° cone ahead. Enemies hit take {dmg} base {dtype} damage{plural}."
    if slot == "Skill2":
        if ranged:
            # DESIGN §6: 短距離ブリンク(350) + 次の通常攻撃にスキル基礎値の +50%
            return (f"Blinks 350 units in the target direction. The next basic attack deals bonus {dtype} "
                    f"damage equal to 50% of {dmg} base damage{single}.")
        return (f"Dashes {rng + 100} units in the target direction. Enemies near the landing point take "
                f"{dmg} base {dtype} damage{plural}.")
    if slot == "Skill3":
        if role == "Vanguard":
            return (f"Releases a shockwave around {name}. Nearby enemies take {dmg} base {dtype} damage{plural}, "
                    f"and {name} gains a shield equal to 8% of max HP.")
        if role == "Support":
            return (f"Creates a restorative field at the target location. Allies inside recover "
                    f"{round(dmg * 0.8)} HP, while enemies take {dmg} base {dtype} damage{plural}.")
        return (f"After a 0.5s warning, erupts at the target location. Enemies in the area take "
                f"{dmg} base {dtype} damage{plural}.")
    if slot == "Ultimate":
        if role == "Vanguard":
            return (f"Leaps up to {rng + 200} units to the target location. On landing, enemies in a wide area "
                    f"take {dmg} base {dtype} damage{plural}.")
        if role == "Duelist":
            return (f"Strikes every enemy hero in range 3 times, each hit dealing 45% of {dmg} base {dtype} "
                    f"damage.{nearby.replace('Nearby enemies', 'Targets')} {name} takes 25% less damage "
                    f"for 2 seconds.")
        if role == "Ranger":
            return (f"Fires a massive piercing arrow 2,000 units long. All enemies in its path take "
                    f"{dmg} base {dtype} damage{plural}.")
        if role == "Arcanist":
            return (f"After a 1s warning, devastates a large area at the target location. Enemies inside take "
                    f"{dmg} base {dtype} damage{plural}.")
        if role == "Support":
            return (f"Heals all allies within 1,500 units for {round(dmg * 1.2)} HP and grants them a shield."
                    f"{nearby}")
        if role == "Assassin":
            return (f"Blinks to the nearest enemy hero within {rng} units and strikes for {dmg} base {dtype} "
                    f"damage plus 12% of the target's missing HP.{nearby.replace('Nearby enemies are', 'The target is')}")
    raise ValueError(f"{skill['skill_id']}: unsupported slot/role {slot}/{role}")


# ---------------------------------------------------------------------------
# 装備
# ---------------------------------------------------------------------------
# 装備の英語名・一覧の短い説明・固有効果の英語文は tools/equipment_spec.mjs（Mobile Legends の装備の英語名）を正本とする
# （node tools/equipment_apply.mjs が tools/equipment_spec.json を書き出す）。
ITEM_PASSIVES = ROOT / "tools" / "equipment_spec.json"


def load_item_passives() -> dict[str, dict]:
    """装備 ID → {name_en, tag_en, passive_name_en, passive_text_en}。"""
    spec = json.loads(ITEM_PASSIVES.read_text(encoding="utf-8"))
    return {it["id"]: it for it in spec["items"]}


# ---------------------------------------------------------------------------
# バトルスペル（名前は日本語名キー、説明は DESIGN §7 を ID キーで）
# ---------------------------------------------------------------------------
SPELL_NAMES = {
    "瞬歩": "Blink",
    "浄化": "Cleanse",
    "治癒波": "Healing Wave",
    "鉄壁": "Bulwark",
    "狩猟印": "Hunter's Mark",
    "加速陣": "Haste Sigil",
    "点火": "Ignite",
    "虚像": "Phantom",
    "帰還門": "Return Gate",
    "星鎖": "Starbind",
    "処断": "Verdict",
    "鼓舞": "Inspire",
    "石化": "Petrify",
    "火炎弾": "Flare Shot",
    "報復": "Reprisal",
}
SPELL_DESCS = {
    "BS01": "Instantly teleports 400 units in the target direction, stopping short of walls.",
    "BS02": "Removes all crowd control effects and grants crowd control immunity for 1.5 seconds.",
    "BS03": ("Restores 15% HP to yourself and the ally with the lowest HP% within 800 units, "
             "and grants both +20% move speed for 2 seconds."),
    "BS04": "Grants a shield equal to 20% of max HP for 3 seconds.",
    "BS05": ("Deals 600 + 40 × level true damage to an enemy minion or monster within 500 units. "
             "Required to buy Jungle items."),
    "BS06": "Grants +40% move speed for 5 seconds.",
    "BS07": ("Burns an enemy hero within 600 units for 70 + 20 × level true damage over 5 seconds "
             "and reduces their healing by 50%."),
    "BS08": "Become stealthed for 1.5 seconds and gain +25% move speed.",
    "BS09": ("After a 3-second channel, teleports to a chosen allied tower or your fountain. "
             "Taking damage interrupts the channel."),
    "BS10": "Slows an enemy hero within 650 units by 40% and reduces their damage dealt by 30% for 2.5 seconds.",
    "BS11": ("Deals 150 + 30 × level true damage plus 25% of the target's missing HP "
             "to an enemy hero within 600 units."),
    "BS12": "Grants +50% attack speed for 5 seconds.",
    "BS13": "Stuns enemy heroes within 450 units for 0.8 seconds, then slows them by 30% for 1.5 seconds.",
    "BS14": ("Fires a flame bolt up to 700 units in a direction. The first enemy hero hit takes "
             "100 + 20 × level magic damage and is knocked back."),
    "BS15": ("For 5 seconds, takes 30% less damage and reflects 35% of damage taken "
             "to the attacker as true damage."),
}

# ---------------------------------------------------------------------------
# ルーン
# ---------------------------------------------------------------------------
RUNE_PATHS = {"勇気": "Valor", "秘術": "Arcana", "堅守": "Resolve", "狡知": "Cunning", "調和": "Harmony"}
RUNE_PATTERN = re.compile(r"^(?P<path>.+)の星紋(?P<no>\d{2})$")
RUNE_EFFECT = re.compile(r"^条件達成時に主要能力を(?P<x>\d+)%補助する。$")


def rune_desc(path: str, x: int) -> str:
    """DESIGN §8 のルーン効果（X = effect の %）。"""
    return {
        "Valor": f"+{x}% attack.",
        "Arcana": f"+{x}% ability power and +{num(x / 2)}% skill damage.",
        "Resolve": f"+{x}% max HP and +{x}% armor and magic resist.",
        "Cunning": f"+{num(x / 2)}% move speed and +{num(x / 2)}% cooldown reduction.",
        "Harmony": f"+{3 * x}% HP and mana regeneration, and +{x}% healing.",
    }[path]


# ---------------------------------------------------------------------------
# コスメ・ストア
# ---------------------------------------------------------------------------
COSMETIC_PATTERN = re.compile(r"^(?P<hero>.+) (?P<type>[A-Za-z]+) (?P<no>\d+)$")
# ヒーロー専用スキン（hero_id, 番号）→ スキン名
HERO_SKINS = {
    ("H001", 1): "Starforged Alden",
    ("H001", 2): "Eclipse Sentinel Alden",
    ("H001", 3): "Aurora Bastion Alden",
    ("H007", 1): "Obsidian Titan Garruk",
    ("H007", 2): "Magma Vein Garruk",
    ("H007", 3): "Crystal Colossus Garruk",
    ("H013", 1): "Frostfang Dagan",
    ("H013", 2): "Emberhide Dagan",
    ("H013", 3): "Celestial Beast Dagan",
    ("H019", 1): "Iron Siege Bram",
    ("H019", 2): "Thunder Ram Bram",
    ("H019", 3): "Starfall Breaker Bram",
}
# 汎用コスメ（全ヒーロー共通）はヒーローの二つ名を「テーマ」として命名する
COSMETIC_TYPES = {
    "Recall": "Recall",
    "Spawn": "Arrival",
    "Emote": "Emote",
    "AvatarFrame": "Frame",
    "KillEffect": "Takedown",
}
ROMAN = {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V", 6: "VI", 7: "VII", 8: "VIII", 9: "IX", 10: "X"}

HERO_UNLOCK_PATTERN = re.compile(r"^(?P<hero>.+) 解放$")
BUNDLE_PATTERN = re.compile(r"^星環バンドル(?P<no>\d{2})$")

EFFECT_PATTERN = re.compile(r"^(?P<hero>.+) - (?P<skill>.+)$")
COMMON_EFFECT_PATTERN = re.compile(r"^共通演出(?P<no>\d+)$")

JAPANESE = re.compile(r"[぀-ヿ㐀-鿿＀-￯]")


class TranslationError(Exception):
    pass


def need(table: dict, key, where: str):
    if key not in table:
        raise TranslationError(f"{where}: 翻訳表にありません: {key!r}")
    return table[key]


def build(master: dict) -> dict[str, str]:
    out: dict[str, str] = {}

    def put(key: str, value: str) -> None:
        if key in out:
            raise TranslationError(f"キーが重複しています: {key}")
        out[key] = value

    # ヒーロー
    hero_by_id = {}
    hero_full_by_ja = {}
    for h in master["heroes"]:
        hid = h["hero_id"]
        name, epithet, _ = need(HEROES, h["display_name_ja"], hid)
        if name != h["code_name"]:
            raise TranslationError(f"{hid}: 英語名 {name} が code_name {h['code_name']} と一致しません")
        full = f"{name}, {epithet}"
        hero_by_id[hid] = h
        hero_full_by_ja[h["display_name_ja"]] = full
        put(hid, full)
        put(f"{hid}.epithet", epithet[0].upper() + epithet[1:])
        m = LORE_PATTERN.match(h["lore"])
        if not m or m["name"] != h["display_name_ja"]:
            raise TranslationError(f"{hid}: lore の文型が想定外です: {h['lore']}")
        put(f"{hid}.lore", LORE_EN.format(full=full))
        put(f"{hid}.strengths", need(STRENGTHS, h["strengths"], f"{hid}.strengths"))
        put(f"{hid}.weaknesses", need(WEAKNESSES, h["weaknesses"], f"{hid}.weaknesses"))
        put(f"{hid}.counterplay", need(COUNTERPLAY, h["counterplay"], f"{hid}.counterplay"))

    # スキル
    skill_name_by_id = {}
    for s in master["skills"]:
        sid = s["skill_id"]
        hero = hero_by_id[s["hero_id"]]
        name_ja = s["name_ja"]
        if (m := SKILL1_PATTERN.match(name_ja)):
            if m["code"] != hero["code_name"]:
                raise TranslationError(f"{sid}: {name_ja} のヒーロー名が {hero['code_name']} と一致しません")
            name = SKILL1_EN.format(code=m["code"])
        elif SKILL2_PATTERN.match(name_ja):
            name = SKILL2_EN
        elif SKILL3_PATTERN.match(name_ja):
            name = SKILL3_EN
        else:
            name = need(SKILL_NAMES, name_ja, sid)
        skill_name_by_id[sid] = name
        put(sid, name)
        hero_number = int(hero["hero_id"][1:])
        if s["slot"] == "Passive":
            desc = passive_desc(hero["role"], hero["code_name"], hero_number)
        else:
            desc = active_desc(s, hero, hero["code_name"])
        put(f"{sid}.desc", desc)

    # 装備（固有効果・一覧の説明が無い装備はキーを作らない）
    item_passives = load_item_passives()
    for it in master["equipment"]:
        iid = it["item_id"]
        sp = need(item_passives, iid, iid)
        put(iid, sp["name_en"])
        if it["passive_name"]:
            put(f"{iid}.desc", sp["passive_text_en"])
            put(f"{iid}.passive", sp["passive_name_en"])
        if it.get("tag_ja"):
            put(f"{iid}.tag", sp["tag_en"])

    # バトルスペル
    for sp in master["battle_spells"]:
        sid = sp["spell_id"]
        put(sid, need(SPELL_NAMES, sp["name_ja"], sid))
        put(f"{sid}.desc", need(SPELL_DESCS, sid, sid))

    # ルーン
    for r in master["runes"]:
        rid = r["rune_id"]
        m = RUNE_PATTERN.match(r["name_ja"])
        if not m:
            raise TranslationError(f"{rid}: ルーン名の文型が想定外です: {r['name_ja']}")
        path = need(RUNE_PATHS, m["path"], rid)
        if path != r["path"]:
            raise TranslationError(f"{rid}: 名前のパス {path} が path {r['path']} と一致しません")
        put(rid, f"{path} Starglyph {m['no']}")
        em = RUNE_EFFECT.match(r["effect"])
        if not em:
            raise TranslationError(f"{rid}: effect の文型が想定外です: {r['effect']}")
        put(f"{rid}.desc", rune_desc(path, int(em["x"])))

    # コスメ
    cosmetic_name_by_id = {}
    cosmetic_ja_by_id = {}
    for c in master["cosmetics"]:
        cid = c["cosmetic_id"]
        m = COSMETIC_PATTERN.match(c["name_ja"])
        if not m or m["type"] != c["type"]:
            raise TranslationError(f"{cid}: コスメ名の文型が想定外です: {c['name_ja']}")
        no = int(m["no"])
        if c["type"] == "HeroSkin":
            name = need(HERO_SKINS, (c["hero_id"], no), cid)
        else:
            _, _, theme = need(HEROES, m["hero"], cid)
            name = f"{theme} {need(COSMETIC_TYPES, c['type'], cid)} {ROMAN[no]}"
        cosmetic_name_by_id[cid] = name
        cosmetic_ja_by_id[cid] = c["name_ja"]
        put(cid, name)

    # ストア商品
    for st in master["store"]:
        sku = st["sku"]
        kind = st["type"]
        if kind == "Cosmetic":
            gid = st["grant_id"]
            if cosmetic_ja_by_id.get(gid) != st["name_ja"]:
                raise TranslationError(f"{sku}: 商品名 {st['name_ja']} が付与コスメ {gid} の名前と一致しません")
            name = cosmetic_name_by_id[gid]
        elif kind == "HeroUnlock":
            m = HERO_UNLOCK_PATTERN.match(st["name_ja"])
            if not m or m["hero"] not in hero_full_by_ja:
                raise TranslationError(f"{sku}: ヒーロー解放の商品名が想定外です: {st['name_ja']}")
            name = f"Unlock {hero_full_by_ja[m['hero']]}"
        elif kind == "Bundle":
            m = BUNDLE_PATTERN.match(st["name_ja"])
            if not m:
                raise TranslationError(f"{sku}: バンドル名が想定外です: {st['name_ja']}")
            name = f"Star Ring Bundle {m['no']}"
        else:
            raise TranslationError(f"{sku}: 未対応の商品種別 {kind}")
        put(sku, name)

    # 演出
    for fx in master["effects"]:
        eid = fx["effect_id"]
        if (m := COMMON_EFFECT_PATTERN.match(fx["name_ja"])):
            put(eid, f"Common Effect {m['no']}")
            continue
        m = EFFECT_PATTERN.match(fx["name_ja"])
        if not m or m["hero"] not in hero_full_by_ja:
            raise TranslationError(f"{eid}: 演出名の文型が想定外です: {fx['name_ja']}")
        skill_id = "SK" + eid[len("FX_SK_"):]
        if skill_id not in skill_name_by_id:
            raise TranslationError(f"{eid}: 対応するスキル {skill_id} がありません")
        # 演出名は短く（ヒーロー名のみ + スキル名）
        hero_name = HEROES[m["hero"]][0]
        put(eid, f"{hero_name} - {skill_name_by_id[skill_id]}")

    return dict(sorted(out.items()))


# ---------------------------------------------------------------------------
# 検証
# ---------------------------------------------------------------------------
TABLES = [
    # (テーブル, ID 列, 必須サフィックス, 名前の重複を禁止するか)
    ("heroes", "hero_id", ["", ".epithet", ".lore", ".strengths", ".weaknesses", ".counterplay"], True),
    ("skills", "skill_id", ["", ".desc"], False),
    ("equipment", "item_id", ["", ".desc", ".passive", ".tag"], True),
    ("battle_spells", "spell_id", ["", ".desc"], True),
    ("runes", "rune_id", ["", ".desc"], True),
    ("cosmetics", "cosmetic_id", [""], True),
    ("store", "sku", [""], True),
    ("effects", "effect_id", [""], False),
]


def validate(master: dict, overlay: dict[str, str]) -> list[str]:
    errors: list[str] = []
    expected: set[str] = set()
    counts = {}
    for table, col, suffixes, unique in TABLES:
        rows = master[table]
        counts[table] = len(rows)
        seen_names: dict[str, str] = {}
        for row in rows:
            rid = row[col]
            for suf in suffixes:
                # 装備: 固有効果・一覧の説明が無い装備（素材など）は .desc / .passive / .tag を持たない
                if table == "equipment" and ((suf in (".desc", ".passive") and not row["passive_name"])
                                             or (suf == ".tag" and not row.get("tag_ja"))):
                    continue
                key = rid + suf
                expected.add(key)
                if key not in overlay:
                    errors.append(f"未翻訳: {key}")
            name = overlay.get(rid)
            if unique and name is not None:
                if name in seen_names:
                    errors.append(f"英語名が重複: {rid} と {seen_names[name]} → {name!r}")
                seen_names[name] = rid
            if name is not None and len(name) > MAX_NAME_LEN:
                errors.append(f"名前が長すぎます（{len(name)} > {MAX_NAME_LEN}）: {rid} → {name!r}")
    for key, value in overlay.items():
        if key not in expected:
            errors.append(f"マスターに存在しないキー: {key}")
        if not isinstance(value, str) or not value.strip():
            errors.append(f"空の値: {key}")
            continue
        if value != value.strip() or "  " in value:
            errors.append(f"余分な空白: {key} → {value!r}")
        if JAPANESE.search(value):
            errors.append(f"日本語が残っています: {key} → {value!r}")
        if key.endswith(".desc") and len(value) > MAX_DESC_LEN:
            errors.append(f"説明が長すぎます: {key}（{len(value)} 文字）")
    # 規模（DESIGN §0 / 仕様パッケージ README と一致すること）
    for table, n in {"heroes": 34, "skills": 136, "equipment": 92, "battle_spells": 15, "runes": 30,
                     "cosmetics": 102, "store": 154}.items():
        if counts.get(table) != n:
            errors.append(f"{table} の件数が想定外です: {counts.get(table)}（想定 {n}）")
    return errors


def render(overlay: dict[str, str]) -> str:
    return json.dumps(overlay, ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    check_only = "--check" in sys.argv[1:]
    master = json.loads(SRC.read_text(encoding="utf-8"))
    try:
        overlay = build(master)
    except TranslationError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    text = render(overlay)

    if check_only:
        if not DST.exists():
            print(f"error: {DST.relative_to(ROOT)} がありません。python3 tools/gen_master_en.py を実行してください",
                  file=sys.stderr)
            return 1
        on_disk = json.loads(DST.read_text(encoding="utf-8"))
        errors = validate(master, on_disk)
        if DST.read_text(encoding="utf-8") != text:
            errors.append(f"{DST.relative_to(ROOT)} が翻訳表・マスターと一致しません（再生成が必要）")
    else:
        DST.write_text(text, encoding="utf-8")
        print(f"wrote {DST.relative_to(ROOT)} ({len(overlay)} keys)")
        errors = validate(master, overlay)

    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        print(f"{len(errors)} 件のエラー", file=sys.stderr)
        return 1
    total_ids = sum(len(master[t]) for t, *_ in TABLES)
    print(f"ok: {total_ids} 件の ID（{', '.join(f'{t} {len(master[t])}' for t, *_ in TABLES)}）を"
          f"すべて網羅（{len(overlay)} キー）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
