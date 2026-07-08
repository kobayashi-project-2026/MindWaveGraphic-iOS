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

            Text(topBarTitle)
                .font(.system(size: 13, weight: .light, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .tracking(1.0)

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
            VStack(spacing: 12) {
                // おすすめバナー
                if let scene = selectedScene {
                    HStack(spacing: 8) {
                        Image(systemName: scene.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.cyan.opacity(0.70))
                        Text("\(scene.displayName) には \(scene.recommendedExercise.title) がおすすめ")
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(.white.opacity(0.50))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.cyan.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.cyan.opacity(0.18), lineWidth: 0.7)
                            )
                    )
                }

                Text("ガイドを選んでください")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.white.opacity(0.45))

                ForEach(GuideExercise.allCases) { exercise in
                    ExerciseCard(
                        exercise:      exercise,
                        isSelected:    selectedExercise == exercise,
                        isRecommended: selectedScene?.recommendedExercise == exercise
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedExercise = exercise
                        }
                        MindWaveDebugLogger.log(.flow, "exercise selected exercise=\(exercise.rawValue)")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // MARK: - ▼ STEP 3: Session

    private var sessionContent: some View {
        VStack(spacing: 0) {
            Spacer()
            sessionVisual
            Spacer()

            if sessionIsFinished {
                VStack(spacing: 4) {
                    Text("セッション終了")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("再測定へ移行中…")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .padding(.bottom, 8)
            }

            Text(sessionTimeString)
                .font(.system(size: 52, weight: .thin, design: .rounded))
                .foregroundStyle(.white.opacity(sessionIsFinished ? 0.30 : 0.90))
                .monospacedDigit()
                .contentTransition(.numericText())

            if !sessionIsRunning && !sessionIsFinished {
                sessionDurationPicker.padding(.vertical, 14)
            }
            if !sessionIsFinished {
                sessionControlButton.padding(.horizontal, 24)
            }

            Spacer(minLength: 36)
        }
    }

    private var sessionVisual: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if selectedExercise == .ripple {
                    RippleGuideVisual()
                } else {
                    FlowGuideVisual()
                }
                if selectedExercise == .ripple && sessionIsRunning {
                    let phaseText = ((sessionDurationSeconds - sessionElapsed) % 8) < 4
                        ? "ゆっくり吸う" : "静かに吐く"
                    Text(phaseText)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.white.opacity(0.42))
                        .offset(y: 148)
                        .animation(.easeInOut(duration: 0.6), value: phaseText)
                }
            }

            // ミニ緊張状態ウィンドウ（右上に常時表示）
            miniStateWindow
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
        .frame(height: 260)
    }

    // MARK: - ミニ緊張状態ウィンドウ

    private var miniStateWindow: some View {
        let input  = viewModel.graphicInput
        let score  = min(max(input.score / 100.0, 0.0), 1.0)
        let hasData = viewModel.didFetchHeartRate || viewModel.didFetchHRV

        let stateName: String
        let stateColor: Color
        if !hasData {
            stateName = "—"
            stateColor = Color.white.opacity(0.38)
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

        return VStack(alignment: .trailing, spacing: 5) {
            // ヘッダー
            HStack(spacing: 4) {
                Text("STRESS")
                    .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .tracking(0.6)
                Circle()
                    .fill(stateColor)
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: stateColor.opacity(0.85), radius: 4)
            }

            // スコアバー
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 3.5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [stateColor.opacity(0.75), stateColor],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: g.size.width * (hasData ? score : 0), height: 3.5)
                        .animation(.easeInOut(duration: 1.2), value: score)
                }
            }
            .frame(height: 3.5)

            // 状態ラベル
            Text(stateName)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(stateColor)
                .tracking(0.4)
                .animation(.easeInOut(duration: 0.8), value: stateName)
        }
        .frame(width: 64)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.black.opacity(0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(stateColor.opacity(0.28), lineWidth: 0.8)
                )
        )
        .shadow(color: stateColor.opacity(0.18), radius: 8)
        .animation(.easeInOut(duration: 1.2), value: hasData)
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

    private var sessionControlLabel: some View {
        let icon = sessionIsRunning ? "stop.circle.fill" : "play.circle.fill"
        let txt  = sessionIsRunning ? "停止" : "開始"
        let fg   = sessionIsRunning ? Color.orange.opacity(0.9) : Color.cyan.opacity(0.9)
        let bg   = sessionIsRunning ? Color.orange.opacity(0.12) : Color.cyan.opacity(0.15)
        let bd   = sessionIsRunning ? Color.orange.opacity(0.28) : Color.cyan.opacity(0.28)
        return HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15))
            Text(txt).font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(bg)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(bd, lineWidth: 1))
        )
    }

    private var sessionControlButton: some View {
        Button { sessionIsRunning.toggle() } label: { sessionControlLabel }
            .buttonStyle(.plain)
            .accessibilityLabel(sessionIsRunning ? "停止する" : "開始する")
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

// MARK: - ExerciseCard（プレミアムガイドカード）

private struct ExerciseCard: View {
    let exercise:      GuideExercise
    let isSelected:    Bool
    let isRecommended: Bool
    let action:        () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // アイコン
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.cyan.opacity(0.18) : Color.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image(systemName: exercise.icon)
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(isSelected ? Color.cyan.opacity(0.95) : Color.white.opacity(0.55))
                }

                // テキスト
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(exercise.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                        if isRecommended {
                            Text("おすすめ")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.cyan.opacity(0.85))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.cyan.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Color.cyan.opacity(0.30), lineWidth: 0.5)
                                        )
                                )
                        }
                    }
                    Text(exercise.description)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.white.opacity(0.40))
                        .lineLimit(2)
                }

                Spacer()

                // 選択インジケーター
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.cyan.opacity(0.90) : .white.opacity(0.20))
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected
                              ? Color(red: 0.02, green: 0.18, blue: 0.30)
                              : Color.white.opacity(0.04))
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isSelected ? Color.cyan.opacity(0.45) : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 1.0 : 0.7
                        )
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.cyan.opacity(0.20), lineWidth: 2)
                            .blur(radius: 4)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(exercise.title)\(isRecommended ? "（おすすめ）" : "")")
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

// MARK: - Preview

#Preview("SceneSelection") {
    GuideFlowView(selectedTab: .constant(1))
        .environmentObject(MindWaveViewModel())
        .environmentObject(GuideHistoryStore())
}
