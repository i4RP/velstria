// 装備の仕様（tools/equipment_spec.mjs）を実行時マスター master_runtime.json の equipment へ反映する。再実行しても同じ結果になる。
// あわせて、英語文の出典 tools/equipment_spec.json を書き出す（tools/gen_master_en.py が読む）。
//   node tools/equipment_apply.mjs          … 書き込む
//   node tools/equipment_apply.mjs --check  … 差分があれば終了コード 1（書き込まない）
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ITEMS, STAT_KEYS, CATEGORIES } from "./equipment_spec.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DST = path.join(ROOT, "Packages/VelstriaCore/Sources/VelstriaCore/Resources/master_runtime.json");
const SPEC_JSON = path.join(ROOT, "tools/equipment_spec.json");

// 検証: ID は一意、素材は存在して循環がない、価格は素材の合計以上、能力値のキーとカテゴリが既知、文がそろっている
const byId = new Map();
for (const s of ITEMS) {
  if (byId.has(s.id)) throw new Error(`装備 ID が重複: ${s.id}`);
  byId.set(s.id, s);
}
const errors = [];
for (const s of ITEMS) {
  const where = `${s.id}（${s.name}）`;
  if (!/^EQ[1-9]\d\d$/.test(s.id)) errors.push(`${where}: ID は EQ101 形式`);
  if (!CATEGORIES.includes(s.cat)) errors.push(`${where}: 未知のカテゴリ ${s.cat}`);
  for (const c of s.also ?? []) if (!CATEGORIES.includes(c) || c === s.cat) errors.push(`${where}: also の ${c} が不正`);
  if (![1, 2, 3].includes(s.tier)) errors.push(`${where}: Tier は 1〜3`);
  if (!(s.price >= 0)) errors.push(`${where}: 価格がない`);
  for (const k of [...Object.keys(s.stats ?? {}), ...Object.keys(s.unique ?? {})]) {
    if (!STAT_KEYS.includes(k)) errors.push(`${where}: 未知の能力値 ${k}`);
  }
  const from = s.from ?? [];
  if (s.tier === 1 && from.length) errors.push(`${where}: T1 に素材`);
  if (s.tier > 1 && !from.length) errors.push(`${where}: T2 以上は素材が必要`);
  let sum = 0;
  for (const c of from) {
    const comp = byId.get(c);
    if (!comp) errors.push(`${where}: 素材 ${c} がありません`);
    else {
      sum += comp.price;
      if (comp.tier >= s.tier) errors.push(`${where}: 素材 ${c} の Tier が同じか上`);
      if (comp.consumable) errors.push(`${where}: 消耗品 ${c} は素材にできない`);
    }
  }
  if (sum > s.price) errors.push(`${where}: 素材の合計 ${sum} が価格 ${s.price} を超える`);
  if (!s.name || !s.ne) errors.push(`${where}: 名前（日・英）がない`);
  for (const p of s.passives ?? []) {
    if (p.length !== 4 || p.some((x) => typeof x !== "string" || !x)) errors.push(`${where}: passives は [名前, 文, 英名, 英文]`);
  }
  for (const e of s.effects ?? []) {
    if (typeof e.id !== "string" || !Array.isArray(e.v) || e.v.some((x) => typeof x !== "number")) errors.push(`${where}: effects が不正`);
  }
  if (s.consumable && !(s.consumable > 0)) errors.push(`${where}: consumable は秒数`);
}
if (errors.length) throw new Error("装備の仕様に誤りがあります:\n" + errors.join("\n"));

/** 能力値の文（一覧・詳細の補助。固有の能力値は「固有」を付ける）。 */
function joinPassives(s, k) {
  return (s.passives ?? []).map((p) => p[k]);
}

const equipment = ITEMS.map((s) => {
  const row = {
    item_id: s.id,
    name_ja: s.name,
    category: s.cat,
    tier: s.tier,
    price_gold: s.price,
  };
  for (const k of STAT_KEYS) row[k] = s.stats?.[k] ?? 0;
  const names = joinPassives(s, 0);
  const texts = (s.passives ?? []).map((p) => (s.passives.length > 1 ? `「${p[0]}」${p[1]}` : p[1]));
  row.passive_name = names.join("・");
  row.passive_text = texts.join("\n");
  row.build_from = s.from ?? [];
  row.unique_stats = s.unique ?? {};
  row.effects = (s.effects ?? []).map((e) => ({ id: e.id, v: e.v }));
  row.consumable_sec = s.consumable ?? 0;
  row.also_in = s.also ?? [];
  row.tag_ja = s.tag ?? "";
  return row;
});

const spec = {
  note: "tools/equipment_spec.mjs から生成。英語文は gen_master_en.py が読む。",
  items: ITEMS.map((s) => ({
    id: s.id,
    name_en: s.ne,
    tag_en: s.tage ?? "",
    passive_name_en: joinPassives(s, 2).join(" / "),
    passive_text_en: (s.passives ?? []).map((p) => (s.passives.length > 1 ? `${p[2]}: ${p[3]}` : p[3])).join("\n"),
    source: s.src ?? "",
  })),
};

const master = JSON.parse(fs.readFileSync(DST, "utf8"));
const next = { ...master, equipment };
const text = JSON.stringify(next);
const specText = JSON.stringify(spec, null, 1) + "\n";
const same = text === fs.readFileSync(DST, "utf8").trim() && fs.existsSync(SPEC_JSON) && specText === fs.readFileSync(SPEC_JSON, "utf8");
if (process.argv.includes("--check")) {
  console.log(same ? "equipment: 最新です" : "equipment: 差分があります（node tools/equipment_apply.mjs で更新）");
  process.exit(same ? 0 : 1);
}
fs.writeFileSync(DST, text);
fs.writeFileSync(SPEC_JSON, specText);
console.log(`equipment を ${equipment.length} 個書き出しました`);
const byCat = {};
for (const e of equipment) byCat[`${e.category} T${e.tier}`] = (byCat[`${e.category} T${e.tier}`] ?? 0) + 1;
console.log(byCat);
