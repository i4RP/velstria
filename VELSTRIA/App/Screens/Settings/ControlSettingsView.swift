import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI061 操作設定（右側に HUD 配置のライブプレビュー）。

struct ControlSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.profile.settings
        ScreenScaffold(title: L("操作設定", "Controls"), showsCurrencies: false) {
            HStack(alignment: .top, spacing: 14) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 10) {
                        SettingsSection(title: L("移動と照準", "Movement & Aiming"), symbol: "gamecontroller.fill") {
                            SettingsChoiceRow(title: L("スティック", "Joystick"), detail: SettingsText.joystickDetail(s.joystickMode),
                                              symbol: "circle.circle",
                                              options: JoystickMode.allCases.map { ($0, SettingsText.joystick($0)) },
                                              selection: settingsBinding(app, \.joystickMode), identifier: "controls_joystick")
                            SettingsDivider()
                            SettingsChoiceRow(title: L("スキル発動", "Skill Casting"), detail: SettingsText.castModeDetail(s.skillCastMode),
                                              symbol: "hand.tap.fill",
                                              options: SkillCastMode.allCases.map { ($0, SettingsText.castMode($0)) },
                                              selection: settingsBinding(app, \.skillCastMode), identifier: "controls_cast")
                        }
                        SettingsSection(title: L("攻撃優先", "Attack Priority"), symbol: "scope") {
                            SettingsChoiceRow(title: L("通常攻撃の対象", "Basic attack target"),
                                              detail: SettingsText.attackPriorityDetail(s.attackPriority), symbol: "target",
                                              options: SettingsText.allPriorities.map { ($0, SettingsText.attackPriority($0)) },
                                              selection: settingsBinding(app, \.attackPriority), identifier: "controls_priority")
                        }
                        SettingsSection(title: L("レイアウトとカメラ", "Layout & Camera"), symbol: "rectangle.3.group.fill") {
                            SettingsToggleRow(title: L("左利きレイアウト", "Left-handed Layout"),
                                              detail: L("スティックを右、スキルボタンを左に配置します。", "Stick on the right, skills on the left."),
                                              symbol: "hand.point.left.fill", isOn: settingsBinding(app, \.leftHandedLayout),
                                              identifier: "controls_left_handed")
                            SettingsDivider()
                            SettingsSliderRow(title: L("HUD の不透明度", "HUD Opacity"), symbol: "circle.lefthalf.filled",
                                              value: settingsBinding(app, \.hudOpacity), range: 0.5...1.0, step: 0.05,
                                              format: SettingsText.percent, identifier: "controls_hud_opacity")
                            SettingsDivider()
                            SettingsSliderRow(title: L("カメラ距離（大きいほど広く表示）", "Camera Distance (higher shows more)"),
                                              symbol: "camera.metering.center.weighted",
                                              value: settingsBinding(app, \.cameraZoom), range: 0.8...1.3, step: 0.05,
                                              format: { String(format: "×%.2f", $0) }, identifier: "controls_camera_zoom")
                        }
                        SettingsSection(title: L("アシスト", "Assists"), symbol: "wand.and.stars") {
                            SettingsToggleRow(title: L("スキル自動習得", "Auto-level Skills"),
                                              detail: L("レベルアップ時に Ult → スキル1 → 2 → 3 の順で自動で習得します。",
                                                        "On level up, learns Ultimate, then Skill 1, 2, 3 automatically."),
                                              symbol: "arrow.up.circle.fill", isOn: settingsBinding(app, \.autoLevelSkills),
                                              identifier: "controls_auto_level")
                            SettingsDivider()
                            SettingsToggleRow(title: L("おすすめ装備", "Recommended Items"),
                                              detail: L("ショップでおすすめ装備を表示し、ワンタップで購入できます。",
                                                        "Shows recommended items in the shop for one-tap buying."),
                                              symbol: "bag.fill", isOn: settingsBinding(app, \.showRecommendedItems),
                                              identifier: "controls_recommended")
                        }
                    }
                    .padding(.bottom, 10)
                }
                ControlLayoutPreview(settings: s)
                    .frame(width: 250)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

/// 戦闘 HUD 配置の簡易プレビュー。
struct ControlLayoutPreview: View {
    let settings: GameSettings

