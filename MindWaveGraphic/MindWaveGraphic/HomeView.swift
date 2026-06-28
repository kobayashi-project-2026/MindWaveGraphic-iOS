//
//  HomeView.swift
//  MindWaveGraphic
//
//  コックピット内部からの前方視点。宇宙空間グラフィックが主役。
//  ダッシュボード下部にPULSE / HRV / 計測ボタン / QUICK WORK をコンパクト配置。
//  架空の値は使用しない。データ未取得時は「—」で表示する。
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @Binding var selectedTab: Int

    @State private var showSettingsSheet  = false
    @State private var showDebugSheet     = false
    @State private var showBreathingSheet = false
    @State private var breathingMode: MindWaveBreathingMode = .fourSevenEight
    @State private var showStatusDetail   = false

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            // 画面高さに応じて比率を調整（小型iPhone対応）
            let ratio: CGFloat = geo.size.height > 780 ? 0.59 : 0.52
            let graphicH = geo.size.height * ratio
            let safeTop  = geo.safeAreaInsets.top

            ZStack(alignment: .top) {
                // 宇宙空間背景
                Color(red: 0.00, green: 0.01, blue: 0.06)

                // ── ワープグラフィック（上部・ステータスバー背後まで延伸）
                GraphicHostView(input: viewModel.graphicInput)
                    .frame(maxWidth: .infinity)
                    .frame(height: graphicH)

                // ── ヘッダーオーバーレイ
                cockpitHeader
                    .padding(.top, safeTop + 8)
                    .padding(.horizontal, 18)

                // ── コックピットダッシュボード（下部固定）
                VStack(spacing: 0) {
                    Spacer(minLength: graphicH)
                    cockpitDashboard(geo: geo)
                        .padding(.bottom, 76)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { print("[CockpitHome] appeared") }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showDebugSheet) {
            DebugDiagnosticsView()
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showStatusDetail) {
            statusDetailSheet
        }
        .fullScreenCover(isPresented: $showBreathingSheet) {
            BreathingFromHomeWrapper(initialMode: breathingMode)
        }
    }

    // MARK: - ヘッダー（グラフィック上フロート）

    private var cockpitHeader: some View {
        HStack(spacing: 8) {
            // 接続状態インジケーター
            Button {
                showStatusDetail = true
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: indicatorColor.opacity(0.9), radius: 3)
                    Text(shortStatusLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .tracking(0.6)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("MIND WAVE")
                    .font(.system(size: 11, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .tracking(3.5)
                Text("STRESS & BIOMETRICS")
                    .font(.system(size: 7, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.22))
                    .tracking(1.8)
            }

            Spacer()

            HStack(spacing: 14) {
                #if DEBUG
                Button {
                    showDebugSheet = true
                    print("[CockpitHome] debug_sheet_opened")
                } label: {
                    Image(systemName: "ant.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.22))
                }
                .buttonStyle(.plain)
                #endif
                Button {
                    showSettingsSheet = true
                    print("[CockpitHome] settings_opened")
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 36)
    }

    // MARK: - コックピットダッシュボード

    private func cockpitDashboard(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // 計測行：PULSE | メインボタン | HRV
            HStack(alignment: .center, spacing: 0) {
                pulsePanel
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 22)

                mainLaunchButton

                hrvPanel
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 22)
            }
            .padding(.top, 18)

            // サブボタン（整える / 履歴）
            secondaryButtons
                .padding(.top, 14)

            // QUICK WORK カード
            quickWorkRow
                .padding(.top, 14)

            Spacer(minLength: 8)
        }
        .background(dashboardBackground)
    }

    // MARK: - ダッシュボード背景

    private var dashboardBackground: some View {
        CockpitPanelShape(chamfer: 20)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.07, blue: 0.16),
                        Color(red: 0.02, green: 0.03, blue: 0.09)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                CockpitPanelShape(chamfer: 20)
                    .stroke(Color.cyan.opacity(0.20), lineWidth: 0.8)
            )
    }

    // MARK: - PULSE パネル

    private var pulsePanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PULSE")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.cyan.opacity(0.65))
                .tracking(1.2)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(heartRateDisplay)
                    .font(.system(size: 34, weight: .thin, design: .rounded))
                    .foregroundStyle(hasRealHeartRate ? Color.cyan : Color.white.opacity(0.22))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: heartRateDisplay)
                Text("BPM")
                    .font(.system(size: 9, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.30))
            }

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 13))
                .foregroundStyle(Color.cyan.opacity(hasRealHeartRate ? 0.45 : 0.18))
        }
    }

    // MARK: - HRV パネル

    private var hrvPanel: some View {
        let hGreen = Color(red: 0.20, green: 0.85, blue: 0.60)
        let hasHRV = viewModel.didFetchHRV
        let hrvText = hasHRV ? String(format: "%.0f", viewModel.currentHRV) : "—"

        return VStack(alignment: .trailing, spacing: 4) {
            Text("HRV")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(hGreen.opacity(0.65))
                .tracking(1.2)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(hrvText)
                    .font(.system(size: 34, weight: .thin, design: .rounded))
                    .foregroundStyle(hasHRV ? hGreen : Color.white.opacity(0.22))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: viewModel.currentHRV)
                Text("ms")
                    .font(.system(size: 9, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.30))
            }

            // 信号バー（HRVレベル表示）
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < hrvBarCount
                            ? hGreen.opacity(0.65)
                            : Color.white.opacity(0.12))
                        .frame(width: 4, height: CGFloat(6 + i * 3))
                }
            }
        }
    }

    private var hrvBarCount: Int {
        guard viewModel.didFetchHRV else { return 0 }
        let hrv = viewModel.currentHRV
        if hrv < 20 { return 1 }
        if hrv < 40 { return 2 }
        if hrv < 60 { return 3 }
        if hrv < 80 { return 4 }
        return 5
    }

    // MARK: - メイン計測ボタン

    private var mainLaunchButton: some View {
        Button {
            viewModel.toggleLiveMonitoring()
            print("[CockpitHome] monitoring toggled")
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    // 外リング（装飾）
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: 108, height: 108)
                    // アクティブリング
                    Circle()
                        .stroke(
                            isLive ? Color.orange.opacity(0.55) : Color.cyan.opacity(0.50),
                            lineWidth: 1.5
                        )
                        .frame(width: 90, height: 90)
                        .shadow(color: isLive ? .orange.opacity(0.30) : .cyan.opacity(0.30),
                                radius: 6)
                    // 内円
                    Circle()
                        .fill(
                            isLive
                            ? Color(red: 0.14, green: 0.05, blue: 0.02)
                            : Color(red: 0.04, green: 0.14, blue: 0.24)
                        )
                        .frame(width: 78, height: 78)
                    // センターアイコン
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(isLive ? Color.orange : Color.cyan)
                }
                Text(isLive ? "計測停止" : "計測開始")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(
                        isLive ? Color.orange.opacity(0.85) : Color.white.opacity(0.70)
                    )
                    .tracking(0.5)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: isLive)
        .accessibilityLabel(isLive ? "計測を停止する" : "ライブ計測を開始する")
    }

    // MARK: - サブボタン（整える / 履歴）

    private var secondaryButtons: some View {
        HStack(spacing: 36) {
            secondaryActionButton(icon: "wind", label: "整える") {
                selectedTab = 1
            }
            secondaryActionButton(icon: "chart.bar", label: "履歴") {
                selectedTab = 2
            }
        }
    }

    private func secondaryActionButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - QUICK WORK 3カード行

    private var quickWorkRow: some View {
        HStack(spacing: 10) {
            quickCard(mode: .fourSevenEight, label: "4-7-8",
                      desc: "深い弛緩",    icon: "moon.stars")
            quickCard(mode: .box,           label: "BOX",
                      desc: "集中と安定",  icon: "square")
            quickCard(mode: .twoOneFour,    label: "2-1-4",
                      desc: "緊張を手放す", icon: "leaf")
        }
        .padding(.horizontal, 16)
    }

    private func quickCard(
        mode: MindWaveBreathingMode,
        label: String,
        desc: String,
        icon: String
    ) -> some View {
        Button {
            print("[CockpitHome] quick work mode=\(mode.displayName)")
            breathingMode = mode
            showBreathingSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.cyan.opacity(0.72))
                Spacer(minLength: 2)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.04, green: 0.06, blue: 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label)呼吸法")
        .accessibilityHint(desc)
    }

    // MARK: - ステータス詳細シート

    private var statusDetailSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(narrativeTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text(narrativeBody)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider().overlay(Color.white.opacity(0.12))

                    HStack(spacing: 0) {
                        metricItem(label: "データソース",
                                   value: dataSourceLabel,
                                   accent: indicatorColor)
                        Divider().frame(height: 28)
                            .background(Color.white.opacity(0.10))
                        metricItem(
                            label: "HRV",
                            value: viewModel.didFetchHRV
                                ? String(format: "%.0f ms", viewModel.currentHRV)
                                : "—",
                            accent: viewModel.didFetchHRV
                                ? Color.cyan
                                : Color.white.opacity(0.25)
                        )
                        Divider().frame(height: 28)
                            .background(Color.white.opacity(0.10))
                        metricItem(
                            label: "状態",
                            value: viewModel.isLiveMonitoring ? "計測中" : "停止中",
                            accent: viewModel.isLiveMonitoring
                                ? Color.cyan
                                : Color.white.opacity(0.35)
                        )
                    }
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.03, green: 0.03, blue: 0.08).ignoresSafeArea())
            .navigationTitle("ミッションステータス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { showStatusDetail = false }
                        .foregroundStyle(Color.cyan)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func metricItem(label: String, value: String, accent: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 計算プロパティ

    private var isLive: Bool { viewModel.isLiveMonitoring }

    private var indicatorColor: Color {
        switch viewModel.activeDataSource {
        case .watchLive:   return .cyan
        case .healthKit:   return Color(red: 0.20, green: 0.85, blue: 0.60)
        case .mock:        return .orange
        case .unavailable: return Color.white.opacity(0.25)
        }
    }

    private var shortStatusLabel: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return viewModel.isLiveMonitoring ? "LIVE" : "WATCH READY"
        case .healthKit:   return "HEALTHKIT"
        case .mock:        return "DEMO"
        case .unavailable: return "STANDBY"
        }
    }

    private var hasRealHeartRate: Bool {
        viewModel.latestWatchHeartRate != nil || viewModel.didFetchHeartRate
    }

    private var heartRateDisplay: String {
        if let w = viewModel.latestWatchHeartRate { return String(format: "%.0f", w) }
        if viewModel.didFetchHeartRate            { return String(format: "%.0f", viewModel.currentHeartRate) }
        return "—"
    }

    private var dataSourceLabel: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return "Watch Live"
        case .healthKit:   return "HealthKit"
        case .mock:        return "デモ"
        case .unavailable: return "未接続"
        }
    }

    private var narrativeTitle: String {
        switch viewModel.activeDataSource {
        case .watchLive:
            return viewModel.isLiveMonitoring
                ? (viewModel.didFetchHRV ? "リアルタイム計測中" : "接続中 — HRV取得待ち")
                : "計測を開始できます"
        case .healthKit:   return "HealthKitから読み込み中"
        case .mock:        return "デモモード"
        case .unavailable: return "データを待っています"
        }
    }

    private var narrativeBody: String {
        switch viewModel.activeDataSource {
        case .watchLive:
            return viewModel.didFetchHRV
                ? "状態グラフィックが現在の心理的揺らぎを反映しています。"
                : "Apple Watchを装着したまましばらくお待ちください。"
        case .healthKit:   return "HealthKitに記録された最新データを表示しています。"
        case .mock:        return "Apple Watchと接続すると実データへ切り替わります。"
        case .unavailable: return "計測を開始するとApple Watchからデータが届きます。"
        }
    }
}

// MARK: - 呼吸ガイド遷移ラッパー

private struct BreathingFromHomeWrapper: View {
    let initialMode: MindWaveBreathingMode
    @State private var syncDone = false

    var body: some View {
        if syncDone {
            MindWaveBreathingGuideView(initialMode: initialMode)
        } else {
            MindWaveSyncTransitionView(subtitle: "呼吸ガイドを準備しています") {
                syncDone = true
            }
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(MindWaveViewModel())
}
