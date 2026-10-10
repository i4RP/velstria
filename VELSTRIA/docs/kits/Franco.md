# Franco (MLBB) - Kit Specification

**正は下の「公式（MLBB Fandom 現行）の数値」**（2026-10 に MediaWiki API で取得した Fandom の現行のスキル表）。それより上のウェブ調査と食い違う値は公式が優先する。

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

## 公式（MLBB Fandom 現行）の数値

`https://mobile-legends.fandom.com/api.php?action=parse&page=Franco&prop=wikitext&format=json` の `{{Ability}}` をそのまま転記。スキルのレベルは S1・S2 が Lv1〜6、アルティメットが Lv1〜3。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | Wasteland Force | Buff | 5 秒間ダメージを受けないと移動速度 +10%、毎秒最大 HP の 1% 回復、Wasteland Force を蓄積（最大 10）。次のスキルの発動ですべて消費し、そのスキルのダメージを最大 150% 増やす（1 つ 15%）。消費したあとは、もう一度ダメージを受けるまで蓄積が始まらない。※ Fandom の properties の「1 つあたり 5% / 10% / … / 50%」は説明文の「最大 150%」と合わない（Liquipedia も「最大 150%」）ので、説明文を採る |
| スキル1 | Iron Hook | CC・Damage | CD 15.0 / 14.2 / 13.4 / 12.6 / 11.8 / 11.0、マナ 135 / 140 / 145 / 150 / 155 / 160。指定方向へ鉄の鉤を放ち、最初に命中した敵ユニットに 400〜650（+100% 総物理攻撃）を与えて自分の元へ引き寄せる。鉤は先にスタンを付けてから引き寄せる。基礎 400 / 450 / 500 / 550 / 600 / 650 |
| スキル2 | Fury Shock | Slow | CD 7.0 / 6.5 / 6.0 / 5.5 / 5.0 / 4.5、マナ 40 / 45 / 50 / 55 / 60 / 65。周囲の敵に 300〜450 + 自分の最大 HP の 4% の物理ダメージ、70% 減速 1.5 秒。基礎 300 / 330 / 360 / 390 / 420 / 450 |
| アルティメット | Bloody Hunt | Burst・CC | CD 62 / 55 / 45（Liquipedia・以前の調査は 62 / 55 / 48。Fandom は 2023 年からずっと 45）、マナ 110 / 125 / 140。対象の敵ヒーローを 1.8 秒制圧し、その間に 6 回、1 回 50 / 60 / 70（+70% 総物理攻撃）。Franco が CC を受けると途中で終わる |

