//
//  GuideFlowView.swift
//  MindWaveGraphic
//
//  ガイドフロー全体のコーディネーターView。
//  完全再設計: CTAを常時固定表示する3ゾーンレイアウト。
//    [TOP]    固定ヘッダー（閉じる / ステップタイトル）
//    [MIDDLE] スクロール可能なコンテンツ（場面カード / ガイドカード）
//    [BOTTOM] 固定CTA（ScrollViewの外 → 常に見える）
//
//  実データポリシー：変更なし（架空値使用禁止）
//

import SwiftUI
import Combine

struct GuideFlowView: View {
    @EnvironmentObject var viewModel:    MindWaveViewModel
    @EnvironmentObject var historyStore: GuideHistoryStore
    @Binding var selectedTab: Int
    @Environment(\.dismiss)              private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - custom init

    init(selectedTab: Binding<Int>, initialScene: MeasurementScene? = nil) {
        _selectedTab = selectedTab
        if let scene = initialScene {
            _step          = State(initialValue: .exerciseSelection)
            _selectedScene = State(initialValue: scene)
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["GUIDE_PHASE"] == "session" {
            _step                   = State(initialValue: .session)
            _selectedScene          = State(initialValue: .interview)
            _selectedExercise       = State(initialValue: .breathing478)
            _sessionElapsed         = State(initialValue: 60)
            _sessionDurationSeconds = State(initialValue: 60)
        }
        #endif
    }

    // MARK: - Flow State

    @State private var step:                RegulationFlowStep = .sceneSelection
    @State private var selectedScene:       MeasurementScene?  = nil
    @State private var selectedExercise:    GuideExercise?     = nil
    @State private var sessionDurationSeconds: Int             = 60
    @State private var beforeSnapshot:      GuideSnapshot?     = nil
    @State private var afterSnapshot:       GuideSnapshot?     = nil
    @State private var showAbandonAlert                        = false
    @State private var hrvUpdatedDuringSession                 = false
    @State private var showFeedbackView                        = false

    // Session
    @State private var sessionElapsed:    Int  = 0
    @State private var sessionIsRunning:  Bool = false
    @State private var sessionIsFinished: Bool = false

    // Remeasurement
    @State private var remeasurementElapsed:   Int   = 0
    @State private var remeasurementCompleted: Bool  = false
    @State private var remeasurementStartCount: Int  = 0
    @State private var remeasurementStartHRVDate: Date? = nil

    private let flowTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Body

    var body: some View {
        ZStack {
            flowBackground

            VStack(spacing: 0) {
                // ── 固定トップバー
                flowTopBar
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                // ── ステッププログレス（選択フローのみ）
                if step == .sceneSelection || step == .exerciseSelection {
                    stepProgressIndicator
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                }

                // セッション時: コックピットHUDセパレーター
                if step == .session {
                    Canvas { ctx, sz in
                        let w = sz.width
                        var line = Path()
                        line.move(to: CGPoint(x: w * 0.04, y: 1))
                        line.addLine(to: CGPoint(x: w * 0.96, y: 1))
                        ctx.stroke(line, with: .color(Color.cyan.opacity(0.22)), lineWidth: 0.8)
                        ctx.stroke(line, with: .color(Color.cyan.opacity(0.06)), lineWidth: 5)
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }

                // ── スクロール可能なコンテンツ（CTA は下部固定に移動）
                Group {
                    switch step {
                    case .sceneSelection:
                        sceneGridContent
                            .transition(stepTransition(insertion: .trailing))
                    case .exerciseSelection:
                        exerciseListContent
                            .transition(stepTransition(insertion: .trailing))
                    case .session:
                        sessionContent
                            .transition(.opacity)
                    case .remeasurement:
                        remeasurementContent
                            .transition(.opacity)
                    case .result:
                        resultContent
                            .transition(stepTransition(insertion: .trailing))
                    }
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28), value: step)
            }
        }
        // ── 固定ボトムCTA（safeAreaInset → ホームインジケーター上に確実配置）
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if step == .sceneSelection || step == .exerciseSelection {
                VStack(spacing: 0) {
                    ctaSummaryAndAction
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                }
                .background(
                    ZStack {
                        // コックピットパネル素材（HomeViewと統一）
                        Color(red: 0.03, green: 0.05, blue: 0.14).opacity(0.96)
                        // 深みメタリックグラデ
                        LinearGradient(
                            colors: [
                                Color(red: 0.06, green: 0.10, blue: 0.22).opacity(0.80),
                                Color(red: 0.01, green: 0.02, blue: 0.09).opacity(0.90)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        // 上端反射ハイライト（ガラス感）
                        VStack(spacing: 0) {
                            Color.white.opacity(0.035).frame(height: 1.5)
                            LinearGradient(
                                colors: [Color.white.opacity(0.04), .clear],
                                startPoint: .top, endPoint: .bottom
                            ).frame(height: 10)
                            Spacer()
                        }
                        // 上端アクセントライン（シアン）
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.50), Color.cyan.opacity(0.08)],
                                startPoint: .leading, endPoint: .trailing
                            ).frame(height: 1.0)
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.14), .clear],
                                startPoint: .top, endPoint: .bottom
                            ).frame(height: 8)
                            Spacer()
                        }
                        // 中央アンビエントグロー
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.06), .clear],
                            center: UnitPoint(x: 0.5, y: 0.0),
                            startRadius: 0,
                            endRadius: 120
                        )
                    }
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .onReceive(flowTimer) { _ in tickTimer() }
        #if DEBUG
        .onAppear {
            // シミュレーター撮影補助: GUIDE_AUTOSTART=1 で session を自動開始
            if ProcessInfo.processInfo.environment["GUIDE_AUTOSTART"] == "1",
               step == .session {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    sessionIsRunning = true
                }
            }
        }
        #endif
        .sheet(isPresented: $showFeedbackView) {
            if let before = beforeSnapshot,
               let scene  = selectedScene,
               let exercise = selectedExercise {
                FeedbackRecordView(
                    before: before, after: afterSnapshot,
                    scene: scene, exercise: exercise,
                    durationSeconds: sessionDurationSeconds,
                    onSave:   { memo in saveWithMemo(memo) },
                    onCancel: { showFeedbackView = false }
                )
            }
        }
        .alert("ガイドを中断しますか？", isPresented: $showAbandonAlert) {
            Button("中断する", role: .destructive) {
                MindWaveDebugLogger.log(.flow, "flow cancelled step=\(step)")
                dismiss()
            }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("現在のガイドを中断すると記録は保存されません。")
        }
    }

    // MARK: - Background

    private var sessionScoreIntensity: Double {
        min(max(viewModel.graphicInput.score / 100.0, 0), 1)
    }

    private var sessionStateColor: Color {
        let sc = sessionScoreIntensity
        let hasData = viewModel.didFetchHeartRate || viewModel.didFetchHRV
        if !hasData { return Color(hue: 0.62, saturation: 0.80, brightness: 0.88) }
        if sc < 0.25 { return Color(hue: 0.62, saturation: 0.80, brightness: 0.88) }
        if sc < 0.55 { return Color(hue: 0.48, saturation: 0.85, brightness: 0.90) }
        if sc < 0.78 { return Color(hue: 0.08, saturation: 0.92, brightness: 0.98) }
        return Color(hue: 0.01, saturation: 0.96, brightness: 1.0)
    }

    private var flowBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.05, blue: 0.18),
                    Color(red: 0.01, green: 0.03, blue: 0.12),
                    Color.black
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            // HUDグリッド（コックピット世界観）
            CyberGridShape(cellSize: 54)
                .stroke(Color.cyan.opacity(0.030), lineWidth: 0.4)
                .ignoresSafeArea()
            // サイドエッジ コックピット反射
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.cyan.opacity(0.08), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 18)
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.cyan.opacity(0.08)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 18)
            }
            .ignoresSafeArea()
            // 消失点グロー（呼吸集中モードの深度感）
            RadialGradient(
                colors: [
                    Color(hue: 0.62, saturation: 0.85, brightness: 0.80).opacity(0.13),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.28),
                startRadius: 0, endRadius: 280
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // セッション時のみ: Home同系統の状態星流（背景に薄く）
            if step == .session {
                SessionAmbientStarfield(score: sessionScoreIntensity, stateColor: sessionStateColor)
                    .ignoresSafeArea()
                // 下部コンソール感（機体内部からの反射）
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.06, blue: 0.18).opacity(0.60),
                            Color(red: 0.01, green: 0.03, blue: 0.10).opacity(0.30),
                            .clear
                        ],
                        startPoint: .bottom, endPoint: .top
                    )
                    .frame(height: 130)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Top Bar

    private var flowTopBar: some View {
        HStack {
            Button { showAbandonAlert = true } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 32, height: 32)
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("フローを中断する")

            Spacer()

            VStack(spacing: 3) {
                Text(topBarTitle)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(step == .session ? 0.88 : 0.65))
                    .tracking(1.8)
                if step == .session {
                    Canvas { ctx, size in
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: 0))
                        line.addLine(to: CGPoint(x: size.width, y: 0))
                        ctx.stroke(line, with: .color(Color.cyan.opacity(0.55)), lineWidth: 0.8)
                        ctx.stroke(line, with: .color(Color.cyan.opacity(0.14)), lineWidth: 4)
                    }
                    .frame(height: 4)
                }
            }

            Spacer()

            // バランス用
            Circle()
                .fill(.clear)
                .frame(width: 32, height: 32)
        }
    }

    private var topBarTitle: String {
        switch step {
        case .sceneSelection:    return "SCENE SELECT"
        case .exerciseSelection: return "GUIDE SELECT"
        case .session:           return "GUIDE SESSION"
        case .remeasurement:     return "RE-MEASURE"
        case .result:            return "RESULT"
        }
    }

    // MARK: - Step Progress Indicator

    private var stepProgressIndicator: some View {
        HStack(spacing: 8) {
            // ステップ1: シーン選択
            stepDot(active: step == .sceneSelection, done: step == .exerciseSelection || step == .session)
            stepLine(lit: step == .exerciseSelection || step == .session)
            // ステップ2: ガイド選択
            stepDot(active: step == .exerciseSelection, done: step == .session)
        }
    }

    private func stepDot(active: Bool, done: Bool) -> some View {
        ZStack {
            Circle()
                .fill(active ? Color.cyan : (done ? Color.cyan.opacity(0.40) : Color.white.opacity(0.12)))
                .frame(width: active ? 10 : 7, height: active ? 10 : 7)
            if active {
                Circle()
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 3)
                    .frame(width: 16, height: 16)
            }
        }
        .animation(.easeInOut(duration: 0.20), value: active)
    }

    private func stepLine(lit: Bool) -> some View {
        Rectangle()
            .fill(lit ? Color.cyan.opacity(0.55) : Color.white.opacity(0.12))
            .frame(height: 1)
            .animation(.easeInOut(duration: 0.20), value: lit)
    }

    // MARK: - Transition

    private func stepTransition(insertion: Edge) -> AnyTransition {
        reduceMotion ? .opacity :
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: insertion)),
            removal:   .opacity.combined(with: .move(edge: .leading))
        )
    }

    // MARK: - CTA + 選択サマリー統合コンテナ

    @ViewBuilder
    private var ctaSummaryAndAction: some View {
        VStack(spacing: 8) {
            selectionSummaryBanner
            fixedBottomCTA
        }
        .animation(.easeInOut(duration: 0.20), value: selectedScene)
        .animation(.easeInOut(duration: 0.20), value: selectedExercise)
    }

    @ViewBuilder
    private var selectionSummaryBanner: some View {
        let bg = RoundedRectangle(cornerRadius: 10)
        if step == .sceneSelection, let scene = selectedScene {
            summaryRow(
                icon: scene.icon,
                label: scene.displayName,
                trailing: "checkmark.circle.fill"
            )
            .background(bg.fill(Color.cyan.opacity(0.06))
                .overlay(bg.strokeBorder(Color.cyan.opacity(0.22), lineWidth: 0.8)))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else if step == .exerciseSelection, let exercise = selectedExercise {
            summaryRow(
                icon: exercise.icon,
                label: exercise.title,
                trailing: "checkmark.circle.fill"
            )
            .background(bg.fill(Color.cyan.opacity(0.06))
                .overlay(bg.strokeBorder(Color.cyan.opacity(0.22), lineWidth: 0.8)))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private func summaryRow(icon: String, label: String,
                            trailing: String? = nil,
                            trailingText: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.cyan.opacity(0.72))
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.80))
            Spacer()
            if let t = trailing {
                Image(systemName: t)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.cyan.opacity(0.70))
            } else if let tt = trailingText {
                Text(tt)
                    .font(.system(size: 10, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.55))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Fixed Bottom CTA（ボタン本体のみ）

    @ViewBuilder
    private var fixedBottomCTA: some View {
        switch step {
        case .sceneSelection:
            // シーン選択: 「次へ」のみ
            Button {
                withAnimation { step = .exerciseSelection }
            } label: {
                ctaLabel(
                    text: "次へ",
                    icon: "arrow.right",
                    enabled: selectedScene != nil
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedScene == nil)

        case .exerciseSelection:
            // ガイド選択: 「戻る」+ 「セッション開始」
            HStack(spacing: 12) {
                Button {
                    withAnimation { step = .sceneSelection }
                } label: {
                    backLabel
                }
                .buttonStyle(.plain)

                Button {
                    startSession()
                } label: {
                    ctaLabel(
                        text: "開始",
                        icon: "play.fill",
                        enabled: selectedExercise != nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedExercise == nil)
            }

        default:
            EmptyView()
        }
    }

    private func ctaLabel(text: String, icon: String, enabled: Bool) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .tracking(2.0)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(enabled ? .black : .white.opacity(0.25))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(enabled
                          ? LinearGradient(
                                colors: [Color.cyan.opacity(0.95), Color.cyan.opacity(0.82)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                          : LinearGradient(
                                colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)],
                                startPoint: .top, endPoint: .bottom
                            ))
                if enabled {
                    // 上端ガラス反射
                    RoundedRectangle(cornerRadius: 13)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.16), .clear],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)
                        ))
                    // シャープアウトライン
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
                    // 外縁グロー（2層）
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.cyan.opacity(0.70), lineWidth: 1.5)
                        .blur(radius: 3)
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.cyan.opacity(0.30), lineWidth: 6)
                        .blur(radius: 8)
                }
            }
        )
        .shadow(color: enabled ? Color.cyan.opacity(0.45) : .clear, radius: 14, y: 3)
        .animation(.easeInOut(duration: 0.18), value: enabled)
    }

    private var backLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
            Text("戻る")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(1.0)
        }
        .foregroundStyle(.white.opacity(0.50))
        .padding(.vertical, 17)
        .padding(.horizontal, 20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color(red: 0.05, green: 0.08, blue: 0.18).opacity(0.85))
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.04), .clear],
                        startPoint: .top, endPoint: .bottom
                    ))
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            }
        )
    }

    // MARK: - ▼ STEP 1: Scene Selection

    private var sceneGridContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Text("今の状況を教えてください")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(.white.opacity(0.50))
                    .padding(.top, 4)

                // 場面カードグリッド（2列）
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(MeasurementScene.allCases) { scene in
                        SceneCard(
                            scene:      scene,
                            isSelected: selectedScene == scene
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedScene = scene
                            }
                            MindWaveDebugLogger.log(.flow, "scene selected scene=\(scene.rawValue)")
                        }
                    }
                }

                // 選択済み確認インジケーター
                if let scene = selectedScene {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.cyan.opacity(0.80))
                        Text("\(scene.displayName) を選択中")
                            .font(.system(size: 12, weight: .light, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // MARK: - ▼ STEP 2: Exercise Selection

    private var exerciseListContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // BREATH SELECT ヘッダー
                HStack(spacing: 0) {
                    Rectangle().fill(Color.cyan.opacity(0.22)).frame(height: 0.6)
                    Text("BREATH SELECT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.52))
                        .tracking(3.0)
                        .fixedSize()
                        .padding(.horizontal, 10)
                    Rectangle().fill(Color.cyan.opacity(0.22)).frame(height: 0.6)
                }
                .padding(.top, 4)

                // 大型カード（縦3枚）
                VStack(spacing: 10) {
                    ForEach(GuideExercise.allCases) { exercise in
                        LargeExerciseCard(
                            exercise:   exercise,
                            isSelected: selectedExercise == exercise
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedExercise = exercise
                            }
                            MindWaveDebugLogger.log(.flow, "exercise selected exercise=\(exercise.rawValue)")
                        }
                    }
                }

                // 選択済みディテール
                if let exercise = selectedExercise {
                    ExerciseDetailPanel(exercise: exercise)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // MARK: - ▼ STEP 3: Session

    private var sessionContent: some View {
        VStack(spacing: 0) {
            // ── エクササイズ切り替えタブ（コックピット セグメント）
            HStack(spacing: 6) {
                ForEach(GuideExercise.allCases) { ex in
                    let isActive = selectedExercise == ex
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedExercise = ex }
                    } label: {
                        ZStack {
                            // 背景フィル
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isActive
                                      ? LinearGradient(colors: [Color.cyan.opacity(0.28), Color.cyan.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                                      : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            // ボーダー
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isActive ? Color.cyan.opacity(0.68) : Color.cyan.opacity(0.15), lineWidth: isActive ? 1.2 : 0.8)
                            // 選択時グロー（強化）
                            if isActive {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.cyan.opacity(0.45), lineWidth: 4)
                                    .blur(radius: 8)
                            }
                            // 上端ハイライト
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(isActive ? Color.cyan.opacity(1.0) : Color.white.opacity(0.06))
                                    .frame(height: isActive ? 1.5 : 1.0)
                                Spacer()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            // コンテンツ
                            VStack(spacing: 3) {
                                HStack(spacing: 4) {
                                    Image(systemName: ex.icon)
                                        .font(.system(size: 10, weight: .medium))
                                    Text(ex.title)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .tracking(0.3)
                                }
                                .foregroundStyle(isActive ? .white : .white.opacity(0.40))
                                Text(ex.subtitle)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(isActive ? Color.cyan.opacity(0.90) : Color.white.opacity(0.22))
                                    .tracking(0.5)
                            }
                            .padding(.vertical, 12)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(ex.title) \(ex.subtitle) に切り替え")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.18), value: selectedExercise)

            // ── ミニ状態ウィンドウ（タブ直下・右寄せ固定、呼吸円と重ならない）
            HStack(spacing: 0) {
                Spacer()
                miniStateWindow
                    .padding(.trailing, 10)
            }
            .padding(.top, 8)
            .padding(.bottom, 2)

            // ── 呼吸ビジュアル（大型・邪魔なし）
            sessionVisual

            // ── 残り時間表示
            VStack(spacing: 2) {
                if sessionIsFinished {
                    Text("SESSION COMPLETE")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.60))
                        .tracking(2.5)
                }
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(sessionTimeString)
                        .font(.system(size: 40, weight: .thin, design: .rounded))
                        .foregroundStyle(.white.opacity(sessionIsFinished ? 0.22 : 0.88))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if !sessionIsFinished {
                        Text("REMAINING")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.20))
                            .tracking(1.5)
                            .padding(.bottom, 5)
                    }
                }
            }
            .padding(.top, 2)

            if !sessionIsRunning && !sessionIsFinished {
                sessionDurationPicker.padding(.vertical, 12)
            }

            Spacer(minLength: 14)

            // ── BIG セッションボタン（コックピット緊急停止風）
            if !sessionIsFinished {
                bigSessionButton.padding(.horizontal, 20)
            }

            Spacer(minLength: 24)
        }
    }

    private var sessionVisual: some View {
        ZStack {
            // ── 呼吸円 背後グロー（深部感・奥行き演出）
            ZStack {
                // 広域アンビエント
                RadialGradient(
                    colors: [
                        Color(hue: 0.60, saturation: 0.85, brightness: 0.75).opacity(0.16),
                        Color(hue: 0.60, saturation: 0.70, brightness: 0.50).opacity(0.06),
                        .clear
                    ],
                    center: .center, startRadius: 0, endRadius: 210
                )
                // 中心コア輝点
                RadialGradient(
                    colors: [
                        Color.cyan.opacity(0.14),
                        .clear
                    ],
                    center: .center, startRadius: 0, endRadius: 90
                )
            }
            .frame(width: 400, height: 400)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)

            // 呼吸サークル（主役・邪魔なし）
            Group {
                if let exercise = selectedExercise {
                    BreathingCircleVisual(
                        exercise: exercise,
                        elapsedSeconds: sessionDurationSeconds - sessionElapsed,
                        isRunning: sessionIsRunning
                    )
                } else {
                    Circle()
                        .stroke(Color.cyan.opacity(0.12), lineWidth: 1.5)
                        .frame(width: 240, height: 240)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 300)
        // ── 左右コックピットサイドフレーム（リベット付き）
        .overlay(alignment: .leading) {
            Canvas { ctx, size in
                let sh = size.height
                ctx.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: sh)),
                    with: .color(Color.cyan.opacity(0.04))
                )
                var el = Path()
                el.move(to: CGPoint(x: size.width - 0.5, y: sh * 0.06))
                el.addLine(to: CGPoint(x: size.width - 0.5, y: sh * 0.94))
                ctx.stroke(el, with: .color(Color.cyan.opacity(0.32)), lineWidth: 0.8)
                for i in 0..<3 {
                    let y = sh * (0.22 + Double(i) * 0.28)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: size.width - 6, y: y - 2.2, width: 4.5, height: 4.5)),
                        with: .color(Color.cyan.opacity(0.40))
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: size.width - 5, y: y - 1.2, width: 2.4, height: 2.4)),
                        with: .color(Color.black.opacity(0.50))
                    )
                }
            }
            .frame(width: 20)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            Canvas { ctx, size in
                let sh = size.height
                ctx.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: sh)),
                    with: .color(Color.cyan.opacity(0.04))
                )
                var el = Path()
                el.move(to: CGPoint(x: 0.5, y: sh * 0.06))
                el.addLine(to: CGPoint(x: 0.5, y: sh * 0.94))
                ctx.stroke(el, with: .color(Color.cyan.opacity(0.32)), lineWidth: 0.8)
                for i in 0..<3 {
                    let y = sh * (0.22 + Double(i) * 0.28)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: 1.5, y: y - 2.2, width: 4.5, height: 4.5)),
                        with: .color(Color.cyan.opacity(0.40))
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: 2.5, y: y - 1.2, width: 2.4, height: 2.4)),
                        with: .color(Color.black.opacity(0.50))
                    )
                }
            }
            .frame(width: 20)
            .allowsHitTesting(false)
        }
    }

    // MARK: - ミニ緊張状態ウィンドウ（宇宙小窓スタイル）

    private var miniStateWindow: some View {
        let input   = viewModel.graphicInput
        let score   = min(max(input.score / 100.0, 0.0), 1.0)
        let hasData = viewModel.didFetchHeartRate || viewModel.didFetchHRV

        let stateName: String
        let stateColor: Color
        if !hasData {
            stateName = "—"
            stateColor = Color.white.opacity(0.62)
        } else if score < 0.25 {
            stateName = "CALM"
            stateColor = Color(hue: 0.62, saturation: 0.80, brightness: 0.88)
        } else if score < 0.55 {
            stateName = "FOCUS"
            stateColor = Color(hue: 0.48, saturation: 0.85, brightness: 0.90)
        } else if score < 0.78 {
            stateName = "ALERT"
            stateColor = Color(hue: 0.08, saturation: 0.92, brightness: 0.98)
        } else {
            stateName = "OVLD"
            stateColor = Color(hue: 0.01, saturation: 0.96, brightness: 1.0)
        }

        let hrText: String = {
            if let w = viewModel.latestWatchHeartRate { return String(format: "%.0f", w) }
            if viewModel.didFetchHeartRate            { return String(format: "%.0f", viewModel.currentHeartRate) }
            if viewModel.activeDataSource == .mock    { return "72" }
            return "—"
        }()

        // スコアに応じて星の速度を変化（高ストレス = 速い）
        let starSpeed = hasData ? (score * 40 + 14) : 10.0
        let capturedColor = stateColor

        return VStack(spacing: 0) {
            // ── 上半分: 流れ星ウィンドウ（右→左）
            ZStack(alignment: .topLeading) {
                TimelineView(.animation) { tl in
                    Canvas { ctx, sz in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let count = 9
                        let speeds: [Double] = [starSpeed,      starSpeed*0.58, starSpeed*1.32,
                                                starSpeed*0.82, starSpeed*1.12, starSpeed*0.72,
                                                starSpeed*1.45, starSpeed*0.90, starSpeed*1.20]
                        let yRatios: [Double] = [0.10, 0.35, 0.58, 0.82, 0.22, 0.50, 0.72, 0.40,
                                                 0.90]
                        let radii: [CGFloat]  = [1.8, 1.3, 1.6, 1.4, 2.1, 1.1, 1.7, 1.2, 1.5]
                        let alphas: [CGFloat] = [0.70, 0.52, 0.64, 0.46, 0.75, 0.40, 0.58, 0.48, 0.66]
                        let tails:  [Double]  = [11, 7, 13, 8, 16, 6, 10, 7, 12]
                        for i in 0..<count {
                            let xBase = t * speeds[i]
                            let x = sz.width - CGFloat(xBase.truncatingRemainder(dividingBy: Double(sz.width) + tails[i] + 4))
                            let y = sz.height * CGFloat(yRatios[i])
                            let r = radii[i]
                            let a = alphas[i]
                            // グロー層
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: x - r*1.9, y: y - r*1.9, width: r*3.8, height: r*3.8)),
                                with: .color(capturedColor.opacity(a * 0.22))
                            )
                            // 光点コア
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                with: .color(capturedColor.opacity(a))
                            )
                            // 尾（右方向）
                            var tail = Path()
                            tail.move(to: CGPoint(x: x + r, y: y))
                            tail.addLine(to: CGPoint(x: x + r + CGFloat(tails[i]), y: y))
                            ctx.stroke(tail, with: .color(capturedColor.opacity(a * 0.28)), lineWidth: r * 0.70)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ◉ LIVE インジケーター
                HStack(spacing: 3) {
                    Circle()
                        .fill(capturedColor.opacity(0.88))
                        .frame(width: 3.5, height: 3.5)
                        .shadow(color: capturedColor.opacity(0.75), radius: 3)
                    Text("LIVE")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(capturedColor.opacity(0.72))
                        .tracking(0.8)
                }
                .padding(.leading, 6)
                .padding(.top, 5)
            }
            .frame(height: 58)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.68), Color.black.opacity(0.32)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                Rectangle().fill(capturedColor.opacity(0.52)).frame(height: 0.9)
            }

            // ── 中仕切り
            Rectangle()
                .fill(stateColor.opacity(0.28))
                .frame(height: 0.6)

            // ── 下半分: STATE + PULSE コンパクト
            VStack(spacing: 5) {
                // STATE行
                HStack(spacing: 5) {
                    Text("STATE")
                        .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.30))
                        .tracking(0.5)
                    Circle()
                        .fill(stateColor)
                        .frame(width: 4.5, height: 4.5)
                        .shadow(color: stateColor.opacity(0.90), radius: 5)
                    Text(stateName)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(stateColor)
                        .shadow(color: stateColor.opacity(0.50), radius: 4)
                        .tracking(0.4)
                        .animation(.easeInOut(duration: 0.8), value: stateName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // PULSE行
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("PULSE")
                        .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.30))
                        .tracking(0.5)
                    Spacer()
                    Text(hrText)
                        .font(.system(size: 14, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(hasData || viewModel.activeDataSource == .mock ? 0.90 : 0.28))
                        .contentTransition(.numericText())
                    Text("bpm")
                        .font(.system(size: 6, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .frame(width: 92)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.01, green: 0.03, blue: 0.12).opacity(0.92))
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.04), .clear],
                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)
                    ))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(stateColor.opacity(0.48), lineWidth: 1.0)
            }
        )
        // コーナーブラケット（コックピット窓枠感）
        .overlay {
            Canvas { ctx, size in
                let len: CGFloat = 8
                let t: CGFloat = 1.2
                let corners: [(CGPoint, CGPoint, CGPoint)] = [
                    (CGPoint(x: 0, y: len),                     CGPoint(x: 0, y: 0),           CGPoint(x: len, y: 0)),
                    (CGPoint(x: size.width - len, y: 0),        CGPoint(x: size.width, y: 0),  CGPoint(x: size.width, y: len)),
                    (CGPoint(x: 0, y: size.height - len),       CGPoint(x: 0, y: size.height), CGPoint(x: len, y: size.height)),
                    (CGPoint(x: size.width - len, y: size.height), CGPoint(x: size.width, y: size.height), CGPoint(x: size.width, y: size.height - len))
                ]
                for (p0, p1, p2) in corners {
                    var path = Path()
                    path.move(to: p0)
                    path.addLine(to: p1)
                    path.addLine(to: p2)
                    ctx.stroke(path, with: .color(stateColor.opacity(0.80)), lineWidth: t)
                }
            }
            .allowsHitTesting(false)
        }
        .shadow(color: stateColor.opacity(0.32), radius: 14)
        .animation(.easeInOut(duration: 1.2), value: hasData)
        .accessibilityIdentifier("guide_session_mini_state_window")
    }

    private var sessionTimeString: String {
        String(format: "%d:%02d", sessionElapsed / 60, sessionElapsed % 60)
    }

    private let sessionDurationOptions: [(label: String, seconds: Int)] = [
        ("1分", 60), ("3分", 180), ("5分", 300)
    ]

    private var sessionDurationPicker: some View {
        HStack(spacing: 10) {
            ForEach(sessionDurationOptions, id: \.seconds) { opt in
                Button {
                    sessionDurationSeconds = opt.seconds
                    sessionElapsed = opt.seconds
                } label: {
                    Text(opt.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(sessionDurationSeconds == opt.seconds ? .black : .white.opacity(0.55))
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(sessionDurationSeconds == opt.seconds
                                      ? Color.cyan.opacity(0.85)
                                      : Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(opt.label)を選択")
            }
        }
    }

    private var bigSessionButton: some View {
        let isStop = sessionIsRunning
        return Button { sessionIsRunning.toggle() } label: {
            ZStack {
                // 外縁グロー（2層）
                // 最外グロー（3層）
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isStop ? Color.orange.opacity(0.28) : Color.cyan.opacity(0.28), lineWidth: 14)
                    .blur(radius: 18)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isStop ? Color.orange.opacity(0.60) : Color.cyan.opacity(0.60), lineWidth: 3)
                    .blur(radius: 6)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isStop ? Color.orange.opacity(0.90) : Color.cyan.opacity(0.88), lineWidth: 1.2)
                    .blur(radius: 1)
                // 背景フィル
                RoundedRectangle(cornerRadius: 20)
                    .fill(isStop
                          ? LinearGradient(colors: [Color.orange.opacity(0.20), Color.orange.opacity(0.10), Color(red:0.12,green:0.02,blue:0.00)], startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color.cyan.opacity(0.18), Color.cyan.opacity(0.08), Color(red:0.00,green:0.06,blue:0.14)], startPoint: .top, endPoint: .bottom))
                // 上端ガラスハイライト
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.03), .clear],
                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)
                    )
                    .frame(height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    Spacer()
                }
                // ボーダー
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                isStop ? Color.orange.opacity(0.80) : Color.cyan.opacity(0.80),
                                isStop ? Color.orange.opacity(0.40) : Color.cyan.opacity(0.40)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1.2
                    )
                // ラベル
                HStack(spacing: 12) {
                    Image(systemName: isStop ? "stop.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                    Text(isStop ? "STOP" : "START")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .tracking(4.0)
                }
                .foregroundStyle(isStop ? Color.orange.opacity(0.97) : Color.cyan.opacity(0.97))
                .shadow(color: isStop ? Color.orange.opacity(0.45) : Color.cyan.opacity(0.45), radius: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
        }
        .buttonStyle(.plain)
        .shadow(color: isStop ? Color.orange.opacity(0.50) : Color.cyan.opacity(0.38), radius: 24, y: 4)
        .accessibilityLabel(isStop ? "停止する" : "開始する")
        .animation(.easeInOut(duration: 0.22), value: isStop)
    }

    // MARK: - ▼ STEP 4: Remeasurement

    private var remeasurementContent: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "applewatch.watchface")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.cyan.opacity(0.55))
            Text("再測定中")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text("Apple Watchから新しい心拍を受信しています")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.white.opacity(0.48))
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                let newSamples    = viewModel.watchMessageCount - remeasurementStartCount
                let targetSamples = GuideFlowConstants.minWatchSamplesForRemeasurement
                HStack(spacing: 6) {
                    Text("受信件数")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.38))
                    Text("\(newSamples) / \(targetSamples)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(newSamples >= targetSamples
                                         ? Color.cyan.opacity(0.9) : .white.opacity(0.65))
                }
                if let hr = viewModel.latestWatchHeartRate {
                    HStack(spacing: 6) {
                        Text("最新心拍").font(.system(size: 12)).foregroundStyle(.white.opacity(0.38))
                        Text(String(format: "%.0f bpm", hr))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                Text("最大 \(GuideFlowConstants.maxRemeasurementSeconds - remeasurementElapsed) 秒で自動完了")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.28))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

            Button { completeRemeasurement() } label: {
                Text("今の値で結果を見る")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - ▼ STEP 5: Result

    private var resultContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Text("計測結果")
                    .font(.system(size: 20, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(3)
                    .padding(.top, 10)

                if let before = beforeSnapshot, let after = afterSnapshot {
                    ResultComparisonCard(before: before, after: after)
                }

                Text("これは医療診断ではありません。\n数値は計測環境により変動します。")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.30))
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button { showFeedbackView = true } label: {
                        HStack(spacing: 8) {
                            Text("レポートを確認して保存")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 14).fill(Color.cyan.opacity(0.88))
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                            }
                        )
                        .shadow(color: Color.cyan.opacity(0.30), radius: 10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        MindWaveDebugLogger.log(.flow, "result dismissed without saving")
                        dismiss()
                        Task { @MainActor in selectedTab = 0 }
                    } label: {
                        Text("保存せずHomeへ戻る")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.50))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)

                    Button { resetForNewSession() } label: {
                        Text("もう一度実施する")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.cyan.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Timer

    private func tickTimer() {
        switch step {
        case .session:
            guard sessionIsRunning else { return }
            if sessionElapsed > 0 {
                sessionElapsed -= 1
                if sessionElapsed == 0 {
                    sessionIsRunning  = false
                    sessionIsFinished = true
                    MindWaveDebugLogger.log(.flow, "session completed")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        guard self.sessionIsFinished else { return }
                        self.startRemeasurement()
                    }
                }
            }
        case .remeasurement:
            remeasurementElapsed += 1
            let newSamples = viewModel.watchMessageCount - remeasurementStartCount
            if newSamples >= GuideFlowConstants.minWatchSamplesForRemeasurement
               || remeasurementElapsed >= GuideFlowConstants.maxRemeasurementSeconds {
                completeRemeasurement()
            }
        default: break
        }
    }

    // MARK: - Session helpers

    private func startSession() {
        beforeSnapshot     = captureBeforeSnapshot()
        sessionElapsed     = sessionDurationSeconds
        sessionIsRunning   = false
        sessionIsFinished  = false
        step = .session
        MindWaveDebugLogger.log(.flow, "session started duration=\(sessionDurationSeconds)")
        print("[Regulation] session started")
    }

    private func captureBeforeSnapshot() -> GuideSnapshot {
        GuideSnapshot(
            timestamp:           Date(),
            score:               viewModel.graphicInput.score,
            confidence:          viewModel.graphicInput.confidence,
            state:               viewModel.graphicInput.state,
            heartRate:           viewModel.latestWatchHeartRate ?? (viewModel.didFetchHeartRate ? viewModel.currentHeartRate : nil),
            hrv:                 viewModel.didFetchHRV ? viewModel.currentHRV : nil,
            isMockData:          viewModel.isMockMode,
            heartRateSampleDate: viewModel.latestHeartRateSampleDate,
            hrvSampleDate:       viewModel.latestHRVSampleDate
        )
    }

    private func startRemeasurement() {
        remeasurementStartCount   = viewModel.watchMessageCount
        remeasurementStartHRVDate = viewModel.latestHRVSampleDate
        remeasurementElapsed      = 0
        remeasurementCompleted    = false
        step = .remeasurement
    }

    private func completeRemeasurement() {
        guard !remeasurementCompleted else { return }
        remeasurementCompleted = true
        let newHRVDate = viewModel.latestHRVSampleDate
        hrvUpdatedDuringSession = (newHRVDate != remeasurementStartHRVDate && newHRVDate != nil)
        afterSnapshot = GuideSnapshot(
            timestamp:           Date(),
            score:               viewModel.graphicInput.score,
            confidence:          viewModel.graphicInput.confidence,
            state:               viewModel.graphicInput.state,
            heartRate:           viewModel.latestWatchHeartRate ?? (viewModel.didFetchHeartRate ? viewModel.currentHeartRate : nil),
            hrv:                 viewModel.didFetchHRV ? viewModel.currentHRV : nil,
            isMockData:          viewModel.isMockMode,
            heartRateSampleDate: viewModel.latestHeartRateSampleDate,
            hrvSampleDate:       viewModel.latestHRVSampleDate
        )
        step = .result
    }

    private func saveWithMemo(_ memo: String) {
        guard let before = beforeSnapshot, let scene = selectedScene,
              let exercise = selectedExercise else { return }
        let record = GuideSessionRecord(
            id: UUID(), startedAt: before.timestamp,
            scene: scene, exercise: exercise,
            durationSeconds: sessionDurationSeconds,
            before: before, after: afterSnapshot,
            hrvUpdated: hrvUpdatedDuringSession,
            emotionMemo: memo.isEmpty ? nil : memo
        )
        historyStore.add(record)
        showFeedbackView = false
        dismiss()
        Task { @MainActor in selectedTab = 2 }
    }

    private func resetForNewSession() {
        sessionIsFinished  = false
        sessionIsRunning   = false
        sessionElapsed     = sessionDurationSeconds
        remeasurementElapsed = 0
        remeasurementCompleted = false
        afterSnapshot = nil
        beforeSnapshot = captureBeforeSnapshot()
        step = .session
    }
}

