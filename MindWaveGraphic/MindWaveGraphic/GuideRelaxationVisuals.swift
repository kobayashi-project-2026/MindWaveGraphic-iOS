//
//  GuideRelaxationVisuals.swift
//  MindWaveGraphic
//
//  呼吸ガイドビジュアル。4-7-8 / BOX / 2-1-4 の3呼吸法に対応した
//  BreathingCircleVisual を提供する。
//  大型サークル + フェーズ秒数内表示 + 宇宙船世界観。
//

import SwiftUI

// MARK: - BreathingCircleVisual

/// 呼吸に合わせて拡縮する大型サークルビジュアル。
/// - 中央に現フェーズの残り秒数を大きく表示
/// - その下にフェーズ名（吸う/止める/吐く）
/// - 外縁リングが呼吸スケールに合わせて拡縮
struct BreathingCircleVisual: View {
    let exercise: GuideExercise
    let elapsedSeconds: Int
    let isRunning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed phase state

    private var phase: (text: String, scale: CGFloat) {
        guard isRunning else { return ("準備", 0.70) }
        return exercise.breathPhase(elapsed: elapsedSeconds)
    }

    private var phaseText: String   { phase.text }
    private var circleScale: CGFloat { phase.scale }

    private var phaseRemaining: Int {
        guard isRunning else { return 0 }
        return exercise.phaseSecondsRemaining(elapsed: elapsedSeconds)
    }

    private var cycleCount: Int {
        guard isRunning, exercise.cycleTotal > 0 else { return 0 }
        return elapsedSeconds / exercise.cycleTotal + 1
    }

    private var isInhaling: Bool { phaseText == "吸う" }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // ── 最外周: アンビエントグロー（呼吸連動）
                Circle()
                    .fill(Color.cyan.opacity(isRunning ? 0.055 : 0.02))
                    .frame(width: 290, height: 290)
                    .scaleEffect(reduceMotion ? 1.0 : circleScale * 1.12)
                    .blur(radius: 24)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.92), value: circleScale)

                // ── 外縁装飾リング（静的HUD）
                Circle()
                    .stroke(Color.cyan.opacity(0.07), lineWidth: 0.7)
                    .frame(width: 268, height: 268)

                // 8分割ダッシュリング（コックピット計器感）
                Circle()
                    .stroke(
                        Color.cyan.opacity(0.10),
                        style: StrokeStyle(lineWidth: 0.5, dash: [18, 16])
                    )
                    .frame(width: 280, height: 280)
                    .rotationEffect(.degrees(22.5))

                // ── メイン呼吸リング（スケール連動）
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(isRunning ? 0.92 : 0.30),
                                Color(hue: 0.60, saturation: 0.72, brightness: 0.85)
                                    .opacity(isRunning ? 0.58 : 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isRunning ? 3.5 : 1.5
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(reduceMotion ? 0.88 : circleScale)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.92), value: circleScale)

                // ── 内側フィル（息の量感）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cyan.opacity(isRunning ? 0.14 : 0.03),
                                Color.cyan.opacity(0.01)
                            ],
                            center: .center, startRadius: 0, endRadius: 118
                        )
                    )
                    .frame(width: 238, height: 238)
                    .scaleEffect(reduceMotion ? 0.88 : circleScale)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.92), value: circleScale)

                // ── 中央コンテンツ
                VStack(spacing: 2) {
                    if isRunning {
                        // フェーズ残り秒数（大）
                        Text("\(phaseRemaining)")
                            .font(.system(size: 72, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .shadow(color: Color.cyan.opacity(0.25), radius: 8)
                    } else {
                        // 未開始
                        Image(systemName: exercise.icon)
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundStyle(Color.cyan.opacity(0.45))
                    }

                    // フェーズテキスト
                    Text(phaseText)
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(isRunning ? .white.opacity(0.90) : .white.opacity(0.28))
                        .tracking(2.0)
                        .animation(.easeInOut(duration: 0.30), value: phaseText)
                }
            }
            .frame(width: 290, height: 290)

            // ── タイミング + サイクル行
            HStack(spacing: 18) {
                Text(exercise.timingLabel)
                    .font(.system(size: 12, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.52))
                    .tracking(2.5)

                if isRunning && cycleCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.22))
                        Text("CYCLE \(cycleCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.30))
                            .tracking(1.5)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isRunning)
        }
        .accessibilityLabel("\(exercise.title) 呼吸ガイド \(phaseText)")
        .accessibilityAddTraits(.isImage)
    }
}
