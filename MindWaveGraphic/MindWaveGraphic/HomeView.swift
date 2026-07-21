//
//  HomeView.swift
//  MindWaveGraphic
//
//  imageUI.png 完全参照 コックピット再設計 (Iteration 1)
//  - 上部 79% = 星グラフィック完全主役
//  - 下部 21% = 暗い金属コックピット (ゲームUIではなく重厚な計器盤)
//  - ストラット: ほぼ黒、極細エッジのみ
//  - HRV/SDNN/ms/SCORE: 通常UI非表示
//  - PULSE: DEMO時に "72" 表示
//

import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var flowState: AppFlowState
    @Binding var selectedTab: Int

    @State private var showSettingsSheet    = false
    @State private var showStatusDetail     = false
    @State private var buttonPulse: Bool    = false
    #if DEBUG
    @State private var showDebugDiagnostics = false
    #endif
    #if DEBUG && targetEnvironment(simulator)
    @State private var showSimulatorDemoControls = false
    @AppStorage("sim_demo_override_enabled") private var simDemoOverrideEnabled = false
    @AppStorage("sim_demo_bpm")             private var simDemoBPM:             Double = 72.0
    @AppStorage("sim_demo_score")           private var simDemoScore:           Double = 12.0
    #endif

    // MARK: - Computed display properties

    // 実際のPULSE表示に使う心拍数値（Simulator demo override → DEMO_HEART_RATE → 実データ）
    private var heartRateNumeric: Double {
        #if DEBUG && targetEnvironment(simulator)
        if simDemoOverrideEnabled { return simDemoBPM }
        if let str = ProcessInfo.processInfo.environment["DEMO_HEART_RATE"],
           let val = Double(str) { return val }
        #endif
        if let w = viewModel.latestWatchHeartRate { return w }
        if viewModel.didFetchHeartRate { return viewModel.currentHeartRate }
        return 0
    }

    // 心拍数から表示色スコアの下限を決定（表示のみ。計算値は変えない）
    private var heartRateVisualFloor: Double {
        let hr = heartRateNumeric
        if hr >= 130 { return 85 }
        if hr >= 115 { return 72 }
        if hr >= 100 { return 55 }
        return 0
    }

    // 表示用 GraphicInput（Simulator demo override → 心拍フロア補正）
    private var displayInput: GraphicInput {
        let base = viewModel.graphicInput
        #if DEBUG && targetEnvironment(simulator)
        if simDemoOverrideEnabled {
            let corrected = max(simDemoScore, heartRateVisualFloor)
            return GraphicInput(score: corrected, confidence: base.confidence,
                                state: MindState.from(score: corrected))
        }
        #endif
        let correctedScore = max(base.score, heartRateVisualFloor)
        guard correctedScore > base.score else { return base }
        return GraphicInput(score: correctedScore, confidence: base.confidence, state: base.state)
    }

    private var hasDisplayData: Bool { viewModel.didFetchHeartRate || viewModel.didFetchHRV }

    private var scoreIntensity: Double { min(max(displayInput.score / 100.0, 0), 1) }

    private var accentColor: Color {
        let t = scoreIntensity
        if t < 0.35 { return Color(hue: 0.620, saturation: 0.92, brightness: 0.92) }
        if t < 0.62 {
            let p = (t - 0.35) / 0.27
            return Color(hue: 0.620 - p * 0.455, saturation: 0.92, brightness: 0.98)
        }
        let p = (t - 0.62) / 0.38
        let h = 0.165 - p * 0.165
        return Color(hue: max(0, h), saturation: 0.96, brightness: 1.0)
    }

    private var pulseDur: Double { 3.6 - scoreIntensity * 2.4 }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let availH   = geo.size.height
            let graphicH = availH * 0.79
            let dashH    = availH * 0.21

            ZStack(alignment: .top) {
                // 1. 宇宙背景
                Color(red: 0, green: 0.005, blue: 0.038).ignoresSafeArea()

                // 2. 星グラフィック (主役)
                GraphicHostView(input: displayInput)
                    .frame(maxWidth: .infinity)
                    .frame(height: graphicH)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                // 3. コックピット窓枠 (ほぼ黒)
                CockpitFrameCanvas(scoreIntensity: scoreIntensity, buttonPulse: buttonPulse)
                    .frame(height: graphicH)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                // 4. ヘッダー上端グラデーション (可読性確保)
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.38), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 60)
                    Spacer()
                }
                .frame(height: graphicH)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // 5. グラフィック→コックピット境界グラデーション
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [.clear,
                                 Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.55),
                                 Color(red: 0.04, green: 0.06, blue: 0.16).opacity(0.90),
                                 Color(red: 0.04, green: 0.07, blue: 0.18)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 60)
                }
                .frame(height: graphicH)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // 6. ヘッダー
                headerBar
                    .padding(.top, 8)
                    .padding(.horizontal, 18)
                    .zIndex(50)

                // 7. コックピット下部
                VStack(spacing: 0) {
                    Spacer()
                    cockpitConsole(dashH: dashH)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                buttonPulse = true
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView().environmentObject(viewModel)
        }
        #if DEBUG
        .sheet(isPresented: $showDebugDiagnostics) {
            NavigationStack {
                DebugDiagnosticsView()
                    .environmentObject(viewModel)
                    .navigationTitle("診断")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { showDebugDiagnostics = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        #endif
        #if DEBUG && targetEnvironment(simulator)
        .sheet(isPresented: $showSimulatorDemoControls) {
            NavigationStack {
                SimulatorDemoControlsView()
                    .environmentObject(viewModel)
                    .navigationTitle("DEMO CONTROLS")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { showSimulatorDemoControls = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        #endif
        .sheet(isPresented: $showStatusDetail) {
            statusDetailSheet
                .presentationDetents([.medium])
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 0) {
            // 左: 接続状態
            Button { showStatusDetail = true } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusDot)
                        .frame(width: 5, height: 5)
                        .shadow(color: statusDot.opacity(0.9), radius: 4)
                    Text(statusShort)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.44))
                        .tracking(0.8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.42))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            // センタータイトル
            VStack(spacing: 1) {
                HStack(spacing: 0) {
                    Text("MIND")
                        .font(.system(size: 17, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .tracking(5.0)
                    Text(" WAVE")
                        .font(.system(size: 17, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.98))
                        .tracking(5.0)
                        .shadow(color: accentColor.opacity(0.45), radius: 10)
                        .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
                }
                Text("STRESS & BIOMETRICS")
                    .font(.system(size: 6.5, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.32))
                    .tracking(2.5)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.48))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
            )

            Spacer()

            // 右: 設定（Simulator+DEBUGのみ長押しでデモ操作パネルを開く。実機では長押し無効）
            Button { showSettingsSheet = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            #if DEBUG && targetEnvironment(simulator)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1.5).onEnded { _ in
                    showSimulatorDemoControls = true
                }
            )
            #endif
        }
        .frame(height: 36)
    }

    // MARK: - Cockpit console (imageUI.png 参照: 暗い重厚な金属パネル)

    private func cockpitConsole(dashH: CGFloat) -> some View {
        ZStack {
            MetalPanelBackground(scoreIntensity: scoreIntensity, buttonPulse: buttonPulse)

            VStack(spacing: 0) {
                panelTopRip
                CockpitLeverNav(selectedTab: $selectedTab, accentColor: accentColor)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .padding(.top, 4)
                Spacer(minLength: 2)
                HStack(alignment: .center, spacing: 6) {
                    pulseInstrument.frame(maxWidth: .infinity)
                    mainButton
                    signalInstrument.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 10)
                Spacer(minLength: 2)
            }
        }
        .frame(height: dashH)
    }

    // MARK: - Panel top rip

    private var panelTopRip: some View {
        Canvas { ctx, size in
            let w = size.width
            let ac = accentColor

            var main = Path()
            main.move(to:    CGPoint(x: w * 0.05, y: size.height - 1.5))
            main.addLine(to: CGPoint(x: w * 0.95, y: size.height - 1.5))
            ctx.stroke(main, with: .color(ac.opacity(0.80)), lineWidth: 2.0)
            ctx.stroke(main, with: .color(ac.opacity(0.22)), lineWidth: 11)

            var sub = Path()
            sub.move(to:    CGPoint(x: w * 0.18, y: size.height - 5))
            sub.addLine(to: CGPoint(x: w * 0.82, y: size.height - 5))
            ctx.stroke(sub, with: .color(ac.opacity(0.18)), lineWidth: 0.6)

            for xf in [0.05, 0.28, 0.72, 0.95] as [Double] {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w*xf - 3, y: size.height - 4.5, width: 6, height: 6)),
                    with: .color(ac.opacity(xf == 0.05 || xf == 0.95 ? 0.72 : 0.42))
                )
                // リベット内影
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w*xf - 1.5, y: size.height - 3.0, width: 3, height: 3)),
                    with: .color(Color.black.opacity(0.55))
                )
            }
            // パネル右端スロット刻み
            var notch = Path()
            notch.move(to: CGPoint(x: w * 0.88, y: size.height - 2))
            notch.addLine(to: CGPoint(x: w * 0.92, y: size.height - 2))
            ctx.stroke(notch, with: .color(ac.opacity(0.30)), lineWidth: 1.0)
        }
        .frame(height: 16)
        .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
    }

    // MARK: - PULSE instrument

    private var pulseInstrument: some View {
        let ac = accentColor
        let hrText = heartRateText
        let hasData = hasRealHR

        return ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cr: CGFloat = 6
                ctx.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: cr),
                    with: .color(Color(red: 0.03, green: 0.055, blue: 0.14))
                )
                var hl = Path()
                hl.move(to: CGPoint(x: cr, y: 1.0)); hl.addLine(to: CGPoint(x: w - cr, y: 1.0))
                ctx.stroke(hl, with: .color(Color.white.opacity(0.18)), lineWidth: 1.0)
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0.4, y: 0.4, width: w-0.8, height: h-0.8), cornerRadius: cr),
                    with: .color(ac.opacity(0.28)), lineWidth: 0.7
                )
                // 極細グリッド (計器内部感)
                for gy in stride(from: 14.0, through: h - 8, by: 14.0) {
                    var gl = Path()
                    gl.move(to: CGPoint(x: 5, y: gy)); gl.addLine(to: CGPoint(x: w - 5, y: gy))
                    ctx.stroke(gl, with: .color(Color.white.opacity(0.022)), lineWidth: 0.4)
                }
                var le = Path()
                le.move(to: CGPoint(x: 1.2, y: cr+2)); le.addLine(to: CGPoint(x: 1.2, y: h-cr-2))
                ctx.stroke(le, with: .color(ac.opacity(0.72)), lineWidth: 2.2)
                ctx.stroke(le, with: .color(ac.opacity(0.18)), lineWidth: 7)
                var div = Path()
                div.move(to: CGPoint(x: 6, y: h - 24)); div.addLine(to: CGPoint(x: w - 6, y: h - 24))
                ctx.stroke(div, with: .color(Color.white.opacity(0.060)), lineWidth: 0.5)
                // ゲージ目盛り
                for ti in 0..<5 {
                    let tx = w * (0.16 + Double(ti) * 0.175)
                    let tLen: CGFloat = ti == 2 ? 6.5 : 3.5
                    var tk = Path()
                    tk.move(to: CGPoint(x: tx, y: h - 23))
                    tk.addLine(to: CGPoint(x: tx, y: h - 23 + tLen))
                    ctx.stroke(tk, with: .color(Color.white.opacity(ti == 2 ? 0.18 : 0.09)),
                               lineWidth: ti == 2 ? 0.7 : 0.5)
                }
            }
            .animation(.easeInOut(duration: 0.9), value: scoreIntensity)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(hasData ? ac : Color.white.opacity(0.10))
                        .frame(width: 4, height: 4)
                        .shadow(color: hasData ? ac.opacity(0.85) : .clear, radius: 4)
                    Text("PULSE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(ac.opacity(0.62))
                        .tracking(1.5)
                    Spacer()
                    Image(systemName: "heart.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(hasData
                            ? Color(red: 0.92, green: 0.22, blue: 0.24)
                            : Color.white.opacity(0.10))
                }
                .padding(.top, 6)
                .padding(.horizontal, 7)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(hrText)
                        .font(.system(size: 40, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(heartRateOpacity))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: hrText)
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 8)
                        Text("BPM")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(hasData ? 0.38 : 0.22))
                            .tracking(0.8)
                    }
                }
                .padding(.horizontal, 7)

                Spacer(minLength: 1)

                Canvas { ctx, sz in
                    let mid = sz.height * 0.52
                    let amp = (hasData || isDemoMode) ? sz.height * 0.38 : sz.height * 0.04
                    let xs: [CGFloat] = [0,0.06,0.11,0.17,0.23,0.27,0.32,0.38,0.44,
                                         0.48,0.50,0.56,0.62,0.67,0.73,0.77,0.82,0.88,0.94,0.97,1.0]
                    let ys: [CGFloat] = [0,-0.05,-0.22,0.30,0,-0.90,1.0,-0.30,0.32,
                                         0,0,-0.05,-0.22,0.30,0,-0.90,1.0,-0.30,0.32,0,0]
                    var p = Path()
                    for i in 0..<xs.count {
                        let pt = CGPoint(x: xs[i] * sz.width, y: mid - ys[i] * amp)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    let a: CGFloat = (hasData || isDemoMode) ? 0.58 : 0.07
                    ctx.stroke(p, with: .color(Color.cyan.opacity(a * 0.22)), lineWidth: 2.8)
                    ctx.stroke(p, with: .color(Color.cyan.opacity(a)), lineWidth: 0.80)
                }
                .frame(height: 17)
                .padding(.horizontal, 7)
                .padding(.bottom, 6)
            }
        }
        .frame(minHeight: 76)
    }

    // MARK: - Main measurement button

    private var mainButton: some View {
        let ac: Color = viewModel.isLiveMonitoring ? .orange : accentColor
        let gi = 0.68 + scoreIntensity * 0.28

        return Button { viewModel.toggleLiveMonitoring() } label: {
            ZStack {
                Circle()
                    .stroke(AngularGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04),
                                 Color.white.opacity(0.04), Color.white.opacity(0.12),
                                 Color.white.opacity(0.18)],
                        center: .center), lineWidth: 1.6)
                    .frame(width: 126, height: 126)

                Circle().stroke(ac.opacity(0.15), lineWidth: 0.8).frame(width: 118, height: 118)
                Circle()
                    .stroke(ac.opacity(gi), lineWidth: 2.0)
                    .frame(width: 108, height: 108)
                    .shadow(color: ac.opacity(0.75), radius: 7)
                    .shadow(color: ac.opacity(0.28), radius: 16)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)
                Circle().stroke(ac.opacity(0.22), lineWidth: 0.6).frame(width: 96, height: 96)
                Circle()
                    .stroke(LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                    .frame(width: 86, height: 86)
                Circle().stroke(ac.opacity(0.12), lineWidth: 0.5).frame(width: 74, height: 74)

                Circle()
                    .fill(RadialGradient(
                        colors: [
                            Color(hue: viewModel.isLiveMonitoring ? 0.07
                                  : max(0, 0.635 - scoreIntensity * 0.50),
                                  saturation: 0.90, brightness: 0.14 + scoreIntensity * 0.18),
                            Color(red: 0.02, green: 0.04, blue: 0.14),
                            Color.black.opacity(0.96)
                        ],
                        center: UnitPoint(x: 0.30, y: 0.22),
                        startRadius: 0, endRadius: 36))
                    .frame(width: 68, height: 68)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.04), .clear],
                        startPoint: UnitPoint(x: 0.18, y: 0.04),
                        endPoint: UnitPoint(x: 0.58, y: 0.50)))
                    .frame(width: 68, height: 68)

                VStack(spacing: 4) {
                    Image(systemName: viewModel.isLiveMonitoring ? "waveform" : "waveform.path.ecg")
                        .font(.system(size: 15, weight: .ultraLight))
                        .foregroundStyle(ac.opacity(0.98))
                        .shadow(color: ac, radius: 8)
                    Text(viewModel.isLiveMonitoring ? "停止" : "計測開始")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .tracking(0.6)
                }
            }
            .frame(width: 126, height: 126)
            .overlay(
                Circle()
                    .stroke(ac.opacity(buttonPulse ? 0.22 : 0.01), lineWidth: 1.0)
                    .scaleEffect(buttonPulse ? 1.20 : 0.88)
                    .frame(width: 144, height: 144)
                    .blur(radius: 2)
                    .animation(.easeInOut(duration: pulseDur).repeatForever(autoreverses: true),
                               value: buttonPulse)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.20), value: viewModel.isLiveMonitoring)
        .accessibilityIdentifier("home_measure_start_button")
        .accessibilityLabel(viewModel.isLiveMonitoring ? "計測を停止する" : "ライブ計測を開始する")
        .overlay(
            Canvas { ctx, size in
                let cx = size.width / 2, cy = size.height / 2
                let outerR = size.width / 2 - 1.2
                for i in 0..<24 {
                    let angle = Double(i) * (.pi / 12.0) - .pi / 2.0
                    let isCard = (i % 6 == 0)
                    guard isCard || (i % 3 == 0) else { continue }
                    let tLen: Double = isCard ? 6.5 : 3.0
                    let x1 = cx + outerR * cos(angle)
                    let y1 = cy + outerR * sin(angle)
                    let x2 = cx + (outerR - tLen) * cos(angle)
                    let y2 = cy + (outerR - tLen) * sin(angle)
                    var tp = Path()
                    tp.move(to: CGPoint(x: x1, y: y1))
                    tp.addLine(to: CGPoint(x: x2, y: y2))
                    let cc = viewModel.isLiveMonitoring ? Color.orange : accentColor
                    ctx.stroke(tp, with: .color(cc.opacity(isCard ? 0.52 : 0.24)),
                               lineWidth: isCard ? 1.0 : 0.55)
                    if isCard {
                        ctx.fill(Path(ellipseIn: CGRect(x: x1-1.6, y: y1-1.6, width: 3.2, height: 3.2)),
                                 with: .color(cc.opacity(0.62)))
                    }
                }
            }
            .frame(width: 150, height: 150)
            .allowsHitTesting(false)
        )
        .overlay(
            Group {
                if scoreIntensity > 0.66 {
                    let t = min(1, (scoreIntensity - 0.66) / 0.34)
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color(red: 0.92, green: 0.22, blue: 0.04)
                                        .opacity(buttonPulse ? 0.52 : 0.22),
                                    Color(red: 0.80, green: 0.04, blue: 0.04)
                                        .opacity(buttonPulse ? 0.36 : 0.12),
                                    Color(red: 0.92, green: 0.22, blue: 0.04)
                                        .opacity(buttonPulse ? 0.52 : 0.22)
                                ],
                                center: .center),
                            lineWidth: 1.2)
                        .frame(width: 158, height: 158)
                        .blur(radius: 3.5)
                        .opacity(t)
                        .animation(.easeInOut(duration: 0.78), value: buttonPulse)
                }
            }
            .animation(.easeInOut(duration: 0.9), value: scoreIntensity)
        )
    }

    // MARK: - SIGNAL instrument

    private var signalInstrument: some View {
        let ac = accentColor
        let hasData = hasDisplayData

        return ZStack(alignment: .topTrailing) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cr: CGFloat = 6
                ctx.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: cr),
                    with: .color(Color(red: 0.02, green: 0.048, blue: 0.13))
                )
                var hl = Path()
                hl.move(to: CGPoint(x: cr, y: 1.0)); hl.addLine(to: CGPoint(x: w - cr, y: 1.0))
                ctx.stroke(hl, with: .color(Color.white.opacity(0.16)), lineWidth: 1.0)
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0.4, y: 0.4, width: w-0.8, height: h-0.8), cornerRadius: cr),
                    with: .color(ac.opacity(0.26)), lineWidth: 0.7
                )
                // 極細グリッド (計器内部感)
                for gy in stride(from: 14.0, through: h - 8, by: 14.0) {
                    var gl = Path()
                    gl.move(to: CGPoint(x: 5, y: gy)); gl.addLine(to: CGPoint(x: w - 5, y: gy))
                    ctx.stroke(gl, with: .color(Color.white.opacity(0.022)), lineWidth: 0.4)
                }
                var re = Path()
                re.move(to: CGPoint(x: w - 1.2, y: cr+2)); re.addLine(to: CGPoint(x: w - 1.2, y: h-cr-2))
                ctx.stroke(re, with: .color(ac.opacity(0.70)), lineWidth: 2.2)
                ctx.stroke(re, with: .color(ac.opacity(0.16)), lineWidth: 7)
                var div = Path()
                div.move(to: CGPoint(x: 6, y: h - 24)); div.addLine(to: CGPoint(x: w - 6, y: h - 24))
                ctx.stroke(div, with: .color(Color.white.opacity(0.060)), lineWidth: 0.5)
                // ゲージ目盛り
                for ti in 0..<5 {
                    let tx = w * (0.16 + Double(ti) * 0.175)
                    let tLen: CGFloat = ti == 2 ? 6.5 : 3.5
                    var tk = Path()
                    tk.move(to: CGPoint(x: tx, y: h - 23))
                    tk.addLine(to: CGPoint(x: tx, y: h - 23 + tLen))
                    ctx.stroke(tk, with: .color(Color.white.opacity(ti == 2 ? 0.18 : 0.09)),
                               lineWidth: ti == 2 ? 0.7 : 0.5)
                }
            }
            .animation(.easeInOut(duration: 0.9), value: scoreIntensity)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 4) {
                    Text("SIGNAL")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(ac.opacity(0.60))
                        .tracking(1.2)
                    Circle()
                        .fill(hasData ? ac : Color.white.opacity(0.10))
                        .frame(width: 4, height: 4)
                        .shadow(color: hasData ? ac.opacity(0.85) : .clear, radius: 4)
                }
                .padding(.top, 6)
                .padding(.horizontal, 7)

                Text(hasData ? (viewModel.isLiveMonitoring ? "LIVE" : "ACTIVE") : "STANDBY")
                    .font(.system(size: 14, weight: .thin, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(hasData ? 0.88 : 0.14))
                    .lineLimit(1).minimumScaleFactor(0.70)
                    .tracking(0.3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 7)
                    .padding(.top, 2)
                    .animation(.easeInOut(duration: 0.35), value: hasData)

                if hasData {
                    HStack(spacing: 3) {
                        Image(systemName: "brain")
                            .font(.system(size: 6, weight: .medium))
                            .foregroundStyle(ac.opacity(0.32))
                        Text("AI INSIGHT READY")
                            .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(ac.opacity(0.28))
                            .tracking(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 7)
                    .padding(.top, 1)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.50), value: hasData)
                }

                Spacer(minLength: 1)

                Canvas { ctx, sz in
                    let mid = sz.height * 0.52
                    let amp = hasData ? sz.height * 0.34 : sz.height * 0.04
                    let xs: [CGFloat] = [0,0.08,0.14,0.20,0.28,0.32,0.36,0.42,
                                         0.50,0.54,0.62,0.68,0.74,0.82,0.86,0.90,0.96,1.0]
                    let ys: [CGFloat] = [0,-0.04,0.18,-0.12,0,-0.85,1.0,-0.28,
                                         0,0,-0.04,0.18,-0.12,0,-0.85,1.0,-0.28,0]
                    var p = Path()
                    for i in 0..<xs.count {
                        let pt = CGPoint(x: xs[i] * sz.width, y: mid - ys[i] * amp)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    let a: CGFloat = hasData ? 0.55 : 0.07
                    ctx.stroke(p, with: .color(ac.opacity(a * 0.22)), lineWidth: 2.8)
                    ctx.stroke(p, with: .color(ac.opacity(a)), lineWidth: 0.80)
                }
                .frame(height: 17)
                .padding(.horizontal, 7)
                .padding(.bottom, 6)
            }
        }
        .frame(minHeight: 76)
    }

    // MARK: - Status detail sheet

    private var statusDetailSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Circle().fill(statusDot).frame(width: 9, height: 9)
                        .shadow(color: statusDot.opacity(0.8), radius: 4)
                    Text(statusTitle).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(statusBody)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineSpacing(3)
                Divider().background(Color.white.opacity(0.10))
                HStack {
                    metricCell(label: "データソース", value: dataSourceText, color: statusDot)
                    Divider().frame(height: 24)
                    metricCell(label: "状態",
                               value: viewModel.isLiveMonitoring ? "計測中" : "停止中",
                               color: viewModel.isLiveMonitoring ? .cyan : Color.white.opacity(0.3))
                }
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                Spacer()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.02, green: 0.02, blue: 0.07).ignoresSafeArea())
            .navigationTitle("ミッションステータス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { showStatusDetail = false }.foregroundStyle(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func metricCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var isDemoMode: Bool { viewModel.activeDataSource == .mock }

    private var hasRealHR: Bool {
        viewModel.latestWatchHeartRate != nil || viewModel.didFetchHeartRate
    }

    private var heartRateText: String {
        #if DEBUG && targetEnvironment(simulator)
        if simDemoOverrideEnabled { return String(format: "%.0f", simDemoBPM) }
        if let str = ProcessInfo.processInfo.environment["DEMO_HEART_RATE"],
           let val = Double(str) { return String(format: "%.0f", val) }
        #endif
        if let w = viewModel.latestWatchHeartRate { return String(format: "%.0f", w) }
        if viewModel.didFetchHeartRate            { return String(format: "%.0f", viewModel.currentHeartRate) }
        if isDemoMode { return "72" }
        return "—"
    }

    private var heartRateOpacity: Double {
        if hasRealHR   { return 0.97 }
        if isDemoMode  { return 0.55 }
        return 0.14
    }

    private var statusDot: Color {
        switch viewModel.activeDataSource {
        case .watchLive:   return .cyan
        case .healthKit:   return Color(red: 0.16, green: 0.82, blue: 0.55)
        case .mock:        return .orange
        case .unavailable: return Color.white.opacity(0.20)
        }
    }

    private var statusShort: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return viewModel.isLiveMonitoring ? "LIVE" : "WATCH"
        case .healthKit:   return "HK"
        case .mock:        return "DEMO"
        case .unavailable: return "STANDBY"
        }
    }

    private var dataSourceText: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return "Watch Live"
        case .healthKit:   return "HealthKit"
        case .mock:        return "デモ"
        case .unavailable: return "未接続"
        }
    }

    private var statusTitle: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return viewModel.isLiveMonitoring ? "リアルタイム計測中" : "計測できます"
        case .healthKit:   return "HealthKit 読み込み中"
        case .mock:        return "デモモード"
        case .unavailable: return "データを待っています"
        }
    }

    private var statusBody: String {
        switch viewModel.activeDataSource {
        case .watchLive:
            return (viewModel.didFetchHeartRate || viewModel.didFetchHRV)
                ? "状態グラフィックがリアルタイムの心理的揺らぎを反映しています。"
                : "Apple Watch を装着したままお待ちください。"
        case .healthKit:   return "HealthKit に記録された最新データを表示しています。"
        case .mock:        return "Apple Watch を接続すると実データへ切り替わります。"
        case .unavailable: return "計測を開始するとデータが届きます。"
        }
    }

}

