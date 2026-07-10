//
//  GuideRelaxationVisuals.swift
//  MindWaveGraphic
//
//  大型呼吸サークルビジュアル。4-7-8 / BOX / 2-1-4 の3呼吸法に対応。
//  フェーズ進行アーク + 中央タイマー + グロー層で「主役」感を演出。
//

import SwiftUI

// MARK: - BreathingCircleVisual

struct BreathingCircleVisual: View {
    let exercise: GuideExercise
    let elapsedSeconds: Int
    let isRunning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed phase state

    private var phase: (text: String, scale: CGFloat) {
        guard isRunning else { return ("準備", 0.78) }
        return exercise.breathPhase(elapsed: elapsedSeconds)
    }
    private var phaseText: String    { phase.text }
    private var circleScale: CGFloat { phase.scale }

    private var phaseRemaining: Int {
        guard isRunning else { return 0 }
        return exercise.phaseSecondsRemaining(elapsed: elapsedSeconds)
    }

    private var cycleCount: Int {
        guard isRunning, exercise.cycleTotal > 0 else { return 0 }
        return elapsedSeconds / exercise.cycleTotal + 1
    }

    // フェーズ進行アーク 0→1（inhale:成長 / hold:1.0 / exhale:縮小 / hold2:0.0）
    private var phaseArcFraction: CGFloat {
        guard isRunning, exercise.cycleTotal > 0 else { return 0 }
        let pos = elapsedSeconds % exercise.cycleTotal
        if pos < exercise.inhaleSeconds {
            return CGFloat(pos + 1) / CGFloat(max(exercise.inhaleSeconds, 1))
        } else if pos < exercise.inhaleSeconds + exercise.hold1Seconds {
            return 1.0
        } else if pos < exercise.inhaleSeconds + exercise.hold1Seconds + exercise.exhaleSeconds {
            let ep = pos - exercise.inhaleSeconds - exercise.hold1Seconds
            return 1.0 - CGFloat(ep + 1) / CGFloat(max(exercise.exhaleSeconds, 1))
        } else {
            return 0.0
        }
    }

    private var phaseArcColor: Color {
        guard isRunning else { return .clear }
        switch phaseText {
        case "吸う":   return Color.cyan
        case "止める": return Color.white.opacity(0.85)
        case "吐く":   return Color(hue: 0.58, saturation: 0.55, brightness: 0.78)
        default:       return Color.cyan.opacity(0.55)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // ── 最外 アンビエントグロー（スケール連動）
                Circle()
                    .fill(Color.cyan.opacity(isRunning ? 0.08 : 0.07))
                    .frame(width: 304, height: 304)
                    .scaleEffect(reduceMotion ? 1.0 : circleScale * 1.10)
                    .blur(radius: 30)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.92), value: circleScale)

                // ── コックピット計器 外縁装飾ダッシュリング
                Circle()
                    .stroke(
                        Color.cyan.opacity(0.10),
                        style: StrokeStyle(lineWidth: 0.6, dash: [18, 16])
                    )
                    .frame(width: 286, height: 286)
                    .rotationEffect(.degrees(22.5))

                // 外縁薄単色リング
                Circle()
                    .stroke(Color.cyan.opacity(0.07), lineWidth: 0.5)
                    .frame(width: 274, height: 274)

                // ── フェーズ進行アーク（240pxリング外側）
                if isRunning {
                    // グロー層
                    Circle()
                        .trim(from: 0, to: phaseArcFraction)
                        .stroke(phaseArcColor.opacity(0.32), lineWidth: 9)
                        .frame(width: 258, height: 258)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 5)
                        .animation(reduceMotion ? nil : .linear(duration: 1.0), value: phaseArcFraction)
                    // シャープ層
                    Circle()
                        .trim(from: 0, to: phaseArcFraction)
                        .stroke(
                            phaseArcColor.opacity(0.92),
                            style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                        )
                        .frame(width: 258, height: 258)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: phaseArcColor.opacity(0.55), radius: 5)
                        .animation(reduceMotion ? nil : .linear(duration: 1.0), value: phaseArcFraction)
                }

                // ── メイン呼吸リング（スケール連動・主役）
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(isRunning ? 0.92 : 0.80),
                                Color(hue: 0.60, saturation: 0.72, brightness: 0.85)
                                    .opacity(isRunning ? 0.58 : 0.52)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isRunning ? 3.5 : 3.2
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(reduceMotion ? 0.88 : circleScale)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.92), value: circleScale)
                    .shadow(color: Color.cyan.opacity(isRunning ? 0.28 : 0.22), radius: 10)

                // ── 内側フィル（息の量感）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cyan.opacity(isRunning ? 0.14 : 0.12),
                                Color.cyan.opacity(0.01)
                            ],
                            center: .center, startRadius: 0, endRadius: 118
                        )
                    )
                    .frame(width: 238, height: 238)
                    .scaleEffect(reduceMotion ? 0.88 : circleScale)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.92), value: circleScale)

                // ── 中央コンテンツ
                VStack(spacing: 4) {
                    if isRunning {
                        // フェーズ残り秒数（大）
                        Text("\(phaseRemaining)")
                            .font(.system(size: 72, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .shadow(color: Color.cyan.opacity(0.32), radius: 12)
                        // フェーズ名
                        Text(phaseText)
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(.white.opacity(0.92))
                            .tracking(3.0)
                            .animation(.easeInOut(duration: 0.25), value: phaseText)
                    } else {
                        // 未開始アイコン
                        Image(systemName: exercise.icon)
                            .font(.system(size: 42, weight: .ultraLight))
                            .foregroundStyle(Color.cyan.opacity(0.88))
                            .shadow(color: Color.cyan.opacity(0.60), radius: 18)
                        Text("準備")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.70))
                            .tracking(3.0)
                    }
                }
            }
            .frame(width: 304, height: 304)

            // ── タイミング行 + サイクルカウンター
            HStack(spacing: 18) {
                Text(exercise.timingLabel)
                    .font(.system(size: 12, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.56))
                    .tracking(2.5)

                if isRunning && cycleCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.22))
                        Text("CYCLE \(cycleCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.32))
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
