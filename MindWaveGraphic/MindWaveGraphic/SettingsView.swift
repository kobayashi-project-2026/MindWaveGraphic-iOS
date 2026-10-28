//
//  SettingsView.swift
//  MindWaveGraphic
//
//  既存ロジックを維持したUI統合：Cyber UIデザインを適用。
//  設定項目・動作・AppStorage参照は変更しない。未実装項目は「準備中」と表示。
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: MindWaveViewModel

    @AppStorage("showsParameterOverlay") private var showsParameterOverlay = true
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled = true
    @AppStorage("autoStartMeasurement")  private var autoStartMeasurement  = false
    @AppStorage("showDetailedMetrics")   private var showDetailedMetrics   = true
    @AppStorage("showHRVWaitingMessage") private var showHRVWaitingMessage = true

    @State private var showAccountSheet = false
    @State private var showPrivacyAlert = false
    /// 外部AIへの要約送信の同意（InsightConsentStore と同じキー・値。0 = 未同意）
    @AppStorage(InsightConsentStore.defaultsKey) private var externalAIConsentVersion = 0

    /// AI相談で入力した文章を外部AIへ送ることへの同意（ChatTextConsentStore と同じキー・値。0 = 未同意）
    @AppStorage(ChatTextConsentStore.defaultsKey) private var chatTextConsentVersion = 0

    private var chatTextConsentBinding: Binding<Bool> {
        Binding(
            get: { chatTextConsentVersion == ChatTextConsentStore.currentConsentVersion },
            set: { ChatTextConsentStore().setConsented($0); chatTextConsentVersion = $0 ? ChatTextConsentStore.currentConsentVersion : 0 }
        )
    }

    private var externalAIConsentBinding: Binding<Bool> {
        Binding(
            get: { externalAIConsentVersion == InsightConsentStore.currentConsentVersion },
            set: { InsightConsentStore().setConsented($0); externalAIConsentVersion = $0 ? InsightConsentStore.currentConsentVersion : 0 }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MindWaveCyberBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // ── プロフィール ───────────────────────────────
                        MindWaveCyberPanel(title: "PROFILE") {
                            Button {
                                showAccountSheet = true
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(MindWaveCyberTheme.cyan.opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(MindWaveCyberTheme.cyan)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("ゲストとして利用中")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(MindWaveCyberTheme.textPrimary)
                                        Text("ログインするとデータを複数デバイスで同期できます")
                                            .font(.system(size: 11, weight: .light))
                                            .foregroundStyle(MindWaveCyberTheme.textTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("アカウント設定を開く")
                        }

                        // ── デバイス連携 ───────────────────────────────
                        MindWaveCyberPanel(title: "DEVICE LINK") {
                            VStack(spacing: 12) {
                                deviceRow(
                                    icon: "applewatch",
                                    title: "Apple Watch",
                                    subtitle: "WatchConnectivity経由",
                                    status: viewModel.watchConnectionStatusLabel,
                                    isConnected: viewModel.watchConnectionStatusLabel.contains("接続済") || viewModel.watchConnectionStatusLabel.contains("LIVE")
                                )
                                Divider().background(MindWaveCyberTheme.borderColor)
                                deviceRow(
                                    icon: "heart.text.square",
                                    title: "HealthKit",
                                    subtitle: "心拍・HRVの読み取り権限",
                                    status: viewModel.healthKitStatusLabel,
                                    isConnected: viewModel.healthKitStatusLabel.contains("許可")
                                )
                            }
                        }

                        // ── 表示設定 ───────────────────────────────────
                        MindWaveCyberPanel(title: "DISPLAY") {
                            VStack(spacing: 12) {
                                cyberToggleRow(
                                    title: "数値表示",
                                    subtitle: "Starfield上にスコア・状態を表示する",
                                    binding: $showsParameterOverlay
                                )
                                Divider().background(MindWaveCyberTheme.borderColor)
                                unavailableRow(
                                    title: "モーションを減らす",
                                    subtitle: "システム設定に従います（次フェーズで接続）"
                                )
                            }
                        }

                        // ── 計測設定 ───────────────────────────────────
                        MindWaveCyberPanel(title: "MEASUREMENT") {
                            VStack(spacing: 12) {
                                cyberToggleRow(
                                    title: "HRV待機メッセージ",
                                    subtitle: "HRV測定中に待機中テキストを表示する",
                                    binding: $showHRVWaitingMessage
                                )
                                Divider().background(MindWaveCyberTheme.borderColor)
                                unavailableRow(title: "計測時の振動", subtitle: "計測開始・完了時に振動でフィードバック")
                                Divider().background(MindWaveCyberTheme.borderColor)
                                unavailableRow(title: "自動計測開始",  subtitle: "アプリ起動時に自動でライブ取得を開始する")
                                Divider().background(MindWaveCyberTheme.borderColor)
                                unavailableRow(title: "詳細指標表示",  subtitle: "心拍上昇率・HRV低下率の詳細を表示する")
                            }
                        }

                        // ── データとプライバシー ────────────────────────
                        MindWaveCyberPanel(title: "PRIVACY") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("データの扱い")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                                Text(externalAIConsentBinding.wrappedValue
                                     ? "計測データはこのデバイス上で処理されます。外部AIを有効にしている場合のみ、ガイド結果の要約（場面・方法・前後の状態・丸めた心拍）をサーバーへ送信します。"
                                     : "計測データはこのデバイス上でのみ処理されます。サーバーへの送信は行っていません。")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundStyle(MindWaveCyberTheme.textTertiary)

                                Divider().background(MindWaveCyberTheme.borderColor).padding(.vertical, 2)

                                // 外部AI（OpenAI をサーバー経由で利用）への同意。既定は OFF
                                cyberToggleRow(
                                    title: "外部AIで振り返りを生成",
                                    subtitle: InsightService.shared.isRemoteConfigured
                                        ? "ガイド結果の要約のみを送信します。メモ・日時・HRVの数値・Mockデータは送信しません。失敗時は端末内AIで表示します。"
                                        : "サーバーが未設定のため利用できません（端末内AIで表示します）。",
                                    binding: externalAIConsentBinding
                                )
                                .disabled(!InsightService.shared.isRemoteConfigured)

                                Divider().background(MindWaveCyberTheme.borderColor).padding(.vertical, 2)

                                // AI相談（入力した文章の送信）への同意。計測データは送らない。いつでも取り消せる
                                cyberToggleRow(
                                    title: "AI相談の文章を外部AIへ送信",
                                    subtitle: "AI相談で入力した文章と直近の会話・選んだ場面だけを送信します。計測データは送信しません。OFF にすると端末内の定型アドバイスで応答します。",
                                    binding: chatTextConsentBinding
                                )

                                Divider().background(MindWaveCyberTheme.borderColor).padding(.vertical, 2)

                                Button(role: .destructive) {
                                    showPrivacyAlert = true
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                        Text("ローカル履歴を削除")
                                            .font(.system(size: 14))
                                    }
                                    .foregroundStyle(Color.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .alert("未実装", isPresented: $showPrivacyAlert) {
                                    Button("OK", role: .cancel) {}
                                } message: {
                                    Text("履歴削除機能は次フェーズで実装予定です。")
                                }
                            }
                        }

                        // ── アプリ情報 ─────────────────────────────────
                        MindWaveCyberPanel(title: "APP INFO", accentColor: MindWaveCyberTheme.emerald) {
                            VStack(spacing: 8) {
                                infoRow("アプリ名",  "MindWave Graphic")
                                infoRow("バージョン", appVersion)
                                infoRow("Build",    appBuild)
                                infoRow("種別",     "研究用プロトタイプ")
                            }

                            Divider().background(MindWaveCyberTheme.borderColor).padding(.vertical, 4)

                            Text("本アプリは研究・開発段階のプロトタイプです。医療診断には使用しないでください。")
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(MindWaveCyberTheme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(MindWaveCyberTheme.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAccountSheet) {
            AccountView()
        }
    }

    // MARK: - Sub Views

    private func deviceRow(icon: String, title: String, subtitle: String, status: String, isConnected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(isConnected ? MindWaveCyberTheme.cyan : MindWaveCyberTheme.textTertiary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
            Spacer()
            MindWaveCyberStatusBadge(label: status, isActive: isConnected)
        }
    }

    private func cyberToggleRow(title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(MindWaveCyberTheme.cyan)
        }
    }

    private func unavailableRow(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MindWaveCyberTheme.textSecondary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
            Spacer()
            Text("準備中")
                .font(.system(size: 11, weight: .light, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
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
