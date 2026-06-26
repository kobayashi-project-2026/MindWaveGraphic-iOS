//
//  HomeView.swift
//  MindWaveGraphic
//
//  参考写真レイアウトへ全面再設計。
//  データ取得経路・WatchConnectivity・HealthKit・ViewModelはすべて変更しない。
//  架空の心拍数・HRV・スコアは使用しない。実データのみ表示する。
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @Binding var selectedTab: Int

    @State private var showDebugSheet     = false
    @State private var showSettingsSheet  = false
    @State private var showBreathingSheet = false
    @State private var breathingInitialMode: MindWaveBreathingMode = .fourSevenEight

    var body: some View {
        ZStack {
            MindWaveCyberBackground()

            VStack(spacing: 0) {

                // ── 最上部ステータスバー ──────────────────────────────
                topStatusBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        // ── 状態説明カード ────────────────────────────
                        statusCard
                            .padding(.horizontal, 20)

                        // ── REALTIME PULSE ────────────────────────────
                        realtimePulseSection
                            .padding(.horizontal, 20)

                        // ── QUICK WORK（横スクロール）────────────────
                        quickWorkSection

                        // ── ライブ取得ボタン ──────────────────────────
                        measurementButton
                            .padding(.horizontal, 20)

                        // safe area 分の下余白（カスタムタブバー対応）
                        Spacer().frame(height: 20)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onAppear { print("[ReferenceUI] home appeared") }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showDebugSheet) {
            DebugDiagnosticsView()
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showBreathingSheet) {
            BreathingFromHomeWrapper(initialMode: breathingInitialMode)
        }
    }

    // MARK: - 最上部ステータスバー

    private var topStatusBar: some View {
        HStack(spacing: 10) {

            // ステータスピル
            HStack(spacing: 7) {
                Circle()
                    .fill(viewModel.isLiveMonitoring
                          ? MindWaveCyberTheme.cyan
                          : MindWaveCyberTheme.textTertiary)
                    .frame(width: 5, height: 5)
                Text(statusPillText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                    .tracking(0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(MindWaveCyberTheme.panelBackground)
                    .overlay(Capsule().strokeBorder(MindWaveCyberTheme.borderColor, lineWidth: 1))
            )

            Spacer()

            // Debug ボタン（DEBUGビルド専用・歯車の左）
            #if DEBUG
            Button { showDebugSheet = true } label: {
                Image(systemName: "ant.circle")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("デバッグ診断を開く")
            #endif

            // 設定ボタン
            Button { showSettingsSheet = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(MindWaveCyberTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .accessibilityLabel("設定を開く")
        }
    }

    private var statusPillText: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return "MIND STATUS: LIVE // FACTOR: Watch"
        case .healthKit:   return "MIND STATUS: HK // FACTOR: HealthKit"
        case .mock:        return "MIND STATUS: DEMO // FACTOR: Mockデータ"
        case .unavailable: return "MIND STATUS: 計測待ち // FACTOR: 未選択"
        }
    }

    // MARK: - 状態説明カード

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(cardAccent.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: cardIcon)
                        .font(.system(size: 19))
                        .foregroundStyle(cardAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(cardCode)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(cardAccent)
                        .tracking(0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("BIOMETRIC STATUS")
                        .font(.system(size: 9, weight: .light, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                        .tracking(1)
                }
                Spacer()
            }

            Rectangle()
                .fill(cardAccent.opacity(0.25))
                .frame(height: 1)

            Text(cardDescription)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
                .lineSpacing(4)

            Text(cardHint)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(MindWaveCyberTheme.panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(cardAccent.opacity(0.45), lineWidth: 1.5)
                )
        )
        .animation(.easeInOut(duration: 0.3), value: viewModel.activeDataSource)
    }

    private var cardAccent: Color {
        switch viewModel.activeDataSource {
        case .watchLive:   return MindWaveCyberTheme.cyan
        case .healthKit:   return MindWaveCyberTheme.emerald
        case .mock:        return MindWaveCyberTheme.orange
        case .unavailable: return MindWaveCyberTheme.orange
        }
    }

    private var cardIcon: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return "waveform.path.ecg"
        case .healthKit:   return "heart.text.square"
        case .mock:        return "testtube.2"
        case .unavailable: return "waveform.badge.exclamationmark"
        }
    }

    private var cardCode: String {
        switch viewModel.activeDataSource {
        case .watchLive:   return "LIVE MONITORING"
        case .healthKit:   return "HEALTHKIT SYNC"
        case .mock:        return "DEMO MODE ACTIVE"
        case .unavailable: return "AWAITING BIOMETRICS"
        }
    }

    private var cardDescription: String {
        switch viewModel.activeDataSource {
        case .watchLive:
            return viewModel.didFetchHRV
                ? "Apple Watchからリアルタイムで心拍数とHRVを取得しています。"
                : "心拍数を受信しています。HRVの取得が完了すると緊張度が計算されます。"
        case .healthKit:
            return "HealthKitに記録されたデータを読み込んでいます。"
        case .mock:
            return "Mockデータで表示中です。Apple Watchを接続してライブデータに切り替えてください。"
        case .unavailable:
            return "Apple Watchからの心拍数とHRVを待っています。\nデータを取得すると、現在の状態をこの画面に表示します。"
        }
    }

    private var cardHint: String {
        switch viewModel.activeDataSource {
        case .watchLive:
            return viewModel.didFetchHRV
                ? "呼吸ガイドを使って状態を整えることができます。"
                : "Apple Watchを装着したままお待ちください。"
        case .healthKit:
            return "より精度の高い計測にはApple WatchとのLive接続をお試しください。"
        case .mock:
            return "「ライブ取得開始」を押すとApple Watchへの接続を試みます。"
        case .unavailable:
            return "計測を開始し、Apple Watchを装着したままお待ちください。"
        }
    }

    // MARK: - REALTIME PULSE

    private var realtimePulseSection: some View {
        HStack(spacing: 20) {

            // 左: 心臓アイコン＋ECG波形
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            viewModel.isLiveMonitoring
                                ? MindWaveCyberTheme.cyan
                                : MindWaveCyberTheme.borderColor,
                            lineWidth: 1.5
                        )
                        .frame(width: 60, height: 60)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(
                            viewModel.isLiveMonitoring
                                ? MindWaveCyberTheme.cyan
                                : MindWaveCyberTheme.textTertiary
                        )
                }
                MiniECGLine(isActive: viewModel.isLiveMonitoring && hasRealHeartRate)
                    .frame(width: 76, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // 右: 数値エリア
            VStack(alignment: .leading, spacing: 4) {
                Text("REALTIME PULSE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                    .tracking(1.5)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(heartRateDisplay)
                        .font(.system(size: 48, weight: .thin, design: .rounded))
                        .foregroundStyle(
                            hasRealHeartRate
                                ? MindWaveCyberTheme.textPrimary
                                : MindWaveCyberTheme.textTertiary
                        )
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: heartRateDisplay)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("BPM")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(MindWaveCyberTheme.textTertiary)
                        Text(pulseStatusLabel)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(
                                viewModel.isLiveMonitoring && hasRealHeartRate
                                    ? MindWaveCyberTheme.cyan
                                    : MindWaveCyberTheme.textTertiary
                            )
                            .tracking(0.4)
                    }
                }

                // HRV補助表示
                if viewModel.didFetchHRV {
                    Text(String(format: "HRV: %.0f ms", viewModel.currentHRV))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.emerald.opacity(0.85))
                } else if viewModel.isLiveMonitoring {
                    Text("HRV: 取得中...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(MindWaveCyberTheme.panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(MindWaveCyberTheme.borderColor, lineWidth: 1)
                )
        )
    }

    private var hasRealHeartRate: Bool {
        viewModel.latestWatchHeartRate != nil || viewModel.didFetchHeartRate
    }

    private var heartRateDisplay: String {
        if let watchHR = viewModel.latestWatchHeartRate {
            return String(format: "%.0f", watchHR)
        }
        if viewModel.didFetchHeartRate {
            return String(format: "%.0f", viewModel.currentHeartRate)
        }
        return "—"
    }

    private var pulseStatusLabel: String {
        if viewModel.isLiveMonitoring {
            return viewModel.latestWatchHeartRate != nil ? "LIVE SIGNAL" : "CONNECTING"
        }
        if viewModel.didFetchHeartRate { return "HK SIGNAL" }
        return "SIGNAL WAITING"
    }

    // MARK: - QUICK WORK（横スクロール・3枚カード）

    private var quickWorkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("QUICK WORK")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                    .tracking(2)
                Spacer()
                Text("← スワイプ →")
                    .font(.system(size: 9, weight: .light, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    quickWorkCard(.fourSevenEight,
                                  title: "4-7-8呼吸法",
                                  subtitle: "深いリラックス",
                                  accent: MindWaveCyberTheme.cyan)
                    quickWorkCard(.box,
                                  title: "BOX呼吸法",
                                  subtitle: "集中力向上",
                                  accent: MindWaveCyberTheme.purple)
                    quickWorkCard(.twoOneFour,
                                  title: "2-1-4呼吸法",
                                  subtitle: "緊張緩和",
                                  accent: MindWaveCyberTheme.emerald)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func quickWorkCard(
        _ mode: MindWaveBreathingMode,
        title: String,
        subtitle: String,
        accent: Color
    ) -> some View {
        Button {
            print("[ReferenceUI] quick breathing selected mode=\(mode.displayName)")
            breathingInitialMode = mode
            showBreathingSheet   = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: "lungs.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(accent)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MindWaveCyberTheme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(MindWaveCyberTheme.textSecondary)
                        .lineLimit(1)
                    Text(mode.displayName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(accent)
                        .tracking(0.3)
                }
            }
            .frame(width: 126, height: 108)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(MindWaveCyberTheme.panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(accent.opacity(0.38), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)を開始する")
        .accessibilityHint("呼吸ガイドを開きます")
    }

    // MARK: - ライブ取得ボタン

    private var measurementButton: some View {
        Button { viewModel.toggleLiveMonitoring() } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isLiveMonitoring
                      ? "stop.circle.fill" : "play.circle.fill")
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
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLiveMonitoring)
        .accessibilityLabel(viewModel.isLiveMonitoring ? "計測を停止する" : "ライブ計測を開始する")
        .accessibilityHint(viewModel.isLiveMonitoring
                           ? "Apple Watchからのデータ取得を停止します"
                           : "Apple Watchからリアルタイムでデータを取得します")
    }
}

// MARK: - Mini ECG Line（視覚演出のみ・生体値ではない）

private struct MiniECGLine: View {
    let isActive: Bool

    var body: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cy = h * 0.5
            let c  = isActive
                ? Color(red: 0.25, green: 0.90, blue: 0.95)
                : Color(white: 0.22)
            let pts: [(CGFloat, CGFloat)] = [
                (0.00, 0.0), (0.12, 0.0), (0.17, -0.65),
                (0.22, 0.55), (0.27, -0.18), (0.32, 0.0),
                (0.44, 0.0), (0.49, -0.65), (0.54, 0.55),
                (0.59, -0.18), (0.64, 0.0),
                (0.76, 0.0), (0.81, -0.65), (0.86, 0.55),
                (0.91, -0.18), (1.00, 0.0),
            ]
            var p = Path()
            p.move(to: CGPoint(x: 0, y: cy))
            for pt in pts {
                p.addLine(to: CGPoint(x: pt.0 * w, y: cy + pt.1 * h * 0.42))
            }
            ctx.stroke(p, with: .color(c), lineWidth: 1.5)
        }
    }
}

// MARK: - HomeViewから呼吸ガイドを開くラッパー

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
