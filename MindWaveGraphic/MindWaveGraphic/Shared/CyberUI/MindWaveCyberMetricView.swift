// MindWaveCyberMetricView.swift
// Shared/CyberUI
// 生体指標・スコアなどを表示する数値パネルセル。

import SwiftUI

struct MindWaveCyberMetricView: View {
    let label: String
    let value: String
    let unit: String
    var accentColor: Color = MindWaveCyberTheme.cyan

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
                .tracking(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .thin, design: .rounded))
                    .foregroundStyle(accentColor)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .light, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
