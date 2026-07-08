//
//  HomeView.swift
//  MindWaveGraphic
//
//  imageUI cockpit reference rebuild — 2026-07-09
//  グラフィック75% + コックピットパネル25% の配置。
//  Homeには心拍数のみ表示。呼吸法カード・スコア・HRV・状態詳細は削除。
//  下部にレバー型ナビゲーション（整える/ホーム/履歴）を配置。
//  バックエンド処理・HealthKit・Watch側は一切変更しない。
//

import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var flowState: AppFlowState
    @Binding var selectedTab: Int

    @State private var showSettingsSheet = false
    @State private var buttonGlow: Bool  = false

    #if DEBUG
    @State private var showDebugSheet     = false
    @State private var visualPreviewScore: Double? = nil
    private let visualQAStates: [(label: String, score: Double?)] = [
        ("OFF",  nil), ("CALM", 12.0), ("FCUS", 40.0), ("ALRT", 70.0), ("OVLD", 92.0)
    ]
    #endif

    // MARK: - 表示用計算プロパティ

    private var displayInput: GraphicInput {
        #if DEBUG
        if let s = visualPreviewScore {
            return GraphicInput(score: s, confidence: 1.0, state: .optimalTension)
        }
        #endif
        return viewModel.graphicInput
    }

    private var scoreIntensity: Double {
        min(max(displayInput.score / 100.0, 0.0), 1.0)
    }

    private var scoreAccentColor: Color {
        let t = scoreIntensity
        if t < 0.30 {
            let p = t / 0.30
            return Color(hue: 0.68 - p * 0.10, saturation: 0.90, brightness: 0.88)
        } else if t < 0.65 {
            let p = (t - 0.30) / 0.35
            return Color(hue: 0.58 - p * 0.48, saturation: 0.92, brightness: 0.97)
        } else {
            let p = (t - 0.65) / 0.35
            let h = 0.10 - p * 0.10
            return Color(hue: h < 0 ? h + 1 : h, saturation: 0.96, brightness: 1.0)
        }
    }

    private var alertIntensity: Double {
        max(0.0, (scoreIntensity - 0.58) / 0.42)
    }

    private var isLive: Bool { viewModel.isLiveMonitoring }

    private var indicatorColor: Color {
        switch viewModel.activeDataSource {
        case .watchLive:   return .cyan
        case .healthKit:   return Color(red: 0.20, green: 0.85, blue: 0.60)
        case .mock:        return .orange
        case .unavailable: return Color.white.opacity(0.25)
        }
    }

    private var shortStatusLabel: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return viewModel.isLiveMonitoring ? "LIVE" : "WATCH"
        case .healthKit:   return "HK"
        case .mock:        return "DEMO"
        case .unavailable: return "STANDBY"
        }
    }

    private var hasRealHeartRate: Bool {
        viewModel.latestWatchHeartRate != nil || viewModel.didFetchHeartRate
    }

    private var heartRateDisplay: String {
        if let w = viewModel.latestWatchHeartRate { return String(format: "%.0f", w) }
        if viewModel.didFetchHeartRate            { return String(format: "%.0f", viewModel.currentHeartRate) }
        return "—"
    }

    private var buttonPulseDuration: Double {
        3.5 - scoreIntensity * 2.3
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let safeBottom = geo.safeAreaInsets.bottom
            let safeTop    = geo.safeAreaInsets.top

            ZStack(alignment: .bottom) {
                // 1. 深宇宙背景
                Color(red: 0.00, green: 0.01, blue: 0.05)
                    .ignoresSafeArea()

                // 2. フルスクリーン星グラフィック（全画面）
                GraphicHostView(input: displayInput)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // 3. コックピット窓枠（左右細いストラット）
                CockpitWindowFrame(
                    accentColor: scoreAccentColor,
                    alertIntensity: alertIntensity
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // 4. 下部グラデーション（星→パネルへのフェード）
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(red: 0.03, green: 0.05, blue: 0.12).opacity(0.50),
                            Color(red: 0.04, green: 0.06, blue: 0.14).opacity(0.88),
                            Color(red: 0.04, green: 0.06, blue: 0.14)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 120)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // 5. タイトルバー（最上部オーバーレイ）
                VStack(spacing: 0) {
                    cockpitTitleBar
                        .padding(.top, safeTop + 2)
                        .padding(.horizontal, 18)
                    Spacer()
                }
                .ignoresSafeArea()
                .allowsHitTesting(true)
                .zIndex(10)

                // 6. 下部コックピットパネル
                CockpitBottomPanel(
                    selectedTab:      $selectedTab,
                    accentColor:      scoreAccentColor,
                    alertIntensity:   alertIntensity,
                    scoreIntensity:   scoreIntensity,
                    isLive:           isLive,
                    buttonGlow:       buttonGlow,
                    buttonPulse:      buttonPulseDuration,
                    heartRateText:    heartRateDisplay,
                    hasHeartRate:     hasRealHeartRate,
                    safeBottom:       safeBottom,
                    onMeasureTap:     { viewModel.toggleLiveMonitoring() }
                )
                .zIndex(5)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0).repeatForever(autoreverses: true)
            ) { buttonGlow = true }
            #if DEBUG
            if let s = resolveVisualQAScore() { visualPreviewScore = s }
            #endif
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView().environmentObject(viewModel)
        }
        #if DEBUG
        .sheet(isPresented: $showDebugSheet) {
            debugQASheet.environmentObject(viewModel)
        }
        #endif
    }

    // MARK: - タイトルバー

    private var cockpitTitleBar: some View {
        HStack(alignment: .center, spacing: 0) {
            // 左: 接続状態ピル
            HStack(spacing: 5) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: indicatorColor.opacity(0.9), radius: 4)
                Text(shortStatusLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .tracking(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.07))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))

            Spacer()

            // 中央: MIND WAVE タイトル
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    Text("MIND")
                        .font(.system(size: 17, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .tracking(5.0)
                        .shadow(color: .black.opacity(0.90), radius: 8)
                    Text(" WAVE")
                        .font(.system(size: 17, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(scoreAccentColor.opacity(0.96))
                        .tracking(5.0)
                        .shadow(color: scoreAccentColor.opacity(0.55), radius: 8)
                        .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
                }
                Text("STRESS  &  BIOMETRICS")
                    .font(.system(size: 7, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .tracking(2.8)
                    .shadow(color: .black.opacity(0.80), radius: 5)
            }

            Spacer()

            // 右: 設定 + debug
            HStack(spacing: 0) {
                Button { showSettingsSheet = true } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                            .frame(width: 28, height: 28)
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.50))
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                #if DEBUG
                Button { showDebugSheet = true } label: {
                    Text("dbg")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.22))
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                #endif
            }
        }
        .frame(height: 36)
    }

    // MARK: - DEBUG Sheet

    #if DEBUG
    private func resolveVisualQAScore() -> Double? {
        guard let s = ProcessInfo.processInfo.environment["VISUAL_QA_STATE"] else { return nil }
        switch s.uppercased() {
        case "CALM":     return 12.0
        case "FOCUS":    return 40.0
        case "ALERT":    return 70.0
        case "OVERLOAD": return 92.0
        default:         return nil
        }
    }

    private var debugQASheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Visual QA — Home States")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan)
                        .padding(.top, 16)

                    HStack(spacing: 8) {
                        ForEach(visualQAStates.indices, id: \.self) { i in
                            let item = visualQAStates[i]
                            let active = visualPreviewScore == item.score
                            Button {
                                withAnimation(.easeInOut(duration: 0.20)) {
                                    visualPreviewScore = item.score
                                }
                            } label: {
                                Text(item.label)
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                                    .foregroundStyle(active ? Color.black : Color.white.opacity(0.75))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(active ? Color.cyan : Color.white.opacity(0.10))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.cyan.opacity(active ? 0 : 0.22), lineWidth: 0.7)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    Divider()

                    DebugDiagnosticsView()
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { showDebugSheet = false }
                        .foregroundStyle(Color.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    #endif
}

// MARK: - CockpitWindowFrame（左右細ストラット）

private struct CockpitWindowFrame: View {
    let accentColor: Color
    let alertIntensity: Double

    var body: some View {
        let alertR = Color(red: 0.97, green: 0.06, blue: 0.06)

        return Canvas { ctx, size in
            let sw = size.width
            let sh = size.height
            let strutW = sw * 0.09          // 細めストラット（参照画像に合わせ9%）
            let windowH = sh * 0.78         // 窓枠はスクリーン78%まで

            // ─── 左ストラット（黒塗り）
            var lStrut = Path()
            lStrut.move(to: .zero)
            lStrut.addLine(to: CGPoint(x: strutW, y: 0))
            lStrut.addLine(to: CGPoint(x: 0, y: windowH))
            lStrut.closeSubpath()
            ctx.fill(lStrut, with: .color(Color.black.opacity(0.92)))

            // ─── 右ストラット（黒塗り）
            var rStrut = Path()
            rStrut.move(to: CGPoint(x: sw, y: 0))
            rStrut.addLine(to: CGPoint(x: sw - strutW, y: 0))
            rStrut.addLine(to: CGPoint(x: sw, y: windowH))
            rStrut.closeSubpath()
            ctx.fill(rStrut, with: .color(Color.black.opacity(0.92)))

            // ─── 左内辺エッジライン
            var lEdge = Path()
            lEdge.move(to: CGPoint(x: strutW, y: 0))
            lEdge.addLine(to: CGPoint(x: 0, y: windowH))

            // ─── 右内辺エッジライン
            var rEdge = Path()
            rEdge.move(to: CGPoint(x: sw - strutW, y: 0))
            rEdge.addLine(to: CGPoint(x: sw, y: windowH))

            // ベースグロー
            ctx.stroke(lEdge, with: .color(accentColor.opacity(0.18)), lineWidth: 10)
            ctx.stroke(lEdge, with: .color(accentColor.opacity(0.72)), lineWidth: 1.3)
            ctx.stroke(rEdge, with: .color(accentColor.opacity(0.18)), lineWidth: 10)
            ctx.stroke(rEdge, with: .color(accentColor.opacity(0.72)), lineWidth: 1.3)

            // 上端ライン
            var topLine = Path()
            topLine.move(to: CGPoint(x: strutW, y: 1.5))
            topLine.addLine(to: CGPoint(x: sw - strutW, y: 1.5))
            ctx.stroke(topLine, with: .color(accentColor.opacity(0.28)), lineWidth: 1.0)
            ctx.stroke(topLine, with: .color(accentColor.opacity(0.08)), lineWidth: 8)

            // コーナードット
            ctx.fill(
                Path(ellipseIn: CGRect(x: strutW - 3, y: 0, width: 6, height: 6)),
                with: .color(accentColor.opacity(0.80))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: sw - strutW - 3, y: 0, width: 6, height: 6)),
                with: .color(accentColor.opacity(0.80))
            )

            // アラートグロー（ALERT/OVERLOAD時に赤く発光）
            if alertIntensity > 0 {
                let a = alertIntensity
                ctx.stroke(lEdge, with: .color(alertR.opacity(a * 0.45)), lineWidth: 28)
                ctx.stroke(lEdge, with: .color(alertR.opacity(a * 0.88)), lineWidth: 2.0)
                ctx.stroke(rEdge, with: .color(alertR.opacity(a * 0.45)), lineWidth: 28)
                ctx.stroke(rEdge, with: .color(alertR.opacity(a * 0.88)), lineWidth: 2.0)
                ctx.stroke(topLine, with: .color(alertR.opacity(a * 0.50)), lineWidth: 14)
                ctx.stroke(topLine, with: .color(alertR.opacity(a * 0.88)), lineWidth: 1.5)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: alertIntensity)
    }
}

// MARK: - CockpitBottomPanel（下部コックピットパネル）

private struct CockpitBottomPanel: View {
    @Binding var selectedTab: Int
    let accentColor:    Color
    let alertIntensity: Double
    let scoreIntensity: Double
    let isLive:         Bool
    let buttonGlow:     Bool
    let buttonPulse:    Double
    let heartRateText:  String
    let hasHeartRate:   Bool
    let safeBottom:     CGFloat
    let onMeasureTap:   () -> Void

    private let panelContentH: CGFloat = 186

    var body: some View {
        VStack(spacing: 0) {
            // 上端ラインとノード
            PanelTopDivider(accentColor: accentColor, alertIntensity: alertIntensity)
                .frame(height: 10)

            // メインコンテンツ
            VStack(spacing: 0) {
                // ナビゲーションレバー
                CockpitNavLever(
                    selectedTab: $selectedTab,
                    accentColor: accentColor
                )
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .frame(height: 56)

                Spacer(minLength: 4)

                // コントロール行（PULSE | 計測開始 | 波形）
                HStack(alignment: .center, spacing: 8) {
                    CockpitPulsePanel(
                        accentColor:  accentColor,
                        heartRateText: heartRateText,
                        hasData:      hasHeartRate
                    )
                    .frame(maxWidth: .infinity)

                    CockpitMeasureButton(
                        accentColor:  accentColor,
                        isLive:       isLive,
                        buttonGlow:   buttonGlow,
                        pulseDuration: buttonPulse,
                        onTap:        onMeasureTap
                    )
                    .frame(width: 76)

                    CockpitWaveformPanel(
                        intensity:   scoreIntensity,
                        accentColor: accentColor
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 72)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .frame(height: panelContentH)

            // ホームインジケーター分スペース
            Color.clear.frame(height: max(safeBottom, 4))
        }
        .background(
            CockpitPanelBackground(alertIntensity: alertIntensity)
        )
    }
}

// MARK: - パネル上端ライン

private struct PanelTopDivider: View {
    let accentColor: Color
    let alertIntensity: Double

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let ac = alertIntensity > 0
                ? Color(red: 0.97, green: 0.06, blue: 0.06)
                : accentColor
            let a = alertIntensity > 0 ? alertIntensity : 1.0

            var line = Path()
            line.move(to:    CGPoint(x: w * 0.04, y: 5))
            line.addLine(to: CGPoint(x: w * 0.96, y: 5))
            ctx.stroke(line, with: .color(ac.opacity(alertIntensity > 0 ? a * 0.45 : 0.12)), lineWidth: 12)
            ctx.stroke(line, with: .color(ac.opacity(alertIntensity > 0 ? a * 0.90 : 0.72)), lineWidth: 1.2)

            for xf in [0.04, 0.96] as [Double] {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * xf - 3.5, y: 1.5, width: 7, height: 7)),
                    with: .color(ac.opacity(0.72))
                )
            }
        }
        .animation(.easeInOut(duration: 0.8), value: alertIntensity)
    }
}

