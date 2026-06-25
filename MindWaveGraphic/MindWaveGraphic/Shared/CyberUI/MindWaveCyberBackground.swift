// MindWaveCyberBackground.swift
// Shared/CyberUI
// 共通Cyber背景。濃紺グラデーション＋グリッド＋放射状グロー。決定論的描画。

import SwiftUI

struct MindWaveCyberBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.08),
                    Color(red: 0.04, green: 0.07, blue: 0.14),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            CyberGridShape(cellSize: MindWaveCyberTheme.gridCellSize)
                .stroke(Color.white.opacity(MindWaveCyberTheme.gridOpacity), lineWidth: 0.5)
                .ignoresSafeArea()

            // 上部放射状グロー（固定・毎フレーム変化なし）
            RadialGradient(
                colors: [MindWaveCyberTheme.cyan.opacity(0.07), Color.clear],
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    MindWaveCyberBackground()
}
