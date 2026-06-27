//
//  DebugDiagnosticsView.swift
//  MindWaveGraphic
//
//  旧 LiveWaveView の debugSection を独立した診断シートへ抽出。
//  HomeView のデバッグボタンからシートとして表示する。
//  Releaseビルドでもコンパイルされるが、呼び出し元で #if DEBUG を使用すること。
//

import SwiftUI

/// 診断シート。HRV Observer 状態・Watch 接続・GraphicInput・Mock 制御をすべて含む。
/// HomeView の Debug ボタンから presentationDetents でシート表示する。
/// ViewModel は EnvironmentObject で受け取る。データ取得処理はここでは行わない。
struct DebugDiagnosticsView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @State private var demoScenarioIndex = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {

                    // ── ビルド識別 ─────────────────────────────────────
                    debugBlock {
                        debugRow("Build", viewModel.debugBuildLabel)
                    }

                    // ── データソース仲裁 ────────────────────────────────
                    debugBlock {
                        debugRow("Active Source", viewModel.activeDataSource.rawValue)
                        debugRow("Graphic更新時刻", formatTime(viewModel.lastGraphicUpdateDate))
                        debugRow("Watch経過秒",
                                 viewModel.watchSampleAge.map { String(format: "%.0f秒", $0) } ?? "---")
                        debugRow("Watch鮮度",
                                 viewModel.watchSampleAge == nil ? "未受信"
                                 : viewModel.isWatchSampleFresh ? "Fresh ✓" : "Expired")
                        debugRow("Mock", viewModel.isMockMode ? "ON" : "OFF")
                    }

                    // ── Mockモード制御 ──────────────────────────────────
                    mockControlSection

                    // ── GraphicInput（パイプライン出力） ────────────────
                    debugBlock {
                        debugRow("GraphicInput.score",
                                 String(format: "%.1f", viewModel.graphicInput.score))
                        debugRow("GraphicInput.confidence",
                                 String(format: "%.2f", viewModel.graphicInput.confidence))
                        debugRow("GraphicInput.state",
                                 viewModel.graphicInput.state.displayName)
                    }

                    // ── Watch ライブ心拍 ────────────────────────────────
                    debugBlock {
                        debugRow("Watch心拍", viewModel.latestWatchHeartRate != nil
                                 ? String(format: "%.0f bpm", viewModel.latestWatchHeartRate!)
                                 : "未受信")
                        debugRow("Watch受信数", "\(viewModel.watchMessageCount) 回")
                        debugRow("Watch最終",   formatTime(viewModel.latestWatchHeartRateDate))
                        debugRow("WCSession",   WatchConnectivityManager.shared.watchConnectionStatusLabel)
                        debugRow("Activation",  WatchConnectivityManager.shared.wcActivationStateLabel)
                        debugRow("Reachable",   WatchConnectivityManager.shared.isWatchReachable ? "YES ✓" : "NO")
                        debugRow("Paired",      WatchConnectivityManager.shared.isWatchPaired ? "YES ✓" : "NO")
                        debugRow("App導入",     WatchConnectivityManager.shared.isWatchAppInstalled ? "YES ✓" : "NO")
                    }

                    // ── ライブ監視状態 ──────────────────────────────────
                    debugBlock {
                        debugRow("監視状態",  viewModel.liveMonitoringMessage)
                        debugRow("更新回数",  "\(viewModel.liveUpdateCount) 回")
                        debugRow("取得間隔",  "\(Int(viewModel.liveUpdateInterval)) 秒")
                        debugRow("最終取得",  formatTime(viewModel.lastLiveUpdateDate))
                    }

                    // ── 心拍・HRVサンプル ───────────────────────────────
                    debugBlock {
                        debugRow("心拍数", viewModel.didFetchHeartRate
                                 ? String(format: "%.0f bpm", viewModel.currentHeartRate)
                                 : "未取得")
                        debugRow("心拍サンプル時刻", formatTime(viewModel.latestHeartRateSampleDate))
                        debugRow("心拍サンプル更新", viewModel.isNewHeartRateSample ? "新規 ✓" : "同じ")
                        debugRow("同じサンプル継続",  "\(viewModel.sameSampleCount) 回")
                        debugRow("HRV（SDNN）", viewModel.didFetchHRV
                                 ? String(format: "%.0f ms", viewModel.currentHRV)
                                 : "未取得")
                        debugRow("HRVサンプル時刻",  formatTime(viewModel.latestHRVSampleDate))
                        debugRow("HRVサンプル更新",  viewModel.isNewHRVSample ? "新規 ✓" : "同じ")
                    }

