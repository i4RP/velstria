#!/usr/bin/env node
// 追加ヒーロー（Mobile Legends 参照）の行を master_runtime.json へ追記する。再実行しても二重追加しない。
//
// usage（リポジトリの VELSTRIA/ で）: node tools/hero_additions.mjs
//
// なぜスクリプトか: tools/gen_runtime_data.py の入力（復元版パッケージの velstria_master.json）は古く、
// 実行時マスター master_runtime.json の方が正本になっている（Skill3 の削除、ベルシア表記など）。
// そのためこのファイルを直接更新する。既存行の表記（2.0 など）を崩さないよう、配列の末尾へ文字列で差し込む。
//
// 追記後は日英の表示名オーバーレイを再生成すること:
//   python3 tools/gen_master_ja.py && python3 tools/gen_master_en.py
// （HEROES / SKILL_NAMES 表も同時に更新が要る。docs/NEW_HEROES.md 参照）
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DST = path.join(ROOT, "Packages/VelstriaCore/Sources/VelstriaCore/Resources/master_runtime.json");

// ロール別の既定文言（既存ヒーローと同じ文型。英語オーバーレイの翻訳表に載っているものだけを使う）
const TEXT = {
  melee: {
    strengths: "局所的な火力と位置取りに優れる",
    weaknesses: "継続的な遠距離圧力に弱い",
  },
  vanguardLike: {
    strengths: "集団戦の起点と役割遂行に優れる",
    weaknesses: "継続的な遠距離圧力に弱い",
  },
  ranged: {
    strengths: "局所的な火力と位置取りに優れる",
    weaknesses: "接近されると選択肢が減る",
  },
};
const COUNTERPLAY = "主要スキルの再使用待ちを見て距離を詰める。視界外からの奇襲を避ける。";
const ROLE_JA = {
  Vanguard: "ヴァンガード", Duelist: "デュエリスト", Ranger: "レンジャー",
  Arcanist: "アルカニスト", Support: "サポート", Assassin: "アサシン",
};
const ROLE_JA_CHECK = ["ヴァンガード", "デュエリスト", "レンジャー", "アルカニスト", "サポート", "アサシン"];