// MARK: - SceneCard（プレミアム場面カード）

private struct SceneCard: View {
    let scene:      MeasurementScene
    let isSelected: Bool
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // カード背景
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isSelected
                        ? Color(red: 0.02, green: 0.20, blue: 0.32)
                        : Color(red: 0.05, green: 0.07, blue: 0.18)
                    )

                // 上端カラーライン（選択時: シアン、非選択時: 薄白）
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            isSelected ? Color.cyan.opacity(0.80) : Color.white.opacity(0.10),
                            .clear
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 1.5)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // ボーダー
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? Color.cyan.opacity(0.55) : Color.white.opacity(0.10),
                        lineWidth: isSelected ? 1.0 : 0.7
                    )

                // 選択時グロー
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.cyan.opacity(0.30), lineWidth: 2)
                        .blur(radius: 4)
                }

                // コンテンツ
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.cyan.opacity(0.18) : Color.white.opacity(0.06))
                            .frame(width: 44, height: 44)
                        Image(systemName: scene.icon)
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(isSelected ? Color.cyan.opacity(0.95) : Color.white.opacity(0.55))
                    }
                    Text(scene.displayName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.60))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scene.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - ExerciseDetailPanel（選択済み呼吸法の詳細）

private struct ExerciseDetailPanel: View {
    let exercise: GuideExercise

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: exercise.icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.cyan.opacity(0.72))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(exercise.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text(exercise.timingLabel)
                        .font(.system(size: 10, weight: .light, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.60))
                        .tracking(0.8)
                }
                Text(exercise.description)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.40))
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cyan.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.cyan.opacity(0.22), lineWidth: 0.7)
                )
        )
    }
}