// MARK: - CockpitFrameCanvas (imageUI.png: ほぼ黒のストラット)

private struct CockpitFrameCanvas: View {
    let scoreIntensity: Double
    let buttonPulse: Bool

    var body: some View {
        Canvas { ctx, size in
            let sw = size.width
            let sh = size.height
            let strutW  = sw * 0.118
            let strutH  = sh * 0.93
            let bridgeY = sh * 0.85

            var lS = Path()
            lS.move(to: .zero)
            lS.addLine(to: CGPoint(x: strutW, y: 0))
            lS.addLine(to: CGPoint(x: 0, y: strutH))
            lS.closeSubpath()
            ctx.fill(lS, with: .color(Color.black.opacity(0.97)))

            var lI = Path()
            lI.move(to: CGPoint(x: strutW, y: 0))
            lI.addLine(to: CGPoint(x: strutW * 0.70, y: 0))
            lI.addLine(to: CGPoint(x: 0, y: strutH * 0.65))
            lI.addLine(to: CGPoint(x: 0, y: strutH))
            lI.closeSubpath()
            ctx.fill(lI, with: .color(Color(red: 0.015, green: 0.030, blue: 0.090).opacity(0.28)))

            var rS = Path()
            rS.move(to: CGPoint(x: sw, y: 0))
            rS.addLine(to: CGPoint(x: sw - strutW, y: 0))
            rS.addLine(to: CGPoint(x: sw, y: strutH))
            rS.closeSubpath()
            ctx.fill(rS, with: .color(Color.black.opacity(0.97)))

            var rI = Path()
            rI.move(to: CGPoint(x: sw - strutW, y: 0))
            rI.addLine(to: CGPoint(x: sw - strutW * 0.70, y: 0))
            rI.addLine(to: CGPoint(x: sw, y: strutH * 0.65))
            rI.addLine(to: CGPoint(x: sw, y: strutH))
            rI.closeSubpath()
            ctx.fill(rI, with: .color(Color(red: 0.015, green: 0.030, blue: 0.090).opacity(0.28)))

            // ガラス反射光（ストラット内側の光沢感）
            let refOp = 0.055 + scoreIntensity * 0.030
            var refL1 = Path()
            refL1.move(to: CGPoint(x: strutW * 0.03, y: sh * 0.07))
            refL1.addLine(to: CGPoint(x: strutW * 0.58, y: sh * 0.05))
            ctx.stroke(refL1, with: .color(Color.white.opacity(refOp)), lineWidth: 0.65)
            var refL2 = Path()
            refL2.move(to: CGPoint(x: strutW * 0.03, y: sh * 0.17))
            refL2.addLine(to: CGPoint(x: strutW * 0.46, y: sh * 0.15))
            ctx.stroke(refL2, with: .color(Color.white.opacity(refOp * 0.50)), lineWidth: 0.45)
            var refR1 = Path()
            refR1.move(to: CGPoint(x: sw - strutW * 0.03, y: sh * 0.07))
            refR1.addLine(to: CGPoint(x: sw - strutW * 0.58, y: sh * 0.05))
            ctx.stroke(refR1, with: .color(Color.white.opacity(refOp)), lineWidth: 0.65)
            var refR2 = Path()
            refR2.move(to: CGPoint(x: sw - strutW * 0.03, y: sh * 0.17))
            refR2.addLine(to: CGPoint(x: sw - strutW * 0.46, y: sh * 0.15))
            ctx.stroke(refR2, with: .color(Color.white.opacity(refOp * 0.50)), lineWidth: 0.45)

            let bridgeH = sh - bridgeY
            var bL = Path()
            bL.move(to: CGPoint(x: 0, y: bridgeY))
            bL.addLine(to: CGPoint(x: sw * 0.20, y: bridgeY + bridgeH * 0.10))
            bL.addLine(to: CGPoint(x: sw * 0.38, y: sh))
            bL.addLine(to: CGPoint(x: 0, y: sh))
            bL.closeSubpath()
            ctx.fill(bL, with: .color(Color.black.opacity(0.95)))

            var bR = Path()
            bR.move(to: CGPoint(x: sw, y: bridgeY))
            bR.addLine(to: CGPoint(x: sw * 0.80, y: bridgeY + bridgeH * 0.10))
            bR.addLine(to: CGPoint(x: sw * 0.62, y: sh))
            bR.addLine(to: CGPoint(x: sw, y: sh))
            bR.closeSubpath()
            ctx.fill(bR, with: .color(Color.black.opacity(0.95)))

            let eOff = strutW

            var lE = Path()
            lE.move(to: CGPoint(x: eOff, y: 0))
            lE.addLine(to: CGPoint(x: 0, y: strutH - 1))
            ctx.stroke(lE, with: .color(Color(hue: 0.625, saturation: 0.75, brightness: 0.85).opacity(0.10 + scoreIntensity * 0.06)), lineWidth: 9)
            ctx.stroke(lE, with: .color(Color.white.opacity(0.14)), lineWidth: 0.7)

            var rE = Path()
            rE.move(to: CGPoint(x: sw - eOff, y: 0))
            rE.addLine(to: CGPoint(x: sw, y: strutH - 1))
            ctx.stroke(rE, with: .color(Color(hue: 0.625, saturation: 0.75, brightness: 0.85).opacity(0.10 + scoreIntensity * 0.06)), lineWidth: 9)
            ctx.stroke(rE, with: .color(Color.white.opacity(0.14)), lineWidth: 0.7)

            var tL = Path()
            tL.move(to: CGPoint(x: eOff, y: 1))
            tL.addLine(to: CGPoint(x: sw - eOff, y: 1))
            ctx.stroke(tL, with: .color(Color.white.opacity(0.07)), lineWidth: 0.6)

            // HUDコーナーブラケット（ビューポート上角マーカー）
            let bLen: CGFloat = 13
            let bOff: CGFloat = eOff + 5
            let bY:   CGFloat = 12
            let bCol = Color(hue: 0.625, saturation: 0.55, brightness: 0.85)
                .opacity(0.30 + scoreIntensity * 0.14)
            var bTL1 = Path()
            bTL1.move(to: CGPoint(x: bOff, y: bY))
            bTL1.addLine(to: CGPoint(x: bOff + bLen, y: bY))
            ctx.stroke(bTL1, with: .color(bCol), lineWidth: 0.8)
            var bTL2 = Path()
            bTL2.move(to: CGPoint(x: bOff, y: bY))
            bTL2.addLine(to: CGPoint(x: bOff, y: bY + bLen))
            ctx.stroke(bTL2, with: .color(bCol), lineWidth: 0.8)
            let bOffR = sw - eOff - 5
            var bTR1 = Path()
            bTR1.move(to: CGPoint(x: bOffR, y: bY))
            bTR1.addLine(to: CGPoint(x: bOffR - bLen, y: bY))
            ctx.stroke(bTR1, with: .color(bCol), lineWidth: 0.8)
            var bTR2 = Path()
            bTR2.move(to: CGPoint(x: bOffR, y: bY))
            bTR2.addLine(to: CGPoint(x: bOffR, y: bY + bLen))
            ctx.stroke(bTR2, with: .color(bCol), lineWidth: 0.8)

            let alertT = max(0.0, scoreIntensity - 0.66) / 0.34
            if alertT > 0.01 {
                let red = Color(red: 0.96, green: 0.06, blue: 0.06)
                var laG = Path()
                laG.move(to: CGPoint(x: eOff, y: 0))
                laG.addLine(to: CGPoint(x: 0, y: strutH - 1))
                ctx.stroke(laG, with: .color(red.opacity(alertT * 0.30)), lineWidth: 16)
                ctx.stroke(laG, with: .color(red.opacity(alertT * 0.52)), lineWidth: 3.5)
                ctx.stroke(laG, with: .color(red.opacity(alertT * 0.72)), lineWidth: 1.2)
                var raG = Path()
                raG.move(to: CGPoint(x: sw - eOff, y: 0))
                raG.addLine(to: CGPoint(x: sw, y: strutH - 1))
                ctx.stroke(raG, with: .color(red.opacity(alertT * 0.30)), lineWidth: 16)
                ctx.stroke(raG, with: .color(red.opacity(alertT * 0.52)), lineWidth: 3.5)
                ctx.stroke(raG, with: .color(red.opacity(alertT * 0.72)), lineWidth: 1.2)
                var taG = Path()
                taG.move(to: CGPoint(x: eOff, y: 1))
                taG.addLine(to: CGPoint(x: sw - eOff, y: 1))
                ctx.stroke(taG, with: .color(red.opacity(alertT * 0.36)), lineWidth: 9)
                ctx.stroke(taG, with: .color(red.opacity(alertT * 0.65)), lineWidth: 1.0)
            }
        }
        .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
    }
}