ランクの対応: S1/S2 は 4 段へ線形補間（ランク 1 = Lv1、最大ランク = Lv6）、アルティメットは公式の Lv1〜3 そのまま（CD は等差でないので表で引く）。

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
| パッシブ: 次のスキルの発動で闘気をすべて消費し、そのスキルのダメージが最大 +150% | ○ / △ | 1 つにつき +15%（公式の「最大 150%」÷ 10。Fandom の properties の 5〜50% は説明文と合わないので採らない）。スキルの発動時に消費（鉤が外れても、アルティメットでも）。スキル1・スキル2 はそのスキルのダメージ全体、アルティメットは 6 回すべてに掛かる。**無被弾の間に消費したら、次にダメージを受けるまで闘気はたまらない**（公式の注記。`ints[6]`）。説明文に「最大150%」（`{maxAmp}`）を書く |
| 闘気 10 個のアルティメットが一撃になるか（調査に無い） | △ | 6 回の合計（軽減前）を **相手の最大 HP の 80%** までに抑える（`Tune.ultMaxHPFraction`）。闘気 10 個・ランク 3 のアルティメットは Lv6 / Lv12 とも通常の相手（H001 / H003〜H005）に最大 HP の 49〜61%（軽減後。上限が効いたあとの値）で、上限は低レベルの相手や HP の低い相手に効く。闘気が少ないときは効かない |
| パッシブ: ダメージを受けると回復と加速が終わる。闘気の減衰の規則は不明 | △ | 被ダメで回復と加速は止まり、闘気は消えずに残る（次のスキルで使う）。5 秒の待ちのあいだは闘気も増えない。死亡で全部リセット |
| パッシブの演出 | ○ | 闘気が 1 つ増えるたびにパッシブの合図（`recipe(.passive).cast`）が出る（光輪を 1.1 秒にして重ね、たまるほど帯びて見える。スタック数で変わる演出は `FXSkillInfo` に個数が無いので不可）。スキルで闘気を使い切った直後は `FX_H034.passiveRelease`（消費した数に比例して鎖がはじけて閃く） |
| スキル1 Iron Hook: 直線の鉤。最初に当たった敵ユニットに 400 → 650（+100% 総物理攻撃）の物理ダメージ | ○ | 非貫通の直線弾（射程 680・幅 55・速度 1800）。最初に当たった敵 1 体（ヒーロー・ミニオン・モンスター）だけ。味方とタワー・構造物には当たらない。ダメージは**公式の表** `(lerp(400, 650) + 1.0 × 攻撃力 × 0.6) × スキル1 の倍率 4.0 × hookScale`（以前は汎用 S1 × 1.30） |
| スキル1: 敵を引き寄せる。引き寄せの間は動けない（スタン） | ○ | 鉤の `onHit` で `Kit.pullIgnoringTerrain`（`Systems/Kits/KitPull.swift`。所要 0.30 秒・端同士の隙間 10 で止まる）+ スタン。CC 無効の相手はダメージのみ、無敵の相手には何も起きない |
| スキル1: 壁・タワーを通り抜ける（地形を無視して引き寄せる） | ○ | 鉤（弾）は壁・タワーを素通りする（弾は構造物に当たらない仕様）。**引き寄せも壁を越える**: 終点（ゴルムの前、端同士の隙間 10）が歩ける場所なら、途中の壁を無視して直線で運ぶ（壁越しに当てた相手がゴルムの側でスタンする。以前は壁の向こう側で止まった）。終点が壁の中（ゴルムが壁に張り付いている）など歩けないときは、従来どおり壁の手前で止まる（`Kit.pull`）。壁が無ければ `Kit.pull` と同じ終点・同じ変位（テスト: 薄い壁を 1 枚置いた地形・実マップの壁を挟んだ 2 点・壁の無い場所での一致） |
| スキル1: 先にスタンを付けてから引き寄せる（公式の注記）。スタンは引き寄せの間だけ | ○（公式） | スタン = 引き寄せの 0.30 秒（`Tune.hookStun = hookPull`）。着いたらすぐ動ける。以前は味方が続けて攻撃するための猶予を足して 1.0 秒にしていた |
| スキル1 の鎖の見え方 | ○ | 鉤（`travel`）に追従する鎖が、鉤の先端を保ったまま手元へ向かって伸びる（長さ = 0.3 + 18t m。鉤の速さ 18m/s）。命中すると相手に追従する短い鎖（3m → 1m に縮む、引き寄せの 0.3 秒）が手元の向きに張られる（`hit`） |
| スキル1: 敵のエネルギーを減らす（旧版の記述・未確認） | × | 採用しない（調査でも未確認） |
| スキル1: CD 15.0 → 11.0、マナ 135 → 160、ダメージ 400 → 650 | ○（公式） | CD は公式の 15 → 11 秒（ランクで線形補間）。**マナは `HeroKit.cost` で 135 / 143.3 / 151.7 / 160**（以前はマスターの 55）。ダメージは上の公式の表 |
| スキル2 Fury Shock: 自身中心の範囲に 300 → 450 + 自分の最大 HP の 4% の物理ダメージ | ○ | 自身中心の円（`.selfAoE`・半径 260）。ダメージ = `lerp(300, 450) × スキル2 の倍率 3.0 × shockScale` + 自分の最大 HP の 4%（換算しない。Velstria の HP は MLBB と同じ桁。`numbers` に含める。`DamageScaling.maxHealth` は「対象の最大 HP」なので使わない）。以前は汎用 S2 × 0.98 + 4%。ミニオン・モンスターにも当たり、構造物には当たらない |
| スキル2: 70% 減速 1.5 秒 | ○ | `slow` の magnitude 0.70、1.5 秒（CC 無効の相手には入らない） |
| スキル2: 攻撃力低下（旧版の記述・未確認） | × | 採用しない |
| スキル2: CD 7.0 → 4.5、マナ 40 → 65 | ○（公式） | CD は公式の 7.0 → 4.5 秒（ランクで線形補間）。**マナは `HeroKit.cost` で 40 → 65**（以前はマスターの 60。S1 より S2 が安いという公式の大小も再現） |
| アルティメット Bloody Hunt: 単体指定の敵ヒーロー（射程は短い） | ○ | `.targetedBlink` 風の対象指定（`requiresTarget`、射程 350 = 術者の中心から対象の縁まで）。敵ヒーローだけが対象（ミニオン・無敵・視認外は不可）。居なければコスト・CD を消費せず失敗。指定ユニット・地点・向きもサポート、自動は HP + シールド最小 |
| アルティメット: 1.8 秒の suppress。浄化不可・CC 無効も無視、対象のスキルは中断される | ○ | `StatusKind.suppress`（`Kit.suppress`）。浄化で外れず、`ccImmune` でも入る。付与の時に前隙を取り消し、スキルのタイマー・突進はハード CC として中断される。無敵の相手には入らない（その場合はゴルムも固まらない） |
| アルティメット: 拘束の間に 6 回、1 回 50 / 60 / 70（+70% 総物理攻撃）を与える | ○ / △ | 拘束の 0.15, 0.45, ..., 1.65 秒に 6 回（`Kit.strikeSequence`）。1 回 = **公式の表** `(lerp(50, 70) + 0.7 × 攻撃力 × 0.6) × 奥義の倍率 2.6 × ultScale`（以前は汎用の式で出した奥義（ランク 1）× 2.1 ÷ 6 × 1 : 1.2 : 1.4）。サポートの汎用のアルティメットは回復でダメージ 0 なので予算は適用せず、勝率で ultScale を決めた |
| アルティメットの演出（6 回の叩きつけ） | ○ | 縛られている間の輪は `impact`（アルティメット発動時に相手の位置へ 1.8 秒）。`hit` は 1 発ごとの短い閃きと小さな火花だけ（`hitPerHit = true`）で、輪を 6 回重ねない |
| アルティメット: ゴルムの行動（調査: 不明。拘束されたら中断のはず） | △ | 拘束中のゴルムは動けず（`root`）、他のスキルも通常攻撃も出せない（`channeling` を表示用に付ける）。スタン・打ち上げ・suppress を受けると残りの連撃は取り消され、相手は解放される（クールダウンは戻らない）。ゴルムが倒れても相手は解放される（`KitRuntime.heroDied` → `Kit.releaseSuppress`）。相手が倒れたら終了 |
| アルティメットの射程（短い・不明） | △ | 射程 350 より離れた相手は指定できない。離れていれば発動で踏み込む（速さ 2600、端同士の隙間 10 で止まる。調査に無い追加）。到着した時に相手が 260 以上離れていた（ブリンクなど）・倒れていた・拘束できなかった場合は不発（コスト・CD は消費） |
| アルティメット: CD 62 / 55 / 45、マナ 110 / 125 / 140 | ○（公式） | CD は Fandom の現行の **62 / 55 / 45 秒**（等差でないので表 `Tune.ultCooldowns` で引く。Liquipedia・以前の調査・実装は 62 / 55 / 48）。**マナは `HeroKit.cost` で 110 / 125 / 140**（以前はマスターの 100） |
| ボット | ○ | 鉤（スキル1）: 狙う敵ヒーローより手前の線上（幅 + 半径以内）にミニオン・モンスターが居れば撃たない（鉤は最初に当たった敵を引くため。手前の別の敵ヒーローは引けるので撃つ）。アルティメット（狩猟鎖獄）: 射程内の敵ヒーローが「HP 70% 未満」「鉤（`kit.H034.hookStun`）でスタン中」「近く（800 以内）に味方ヒーローが居る」のいずれかなら、汎用の関門（倒せる・2 体）を飛び越えて撃つ（`.castNow`）。鉤 → アルティメットの連携。それ以外は汎用の判断、射程外は見送り |
| 基本の通常攻撃（近接単体、射程 1.8） | ○ | 汎用のまま（射程 150） |
| スキルのタグ（UI） | ○ / △ | パッシブ `buff`、スキル1 `disrupt burst`（公式 CC・Damage。Damage に当たるキーが無いので「バースト」で近似）、スキル2 `slow`、アルティメット `burst disrupt`（`KitText.tags` / `HeroKits.tags`） |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| 鉤の射程 | 680 | 調査に無い。他の近接スキル（マスターの射程 300）の 2 倍以上、通常攻撃（150）の 4 倍以上で、鉤がゴルムの個性になる長さ。ツールチップは近接射程の約 4.5 倍 |
| 鉤の幅・速さ | 半幅 55・1800 | ヒーロー半径（55）と合わせて左右 110 の筋に届く細めの鉤。汎用の直線弾（1600）より少し速い（680 を 0.38 秒） |
| 引き寄せの所要時間 | 0.30 秒 | 距離に関わらず一定（距離に比例させると近距離で遅く見える） |
| 鉤のランク 1 のクールダウン | 15 秒（MLBB と同じ） | 全体の CD が半分だったころは 10 秒（× 0.5）にしていた。上の表 |
| スキル2 の半径 | 260（術者の半径込み） | 調査に無い。近接スキルの標準（190〜225）より少し広い自身中心の範囲。ツールチップは近接射程の約 1.7 倍 |
| 闘気のたまる速さ | 1 秒に 1 つ | 調査に無い（10 個が約 15 秒） |
| 闘気 1 つ分 | +15% | 調査の「推定」。最大で +150% |
| アルティメットの上限 | 6 回の合計（軽減前）が相手の最大 HP の 80% まで | 闘気 10 個の +150% が一撃にならないための安全弁 |
| アルティメットの発動の流れ | 踏み込み → 拘束 → 6 回 | 調査は「単体指定・短射程」だけ。連撃が届くように拘束の前に踏み込む |
| 数値の換算 | `hookScale` / `shockScale`（最大 HP の 4% には掛けない）/ `ultScale` | 公式の表（ランクで補間 + 攻撃力係数）を sim の通常の式 × スロット倍率に通したあとに掛ける。値は下の「公式の数値へ（2026-10）」 |
| 説明文の数値 | パッシブ x0 = 待ち（5 秒）、x1 = 加速 %、x2 = 回復 %、x3 = 闘気 1 つの %、`{hits}` = 最大の個数、`{maxAmp}` = 最大の上乗せ %、`{stackInterval}` = 闘気の間隔 / 各スキルの `{reachMult}` | `KitText` のトークンに sim の数値を入れる |

