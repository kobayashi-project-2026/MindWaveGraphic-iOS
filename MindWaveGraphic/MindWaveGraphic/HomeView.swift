//
//  HomeView.swift
//  MindWaveGraphic
//
//  コックピット内部からの前方視点。宇宙空間グラフィックが主役。
//  1画面完結 — ScrollView なし。グラフィック57%＋ダッシュボード43%。
//  Phase C v3（発表向け改革版）: コックピット窓枠・メトリクス強化・統合パネル。
//  架空の値は使用しない。データ未取得時は「—」で表示する。
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var flowState: AppFlowState
    @Binding var selectedTab: Int

    @State private var showSettingsSheet  = false
    @State private var showDebugSheet     = false
    @State private var showBreathingSheet = false
    @State private var breathingMode: MindWaveBreathingMode = .fourSevenEight
    @State private var showStatusDetail   = false
    @State private var buttonGlow: Bool    = false

    #if DEBUG
    // DEBUG専用: visual QA状態の上書き（バックエンド無影響）
    @State private var visualPreviewScore: Double? = nil
    private let visualQAStates: [(label: String, id: String, score: Double?)] = [
        ("OFF",  "off",      nil),
        ("CALM", "calm",     12.0),
        ("FCUS", "focus",    40.0),
        ("ALRT", "alert",    70.0),
        ("OVLD", "overload", 92.0),
    ]
    #endif

    // 表示用入力（DEBUG上書きがあればそちらを優先、バックエンドは無変更）
    private var displayInput: GraphicInput {
        #if DEBUG
        if let score = visualPreviewScore {
            return GraphicInput(score: score, confidence: 1.0, state: .optimalTension)
        }
        #endif
        return viewModel.graphicInput
    }

    // DEBUG上書き中はデータあり扱いにして STATE パネルを正しく表示する
    private var displayHasData: Bool {
        #if DEBUG
        if visualPreviewScore != nil { return true }
        #endif
        return viewModel.didFetchHeartRate || viewModel.didFetchHRV
    }

    // MARK: - Score-reactive accent

    // score 0-100 → 0.0-1.0 (displayInput で DEBUG上書きを反映)
    private var scoreIntensity: Double {
        min(max(displayInput.score / 100.0, 0.0), 1.0)
    }

    // 低: 深青 / 中: シアン→緑 / 高: 橙→赤/深紅（ALERT明確・OVERLOAD警告赤）
    private var scoreAccentColor: Color {
        let t = scoreIntensity
        if t < 0.30 {
            // 深い青→シアン
            let phase = t / 0.30
            return Color(hue: 0.68 - phase * 0.10, saturation: 0.90, brightness: 0.88)
        } else if t < 0.65 {
            // シアン→グリーン→橙（0.58→0.10）
            let phase = (t - 0.30) / 0.35
            return Color(hue: 0.58 - phase * 0.48, saturation: 0.92, brightness: 0.97)
        } else {
            // ALERT→OVERLOAD: 橙→深赤/深紅（0.10→0.00）
            let phase = (t - 0.65) / 0.35
            let h = 0.10 - phase * 0.10
            return Color(hue: h < 0 ? h + 1 : h, saturation: 0.96, brightness: 1.0)
        }
    }

    // 高緊張時の警戒赤味（ALERT以降で深紅化）
    private var dangerTint: Color {
        guard scoreIntensity > 0.60 else { return .clear }
        let t = min(1.0, (scoreIntensity - 0.60) / 0.40)
        return Color(red: 0.88 * t, green: 0.0, blue: 0.04 * t)
    }

    // 計測ボタン呼吸パルス周期 (低=3.5s, 高=1.2s)
    private var buttonPulseDuration: Double {
        3.5 - scoreIntensity * 2.3
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let tabBarInset: CGFloat = MainTabView.missionBarReservedHeight
            let availH   = geo.size.height - tabBarInset
            let graphicH = availH * 0.72
            let dashH    = availH * 0.28

            ZStack(alignment: .top) {
                // ── 宇宙空間背景
                Color(red: 0.00, green: 0.01, blue: 0.06)
                    .ignoresSafeArea()

                // ── 星粒子グラフィック
                GraphicHostView(input: displayInput)
                    .frame(maxWidth: .infinity)
                    .frame(height: graphicH)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                // ── コックピット窓枠（三角ストラット構造）
                cockpitWindowFrame
                    .frame(height: graphicH)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                // ── グラフィック上端グラデーション（ヘッダー可読性）
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.62), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 90)
                    Spacer()
                }
                .frame(height: graphicH)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // ── グラフィック下端グラデーション（パネルへの接続）
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(red: 0.04, green: 0.07, blue: 0.19).opacity(0.45),
                            Color(red: 0.05, green: 0.09, blue: 0.21).opacity(0.80),
                            Color(red: 0.06, green: 0.10, blue: 0.22).opacity(0.96)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 72)
                }
                .frame(height: graphicH)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // ── ヘッダー
                cockpitHeader
                    .padding(.top, 8)
                    .padding(.horizontal, 18)
                    .zIndex(50)

                #if DEBUG
                // ── Visual QA パレット（DEBUG専用: タブバー直上に浮遊、大タップ領域）
                visualQAPalette
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .zIndex(51)
                    .allowsHitTesting(true)
                #endif

                // ── ダッシュボード
                VStack(spacing: 0) {
                    Spacer()
                    cockpitDashboard(dashH: dashH)
                    Spacer().frame(height: tabBarInset)
                }
            }
        }
        .onAppear {
            print("[CockpitHome] appeared")
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                buttonGlow = true
            }
            #if DEBUG
            if let qaScore = resolveVisualQAScore() {
                visualPreviewScore = qaScore
                print("[VisualQA] env override score=\(qaScore)")
            }
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
        .fullScreenCover(isPresented: $showBreathingSheet) {
            BreathingFromHomeWrapper(initialMode: breathingMode)
        }
    }

    // MARK: - コックピット窓枠

    private var cockpitWindowFrame: some View {
        let accent = scoreAccentColor
        return ZStack {
            // ── ストラット本体（Canvas）
            Canvas { ctx, size in
                let sw = size.width
                let sh = size.height
                let strutW = sw * 0.175   // 幅を増やして重厚感アップ
                let strutH = sh * 0.92
                let bridgeY = sh * 0.83
                let bridgeH = sh - bridgeY

                // ─ 左ストラット（外側 = 真っ黒）
                var lStrut = Path()
                lStrut.move(to: .zero)
                lStrut.addLine(to: CGPoint(x: strutW, y: 0))
                lStrut.addLine(to: CGPoint(x: 0, y: strutH))
                lStrut.closeSubpath()
                ctx.fill(lStrut, with: .color(Color.black.opacity(0.95)))

                // 左ストラット メタル層（斜め光沢）
                var lMetal = Path()
                lMetal.move(to: CGPoint(x: strutW, y: 0))
                lMetal.addLine(to: CGPoint(x: strutW * 0.75, y: 0))
                lMetal.addLine(to: CGPoint(x: 0, y: strutH * 0.72))
                lMetal.addLine(to: CGPoint(x: 0, y: strutH))
                lMetal.closeSubpath()
                ctx.fill(lMetal, with: .color(Color(red: 0.04, green: 0.07, blue: 0.18).opacity(0.70)))

                // 左ストラット 中央ハイライト帯（ベベル光）
                var lBevel = Path()
                lBevel.move(to: CGPoint(x: strutW * 0.42, y: 0))
                lBevel.addLine(to: CGPoint(x: strutW * 0.52, y: 0))
                lBevel.addLine(to: CGPoint(x: strutW * 0.08, y: strutH * 0.85))
                lBevel.addLine(to: CGPoint(x: 0, y: strutH * 0.85))
                lBevel.closeSubpath()
                ctx.fill(lBevel, with: .color(Color.white.opacity(0.025)))

                // ─ 右ストラット
                var rStrut = Path()
                rStrut.move(to: CGPoint(x: sw, y: 0))
                rStrut.addLine(to: CGPoint(x: sw - strutW, y: 0))
                rStrut.addLine(to: CGPoint(x: sw, y: strutH))
                rStrut.closeSubpath()
                ctx.fill(rStrut, with: .color(Color.black.opacity(0.95)))

                var rMetal = Path()
                rMetal.move(to: CGPoint(x: sw - strutW, y: 0))
                rMetal.addLine(to: CGPoint(x: sw - strutW * 0.75, y: 0))
                rMetal.addLine(to: CGPoint(x: sw, y: strutH * 0.72))
                rMetal.addLine(to: CGPoint(x: sw, y: strutH))
                rMetal.closeSubpath()
                ctx.fill(rMetal, with: .color(Color(red: 0.04, green: 0.07, blue: 0.18).opacity(0.70)))

                var rBevel = Path()
                rBevel.move(to: CGPoint(x: sw - strutW * 0.42, y: 0))
                rBevel.addLine(to: CGPoint(x: sw - strutW * 0.52, y: 0))
                rBevel.addLine(to: CGPoint(x: sw - strutW * 0.08, y: strutH * 0.85))
                rBevel.addLine(to: CGPoint(x: sw, y: strutH * 0.85))
                rBevel.closeSubpath()
                ctx.fill(rBevel, with: .color(Color.white.opacity(0.025)))

                // ─ 下部ブリッジ
                var bridge = Path()
                bridge.move(to: CGPoint(x: 0, y: bridgeY))
                bridge.addLine(to: CGPoint(x: sw * 0.24, y: bridgeY + bridgeH * 0.12))
                bridge.addLine(to: CGPoint(x: sw * 0.40, y: sh))
                bridge.addLine(to: CGPoint(x: 0, y: sh))
                bridge.closeSubpath()
                ctx.fill(bridge, with: .color(Color.black.opacity(0.88)))

                var bridgeR = Path()
                bridgeR.move(to: CGPoint(x: sw, y: bridgeY))
                bridgeR.addLine(to: CGPoint(x: sw * 0.76, y: bridgeY + bridgeH * 0.12))
                bridgeR.addLine(to: CGPoint(x: sw * 0.60, y: sh))
                bridgeR.addLine(to: CGPoint(x: sw, y: sh))
                bridgeR.closeSubpath()
                ctx.fill(bridgeR, with: .color(Color.black.opacity(0.88)))

                // ══ エッジライト（3層: ソフトハロー / シャープライン / 細い二重）
                let eOff: Double = strutW  // 内辺のX位置

                // グロー層（太くてソフト）
                var lGlow = Path()
                lGlow.move(to: CGPoint(x: eOff, y: 0))
                lGlow.addLine(to: CGPoint(x: 0, y: strutH - 2))
                ctx.stroke(lGlow, with: .color(accent.opacity(0.22)), lineWidth: 12)

                var rGlow = Path()
                rGlow.move(to: CGPoint(x: sw - eOff, y: 0))
                rGlow.addLine(to: CGPoint(x: sw, y: strutH - 2))
                ctx.stroke(rGlow, with: .color(accent.opacity(0.22)), lineWidth: 12)

                // シャープライン（メイン）
                var lEdge = Path()
                lEdge.move(to: CGPoint(x: eOff, y: 0))
                lEdge.addLine(to: CGPoint(x: 0, y: strutH - 2))
                ctx.stroke(lEdge, with: .color(accent.opacity(0.70)), lineWidth: 1.5)

                var rEdge = Path()
                rEdge.move(to: CGPoint(x: sw - eOff, y: 0))
                rEdge.addLine(to: CGPoint(x: sw, y: strutH - 2))
                ctx.stroke(rEdge, with: .color(accent.opacity(0.70)), lineWidth: 1.5)

                // 内側二重ライン
                var lEdge2 = Path()
                lEdge2.move(to: CGPoint(x: eOff - 4, y: 0))
                lEdge2.addLine(to: CGPoint(x: 4, y: strutH - 2))
                ctx.stroke(lEdge2, with: .color(accent.opacity(0.25)), lineWidth: 0.7)

                var rEdge2 = Path()
                rEdge2.move(to: CGPoint(x: sw - eOff + 4, y: 0))
                rEdge2.addLine(to: CGPoint(x: sw - 4, y: strutH - 2))
                ctx.stroke(rEdge2, with: .color(accent.opacity(0.25)), lineWidth: 0.7)

                // 上端ライン
                var topLine = Path()
                topLine.move(to: CGPoint(x: eOff, y: 1.5))
                topLine.addLine(to: CGPoint(x: sw - eOff, y: 1.5))
                ctx.stroke(topLine, with: .color(accent.opacity(0.38)), lineWidth: 1.2)

                // 上端グロー
                var topGlow = Path()
                topGlow.move(to: CGPoint(x: eOff, y: 1.5))
                topGlow.addLine(to: CGPoint(x: sw - eOff, y: 1.5))
                ctx.stroke(topGlow, with: .color(accent.opacity(0.14)), lineWidth: 8)

                // ブリッジライン（左・右）
                var bLineL = Path()
                bLineL.move(to: CGPoint(x: 0, y: bridgeY))
                bLineL.addLine(to: CGPoint(x: sw * 0.24, y: bridgeY + bridgeH * 0.12))
                ctx.stroke(bLineL, with: .color(accent.opacity(0.42)), lineWidth: 1.2)

                var bLineR = Path()
                bLineR.move(to: CGPoint(x: sw, y: bridgeY))
                bLineR.addLine(to: CGPoint(x: sw * 0.76, y: bridgeY + bridgeH * 0.12))
                ctx.stroke(bLineR, with: .color(accent.opacity(0.42)), lineWidth: 1.2)

                // ブリッジグロー
                var bGlowL = Path()
                bGlowL.move(to: CGPoint(x: 0, y: bridgeY))
                bGlowL.addLine(to: CGPoint(x: sw * 0.24, y: bridgeY + bridgeH * 0.12))
                ctx.stroke(bGlowL, with: .color(accent.opacity(0.12)), lineWidth: 7)

                var bGlowR = Path()
                bGlowR.move(to: CGPoint(x: sw, y: bridgeY))
                bGlowR.addLine(to: CGPoint(x: sw * 0.76, y: bridgeY + bridgeH * 0.12))
                ctx.stroke(bGlowR, with: .color(accent.opacity(0.12)), lineWidth: 7)

                // ストラット横アクセントライン（機械的な刻み）
                let ticY1: Double = strutH * 0.30
                let ticY2: Double = strutH * 0.58

                // 左ストラット横アクセント
                var lTic1 = Path()
                let lX1at1 = strutW * (1.0 - ticY1/strutH)
                lTic1.move(to: CGPoint(x: 0, y: ticY1))
                lTic1.addLine(to: CGPoint(x: lX1at1 * 0.65, y: ticY1))
                ctx.stroke(lTic1, with: .color(Color.white.opacity(0.08)), lineWidth: 0.8)

                var lTic2 = Path()
                let lX1at2 = strutW * (1.0 - ticY2/strutH)
                lTic2.move(to: CGPoint(x: 0, y: ticY2))
                lTic2.addLine(to: CGPoint(x: lX1at2 * 0.65, y: ticY2))
                ctx.stroke(lTic2, with: .color(Color.white.opacity(0.06)), lineWidth: 0.6)

                // 右ストラット横アクセント（対称）
                var rTic1 = Path()
                rTic1.move(to: CGPoint(x: sw, y: ticY1))
                rTic1.addLine(to: CGPoint(x: sw - lX1at1 * 0.65, y: ticY1))
                ctx.stroke(rTic1, with: .color(Color.white.opacity(0.08)), lineWidth: 0.8)

                var rTic2 = Path()
                rTic2.move(to: CGPoint(x: sw, y: ticY2))
                rTic2.addLine(to: CGPoint(x: sw - lX1at2 * 0.65, y: ticY2))
                ctx.stroke(rTic2, with: .color(Color.white.opacity(0.06)), lineWidth: 0.6)

                // コーナーアクセントドット（左右上コーナー）
                ctx.fill(
                    Path(ellipseIn: CGRect(x: eOff - 3, y: 0, width: 6, height: 6)),
                    with: .color(accent.opacity(0.80))
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: sw - eOff - 3, y: 0, width: 6, height: 6)),
                    with: .color(accent.opacity(0.80))
                )

                // 内側星空エッジシャドウ（奥行き）
                var lShadow = Path()
                lShadow.move(to: CGPoint(x: eOff, y: 0))
                lShadow.addLine(to: CGPoint(x: eOff + 22, y: 0))
                lShadow.addLine(to: CGPoint(x: 22, y: strutH - 2))
                lShadow.addLine(to: CGPoint(x: 0, y: strutH - 2))
                lShadow.closeSubpath()
                ctx.fill(lShadow, with: .color(Color.black.opacity(0.35)))

                var rShadow = Path()
                rShadow.move(to: CGPoint(x: sw - eOff, y: 0))
                rShadow.addLine(to: CGPoint(x: sw - eOff - 22, y: 0))
                rShadow.addLine(to: CGPoint(x: sw - 22, y: strutH - 2))
                rShadow.addLine(to: CGPoint(x: sw, y: strutH - 2))
                rShadow.closeSubpath()
                ctx.fill(rShadow, with: .color(Color.black.opacity(0.35)))

                // ── 高緊張アラートグロー (t>0.58 → 赤がストラット縁に強く立ち上がる)
                let alertT = max(0.0, scoreIntensity - 0.58) / 0.42
                if alertT > 0 {
                    let alertR = Color(red: 0.97, green: 0.06, blue: 0.06)
                    // 左ストラット — 広ソフトハロー
                    var lAlertGlow = Path()
                    lAlertGlow.move(to: CGPoint(x: eOff, y: 0))
                    lAlertGlow.addLine(to: CGPoint(x: 0, y: strutH - 2))
                    ctx.stroke(lAlertGlow, with: .color(alertR.opacity(alertT * 0.55)),
                               lineWidth: 30)
                    // 左ストラット — ミディアムグロー
                    ctx.stroke(lAlertGlow, with: .color(alertR.opacity(alertT * 0.72)),
                               lineWidth: 5)
                    // 左ストラット — シャープコア
                    ctx.stroke(lAlertGlow, with: .color(alertR.opacity(alertT * 0.90)),
                               lineWidth: 2.0)

                    // 右ストラット — 広ソフトハロー
                    var rAlertGlow = Path()
                    rAlertGlow.move(to: CGPoint(x: sw - eOff, y: 0))
                    rAlertGlow.addLine(to: CGPoint(x: sw, y: strutH - 2))
                    ctx.stroke(rAlertGlow, with: .color(alertR.opacity(alertT * 0.55)),
                               lineWidth: 30)
                    ctx.stroke(rAlertGlow, with: .color(alertR.opacity(alertT * 0.72)),
                               lineWidth: 5)
                    ctx.stroke(rAlertGlow, with: .color(alertR.opacity(alertT * 0.90)),
                               lineWidth: 2.0)

                    // 上端アラートライン（強：パルスライン）
                    var topAlert = Path()
                    topAlert.move(to: CGPoint(x: eOff, y: 1.5))
                    topAlert.addLine(to: CGPoint(x: sw - eOff, y: 1.5))
                    ctx.stroke(topAlert, with: .color(alertR.opacity(alertT * 0.62)),
                               lineWidth: 18)
                    ctx.stroke(topAlert, with: .color(alertR.opacity(alertT * 0.85)),
                               lineWidth: 1.6)

                    // ブリッジにも赤みを伝播
                    var bAlertL = Path()
                    bAlertL.move(to: CGPoint(x: 0, y: bridgeY))
                    bAlertL.addLine(to: CGPoint(x: sw * 0.24, y: bridgeY + bridgeH * 0.12))
                    ctx.stroke(bAlertL, with: .color(alertR.opacity(alertT * 0.38)), lineWidth: 8)
                    ctx.stroke(bAlertL, with: .color(alertR.opacity(alertT * 0.65)), lineWidth: 1.2)
                    var bAlertR = Path()
                    bAlertR.move(to: CGPoint(x: sw, y: bridgeY))
                    bAlertR.addLine(to: CGPoint(x: sw * 0.76, y: bridgeY + bridgeH * 0.12))
                    ctx.stroke(bAlertR, with: .color(alertR.opacity(alertT * 0.38)), lineWidth: 8)
                    ctx.stroke(bAlertR, with: .color(alertR.opacity(alertT * 0.65)), lineWidth: 1.2)
                }
            }
        }
    }

    // MARK: - ヘッダー

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

            // センタータイトル（MIND白 / WAVE cyan の2色）
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    Text("MIND")
                        .font(.system(size: 17, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .tracking(5.0)
                        .shadow(color: .black.opacity(0.90), radius: 8)
                        .shadow(color: .black.opacity(0.60), radius: 3)
                    Text(" WAVE")
                        .font(.system(size: 17, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(scoreAccentColor.opacity(0.96))
                        .tracking(5.0)
                        .shadow(color: scoreAccentColor.opacity(0.55), radius: 8)
                        .shadow(color: scoreAccentColor.opacity(0.22), radius: 20)
                        .shadow(color: .black.opacity(0.70), radius: 4)
                        .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
                }
                Text("STRESS  &  BIOMETRICS")
                    .font(.system(size: 7, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .tracking(2.8)
                    .shadow(color: .black.opacity(0.90), radius: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.38))
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

            // 右側（設定 + dbg）
            HStack(spacing: 0) {
                Button {
                    showSettingsSheet = true
                    print("[CockpitHome] settings_opened")
                } label: {
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
                Button {
                    showDebugSheet = true
                    print("[CockpitHome] debug_sheet_opened")
                } label: {
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

    #if DEBUG
    // MARK: - Visual QA パレット（DEBUG専用：タブバー直上、大きなタップ領域）

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
                                                startPoint: .top, endPoint: .bottom
                                            ))
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        active ? Color.white.opacity(0.28) : Color.cyan.opacity(0.22),
                                        lineWidth: active ? 1.0 : 0.7
                                    )
                            )
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
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.cyan.opacity(0.35), lineWidth: 1.0)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, MainTabView.missionBarReservedHeight + 6)
    }

    private func resolveVisualQAScore() -> Double? {
        guard let state = ProcessInfo.processInfo.environment["VISUAL_QA_STATE"] else { return nil }
        switch state.uppercased() {
        case "CALM":     return 12.0
        case "FOCUS":    return 40.0
        case "ALERT":    return 70.0
        case "OVERLOAD": return 92.0
        default:         return nil
        }
    }
    #endif

    // MARK: - ダッシュボード

    private func cockpitDashboard(dashH: CGFloat) -> some View {
        let accent = scoreAccentColor
        return VStack(spacing: 0) {
            // ── コンソール上端ブリッジ（窓枠→計器盤の接続ライン）
            Canvas { ctx, size in
                let w = size.width, h = size.height
                // 全幅ベースライン（薄）
                var baseLine = Path()
                baseLine.move(to: CGPoint(x: 0, y: h - 1))
                baseLine.addLine(to: CGPoint(x: w, y: h - 1))
                ctx.stroke(baseLine, with: .color(Color.white.opacity(0.16)), lineWidth: 1.0)
                // 中央アクセントライン（score連動グロー）
                var accentLine = Path()
                accentLine.move(to: CGPoint(x: w * 0.10, y: h - 1))
                accentLine.addLine(to: CGPoint(x: w * 0.90, y: h - 1))
                ctx.stroke(accentLine, with: .color(accent.opacity(0.82)), lineWidth: 2.2)
                ctx.stroke(accentLine, with: .color(accent.opacity(0.34)), lineWidth: 14)
                // セカンドライン（2px上）
                var line2 = Path()
                line2.move(to: CGPoint(x: w * 0.25, y: h - 4))
                line2.addLine(to: CGPoint(x: w * 0.75, y: h - 4))
                ctx.stroke(line2, with: .color(accent.opacity(0.30)), lineWidth: 0.8)
                // 左右接続ノード（大）
                for xFrac in [0.10, 0.90] as [Double] {
                    let nx = w * xFrac
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: nx - 4, y: h - 5, width: 8, height: 8)),
                        with: .color(accent.opacity(0.72))
                    )
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: nx - 6, y: h - 7, width: 12, height: 12)),
                        with: .color(accent.opacity(0.25)), lineWidth: 0.8
                    )
                }
                // 中央補助ノード
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.5 - 2.5, y: h - 4.5, width: 5, height: 5)),
                    with: .color(accent.opacity(0.45))
                )
                // 左右対称小ノード（1/4位置）
                for xFrac in [0.25, 0.75] as [Double] {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: w * xFrac - 2, y: h - 3.5, width: 4, height: 4)),
                        with: .color(accent.opacity(0.35))
                    )
                }
            }
            .frame(height: 22)
            .animation(.easeInOut(duration: 1.2), value: scoreIntensity)

            Spacer(minLength: 2)

            // ── CONTEXTチップ（常時表示・タップで設定変更）
            Button {
                flowState.authStatus = .contextCalibration
            } label: {
                HStack(spacing: 6) {
                    Text("CONTEXT")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.65))
                        .tracking(1.2)
                    Rectangle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 0.7, height: 11)
                    Image(systemName: flowState.measurementContext.scene.icon)
                        .font(.system(size: 8))
                        .foregroundStyle(Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.80))
                    Text(contextChipDisplayLabel)
                        .font(.system(size: 9, weight: .light, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .frame(maxWidth: 155, alignment: .leading)
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        Color(red: 0.35, green: 0.75, blue: 0.95).opacity(
                            flowState.measurementContext.isDefault ? 0.13 : 0.28
                        ),
                        lineWidth: 0.6
                    )
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .accessibilityIdentifier("home_context_chip")
            .accessibilityLabel("状況設定: \(contextChipDisplayLabel)。タップで変更")

            // ── 上段: PULSE | 大型計測ボタン | STATE
            HStack(alignment: .center, spacing: 8) {
                pulsePanel
                    .frame(maxWidth: .infinity, alignment: .leading)
                mainLaunchButton
                statePanel
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

            // ── 下段: Quick Work
            quickWorkRow
                .frame(height: 50)
                .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
        .frame(height: dashH)
        .background(cockpitPanelBackground)
    }

    // MARK: - コックピットパネル背景

    private var cockpitPanelBackground: some View {
        let accent = scoreAccentColor
        let danger = dangerTint

        return ZStack {
            // 深いメタリックグラデーション（3層）
            CockpitPanelShape(chamfer: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.10, blue: 0.22),
                            Color(red: 0.03, green: 0.05, blue: 0.14),
                            Color(red: 0.01, green: 0.02, blue: 0.09)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 高緊張時: 危険感の赤いオーバーレイ（ALERT以降で深紅化）
            CockpitPanelShape(chamfer: 28)
                .fill(danger.opacity(0.28))
                .animation(.easeInOut(duration: 1.0), value: scoreIntensity)

            // 高緊張時: アラートボーダー（パネル縁に赤が強く立ち上がる）
            if scoreIntensity > 0.60 {
                let alertBorderT = min(1.0, (scoreIntensity - 0.60) / 0.40)
                // 外側ワイドグロー
                CockpitPanelShape(chamfer: 28)
                    .stroke(
                        Color(red: 0.97, green: 0.06, blue: 0.06)
                            .opacity(alertBorderT * (buttonGlow ? 0.72 : 0.40)),
                        lineWidth: 4.0
                    )
                    .blur(radius: 6)
                    .animation(.easeInOut(duration: 0.9), value: buttonGlow)
                    .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
                // 内側シャープライン
                CockpitPanelShape(chamfer: 28)
                    .stroke(
                        Color(red: 1.0, green: 0.06, blue: 0.06)
                            .opacity(alertBorderT * 0.88),
                        lineWidth: 1.0
                    )
                    .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
            }

            // 上端ガラス反射ハイライト
            CockpitPanelShape(chamfer: 28)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.07), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.14)
                    )
                )

            // 水平スキャンライン（金属感テクスチャ）
            CockpitPanelShape(chamfer: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.015),
                            .clear,
                            Color.white.opacity(0.012),
                            .clear
                        ],
                        startPoint: .init(x: 0.5, y: 0.18),
                        endPoint: .init(x: 0.5, y: 0.55)
                    )
                )

            // 外縁ライン（score連動グラデ）
            CockpitPanelShape(chamfer: 28)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.65), accent.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)

            // 上端グロー1層（鋭いライン）
            CockpitPanelShape(chamfer: 28)
                .stroke(accent.opacity(0.60), lineWidth: 2.5)
                .blur(radius: 4)
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)

            // 上端グロー2層（ソフトハロー）
            CockpitPanelShape(chamfer: 28)
                .stroke(accent.opacity(0.22), lineWidth: 12)
                .blur(radius: 16)
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)

            // 内側上端シャドウ（奥行き）
            CockpitPanelShape(chamfer: 28)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.32), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.12)
                    )
                )

            // 中央環境グロー（計測装置背後 - score連動）
            GeometryReader { g in
                RadialGradient(
                    colors: [
                        accent.opacity(0.10 + scoreIntensity * 0.10),
                        accent.opacity(0.04 + scoreIntensity * 0.04),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.22),
                    startRadius: 20,
                    endRadius: g.size.width * 0.40
                )
                .clipShape(CockpitPanelShape(chamfer: 28))
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
            }

            // サイドアクセントライン（左右縦ライン）
            GeometryReader { g in
                let panelH = g.size.height
                HStack(spacing: 0) {
                    // 左サイドライン
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.clear, accent.opacity(0.40), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(width: 1.0)
                        .frame(height: panelH * 0.72)
                        .padding(.leading, 14)
                        .padding(.top, panelH * 0.12)
                    }
                    Spacer()
                    // 右サイドライン
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.clear, accent.opacity(0.40), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(width: 1.0)
                        .frame(height: panelH * 0.72)
                        .padding(.trailing, 14)
                        .padding(.top, panelH * 0.12)
                    }
                }
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
            }
        }
    }

    // MARK: - PULSE 計器パネル（コックピット計器グレード）

    private var pulsePanel: some View {
        let accent  = scoreAccentColor
        let hasData = hasRealHeartRate
        let hrText  = heartRateDisplay

        return ZStack(alignment: .topLeading) {
            // ── 金属フレーム（Canvas）
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cr: CGFloat = 9
                // ベース深みメタリック
                ctx.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: cr),
                    with: .color(Color(red: 0.05, green: 0.08, blue: 0.20))
                )
                // 内側上段ハイライト（ガラス感）
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: h * 0.36), cornerRadius: cr - 1),
                    with: .color(Color.white.opacity(0.024))
                )
                // 上端ベベル輝線
                var topHL = Path()
                topHL.move(to: CGPoint(x: cr + 1, y: 1.3))
                topHL.addLine(to: CGPoint(x: w - cr - 1, y: 1.3))
                ctx.stroke(topHL, with: .color(Color.white.opacity(0.20)), lineWidth: 1.3)
                // 外縁アウトライン（score連動）
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0.6, y: 0.6, width: w - 1.2, height: h - 1.2), cornerRadius: cr),
                    with: .color(accent.opacity(0.32)), lineWidth: 0.8
                )
                // 左エッジグロー（score連動）
                var lEdge = Path()
                lEdge.move(to: CGPoint(x: 1.5, y: cr + 2))
                lEdge.addLine(to: CGPoint(x: 1.5, y: h - cr - 2))
                ctx.stroke(lEdge, with: .color(accent.opacity(0.75)), lineWidth: 2.5)
                ctx.stroke(lEdge, with: .color(accent.opacity(0.22)), lineWidth: 9)
                // 内側上段シャドウ（奥行き）
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: 16), cornerRadius: cr - 1),
                    with: .color(Color.black.opacity(0.30))
                )
                // 下段仕切り線（計器分割）
                var divider = Path()
                divider.move(to: CGPoint(x: 9, y: h - 29))
                divider.addLine(to: CGPoint(x: w - 9, y: h - 29))
                ctx.stroke(divider, with: .color(Color.white.opacity(0.07)), lineWidth: 0.6)
                // 右端補助目盛り（8本：精度UP）
                for i in 0..<8 {
                    let ty = h * 0.30 + CGFloat(i) * 5.0
                    let isMajor = (i % 4 == 0)
                    var tick = Path()
                    tick.move(to: CGPoint(x: w - (isMajor ? 10 : 7), y: ty))
                    tick.addLine(to: CGPoint(x: w - 3, y: ty))
                    ctx.stroke(tick, with: .color(Color.white.opacity(isMajor ? 0.16 : 0.07)), lineWidth: isMajor ? 0.9 : 0.6)
                }
                // アーク型ゲージ背景（左下隅）
                var arc = Path()
                arc.addArc(center: CGPoint(x: 9, y: h - 9), radius: h * 0.28,
                           startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                ctx.stroke(arc, with: .color(accent.opacity(0.10)), lineWidth: 0.8)
                // 底辺パネルフィル
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: h - 28, width: w - 4, height: 26), cornerRadius: 0),
                    with: .color(Color.black.opacity(0.10))
                )
            }
            .animation(.easeInOut(duration: 1.0), value: scoreIntensity)

            // ── コンテンツ（SwiftUI）
            VStack(alignment: .leading, spacing: 0) {
                // 上段: ラベル + 状態ランプ
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(hasData ? accent.opacity(0.22) : Color.clear)
                            .frame(width: 8, height: 8)
                        Circle()
                            .fill(hasData ? accent : Color.white.opacity(0.10))
                            .frame(width: 4, height: 4)
                            .shadow(color: hasData ? accent.opacity(0.90) : .clear, radius: 4)
                    }
                    Text("PULSE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(hasData ? 0.70 : 0.28))
                        .tracking(2.0)
                    Spacer()
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(
                            hasData
                                ? Color(red: 0.92, green: 0.28, blue: 0.30)
                                : Color.white.opacity(0.12)
                        )
                        .shadow(color: hasData ? Color.red.opacity(0.60) : .clear, radius: 4)
                }
                .padding(.top, 8)
                .padding(.horizontal, 9)

                // 中段: BPM 大型数値
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(hrText)
                        .font(.system(size: 42, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(hasData ? Color.white.opacity(0.96) : Color.white.opacity(0.16))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.30), value: hrText)
                        .shadow(color: hasData ? accent.opacity(0.40) : .clear, radius: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 10)
                        Text("BPM")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(hasData ? 0.42 : 0.12))
                            .tracking(1.2)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.top, 0)

                Spacer(minLength: 2)

                // 下段: ECG 波形（Canvas）
                Canvas { ctx, sz in
                    let mid = sz.height * 0.52
                    let amp = hasData ? sz.height * 0.38 : sz.height * 0.04
                    let xs: [CGFloat] = [0,0.06,0.11,0.16,0.22,0.26,0.31,0.37,0.43,0.48,
                                         0.50,0.56,0.61,0.66,0.72,0.76,0.81,0.87,0.93,0.97,1.0]
                    let ys: [CGFloat] = [0,-0.05,-0.22,0.30,0,-0.90,1.0,-0.30,0.32,0,
                                         0,-0.05,-0.22,0.30,0,-0.90,1.0,-0.30,0.32,0,0]
                    var p = Path()
                    for i in 0..<xs.count {
                        let pt = CGPoint(x: xs[i] * sz.width, y: mid - ys[i] * amp)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    let a: CGFloat = hasData ? 0.62 : 0.10
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
        .animation(.easeInOut(duration: 0.40), value: hasData)
    }

    // MARK: - STATE 計器パネル

    private var statePanel: some View {
        let accent    = scoreAccentColor
        let hasData   = displayHasData
        let stateStr  = stateLabel
        let barCnt    = stateBarCount

        return ZStack(alignment: .topTrailing) {
            // ── 金属フレーム（Canvas）
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cr: CGFloat = 9
                ctx.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: cr),
                    with: .color(Color(red: 0.04, green: 0.08, blue: 0.19))
                )
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: h * 0.36), cornerRadius: cr - 1),
                    with: .color(Color.white.opacity(0.020))
                )
                var topHL = Path()
                topHL.move(to: CGPoint(x: cr + 1, y: 1.3))
                topHL.addLine(to: CGPoint(x: w - cr - 1, y: 1.3))
                ctx.stroke(topHL, with: .color(Color.white.opacity(0.18)), lineWidth: 1.3)
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0.6, y: 0.6, width: w - 1.2, height: h - 1.2), cornerRadius: cr),
                    with: .color(accent.opacity(0.30)), lineWidth: 0.8
                )
                var rEdge = Path()
                rEdge.move(to: CGPoint(x: w - 1.5, y: cr + 2))
                rEdge.addLine(to: CGPoint(x: w - 1.5, y: h - cr - 2))
                ctx.stroke(rEdge, with: .color(accent.opacity(0.72)), lineWidth: 2.5)
                ctx.stroke(rEdge, with: .color(accent.opacity(0.22)), lineWidth: 9)
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

            // ── コンテンツ（SwiftUI）
            VStack(alignment: .trailing, spacing: 0) {
                // 上段: ラベル + 状態ランプ
                HStack(spacing: 5) {
                    Spacer()
                    Text("STATE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent.opacity(hasData ? 0.70 : 0.28))
                        .tracking(1.5)
                    ZStack {
                        Circle()
                            .fill(hasData ? accent.opacity(0.22) : Color.clear)
                            .frame(width: 8, height: 8)
                        Circle()
                            .fill(hasData ? accent : Color.white.opacity(0.10))
                            .frame(width: 4, height: 4)
                            .shadow(color: hasData ? accent.opacity(0.90) : .clear, radius: 4)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 9)

                // 中段: 状態テキスト
                Text(stateStr)
                    .font(.system(size: 22, weight: .thin, design: .monospaced))
                    .foregroundStyle(hasData ? Color.white.opacity(0.94) : Color.white.opacity(0.16))
                    .tracking(1.0)
                    .contentTransition(.identity)
                    .animation(.easeInOut(duration: 0.40), value: stateStr)
                    .shadow(color: hasData ? accent.opacity(0.40) : .clear, radius: 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 9)
                    .padding(.top, 6)

                Spacer(minLength: 2)

                // 下段: 強度バー（右揃え・6本）
                HStack(alignment: .bottom, spacing: 3.0) {
                    ForEach(0..<6, id: \.self) { i in
                        let active = i < barCnt
                        let bh: CGFloat = 4 + CGFloat(i) * 3.8
                        ZStack {
                            Capsule()
                                .fill(active ? accent.opacity(0.12) : Color.clear)
                                .frame(width: 4, height: bh)
                            Capsule()
                                .fill(active
                                      ? (i == barCnt - 1 ? accent.opacity(0.92) : accent.opacity(0.52))
                                      : Color.white.opacity(0.07))
                                .frame(width: 3, height: bh)
                                .shadow(color: active && i == barCnt - 1 ? accent.opacity(0.60) : .clear, radius: 4)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.40), value: barCnt)
                .padding(.trailing, 9)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 90)
        .animation(.easeInOut(duration: 0.40), value: scoreIntensity)
    }

    private var stateBarCount: Int {
        guard displayHasData else { return 0 }
        return min(Int(scoreIntensity * 6.0 + 0.5), 6)
    }

    private var stateLabel: String {
        guard displayHasData else { return "—" }
        let t = scoreIntensity
        if t < 0.29 { return "CALM" }
        if t < 0.44 { return "READY" }
        if t < 0.59 { return "FOCUS" }
        if t < 0.79 { return "ALERT" }
        return "OVERLOAD"
    }

    private var contextChipDisplayLabel: String {
        let ctx = flowState.measurementContext
        if ctx.isDefault { return "安静" }
        var parts: [String] = [ctx.scene.displayName]
        let bodyConds = ctx.conditions.filter { $0 != .none }.prefix(2)
        parts.append(contentsOf: bodyConds.map { $0.displayName })
        return parts.joined(separator: " · ")
    }

    // MARK: - 大型計測ボタン（近未来計器ディスプレイ）

    private var mainLaunchButton: some View {
        let ac: Color  = isLive ? .orange : scoreAccentColor
        let gI: Double = 0.72 + scoreIntensity * 0.26

        return Button {
            viewModel.toggleLiveMonitoring()
            print("[CockpitHome] monitoring toggled")
        } label: {
            ZStack {
                // ── L1: 最外装メタルベゼル（上から右へ明るい）
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.22), Color.white.opacity(0.05),
                                Color.white.opacity(0.04), Color.white.opacity(0.16),
                                Color.white.opacity(0.22)
                            ],
                            center: .center
                        ),
                        lineWidth: 2.0
                    )
                    .frame(width: 138, height: 138)

                // ── L2: アウターリング（score連動色）
                Circle()
                    .stroke(ac.opacity(0.18), lineWidth: 1.0)
                    .frame(width: 128, height: 128)

                // ── L3: メイン発光リング（二重シャドウ）
                Circle()
                    .stroke(ac.opacity(gI), lineWidth: 2.5)
                    .frame(width: 116, height: 116)
                    .shadow(color: ac.opacity(0.80), radius: 8)
                    .shadow(color: ac.opacity(0.35), radius: 20)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)

                // ── L4: ミッドリング（細い）
                Circle()
                    .stroke(ac.opacity(0.28), lineWidth: 0.8)
                    .frame(width: 104, height: 104)

                // ── L5: インナーリング（メタル）
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
                    .frame(width: 94, height: 94)

                // ── L6: インナーアクセント
                Circle()
                    .stroke(ac.opacity(0.16), lineWidth: 0.6)
                    .frame(width: 82, height: 82)

                // ── ガラス面（深いラジアルグラデ）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hue: isLive ? 0.07 : max(0, 0.65 - scoreIntensity * 0.55),
                                      saturation: 0.88,
                                      brightness: 0.18 + scoreIntensity * 0.16),
                                Color(red: 0.02, green: 0.04, blue: 0.16),
                                Color.black.opacity(0.94)
                            ],
                            center: UnitPoint(x: 0.32, y: 0.24),
                            startRadius: 0, endRadius: 40
                        )
                    )
                    .frame(width: 78, height: 78)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)

                // ガラスハイライト（レンズ効果 - 強化）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.06),
                                .clear
                            ],
                            startPoint: UnitPoint(x: 0.22, y: 0.04),
                            endPoint: UnitPoint(x: 0.62, y: 0.55)
                        )
                    )
                    .frame(width: 78, height: 78)

                // 内側環境グロー（score連動）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ac.opacity(0.15 + scoreIntensity * 0.12), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 35
                        )
                    )
                    .frame(width: 78, height: 78)
                    .animation(.easeInOut(duration: 0.8), value: scoreIntensity)

                // ガラス小ハイライト（右下 反射）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.06), .clear],
                            center: UnitPoint(x: 0.72, y: 0.78),
                            startRadius: 0,
                            endRadius: 18
                        )
                    )
                    .frame(width: 78, height: 78)

                // ── アイコン + テキスト
                VStack(spacing: 5) {
                    Image(systemName: isLive ? "waveform" : "waveform.path.ecg")
                        .font(.system(size: 17, weight: .ultraLight))
                        .foregroundStyle(ac.opacity(0.97))
                        .shadow(color: ac, radius: 10)
                        .shadow(color: ac.opacity(0.50), radius: 22)
                    Text(isLive ? "停止" : "計測開始")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isLive ? Color.orange.opacity(0.90) : Color.white.opacity(0.80))
                        .tracking(1.0)
                }
            }
            .frame(width: 138, height: 138)
            // 呼吸パルスリング（score連動周期）
            .overlay(
                Circle()
                    .stroke(ac.opacity(buttonGlow ? 0.28 : 0.02), lineWidth: 1.4)
                    .scaleEffect(buttonGlow ? 1.20 : 0.93)
                    .frame(width: 155, height: 155)
                    .blur(radius: 2.5)
            )
            // 外周スキャンリング（常時薄く）
            .overlay(
                Circle()
                    .stroke(ac.opacity(0.07 + scoreIntensity * 0.10), lineWidth: 0.7)
                    .frame(width: 162, height: 162)
                    .animation(.easeInOut(duration: 1.2), value: scoreIntensity)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: isLive)
        .accessibilityLabel(isLive ? "計測を停止する" : "ライブ計測を開始する")
        // ── 外周カリブレーションリング（分度器状目盛り）
        .overlay(
            Canvas { ctx, size in
                let cx = size.width / 2
                let cy = size.height / 2
                let outerR = size.width / 2 - 2
                for i in 0..<24 {
                    let angle = Double(i) * (.pi / 12.0) - .pi / 2.0
                    let isCardinal = (i % 6 == 0)
                    let isOctant   = (i % 3 == 0) && !isCardinal
                    guard isCardinal || isOctant else { continue }
                    let tickLen: Double = isCardinal ? 8 : 4
                    let x1 = cx + outerR * cos(angle)
                    let y1 = cy + outerR * sin(angle)
                    let x2 = cx + (outerR - tickLen) * cos(angle)
                    let y2 = cy + (outerR - tickLen) * sin(angle)
                    var tick = Path()
                    tick.move(to: CGPoint(x: x1, y: y1))
                    tick.addLine(to: CGPoint(x: x2, y: y2))
                    ctx.stroke(tick,
                               with: .color(ac.opacity(isCardinal ? 0.62 : 0.32)),
                               lineWidth: isCardinal ? 1.2 : 0.7)
                    if isCardinal {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x1 - 2, y: y1 - 2, width: 4, height: 4)),
                            with: .color(ac.opacity(0.72))
                        )
                    }
                }
            }
            .frame(width: 164, height: 164)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 1.2), value: isLive)
        )
        // ── 高緊張アラートリング（scoreIntensity > 0.70 で出現）
        .overlay(
            Group {
                if scoreIntensity > 0.70 {
                    let alertT = (scoreIntensity - 0.70) / 0.30
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color(red: 0.92, green: 0.28, blue: 0.04)
                                        .opacity(buttonGlow ? 0.60 : 0.28),
                                    Color(red: 0.85, green: 0.08, blue: 0.05)
                                        .opacity(buttonGlow ? 0.45 : 0.18),
                                    Color(red: 0.92, green: 0.28, blue: 0.04)
                                        .opacity(buttonGlow ? 0.60 : 0.28)
                                ],
                                center: .center
                            ),
                            lineWidth: 1.6
                        )
                        .frame(width: 174, height: 174)
                        .blur(radius: 4)
                        .opacity(alertT)
                        .animation(.easeInOut(duration: 0.85), value: buttonGlow)
                }
            }
            .animation(.easeInOut(duration: 1.0), value: scoreIntensity)
        )
    }

    // MARK: - Quick Work

    private var quickWorkRow: some View {
        HStack(spacing: 7) {
            quickCard(mode: .fourSevenEight, label: "4-7-8",  desc: "深い弛緩",    icon: "moon.stars.fill", duration: "15 MIN")
            quickCard(mode: .box,            label: "BOX",    desc: "集中・安定",  icon: "square.fill",     duration: "5 MIN")
            quickCard(mode: .twoOneFour,     label: "2-1-4",  desc: "緊張を手放す", icon: "leaf.fill",      duration: "5 MIN")
        }
    }

    private func quickCard(mode: MindWaveBreathingMode, label: String, desc: String, icon: String, duration: String) -> some View {
        Button {
            breathingMode = mode
            showBreathingSheet = true
            print("[CockpitHome] quick_work mode=\(mode.displayName)")
        } label: {
            ZStack(alignment: .topLeading) {
                // ── カード本体
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.07, green: 0.15, blue: 0.34),
                                Color(red: 0.03, green: 0.07, blue: 0.20),
                                Color(red: 0.02, green: 0.04, blue: 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 上端スコア連動カラーライン
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [scoreAccentColor.opacity(0.60), scoreAccentColor.opacity(0.08)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 1.2)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .animation(.easeInOut(duration: 1.2), value: scoreIntensity)

                // カードボーダー（スコア連動）
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        LinearGradient(
                            colors: [scoreAccentColor.opacity(0.35), Color.white.opacity(0.06), scoreAccentColor.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                    .animation(.easeInOut(duration: 1.2), value: scoreIntensity)

                // 内側シャドウ（下部）
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.30)],
                        startPoint: .center, endPoint: .bottom
                    )
                    .frame(height: 20)
                }
                .clipShape(RoundedRectangle(cornerRadius: 11))

                // ── コンテンツ
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(scoreAccentColor.opacity(0.12))
                                .frame(width: 22, height: 22)
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(scoreAccentColor.opacity(0.92))
                                .shadow(color: Color.cyan.opacity(0.60), radius: 5)
                                .shadow(color: Color.cyan.opacity(0.25), radius: 12)
                        }
                        Spacer(minLength: 0)
                        Text(duration)
                            .font(.system(size: 6, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.48))
                            .tracking(0.3)
                            .padding(.top, 1)
                    }
                    .padding(.bottom, 4)

                    Text(label)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .minimumScaleFactor(0.82)
                    Text(desc)
                        .font(.system(size: 7.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) 呼吸法 \(duration)")
        .accessibilityHint(desc)
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
                        metricItem(label: "データソース", value: dataSourceLabel,  accent: indicatorColor)
                        Divider().frame(height: 28).background(Color.white.opacity(0.10))
                        metricItem(
                            label: "スコア",
                            value: (viewModel.didFetchHeartRate || viewModel.didFetchHRV)
                                ? String(format: "%.0f", viewModel.graphicInput.score)
                                : "—",
                            accent: scoreAccentColor
                        )
                        Divider().frame(height: 28).background(Color.white.opacity(0.10))
                        metricItem(
                            label: "状態",
                            value: viewModel.isLiveMonitoring ? "計測中" : "停止中",
                            accent: viewModel.isLiveMonitoring ? Color.cyan : Color.white.opacity(0.35)
                        )
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
                    Button("閉じる") { showStatusDetail = false }
                        .foregroundStyle(Color.cyan)
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 計算プロパティ

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
        case .watchLive:
            return viewModel.isLiveMonitoring
                ? "リアルタイム計測中"
                : "計測を開始できます"
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

// MARK: - 呼吸ガイド遷移ラッパー

private struct BreathingFromHomeWrapper: View {
    let initialMode: MindWaveBreathingMode
    @State private var syncDone = false

    var body: some View {
        if syncDone {
            MindWaveBreathingGuideView(initialMode: initialMode)
        } else {
            MindWaveSyncTransitionView(subtitle: "呼吸ガイドを準備しています") {
                syncDone = true
            }
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(MindWaveViewModel())
        .environmentObject(AppFlowState())
}