// MARK: - MetalPanelBackground

private struct MetalPanelBackground: View {
    let scoreIntensity: Double
    let buttonPulse: Bool

    private func alertAwareAccent(_ t: Double) -> Color {
        if t < 0.35 { return Color(hue: 0.62, saturation: 0.90, brightness: 0.90) }
        if t < 0.62 { return Color(hue: 0.62 - (t-0.35)/0.27 * 0.45, saturation: 0.92, brightness: 0.98) }
        let p = (t - 0.62) / 0.38
        return Color(hue: max(0, 0.17 - p * 0.17), saturation: 0.96, brightness: 1.0)
    }

    var body: some View {
        let ac = alertAwareAccent(scoreIntensity)

        return ZStack {
            CockpitPanelShape(chamfer: 22)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.045, green: 0.075, blue: 0.18),
                        Color(red: 0.025, green: 0.042, blue: 0.10),
                        Color(red: 0.010, green: 0.018, blue: 0.055)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))

            // 水平マイクロスキャンライン（電子計器パネル感）
            Canvas { ctx, size in
                for i in 0..<8 {
                    let y = size.height * (0.16 + Double(i) * 0.105)
                    var sl = Path()
                    sl.move(to: CGPoint(x: size.width * 0.04, y: y))
                    sl.addLine(to: CGPoint(x: size.width * 0.96, y: y))
                    ctx.stroke(sl, with: .color(Color.white.opacity(0.013)), lineWidth: 0.4)
                }
            }
            .clipShape(CockpitPanelShape(chamfer: 22))
            .allowsHitTesting(false)

            CockpitPanelShape(chamfer: 22)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.055), .clear],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.14)
                ))

            CockpitPanelShape(chamfer: 22)
                .stroke(ac.opacity(0.38), lineWidth: 0.8)
                .animation(.easeInOut(duration: 1.0), value: scoreIntensity)

            // 上端ハイライトリップ（計器パネル感）
            CockpitPanelShape(chamfer: 22)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.08), .clear],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.04)
                ))

            if scoreIntensity > 0.58 {
                let t = min(1.0, (scoreIntensity - 0.58) / 0.42)
                CockpitPanelShape(chamfer: 22)
                    .fill(Color(red: 0.55 * t, green: 0, blue: 0).opacity(0.18))
                    .animation(.easeInOut(duration: 0.9), value: scoreIntensity)
                CockpitPanelShape(chamfer: 22)
                    .stroke(Color(red: 0.96, green: 0.05, blue: 0.05).opacity(t * 0.72), lineWidth: 0.9)
                    .animation(.easeInOut(duration: 0.9), value: scoreIntensity)
                CockpitPanelShape(chamfer: 22)
                    .stroke(Color(red: 1.0, green: 0.04, blue: 0.04)
                        .opacity(t * (buttonPulse ? 0.55 : 0.26)), lineWidth: 3.0)
                    .blur(radius: 4)
                    .animation(.easeInOut(duration: 0.8), value: buttonPulse)
            }
        }
    }
}

