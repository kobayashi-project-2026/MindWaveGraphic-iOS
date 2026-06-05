//
//  LiveWaveView.swift
//  MindWaveGraphic
//

import SwiftUI
import Combine

// MARK: - Live Wave View

struct LiveWaveView: View {
    @State private var selectedIndex = 0
    @State private var elapsed: Int = 0

    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var scenario: MindSampleScenario {
        MindSampleScenario.allScenarios[selectedIndex]
    }

    private var result: StressScoreResult {
        StressScoreCalculator.calculate(
            currentHeartRate: scenario.currentHeartRate,
            averageHeartRate: scenario.averageHeartRate,
            currentHRV: scenario.currentHRV,
            averageHRV: scenario.averageHRV
        )
    }

    private var stressColor: Color { MindWaveTheme.stressColor(score: result.stressScore) }
    private var stressLabel: String { MindWaveTheme.stressLabel(score: result.stressScore) }

    // 波の振幅・速度をスコアに比例させる
    private var waveAmplitude: Double { 0.28 + (result.stressScore / 100.0) * 0.44 }
    private var waveSpeed: Double     { 0.55 + (result.stressScore / 100.0) * 0.55 }

    var body: some View {
        ZStack {
            MindWaveTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                // アニメーション波形
                WaveCanvas(amplitude: waveAmplitude, speed: waveSpeed, color: stressColor)
                    .frame(height: 160)

                Spacer(minLength: 12)

                // スコア・指標カード
                scoreCard
                    .padding(.horizontal, 20)

                Spacer(minLength: 16)

                // シナリオ切り替え
                scenarioPicker
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .onReceive(sessionTimer) { _ in elapsed += 1 }
    }

    // MARK: Header

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
                    .fill(MindWaveTheme.accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: MindWaveTheme.accent.opacity(0.9), radius: 5)
                Text("LIVE")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MindWaveTheme.accent)
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

    // MARK: Score Card

    private var scoreCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {

                // 緊張不安定度
                VStack(alignment: .leading, spacing: 4) {
                    Text("緊張不安定度")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .tracking(0.5)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.0f", result.stressScore))
                            .font(.system(size: 50, weight: .thin, design: .rounded))
                            .foregroundStyle(stressColor)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.4), value: selectedIndex)
                        Text("/ 100")
                            .font(.caption)
                            .foregroundStyle(MindWaveTheme.textTertiary)
                            .padding(.bottom, 8)
                    }

                    Text(stressLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(stressColor)
                        .animation(.easeInOut(duration: 0.3), value: selectedIndex)
                }

                Spacer()

                // 心拍数・HRV
                VStack(alignment: .trailing, spacing: 10) {
                    miniMetric(
                        label: "心拍数",
                        value: String(format: "%.0f", scenario.currentHeartRate),
                        unit: "bpm"
                    )
                    miniMetric(
                        label: "HRV（SDNN）",
                        value: String(format: "%.0f", scenario.currentHRV),
                        unit: "ms"
                    )
                }
                .padding(.top, 4)
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // 変化率（研究発表用）
            HStack(spacing: 0) {
                rateCell(label: "心拍上昇率", value: result.heartRateIncreaseRate)
                Spacer()
                rateCell(label: "HRV低下率", value: result.hrvDecreaseRate, alignTrailing: true)
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
                    .animation(.easeInOut(duration: 0.4), value: selectedIndex)
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
                .animation(.easeInOut(duration: 0.3), value: selectedIndex)
        }
    }

    // MARK: Scenario Picker

    private var scenarioPicker: some View {
        HStack(spacing: 8) {
            ForEach(MindSampleScenario.allScenarios.indices, id: \.self) { i in
                let isSelected = selectedIndex == i
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { selectedIndex = i }
                } label: {
                    Text(MindSampleScenario.allScenarios[i].name)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.black : MindWaveTheme.textSecondary)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected
                                      ? MindWaveTheme.accent
                                      : Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Wave Canvas

/// TimelineView(.animation) でフレームごとに位相を更新し、
/// スコアに応じて振幅・速度が変化する3層の正弦波を描画する。
struct WaveCanvas: View {
    let amplitude: Double   // 0.28〜0.72（stressScoreで変化）
    let speed: Double       // 0.55〜1.1（stressScoreで変化）
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * speed
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let mid = h * 0.52

                for layer in 0..<3 {
                    let lPhase   = phase + Double(layer) * 0.90
                    let lAmp     = amplitude * (1.0 - Double(layer) * 0.22) * h * 0.34
                    let lFreq    = 1.4  + Double(layer) * 0.35
                    let lOpacity = 0.75 - Double(layer) * 0.20
                    let lineW    = layer == 0 ? 1.8 : 1.2

                    // 波の塗りつぶし
                    var fill = Path()
                    fill.move(to: CGPoint(x: 0, y: h))
                    for x in stride(from: 0.0, through: w, by: 2.0) {
                        let y = mid + sin(x / w * .pi * 2 * lFreq + lPhase) * lAmp
                        fill.addLine(to: CGPoint(x: x, y: y))
                    }
                    fill.addLine(to: CGPoint(x: w, y: h))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .color(color.opacity(lOpacity * 0.11)))

                    // 波の線
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
        .preferredColorScheme(.dark)
}