### 検証した 1v1 の目安

- ロール代表（H001〜H006）との 1v1 は Lv 1 / 6 / 12 とも TTK 2.5〜22 秒（CD が半分だったころの帯は 2.5〜15 秒）に収まる。
- `KitBalanceTests`（Release、`BalanceHarness`）の勝率（総当たり・両陣営 x 開始距離 x 種の平均、%）。ロール「サポート」の汎用ヒーローの中央値との比較:

  | | Lv1 | Lv6 | Lv12 |
  |---|---|---|---|
  | 変更前（鉤のクールダウン 15 → 11 秒） | 2.0（中央値 36.4）| 31.6（27.3）| 50.5（43.4）|
  | 今回 | 32.8（中央値 38.9）| 34.6（31.8）| 52.0（44.2）|

  開幕 3 秒の瞬間火力の比（同ロール中央値に対する倍率、報告のみ）: 変更前 1.11 / 1.38 / 1.25 → 今回 1.11 / 1.38 / 1.25（変わらない）。

### 既知の差・リスク

- スキルのマナは公式の値（S1 135 → 160、S2 40 → 65、アルティメット 110 / 125 / 140）を `HeroKit.cost` で適用する（マスターデータの 55 / 60 / 100 は使わない）。最大マナ 460（マスター）に対して鉤 1 回 135 は重く、連発すると足りなくなる。
- `DamageScaling.maxHealth` は「対象の最大 HP」なので、フランコの「自分の最大 HP の 4%」は `numbers` の固定値に含めている。装備で最大 HP が増えると `numbers` を再計算した時点で増える（発動時の値）。
- 鉤が最初に当たる「敵ユニット」にはミニオン・モンスターを含む。ミニオンの波の後ろの敵ヒーローは狙えない（調査の記述どおり）。ボットは線上にミニオン・モンスターが居ると鉤を撃たなくなった（上の表）が、鉤の飛ぶ間に割り込まれて外すことはある。
- 引き寄せは壁を越える（調査: 「地形を無視して引き寄せる」）。ただし終点（ゴルムの前）が壁の中なら壁の手前で止まる（壁の中には入れない）。引き寄せの途中（0.3 秒）は壁の中を通って見える。
- アルティメットの踏み込みは `MovementSystem.dash`（壁の手前で止まる）。壁越しに指定した相手には届かず不発になる。
- suppress は無敵の相手に付かない。拘束の途中で相手が無敵になっても、拘束は続き 6 回の打撃だけが入らない。
- 鎖の演出は鉤の先端に追従する描画（`FX_H034`）。着弾後も鎖の手前側が 0.3 秒ほど伸び続ける（鉤の先端は着弾点に残る）ので、近距離で当たると手元の後ろへ鎖が少しはみ出して見える。App は Windows で書いたため CI 未実行。
- 鉤のクールダウンは MLBB と同じ 15 → 11 秒（以前のランク 1 だけ 10 秒にする特例は外した）。
- フレームワークの追加: `KitRuntime.heroDied` に 1 行（術者が死んだら、その術者が掛けた suppress を全員から外す `Kit.releaseSuppress`）。鉤の引き寄せは新しい部品 `Kit.pullIgnoringTerrain`（`Systems/Kits/KitPull.swift`）。それ以外の共有ファイルは変えていない。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 と、鉤のランク 1 だけ 10 秒にする特例を廃止（鉤 15 → 11 秒、スキル2 7 → 4.5 秒、アルティメット 62 / 55 / 48 秒）。数値は変えていない。
- `KitBalanceTests`（サポート中央値との差）: 変更前 −7.8 / +4.0 / +7.8 → 変更後 −17.3 / +12.8 / +13.0 pt（Lv1 は帯 45 pt の内）。

