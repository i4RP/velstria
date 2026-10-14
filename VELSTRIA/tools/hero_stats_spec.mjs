// ヒーローの能力値の正本（2026-10-14。MLBB の値へ揃えた。docs/HERO_STATS.md）。
// `node tools/hero_stats_apply.mjs` が master_runtime.json の heroes の能力値の列を書き換える。
//
// 出典の優先順（ユーザー指示 2026-10-12・14）:
//   1. 日本語クライアントの画面（基礎能力値のスクリーンショットはまだ無い。届いたら ref に足して置き換える）
//   2. Liquipedia の infobox（Lv1 の値だけ。2026-10-14 取得。ティグリアルのスキルは日本語クライアントと完全に一致した）
//   3. Fandom の Module:Hero/data（Lv1 と Lv15。2026-10-14 取得、版の日時 2026-10-01T16:35:15Z）
// Lv1 は Liquipedia（無ければ Fandom）、レベル毎の成長は Fandom の (Lv15 − Lv1) / 14。両者の Lv1 が違う項目は
// conflicts に出す（Liquipedia の Lv1 + Fandom の成長を使う）。
//
// 取得: https://liquipedia.net/mobilelegends/api.php?action=parse&page=<Hero>&prop=wikitext&format=json
//       https://mobile-legends.fandom.com/api.php?action=query&prop=revisions&titles=Module:Hero/data&rvprop=content|timestamp&rvslots=main&format=json

export const FETCHED = {
  liquipedia: "2026-10-14（infobox の Base Stats）",
  fandom: "2026-10-14（Module:Hero/data の版 2026-10-01T16:35:15Z）",
};

