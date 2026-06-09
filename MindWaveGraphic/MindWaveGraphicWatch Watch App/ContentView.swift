//
//  ContentView.swift
//  MindWaveGraphicWatch Watch App
//
//  Watch側のメイン画面。
//  HKWorkoutSession で心拍をライブ取得し、WatchConnectivity でiPhoneに送信する。
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {

                    // ─── 心拍数表示（メイン） ────────────────────
                    heartRateSection

                    // ─── 計測ボタン ──────────────────────────────
                    controlButtons

                    // ─── 状態・送信情報 ──────────────────────────
                    statusSection
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .navigationTitle("Mind Wave")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // 画面表示時にHealthKit権限をリクエストする
            await workoutManager.requestAuthorization()
        }
    }

    // MARK: - 心拍数セクション

    private var heartRateSection: some View {
        VStack(spacing: 2) {
            // 心拍数（大きく表示）
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(heartRateText)
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .foregroundStyle(heartRateColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: workoutManager.currentHeartRate)

                if workoutManager.isRunning {
                    Text("bpm")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                }
            }

            // 計測中インジケーター
            if workoutManager.isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("計測中")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.red)
                }
            } else {
                Text("停止中")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - コントロールボタン

    private var controlButtons: some View {
        HStack(spacing: 8) {
            if workoutManager.isRunning {
                // 停止ボタン
                Button {
                    workoutManager.stopWorkout()
                } label: {
                    Label("停止", systemImage: "stop.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

            } else {
                // 計測開始ボタン
                Button {
                    Task { await workoutManager.startWorkout() }
                } label: {
                    Label("計測開始", systemImage: "heart.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 状態セクション

    private var statusSection: some View {
        VStack(spacing: 6) {
            infoRow("状態",         workoutManager.statusMessage)
            infoRow("iPhone送信",   "\(workoutManager.sendCount) 回")
            infoRow("WCSession",    workoutManager.wcStatus)
            infoRow("HealthKit",    workoutManager.authStatus)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - 計算プロパティ

    private var heartRateText: String {
        workoutManager.currentHeartRate > 0
            ? String(format: "%.0f", workoutManager.currentHeartRate)
            : "--"
    }

    private var heartRateColor: Color {
        guard workoutManager.currentHeartRate > 0 else { return .secondary }
        switch workoutManager.currentHeartRate {
        case ..<60:  return Color(red: 0.40, green: 0.80, blue: 1.00)
        case ..<100: return Color.green
        case ..<130: return Color.orange
        default:     return Color.red
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutManager())
}
