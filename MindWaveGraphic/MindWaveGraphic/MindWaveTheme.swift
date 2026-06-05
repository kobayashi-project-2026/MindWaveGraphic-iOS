//
//  MindWaveTheme.swift
//  MindWaveGraphic
//

import SwiftUI

enum MindWaveTheme {

    // MARK: - Colors

    static let background     = Color(red: 0.04, green: 0.04, blue: 0.10)
    static let cardBackground = Color(red: 0.10, green: 0.11, blue: 0.18)
    static let accent         = Color(red: 0.35, green: 0.75, blue: 0.95)
    static let accentGlow     = Color(red: 0.20, green: 0.55, blue: 0.85)
    static let textPrimary    = Color.white
    static let textSecondary  = Color(white: 0.60)
    static let textTertiary   = Color(white: 0.38)

    // ストレス状態カラー
    static let calm    = Color(red: 0.35, green: 0.70, blue: 0.95)   // 青白
    static let mild    = Color(red: 0.95, green: 0.62, blue: 0.25)   // 橙（控えめ）
    static let intense = Color(red: 0.90, green: 0.28, blue: 0.22)   // 赤（控えめ）

    // MARK: - Gradients

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.04, green: 0.04, blue: 0.10),
            Color(red: 0.06, green: 0.12, blue: 0.22)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Helpers

    static func stressColor(score: Double) -> Color {
        switch score {
        case 0..<40:  return calm
        case 40..<70: return mild
        default:      return intense
        }
    }

    static func stressLabel(score: Double) -> String {
        switch score {
        case 0..<40:  return "落ち着き"
        case 40..<70: return "やや高まり"
        default:      return "高い緊張"
        }
    }
}

// MARK: - DarkCard ViewModifier

struct DarkCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(MindWaveTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func darkCard() -> some View {
        modifier(DarkCardModifier())
    }
}
