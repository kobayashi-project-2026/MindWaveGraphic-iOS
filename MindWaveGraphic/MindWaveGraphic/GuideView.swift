//
//  GuideView.swift
//  MindWaveGraphic
//
//  参考写真レイアウトへ全面再設計。
//  場面選択・GuideFlowView遷移処理は変更しない。
//  3モード呼吸はHomeViewのQuick Workから利用。
//  Ripple/FlowはGuideFlowView内で選択。
//

import SwiftUI

struct GuideView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var historyStore: GuideHistoryStore
    @Binding var selectedTab: Int

    // MARK: - State（必要最小限）

    @State private var selectedScene: MeasurementScene? = nil
    @State private var showFlowView   = false
    @State private var showOtherSheet = false

    // MARK: - 場面データ

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
        case .interview: return "プレゼン・発表"
        case .sports:    return "スポーツ・大会"
        case .social:    return "大切な約束"
        case .other:     return "カスタム計測"
        default:         return ""
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            MindWaveCyberBackground()

            VStack(spacing: 0) {

                // ── スクロール可能なコンテンツ ────────────────────────
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        // アクティブな場面パネル
                        activeScenePanel
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        // 案内文
                        Text("▼ 挑むシチュエーションを選択してください")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(MindWaveCyberTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        // 場面グリッド（2×2）
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(primaryScenes) { scene in
                                cyberSceneCard(scene)
                            }
                        }
                        .padding(.horizontal, 20)
                        .animation(.easeInOut(duration: 0.2), value: selectedScene)

                        // CTA より下の余白（ctaSection の高さ＋タブバー分）
                        Spacer().frame(height: 20)
                    }
                }

                // ── 固定CTA（タブバー直上）────────────────────────────
                ctaSection
            }
        }
        .onAppear { print("[ReferenceUI] scene selection appeared") }
        .fullScreenCover(isPresented: $showFlowView) {
            GuideFlowView(selectedTab: $selectedTab, initialScene: selectedScene)
                .environmentObject(viewModel)
                .environmentObject(historyStore)
        }
        .sheet(isPresented: $showOtherSheet) {
            OtherSceneSelectorView(
                selectedScene: $selectedScene,
                isPresented: $showOtherSheet
            )
        }
    }

    // MARK: - アクティブ場面パネル（日本語中心）

    private var activeScenePanel: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("アクティブな場面設定")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                    .tracking(0.5)
                if let scene = selectedScene {
                    Text("【場面：\(cardTitle(for: scene))】")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MindWaveCyberTheme.textPrimary)
                        .transition(.opacity)
                } else {
                    Text("【場面：未選択】")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                }
            }
            Spacer()
            if let scene = selectedScene {
                Image(systemName: scene.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(MindWaveCyberTheme.cyan)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(MindWaveCyberTheme.panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            selectedScene != nil
                                ? MindWaveCyberTheme.cyan.opacity(0.40)
                                : MindWaveCyberTheme.borderColor,
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: selectedScene)
    }

    // MARK: - 場面カード（選択時は全面シアン）

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
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected
                              ? Color.black.opacity(0.12)
                              : Color.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image(systemName: scene.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? Color.black : MindWaveCyberTheme.textSecondary)
                }
                Text(cardTitle(for: scene))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Color.black : MindWaveCyberTheme.textPrimary)
                    .lineLimit(1)
                Text(cardSubtitle(for: scene))
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(selected ? Color.black.opacity(0.70) : MindWaveCyberTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? MindWaveCyberTheme.cyan : MindWaveCyberTheme.panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                selected
                                    ? MindWaveCyberTheme.cyan
                                    : MindWaveCyberTheme.borderColor,
                                lineWidth: selected ? 0 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: selected)
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

    // MARK: - 固定CTA（タブバー直上）

    private var ctaSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(MindWaveCyberTheme.borderColor)
                .frame(height: 1)

            Button {
                guard selectedScene != nil else { return }
                print("[Regulation] session requested scene=\(selectedScene!.rawValue)")
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
                              : MindWaveCyberTheme.panelBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    selectedScene != nil
                                        ? MindWaveCyberTheme.cyan
                                        : MindWaveCyberTheme.borderColor,
                                    lineWidth: selectedScene != nil ? 0 : 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedScene == nil)
            .animation(.easeInOut(duration: 0.2), value: selectedScene)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .accessibilityLabel("呼吸セッションを開始する")
            .accessibilityHint(selectedScene == nil ? "場面を先に選んでください" : "選択した場面でガイドを開始します")
        }
        .background(
            MindWaveCyberTheme.background
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - OtherSceneSelectorView（変更なし）

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
