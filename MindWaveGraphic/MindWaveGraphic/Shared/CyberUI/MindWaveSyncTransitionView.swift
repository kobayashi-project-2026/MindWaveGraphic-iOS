// MindWaveSyncTransitionView.swift
// Shared/CyberUI
// 純粋な画面演出。測定・解析・補正は行わない。

import SwiftUI

struct MindWaveSyncTransitionView: View {
    let subtitle: String
    let onComplete: () -> Void

    @State private var rotation: Double = 0
    @State private var showContent: Bool = false
    @State private var gridScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            MindWaveCyberBackground()

            // グリッドの拡大（純粋な視覚演出）
            CyberGridShape(cellSize: MindWaveCyberTheme.gridCellSize)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
                .ignoresSafeArea()
                .scaleEffect(gridScale)

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .strokeBorder(MindWaveCyberTheme.cyan.opacity(0.12), lineWidth: 1)
                        .frame(width: 110, height: 110)

                    // 回転する細線（純粋な演出）
                    Circle()
                        .trim(from: 0, to: 0.30)
                        .stroke(
                            MindWaveCyberTheme.cyan,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 110, height: 110)
                        .rotationEffect(.degrees(rotation))
                        .shadow(color: MindWaveCyberTheme.cyan.opacity(0.7), radius: 8)

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(MindWaveCyberTheme.cyan)
                        .shadow(color: MindWaveCyberTheme.cyan.opacity(0.5), radius: 6)
                }

                VStack(spacing: 10) {
                    Text("MIND WAVE SYNC")
                        .font(.system(size: 17, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.textPrimary)
                        .tracking(4)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .opacity(showContent ? 1 : 0)
            .scaleEffect(showContent ? 1 : 0.88)
        }
        .onAppear {
            print("[CyberUI] sync transition started")
            withAnimation(.easeOut(duration: 0.4)) {
                showContent = true
                gridScale = 1.08
            }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                await MainActor.run {
                    print("[CyberUI] sync transition completed")
                    withAnimation(.easeIn(duration: 0.25)) { showContent = false }
                }
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run { onComplete() }
            }
        }
    }
}

#Preview {
    MindWaveSyncTransitionView(subtitle: "呼吸ガイドを準備しています") {}
}
