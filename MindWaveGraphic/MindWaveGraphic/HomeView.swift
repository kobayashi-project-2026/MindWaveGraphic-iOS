//
//  HomeView.swift
//  MindWaveGraphic
//
//  Iteration 1: imageUI.png 本気再設計
//  グラフィック78% / コックピット22%
//  ストラット: ほぼ黒（暗い金属、発光最小限）
//  QAパレット: デバッグシートに移動（本番UI非表示）
//  PULSE: デモ時に"72"を表示
//  星グラフィックが主役、コックピットは添え
//
//  HRV / SDNN / ms / SCORE 通常UI非表示
//

import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var flowState: AppFlowState
    @Binding var selectedTab: Int

    @State private var showSettingsSheet  = false
    @State private var showDebugSheet     = false
    @State private var showStatusDetail   = false
    @State private var buttonGlow: Bool   = false

    #if DEBUG
    @State private var visualPreviewScore: Double? = nil
    private let visualQAStates: [(label: String, id: String, score: Double?)] = [
        ("OFF",  "off",      nil),
        ("CALM", "calm",     12.0),
        ("FCUS", "focus",    40.0),
        ("ALRT", "alert",    70.0),
        ("OVLD", "overload", 92.0),
    ]
    #endif

    // MARK: - 表示データ

    private var displayInput: GraphicInput {
        #if DEBUG
        if let s = visualPreviewScore {
            return GraphicInput(score: s, confidence: 1.0, state: .optimalTension)
        }
        #endif
        return viewModel.graphicInput
    }

    private var displayHasData: Bool {
        #if DEBUG
        if visualPreviewScore != nil { return true }
        #endif
        return viewModel.didFetchHeartRate || viewModel.didFetchHRV
    }

    // MARK: - Score計算

    private var scoreIntensity: Double {
        min(max(displayInput.score / 100.0, 0.0), 1.0)
    }

    private var scoreAccentColor: Color {
        let t = scoreIntensity
        if t < 0.35 {
            return Color(hue: 0.62 - t * 0.05, saturation: 0.88, brightness: 0.90)
        } else if t < 0.62 {
            let p = (t - 0.35) / 0.27
            return Color(hue: 0.57 - p * 0.45, saturation: 0.92, brightness: 0.98)
        } else {
            let p = (t - 0.62) / 0.38
            let h = 0.12 - p * 0.12
            return Color(hue: h < 0 ? h + 1 : h, saturation: 0.96, brightness: 1.0)
        }
    }

    private var buttonPulseDuration: Double { 3.8 - scoreIntensity * 2.6 }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            // tab 0: missionBar非表示, inset=0
            let availH   = geo.size.height
            let graphicH = availH * 0.78   // 星グラフィック78%
            let dashH    = availH * 0.22   // コックピット22%

            ZStack(alignment: .top) {
                // 1. 宇宙背景
                Color(red: 0.00, green: 0.008, blue: 0.05).ignoresSafeArea()

                // 2. 星粒子グラフィック（主役）
                GraphicHostView(input: displayInput)
                    .frame(maxWidth: .infinity)
                    .frame(height: graphicH)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                // 3. コックピット窓枠（ほぼ黒、発光最小）
                cockpitWindowFrame
                    .frame(height: graphicH)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                // 4. グラフィック上端グラデーション（ヘッダー可読性）
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 90)
                    Spacer()
                }
                .frame(height: graphicH)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // 5. グラフィック下端グラデーション（パネルとの境界）
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.50),
                            Color(red: 0.04, green: 0.07, blue: 0.18).opacity(0.88),
                            Color(red: 0.05, green: 0.08, blue: 0.20)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 68)
                }
                .frame(height: graphicH)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // 6. ヘッダー
                cockpitHeader
                    .padding(.top, 10)
                    .padding(.horizontal, 18)
                    .zIndex(50)

                // 7. コックピットダッシュボード
                VStack(spacing: 0) {
                    Spacer()
                    cockpitDashboard(dashH: dashH)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                buttonGlow = true
            }
            #if DEBUG
            if let s = resolveVisualQAScore() { visualPreviewScore = s }
            #endif
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showDebugSheet) {
            debugSheet
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showStatusDetail) {
            statusDetailSheet
        }
    }

    // MARK: - コックピット窓枠（ほぼ黒・暗い金属・発光最小）

    private var cockpitWindowFrame: some View {
        ZStack {
            Canvas { ctx, size in
                let sw = size.width
                let sh = size.height
                let strutW  = sw * 0.180    // 少し広め
                let strutH  = sh * 0.94
                let bridgeY = sh * 0.86
                let bridgeH = sh - bridgeY

                // ── 左ストラット（ほぼ純黒）
                var lStrut = Path()
                lStrut.move(to: .zero)
                lStrut.addLine(to: CGPoint(x: strutW, y: 0))
                lStrut.addLine(to: CGPoint(x: 0, y: strutH))
                lStrut.closeSubpath()
                ctx.fill(lStrut, with: .color(Color.black.opacity(0.97)))

                // 左メタル質感（極めて暗い紺）
                var lMetal = Path()
                lMetal.move(to: CGPoint(x: strutW, y: 0))
                lMetal.addLine(to: CGPoint(x: strutW * 0.72, y: 0))
                lMetal.addLine(to: CGPoint(x: 0, y: strutH * 0.68))
                lMetal.addLine(to: CGPoint(x: 0, y: strutH))
                lMetal.closeSubpath()
                ctx.fill(lMetal, with: .color(Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.80)))

                // ── 右ストラット
                var rStrut = Path()
                rStrut.move(to: CGPoint(x: sw, y: 0))
                rStrut.addLine(to: CGPoint(x: sw - strutW, y: 0))
                rStrut.addLine(to: CGPoint(x: sw, y: strutH))
                rStrut.closeSubpath()
                ctx.fill(rStrut, with: .color(Color.black.opacity(0.97)))

                var rMetal = Path()
                rMetal.move(to: CGPoint(x: sw - strutW, y: 0))
                rMetal.addLine(to: CGPoint(x: sw - strutW * 0.72, y: 0))
                rMetal.addLine(to: CGPoint(x: sw, y: strutH * 0.68))
                rMetal.addLine(to: CGPoint(x: sw, y: strutH))
                rMetal.closeSubpath()
                ctx.fill(rMetal, with: .color(Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.80)))

                // ── 下部ブリッジ
                var bL = Path()
                bL.move(to: CGPoint(x: 0, y: bridgeY))
                bL.addLine(to: CGPoint(x: sw * 0.22, y: bridgeY + bridgeH * 0.10))
                bL.addLine(to: CGPoint(x: sw * 0.38, y: sh))
                bL.addLine(to: CGPoint(x: 0, y: sh))
                bL.closeSubpath()
                ctx.fill(bL, with: .color(Color.black.opacity(0.94)))

                var bR = Path()
                bR.move(to: CGPoint(x: sw, y: bridgeY))
                bR.addLine(to: CGPoint(x: sw * 0.78, y: bridgeY + bridgeH * 0.10))
                bR.addLine(to: CGPoint(x: sw * 0.62, y: sh))
                bR.addLine(to: CGPoint(x: sw, y: sh))
                bR.closeSubpath()
                ctx.fill(bR, with: .color(Color.black.opacity(0.94)))

                // ── エッジライン（非常に細く、輝度低め）
                let eOff = strutW

                // メインエッジ（細い白線＋極細グロー）
                var lEdge = Path()
                lEdge.move(to: CGPoint(x: eOff, y: 0))
                lEdge.addLine(to: CGPoint(x: 0, y: strutH - 1))
                ctx.stroke(lEdge, with: .color(Color.white.opacity(0.12)), lineWidth: 0.8)
                ctx.stroke(lEdge, with: .color(Color.white.opacity(0.04)), lineWidth: 5.0)

                var rEdge = Path()
                rEdge.move(to: CGPoint(x: sw - eOff, y: 0))
                rEdge.addLine(to: CGPoint(x: sw, y: strutH - 1))
                ctx.stroke(rEdge, with: .color(Color.white.opacity(0.12)), lineWidth: 0.8)
                ctx.stroke(rEdge, with: .color(Color.white.opacity(0.04)), lineWidth: 5.0)

                // 上端線
                var topLine = Path()
                topLine.move(to: CGPoint(x: eOff, y: 1))
                topLine.addLine(to: CGPoint(x: sw - eOff, y: 1))
                ctx.stroke(topLine, with: .color(Color.white.opacity(0.08)), lineWidth: 0.8)

                // ブリッジ線
                var bLineL = Path()
                bLineL.move(to: CGPoint(x: 0, y: bridgeY))
                bLineL.addLine(to: CGPoint(x: sw * 0.22, y: bridgeY + bridgeH * 0.10))
                ctx.stroke(bLineL, with: .color(Color.white.opacity(0.09)), lineWidth: 0.8)

                var bLineR = Path()
                bLineR.move(to: CGPoint(x: sw, y: bridgeY))
                bLineR.addLine(to: CGPoint(x: sw * 0.78, y: bridgeY + bridgeH * 0.10))
                ctx.stroke(bLineR, with: .color(Color.white.opacity(0.09)), lineWidth: 0.8)

                // ── ALERT グロー（score > 0.56 で赤みが出る）
                let alertT = max(0.0, scoreIntensity - 0.56) / 0.44
                if alertT > 0 {
                    let aR = Color(red: 0.95, green: 0.06, blue: 0.06)

                    var laG = Path()
                    laG.move(to: CGPoint(x: eOff, y: 0))
                    laG.addLine(to: CGPoint(x: 0, y: strutH - 1))
                    ctx.stroke(laG, with: .color(aR.opacity(alertT * 0.65)), lineWidth: 28)
                    ctx.stroke(laG, with: .color(aR.opacity(alertT * 0.80)), lineWidth: 5)
                    ctx.stroke(laG, with: .color(aR.opacity(alertT * 0.95)), lineWidth: 1.8)

                    var raG = Path()
                    raG.move(to: CGPoint(x: sw - eOff, y: 0))
                    raG.addLine(to: CGPoint(x: sw, y: strutH - 1))
                    ctx.stroke(raG, with: .color(aR.opacity(alertT * 0.65)), lineWidth: 28)
                    ctx.stroke(raG, with: .color(aR.opacity(alertT * 0.80)), lineWidth: 5)
                    ctx.stroke(raG, with: .color(aR.opacity(alertT * 0.95)), lineWidth: 1.8)

                    var taG = Path()
                    taG.move(to: CGPoint(x: eOff, y: 1))
                    taG.addLine(to: CGPoint(x: sw - eOff, y: 1))
                    ctx.stroke(taG, with: .color(aR.opacity(alertT * 0.70)), lineWidth: 16)
                    ctx.stroke(taG, with: .color(aR.opacity(alertT * 0.90)), lineWidth: 1.4)
                }
            }
        }
        .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
    }

    // MARK: - ヘッダー

    private var cockpitHeader: some View {
        HStack(spacing: 0) {
            // 接続状態インジケータ
            Button { showStatusDetail = true } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: indicatorColor.opacity(0.85), radius: 4)
                    Text(shortStatusLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .tracking(0.8)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            // センタータイトル（背景パネル付きでノッチ被り防止）
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    Text("MIND")
                        .font(.system(size: 18, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .tracking(5.5)
                    Text(" WAVE")
                        .font(.system(size: 18, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(scoreAccentColor.opacity(0.98))
                        .tracking(5.5)
                        .shadow(color: scoreAccentColor.opacity(0.55), radius: 10)
                        .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
                }
                Text("STRESS  &  BIOMETRICS")
                    .font(.system(size: 7, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .tracking(2.5)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.50))
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            )

            Spacer()

            // 右側ボタン群
            HStack(spacing: 0) {
                Button { showSettingsSheet = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                #if DEBUG
                Button { showDebugSheet = true } label: {
                    Text("dbg")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.18))
                        .frame(width: 28, height: 36)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                #endif
            }
        }
        .frame(height: 36)
    }

    // MARK: - コックピットダッシュボード

    private func cockpitDashboard(dashH: CGFloat) -> some View {
        VStack(spacing: 0) {
            // コンソール上端ブリッジライン
            consoleBridgeLine

            Spacer(minLength: 1)

            // レバー型ナビゲーション
            CockpitLeverNav(selectedTab: $selectedTab, accentColor: scoreAccentColor)
                .padding(.horizontal, 12)
                .frame(height: 46)

            Spacer(minLength: 3)

            // 計器行: PULSE | 計測ボタン | SIGNAL
            HStack(alignment: .center, spacing: 7) {
                pulsePanel.frame(maxWidth: .infinity)
                mainLaunchButton
                signalPanel.frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .frame(height: dashH)
        .background(cockpitPanelBackground)
    }

    // MARK: - コンソールブリッジライン

    private var consoleBridgeLine: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let ac = scoreAccentColor

            // 主線
            var main = Path()
            main.move(to: CGPoint(x: w * 0.06, y: h - 1))
            main.addLine(to: CGPoint(x: w * 0.94, y: h - 1))
            ctx.stroke(main, with: .color(ac.opacity(0.82)), lineWidth: 2.0)
            ctx.stroke(main, with: .color(ac.opacity(0.28)), lineWidth: 12)

            // 補助線
            var sub = Path()
            sub.move(to: CGPoint(x: w * 0.20, y: h - 4))
            sub.addLine(to: CGPoint(x: w * 0.80, y: h - 4))
            ctx.stroke(sub, with: .color(ac.opacity(0.22)), lineWidth: 0.7)

            // コーナードット
            for xf in [0.06, 0.94] as [Double] {
                let nx = w * xf
                ctx.fill(Path(ellipseIn: CGRect(x: nx - 3.5, y: h - 4.5, width: 7, height: 7)),
                         with: .color(ac.opacity(0.72)))
            }
        }
        .frame(height: 18)
        .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
    }

    // MARK: - コックピットパネル背景

    private var cockpitPanelBackground: some View {
        let ac = scoreAccentColor
        return ZStack {
            // ベース: 深い暗紺
            CockpitPanelShape(chamfer: 26)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.09, blue: 0.22),
                        Color(red: 0.03, green: 0.05, blue: 0.13),
                        Color(red: 0.01, green: 0.02, blue: 0.08)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
            // ガラス反射
            CockpitPanelShape(chamfer: 26)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.055), .clear],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12)
                ))
            // ALERT赤オーバーレイ
            if scoreIntensity > 0.58 {
                let t = min(1.0, (scoreIntensity - 0.58) / 0.42)
                CockpitPanelShape(chamfer: 26)
                    .fill(Color(red: 0.65 * t, green: 0, blue: 0).opacity(0.22))
                    .animation(.easeInOut(duration: 0.9), value: scoreIntensity)
                CockpitPanelShape(chamfer: 26)
                    .stroke(Color(red: 0.95, green: 0.06, blue: 0.06).opacity(t * 0.80), lineWidth: 0.9)
                    .animation(.easeInOut(duration: 0.9), value: scoreIntensity)
                CockpitPanelShape(chamfer: 26)
                    .stroke(Color(red: 1.0, green: 0.06, blue: 0.06)
                        .opacity(t * (buttonGlow ? 0.65 : 0.32)), lineWidth: 3.5)
                    .blur(radius: 5)
                    .animation(.easeInOut(duration: 0.8), value: buttonGlow)
            }
            // 外縁アクセント（通常時は非常に細く）
            CockpitPanelShape(chamfer: 26)
                .stroke(ac.opacity(0.40), lineWidth: 0.8)
                .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
            CockpitPanelShape(chamfer: 26)
                .stroke(ac.opacity(0.42), lineWidth: 2.0)
                .blur(radius: 3.5)
                .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
        }
    }

    // MARK: - PULSE パネル（42pt BPM）

    private var pulsePanel: some View {
        let ac      = scoreAccentColor
        let hasData = hasRealHeartRate
        let hrText  = heartRateDisplayForUI   // DEMO時は"72"を表示

        return ZStack(alignment: .topLeading) {
            // Canvas 金属フレーム
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cr: CGFloat = 8
                ctx.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: cr),
                    with: .color(Color(red: 0.04, green: 0.07, blue: 0.18))
                )
                // 上端ハイライト
                var topHL = Path()
                topHL.move(to: CGPoint(x: cr, y: 1.2))
                topHL.addLine(to: CGPoint(x: w - cr, y: 1.2))
                ctx.stroke(topHL, with: .color(Color.white.opacity(0.20)), lineWidth: 1.2)
                // 外縁
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1), cornerRadius: cr),
                    with: .color(ac.opacity(0.30)), lineWidth: 0.7
                )
                // 左エッジグロー
                var lE = Path()
                lE.move(to: CGPoint(x: 1.2, y: cr + 2))
                lE.addLine(to: CGPoint(x: 1.2, y: h - cr - 2))
                ctx.stroke(lE, with: .color(ac.opacity(0.75)), lineWidth: 2.2)
                ctx.stroke(lE, with: .color(ac.opacity(0.22)), lineWidth: 8)
                // 下段仕切り
                var div = Path()
                div.move(to: CGPoint(x: 7, y: h - 26))
                div.addLine(to: CGPoint(x: w - 7, y: h - 26))
                ctx.stroke(div, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
            }
            .animation(.easeInOut(duration: 0.9), value: scoreIntensity)

            VStack(alignment: .leading, spacing: 0) {
                // ラベル行
                HStack(spacing: 4) {
                    Circle()
                        .fill(hasData ? ac : Color.white.opacity(0.10))
                        .frame(width: 4, height: 4)
                        .shadow(color: hasData ? ac.opacity(0.85) : .clear, radius: 4)
                    Text("PULSE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(ac.opacity(0.65))
                        .tracking(1.8)
                    Spacer()
                    Image(systemName: "heart.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(hasData
                            ? Color(red: 0.92, green: 0.24, blue: 0.28)
                            : Color.white.opacity(0.10))
                        .shadow(color: hasData ? Color.red.opacity(0.55) : .clear, radius: 3)
                }
                .padding(.top, 7)
                .padding(.horizontal, 8)

                // 42pt BPM
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(hrText)
                        .font(.system(size: 42, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(hasData
                            ? Color.white.opacity(0.97)
                            : Color.white.opacity(isDemoMode ? 0.55 : 0.16))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: hrText)
                        .shadow(color: hasData ? ac.opacity(0.35) : .clear, radius: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 9)
                        Text("BPM")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(hasData ? 0.40 : (isDemoMode ? 0.30 : 0.10)))
                            .tracking(1.0)
                    }
                }
                .padding(.horizontal, 8)

                Spacer(minLength: 2)

                // ECG波形
                Canvas { ctx, sz in
                    let mid = sz.height * 0.52
                    let amp = (hasData || isDemoMode) ? sz.height * 0.38 : sz.height * 0.04
                    let xs: [CGFloat] = [0,0.06,0.11,0.16,0.22,0.26,0.31,0.37,0.43,
                                         0.48,0.50,0.56,0.61,0.66,0.72,0.76,0.81,0.87,0.93,0.97,1.0]
                    let ys: [CGFloat] = [0,-0.05,-0.22,0.30,0,-0.90,1.0,-0.30,0.32,
                                         0,0,-0.05,-0.22,0.30,0,-0.90,1.0,-0.30,0.32,0,0]
                    var p = Path()
                    for i in 0..<xs.count {
                        let pt = CGPoint(x: xs[i] * sz.width, y: mid - ys[i] * amp)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    let a: CGFloat = (hasData || isDemoMode) ? 0.60 : 0.08
                    ctx.stroke(p, with: .color(Color.cyan.opacity(a * 0.25)), lineWidth: 3.0)
                    ctx.stroke(p, with: .color(Color.cyan.opacity(a)), lineWidth: 0.85)
                }
                .frame(height: 18)
                .padding(.horizontal, 8)
                .padding(.bottom, 7)
            }
        }
        .frame(minHeight: 80)
    }

    // MARK: - 138pt 計測ボタン

    private var mainLaunchButton: some View {
        let ac: Color  = isLive ? .orange : scoreAccentColor
        let gI: Double = 0.72 + scoreIntensity * 0.26

        return Button { viewModel.toggleLiveMonitoring() } label: {
            ZStack {
                // 最外メタルベゼル
                Circle()
                    .stroke(AngularGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.04),
                                 Color.white.opacity(0.04), Color.white.opacity(0.14),
                                 Color.white.opacity(0.20)],
                        center: .center), lineWidth: 1.8)
                    .frame(width: 132, height: 132)
                // アウターリング
                Circle().stroke(ac.opacity(0.16), lineWidth: 0.9).frame(width: 122, height: 122)
                // メイン発光リング
                Circle()
                    .stroke(ac.opacity(gI), lineWidth: 2.2)
                    .frame(width: 112, height: 112)
                    .shadow(color: ac.opacity(0.80), radius: 8)
                    .shadow(color: ac.opacity(0.32), radius: 18)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)
                // ミッドリング
                Circle().stroke(ac.opacity(0.24), lineWidth: 0.7).frame(width: 100, height: 100)
                // インナーメタル
                Circle()
                    .stroke(LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
                    .frame(width: 90, height: 90)
                // インナーアクセント
                Circle().stroke(ac.opacity(0.14), lineWidth: 0.5).frame(width: 78, height: 78)
                // ガラス面
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            Color(hue: isLive ? 0.07 : max(0, 0.64 - scoreIntensity * 0.54),
                                  saturation: 0.90, brightness: 0.16 + scoreIntensity * 0.18),
                            Color(red: 0.02, green: 0.04, blue: 0.14),
                            Color.black.opacity(0.95)
                        ],
                        center: UnitPoint(x: 0.30, y: 0.22),
                        startRadius: 0, endRadius: 38))
                    .frame(width: 72, height: 72)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)
                // ガラスハイライト
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.05), .clear],
                        startPoint: UnitPoint(x: 0.20, y: 0.04),
                        endPoint: UnitPoint(x: 0.60, y: 0.52)))
                    .frame(width: 72, height: 72)
                // 環境グロー
                Circle()
                    .fill(RadialGradient(
                        colors: [ac.opacity(0.14 + scoreIntensity * 0.12), .clear],
                        center: .center, startRadius: 0, endRadius: 33))
                    .frame(width: 72, height: 72)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)
                // アイコン + ラベル
                VStack(spacing: 5) {
                    Image(systemName: isLive ? "waveform" : "waveform.path.ecg")
                        .font(.system(size: 16, weight: .ultraLight))
                        .foregroundStyle(ac.opacity(0.98))
                        .shadow(color: ac, radius: 10)
                    Text(isLive ? "停止" : "計測開始")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isLive ? Color.orange.opacity(0.95) : Color.white.opacity(0.82))
                        .tracking(0.8)
                }
            }
            .frame(width: 132, height: 132)
            // 呼吸パルスリング
            .overlay(
                Circle()
                    .stroke(ac.opacity(buttonGlow ? 0.25 : 0.01), lineWidth: 1.2)
                    .scaleEffect(buttonGlow ? 1.22 : 0.90)
                    .frame(width: 150, height: 150)
                    .blur(radius: 2.5)
                    .animation(.easeInOut(duration: buttonPulseDuration).repeatForever(autoreverses: true),
                               value: buttonGlow)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.20), value: isLive)
        .accessibilityIdentifier("home_measure_start_button")
        .accessibilityLabel(isLive ? "計測を停止する" : "ライブ計測を開始する")
        // 較正マーク
        .overlay(
            Canvas { ctx, size in
                let cx = size.width / 2, cy = size.height / 2
                let outerR = size.width / 2 - 1.5
                for i in 0..<24 {
                    let angle = Double(i) * (.pi / 12.0) - .pi / 2.0
                    let isCard = (i % 6 == 0)
                    let isOct  = (i % 3 == 0) && !isCard
                    guard isCard || isOct else { continue }
                    let tLen: Double = isCard ? 7 : 3.5
                    let x1 = cx + outerR * cos(angle)
                    let y1 = cy + outerR * sin(angle)
                    let x2 = cx + (outerR - tLen) * cos(angle)
                    let y2 = cy + (outerR - tLen) * sin(angle)
                    var t2 = Path()
                    t2.move(to: CGPoint(x: x1, y: y1))
                    t2.addLine(to: CGPoint(x: x2, y: y2))
                    let ac2 = isLive ? Color.orange : scoreAccentColor
                    ctx.stroke(t2, with: .color(ac2.opacity(isCard ? 0.58 : 0.28)),
                               lineWidth: isCard ? 1.1 : 0.6)
                    if isCard {
                        ctx.fill(Path(ellipseIn: CGRect(x: x1 - 1.8, y: y1 - 1.8, width: 3.6, height: 3.6)),
                                 with: .color(ac2.opacity(0.68)))
                    }
                }
            }
            .frame(width: 156, height: 156)
            .allowsHitTesting(false)
        )
        // ALERT リング
        .overlay(
            Group {
                if scoreIntensity > 0.68 {
                    let t = min(1.0, (scoreIntensity - 0.68) / 0.32)
                    Circle()
                        .stroke(AngularGradient(
                            colors: [
                                Color(red: 0.92, green: 0.24, blue: 0.04)
                                    .opacity(buttonGlow ? 0.58 : 0.26),
                                Color(red: 0.80, green: 0.06, blue: 0.04)
                                    .opacity(buttonGlow ? 0.42 : 0.16),
                                Color(red: 0.92, green: 0.24, blue: 0.04)
                                    .opacity(buttonGlow ? 0.58 : 0.26)
                            ], center: .center), lineWidth: 1.4)
                        .frame(width: 164, height: 164)
                        .blur(radius: 4)
                        .opacity(t)
                        .animation(.easeInOut(duration: 0.80), value: buttonGlow)
                }
            }
            .animation(.easeInOut(duration: 0.9), value: scoreIntensity)
        )
    }

    // MARK: - SIGNAL パネル（波形のみ）

    private var signalPanel: some View {
        let ac      = scoreAccentColor
        let hasData = displayHasData

        return ZStack(alignment: .topTrailing) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cr: CGFloat = 8
                ctx.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: cr),
                    with: .color(Color(red: 0.03, green: 0.06, blue: 0.17))
                )
                var topHL = Path()
                topHL.move(to: CGPoint(x: cr, y: 1.2))
                topHL.addLine(to: CGPoint(x: w - cr, y: 1.2))
                ctx.stroke(topHL, with: .color(Color.white.opacity(0.18)), lineWidth: 1.2)
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1), cornerRadius: cr),
                    with: .color(ac.opacity(0.28)), lineWidth: 0.7
                )
                // 右エッジグロー
                var rE = Path()
                rE.move(to: CGPoint(x: w - 1.2, y: cr + 2))
                rE.addLine(to: CGPoint(x: w - 1.2, y: h - cr - 2))
                ctx.stroke(rE, with: .color(ac.opacity(0.72)), lineWidth: 2.2)
                ctx.stroke(rE, with: .color(ac.opacity(0.20)), lineWidth: 8)
                var div = Path()
                div.move(to: CGPoint(x: 7, y: h - 26))
                div.addLine(to: CGPoint(x: w - 7, y: h - 26))
                ctx.stroke(div, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
            }
            .animation(.easeInOut(duration: 0.9), value: scoreIntensity)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 4) {
                    Spacer()
                    Text("SIGNAL")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(ac.opacity(0.62))
                        .tracking(1.4)
                    Circle()
                        .fill(hasData ? ac : Color.white.opacity(0.10))
                        .frame(width: 4, height: 4)
                        .shadow(color: hasData ? ac.opacity(0.85) : .clear, radius: 4)
                }
                .padding(.top, 7)
                .padding(.horizontal, 8)

                Text(hasData ? (isLive ? "LIVE" : "ACTIVE") : "OFFLINE")
                    .font(.system(size: 16, weight: .thin, design: .monospaced))
                    .foregroundStyle(hasData ? Color.white.opacity(0.90) : Color.white.opacity(0.16))
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .tracking(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .padding(.top, 3)
                    .animation(.easeInOut(duration: 0.35), value: hasData)

                Spacer(minLength: 2)

                Canvas { ctx, sz in
                    let mid = sz.height * 0.52
                    let amp = hasData ? sz.height * 0.36 : sz.height * 0.04
                    let xs: [CGFloat] = [0,0.08,0.14,0.20,0.28,0.32,0.36,0.42,
                                         0.50,0.54,0.62,0.68,0.74,0.82,0.86,0.90,0.96,1.0]
                    let ys: [CGFloat] = [0,-0.04,0.18,-0.12,0,-0.85,1.0,-0.28,
                                         0,0,-0.04,0.18,-0.12,0,-0.85,1.0,-0.28,0]
                    var p = Path()
                    for i in 0..<xs.count {
                        let pt = CGPoint(x: xs[i] * sz.width, y: mid - ys[i] * amp)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    let a: CGFloat = hasData ? 0.62 : 0.08
                    ctx.stroke(p, with: .color(ac.opacity(a * 0.25)), lineWidth: 3.0)
                    ctx.stroke(p, with: .color(ac.opacity(a)), lineWidth: 0.85)
                }
                .frame(height: 18)
                .padding(.horizontal, 8)
                .padding(.bottom, 7)
            }
        }
        .frame(minHeight: 80)
    }

    // MARK: - ステータス詳細シート

    private var statusDetailSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Circle().fill(indicatorColor).frame(width: 10, height: 10)
                        .shadow(color: indicatorColor.opacity(0.8), radius: 5)
                    Text(narrativeTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(narrativeBody)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .lineSpacing(4)
                Divider().background(Color.white.opacity(0.10))
                HStack {
                    metricItem(label: "データソース", value: dataSourceLabel, accent: indicatorColor)
                    Divider().frame(height: 28)
                    metricItem(label: "状態",
                               value: viewModel.isLiveMonitoring ? "計測中" : "停止中",
                               accent: viewModel.isLiveMonitoring ? .cyan : Color.white.opacity(0.3))
                }
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.03, green: 0.03, blue: 0.08).ignoresSafeArea())
            .navigationTitle("ミッションステータス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { showStatusDetail = false }.foregroundStyle(.cyan)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func metricItem(label: String, value: String, accent: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(accent)
            Text(label).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.36))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - DEBUG シート（本番UIからは完全非表示）

    private var debugSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    #if DEBUG
                    // Visual QA
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Visual QA — スコア状態プレビュー")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                        HStack(spacing: 8) {
                            ForEach(visualQAStates.indices, id: \.self) { i in
                                let item = visualQAStates[i]
                                let active = visualPreviewScore == item.score
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        visualPreviewScore = item.score
                                    }
                                } label: {
                                    Text(item.label)
                                        .font(.system(size: 11, weight: .black, design: .monospaced))
                                        .foregroundStyle(active ? .black : Color.white.opacity(0.75))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(active ? Color.cyan : Color.white.opacity(0.10))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(active ? Color.white.opacity(0.25) : Color.cyan.opacity(0.20), lineWidth: 0.8)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("visual_state_\(item.id)")
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    #endif

                    // DebugDiagnostics
                    DebugDiagnosticsView()
                        .environmentObject(viewModel)
                }
                .padding(16)
            }
            .background(Color(red: 0.03, green: 0.03, blue: 0.08).ignoresSafeArea())
            .navigationTitle("デバッグ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { showDebugSheet = false }.foregroundStyle(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - DEBUG ENV

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
    #endif

    // MARK: - ヘルパー

    private var isLive: Bool { viewModel.isLiveMonitoring }

    private var isDemoMode: Bool {
        viewModel.activeDataSource == .mock
    }

    private var indicatorColor: Color {
        switch viewModel.activeDataSource {
        case .watchLive:   return .cyan
        case .healthKit:   return Color(red: 0.18, green: 0.82, blue: 0.58)
        case .mock:        return .orange
        case .unavailable: return Color.white.opacity(0.22)
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

    // VIEW専用: DEMO時は"72"を表示（バックエンド変更なし）
    private var heartRateDisplayForUI: String {
        if let w = viewModel.latestWatchHeartRate { return String(format: "%.0f", w) }
        if viewModel.didFetchHeartRate            { return String(format: "%.0f", viewModel.currentHeartRate) }
        if isDemoMode                             { return "72" }  // VIEW側デモ表示
        return "—"
    }

    private var dataSourceLabel: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return "Watch Live"
        case .healthKit:   return "HealthKit"
        case .mock:        return "デモ"
        case .unavailable: return "未接続"
        }
    }

    private var narrativeTitle: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return viewModel.isLiveMonitoring ? "リアルタイム計測中" : "計測を開始できます"
        case .healthKit:   return "HealthKitから読み込み中"
        case .mock:        return "デモモード"
        case .unavailable: return "データを待っています"
        }
    }

    private var narrativeBody: String {
        switch viewModel.activeDataSource {
        case .watchLive:
            return (viewModel.didFetchHeartRate || viewModel.didFetchHRV)
                ? "状態グラフィックが現在の心理的揺らぎを反映しています。"
                : "Apple Watchを装着したまましばらくお待ちください。"
        case .healthKit:   return "HealthKitに記録された最新データを表示しています。"
        case .mock:        return "Apple Watchと接続すると実データへ切り替わります。"
        case .unavailable: return "計測を開始するとApple Watchからデータが届きます。"
        }
    }
}

