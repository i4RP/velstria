#!/usr/bin/env node
// キット化したヒーロー（H025〜H034）の S1 / S2 に、汎用名（「◯◯式・一閃」「星環シフト◯」）ではなく固有名を付ける。
// master_runtime.json の skills と effects の name_ja を文字列置換する（既存行の表記を崩さない）。再実行しても同じ結果。
//
// usage（VELSTRIA/ で）: node tools/rename_kit_skills.mjs
// 後始末: python3 tools/gen_master_ja.py && python3 tools/gen_master_en.py（gen_master_en.py の SKILL_NAMES にも英語名が要る）
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DST = path.join(ROOT, "Packages/VelstriaCore/Sources/VelstriaCore/Resources/master_runtime.json");

// skill_id → 新しい日本語名（英語名は tools/gen_master_en.py の SKILL_NAMES）
export const NAMES = {
  SK025_2: "月弦分矢", SK025_3: "月蝕の矢",
  SK026_2: "分岐雷", SK026_3: "雷球",
  SK027_2: "跳槍撃", SK027_3: "竜牙突き",
  SK028_2: "環剣", SK028_3: "断空突進",
  SK029_2: "聖槌波", SK029_3: "聖槌突撃",
  SK030_2: "遠星弾", SK030_3: "星爆弾",
  SK031_2: "雹撃", SK031_3: "霜風",
  SK032_2: "赤拳連斬", SK032_3: "紅蓮の踏込",
  SK033_2: "裂地撃", SK033_3: "旋回斬",
  SK034_2: "鎖鉤", SK034_3: "鉄鎖旋",
  // パッシブ・奥義（元のキットに合わせた名前）
  SK025_5: "隠れ月光",
  SK026_1: "超伝導",
  SK027_1: "竜の三連突き", SK027_5: "至高の武人",
  SK031_1: "氷の誇り",
  SK032_5: "奈落の一撃",
  SK033_5: "核分裂波",
};

let src = fs.readFileSync(DST, "utf8");
let changed = 0;
for (const [sid, name] of Object.entries(NAMES)) {
  // skills 行: "skill_id":"SKxxx_n" ... "name_ja":"旧名"
  const reSkill = new RegExp(`("skill_id":"${sid}"[^}]*?"name_ja":")([^"]*)(")`);
  const m = src.match(reSkill);
  if (!m) throw new Error(`skills 行が見つかりません: ${sid}`);
  const oldName = m[2];
  if (oldName !== name) {
    src = src.replace(reSkill, (_, a, __, c) => a + name + c);
    changed++;
  }
  // effects 行: "effect_id":"FX_SK_xxx_n","name_ja":"<ヒーロー名> - 旧名"
  const eid = "FX_SK_" + sid.slice(2);
  const reFx = new RegExp(`("effect_id":"${eid}","name_ja":"[^"]*? - )([^"]*)(")`);
  if (!reFx.test(src)) throw new Error(`effects 行が見つかりません: ${eid}`);
  src = src.replace(reFx, (_, a, __, c) => a + name + c);
}
JSON.parse(src);
fs.writeFileSync(DST, src, "utf8");
console.log(`改名: ${changed} 件（skills）`);
