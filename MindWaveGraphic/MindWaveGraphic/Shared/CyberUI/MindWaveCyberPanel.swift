// MindWaveCyberPanel.swift
// Shared/CyberUI
// 共通Cyber UIパネルコンポーネント。半透明・細ボーダー・淡い発光。

import SwiftUI

struct MindWaveCyberPanel<Content: View>: View {
    var title: String? = nil
    var accentColor: Color = MindWaveCyberTheme.cyan
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: title != nil ? 12 : 0) {
            if let title {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 2, height: 10)
                    Text(title)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.80))
                        .tracking(1.5)
                }
            }
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: MindWaveCyberTheme.panelRadius)
                .fill(MindWaveCyberTheme.panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: MindWaveCyberTheme.panelRadius)
                        .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: accentColor.opacity(0.06), radius: 8, x: 0, y: 0)
        )
    }
}
