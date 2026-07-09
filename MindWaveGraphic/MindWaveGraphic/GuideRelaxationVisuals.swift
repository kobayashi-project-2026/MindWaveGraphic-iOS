//
//  GuideRelaxationVisuals.swift
//  MindWaveGraphic
//
//  呼吸ガイドビジュアル。4-7-8 / BOX / 2-1-4 の3呼吸法に対応した
//  BreathingCircleVisual を提供する。
//

import SwiftUI

// MARK: - BreathingCircleVisual

/// 呼吸に合わせて拡縮するサークルビジュアル。
/// exercise の cycleTotal / breathPhase を使い、1秒刻みでフェーズを計算する。
struct BreathingCircleVisual: View {
    let exercise: GuideExercise
    let elapsedSeconds: Int
    let isRunning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phaseText: String {
        guard isRunning else { return "準備" }
        return exercise.breathPhase(elapsed: elapsedSeconds).text
    }

    private var circleScale: CGFloat {
        guard isRunning else { return 0.68 }
        return exercise.breathPhase(elapsed: elapsedSeconds).scale
    }

    private var cycleCount: Int {
        guard isRunning, exercise.cycleTotal > 0 else { return 0 }
        return elapsedSeconds / exercise.cycleTotal + 1
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // 外側アンビエントグロー
                Circle()
                    .fill(Color.cyan.opacity(0.04))
                    .frame(width: 195, height: 195)
                    .scaleEffect(reduceMotion ? 1.0 : circleScale * 1.14)
                    .blur(radius: 18)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.85), value: circleScale)

                // 外縁HUDリング（装飾）
                Circle()
                    .stroke(Color.cyan.opacity(0.06), lineWidth: 0.6)
                    .frame(width: 176, height: 176)

                // メインストロークリング
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.82),
                                Color(hue: 0.60, saturation: 0.70, brightness: 0.80).opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.2
                    )
                    .frame(width: 152, height: 152)
                    .scaleEffect(reduceMotion ? 0.85 : circleScale)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.85), value: circleScale)

                // 内側フィル（息の量感）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.10), Color.cyan.opacity(0.02)],
                            center: .center, startRadius: 0, endRadius: 76
                        )
                    )
                    .frame(width: 150, height: 150)
                    .scaleEffect(reduceMotion ? 0.85 : circleScale)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.85), value: circleScale)

                // 中央テキスト
                VStack(spacing: 5) {
                    Text(phaseText)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white.opacity(0.90))
                        .animation(.easeInOut(duration: 0.30), value: phaseText)
                    Text(exercise.timingLabel)
                        .font(.system(size: 10, weight: .light, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.52))
                        .tracking(1.8)
                }
            }
            .frame(width: 200, height: 200)

            // サイクルカウンター
            if isRunning {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.22))
                    Text("CYCLE \(cycleCount)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.28))
                        .tracking(1.5)
                }
                .transition(.opacity)
            }
        }
        .accessibilityLabel("\(exercise.title) 呼吸ガイド \(phaseText)")
        .accessibilityAddTraits(.isImage)
    }
}