// MARK: - LargeExerciseCard（大型呼吸法選択カード）

private struct LargeExerciseCard: View {
    let exercise:   GuideExercise
    let isSelected: Bool
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // アイコン円
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.cyan.opacity(0.20) : Color.white.opacity(0.06))
                        .frame(width: 54, height: 54)
                    Circle()
                        .stroke(isSelected ? Color.cyan.opacity(0.40) : Color.clear, lineWidth: 1.0)
                        .frame(width: 54, height: 54)
                    Image(systemName: exercise.icon)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(isSelected ? Color.cyan.opacity(0.95) : Color.white.opacity(0.50))
                }

                // テキスト
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(exercise.title)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                            .tracking(0.5)
                        Text(exercise.subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isSelected ? Color.cyan.opacity(0.75) : Color.white.opacity(0.28))
                    }
                    Text(exercise.timingLabel)
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.cyan.opacity(0.60) : Color.white.opacity(0.24))
                        .tracking(1.5)
                    Text(exercise.description)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.white.opacity(isSelected ? 0.55 : 0.28))
                        .lineLimit(1)
                }

                Spacer()

                // 選択インジケーター
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.cyan.opacity(0.90) : .white.opacity(0.15))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected
                              ? Color(red: 0.02, green: 0.18, blue: 0.30)
                              : Color.white.opacity(0.04))
                    // 上端アクセントライン
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                isSelected ? Color.cyan.opacity(0.75) : Color.white.opacity(0.08),
                                .clear
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(height: 1.2)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    // ボーダー
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isSelected ? Color.cyan.opacity(0.52) : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 1.1 : 0.7
                        )
                    // 選択時グロー
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.cyan.opacity(0.30), lineWidth: 3)
                            .blur(radius: 6)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(exercise.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - ResultComparisonCard（変更なし）

private struct ResultComparisonCard: View {
    let before: GuideSnapshot
    let after:  GuideSnapshot

    private var scoreDelta: Double { after.score - before.score }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                snapshotColumn("ガイド前", snap: before)
                Divider().background(.white.opacity(0.12)).frame(width: 1)
                snapshotColumn("ガイド後", snap: after)
            }
            Divider().background(.white.opacity(0.08))
            HStack(spacing: 6) {
                Text("スコア変化")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.40))
                Text(String(format: "%+.1f", scoreDelta))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        scoreDelta < 0 ? Color.cyan.opacity(0.9)
                        : scoreDelta > 0 ? Color.orange.opacity(0.8)
                        : .white.opacity(0.6)
                    )
            }
            if before.isMockData || after.isMockData {
                Text("⚠ Mockモード中のデータを含みます")
                    .font(.system(size: 10)).foregroundStyle(Color.orange.opacity(0.65))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.30), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func snapshotColumn(_ label: String, snap: GuideSnapshot) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.38)).tracking(0.5)
            Text(String(format: "%.0f", snap.score))
                .font(.system(size: 36, weight: .thin, design: .rounded))
                .foregroundStyle(MindWaveTheme.stressColor(score: snap.score))
            Text(snap.state.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MindWaveTheme.stressColor(score: snap.score).opacity(0.8))
            if let hr = snap.heartRate {
                Text(String(format: "%.0f bpm", hr))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.42))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}

