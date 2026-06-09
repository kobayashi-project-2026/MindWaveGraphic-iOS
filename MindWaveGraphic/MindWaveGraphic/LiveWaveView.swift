//
//  LiveWaveView.swift
//  MindWaveGraphic
//

import SwiftUI
import Combine

// MARK: - Live Wave View

struct LiveWaveView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @State private var elapsed: Int = 0
    @State private var showDebug   = false
    @State private var demoScenarioIndex = 0

    // displayedScore: 実際のstressScoreを滑らかに補間したUI表示用スコア。
    // HealthKitの値が数秒おきに変化しても、波形が急に跳ぶのを防ぐ。
    // withAnimation(.easeInOut(duration: 1.5)) で緩やかに変化する。
    @State private var displayedScore: Double = 50

    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // displayedScore を使って波のパラメータを計算する。
    // viewModel.stressResult.stressScore が変化した時、displayedScore が追いかける。
    private var waveAmplitude: Double { 0.28 + (displayedScore / 100.0) * 0.44 }
    private var waveSpeed: Double     { 0.55 + (displayedScore / 100.0) * 0.55 }
    private var stressColor: Color    { MindWaveTheme.stressColor(score: displayedScore) }
    private var stressLabel: String   { MindWaveTheme.stressLabel(score: displayedScore) }

    var body: some View {
        ZStack {
            MindWaveTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                // 推定の説明
                statusSubtitle.padding(.bottom, 4)

                // アニメーション波形（displayedScore ベースで滑らかに変化する）
                WaveCanvas(amplitude: waveAmplitude, speed: waveSpeed, color: stressColor)
                    .frame(height: 150)
                    // スコアが変化したら、displayedScore を滑らかにアニメーションで追従させる
                    .onChange(of: viewModel.stressResult.stressScore) { _, newScore in
                        withAnimation(.easeInOut(duration: 1.5)) {
                            displayedScore = newScore
                        }
                    }

                Spacer(minLength: 8)

                // スコアカード（グラフィック主体、数値は控えめ）
                scoreCard.padding(.horizontal, 20)

                // データ元バッジ + ライブ監視開始/停止ボタン
                liveControlBar.padding(.top, 8)

                Spacer(minLength: 4)

                // Debug セクション
                debugSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            // 画面表示時にdisplayedScoreを現在値に合わせる
            displayedScore = viewModel.stressResult.stressScore
        }
        .onDisappear {
            // ライブ画面を離れたら自動取得を停止する（バッテリー節約）
            if viewModel.isLiveMonitoring {
                viewModel.stopLiveMonitoring()
            }
        }
        .onReceive(sessionTimer) { _ in elapsed += 1 }
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
            // ライブ取得中は点滅するドット + "LIVE" を表示
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isLiveMonitoring ? MindWaveTheme.accent : MindWaveTheme.textTertiary)
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

    // MARK: - Score Card（グラフィック主体）

    private var scoreCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {

                // 緊張不安定度（displayedScore で表示）
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

                // 心拍数・HRV（小さめに表示。数値より波形が主役）
                VStack(alignment: .trailing, spacing: 10) {
                    miniMetric(label: "心拍数",
                               value: String(format: "%.0f", viewModel.currentHeartRate),
                               unit: "bpm")
                    miniMetric(label: "HRV（SDNN）",
                               value: String(format: "%.0f", viewModel.currentHRV),
                               unit: "ms")
                }
                .padding(.top, 4)
            }

            Divider().background(Color.white.opacity(0.08))

            // 変化率（研究発表で式の説明に使う）
            HStack(spacing: 0) {
                rateCell(label: "心拍上昇率", value: viewModel.stressResult.heartRateIncreaseRate)
                Spacer()
                rateCell(label: "HRV低下率",  value: viewModel.stressResult.hrvDecreaseRate, alignTrailing: true)
            }
        }
        .padding(16)
        .darkCard()
    }

    private func miniMetric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
                .tracking(0.3)
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
                .foregroundStyle(
                    value > 0
                    ? Color(red: 0.90, green: 0.40, blue: 0.40)
                    : MindWaveTheme.accent
                )
                .animation(.easeInOut(duration: 0.5), value: displayedScore)
        }
    }

    // MARK: - ライブ制御バー（データ元 + 開始/停止ボタン）

    private var liveControlBar: some View {
        HStack(spacing: 12) {
            // データ元バッジ
            HStack(spacing: 4) {
                Image(systemName: viewModel.isUsingDemoData ? "info.circle" : "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                Text(viewModel.dataSourceLabel)
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(MindWaveTheme.textTertiary)
            }

            Spacer()

            // ライブ取得 開始/停止ボタン
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
            // 開閉ボタン
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
                VStack(spacing: 8) {
                    // ─── ライブ監視状態 ──────────────────────────
                    VStack(spacing: 4) {
                        debugRow(label: "監視状態", value: viewModel.liveMonitoringMessage)
                        debugRow(label: "更新回数", value: "\(viewModel.liveUpdateCount) 回")
                        debugRow(label: "最終更新",
                                 value: viewModel.lastLiveUpdateDate.map { formatTime($0) } ?? "未更新")
                        debugRow(label: "取得間隔", value: "\(Int(viewModel.liveUpdateInterval)) 秒")
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.04))
                    )

                    // ─── 現在の値 ────────────────────────────────
                    VStack(spacing: 4) {
                        debugRow(label: "心拍数",
                                 value: viewModel.didFetchHeartRate
                                    ? String(format: "%.0f bpm ✓", viewModel.currentHeartRate)
                                    : "未取得")
                        debugRow(label: "HRV（SDNN）",
                                 value: viewModel.didFetchHRV
                                    ? String(format: "%.0f ms ✓", viewModel.currentHRV)
                                    : "未取得")
                        debugRow(label: "スコア",
                                 value: String(format: "計算値: %.1f / 表示値: %.1f",
                                               viewModel.stressResult.stressScore,
                                               displayedScore))
                        if !viewModel.lastFetchMessage.isEmpty {
                            Text(viewModel.lastFetchMessage)
                                .font(.system(size: 9, weight: .light))
                                .foregroundStyle(MindWaveTheme.textTertiary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.04))
                    )

                    // ─── サンプリング注記 ──────────────────────────
                    Text(viewModel.healthKitSamplingNote)
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // ─── デモシナリオ切り替え ──────────────────────
                    Text("デモデータ切り替え")
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

    private func debugRow(label: String, value: String) -> some View {
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

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

// MARK: - Wave Canvas

/// TimelineView(.animation) でフレームごとに位相を更新し、
/// スコアに応じて振幅・速度が変化する3層の正弦波を描画する。
/// スコアが高いほど波の振幅が大きく、速度が速くなる。
struct WaveCanvas: View {
    let amplitude: Double   // 振幅（0.28〜0.72）
    let speed: Double       // 速度（0.55〜1.1）
    let color: Color        // ストレス状態に応じた色

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * speed
            Canvas { ctx, size in
                let w   = size.width
                let h   = size.height
                let mid = h * 0.52

                // 3層の波を描画する。layer0が最も目立つ主波、layer1・2は補助的な波。
                for layer in 0..<3 {
                    let lPhase   = phase + Double(layer) * 0.90
                    let lAmp     = amplitude * (1.0 - Double(layer) * 0.22) * h * 0.34
                    let lFreq    = 1.4 + Double(layer) * 0.35
                    let lOpacity = 0.75 - Double(layer) * 0.20
                    let lineW    = layer == 0 ? 1.8 : 1.2

                    // 波の下側を薄く塗りつぶす（奥行き感を出す）
                    var fill = Path()
                    fill.move(to: CGPoint(x: 0, y: h))
                    for x in stride(from: 0.0, through: w, by: 2.0) {
                        let y = mid + sin(x / w * .pi * 2 * lFreq + lPhase) * lAmp
                        fill.addLine(to: CGPoint(x: x, y: y))
                    }
                    fill.addLine(to: CGPoint(x: w, y: h))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .color(color.opacity(lOpacity * 0.11)))

                    // 波の線（色の濃い青白い光のライン）
                    var line = Path()
                    var first = true
                    for x in stride(from: 0.0, through: w, by: 2.0) {
                        let y = mid + sin(x / w * .pi * 2 * lFreq + lPhase) * lAmp
                        let pt = CGPoint(x: x, y: y)
                        if first { line.move(to: pt); first = false }
                        else { line.addLine(to: pt) }
                    }
                    ctx.stroke(line, with: .color(color.opacity(lOpacity * 0.55)),
                               lineWidth: lineW)
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
