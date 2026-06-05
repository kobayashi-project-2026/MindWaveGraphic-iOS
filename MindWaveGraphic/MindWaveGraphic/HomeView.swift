//
//  HomeView.swift
//  MindWaveGraphic
//

import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: Int

    var body: some View {
        ZStack {
            MindWaveTheme.backgroundGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // Header
                    VStack(spacing: 8) {
                        Text("Mind Wave")
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundStyle(MindWaveTheme.textPrimary)
                            .tracking(3)
                        Text("いまの自分を、流れで知る。")
                            .font(.subheadline)
                            .foregroundStyle(MindWaveTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    // Apple Watch 接続カード
                    watchConnectionCard

                    // 準備チェックリスト
                    preparationCard

                    // セッション開始ボタン
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 1 }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                            Text("セッションを開始")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(MindWaveTheme.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Watch Card

    private var watchConnectionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MindWaveTheme.accentGlow.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "applewatch")
                    .font(.system(size: 22))
                    .foregroundStyle(MindWaveTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Watch")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MindWaveTheme.textPrimary)
                Text("接続準備中")
                    .font(.caption)
                    .foregroundStyle(MindWaveTheme.textSecondary)
                Text("フェーズ2でHealthKit連携予定")
                    .font(.caption2)
                    .foregroundStyle(MindWaveTheme.textTertiary)
            }

            Spacer()

            // 未接続インジケーター
            Circle()
                .fill(Color.orange.opacity(0.85))
                .frame(width: 8, height: 8)
        }
        .padding(16)
        .darkCard()
    }

    // MARK: - Preparation Card

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("準備チェック")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
                .tracking(1.2)
                .textCase(.uppercase)

            VStack(spacing: 10) {
                CheckItem(label: "装着の確認")
                CheckItem(label: "センサーの準備")
                CheckItem(label: "静かな環境を選ぶ")
            }
        }
        .padding(16)
        .darkCard()
    }
}

// MARK: - Check Item

private struct CheckItem: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(MindWaveTheme.accent)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(MindWaveTheme.textPrimary)
            Spacer()
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .preferredColorScheme(.dark)
}
