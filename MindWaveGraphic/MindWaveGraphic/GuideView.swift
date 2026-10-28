//
//  GuideView.swift
//  MindWaveGraphic
//
//  「整える」画面。場面を選んでから呼吸ガイドへ進む。
//  架空の値は使用しない。GuideFlowViewへの遷移を維持する。
//

import SwiftUI

struct GuideView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var historyStore: GuideHistoryStore
    // AI相談は共通の画面遷移管理（AppNavigationManager のモーダル）で開く
    @EnvironmentObject var navManager: AppNavigationManager
    @Binding var selectedTab: Int

    @State private var selectedScene: MeasurementScene? = nil
    @State private var showFlowView   = false
    @State private var showOtherSheet = false

    private let primaryScenes: [MeasurementScene] = [.interview, .sports, .social, .other]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    selectionHint
                        .padding(.horizontal, 20)
                    sceneGrid
                        .padding(.horizontal, 20)
                    if let scene = selectedScene {
                        AISceneSuggestionView(scene: scene)
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    AIConsultEntryCard { navManager.navigate(to: .aiChat) }
                        .padding(.horizontal, 20)
                    Spacer().frame(height: 8)
                }
                .padding(.top, 4)
                .animation(.easeInOut(duration: 0.22), value: selectedScene)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                pageHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .background(Color(red: 0.02, green: 0.02, blue: 0.06).opacity(0.98))
            }
            ctaSection
            Spacer().frame(height: MainTabView.missionBarReservedHeight)
        }
        .background(background)
        .onAppear {
            print("[UI][Guide] view_appeared")
            #if DEBUG
            if ProcessInfo.processInfo.environment["GUIDE_PHASE"] == "session"
               || ProcessInfo.processInfo.environment["GUIDE_PHASE"] == "result" {
                selectedScene = .interview
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showFlowView = true
                }
            }
            #endif
        }
        .fullScreenCover(isPresented: $showFlowView) {
            GuideFlowView(selectedTab: $selectedTab, initialScene: selectedScene)
                .environmentObject(viewModel)
                .environmentObject(historyStore)
        }
        .sheet(isPresented: $showOtherSheet) {
            OtherSceneSelectorView(
                selectedScene: $selectedScene,
                isPresented: $showOtherSheet
            )
        }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.06).ignoresSafeArea()
            // HUDグリッド
            CyberGridShape(cellSize: 44)
                .stroke(Color.cyan.opacity(0.052), lineWidth: 0.5)
                .ignoresSafeArea()
            // 上部消失点グロー（宇宙感の奥行き）
            RadialGradient(
                colors: [
                    Color(hue: 0.62, saturation: 0.90, brightness: 0.85).opacity(0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 0, endRadius: 280
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // 散在星ドット（静的・深宇宙感）
            Canvas { ctx, sz in
                let dots: [(x: Double, y: Double, r: CGFloat, a: CGFloat)] = [
                    (0.08, 0.06, 0.9, 0.40), (0.23, 0.13, 0.6, 0.28), (0.72, 0.04, 1.1, 0.48),
                    (0.88, 0.10, 0.7, 0.32), (0.45, 0.09, 0.8, 0.36), (0.61, 0.17, 0.5, 0.24),
                    (0.14, 0.22, 0.6, 0.30), (0.37, 0.19, 1.0, 0.42), (0.82, 0.21, 0.7, 0.34),
                    (0.95, 0.28, 0.8, 0.38), (0.04, 0.35, 0.5, 0.22), (0.55, 0.30, 0.6, 0.26),
                    (0.78, 0.38, 0.9, 0.44), (0.29, 0.42, 0.7, 0.32), (0.91, 0.44, 0.5, 0.20),
                    (0.18, 0.50, 0.8, 0.36), (0.66, 0.48, 1.0, 0.45), (0.43, 0.55, 0.6, 0.28),
                ]
                for d in dots {
                    let x = sz.width  * CGFloat(d.x)
                    let y = sz.height * CGFloat(d.y)
                    let r = d.r
                    let a = d.a
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(Color.cyan.opacity(Double(a)))
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r * 2, y: y - r * 2, width: r * 4, height: r * 4)),
                        with: .color(Color.cyan.opacity(Double(a * 0.15)))
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // 下部から上向きのコックピットパネル反射グロー
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color(red: 0.02, green: 0.07, blue: 0.22).opacity(0.55), .clear],
                    startPoint: .bottom, endPoint: .top
                )
                .frame(height: 180)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)
            // コックピットサイドストラット（計器パネル感）
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.07), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    Canvas { ctx, size in
                        let sh = size.height
                        // ストラット内側エッジライン
                        var el = Path()
                        el.move(to: CGPoint(x: size.width - 1, y: sh * 0.10))
                        el.addLine(to: CGPoint(x: size.width - 1, y: sh * 0.90))
                        ctx.stroke(el, with: .color(Color.cyan.opacity(0.22)), lineWidth: 0.6)
                        // リベット（等間隔3点）
                        for i in 0..<3 {
                            let y = sh * (0.25 + Double(i) * 0.25)
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: size.width - 5, y: y - 1.5, width: 3, height: 3)),
                                with: .color(Color.cyan.opacity(0.28))
                            )
                        }
                    }
                }
                .frame(width: 22)
                Spacer()
                ZStack(alignment: .trailing) {
                    LinearGradient(
                        colors: [.clear, Color.cyan.opacity(0.07)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    Canvas { ctx, size in
                        let sh = size.height
                        var el = Path()
                        el.move(to: CGPoint(x: 1, y: sh * 0.10))
                        el.addLine(to: CGPoint(x: 1, y: sh * 0.90))
                        ctx.stroke(el, with: .color(Color.cyan.opacity(0.22)), lineWidth: 0.6)
                        for i in 0..<3 {
                            let y = sh * (0.25 + Double(i) * 0.25)
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: 2, y: y - 1.5, width: 3, height: 3)),
                                with: .color(Color.cyan.opacity(0.28))
                            )
                        }
                    }
                }
                .frame(width: 22)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - ページヘッダー

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            // HUD ラベル行
            HStack(spacing: 8) {
                Text("MISSION CTRL")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.55))
                    .tracking(1.8)
                Rectangle()
                    .fill(Color.cyan.opacity(0.18))
                    .frame(height: 0.6)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.cyan.opacity(i == 2 ? 0.55 : 0.18))
                            .frame(width: 3, height: 3)
                    }
                }
            }
            Text("整える")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)
            Text("シチュエーションを選んで呼吸ガイドを開始します")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.38))
                .tracking(0.1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 選択ヒント

    @ViewBuilder
    private var selectionHint: some View {
        if let scene = selectedScene {
            HStack(spacing: 12) {
                Image(systemName: scene.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.cyan)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardTitle(for: scene))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("この場面に合わせた呼吸ガイドで整えます")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.50))
                }
                Spacer()
                Button {
                    selectedScene = nil
                    print("[UI][Guide] scene_cleared")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.30))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("選択を解除する")
            }
            .padding(14)
            .background(
                ZStack {
                    Color(red: 0.04, green: 0.07, blue: 0.14)
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.cyan.opacity(0.75))
                            .frame(width: 2.5)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cyan.opacity(0.30), lineWidth: 1))
            .animation(.easeInOut(duration: 0.2), value: selectedScene)
        } else {
            Text("どんな場面の前ですか？")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 場面グリッド（2×2）

    private var sceneGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(primaryScenes) { scene in
                sceneCard(scene)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedScene)
    }

    private func sceneCard(_ scene: MeasurementScene) -> some View {
        let selected = isSelected(scene)
        return Button {
            if scene == .other {
                showOtherSheet = true
            } else {
                selectedScene = scene
                print("[UI][Guide] scene_selected value=\(scene.rawValue)")
            }
        } label: {
            VStack(spacing: 10) {
                Spacer()
                ZStack {
                    // 場面固有の背景モチーフ
                    Circle()
                        .fill(selected ? Color.cyan.opacity(0.20) : sceneAccent(scene).opacity(0.08))
                        .frame(width: 52, height: 52)
                    Image(systemName: scene.icon)
                        .font(.system(size: 24, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.cyan : sceneAccent(scene))
                }
                VStack(spacing: 3) {
                    Text(cardTitle(for: scene))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.85))
                        .lineLimit(1)
                    Text(cardSubtitle(for: scene))
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.60) : Color.white.opacity(0.38))
                        .lineLimit(1)
                }
                Spacer()
                // 選択インジケーター
                if selected {
                    Capsule()
                        .fill(Color.cyan)
                        .frame(width: 24, height: 3)
                        .padding(.bottom, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected
                              ? Color(red: 0.04, green: 0.10, blue: 0.18)
                              : Color(red: 0.03, green: 0.06, blue: 0.14))
                    // 上端ハイライトリップ（計器パネル感）
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(selected ? 0.09 : 0.05), .clear],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.18)
                        ))
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            selected ? Color.cyan.opacity(0.55) : Color.cyan.opacity(0.18),
                            lineWidth: selected ? 1.5 : 1.0
                        )
                    // 非選択時でも外周にわずかなグロー
                    if !selected {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan.opacity(0.08), lineWidth: 3)
                            .blur(radius: 3)
                    }
                    // 選択時: 左エッジ発光
                    if selected {
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.cyan.opacity(0.75))
                                .frame(width: 2.5)
                                .blur(radius: 1)
                                .shadow(color: Color.cyan.opacity(0.50), radius: 5)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    // STATUSラベル（右上）
                    VStack {
                        HStack {
                            Spacer()
                            Text(selected ? "SEL" : "RDY")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .foregroundStyle(selected ? Color.cyan.opacity(0.60) : Color.cyan.opacity(0.30))
                                .tracking(0.8)
                                .padding(.top, 7)
                                .padding(.trailing, 8)
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    // 選択時: コーナーHUDブラケット
                    if selected {
                        Canvas { ctx, size in
                            let m: CGFloat = 7
                            let l: CGFloat = 9
                            let corners: [(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat)] = [
                                (m, m, 1, 1), (size.width - m, m, -1, 1),
                                (m, size.height - m, 1, -1), (size.width - m, size.height - m, -1, -1)
                            ]
                            for c in corners {
                                var ph = Path()
                                ph.move(to: CGPoint(x: c.x, y: c.y))
                                ph.addLine(to: CGPoint(x: c.x + c.dx * l, y: c.y))
                                ctx.stroke(ph, with: .color(Color.cyan.opacity(0.58)), lineWidth: 1.0)
                                var pv = Path()
                                pv.move(to: CGPoint(x: c.x, y: c.y))
                                pv.addLine(to: CGPoint(x: c.x, y: c.y + c.dy * l))
                                ctx.stroke(pv, with: .color(Color.cyan.opacity(0.58)), lineWidth: 1.0)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .allowsHitTesting(false)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: selected)
        .accessibilityLabel(cardTitle(for: scene))
        .accessibilityHint("この場面を選択します")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func sceneAccent(_ scene: MeasurementScene) -> Color {
        switch scene {
        case .interview: return Color(red: 0.45, green: 0.80, blue: 0.95)
        case .sports:    return Color(red: 0.20, green: 0.85, blue: 0.60)
        case .social:    return Color(red: 0.90, green: 0.65, blue: 0.40)
        case .other:     return Color.white.opacity(0.55)
        default:         return Color.cyan
        }
    }

    private func isSelected(_ scene: MeasurementScene) -> Bool {
        guard let s = selectedScene else { return false }
        if scene == .other {
            return [MeasurementScene.study, .meeting, .speech, .daily, .other].contains(s)
        }
        return s == scene
    }

    // MARK: - テキストラベル

    private func cardTitle(for scene: MeasurementScene) -> String {
        switch scene {
        case .interview: return "面接・発表前"
        case .sports:    return "試合・大会前"
        case .social:    return "大切な約束前"
        case .other:     return "その他の場面"
        case .study:     return "試験・勉強"
        case .meeting:   return "重要な会議"
        case .speech:    return "スピーチ"
        case .daily:     return "日常の計測"
        }
    }

    private func cardSubtitle(for scene: MeasurementScene) -> String {
        switch scene {
        case .interview: return "緊張を和らげ集中へ"
        case .sports:    return "心拍を整えリズムへ"
        case .social:    return "気持ちを落ち着かせて"
        case .other:     return "目的に合わせて選択"
        default:         return ""
        }
    }

    // MARK: - CTA セクション

    private var ctaSection: some View {
        VStack(spacing: 0) {
            // パネルリップライン（HomeView panelTopRip と同じ意匠）
            Canvas { ctx, size in
                let w = size.width
                var main = Path()
                main.move(to: CGPoint(x: w * 0.05, y: size.height * 0.5))
                main.addLine(to: CGPoint(x: w * 0.95, y: size.height * 0.5))
                ctx.stroke(main, with: .color(Color.cyan.opacity(0.28)), lineWidth: 1.0)
                ctx.stroke(main, with: .color(Color.cyan.opacity(0.08)), lineWidth: 6)
                for xf in [0.05, 0.30, 0.70, 0.95] as [Double] {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: w*xf - 2, y: size.height*0.5 - 2, width: 4, height: 4)),
                        with: .color(Color.cyan.opacity(xf == 0.05 || xf == 0.95 ? 0.45 : 0.22))
                    )
                }
            }
            .frame(height: 8)
            Button {
                guard selectedScene != nil else { return }
                print("[UI][Guide] session_start_requested scene=\(selectedScene!.rawValue)")
                showFlowView = true
            } label: {
                let active = selectedScene != nil
                ZStack {
                    // 外縁グロー（選択時）
                    if active {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.cyan.opacity(0.35), lineWidth: 10)
                            .blur(radius: 12)
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.cyan.opacity(0.70), lineWidth: 2)
                            .blur(radius: 4)
                    }
                    // 背景フィル
                    RoundedRectangle(cornerRadius: 14)
                        .fill(active
                              ? LinearGradient(colors: [Color.cyan.opacity(0.88), Color.cyan.opacity(0.68), Color(red:0.00,green:0.18,blue:0.28)],
                                               startPoint: .top, endPoint: .bottom)
                              : LinearGradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.20), Color(red: 0.03, green: 0.06, blue: 0.14)],
                                               startPoint: .top, endPoint: .bottom))
                    // ガラス上端ハイライト
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(active ? 0.22 : 0.06), .clear],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)
                        ))
                    // エッジライン
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            active ? LinearGradient(colors: [Color.white.opacity(0.55), Color.cyan.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                                   : LinearGradient(colors: [Color.cyan.opacity(0.22), Color.cyan.opacity(0.10)], startPoint: .top, endPoint: .bottom),
                            lineWidth: active ? 1.2 : 0.8
                        )
                    HStack(spacing: 12) {
                        Image(systemName: active ? "play.fill" : "dot.radiowaves.right")
                            .font(.system(size: 16, weight: .bold))
                        Text(active ? "LAUNCH GUIDE" : "SCENE SELECT")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .tracking(2.0)
                    }
                    .foregroundStyle(active ? Color.black.opacity(0.90) : Color.white.opacity(0.28))
                    .shadow(color: active ? Color.cyan.opacity(0.25) : .clear, radius: 6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .shadow(color: active ? Color.cyan.opacity(0.45) : .clear, radius: 20, y: 4)
            }
            .disabled(selectedScene == nil)
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.22), value: selectedScene)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .accessibilityLabel(selectedScene != nil ? "この場面で整える" : "場面を選んでから開始できます")
            .accessibilityIdentifier("guide_start_button")
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - OtherSceneSelector

