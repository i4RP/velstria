# Franco (MLBB) - Kit Specification

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

## Velstria 実装対応表

H034 鎖鉤のゴルム（サポート・近接 150・Mana）= Velstria 版の Franco。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H034.swift`
（追加プリミティブ `KitGormLock.swift`）、テスト: `Tests/VelstriaCoreTests/Kits/Kit_H034Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H034.swift`。
スロットは上の調査の順に割り当てる（スキル1 = Iron Hook「鎖鉤」、スキル2 = Fury Shock「鉄鎖旋」、アルティメット = Bloody Hunt「狩猟鎖獄」、パッシブ = Wasteland Force「鉄鎖の執念」。名前はマスターデータのもの）。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（射程・幅・半径など）は下の「選んだ値」に書いた。
ダメージは Velstria 全体の係数（`Balance.Skills`）に合わせた換算で、MLBB の数値そのままではない。クールダウンは MLBB の秒数そのまま（6 段のランクを Velstria の 4 段・奥義 3 段へ線形補間。全体倍率 `cooldownScale` は 1.0）。
このキットはロール「サポート」の汎用の味方回復パッシブと、アルティメットの味方全体回復を置き換える（ゴルムは回復役ではなく鉤の起点役）。
ツールチップの距離は単位の無い数字を出さず、近接攻撃の射程（150）に対する倍率で書く（`{reachMult}`: 鎖鉤 約 4.5 倍、鉄鎖旋 約 1.7 倍、狩猟鎖獄 約 2.3 倍）。

### 対応表（○ = 実装、△ = 簡略化・調整、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 近接・マナ・基本ステータス（HP 2600 ほか） | ○ | `master_runtime.json` の H034 のまま（近接 150・Mana）。ステータスは変えない |
| パッシブ: 5 秒ダメージを受けないと移動速度 +10%・毎秒最大 HP の 1% 回復 | ○ | 被ダメ（シールドが吸収した分も数える）のたびに待ち（`timers[0]`）を 5 秒に戻す。待ちが 0 の間は `speedBoost` 0.10（被ダメで外す無期限のステータス）と、0.5 秒ごとに最大 HP の 0.5% の回復（合計で毎秒 1%。回復量スコア・回復強化の対象外） |
| パッシブ: 闘気（Wasteland Force）が最大 10 たまる | △ | 調査に「たまる速さ」が無いので無被弾の間 1 秒に 1 つ（10 個で 15 秒）。HUD はパッシブのバッジに個数を出す。説明文は `Tune.stackInterval` を `{stackInterval}` で引く |
| パッシブ: 次のスキルの発動で闘気をすべて消費し、そのスキルのダメージが最大 +150% | △ | 1 つにつき +15%（調査: 「推定、未確認」）。スキルの発動時に消費（鉤が外れても、アルティメットでも）。スキル1・スキル2 はそのスキルのダメージ全体、アルティメットは 6 回すべてに掛かる。説明文に「最大+150%」（`{maxAmp}`）を書く |
| 闘気 10 個のアルティメットが一撃になるか（調査に無い） | △ | 6 回の合計（軽減前）を **相手の最大 HP の 80%** までに抑える（`Tune.ultMaxHPFraction`）。闘気 10 個・ランク 3 のアルティメットは Lv6 / Lv12 とも通常の相手（H001 / H003〜H005）に最大 HP の 49〜61%（軽減後。上限が効いたあとの値）で、上限は低レベルの相手や HP の低い相手に効く。闘気が少ないときは効かない |
| パッシブ: ダメージを受けると回復と加速が終わる。闘気の減衰の規則は不明 | △ | 被ダメで回復と加速は止まり、闘気は消えずに残る（次のスキルで使う）。5 秒の待ちのあいだは闘気も増えない。死亡で全部リセット |
| パッシブの演出 | ○ | 闘気が 1 つ増えるたびにパッシブの合図（`recipe(.passive).cast`）が出る（光輪を 1.1 秒にして重ね、たまるほど帯びて見える。スタック数で変わる演出は `FXSkillInfo` に個数が無いので不可）。スキルで闘気を使い切った直後は `FX_H034.passiveRelease`（消費した数に比例して鎖がはじけて閃く） |
| スキル1 Iron Hook: 直線の鉤。最初に当たった敵ユニットに 400（+100% 攻撃力）の物理ダメージ | ○ | 非貫通の直線弾（射程 680・幅 55・速度 1800）。最初に当たった敵 1 体（ヒーロー・ミニオン・モンスター）だけ。味方とタワー・構造物には当たらない。ダメージは汎用 S1（扇形）の 1.30 倍（単体 + 引き寄せ + スタン） |
| スキル1: 敵を引き寄せる。引き寄せの間は動けない（スタン） | ○ | `HitEffect.pullToOwner`（所要 0.30 秒・端同士の隙間 10 で止まる。壁の手前で止まり、壁の中へは入らない）+ スタン。CC 無効の相手はダメージのみ、無敵の相手には何も起きない |
| スキル1: 壁・タワーを通り抜ける | ○ | 鉤（弾）は壁・タワーを素通りする（弾は構造物に当たらない仕様）。引き寄せだけは壁で止める（テスト: 壁を挟んだ 2 点）。**鉤の軌道だけが壁を越える** もので、壁の向こうに当てても引き寄せは壁の手前までなので見送りのまま（G3: 地形の扱いは共有の移動処理で、キット側で足すには大きい） |
| スキル1: スタンの長さは引き寄せの間だけ（不明） | △ | 命中から 1.0 秒（引き寄せ 0.30 秒 + 着いてから 0.7 秒）。味方が続けて攻撃するための猶予を足した調整 |
| スキル1 の鎖の見え方 | ○ | 鉤（`travel`）に追従する鎖が、鉤の先端を保ったまま手元へ向かって伸びる（長さ = 0.3 + 18t m。鉤の速さ 18m/s）。命中すると相手に追従する短い鎖（3m → 1m に縮む、引き寄せの 0.3 秒）が手元の向きに張られる（`hit`） |
| スキル1: 敵のエネルギーを減らす（旧版の記述・未確認） | × | 採用しない（調査でも未確認） |
| スキル1: CD 15.0 → 11.0、マナ 135 → 160、ダメージ 400 → 650 | △ | CD は 15 → 11 秒をランクで線形補間 × `cooldownScale`（0.5）。**ランク 1 だけは 10 秒**（`Tune.hookRank1Cooldown`。Lv1 の 1v1 は鉤しか持たず、15 秒のままだと勝率が 0〜2% まで落ちるため。ランク 2 以降は変えないので Lv6 / Lv12 は動かない）。ランクは 4 段（元は 6 段）で、ダメージの伸びは汎用の +30%/ランク。コストはマスターデータ（`cost`）のまま |
| スキル2 Fury Shock: 自身中心の範囲に 300 + 自分の最大 HP の 4% の物理ダメージ | ○ | 自身中心の円（`.selfAoE`・半径 260）。ダメージ = 汎用 S2 × 0.98 + 自分の最大 HP の 4%（`numbers` に含める。`DamageScaling.maxHealth` は「対象の最大 HP」なので使わない）。汎用の 1.1〜1.3 倍。ミニオン・モンスターにも当たり、構造物には当たらない |
| スキル2: 70% 減速 1.5 秒 | ○ | `slow` の magnitude 0.70、1.5 秒（CC 無効の相手には入らない） |
| スキル2: 攻撃力低下（旧版の記述・未確認） | × | 採用しない |
| スキル2: CD 7.0 → 4.5、マナ 40 → 65 | △ | CD は 7.0 → 4.5 秒をランクで線形補間 × 0.5。コストはマスターのまま（S1 より S2 が安いという元の大小は再現できない） |
| アルティメット Bloody Hunt: 単体指定の敵ヒーロー（射程は短い） | ○ | `.targetedBlink` 風の対象指定（`requiresTarget`、射程 350 = 術者の中心から対象の縁まで）。敵ヒーローだけが対象（ミニオン・無敵・視認外は不可）。居なければコスト・CD を消費せず失敗。指定ユニット・地点・向きもサポート、自動は HP + シールド最小 |
| アルティメット: 1.8 秒の suppress。浄化不可・CC 無効も無視、対象のスキルは中断される | ○ | `StatusKind.suppress`（`Kit.suppress`）。浄化で外れず、`ccImmune` でも入る。付与の時に前隙を取り消し、スキルのタイマー・突進はハード CC として中断される。無敵の相手には入らない（その場合はゴルムも固まらない） |
| アルティメット: 拘束の間に 6 回、1 回 50（+70% 攻撃力）を与える | △ | 拘束の 0.15, 0.45, ..., 1.65 秒に 6 回（`Kit.strikeSequence`）。6 回の合計 = 汎用の式で出したアルティメット（ランク 1）のダメージ × 2.1、ランクの伸びは調査の 50 / 60 / 70 に合わせて 1 : 1.2 : 1.4。サポートの汎用のアルティメットは回復でダメージ 0 なので、同じ式で出した値を目安にし、クールダウンが汎用（34 秒 × 0.5）より長いぶん（62 → 48 秒 × 0.5）を補った（1 秒あたりでは汎用の 1.0〜1.3 倍） |
| アルティメットの演出（6 回の叩きつけ） | ○ | 縛られている間の輪は `impact`（アルティメット発動時に相手の位置へ 1.8 秒）。`hit` は 1 発ごとの短い閃きと小さな火花だけ（`hitPerHit = true`）で、輪を 6 回重ねない |
| アルティメット: ゴルムの行動（調査: 不明。拘束されたら中断のはず） | △ | 拘束中のゴルムは動けず（`root`）、他のスキルも通常攻撃も出せない（`channeling` を表示用に付ける）。スタン・打ち上げ・suppress を受けると残りの連撃は取り消され、相手は解放される（クールダウンは戻らない）。ゴルムが倒れても相手は解放される（`KitRuntime.heroDied` → `Kit.releaseSuppress`）。相手が倒れたら終了 |
| アルティメットの射程（短い・不明） | △ | 射程 350 より離れた相手は指定できない。離れていれば発動で踏み込む（速さ 2600、端同士の隙間 10 で止まる。調査に無い追加）。到着した時に相手が 260 以上離れていた（ブリンクなど）・倒れていた・拘束できなかった場合は不発（コスト・CD は消費） |
| アルティメット: CD 62 / 55 / 48、マナ 110 / 125 / 140 | △ | CD は 62 → 48 秒を 3 ランクで線形 × 0.5。コストはマスターのまま |
| ボット | ○ | 鉤（スキル1）: 狙う敵ヒーローより手前の線上（幅 + 半径以内）にミニオン・モンスターが居れば撃たない（鉤は最初に当たった敵を引くため。手前の別の敵ヒーローは引けるので撃つ）。アルティメット（狩猟鎖獄）: 射程内の敵ヒーローが「HP 70% 未満」「鉤（`kit.H034.hookStun`）でスタン中」「近く（800 以内）に味方ヒーローが居る」のいずれかなら、汎用の関門（倒せる・2 体）を飛び越えて撃つ（`.castNow`）。鉤 → アルティメットの連携。それ以外は汎用の判断、射程外は見送り |
| 基本の通常攻撃（近接単体、射程 1.8） | ○ | 汎用のまま（射程 150） |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| 鉤の射程 | 680 | 調査に無い。他の近接スキル（マスターの射程 300）の 2 倍以上、通常攻撃（150）の 4 倍以上で、鉤がゴルムの個性になる長さ。ツールチップは近接射程の約 4.5 倍 |
| 鉤の幅・速さ | 半幅 55・1800 | ヒーロー半径（55）と合わせて左右 110 の筋に届く細めの鉤。汎用の直線弾（1600）より少し速い（680 を 0.38 秒） |
| 引き寄せの所要時間 | 0.30 秒 | 距離に関わらず一定（距離に比例させると近距離で遅く見える） |
| 鉤のランク 1 のクールダウン | 10 秒（× 0.5） | 上の表。ランク 1 → 2 で CD が一度延びる（10 → 13.7 秒）が、ダメージが +30% 伸びる |
| スキル2 の半径 | 260（術者の半径込み） | 調査に無い。近接スキルの標準（190〜225）より少し広い自身中心の範囲。ツールチップは近接射程の約 1.7 倍 |
| 闘気のたまる速さ | 1 秒に 1 つ | 調査に無い（10 個が約 15 秒） |
| 闘気 1 つ分 | +15% | 調査の「推定」。最大で +150% |
| アルティメットの上限 | 6 回の合計（軽減前）が相手の最大 HP の 80% まで | 闘気 10 個の +150% が一撃にならないための安全弁 |
| アルティメットの発動の流れ | 踏み込み → 拘束 → 6 回 | 調査は「単体指定・短射程」だけ。連撃が届くように拘束の前に踏み込む |
| 数値の換算 | スキル1 = 汎用 S1 × 1.30、スキル2 = 汎用 S2 × 0.98 + 最大 HP の 4%、アルティメット = 目安 × 2.1（× 1 : 1.2 : 1.4） | 1 スロットの単体ダメージを汎用の 0.8〜1.3 倍に収める |
| 説明文の数値 | パッシブ x0 = 待ち（5 秒）、x1 = 加速 %、x2 = 回復 %、x3 = 闘気 1 つの %、`{hits}` = 最大の個数、`{maxAmp}` = 最大の上乗せ %、`{stackInterval}` = 闘気の間隔 / 各スキルの `{reachMult}` | `KitText` のトークンに sim の数値を入れる |

### 検証した 1v1 の目安

- ロール代表（H001〜H006）との 1v1 は Lv 1 / 6 / 12 とも TTK 2.5〜15 秒に収まる。
- `KitBalanceTests`（Release、`BalanceHarness`）の勝率（総当たり・両陣営 x 開始距離 x 種の平均、%）。ロール「サポート」の汎用ヒーローの中央値との比較:

  | | Lv1 | Lv6 | Lv12 |
  |---|---|---|---|
  | 変更前（鉤のクールダウン 15 → 11 秒） | 2.0（中央値 36.4）| 31.6（27.3）| 50.5（43.4）|
  | 今回 | 32.8（中央値 38.9）| 34.6（31.8）| 52.0（44.2）|

  開幕 3 秒の瞬間火力の比（同ロール中央値に対する倍率、報告のみ）: 変更前 1.11 / 1.38 / 1.25 → 今回 1.11 / 1.38 / 1.25（変わらない）。

### 既知の差・リスク

- スキルのマナ（コスト）の相対関係（S1 135〜160、S2 40〜65、アルティメット 110〜140）は再現できない（マスターデータ固定。S1 55・S2 60・アルティメット 100）。
- `DamageScaling.maxHealth` は「対象の最大 HP」なので、フランコの「自分の最大 HP の 4%」は `numbers` の固定値に含めている。装備で最大 HP が増えると `numbers` を再計算した時点で増える（発動時の値）。
- 鉤が最初に当たる「敵ユニット」にはミニオン・モンスターを含む。ミニオンの波の後ろの敵ヒーローは狙えない（調査の記述どおり）。ボットは線上にミニオン・モンスターが居ると鉤を撃たなくなった（上の表）が、鉤の飛ぶ間に割り込まれて外すことはある。
- 引き寄せは壁を越えない（調査: 「地形を無視して引き寄せる」とあるが、「壁の中に入れない」を優先）。壁の向こうに当てた鉤は、壁の手前の位置までしか引き寄せられない（見送り）。
- アルティメットの踏み込みは `MovementSystem.dash`（壁の手前で止まる）。壁越しに指定した相手には届かず不発になる。
- suppress は無敵の相手に付かない。拘束の途中で相手が無敵になっても、拘束は続き 6 回の打撃だけが入らない。
- 鎖の演出は鉤の先端に追従する描画（`FX_H034`）。着弾後も鎖の手前側が 0.3 秒ほど伸び続ける（鉤の先端は着弾点に残る）ので、近距離で当たると手元の後ろへ鎖が少しはみ出して見える。App は Windows で書いたため CI 未実行。
- ランク 1 の鉤のクールダウンだけが短い（10 秒）。スキル詳細のランク表では 1 → 2 で一度延びて見える。
- フレームワークの追加: `KitRuntime.heroDied` に 1 行（術者が死んだら、その術者が掛けた suppress を全員から外す `Kit.releaseSuppress`）。それ以外の共有ファイルは変えていない。