// MARK: - CockpitLeverNav (shared across Home/Guide/History panels)

struct CockpitLeverNav: View {
    @Binding var selectedTab: Int
    let accentColor: Color

    private var leverPos: Int {
        switch selectedTab { case 1: return 0; case 2: return 2; default: return 1 }
    }

    private let navItems: [(label: String, icon: String, tab: Int)] = [
        ("整える", "wind",       1),
        ("ホーム",  "house.fill", 0),
        ("履歴",   "clock.fill",  2),
    ]

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(navItems.indices, id: \.self) { i in
                    let item = navItems[i]
                    let active = selectedTab == item.tab
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.64)) {
                            selectedTab = item.tab
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: active ? .semibold : .ultraLight))
                                .foregroundStyle(active ? accentColor : Color.white.opacity(0.22))
                                .shadow(color: active ? accentColor.opacity(0.65) : .clear, radius: 4)
                            Text(item.label)
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(active ? accentColor.opacity(0.88) : Color.white.opacity(0.20))
                        }
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.18), value: active)
                    .accessibilityIdentifier(item.tab == 1 ? "nav_calm" : item.tab == 0 ? "nav_home" : "nav_history")
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let positions: [CGFloat] = [w * 0.163, w * 0.500, w * 0.837]
                let knobX = positions[leverPos]

                ZStack(alignment: .leading) {
                    Canvas { ctx, size in
                        let rw = size.width, rh = size.height
                        let cr: CGFloat = rh / 2
                        ctx.fill(
                            Path(roundedRect: CGRect(x: 0, y: 0, width: rw, height: rh), cornerRadius: cr),
                            with: .color(Color(red: 0.05, green: 0.09, blue: 0.20))
                        )
                        ctx.fill(
                            Path(roundedRect: CGRect(x: 2, y: 2, width: rw-4, height: rh-4), cornerRadius: cr-2),
                            with: .color(Color(red: 0.02, green: 0.03, blue: 0.10))
                        )
                        var rail = Path()
                        rail.move(to: CGPoint(x: cr, y: rh/2))
                        rail.addLine(to: CGPoint(x: rw-cr, y: rh/2))
                        ctx.stroke(rail, with: .color(Color.white.opacity(0.06)), lineWidth: 0.8)
                        ctx.stroke(
                            Path(roundedRect: CGRect(x: 0.4, y: 0.4, width: rw-0.8, height: rh-0.8), cornerRadius: cr),
                            with: .color(Color.white.opacity(0.08)), lineWidth: 0.5
                        )
                        for xf in [0.163, 0.500, 0.837] as [Double] {
                            let mx = rw * xf
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: mx-1.8, y: rh/2-1.8, width: 3.6, height: 3.6)),
                                with: .color(Color.white.opacity(0.14))
                            )
                        }
                    }
                    .frame(height: 15)

                    Capsule()
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 40, height: 11)
                        .blur(radius: 6)
                        .offset(x: knobX - 20, y: 2)
                        .animation(.spring(response: 0.26, dampingFraction: 0.64), value: leverPos)

                    ZStack {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.22, green: 0.30, blue: 0.52),
                                         Color(red: 0.08, green: 0.12, blue: 0.26)],
                                startPoint: .top, endPoint: .bottom))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.24), .clear],
                                startPoint: .top, endPoint: .center))
                        Capsule().strokeBorder(accentColor.opacity(0.88), lineWidth: 1.0)
                        HStack(spacing: 3.5) {
                            ForEach(0..<3, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: 1, height: 8)
                            }
                        }
                    }
                    .frame(width: 48, height: 20)
                    .shadow(color: accentColor.opacity(0.50), radius: 6)
                    .shadow(color: .black.opacity(0.40), radius: 3, y: 2)
                    .offset(x: knobX - 24, y: -2.5)
                    .animation(.spring(response: 0.26, dampingFraction: 0.64), value: leverPos)
                }
                .frame(height: 15)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { v in
                            withAnimation {
                                if v.translation.width > 40 {
                                    selectedTab = leverPos == 0 ? 0 : leverPos == 1 ? 2 : 2
                                } else if v.translation.width < -40 {
                                    selectedTab = leverPos == 2 ? 0 : leverPos == 1 ? 1 : 1
                                }
                            }
                        }
                )
            }
            .frame(height: 15)
        }
    }
}