                    // ── HRV Observer ──────────────────────────────────
                    debugBlock {
                        debugRow("HRV監視",       viewModel.isHRVObserverActive ? "稼働中 ●" : "停止中")
                        debugRow("HRV監視方式",   "HKAnchoredObjectQuery")
                        debugRow("HRV実測取得",   viewModel.didFetchHRV ? "済 ✓" : "未取得")
                        debugRow("HRV取得元",     viewModel.lastHRVFetchSource)
                        debugRow("HRV新規受理",   "\(viewModel.hrvManagerAcceptedCount) 件")
                        debugRow("HRV重複除外",   "\(viewModel.hrvManagerDuplicateCount) 件")
                        debugRow("HRV古値除外",   "\(viewModel.hrvManagerStaleCount) 件")
                        debugRow("HRV新規受信",   "\(viewModel.hrvObserverUpdateCount) 回")
                        debugRow("HRV最終通知",   formatTime(viewModel.lastHRVObserverDate))
                        debugRow("HRV経過",       hrvAgeString(viewModel.latestHRVSampleDate))
                        debugRow("HRV終了時刻",   formatTime(viewModel.latestHRVEndDate))
                        debugRow("HRV Source",    viewModel.latestHRVSourceName ?? "---")
                        debugRow("HRV Bundle",    shortBundleID(viewModel.latestHRVBundleID))
                        debugRow("HRV初回Query",  viewModel.hrvInitialQueryStatus)
                        debugRow("Graphic更新契機", viewModel.lastGraphicUpdateTrigger)
                    }

                    // ── HRV 手動診断（DEBUGのみ） ──────────────────────
                    VStack(spacing: 6) {
                        // 診断ボタン
                        Button {
                            Task {
                                await viewModel.runHRVDiagnostic()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "heart.text.square")
                                    .font(.system(size: 10))
                                Text("HRVを再取得・診断")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(MindWaveTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(MindWaveTheme.accent.opacity(0.10)))
                        }
                        .buttonStyle(.plain)

                        // 診断結果
                        debugBlock {
                            debugRow("HRV診断件数", viewModel.hrvDiagnosticSamples.isEmpty
                                     && viewModel.hrvDiagnosticError == nil
                                     && viewModel.hrvInitialQueryStatus == "未実行"
                                     ? "未実行"
                                     : "\(viewModel.hrvDiagnosticSamples.count) 件")
                            debugRow("HRV Queryエラー", viewModel.hrvDiagnosticError ?? "なし")
                            if let s = viewModel.hrvDiagnosticSamples.first {
                                debugRow("最新HRV値",    String(format: "%.1f ms", s.valueMilliseconds))
                                debugRow("最新HRV開始",  formatTime(s.startDate))
                                debugRow("最新HRV終了",  formatTime(s.endDate))
                                debugRow("最新HRV Source", s.sourceName)
                                debugRow("最新HRV Bundle", shortBundleID(s.sourceBundleIdentifier))
                                debugRow("最新HRV UUID", String(s.uuid.uuidString.prefix(8)))
                                debugRow("最新HRV Device", s.deviceName ?? "---")
                            } else if viewModel.hrvInitialQueryStatus != "未実行" {
                                Text("HealthKitにHRVサンプルが見つかりません。\nHealthアプリで「心臓→心拍変動」を確認してください。")
                                    .font(.system(size: 9, weight: .light))
                                    .foregroundStyle(MindWaveTheme.textTertiary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(MindWaveTheme.accent.opacity(0.15), lineWidth: 1))
                    )

                    // ── スコア計算 ─────────────────────────────────────
                    debugBlock {
                        debugRow("スコア（計算値）", String(format: "%.1f", viewModel.stressResult.stressScore))
                        debugRow("GraphicInput.score", String(format: "%.1f", viewModel.graphicInput.score))
                        debugRow("livePulseTrigger", "\(viewModel.livePulseTrigger)")
                        debugRow("データ元",          viewModel.dataSourceLabel)
                        debugRow("メッセージ",         viewModel.lastFetchMessage)
                    }

                    // ── サンプリング注記 ────────────────────────────────
                    Text(viewModel.healthKitSamplingNote)
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // ── デモシナリオ切り替え ─────────────────────────────
                    Text("デモシナリオ（StressScoreCalculator経由）")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        ForEach(MindSampleScenario.allScenarios.indices, id: \.self) { i in
                            let isSelected = demoScenarioIndex == i
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    demoScenarioIndex = i
                                    viewModel.loadDemoScenario(index: i)
                                }
                            } label: {
                                Text(MindSampleScenario.allScenarios[i].name)
                                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                                    .foregroundStyle(isSelected ? Color.black : MindWaveTheme.textTertiary)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected
                                                  ? MindWaveTheme.accent.opacity(0.7)
                                                  : Color.white.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(MindWaveTheme.background.ignoresSafeArea())
            .navigationTitle("診断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(MindWaveTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Mock Control Section

    private var mockControlSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Mockモード")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MindWaveTheme.textTertiary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.isMockMode },
                    set: { viewModel.setMockMode($0) }
                ))
                .labelsHidden()
                .scaleEffect(0.7)
                .tint(MindWaveTheme.accent)
            }