// MLBB 由来の 10 体。lq = Liquipedia の Lv1、fd = Fandom の [Lv1, Lv15]（攻撃速度比率と射程は 1 つの値）。
// 射程は Fandom の basic_atk_range（MLBB の 1 マス = Velstria の 100）。resource は MLBB のリソースバー。
export const MLBB_HEROES = [
  {
    id: "H025", mlbb: "Miya", resource: "Mana",
    lq: { hp: 2320, hpRegen: 6, atk: 115, def: 17, mdef: 15, as: 1.06, asRatio: 1, mana: 500, manaRegen: 4, ms: 250 },
    fd: { hp: [2225, 4367], hpRegen: [6.0, 9.0], atk: [115, 227], def: [17, 74], mdef: [15, 50], as: [1.06, 1.41],
          mana: [500, 1900], manaRegen: [4, 6.8], ms: 240, range: 4.8 },
  },
  {
    id: "H026", mlbb: "Eudora", resource: "Mana",
    lq: { hp: 2440, hpRegen: 7.6, atk: 112, def: 18, mdef: 15, as: 1.0, asRatio: 1, mana: 500, manaRegen: 4, ms: 250 },
    fd: { hp: [2403, 4771], hpRegen: [7.6, 12.0], atk: [112, 193], def: [19, 77], mdef: [15, 50], as: [1.0, 1.14],
          mana: [500, 1900], manaRegen: [4, 6.8], ms: 250, range: 4.5 },
  },
  {
    id: "H027", mlbb: "Zilong", resource: "Mana",
    lq: { hp: 2511, hpRegen: 7, atk: 123, def: 25, mdef: 15, as: 1.05, asRatio: 1, mana: 500, manaRegen: 4, ms: 265 },
    fd: { hp: [2511, 5549], hpRegen: [7.0, 12.6], atk: [123, 249], def: [25, 90], mdef: [15, 50], as: [1.05, 1.33],
          mana: [500, 1900], manaRegen: [4, 6.8], ms: 265, range: 1.8 /* 三連突きは 2.5（キット） */ },
  },
  {
    id: "H028", mlbb: "Saber", resource: "Mana",
    lq: { hp: 2500, hpRegen: 7, atk: 118, def: 20, mdef: 15, as: 1.08, asRatio: 1, mana: 500, manaRegen: 4, ms: 260 },
    fd: { hp: [2440, 4960], hpRegen: [7, 13.2], atk: [118, 254], def: [20, 77], mdef: [15, 50], as: [1.08, 1.36],
          mana: [500, 1900], manaRegen: [4, 6.8], ms: 260, range: 1.8 },
  },
  {
    id: "H029", mlbb: "Tigreal", resource: "Mana",
    lq: { hp: 2581, hpRegen: 8.4, atk: 112, def: 20, mdef: 15, as: 1.03, asRatio: 1, mana: 500, manaRegen: 4, ms: 260 },
    fd: { hp: [2581, 6879], hpRegen: [8.4, 16.8], atk: [112, 207], def: [20, 95], mdef: [15, 71], as: [1.03, 1.31],
          mana: [500, 1900], manaRegen: [4, 6.8], ms: 260, range: 1.8 },
  },
  {
    id: "H030", mlbb: "Layla", resource: "Mana",
    lq: { hp: 2320, hpRegen: 5.4, atk: 133, def: 17, mdef: 15, as: 1.06, asRatio: 1, mana: 500, manaRegen: 4, ms: 250 },
    fd: { hp: [2250, 4378], hpRegen: [5.4, 8.2], atk: [133, 252], def: [15, 71], mdef: [15, 50], as: [1.06, 1.34],
          mana: [500, 1900], manaRegen: [4, 6.8], ms: 240, range: 4.3 },
  },
  {
    id: "H031", mlbb: "Aurora", resource: "Mana",
    lq: { hp: 2380, hpRegen: 6.8, atk: 110, def: 17, mdef: 15, as: 1.0, asRatio: 1, mana: 500, manaRegen: 4, ms: 250 },
    fd: { hp: [2380, 4496], hpRegen: [6.8, 11.0], atk: [110, 225], def: [17, 73], mdef: [15, 50], as: [1.0, 1.21],
          mana: [500, 1900], manaRegen: [4, 6.8], ms: 250, range: 4.7 },
  },
  {
    id: "H032", mlbb: "Dyrroth", resource: "Rage",
    lq: { hp: 2580, hpRegen: 8.2, atk: 117, def: 22, mdef: 15, as: 1.14, asRatio: 1, mana: 0, manaRegen: 0, ms: 265 },
    fd: { hp: [2758, 5768], hpRegen: [8.2, 15.0], atk: [117, 266], def: [22, 75], mdef: [15, 38], as: [1.14, 1.56],
          mana: [0, 0], manaRegen: [0, 0], ms: 265, range: 1.7 /* 円撃は 2.0（キット） */ },
  },
  {
    id: "H033", mlbb: "Alucard", resource: "None",
    lq: { hp: 2443, hpRegen: 7.8, atk: 123, def: 21, mdef: 15, as: 1.12, asRatio: 1, mana: 0, manaRegen: 0, ms: 260 },
    fd: { hp: [2443, 5593], hpRegen: [7.8, 14.0], atk: [123, 244], def: [21, 86], mdef: [15, 50], as: [1.13, 1.54],
          mana: [0, 0], manaRegen: [0, 0], ms: 260, range: 1.8 },
  },
  {
    id: "H034", mlbb: "Franco", resource: "Mana",
    lq: { hp: 2600, hpRegen: 9.2, atk: 116, def: 25, mdef: 15, as: 1.03, asRatio: 1, mana: 500, manaRegen: 4, ms: 260 },
    fd: { hp: [2600, 6534], hpRegen: [9.2, 18.6], atk: [116, 217], def: [25, 93], mdef: [15, 50], as: [1.03, 1.24],
          mana: [500, 1900], manaRegen: [4, 6.8], ms: 260, range: 1.8 },
  },
];

