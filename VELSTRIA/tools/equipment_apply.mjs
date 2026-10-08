// 装備の仕様（tools/equipment_spec.mjs）を実行時マスター master_runtime.json の equipment へ反映する。再実行しても同じ結果になる。
// あわせて、英語文の出典 tools/equipment_spec.json を書き出す（tools/gen_master_en.py が読む）。
//   node tools/equipment_apply.mjs          … 書き込む
//   node tools/equipment_apply.mjs --check  … 差分があれば終了コード 1（書き込まない）
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { priced } from "./equipment_spec.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DST = path.join(ROOT, "Packages/VelstriaCore/Sources/VelstriaCore/Resources/master_runtime.json");
const SPEC_JSON = path.join(ROOT, "tools/equipment_spec.json");

const STAT_KEYS = [
  "attack", "ability_power", "hp", "armor", "magic_resist", "move_speed", "cooldown_reduction_pct",
  "attack_speed_pct", "crit_chance_pct", "crit_damage_pct", "lifesteal_pct", "spell_vamp_pct",
  "armor_pen_pct", "armor_pen_flat", "magic_pen_pct", "magic_pen_flat", "hp_regen", "resource_regen",
  "ability_power_pct", "move_speed_pct", "out_of_combat_move_pct", "heal_shield_power_pct", "monster_damage_pct",
];

const master = JSON.parse(fs.readFileSync(DST, "utf8"));
const old = new Map(master.equipment.map((e) => [e.item_id, e]));
const specs = priced();
if (specs.length !== 72 || old.size !== 72) throw new Error(`装備は 72 個のはず: spec ${specs.length} / master ${old.size}`);

// 検証: 素材は存在し、同じ素材を含む循環がなく、能力値のキーが既知
const ids = new Set(specs.map((s) => s.id));
for (const s of specs) {
  if (!old.has(s.id)) throw new Error(`マスターに無い装備: ${s.id}`);
  if (old.get(s.id).category !== s.cat) throw new Error(`${s.id}: カテゴリが違います（${old.get(s.id).category} / ${s.cat}）`);
  if (old.get(s.id).tier !== s.tier) throw new Error(`${s.id}: Tier が違います`);
  for (const c of s.from ?? []) if (!ids.has(c)) throw new Error(`${s.id}: 素材 ${c} がありません`);
  for (const k of Object.keys(s.stats)) if (!STAT_KEYS.includes(k)) throw new Error(`${s.id}: 未知の能力値 ${k}`);
  if (s.tier === 1 && s.from?.length) throw new Error(`${s.id}: T1 に素材`);
  if (s.tier > 1 && !(s.from?.length >= 2)) throw new Error(`${s.id}: T2 以上は素材が 2 つ以上必要`);
}

const equipment = specs.map((s) => {
  const row = {
    item_id: s.id,
    name_ja: old.get(s.id).name_ja,
    category: s.cat,
    tier: s.tier,
    price_gold: s.price,
  };
  for (const k of STAT_KEYS) row[k] = s.stats[k] ?? 0;
  row.passive_name = s.pn;
  row.passive_text = s.pt;
  row.build_from = s.from ?? [];
  row.effect_id = s.effect?.id ?? "";
  row.effect_values = s.effect?.v ?? [];
  return row;
});

const spec = {
  note: "tools/equipment_spec.mjs から生成。英語文は gen_master_en.py が読む。",
  items: specs.map((s) => ({ id: s.id, passive_name_en: s.pne, passive_text_en: s.pte, has_effect: !!s.effect })),
};

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
console.log(`equipment を ${equipment.length} 個更新しました`);
const byCat = {};
for (const e of equipment) byCat[e.category] = (byCat[e.category] ?? 0) + 1;
console.log(byCat);
