//
//  GuideView.swift
//  MindWaveGraphic
//

import SwiftUI

struct GuideView: View {
    @State private var expanding = false

    var body: some View {
        ZStack {
            MindWaveTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {

                // タイトル
                VStack(spacing: 8) {
                    Text("ガイダンス")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(MindWaveTheme.textPrimary)
                        .tracking(2.5)
                    Text("呼吸に意識を向けましょう")
                        .font(.subheadline)
                        .foregroundStyle(MindWaveTheme.textSecondary)
                }
                .padding(.top, 40)

                Spacer()

                // 発光リング
                breathingRing

                Spacer()

                // ボタン
                actionButtons
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Breathing Ring

    private var breathingRing: some View {
        ZStack {
            // 外側グロー（最も薄い）
            Circle()
                .fill(MindWaveTheme.accentGlow.opacity(0.05))
                .frame(width: 280, height: 280)
                .scaleEffect(expanding ? 1.12 : 0.90)
                .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: expanding)

            // 中間グロー
            Circle()
                .fill(MindWaveTheme.accentGlow.opacity(0.09))
                .frame(width: 220, height: 220)
                .scaleEffect(expanding ? 1.08 : 0.94)
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: expanding)

            // メインリング
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            MindWaveTheme.accent,
                            MindWaveTheme.accentGlow.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 170, height: 170)
                .scaleEffect(expanding ? 1.05 : 0.96)
                .shadow(color: MindWaveTheme.accent.opacity(0.45), radius: 14)
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: expanding)

            // 内側リング（補助）
            Circle()
                .strokeBorder(MindWaveTheme.accent.opacity(0.20), lineWidth: 1)
                .frame(width: 128, height: 128)
                .scaleEffect(expanding ? 0.96 : 1.04)
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: expanding)

            // サブテキスト
            Text("ゆっくり吸って、ゆっくり吐く")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(MindWaveTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 160)
                .offset(y: 100)
        }
        .onAppear { expanding = true }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                // フェーズ2で実装予定
            } label: {
                Text("一時停止")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MindWaveTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            Button {
                // フェーズ2で実装予定
            } label: {
                Text("終了する")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(MindWaveTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    GuideView()
        .preferredColorScheme(.dark)
}