// H001〜H024（Velstria の独自ヒーロー。MLBB の対応ヒーローは無い）: MLBB のロール別の中央値（Fandom の 134 体。
// 監査 A の raw/role_medians.md、2026-10-14 の取得で再計算して一致）。[Lv1, Lv15]。射程は MLBB の値（×100 で使う）。
export const ROLE_OF = {
  Vanguard: "Tank", Duelist: "Fighter", Ranger: "Marksman", Arcanist: "Mage", Support: "Support", Assassin: "Assassin",
};
export const ROLE_MEDIANS = {
  Tank: { n: 18, hp: [2629, 6099], atk: [117, 207], def: [20, 73], mdef: [15, 50], as: [1.01, 1.24], hpRegen: [8.4, 16.8], ms: 260, range: 1.8 },
  Fighter: { n: 37, hp: [2600, 5568], atk: [121, 244], def: [22, 84], mdef: [15, 50], as: [1.07, 1.34], hpRegen: [7.8, 14.2], ms: 260, range: 1.8 },
  Marksman: { n: 20, hp: [2288, 4409], atk: [116, 245], def: [17, 73], mdef: [15, 50], as: [1.03, 1.25], hpRegen: [6.6, 9.6], ms: 240, range: 4.8 },
  Mage: { n: 26, hp: [2421, 4496], atk: [112, 199], def: [18, 72], mdef: [15, 50], as: [1.0, 1.14], hpRegen: [6.8, 11], ms: 245, range: 4.7 },
  Support: { n: 13, hp: [2468, 4902], atk: [119, 216], def: [20, 70], mdef: [15, 50], as: [1.0, 1.14], hpRegen: [7.6, 11.8], ms: 250, range: 4.1 },
  Assassin: { n: 20, hp: [2549, 4750], atk: [121, 255], def: [18, 73], mdef: [15, 50], as: [1.09, 1.36], hpRegen: [7, 13.2], ms: 260, range: 1.8 },
};
/** H001〜H024 の個性: 同じロールの 4 体の中での以前の値の z 値を、中央値の ±SPREAD の帯へ写す（順位は変わらない）。 */
export const SPREAD = 0.05;
/** H001〜H024 の以前の値（2026-10-14 の変更前の master。散らす順位の元。再実行しても結果が変わらないよう固定）。 */
export const GENERIC_BEFORE_COLUMNS = [
  "base_hp", "hp_growth", "base_attack", "attack_growth", "base_defense", "defense_growth",
  "base_magic_defense", "magic_defense_growth", "move_speed", "attack_range",
];
export const GENERIC_BEFORE = {
  H001: [2587, 166, 117, 4.45, 18, 2.65, 15, 1.6, 252, 150],
  H002: [2724, 177, 126, 4.9, 21, 2.9, 20, 1.8, 259, 150],
  H003: [2861, 188, 135, 5.35, 24, 3.15, 11, 2, 266, 550],
  H004: [2998, 199, 144, 5.8, 27, 3.4, 16, 1.4, 248, 550],
  H005: [2515, 162, 110, 6.25, 30, 2.4, 21, 1.6, 255, 550],
  H006: [2652, 173, 119, 4, 17, 2.65, 12, 1.8, 262, 150],
  H007: [2789, 184, 128, 4.45, 20, 2.9, 17, 2, 269, 150],
  H008: [2926, 195, 137, 4.9, 23, 3.15, 22, 1.4, 251, 150],
  H009: [3063, 158, 146, 5.35, 26, 3.4, 13, 1.6, 258, 550],
  H010: [2580, 169, 112, 5.8, 29, 2.4, 18, 1.8, 265, 550],
  H011: [2717, 180, 121, 6.25, 16, 2.65, 23, 2, 247, 550],
  H012: [2854, 191, 130, 4, 19, 2.9, 14, 1.4, 254, 150],
  H013: [2991, 202, 139, 4.45, 22, 3.15, 19, 1.6, 261, 150],
  H014: [2508, 165, 148, 4.9, 25, 3.4, 10, 1.8, 268, 150],
  H015: [2645, 176, 114, 5.35, 28, 2.4, 15, 2, 250, 550],
  H016: [2782, 187, 123, 5.8, 15, 2.65, 20, 1.4, 257, 550],
  H017: [2919, 198, 132, 6.25, 18, 2.9, 11, 1.6, 264, 550],
  H018: [3056, 161, 141, 4, 21, 3.15, 16, 1.8, 246, 150],
  H019: [2573, 172, 150, 4.45, 24, 3.4, 21, 2, 253, 150],
  H020: [2710, 183, 116, 4.9, 27, 2.4, 12, 1.4, 260, 150],
  H021: [2847, 194, 125, 5.35, 30, 2.65, 17, 1.6, 267, 550],
  H022: [2984, 157, 134, 5.8, 17, 2.9, 22, 1.8, 249, 550],
  H023: [2501, 168, 143, 6.25, 20, 3.15, 13, 2, 256, 550],
  H024: [2638, 179, 109, 4, 23, 3.4, 18, 1.4, 263, 150],
};
/** 以前の Energy のヒーロー（Energy のまま。上限を MLBB の 100 にする）。ほかの H001〜H024 は Mana。 */
export const GENERIC_ENERGY = ["H002", "H006", "H008", "H012", "H014", "H018", "H020", "H024"];

