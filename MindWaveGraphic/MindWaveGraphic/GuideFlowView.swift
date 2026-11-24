//
//  GuideFlowView.swift
//  MindWaveGraphic
//
//  ガイドフロー全体のコーディネーターView。
//  - 第1階層: 「呼吸法」「スライドパズル」「手のツボ押し」の3択
//  - 第2階層: 「呼吸法」選択時のみ「どの呼吸法にしますか？（4-7-8 / BOX / 2-1-4）」を展開
//

import SwiftUI
import Combine

// MARK: - 改善カテゴリ（第1階層）

private enum ImprovementCategory: String, CaseIterable, Identifiable {
    case breathing
    case puzzle
    case acupressure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathing:   return "呼吸法"
        case .puzzle:      return "スライドパズル"
        case .acupressure: return "手のツボ押し"
        }
    }

    var subtitle: String {
        switch self {
        case .breathing:   return "4-7-8 / BOX / 2-1-4"
        case .puzzle:      return "1から順に並べて心を整える"
        case .acupressure: return "手のひらのツボで緊張をほぐす"
        }
    }

    var icon: String {
        switch self {
        case .breathing:   return "wind"
        case .puzzle:      return "square.grid.3x3.fill"
        case .acupressure: return "hand.raised.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .breathing:   return .cyan
        case .puzzle:      return Color(red: 0.45, green: 0.78, blue: 0.92)
        case .acupressure: return Color(red: 0.95, green: 0.62, blue: 0.78)
        }
    }
}

// MARK: - GuideFlowView

struct GuideFlowView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var historyStore: GuideHistoryStore
    @EnvironmentObject var flowState: AppFlowState
    @Binding var selectedTab: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
#if DEBUG && targetEnvironment(simulator)
    @AppStorage("sim_demo_override_enabled") private var simDemoOverrideEnabled = false
    @AppStorage("sim_demo_bpm")             private var simDemoBPM:             Double = 72.0
    @AppStorage("sim_demo_score")           private var simDemoScore:           Double = 12.0
#endif
    
    // MARK: - Custom Init
    
    private let resume: PendingImprovement?
    
    init(selectedTab: Binding<Int>, initialScene: MeasurementScene? = nil, resume: PendingImprovement? = nil) {
        _selectedTab = selectedTab
        self.resume = resume
        _step = State(initialValue: .exerciseSelection)
        _selectedScene = State(initialValue: initialScene ?? .other)
        if let r = resume {
            _step = State(initialValue: .session)
            _selectedScene = State(initialValue: r.scene)
            _selectedExercise = State(initialValue: r.exercise)
            _sessionDurationSeconds = State(initialValue: r.durationSeconds)
        }
#if DEBUG
        if ProcessInfo.processInfo.environment["GUIDE_PHASE"] == "session" {
            _step = State(initialValue: .session)
            _selectedScene = State(initialValue: .interview)
            _selectedExercise = State(initialValue: .breathing478)
            _sessionElapsed = State(initialValue: 60)
            _sessionDurationSeconds = State(initialValue: 60)
        }
#endif
    }
    
    // MARK: - Flow State
    
    @State private var step: RegulationFlowStep = .exerciseSelection
    @State private var selectedScene: MeasurementScene? = .other
    @State private var selectedCategory: ImprovementCategory = .breathing
    @State private var selectedExercise: GuideExercise? = nil
    @State private var activeInteractiveTool: ImprovementCategory? = nil
    
    private var needsRetryOptions: Bool {
        if let afterReport = selfReportAfter {
            let index = SelfReportLevel.allCases.firstIndex(of: afterReport) ?? 0
            return index >= 2
        }
        if let before = beforeSnapshot, let after = afterSnapshot {
            return after.score >= before.score || after.state == .overTense
        }
        return false
    }
    
    @State private var sessionDurationSeconds: Int = 60
    @State private var beforeSnapshot: GuideSnapshot? = nil
    @State private var afterSnapshot: GuideSnapshot? = nil
    @State private var showAbandonAlert = false
    @State private var hrvUpdatedDuringSession = false
    @State private var showFeedbackView = false
    @State private var showMokorinCompanion = false
    @State private var showMokorinTalk = false
    @State private var subjectiveAfter: Int? = nil
    @State private var reflectionAnswer: ReflectionAnswer? = nil
    @State private var showHomeConfirm = false
    @State private var showDurationPicker = false
    @State private var customMinutes = 2
    @State private var didApplyResume = false
    @State private var adoptedResume: PendingImprovement? = nil
    
    // Session
    @State private var sessionElapsed: Int = 0
    @State private var sessionIsRunning: Bool = false
    @State private var sessionIsFinished: Bool = false
    @State private var aiFeedbackResult: LocalAIFeedbackResult? = nil
    @State private var latestAIInsight: MindWaveAIInsight? = nil
    @State private var insightProviderVersion: String = "local-v1"
    @State private var remoteInsightTask: Task<Void, Never>? = nil
    @State private var selfReportBefore: SelfReportLevel? = nil
    @State private var selfReportAfter: SelfReportLevel? = nil
    
    // Remeasurement
    @State private var remeasurementElapsed: Int = 0
    @State private var remeasurementCompleted: Bool = false
    @State private var remeasurementStartCount: Int = 0
    @State private var remeasurementStartHRVDate: Date? = nil
    
    private let flowTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var canStartSelection: Bool {
        switch selectedCategory {
        case .breathing:
            return selectedExercise != nil
        case .puzzle, .acupressure:
            return true
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            flowBackground
            
            VStack(spacing: 0) {
                flowTopBar
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                
                if step == .sceneSelection || step == .exerciseSelection {
                    stepProgressIndicator
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                }
                
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
                
                Group {
                    switch step {
                    case .exerciseSelection:
                        exerciseListContent
                            .transition(stepTransition(insertion: .trailing))
                    case .session:
                        ViewThatFits(in: .vertical) {
                            sessionContent
                            ScrollView(showsIndicators: false) { sessionContent }
                        }
                        .transition(.opacity)
                    case .remeasurement:
                        remeasurementContent
                            .transition(.opacity)
                    case .result:
                        resultContent
                            .transition(stepTransition(insertion: .trailing))
                    default:
                        exerciseListContent
                    }
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28), value: step)
            }
        }
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
                        Color(red: 0.03, green: 0.05, blue: 0.14).opacity(0.96)
                        LinearGradient(
                            colors: [
                                Color(red: 0.06, green: 0.10, blue: 0.22).opacity(0.80),
                                Color(red: 0.01, green: 0.02, blue: 0.09).opacity(0.90)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        VStack(spacing: 0) {
                            Color.white.opacity(0.035).frame(height: 1.5)
                            LinearGradient(
                                colors: [Color.white.opacity(0.04), .clear],
                                startPoint: .top, endPoint: .bottom
                            ).frame(height: 10)
                            Spacer()
                        }
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
      
                .fullScreenCover(item: $activeInteractiveTool) { tool in
                    InteractiveToolContainerView(
                        tool: tool,
                        onBack: { activeInteractiveTool = nil },
                        onClose: {
                            activeInteractiveTool = nil
                            dismiss()
                            selectedTab = 0
                        }
                    )
                }
#if DEBUG
                .onAppear {
                    if ProcessInfo.processInfo.environment["GUIDE_AUTOSTART"] == "1",
                       step == .session {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            sessionIsRunning = true
                        }
                    }
                    if ProcessInfo.processInfo.environment["GUIDE_PHASE"] == "result" {
                        if ProcessInfo.processInfo.environment["MW_DEMO_S0"] == "1" { selfReportBefore = .significantTension }
                        let hr = ProcessInfo.processInfo.environment["DEMO_HEART_RATE"]
                            .flatMap(Double.init) ?? 115.0
                        let beforeScore: Double = hr >= 130 ? 85 : hr >= 115 ? 72 : hr >= 100 ? 55 : hr >= 80 ? 38 : 18
                        let beforeState: MindState = beforeScore > 69 ? .overTense : beforeScore > 32 ? .optimalTension : .underAroused
                        let afterScore = max(beforeScore - 20, 8)
                        let afterState: MindState = afterScore > 69 ? .overTense : afterScore > 32 ? .optimalTension : .underAroused
                        beforeSnapshot = GuideSnapshot(
                            timestamp: Date(), score: beforeScore,
                            confidence: 0.80, state: beforeState,
                            heartRate: hr, hrv: nil, isMockData: true,
                            heartRateSampleDate: Date(), hrvSampleDate: nil
                        )
                        afterSnapshot = GuideSnapshot(
                            timestamp: Date(), score: afterScore,
                            confidence: 0.80, state: afterState,
                            heartRate: max(hr - 14, 60), hrv: nil, isMockData: true,
                            heartRateSampleDate: Date(), hrvSampleDate: nil
                        )
                        selectedScene = .interview
                        selectedExercise = .breathing478
                        aiFeedbackResult = LocalAIFeedbackGenerator.generate(
                            heartRate: hr, exercise: .breathing478, scene: .interview
                        )
                        step = .result
                        if ProcessInfo.processInfo.environment["MW_COMPANION"] == "result" {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showMokorinCompanion = true }
                        }
                    }
                }