// MARK: - CockpitLeverNav（操縦レール型ナビゲーション）

private struct CockpitLeverNav: View {
    @Binding var selectedTab: Int
    let accentColor: Color

    // レール上の位置: 整える=左(0), ホーム=中央(1), 履歴=右(2)
    private var leverPos: Int {
        switch selectedTab {
        case 1:  return 0   // 整える
        case 2:  return 2   // 履歴
        default: return 1   // ホーム
        }
    }

    private let navItems: [(label: String, icon: String, tab: Int)] = [
        ("整える", "wind",       1),
        ("ホーム",  "house.fill", 0),
        ("履歴",   "clock.fill",  2),
    ]

    var body: some View {
        VStack(spacing: 3) {
            // ラベル行（アイコン + テキスト）
            HStack(spacing: 0) {
                ForEach(navItems.indices, id: \.self) { i in
                    let item = navItems[i]
                    let active = selectedTab == item.tab
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.66)) {
                            selectedTab = item.tab
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: active ? .semibold : .ultraLight))
                                .foregroundStyle(active ? accentColor : Color.white.opacity(0.24))
                                .shadow(color: active ? accentColor.opacity(0.70) : .clear, radius: 5)
                            Text(item.label)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(active ? accentColor.opacity(0.92) : Color.white.opacity(0.22))
                                .tracking(0.1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.20), value: active)
                    .accessibilityLabel(item.label)
                    .accessibilityIdentifier(item.tab == 1 ? "nav_calm" : item.tab == 0 ? "nav_home" : "nav_history")
                    .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                }
            }

            // レール
            GeometryReader { geo in
                let w = geo.size.width
                let positions: [CGFloat] = [w * 0.163, w * 0.500, w * 0.837]
                let knobX = positions[leverPos]

                ZStack(alignment: .leading) {
                    // レールベース（金属筐体）
                    Canvas { ctx, size in
                        let rw = size.width, rh = size.height
                        let cr: CGFloat = rh / 2
                        // 外側ハウジング
                        ctx.fill(
                            Path(roundedRect: CGRect(x: 0, y: 0, width: rw, height: rh), cornerRadius: cr),
                            with: .color(Color(red: 0.06, green: 0.10, blue: 0.22))
                        )
                        // 内側凹み
                        ctx.fill(
                            Path(roundedRect: CGRect(x: 2, y: 2, width: rw - 4, height: rh - 4), cornerRadius: cr - 2),
                            with: .color(Color(red: 0.02, green: 0.04, blue: 0.12))
                        )
                        // レールコア線
                        var rail = Path()
                        rail.move(to: CGPoint(x: cr, y: rh / 2))
                        rail.addLine(to: CGPoint(x: rw - cr, y: rh / 2))
                        ctx.stroke(rail, with: .color(Color.white.opacity(0.07)), lineWidth: 0.9)
                        // 外縁
                        ctx.stroke(
                            Path(roundedRect: CGRect(x: 0.4, y: 0.4, width: rw - 0.8, height: rh - 0.8), cornerRadius: cr),
                            with: .color(Color.white.opacity(0.09)), lineWidth: 0.5
                        )
                        // 3ポジションマーク
                        for xf in [0.163, 0.500, 0.837] as [Double] {
                            let mx = rw * xf
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: mx - 2, y: rh / 2 - 2, width: 4, height: 4)),
                                with: .color(Color.white.opacity(0.16))
                            )
                        }
                    }
                    .frame(height: 16)

                    // ノブグロー
                    Capsule()
                        .fill(accentColor.opacity(0.16))
                        .frame(width: 42, height: 12)
                        .blur(radius: 7)
                        .offset(x: knobX - 21, y: 2)
                        .animation(.spring(response: 0.28, dampingFraction: 0.66), value: leverPos)

                    // ノブ本体（物理レバー感）
                    ZStack {
                        // ベース
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.25, green: 0.32, blue: 0.55),
                                         Color(red: 0.10, green: 0.14, blue: 0.28)],
                                startPoint: .top, endPoint: .bottom))
                        // 上端ハイライト
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.28), .clear],
                                startPoint: .top, endPoint: .center))
                        // 発光縁
                        Capsule()
                            .strokeBorder(accentColor.opacity(0.90), lineWidth: 1.1)
                        // グリップ溝（3本）
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.white.opacity(0.14))
                                    .frame(width: 1, height: 9)
                            }
                        }
                    }
                    .frame(width: 50, height: 22)
                    .shadow(color: accentColor.opacity(0.55), radius: 7)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                    .offset(x: knobX - 25, y: -3)
                    .animation(.spring(response: 0.28, dampingFraction: 0.66), value: leverPos)
                }
                .frame(height: 16)
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onEnded { v in
                            if v.translation.width > 36 {
                                withAnimation { selectedTab = leverPos == 0 ? 0 : leverPos == 1 ? 2 : 2 }
                            } else if v.translation.width < -36 {
                                withAnimation { selectedTab = leverPos == 2 ? 0 : leverPos == 1 ? 1 : 1 }
                            }
                        }
                )
            }
            .frame(height: 16)
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(MindWaveViewModel())
        .environmentObject(AppFlowState())
}
