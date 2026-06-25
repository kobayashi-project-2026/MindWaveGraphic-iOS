//
//  MindWaveBreathingGuideView.swift
//  MindWaveGraphic
//
//  既存フローとは独立した追加UI：3モード呼吸ガイド画面。
//  GuideView から fullScreenCover で開く。
//  HealthKit・WatchConnectivity・履歴保存には接続しない。
//

import SwiftUI

struct MindWaveBreathingGuideView: View {
    @StateObject private var viewModel = MindWaveBreathingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // ── 閉じるボタン（左上） ──────────────────────────
                    HStack {
                        Button {
                            viewModel.stop()  // タイマーを停止してから閉じる
                            print("[Breathing] guide closed")
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(10)
                                .background(Circle().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("閉じる")
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // ── モード名・用途説明 ──────────────────────────
                    VStack(spacing: 4) {
                        Text(viewModel.mode.displayName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text(viewModel.mode.purpose)
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // ── モード選択ボタン（3つ・横並び） ──────────────
                    HStack(spacing: 10) {
                        ForEach(MindWaveBreathingMode.allCases) { mode in
                            modeButton(mode)
                        }
                    }
                    .padding(.horizontal, 20)

                    // ── 円形プログレスリング + 残り秒数 ──────────────
                    ZStack {
                        // 背景リング
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 12)
                            .frame(width: 250, height: 250)

                        // 進行リング（フェーズのカラーで表示）
                        Circle()
                            .trim(from: 0, to: viewModel.progress)
                            .stroke(
                                viewModel.currentPhase.color,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .frame(width: 250, height: 250)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.05), value: viewModel.progress)

                        // 中央：残り秒数（大）＋ フェーズ名
                        VStack(spacing: 6) {
                            Text("\(viewModel.remainingSeconds)")
                                .font(.system(size: 72, weight: .thin, design: .rounded))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.2), value: viewModel.remainingSeconds)

                            Text(viewModel.currentPhase.label)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(viewModel.currentPhase.color)
                        }
                    }

                    // ── モード名・サイクル数 ──────────────────────────
                    HStack(spacing: 28) {
                        VStack(spacing: 2) {
                            Text("モード")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(viewModel.mode.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        Rectangle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 1, height: 32)
                        VStack(spacing: 2) {
                            Text("サイクル")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("\(viewModel.cycles)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }

                    // ── 開始／停止ボタン ──────────────────────────────
                    Button {
                        viewModel.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                                .font(.system(size: 14))
                            Text(viewModel.isRunning ? "停止" : "開始")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(width: 180, height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.white)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.isRunning ? "停止" : "開始")
                    .padding(.bottom, 40)
                }
            }
        }
        // 画面終了時にタイマーを停止する（バックグラウンドタイマー継続禁止）
        .onDisappear {
            viewModel.stop()
        }
        .onAppear {
            print("[Breathing] guide opened")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - モード選択ボタン（約95 × 60）

    private func modeButton(_ mode: MindWaveBreathingMode) -> some View {
        let isSelected = viewModel.mode == mode
        return Button {
            viewModel.changeMode(mode)
        } label: {
            VStack(spacing: 4) {
                Text(mode.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : .white)
                Text(mode.purpose)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .black.opacity(0.65) : .white.opacity(0.50))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.10))
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
