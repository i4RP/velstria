#!/usr/bin/env node
// ヒーローの能力値（tools/hero_stats_spec.mjs）を実行時マスター master_runtime.json の heroes へ反映する。再実行しても同じ結果。
//   node tools/hero_stats_apply.mjs           … 書き込む
//   node tools/hero_stats_apply.mjs --check   … 差分があれば終了コード 1（書き込まない）
//   node tools/hero_stats_apply.mjs --report [--old=<変更前の master>]  … 旧 → 新の表と食い違いの一覧を Markdown で出す
//                                             （docs/HERO_STATS.md 用。書き込まない）
//
// H025〜H034: MLBB の値（Liquipedia の Lv1 + Fandom の成長）。H001〜H024: MLBB のロール別中央値のまわりに ±5% で散らす。
// 旧 → 新の表は既定で「今の master」を旧として出す。書き込んだ後は --old で変更前の master を渡す。
// tools/gen_runtime_data.py は古いデータを書き出すので使わない。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  MLBB_HEROES, ROLE_OF, ROLE_MEDIANS, SPREAD, MANA, ENERGY, FETCHED, GENERIC_BEFORE, GENERIC_BEFORE_COLUMNS, GENERIC_ENERGY,
  mlbbStatColumns,
} from "./hero_stats_spec.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DST = path.join(ROOT, "Packages/VelstriaCore/Sources/VelstriaCore/Resources/master_runtime.json");

const round = (v, d) => { const k = 10 ** d; return Math.round(v * k) / k; };
const growth = ([lv1, lv15]) => (lv15 - lv1) / 14;

// MLBB の 10 体（列の作り方は hero_stats_spec.mjs の mlbbStatColumns。hero_additions.mjs と共通）
const conflicts = [];
const fromMLBB = (h) => mlbbStatColumns(h, (c) => conflicts.push(c));

// H001〜H024: ロールの 4 体の中の z 値 → 中央値 × (1 ± SPREAD)。いちばん外れた 1 体が ±SPREAD になる（順位を保つ）。
function spreadOf(values) {
  const n = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const sd = Math.sqrt(values.reduce((a, b) => a + (b - mean) ** 2, 0) / n);
  if (sd === 0) return values.map(() => 0);
  const z = values.map((v) => (v - mean) / sd);
  const zmax = Math.max(...z.map(Math.abs));
  return z.map((x) => x / zmax);
}

function genericRows(master) {
  const out = new Map();
  // 散らす順位は以前の値（GENERIC_BEFORE）から取る（今の master から取ると、書き込むたびに丸めで値がずれる）
  const before = (h) => {
    const v = GENERIC_BEFORE[h.hero_id];
    if (!v) throw new Error(`${h.hero_id}: GENERIC_BEFORE にありません`);
    return { ...h, ...Object.fromEntries(GENERIC_BEFORE_COLUMNS.map((c, k) => [c, v[k]])),
             resource: GENERIC_ENERGY.includes(h.hero_id) ? "Energy" : "Mana" };
  };
  const generic = master.heroes.filter((h) => !MLBB_HEROES.some((m) => m.id === h.hero_id)).map(before);
  for (const role of Object.keys(ROLE_OF)) {
    const heroes = generic.filter((h) => h.role === role);
    if (!heroes.length) continue;
    const med = ROLE_MEDIANS[ROLE_OF[role]];
    // [列名, 中央値, 小数の桁, 今の値の列（散らす順位の元）]
    const cols = [
      ["base_hp", med.hp[0], 0, "base_hp"],
      ["hp_growth", growth(med.hp), 2, "hp_growth"],
      ["base_attack", med.atk[0], 1, "base_attack"],
      ["attack_growth", growth(med.atk), 3, "attack_growth"],
      ["base_defense", med.def[0], 1, "base_defense"],
      ["defense_growth", growth(med.def), 3, "defense_growth"],
      ["base_magic_defense", med.mdef[0], 1, "base_magic_defense"],
      ["magic_defense_growth", growth(med.mdef), 3, "magic_defense_growth"],
      ["move_speed", med.ms, 0, "move_speed"],
    ];
    const rows = heroes.map(() => ({}));
    for (const [col, m, digits, src] of cols) {
      const s = spreadOf(heroes.map((h) => h[src]));
      heroes.forEach((_, k) => { rows[k][col] = round(m * (1 + SPREAD * s[k]), digits); });
    }
    heroes.forEach((h, k) => {
      const ranged = h.attack_range >= 300;
      const res = h.resource === "Energy" ? ENERGY : MANA;
      Object.assign(rows[k], {
        // 射程: 遠隔は MLBB のロールの中央値、近接は MLBB の近接の標準 1.8（どちらも ×100）
        attack_range: ranged ? round(med.range * 100, 0) : 180,
        attack_speed: med.as[0], attack_speed_growth: round(growth(med.as), 5), attack_speed_ratio: 1,
        hp_regen: med.hpRegen[0], hp_regen_growth: round(growth(med.hpRegen), 4),
        resource: h.resource === "Energy" ? "Energy" : "Mana",
        resource_max: res.max, resource_growth: res.growth, resource_regen: res.regen, resource_regen_growth: res.regenGrowth,
      });
      out.set(h.hero_id, rows[k]);
    });
  }
  return out;
}

