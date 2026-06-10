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

                    // ─── タイトル ────────────────────────────────
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

                    // ─── Apple Watch / HealthKit カード ──────────
                    watchConnectionCard

                    // ─── Watch ライブ心拍 状態カード ──────────────
                    watchLiveHeartRateCard

                    // ─── ライブ取得状態カード ─────────────────────
                    liveStatusCard

                    // ─── 準備チェック ─────────────────────────────
                    preparationCard

                    // ─── ライブ波形へ移動 ─────────────────────────
                    // ライブ画面に入ったら「ライブ取得開始」ボタンで自動取得を開始できる。
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

    // MARK: - Watch ライブ心拍 状態カード

    /// Apple Watch アプリから WatchConnectivity で受信した心拍数の状態を表示する。
    private var watchLiveHeartRateCard: some View {
        let wcManager = WatchConnectivityManager.shared
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "applewatch.watchface")
                    .font(.system(size: 13))
                    .foregroundStyle(MindWaveTheme.accent)
                Text("Watch ライブ心拍")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                    .tracking(1.2)
                Spacer()
                // Watchから受信があれば緑ドット
                Circle()
                    .fill(viewModel.latestWatchHeartRate != nil
                          ? MindWaveTheme.accent : Color.gray.opacity(0.4))
                    .frame(width: 6, height: 6)
            }

            statusRow("Watchライブ状態",
                      value: viewModel.latestWatchHeartRate != nil ? "受信中 ✓" : "未受信",
                      isOK: viewModel.latestWatchHeartRate != nil)
            statusRow("Watch心拍数",
                      value: viewModel.latestWatchHeartRate != nil
                          ? String(format: "%.0f bpm", viewModel.latestWatchHeartRate!)
                          : "---",
                      isOK: viewModel.latestWatchHeartRate != nil)
            statusRow("Watch受信回数",  value: "\(viewModel.watchMessageCount) 回",
                      isOK: viewModel.watchMessageCount > 0)
            statusRow("Watch最終受信",  value: formatTime(viewModel.latestWatchHeartRateDate))
            statusRow("WCSession",     value: wcManager.watchConnectionStatusLabel,
                      isOK: wcManager.watchConnectionStatusLabel == "接続済み")
            statusRow("受信チャネル",   value: wcManager.lastReceiveChannel)
            statusRow("データ元",       value: viewModel.dataSourceLabel,
                      isOK: !viewModel.isUsingDemoData)

            // 診断用: 最後に受信した生ペイロードの内容
            Divider().background(Color.white.opacity(0.08))
            VStack(alignment: .leading, spacing: 2) {
                Text("最終受信ペイロード（診断）")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                Text(wcManager.lastPayloadDebug)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(viewModel.latestWatchHeartRate != nil
                                     ? MindWaveTheme.accent : Color.orange.opacity(0.8))
            }

            // Watch未受信時の案内テキスト
            if viewModel.latestWatchHeartRate == nil {
                Text("Apple WatchでMind Waveアプリを開き「計測開始」を押してください。")
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                    .multilineTextAlignment(.leading)
            } else {
                Text(viewModel.lastWatchMessage)
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(MindWaveTheme.textTertiary)
            }
        }
        .padding(16)
        .darkCard()
    }

    // MARK: - Watch / HealthKit カード

    private var watchConnectionCard: some View {
        VStack(spacing: 14) {
            // ── 接続状態表示 ─────────────────────────────────
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
                    Text(viewModel.healthKitStatusLabel)
                        .font(.caption)
                        .foregroundStyle(MindWaveTheme.textSecondary)
                    Text("許可後、心拍数とHRVを読み取ります")
                        .font(.caption2)
                        .foregroundStyle(MindWaveTheme.textTertiary)
                }
                Spacer()
                Circle()
                    .fill(viewModel.isUsingDemoData ? Color.orange.opacity(0.85) : MindWaveTheme.accent)
                    .frame(width: 8, height: 8)
            }

            Divider().background(Color.white.opacity(0.08))

            // ── HealthKit許可ボタン ──────────────────────────
            Button {
                Task { await viewModel.requestHealthKitAuthorization() }
            } label: {
                iconButton(icon: "heart.text.square.fill", label: "HealthKitを許可する",
                           color: MindWaveTheme.accent)
            }
            .buttonStyle(.plain)

            // ── 1回取得ボタン ────────────────────────────────
            Button {
                Task { await viewModel.fetchHealthKitData() }
            } label: {
                iconButton(icon: "arrow.clockwise.heart", label: "身体データを1回読み取る",
                           color: MindWaveTheme.textPrimary, fillOpacity: 0.07)
            }
            .buttonStyle(.plain)

            // ── ライブ取得 開始 / 停止 ─────────────────────
            // ホーム画面からも開始でき、タブ移動しても停止しない。
            Button {
                viewModel.toggleLiveMonitoring()
            } label: {
                iconButton(
                    icon: viewModel.isLiveMonitoring ? "stop.circle.fill" : "waveform.badge.plus",
                    label: viewModel.isLiveMonitoring ? "ライブ取得を停止" : "ライブ取得を開始",
                    color: viewModel.isLiveMonitoring ? Color.orange : MindWaveTheme.accent,
                    fillOpacity: 0.10
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .darkCard()
    }

    /// アイコン + テキストのボタンラベル共通スタイル
    private func iconButton(icon: String, label: String,
                            color: Color, fillOpacity: Double = 0.10) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 14))
            Text(label).font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(fillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(color.opacity(0.30), lineWidth: 1)
                )
        )
    }

    // MARK: - ライブ取得状態カード

    private var liveStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("取得状態")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                    .tracking(1.2)
                    .textCase(.uppercase)
                Spacer()
                // ビルド識別ラベル（実機で最新ビルドか確認するために表示する）
                Text("Build: \(viewModel.debugBuildLabel)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(MindWaveTheme.textTertiary)
            }

            statusRow("ライブ状態",
                      value: viewModel.isLiveMonitoring ? "ライブ取得中" : "停止中",
                      isOK: viewModel.isLiveMonitoring)
            statusRow("更新回数",    value: "\(viewModel.liveUpdateCount) 回", isOK: viewModel.liveUpdateCount > 0)
            statusRow("最終取得",    value: formatTime(viewModel.lastLiveUpdateDate))
            statusRow("データ元",    value: viewModel.dataSourceLabel,
                      isOK: !viewModel.isUsingDemoData)
            statusRow("心拍数",
                      value: viewModel.didFetchHeartRate
                          ? String(format: "%.0f bpm", viewModel.currentHeartRate)
                          : "未取得",
                      isOK: viewModel.didFetchHeartRate)
            statusRow("心拍サンプル時刻", value: formatTime(viewModel.latestHeartRateSampleDate))
            statusRow("新規サンプル",
                      value: viewModel.didFetchHeartRate
                          ? (viewModel.isNewHeartRateSample ? "あり ✓" : "なし（同じサンプル）")
                          : "---",
                      isOK: viewModel.isNewHeartRateSample)
            statusRow("同じサンプル継続", value: "\(viewModel.sameSampleCount) 回")
            statusRow("HRV（SDNN）",
                      value: viewModel.didFetchHRV
                          ? String(format: "%.0f ms", viewModel.currentHRV)
                          : "未取得",
                      isOK: viewModel.didFetchHRV)

            if !viewModel.lastFetchMessage.isEmpty {
                Text(viewModel.lastFetchMessage)
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Apple Watch同期の注意書き
            Text(viewModel.healthKitSamplingNote)
                .font(.system(size: 9, weight: .light))
                .foregroundStyle(MindWaveTheme.textTertiary)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .darkCard()
    }

    private func statusRow(_ label: String, value: String, isOK: Bool = true) -> some View {
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

    // MARK: - 準備チェック

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

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "---" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

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
