import Foundation

// 担当: core-combat（検証用の観測。docs/vfx/RANGES.md）。sim が実際に当たりを調べた形を、その瞬間に受け口（sink）へ渡す。
// 内部ビルドの「判定の形」の表示（App の HitShapeOverlay）と、演出の範囲の検査（App の FXRangeAudit・HitShapeScenario）が使う。
// 規則:
// - SimState・SimEvent・乱数・判定の結果には一切触れない（決定論・リプレイ・オンラインの同期に影響しない）。SimEvent に
//   載せないので、記録・配信もされない。
// - 受け口が無い（既定）とき、呼び出し側の負担は isActive の読み取り 1 つだけ（形は autoclosure なので作らない）。
// - メインスレッドで進む sim の判定だけを渡す（裏で進めるリプレイの事前計算などの sim は拾わない）。
// - 形は判定そのものの寸法で、対象の半径は含まない（どの判定も「対象の円が形に重なれば当たり」）。

/// 1 回の判定の形（sim の単位。100 = 1 m）。
public struct HitShape: Hashable, Sendable {
    public enum Form: Hashable, Sendable {
        /// 円（中心・半径）。inner > 0 なら、中心から inner より内側（対象の半径を足しても届かない対象）を除く。
        case circle(center: Vec2, radius: Double, inner: Double)
        /// 扇（頂点・中心の向き・半径・半角 rad）。inner は円と同じ。
        case cone(center: Vec2, direction: Vec2, radius: Double, halfAngle: Double, inner: Double)
        /// 線分（始点 → 終点、半幅）。squareEnds = 両端を丸めない長方形（false = 端が半円のカプセル）。
        /// 直線弾・経路ヒット突進は 1 tick の移動区間、線のゾーンは全長。
        case line(from: Vec2, to: Vec2, halfWidth: Double, squareEnds: Bool)
        /// 多角形（頂点を順に。凸。キット独自の台形の帯など）。
        case polygon([Vec2])
        /// 単体（対象指定の命中。対象の位置と半径）。
        case unit(at: Vec2, radius: Double)
    }

    /// 判定の出どころ（どの共通処理か）。
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        /// 地面のゾーン（ZoneSystem。予告の後の発動・持続の毎回）。
        case zone
        /// 即時の範囲（SkillArchetypes.hitArea・Kit.hitAreaEach）。
        case area
        /// 直線弾の 1 tick の掃引（ProjectileSystem）。
        case projectile
        /// 経路ヒット突進の 1 tick の掃引（KitRuntime.stepSweep）。
        case sweep
        /// 対象指定の単体の命中。
        case single
        /// キット独自の判定（共通の処理を通らない形）。
        case kit
    }

    public var form: Form
    public var kind: Kind
    public var team: Team
    /// 判定の持ち主（術者・弾の持ち主）。
    public var sourceID: EntityID?
    public var source: DamageSource
    /// 続きの判定をつなぐ鍵（弾・ゾーンの ID、突進は術者の ID）。0 = 単発。表示は同じ鍵の線分を 1 本につなぐ。
    public var trackID: EntityID
    /// sim の時刻（秒）。
    public var time: Double

    public init(form: Form, kind: Kind, team: Team, sourceID: EntityID?, source: DamageSource, trackID: EntityID = 0,
                time: Double) {
        self.form = form
        self.kind = kind
        self.team = team
        self.sourceID = sourceID
        self.source = source
        self.trackID = trackID
        self.time = time
    }

    /// ゾーン z の今の形（ZoneSystem.contains(zone:) と同じ寸法）。
    static func zone(_ z: AreaZone, time: Double) -> HitShape {
        let inner = max(0, z.innerRadius ?? 0)
        let form: Form
        switch z.shape {
        case .circle:
            form = .circle(center: z.center, radius: z.radius, inner: inner)
        case .cone(let direction, let halfAngle):
            form = .cone(center: z.center, direction: direction.normalized, radius: z.radius, halfAngle: halfAngle,
                         inner: inner)
        case .line(let direction, let length):
            form = .line(from: z.center, to: z.center + direction.normalized * max(0, length), halfWidth: z.radius,
                         squareEnds: z.squareEnds == true)
        }
        return HitShape(form: form, kind: .zone, team: z.team, sourceID: z.ownerID, source: z.payload.source,
                        trackID: z.id, time: time)
    }

    /// 即時の範囲（形 shape・中心・半径。ZoneSystem.contains(shape:) と同じ寸法）。
    static func area(_ shape: ZoneShape, center: Vec2, radius: Double, team: Team, sourceID: EntityID?,
                     source: DamageSource, kind: Kind = .area, time: Double) -> HitShape {
        let form: Form
        switch shape {
        case .circle:
            form = .circle(center: center, radius: radius, inner: 0)
        case .cone(let direction, let halfAngle):
            form = .cone(center: center, direction: direction.normalized, radius: radius, halfAngle: halfAngle, inner: 0)
        case .line(let direction, let length):
            form = .line(from: center, to: center + direction.normalized * max(0, length), halfWidth: radius,
                         squareEnds: false)
        }
        return HitShape(form: form, kind: kind, team: team, sourceID: sourceID, source: source, time: time)
    }

    /// キット独自の判定（術者 i の形 form）。
    static func kit(_ form: Form, _ s: SimState, caster i: Int, source: DamageSource) -> HitShape {
        HitShape(form: form, kind: .kit, team: s.units[i].team, sourceID: s.units[i].id, source: source, time: s.time)
    }
}

/// 判定の形の受け口（検証用。docs/vfx/RANGES.md）。App の内部ビルドが、設定で表示を有効にした試合の間だけ置く。
public enum HitShapeProbe {
    /// 受け口（既定 nil = 何もしない）。メインスレッドから置く・外す。
    nonisolated(unsafe) public static var sink: ((HitShape) -> Void)? {
        didSet { isActive = sink != nil }
    }

    /// 受け口があるか（判定の側はまずこれだけを見る。無ければ形を作らない）。
    nonisolated(unsafe) public private(set) static var isActive = false

    /// 判定の形を受け口へ渡す（受け口が無い・メインスレッドでない sim なら何もしない）。
    @inline(__always)
    static func emit(_ shape: @autoclosure () -> HitShape) {
        guard isActive, Thread.isMainThread, let sink else { return }
        sink(shape())
    }
}