// skill: [slot, name_ja|null(共通名は生成), damage_type, base, scaling_attack, scaling_power, cd, cost, range, radius, cc]
// 共通名: Skill1 は「{code}式・一閃」、Skill2 は「星環シフト{番号}」
const HEROES = [
  {
    // ミヤ（Miya）参照: 月の弓の射手。ゴールドレーン
    id: "H025", code: "Lumina", name: "月弦のルミナ", role: "Ranger", difficulty: 2, text: "ranged",
    hp: [2780, 178], atk: [138, 5.4], def: [22, 3], mdef: [12, 1.8], ms: 262, range: 550, resource: "Mana", resourceMax: 500,
    cosmetic: "Recall",
    skills: [
      ["Passive", "月環の導き", "Physical", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Physical", 112, 0.57, 0.5, 6.5, 50, 650, 155, "None"],
      ["Skill2", null, "Physical", 124, 0.69, 0.5, 8.7, 55, 650, 190, "Slow"],
      ["Ultimate", "月華の天弦", "Physical", 262, 0.81, 0.35, 32.5, 100, 770, 120, "None"],
    ],
  },
  {
    // エウドラ（Eudora）参照: 雷の魔導士。ミドルレーン
    id: "H026", code: "Euria", name: "紫電のエウリア", role: "Arcanist", difficulty: 3, text: "ranged",
    hp: [2700, 172], atk: [124, 5.8], def: [19, 2.7], mdef: [20, 1.6], ms: 255, range: 550, resource: "Mana", resourceMax: 600,
    cosmetic: "Spawn",
    skills: [
      ["Passive", "紫電の囁き", "Magic", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Magic", 138, 0.45, 0.8, 6.5, 62, 650, 155, "None"],
      ["Skill2", null, "Magic", 172, 0.45, 0.8, 10.9, 74, 650, 190, "Stun"],
      ["Ultimate", "九天雷鳴", "Magic", 318, 0.45, 0.8, 34.0, 118, 770, 155, "Stun"],
    ],
  },
  {
    // 趙子龍（Zilong）参照: 竜槍の戦士。EXP レーン
    id: "H027", code: "Jarld", name: "竜槍のジャルド", role: "Duelist", difficulty: 2, text: "melee",
    hp: [2850, 190], atk: [128, 4.9], def: [24, 3.1], mdef: [16, 1.7], ms: 270, range: 150, resource: "Energy", resourceMax: 480,
    cosmetic: "Emote",
    skills: [
      ["Passive", "竜鱗の構え", "Physical", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Physical", 120, 0.81, 0.35, 6.5, 40, 300, 155, "None"],
      ["Skill2", null, "Physical", 144, 0.69, 0.5, 8.7, 50, 300, 190, "Knockback"],
      ["Ultimate", "昇竜天翔", "Physical", 240, 0.69, 0.5, 31.6, 84, 420, 155, "None"],
    ],
  },
  {
    // セイバー（Saber）参照: 剣の暗殺者。ジャングル
    id: "H028", code: "Zail", name: "断空のザイル", role: "Assassin", difficulty: 3, text: "melee",
    hp: [2700, 180], atk: [116, 4], def: [22, 3.3], mdef: [16, 1.4], ms: 268, range: 150, resource: "Energy", resourceMax: 470,
    cosmetic: "AvatarFrame",
    skills: [
      ["Passive", "空断の理", "Physical", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Physical", 135, 0.93, 0.5, 8.7, 45, 300, 155, "None"],
      ["Skill2", null, "Physical", 152, 0.81, 0.65, 9.8, 55, 350, 190, "Knockback"],
      ["Ultimate", "三連断空", "Physical", 282, 0.93, 0.35, 33.0, 92, 600, 120, "Stun"],
    ],
  },
  {
    // ティグリアル（Tigreal）参照: 聖槌の重装騎士。ローム
    id: "H029", code: "Borg", name: "聖槌のボルグ", role: "Support", difficulty: 2, text: "vanguardLike",
    hp: [2800, 185], atk: [124, 6.25], def: [24, 3], mdef: [18, 2], ms: 250, range: 150, resource: "Mana", resourceMax: 480,
    cosmetic: "KillEffect",
    skills: [
      ["Passive", "聖鎚の誓い", "Magic", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Magic", 104, 0.45, 0.5, 8.7, 55, 300, 190, "Slow"],
      ["Skill2", null, "Magic", 146, 0.57, 0.5, 10.9, 62, 300, 190, "Stun"],
      ["Ultimate", "崩落聖域", "Magic", 236, 0.57, 0.5, 34.0, 100, 420, 190, "Stun"],
    ],
  },
  // ---- 第 2 段階 ----
  {
    // ライラ（Layla）参照: 長射程の砲撃手。ゴールドレーン
    id: "H030", code: "Raina", name: "星砲のライナ", role: "Ranger", difficulty: 1, text: "ranged",
    hp: [2650, 165], atk: [142, 5.5], def: [20, 2.8], mdef: [10, 1.6], ms: 255, range: 550, resource: "Mana", resourceMax: 520,
    cosmetic: "Recall",
    skills: [
      ["Passive", "遠星の照準", "Physical", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Physical", 105, 0.57, 0.35, 6.5, 45, 650, 155, "None"],
      ["Skill2", null, "Physical", 118, 0.69, 0.5, 7.6, 50, 650, 190, "Slow"],
      ["Ultimate", "星砕の大砲", "Physical", 290, 0.93, 0.35, 33.0, 100, 770, 120, "None"],
    ],
  },
  {
    // オーロラ（Aurora）参照: 氷の魔導士。ミッドレーン
    id: "H031", code: "Oria", name: "氷嵐のオーリア", role: "Arcanist", difficulty: 3, text: "ranged",
    hp: [2680, 170], atk: [122, 5.8], def: [18, 2.6], mdef: [22, 1.7], ms: 252, range: 550, resource: "Mana", resourceMax: 620,
    cosmetic: "Spawn",
    skills: [
      ["Passive", "霜華の祝福", "Magic", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Magic", 135, 0.45, 0.8, 6.5, 60, 650, 155, "Slow"],
      ["Skill2", null, "Magic", 165, 0.45, 0.8, 9.8, 72, 650, 190, "Root"],
      ["Ultimate", "絶界凍獄", "Magic", 330, 0.45, 0.8, 34.0, 120, 770, 155, "Stun"],
    ],
  },
  {
    // ディロス（Dyrroth）参照: 拳剣の戦士。EXP レーン
    id: "H032", code: "Dias", name: "赤拳のディアス", role: "Duelist", difficulty: 3, text: "melee",
    hp: [2900, 195], atk: [130, 4.9], def: [25, 3.2], mdef: [17, 1.7], ms: 262, range: 150, resource: "Energy", resourceMax: 500,
    cosmetic: "Emote",
    skills: [
      ["Passive", "紅血の拳", "Physical", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Physical", 125, 0.81, 0.35, 6.5, 40, 300, 155, "None"],
      ["Skill2", null, "Physical", 150, 0.69, 0.5, 8.7, 50, 300, 190, "Stun"],
      ["Ultimate", "煉獄連拳", "Physical", 250, 0.81, 0.35, 31.6, 85, 420, 155, "Slow"],
    ],
  },
  {
    // アルカード（Alucard）参照: 吸血の大剣士。ジャングル
    id: "H033", code: "Vald", name: "紅牙のヴァルド", role: "Assassin", difficulty: 2, text: "melee",
    hp: [2780, 186], atk: [120, 4.2], def: [24, 3.3], mdef: [15, 1.4], ms: 265, range: 150, resource: "Energy", resourceMax: 480,
    cosmetic: "AvatarFrame",
    skills: [
      ["Passive", "吸血の渇き", "Physical", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Physical", 130, 0.93, 0.5, 8.7, 45, 300, 155, "Slow"],
      ["Skill2", null, "Physical", 155, 0.81, 0.65, 9.8, 55, 350, 190, "None"],
      ["Ultimate", "血月断裂", "Physical", 275, 0.93, 0.35, 33.0, 90, 600, 120, "Slow"],
    ],
  },
  {
    // フランコ（Franco）参照: 鎖鉤の大男。ローム
    id: "H034", code: "Gorm", name: "鎖鉤のゴルム", role: "Support", difficulty: 3, text: "vanguardLike",
    hp: [2650, 190], atk: [124, 6.25], def: [21, 3], mdef: [16, 2], ms: 248, range: 150, resource: "Mana", resourceMax: 460,
    cosmetic: "KillEffect",
    skills: [
      ["Passive", "鉄鎖の執念", "Physical", 0, 0, 0, 0, 0, 0, 0, "None"],
      ["Skill1", null, "Physical", 112, 0.45, 0.5, 10.9, 55, 300, 190, "Root"],
      ["Skill2", null, "Physical", 142, 0.57, 0.5, 9.8, 60, 300, 190, "Slow"],
      ["Ultimate", "狩猟鎖獄", "Physical", 230, 0.57, 0.5, 34.0, 100, 420, 190, "Stun"],
    ],
  },
];

const EFFECT_TYPES = { Passive: "Burst", Skill1: "Trail", Skill2: "Area", Ultimate: "Projectile" };
const SLOT_NO = { Passive: 1, Skill1: 2, Skill2: 3, Ultimate: 5 };
const RARITY = ["Common", "Rare", "Epic", "Mythic"];
const COSMETIC_PRICE = { Common: 120, Rare: 260, Epic: 520, Mythic: 880 };
const REFUND = "未消費・プラットフォーム規約の範囲で処理";
const DUP = "所有済みの場合は購入不可または同価値通貨へ変換（商品設定で固定）";

/** 文字列中の `"key":[ ... ]` の配列末尾（`]` の位置）を返す。文字列リテラルを読み飛ばす。 */
function arrayEnd(src, key) {
  const start = src.indexOf(`"${key}":[`);
  if (start < 0) throw new Error(`テーブルがありません: ${key}`);
  let i = src.indexOf("[", start);
  let depth = 0;
  let inStr = false;
  for (; i < src.length; i++) {
    const c = src[i];
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') inStr = true;
    else if (c === "[") depth++;
    else if (c === "]" && --depth === 0) return i;
  }
  throw new Error(`配列が閉じていません: ${key}`);
}

function append(src, key, rows) {
  if (rows.length === 0) return src;
  const end = arrayEnd(src, key);
  return src.slice(0, end) + "," + rows.map((r) => JSON.stringify(r)).join(",") + src.slice(end);
}

const f1 = (n) => n; // 数値はそのまま JSON へ
let src = fs.readFileSync(DST, "utf8");
const master = JSON.parse(src);

const have = (table, col, v) => master[table].some((r) => r[col] === v);
const heroRows = [], skillRows = [], effectRows = [], cosmeticRows = [], storeRows = [];

let nextCosmetic = master.cosmetics.length;
let nextSku = master.store.length;
const lastUnlockPrice = Math.max(0, ...master.store.filter((s) => s.type === "HeroUnlock").map((s) => s.price));
const lastHero = master.heroes[master.heroes.length - 1];
let unlockPrice = master.store.find((s) => s.grant_id === lastHero.hero_id)?.price ?? lastUnlockPrice;

for (const h of HEROES) {
  if (have("heroes", "hero_id", h.id)) continue;
  if (!ROLE_JA[h.role]) throw new Error(`${h.id}: 未知のロール ${h.role}`);
  if (!ROLE_JA_CHECK.includes(ROLE_JA[h.role])) throw new Error("ロール表記");
  const t = TEXT[h.text];
  heroRows.push({
    hero_id: h.id, code_name: h.code, display_name_ja: h.name, role: h.role, role_ja: ROLE_JA[h.role],
    difficulty: h.difficulty,
    base_hp: h.hp[0], hp_growth: h.hp[1], base_attack: h.atk[0], attack_growth: f1(h.atk[1]),
    base_defense: h.def[0], defense_growth: h.def[1], base_magic_defense: h.mdef[0], magic_defense_growth: h.mdef[1],
    move_speed: h.ms, attack_range: h.range, resource: h.resource, resource_max: h.resourceMax,
    lore: `星環崩壊後のベルシアで、${h.name}は失われた星核の断片を巡る戦いに身を投じる。`,
    strengths: t.strengths, weaknesses: t.weaknesses, counterplay: COUNTERPLAY,
  });
  const num = h.id.slice(1);
  const n = Number(num);
  const shortNo = String(n); // 「星環シフト25」のようにヒーロー番号を付ける（既存と同じ）
  h.skills.forEach(([slot, uniq, dtype, base, sa, sp, cd, cost, rng, rad, cc], idx) => {
    const sid = `SK${num}_${SLOT_NO[slot]}`;
    const name = uniq ?? (slot === "Skill1" ? `${h.code}式・一閃` : `星環シフト${shortNo}`);
    skillRows.push({
      skill_id: sid, hero_id: h.id, hero_name: h.name, slot, name_ja: name, damage_type: dtype,
      base_damage: base, scaling_attack: sa, scaling_power: sp, cooldown_sec: cd, cost, range: rng, radius: rad, cc,
      effect_id: `FX_SK_${num}_${SLOT_NO[slot]}`,
      description: slot === "Passive" ? "条件達成時に固有強化を得る。" : `指定方向へ効果を発生し、基礎${base}ダメージ。`,
    });
    effectRows.push({
      effect_id: `FX_SK_${num}_${SLOT_NO[slot]}`, name_ja: `${h.name} - ${name}`, effect_type: EFFECT_TYPES[slot],
      duration_sec: Math.round((0.53 + ((n * 3 + idx * 5) % 6) * 0.18) * 100) / 100,
      scale_m: Math.round((0.8 + ((n + idx * 2) % 6) * 0.25) * 100) / 100,
      particle_budget: 147 + ((n * 17 + idx * 17) % 14) * 17,
    });
  });
  // コスメ（このヒーローの名を冠した 3 点）と解放商品
  for (let k = 1; k <= 3; k++) {
    nextCosmetic++;
    const cid = `CO${String(nextCosmetic).padStart(3, "0")}`;
    const rarity = RARITY[(nextCosmetic - 1) % 4];
    const cname = `${h.name} ${h.cosmetic} ${k}`;
    cosmeticRows.push({ cosmetic_id: cid, name_ja: cname, type: h.cosmetic, hero_id: "", rarity, competitive_power: 0 });
    nextSku++;
    storeRows.push({
      sku: `SKU${String(nextSku).padStart(3, "0")}`, name_ja: cname, type: "Cosmetic", currency: "AstralGem",
      price: COSMETIC_PRICE[rarity], grant_id: cid, purchase_limit: 1, refund_policy: REFUND, duplicate_policy: DUP,
      competitive_power: 0,
    });
  }
  nextSku++;
  unlockPrice += 317;
  storeRows.push({
    sku: `SKU${String(nextSku).padStart(3, "0")}`, name_ja: `${h.name} 解放`, type: "HeroUnlock", currency: "StarlightCoin",
    price: unlockPrice, grant_id: h.id, purchase_limit: 1, refund_policy: REFUND, duplicate_policy: DUP,
    competitive_power: 0,
  });
}

if (heroRows.length === 0) {
  console.log("追加するヒーローはありません（すべて登録済み）");
  process.exit(0);
}
src = append(src, "heroes", heroRows);
src = append(src, "skills", skillRows);
src = append(src, "effects", effectRows);
src = append(src, "cosmetics", cosmeticRows);
src = append(src, "store", storeRows);
JSON.parse(src); // 壊れていないこと
fs.writeFileSync(DST, src, "utf8");
console.log(`追加: heroes ${heroRows.length}, skills ${skillRows.length}, effects ${effectRows.length}, cosmetics ${cosmeticRows.length}, store ${storeRows.length}`);
