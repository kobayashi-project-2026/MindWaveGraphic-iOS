//
//  MindWaveBreathingGuideView.swift
//  MindWaveGraphic
//
//  既存ロジックを維持したUI統合：Cyber UIデザインを適用。
//  4-7-8・BOX・2-1-4のタイマー・停止・再開・モード変更・サイクル数は変更しない。
//  HealthKit・WatchConnectivity・履歴保存には接続しない。
//

import SwiftUI

struct MindWaveBreathingGuideView: View {
    /// HomeViewのクイックワークカードからモードを指定するための初期モード（省略可）。
    var initialMode: MindWaveBreathingMode = .fourSevenEight
    @StateObject private var viewModel = MindWaveBreathingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Cyber背景（グリッド＋グラデーション）
            MindWaveCyberBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // ── 閉じるボタン ──────────────────────────────────
                    HStack {
                        Button {
                            viewModel.stop()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(MindWaveCyberTheme.textSecondary)
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(MindWaveCyberTheme.panelBackground)
                                        .overlay(Circle().strokeBorder(MindWaveCyberTheme.borderColor, lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("閉じる")
                        Spacer()

                        // サイクル数バッジ
                        MindWaveCyberStatusBadge(
                            label: "CYCLE \(viewModel.cycles)",
                            isActive: viewModel.cycles > 0
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // ── モード名・用途 ────────────────────────────────
                    VStack(spacing: 4) {
                        Text(viewModel.mode.displayName)
                            .font(.system(size: 28, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(MindWaveCyberTheme.textPrimary)
                            .tracking(2)
                        Text(viewModel.mode.purpose)
                            .font(.system(size: 12, weight: .light, design: .monospaced))
                            .foregroundStyle(MindWaveCyberTheme.textSecondary)
                            .tracking(1)
                    }

                    // ── モード選択ボタン ───────────────────────────────
                    HStack(spacing: 10) {
                        ForEach(MindWaveBreathingMode.allCases) { mode in
                            cyberModeButton(mode)
                        }
                    }
                    .padding(.horizontal, 20)

                    // ── 円形プログレスリング（発光Cyber化）───────────
                    ZStack {
                        // 背景リング
                        Circle()
                            .stroke(Color.white.opacity(0.06), lineWidth: 14)
                            .frame(width: 250, height: 250)

                        // グロー外輪
                        Circle()
                            .stroke(viewModel.currentPhase.color.opacity(0.10), lineWidth: 24)
                            .frame(width: 250, height: 250)

                        // 進行リング
                        Circle()
                            .trim(from: 0, to: viewModel.progress)
                            .stroke(
                                viewModel.currentPhase.color,
                                style: StrokeStyle(lineWidth: 14, lineCap: .round)
                            )
                            .frame(width: 250, height: 250)
                            .rotationEffect(.degrees(-90))
                            .shadow(color: viewModel.currentPhase.color.opacity(0.65), radius: 12)
                            .animation(.linear(duration: 0.05), value: viewModel.progress)

                        // グリッド装飾（内側）
                        CyberGridShape(cellSize: 30)
                            .stroke(Color.white.opacity(0.03), lineWidth: 0.5)
                            .frame(width: 200, height: 200)
                            .clipShape(Circle())

                        // 残り秒数 ＋ フェーズ名
                        VStack(spacing: 6) {
                            Text("\(viewModel.remainingSeconds)")
                                .font(.system(size: 72, weight: .thin, design: .rounded))
                                .foregroundStyle(MindWaveCyberTheme.textPrimary)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.2), value: viewModel.remainingSeconds)
                                .shadow(color: viewModel.currentPhase.color.opacity(0.5), radius: 8)

                            Text(viewModel.currentPhase.label)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(viewModel.currentPhase.color)
                                .tracking(1.5)
                                .shadow(color: viewModel.currentPhase.color.opacity(0.6), radius: 6)
                        }
                    }

                    // ── ステータスバー ────────────────────────────────
                    HStack(spacing: 0) {
                        MindWaveCyberMetricView(
                            label: "モード",
                            value: viewModel.mode.displayName,
                            unit: "",
                            accentColor: MindWaveCyberTheme.cyan
                        )
                        Rectangle()
                            .fill(MindWaveCyberTheme.borderColor)
                            .frame(width: 1, height: 32)
                        MindWaveCyberMetricView(
                            label: "サイクル",
                            value: "\(viewModel.cycles)",
                            unit: "",
                            accentColor: MindWaveCyberTheme.emerald
                        )
                    }
                    .padding(.horizontal, 20)

                    // ── 開始・停止ボタン（Cyber UI化）─────────────────
                    Button {
                        viewModel.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                                .font(.system(size: 14))
                            Text(viewModel.isRunning ? "停止" : "開始")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(viewModel.isRunning ? .black : .black)
                        .frame(width: 200, height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(viewModel.isRunning
                                      ? MindWaveCyberTheme.orange
                                      : MindWaveCyberTheme.cyan)
                                .shadow(color: viewModel.isRunning
                                        ? MindWaveCyberTheme.orange.opacity(0.5)
                                        : MindWaveCyberTheme.cyan.opacity(0.5),
                                        radius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.isRunning ? "停止" : "開始")
                    .accessibilityHint(viewModel.isRunning ? "呼吸タイマーを停止します" : "呼吸タイマーを開始します")
                    .padding(.bottom, 40)
                }
            }
        }
        .onDisappear { viewModel.stop() }
        .onAppear {
            viewModel.changeMode(initialMode)
            print("[CyberUI] breathing guide presented mode=\(initialMode.displayName)")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - モード選択ボタン（Cyber UI化）

    private func cyberModeButton(_ mode: MindWaveBreathingMode) -> some View {
        let isSelected = viewModel.mode == mode
        return Button {
            viewModel.changeMode(mode)
        } label: {
            VStack(spacing: 4) {
                Text(mode.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? .black : MindWaveCyberTheme.textPrimary)
                Text(mode.purpose)
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(isSelected ? .black.opacity(0.65) : MindWaveCyberTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? MindWaveCyberTheme.cyan : MindWaveCyberTheme.panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? MindWaveCyberTheme.cyan : MindWaveCyberTheme.borderColor,
                                lineWidth: isSelected ? 0 : 1
                            )
                    )
                    .shadow(color: isSelected ? MindWaveCyberTheme.cyan.opacity(0.45) : .clear, radius: 8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.displayName) \(mode.purpose)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    MindWaveBreathingGuideView()
}
