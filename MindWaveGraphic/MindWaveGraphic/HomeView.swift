//
//  HomeView.swift
//  MindWaveGraphic
//
//  Home design recovery — 2026-07-09
//  imageUI.png 参照デザインへ再構築。
//  上部70%: 全画面星グラフィック + 重厚コックピット窓枠 (strutW=17.5%)
//  下部30%: CockpitPanelShape + レバーナビ + PULSE(42pt BPM) + 138pt計測ボタン + 波形パネル
//
//  HRV / SDNN / ms / SCORE / 呼吸法カード / statePanel は Home に表示しない
//  バックエンド(HK/Watch/ViewModel)は一切変更しない
//

import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var flowState: AppFlowState
    @Binding var selectedTab: Int

    @State private var showSettingsSheet = false
    @State private var showDebugSheet    = false
    @State private var showStatusDetail  = false
    @State private var buttonGlow: Bool  = false

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

    // MARK: - 表示入力（DEBUG上書き優先、バックエンド変更なし）

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

    // MARK: - Score連動アクセントカラー

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

    private var dangerTint: Color {
        guard scoreIntensity > 0.60 else { return .clear }
        let t = min(1.0, (scoreIntensity - 0.60) / 0.40)
        return Color(red: 0.88 * t, green: 0.0, blue: 0.04 * t)
    }

    private var buttonPulseDuration: Double { 3.5 - scoreIntensity * 2.3 }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            // tab 0 では missionBar を非表示にしているため inset = 0
            let availH   = geo.size.height
            let graphicH = availH * 0.70
            let dashH    = availH * 0.30

            ZStack(alignment: .top) {
                // 1. 宇宙背景
                Color(red: 0.00, green: 0.01, blue: 0.06)
                    .ignoresSafeArea()

                // 2. 星粒子グラフィック（主役）
                GraphicHostView(input: displayInput)
                    .frame(maxWidth: .infinity)
                    .frame(height: graphicH)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                // 3. コックピット窓枠（重厚ストラット）
                cockpitWindowFrame
                    .frame(height: graphicH)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                // 4. グラフィック上端グラデーション（ヘッダー可読性）
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.68), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 100)
                    Spacer()
                }
                .frame(height: graphicH)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // 5. グラフィック下端グラデーション（パネルへの接続）
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(red: 0.04, green: 0.07, blue: 0.19).opacity(0.45),
                            Color(red: 0.05, green: 0.09, blue: 0.21).opacity(0.82),
                            Color(red: 0.06, green: 0.10, blue: 0.22).opacity(0.97)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 80)
                }
                .frame(height: graphicH)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // 6. ヘッダー（背景パネル付き、ノッチ被り防止）
                cockpitHeader
                    .padding(.top, 10)
                    .padding(.horizontal, 18)
                    .zIndex(50)

                // 7. DEBUG Visual QA パレット（コックピットパネル上端に浮遊）
                #if DEBUG
                visualQAPalette
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, dashH + 10)
                    .zIndex(51)
                    .allowsHitTesting(true)
                #endif

                // 8. コックピットダッシュボード
                VStack(spacing: 0) {
                    Spacer()
                    cockpitDashboard(dashH: dashH)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
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
            DebugDiagnosticsView()
                .environmentObject(viewModel)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showStatusDetail) {
            statusDetailSheet
        }
    }

    // MARK: - コックピット窓枠（strutW=0.175、金属/ブリッジ/刻み/アラートグロー）

    private var cockpitWindowFrame: some View {
        let accent = scoreAccentColor
        return ZStack {
            Canvas { ctx, size in
                let sw = size.width
                let sh = size.height
                let strutW  = sw * 0.175
                let strutH  = sh * 0.92
                let bridgeY = sh * 0.83
                let bridgeH = sh - bridgeY

                // ── 左ストラット黒ベース
                var lStrut = Path()
                lStrut.move(to: .zero)
                lStrut.addLine(to: CGPoint(x: strutW, y: 0))
                lStrut.addLine(to: CGPoint(x: 0, y: strutH))
                lStrut.closeSubpath()
                ctx.fill(lStrut, with: .color(Color.black.opacity(0.96)))

                // 左メタル層
                var lMetal = Path()
                lMetal.move(to: CGPoint(x: strutW, y: 0))
                lMetal.addLine(to: CGPoint(x: strutW * 0.75, y: 0))
                lMetal.addLine(to: CGPoint(x: 0, y: strutH * 0.72))
                lMetal.addLine(to: CGPoint(x: 0, y: strutH))
                lMetal.closeSubpath()
                ctx.fill(lMetal, with: .color(Color(red: 0.04, green: 0.07, blue: 0.18).opacity(0.72)))

                // 左ベベル
                var lBevel = Path()
                lBevel.move(to: CGPoint(x: strutW * 0.42, y: 0))
                lBevel.addLine(to: CGPoint(x: strutW * 0.52, y: 0))
                lBevel.addLine(to: CGPoint(x: strutW * 0.08, y: strutH * 0.85))
                lBevel.addLine(to: CGPoint(x: 0, y: strutH * 0.85))
                lBevel.closeSubpath()
                ctx.fill(lBevel, with: .color(Color.white.opacity(0.026)))

                // ── 右ストラット
                var rStrut = Path()
                rStrut.move(to: CGPoint(x: sw, y: 0))
                rStrut.addLine(to: CGPoint(x: sw - strutW, y: 0))
                rStrut.addLine(to: CGPoint(x: sw, y: strutH))
                rStrut.closeSubpath()
                ctx.fill(rStrut, with: .color(Color.black.opacity(0.96)))

                var rMetal = Path()
                rMetal.move(to: CGPoint(x: sw - strutW, y: 0))
                rMetal.addLine(to: CGPoint(x: sw - strutW * 0.75, y: 0))
                rMetal.addLine(to: CGPoint(x: sw, y: strutH * 0.72))
                rMetal.addLine(to: CGPoint(x: sw, y: strutH))
                rMetal.closeSubpath()
                ctx.fill(rMetal, with: .color(Color(red: 0.04, green: 0.07, blue: 0.18).opacity(0.72)))

                var rBevel = Path()
                rBevel.move(to: CGPoint(x: sw - strutW * 0.42, y: 0))
                rBevel.addLine(to: CGPoint(x: sw - strutW * 0.52, y: 0))
                rBevel.addLine(to: CGPoint(x: sw - strutW * 0.08, y: strutH * 0.85))
                rBevel.addLine(to: CGPoint(x: sw, y: strutH * 0.85))
                rBevel.closeSubpath()
                ctx.fill(rBevel, with: .color(Color.white.opacity(0.026)))

                // ── 下部ブリッジ
                var bL = Path()
                bL.move(to: CGPoint(x: 0, y: bridgeY))
                bL.addLine(to: CGPoint(x: sw * 0.24, y: bridgeY + bridgeH * 0.12))
                bL.addLine(to: CGPoint(x: sw * 0.40, y: sh))
                bL.addLine(to: CGPoint(x: 0, y: sh))
                bL.closeSubpath()
                ctx.fill(bL, with: .color(Color.black.opacity(0.90)))

                var bR = Path()
                bR.move(to: CGPoint(x: sw, y: bridgeY))
                bR.addLine(to: CGPoint(x: sw * 0.76, y: bridgeY + bridgeH * 0.12))
                bR.addLine(to: CGPoint(x: sw * 0.60, y: sh))
                bR.addLine(to: CGPoint(x: sw, y: sh))
                bR.closeSubpath()
                ctx.fill(bR, with: .color(Color.black.opacity(0.90)))

                // ── エッジライト（3層）
                let eOff = strutW

                var lGlow = Path()
                lGlow.move(to: CGPoint(x: eOff, y: 0))
                lGlow.addLine(to: CGPoint(x: 0, y: strutH - 2))
                ctx.stroke(lGlow, with: .color(accent.opacity(0.22)), lineWidth: 12)
                ctx.stroke(lGlow, with: .color(accent.opacity(0.72)), lineWidth: 1.5)

                var lGlow2 = Path()
                lGlow2.move(to: CGPoint(x: eOff - 4, y: 0))
                lGlow2.addLine(to: CGPoint(x: 4, y: strutH - 2))
                ctx.stroke(lGlow2, with: .color(accent.opacity(0.24)), lineWidth: 0.7)

                var rGlow = Path()
                rGlow.move(to: CGPoint(x: sw - eOff, y: 0))
                rGlow.addLine(to: CGPoint(x: sw, y: strutH - 2))
                ctx.stroke(rGlow, with: .color(accent.opacity(0.22)), lineWidth: 12)
                ctx.stroke(rGlow, with: .color(accent.opacity(0.72)), lineWidth: 1.5)

                var rGlow2 = Path()
                rGlow2.move(to: CGPoint(x: sw - eOff + 4, y: 0))
                rGlow2.addLine(to: CGPoint(x: sw - 4, y: strutH - 2))
                ctx.stroke(rGlow2, with: .color(accent.opacity(0.24)), lineWidth: 0.7)

                // 上端ライン
                var topLine = Path()
                topLine.move(to: CGPoint(x: eOff, y: 1.5))
                topLine.addLine(to: CGPoint(x: sw - eOff, y: 1.5))
                ctx.stroke(topLine, with: .color(accent.opacity(0.40)), lineWidth: 1.2)
                ctx.stroke(topLine, with: .color(accent.opacity(0.16)), lineWidth: 8)

                // ブリッジライン
                var bLineL = Path()
                bLineL.move(to: CGPoint(x: 0, y: bridgeY))
                bLineL.addLine(to: CGPoint(x: sw * 0.24, y: bridgeY + bridgeH * 0.12))
                ctx.stroke(bLineL, with: .color(accent.opacity(0.44)), lineWidth: 1.2)
                ctx.stroke(bLineL, with: .color(accent.opacity(0.14)), lineWidth: 7)

                var bLineR = Path()
                bLineR.move(to: CGPoint(x: sw, y: bridgeY))
                bLineR.addLine(to: CGPoint(x: sw * 0.76, y: bridgeY + bridgeH * 0.12))
                ctx.stroke(bLineR, with: .color(accent.opacity(0.44)), lineWidth: 1.2)
                ctx.stroke(bLineR, with: .color(accent.opacity(0.14)), lineWidth: 7)

                // 横刻みティック
                let ticY1: Double = strutH * 0.30
                let ticY2: Double = strutH * 0.58
                let lX1 = strutW * (1.0 - ticY1 / strutH) * 0.65
                let lX2 = strutW * (1.0 - ticY2 / strutH) * 0.65

                var lT1 = Path()
                lT1.move(to: CGPoint(x: 0, y: ticY1))
                lT1.addLine(to: CGPoint(x: lX1, y: ticY1))
                ctx.stroke(lT1, with: .color(Color.white.opacity(0.09)), lineWidth: 0.8)

                var lT2 = Path()
                lT2.move(to: CGPoint(x: 0, y: ticY2))
                lT2.addLine(to: CGPoint(x: lX2, y: ticY2))
                ctx.stroke(lT2, with: .color(Color.white.opacity(0.06)), lineWidth: 0.6)

                var rT1 = Path()
                rT1.move(to: CGPoint(x: sw, y: ticY1))
                rT1.addLine(to: CGPoint(x: sw - lX1, y: ticY1))
                ctx.stroke(rT1, with: .color(Color.white.opacity(0.09)), lineWidth: 0.8)

                var rT2 = Path()
                rT2.move(to: CGPoint(x: sw, y: ticY2))
                rT2.addLine(to: CGPoint(x: sw - lX2, y: ticY2))
                ctx.stroke(rT2, with: .color(Color.white.opacity(0.06)), lineWidth: 0.6)

                // コーナードット
                ctx.fill(Path(ellipseIn: CGRect(x: eOff - 3, y: 0, width: 6, height: 6)),
                         with: .color(accent.opacity(0.82)))
                ctx.fill(Path(ellipseIn: CGRect(x: sw - eOff - 3, y: 0, width: 6, height: 6)),
                         with: .color(accent.opacity(0.82)))

                // 内側シャドウ
                var lSh = Path()
                lSh.move(to: CGPoint(x: eOff, y: 0))
                lSh.addLine(to: CGPoint(x: eOff + 22, y: 0))
                lSh.addLine(to: CGPoint(x: 22, y: strutH - 2))
                lSh.addLine(to: CGPoint(x: 0, y: strutH - 2))
                lSh.closeSubpath()
                ctx.fill(lSh, with: .color(Color.black.opacity(0.35)))

                var rSh = Path()
                rSh.move(to: CGPoint(x: sw - eOff, y: 0))
                rSh.addLine(to: CGPoint(x: sw - eOff - 22, y: 0))
                rSh.addLine(to: CGPoint(x: sw - 22, y: strutH - 2))
                rSh.addLine(to: CGPoint(x: sw, y: strutH - 2))
                rSh.closeSubpath()
                ctx.fill(rSh, with: .color(Color.black.opacity(0.35)))

                // ── ALERT グロー（3層、score > 0.58 で発動）
                let alertT = max(0.0, scoreIntensity - 0.58) / 0.42
                if alertT > 0 {
                    let aR = Color(red: 0.97, green: 0.06, blue: 0.06)

                    var laG = Path()
                    laG.move(to: CGPoint(x: eOff, y: 0))
                    laG.addLine(to: CGPoint(x: 0, y: strutH - 2))
                    ctx.stroke(laG, with: .color(aR.opacity(alertT * 0.55)), lineWidth: 30)
                    ctx.stroke(laG, with: .color(aR.opacity(alertT * 0.72)), lineWidth: 5)
                    ctx.stroke(laG, with: .color(aR.opacity(alertT * 0.90)), lineWidth: 2.0)

                    var raG = Path()
                    raG.move(to: CGPoint(x: sw - eOff, y: 0))
                    raG.addLine(to: CGPoint(x: sw, y: strutH - 2))
                    ctx.stroke(raG, with: .color(aR.opacity(alertT * 0.55)), lineWidth: 30)
                    ctx.stroke(raG, with: .color(aR.opacity(alertT * 0.72)), lineWidth: 5)
                    ctx.stroke(raG, with: .color(aR.opacity(alertT * 0.90)), lineWidth: 2.0)

                    var taG = Path()
                    taG.move(to: CGPoint(x: eOff, y: 1.5))
                    taG.addLine(to: CGPoint(x: sw - eOff, y: 1.5))
                    ctx.stroke(taG, with: .color(aR.opacity(alertT * 0.62)), lineWidth: 18)
                    ctx.stroke(taG, with: .color(aR.opacity(alertT * 0.86)), lineWidth: 1.6)

                    var baL = Path()
                    baL.move(to: CGPoint(x: 0, y: bridgeY))
                    baL.addLine(to: CGPoint(x: sw * 0.24, y: bridgeY + bridgeH * 0.12))
                    ctx.stroke(baL, with: .color(aR.opacity(alertT * 0.38)), lineWidth: 8)
                    ctx.stroke(baL, with: .color(aR.opacity(alertT * 0.65)), lineWidth: 1.2)

                    var baR = Path()
                    baR.move(to: CGPoint(x: sw, y: bridgeY))
                    baR.addLine(to: CGPoint(x: sw * 0.76, y: bridgeY + bridgeH * 0.12))
                    ctx.stroke(baR, with: .color(aR.opacity(alertT * 0.38)), lineWidth: 8)
                    ctx.stroke(baR, with: .color(aR.opacity(alertT * 0.65)), lineWidth: 1.2)
                }
            }
        }
        .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
    }

    // MARK: - ヘッダー（背景パネル付き、ノッチ被り防止）

    private var cockpitHeader: some View {
        HStack(spacing: 0) {
            // 接続状態ピル
            Button { showStatusDetail = true } label: {
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
            }
            .buttonStyle(.plain)

            Spacer()

            // センタータイトル（背景パネルで視認性確保、ノッチ被り防止）
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    Text("MIND")
                        .font(.system(size: 17, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .tracking(5.0)
                        .shadow(color: .black.opacity(0.90), radius: 8)
                        .shadow(color: .black.opacity(0.60), radius: 3)
                    Text(" WAVE")
                        .font(.system(size: 17, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(scoreAccentColor.opacity(0.97))
                        .tracking(5.0)
                        .shadow(color: scoreAccentColor.opacity(0.60), radius: 8)
                        .shadow(color: scoreAccentColor.opacity(0.22), radius: 20)
                        .shadow(color: .black.opacity(0.70), radius: 4)
                        .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
                }
                Text("STRESS  &  BIOMETRICS")
                    .font(.system(size: 7, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .tracking(2.8)
                    .shadow(color: .black.opacity(0.90), radius: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.42))
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.10), Color.cyan.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )

            Spacer()

            // 右側ボタン群
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

    // MARK: - ダッシュボード

    private func cockpitDashboard(dashH: CGFloat) -> some View {
        let accent = scoreAccentColor
        return VStack(spacing: 0) {
            // コンソール上端ブリッジ
            Canvas { ctx, size in
                let w = size.width, h = size.height
                var base = Path()
                base.move(to: CGPoint(x: 0, y: h - 1))
                base.addLine(to: CGPoint(x: w, y: h - 1))
                ctx.stroke(base, with: .color(Color.white.opacity(0.16)), lineWidth: 1.0)

                var acL = Path()
                acL.move(to: CGPoint(x: w * 0.08, y: h - 1))
                acL.addLine(to: CGPoint(x: w * 0.92, y: h - 1))
                ctx.stroke(acL, with: .color(accent.opacity(0.85)), lineWidth: 2.2)
                ctx.stroke(acL, with: .color(accent.opacity(0.35)), lineWidth: 14)

                var l2 = Path()
                l2.move(to: CGPoint(x: w * 0.22, y: h - 4))
                l2.addLine(to: CGPoint(x: w * 0.78, y: h - 4))
                ctx.stroke(l2, with: .color(accent.opacity(0.28)), lineWidth: 0.8)

                for xf in [0.08, 0.92] as [Double] {
                    let nx = w * xf
                    ctx.fill(Path(ellipseIn: CGRect(x: nx - 4, y: h - 5, width: 8, height: 8)),
                             with: .color(accent.opacity(0.74)))
                    ctx.stroke(Path(ellipseIn: CGRect(x: nx - 6, y: h - 7, width: 12, height: 12)),
                               with: .color(accent.opacity(0.26)), lineWidth: 0.8)
                }
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.5 - 2.5, y: h - 4.5, width: 5, height: 5)),
                         with: .color(accent.opacity(0.46)))
                for xf in [0.25, 0.75] as [Double] {
                    ctx.fill(Path(ellipseIn: CGRect(x: w * xf - 2, y: h - 3.5, width: 4, height: 4)),
                             with: .color(accent.opacity(0.35)))
                }
            }
            .frame(height: 22)
            .animation(.easeInOut(duration: 1.2), value: scoreIntensity)

            Spacer(minLength: 2)

            // レバー型ナビゲーション
            CockpitLeverNav(selectedTab: $selectedTab, accentColor: scoreAccentColor)
                .padding(.horizontal, 14)
                .frame(height: 52)

            Spacer(minLength: 4)

            // 計器行
            HStack(alignment: .center, spacing: 8) {
                pulsePanel.frame(maxWidth: .infinity, alignment: .leading)
                mainLaunchButton
                signalPanel.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
        .frame(height: dashH)
        .background(cockpitPanelBackground)
    }

    // MARK: - コックピットパネル背景（CockpitPanelShape 多重グラデーション）

    private var cockpitPanelBackground: some View {
        let accent = scoreAccentColor
        let danger = dangerTint
        return ZStack {
            CockpitPanelShape(chamfer: 28)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.11, blue: 0.24),
                        Color(red: 0.04, green: 0.06, blue: 0.16),
                        Color(red: 0.01, green: 0.02, blue: 0.10)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
            CockpitPanelShape(chamfer: 28)
                .fill(danger.opacity(0.30))
                .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
            if scoreIntensity > 0.60 {
                let t = min(1.0, (scoreIntensity - 0.60) / 0.40)
                CockpitPanelShape(chamfer: 28)
                    .stroke(Color(red: 0.97, green: 0.06, blue: 0.06)
                        .opacity(t * (buttonGlow ? 0.72 : 0.42)), lineWidth: 4.0)
                    .blur(radius: 6)
                    .animation(.easeInOut(duration: 0.9), value: buttonGlow)
                CockpitPanelShape(chamfer: 28)
                    .stroke(Color(red: 1.0, green: 0.06, blue: 0.06).opacity(t * 0.88), lineWidth: 1.0)
            }
            CockpitPanelShape(chamfer: 28)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.07), .clear],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.14)
                ))
            CockpitPanelShape(chamfer: 28)
                .fill(LinearGradient(
                    colors: [.clear, Color.white.opacity(0.014), .clear, Color.white.opacity(0.012), .clear],
                    startPoint: .init(x: 0.5, y: 0.18), endPoint: .init(x: 0.5, y: 0.58)
                ))
            CockpitPanelShape(chamfer: 28)
                .stroke(LinearGradient(
                    colors: [accent.opacity(0.68), accent.opacity(0.16)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1.0)
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
            CockpitPanelShape(chamfer: 28)
                .stroke(accent.opacity(0.62), lineWidth: 2.5)
                .blur(radius: 4)
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
            CockpitPanelShape(chamfer: 28)
                .stroke(accent.opacity(0.24), lineWidth: 12)
                .blur(radius: 16)
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
            CockpitPanelShape(chamfer: 28)
                .fill(LinearGradient(
                    colors: [Color.black.opacity(0.34), .clear],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12)
                ))
            GeometryReader { g in
                RadialGradient(
                    colors: [
                        accent.opacity(0.10 + scoreIntensity * 0.10),
                        accent.opacity(0.04 + scoreIntensity * 0.04),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.20),
                    startRadius: 20,
                    endRadius: g.size.width * 0.40
                )
                .clipShape(CockpitPanelShape(chamfer: 28))
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
            }
        }
    }

    // MARK: - PULSE 計器パネル（Canvas金属フレーム + 42pt BPM + ECG）

    private var pulsePanel: some View {
        let accent  = scoreAccentColor
        let hasData = hasRealHeartRate
        let hrText  = heartRateDisplay

        return ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cr: CGFloat = 9
                ctx.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: cr),
                    with: .color(Color(red: 0.05, green: 0.08, blue: 0.20))
                )
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: h * 0.34), cornerRadius: cr - 1),
                    with: .color(Color.white.opacity(0.025))
                )
                var topHL = Path()
                topHL.move(to: CGPoint(x: cr + 1, y: 1.3))
                topHL.addLine(to: CGPoint(x: w - cr - 1, y: 1.3))
                ctx.stroke(topHL, with: .color(Color.white.opacity(0.22)), lineWidth: 1.3)
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0.6, y: 0.6, width: w - 1.2, height: h - 1.2), cornerRadius: cr),
                    with: .color(accent.opacity(0.34)), lineWidth: 0.8
                )
                var lEdge = Path()
                lEdge.move(to: CGPoint(x: 1.5, y: cr + 2))
                lEdge.addLine(to: CGPoint(x: 1.5, y: h - cr - 2))
                ctx.stroke(lEdge, with: .color(accent.opacity(0.80)), lineWidth: 2.5)
                ctx.stroke(lEdge, with: .color(accent.opacity(0.24)), lineWidth: 9)
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: 16), cornerRadius: cr - 1),
                    with: .color(Color.black.opacity(0.30))
                )
                var divider = Path()
                divider.move(to: CGPoint(x: 9, y: h - 29))
                divider.addLine(to: CGPoint(x: w - 9, y: h - 29))
                ctx.stroke(divider, with: .color(Color.white.opacity(0.07)), lineWidth: 0.6)
                for i in 0..<8 {
                    let ty = h * 0.30 + CGFloat(i) * 5.0
                    let major = (i % 4 == 0)
                    var tick = Path()
                    tick.move(to: CGPoint(x: w - (major ? 10 : 7), y: ty))
                    tick.addLine(to: CGPoint(x: w - 3, y: ty))
                    ctx.stroke(tick, with: .color(Color.white.opacity(major ? 0.16 : 0.07)),
                               lineWidth: major ? 0.9 : 0.6)
                }
                var arc = Path()
                arc.addArc(center: CGPoint(x: 9, y: h - 9), radius: h * 0.28,
                           startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                ctx.stroke(arc, with: .color(accent.opacity(0.11)), lineWidth: 0.8)
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: h - 28, width: w - 4, height: 26), cornerRadius: 0),
                    with: .color(Color.black.opacity(0.10))
                )
            }
            .animation(.easeInOut(duration: 1.0), value: scoreIntensity)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    ZStack {
                        Circle().fill(hasData ? accent.opacity(0.22) : Color.clear).frame(width: 8, height: 8)
                        Circle().fill(hasData ? accent : Color.white.opacity(0.10)).frame(width: 4, height: 4)
                            .shadow(color: hasData ? accent.opacity(0.90) : .clear, radius: 4)
                    }
                    Text("PULSE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(hasData ? 0.70 : 0.28))
                        .tracking(2.0)
                    Spacer()
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(hasData
                            ? Color(red: 0.92, green: 0.28, blue: 0.30)
                            : Color.white.opacity(0.12))
                        .shadow(color: hasData ? Color.red.opacity(0.60) : .clear, radius: 4)
                }
                .padding(.top, 8)
                .padding(.horizontal, 9)

                // 42pt BPM 数値（仕様必須）
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(hrText)
                        .font(.system(size: 42, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(hasData ? Color.white.opacity(0.96) : Color.white.opacity(0.18))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.30), value: hrText)
                        .shadow(color: hasData ? accent.opacity(0.40) : .clear, radius: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 10)
                        Text("BPM")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(hasData ? 0.44 : 0.12))
                            .tracking(1.2)
                    }
                }
                .padding(.horizontal, 9)

                Spacer(minLength: 2)

                // ECG 波形
                Canvas { ctx, sz in
                    let mid = sz.height * 0.52
                    let amp = hasData ? sz.height * 0.38 : sz.height * 0.04
                    let xs: [CGFloat] = [0, 0.06, 0.11, 0.16, 0.22, 0.26, 0.31, 0.37, 0.43,
                                         0.48, 0.50, 0.56, 0.61, 0.66, 0.72, 0.76, 0.81, 0.87,
                                         0.93, 0.97, 1.0]
                    let ys: [CGFloat] = [0, -0.05, -0.22, 0.30, 0, -0.90, 1.0, -0.30, 0.32,
                                         0, 0, -0.05, -0.22, 0.30, 0, -0.90, 1.0, -0.30, 0.32,
                                         0, 0]
                    var p = Path()
                    for i in 0..<xs.count {
                        let pt = CGPoint(x: xs[i] * sz.width, y: mid - ys[i] * amp)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    let a: CGFloat = hasData ? 0.65 : 0.10
                    ctx.stroke(p, with: .color(Color.cyan.opacity(a * 0.28)), lineWidth: 3.2)
                    ctx.stroke(p, with: .color(Color.cyan.opacity(a)), lineWidth: 0.9)
                }
                .frame(height: 20)
                .padding(.horizontal, 9)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 90)
        .animation(.easeInOut(duration: 0.40), value: hasRealHeartRate)
    }

    // MARK: - 138pt 計測ボタン（多重リング・較正マーク・アラートリング）

    private var mainLaunchButton: some View {
        let ac: Color  = isLive ? .orange : scoreAccentColor
        let gI: Double = 0.72 + scoreIntensity * 0.26

        return Button {
            viewModel.toggleLiveMonitoring()
        } label: {
            ZStack {
                // L1 最外メタルベゼル
                Circle()
                    .stroke(AngularGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.05),
                                 Color.white.opacity(0.04), Color.white.opacity(0.16),
                                 Color.white.opacity(0.22)],
                        center: .center), lineWidth: 2.0)
                    .frame(width: 138, height: 138)
                // L2
                Circle().stroke(ac.opacity(0.18), lineWidth: 1.0).frame(width: 128, height: 128)
                // L3 メイン発光リング
                Circle()
                    .stroke(ac.opacity(gI), lineWidth: 2.5)
                    .frame(width: 116, height: 116)
                    .shadow(color: ac.opacity(0.82), radius: 8)
                    .shadow(color: ac.opacity(0.36), radius: 20)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)
                // L4
                Circle().stroke(ac.opacity(0.28), lineWidth: 0.8).frame(width: 104, height: 104)
                // L5
                Circle()
                    .stroke(LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.0)
                    .frame(width: 94, height: 94)
                // L6
                Circle().stroke(ac.opacity(0.16), lineWidth: 0.6).frame(width: 82, height: 82)
                // ガラス面
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            Color(hue: isLive ? 0.07 : max(0, 0.65 - scoreIntensity * 0.55),
                                  saturation: 0.88,
                                  brightness: 0.18 + scoreIntensity * 0.16),
                            Color(red: 0.02, green: 0.04, blue: 0.16),
                            Color.black.opacity(0.94)
                        ],
                        center: UnitPoint(x: 0.32, y: 0.24),
                        startRadius: 0, endRadius: 40))
                    .frame(width: 78, height: 78)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)
                // ガラスハイライト
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.06), .clear],
                        startPoint: UnitPoint(x: 0.22, y: 0.04),
                        endPoint: UnitPoint(x: 0.62, y: 0.55)))
                    .frame(width: 78, height: 78)
                // 環境グロー
                Circle()
                    .fill(RadialGradient(
                        colors: [ac.opacity(0.15 + scoreIntensity * 0.12), .clear],
                        center: .center, startRadius: 0, endRadius: 35))
                    .frame(width: 78, height: 78)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)
                // アイコン + ラベル
                VStack(spacing: 5) {
                    Image(systemName: isLive ? "waveform" : "waveform.path.ecg")
                        .font(.system(size: 17, weight: .ultraLight))
                        .foregroundStyle(ac.opacity(0.97))
                        .shadow(color: ac, radius: 10)
                        .shadow(color: ac.opacity(0.50), radius: 22)
                    Text(isLive ? "停止" : "計測開始")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isLive ? Color.orange.opacity(0.92) : Color.white.opacity(0.82))
                        .tracking(1.0)
                }
            }
            .frame(width: 138, height: 138)
            // 呼吸パルスリング
            .overlay(
                Circle()
                    .stroke(ac.opacity(buttonGlow ? 0.28 : 0.02), lineWidth: 1.4)
                    .scaleEffect(buttonGlow ? 1.20 : 0.93)
                    .frame(width: 155, height: 155)
                    .blur(radius: 2.5)
                    .animation(
                        .easeInOut(duration: buttonPulseDuration).repeatForever(autoreverses: true),
                        value: buttonGlow)
            )
            // 外周スキャンリング
            .overlay(
                Circle()
                    .stroke(ac.opacity(0.07 + scoreIntensity * 0.10), lineWidth: 0.7)
                    .frame(width: 162, height: 162)
                    .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: isLive)
        .accessibilityIdentifier("home_measure_start_button")
        .accessibilityLabel(isLive ? "計測を停止する" : "ライブ計測を開始する")
        // 較正マーク（Canvas）
        .overlay(
            Canvas { ctx, size in
                let cx = size.width / 2, cy = size.height / 2
                let outerR = size.width / 2 - 2
                for i in 0..<24 {
                    let angle = Double(i) * (.pi / 12.0) - .pi / 2.0
                    let isCard = (i % 6 == 0)
                    let isOct  = (i % 3 == 0) && !isCard
                    guard isCard || isOct else { continue }
                    let tLen: Double = isCard ? 8 : 4
                    let x1 = cx + outerR * cos(angle)
                    let y1 = cy + outerR * sin(angle)
                    let x2 = cx + (outerR - tLen) * cos(angle)
                    let y2 = cy + (outerR - tLen) * sin(angle)
                    var t = Path()
                    t.move(to: CGPoint(x: x1, y: y1))
                    t.addLine(to: CGPoint(x: x2, y: y2))
                    let ac2 = isLive ? Color.orange : scoreAccentColor
                    ctx.stroke(t, with: .color(ac2.opacity(isCard ? 0.62 : 0.32)),
                               lineWidth: isCard ? 1.2 : 0.7)
                    if isCard {
                        ctx.fill(Path(ellipseIn: CGRect(x: x1 - 2, y: y1 - 2, width: 4, height: 4)),
                                 with: .color(ac2.opacity(0.72)))
                    }
                }
            }
            .frame(width: 164, height: 164)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 1.2), value: isLive)
        )
        // ALERT リング（score > 0.70）
        .overlay(
            Group {
                if scoreIntensity > 0.70 {
                    let t = (scoreIntensity - 0.70) / 0.30
                    Circle()
                        .stroke(AngularGradient(
                            colors: [
                                Color(red: 0.92, green: 0.28, blue: 0.04)
                                    .opacity(buttonGlow ? 0.60 : 0.28),
                                Color(red: 0.85, green: 0.08, blue: 0.05)
                                    .opacity(buttonGlow ? 0.45 : 0.18),
                                Color(red: 0.92, green: 0.28, blue: 0.04)
                                    .opacity(buttonGlow ? 0.60 : 0.28)
                            ],
                            center: .center), lineWidth: 1.6)
                        .frame(width: 174, height: 174)
                        .blur(radius: 4)
                        .opacity(t)
                        .animation(.easeInOut(duration: 0.85), value: buttonGlow)
                }
            }
            .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
        )
    }

    // MARK: - SIGNAL 波形パネル（ECGのみ・数値なし）

    private var signalPanel: some View {
        let accent  = scoreAccentColor
        let hasData = displayHasData

        return ZStack(alignment: .topTrailing) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cr: CGFloat = 9
                ctx.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: cr),
                    with: .color(Color(red: 0.04, green: 0.08, blue: 0.19))
                )
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: h * 0.34), cornerRadius: cr - 1),
                    with: .color(Color.white.opacity(0.022))
                )
                var topHL = Path()
                topHL.move(to: CGPoint(x: cr + 1, y: 1.3))
                topHL.addLine(to: CGPoint(x: w - cr - 1, y: 1.3))
                ctx.stroke(topHL, with: .color(Color.white.opacity(0.20)), lineWidth: 1.3)
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0.6, y: 0.6, width: w - 1.2, height: h - 1.2), cornerRadius: cr),
                    with: .color(accent.opacity(0.32)), lineWidth: 0.8
                )
                var rEdge = Path()
                rEdge.move(to: CGPoint(x: w - 1.5, y: cr + 2))
                rEdge.addLine(to: CGPoint(x: w - 1.5, y: h - cr - 2))
                ctx.stroke(rEdge, with: .color(accent.opacity(0.78)), lineWidth: 2.5)
                ctx.stroke(rEdge, with: .color(accent.opacity(0.24)), lineWidth: 9)
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: 16), cornerRadius: cr - 1),
                    with: .color(Color.black.opacity(0.28))
                )
                var divider = Path()
                divider.move(to: CGPoint(x: 9, y: h - 29))
                divider.addLine(to: CGPoint(x: w - 9, y: h - 29))
                ctx.stroke(divider, with: .color(Color.white.opacity(0.07)), lineWidth: 0.6)
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: h - 28, width: w - 4, height: 26), cornerRadius: 0),
                    with: .color(Color.black.opacity(0.10))
                )
            }
            .animation(.easeInOut(duration: 1.0), value: scoreIntensity)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 5) {
                    Spacer()
                    Text("SIGNAL")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent.opacity(hasData ? 0.70 : 0.28))
                        .tracking(1.5)
                    ZStack {
                        Circle().fill(hasData ? accent.opacity(0.22) : Color.clear).frame(width: 8, height: 8)
                        Circle().fill(hasData ? accent : Color.white.opacity(0.10)).frame(width: 4, height: 4)
                            .shadow(color: hasData ? accent.opacity(0.90) : .clear, radius: 4)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 9)

                Text(hasData ? (isLive ? "LIVE" : "ACTIVE") : "OFFLINE")
                    .font(.system(size: 17, weight: .thin, design: .monospaced))
                    .foregroundStyle(hasData ? Color.white.opacity(0.92) : Color.white.opacity(0.18))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 9)
                    .padding(.top, 4)
                    .animation(.easeInOut(duration: 0.40), value: hasData)

                Spacer(minLength: 2)

                Canvas { ctx, sz in
                    let mid = sz.height * 0.52
                    let amp = hasData ? sz.height * 0.36 : sz.height * 0.04
                    let xs: [CGFloat] = [0, 0.08, 0.14, 0.20, 0.28, 0.32, 0.36, 0.42,
                                         0.50, 0.54, 0.62, 0.68, 0.74, 0.82, 0.86, 0.90,
                                         0.96, 1.0]
                    let ys: [CGFloat] = [0, -0.04, 0.18, -0.12, 0, -0.85, 1.0, -0.28,
                                         0, 0, -0.04, 0.18, -0.12, 0, -0.85, 1.0, -0.28, 0]
                    var p = Path()
                    for i in 0..<xs.count {
                        let pt = CGPoint(x: xs[i] * sz.width, y: mid - ys[i] * amp)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    let a: CGFloat = hasData ? 0.65 : 0.10
                    ctx.stroke(p, with: .color(accent.opacity(a * 0.28)), lineWidth: 3.2)
                    ctx.stroke(p, with: .color(accent.opacity(a)), lineWidth: 0.9)
                }
                .frame(height: 20)
                .padding(.horizontal, 9)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 90)
        .animation(.easeInOut(duration: 0.40), value: scoreIntensity)
    }

    // MARK: - ステータス詳細シート

    private var statusDetailSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(narrativeTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text(narrativeBody)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider().overlay(Color.white.opacity(0.12))
                    HStack(spacing: 0) {
                        metricItem(label: "データソース", value: dataSourceLabel, accent: indicatorColor)
                        Divider().frame(height: 28).background(Color.white.opacity(0.10))
                        metricItem(label: "状態",
                                   value: viewModel.isLiveMonitoring ? "計測中" : "停止中",
                                   accent: viewModel.isLiveMonitoring ? Color.cyan : Color.white.opacity(0.35))
                    }
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.03, green: 0.03, blue: 0.08).ignoresSafeArea())
            .navigationTitle("ミッションステータス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { showStatusDetail = false }.foregroundStyle(Color.cyan)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func metricItem(label: String, value: String, accent: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - DEBUG Visual QA パレット

    #if DEBUG
    private var visualQAPalette: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.cyan.opacity(0.60))
                    .frame(width: 22)
                Text("QA")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.55))
                    .tracking(1.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)

            HStack(spacing: 5) {
                ForEach(visualQAStates.indices, id: \.self) { i in
                    let item = visualQAStates[i]
                    let active = visualPreviewScore == item.score
                    Button {
                        withAnimation(.easeInOut(duration: 0.20)) {
                            visualPreviewScore = item.score
                        }
                    } label: {
                        Text(item.label)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(active ? Color.black : Color.white.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(active ? Color.cyan : Color.white.opacity(0.10))
                                    if active {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(LinearGradient(
                                                colors: [Color.white.opacity(0.20), .clear],
                                                startPoint: .top, endPoint: .bottom))
                                    }
                                }
                            )
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    active ? Color.white.opacity(0.28) : Color.cyan.opacity(0.22),
                                    lineWidth: active ? 1.0 : 0.7))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("visual_state_\(item.id)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.84))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.cyan.opacity(0.35), lineWidth: 1.0))
        )
        .padding(.horizontal, 16)
    }

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

