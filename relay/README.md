# velstria-relay（インターネット対戦の中継）

違う場所・違う Wi-Fi / モバイル回線の端末同士で、オンライン対戦（リッスンサーバー方式: ホストの iPhone が権威シミュレーション）を
遊べるようにするための中継サーバー。Cloudflare Workers + Durable Objects で動く。

- **中身を解釈しない土管**。ゲームの手順（アプリの `App/Online/OnlineProtocol.swift` の `OnlineMessage`、`OnlineFramer` の
  4 バイト長さ区切り JSON）はそのまま流す。中継はホストと参加者の間でバイト列を付け替えるだけ。
- **対戦の中身は保存しない**。対戦データ（payload）は保存もログ出力もしない。Workers Logs も無効（`wrangler.jsonc` の `observability`）。
  部屋について保存するのは参加者番号の採番（数値 1 つ）だけで、ホストが去ってから 10 分で消す。
  フレンドの受信箱は、鍵のハッシュ・最後に繋いだ日時・預かった申請を保存する（下の「フレンドの受信箱」。本人が消せる、1 年繋がなければ自動で消える）。
  ランクは、鍵のハッシュ・ランク・直近 50 試合の結果を保存する（下の「ランク」。本人が消せる）。
- 部屋コード 1 つ = Durable Object（`RelayRoom`）1 つ。WebSocket Hibernation API で、通信の無い間は DO を眠らせる（課金・メモリを使わない）。
- LAN（Bonjour / IP:ポート直結）は今まで通りアプリに残る。ホストは LAN の待ち受けと中継の両方で参加者を受け入れる。

配備先: **`wss://velstria-relay.shoei0205.workers.dev`**（アプリの `OnlineRelayConfig.defaultBaseURL`）

## 構成

| パス | 内容 |
|---|---|
| `src/index.ts` | Worker（入口の検証）と Durable Object `RelayRoom`（中継の本体） |
| `src/inbox.ts` | Durable Object `FriendInbox`（フレンドの受信箱。下の「フレンドの受信箱」） |
| `src/rank.ts` | Durable Object `RankAccount`（アカウントごとのランクと規則の計算。`POST /v1/rank/…`。下の「ランク」） |
| `src/directory.ts` | Durable Object `Directory`（全体で 1 つ。公開の名刺・ランキングの表・運営からのメール。下の「名刺・ランキング・メール」） |
| `src/account.ts` | Durable Object `CloudAccount`（アカウント: クラウド保存・パスワード・Game Center の連携）と `GameCenterIndex`（teamPlayerID → コード）、Game Center の署名の確かめ。下の「アカウント」 |
| `wrangler.jsonc` | Worker 名 `velstria-relay`、DO の束縛 `RELAY_ROOM` / `FRIEND_INBOX` / `RANK_ACCOUNT` / `DIRECTORY` / `CLOUD_ACCOUNT` / `GAME_CENTER_INDEX`、SQLite バックエンドの移行 `v1`〜`v5` |
| `test/relay.test.mjs` | 結合テスト（Node の組み込みテストランナー + Node の WebSocket。本物の Worker を相手にする）と、ランクの規則・シーズンの単体テスト |
| `../.github/workflows/relay.yml` | `relay/**` が変わった時に CI（ubuntu）でテストを流す（配備はしない） |

## 手順（プロトコル v1）

### HTTP

| 要求 | 応答 |
|---|---|
| `GET /v1/health` | 200 `{"ok":true,"relay":1}` |
| `GET /v1/rooms/<CODE>?role=host\|guest&rv=1`（WebSocket Upgrade） | 101（下の close コードで断る時も、いったん受け入れてから閉じる） |
| `GET /v1/inbox/<FRIENDCODE>?key=<KEY>&rv=1`（WebSocket Upgrade） | 101（下の「フレンドの受信箱」）。コードが規則に合わなければ 400 `bad_friend_code` |
| `POST /v1/inbox/<FRIENDCODE>/erase`（本文 `{"key":"<KEY>"}`） | 200 `{"ok":true,"result":"erased"\|"none"}` / 403 `inbox_taken` / 400 / 405（下の「受信箱の消去」） |
| `POST /v1/rank/<FRIENDCODE>/get\|seed\|match\|erase`（本文 `{"key":"<KEY>",…}`） | 200 `{"ok":true,"state":{…}}` / 400 / 403 / 405（下の「ランク」） |
| 部屋コードが規則に合わない | 400 `bad_room_code` |
| `role` が `host` / `guest` 以外 | 400 `bad_role` |
| WebSocket Upgrade でない | 426 |
| 知らない道 | 404 |