#endif
                .sheet(isPresented: $showMokorinCompanion) {
                    if let model = makeMokorinCompanion() {
                        MokorinCompanionView(title: "もこりんと結果を見る", model: model) {
                            showMokorinCompanion = false
                        }
                    }
                }
                .sheet(isPresented: $showFeedbackView) {
                    if let before = beforeSnapshot,
                       let scene = selectedScene,
                       let exercise = selectedExercise {
                        FeedbackRecordView(
                            before: before, after: afterSnapshot,
                            scene: scene, exercise: exercise,
                            durationSeconds: sessionDurationSeconds,
                            onSave: { memo in saveWithMemo(memo) },
                            onCancel: { showFeedbackView = false }
                        )
                    }
                }
                .alert("ガイドを中断しますか？", isPresented: $showAbandonAlert) {
                    Button("中断する", role: .destructive) {
                        MindWaveDebugLogger.log(.flow, "flow cancelled step=\(step)")
                        step = .exerciseSelection
                        selectedExercise = nil
                        dismiss()
                        Task { @MainActor in selectedTab = 0 }
                    }
                    Button("続ける", role: .cancel) {}
                } message: {
                    Text("現在のガイドを中断すると記録は保存されません。")
                }
        }
        
        // MARK: - Background
        
        private var guideHeartRateNumeric: Double {
#if DEBUG && targetEnvironment(simulator)
            if simDemoOverrideEnabled { return simDemoBPM }
            if let str = ProcessInfo.processInfo.environment["DEMO_HEART_RATE"],
               let val = Double(str) { return val }
#endif
            if let w = viewModel.latestWatchHeartRate { return w }
            if viewModel.didFetchHeartRate { return viewModel.currentHeartRate }
            return 0
        }
        
        private var guideHRVisualFloor: Double {
            let hr = guideHeartRateNumeric
            if hr >= 130 { return 85 }
            if hr >= 115 { return 72 }
            if hr >= 100 { return 55 }
            return 0
        }
        
        private var sessionScoreIntensity: Double {
#if DEBUG && targetEnvironment(simulator)
            if simDemoOverrideEnabled {
                return min(max(max(simDemoScore, guideHRVisualFloor) / 100.0, 0), 1)
            }
#endif
            let raw = min(max(viewModel.graphicInput.score / 100.0, 0), 1)
            return max(raw, guideHRVisualFloor / 100.0)
        }
        
        private var sessionStateColor: Color {
            let sc = sessionScoreIntensity
            let hasData = viewModel.didFetchHeartRate || viewModel.didFetchHRV
            let hasHR = guideHeartRateNumeric > 0
            if !hasData && !hasHR { return Color(hue: 0.62, saturation: 0.80, brightness: 0.88) }
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
                
                CyberGridShape(cellSize: 54)
                    .stroke(Color.cyan.opacity(0.030), lineWidth: 0.4)
                    .ignoresSafeArea()
                
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
                
                if step == .session {
                    SessionAmbientStarfield(score: sessionScoreIntensity, stateColor: sessionStateColor)
                        .ignoresSafeArea()
                    
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
            HStack(spacing: 10) {
                if step == .session {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sessionIsRunning = false
                            sessionElapsed = 0
                            sessionIsFinished = false
                            step = .exerciseSelection
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("改善選択に戻る")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.cyan.opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.cyan.opacity(0.35), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // 閉じる（中断）ボタン
                Button {
                    if step == .session && sessionIsRunning {
                        showAbandonAlert = true
                    } else {
                        step = .exerciseSelection
                        selectedExercise = nil
                        dismiss()
                        selectedTab = 0
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                // 元々あった右上の三本線メニューボタン
                GlobalMenuButton()
            }
        }
        
        
        private var topBarTitle: String {
            switch step {
            case .sceneSelection:    return "場面を選ぶ"
            case .exerciseSelection: return "改善"
            case .session:           return "改善中"
            case .remeasurement:     return "再計測"
            case .result:            return "結果"
            }
        }
        
        // MARK: - Step Progress Indicator
        
        private var stepProgressIndicator: some View {
            HStack(spacing: 8) {
                stepDot(active: step == .sceneSelection, done: step == .exerciseSelection || step == .session)
                stepLine(lit: step == .exerciseSelection || step == .session)
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
                    removal: .opacity.combined(with: .move(edge: .leading))
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
            .animation(.easeInOut(duration: 0.20), value: selectedCategory)
            .animation(.easeInOut(duration: 0.20), value: selectedExercise)
        }
        
        @ViewBuilder
        private var selectionSummaryBanner: some View {
            let bg = RoundedRectangle(cornerRadius: 10)
            if step == .exerciseSelection {
                switch selectedCategory {
                case .breathing:
                    if let exercise = selectedExercise {
                        summaryRow(
                            icon: exercise.icon,
                            label: "呼吸法・\(exercise.title)",
                            trailing: "checkmark.circle.fill"
                        )
                        .background(bg.fill(Color.cyan.opacity(0.06))
                            .overlay(bg.strokeBorder(Color.cyan.opacity(0.22), lineWidth: 0.8)))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                case .puzzle:
                    summaryRow(
                        icon: "square.grid.3x3.fill",
                        label: "スライドパズル",
                        trailing: "checkmark.circle.fill"
                    )
                    .background(bg.fill(Color.cyan.opacity(0.06))
                        .overlay(bg.strokeBorder(Color.cyan.opacity(0.22), lineWidth: 0.8)))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                case .acupressure:
                    summaryRow(
                        icon: "hand.raised.fill",
                        label: "手のツボ押し",
                        trailing: "checkmark.circle.fill"
                    )
                    .background(bg.fill(Color.pink.opacity(0.08))
                        .overlay(bg.strokeBorder(Color.pink.opacity(0.28), lineWidth: 0.8)))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        
        private func summaryRow(icon: String, label: String, trailing: String? = nil, trailingText: String? = nil) -> some View {
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
        
        // MARK: - Fixed Bottom CTA
        
        @ViewBuilder
        private var fixedBottomCTA: some View {
            switch step {
            case .exerciseSelection:
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                        Task { @MainActor in selectedTab = 0 }
                    } label: {
                        backLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ホームへ戻る")
                    
                    Button {
                        handleStartAction()
                    } label: {
                        ctaLabel(
                            text: "開始",
                            icon: "play.fill",
                            enabled: canStartSelection
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStartSelection)
                    
                    Button { showMokorinTalk = true } label: {
                        Text("AI相談")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.cyan.opacity(0.9))
                            .padding(.horizontal, 14).padding(.vertical, 17)
                            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cyan.opacity(0.5), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guide_select_ai_consult")
                }
                
            case .result:
                VStack(spacing: 10) {
                    if needsRetryOptions {
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("まだ緊張が残っているようです。続けますか？")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Color.cyan.opacity(0.85))
                            
                            HStack(spacing: 10) {
                                Button {
                                    selfReportAfter = nil
                                    afterSnapshot = nil
                                    startSession()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text("もう一度やる")
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.08))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(Color.cyan.opacity(0.45), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    selfReportAfter = nil
                                    afterSnapshot = nil
                                    selectedExercise = nil
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        step = .exerciseSelection
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("別の方法を試す")
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.cyan)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.cyan.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 0.8)
                                )
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                
            default:
                EmptyView()
            }
        }
        
        private func handleStartAction() {
            switch selectedCategory {
            case .breathing:
                startSession()
            case .puzzle, .acupressure:
                activeInteractiveTool = selectedCategory
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
                        RoundedRectangle(cornerRadius: 13)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.16), .clear],
                                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)
                            ))
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
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
        
        // MARK: - ▼ STEP 2: Exercise Selection（第1階層3択 ＋ 呼吸法選択時のみ第2階層を展開）
        
        private var exerciseListContent: some View {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // 上部: もこりんのおすすめ
                    HStack(alignment: .center, spacing: 12) {
                        MokorinAvatarView(size: 64, pose: MokorinPose().with(.happy, .nod))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("今のあなたには")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.65))
                            Text("「\((recommendedExercise.map { ImprovementMethod.from($0).title }) ?? methodRecommendations.first?.method.title ?? "呼吸法")」がおすすめ")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            if let reason = recommendationReason {
                                Text(reason)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.cyan.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("mokorin_recommendation")
                    
                    // ━━━ 第1階層：改善方法のカテゴリ（呼吸法 / スライドパズル / 手のツボ押し）
                    sectionHeader("改善方法を選ぶ", note: "まずは種類を選択")
                    
                    VStack(spacing: 10) {
                        ForEach(ImprovementCategory.allCases) { category in
                            categoryChoiceCard(category)
                        }
                    }
                    
                    // ━━━ 第2階層：「呼吸法」を選択したときだけ展開する3択
                    if selectedCategory == .breathing {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("どの呼吸法にしますか？", note: "3つから選択")
                            
                            if let rec = recommendedExercise {
                                recommendedExerciseCard(rec)
                            }
                            
                            VStack(spacing: 8) {
                                ForEach(GuideExercise.allCases.filter { $0 != recommendedExercise }) { exercise in
                                    compactExerciseRow(exercise)
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.cyan.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(Color.cyan.opacity(0.24), lineWidth: 0.9)
                                )
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // ガイドのない方法（手順を見て自分で）
                    sectionHeader("手順を見て自分で", note: "タイマーなし")
                    VStack(spacing: 8) {
                        ForEach(stepOnlyMethods, id: \.self) { method in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(method.steps.enumerated()), id: \.offset) { i, stepText in
                                        Text("\(i + 1). \(stepText)")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(method.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.9))
                                    if methodRecommendations.contains(where: { $0.method == method }) {
                                        Text("おすすめ")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.cyan.opacity(0.85)))
                                    }
                                }
                            }
                            .tint(.cyan)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                        }
                    }
                    
                    // 体感入力（任意）
                    SelfReportPickerView(selection: $selfReportBefore)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .onAppear {
                if resume == nil, let p = flowState.pendingImprovement {
                    adoptPendingImprovement(p)
                    return
                }
                if selectedScene == nil || selectedScene == .other {
                    selectedScene = sceneFromConversation
                }
                if selectedExercise == nil, let ex = recommendedExercise {
                    selectedExercise = ex
                }
                if let d = recommendedDuration?.seconds, sessionElapsed == sessionDurationSeconds {
                    sessionDurationSeconds = d
                    sessionElapsed = d
                }
#if DEBUG
                if ProcessInfo.processInfo.environment["MW_FLOW_AUTOPILOT"] == "1" {
                    let pauseTest = ProcessInfo.processInfo.environment["MW_GUIDE_PAUSE_TEST"] == "1"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if step == .exerciseSelection { startSession() } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { if step == .session { sessionIsRunning = true } }
                    if pauseTest {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { if step == .session { sessionIsRunning = false } }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { if step == .session, isSessionPaused { sessionIsRunning = true } }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (pauseTest ? 26 : 10)) { if step == .session { finishSession(early: true) } }
                }
#endif
            }
            .sheet(isPresented: $showMokorinTalk) {
                ContextCalibrationView(flowState: flowState) { showMokorinTalk = false }
            }
        }
        
        /// 第1階層カテゴリカード（呼吸法 / スライドパズル / 手のツボ押し）
        private func categoryChoiceCard(_ category: ImprovementCategory) -> some View {
            let isSelected = selectedCategory == category
            let ac = category.accentColor
            
            return Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    selectedCategory = category
                    if category == .breathing && selectedExercise == nil {
                        selectedExercise = recommendedExercise ?? .breathing478
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? ac.opacity(0.22) : Color.white.opacity(0.06))
                            .frame(width: 46, height: 46)
                        Image(systemName: category.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isSelected ? ac : .white.opacity(0.65))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(category.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                            if category == .breathing {
                                Text("おすすめ")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.cyan.opacity(0.9)))
                            }
                        }
                        Text(category.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(isSelected ? ac.opacity(0.9) : .white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    if category == .breathing {
                        Image(systemName: isSelected ? "chevron.down.circle.fill" : "chevron.right.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? ac : .white.opacity(0.3))
                    } else {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? ac : .white.opacity(0.25))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(isSelected ? ac.opacity(0.12) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .strokeBorder(isSelected ? ac.opacity(0.75) : Color.white.opacity(0.10), lineWidth: isSelected ? 1.4 : 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        
        private var sceneFromConversation: MeasurementScene {
            if let s = flowState.mokorinMemory?.checkIn?.situation?.value {
                switch s {
                case .presentation: return .speech
                case .interviewExam: return .interview
                case .communication, .importantEvent: return .social
                case .restless: return .daily
                case .other: return .other
                }
            }
            switch flowState.measurementContext.scene {
            case .interview: return .interview
            case .sports: return .sports
            case .important: return .social
            case .work: return .study
            case .calm: return .daily
            case .other: return .other
            }
        }
        
        private func adoptPendingImprovement(_ p: PendingImprovement) {
            adoptedResume = p
            didApplyResume = false
            selectedScene = p.scene
            selectedCategory = .breathing
            selectedExercise = p.exercise
            sessionDurationSeconds = p.durationSeconds
            step = .session
        }
        
        private var stepOnlyMethods: [ImprovementMethod] {
            let recs = methodRecommendations.map(\.method).filter { $0.guideExercise == nil && !$0.steps.isEmpty && $0 != .rest }
            let base: [ImprovementMethod] = [.stretch, .muscleRelaxation, .grounding]
            return recs + base.filter { !recs.contains($0) }
        }
        
        private func sectionHeader(_ title: String, note: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.top, 2)
        }
        
        private func recommendedExerciseCard(_ exercise: GuideExercise) -> some View {
            let selected = selectedExercise == exercise
            return Button {
                withAnimation(.easeInOut(duration: 0.15)) { selectedExercise = exercise }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: exercise.icon)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color.cyan)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.cyan.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(exercise.title)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                            Text("おすすめ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.yellow.opacity(0.9)))
                        }
                        Text(exercise.timingLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.8))
                        Text(exercise.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? Color.cyan : .white.opacity(0.3))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [Color.cyan.opacity(0.22), Color.cyan.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.yellow.opacity(selected ? 0.9 : 0.5), lineWidth: selected ? 2 : 1))
                )
            }
            .shadow(color: Color.cyan.opacity(0.28), radius: 10)
            .buttonStyle(.plain)
            .accessibilityLabel("おすすめ: \(exercise.title)。\(exercise.description)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("recommended_exercise_card")
        }
        
        private func compactExerciseRow(_ exercise: GuideExercise) -> some View {
            let selected = selectedExercise == exercise
            return Button {
                withAnimation(.easeInOut(duration: 0.15)) { selectedExercise = exercise }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: exercise.icon)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.title + " " + exercise.subtitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(exercise.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Color.cyan : .white.opacity(0.25))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(selected ? 0.10 : 0.04))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.cyan.opacity(selected ? 0.7 : 0.15), lineWidth: 1)))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        
        // MARK: - ▼ STEP 3: Session
        
        private var sessionContent: some View {
            VStack(spacing: 0) {
                if sessionElapsed < sessionDurationSeconds || sessionIsRunning || sessionIsFinished {
                    if let ex = selectedExercise {
                        Text("\(ex.title) \(ex.subtitle)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.cyan.opacity(0.9))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(Color.cyan.opacity(0.12)))
                            .padding(.top, 6)
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach(GuideExercise.allCases) { ex in
                            let isActive = selectedExercise == ex
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) { selectedExercise = ex }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isActive
                                              ? LinearGradient(colors: [Color.cyan.opacity(0.28), Color.cyan.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                                              : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                    
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(isActive ? Color.cyan.opacity(0.68) : Color.cyan.opacity(0.15), lineWidth: isActive ? 1.2 : 0.8)
                                    
                                    if isActive {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.cyan.opacity(0.45), lineWidth: 4)
                                            .blur(radius: 8)
                                    }
                                    
                                    VStack(spacing: 0) {
                                        Rectangle()
                                            .fill(isActive ? Color.cyan.opacity(1.0) : Color.white.opacity(0.06))
                                            .frame(height: isActive ? 1.5 : 1.0)
                                        Spacer()
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
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
                }
                
                HStack(spacing: 0) {
                    Text(sessionAIMicrocopy)
                        .font(.system(size: 9.5, weight: .light, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.38))
                        .tracking(0.4)
                        .lineLimit(1)
                        .padding(.leading, 12)
                        .animation(.easeInOut(duration: 0.4), value: sessionAIMicrocopy)
                    Spacer()
                    miniStateWindow
                        .padding(.trailing, 10)
                        .onTapGesture { showHomeConfirm = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("ホームのグラフィックへ戻る")
                        .accessibilityIdentifier("guide_mini_window")
                        .alert("ホームへ戻りますか？", isPresented: $showHomeConfirm) {
                            Button("Yes") { returnHomeKeepingProgress() }
                            Button("No", role: .cancel) {}
                        } message: {
                            Text(step == .session && !sessionIsFinished ? "途中の改善は「改善途中」として残り、改善からあとで再開できます。" : "")
                        }
                }
                .padding(.top, 8)
                .padding(.bottom, 2)
                
                sessionVisual
                    .padding(.bottom, isCompactHeight ? 14 : 16)
                
                VStack(spacing: 2) {
                    if sessionIsFinished {
                        Text("おつかれさま！結果をまとめているよ")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.cyan.opacity(0.8))
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(sessionTimeString)
                            .font(.system(size: isCompactHeight ? 40 : 64, weight: .thin, design: .rounded))
                            .foregroundStyle(.white.opacity(sessionIsFinished ? 0.22 : 0.88))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if !sessionIsFinished {
                            Text("のこり")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.bottom, 10)
                        }
                    }
                }
                .padding(.top, 2)
                
                if !sessionIsRunning && !sessionIsFinished {
                    sessionDurationPicker.padding(.vertical, isCompactHeight ? 6 : 12)
                }
                
                Spacer(minLength: isCompactHeight ? 6 : 14)
                
                if !sessionIsFinished {
                    if isSessionPaused {
                        Label("一時停止中 —「再開」で続きから", systemImage: "pause.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.cyan.opacity(0.85))
                            .padding(.bottom, 8)
                            .accessibilityIdentifier("guide_paused_label")
                    }
                    
                    bigSessionButton.padding(.horizontal, 20)
                    
                    if sessionIsRunning {
                        HStack(spacing: 24) {
                            Button { sessionIsRunning = false } label: {
                                Label("一時停止", systemImage: "pause.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("ガイドを止めて、あとで再開できます")
                            .accessibilityIdentifier("guide_pause_button")
                            
                            if MindState.from(score: viewModel.graphicInput.score) != .overTense {
                                Button { finishSession(early: true) } label: {
                                    Text("→ Finish")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.cyan.opacity(0.9))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("ここで終えて結果を見る")
                                .accessibilityIdentifier("guide_finish_button")
                            }
                        }
                        .padding(.top, 10)
                    }
                }
                
                Spacer(minLength: isCompactHeight ? 10 : 24)
            }
            .sheet(isPresented: $showMokorinTalk) {
                ContextCalibrationView(flowState: flowState) { showMokorinTalk = false }
            }
            .onAppear {
                if adoptedResume == nil, resume == nil, flowState.pendingImprovement != nil {
                    flowState.pendingImprovement = nil
                    return
                }
                guard let r = adoptedResume ?? resume, !didApplyResume else { return }
                didApplyResume = true
                startSession()
                sessionElapsed = r.remainingSeconds
                flowState.pendingImprovement = nil
            }
        }
        
        private var sessionVisual: some View {
            ZStack {
                ZStack {
                    RadialGradient(
                        colors: [
                            Color(hue: 0.60, saturation: 0.85, brightness: 0.75).opacity(0.16),
                            Color(hue: 0.60, saturation: 0.70, brightness: 0.50).opacity(0.06),
                            .clear
                        ],
                        center: .center, startRadius: 0, endRadius: 210
                    )
                    RadialGradient(
                        colors: [Color.cyan.opacity(0.14), .clear],
                        center: .center, startRadius: 0, endRadius: 90
                    )
                }
                .frame(width: isCompactHeight ? 220 : 340, height: isCompactHeight ? 220 : 340)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                
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
                .scaleEffect(isCompactHeight
                             ? (sessionIsRunning || sessionIsFinished ? 0.76 : 0.68)
                             : (sessionIsRunning || sessionIsFinished ? 1.3 : 1.05))
                .frame(height: isCompactHeight
                       ? (sessionIsRunning || sessionIsFinished ? 228 : 176)
                       : (sessionIsRunning || sessionIsFinished ? 400 : 330))
            }
            .animation(.easeInOut(duration: 0.5), value: sessionIsRunning)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                MokorinSessionHint(remaining: sessionElapsed, total: sessionDurationSeconds, isRunning: sessionIsRunning)
                    .padding(.leading, 6)
                    .padding(.top, 2)
                    .animation(.easeInOut(duration: 0.4), value: sessionElapsed)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: isCompactHeight ? 200 : 300)
            .overlay(alignment: .leading) {
                Canvas { ctx, size in
                    let sh = size.height
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: sh)), with: .color(Color.cyan.opacity(0.04)))
                    var el = Path()
                    el.move(to: CGPoint(x: size.width - 0.5, y: sh * 0.06))
                    el.addLine(to: CGPoint(x: size.width - 0.5, y: sh * 0.94))
                    ctx.stroke(el, with: .color(Color.cyan.opacity(0.32)), lineWidth: 0.8)
                    for i in 0..<3 {
                        let y = sh * (0.22 + Double(i) * 0.28)
                        ctx.fill(Path(ellipseIn: CGRect(x: size.width - 6, y: y - 2.2, width: 4.5, height: 4.5)), with: .color(Color.cyan.opacity(0.40)))
                        ctx.fill(Path(ellipseIn: CGRect(x: size.width - 5, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(Color.black.opacity(0.50)))
                    }
                }
                .frame(width: 20)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                Canvas { ctx, size in
                    let sh = size.height
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: sh)), with: .color(Color.cyan.opacity(0.04)))
                    var el = Path()
                    el.move(to: CGPoint(x: 0.5, y: sh * 0.06))
                    el.addLine(to: CGPoint(x: 0.5, y: sh * 0.94))
                    ctx.stroke(el, with: .color(Color.cyan.opacity(0.32)), lineWidth: 0.8)
                    for i in 0..<3 {
                        let y = sh * (0.22 + Double(i) * 0.28)
                        ctx.fill(Path(ellipseIn: CGRect(x: 1.5, y: y - 2.2, width: 4.5, height: 4.5)), with: .color(Color.cyan.opacity(0.40)))
                        ctx.fill(Path(ellipseIn: CGRect(x: 2.5, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(Color.black.opacity(0.50)))
                    }
                }
                .frame(width: 20)
                .allowsHitTesting(false)
            }
        }
        
        // MARK: - ミニ緊張状態ウィンドウ
        
        private var miniStateWindow: some View {
            let input = viewModel.graphicInput
#if DEBUG && targetEnvironment(simulator)
            let rawScore = simDemoOverrideEnabled
            ? min(max(simDemoScore / 100.0, 0.0), 1.0)
            : min(max(input.score / 100.0, 0.0), 1.0)
#else
            let rawScore = min(max(input.score / 100.0, 0.0), 1.0)
#endif
            let score = max(rawScore, guideHRVisualFloor / 100.0)
            let hasData = viewModel.didFetchHeartRate || viewModel.didFetchHRV
            let hasHR = guideHeartRateNumeric > 0
            
            let stateName: String
            let stateColor: Color
            if !hasData && !hasHR {
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
#if DEBUG && targetEnvironment(simulator)
                if simDemoOverrideEnabled { return String(format: "%.0f", simDemoBPM) }
#endif
                if let w = viewModel.latestWatchHeartRate { return String(format: "%.0f", w) }
                if viewModel.didFetchHeartRate { return String(format: "%.0f", viewModel.currentHeartRate) }
                if viewModel.activeDataSource == .mock { return "72" }
                return "—"
            }()
            
            let starSpeed = hasData ? (score * 40 + 14) : 10.0
            let capturedColor = stateColor
            
            return VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    TimelineView(.animation) { tl in
                        Canvas { ctx, sz in
                            let t = tl.date.timeIntervalSinceReferenceDate
                            let count = 9
                            let speeds: [Double] = [starSpeed, starSpeed * 0.58, starSpeed * 1.32, starSpeed * 0.82, starSpeed * 1.12, starSpeed * 0.72, starSpeed * 1.45, starSpeed * 0.90, starSpeed * 1.20]
                            let yRatios: [Double] = [0.10, 0.35, 0.58, 0.82, 0.22, 0.50, 0.72, 0.40, 0.90]
                            let radii: [CGFloat] = [1.8, 1.3, 1.6, 1.4, 2.1, 1.1, 1.7, 1.2, 1.5]
                            let alphas: [CGFloat] = [0.70, 0.52, 0.64, 0.46, 0.75, 0.40, 0.58, 0.48, 0.66]
                            let tails: [Double] = [11, 7, 13, 8, 16, 6, 10, 7, 12]
                            
                            for i in 0..<count {
                                let xBase = t * speeds[i]
                                let x = sz.width - CGFloat(xBase.truncatingRemainder(dividingBy: Double(sz.width) + tails[i] + 4))
                                let y = sz.height * CGFloat(yRatios[i])
                                let r = radii[i]
                                let a = alphas[i]
                                
                                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 1.9, y: y - r * 1.9, width: r * 3.8, height: r * 3.8)), with: .color(capturedColor.opacity(a * 0.22)))
                                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(capturedColor.opacity(a)))
                                
                                var tail = Path()
                                tail.move(to: CGPoint(x: x + r, y: y))
                                tail.addLine(to: CGPoint(x: x + r + CGFloat(tails[i]), y: y))
                                ctx.stroke(tail, with: .color(capturedColor.opacity(a * 0.28)), lineWidth: r * 0.70)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
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
                    LinearGradient(colors: [Color.black.opacity(0.68), Color.black.opacity(0.32)], startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .top) {
                    Rectangle().fill(capturedColor.opacity(0.52)).frame(height: 0.9)
                }
                
                Rectangle()
                    .fill(stateColor.opacity(0.28))
                    .frame(height: 0.6)
                
                VStack(spacing: 5) {
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
                        .fill(LinearGradient(colors: [Color.white.opacity(0.04), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)))
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(stateColor.opacity(0.48), lineWidth: 1.0)
                }
            )
            .shadow(color: stateColor.opacity(0.32), radius: 14)
            .animation(.easeInOut(duration: 1.2), value: hasData)
            .accessibilityIdentifier("guide_session_mini_state_window")
        }
        
        private var sessionTimeString: String {
            String(format: "%d:%02d", sessionElapsed / 60, sessionElapsed % 60)
        }
        
        private var sessionAIMicrocopy: String {
            guard sessionIsRunning else { return "" }
            switch viewModel.graphicInput.state {
            case .underAroused:   return "このリズムを維持"
            case .optimalTension: return guideHeartRateNumeric < 105 ? "集中を保ちながら整える" : "吐く時間を意識して"
            case .overTense:      return "まず吐く呼吸を長く"
            }
        }
        
        private let sessionDurationOptions: [(label: String, seconds: Int)] = [
            ("1分", 60), ("3分", 180), ("5分", 300)
        ]
        
        private var sessionDurationPicker: some View {
            VStack(spacing: 6) {
                if let rec = recommendedDuration {
                    Text("おすすめは\(rec.seconds / 60)分だよ（\(rec.reason)）")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .accessibilityIdentifier("recommended_duration")
                }
                HStack(spacing: 10) {
                    ForEach(sessionDurationOptions, id: \.seconds) { opt in
                        let recommended = recommendedDuration?.seconds == opt.seconds
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
                                        .fill(sessionDurationSeconds == opt.seconds ? Color.cyan.opacity(0.85) : Color.white.opacity(0.10))
                                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.yellow.opacity(recommended ? 0.85 : 0), lineWidth: 1.5))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(opt.label)を選択" + (recommended ? "（おすすめ）" : ""))
                    }
                    
                    Button { showDurationPicker = true } label: {
                        Text(sessionDurationOptions.contains { $0.seconds == sessionDurationSeconds } ? "選択" : "\(sessionDurationSeconds / 60)分")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(sessionDurationOptions.contains { $0.seconds == sessionDurationSeconds } ? .white.opacity(0.55) : .black)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 20).fill(sessionDurationOptions.contains { $0.seconds == sessionDurationSeconds } ? Color.white.opacity(0.10) : Color.cyan.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("時間を自分で選ぶ")
                    .accessibilityIdentifier("duration_custom")
                }
            }
            .sheet(isPresented: $showDurationPicker) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Text("何分で行いますか？")
                            .font(.system(size: 17, weight: .semibold))
                        Stepper("\(customMinutes) 分", value: $customMinutes, in: 1...10)
                            .padding(.horizontal, 40)
                        Button("この時間にする") {
                            sessionDurationSeconds = customMinutes * 60
                            sessionElapsed = customMinutes * 60
                            showDurationPicker = false
                        }
                        .buttonStyle(.borderedProminent)
                        Button("→ 時間を相談する") {
                            showDurationPicker = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showMokorinTalk = true }
                        }
                        .accessibilityIdentifier("duration_consult")
                    }
                    .padding(.top, 24)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { showDurationPicker = false } } }
                    .presentationDetents([.medium])
                }
                .preferredColorScheme(.dark)
            }
        }
        
        private var bigSessionButton: some View {
            let isStop = sessionIsRunning
            return Button {
                if sessionIsRunning { finishSession(early: true) } else { sessionIsRunning = true }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isStop ? Color.orange.opacity(0.28) : Color.cyan.opacity(0.28), lineWidth: 14)
                        .blur(radius: 18)
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isStop ? Color.orange.opacity(0.60) : Color.cyan.opacity(0.60), lineWidth: 3)
                        .blur(radius: 6)
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isStop ? Color.orange.opacity(0.90) : Color.cyan.opacity(0.88), lineWidth: 1.2)
                        .blur(radius: 1)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isStop
                              ? LinearGradient(colors: [Color.orange.opacity(0.20), Color.orange.opacity(0.10), Color(red: 0.12, green: 0.02, blue: 0.00)], startPoint: .top, endPoint: .bottom)
                              : LinearGradient(colors: [Color.cyan.opacity(0.18), Color.cyan.opacity(0.08), Color(red: 0.00, green: 0.06, blue: 0.14)], startPoint: .top, endPoint: .bottom))
                    
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.03), .clear],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)
                        )
                        .frame(height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        Spacer()
                    }
                    
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
                    
                    HStack(spacing: 12) {
                        Image(systemName: isStop ? "stop.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                        Text(isStop ? "STOP" : (isSessionPaused ? "再開" : "START"))
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .tracking(4.0)
                    }
                    .foregroundStyle(isStop ? Color.orange.opacity(0.97) : Color.cyan.opacity(0.97))
                    .shadow(color: isStop ? Color.orange.opacity(0.45) : Color.cyan.opacity(0.45), radius: 8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: isCompactHeight ? 62 : 76)
            }
            .buttonStyle(.plain)
            .shadow(color: isStop ? Color.orange.opacity(0.50) : Color.cyan.opacity(0.38), radius: 24, y: 4)
            .accessibilityLabel(isStop ? "停止する" : (isSessionPaused ? "再開する" : "開始する"))
            .accessibilityIdentifier("guide_session_button")
            .animation(.easeInOut(duration: 0.22), value: isStop)
        }
        
        private var isSessionPaused: Bool {
            !sessionIsRunning && !sessionIsFinished && sessionElapsed > 0 && sessionElapsed < sessionDurationSeconds
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
                Text("もこりん：今、測定しているよ。いつもどおりにしていてね。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("mokorin_measuring_hint")
                
                VStack(spacing: 8) {
                    let newSamples = viewModel.watchMessageCount - remeasurementStartCount
                    let targetSamples = GuideFlowConstants.minWatchSamplesForRemeasurement
                    HStack(spacing: 6) {
                        Text("受信件数")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.38))
                        Text("\(newSamples) / \(targetSamples)")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(newSamples >= targetSamples ? Color.cyan.opacity(0.9) : .white.opacity(0.65))
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
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        resultHero
                            .padding(.top, 8)
                        
                        if let before = beforeSnapshot {
                            resultChangeGraphic(before: before, after: afterSnapshot)
                        }
                        resultMokorinExplanation
                        
                        Color.clear.frame(height: 1).id("result_reflection")
                        
                        if let result = prototypeResult {
                            PrototypeScorePanel(
                                s0: subjectiveBefore,
                                s0After: $subjectiveAfter,
                                result: result,
                                usesDemoData: (beforeSnapshot?.isMockData ?? false) || (afterSnapshot?.isMockData ?? false)
                            )
                        }
                        
                        MokorinReflectionView(alternative: nextMethod, answer: $reflectionAnswer) { next in
                            guard let ex = next.guideExercise else { return }
                            selectedExercise = ex
                            reflectionAnswer = nil
                            subjectiveAfter = nil
                            resetForNewSession()
                        }
                        
                        if latestAIInsight != nil || aiFeedbackResult != nil {
                            DisclosureGroup {
                                if let insight = latestAIInsight {
                                    AIDebriefCard(insight: insight, selfReportBefore: selfReportBefore, selfReportAfter: selfReportAfter)
                                } else if let feedback = aiFeedbackResult {
                                    AIFeedbackCardView(result: feedback)
                                }
                            } label: {
                                Text("詳しいフィードバック")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .tint(.cyan)
                            .accessibilityIdentifier("result_detail_feedback")
                        }
                        
                        SelfReportAfterView(selection: $selfReportAfter, onChanged: {
                            regenerateInsightWithAfterReport()
                        })
                        
                        Text("このフィードバックは医療診断ではありません。\n数値は計測環境により変動します。")
                            .font(.system(size: 10, weight: .light))
                            .foregroundStyle(.white.opacity(0.26))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                        
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
                    Color.clear.frame(height: 1).id("result_bottom")
                }
#if DEBUG
                .onAppear {
                    if ProcessInfo.processInfo.environment["MW_FLOW_AUTOPILOT"] == "1" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { proxy.scrollTo("result_reflection", anchor: .top) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { reflectionAnswer = .littleCalmer }
                    }
                    if ProcessInfo.processInfo.environment["MW_SCROLL_RESULT"] == "reflection" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { proxy.scrollTo("result_reflection", anchor: .top) }
                    }
                }
#endif
            }
        }
        
        // MARK: - Timer
        
        private func tickTimer() {
            switch step {
            case .session:
                guard sessionIsRunning else { return }
                if sessionElapsed > 0 {
                    sessionElapsed -= 1
                    if sessionElapsed == 0 { finishSession(early: false) }
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
        
        private func finishSession(early: Bool) {
            guard step == .session, !sessionIsFinished else { return }
            let practiced = sessionDurationSeconds - sessionElapsed
            MindWaveDebugLogger.log(.flow, "session finish early=\(early) practicedSeconds=\(practiced)")
            sessionIsRunning = false
            sessionIsFinished = true
            aiFeedbackResult = LocalAIFeedbackGenerator.generate(
                heartRate: guideHeartRateNumeric,
                exercise: selectedExercise ?? .breathing478,
                scene: selectedScene ?? .other
            )
            let ctx = MindWaveAIContext(
                scene: selectedScene ?? .other,
                breathingMethod: selectedExercise ?? .breathing478,
                currentHeartRate: guideHeartRateNumeric,
                state: viewModel.graphicInput.state,
                sessionElapsed: practiced,
                sessionCompleted: !early,
                beforeHeartRate: beforeSnapshot?.heartRate,
                afterHeartRate: nil,
                beforeState: beforeSnapshot?.state,
                afterState: nil,
                selfReportBefore: selfReportBefore,
                selfReportAfter: nil,
                baselineHeartRate: viewModel.baseline.heartRateStatus == .personal ? viewModel.baseline.heartRate : nil,
                source: "local"
            )
            latestAIInsight = LocalMindWaveAIEngine.generate(context: ctx)
            MindWaveDebugLogger.log(.flow, "session completed")
            DispatchQueue.main.asyncAfter(deadline: .now() + (early ? 0.3 : 1.5)) {
                guard self.sessionIsFinished else { return }
                self.startRemeasurement()
            }
        }
        
        // MARK: - Session Helpers
        
        private func startSession() {
            beforeSnapshot = captureBeforeSnapshot()
            sessionElapsed = sessionDurationSeconds
            sessionIsRunning = false
            sessionIsFinished = false
            step = .session
            MindWaveDebugLogger.log(.flow, "session started duration=\(sessionDurationSeconds)")
        }
        
        private func captureBeforeSnapshot() -> GuideSnapshot {
            GuideSnapshot(
                timestamp: Date(),
                score: viewModel.graphicInput.score,
                confidence: viewModel.graphicInput.confidence,
                state: viewModel.graphicInput.state,
                heartRate: viewModel.snapshotHeartRate,
                hrv: viewModel.snapshotHRV,
                isMockData: viewModel.isMockMode,
                heartRateSampleDate: viewModel.latestHeartRateSampleDate,
                hrvSampleDate: viewModel.latestHRVSampleDate,
                dataSource: viewModel.activeDataSource
            )
        }
        
        private func startRemeasurement() {
            remeasurementStartCount = viewModel.watchMessageCount
            remeasurementStartHRVDate = viewModel.latestHRVSampleDate
            remeasurementElapsed = 0
            remeasurementCompleted = false
            step = .remeasurement
        }
        
        private func completeRemeasurement() {
            guard !remeasurementCompleted else { return }
            remeasurementCompleted = true
            let newHRVDate = viewModel.latestHRVSampleDate
            hrvUpdatedDuringSession = (newHRVDate != remeasurementStartHRVDate && newHRVDate != nil)
            let snap = GuideSnapshot(
                timestamp: Date(),
                score: viewModel.graphicInput.score,
                confidence: viewModel.graphicInput.confidence,
                state: viewModel.graphicInput.state,
                heartRate: viewModel.snapshotHeartRate,
                hrv: viewModel.snapshotHRV,
                isMockData: viewModel.isMockMode,
                heartRateSampleDate: viewModel.latestHeartRateSampleDate,
                hrvSampleDate: viewModel.latestHRVSampleDate,
                dataSource: viewModel.activeDataSource
            )
            afterSnapshot = snap
            let ctx = MindWaveAIContext(
                scene: selectedScene ?? .other,
                breathingMethod: selectedExercise ?? .breathing478,
                currentHeartRate: snap.heartRate ?? guideHeartRateNumeric,
                state: snap.state,
                sessionElapsed: sessionDurationSeconds,
                sessionCompleted: true,
                beforeHeartRate: beforeSnapshot?.heartRate,
                afterHeartRate: snap.heartRate,
                beforeState: beforeSnapshot?.state,
                afterState: snap.state,
                selfReportBefore: selfReportBefore,
                selfReportAfter: nil,
                baselineHeartRate: viewModel.baseline.heartRateStatus == .personal ? viewModel.baseline.heartRate : nil,
                source: "local"
            )
            latestAIInsight = LocalMindWaveAIEngine.generate(context: ctx)
            requestEnhancedInsight(ctx: ctx)
            step = .result
        }
        
        private func saveWithMemo(_ memo: String) {
            guard let before = beforeSnapshot,
                  let exercise = selectedExercise else { return }
            let scene = selectedScene ?? .other
            let record = GuideSessionRecord(
                id: UUID(), startedAt: before.timestamp,
                scene: scene, exercise: exercise,
                durationSeconds: sessionDurationSeconds,
                before: before, after: afterSnapshot,
                hrvUpdated: hrvUpdatedDuringSession,
                emotionMemo: memo.isEmpty ? nil : memo,
                selfReportBefore: selfReportBefore,
                selfReportAfter: selfReportAfter,
                aiInsightTitle: latestAIInsight?.title,
                aiInsightSummary: latestAIInsight?.summary,
                aiInsightRecommendation: latestAIInsight?.recommendation,
                localAIVersion: insightProviderVersion
            )
            historyStore.add(record)
            showFeedbackView = false
            dismiss()
            Task { @MainActor in selectedTab = 0 }
        }
        
        private func regenerateInsightWithAfterReport() {
            guard let snap = afterSnapshot ?? beforeSnapshot else { return }
            let ctx = MindWaveAIContext(
                scene: selectedScene ?? .other,
                breathingMethod: selectedExercise ?? .breathing478,
                currentHeartRate: snap.heartRate ?? guideHeartRateNumeric,
                state: snap.state,
                sessionElapsed: sessionDurationSeconds,
                sessionCompleted: true,
                beforeHeartRate: beforeSnapshot?.heartRate,
                afterHeartRate: afterSnapshot?.heartRate,
                beforeState: beforeSnapshot?.state,
                afterState: afterSnapshot?.state,
                selfReportBefore: selfReportBefore,
                selfReportAfter: selfReportAfter,
                baselineHeartRate: viewModel.baseline.heartRateStatus == .personal ? viewModel.baseline.heartRate : nil,
                source: "local"
            )
            latestAIInsight = LocalMindWaveAIEngine.generate(context: ctx)
            requestEnhancedInsight(ctx: ctx)
        }
        
        private func requestEnhancedInsight(ctx: MindWaveAIContext) {
            remoteInsightTask?.cancel()
            insightProviderVersion = "local-v1"
            guard let before = beforeSnapshot else { return }
            let input = InsightSessionInput(context: ctx, before: before, after: afterSnapshot, durationSeconds: sessionDurationSeconds)
            if let reason = InsightService.shared.remoteIneligibility(for: input) {
                MindWaveDebugLogger.log(.insight, "guide result uses local insight reason=\(reason.rawValue)")
                return
            }
            remoteInsightTask = Task { @MainActor in
                let outcome = await InsightService.shared.generate(input)
                guard !Task.isCancelled, outcome.usedRemote else { return }
                latestAIInsight = outcome.insight
                insightProviderVersion = outcome.providerVersion
            }
        }
        
        // MARK: - もこりん
        
        private var recentMemory: MokorinSessionMemory? {
            guard let m = flowState.mokorinMemory, Date().timeIntervalSince(m.capturedAt) <= 6 * 3600 else { return nil }
            return m
        }
        
        private var methodRecommendations: [MethodRecommendation] {
            MokorinMethodAdvisor.recommend(recentMemory?.checkIn ?? MokorinCheckIn())
        }
        
        private var recommendedExercise: GuideExercise? {
            if let ex = methodRecommendations.compactMap({ $0.method.guideExercise }).first { return ex }
            if recentMemory?.checkIn?.body?.value.contains(.shallowBreath) == true { return .breathing214 }
            if guideHeartRateNumeric > 0 {
                let score = sessionScoreIntensity * 100.0
                if score >= 66 || viewModel.graphicInput.state == .overTense { return .breathing214 }
                if score >= 33 || viewModel.graphicInput.state == .optimalTension { return .breathing478 }
                return .box
            }
            return selectedScene?.recommendedExercise
        }
        
        private var recommendationReason: String? {
            if let ex = recommendedExercise, let rec = methodRecommendations.first(where: { $0.method.guideExercise == ex }) {
                return rec.reason
            }
            if recommendedExercise == .breathing214,
               recentMemory?.checkIn?.body?.value.contains(.shallowBreath) == true {
                return "息苦しさがあると話していたから、息を長く止めない呼吸にしたよ"
            }
            if let first = methodRecommendations.first, first.method.guideExercise == nil {
                return "「\(first.method.title)」もおすすめ：\(first.reason)"
            }
            return methodRecommendations.first?.reason
        }
        
        private var nextMethod: ImprovementMethod? {
            if let m = methodRecommendations.map(\.method).first(where: { $0.guideExercise != nil && $0.guideExercise != selectedExercise }) { return m }
            return GuideExercise.allCases.first {
                $0 != selectedExercise &&
                !(recentMemory?.checkIn?.body?.value.contains(.shallowBreath) == true && ImprovementMethod.from($0).hasLongBreathHold)
            }
            .map(ImprovementMethod.from)
        }
        
        private var recommendedDuration: (seconds: Int, reason: String)? {
            guard let rec = methodRecommendations.first(where: { $0.method.guideExercise != nil }) ?? methodRecommendations.first else { return nil }
            let options = [60, 180, 300]
            let nearest = options.min { abs($0 - rec.suggestedSeconds) < abs($1 - rec.suggestedSeconds) } ?? 60
            let why = recentMemory?.checkIn?.timing?.value == .soon ? "予定がすぐだから短めに" : "落ち着いて取り組めるように"
            return (nearest, why)
        }
        
        private var subjectiveBefore: Int? {
            recentMemory?.checkIn?.tension?.value ?? SubjectiveScale.from(selfReportBefore)
        }
        
        private var prototypeResult: PrototypeTensionResult? {
            guard let before = beforeSnapshot else { return nil }
            return PrototypeTensionScore.calculate(PrototypeScoreInputBuilder.make(s0: subjectiveBefore, before: before, after: afterSnapshot))
        }
        
        private func makeMokorinCompanion() -> MokorinCompanionViewModel? {
            guard let before = beforeSnapshot else { return nil }
            let input = MokorinResultInput(
                startedAt: before.timestamp,
                scene: selectedScene ?? .other,
                exerciseTitle: (selectedExercise ?? .breathing478).title,
                durationSeconds: sessionDurationSeconds,
                before: before,
                after: afterSnapshot,
                selfReportBefore: selfReportBefore,
                selfReportAfter: selfReportAfter
            )
            let history = historyStore.records
            let memory = flowState.mokorinMemory
            let flowState = self.flowState, viewModel = self.viewModel
            let chat = ChatViewModel(
                sceneProvider: { flowState.measurementContext.scene },
                measurementProvider: {
                    ChatBiometricPolicy.measurementContext(from: viewModel.lastAnalysisResult, now: Date(), consented: InsightConsentStore().isConsented)
                },
                biometricConsentProvider: { InsightConsentStore().isConsented }
            )
            return MokorinCompanionViewModel(chat: chat) { recent in
                MokorinResultExplainer.explain(input, history: history, memory: memory, purpose: .result, recentUserText: recent)
            }
        }
        
        // MARK: - 結果
        
        private var isCompactHeight: Bool { UIScreen.main.bounds.height < 700 }
        private var usesDemoResult: Bool { (beforeSnapshot?.isMockData ?? false) || (afterSnapshot?.isMockData ?? false) }
        
        private var resultHero: some View {
            let practiced = max(0, sessionDurationSeconds - sessionElapsed)
            return VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\((selectedExercise ?? .breathing478).title)を\(practiced / 60 > 0 ? "\(practiced / 60)分" : "")\(practiced % 60 > 0 ? "\(practiced % 60)秒" : "")")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(usesDemoResult ? "デモ値" : "実測")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(usesDemoResult ? Color.orange : Color.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill((usesDemoResult ? Color.orange : Color.green).opacity(0.15)))
                }
                .accessibilityIdentifier("result_data_badge")
                
                HStack(spacing: 8) {
                    metricChip("緊張(本人)", before: subjectiveBefore.map(Double.init), after: subjectiveAfter.map(Double.init), unit: "")
                    metricChip("心拍", before: beforeSnapshot?.heartRate, after: afterSnapshot?.heartRate, unit: "bpm")
                    metricChip("SDNN", before: beforeSnapshot?.hrv, after: afterSnapshot?.hrv, unit: "ms")
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.cyan.opacity(0.25), lineWidth: 1)))
            .accessibilityIdentifier("result_hero")
        }
        
        private func metricChip(_ title: String, before: Double?, after: Double?, unit: String) -> some View {
            let f: (Double?) -> String = { $0.map { "\(Int($0.rounded()))" } ?? "--" }
            return VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                Text("\(f(before)) → \(f(after))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(before == nil && after == nil ? "未取得" : unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))
            .accessibilityElement(children: .combine)
        }
        
        private func resultChangeGraphic(before: GuideSnapshot, after: GuideSnapshot?) -> some View {
            let b = before.score, a = after?.score
            let delta = a.map { Int(($0 - b).rounded()) }
            return VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("緊張スコアの変化")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    if let d = delta {
                        Text(d == 0 ? "±0" : (d > 0 ? "+\(d)" : "\(d)"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(d < 0 ? Color.cyan : (d > 0 ? Color.orange : .white))
                    }
                }
                scoreBar(label: "前", value: b, color: .orange)
                if let a {
                    scoreBar(label: "後", value: a, color: .cyan)
                } else {
                    Text("ガイド後の値は取れていないよ")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.04)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("緊張スコア 前 \(Int(b.rounded()))" + (a.map { "、後 \(Int($0.rounded()))" } ?? "、後は未取得"))
            .accessibilityIdentifier("result_change_graphic")
        }
        
        private func scoreBar(label: String, value: Double, color: Color) -> some View {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 18)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient(colors: [color.opacity(0.5), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, g.size.width * CGFloat(min(100, max(0, value)) / 100)))
                    }
                }
                .frame(height: 14)
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        
        @ViewBuilder
        private var resultMokorinExplanation: some View {
            if let before = beforeSnapshot {
                let input = MokorinResultInput(
                    startedAt: before.timestamp,
                    scene: selectedScene ?? .other,
                    exerciseTitle: (selectedExercise ?? .breathing478).title,
                    durationSeconds: sessionDurationSeconds,
                    before: before,
                    after: afterSnapshot,
                    selfReportBefore: selfReportBefore,
                    selfReportAfter: selfReportAfter
                )
                let brief = MokorinResultExplainer.explain(input, history: historyStore.records, memory: flowState.mokorinMemory)
                let lines = Array((brief.cautions.prefix(usesDemoResult ? 1 : 0) + brief.interpretation.prefix(1) + brief.missing.prefix(1)).prefix(2))
                HStack(alignment: .top, spacing: 10) {
                    MokorinAvatarView(size: 56, pose: MokorinPose().with(.happy, .nod))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lines.isEmpty ? "おつかれさま！一緒に結果を見てみよう。" : lines.joined(separator: "\n"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.22))
                            .fixedSize(horizontal: false, vertical: true)
                        Button { showMokorinCompanion = true } label: {
                            Text("もこりんと詳しく見る >")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 0.1, green: 0.45, blue: 0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mokorin_result_button")
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.93, green: 0.96, blue: 1.0)))
                    .accessibilityElement(children: .combine)
                }
                .accessibilityIdentifier("result_mokorin_explanation")
            }
        }
        
        private func returnHomeKeepingProgress() {
            if step == .session, !sessionIsFinished, let ex = selectedExercise, sessionElapsed > 0 {
                sessionIsRunning = false
                flowState.pendingImprovement = PendingImprovement(
                    scene: selectedScene ?? .other,
                    exercise: ex,
                    durationSeconds: sessionDurationSeconds,
                    remainingSeconds: sessionElapsed,
                    savedAt: Date()
                )
            }
            dismiss()
            Task { @MainActor in selectedTab = 0 }
        }
        
        private func resetForNewSession() {
            remoteInsightTask?.cancel()
            insightProviderVersion = "local-v1"
            sessionIsFinished = false
            sessionIsRunning = false
            sessionElapsed = sessionDurationSeconds
            remeasurementElapsed = 0
            remeasurementCompleted = false
            afterSnapshot = nil
            aiFeedbackResult = nil
            latestAIInsight = nil
            selfReportAfter = nil
            beforeSnapshot = captureBeforeSnapshot()
            step = .session
        }
    }
    
    // MARK: - スライドパズル / 手のツボ押し フルスクリーンコンテナ
    