private struct OtherSceneSelectorView: View {
    @Binding var selectedScene: MeasurementScene?
    @Binding var isPresented: Bool

    private let subScenes: [(scene: MeasurementScene, label: String, sub: String)] = [
        (.study,   "試験・勉強",   "集中と記憶力"),
        (.meeting, "重要な会議",   "落ち着きと明晰さ"),
        (.speech,  "スピーチ",     "声と気持ちを整える"),
        (.daily,   "日常の計測",   "毎日の習慣として"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.02, green: 0.02, blue: 0.06).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(subScenes, id: \.scene) { item in
                            Button {
                                selectedScene = item.scene
                                print("[UI][Guide] other_scene_selected value=\(item.scene.rawValue)")
                                isPresented = false
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: item.scene.icon)
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.cyan.opacity(0.80))
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Color.white)
                                        Text(item.sub)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.45))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.25))
                                }
                                .padding(16)
                                .frame(minHeight: 60)
                                .background(Color(red: 0.05, green: 0.07, blue: 0.11))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.label)
                            .accessibilityHint(item.sub)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("その他の場面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isPresented = false }
                        .foregroundStyle(Color.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - AI Scene Suggestion View

private struct AISceneSuggestionView: View {
    let scene: MeasurementScene

    private var recommended: GuideExercise { scene.recommendedExercise }

    private var suggestionText: String {
        switch scene {
        case .interview, .speech:
            return "4-7-8は吐く時間を長く取りやすく、本番前の高まりを落ち着ける準備に向いています。"
        case .sports:
            return "BOXは一定のリズムを保ちやすく、集中を維持したまま整えたい場面に向いています。"
        case .social:
            return "BOXは一定のリズムで気持ちを安定させやすく、大切な場面の前後に向いています。"
        case .study, .meeting:
            return "2-1-4は息を長く吐きやすく、高まりをほぐして集中しやすい状態に向いています。"
        case .daily, .other:
            return "4-7-8はゆっくりとした呼吸のリズムで、日常的なリセットに向いています。"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // アイコン
            ZStack {
                Circle()
                    .fill(Color(hue: 0.62, saturation: 0.72, brightness: 0.25).opacity(0.60))
                Image(systemName: "brain")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color(hue: 0.62, saturation: 0.78, brightness: 0.92))
            }
            .frame(width: 34, height: 34)

            // テキスト
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text("AI SUGGEST")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hue: 0.62, saturation: 0.78, brightness: 0.80).opacity(0.72))
                        .tracking(1.8)
                    Text("→")
                        .font(.system(size: 8, weight: .light, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.22))
                    Text(recommended.title)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.80))
                        .tracking(0.5)
                }
                Text(suggestionText)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2.5)
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.01, green: 0.04, blue: 0.14).opacity(0.95))
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color(hue: 0.62, saturation: 0.80, brightness: 0.50).opacity(0.08), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(hue: 0.62, saturation: 0.72, brightness: 0.70).opacity(0.28), lineWidth: 0.8)
            }
        )
    }
}

#Preview {
    GuideView(selectedTab: .constant(1))
        .environmentObject(MindWaveViewModel())
        .environmentObject(GuideHistoryStore())
        .environmentObject(AppNavigationManager())
        .preferredColorScheme(.dark)
}

// MARK: - AI相談への入口

/// 「整える」から AI相談（AIChatView）を開くカード
private struct AIConsultEntryCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.cyan.opacity(0.85))
                VStack(alignment: .leading, spacing: 3) {
                    Text("AIに相談する")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("緊張していることを文章で相談できます")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cyan.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AIに相談する")
        .accessibilityHint("緊張や不安について文章で相談する画面を開きます")
        .accessibilityIdentifier("guide_ai_consult_button")
    }
}
