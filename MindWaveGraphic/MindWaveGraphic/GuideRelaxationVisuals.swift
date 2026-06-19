//
//  GuideRelaxationVisuals.swift
//  MindWaveGraphic
//
//  友人のコードの波紋・流れる帯アニメーションを既存UIへ統合したもの。
//  RippleGuideVisual と FlowGuideVisual を提供する。
//  MindWaveのデザイン（黒〜濃紺、青/シアン系）に合わせて再実装。
//  Reduce Motion 対応・VoiceOver ラベル付き。
//

import SwiftUI

// MARK: - Ripple

/// 波紋呼吸ガイドビジュアル。3つの波紋円が時間差で外側へ広がる。
/// 友人コードの概念（Circle + scaleEffect + opacity animation）を
/// MindWaveデザインへ統合。青〜シアン系、背景は黒〜濃紺。
struct RippleGuideVisual: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                MindWaveRippleCircle(delay: Double(index) * 1.4)
            }
        }
        .accessibilityLabel("呼吸を整える波紋アニメーション")
        .accessibilityAddTraits(.isImage)
    }
}

/// 波紋の1リング。外側へ広がりながら透明になる。
/// delay パラメータで各リングの開始タイミングをずらす。
/// Reduce Motion ON のときはアニメーションを停止し、静止した半透明リングのみ表示する。
struct MindWaveRippleCircle: View {
    let delay: Double
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color.cyan.opacity(0.65),
                        Color.blue.opacity(0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.8
            )
            .scaleEffect(reduceMotion ? 1.5 : (animate ? 4.2 : 0.1))
            .opacity(reduceMotion ? 0.3 : (animate ? 0 : 0.85))
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 4.5)
                        .repeatForever(autoreverses: false)
                        .delay(delay),
                value: animate
            )
            .onAppear { animate = true }
    }
}

// MARK: - Flow

/// 流れる帯ガイドビジュアル。5本の横長帯が左右へゆっくり往復する。
/// 友人コードの概念（RoundedRectangle + offset animation）を
/// GeometryReader で画面幅対応にし、MindWaveデザインへ統合。
/// Reduce Motion ON のときは帯の移動を停止する。
struct FlowGuideVisual: View {
    @State private var move = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            // 画面幅の80%を使用、最大360ptに制限
            let bandWidth = min(geometry.size.width * 0.80, 360)
            let spacing: CGFloat = 20

            VStack(spacing: spacing) {
                ForEach(0..<5, id: \.self) { index in
                    flowBand(width: bandWidth, index: index)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { move = true }
        .accessibilityLabel("ゆっくり流れるリラクゼーションアニメーション")
        .accessibilityAddTraits(.isImage)
    }

    private func flowBand(width: CGFloat, index: Int) -> some View {
        RoundedRectangle(cornerRadius: 50)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.cyan.opacity(0.15)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: 18)
            .offset(x: reduceMotion ? 0 : (move ? 28 : -28))
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 3.2)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.30),
                value: move
            )
    }
}
