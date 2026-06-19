//
//  GuideSessionView.swift
//  MindWaveGraphic
//
//  ガイドセッションの全体を管理するView。
//  GuideView から fullScreenCover で表示される。
//  RippleGuideVisual / FlowGuideVisual のどちらかを表示し、
//  1分・3分・5分の時間選択、開始・停止、残り時間カウントダウンを提供する。
//  Timer は 1つだけ生成する（重複起動なし）。
//  本機能は視覚的なリラクゼーション補助であり、医療効果を保証しない。
//

import SwiftUI
import Combine

/// ガイド種別。GuideView からこのView へ渡される。
enum GuideExercise: String, CaseIterable, Identifiable {
    case ripple = "ripple"
    case flow   = "flow"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ripple: return "波紋呼吸"
        case .flow:   return "流れを整える"
        }
    }

    var description: String {
        switch self {
        case .ripple: return "広がる波紋に合わせて、呼吸をゆっくり整える。"
        case .flow:   return "流れる帯を眺めながら、身体の力を抜く。"
        }
    }

    var icon: String {
        switch self {
        case .ripple: return "waveform.circle"
        case .flow:   return "wind"
        }
    }
}

// MARK: - GuideSessionView

/// ガイド体験を管理するフルスクリーンView。
/// fullScreenCover で表示し、閉じるとアニメーションと Timer が停止する。
/// Timer は onReceive で購読し、View 消滅時に購読が解除されて停止する。
struct GuideSessionView: View {
    let exercise: GuideExercise
    @Environment(\.dismiss) private var dismiss

    // MARK: - Session state
    @State private var selectedDuration = 60   // 選択した秒数
    @State private var remaining        = 60   // 残り秒数
    @State private var isRunning        = false
    @State private var isFinished       = false

    // MARK: - Timer（1つのみ。autoconnect で View 表示中のみ稼働）
    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let durationOptions: [(label: String, seconds: Int)] = [
        ("1分", 60), ("3分", 180), ("5分", 300)
    ]

    var body: some View {
        ZStack {
            // MindWave デザインに合わせた青みがかった黒背景
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.03, green: 0.08, blue: 0.18),
                    Color.cyan.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                Spacer()

                // ビジュアル（Ripple または Flow）
                visualArea
                    .frame(height: 270)

                Spacer()

                // 終了・残り時間・制御
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
                isRunning  = false
                isFinished = true
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
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

            // レイアウトバランス用（透明）
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.clear)
        }
    }

    // MARK: - Visual Area

    private var visualArea: some View {
        ZStack {
            if exercise == .ripple {
                RippleGuideVisual()
                // 呼吸案内テキスト（Ripple セッション実行中のみ）
                if isRunning {
                    Text(breathingPhaseText)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .offset(y: 148)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.6), value: breathingPhaseText)
                }
            } else {
                FlowGuideVisual()
            }
        }
    }

    /// 波紋アニメーション（4.5s サイクル）に合わせて呼吸案内を交互に表示する。
    /// 4秒ごとに「ゆっくり吸う」→「静かに吐く」を切り替える（視覚ガイドであり医療呼吸法ではない）。
    private var breathingPhaseText: String {
        let elapsed = selectedDuration - remaining
        return (elapsed % 8) < 4 ? "ゆっくり吸う" : "静かに吐く"
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 14) {
            // セッション完了時
            if isFinished {
                Text("セッション終了")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 4)
            }

            // 残り時間 / 経過時間
            Text(timeString)
                .font(.system(size: 52, weight: .thin, design: .rounded))
                .foregroundStyle(.white.opacity(isFinished ? 0.38 : 0.88))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: remaining)

            // 時間選択（未開始時のみ）
            if !isRunning && !isFinished {
                durationPicker
            }

            // 開始・停止・もう一度
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
                    remaining        = option.seconds
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selectedDuration == option.seconds
                                         ? .black : .white.opacity(0.58))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
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

    /// 開始・停止ボタンのラベル View。型推論タイムアウトを避けるため単独プロパティに分離。
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
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(bd, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        if isFinished {
            // セッション完了後：もう一度
            Button {
                remaining  = selectedDuration
                isFinished = false
                isRunning  = true
            } label: {
                Text("もう一度")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cyan.opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.cyan.opacity(0.35), lineWidth: 1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("もう一度開始する")
        } else {
            // 開始 / 停止
            Button {
                if !isRunning && remaining == 0 {
                    remaining = selectedDuration
                }
                isRunning.toggle()
            } label: {
                startStopLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRunning ? "停止する" : "開始する")
        }
    }
}

// MARK: - Preview

#Preview("波紋呼吸") {
    GuideSessionView(exercise: .ripple)
}

#Preview("流れを整える") {
    GuideSessionView(exercise: .flow)
}
