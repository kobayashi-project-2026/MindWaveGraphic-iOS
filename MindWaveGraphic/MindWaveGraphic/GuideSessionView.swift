//
//  GuideSessionView.swift
//  MindWaveGraphic
//
//  ガイドセッションのView と GuideExercise 定義。
//  呼吸法を3つに統一: 4-7-8 / BOX / 2-1-4
//

import SwiftUI
import Combine

// MARK: - GuideExercise

/// 呼吸ガイド種別。3種類に統一。
enum GuideExercise: String, CaseIterable, Identifiable {
    case breathing478 = "breathing478"
    case box          = "box"
    case breathing214 = "breathing214"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathing478: return "4-7-8呼吸"
        case .box:          return "BOX呼吸"
        case .breathing214: return "2-1-4呼吸"
        }
    }

    var description: String {
        switch self {
        case .breathing478: return "吸う4秒・止める7秒・吐く8秒。深い鎮静効果。"
        case .box:          return "4秒ずつ4フェーズ。集中と落ち着きを同時に。"
        case .breathing214: return "吸う2秒・止める1秒・吐く4秒。手軽にリセット。"
        }
    }

    var icon: String {
        switch self {
        case .breathing478: return "moon.zzz"
        case .box:          return "square.dashed"
        case .breathing214: return "wind"
        }
    }

    var timingLabel: String {
        switch self {
        case .breathing478: return "4 · 7 · 8"
        case .box:          return "4 · 4 · 4 · 4"
        case .breathing214: return "2 · 1 · 4"
        }
    }

    // Breathing cycle timing (seconds)
    var inhaleSeconds: Int {
        switch self {
        case .breathing478: return 4
        case .box:          return 4
        case .breathing214: return 2
        }
    }
    var hold1Seconds: Int {
        switch self {
        case .breathing478: return 7
        case .box:          return 4
        case .breathing214: return 1
        }
    }
    var exhaleSeconds: Int {
        switch self {
        case .breathing478: return 8
        case .box:          return 4
        case .breathing214: return 4
        }
    }
    var hold2Seconds: Int {
        switch self {
        case .breathing478: return 0
        case .box:          return 4
        case .breathing214: return 0
        }
    }
    var cycleTotal: Int { inhaleSeconds + hold1Seconds + exhaleSeconds + hold2Seconds }

    /// elapsed = 経過秒数。返値: (phaseText, circleScale 0.55–1.0)
    func breathPhase(elapsed: Int) -> (text: String, scale: CGFloat) {
        guard cycleTotal > 0 else { return ("準備", 0.68) }
        let pos = elapsed % cycleTotal
        if pos < inhaleSeconds {
            let p = CGFloat(pos + 1) / CGFloat(inhaleSeconds)
            return ("吸う", 0.55 + 0.45 * p)
        } else if pos < inhaleSeconds + hold1Seconds {
            return ("止める", 1.0)
        } else if pos < inhaleSeconds + hold1Seconds + exhaleSeconds {
            let p = CGFloat(pos - inhaleSeconds - hold1Seconds + 1) / CGFloat(exhaleSeconds)
            return ("吐く", 1.0 - 0.45 * p)
        } else {
            return ("止める", 0.55)
        }
    }
}

// MARK: - GuideSessionView (legacy wrapper)

/// ガイド体験を管理するフルスクリーンView（GuideFlowView の session ステップで使用）。
struct GuideSessionView: View {
    let exercise: GuideExercise
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDuration = 60
    @State private var remaining        = 60
    @State private var isRunning        = false
    @State private var isFinished       = false

    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let durationOptions: [(label: String, seconds: Int)] = [
        ("1分", 60), ("3分", 180), ("5分", 300)
    ]

    private var elapsedSeconds: Int { selectedDuration - remaining }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black,
                         Color(red: 0.03, green: 0.08, blue: 0.18),
                         Color.cyan.opacity(0.18)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
                Spacer()
                BreathingCircleVisual(
                    exercise: exercise,
                    elapsedSeconds: elapsedSeconds,
                    isRunning: isRunning
                )
                .frame(height: 260)
                Spacer()
                bottomControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 44)
            }
        }
        .onReceive(sessionTimer) { _ in
            guard isRunning else { return }
            if remaining > 0 {
                remaining -= 1
            } else {
                isRunning = false
                isFinished = true
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
            Spacer()
            Text(exercise.title)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.white.opacity(0.80))
                .tracking(1)
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.clear)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 14) {
            if isFinished {
                Text("セッション終了")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 4)
            }
            Text(timeString)
                .font(.system(size: 52, weight: .thin, design: .rounded))
                .foregroundStyle(.white.opacity(isFinished ? 0.38 : 0.88))
                .monospacedDigit()
                .contentTransition(.numericText())
            if !isRunning && !isFinished { durationPicker }
            actionButton
        }
    }

    private var timeString: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private var durationPicker: some View {
        HStack(spacing: 10) {
            ForEach(durationOptions, id: \.seconds) { option in
                Button {
                    selectedDuration = option.seconds
                    remaining = option.seconds
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selectedDuration == option.seconds
                                         ? .black : .white.opacity(0.58))
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedDuration == option.seconds
                                      ? Color.cyan.opacity(0.80)
                                      : Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.label)を選択")
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isFinished {
            Button {
                remaining = selectedDuration
                isFinished = false
                isRunning = true
            } label: {
                Text("もう一度")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.cyan.opacity(0.22))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.cyan.opacity(0.35), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("もう一度開始する")
        } else {
            Button {
                if !isRunning && remaining == 0 { remaining = selectedDuration }
                isRunning.toggle()
            } label: {
                startStopLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRunning ? "停止する" : "開始する")
        }
    }

    private var startStopLabel: some View {
        let icon  = isRunning ? "stop.circle.fill" : "play.circle.fill"
        let label = isRunning ? "停止" : "開始"
        let fg    = isRunning ? Color.orange.opacity(0.90) : Color.cyan.opacity(0.90)
        let bg    = isRunning ? Color.orange.opacity(0.12) : Color.cyan.opacity(0.15)
        let bd    = isRunning ? Color.orange.opacity(0.28) : Color.cyan.opacity(0.28)
        return HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15))
            Text(label).font(.system(size: 15, weight: .medium))
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
}

// MARK: - Preview

#Preview("4-7-8呼吸") { GuideSessionView(exercise: .breathing478) }
#Preview("BOX呼吸")   { GuideSessionView(exercise: .box) }
#Preview("2-1-4呼吸") { GuideSessionView(exercise: .breathing214) }