// MARK: - レバー型ナビゲーション

private struct CockpitNavLever: View {
    @Binding var selectedTab: Int
    let accentColor: Color

    // レバー位置マッピング: 整える=0(left) ホーム=1(center) 履歴=2(right)
    private var leverPos: Int {
        switch selectedTab {
        case 1:  return 0
        case 2:  return 2
        default: return 1
        }
    }

    private let navDefs: [(label: String, icon: String, tab: Int)] = [
        ("整える", "wind",       1),
        ("ホーム",  "house.fill", 0),
        ("履歴",   "clock.fill",  2),
    ]

    var body: some View {
        VStack(spacing: 4) {
            // ラベル行
            HStack(spacing: 0) {
                ForEach(navDefs.indices, id: \.self) { i in
                    let item = navDefs[i]
                    let active = selectedTab == item.tab
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.70)) {
                            selectedTab = item.tab
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: active ? .semibold : .ultraLight))
                                .foregroundStyle(active ? accentColor : Color.white.opacity(0.28))
                                .shadow(color: active ? accentColor.opacity(0.70) : .clear, radius: 5)
                            Text(item.label)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(active ? accentColor.opacity(0.92) : Color.white.opacity(0.26))
                                .tracking(0.3)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.20), value: active)
                    .accessibilityLabel(item.label)
                    .accessibilityIdentifier(
                        item.tab == 1 ? "nav_calm" :
                        item.tab == 0 ? "nav_home" : "nav_history"
                    )
                    .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                }
            }

            // レバーレール
            GeometryReader { geo in
                let w = geo.size.width
                let positions: [CGFloat] = [w * 0.17, w * 0.50, w * 0.83]
                let knobX = positions[leverPos]

                ZStack(alignment: .leading) {
                    // レール背景
                    Capsule()
                        .fill(Color(red: 0.06, green: 0.08, blue: 0.20))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))

                    // レール中央線
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.horizontal, 22)

                    // ノブグロー
                    Capsule()
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 54, height: 14)
                        .blur(radius: 7)
                        .offset(x: knobX - 27, y: 1)
                        .animation(.spring(response: 0.30, dampingFraction: 0.70), value: leverPos)

                    // ノブ本体
                    ZStack {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.28, green: 0.34, blue: 0.52),
                                        Color(red: 0.10, green: 0.13, blue: 0.28)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), .clear],
                                    startPoint: .top, endPoint: .center
                                )
                            )
                        Capsule()
                            .strokeBorder(accentColor.opacity(0.82), lineWidth: 1.0)
                    }
                    .frame(width: 50, height: 22)
                    .shadow(color: accentColor.opacity(0.50), radius: 6)
                    .offset(x: knobX - 25, y: -3)
                    .animation(.spring(response: 0.30, dampingFraction: 0.70), value: leverPos)
                }
                .frame(height: 16)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 16)
            .accessibilityIdentifier("cockpit_nav_lever")
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { v in
                        if v.translation.width > 40 {
                            // 右スワイプ → レバーを右へ
                            if leverPos == 0 { selectedTab = 0 }       // 整える→ホーム
                            else if leverPos == 1 { selectedTab = 2 }  // ホーム→履歴
                        } else if v.translation.width < -40 {
                            // 左スワイプ → レバーを左へ
                            if leverPos == 2 { selectedTab = 0 }       // 履歴→ホーム
                            else if leverPos == 1 { selectedTab = 1 }  // ホーム→整える
                        }
                    }
            )
        }
    }
}

