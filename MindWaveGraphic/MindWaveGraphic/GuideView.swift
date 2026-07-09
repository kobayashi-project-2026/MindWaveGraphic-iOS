//
//  GuideView.swift
//  MindWaveGraphic
//
//  「整える」画面。場面を選んでから呼吸ガイドへ進む。
//  架空の値は使用しない。GuideFlowViewへの遷移を維持する。
//

import SwiftUI

struct GuideView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var historyStore: GuideHistoryStore
    @Binding var selectedTab: Int

    @State private var selectedScene: MeasurementScene? = nil
    @State private var showFlowView   = false
    @State private var showOtherSheet = false

    private let primaryScenes: [MeasurementScene] = [.interview, .sports, .social, .other]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    selectionHint
                        .padding(.horizontal, 20)
                    sceneGrid
                        .padding(.horizontal, 20)
                    Spacer().frame(height: 8)
                }
                .padding(.top, 4)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                pageHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .background(Color(red: 0.02, green: 0.02, blue: 0.06).opacity(0.98))
            }
            ctaSection
            Spacer().frame(height: MainTabView.missionBarReservedHeight)
        }
        .background(background)
        .onAppear {
            print("[UI][Guide] view_appeared")
            #if DEBUG
            if ProcessInfo.processInfo.environment["GUIDE_PHASE"] == "session" {
                selectedScene = .interview
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showFlowView = true
                }
            }
            #endif
        }
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

    // MARK: - 背景

    private var background: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.06).ignoresSafeArea()
            CyberGridShape(cellSize: 44)
                .stroke(Color.cyan.opacity(0.025), lineWidth: 0.5)
                .ignoresSafeArea()
        }
    }

    // MARK: - ページヘッダー

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("整える")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)
            Text("シチュエーションを選んで呼吸ガイドを開始します")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 選択ヒント

    @ViewBuilder
    private var selectionHint: some View {
        if let scene = selectedScene {
            HStack(spacing: 12) {
                Image(systemName: scene.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.cyan)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardTitle(for: scene))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("この場面に合わせた呼吸ガイドで整えます")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.50))
                }
                Spacer()
                Button {
                    selectedScene = nil
                    print("[UI][Guide] scene_cleared")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.30))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("選択を解除する")
            }
            .padding(14)
            .background(Color(red: 0.05, green: 0.08, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cyan.opacity(0.30), lineWidth: 1))
            .animation(.easeInOut(duration: 0.2), value: selectedScene)
        } else {
            Text("どんな場面の前ですか？")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 場面グリッド（2×2）

    private var sceneGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(primaryScenes) { scene in
                sceneCard(scene)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedScene)
    }

    private func sceneCard(_ scene: MeasurementScene) -> some View {
        let selected = isSelected(scene)
        return Button {
            if scene == .other {
                showOtherSheet = true
            } else {
                selectedScene = scene
                print("[UI][Guide] scene_selected value=\(scene.rawValue)")
            }
        } label: {
            VStack(spacing: 10) {
                Spacer()
                ZStack {
                    // 場面固有の背景モチーフ
                    Circle()
                        .fill(selected ? Color.cyan.opacity(0.20) : sceneAccent(scene).opacity(0.08))
                        .frame(width: 52, height: 52)
                    Image(systemName: scene.icon)
                        .font(.system(size: 24, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.cyan : sceneAccent(scene))
                }
                VStack(spacing: 3) {
                    Text(cardTitle(for: scene))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.85))
                        .lineLimit(1)
                    Text(cardSubtitle(for: scene))
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.60) : Color.white.opacity(0.38))
                        .lineLimit(1)
                }
                Spacer()
                // 選択インジケーター
                if selected {
                    Capsule()
                        .fill(Color.cyan)
                        .frame(width: 24, height: 3)
                        .padding(.bottom, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected
                          ? Color(red: 0.04, green: 0.10, blue: 0.14)
                          : Color(red: 0.05, green: 0.07, blue: 0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                selected ? Color.cyan.opacity(0.45) : Color.white.opacity(0.07),
                                lineWidth: selected ? 1.5 : 1
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

    private func sceneAccent(_ scene: MeasurementScene) -> Color {
        switch scene {
        case .interview: return Color(red: 0.45, green: 0.80, blue: 0.95)
        case .sports:    return Color(red: 0.20, green: 0.85, blue: 0.60)
        case .social:    return Color(red: 0.90, green: 0.65, blue: 0.40)
        case .other:     return Color.white.opacity(0.55)
        default:         return Color.cyan
        }
    }

    private func isSelected(_ scene: MeasurementScene) -> Bool {
        guard let s = selectedScene else { return false }
        if scene == .other {
            return [MeasurementScene.study, .meeting, .speech, .daily, .other].contains(s)
        }
        return s == scene
    }

    // MARK: - テキストラベル

    private func cardTitle(for scene: MeasurementScene) -> String {
        switch scene {
        case .interview: return "面接・発表前"
        case .sports:    return "試合・大会前"
        case .social:    return "大切な約束前"
        case .other:     return "その他の場面"
        case .study:     return "試験・勉強"
        case .meeting:   return "重要な会議"
        case .speech:    return "スピーチ"
        case .daily:     return "日常の計測"
        }
    }

    private func cardSubtitle(for scene: MeasurementScene) -> String {
        switch scene {
        case .interview: return "緊張を和らげ集中へ"
        case .sports:    return "心拍を整えリズムへ"
        case .social:    return "気持ちを落ち着かせて"
        case .other:     return "目的に合わせて選択"
        default:         return ""
        }
    }

    // MARK: - CTA セクション

    private var ctaSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
            Button {
                guard selectedScene != nil else { return }
                print("[UI][Guide] session_start_requested scene=\(selectedScene!.rawValue)")
                showFlowView = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wind")
                        .font(.system(size: 15))
                    Text(selectedScene != nil ? "この場面で整える" : "場面を選んでください")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(selectedScene != nil ? Color.black : Color.white.opacity(0.60))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(selectedScene != nil ? Color.cyan : Color(red: 0.10, green: 0.13, blue: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selectedScene != nil ? .clear : Color.white.opacity(0.30), lineWidth: 1)
                )
            }
            .disabled(selectedScene == nil)
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: selectedScene)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .accessibilityLabel(selectedScene != nil ? "この場面で整える" : "場面を選んでから開始できます")
            .accessibilityIdentifier("guide_start_button")
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - OtherSceneSelector

private struct OtherSceneSelectorView: View {
    @Binding var selectedScene: MeasurementScene?
    @Binding var isPresented: Bool

    private let subScenes: [(scene: MeasurementScene, label: String, sub: String)] = [
        (.study,   "試験・勉強",   "集中と記憶力"),
        (.meeting, "重要な会議",   "落ち着きと明晰さ"),
        (.speech,  "スピーチ",     "声と気持ちを整える"),
        (.daily,   "日常の計測",   "毎日の習慣として"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.02, green: 0.02, blue: 0.06).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(subScenes, id: \.scene) { item in
                            Button {
                                selectedScene = item.scene
                                print("[UI][Guide] other_scene_selected value=\(item.scene.rawValue)")
                                isPresented = false
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: item.scene.icon)
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.cyan.opacity(0.80))
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Color.white)
                                        Text(item.sub)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.45))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.25))
                                }
                                .padding(16)
                                .frame(minHeight: 60)
                                .background(Color(red: 0.05, green: 0.07, blue: 0.11))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.label)
                            .accessibilityHint(item.sub)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("その他の場面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isPresented = false }
                        .foregroundStyle(Color.cyan)
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