// MARK: - SessionAmbientStarfield

private struct SessionAmbientStarfield: View {
    let score: Double
    let stateColor: Color

    // 遠景層: 小さく遅く薄い (indices 0-15)
    // 近景層: 大きく速く明るい (indices 16-27)
    private var farSpeed:  Double  { score * 14.0 + 4.0 }
    private var nearSpeed: Double  { score * 28.0 + 10.0 }
    private var farBase:   CGFloat { 0.14 + CGFloat(score) * 0.08 }
    private var nearBase:  CGFloat { 0.22 + CGFloat(score) * 0.10 }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, sz in
                let t = tl.date.timeIntervalSinceReferenceDate

                // ── 遠景星 (16個: 小・遅・薄)
                let farSpeeds:  [Double]  = [1.00, 0.60, 1.18, 0.78, 1.32, 0.52, 1.08, 0.88,
                                             1.24, 0.70, 0.92, 1.40, 0.64, 1.16, 0.80, 1.28]
                let farYRat:    [Double]  = [0.04, 0.12, 0.21, 0.30, 0.39, 0.48, 0.55, 0.63,
                                             0.71, 0.79, 0.87, 0.94, 0.09, 0.18, 0.43, 0.66]
                let farRadii:   [CGFloat] = [0.55, 0.40, 0.65, 0.45, 0.70, 0.38, 0.58, 0.48,
                                             0.62, 0.42, 0.52, 0.68, 0.44, 0.60, 0.50, 0.64]
                let farAlphas:  [CGFloat] = [0.90, 0.65, 0.80, 0.58, 0.95, 0.50, 0.78, 0.62,
                                             0.85, 0.55, 0.72, 0.88, 0.48, 0.76, 0.60, 0.82]
                let farTails:   [Double]  = [5, 3, 7, 4, 8, 3, 6, 4, 7, 3, 5, 8, 3, 6, 4, 7]