### 公式の数値へ（2026-10）

Fandom の現行のスキル表（上の「公式（MLBB Fandom 現行）の数値」）に、クールダウン・コスト・ダメージの表・CC・挙動を合わせた（H029 ボルグと同じ方法）。

| 項目 | 公式 | 変更前 | 変更後 |
|---|---|---|---|
| パッシブ | 5 秒無被弾で +10% 移動速度・毎秒 1%、最大 10、次のスキルで最大 +150%。消費したら次の被弾まで蓄積しない | 同じ（消費後もたまり続けた） | 同じ + **無被弾の間に消費したら次にダメージを受けるまでたまらない** |
| S1 クールダウン | 15.0 → 11.0 | 15 → 11 | 同じ |
| S1 コスト | 135 → 160 | マスター 55 | 135 / 143.3 / 151.7 / 160 |
| S1 ダメージ | 400 → 650（+100%） | 汎用 S1 × 1.30（Lv1 756 / Lv12 1377） | `(400 → 650 + 1.0 × 攻撃 × 0.6) × 4.0 × 0.45`（Lv1 854 / Lv12 1378） |
| S1 スタン | 先にスタン、それから引き寄せ（引き寄せの間だけ） | 1.0 秒（引き寄せ 0.3 秒 + 0.7 秒） | 0.3 秒（引き寄せの間だけ） |
| S2 クールダウン・コスト | 7.0 → 4.5・40 → 65 | 7 → 4.5・マスター 60 | 7 → 4.5・40 → 65 |
| S2 ダメージ | 300 → 450 + 最大 HP 4%、70% 減速 1.5 秒 | 汎用 S2 × 0.98 + 4%（Lv1 648 / Lv12 1177） | `(300 → 450) × 3.0 × 0.65` + 4%（Lv1 691 / Lv12 1067）、減速同じ |
| 奥義 クールダウン | 62 / 55 / 45（Liquipedia 62 / 55 / 48） | 62 / 55 / 48 | 62 / 55 / 45 |
| 奥義 コスト | 110 / 125 / 140 | マスター 100 | 110 / 125 / 140 |
| 奥義 1 撃 | 50 / 60 / 70（+70%）× 6、suppress 1.8 秒 | 汎用の式（ランク 1）× 2.1 ÷ 6 × 1 : 1.2 : 1.4（ランク 3・Lv12 377） | `(50 → 70 + 0.7 × 攻撃 × 0.6) × 2.6 × 1.0`（ランク 3・Lv12 392）、suppress 同じ |
| タグ | Buff / CC・Damage / Slow / Burst・CC | なし | `buff` / `disrupt burst`（Damage のキーが無いので「バースト」）/ `slow` / `burst disrupt` |
| 説明文 | — | 独自の文 | 公式の文の構造（`{base}(+{atkPct}%物理攻撃)` は換算後の値） |

