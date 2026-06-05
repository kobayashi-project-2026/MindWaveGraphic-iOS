//
//  HomeView.swift
//  MindWaveGraphic
//

import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var viewModel: MindWaveViewModel

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

                    // Apple Watch / HealthKit カード
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

    // MARK: - Watch / HealthKit Card

    private var watchConnectionCard: some View {
        VStack(spacing: 14) {
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
                    Text("Apple Watch / HealthKit")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(MindWaveTheme.textPrimary)
                    Text("接続準備中")
                        .font(.caption)
                        .foregroundStyle(MindWaveTheme.textSecondary)
                    Text("許可後、心拍数とHRVを読み取ります")
                        .font(.caption2)
                        .foregroundStyle(MindWaveTheme.textTertiary)
                }

                Spacer()

                Circle()
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: 8, height: 8)
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // HealthKit許可ボタン
            Button {
                Task { await viewModel.requestHealthKitAuthorization() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 14))
                    Text("HealthKitを許可する")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(MindWaveTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(MindWaveTheme.accent.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(MindWaveTheme.accent.opacity(0.30), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Text(viewModel.authorizationStatusMessage)
                .font(.caption2)
                .foregroundStyle(MindWaveTheme.textTertiary)
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
        .environmentObject(MindWaveViewModel())
        .preferredColorScheme(.dark)
}
