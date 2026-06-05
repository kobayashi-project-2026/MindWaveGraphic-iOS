//
//  ContentView.swift
//  MindWaveGraphic
//

import SwiftUI

struct ContentView: View {
    @State private var selectedIndex = 0

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

    private var statusLabel: String {
        switch result.stressScore {
        case 0..<40:  return "落ち着き"
        case 40..<70: return "軽い緊張"
        default:      return "強い緊張"
        }
    }

    private var statusColor: Color {
        switch result.stressScore {
        case 0..<40:  return .blue
        case 40..<70: return .orange
        default:      return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // シナリオ選択
                    Picker("シナリオ", selection: $selectedIndex) {
                        ForEach(MindSampleScenario.allScenarios.indices, id: \.self) { i in
                            Text(MindSampleScenario.allScenarios[i].name).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    Text(scenario.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // スコアゲージ
                    StressGaugeView(
                        score: result.stressScore,
                        color: statusColor,
                        label: statusLabel
                    )

                    // 入力値
                    GroupBox("入力値（ダミーデータ）") {
                        VStack(spacing: 10) {
                            DataRow(label: "現在の心拍数",
                                    value: String(format: "%.0f bpm", scenario.currentHeartRate))
                            DataRow(label: "平均心拍数（個人）",
                                    value: String(format: "%.0f bpm", scenario.averageHeartRate))
                            Divider()
                            DataRow(label: "現在のHRV（SDNN）",
                                    value: String(format: "%.0f ms", scenario.currentHRV))
                            DataRow(label: "平均HRV（個人）",
                                    value: String(format: "%.0f ms", scenario.averageHRV))
                        }
                    }
                    .padding(.horizontal)

                    // 計算結果
                    GroupBox("計算結果") {
                        VStack(spacing: 10) {
                            DataRow(
                                label: "心拍上昇率",
                                value: String(format: "%+.1f%%", result.heartRateIncreaseRate * 100),
                                valueColor: result.heartRateIncreaseRate > 0 ? .red : .blue
                            )
                            DataRow(
                                label: "HRV低下率",
                                value: String(format: "%+.1f%%", result.hrvDecreaseRate * 100),
                                valueColor: result.hrvDecreaseRate > 0 ? .red : .blue
                            )
                            Divider()
                            DataRow(
                                label: "緊張不安定度",
                                value: String(format: "%.1f / 100", result.stressScore),
                                isBold: true,
                                valueColor: statusColor
                            )
                        }
                    }
                    .padding(.horizontal)

                    Text("※ ダミーデータで動作確認中。HealthKit連携は次フェーズで実装予定。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom)
                }
                .padding(.top)
            }
            .navigationTitle("Mind Wave Graphic")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Gauge

struct StressGaugeView: View {
    let score: Double
    let color: Color
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 18)
                .frame(width: 180, height: 180)

            Circle()
                .trim(from: 0, to: score / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: score)

            VStack(spacing: 2) {
                Text(String(format: "%.0f", score))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Row

struct DataRow: View {
    let label: String
    let value: String
    var isBold: Bool = false
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(isBold ? .semibold : .regular)
                .foregroundStyle(valueColor)
        }
    }
}

#Preview {
    ContentView()
}