// MARK: - 心拍パネル（左）

private struct CockpitPulsePanel: View {
    let accentColor:   Color
    let heartRateText: String
    let hasData:       Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(hasData ? Color.red.opacity(0.90) : Color.white.opacity(0.18))
                Text("PULSE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .tracking(1.0)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(heartRateText)
                    .font(.system(size: 28, weight: .thin, design: .monospaced))
                    .foregroundStyle(hasData ? Color.white : Color.white.opacity(0.20))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if heartRateText != "—" {
                    Text("BPM")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.65))
                        .offset(y: -2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accentColor.opacity(0.38), accentColor.opacity(0.12)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        )
    }
}

// MARK: - 計測開始ボタン（中央）

private struct CockpitMeasureButton: View {
    let accentColor:   Color
    let isLive:        Bool
    let buttonGlow:    Bool
    let pulseDuration: Double
    let onTap:         () -> Void

    var body: some View {
        let ac = isLive ? Color.orange : accentColor

        return Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    // 外リング
                    Circle()
                        .fill(Color(red: 0.05, green: 0.07, blue: 0.18))
                    Circle()
                        .strokeBorder(ac.opacity(buttonGlow ? 0.88 : 0.38), lineWidth: 1.5)
                        .shadow(color: ac.opacity(0.50), radius: 8)
                        .animation(
                            .easeInOut(duration: pulseDuration)
                            .repeatForever(autoreverses: true),
                            value: buttonGlow
                        )
                    Image(systemName: isLive ? "waveform" : "waveform.path.ecg")
                        .font(.system(size: 14, weight: .ultraLight))
                        .foregroundStyle(ac)
                }
                .frame(width: 44, height: 44)

