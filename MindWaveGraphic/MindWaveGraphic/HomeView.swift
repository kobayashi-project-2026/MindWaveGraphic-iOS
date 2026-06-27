//
//  HomeView.swift
//  MindWaveGraphic
//
//  ホーム画面。GraphicHostViewを主役とし、状態説明・メトリクス・CTAを補助表示する。
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

    // MARK: - Body

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                compactHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        stateCanvas
                            .padding(.horizontal, 16)
                        stateNarrative
                            .padding(.horizontal, 20)
                        metricsRow
                            .padding(.horizontal, 20)
                        regulationSection
                        primaryAction
                            .padding(.horizontal, 20)
                        Spacer().frame(height: 96)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onAppear { print("[UI][Home] view_appeared") }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showDebugSheet) {
            DebugDiagnosticsView()
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showBreathingSheet) {
            BreathingFromHomeWrapper(initialMode: breathingMode)
        }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.06).ignoresSafeArea()
            CyberGridShape(cellSize: 44)
                .stroke(Color.cyan.opacity(0.025), lineWidth: 0.5)
                .ignoresSafeArea()
        }
    }

    // MARK: - コンパクトヘッダー

    private var compactHeader: some View {
        HStack(spacing: 10) {
            // 接続状態インジケーター
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: indicatorColor.opacity(0.8), radius: 4)
                Text(shortStatusLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.70))
            }
            Spacer()
            #if DEBUG
            Button {
                showDebugSheet = true
                print("[UI][Home] debug_sheet_opened")
            } label: {
                Image(systemName: "ant.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.28))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("診断画面を開く")
            #endif
            Button {
                showSettingsSheet = true
                print("[UI][Home] settings_opened")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.white.opacity(0.50))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("設定を開く")
        }
        .frame(height: 36)
    }

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
        case .watchLive:   return viewModel.isLiveMonitoring ? "計測中" : "Watch 接続済"
        case .healthKit:   return "HealthKit"
        case .mock:        return "デモ"
        case .unavailable: return "待機中"
        }
    }

    // MARK: - グラフィックキャンバス（主役）

    private var stateCanvas: some View {
        GeometryReader { geo in
            let h = min(max(geo.size.width * 0.62, 200), 300)
            ZStack(alignment: .bottomLeading) {
                GraphicHostView(input: viewModel.graphicInput)
                    .frame(maxWidth: .infinity)
                    .frame(height: h)
                    .allowsHitTesting(false)

                // BPM オーバーレイ（左下・補助情報）
                bpmOverlay
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.02, green: 0.02, blue: 0.06).opacity(0.85), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
            }
            .frame(height: h)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        }
        .frame(height: 240)   // GeometryReader には固定高さが必要
    }

    private var bpmOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(heartRateDisplay)
                    .font(.system(size: 42, weight: .thin, design: .rounded))
                    .foregroundStyle(hasRealHeartRate ? Color.white : Color.white.opacity(0.25))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: heartRateDisplay)
                VStack(alignment: .leading, spacing: 1) {
                    Text("BPM")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.40))
                    if viewModel.isLiveMonitoring {
                        Text(viewModel.latestWatchHeartRate != nil ? "LIVE" : "接続中")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.75))
                    }
                }
            }
            if viewModel.didFetchHRV {
                Text(String(format: "HRV  %.0f ms", viewModel.currentHRV))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.70))
            }
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

    // MARK: - 状態ナラティブ

    private var stateNarrative: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(narrativeTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.90))
            Text(narrativeBody)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.50))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.activeDataSource)
    }

    private var narrativeTitle: String {
        switch viewModel.activeDataSource {
        case .watchLive:
            if viewModel.isLiveMonitoring {
                return viewModel.didFetchHRV ? "リアルタイム計測中" : "接続中 — HRV取得待ち"
            }
            return "計測を開始できます"
        case .healthKit: return "HealthKitから読み込み中"
        case .mock:      return "デモモード"
        case .unavailable: return "データを待っています"
        }
    }

    private var narrativeBody: String {
        switch viewModel.activeDataSource {
        case .watchLive:
            if viewModel.didFetchHRV { return "状態グラフィックが現在の心理的揺らぎを反映しています。" }
            return "Apple Watchを装着したまましばらくお待ちください。"
        case .healthKit:
            return "HealthKitに記録された最新データを表示しています。"
        case .mock:
            return "Apple Watchと接続すると実データへ切り替わります。"
        case .unavailable:
            return "下のボタンで計測を開始すると、Apple Watchからデータが届きます。"
        }
    }

    // MARK: - メトリクス行（補助情報）

    private var metricsRow: some View {
        HStack(spacing: 0) {
            metricItem(
                label: "データソース",
                value: dataSourceLabel,
                accent: indicatorColor
            )
            Divider()
                .frame(height: 28)
                .background(Color.white.opacity(0.10))
            metricItem(
                label: "HRV",
                value: viewModel.didFetchHRV ? String(format: "%.0f ms", viewModel.currentHRV) : "—",
                accent: viewModel.didFetchHRV ? Color.cyan : Color.white.opacity(0.25)
            )
            Divider()
                .frame(height: 28)
                .background(Color.white.opacity(0.10))
            metricItem(
                label: "状態",
                value: viewModel.isLiveMonitoring ? "計測中" : "停止中",
                accent: viewModel.isLiveMonitoring ? Color.cyan : Color.white.opacity(0.35)
            )
        }
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var dataSourceLabel: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return "Watch Live"
        case .healthKit:   return "HealthKit"
        case .mock:        return "デモ"
        case .unavailable: return "未接続"
        }
    }

    // MARK: - クイック調整セクション

    private var regulationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("呼吸で整える")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    regulationCard(
                        mode: .fourSevenEight,
                        label: "4-7-8",
                        description: "深い弛緩",
                        icon: "moon.stars"
                    )
                    regulationCard(
                        mode: .box,
                        label: "ボックス",
                        description: "集中と安定",
                        icon: "square"
                    )
                    regulationCard(
                        mode: .twoOneFour,
                        label: "2-1-4",
                        description: "緊張を手放す",
                        icon: "leaf"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }

    private func regulationCard(
        mode: MindWaveBreathingMode,
        label: String,
        description: String,
        icon: String
    ) -> some View {
        Button {
            print("[UI][Home] regulation_selected mode=\(mode.displayName)")
            breathingMode      = mode
            showBreathingSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.cyan.opacity(0.80))
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text(mode.displayName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.55))
                }
            }
            .padding(14)
            .frame(width: 140, height: 110)
            .background(Color(red: 0.05, green: 0.07, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label)呼吸法で整える")
        .accessibilityHint(description)
    }

    // MARK: - 主要CTA（ライブ計測）

    private var primaryAction: some View {
        Button {
            viewModel.toggleLiveMonitoring()
            print("[UI][Home] live_monitoring_toggle requested")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: viewModel.isLiveMonitoring ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 16))
                Text(viewModel.isLiveMonitoring ? "計測を停止する" : "計測を開始する")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(viewModel.isLiveMonitoring ? Color.orange : Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                viewModel.isLiveMonitoring
                    ? Color(red: 0.10, green: 0.06, blue: 0.03)
                    : Color.cyan
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(viewModel.isLiveMonitoring ? Color.orange.opacity(0.50) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: viewModel.isLiveMonitoring)
        .accessibilityLabel(viewModel.isLiveMonitoring ? "計測を停止する" : "ライブ計測を開始する")
        .accessibilityHint(
            viewModel.isLiveMonitoring
                ? "Apple Watchからのデータ取得を停止します"
                : "Apple Watchとリアルタイムで接続して計測します"
        )
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
