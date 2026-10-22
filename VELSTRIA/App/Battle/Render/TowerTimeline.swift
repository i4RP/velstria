import Foundation

// 担当: battle-renderer。塔・Star Core の見た目の時刻表（docs/STAGE_REDESIGN.md の E）。
// ゲームの判定（稼働開始・射程・攻撃間隔・破壊・報酬・勝敗）は sim のまま。ここは描画だけが使う。
// 表示は全て「sim の時刻 − きっかけの時刻」の関数として毎フレーム求める（積み上げない）ので、
// シーク・再同期・一時停止・リプレイ・同じイベントの重複でも同じ見た目になる。
//
// 部品（USDZ の子メッシュ名。tools/structures/tower_parts.py が書く）:
//   part_plinth  固定の基壇（最後まで残る）
//   part_lower   中央支柱の下半（立ち上がりで竪穴からせり上がる。破壊後は折れた根元として残る）
//   part_upper   中央支柱の上半＋外装（立ち上がりで下半と一緒に上がる。破壊で傾いて落ちる）
//   part_crown   頂部構造（立ち上がりの最後に収まってロックする。破壊で落ちる）
//   part_crystal 魔力コア（浮遊・脈動。破壊で異常発光 → 割れて失活）
// Core は part_plinth（聖域の台座）・part_upper（石柱と弧）・part_crystal（大結晶）。
enum TowerTimeline {
    // MARK: 立ち上がり（試合開始 t = 0 から。塔の稼働は sim どおり t = 0 から）

    /// 基壇の紋様が点灯し、継ぎ目から砂が出る。
    static let riseGlowEnd: Double = 0.3
    /// 中央支柱がせり上がり終える。
    static let risePillarEnd: Double = 1.3
    /// 頂部構造・支持部品が収まってロックする。
    static let riseLockEnd: Double = 1.9
    /// 魔力が下から上へ流れ、コアが点灯して通常の明るさへ落ち着く。
    static let riseEnd: Double = 2.4

    // MARK: 破壊（unit.deathTime から）

    /// 稼働光の停止・コアの異常発光・破断箇所の粉塵。
    static let breakFlashEnd: Double = 0.2
    /// 亀裂が広がり接合部が破断する。
    static let crackEnd: Double = 0.6
    /// 上部が奥へ傾き、大きな塊に分かれて落ちる。
    static let toppleEnd: Double = 1.5
    /// 着地・低い粉塵。以降は瓦礫として落ち着く。
    static let impactEnd: Double = 2.3
    /// 瓦礫を残す時間の終わり（ここから整理が始まる）。
    static let rubbleHoldEnd: Double = 4.8
    /// 整理の終わり（小破片 → 結晶片 → 大きな石の順）。以降は破損基壇と根元だけ。
    static let clearEnd: Double = 6.3

    // MARK: Star Core の終幕（Core の deathTime から。全員の画面で同じ）

    /// ゲームカメラのまま Core へ寄る（HUD を隠す）。
    static let finalePushEnd: Double = 0.6
    /// 低い第三者視点で回り込む区間の終わり（結晶の分裂・光の柱・収縮）。
    static let finaleOrbitEnd: Double = 4.0
    /// 衝撃波の後、引きの構図で落ち着く。
    static let finaleSettleEnd: Double = 5.2
    /// リザルト（勝敗のバナー）を出す時刻。
    static let finaleResult: Double = 5.2

    // MARK: 損傷（HP の割合。閾値をまたいだ時だけ段階が変わる）

    static let damage1: Double = 0.7
    static let damage2: Double = 0.35

    /// 損傷の段階（0 = 無傷、1 = ひび・欠け、2 = 剥落・魔力漏れ）。
    static func damageStage(hpRatio r: Double) -> Int {
        r < damage2 ? 2 : r < damage1 ? 1 : 0
    }

    // MARK: 上限（docs/BATTLE_PERFORMANCE.md）

    /// 倒壊を演出つきで同時に進める塔の数（超えた分は粉塵を減らした短縮版）。
    static let maxConcurrentCollapses = 2
    /// 1 基あたりの小破片の上限。
    static let maxSmallDebris = 12
}
