//
//  LiveWaveView.swift
//  MindWaveGraphic
//

import SwiftUI
import Combine

struct LiveWaveView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @State private var elapsed: Int       = 0
    @State private var showDebug          = false
    @State private var demoScenarioIndex  = 0

    // displayedScore: graphicInput.score を滑らかに補間するUI表示用スコア。
    // スコアが急変しても数値・色が跳ばないように 1.5秒でアニメーションする。
    @State private var displayedScore: Double = 50

    // LIVEドットの点滅用
    @State private var liveDotVisible: Bool = true

    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let blinkTimer   = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    private var stressColor: Color  { MindWaveTheme.stressColor(score: displayedScore) }
    private var stressLabel: String { MindWaveTheme.stressLabel(score: displayedScore) }

    var body: some View {
        ZStack {
            MindWaveTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                statusSubtitle.padding(.bottom, 4)

                // ── グラフィック差し込み口 ────────────────────────────
                // GraphicPlugin.swift の登録1行を変えるだけで差し替えられる。
                // GraphicHostView はデータ取得・スコア計算を行わない。
                GraphicHostView(input: viewModel.graphicInput)
                    .frame(height: 150)
                    .onChange(of: viewModel.graphicInput.score) { _, newScore in
                        withAnimation(.easeInOut(duration: 1.5)) {
                            displayedScore = newScore
                        }
                    }

                Spacer(minLength: 8)

                scoreCard.padding(.horizontal, 20)

                liveControlBar.padding(.top, 8)

                Spacer(minLength: 4)

                debugSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            displayedScore = viewModel.graphicInput.score
        }
        .onReceive(sessionTimer) { _ in elapsed += 1 }
        .onReceive(blinkTimer) { _ in
            if viewModel.isLiveMonitoring { liveDotVisible.toggle() }
            else { liveDotVisible = true }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mind Wave")
                    .font(.system(size: 18, weight: .ultraLight))
                    .foregroundStyle(MindWaveTheme.textPrimary)
                    .tracking(2)
                Text(timeString)
                    .font(.system(size: 12, weight: .light, design: .monospaced))
                    .foregroundStyle(MindWaveTheme.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isLiveMonitoring ? MindWaveTheme.accent : MindWaveTheme.textTertiary)
                    .opacity(viewModel.isLiveMonitoring ? (liveDotVisible ? 1.0 : 0.25) : 0.4)
                    .frame(width: 7, height: 7)
                    .shadow(color: viewModel.isLiveMonitoring ? MindWaveTheme.accent.opacity(0.9) : .clear,
                            radius: 5)
                Text("LIVE")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(viewModel.isLiveMonitoring ? MindWaveTheme.accent : MindWaveTheme.textTertiary)
                    .tracking(1.5)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var timeString: String {
        String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    // MARK: - Status Subtitle

    private var statusSubtitle: some View {
        Text("Mind Waveが心拍とHRVの変化をもとに推定しています")
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(MindWaveTheme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
    }

    // MARK: - Score Card

    private var scoreCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("緊張不安定度")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .tracking(0.5)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.0f", displayedScore))
                            .font(.system(size: 50, weight: .thin, design: .rounded))
                            .foregroundStyle(stressColor)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.4), value: displayedScore)
                        Text("/ 100")
                            .font(.caption)
                            .foregroundStyle(MindWaveTheme.textTertiary)
                            .padding(.bottom, 8)
                    }
                    Text(stressLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(stressColor)
                        .animation(.easeInOut(duration: 0.3), value: displayedScore)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    miniMetric(label: "心拍数",
                               value: String(format: "%.0f", viewModel.currentHeartRate),
                               unit: "bpm",
                               isNew: viewModel.isNewHeartRateSample)
                    miniMetric(label: "HRV（SDNN）",
                               value: viewModel.didFetchHRV
                                   ? String(format: "%.0f", viewModel.currentHRV)
                                   : "---",
                               unit: viewModel.didFetchHRV ? "ms" : "",
                               isNew: viewModel.isNewHRVSample && viewModel.didFetchHRV)
                }
                .padding(.top, 4)
            }

            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 0) {
                rateCell(label: "心拍上昇率", value: viewModel.stressResult.heartRateIncreaseRate)
                Spacer()
                rateCell(label: "HRV低下率", value: viewModel.stressResult.hrvDecreaseRate, alignTrailing: true)
            }
        }
        .padding(16)
        .darkCard()
    }

    private func miniMetric(label: String, value: String, unit: String, isNew: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 3) {
                if isNew {
                    Circle()
                        .fill(MindWaveTheme.accent)
                        .frame(width: 4, height: 4)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                    .tracking(0.3)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(MindWaveTheme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.8), value: displayedScore)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(MindWaveTheme.textSecondary)
            }
        }
    }

    private func rateCell(label: String, value: Double, alignTrailing: Bool = false) -> some View {
        VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
                .tracking(0.3)
            Text(String(format: "%+.1f%%", value * 100))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(value > 0
                                 ? Color(red: 0.90, green: 0.40, blue: 0.40)
                                 : MindWaveTheme.accent)
                .animation(.easeInOut(duration: 0.5), value: displayedScore)
        }
    }

    // MARK: - ライブ制御バー

    private var liveControlBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: viewModel.isMockMode ? "sparkles" : "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                Text(viewModel.dataSourceLabel)
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(MindWaveTheme.textTertiary)
            }
            Spacer()
            Button {
                viewModel.toggleLiveMonitoring()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.isLiveMonitoring ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 12))
                    Text(viewModel.isLiveMonitoring ? "取得停止" : "ライブ取得開始")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(viewModel.isLiveMonitoring ? Color.orange.opacity(0.8) : MindWaveTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(viewModel.isLiveMonitoring
                              ? Color.orange.opacity(0.12)
                              : MindWaveTheme.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Debug Section

    private var debugSection: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDebug.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .rotationEffect(.degrees(showDebug ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: showDebug)
                    Text("Debug")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(MindWaveTheme.textTertiary)
            }
            .buttonStyle(.plain)

            if showDebug {
                VStack(spacing: 6) {
                    // ── ビルド識別 ─────────────────────────────────────
                    debugBlock {
                        debugRow("Build", viewModel.debugBuildLabel)
                    }

                    // ── データソース仲裁 ────────────────────────────────
                    debugBlock {
                        debugRow("Active Source", viewModel.activeDataSource.rawValue)
                        debugRow("Graphic更新時刻", formatTime(viewModel.lastGraphicUpdateDate))
                        debugRow("Watch経過秒",
                                 viewModel.watchSampleAge.map { String(format: "%.0f秒", $0) } ?? "---")
                        debugRow("Watch鮮度",
                                 viewModel.watchSampleAge == nil ? "未受信"
                                 : viewModel.isWatchSampleFresh ? "Fresh ✓" : "Expired")
                        debugRow("Mock", viewModel.isMockMode ? "ON" : "OFF")
                    }

#if DEBUG
                    // ── Mockモード（DEBUGビルド限定） ───────────────────
                    mockControlSection
#endif

                    // ── GraphicInput（パイプライン出力） ────────────────
                    debugBlock {
                        debugRow("GraphicInput.score",
                                 String(format: "%.1f", viewModel.graphicInput.score))
                        debugRow("GraphicInput.confidence",
                                 String(format: "%.2f", viewModel.graphicInput.confidence))
                        debugRow("GraphicInput.state",
                                 viewModel.graphicInput.state.displayName)
                    }

                    // ── Watch ライブ心拍 ────────────────────────────────
                    debugBlock {
                        debugRow("Watch心拍",  viewModel.latestWatchHeartRate != nil
                                              ? String(format: "%.0f bpm", viewModel.latestWatchHeartRate!)
                                              : "未受信")
                        debugRow("Watch受信数", "\(viewModel.watchMessageCount) 回")
                        debugRow("Watch最終",   formatTime(viewModel.latestWatchHeartRateDate))
                        debugRow("WCSession",   WatchConnectivityManager.shared.watchConnectionStatusLabel)
                    }

                    // ── ライブ監視状態 ──────────────────────────────────
                    debugBlock {
                        debugRow("監視状態",  viewModel.liveMonitoringMessage)
                        debugRow("更新回数",  "\(viewModel.liveUpdateCount) 回")
                        debugRow("取得間隔",  "\(Int(viewModel.liveUpdateInterval)) 秒")
                        debugRow("最終取得",  formatTime(viewModel.lastLiveUpdateDate))
                    }

                    // ── 心拍・HRVサンプル ───────────────────────────────
                    debugBlock {
                        debugRow("心拍数", viewModel.didFetchHeartRate
                                 ? String(format: "%.0f bpm", viewModel.currentHeartRate)
                                 : "未取得")
                        debugRow("心拍サンプル時刻", formatTime(viewModel.latestHeartRateSampleDate))
                        debugRow("心拍サンプル更新", viewModel.isNewHeartRateSample ? "新規 ✓" : "同じ")
                        debugRow("同じサンプル継続",  "\(viewModel.sameSampleCount) 回")
                        debugRow("HRV（SDNN）", viewModel.didFetchHRV
                                 ? String(format: "%.0f ms", viewModel.currentHRV)
                                 : "未取得")
                        debugRow("HRVサンプル時刻",  formatTime(viewModel.latestHRVSampleDate))
                        debugRow("HRVサンプル更新",  viewModel.isNewHRVSample ? "新規 ✓" : "同じ")
                    }

                    // ── HRV Observer ──────────────────────────────────
                    debugBlock {
                        debugRow("HRV監視",     viewModel.isHRVObserverActive ? "稼働中 ●" : "停止中")
                        debugRow("HRV実測取得", viewModel.didFetchHRV ? "済 ✓" : "未取得")
                        debugRow("HRV取得元",   viewModel.lastHRVFetchSource)
                        debugRow("HRV新規受信", "\(viewModel.hrvObserverUpdateCount) 回")
                        debugRow("HRV最終通知", formatTime(viewModel.lastHRVObserverDate))
                        debugRow("HRV経過",     hrvAgeString(viewModel.latestHRVSampleDate))
                        debugRow("Graphic更新契機", viewModel.lastGraphicUpdateTrigger)
                    }

                    // ── スコア ─────────────────────────────────────────
                    debugBlock {
                        debugRow("スコア（計算値）", String(format: "%.1f", viewModel.stressResult.stressScore))
                        debugRow("スコア（表示値）", String(format: "%.1f", displayedScore))
                        debugRow("livePulseTrigger", "\(viewModel.livePulseTrigger)")
                        debugRow("データ元",          viewModel.dataSourceLabel)
                        debugRow("メッセージ",         viewModel.lastFetchMessage)
                    }

                    // ── サンプリング注記 ────────────────────────────────
                    Text(viewModel.healthKitSamplingNote)
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // ── デモシナリオ切り替え ─────────────────────────────
                    Text("デモシナリオ（StressScoreCalculator経由）")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        ForEach(MindSampleScenario.allScenarios.indices, id: \.self) { i in
                            let isSelected = demoScenarioIndex == i
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    demoScenarioIndex = i
                                    viewModel.loadDemoScenario(index: i)
                                }
                            } label: {
                                Text(MindSampleScenario.allScenarios[i].name)
                                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                                    .foregroundStyle(isSelected ? Color.black : MindWaveTheme.textTertiary)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected
                                                  ? MindWaveTheme.accent.opacity(0.7)
                                                  : Color.white.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Mock Control Section（DEBUGビルド限定）

    private var mockControlSection: some View {
        VStack(spacing: 6) {
            // ヘッダー行
            HStack {
                Text("Mockモード")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.isMockMode },
                    set: { viewModel.setMockMode($0) }
                ))
                .labelsHidden()
                .scaleEffect(0.7)
                .tint(MindWaveTheme.accent)
            }

            if viewModel.isMockMode {
                // 3状態ボタン
                HStack(spacing: 4) {
                    ForEach(MindState.allCases, id: \.self) { state in
                        let scores: [MindState: Double] = [
                            .underAroused: 15, .optimalTension: 50, .overTense: 85
                        ]
                        let isSelected = viewModel.graphicInput.state == state
                        Button {
                            viewModel.mockScore = scores[state] ?? 50
                            viewModel.sendMockSample()
                        } label: {
                            Text(state.displayName)
                                .font(.system(size: 9, weight: isSelected ? .medium : .regular))
                                .foregroundStyle(isSelected ? Color.black : MindWaveTheme.textTertiary)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected
                                              ? MindWaveTheme.accent.opacity(0.7)
                                              : Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Score スライダー
                VStack(spacing: 2) {
                    HStack {
                        Text("Score")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                        Spacer()
                        Text(String(format: "%.0f", viewModel.mockScore))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MindWaveTheme.textSecondary)
                    }
                    Slider(value: Binding(
                        get: { viewModel.mockScore },
                        set: { viewModel.mockScore = $0; viewModel.sendMockSample() }
                    ), in: 0...100)
                    .tint(MindWaveTheme.accent)
                }

                // Confidence スライダー
                VStack(spacing: 2) {
                    HStack {
                        Text("Confidence")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                        Spacer()
                        Text(String(format: "%.2f", viewModel.mockConfidence))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MindWaveTheme.textSecondary)
                    }
                    Slider(value: Binding(
                        get: { viewModel.mockConfidence },
                        set: { viewModel.mockConfidence = $0; viewModel.sendMockSample() }
                    ), in: 0...1)
                    .tint(MindWaveTheme.accent)
                }

                // 5秒ごと自動更新
                Button {
                    viewModel.toggleMockAutoUpdate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isMockAutoUpdate ? "stop.circle.fill" : "arrow.clockwise.circle")
                            .font(.system(size: 9))
                        Text(viewModel.isMockAutoUpdate ? "自動更新停止" : "5秒ごと自動更新")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(viewModel.isMockAutoUpdate ? Color.orange.opacity(0.8) : MindWaveTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(viewModel.isMockAutoUpdate
                                  ? Color.orange.opacity(0.10)
                                  : MindWaveTheme.accent.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(MindWaveTheme.accent.opacity(0.20), lineWidth: 1)
                )
        )
    }

    // MARK: - Debug Helpers

    private func debugBlock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 4) { content() }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
            )
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MindWaveTheme.textSecondary)
        }
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "---" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func hrvAgeString(_ date: Date?) -> String {
        guard let date else { return "---" }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        return minutes < 1 ? "1分未満" : "\(minutes)分"
    }
}

