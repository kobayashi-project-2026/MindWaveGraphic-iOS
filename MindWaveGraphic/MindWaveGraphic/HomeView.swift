//
//  HomeView.swift
//  MindWaveGraphic
//
//  既存ロジックを維持したUI統合：Cyber UIデザインを適用。
//  Starfield背景はそのまま維持し、Cyber UIパネルをオーバーレイとして追加。
//  HealthKit/Watch取得データのみ表示し、架空の生体値は使用しない。
//

import SwiftUI
import Combine

struct HomeView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @Binding var selectedTab: Int

    // MARK: - UI State（既存・変更なし）
    @State private var elapsed: Int = 0
    @State private var liveDotVisible: Bool = true
    @State private var showDebugSheet = false
    @State private var showAccountSheet = false
    @State private var showSettingsSheet = false

    // MARK: - Timers（既存・変更なし）
    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let blinkTimer   = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    // MARK: - Computed（既存・変更なし）
    private var isHRVWaiting: Bool {
        viewModel.isWatchSampleFresh && !viewModel.didFetchHRV && !viewModel.isMockMode
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── 全画面 Starfield 背景（既存・変更なし）────────────────
            GraphicHostView(input: viewModel.graphicInput)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            // ── Cyber UI オーバーレイ ─────────────────────────────────
            VStack(spacing: 0) {

                // MIND STATUS ヘッダー（新規追加）
                mindStatusHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer()

                // 生体データ Cyber パネル（新規追加）
                biometricCyberPanel
                    .padding(.horizontal, 20)

                // 状態ストーリー（新規追加・実データのみ）
                storyText
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // 計測コントロール（既存・維持）
                measurementButton
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                // ガイドへの導線（既存・維持）
                Button {
                    selectedTab = 1
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "wind")
                            .font(.system(size: 10))
                        Text("今の状態を整える")
                            .font(.system(size: 11, weight: .light))
                    }
                    .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityLabel("ガイドタブを開く")

                // Debug ボタン（DEBUGビルドのみ・既存）
                #if DEBUG
                Button { showDebugSheet = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "ant.circle").font(.system(size: 9))
                        Text("Debug").font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                #endif

                Spacer().frame(height: 20)
            }
        }
        .onAppear {
            elapsed = 0
            print("[CyberUI] home appeared")
        }
        .onChange(of: viewModel.isLiveMonitoring) { _, active in
            if !active { elapsed = 0 }
        }
        .onReceive(sessionTimer) { _ in
            if viewModel.isLiveMonitoring { elapsed += 1 }
        }
        .onReceive(blinkTimer) { _ in
            liveDotVisible = viewModel.isLiveMonitoring ? !liveDotVisible : true
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showAccountSheet) {
            AccountView()
        }
        .sheet(isPresented: $showDebugSheet) {
            DebugDiagnosticsView()
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - MIND STATUS ヘッダー（新規）

    private var mindStatusHeader: some View {
        HStack(alignment: .center) {
            // アプリ名 + 経過時間
            VStack(alignment: .leading, spacing: 2) {
                Text("MIND STATUS")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.cyan.opacity(0.8))
                    .tracking(2)
                if viewModel.isLiveMonitoring {
                    Text(timeString)
                        .font(.system(size: 10, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.40))
                        .transition(.opacity)
                }
            }

            Spacer()

            // LIVE / 接続ステータスバッジ
            MindWaveCyberStatusBadge(
                label: statusLabel,
                isActive: viewModel.isLiveMonitoring
            )
            .animation(.easeInOut(duration: 0.3), value: viewModel.isLiveMonitoring)

            // 設定ボタン（SettingsViewをsheetで表示）
            Button {
                showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .accessibilityLabel("設定を開く")

            // プロフィールボタン（既存動作維持）
            Button { showAccountSheet = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
        }
    }

    // MARK: - 生体データ Cyber パネル（新規）
    // 実データがない場合は「未取得」と表示する。架空の数値は使用しない。

    private var biometricCyberPanel: some View {
        MindWaveCyberPanel(title: "BIOMETRICS") {
            HStack(spacing: 0) {
                MindWaveCyberMetricView(
                    label: "心拍数",
                    value: heartRateDisplay,
                    unit: viewModel.didFetchHeartRate || viewModel.latestWatchHeartRate != nil ? "bpm" : "",
                    accentColor: Color(red: 0.95, green: 0.40, blue: 0.40)
                )

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1, height: 36)

                MindWaveCyberMetricView(
                    label: "HRV",
                    value: hrvDisplay,
                    unit: viewModel.didFetchHRV ? "ms" : "",
                    accentColor: MindWaveCyberTheme.cyan
                )

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1, height: 36)

                MindWaveCyberMetricView(
                    label: "緊張度",
                    value: scoreDisplay,
                    unit: "",
                    accentColor: MindWaveTheme.stressColor(score: viewModel.graphicInput.score)
                )
            }

            if let updateDate = viewModel.lastLiveUpdateDate {
                HStack {
                    Spacer()
                    Text("最終更新 \(updateDateString(updateDate))")
                        .font(.system(size: 9, weight: .light, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: - 状態ストーリー（新規・実データのみ）

    private var storyText: some View {
        Text(storyMessage)
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(.white.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: - 計測ボタン（既存・デザイン統一）

    private var measurementButton: some View {
        Button { viewModel.toggleLiveMonitoring() } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isLiveMonitoring ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 14))
                Text(viewModel.isLiveMonitoring ? "取得停止" : "ライブ取得開始")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(viewModel.isLiveMonitoring
                             ? Color.orange.opacity(0.90) : MindWaveCyberTheme.cyan)
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.isLiveMonitoring
                          ? Color.orange.opacity(0.12)
                          : MindWaveCyberTheme.cyan.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                viewModel.isLiveMonitoring
                                    ? Color.orange.opacity(0.35)
                                    : MindWaveCyberTheme.cyan.opacity(0.35),
                                lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLiveMonitoring)
        .accessibilityLabel(viewModel.isLiveMonitoring ? "計測を停止する" : "ライブ計測を開始する")
        .accessibilityHint(viewModel.isLiveMonitoring ? "Apple Watchからのデータ取得を停止します" : "Apple Watchからリアルタイムでデータを取得します")
    }

    // MARK: - Helpers

    private var timeString: String {
        String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private var statusLabel: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return "LIVE"
        case .healthKit:   return "HK"
        case .mock:        return "MOCK"
        case .unavailable: return "待機中"
        }
    }

    // 実データがない場合は「未取得」と表示する
    private var heartRateDisplay: String {
        guard viewModel.didFetchHeartRate || viewModel.latestWatchHeartRate != nil else { return "未取得" }
        return String(format: "%.0f", viewModel.currentHeartRate)
    }

    private var hrvDisplay: String {
        viewModel.didFetchHRV ? String(format: "%.0f", viewModel.currentHRV) : "未取得"
    }

    private var scoreDisplay: String {
        viewModel.activeDataSource == .unavailable ? "未取得" : String(format: "%.0f", viewModel.graphicInput.score)
    }

    private func updateDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    // 実データ取得状態に基づく状態説明（架空の生体解析は行わない）
    private var storyMessage: String {
        switch viewModel.activeDataSource {
        case .watchLive:
            if viewModel.didFetchHRV {
                return "Apple Watchからデータを取得しています。"
            }
            return "心拍数を取得中です。HRVの取得が完了すると緊張度が計算されます。"
        case .healthKit:
            return "HealthKitからデータを読み込んでいます。"
        case .mock:
            return "Mockデータで表示中です。Apple Watchを接続するとライブデータに切り替わります。"
        case .unavailable:
            return "心拍数とHRVが取得されると、状態の変化をグラフィックで表示します。"
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(MindWaveViewModel())
}
