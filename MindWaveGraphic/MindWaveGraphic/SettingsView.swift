//
//  SettingsView.swift
//  MindWaveGraphic
//
//  設定画面。アカウント・計測設定・表示設定・データとプライバシー・アプリ情報を提供する。
//  本物のサーバー認証・クラウド同期はまだ未接続。未接続項目は明示的に「未接続」と表記する。
//  数値表示設定（showsParameterOverlay）だけは StarfieldGraphicView へ実際に反映する。
//

import SwiftUI

/// 設定画面。4タブのうち「設定」に割り当てられる。
/// 数値オーバーレイの ON/OFF だけが Starfield に即時反映される実機能。
/// Account・計測設定・プライバシーは UI プロトタイプ（次フェーズで接続予定）。
struct SettingsView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel

    /// Starfield 上の数値オーバーレイ表示設定。TeamGraphicView と同じキーを参照する。
    /// false にすると score / confidence / state 数値がグラフィック上から消える。
    @AppStorage("showsParameterOverlay") private var showsParameterOverlay = true

    // 計測設定（UI のみ・未接続）
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled = true
    @AppStorage("autoStartMeasurement")  private var autoStartMeasurement  = false
    @AppStorage("showDetailedMetrics")   private var showDetailedMetrics   = true
    @AppStorage("showHRVWaitingMessage") private var showHRVWaitingMessage = true

    @State private var showAccountSheet = false
    @State private var showPrivacyAlert = false

    var body: some View {
        NavigationStack {
            List {
                // ── アカウント ──────────────────────────────────────────
                Section("アカウント") {
                    Button {
                        showAccountSheet = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(MindWaveTheme.accent.opacity(0.2))
                                    .frame(width: 42, height: 42)
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(MindWaveTheme.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ゲストとして利用中")
                                    .font(.system(size: 15))
                                    .foregroundStyle(MindWaveTheme.textPrimary)
                                Text("ログインするとデータを複数デバイスで同期できます")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MindWaveTheme.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // ── 表示設定 ───────────────────────────────────────────
                Section("表示設定") {
                    Toggle(isOn: $showsParameterOverlay) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("数値表示")
                                .font(.system(size: 15))
                                .foregroundStyle(MindWaveTheme.textPrimary)
                            Text("Starfield 上にスコア・状態を重ねて表示する")
                                .font(.system(size: 11))
                                .foregroundStyle(MindWaveTheme.textTertiary)
                        }
                    }
                    .tint(MindWaveTheme.accent)

                    // Reduce Motion は accessibilityReduceMotion を参照（将来接続）
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("モーションを減らす")
                                .font(.system(size: 15))
                                .foregroundStyle(MindWaveTheme.textPrimary)
                            Text("システム設定に従います（次フェーズで接続）")
                                .font(.system(size: 11))
                                .foregroundStyle(MindWaveTheme.textTertiary)
                        }
                        Spacer()
                        Text("未接続")
                            .font(.system(size: 11))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                    }
                }

                // ── 計測設定 ───────────────────────────────────────────
                Section("計測設定") {
                    Toggle(isOn: $showHRVWaitingMessage) {
                        settingLabel("HRV 待機メッセージ", sub: "HRV 測定中に待機中テキストを表示する")
                    }
                    .tint(MindWaveTheme.accent)

                    unavailableRow("計測時の振動", sub: "計測開始・完了時に振動でフィードバック")
                    unavailableRow("自動計測開始", sub: "アプリ起動時に自動でライブ取得を開始する")
                    unavailableRow("詳細指標表示", sub: "心拍上昇率・HRV 低下率の詳細を表示する")
                }

                // ── データとプライバシー ────────────────────────────────
                Section("データとプライバシー") {
                    HStack {
                        settingLabel("HealthKit 接続", sub: "心拍・HRV の読み取り権限")
                        Spacer()
                        Text(viewModel.healthKitStatusLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(MindWaveTheme.textSecondary)
                    }

                    HStack {
                        settingLabel("Apple Watch 接続", sub: "WatchConnectivity 経由")
                        Spacer()
                        Text(viewModel.watchConnectionStatusLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(MindWaveTheme.textSecondary)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("データの扱い")
                            .font(.system(size: 15))
                            .foregroundStyle(MindWaveTheme.textPrimary)
                        Text("計測データはこのデバイス上でのみ処理されます。サーバーへの送信は現在行っていません。")
                            .font(.system(size: 11))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                    }
                    .padding(.vertical, 4)

                    Button(role: .destructive) {
                        showPrivacyAlert = true
                    } label: {
                        Text("ローカル履歴を削除")
                            .font(.system(size: 15))
                    }
                    .alert("未実装", isPresented: $showPrivacyAlert) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("履歴削除機能は次フェーズで実装予定です。")
                    }

                    unavailableRow("プライバシーポリシー", sub: "準備中")
                }

                // ── アプリ情報 ─────────────────────────────────────────
                Section("アプリ情報") {
                    infoRow("アプリ名", "MindWave Graphic")
                    infoRow("バージョン", appVersion)
                    infoRow("Build", appBuild)
                    infoRow("種別", "研究用プロトタイプ")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("注意")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                        Text("本アプリは研究・開発段階のプロトタイプです。医療診断には使用しないでください。")
                            .font(.system(size: 11))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MindWaveTheme.background.ignoresSafeArea())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAccountSheet) {
            AccountView()
        }
    }

    // MARK: - Helpers

    private func settingLabel(_ title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(MindWaveTheme.textPrimary)
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(MindWaveTheme.textTertiary)
        }
    }

    private func unavailableRow(_ title: String, sub: String) -> some View {
        HStack {
            settingLabel(title, sub: sub)
            Spacer()
            Text("未接続")
                .font(.system(size: 11))
                .foregroundStyle(MindWaveTheme.textTertiary)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(MindWaveTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(MindWaveTheme.textSecondary)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "---"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "---"
    }
}

#Preview {
    SettingsView()
        .environmentObject(MindWaveViewModel())
}