（ダメージの例は Lv1 = ランク 1、Lv12 = S1/S2 ランク 4。攻撃力・最大 HP は装備なしの値。）
換算（`hookScale` 0.45 / `shockScale` 0.65 / `ultScale` 1.0）は勝率で決めた。予算（汎用の何倍か）は鉤 1.30〜1.47（上限 1.3 を少し超える。テストの上限は 1.5）、S2 1.05〜1.25。
スタンが公式の「引き寄せの間だけ」になって、Lv1（鉤しか無い決闘）が −25 pt まで落ちた（予算内の 0.39 のとき）。鉤の換算を 0.45 に上げて戻した（0.5 で −5 pt、0.6 で −2 pt）。S2 とアルティメットは Lv6 / Lv12 にとても効く（0.8 / 1.1 で Lv6 +32 pt、0.9 / 1.3 で +53 pt）。

`KitBalanceTests`（Release。サポート中央値との差、pt）:

| | Lv1 | Lv6 | Lv12 |
|---|---|---|---|
| 変更前（クールダウンを MLBB の秒数にした直後） | −17.3 | +12.8 | +13.0 |
| 公式の表へ置き換えた直後（換算 0.39 / 0.65 / 0.90） | −25.4 | +3.9 | −15.8 |
| **今回**（換算 0.45 / 0.65 / 1.0） | −5.7（26.3% / 中央値 31.9） | +9.7（37.4% / 27.7） | −8.0（32.3% / 40.3） |

開幕 3 秒の瞬間火力の比（同ロール中央値に対する倍率、報告のみ）: 置き換え直後 1.09 / 1.39 / 1.33 → 今回 1.20 / 1.55 / 1.49。闘気 5 個以上のアルティメットは、Lv12 の相手には 6 回の合計の上限（最大 HP の 80%）に届く（`testStacksAreConsumedEvenWhenTheHookMissesAndByTheHookAndUltimate`）。Release の全テスト 981 件・失敗 0（スキップ 6）。