            if viewModel.isMockMode {
                HStack(spacing: 4) {
                    ForEach(MindState.allCases, id: \.self) { state in
                        let scores: [MindState: Double] = [
                            .underAroused: 15, .optimalTension: 50, .overTense: 85
                        ]
                        let isSelected = viewModel.graphicInput.state == state
                        Button {
                            viewModel.mockScore = scores[state] ?? 50
                            viewModel.sendMockSample()
                        } label: {
                            Text(state.displayName)
                                .font(.system(size: 9, weight: isSelected ? .medium : .regular))
                                .foregroundStyle(isSelected ? Color.black : MindWaveTheme.textTertiary)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected
                                              ? MindWaveTheme.accent.opacity(0.7)
                                              : Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 2) {
                    HStack {
                        Text("Score")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                        Spacer()
                        Text(String(format: "%.0f", viewModel.mockScore))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MindWaveTheme.textSecondary)
                    }
                    Slider(value: Binding(
                        get: { viewModel.mockScore },
                        set: { viewModel.mockScore = $0; viewModel.sendMockSample() }
                    ), in: 0...100)
                    .tint(MindWaveTheme.accent)
                }

                VStack(spacing: 2) {
                    HStack {
                        Text("Confidence")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                        Spacer()
                        Text(String(format: "%.2f", viewModel.mockConfidence))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MindWaveTheme.textSecondary)
                    }
                    Slider(value: Binding(
                        get: { viewModel.mockConfidence },
                        set: { viewModel.mockConfidence = $0; viewModel.sendMockSample() }
                    ), in: 0...1)
                    .tint(MindWaveTheme.accent)
                }

                Button {
                    viewModel.toggleMockAutoUpdate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isMockAutoUpdate
                              ? "stop.circle.fill" : "arrow.clockwise.circle")
                            .font(.system(size: 9))
                        Text(viewModel.isMockAutoUpdate ? "自動更新停止" : "5秒ごと自動更新")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(viewModel.isMockAutoUpdate
                                     ? Color.orange.opacity(0.8) : MindWaveTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(viewModel.isMockAutoUpdate
                                  ? Color.orange.opacity(0.10)
                                  : MindWaveTheme.accent.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(MindWaveTheme.accent.opacity(0.20), lineWidth: 1)
                )
        )
    }

    // MARK: - Debug Helpers

    private func debugBlock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 4) { content() }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
            )
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MindWaveTheme.textSecondary)
        }
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "---" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func hrvAgeString(_ date: Date?) -> String {
        guard let date else { return "---" }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        return minutes < 1 ? "1分未満" : "\(minutes)分"
    }

    /// Bundle IDを末尾20文字に短縮して表示する（長くなりすぎないよう）
    private func shortBundleID(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "---" }
        return id.count > 20 ? "..." + String(id.suffix(20)) : id
    }
}

#Preview {
    DebugDiagnosticsView()
        .environmentObject(MindWaveViewModel())
}
