# velstria-relay（インターネット対戦の中継）

違う場所・違う Wi-Fi / モバイル回線の端末同士で、オンライン対戦（リッスンサーバー方式: ホストの iPhone が権威シミュレーション）を
遊べるようにするための中継サーバー。Cloudflare Workers + Durable Objects で動く。

- **中身を解釈しない土管**。ゲームの手順（アプリの `App/Online/OnlineProtocol.swift` の `OnlineMessage`、`OnlineFramer` の
  4 バイト長さ区切り JSON）はそのまま流す。中継はホストと参加者の間でバイト列を付け替えるだけ。
- **何も保存しない**。対戦データ（payload）は保存もログ出力もしない。Workers Logs も無効（`wrangler.jsonc` の `observability`）。
  保存するのは部屋ごとの参加者番号の採番（数値 1 つ）だけで、ホストが去ってから 10 分で消す。
- 部屋コード 1 つ = Durable Object（`RelayRoom`）1 つ。WebSocket Hibernation API で、通信の無い間は DO を眠らせる（課金・メモリを使わない）。
- LAN（Bonjour / IP:ポート直結）は今まで通りアプリに残る。ホストは LAN の待ち受けと中継の両方で参加者を受け入れる。

配備先: **`wss://velstria-relay.shoei0205.workers.dev`**（アプリの `OnlineRelayConfig.defaultBaseURL`）

## 構成

| パス | 内容 |
|---|---|
| `src/index.ts` | Worker（入口の検証）と Durable Object `RelayRoom`（中継の本体） |
| `wrangler.jsonc` | Worker 名 `velstria-relay`、DO の束縛 `RELAY_ROOM`、SQLite バックエンドの移行 `v1` |
| `test/relay.test.mjs` | 結合テスト（Node の組み込みテストランナー + Node の WebSocket。本物の Worker を相手にする） |
| `../.github/workflows/relay.yml` | `relay/**` が変わった時に CI（ubuntu）でテストを流す（配備はしない） |

## 手順（プロトコル v1）

### HTTP

| 要求 | 応答 |
|---|---|
| `GET /v1/health` | 200 `{"ok":true,"relay":1}` |
| `GET /v1/rooms/<CODE>?role=host\|guest&rv=1`（WebSocket Upgrade） | 101（下の close コードで断る時も、いったん受け入れてから閉じる） |
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
| 1003 | `malformed` | ホストからの不正な形式 |
| 1009 | `message_too_big` | 256 KiB を超えるメッセージ |

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

- 秘密情報は使わない（API キー・トークンはリポジトリにも Worker にも無い）。CI からは配備しない（手元から `wrangler deploy`）。
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
npm test                             # 手元で wrangler dev を空いているポートで起こし、結合テストを流す（約 10 秒）
npm run test:deployed                # 配備済みの中継（wss://velstria-relay.shoei0205.workers.dev）に流す（約 1 分）
RELAY_URL=wss://... npm test         # 任意の中継に流す
```

確かめていること: health、ホスト / 参加者の接続と `GUEST_OPEN`、両方向のデータ（200 KiB を含む・順序・宛先）、
いない参加者宛ての `SEND` / `KICK`、`KICK`、`GUEST_CLOSE`、`host_left`、`room_taken`、`no_room`、`room_full`（33 人目）、
`relay_version`、部屋コードの 400（WebSocket の握手でも）、role の 400、426、404、上限超えの 1009（参加者・ホスト）、
不正な形式の 1003、`ping` → `pong` の自動応答とそれ以外のテキストの無視、抜けた参加者・ホストの入れ替わりをまたぐ `guestId` の単調増加。
部屋コードはテストごとに乱数で作るので、配備済みの中継に何度流しても互いに混ざらない。

Node 22 以上（組み込みの `WebSocket` と `node:test` を使う）。CI（`.github/workflows/relay.yml`）は `relay/**` が変わった時に
ubuntu で型検査と `npm test` を流す。