// MARK: - CockpitLeverNav（操縦席レール型ナビゲーション）

private struct CockpitLeverNav: View {
    @Binding var selectedTab: Int
    let accentColor: Color

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
        VStack(spacing: 2) {
            // ラベル行
            HStack(spacing: 0) {
                ForEach(navDefs.indices, id: \.self) { i in
                    let item = navDefs[i]
                    let active = selectedTab == item.tab
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.68)) {
                            selectedTab = item.tab
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: active ? .semibold : .ultraLight))
                                .foregroundStyle(active ? accentColor : Color.white.opacity(0.26))
                                .shadow(color: active ? accentColor.opacity(0.75) : .clear, radius: 6)
                            Text(item.label)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(active ? accentColor.opacity(0.94) : Color.white.opacity(0.25))
                                .tracking(0.2)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.22), value: active)
                    .accessibilityLabel(item.label)
                    .accessibilityIdentifier(item.tab == 1 ? "nav_calm" : item.tab == 0 ? "nav_home" : "nav_history")
                    .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                }
            }

            // 操縦レール
            GeometryReader { geo in
                let w = geo.size.width
                let positions: [CGFloat] = [w * 0.165, w * 0.50, w * 0.835]
                let knobX = positions[leverPos]

                ZStack(alignment: .leading) {
                    Canvas { ctx, size in
                        let rw = size.width, rh = size.height
                        let cr: CGFloat = rh / 2
                        ctx.fill(
                            Path(roundedRect: CGRect(x: 0, y: 0, width: rw, height: rh), cornerRadius: cr),
                            with: .color(Color(red: 0.08, green: 0.12, blue: 0.26))
                        )
                        ctx.fill(
                            Path(roundedRect: CGRect(x: 2, y: 2, width: rw - 4, height: rh - 4), cornerRadius: cr - 2),
                            with: .color(Color(red: 0.04, green: 0.06, blue: 0.16))
                        )
                        var rail = Path()
                        rail.move(to: CGPoint(x: cr, y: rh / 2))
                        rail.addLine(to: CGPoint(x: rw - cr, y: rh / 2))
                        ctx.stroke(rail, with: .color(Color.white.opacity(0.08)), lineWidth: 1.0)
                        ctx.stroke(
                            Path(roundedRect: CGRect(x: 0.5, y: 0.5, width: rw - 1, height: rh - 1), cornerRadius: cr),
                            with: .color(Color.white.opacity(0.10)), lineWidth: 0.6
                        )
                        for xf in [0.165, 0.500, 0.835] as [Double] {
                            let mx = rw * xf
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: mx - 2, y: rh / 2 - 2, width: 4, height: 4)),
                                with: .color(Color.white.opacity(0.18))
                            )
                        }
                    }
                    .frame(height: 18)

                    // ノブグロー
                    Capsule()
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 44, height: 14)
                        .blur(radius: 8)
                        .offset(x: knobX - 22, y: 2)
                        .animation(.spring(response: 0.30, dampingFraction: 0.68), value: leverPos)

                    // ノブ本体
                    ZStack {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.22, green: 0.30, blue: 0.52),
                                         Color(red: 0.10, green: 0.14, blue: 0.30)],
                                startPoint: .top, endPoint: .bottom))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.24), .clear],
                                startPoint: .top, endPoint: .center))
                        Capsule()
                            .strokeBorder(accentColor.opacity(0.88), lineWidth: 1.2)
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 1, height: 10)
                    }
                    .frame(width: 52, height: 24)
                    .shadow(color: accentColor.opacity(0.60), radius: 8)
                    .shadow(color: .black.opacity(0.40), radius: 4, y: 2)
                    .offset(x: knobX - 26, y: -3)
                    .animation(.spring(response: 0.30, dampingFraction: 0.68), value: leverPos)
                }
                .frame(height: 18)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("cockpit_nav_lever")
            }
            .frame(height: 18)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { v in
                        if v.translation.width > 40 {
                            if leverPos == 0 { withAnimation { selectedTab = 0 } }
                            else if leverPos == 1 { withAnimation { selectedTab = 2 } }
                        } else if v.translation.width < -40 {
                            if leverPos == 2 { withAnimation { selectedTab = 0 } }
                            else if leverPos == 1 { withAnimation { selectedTab = 1 } }
                        }
                    }
            )
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(MindWaveViewModel())
        .environmentObject(AppFlowState())
}
