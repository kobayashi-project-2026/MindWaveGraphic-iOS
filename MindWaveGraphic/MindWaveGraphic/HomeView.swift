//
//  HomeView.swift
//  MindWaveGraphic
//
//  没入型ホーム画面。旧 Live タブの計測機能をすべてここに統合。
//  Starfield グラフィックを画面全面に描画し、UI を薄いオーバーレイとして重ねる。
//  ViewModel は ContentView からの EnvironmentObject を使用し、新規生成はしない。
//

import SwiftUI
import Combine

/// アプリの中心画面。Starfield を全画面背景として使用し、Watch ライブ計測を行う。
/// 旧 Live タブの GraphicHostView・心拍/HRV 表示・計測開始停止・Debug シートをすべて含む。
/// ViewModelは ContentView から @EnvironmentObject で受け取る（新規生成しない）。
struct HomeView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel

    // MARK: - UI State
    /// 計測経過時間（秒）。計測停止でリセット。
    @State private var elapsed: Int = 0
    /// LIVE ドット点滅フラグ
    @State private var liveDotVisible: Bool = true
    /// Debug 診断シートの表示フラグ（DEBUG ビルドのみ使用）
    @State private var showDebugSheet = false
    /// Account シートの表示フラグ
    @State private var showAccountSheet = false

    // MARK: - Timers
    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let blinkTimer   = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    // MARK: - Computed
    /// Watch 鮮度があり HRV が未取得の場合、HRV 待機中を示す
    private var isHRVWaiting: Bool {
        viewModel.isWatchSampleFresh && !viewModel.didFetchHRV && !viewModel.isMockMode
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── 全画面 Starfield 背景 ──────────────────────────────────
            // GraphicPlugin → TeamGraphicView → StarfieldGraphicView に委譲。
            // .ignoresSafeArea() でノッチ・タブバー下まで描画して没入感を出す。
            GraphicHostView(input: viewModel.graphicInput)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            // ── UI オーバーレイ ──────────────────────────────────────
            VStack(spacing: 0) {
                topHUD
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer()

                bottomPanel
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .onAppear { elapsed = 0 }
        .onChange(of: viewModel.isLiveMonitoring) { _, active in
            if !active { elapsed = 0 }
        }
        .onReceive(sessionTimer) { _ in
            if viewModel.isLiveMonitoring { elapsed += 1 }
        }
        .onReceive(blinkTimer) { _ in
            liveDotVisible = viewModel.isLiveMonitoring ? !liveDotVisible : true
        }
        .onChange(of: viewModel.graphicInput.score) { _, _ in
            // スコア変化時の animation は StarfieldGraphicView 内で処理済み
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

    // MARK: - Top HUD

    /// アプリ名・計測時間・接続状態・プロフィールボタンを表示する上部 HUD
    private var topHUD: some View {
        HStack(alignment: .center) {
            // アプリ名 + 経過時間
            VStack(alignment: .leading, spacing: 2) {
                Text("Mind Wave")
                    .font(.system(size: 17, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.90))
                    .tracking(2)
                if viewModel.isLiveMonitoring {
                    Text(timeString)
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.40))
                        .transition(.opacity)
                }
            }

            Spacer()

            // Active Source / LIVE ドット
            HStack(spacing: 5) {
                Circle()
                    .fill(viewModel.isLiveMonitoring ? MindWaveTheme.accent : .white.opacity(0.3))
                    .opacity(viewModel.isLiveMonitoring ? (liveDotVisible ? 1.0 : 0.20) : 0.35)
                    .frame(width: 6, height: 6)
                    .shadow(color: viewModel.isLiveMonitoring
                            ? MindWaveTheme.accent.opacity(0.9) : .clear, radius: 4)
                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(viewModel.isLiveMonitoring
                                     ? MindWaveTheme.accent : .white.opacity(0.30))
                    .tracking(1.2)
            }
            .padding(.trailing, 14)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isLiveMonitoring)

            // プロフィールボタン → AccountView シート
            Button { showAccountSheet = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(.white.opacity(0.60))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bottom Panel

    /// 生体指標（心拍・HRV）・状態名・計測開始停止・Debug ボタンを表示する下部パネル
    private var bottomPanel: some View {
        VStack(spacing: 10) {
            // 状態名
            if viewModel.activeDataSource != .unavailable {
                Text(viewModel.graphicInput.state.displayName)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .animation(.easeInOut(duration: 0.4), value: viewModel.graphicInput.state)
            }

            // HRV 待機メッセージ
            if isHRVWaiting {
                Text("HRV測定を待機中")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                    .transition(.opacity)
            }

            // 生体指標ストリップ（心拍・HRV）
            biometricStrip

            // 計測開始・停止
            measurementButton

            // Debug ボタン（DEBUGビルドのみ）
            #if DEBUG
            Button { showDebugSheet = true } label: {
                HStack(spacing: 3) {
                    Image(systemName: "ant.circle")
                        .font(.system(size: 9))
                    Text("Debug")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.22))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    /// 心拍数と HRV SDNN をガラス調ストリップで表示する
    private var biometricStrip: some View {
        HStack(spacing: 0) {
            biometricCell(icon: "heart.fill",
                          value: heartRateString,
                          unit: "bpm",
                          accentColor: Color(red: 0.95, green: 0.35, blue: 0.35))
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1, height: 32)
            biometricCell(icon: "waveform.path.ecg",
                          value: hrvString,
                          unit: viewModel.didFetchHRV ? "ms" : "",
                          accentColor: MindWaveTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private func biometricCell(icon: String, value: String,
                                unit: String, accentColor: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(accentColor.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// ライブ取得開始・停止ボタン
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
                             ? Color.orange.opacity(0.90) : MindWaveTheme.accent)
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.isLiveMonitoring
                          ? Color.orange.opacity(0.12)
                          : MindWaveTheme.accent.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                viewModel.isLiveMonitoring
                                    ? Color.orange.opacity(0.30)
                                    : MindWaveTheme.accent.opacity(0.30),
                                lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLiveMonitoring)
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

    private var heartRateString: String {
        guard viewModel.didFetchHeartRate || viewModel.latestWatchHeartRate != nil else { return "---" }
        return String(format: "%.0f", viewModel.currentHeartRate)
    }

    private var hrvString: String {
        viewModel.didFetchHRV ? String(format: "%.0f", viewModel.currentHRV) : "---"
    }
}

#Preview {
    HomeView()
        .environmentObject(MindWaveViewModel())
}