                // ── 近景星 (12個: 大・速・明)
                let nearSpeeds: [Double]  = [1.00, 0.72, 1.38, 0.84, 1.22, 0.64,
                                             1.48, 0.90, 1.16, 0.78, 1.34, 1.06]
                let nearYRat:   [Double]  = [0.07, 0.24, 0.44, 0.61, 0.76, 0.92,
                                             0.15, 0.34, 0.52, 0.68, 0.83, 0.97]
                let nearRadii:  [CGFloat] = [1.4, 1.0, 1.6, 1.2, 1.8, 1.1,
                                             1.5, 0.9, 1.3, 1.7, 1.0, 1.4]
                let nearAlphas: [CGFloat] = [1.00, 0.75, 0.90, 0.68, 0.95, 0.60,
                                             0.85, 0.72, 0.80, 0.92, 0.65, 0.88]
                let nearTails:  [Double]  = [14, 9, 18, 11, 22, 8, 16, 10, 13, 20, 9, 15]

                let cx = sz.width * 0.50
                let cy = sz.height * 0.44
                let maskInner: CGFloat = 112
                let maskOuter: CGFloat = 230

                func maskFade(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
                    let dist = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
                    if dist < maskInner { return 0 }
                    if dist < maskOuter { return (dist - maskInner) / (maskOuter - maskInner) }
                    return 1.0
                }

