//
//  GuideView.swift
//  MindWaveGraphic
//
//  ガイドタブのメイン画面。
//  既存の発光リングアニメーションを背景 ambient 表現として維持しながら、
//  友人コードから統合した 2 種のリラクゼーションガイドカードを追加。
//  カードをタップすると GuideSessionView が fullScreenCover で開く。
//

import SwiftUI

struct GuideView: View {
    @State private var expanding        = false
    @State private var selectedExercise: GuideExercise? = nil

    var body: some View {
        ZStack {
            MindWaveTheme.backgroundGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── ヘッダー ──────────────────────────────────────
                    VStack(spacing: 8) {
                        Text("整える")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(MindWaveTheme.textPrimary)
                            .tracking(3)
                        Text("呼吸と流れを意識する時間")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(MindWaveTheme.textSecondary)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 24)

                    // ── 既存の発光リング（ambient アニメーションとして維持） ──
                    breathingRing
                        .padding(.bottom, 32)

                    // ── おすすめガイドカード ──────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ガイドを選ぶ")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                            .tracking(0.5)
                            .padding(.leading, 4)

                        ForEach(GuideExercise.allCases) { exercise in
                            exerciseCard(exercise)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)

                    // ── 注意書き ──────────────────────────────────────
                    Text("本機能は視覚的なリラクゼーション補助を目的としています。\n医療効果や治療効果を保証するものではありません。")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(item: $selectedExercise) { exercise in
            GuideSessionView(exercise: exercise)
        }
    }

    // MARK: - 既存の発光リング（呼吸リズムの ambient 表現・変更なし）

    private var breathingRing: some View {
        ZStack {
            Circle()
                .fill(MindWaveTheme.accentGlow.opacity(0.05))
                .frame(width: 240, height: 240)
                .scaleEffect(expanding ? 1.12 : 0.90)
                .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: expanding)

            Circle()
                .fill(MindWaveTheme.accentGlow.opacity(0.09))
                .frame(width: 185, height: 185)
                .scaleEffect(expanding ? 1.08 : 0.94)
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: expanding)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            MindWaveTheme.accent,
                            MindWaveTheme.accentGlow.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 140, height: 140)
                .scaleEffect(expanding ? 1.05 : 0.96)
                .shadow(color: MindWaveTheme.accent.opacity(0.45), radius: 14)
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: expanding)

            Circle()
                .strokeBorder(MindWaveTheme.accent.opacity(0.20), lineWidth: 1)
                .frame(width: 105, height: 105)
                .scaleEffect(expanding ? 0.96 : 1.04)
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: expanding)

            Text("ゆっくり吸って、ゆっくり吐く")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(MindWaveTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 140)
                .offset(y: 88)
        }
        .onAppear { expanding = true }
        .accessibilityLabel("ゆっくりと拡縮する呼吸ガイドリング")
        .accessibilityAddTraits(.isImage)
    }

    // MARK: - ガイドカード

    /// 各ガイド種別を薄いガラスカードとして表示する。タップで GuideSessionView を開く。
    private func exerciseCard(_ exercise: GuideExercise) -> some View {
        Button {
            selectedExercise = exercise
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: exercise.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.cyan.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MindWaveTheme.textPrimary)
                    Text(exercise.description)
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(MindWaveTheme.textTertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(exercise.title)を開始する")
        .accessibilityHint(exercise.description)
    }
}

#Preview {
    GuideView()
        .preferredColorScheme(.dark)
}
