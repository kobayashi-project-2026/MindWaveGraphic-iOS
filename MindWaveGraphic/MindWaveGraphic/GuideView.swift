//
//  GuideView.swift
//  MindWaveGraphic
//
//  既存ロジックを維持したUI統合：Cyber UIデザインを適用。
//  場面選択・GuideFlowView遷移・3モード呼吸・クイックスタートは変更しない。
//  MindWaveSyncTransitionViewは3モード呼吸ガイドを開く経路のみに適用。
//

import SwiftUI

struct GuideView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var historyStore: GuideHistoryStore
    @Binding var selectedTab: Int

    // MARK: - State（既存・変更なし）

    @State private var expanding          = false
    @State private var selectedScene: MeasurementScene? = nil
    @State private var selectedExercise: GuideExercise? = nil
    @State private var showFlowView       = false
    @State private var showOtherSheet     = false
    @State private var showBreathingModes = false

    // MARK: - 主要場面（既存・変更なし）

    private let primaryScenes: [MeasurementScene] = [.interview, .sports, .social, .other]

    private func cardTitle(for scene: MeasurementScene) -> String {
        switch scene {
        case .interview: return "面接前"
        case .sports:    return "試合前"
        case .social:    return "デート前"
        case .other:     return "その他"
        case .study:     return "試験・勉強"
        case .meeting:   return "重要な会議"
        case .speech:    return "スピーチ"
        case .daily:     return "日常計測"
        }
    }

    private func cardSubtitle(for scene: MeasurementScene) -> String {
        switch scene {
        case .interview: return "プレゼン / 発表"
        case .sports:    return "スポーツ / 大会"
        case .social:    return "大切な約束"
        case .other:     return "カスタム計測"
        default:         return ""
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            MindWaveCyberBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── ACTIVE SCENE ヘッダー（新規）────────────────────
                    activeSceneHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                    // ── ページタイトル ────────────────────────────────
                    VStack(spacing: 6) {
                        Text("整える")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(MindWaveCyberTheme.textPrimary)
                            .tracking(3)
                        Text("呼吸と流れを意識する時間")
                            .font(.system(size: 13, weight: .light, design: .monospaced))
                            .foregroundStyle(MindWaveCyberTheme.textSecondary)
                    }
                    .padding(.bottom, 24)

                    // ── 既存の発光リング（変更なし）────────────────────
                    breathingRing
                        .padding(.bottom, 28)

                    // ── 場面選択（Cyber UI化）────────────────────────
                    VStack(spacing: 10) {
                        MindWaveCyberSectionHeader(title: "SCENE SELECT")
                            .padding(.leading, 4)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(primaryScenes) { scene in
                                cyberSceneCard(scene)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .animation(.easeInOut(duration: 0.2), value: selectedScene)

                    // ── 呼吸セッション開始ボタン（Cyber UI化・既存処理維持）──
                    Button {
                        guard let scene = selectedScene else { return }
                        print("[Regulation] session requested scene=\(scene.rawValue)")
                        showFlowView = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wind").font(.system(size: 14))
                            Text("呼吸セッションを開始する")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(selectedScene != nil ? .black : MindWaveCyberTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(selectedScene != nil
                                      ? MindWaveCyberTheme.cyan
                                      : MindWaveCyberTheme.cyan.opacity(0.15))
                                .shadow(color: selectedScene != nil
                                        ? MindWaveCyberTheme.cyan.opacity(0.35) : .clear,
                                        radius: 10, x: 0, y: 0)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedScene == nil)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .accessibilityLabel("呼吸セッションを開始する")
                    .accessibilityHint(selectedScene == nil ? "場面を先に選んでください" : "選択した場面でガイドを開始します")

                    // ── 3モード呼吸ガイド（同期演出付き・Cyber UI化）────
                    cyberBreathingCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    // ── クイックスタート（Cyber UI化・既存処理維持）────
                    VStack(alignment: .leading, spacing: 12) {
                        MindWaveCyberSectionHeader(title: "QUICK START")
                            .padding(.leading, 4)

                        ForEach(GuideExercise.allCases) { exercise in
                            cyberExerciseCard(exercise)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                    Text("本機能は視覚的なリラクゼーション補助を目的としています。\n医療効果や治療効果を保証するものではありません。")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear { print("[CyberUI] guide appeared") }
        .fullScreenCover(isPresented: $showFlowView) {
            GuideFlowView(selectedTab: $selectedTab, initialScene: selectedScene)
                .environmentObject(viewModel)
                .environmentObject(historyStore)
        }
        .fullScreenCover(item: $selectedExercise) { exercise in
            GuideSessionView(exercise: exercise)
        }
        // 同期演出 → MindWaveBreathingGuideView の順で表示
        .fullScreenCover(isPresented: $showBreathingModes) {
            BreathingWithSyncWrapper()
        }
        .sheet(isPresented: $showOtherSheet) {
            OtherSceneSelectorView(
                selectedScene: $selectedScene,
                isPresented: $showOtherSheet
            )
        }
    }

    // MARK: - ACTIVE SCENE ヘッダー

    private var activeSceneHeader: some View {
        MindWaveCyberPanel(title: "ACTIVE SCENE") {
            HStack(spacing: 10) {
                if let scene = selectedScene {
                    Image(systemName: scene.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(MindWaveCyberTheme.cyan)
                    Text(cardTitle(for: scene))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MindWaveCyberTheme.textPrimary)
                    Text("·")
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                    Text(cardSubtitle(for: scene))
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(MindWaveCyberTheme.textSecondary)
                } else {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                    Text("未選択")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                }
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedScene)
    }

    // MARK: - 場面カード（Cyber UI化・既存選択ロジック維持）

    private func cyberSceneCard(_ scene: MeasurementScene) -> some View {
        let selected = isSelected(scene)
        return Button {
            if scene == .other {
                showOtherSheet = true
            } else {
                selectedScene = scene
                print("[Navigation] scene selected: \(scene.rawValue)")
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(selected
                              ? MindWaveCyberTheme.cyan.opacity(0.20)
                              : Color.white.opacity(0.06))
                        .frame(width: 46, height: 46)
                        .shadow(color: selected ? MindWaveCyberTheme.cyan.opacity(0.4) : .clear,
                                radius: 8)
                    Image(systemName: scene.icon)
                        .font(.system(size: 21))
                        .foregroundStyle(selected ? MindWaveCyberTheme.cyan : MindWaveCyberTheme.textSecondary)
                }
                Text(cardTitle(for: scene))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? MindWaveCyberTheme.textPrimary : MindWaveCyberTheme.textSecondary)
                    .lineLimit(1)
                Text(cardSubtitle(for: scene))
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(selected ? MindWaveCyberTheme.cyan.opacity(0.8) : MindWaveCyberTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected
                          ? MindWaveCyberTheme.cyan.opacity(0.10)
                          : MindWaveCyberTheme.panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                selected ? MindWaveCyberTheme.cyan.opacity(0.55) : MindWaveCyberTheme.borderColor,
                                lineWidth: selected ? 1.5 : 1
                            )
                    )
                    .shadow(color: selected ? MindWaveCyberTheme.cyan.opacity(0.15) : .clear, radius: 12)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cardTitle(for: scene))
        .accessibilityHint("この場面を選択します")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func isSelected(_ scene: MeasurementScene) -> Bool {
        guard let selectedScene else { return false }
        if scene == .other {
            return [MeasurementScene.study, .meeting, .speech, .daily, .other].contains(selectedScene)
        }
        return selectedScene == scene
    }

    // MARK: - 3モード呼吸カード（Cyber UI化）

    private var cyberBreathingCard: some View {
        Button {
            print("[CyberUI] breathing guide presented")
            showBreathingModes = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(MindWaveCyberTheme.cyan.opacity(0.12))
                        .frame(width: 46, height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(MindWaveCyberTheme.cyan.opacity(0.25), lineWidth: 1)
                        )
                    Image(systemName: "lungs.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(MindWaveCyberTheme.cyan)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("3モード呼吸ガイド")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(MindWaveCyberTheme.textPrimary)
                    Text("4-7-8 · BOX · 2-1-4 から選んで整える")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(MindWaveCyberTheme.panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(MindWaveCyberTheme.cyan.opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("3モード呼吸ガイドを開く")
        .accessibilityHint("4-7-8・BOX・2-1-4 の呼吸モードから選べます")
    }

    // MARK: - クイックスタートカード（Cyber UI化・既存処理維持）

    private func cyberExerciseCard(_ exercise: GuideExercise) -> some View {
        Button {
            selectedExercise = exercise
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(MindWaveCyberTheme.cyan.opacity(0.10))
                        .frame(width: 46, height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(MindWaveCyberTheme.cyan.opacity(0.22), lineWidth: 1)
                        )
                    Image(systemName: exercise.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(MindWaveCyberTheme.cyan.opacity(0.90))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MindWaveCyberTheme.textPrimary)
                    Text(exercise.description)
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(MindWaveCyberTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
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
        .buttonStyle(.plain)
        .accessibilityLabel("\(exercise.title)を開始する")
        .accessibilityHint(exercise.description)
    }

    // MARK: - 既存の発光リング（変更なし）

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
                        colors: [MindWaveCyberTheme.cyan, MindWaveTheme.accentGlow.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 140, height: 140)
                .scaleEffect(expanding ? 1.05 : 0.96)
                .shadow(color: MindWaveCyberTheme.cyan.opacity(0.50), radius: 16)
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: expanding)

            Circle()
                .strokeBorder(MindWaveCyberTheme.cyan.opacity(0.18), lineWidth: 1)
                .frame(width: 105, height: 105)
                .scaleEffect(expanding ? 0.96 : 1.04)
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: expanding)

            Text("ゆっくり吸って、ゆっくり吐く")
                .font(.system(size: 11, weight: .light, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 140)
                .offset(y: 88)
        }
        .onAppear { expanding = true }
        .accessibilityLabel("ゆっくりと拡縮する呼吸ガイドリング")
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - 同期演出ラッパー
// 3モード呼吸ガイドを開く前にMindWaveSyncTransitionViewを表示する。
// 同期演出は純粋な視覚演出であり、測定・解析は行わない。

private struct BreathingWithSyncWrapper: View {
    @State private var syncDone = false

    var body: some View {
        if syncDone {
            MindWaveBreathingGuideView()
        } else {
            MindWaveSyncTransitionView(subtitle: "呼吸ガイドを準備しています") {
                syncDone = true
            }
        }
    }
}

// MARK: - OtherSceneSelectorView（既存・Cyber UI化）

private struct OtherSceneSelectorView: View {
    @Binding var selectedScene: MeasurementScene?
    @Binding var isPresented: Bool

    private let subScenes: [(scene: MeasurementScene, label: String)] = [
        (.study,   "試験・勉強"),
        (.meeting, "重要な会議"),
        (.speech,  "スピーチ"),
        (.daily,   "日常計測"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                MindWaveCyberBackground()

                VStack(spacing: 12) {
                    ForEach(subScenes, id: \.scene) { item in
                        Button {
                            selectedScene = item.scene
                            print("[Navigation] scene selected: \(item.scene.rawValue)")
                            isPresented = false
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.scene.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(MindWaveCyberTheme.cyan.opacity(0.85))
                                    .frame(width: 32)
                                Text(item.label)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
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
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.label)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("場面を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isPresented = false }
                        .foregroundStyle(MindWaveCyberTheme.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    GuideView(selectedTab: .constant(1))
        .environmentObject(MindWaveViewModel())
        .environmentObject(GuideHistoryStore())
        .preferredColorScheme(.dark)
}