// MARK: - Wave Canvas（既存グラフィック実装、将来参照用に保持）

/// TimelineView(.animation) で 60fps 更新する3層波形。
/// GraphicHostViewへの移行後も削除せず保持する。
struct WaveCanvas: View {
    let amplitude: Double
    let speed: Double
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * speed
            Canvas { ctx, size in
                let w = size.width, h = size.height, mid = h * 0.52

                for layer in 0..<3 {
                    let lPhase   = phase + Double(layer) * 0.90
                    let lAmp     = amplitude * (1.0 - Double(layer) * 0.22) * h * 0.34
                    let lFreq    = 1.4 + Double(layer) * 0.35
                    let lOpacity = 0.75 - Double(layer) * 0.20
                    let lineW    = layer == 0 ? 1.8 : 1.2

                    var fill = Path()
                    fill.move(to: CGPoint(x: 0, y: h))
                    for x in stride(from: 0.0, through: w, by: 2.0) {
                        let y = mid + sin(x / w * .pi * 2 * lFreq + lPhase) * lAmp
                        fill.addLine(to: CGPoint(x: x, y: y))
                    }
                    fill.addLine(to: CGPoint(x: w, y: h))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .color(color.opacity(lOpacity * 0.11)))

                    var line = Path()
                    var first = true
                    for x in stride(from: 0.0, through: w, by: 2.0) {
                        let y = mid + sin(x / w * .pi * 2 * lFreq + lPhase) * lAmp
                        let pt = CGPoint(x: x, y: y)
                        if first { line.move(to: pt); first = false }
                        else { line.addLine(to: pt) }
                    }
                    ctx.stroke(line, with: .color(color.opacity(lOpacity * 0.55)), lineWidth: lineW)
                }
            }
        }
    }
}

#Preview {
    LiveWaveView()
        .environmentObject(MindWaveViewModel())
        .preferredColorScheme(.dark)
}