調べる順序: 道 → 部屋コード（400）→ role（400）→ Upgrade（426）→ rv（4010）→ 部屋（DO）。

### 部屋コード

6 文字。英大文字と数字から紛らわしい `I` `L` `O` `0` `1` を除いた 31 文字 `ABCDEFGHJKMNPQRSTUVWXYZ23456789`。
正規表現 `^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$`。コードはアプリが作る（中継は小文字・空白の正規化をしない。アプリ側で揃えてから繋ぐ）。

### 部屋への出入り

- **ホスト**（`role=host`）: 部屋にホストが既にいれば 4009 `room_taken`（ホストはコードを作り直して再試行する）。
  ただし URL に `hk=<再接続の鍵>`（`^[A-Za-z0-9_-]{16,64}$`。ホストの端末が部屋ごとに乱数で作り、参加者には渡さない）があり、いるホストが同じ鍵で入っていれば、
  切れたのに中継がまだ気づいていない前のホストの接続（携帯回線の切り替えなどで起きる）と**入れ替わる**: 前の接続は 4011 `host_replaced`、
  前の接続の参加者は 4001 `host_left` で閉じ、新しいホストを受け入れる（参加者は同じコードで入り直す）。鍵が無い・違う・形式が不正なら 4009 のまま。
- **参加者**（`role=guest`）: ホストがいなければ 4004 `no_room`。参加者が既に 32 人なら 4008 `room_full`。
  受け入れたら部屋内で一意の `guestId`（1 から増える u32）を振り、ホストへ `GUEST_OPEN` を送る。
  `guestId` は部屋の寿命の間は再利用しない（抜けた参加者の番号も、ホストが去って同じコードで戻った後も、続きから振る）。
  DO の SQLite に置くので、ハイバネーションをまたいでも続く。
- `rv`（中継の版数）が 1 でなければ 4010 `relay_version`（ホスト・参加者とも。DO は起こさない）。
- ホストが閉じた・切れたら、そのホストの参加者を全員 4001 `host_left` で閉じる。
- 部屋の寿命: ホストが去ってから 10 分、誰も繋がらなければ採番の記録を消す（その後の同じコードは新しい部屋）。

### バイナリの形式（ビッグエンディアン）

| 向き | 種類 | 形 | 意味 |
|---|---|---|---|
| サーバー → ホスト | `0x10 GUEST_OPEN` | `[u8 0x10][u32 guestId]` | 参加者を受け入れた |
| サーバー → ホスト | `0x11 GUEST_DATA` | `[u8 0x11][u32 guestId][payload...]` | 参加者から届いたバイナリ |
| サーバー → ホスト | `0x12 GUEST_CLOSE` | `[u8 0x12][u32 guestId]` | 参加者がいなくなった |
| ホスト → サーバー | `0x21 SEND` | `[u8 0x21][u32 guestId][payload...]` | その参加者へ payload をそのままバイナリで送る（いなければ捨てる） |
| ホスト → サーバー | `0x22 KICK` | `[u8 0x22][u32 guestId]` | その参加者を 4002 `closed_by_host` で閉じる（いなければ捨てる） |
| 参加者 ↔ サーバー | （ヘッダ無し） | `payload...` | 参加者 → サーバーはホストへ `GUEST_DATA` で、`SEND` の payload は参加者へそのまま |

- `GUEST_CLOSE` は `GUEST_OPEN` 1 回につき 1 回だけ、参加者の接続が終わった時に届く（参加者が閉じた・切れた、`KICK`、上限超え）。
  ホストが去った時は（ホストがもういないので）送らない。
- `GUEST_OPEN` はその参加者の最初の `GUEST_DATA` より必ず先に届く。同じ接続の中では順序が保たれる。
- 空の payload（参加者からの空のバイナリ、payload の無い `SEND`）は捨てる。
- ホストからの不正な形式（5 バイト未満・未知の種類）は 1003 で閉じる（その接続だけ。ホストが閉じるので参加者は `host_left` になる）。
  参加者からのバイナリは中身を見ないので、形式の誤りは無い。