    var body: some View {
        Panel(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                LiveOpsSectionHeader(title: L("プレビュー", "Preview"), symbol: "eye.fill")
                screen
                    .aspectRatio(2.05, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 2))
                    .animation(.easeInOut(duration: 0.25), value: settings)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary)
                VStack(alignment: .leading, spacing: 3) {
                    legend("circle.circle", settings.joystickMode == .floating ? L("スティック: 触れた位置に出現", "Stick: appears on touch")
                                                                            : L("スティック: 定位置", "Stick: fixed position"))
                    legend("hand.tap.fill", "\(L("発動", "Cast")): \(SettingsText.castMode(settings.skillCastMode))")
                    legend("scope", "\(L("優先", "Priority")): \(SettingsText.attackPriority(settings.attackPriority))")
                }
            }
        }
    }

    private func legend(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(Theme.body(11))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var screen: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let left = !settings.leftHandedLayout
            ZStack {
                // 戦場（カメラ距離で格子の細かさが変わる）
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .linearGradient(Gradient(colors: [Color(red: 0.10, green: 0.20, blue: 0.18), Color(red: 0.06, green: 0.10, blue: 0.16)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                    let step = 22 / settings.cameraZoom
                    var x = 0.0
                    while x < size.width {
                        ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                                   with: .color(.white.opacity(0.06)), lineWidth: 1)
                        x += step
                    }
                    var y = 0.0
                    while y < size.height {
                        ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                                   with: .color(.white.opacity(0.06)), lineWidth: 1)
                        y += step
                    }
                }
                Circle()
                    .fill(Theme.teamColor(.blue, colorblind: settings.colorblindMode))
                    .frame(width: 12 / settings.cameraZoom, height: 12 / settings.cameraZoom)
                    .overlay(Circle().stroke(.white, lineWidth: 1))
                    .position(x: w * 0.5, y: h * 0.48)
                Group {
                    joystick(size: h * 0.42)
                        .position(x: left ? w * 0.15 : w * 0.85, y: h * 0.70)
                    skills(size: h * 0.5)
                        .position(x: left ? w * 0.80 : w * 0.20, y: h * 0.66)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                        .frame(width: h * 0.28, height: h * 0.28)
                        .position(x: left ? w * 0.9 : w * 0.1, y: h * 0.2)
                }
                .opacity(settings.hudOpacity)
            }
        }
    }

    @ViewBuilder
    private func joystick(size: CGFloat) -> some View {
        if settings.joystickMode == .floating {
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: size * 1.35, height: size * 1.35)
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: size * 0.32))
                    .foregroundStyle(.white.opacity(0.8))
            }
        } else {
            ZStack {
                Circle().fill(Color.white.opacity(0.12)).overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                Circle().fill(Color.white.opacity(0.75)).frame(width: size * 0.42, height: size * 0.42)
            }
            .frame(width: size, height: size)
        }
    }

    /// 攻撃ボタン（金）と、その内側に弧状に並ぶスキル 4 つ（最後が Ult）。
    private func skills(size: CGFloat) -> some View {
        let small = size * 0.32
        // 右手配置では攻撃ボタンを右下、左利き配置では左右反転
        let mirror: CGFloat = settings.leftHandedLayout ? -1 : 1
        let attackX = size * 0.30 * mirror
        let attackY = size * 0.22
        return ZStack {
            Circle()
                .fill(Theme.gold.opacity(0.85))
                .frame(width: size * 0.52, height: size * 0.52)
                .overlay(Image(systemName: "scope").font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(.black.opacity(0.7)))
                .offset(x: attackX, y: attackY)
            ForEach(0..<4, id: \.self) { i in
                let angle = 180.0 - Double(i) * 30
                let r = size * 0.6
                let dx = CGFloat(cos(angle * .pi / 180)) * r * mirror
                let dy = -CGFloat(sin(angle * .pi / 180)) * r
                Circle()
                    .fill(i == 3 ? Theme.cyan.opacity(0.9) : Color.white.opacity(0.3))
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 0.5))
                    .frame(width: small, height: small)
                    .offset(x: attackX + dx, y: attackY + dy)
            }
        }
    }

    private var accessibilitySummary: String {
        let side = settings.leftHandedLayout ? L("スティック右・スキル左", "stick right, skills left")
                                             : L("スティック左・スキル右", "stick left, skills right")
        return "\(L("HUD プレビュー", "HUD preview")): \(side), \(L("不透明度", "opacity")) \(SettingsText.percent(settings.hudOpacity))"
    }
}
