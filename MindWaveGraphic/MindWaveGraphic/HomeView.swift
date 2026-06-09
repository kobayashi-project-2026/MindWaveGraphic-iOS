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

                    // ─── アプリタイトル ────────────────────────────
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

                    // ─── Apple Watch / HealthKit カード ────────────
                    watchConnectionCard

                    // ─── 診断カード（実機でデータ確認用）─────────────
                    diagnosticCard

                    // ─── 準備チェックリスト ───────────────────────
                    preparationCard

                    // ─── ライブ波形へ移動ボタン ───────────────────
                    // ライブ画面に入ったら「ライブ取得開始」で自動更新を開始できる。
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 1 }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                            Text("ライブ波形を見る")
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

    // MARK: - Watch / HealthKit カード

    private var watchConnectionCard: some View {
        VStack(spacing: 14) {
            // ── 接続状態表示 ──────────────────────────
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

                // 接続状態インジケーター（未接続=橙、接続中=青）
                Circle()
                    .fill(viewModel.isUsingDemoData
                          ? Color.orange.opacity(0.85)
                          : MindWaveTheme.accent)
                    .frame(width: 8, height: 8)
            }

            Divider().background(Color.white.opacity(0.08))

            // ── HealthKit許可ボタン ──────────────────────
            // HealthKitの読み取り権限をリクエストする。
            // 許可が取れた後に身体データ取得ボタンを押すことで実データが波形に反映される。
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

            // ── 身体データ取得ボタン ─────────────────────
            // 許可済みの場合、HealthKitから心拍数・HRVを読み取り波形に反映する。
            // Apple WatchのデータがiPhoneのヘルスケアに同期されている必要がある。
            Button {
                Task { await viewModel.fetchHealthKitData() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise.heart")
                        .font(.system(size: 14))
                    Text("身体データを読み取る")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(MindWaveTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // HealthKit状態ラベル
            Text(viewModel.healthKitStatusLabel)
                .font(.caption2)
                .foregroundStyle(MindWaveTheme.textTertiary)
        }
        .padding(16)
        .darkCard()
    }

    // MARK: - 診断カード（取得状態の確認）

    /// 実機でデータが取れているかを確認するための診断表示。
    /// HealthKit許可・取得を試みた後にここで結果を確認できる。
    private var diagnosticCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("取得状態")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
                .tracking(1.2)
                .textCase(.uppercase)

            // データ元
            diagRow(
                label: "データ元",
                value: viewModel.dataSourceLabel,
                isOK: !viewModel.isUsingDemoData
            )
            // 心拍数取得
            diagRow(
                label: "心拍数",
                value: viewModel.didFetchHeartRate
                    ? String(format: "%.0f bpm", viewModel.currentHeartRate)
                    : "未取得",
                isOK: viewModel.didFetchHeartRate
            )
            // HRV取得
            diagRow(
                label: "HRV（SDNN）",
                value: viewModel.didFetchHRV
                    ? String(format: "%.0f ms", viewModel.currentHRV)
                    : "未取得",
                isOK: viewModel.didFetchHRV
            )
            // 最終取得時刻
            diagRow(
                label: "最終取得",
                value: viewModel.lastFetchDate.map {
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm:ss"
                    return f.string(from: $0)
                } ?? "未取得",
                isOK: viewModel.lastFetchDate != nil
            )

            // 取得メッセージ（問題がある場合に理由が分かる）
            if !viewModel.lastFetchMessage.isEmpty {
                Text(viewModel.lastFetchMessage)
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .darkCard()
    }

    /// 診断カードの1行表示（OK=青、NG=橙）
    private func diagRow(label: String, value: String, isOK: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(MindWaveTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOK ? MindWaveTheme.accent : Color.orange.opacity(0.8))
        }
    }

    // MARK: - 準備チェックリスト

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("準備チェック")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
                .tracking(1.2)
                .textCase(.uppercase)

            VStack(spacing: 10) {
                CheckItem(label: "Apple Watchを装着する")
                CheckItem(label: "ヘルスケアアプリで心拍数を確認する")
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