- 1 メッセージの上限は **256 KiB**（超えたら 1009 で閉じる）。アプリは 64 KiB 以下に分けて送る（`OnlineFramer` がストリームとして
  再結合するので、分割の境界はどこでもよい）。ちょうど 256 KiB の参加者メッセージはホストへ 256 KiB + 5 バイトの `GUEST_DATA` で届く。

### テキスト・生存確認

- テキスト `ping` には `pong` を自動応答する（`setWebSocketAutoResponse`。DO を起こさない・課金されない）。
  アプリは 15 秒毎に `ping` を送ってよい（携帯回線の NAT のタイムアウト対策）。それ以外のテキストは無視する。
- アプリ側の生存確認（`OnlineSession` の ping / pong、20 秒）は、中継の上をそのまま流れる。
- **接続が開いたら、すぐに何か 1 つ送ること**（参加者は名乗り、ホストは `ping` で十分）。一度も何も送っていない接続を中継が閉じる
  （`KICK` / `host_left`）と、close フレームはすぐ届くが、TCP が約 10 秒残る（workerd の既知の不具合
  [cloudflare/workerd#7566](https://github.com/cloudflare/workerd/issues/7566)）。close フレームを受けた時点で閉じたものとして扱えば影響は無い。

### close コード

| コード | 理由 | いつ |
|---|---|---|
| 4001 | `host_left` | ホストが閉じた・切れた（参加者側） |
| 4002 | `closed_by_host` | ホストの `KICK` |
| 4004 | `no_room` | ホストのいない部屋への参加 |
| 4008 | `room_full` | 参加者が既に 32 人 |
| 4009 | `room_taken` | ホストのいる部屋へのホスト |
| 4010 | `relay_version` | `rv` が 1 でない |
| 4011 | `host_replaced` | 同じ鍵（`hk`）で戻ってきた新しいホストに、前のホストの接続が入れ替えられた（受信箱も同じ鍵の新しい接続に入れ替わる） |
| 4012 | `inbox_taken` | 受信箱のコードが別の鍵の持ち主のもの |
| 4013 | `inbox_suspended` | 運営が利用を止めたフレンドコード（`SUSPENDED_FRIEND_CODES`） |
| 4014 | `inbox_erased` | 消した受信箱のコード（本人が消した・1 年繋がなかった）。アプリは新しいコードを作り直す |
| 1003 | `malformed` | ホストからの不正な形式 |
| 1009 | `message_too_big` | 256 KiB を超えるメッセージ |

## フレンドの受信箱

フレンドからの申請・パーティの招待を届けるための、部屋とは別の経路。フレンドコード 1 つ = Durable Object（`FriendInbox`）1 つ。
アプリを開いている間だけ WebSocket で繋ぐ（`src/inbox.ts`）。アカウントは作らない。

- 接続: `GET /v1/inbox/<FRIENDCODE>?key=<KEY>&rv=1`（WebSocket）。フレンドコードは 8 文字（部屋コードと同じ 31 文字）、
  `key` は端末が最初に乱数で作る秘密（`^[A-Za-z0-9_-]{16,64}$`）。形式が合わなければ 400 `bad_friend_code`（コード）/ 1003 `malformed`（鍵）、
  `rv` 違いは 4010。
- **持ち主**: 最初に繋いだ鍵の SHA-256 を保存し、以後は同じ鍵でしか繋げない（別の鍵は 4012 `inbox_taken`）。コードを知っていても受信箱は読めない。
  同じ鍵の新しい接続は古い接続を 4011 `host_replaced` で入れ替える。
- 繋がると `{"t":"hello","code":"…"}` が届く（この後に預かっていた申請が続く）。メッセージはテキストの JSON（1 通 4 KiB まで、超えたら 1009）:

| 向き | 形 | 意味 |
|---|---|---|
| アプリ → 中継 | `{"t":"send","to":"CODE","id":n,"queue":true?,"m":{…}}` | `to` の受信箱へ `m` を渡す。`m` は中継が解釈しない JSON オブジェクト |
| 中継 → アプリ | `{"t":"ack","id":n,"result":"delivered\|queued\|offline"}` | `delivered` = 相手が繋いでいて渡した / `queued` = 不在で預かった（`queue:true` のみ）/ `offline` = 不在で預けない・送りすぎ |
| 中継 → アプリ | `{"t":"msg","from":"CODE","m":{…}}` | 届いたメッセージ。`from` は中継が接続のコードから付ける（なりすませない） |
| アプリ → 中継 | `{"t":"presence","codes":["CODE",…]}`（最大 100） | 在席の問い合わせ |
| 中継 → アプリ | `{"t":"presence","online":["CODE",…]}` | いま繋がっているもの |

- 預かり: `queue:true`（フレンド申請・承認だけ）で相手が不在なら、受信箱の SQLite に最大 20 通・受け付けから 14 日預かり、次に繋いだ時に
  渡して消す。期限の時刻に alarm で消す（最も古い預かりの期限に目覚ましを掛ける）。同じ差出人の同じ内容は 1 通にまとめ、届き直しても期限は
  延ばさない（アプリは承認待ちの申請を繋ぐたびに送り直すが、送り直すのは申請から 14 日の間だけ。`FriendHub.outgoingRequestLifetime`）。
  招待は預けない（古い部屋コードを渡さないため）。
- 歯止め: 1 接続あたり 1 分に 40 通まで（超えた分は `offline`）。自分宛て・不正なコード・オブジェクトでない `m` は捨てる。
- 保存するもの: 鍵のハッシュ、最後に繋いだ日時（繋いだ時・切れた時）、預かった申請だけ。在席の問い合わせはコードを知っている人なら
  誰でもできる（コードは本人が配るもの）。
- **受信箱の消去**: `POST /v1/inbox/<FRIENDCODE>/erase`、本文 `{"key":"<KEY>"}`（鍵は URL に載せない）。鍵のハッシュが持ち主と一致すれば、
  鍵のハッシュ・最後に繋いだ日時・預かった申請をすべて消し、繋がっている接続を 4014 `inbox_erased` で閉じ、「消した印」だけを残す
  （そのコードは二度と使えない。他人が同じコードを名乗って、フレンドからの申請・招待を受け取れないように）。消し済みなら `erased`、
  繋いだことのないコードなら何も作らずに `none`、鍵が違えば 403。アプリは「全データを削除」と「フレンドサーバーのデータを削除」から呼ぶ。
  消した受信箱へは申請を預けない（`offline`）。
- **自動の消去**: 持ち主が 1 年（`OWNER_IDLE_TTL_MS`）まったく繋がなければ、alarm で同じように消して「消した印」を残す。
- **利用停止**: 運営が規約違反を確かめたフレンドコードは、秘密 `SUSPENDED_FRIEND_CODES`（空白・カンマ区切り）に足す。止めたコードは
  受信箱へ繋げず（4013 `inbox_suspended`）、申請・招待・在席の問い合わせができない。部屋コードと同じ Wi-Fi の対戦はフレンドコードと
  結び付かないので止められない（ホストのブロック・追い出しで対処する）。
- アプリ側の使い方（`m` の種類 `friendRequest` / `friendAccept` / `partyInvite` / `inviteReply`）は `FriendHub.swift`、
  ARCHITECTURE.md「フレンドとパーティ」。

## ランク（アカウントごと）

Durable Object `RankAccount`（`src/rank.ts`。フレンドコード 1 つ = 1 つ）。持ち主は受信箱と同じ鍵で縛る（最初に来た鍵の SHA-256 を保存。
受信箱の持ち主とは別に確かめる）。規則は Mobile Legends と同じで `src/rank.ts` が正（アプリの `RankService.swift`・`SeasonService.swift`
は通信できない時の写し）。

- **ポイントの満タン**（ティアごと。Fandom「Ranked」）: スターポイント ウォリアー 100・エリート 200・マスター 300・グランドマスター 500・
  エピック 700・レジェンド 1000（満タンで星 +1。1 試合で 1 つまで。ミシックには無く、上がると 0）。保護ポイントは同じ値でミシック 1100
  （満タンで負けると星が減らず 0 に戻る。ミシックでもたまる）。ティアが変わったら新しいティアの満タンに収める。
- **シーズン**: 番号は MLBB と同じ。S42 は 2026-09-16 08:00 UTC から、1 シーズン 91 日（S43 は 2026-12-16 08:00 UTC から）。
  新しいシーズンの最初の get・seed・match で、前のシーズンの最終ランクから 1 回だけ下げて保存する（何シーズン空いても 1 回）。
  星・両ポイント・勝敗（`wins`・`losses`）は 0、最高到達（`highestTier`・`highestMythicStars`）はそのまま。下げ方（`SEASON_RESET`）:
  ウォリアー・エリートは同じ段位、マスター IV・III → エリート I、マスター II → IV、I → III、グランドマスター V → マスター II、IV → マスター I、
  III → V、II → IV、I → III、エピック V → グランドマスター II、IV → グランドマスター I、III・II → V、I → IV、レジェンド V → エピック IV、
  IV〜I → エピック III、ミシック 0〜24・H ミシック・G ミシック → エピック II、I ミシック → エピック I・星 1（2.2.16 の映像。0〜24 は未確認）。シーズン報酬はアプリがメールで送る。
- `POST /v1/rank/<CODE>/get` 本文 `{"key":"…"}` → `{"ok":true,"state":{…}}`（記録が無ければ今のシーズンの初期値を返し、記録は作らない）
- `POST /v1/rank/<CODE>/seed` 本文 `{"key":"…","state":{…}}`（サーバーに記録が無い時だけ端末の値を取り込む。あれば今の記録を返す）。
  `tier`・`division`・`stars` は必須で規則の範囲、ほかの数は 0 以上の整数（`starPoints` は 999 まで、`protectionPoints` は 1500 まで。
  旧版の全ティア 700 共通の値も受け付け、ティアの満タンに収める）。`season` は省けば今のシーズン（旧版のアプリは送らない）、42 より前は 42、
  先のシーズンは次のシーズンまで（端末の時計が進んでいて、もう下げてある記録）。前のシーズンの記録は下げてから取り込む。知らない項目は取り込まない。
- `POST /v1/rank/<CODE>/match` 本文 `{"key":"…","match":{"matchId":"…","won":true,"rating":8.2,"mvp":false}}`
  → `{"ok":true,"state":{…},"result":{"before","after","starPointsGain","scoreBonus","activeBonus","protected"}}`。
  `matchId` は 8〜64 文字の英数・`_`・`-`（`__proto__`・`toString` など Object.prototype の名前は不可）、`rating` は 0〜16 に収める。
  同じ matchId は最初の結果を返す（直近 50 試合。`state` はその時の記録）。新しいシーズンの最初の match は、下げてから数える
  （`result.before` は下げた記録）。
- `POST /v1/rank/<CODE>/erase` 本文 `{"key":"…"}` → `{"ok":true,"state":{初期値}}`。記録・持ち主の鍵・覚えている matchId をすべて消す
  （アプリは受信箱の消去と一緒に呼ぶ: `FriendHub.eraseServerData`）。運営が利用を止めたコードでも消せる。
- 誤りは平文: 400 `bad_friend_code` / `bad_key` / `bad_request`（JSON でない・本文 4 KiB 超・`state` / `match` の誤り）、
  403 `forbidden`（鍵が持ち主のものでない）/ `suspended`（利用停止のコードの get・seed・match）、
  409 `not_seeded`（seed の前の match。数えない。端末は自分の計算のまま進み、次の起動の seed で取り込まれる）、405（POST 以外）、404（知らない操作）。
- `rv` は見ない（版は道の `/v1`）。期限による自動の消去は無い（受信箱と違い、本人の erase だけで消える）。

## 名刺・ランキング・メール

全体で 1 つの Durable Object `Directory`（`getByName("global")`。SQLite）。アプリはオンラインに同意した 13 歳以上の時だけ使う。

| 要求 | 応答 |
|---|---|
| `POST /v1/profile/<FRIENDCODE>/put`（本文 `{"key":…,"profile":{…}}`） | 200 `{"ok":true,"profile":{…}}` / 400 `bad_profile` `bad_key` / 403 `forbidden` `erased` `suspended` |
| `POST /v1/profile/<FRIENDCODE>/erase`（本文 `{"key":…}`） | 200 `{"ok":true,"result":"erased"\|"none"}` / 403 `forbidden` |
| `POST /v1/profiles`（本文 `{"codes":[…]}`。最大 100） | 200 `{"ok":true,"profiles":[…]}`（名刺のあるコードだけ。`lastSeen` = 受信箱に最後に繋いだ日時） |
| `POST /v1/ranking`（本文 `{"scope":"global"\|"country"\|"friends","country":"JP","codes":[…],"me":…}`） | 200 `{"ok":true,"entries":[{"position":…,"profile":{…}}],"me":{…}\|null}` |
| `GET /v1/mail` | 200 `{"ok":true,"mail":[…]}`（今公開中の運営のメール。新しい順・最大 50） |
| `POST /v1/mail/publish`・`/v1/mail/delete`（本文 `{"key":"<OPS_MAIL_KEY>","mail":{…}}` / `{"key":…,"id":…}`） | 200 / 400 `bad_mail` / 403 `forbidden` |

- **名刺**（本人が送る表示用の自己申告）: 名前（1〜12 文字）・アイコンのヒーロー・アバターの枠・レベル・国・得意ヒーロー 3 体（試合数・勝ち数）・
  通算の試合数と勝ち数。**ランクは送らせない**: ランク戦の結果（`/v1/rank/…/seed|match|get`）のたびに、今のランク・今シーズンの最高ランク・
  今シーズンの勝敗を中継が書く。ランクの消去（`/v1/rank/…/erase`。アプリの「全データを削除」・同意の取り消し）で名刺も消える。
- **コードの持ち主**: ランク・名刺・受信箱で 1 つ。先に使った鍵（のハッシュ）が持ち主になり、以後は同じ鍵でしか書けない（`FriendInbox.claimOrMatch`）。
  ランクを消してもコードは他の鍵に渡らない。**残る危険**: 持ち主が一度も使う前のコードは、そのコードを知った他人が先に使える。
  アプリは同意の直後に受信箱とランクを登録し、登録を済ませるまで自分のコードを見せない（コードは端末の乱数で 8 文字。推測は難しい）。
- **ランキング**: 名刺のある人だけを、今シーズンの最高ランクの順（ティア → 段位 → 星。ミシックは星の累計。同じなら先に到達した人）に上位 100 人。
  範囲は世界・国（名刺の国。MLBB のサーバーの代わり）・フレンド（アプリが渡すコード）。`me` の行は範囲の中に居なければ `null`（ランク外）。
- **運営からのメール**: 運営だけが秘密の鍵で登録・削除する（`npx wrangler secret put OPS_MAIL_KEY`。鍵は公開リポジトリに書かない）。
  公開の期間は省けば登録から 60 日（MLBB の保存期間）。アプリは起動時と前面に戻った時に取りに来て、ID で重複を除き、添付は端末で受け取る。
  種類（`category`）は `important`・`system`・`report`・`inbox`・`gift`（MLBB のメールのタブ）。例（鍵はプレースホルダー）:

```sh
curl -X POST https://velstria-relay.<sub>.workers.dev/v1/mail/publish -H 'content-type: application/json' -d '{
  "key": "<OPS_MAIL_KEY>",
  "mail": {"id": "maint_20261101", "titleJa": "メンテナンスのお知らせ", "titleEn": "Maintenance",
           "bodyJa": "…", "bodyEn": "…", "important": true,
           "attachments": [{"kind": "coin", "amount": 500}]}
}'
```

## アカウント

MLBB のアカウント設定（Moonton アカウント・Game Center の連携・アカウント切替）にあたる。**アカウント ID = フレンドコード**、持ち主は受信箱と同じ鍵
（Worker が `FriendInbox.claimOrMatch` で確かめる）。端末のプロフィール（zlib で縮めた JSON、先頭に `VSA1`）を預かり、別の端末で
「ID + パスワード」か「Game Center」で取り出す。プロフィールにはフレンドコードと鍵が入っているので、取り出した端末がそのアカウントになる。

| 要求 | 応答 |
|---|---|
| `POST /v1/account/<CODE>/status`（本文 `{"key":…}`） | 200 `{"ok":true,"account":{"password":bool,"savedAt":ms\|null,"size":n,"gameCenter":bool}}` |
| `POST /v1/account/<CODE>/password`（本文 `{"key":…,"verifier":"<64 桁の 16 進>"}`） | 200 `{"ok":true,"account":…}` / 400 `bad_verifier` |
| `POST /v1/account/<CODE>/save`（本文 = プロフィールのバイト列、見出し `x-velsia-key`・`x-velsia-saved-at`） | 200 `{"ok":true,"account":…}` / 413 `too_large`（4 MiB 超） |
| `POST /v1/account/<CODE>/gamecenter`（本文 `{"key":…,"gc":{…署名…}}`） | 200 / 409 `gamecenter_taken`（別のコードに連携済み）/ 403 `gamecenter_invalid` `gamecenter_expired` / 400 `bad_gamecenter` |
| `POST /v1/account/<CODE>/unlink-gamecenter`（本文 `{"key":…}`） | 200 |
| `POST /v1/account/<CODE>/erase`（本文 `{"key":…}`） | 200 `{"ok":true,"result":"erased"}`（預かったデータ・パスワード・連携を消す） |
| `POST /v1/account/login`（本文 `{"code":…,"verifier":…}`） | 200 バイト列（見出し `x-velsia-code`・`x-velsia-saved-at`・`x-velsia-password`・`x-velsia-gamecenter`）/ 403 `wrong_password` / 404 `no_password` `no_data` / 429 `locked`（`retry-after`） |
| `POST /v1/account/login-gamecenter`（本文 `{"gc":{…署名…}}`） | 200 バイト列（同上）/ 404 `not_linked` |

- 持ち主の操作（status・password・save・gamecenter・unlink・erase）は鍵が違えば 403 `forbidden`、消した受信箱のコードは 403 `erased`、
  止めたコードは 403 `suspended`（erase だけはできる）。
- **パスワード**: 端末が PBKDF2-HMAC-SHA256（10 万回、塩 `velsia-account-v1:<CODE>`）で作った照合値だけを受け取り、乱数の塩を付けた
  SHA-256 を保存する（パスワードそのものは届かない）。5 回続けて違えると 15 分ロック（429）。持ち主の鍵でパスワードを設定し直すと解ける。
- **Game Center**: 端末の `GKLocalPlayer.fetchItems(forIdentityVerificationSignature:)` の `playerId`（teamPlayerID）・`bundleId`・
  `publicKeyUrl`・`signature`・`salt`（base64）・`timestamp`（ミリ秒）。公開鍵の URL は https の `*.apple.com` だけ取り寄せ、
  証明書の SubjectPublicKeyInfo で `playerId + bundleId + timestamp（u64 BE）+ salt` の RSA-SHA256 を確かめる。時刻のずれは 1 時間まで。
  bundle ID は `com.bitcoinpay.velstria` だけ。テストの Worker だけ `GAME_CENTER_TEST_KEY_ORIGIN` の下の鍵も使う（配備では設定しない）。
- 保存は 512 KiB ずつの区切り（SQLite の DO の値は鍵と合わせて 2 MB まで）。自動では消さない（本人の erase・受信箱の消去と一緒に）。

## 実装の要点

- 接続ごとの状態（役割・`guestId`・ホストの識別子 `hostKey`）は `serializeAttachment` に置き、ハイバネーションをまたぐ。
  メモリ上の状態は持たない（起きるたびに `getWebSockets(tag)` から引く。タグは `host` / `guest` / `g:<guestId>`）。
- `hostKey` はホストの接続 1 本ごとの識別子。ホストが去って同じコードで戻った直後でも、前のホストの参加者を新しいホストへ混ぜない。
- 断る接続（`room_taken` / `no_room` / `room_full` / `relay_version`）は、ハイバネーションしない普通の `accept()` で受けてすぐ閉じる。
- 参加者番号の採番は SQLite の 1 行（`INSERT ... ON CONFLICT DO UPDATE ... RETURNING`）。ホストが去ったら 10 分後の alarm で `deleteAll()`。
- 相手からの close には `webSocketClose` の中で `close()` を返す（配備先では自動応答に任せると応答が返らないことがあった）。

## 配備

```sh
cd relay
npm ci
npx wrangler whoami     # ログイン済みか（OAuth）
npx wrangler deploy     # → https://velstria-relay.<アカウントのサブドメイン>.workers.dev
```

- API キー・トークンは使わない。CI からは配備しない（手元から `wrangler deploy`）。
- 利用停止のコード一覧は Worker の秘密 `SUSPENDED_FRIEND_CODES` に置く（公開リポジトリに書かない）。
  `npx wrangler secret put SUSPENDED_FRIEND_CODES` で一覧全体を入れ直す（新しい版として配備され、繋がっている WebSocket は切れる）。
  一覧と、止めた理由・日時・通報の記録は社内で管理する（`VELSTRIA/docs/appstore/review_notes.md`「通報への対応」）。
- **配備すると、その時に繋がっている WebSocket は全部切れる**（Durable Object の仕様）。対戦中の人がいない時に配備する。
  アプリはホストなら同じコードで再接続し、参加者は切断扱い（→ 再参加）になる。
- 形式を変える時は `RELAY_VERSION` と URL の `rv` を上げ、古い版を話すアプリには 4010 で更新を促す。
- 料金の目安: Durable Objects は届いた WebSocket メッセージ 20 通を 1 リクエストと数える（送り出しは無料）。
  Workers Free は 1 日 10 万リクエストまで。10 人の対戦ではホストが参加者ごとに毎フレーム `SEND` を送る（秒間数百通）ので、
  Free だと全部屋の合計で 1 日 1 時間前後の対戦で上限に届く見込み（フレームあたりの送信数による）。
  超えるなら Workers Paid（月 100 万リクエスト込み、以後 100 万あたり $0.15）にする。2〜4 人の対戦ならその数分の一で済む。

## テスト

```sh
cd relay
npm ci
npm run typecheck                    # 型検査（tsc）
npm test                             # 手元で wrangler dev を空いているポートで起こし、結合テストを流す（約 20 秒）
npm run test:deployed                # 配備済みの中継（wss://velstria-relay.shoei0205.workers.dev）に流す（約 1 分）
RELAY_URL=wss://... npm test         # 任意の中継に流す
```

確かめていること: health、ホスト / 参加者の接続と `GUEST_OPEN`、両方向のデータ（200 KiB を含む・順序・宛先）、
いない参加者宛ての `SEND` / `KICK`、`KICK`、`GUEST_CLOSE`、`host_left`、`room_taken`、`no_room`、`room_full`（33 人目）、
`relay_version`、部屋コードの 400（WebSocket の握手でも）、role の 400、426、404、上限超えの 1009（参加者・ホスト）、
不正な形式の 1003、`ping` → `pong` の自動応答とそれ以外のテキストの無視、抜けた参加者・ホストの入れ替わりをまたぐ `guestId` の単調増加。
受信箱: 招待の配送と差出人の付与、不在の相手への `offline` / `queued`（繋いだ時に渡る）、在席の問い合わせ、持ち主の鍵（別の鍵は 4012）、
同じ鍵の再接続での入れ替え（4011）、自分宛て・不正な宛先の無視、不正なコード・鍵・`rv` の拒否、同じ申請の 1 通へのまとめ。
受信箱の消去: 鍵の違いの 403、消去（繋いでいる接続の 4014、以後の接続の 4014、預けない、消し直し）、繋いだことのないコードの `none`、要求の誤りの 400 / 405、
利用停止のコードの 4013（手元の Worker だけ。`wrangler dev --var SUSPENDED_FRIEND_CODES:…` で渡す）。
ランク: seed → match → get の往復、get が記録を作らないこと・seed が最初の 1 回だけ取り込むこと、規則（昇格・降格・ティアの境目・ミシック・
ティアごとのスターポイント・保護ポイントの満タン・評価の上限下限）、最高到達が下がらないこと、同じ matchId の二重送信（同時も）と直近 50 試合、持ち主の鍵の 403
（同時の取り合いも 1 人だけ）、erase、コード・鍵・本文・`match`・`seed` の誤りの 400 / 405 / 404、利用停止のコードの 403（消去はできる）、`rv` を見ないこと、
応答の `season`、旧版のアプリの seed（`season` なし・全ティア 700 の頃のポイント）を受け付けること。
試したランクのアカウントは最後に erase する。
ランクの規則とシーズン（Worker を起こさない）: `src/rank.ts` を wrangler の esbuild で 1 つにまとめて読み込み（`cloudflare:workers` は代役）、
同じ規則の表を `applyMatch` に流し、時計と保存先を差し替えた `RankAccount` でシーズンの境目・下げ方の表・新しいシーズンの最初の
get / seed / match で 1 回だけ下げること（二度下げない・先のシーズンを戻さない・旧版の番号）を確かめる。
部屋コードはテストごとに乱数で作るので、配備済みの中継に何度流しても互いに混ざらない。

Node 22 以上（組み込みの `WebSocket` と `node:test` を使う）。CI（`.github/workflows/relay.yml`）は `relay/**` が変わった時に
ubuntu で型検査と `npm test` を流す。
