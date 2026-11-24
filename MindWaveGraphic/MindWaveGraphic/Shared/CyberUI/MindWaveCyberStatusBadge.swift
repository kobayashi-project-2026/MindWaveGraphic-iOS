// MindWaveCyberStatusBadge.swift
// Shared/CyberUI
// 接続状態や稼働状態を示すカプセル型バッジ。

import SwiftUI

struct MindWaveCyberStatusBadge: View {
    let label: String
    var isActive: Bool = true
    var color: Color = MindWaveCyberTheme.cyan

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? color : Color.white.opacity(0.25))
                .frame(width: 5, height: 5)
                .shadow(color: isActive ? color.opacity(0.9) : .clear, radius: 4)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(isActive ? color : MindWaveCyberTheme.textTertiary)
                .tracking(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(isActive ? 0.12 : 0.04))
                .overlay(Capsule().strokeBorder(color.opacity(isActive ? 0.30 : 0.10), lineWidth: 1))
        )
    }
}
