# App のプライバシー（プライバシー栄養ラベル）

ASC > App のプライバシー の回答。結論: **「データを収集しない」（Data Not Collected）**。

## 回答

| 質問 | 回答 |
|---|---|
| お客様またはサードパーティパートナーは、この App からデータを収集しますか？ | **いいえ、この App からデータを収集しません** |
| プライバシーポリシー URL | `metadata/ja/privacy_url.txt` / `metadata/en-US/privacy_url.txt` |
| プライバシー選択肢 URL（任意） | 未設定（収集データが無いため） |
| トラッキング | なし（App Tracking Transparency 不使用、`NSUserTrackingUsageDescription` なし） |

## 根拠（Apple の定義する「収集」に該当しない理由）

Apple の定義では、データが端末外へ送信され、開発者または第三者が要求時間を超えて保持できる状態になることが「収集」にあたる。
VELSIA は開発者のサーバーを持たず、以下のデータはすべて**端末内（Application Support）にのみ保存**し、外部へ送信しない。

| データ | 保存場所 | 送信 |
|---|---|---|
| プロフィール（プレイヤー名、所持品、進行、設定、年齢区分） | 端末内 `profile.json` | しない |
| リプレイ | 端末内 `replays/` | しない |
| 購入台帳（トランザクション ID、付与量） | 端末内 `profile.json` | しない |
| 年齢区分（自己申告） | 端末内 | しない（購入上限の判定にのみ使用） |

- **App 内課金**: 決済は Apple が処理する。アプリは StoreKit から端末上で検証済みトランザクションを受け取り、アイテムを付与するだけで、
  購入履歴を開発者へ送信しない。Apple が決済のために取得する情報は Apple のプライバシーポリシーの対象で、開発者の申告対象外。
- **クラッシュレポート**: 利用者が「App デベロッパと共有」を許可した場合に Apple 経由で届くクラッシュログは Apple が収集するもので、
  サードパーティの解析 SDK は入れていない。Apple のガイダンス上、申告は不要。
- **サポートへの問い合わせ**: 利用者が自分でメールを送った場合に受け取るメールアドレス・本文は、アプリによる収集ではない
  （プライバシーポリシーに取り扱いを明記している）。
- **データのバックアップ書き出し**: 利用者の操作で共有シートに渡すだけで、送信先は利用者が選ぶ。

## プライバシーマニフェストとの対応

`App/Resources/PrivacyInfo.xcprivacy`:

| キー | 値 |
|---|---|
| `NSPrivacyTracking` | false |
| `NSPrivacyTrackingDomains` | 空 |
| `NSPrivacyCollectedDataTypes` | 空（= 栄養ラベルの「収集しない」と一致） |
| `NSPrivacyAccessedAPITypes` | UserDefaults: `CA92.1`（アプリ自身の設定値） / File timestamp: `C617.1`（アプリコンテナ内のセーブ・リプレイの日時/サイズ） / System boot time: `35F9.1`（効果音・触覚の再生間隔などアプリ内のイベント間の経過時間。`ProcessInfo.systemUptime`） |

- Disk space API は現時点で未使用のため宣言していない。
  使用を追加した場合は `python3 tools/privacy_audit.py` がエラーにするので、理由コード（例 `E174.1`）を追加する。
- 宣言済みの理由コードはいずれも「端末内で完結する用途」で、値を端末外へ送信しない（送信すると理由コードの条件を満たさない）。
- 外部 SDK を追加する場合は、その SDK 自身のプライバシーマニフェストと署名を確認し、収集データがあれば栄養ラベルを更新する。

## 変更時のルール

解析・広告・クラッシュ収集 SDK、オンライン機能（Phase 2）、クラウド保存などを追加する場合は、リリース前に
1) 栄養ラベル、2) `PrivacyInfo.xcprivacy` の `NSPrivacyCollectedDataTypes`、3) `docs/legal/privacy_policy_*.md` の 3 点を同時に更新する。
