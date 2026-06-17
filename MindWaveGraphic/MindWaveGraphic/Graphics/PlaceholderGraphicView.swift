import SwiftUI

// ビルド確認・データ疎通確認専用のプレースホルダー。
// 宇宙グラフィック・アニメーション・本番デザインは含まない。
// グラフィックチームが実装完了後、GraphicPlugin.swift の1行を変更して差し替える。
struct PlaceholderGraphicView: View {
    let input: GraphicInput

    var body: some View {
        VStack(spacing: 16) {
            Text("Graphic Team Component")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
                .tracking(1.5)

            RoundedRectangle(cornerRadius: 4)
                .fill(stateColor.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(stateColor.opacity(0.45), lineWidth: 1)
                )
                .frame(height: 3)
                .padding(.horizontal, 32)

            Text(input.state.displayName)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(stateColor)
                .animation(.easeInOut(duration: 0.4), value: input.state)

            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text(String(format: "%.0f", input.score))
                        .font(.system(size: 44, weight: .thin, design: .rounded))
                        .foregroundStyle(stateColor)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.5), value: input.score)
                    Text("score / 100")
                        .font(.system(size: 9))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                }
                VStack(spacing: 4) {
                    Text(String(format: "%.0f%%", input.confidence * 100))
                        .font(.system(size: 44, weight: .thin, design: .rounded))
                        .foregroundStyle(MindWaveTheme.textSecondary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.5), value: input.confidence)
                    Text("confidence")
                        .font(.system(size: 9))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stateColor: Color {
        switch input.state {
        case .underAroused:   return MindWaveTheme.calm
        case .optimalTension: return MindWaveTheme.accent
        case .overTense:      return MindWaveTheme.intense
        }
    }
}

#Preview {
    ZStack {
        MindWaveTheme.backgroundGradient.ignoresSafeArea()
        PlaceholderGraphicView(input: GraphicInput(score: 55, confidence: 0.75, state: .optimalTension))
            .padding()
    }
    .preferredColorScheme(.dark)
}