// リソース（MLBB の標準）。Mana はほぼ全員 500 → 1900（+100/Lv）・回復 4 → 6.8（+0.2/Lv）。エナジーは最大 100。
export const MANA = { max: 500, growth: 100, regen: 4, regenGrowth: 0.2 };
// エナジーの回復は MLBB ではヒーローごと（通常攻撃・移動で溜まるものも多い）。Velstria の汎用スキルは毎秒の回復なので、
// 以前（上限 約 500・毎秒 12）と同じ発動の間隔になるよう、上限 100 に合わせて毎秒 12 × 100/500 = 2.4（暫定）。
export const ENERGY = { max: 100, growth: 0, regen: 2.4, regenGrowth: 0 };

const round = (v, d) => { const k = 10 ** d; return Math.round(v * k) / k; };
const growth = ([lv1, lv15]) => (lv15 - lv1) / 14;

/** MLBB の 1 体（MLBB_HEROES の要素）から master の能力値の列を作る。Lv1 は Liquipedia（無ければ Fandom）、成長は
 *  Fandom の (Lv15 − Lv1) / 14。Lv1 が食い違う項目は onConflict({ id, mlbb, label, lq, fd }) に渡す。 */
export function mlbbStatColumns(h, onConflict = () => {}) {
  const pick = (key, label) => {
    const lq = h.lq[key];
    const fd = Array.isArray(h.fd[key]) ? h.fd[key][0] : h.fd[key];
    if (lq !== undefined && fd !== undefined && lq !== fd) onConflict({ id: h.id, mlbb: h.mlbb, label, lq, fd });
    return lq ?? fd;
  };
  const res = h.resource === "Mana" ? MANA : h.resource === "Energy" ? ENERGY : null;
  return {
    base_hp: pick("hp", "HP"), hp_growth: round(growth(h.fd.hp), 4),
    base_attack: pick("atk", "物理攻撃"), attack_growth: round(growth(h.fd.atk), 4),
    base_defense: pick("def", "物理防御"), defense_growth: round(growth(h.fd.def), 4),
    base_magic_defense: pick("mdef", "魔法防御"), magic_defense_growth: round(growth(h.fd.mdef), 4),
    move_speed: pick("ms", "移動速度"),
    attack_range: round(h.fd.range * 100, 0),
    attack_speed: pick("as", "攻撃速度"), attack_speed_growth: round(growth(h.fd.as), 5), attack_speed_ratio: h.lq.asRatio,
    hp_regen: pick("hpRegen", "HP 回復"), hp_regen_growth: round(growth(h.fd.hpRegen), 4),
    resource: h.resource,
    resource_max: res ? pick("mana", "マナ") : 0, resource_growth: res ? round(growth(h.fd.mana), 4) : 0,
    resource_regen: res ? pick("manaRegen", "マナ回復") : 0, resource_regen_growth: res ? round(growth(h.fd.manaRegen), 4) : 0,
  };
}