private struct InteractiveToolContainerView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    let tool: ImprovementCategory
    let onBack: () -> Void
    let onClose: () -> Void

    #if DEBUG && targetEnvironment(simulator)
    @AppStorage("sim_demo_override_enabled") private var simDemoOverrideEnabled = false
    @AppStorage("sim_demo_bpm")             private var simDemoBPM:             Double = 72.0
    @AppStorage("sim_demo_score")           private var simDemoScore:           Double = 12.0
    #endif

    // 呼吸画面の guideHeartRateNumeric / guideHRVisualFloor と同じ計算
    private var guideHeartRateNumeric: Double {
        #if DEBUG && targetEnvironment(simulator)
        if simDemoOverrideEnabled { return simDemoBPM }
        #endif
        if let w = viewModel.latestWatchHeartRate { return w }
        if viewModel.didFetchHeartRate { return viewModel.currentHeartRate }
        if viewModel.activeDataSource == .mock { return 72.0 }
        return 0
    }

    private var guideHRVisualFloor: Double {
        let hr = guideHeartRateNumeric
        guard hr > 0 else { return 0 }
        if hr >= 115 { return 82.0 }
        if hr >= 95  { return 58.0 }
        if hr >= 80  { return 30.0 }
        return 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            // メインコンテンツ（パズル / ツボ押し）
            switch tool {
            case .puzzle:
                CalmPuzzleView()
            case .acupressure:
                HandAcupressureGuideView()
            case .breathing:
                EmptyView()
            }

            // 上部ナビゲーションバー ＋ 呼吸画面と100%同じミニ緊張状態ウィンドウ
            VStack(alignment: .trailing, spacing: 10) {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("改善一覧へ戻る")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.03, green: 0.05, blue: 0.14).opacity(0.88))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.cyan.opacity(0.40), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(Color(red: 0.03, green: 0.05, blue: 0.14).opacity(0.88))
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                // ── 呼吸法画面の miniStateWindow と完全に同じもの ──
                miniStateWindow
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    // MARK: - ミニ緊張状態ウィンドウ（呼吸法画面と100%同一）

    private var miniStateWindow: some View {
        let input = viewModel.graphicInput
        #if DEBUG && targetEnvironment(simulator)
        let rawScore = simDemoOverrideEnabled
            ? min(max(simDemoScore / 100.0, 0.0), 1.0)
            : min(max(input.score / 100.0, 0.0), 1.0)
        #else
        let rawScore = min(max(input.score / 100.0, 0.0), 1.0)
        #endif
        let score = max(rawScore, guideHRVisualFloor / 100.0)
        let hasData = viewModel.didFetchHeartRate || viewModel.didFetchHRV
        let hasHR = guideHeartRateNumeric > 0

        let stateName: String
        let stateColor: Color
        if !hasData && !hasHR {
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
            #if DEBUG && targetEnvironment(simulator)
            if simDemoOverrideEnabled { return String(format: "%.0f", simDemoBPM) }
            #endif
            if let w = viewModel.latestWatchHeartRate { return String(format: "%.0f", w) }
            if viewModel.didFetchHeartRate { return String(format: "%.0f", viewModel.currentHeartRate) }
            if viewModel.activeDataSource == .mock { return "72" }
            return "—"
        }()

        let starSpeed = hasData ? (score * 40 + 14) : 10.0
        let capturedColor = stateColor

        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TimelineView(.animation) { tl in
                    Canvas { ctx, sz in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let count = 9
                        let speeds: [Double] = [starSpeed, starSpeed * 0.58, starSpeed * 1.32, starSpeed * 0.82, starSpeed * 1.12, starSpeed * 0.72, starSpeed * 1.45, starSpeed * 0.90, starSpeed * 1.20]
                        let yRatios: [Double] = [0.10, 0.35, 0.58, 0.82, 0.22, 0.50, 0.72, 0.40, 0.90]
                        let radii: [CGFloat] = [1.8, 1.3, 1.6, 1.4, 2.1, 1.1, 1.7, 1.2, 1.5]
                        let alphas: [CGFloat] = [0.70, 0.52, 0.64, 0.46, 0.75, 0.40, 0.58, 0.48, 0.66]
                        let tails: [Double] = [11, 7, 13, 8, 16, 6, 10, 7, 12]

                        for i in 0..<count {
                            let xBase = t * speeds[i]
                            let x = sz.width - CGFloat(xBase.truncatingRemainder(dividingBy: Double(sz.width) + tails[i] + 4))
                            let y = sz.height * CGFloat(yRatios[i])
                            let r = radii[i]
                            let a = alphas[i]

                            ctx.fill(Path(ellipseIn: CGRect(x: x - r * 1.9, y: y - r * 1.9, width: r * 3.8, height: r * 3.8)), with: .color(capturedColor.opacity(a * 0.22)))
                            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(capturedColor.opacity(a)))

                            var tail = Path()
                            tail.move(to: CGPoint(x: x + r, y: y))
                            tail.addLine(to: CGPoint(x: x + r + CGFloat(tails[i]), y: y))
                            ctx.stroke(tail, with: .color(capturedColor.opacity(a * 0.28)), lineWidth: r * 0.70)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                LinearGradient(colors: [Color.black.opacity(0.68), Color.black.opacity(0.32)], startPoint: .top, endPoint: .bottom)
            )
            .overlay(alignment: .top) {
                Rectangle().fill(capturedColor.opacity(0.52)).frame(height: 0.9)
            }

            Rectangle()
                .fill(stateColor.opacity(0.28))
                .frame(height: 0.6)

            VStack(spacing: 5) {
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
                    .fill(LinearGradient(colors: [Color.white.opacity(0.04), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(stateColor.opacity(0.48), lineWidth: 1.0)
            }
        )
        .shadow(color: stateColor.opacity(0.32), radius: 14)
        .animation(.easeInOut(duration: 1.2), value: hasData)
    }
}

// MARK: - SessionAmbientStarfield

private struct SessionAmbientStarfield: View {
    let score: Double
    let stateColor: Color

    private var farSpeed: Double { score * 14.0 + 4.0 }
    private var nearSpeed: Double { score * 28.0 + 10.0 }
    private var farBase: CGFloat { 0.14 + CGFloat(score) * 0.08 }
    private var nearBase: CGFloat { 0.22 + CGFloat(score) * 0.10 }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, sz in
                let t = tl.date.timeIntervalSinceReferenceDate
                let farSpeeds: [Double] = [1.00, 0.60, 1.18, 0.78, 1.32, 0.52, 1.08, 0.88, 1.24, 0.70, 0.92, 1.40, 0.64, 1.16, 0.80, 1.28]
                let farYRat: [Double] = [0.04, 0.12, 0.21, 0.30, 0.39, 0.48, 0.55, 0.63, 0.71, 0.79, 0.87, 0.94, 0.09, 0.18, 0.43, 0.66]
                let farRadii: [CGFloat] = [0.55, 0.40, 0.65, 0.45, 0.70, 0.38, 0.58, 0.48, 0.62, 0.42, 0.52, 0.68, 0.44, 0.60, 0.50, 0.64]
                let farAlphas: [CGFloat] = [0.90, 0.65, 0.80, 0.58, 0.95, 0.50, 0.78, 0.62, 0.85, 0.55, 0.72, 0.88, 0.48, 0.76, 0.60, 0.82]
                let farTails: [Double] = [5, 3, 7, 4, 8, 3, 6, 4, 7, 3, 5, 8, 3, 6, 4, 7]

                let nearSpeeds: [Double] = [1.00, 0.72, 1.38, 0.84, 1.22, 0.64, 1.48, 0.90, 1.16, 0.78, 1.34, 1.06]
                let nearYRat: [Double] = [0.07, 0.24, 0.44, 0.61, 0.76, 0.92, 0.15, 0.34, 0.52, 0.68, 0.83, 0.97]
                let nearRadii: [CGFloat] = [1.4, 1.0, 1.6, 1.2, 1.8, 1.1, 1.5, 0.9, 1.3, 1.7, 1.0, 1.4]
                let nearAlphas: [CGFloat] = [1.00, 0.75, 0.90, 0.68, 0.95, 0.60, 0.85, 0.72, 0.80, 0.92, 0.65, 0.88]
                let nearTails: [Double] = [14, 9, 18, 11, 22, 8, 16, 10, 13, 20, 9, 15]

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

                for i in 0..<16 {
                    let spd = farSpeed * farSpeeds[i]
                    let tLen = CGFloat(farTails[i])
                    let x = sz.width - CGFloat((t * spd).truncatingRemainder(dividingBy: Double(sz.width) + Double(tLen) + 2))
                    let y = sz.height * CGFloat(farYRat[i])
                    let r = farRadii[i]
                    let a = farBase * farAlphas[i] * maskFade(x, y)
                    guard a > 0.003 else { continue }

                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(stateColor.opacity(Double(a))))
                    if tLen > 2 {
                        var tail = Path()
                        tail.move(to: CGPoint(x: x + r, y: y))
                        tail.addLine(to: CGPoint(x: x + r + tLen, y: y))
                        ctx.stroke(tail, with: .color(stateColor.opacity(Double(a * 0.22))), lineWidth: r * 0.50)
                    }
                }

                for i in 0..<12 {
                    let spd = nearSpeed * nearSpeeds[i]
                    let tLen = CGFloat(nearTails[i])
                    let x = sz.width - CGFloat((t * spd).truncatingRemainder(dividingBy: Double(sz.width) + Double(tLen) + 4))
                    let y = sz.height * CGFloat(nearYRat[i])
                    let r = nearRadii[i]
                    let a = nearBase * nearAlphas[i] * maskFade(x, y)
                    guard a > 0.004 else { continue }

                    ctx.fill(Path(ellipseIn: CGRect(x: x - r * 2.4, y: y - r * 2.4, width: r * 4.8, height: r * 4.8)), with: .color(stateColor.opacity(Double(a * 0.22))))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(stateColor.opacity(Double(a))))
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

// MARK: - LocalAIFeedbackData & Generator

private struct LocalAIFeedbackResult {
    let title: String
    let summary: String
    let analysis: String
    let recommendation: String
    let nextAction: String
    let caution: String
}

private enum LocalAIFeedbackGenerator {
    private enum HRTier { case calm, normal, elevated, high, veryHigh }

    private static func tier(_ hr: Double) -> HRTier {
        if hr < 1 { return .calm }
        if hr < 80 { return .calm }
        if hr < 100 { return .normal }
        if hr < 115 { return .elevated }
        if hr < 130 { return .high }
        return .veryHigh
    }

    static func generate(heartRate: Double, exercise: GuideExercise, scene: MeasurementScene) -> LocalAIFeedbackResult {
        let t = tier(heartRate)
        return LocalAIFeedbackResult(
            title: makeTitle(t, exercise),
            summary: makeSummary(t, exercise),
            analysis: makeAnalysis(t, scene),
            recommendation: makeRecommendation(exercise),
            nextAction: makeNextAction(t, scene),
            caution: "このフィードバックは医療的な診断ではなく、セルフケアの参考情報です。"
        )
    }

    private static func makeTitle(_ t: HRTier, _ e: GuideExercise) -> String {
        switch e {
        case .breathing478:
            switch t {
            case .calm: return "深い鎮静でリラックスを達成"
            case .normal: return "4-7-8呼吸で安定したリラックスを確認"
            case .elevated: return "興奮状態から4-7-8呼吸で回復を図りました"
            case .high: return "4-7-8呼吸で高緊張から鎮静モードへ移行"
            case .veryHigh: return "強い興奮状態に4-7-8呼吸で対処しました"
            }
        case .box:
            switch t {
            case .calm: return "安静時の集中呼吸でコンディション良好"
            case .normal: return "ボックス呼吸でリズムが整っています"
            case .elevated: return "ボックス呼吸で高まりを安定化させました"
            case .high: return "ボックス呼吸で高負荷を着実に乗り越え中"
            case .veryHigh: return "ボックス呼吸で緊張ピーク時のケアを実施"
            }
        case .breathing214:
            switch t {
            case .calm: return "穏やかな状態でリズムが整いました"
            case .normal: return "2-1-4呼吸で心身のバランスが良好"
            case .elevated: return "2-1-4呼吸で緊張の解放が進行しています"
            case .high: return "2-1-4呼吸で高緊張に積極的にアプローチ"
            case .veryHigh: return "強いストレスに2-1-4呼吸で緊急対応しました"
            }
        }
    }

    private static func makeSummary(_ t: HRTier, _ e: GuideExercise) -> String {
        let exName: String
        switch e {
        case .breathing478: exName = "4-7-8呼吸法"
        case .box: exName = "ボックス呼吸"
        case .breathing214: exName = "2-1-4呼吸"
        }
        switch t {
        case .calm: return "リラックスした状態で\(exName)を実践しました。呼吸が整っており、コンディションは良好です。"
        case .normal: return "安定したコンディションで\(exName)に取り組みました。継続的な実践が今後のパフォーマンス向上につながります。"
        case .elevated: return "やや活性化した状態で\(exName)に取り組みました。呼吸を重ねることで気持ちが整いやすくなります。"
        case .high: return "高まりが見られる状態で\(exName)に取り組みました。継続的なケアが気持ちの安定につながります。"
        case .veryHigh: return "強い緊張が見られた状況で\(exName)による緊急セルフケアを実施しました。継続した取り組みが重要です。"
        }
    }

    private static func makeAnalysis(_ t: HRTier, _ scene: MeasurementScene) -> String {
        let sceneDesc: String
        switch scene {
        case .interview: sceneDesc = "面接・プレゼン前"
        case .study: sceneDesc = "試験・勉強中"
        case .sports: sceneDesc = "試合・競技前"
        case .social: sceneDesc = "対人場面"
        case .daily: sceneDesc = "日常生活"
        case .other: sceneDesc = "日常場面"
        case .meeting: sceneDesc = "重要な会議前"
        case .speech: sceneDesc = "スピーチ前"
        }
        switch t {
        case .calm: return "\(sceneDesc)において、心身がリラックスした状態にあります。このコンディションを本番まで維持することが理想的です。"
        case .normal: return "\(sceneDesc)において、適度な集中状態が確認されています。緊張と緩和のバランスが取れており、パフォーマンスに適した状態です。"
        case .elevated: return "\(sceneDesc)において、やや興奮気味の反応が見られます。呼吸調整が奏功しており、安静方向への変化が期待されます。"
        case .high: return "\(sceneDesc)において、高めの緊張反応が観察されました。呼吸ガイドを継続することで、緊張の緩和をサポートできます。"
        case .veryHigh: return "\(sceneDesc)において、強い緊張反応が見られました。呼吸練習を積み重ねることで、今後の緊張マネジメントに役立てましょう。"
        }
    }

    private static func makeRecommendation(_ e: GuideExercise) -> String {
        switch e {
        case .breathing478:
            return "4-7-8呼吸はゆっくりした呼吸で吐く時間を長く取りやすく、深く落ち着きたいタイミングに向いています。就寝前や本番直前におすすめです。"
        case .box:
            return "ボックス呼吸は意識的な集中力を高め、ストレス反応を抑えます。重要な場面の直前に活用すると集中力の維持に役立ちます。"
        case .breathing214:
            return "2-1-4呼吸は短い吸気と長い呼気でリラックス効果を高めます。気持ちをすぐにリセットしたいときや、緊張を素早く和らげたいときに有効です。"
        }
    }

    private static func makeNextAction(_ t: HRTier, _ scene: MeasurementScene) -> String {
        let isCalm = (t == .calm || t == .normal)
        switch scene {
        case .interview, .meeting, .speech:
            return isCalm ? "現在の落ち着きを保ちながら、自信を持って本番に臨んでください。" : "もう1セット深呼吸を行い、心を整えてから本番に向かいましょう。"
        case .sports, .study:
            return isCalm ? "良いコンディションです。このまま軽くウォームアップを続けましょう。" : "緊張は集中力の源にもなります。呼吸を整えて、本番に集中してください。"
        case .social, .daily, .other:
            return isCalm ? "心身が整っています。この状態を意識しながら次の活動に移りましょう。" : "少し休憩を取り、引き続き呼吸ケアを続けてください。"
        }
    }
}

// MARK: - AI Feedback Card View

private struct AIFeedbackCardView: View {
    let result: LocalAIFeedbackResult
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(Color.cyan.opacity(0.42)).frame(height: 0.7)
                Text(" AI FEEDBACK ")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.72))
                    .tracking(3.2)
                    .fixedSize()
                    .padding(.vertical, 9)
                Rectangle().fill(Color.cyan.opacity(0.42)).frame(height: 0.7)
            }
            Text(result.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.93))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.6).padding(.horizontal, 16).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 12) {
                aiFeedbackRow(label: "SUMMARY", text: result.summary, color: .cyan)
                aiFeedbackRow(label: "ANALYSIS", text: result.analysis, color: Color(hue: 0.08, saturation: 0.72, brightness: 0.98))
                aiFeedbackRow(label: "RECOMMENDATION", text: result.recommendation, color: Color(hue: 0.48, saturation: 0.72, brightness: 0.90))
                aiFeedbackRow(label: "NEXT ACTION", text: result.nextAction, color: .cyan)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.6).padding(.horizontal, 16)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .padding(.top, 1)
                Text(result.caution)
                    .font(.system(size: 9.5, weight: .light))
                    .foregroundStyle(.white.opacity(0.30))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.01, green: 0.04, blue: 0.14).opacity(0.97))
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.cyan.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom).frame(height: 22)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cyan.opacity(0.28), lineWidth: 0.8)
            }
        )
        .shadow(color: Color.cyan.opacity(0.12), radius: 18)
    }
}