                Text(isLive ? "停止" : "計測開始")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ac.opacity(0.72))
                    .tracking(0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_measure_start_button")
        .accessibilityLabel(isLive ? "計測を停止する" : "ライブ計測を開始する")
        .animation(.easeInOut(duration: 0.22), value: isLive)
    }
}

// MARK: - 心拍波形パネル（右）

private struct CockpitWaveformPanel: View {
    let intensity:   Double
    let accentColor: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // パネル背景
            ctx.fill(
                Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 10),
                with: .color(Color(red: 0.04, green: 0.06, blue: 0.16))
            )

            // ECG波形
            let midY = h * 0.54
            let amp  = h * 0.28 * (0.55 + intensity * 0.45)

            var wave = Path()
            wave.move(to:    CGPoint(x: 4, y: midY))
            wave.addLine(to: CGPoint(x: w * 0.14, y: midY))
            // P波
            wave.addCurve(
                to:       CGPoint(x: w * 0.24, y: midY),
                control1: CGPoint(x: w * 0.17, y: midY - amp * 0.35),
                control2: CGPoint(x: w * 0.22, y: midY - amp * 0.35)
            )
            wave.addLine(to: CGPoint(x: w * 0.31, y: midY))
            // QRS複合
            wave.addLine(to: CGPoint(x: w * 0.35, y: midY + amp * 0.22))
            wave.addLine(to: CGPoint(x: w * 0.39, y: midY - amp))
            wave.addLine(to: CGPoint(x: w * 0.43, y: midY + amp * 0.38))
            wave.addLine(to: CGPoint(x: w * 0.47, y: midY))
            // T波
            wave.addCurve(
                to:       CGPoint(x: w * 0.63, y: midY),
                control1: CGPoint(x: w * 0.53, y: midY - amp * 0.52),
                control2: CGPoint(x: w * 0.61, y: midY - amp * 0.52)
            )
            wave.addLine(to: CGPoint(x: w - 4, y: midY))

            ctx.stroke(wave, with: .color(accentColor.opacity(0.22)), lineWidth: 5.5)
            ctx.stroke(wave, with: .color(accentColor.opacity(0.80)), lineWidth: 1.2)

            // パネル枠線
            ctx.stroke(
                Path(roundedRect: CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1), cornerRadius: 10),
                with: .color(accentColor.opacity(0.22)), lineWidth: 0.8
            )
        }
        .animation(.easeInOut(duration: 0.8), value: intensity)
    }
}

// MARK: - コックピットパネル背景

private struct CockpitPanelBackground: View {
    let alertIntensity: Double

    var body: some View {
        let r = 0.06 + 0.18 * alertIntensity
        let r2 = 0.04 + 0.14 * alertIntensity

        return LinearGradient(
            colors: [
                Color(red: r,  green: 0.09, blue: 0.20),
                Color(red: r2, green: 0.06, blue: 0.14),
                Color(red: 0.02 + 0.08 * alertIntensity, green: 0.03, blue: 0.10)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.8), value: alertIntensity)
    }
}

// MARK: - Preview

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(MindWaveViewModel())
        .environmentObject(AppFlowState())
}