// 列の順（既存の列の並びを崩さず、新しい列は射程の後・リソースの前後に入れる）
const ORDER = [
  "hero_id", "code_name", "display_name_ja", "role", "role_ja", "difficulty",
  "base_hp", "hp_growth", "base_attack", "attack_growth", "base_defense", "defense_growth",
  "base_magic_defense", "magic_defense_growth", "move_speed", "attack_range",
  "attack_speed", "attack_speed_growth", "attack_speed_ratio", "hp_regen", "hp_regen_growth",
  "resource", "resource_max", "resource_growth", "resource_regen", "resource_regen_growth",
  "lore", "strengths", "weaknesses", "counterplay",
];

const src = fs.readFileSync(DST, "utf8");
const master = JSON.parse(src);
const generic = genericRows(master);
const stats = new Map(MLBB_HEROES.map((h) => [h.id, fromMLBB(h)]));
for (const [id, row] of generic) stats.set(id, row);

const heroes = master.heroes.map((h) => {
  const s = stats.get(h.hero_id);
  if (!s) throw new Error(`${h.hero_id}: 能力値がありません`);
  const merged = { ...h, ...s };
  const row = {};
  for (const k of ORDER) {
    if (!(k in merged)) throw new Error(`${h.hero_id}: 列 ${k} がありません`);
    row[k] = merged[k];
  }
  for (const k of Object.keys(merged)) if (!ORDER.includes(k)) throw new Error(`${h.hero_id}: 未知の列 ${k}`);
  const wasRange = GENERIC_BEFORE[h.hero_id]?.[GENERIC_BEFORE_COLUMNS.indexOf("attack_range")] ?? h.attack_range;
  if ((row.attack_range >= 300) !== (wasRange >= 300)) throw new Error(`${h.hero_id}: 遠隔/近接が変わる（${wasRange} → ${row.attack_range}）`);
  return row;
});

