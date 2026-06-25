// MindWaveCyberSectionHeader.swift
// Shared/CyberUI
// セクション見出しコンポーネント。左端のアクセントバーとラベルを含む。

import SwiftUI

struct MindWaveCyberSectionHeader: View {
    let title: String
    var accentColor: Color = MindWaveCyberTheme.cyan

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 2, height: 14)
                .shadow(color: accentColor.opacity(0.7), radius: 4)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
                .tracking(1.5)
            Spacer()
        }
    }
}
