# Franco (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`）。この文書の調査の節（英語）の能力値は置き換え前の調べ。
>
> 2026-10-14（スキルの段階）: **スキルは公式の表をそのまま使う（スキル1・2 = 6 段、アルティメット = 3 段）**。rank = 公式の Lv。ダメージ = 公式の基礎[Lv] + 公式の係数 × 能力値（合計の物理攻撃 / 自身の最大 HP）。スロット倍率・物理係数の × 0.6・キットの換算（`hookScale` / `shockScale` / `ultScale`）・線形補間（`lerp`）・アルティメットの上限（相手の最大 HP の 80%）・アルティメットの踏み込みは外した。下の「Velstria 実装対応表」と「公式の表へ（スキルの段階）」。

**数値の正は「公式（日本語クライアント）の数値」**（2026-10-10 / 10-11 に受け取った日本語クライアントのスキル詳細の画面）。Fandom・Liquipedia・それより上のウェブ調査と食い違う値は日本語クライアントが優先する。

Values come from Mobile Legends Fandom / Liquipedia search extracts plus mlbb.io, mlbb.tools and oneesports (direct Fandom/Liquipedia fetch was blocked). "unknown" = not found. "disputed" = sources disagree.

## Hero overview
- Role / lane: Tank, roam. Melee.
- Resource: mana (mlbb.io level 1: 500, +100 per level; mlbb.tools lists 460, regen 3.2).
- Basic attack: melee single target.
- Attack range: about 1.8 (low confidence; extract).
- Base stats at level 1 (Fandom / mlbb.io): HP 2600, physical attack 116, physical defense 25, magic defense 15, attack speed 1.03, movement speed 260.
- Growth per level: HP +281, phys attack +7.21, phys defense +4.8571, magic defense +2.5, attack speed +0.015 to +0.02 (level 15: HP 6534, attack 217, phys def 93).
- Disputed (mlbb.tools): HP 2869, regen 8.8, phys defense 26, attack speed 0.79, movement speed 255. Prefer Fandom/mlbb.io.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Wasteland Force
- Cast type: passive.
- If no damage is taken for 5 s, Franco gains 10% movement speed, recovers 1% max HP per second, and begins accumulating Wasteland Force (up to 10 stacks). His next skill cast consumes all stacks, increasing that skill's damage by up to 150% (per-stack value = unknown; presumably +15% per stack, not confirmed).
- Taking damage ends the regeneration/speed state; stack decay rules = unknown.

## Skill 1 - Iron Hook
- Cast type: directional line skillshot (projectile hook).
- Effect: launches an iron hook in the target direction; the first enemy unit hit takes 400 (+100% Total Physical Attack) physical damage and is dragged to Franco. Per oneesports the hook passes through walls and turrets and the target is stunned/immobile during the drag. A guide extract also says it reduces the enemy's energy (older text); unverified.
- Cooldown by level: 15.0 / 14.2 / 13.4 / 12.6 / 11.8 / 11.0 s.
- Mana by level: 135 / 140 / 145 / 150 / 155 / 160.
- Base damage: 400 / 450 / 500 / 550 / 600 / 650.
- Range, width, projectile speed, stun duration during drag: unknown. (Older guide text claims 170% attack; superseded.)

## Skill 2 - Fury Shock
- Cast type: self-centered AoE lash.
- Effect: lashes nearby enemies for 300 plus 4% of Franco's max HP as physical damage, slowing them by 70% for 1.5 s (older text also mentions an attack reduction; unverified). Higher HP = more damage.
- Cooldown by level: 7.0 / 6.5 / 6.0 / 5.5 / 5.0 / 4.5 s.
- Mana by level: 40 / 45 / 50 / 55 / 60 / 65.
- Base damage: 300 / 330 / 360 / 390 / 420 / 450 (+4% max HP; per-level change of the HP ratio = unknown).
- Radius: unknown.