// MARK: - Simulator Demo Controls

#if DEBUG && targetEnvironment(simulator)
private struct SimulatorDemoControlsView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel

    @AppStorage("sim_demo_override_enabled") private var overrideEnabled = false
    @AppStorage("sim_demo_bpm")             private var demoBPM:         Double = 72.0
    @AppStorage("sim_demo_score")           private var demoScore:       Double = 12.0

    private var hrFloor: Double {
        if demoBPM >= 130 { return 85 }
        if demoBPM >= 115 { return 72 }
        if demoBPM >= 100 { return 55 }
        return 0
    }

    private var displayScore: Double {
        overrideEnabled ? max(demoScore, hrFloor) : viewModel.graphicInput.score
    }

    private var derivedStateName: String {
        let s = displayScore / 100.0
        if s < 0.25 { return "CALM" }
        if s < 0.55 { return "FOCUS" }
        if s < 0.78 { return "ALERT" }
        return "OVLD"
    }

    private var derivedStateColor: Color {
        let s = displayScore / 100.0
        if s < 0.25 { return Color(hue: 0.62, saturation: 0.80, brightness: 0.88) }
        if s < 0.55 { return Color(hue: 0.48, saturation: 0.85, brightness: 0.90) }
        if s < 0.78 { return Color(hue: 0.08, saturation: 0.92, brightness: 0.98) }
        return Color(hue: 0.01, saturation: 0.96, brightness: 1.0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── ヘッダー
                VStack(alignment: .leading, spacing: 4) {
                    Text("SIMULATOR DEMO CONTROLS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.88))
                        .tracking(1.5)
                    Text("Simulator only. Not compiled into device builds.")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                Divider().background(Color.cyan.opacity(0.25))

                // ── Demo Override トグル
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DEMO OVERRIDE")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(overrideEnabled ? Color.cyan : Color.white.opacity(0.55))
                            .tracking(1)
                        Text(overrideEnabled ? "ON — demo values active" : "OFF — real sensor data")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    Spacer()
                    Toggle("", isOn: $overrideEnabled).labelsHidden().tint(.cyan)
                }

                Divider().background(Color.white.opacity(0.08))

                // ── Heart Rate / BPM スライダー
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("HEART RATE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .tracking(1)
                        Spacer()
                        Text(String(format: "%.0f BPM", demoBPM))
                            .font(.system(size: 16, weight: .thin, design: .monospaced))
                            .foregroundStyle(overrideEnabled ? Color.white : Color.white.opacity(0.30))
                            .monospacedDigit()
                    }
                    Slider(value: $demoBPM, in: 40...170, step: 1)
                        .tint(derivedStateColor)
                        .disabled(!overrideEnabled)

                    // BPM プリセット
                    HStack(spacing: 6) {
                        bpmButton("CALM",   72)
                        bpmButton("FOCUS", 100)
                        bpmButton("ALERT", 115)
                        bpmButton("OVLD",  130)
                        bpmButton("MAX",   150)
                    }
                }

                Divider().background(Color.white.opacity(0.08))

                // ── Visual Score スライダー
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("VISUAL SCORE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .tracking(1)
                        Spacer()
                        Text(String(format: "%.0f / 100", demoScore))
                            .font(.system(size: 14, weight: .thin, design: .monospaced))
                            .foregroundStyle(overrideEnabled ? Color.white : Color.white.opacity(0.30))
                            .monospacedDigit()
                    }
                    Slider(value: $demoScore, in: 0...100, step: 1)
                        .tint(derivedStateColor)
                        .disabled(!overrideEnabled)
                }

                Divider().background(Color.white.opacity(0.08))

                // ── State Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("STATE PREVIEW")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .tracking(1)

                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(derivedStateColor)
                                .frame(width: 10, height: 10)
                                .shadow(color: derivedStateColor.opacity(0.80), radius: 8)
                            Text(derivedStateName)
                                .font(.system(size: 22, weight: .black, design: .monospaced))
                                .foregroundStyle(derivedStateColor)
                                .shadow(color: derivedStateColor.opacity(0.50), radius: 8)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            infoRow("BPM",           overrideEnabled ? String(format: "%.0f", demoBPM) : "—")
                            infoRow("raw score",     String(format: "%.0f", viewModel.graphicInput.score))
                            infoRow("display score", String(format: "%.0f", displayScore))
                            infoRow("source",        overrideEnabled ? "simulator demo" : "real / sensor")
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.60))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(derivedStateColor.opacity(0.40), lineWidth: 1))
                    )
                }

                Divider().background(Color.white.opacity(0.08))

                // ── Reset ボタン
                Button {
                    overrideEnabled = false
                    demoBPM   = 72.0
                    demoScore = 12.0
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("RESET TO DEFAULT")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundStyle(Color.orange.opacity(0.80))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 32)
            }
            .padding(20)
        }
        .background(Color(red: 0.02, green: 0.04, blue: 0.12).ignoresSafeArea())
    }

    private func bpmButton(_ label: String, _ bpm: Double) -> some View {
        let isActive = abs(demoBPM - bpm) < 0.5 && overrideEnabled
        return Button { demoBPM = bpm } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                Text(String(format: "%.0f", bpm))
                    .font(.system(size: 9, weight: .thin, design: .monospaced))
            }
            .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.65))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? derivedStateColor : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(!overrideEnabled)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.40))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
                .monospacedDigit()
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(MindWaveViewModel())
        .environmentObject(AppFlowState())
}