if (process.argv.includes("--report")) {
  // --old=<path>: 旧として比べる master（既定は今の master。書き込んだ後は変更前の master を渡す）
  const oldArg = process.argv.find((a) => a.startsWith("--old="));
  const oldMaster = oldArg ? JSON.parse(fs.readFileSync(oldArg.slice(6), "utf8")) : master;
  const fmt = (v) => (typeof v === "number" ? String(round(v, 4)) : String(v));
  const lv15 = (b, g) => round(b + 14 * g, 2);
  const lines = [];
  lines.push(`取得: Liquipedia ${FETCHED.liquipedia} / Fandom ${FETCHED.fandom}`, "");
  lines.push("| ID | 項目 | 旧 Lv1 → Lv15 | 新 Lv1 → Lv15（成長/Lv） | 出典 |", "|---|---|---|---|---|");
  for (const old of oldMaster.heroes) {
    const n = heroes.find((h) => h.hero_id === old.hero_id);
    const m = MLBB_HEROES.find((h) => h.id === old.hero_id);
    const name = m ? `${old.hero_id} ${m.mlbb}` : `${old.hero_id} ${old.code_name}（${old.role}）`;
    const srcOf = (label) => {
      if (!m) return `MLBB ${ROLE_OF[old.role]} 中央値 ±${SPREAD * 100}%`;
      const hit = conflicts.find((c) => c.id === m.id && c.label === label);
      if (!hit) return "LQ = FD";
      return label === "移動速度" ? `LQ（FD は ${hit.fd}）` : `LQ Lv1 + FD 成長（FD の Lv1 は ${hit.fd}）`;
    };
    const row = (label, ob, og, nb, ng, s) =>
      lines.push(`| ${name} | ${label} | ${fmt(ob)} → ${fmt(lv15(ob, og))} | ${fmt(nb)} → ${fmt(lv15(nb, ng))}（${fmt(ng)}） | ${s} |`);
    row("HP", old.base_hp, old.hp_growth, n.base_hp, n.hp_growth, srcOf("HP"));
    row("物理攻撃", old.base_attack, old.attack_growth, n.base_attack, n.attack_growth, srcOf("物理攻撃"));
    row("物理防御", old.base_defense, old.defense_growth, n.base_defense, n.defense_growth, srcOf("物理防御"));
    row("魔法防御", old.base_magic_defense, old.magic_defense_growth, n.base_magic_defense, n.magic_defense_growth, srcOf("魔法防御"));
    const oldAS = old.attack_range >= 300 ? 0.8 : 0.85;
    lines.push(`| ${name} | 攻撃速度 | ${oldAS} → ${round(oldAS * 1.28, 3)}（一律） | ${n.attack_speed} → ${lv15(n.attack_speed, n.attack_speed_growth)}（${fmt(n.attack_speed_growth)}）・比率 ${n.attack_speed_ratio * 100}% | ${m ? srcOf("攻撃速度") : `MLBB ${ROLE_OF[old.role]} 中央値`} |`);
    lines.push(`| ${name} | HP 回復/秒 | 4.6 → 13（一律） | ${n.hp_regen} → ${lv15(n.hp_regen, n.hp_regen_growth)}（${fmt(n.hp_regen_growth)}） | ${m ? srcOf("HP 回復") : `MLBB ${ROLE_OF[old.role]} 中央値`} |`);
    lines.push(`| ${name} | 移動速度 | ${old.move_speed}（×1.35） | ${n.move_speed}（×mapScale 1.35） | ${srcOf("移動速度")} |`);
    lines.push(`| ${name} | 射程 | ${old.attack_range} | ${n.attack_range} | ${m ? "FD × 100" : "MLBB 中央値 × 100（近接 180）"} |`);
    const oldRes = `${old.resource} ${old.resource_max}（成長なし）・回復 ${old.resource === "Energy" ? "12（一律）" : "3.35 → 8.25（一律）"}`;
    const newRes = n.resource_max > 0
      ? `${n.resource} ${n.resource_max} → ${lv15(n.resource_max, n.resource_growth)}・回復 ${n.resource_regen} → ${lv15(n.resource_regen, n.resource_regen_growth)}`
      : `${n.resource}（量を持たない）`;
    lines.push(`| ${name} | リソース | ${oldRes} | ${newRes} | ${m ? "FD・LQ" : n.resource === "Energy" ? "エナジー（MLBB の上限 100）" : "MLBB の標準のマナ"} |`);
  }
  lines.push("", "### Liquipedia と Fandom の Lv1 の食い違い（Liquipedia の Lv1 + Fandom の成長を採用）", "",
    "| ID | MLBB | 項目 | Liquipedia | Fandom |", "|---|---|---|---|---|");
  for (const c of conflicts) lines.push(`| ${c.id} | ${c.mlbb} | ${c.label} | ${c.lq} | ${c.fd} |`);
  console.log(lines.join("\n"));
  process.exit(0);
}

const next = { ...master, heroes };
const text = JSON.stringify(next);
const same = text === src.trim();
if (process.argv.includes("--check")) {
  console.log(same ? "heroes: 最新です" : "heroes: 差分があります（node tools/hero_stats_apply.mjs で更新）");
  process.exit(same ? 0 : 1);
}
fs.writeFileSync(DST, text);
console.log(`heroes の能力値を ${heroes.length} 体分書き出しました（食い違い ${conflicts.length} 件）`);