## Ultimate - Bloody Hunt
- Cast type: point-and-click single-target enemy hero (short range).
- Effect: suppresses the target hero for 1.8 s and strikes 6 times during it, each hit dealing 50 (+70% Total Physical Attack) physical damage at level 1. Suppression cannot be removed by Purify and cancels skills of the target, including those with control immunity.
- Cooldown by level: 62 / 55 / 48 s. Mana: 110 / 125 / 140.
- Damage per hit base: 50 / 60 / 70 (+70% Total Physical Attack); total with ratio about 6 hits.
- Cast range: short (exact unknown). Interruptibility of Franco while channeling: unknown (suppression by an enemy would presumably interrupt).

## Gameplay identity
- Hook-and-chain tank: one successful Iron Hook sets up the whole team's kill.
- Sustain when out of combat (passive) and big HP scaling in Fury Shock.
- Ultimate is a hard-lock 1.8 s suppression that bypasses control immunity and Purify.
- High-risk, high-reward skillshot play; stack-empowered hook rewards patience.

## Simulation notes
- Standard: line skillshot projectile, self-centered AoE with slow and max-HP scaling, single-target lock with multi-hit damage, mana costs, out-of-combat regen.
- Needs special state: hook projectile that stops at first hit and pulls the target (displacement toward caster, ignoring terrain/turrets); Wasteland Force stack timer (5 s without damage, 10 stacks, consumed by next skill with damage multiplier); suppression status (cannot be cleansed, cancels the target's actions); self-lock channel during Bloody Hunt; max-HP percent scaling.

## Sources
- https://mobile-legends.fandom.com/wiki/Franco (via search extract)
- https://liquipedia.net/mobilelegends/Franco (via search extract)
- https://mlbb.io/en/hero/franco
- https://mlbb.tools/heroes/franco
- https://www.oneesports.gg/mobile-legends/franco-guide-best-build-emblem/

## 公式（日本語クライアント）の数値

フランコ(Franco)、ロール「タンク」、サブタグ「先手/コントロール」。2026-10-10 に受け取った日本語クライアントの実機のスクリーンショット（スキル詳細の画面）の転記（スキルのレベルは S1・S2 が Lv1〜6、
アルティメットが Lv1〜3）。**下の Fandom・Liquipedia の値と違うところはこちらを正とする**（違いはアルティメットの Lv3 の CD だけ: Fandom 45 → 48 秒）。
日本語クライアントのタグ「攻撃」は英語版の Damage（`KitTag.damage`）、「爆発力」は Burst（`KitTag.burst`）、「妨害」は CC（`KitTag.disrupt`）。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | ワイルドフォース | バフ | 5秒間ダメージを受けなかった場合、移動速度が10%上昇し、1秒ごとに最大HPの1%を回復し、ワイルドフォースが蓄積され始める（最大10スタック）。次のスキル発動時にすべてのワイルドフォースを消費し、そのスキルダメージを最大150%増加させる。 |
| スキル1 | アイアンフック | 妨害・攻撃 | CD 15.0 / 14.2 / 13.4 / 12.6 / 11.8 / 11.0、MP 135 / 140 / 145 / 150 / 155 / 160、基礎ダメージ 400 / 450 / 500 / 550 / 600 / 650。指定方向へアイアンフックを放ち、最初に命中した敵に400(+100%物理攻撃)の物理ダメージを与え、自身の元へ引き寄せる。 |
| スキル2 | レイジショック | 減速 | CD 7.0 / 6.5 / 6.0 / 5.5 / 5.0 / 4.5、MP 40 / 45 / 50 / 55 / 60 / 65、基礎ダメージ 300 / 330 / 360 / 390 / 420 / 450。怒りの一撃で周囲の敵に300(+自身の最大HPの4%)の物理ダメージを与え、1.5秒間移動速度を70%低下させる。 |
| アルティメット | マサクル | 爆発力・妨害 | CD 62.0 / 55.0 / 48.0、MP 110 / 125 / 140、各回ダメージ 50 / 60 / 70。対象の敵ヒーローを1.8秒間、制圧状態にし、その間に6回攻撃する。攻撃ごとに50(+70%物理攻撃)の物理ダメージを与える。 |

2026-10-11 に受け取った無加工の原本（日本語クライアントのスキル詳細の画面 IMG_4479〜4483。画像はコミットしない）と照合した: 上の表の数値（CD・MP・基礎ダメージ・係数・
減速 70% 1.5 秒・制圧 1.8 秒 6 回・ワイルドフォース最大 10 スタック 150%）・タグ（バフ / 妨害・攻撃 / 減速 / 爆発力・妨害）・文の構造はすべて一致した（変更なし）。
スキル吸収率・攻撃エフェクト・ミニオン / モンスターへの補正の節は、どのスキルにも無い。

## 公式（MLBB Fandom 現行）の数値

`https://mobile-legends.fandom.com/api.php?action=parse&page=Franco&prop=wikitext&format=json` の `{{Ability}}` をそのまま転記。スキルのレベルは S1・S2 が Lv1〜6、アルティメットが Lv1〜3。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | Wasteland Force | Buff | 5 秒間ダメージを受けないと移動速度 +10%、毎秒最大 HP の 1% 回復、Wasteland Force を蓄積（最大 10）。次のスキルの発動ですべて消費し、そのスキルのダメージを最大 150% 増やす（1 つ 15%）。消費したあとは、もう一度ダメージを受けるまで蓄積が始まらない。※ Fandom の properties の「1 つあたり 5% / 10% / … / 50%」は説明文の「最大 150%」と合わない（Liquipedia も「最大 150%」）ので、説明文を採る |
| スキル1 | Iron Hook | CC・Damage | CD 15.0 / 14.2 / 13.4 / 12.6 / 11.8 / 11.0、マナ 135 / 140 / 145 / 150 / 155 / 160。指定方向へ鉄の鉤を放ち、最初に命中した敵ユニットに 400〜650（+100% 総物理攻撃）を与えて自分の元へ引き寄せる。鉤は先にスタンを付けてから引き寄せる。基礎 400 / 450 / 500 / 550 / 600 / 650 |
| スキル2 | Fury Shock | Slow | CD 7.0 / 6.5 / 6.0 / 5.5 / 5.0 / 4.5、マナ 40 / 45 / 50 / 55 / 60 / 65。周囲の敵に 300〜450 + 自分の最大 HP の 4% の物理ダメージ、70% 減速 1.5 秒。基礎 300 / 330 / 360 / 390 / 420 / 450 |
| アルティメット | Bloody Hunt | Burst・CC | CD 62 / 55 / 45（Liquipedia・以前の調査は 62 / 55 / 48。Fandom は 2023 年からずっと 45）、マナ 110 / 125 / 140。対象の敵ヒーローを 1.8 秒制圧し、その間に 6 回、1 回 50 / 60 / 70（+70% 総物理攻撃）。Franco が CC を受けると途中で終わる |

Fandom の CC の頁（`%TEMP%\mlbb_audit\raw\fd_mech2.json`）: 「Stunned」の頁の「Abilities with stunned and 1 or more CC effects」に **Franco's Iron Hook (+pulled)**。
「Pulled」の頁: 移動・通常攻撃・スキルを封じ、発動中のスキルを中断する（詠唱が要るスキルは除く）、強靭で縮まない、CC 無効で防げる。「Suppressed」の頁: Bloody Hunt は追加の CC を持たない唯一の制圧。
Liquipedia の Iron Hook の文（日本語クライアントと同じ）にはスタンが無い。

ランクの対応: rank = 公式の Lv（スキル1・2 は 1〜6、アルティメットは 1〜3）。表をそのまま引く（`Kit.level`）。

## Velstria 実装対応表

H034 鎖鉤のゴルム（サポート・近接・Mana）= Velstria 版の Franco。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H034.swift`
（追加プリミティブ `KitGormLock.swift`）、テスト: `Tests/VelstriaCoreTests/Kits/Kit_H034Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H034.swift`。
スロットは上の調査の順に割り当てる（スキル1 = Iron Hook「鎖鉤」、スキル2 = Fury Shock「鉄鎖旋」、アルティメット = Bloody Hunt「狩猟鎖獄」、パッシブ = Wasteland Force「鉄鎖の執念」。名前はマスターデータのもの）。
ロールは Velstria では「サポート」のまま（MLBB はタンク。ロールは汎用のパッシブの置き換えと比べる相手を決める。既知の外れ値）。

**公式の表をそのまま使う（6 / 6 / 3 段）**: スキル1・2 は Lv1〜6、アルティメットは Lv1〜3 の表（基礎ダメージ・CD・MP）を `[Double]` で持ち、`Kit.level` / `Kit.official` / `Kit.cooldown` で引く。
ダメージ = 公式の基礎[Lv] + 公式の係数 × 能力値（鉤・アルティメット = 合計の物理攻撃 `.totalAttack`、スキル2 = 自身の最大 HP `.maxHP`）。全体の倍率・キットの換算・補間は無い。
CD = 公式の秒数 × (1 − CD 短縮)。マナ = 公式の表（`HeroKits.resourceCost`）。
スキル吸収率・攻撃エフェクト・ミニオン / モンスターへの補正は日本語クライアントの文に無いので既定（スキル吸収 100%・補正なし）。
距離は Velstria 単位（≈ MLBB × 100）。資料に無い値（射程・幅・半径・時間など）は下の「推測の値」に書いた。
このキットはロール「サポート」の汎用の味方回復パッシブと、アルティメットの味方全体回復を置き換える（ゴルムは回復役ではなく鉤の起点役）。
ツールチップの距離は単位の無い数字を出さず、近接攻撃の射程（MLBB の 1.8 = 180）に対する倍率で書く（`{reachMult}`: 鎖鉤 約 3.8 倍、鉄鎖旋 約 1.4 倍、狩猟鎖獄 約 1.9 倍）。

### 対応表（○ = 実装、△ = 簡略化・推測、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 近接・マナ・基本ステータス | ○ | `master_runtime.json` の H034（能力値は MLBB の値。`docs/HERO_STATS.md`） |
| パッシブ: 5 秒ダメージを受けないと移動速度 +10%・毎秒最大 HP の 1% 回復 | ○（公式） | 被ダメ（シールドが吸収した分も数える）のたびに待ち（`timers[0]`）を 5 秒に戻す。待ちが 0 の間は `speedBoost` 0.10（被ダメで外す無期限のステータス）と、0.5 秒ごとに最大 HP の 0.5% の回復（合計で毎秒 1%。回復量スコア・回復強化の対象外） |
| パッシブ: 闘気（Wasteland Force）が最大 10 たまる | ○ / △（推測） | 最大 10 は公式。**たまる速さは推測**: 無被弾の間 1 秒に 1 つ（10 個で 15 秒）。HUD はパッシブのバッジに個数を出す。説明文は公式の文のとおり速さを書かない |
| パッシブ: 次のスキルの発動で闘気をすべて消費し、そのスキルのダメージが最大 +150% | ○ / △（推測） | 最大 150% は公式。**1 つあたりは推測**: 1 つにつき +15%（「最大 150%」÷ 10。Fandom の properties の 5〜50% は説明文と合わないので採らない）。スキルの発動時に消費（鉤が外れても、アルティメットでも）。スキル1・スキル2 はそのスキルのダメージ全体、アルティメットは 6 回すべてに掛かる。**無被弾の間に消費したら、次にダメージを受けるまで闘気はたまらない**（Fandom の注記。`ints[6]`）。説明文は公式の文（「最大150%」= `{maxAmp}`）で、1 つあたりの値を書かない |
| パッシブ: ダメージを受けると回復と加速が終わる。闘気の減衰の規則は不明 | △ | 被ダメで回復と加速は止まり、闘気は消えずに残る（次のスキルで使う）。5 秒の待ちのあいだは闘気も増えない。死亡で全部リセット |
| パッシブの演出 | ○ | 闘気が 1 つ増えるたびにパッシブの合図（`recipe(.passive).cast`）が出る。スキルで闘気を使い切った直後は `FX_H034.passiveRelease`（消費した数に比例して鎖がはじけて閃く） |
| スキル1 Iron Hook: 直線の鉤。最初に当たった敵ユニットに 400〜650（+100% 物理攻撃）の物理ダメージ | ○（公式） | 非貫通の直線弾（射程 680・幅 55・速度 1800。推測）。最初に当たった敵 1 体（ヒーロー・ミニオン・モンスター）だけ。味方とタワー・構造物には当たらない。ダメージ = **公式の表** `[400, 450, 500, 550, 600, 650][Lv] + 1.0 × 合計の物理攻撃`（`Kit.official(…, .totalAttack)`）。ミニオン・モンスターにも同じ値（補正なし） |
| スキル1: 敵を引き寄せる | ○ | 鉤の `onHit` で `Kit.pullIgnoringTerrain`（`Systems/Kits/KitPull.swift`。所要 0.30 秒・端同士の隙間 10 で止まる）。強制移動の間は動けず行動できない。CC 無効の相手はダメージのみ、無敵の相手には何も起きない |
| スキル1: 引き寄せの間のスタン | ○（Fandom） | 日本語クライアント・Liquipedia の文には無いが、Fandom の「Stunned」の頁に Iron Hook が「スタン + 引き寄せ」として載る（上）。MLBB の「引き寄せ」は発動中のスキルを中断するが、Velstria の強制移動は中断しないので、引き寄せの 0.30 秒の間のスタン（`Tune.hookStun = hookPull`、基本の段階）で中断を起こす。着いたらすぐ動ける。至近距離（引き寄せが無い）でも 0.30 秒のスタン。スタンは強靭で縮み浄化で外れる（MLBB の引き寄せは強靭で縮まない。共通の `CombatSystem.resilienceExemptTags` に鉤のタグを足せば揃う） |
| スキル1: 壁・タワーを通り抜ける（地形を無視して引き寄せる） | ○ | 鉤（弾）は壁・タワーを素通りする（弾は構造物に当たらない仕様）。**引き寄せも壁を越える**: 終点（ゴルムの前、端同士の隙間 10）が歩ける場所なら、途中の壁を無視して直線で運ぶ。終点が壁の中（ゴルムが壁に張り付いている）など歩けないときは、壁の手前で止まる（`Kit.pull`）。壁が無ければ `Kit.pull` と同じ終点・同じ変位 |
| スキル1 の鎖の見え方 | ○ | 鉤（`travel`）に追従する鎖が、鉤の先端を保ったまま手元へ向かって伸びる。命中すると相手に追従する短い鎖（引き寄せの 0.3 秒）が手元の向きに張られる（`hit`） |
| スキル1: 敵のエネルギーを減らす（旧版の記述・未確認） | × | 採用しない（公式の文に無い） |
| スキル1: CD・MP | ○（公式） | CD `[15.0, 14.2, 13.4, 12.6, 11.8, 11.0]`、MP `[135, 140, 145, 150, 155, 160]` |
| スキル2 Fury Shock: 自身中心の範囲に 300〜450（+自身の最大 HP の 4%）の物理ダメージ | ○（公式） | 自身中心の円（`.selfAoE`・半径 260。推測）。ダメージ = **公式の表** `[300, 330, 360, 390, 420, 450][Lv] + 0.04 × 自身の最大 HP`（`Kit.official(…, .maxHP)`。`DamageScaling.maxHealth` は「対象の最大 HP」なので使わない）。ミニオン・モンスターにも当たり（補正なし）、構造物には当たらない |
| スキル2: 70% 減速 1.5 秒 | ○（公式） | `slow` の magnitude 0.70、1.5 秒（CC 無効の相手には入らない） |
| スキル2: 攻撃力低下（旧版の記述・未確認） | × | 採用しない |
| スキル2: CD・MP | ○（公式） | CD `[7.0, 6.5, 6.0, 5.5, 5.0, 4.5]`、MP `[40, 45, 50, 55, 60, 65]` |
| アルティメット Bloody Hunt: 単体指定の敵ヒーロー | ○ | `.targetedBlink` の型の対象指定（`requiresTarget`、射程 350 = 術者の中心から対象の縁まで。推測）。敵ヒーローだけが対象（ミニオン・無敵・視認外は不可）。居なければコスト・CD を消費せず失敗。指定ユニット・地点・向きもサポート、自動は HP + シールド最小 |
| アルティメット: 踏み込まない（その場で拘束） | ○ | MLBB の Bloody Hunt に突進・ブリンクは無い。**以前の「離れていれば踏み込む」（速さ 2600、調査に無い追加）は外した**。射程内の相手を発動の tick にその場で拘束する（ゴルムは動かない）。照準の型は targetedBlink のままだが、`movesCaster(slot: .ultimate)` = false なので**バインド（敵の root）の間も撃てる**（バインドは移動・ブリンク・突進だけを封じる） |
| アルティメット: 1.8 秒の suppress。浄化不可・CC 無効も無視、対象のスキルは中断される | ○（公式） | `StatusKind.suppress`（`Kit.suppress`。CC の段階は最上級）。浄化で外れず、`ccImmune` でも入る。付与の時に前隙を取り消し、スキルのタイマー・突進は中断される。無敵の相手には入らない（その場合はゴルムも固まらない） |
| アルティメット: 拘束の間に 6 回、1 回 50 / 60 / 70（+70% 物理攻撃） | ○（公式） / △（時刻は推測） | 拘束の 0.15, 0.45, ..., 1.65 秒に 6 回（`Kit.strikeSequence`）。1 回 = **公式の表** `[50, 60, 70][Lv] + 0.7 × 合計の物理攻撃`。**6 回の合計に上限は無い**（以前の「相手の最大 HP の 80% まで」`ultMaxHPFraction` は MLBB に無い独自の安全弁で、外した）。闘気 10 個なら 1 回 × 2.5 |
| アルティメットの演出（6 回の叩きつけ） | ○ | 縛られている間の輪は `impact`（アルティメット発動時に相手の位置へ 1.8 秒）。`hit` は 1 発ごとの短い閃きと小さな火花だけ（`hitPerHit = true`） |
| アルティメット: ゴルムの行動（Fandom: Franco が CC を受けると途中で終わる） | ○ | 拘束中のゴルムは動けず（自分に付ける `root`。sourceID = 自分なのでバインドではない）、他のスキルも通常攻撃も出せない（`channeling` を表示用に付ける）。スタン・打ち上げ・suppress を受けると残りの連撃は取り消され、相手は解放される（クールダウンは戻らない）。ゴルムが倒れても相手は解放される（`KitRuntime.heroDied` → `Kit.releaseSuppress`）。相手が倒れたら終了 |
| アルティメット: CD・MP | ○（公式） | CD は日本語クライアントの `[62, 55, 48]`（Fandom の 45 は日本語クライアント・Liquipedia と合わないので採らない）、MP `[110, 125, 140]` |
| スキル吸収率・攻撃エフェクト・ミニオン / モンスターへの補正 | ○（公式） | どのスキルの文にも無いので既定（`HitPayload` の既定: スキル吸収率 100%、ミニオン・モンスター × 1）。鉤・スキル2・アルティメットは通常攻撃ではないので攻撃エフェクトは関係しない |
| ボット | ○ | 鉤（スキル1）: 狙う敵ヒーローより手前の線上（幅 + 半径以内）にミニオン・モンスターが居れば撃たない（手前の別の敵ヒーローは引けるので撃つ）。アルティメット（狩猟鎖獄）: 射程内の敵ヒーローが「HP 70% 未満」「鉤（`kit.H034.hookStun`）でスタン中」「近く（800 以内）に味方ヒーローが居る」のいずれかなら、汎用の関門（倒せる・2 体）を飛び越えて撃つ（`.castNow`）。それ以外は汎用の判断、射程外は見送り |
| 基本の通常攻撃（近接単体、射程 1.8） | ○ | 汎用のまま |
| スキルのタグ（UI） | ○（公式） | パッシブ `buff`、スキル1 `disrupt damage`（妨害・攻撃）、スキル2 `slow`、アルティメット `burst disrupt`（爆発力・妨害）（`KitText.tags` / `HeroKits.tags`） |
| 説明文 | ○（公式の文） | 日本語クライアントの文の構造（`{base}(+{atkPct}%物理攻撃)` は公式の値そのもの。例: スキル1 Lv2 = 450(+100%物理攻撃)）。名前は master（闘気・鎖鉤）。距離の倍率を括弧に、スタンの長さ・壁とタワーの扱い・制圧の性質を 2 段落目に足す。以前あった「1秒に1スタック」「+15%」（推測）・「先にスタンを付けてから引き寄せる」（Fandom の言い回し）・「離れていれば踏み込む」（外した）は消した |

### 推測の値（MLBB の資料に無い）

| 項目 | 値 | 理由 |
|---|---|---|
| 鉤の射程 | 680 | 日本語クライアントの文に無い。他の近接スキル（マスターの射程 300）の 2 倍以上、通常攻撃の約 3.8 倍で、鉤がゴルムの個性になる長さ |
| 鉤の幅・速さ | 半幅 55・1800 | ヒーロー半径（55）と合わせて左右 110 の筋に届く細めの鉤。680 を 0.38 秒 |
| 引き寄せの所要時間（= スタンの長さ） | 0.30 秒 | 距離に関わらず一定（距離に比例させると近距離で遅く見える） |
| スキル2 の半径 | 260（術者の半径込み） | 文に無い。近接スキルの標準（190〜225）より少し広い自身中心の範囲 |
| 闘気のたまる速さ | 1 秒に 1 つ | 文に無い（10 個が約 15 秒） |
| 闘気 1 つ分 | +15% | 「最大 150%」÷ 10（Fandom の properties の 5〜50% は説明文と合わない） |
| アルティメットの射程 | 350（中心から対象の縁まで） | 文は「対象の敵ヒーロー」だけ。踏み込みが無いので、この距離のまま拘束する |
| アルティメットの連撃の時刻 | 拘束の 0.15 秒後から 0.30 秒ごと | 6 回が 1.8 秒の拘束に収まる等間隔 |

### 既知の差・リスク

- ロールは Velstria の「サポート」（MLBB はタンク）。汎用の味方回復をキットが置き換える。比べる相手（汎用のサポートの中央値）はタンクではない。
- 鉤のスタンは日本語クライアントの文に無い（Fandom の CC の頁が根拠）。強靭で縮み浄化で外れる点は MLBB の「引き寄せ」と違う。
- `DamageScaling.maxHealth` は「対象の最大 HP」なので、フランコの「自分の最大 HP の 4%」は `numbers` の値（`Kit.official(…, .maxHP)`）に含めている。装備で最大 HP が増えると `numbers` を再計算した時点で増える（発動時の値）。
- 鉤が最初に当たる「敵ユニット」にはミニオン・モンスターを含む。ボットは線上にミニオン・モンスターが居ると鉤を撃たないが、鉤の飛ぶ間に割り込まれて外すことはある。
- 引き寄せは壁を越える（調査: 「地形を無視して引き寄せる」）。ただし終点（ゴルムの前）が壁の中なら壁の手前で止まる。引き寄せの途中（0.3 秒）は壁の中を通って見える。
- アルティメットは射程 350 の相手を、その場で（離れたまま）拘束する。踏み込みを外したので、MLBB の実際の射程（未計測）より遠い・近いことがある。演出 `FX_H034` の冒頭のコメント（「踏み込み ≦0.13 秒」）は古い（演出の動きは対象の位置に出るので壊れない）。
- アルティメットの 6 回の合計に上限が無いので、闘気 10 個（+150%）の奥義は低レベル・低 HP の相手を一度で倒しうる（MLBB と同じ）。
- suppress は無敵の相手に付かない。拘束の途中で相手が無敵になっても、拘束は続き 6 回の打撃だけが入らない。
- フレームワークの追加: `KitRuntime.heroDied` に 1 行（術者が死んだら、その術者が掛けた suppress を全員から外す `Kit.releaseSuppress`）。鉤の引き寄せは `Kit.pullIgnoringTerrain`（`Systems/Kits/KitPull.swift`）。

### 公式の表へ（スキルの段階、2026-10-14）

| 項目 | 公式（日本語クライアント） | 変更前 | 変更後 |
|---|---|---|---|
| 段 | S1・S2 6 段、奥義 3 段 | S1・S2 4 段（Lv1 → Lv6 を線形補間）、奥義 3 段 | 6 / 6 / 3 段、表をそのまま（`Kit.level`） |
| S1 ダメージ | 400〜650（+100% 物理攻撃） | `(lerp(400, 650) + 1.0 × 攻撃 × 0.6) × 4.0 × hookScale 0.45` | `[400 … 650][Lv] + 1.0 × 合計の物理攻撃` |
| S1 CD / MP | 15.0〜11.0 / 135〜160 | 15 → 11・135 → 160 を 4 段へ補間（143.3 など） | 表 `[15.0, 14.2, 13.4, 12.6, 11.8, 11.0]` / `[135 … 160]` |
| S1 スタン | 文に無い（Fandom: スタン + 引き寄せ） | 引き寄せの 0.3 秒 | 同じ（Fandom を根拠に残す。説明文の「先にスタンを付けてから」は消した） |
| S2 ダメージ | 300〜450（+自身の最大 HP の 4%） | `lerp(300, 450) × 3.0 × shockScale 0.65 + 4%` | `[300 … 450][Lv] + 0.04 × 自身の最大 HP` |
| S2 CD / MP | 7.0〜4.5 / 40〜65 | 4 段へ補間 | 表 `[7.0, 6.5, 6.0, 5.5, 5.0, 4.5]` / `[40 … 65]` |
| 奥義 1 撃 | 50 / 60 / 70（+70% 物理攻撃）× 6 | `(lerp(50, 70) + 0.7 × 攻撃 × 0.6) × 2.6 × ultScale 1.0` | `[50, 60, 70][Lv] + 0.7 × 合計の物理攻撃` |
| 奥義の上限 | 無い | 6 回の合計（軽減前）が相手の最大 HP の 80%（`ultMaxHPFraction`） | 無い |
| 奥義の踏み込み | 無い | 離れていれば速さ 2600 で踏み込む（推測の追加） | 無い（その場で拘束。`movesCaster` = false でバインド中も撃てる） |
| 説明文の数値 | 公式の値 | 換算後の値（`{base}` = 基礎 × スロット倍率 × 換算） | 公式の値そのもの |

例（装備なし、Lv1 ・ rank 1）: S1 = 400 + 合計の物理攻撃、S2 = 300 + 最大 HP の 4%、奥義 1 撃 = 50 + 0.7 × 合計の物理攻撃。
テストは公式の表と等しいことを確かめる（`Kit_H034Tests`。予算「汎用の 0.8〜1.5 倍」と `lv = 1 + (rank−1)·5/3` の式は消した）。
1v1 の TTK・総当たりの勝率（バランスの帯）は全キットを統合した後に測り直す（帯の数値は変えていない）。
このキットだけを移した時点の値（Windows・`swift test` Debug、他のキットは旧換算のまま）: ロール代表（H001〜H006）との 1v1 は 16 / 18 勝、
TTK 12.4〜22.1 秒で **Lv12 vs H005 の 22.1 秒が帯（2.5〜22 秒）を 0.1 秒超える**（`testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives` が落ちる）。
総当たりの勝率は Lv6 85% / Lv12 79%（全体 82%、上限 85% の内）。

### 履歴（要約）

- 2026-10: クールダウンを MLBB の秒数に（全体の CD 倍率 0.5 と、鉤のランク 1 だけ 10 秒にする特例を廃止）。
- 2026-10: Fandom の現行のスキル表に CD・コスト・CC・挙動を合わせた（鉤のスタンを 1.0 → 0.3 秒 = 引き寄せの間だけ。無被弾の間に消費したら次の被弾まで闘気がたまらない注記）。マナを公式の値に（以前はマスターの 55 / 60 / 100）。
- 2026-10: 日本語クライアントの数値へ（奥義の Lv3 の CD 45 → 48 秒、説明文を日本語クライアントの文の構造に）。
- 2026-10-14: スキルの段階（上の表）。