                // 遠景描画
                for i in 0..<16 {
                    let spd = farSpeed * farSpeeds[i]
                    let tLen = CGFloat(farTails[i])
                    let x = sz.width - CGFloat((t * spd).truncatingRemainder(dividingBy: Double(sz.width) + Double(tLen) + 2))
                    let y = sz.height * CGFloat(farYRat[i])
                    let r = farRadii[i]
                    let a = farBase * farAlphas[i] * maskFade(x, y)
                    guard a > 0.003 else { continue }
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(stateColor.opacity(Double(a)))
                    )
                    if tLen > 2 {
                        var tail = Path()
                        tail.move(to: CGPoint(x: x + r, y: y))
                        tail.addLine(to: CGPoint(x: x + r + tLen, y: y))
                        ctx.stroke(tail, with: .color(stateColor.opacity(Double(a * 0.22))), lineWidth: r * 0.50)
                    }
                }

                // 近景描画
                for i in 0..<12 {
                    let spd = nearSpeed * nearSpeeds[i]
                    let tLen = CGFloat(nearTails[i])
                    let x = sz.width - CGFloat((t * spd).truncatingRemainder(dividingBy: Double(sz.width) + Double(tLen) + 4))
                    let y = sz.height * CGFloat(nearYRat[i])
                    let r = nearRadii[i]
                    let a = nearBase * nearAlphas[i] * maskFade(x, y)
                    guard a > 0.004 else { continue }
                    // グロー
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r * 2.4, y: y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                        with: .color(stateColor.opacity(Double(a * 0.22)))
                    )
                    // コア
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(stateColor.opacity(Double(a)))
                    )
                    // 尾
                    if tLen > 6 {
                        var tail = Path()
                        tail.move(to: CGPoint(x: x + r, y: y))
                        tail.addLine(to: CGPoint(x: x + r + tLen, y: y))
                        ctx.stroke(tail, with: .color(stateColor.opacity(Double(a * 0.32))), lineWidth: r * 0.55)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview("SceneSelection") {
    GuideFlowView(selectedTab: .constant(1))
        .environmentObject(MindWaveViewModel())
        .environmentObject(GuideHistoryStore())
}
