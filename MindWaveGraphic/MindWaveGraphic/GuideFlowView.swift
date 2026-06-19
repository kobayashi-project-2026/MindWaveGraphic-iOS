//
//  GuideFlowView.swift
//  MindWaveGraphic
//
//  ガイドフローの全体を管理するコーディネーターView。
//  GuideViewからfullScreenCoverで開かれる。
//
//  参考コードから採用したもの：
//    - シーン選択 → ガイド選択 → セッション → 再測定 → 結果 → 保存 という遷移の考え方
//
//  参考コードから採用しなかったもの：
//    - ランダム生成BPM・架空の改善結果・ダミー演出
//    - 文字列ベースの状態管理（currentStep: Int, currentMode: String）
//    - ログイン遷移・認証ロジック
//    - 架空のクラウド同期
//
//  実データポリシー：
//    - ガイド前後の値はMindWaveViewModelから読み取り（書き込みなし）
//    - HRVは新規サンプルが生成される保証がないため、更新されなかった場合は明示する
//    - MockモードON中の記録はisMockData=trueとして区別する
//    - 保存はユーザーが「履歴へ保存」を選択したときだけ行う
//

import SwiftUI
import Combine

/// ガイドフロー全体のコーディネーター。
/// RegulationFlowStep を @State で管理し、各ステップを ZStack で切り替える。
/// ViewModelは読み取り専用で参照する（書き込みなし）。
struct GuideFlowView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var historyStore: GuideHistoryStore
    /// 結果保存後にHistoryタブへ移動するためのバインディング
    @Binding var selectedTab: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Flow State

    @State private var step: RegulationFlowStep = .sceneSelection
    @State private var selectedScene: MeasurementScene? = nil
    @State private var selectedExercise: GuideExercise? = nil
    @State private var sessionDurationSeconds: Int = 60
    @State private var beforeSnapshot: GuideSnapshot? = nil
    @State private var afterSnapshot: GuideSnapshot? = nil
    @State private var showAbandonAlert = false
    @State private var hrvUpdatedDuringSession = false

    // Session step (inline session state)
    @State private var sessionElapsed: Int = 0
    @State private var sessionIsRunning: Bool = false
    @State private var sessionIsFinished: Bool = false
    @State private var sessionMove: Bool = false   // FlowGuideVisual用
    @State private var sessionAnimate: Bool = false // RippleGuideVisual用

    // Remeasurement step
    @State private var remeasurementElapsed: Int = 0
    @State private var remeasurementCompleted: Bool = false
    @State private var remeasurementStartCount: Int = 0   // watchMessageCount at session end
    @State private var remeasurementStartHRVDate: Date? = nil

    // Timer for session countdown and remeasurement polling
    private let flowTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Body

    var body: some View {
        ZStack {
            flowBackground

            VStack(spacing: 0) {
                // 上部バー（閉じるボタン）
                flowTopBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // ステップコンテンツ
                Group {
                    switch step {
                    case .sceneSelection:
                        sceneSelectionContent
                            .transition(stepTransition(insertion: .trailing))
                    case .exerciseSelection:
                        exerciseSelectionContent
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
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.32), value: step)
            }
        }
        .onReceive(flowTimer) { _ in
            tickTimer()
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
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.03, green: 0.08, blue: 0.18),
                Color.cyan.opacity(0.14)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var flowTopBar: some View {
        HStack {
            Button {
                showAbandonAlert = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.50))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("フローを中断する")

            Spacer()

            Text(topBarTitle)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.white.opacity(0.65))
                .tracking(0.5)

            Spacer()

            // バランス用スペーサー
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.clear)
        }
    }

    private var topBarTitle: String {
        switch step {
        case .sceneSelection:   return "シーンを選ぶ"
        case .exerciseSelection: return "ガイドを選ぶ"
        case .session:           return "ガイド中"
        case .remeasurement:     return "再測定"
        case .result:            return "計測結果"
        }
    }

    // MARK: - Transition

    private func stepTransition(insertion: Edge) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: insertion)),
            removal:   .opacity.combined(with: .move(edge: .leading))
        )
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
                    // セッション終了後1.5秒で再測定へ自動進行
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

        default:
            break
        }
    }

    // MARK: - Before Snapshot

    private func captureBeforeSnapshot() -> GuideSnapshot {
        GuideSnapshot(
            timestamp:          Date(),
            score:              viewModel.graphicInput.score,
            confidence:         viewModel.graphicInput.confidence,
            state:              viewModel.graphicInput.state,
            heartRate:          viewModel.latestWatchHeartRate ?? (viewModel.didFetchHeartRate ? viewModel.currentHeartRate : nil),
            hrv:                viewModel.didFetchHRV ? viewModel.currentHRV : nil,
            isMockData:         viewModel.isMockMode,
            heartRateSampleDate: viewModel.latestHeartRateSampleDate,
            hrvSampleDate:       viewModel.latestHRVSampleDate
        )
    }

    // MARK: - Remeasurement

    private func startRemeasurement() {
        remeasurementStartCount   = viewModel.watchMessageCount
        remeasurementStartHRVDate = viewModel.latestHRVSampleDate
        remeasurementElapsed      = 0
        remeasurementCompleted    = false
        step = .remeasurement
        MindWaveDebugLogger.log(.flow, "remeasurement started watchCount=\(remeasurementStartCount)")
    }

    private func completeRemeasurement() {
        guard !remeasurementCompleted else { return }
        remeasurementCompleted = true

        // HRV更新チェック：HRVサンプル日時が変わっていたら更新あり
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

        let samples = viewModel.watchMessageCount - remeasurementStartCount
        MindWaveDebugLogger.log(.flow, "remeasurement completed samples=\(samples) hrv=\(hrvUpdatedDuringSession ? "updated" : "unchanged")")
        step = .result
        MindWaveDebugLogger.log(.flow, "result presented")
    }

    // MARK: - ▼ STEP 1: Scene Selection

    private var sceneSelectionContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Text("今の状況を教えてください")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 16)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(MeasurementScene.allCases) { scene in
                        SceneButton(
                            scene: scene,
                            isSelected: selectedScene == scene
                        ) {
                            selectedScene = scene
                            MindWaveDebugLogger.log(.flow, "scene selected scene=\(scene.rawValue)")
                        }
                    }
                }

                // 次へ
                Button {
                    step = .exerciseSelection
                } label: {
                    Text("次へ")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selectedScene != nil ? .black : .white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedScene != nil ? Color.cyan.opacity(0.85) : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(selectedScene == nil)
                .accessibilityLabel("次のステップへ進む")
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - ▼ STEP 2: Exercise Selection

    private var exerciseSelectionContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // おすすめ表示
                if let scene = selectedScene {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.cyan.opacity(0.7))
                        Text("\(scene.displayName) には \(scene.recommendedExercise.title) がおすすめです")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 12)
                }

                Text("ガイドを選んでください")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))

                ForEach(GuideExercise.allCases) { exercise in
                    let isRecommended = selectedScene?.recommendedExercise == exercise
                    ExerciseSelectionCard(
                        exercise: exercise,
                        isSelected: selectedExercise == exercise,
                        isRecommended: isRecommended
                    ) {
                        selectedExercise = exercise
                        MindWaveDebugLogger.log(.flow, "exercise selected exercise=\(exercise.rawValue)")
                    }
                }

                // 戻る + 次へ
                HStack(spacing: 12) {
                    Button {
                        step = .sceneSelection
                    } label: {
                        Text("戻る")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("シーン選択へ戻る")

                    Button {
                        startSession()
                    } label: {
                        Text("次へ")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selectedExercise != nil ? .black : .white.opacity(0.35))
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedExercise != nil ? Color.cyan.opacity(0.85) : Color.white.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedExercise == nil)
                    .accessibilityLabel("ガイドセッションを開始する")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func startSession() {
        beforeSnapshot = captureBeforeSnapshot()
        sessionElapsed     = sessionDurationSeconds
        sessionIsRunning   = false
        sessionIsFinished  = false
        sessionMove        = false
        sessionAnimate     = false
        step = .session
        MindWaveDebugLogger.log(.flow, "session started duration=\(sessionDurationSeconds) exercise=\(selectedExercise?.rawValue ?? "?")")
    }

    // MARK: - ▼ STEP 3: Session (インラインセッション、GuideRelaxationVisualsを使用)

    private var sessionContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // ビジュアル
            ZStack {
                if selectedExercise == .ripple {
                    RippleGuideVisual()
                } else {
                    FlowGuideVisual()
                }
                // 呼吸案内（Rippleのみ、実行中）
                if selectedExercise == .ripple && sessionIsRunning {
                    let phaseText = ((sessionDurationSeconds - sessionElapsed) % 8) < 4 ? "ゆっくり吸う" : "静かに吐く"
                    Text(phaseText)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                        .offset(y: 148)
                        .animation(.easeInOut(duration: 0.6), value: phaseText)
                }
            }
            .frame(height: 260)

            Spacer()

            // 終了表示
            if sessionIsFinished {
                Text("セッション終了")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 8)
                Text("再測定へ移行しています…")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // 残り時間
            Text(sessionTimeString)
                .font(.system(size: 48, weight: .thin, design: .rounded))
                .foregroundStyle(.white.opacity(sessionIsFinished ? 0.35 : 0.88))
                .monospacedDigit()
                .contentTransition(.numericText())

            // 時間選択（未開始時）
            if !sessionIsRunning && !sessionIsFinished {
                sessionDurationPicker
                    .padding(.vertical, 12)
            }

            // 開始/停止ボタン（終了時は非表示）
            if !sessionIsFinished {
                sessionControlButton
                    .padding(.horizontal, 20)
            }

            Spacer(minLength: 40)
        }
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
                    sessionElapsed         = opt.seconds
                } label: {
                    Text(opt.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(sessionDurationSeconds == opt.seconds ? .black : .white.opacity(0.55))
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(sessionDurationSeconds == opt.seconds ? Color.cyan.opacity(0.80) : Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(opt.label)を選択")
            }
        }
    }

    /// 型推論タイムアウトを避けるため複雑なテナリーを分離
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
        Button {
            sessionIsRunning.toggle()
        } label: {
            sessionControlLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sessionIsRunning ? "停止する" : "開始する")
    }

    // MARK: - ▼ STEP 4: Remeasurement

    private var remeasurementContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "applewatch.watchface")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.cyan.opacity(0.6))

            Text("再測定中")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.85))

            Text("Apple Watchから新しい心拍を受信しています")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.white.opacity(0.50))
                .multilineTextAlignment(.center)

            // 受信状況
            VStack(spacing: 8) {
                let newSamples = viewModel.watchMessageCount - remeasurementStartCount
                let targetSamples = GuideFlowConstants.minWatchSamplesForRemeasurement

                HStack(spacing: 6) {
                    Text("受信件数")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.40))
                    Text("\(newSamples) / \(targetSamples)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(newSamples >= targetSamples ? Color.cyan.opacity(0.9) : .white.opacity(0.65))
                }

                if let hr = viewModel.latestWatchHeartRate {
                    HStack(spacing: 6) {
                        Text("最新心拍")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.40))
                        Text(String(format: "%.0f bpm", hr))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                Text("最大 \(GuideFlowConstants.maxRemeasurementSeconds - remeasurementElapsed) 秒で自動完了")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.30))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

            // 手動完了ボタン
            Button {
                completeRemeasurement()
            } label: {
                Text("今の値で結果を見る")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("現在の値で結果画面へ進む")

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - ▼ STEP 5: Result

    private var resultContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                Text("計測結果")
                    .font(.system(size: 22, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(2)
                    .padding(.top, 12)

                if let before = beforeSnapshot, let after = afterSnapshot {
                    ResultComparisonCard(before: before, after: after, hrvUpdated: hrvUpdatedDuringSession)
                }

                // 注意書き
                Text("これは医療診断ではありません。\n数値は計測環境により変動します。")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)

                // アクションボタン群
                VStack(spacing: 10) {
                    // 履歴へ保存
                    Button {
                        saveAndNavigateToHistory()
                    } label: {
                        Text("履歴へ保存")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.cyan.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("このセッションを履歴に保存する")

                    // 保存せずHomeへ
                    Button {
                        MindWaveDebugLogger.log(.flow, "result dismissed without saving")
                        dismiss()
                        Task { @MainActor in
                            selectedTab = 0
                        }
                    } label: {
                        Text("保存せずHomeへ戻る")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("保存せずホームへ戻る")

                    // もう一度
                    Button {
                        resetForNewSession()
                    } label: {
                        Text("もう一度実施する")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.cyan.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("同じシーンとガイドでもう一度行う")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func saveAndNavigateToHistory() {
        guard let before = beforeSnapshot,
              let scene = selectedScene,
              let exercise = selectedExercise else { return }

        let record = GuideSessionRecord(
            id:                  UUID(),
            startedAt:           before.timestamp,
            scene:               scene,
            exercise:            exercise,
            durationSeconds:     sessionDurationSeconds,
            before:              before,
            after:               afterSnapshot,
            hrvUpdated:          hrvUpdatedDuringSession
        )
        historyStore.add(record)
        dismiss()
        // dismiss完了後にタブ切替（fullScreenCoverのdismiss後に反映される）
        Task { @MainActor in
            selectedTab = 2
        }
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
        MindWaveDebugLogger.log(.flow, "session restarted exercise=\(selectedExercise?.rawValue ?? "?")")
    }
}

// MARK: - SceneButton

private struct SceneButton: View {
    let scene: MeasurementScene
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: scene.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(isSelected ? .black : Color.cyan.opacity(0.75))
                Text(scene.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.cyan.opacity(0.85) : Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scene.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - ExerciseSelectionCard

private struct ExerciseSelectionCard: View {
    let exercise: GuideExercise
    let isSelected: Bool
    let isRecommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.cyan.opacity(0.25) : Color.cyan.opacity(0.10))
                        .frame(width: 46, height: 46)
                    Image(systemName: exercise.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.cyan.opacity(0.9))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(exercise.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.90))
                        if isRecommended {
                            Text("おすすめ")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.cyan.opacity(0.8))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.cyan.opacity(0.15)))
                        }
                    }
                    Text(exercise.description)
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.cyan.opacity(0.9) : .white.opacity(0.25))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.cyan.opacity(0.10) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.cyan.opacity(0.40) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(exercise.title)\(isRecommended ? "（おすすめ）" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - ResultComparisonCard

private struct ResultComparisonCard: View {
    let before: GuideSnapshot
    let after: GuideSnapshot
    let hrvUpdated: Bool

    private var scoreDelta: Double { after.score - before.score }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                snapshotColumn("ガイド前", snap: before)
                Divider().background(.white.opacity(0.12)).frame(width: 1)
                snapshotColumn("ガイド後", snap: after)
            }

            Divider().background(.white.opacity(0.08))

            // 変化量
            HStack(spacing: 6) {
                Text("スコア変化")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.40))
                Text(String(format: "%+.1f", scoreDelta))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(scoreDelta < 0 ? Color.cyan.opacity(0.9) : scoreDelta > 0 ? Color.orange.opacity(0.8) : .white.opacity(0.6))
            }

            // HRV更新状態
            HStack(spacing: 5) {
                Image(systemName: hrvUpdated ? "checkmark.circle.fill" : "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(hrvUpdated ? Color.cyan.opacity(0.7) : .white.opacity(0.25))
                Text(hrvUpdated ? "HRVが更新されました" : "HRVは今回更新されませんでした")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.40))
            }

            if before.isMockData || after.isMockData {
                Text("⚠ Mockモード中のデータを含みます")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange.opacity(0.65))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func snapshotColumn(_ label: String, snap: GuideSnapshot) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.40))
                .tracking(0.5)
            Text(String(format: "%.0f", snap.score))
                .font(.system(size: 36, weight: .thin, design: .rounded))
                .foregroundStyle(MindWaveTheme.stressColor(score: snap.score))
            Text(snap.state.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MindWaveTheme.stressColor(score: snap.score).opacity(0.8))
            if let hr = snap.heartRate {
                Text(String(format: "%.0f bpm", hr))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview("SceneSelection") {
    GuideFlowView(selectedTab: .constant(1))
        .environmentObject(MindWaveViewModel())
        .environmentObject(GuideHistoryStore())
}