private func aiFeedbackRow(label: String, text: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundStyle(color.opacity(0.62))
            .tracking(2.2)
        Text(text)
            .font(.system(size: 12, weight: .light))
            .foregroundStyle(.white.opacity(0.80))
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2.5)
    }
}

// MARK: - Self Report Picker View

private struct SelfReportPickerView: View {
    @Binding var selection: SelfReportLevel?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
                Text(" 体感入力（任意） ")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .tracking(1.8)
                    .fixedSize()
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
            }
            HStack(spacing: 6) {
                ForEach(SelfReportLevel.allCases) { level in
                    let isSelected = selection == level
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            selection = isSelected ? nil : level
                        }
                    } label: {
                        Text(level.shortLabel)
                            .font(.system(size: 9, weight: isSelected ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(isSelected ? .black : level.accentColor.opacity(0.65))
                            .tracking(0.8)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(isSelected ? level.accentColor.opacity(0.88) : Color.white.opacity(0.05))
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(isSelected ? level.accentColor : level.accentColor.opacity(0.22), lineWidth: isSelected ? 1.2 : 0.7)
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.14), value: isSelected)
                }
            }
            if let sel = selection {
                Text(sel.label)
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(sel.accentColor.opacity(0.65))
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Local MindWave AI Engine

enum LocalMindWaveAIEngine {
    static func generate(context ctx: MindWaveAIContext) -> MindWaveAIInsight {
        let tone = displayTone(for: ctx)
        return MindWaveAIInsight(
            title: makeTitle(ctx),
            summary: makeSituationText(ctx),
            analysis: makeChangeText(ctx),
            recommendation: makeRecommendation(ctx),
            nextAction: makeNextAction(ctx),
            caution: "このフィードバックは医療診断ではなく、セルフケアの参考情報です。",
            confidenceLabel: dataQualityLabel(ctx: ctx),
            displayTone: tone,
            shouldShowOnHome: false,
            shouldShowInSession: false,
            shouldShowInResult: true,
            shouldShowInHistory: true
        )
    
    }

    private static func displayTone(for ctx: MindWaveAIContext) -> AIDisplayTone {
        switch ctx.state {
        case .underAroused: return .calm
        case .optimalTension: return ctx.currentHeartRate < 105 ? .focus : .alert
        case .overTense: return .ovld
        }
    }

    private static func dataQualityLabel(ctx: MindWaveAIContext) -> String {
        var pts = 0
        if ctx.currentHeartRate > 0 { pts += 2 }
        if ctx.beforeHeartRate != nil { pts += 1 }
        if ctx.afterHeartRate != nil { pts += 1 }
        if ctx.selfReportBefore != nil { pts += 1 }
        if ctx.selfReportAfter != nil { pts += 1 }
        switch pts {
        case 6: return "データ充実"
        case 3, 4, 5: return "データ標準"
        default: return "データ限定"
        }
    }

    private static func makeTitle(_ ctx: MindWaveAIContext) -> String {
        switch ctx.breathingMethod {
        case .breathing478:
            switch ctx.state {
            case .underAroused: return "4-7-8呼吸: 落ち着いた状態で完了"
            case .optimalTension: return "4-7-8呼吸: 整えながら完了"
            case .overTense: return "4-7-8呼吸: 高まりの中でケアを実施"
            }
        case .box:
            switch ctx.state {
            case .underAroused: return "BOX呼吸: 安定したリズムで完了"
            case .optimalTension: return "BOX呼吸: バランス良く完了"
            case .overTense: return "BOX呼吸: 反応が高い中でケアを実施"
            }
        case .breathing214:
            switch ctx.state {
            case .underAroused: return "2-1-4呼吸: 穏やかな状態で完了"
            case .optimalTension: return "2-1-4呼吸: 緊張をほぐしながら完了"
            case .overTense: return "2-1-4呼吸: 強い高まりにケアを実施"
            }
        }
    }

    private static func makeSituationText(_ ctx: MindWaveAIContext) -> String {
        let selfPrefix = ctx.selfReportBefore.map { "体感「\($0.label)」でスタートし、" } ?? ""
        switch ctx.state {
        case .underAroused: return "\(selfPrefix)身体の反応は落ち着いた状態にあります。呼吸が整いやすい状況です。"
        case .optimalTension: return "\(selfPrefix)ほどよい反応レベルが確認されています。\(ctx.scene.displayName)に向いた状態に見えます。"
        case .overTense: return "\(selfPrefix)身体の反応がやや高まった状態です。引き続き呼吸ケアを続けると落ち着きやすくなる可能性があります。"
        }
    }

    private static func makeChangeText(_ ctx: MindWaveAIContext) -> String {
        guard let bhr = ctx.beforeHeartRate, let ahr = ctx.afterHeartRate, bhr > 0, ahr > 0 else {
            return beforeStateOnly(ctx)
        }
        let diff = ahr - bhr
        if diff < -4 {
            return "呼吸前と比べ、身体反応が落ち着く方向に変化しています。"
        } else if diff > 4 {
            return "呼吸後も身体反応がやや高めです。焦らず、吐く時間を長めに意識してみてください。"
        } else {
            return "呼吸前後で大きな変化はまだ見られません。継続的なケアが助けになることがあります。"
        }
    }

    private static func beforeStateOnly(_ ctx: MindWaveAIContext) -> String {
        switch ctx.beforeState ?? ctx.state {
        case .underAroused: return "呼吸前から落ち着いた状態でした。このコンディションを次の活動に活かせます。"
        case .optimalTension: return "呼吸前は程よい反応レベルでした。引き続きこの状態を意識してみてください。"
        case .overTense: return "呼吸前から反応が高めでした。呼吸ケアを続けると変化しやすくなることがあります。"
        }
    }

    private static func makeRecommendation(_ ctx: MindWaveAIContext) -> String {
        let stillTense: Bool
        switch ctx.selfReportAfter {
        case .strongTension, .significantTension: stillTense = true
        default: stillTense = false
        }
        let isCalm = !stillTense && (ctx.state == .underAroused || ctx.state == .optimalTension)
        if stillTense {
            switch ctx.breathingMethod {
            case .breathing478: return "体感がまだ高めです。もう1セット、7カウントの息止めを抜いてゆっくり吐くだけ試してみましょう。"
            case .box: return "体感がまだ高めです。BOX呼吸のペースを少しゆっくりにして、吐く時間を意識するともう少し楽になることがあります。"
            case .breathing214: return "体感がまだ高めです。吐く（4カウント）を2〜3回だけ繰り返してみましょう。"
            }
        }
        switch ctx.scene {
        case .interview, .meeting, .speech:
            return isCalm ? "落ち着いた状態が続いています。このまま本番に向かいましょう。" : "もう1セット、ゆっくり息を吐く呼吸を続けてみましょう。"
        case .sports:
            return isCalm ? "身体の準備が整いやすい状態です。軽いウォームアップへ移りましょう。" : "高まりを感じているときは、吐く息を少し長めにすると落ち着きやすくなります。"
        case .study:
            return isCalm ? "集中しやすい状態です。短い休憩を入れてから学習を始めましょう。" : "焦らず、呼吸をゆっくり続けながら取り組んでみましょう。"
        case .social:
            return isCalm ? "気持ちが整った状態です。自然体でいきましょう。" : "ゆっくりとした呼吸を続けながら、状況に慣れていきましょう。"
        case .daily, .other:
            return isCalm ? "整った状態です。この感覚を次の活動に持っていきましょう。" : "少し休憩を取りながら、呼吸ケアを続けてみましょう。"
        }
    }

    private static func makeNextAction(_ ctx: MindWaveAIContext) -> String {
        switch ctx.selfReportAfter {
        case .strongTension, .significantTension:
            return "体感が高いまま終わっても問題ありません。記録が積み上がると次回の提案に反映されます"
        case .calm, .slightTension:
            return "呼吸後の体感も良好です。このデータが傾向の学習に役立ちます"
        case nil:
            switch ctx.state {
            case .underAroused: return "この状態をキープ。5分後に気分を確認してみましょう"
            case .optimalTension: return "そのまま次の活動へ。気になるときは短い呼吸ケアを挟みましょう"
            case .overTense: return "2-1-4呼吸を1セット追加し、もう一度気持ちを確かめましょう"
            }
        }
    }
}

// MARK: - AI Debrief Card

private struct AIDebriefCard: View {
    let insight: MindWaveAIInsight
    let selfReportBefore: SelfReportLevel?
    let selfReportAfter: SelfReportLevel?
    private var accentColor: Color { insight.displayTone.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(accentColor.opacity(0.38)).frame(height: 0.8)
                Text(" AI DEBRIEF ")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor.opacity(0.78))
                    .tracking(3.0)
                    .fixedSize()
                    .padding(.vertical, 10)
                Rectangle().fill(accentColor.opacity(0.38)).frame(height: 0.8)
            }
            Text(insight.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(LinearGradient(colors: [accentColor.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 14) {
                debriefRow(label: "状況", text: insight.summary, color: accentColor)
                debriefRow(label: "変化", text: insight.analysis, color: insight.displayTone == .calm ? Color(hue: 0.48, saturation: 0.70, brightness: 0.88) : accentColor.opacity(0.85))
                if selfReportBefore != nil || selfReportAfter != nil {
                    debriefRow(label: "体感", text: makeSelfReportText(), color: Color.white.opacity(0.55))
                }
                debriefRow(label: "おすすめ", text: insight.recommendation, color: accentColor)
                debriefRow(label: "次のアクション", text: insight.nextAction, color: accentColor.opacity(0.72))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5).padding(.horizontal, 16)
            let hasReport = selfReportBefore != nil || selfReportAfter != nil
            HStack(spacing: 5) {
                Image(systemName: hasReport ? "arrow.up.doc.on.clipboard" : "doc.on.clipboard")
                    .font(.system(size: 7))
                    .foregroundStyle(hasReport ? accentColor.opacity(0.55) : Color.white.opacity(0.18))
                Text(hasReport ? "LEARNING SIGNAL — 体感データが記録されました" : "LEARNING SIGNAL — 保存時に学習データとして記録されます")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(hasReport ? accentColor.opacity(0.45) : Color.white.opacity(0.18))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.white.opacity(0.22))
                    Text("LOCAL AI")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.28))
                        .tracking(1.0)
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.03)).overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)))

                HStack(spacing: 3) {
                    Circle().fill(accentColor.opacity(0.55)).frame(width: 4, height: 4)
                    Text(insight.confidenceLabel)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.55))
                        .tracking(0.8)
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Capsule().fill(accentColor.opacity(0.05)).overlay(Capsule().strokeBorder(accentColor.opacity(0.18), lineWidth: 0.6)))

                Spacer()
                Text(insight.caution)
                    .font(.system(size: 7.5, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.01, green: 0.03, blue: 0.12).opacity(0.97))
                VStack(spacing: 0) {
                    LinearGradient(colors: [accentColor.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom).frame(height: 30)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                RoundedRectangle(cornerRadius: 14).strokeBorder(accentColor.opacity(0.30), lineWidth: 0.9)
                RoundedRectangle(cornerRadius: 14).stroke(accentColor.opacity(0.12), lineWidth: 6).blur(radius: 6)
            }
        )
        .shadow(color: accentColor.opacity(0.10), radius: 16)
    }

    private func debriefRow(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.60))
                .tracking(2.0)
            Text(text)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2.5)
        }
    }

    private func makeSelfReportText() -> String {
        switch (selfReportBefore, selfReportAfter) {
        case (.strongTension, .calm), (.significantTension, .calm): return "体感としても落ち着きが感じられています。"
        case (.strongTension, .slightTension), (.significantTension, .slightTension): return "体感の高まりが和らいでいます。引き続き呼吸を続けましょう。"
        case (.calm, .calm): return "はじめから落ち着いた体感でした。"
        case (_, .strongTension), (_, .significantTension): return "まだ体感が高めです。吐く呼吸を意識してもう少し続けてみましょう。"
        case let (b, nil) where b != nil: return "呼吸前: \(b!.label)。呼吸後の体感を入力するとより参考になります。"
        default: return "体感を入力すると、次回のケアの参考にできます。"
        }
    }
}

// MARK: - Self Report After View

private struct SelfReportAfterView: View {
    @Binding var selection: SelfReportLevel?
    var onChanged: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                Text(" 呼吸後の体感（任意） ")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .tracking(1.6)
                    .fixedSize()
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            }
            HStack(spacing: 6) {
                ForEach(SelfReportLevel.allCases) { level in
                    let isSelected = selection == level
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            selection = isSelected ? nil : level
                            onChanged?()
                        }
                    } label: {
                        Text(level.shortLabel)
                            .font(.system(size: 9, weight: isSelected ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(isSelected ? .black : level.accentColor.opacity(0.58))
                            .tracking(0.6)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(isSelected ? level.accentColor.opacity(0.85) : Color.white.opacity(0.04))
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(isSelected ? level.accentColor : level.accentColor.opacity(0.18), lineWidth: isSelected ? 1.0 : 0.6)
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.14), value: isSelected)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("GuideFlow") {
    GuideFlowView(selectedTab: .constant(1))
        .environmentObject(MindWaveViewModel())
        .environmentObject(GuideHistoryStore())
        .environmentObject(AppFlowState())
}
