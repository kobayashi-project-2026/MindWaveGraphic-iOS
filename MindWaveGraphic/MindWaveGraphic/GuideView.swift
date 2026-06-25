//
//  GuideView.swift
//  MindWaveGraphic
//
//  ガイドタブのメイン画面（フェーズ4改訂版）。
//  場面選択カード（面接前・試合前・デート前・その他）を主要選択肢として配置し、
//  「呼吸セッションを開始する」ボタンで GuideFlowView へ渡す。
//
//  既存の発光リング・クイックスタート・呼吸ガイドは維持する。
//  GuideFlowView は initialScene を受け取り scene 選択をスキップして
//  exerciseSelection から開始する。
//

import SwiftUI

struct GuideView: View {
    @EnvironmentObject var viewModel: MindWaveViewModel
    @EnvironmentObject var historyStore: GuideHistoryStore
    /// タブ移動用。MainTabViewから渡される。
    @Binding var selectedTab: Int

    // MARK: - State

    @State private var expanding           = false
    /// 選択中の場面（主要4選択肢から選ぶ）
    @State private var selectedScene: MeasurementScene? = nil
    /// クイックスタート用（既存GuideSessionViewへ直接遷移）
    @State private var selectedExercise: GuideExercise? = nil
    /// GuideFlowViewのfullScreenCover表示フラグ
    @State private var showFlowView        = false
    /// 「その他」サブ選択シート
    @State private var showOtherSheet      = false
    /// 3モード呼吸ガイド（既存フローとは独立した追加UI）
    @State private var showBreathingModes  = false

    // MARK: - 主要場面（4カード固定表示）
    /// GuideViewの主要選択肢。その他は別途シートで展開する。
    private let primaryScenes: [MeasurementScene] = [.interview, .sports, .social, .other]

    // MARK: - 表示名オーバーライド（GuideView専用・短縮表示）
    private func cardTitle(for scene: MeasurementScene) -> String {
        switch scene {
        case .interview: return "面接前"
        case .sports:    return "試合前"
        case .social:    return "デート前"
        case .other:     return "その他"
        // サブ選択肢（現在選択中の場面表示に使用）
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

                    // ── 既存の発光リング（ambient アニメーション・変更なし）──
                    breathingRing
                        .padding(.bottom, 28)

                    // ── 現在選択中の場面表示 ─────────────────────────
                    if let scene = selectedScene {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(MindWaveTheme.accent.opacity(0.8))
                            Text("場面：\(cardTitle(for: scene))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MindWaveTheme.accent.opacity(0.9))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(MindWaveTheme.accent.opacity(0.10))
                        )
                        .padding(.bottom, 16)
                        .transition(.opacity)
                    }

                    // ── 場面選択カード（2列グリッド）──────────────────
                    VStack(spacing: 10) {
                        Text("場面を選ぶ")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                            .tracking(0.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(primaryScenes) { scene in
                                sceneCard(scene)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .animation(.easeInOut(duration: 0.2), value: selectedScene)

                    // ── 呼吸セッションを開始するボタン ──────────────────
                    Button {
                        guard let scene = selectedScene else { return }
                        print("[Regulation] session requested scene=\(scene.rawValue)")
                        showFlowView = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wind")
                                .font(.system(size: 14))
                            Text("呼吸セッションを開始する")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(selectedScene != nil ? .black : MindWaveTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(selectedScene != nil
                                      ? MindWaveTheme.accent
                                      : MindWaveTheme.accent.opacity(0.20))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedScene == nil)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .accessibilityLabel("呼吸セッションを開始する")
                    .accessibilityHint(selectedScene == nil ? "場面を先に選んでください" : "選択した場面でガイドを開始します")

                    // ── 3モード呼吸ガイド（追加入口・既存フローとは独立）────
                    Button {
                        print("[Breathing] guide opened from GuideView")
                        showBreathingModes = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 42, height: 42)
                                Image(systemName: "lungs.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.cyan.opacity(0.85))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("3モード呼吸ガイド")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(MindWaveTheme.textPrimary)
                                Text("4-7-8・BOX・2-1-4 から選んで整える")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundStyle(MindWaveTheme.textTertiary)
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .accessibilityLabel("3モード呼吸ガイドを開く")
                    .accessibilityHint("4-7-8・BOX・2-1-4 の呼吸モードから選べます")

                    // ── クイックスタート（既存・変更なし）──────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("クイックスタート")
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
        // ── フルスクリーンカバー：場面選択 → GuideFlowView ──
        // initialScene を渡すことで sceneSelection ステップをスキップする
        .fullScreenCover(isPresented: $showFlowView) {
            GuideFlowView(selectedTab: $selectedTab, initialScene: selectedScene)
                .environmentObject(viewModel)
                .environmentObject(historyStore)
        }
        // ── フルスクリーンカバー：クイックスタート → GuideSessionView ──
        .fullScreenCover(item: $selectedExercise) { exercise in
            GuideSessionView(exercise: exercise)
        }
        // ── 3モード呼吸ガイド（既存 fullScreenCover と競合しない追加）──
        .fullScreenCover(isPresented: $showBreathingModes) {
            MindWaveBreathingGuideView()
        }
        // ── 「その他」サブ選択シート ──────────────────────────
        .sheet(isPresented: $showOtherSheet) {
            OtherSceneSelectorView(
                selectedScene: $selectedScene,
                isPresented: $showOtherSheet
            )
        }
    }

    // MARK: - 場面カード

    /// 主要4場面のカード表示。選択中は背景とボーダーをアクセントカラーへ変更。
    private func sceneCard(_ scene: MeasurementScene) -> some View {
        Button {
            if scene == .other {
                // 「その他」はサブ選択シートを開く
                showOtherSheet = true
            } else {
                selectedScene = scene
                print("[Navigation] scene selected: \(scene.rawValue)")
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected(scene) ? MindWaveTheme.accent.opacity(0.25) : Color.white.opacity(0.06))
                        .frame(width: 44, height: 44)
                    Image(systemName: scene.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected(scene) ? MindWaveTheme.accent : MindWaveTheme.textSecondary)
                }
                Text(cardTitle(for: scene))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected(scene) ? MindWaveTheme.textPrimary : MindWaveTheme.textSecondary)
                    .lineLimit(1)
                Text(cardSubtitle(for: scene))
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(isSelected(scene) ? MindWaveTheme.accent.opacity(0.8) : MindWaveTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected(scene)
                          ? MindWaveTheme.accent.opacity(0.12)
                          : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected(scene) ? MindWaveTheme.accent.opacity(0.5) : Color.white.opacity(0.10),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cardTitle(for: scene))
        .accessibilityAddTraits(isSelected(scene) ? [.isButton, .isSelected] : .isButton)
    }

    /// 指定場面が選択中か（「その他」からのサブ選択も考慮）。
    /// 「その他」カードは、サブ選択肢（.study/.meeting/.speech/.daily/.other）が
    /// 選ばれている場合に選択済みとして表示する。
    private func isSelected(_ scene: MeasurementScene) -> Bool {
        guard let selectedScene else { return false }
        if scene == .other {
            return [MeasurementScene.study, .meeting, .speech, .daily, .other].contains(selectedScene)
        }
        return selectedScene == scene
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
                        colors: [MindWaveTheme.accent, MindWaveTheme.accentGlow.opacity(0.5)],
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

    // MARK: - 既存クイックスタートカード（変更なし）

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

// MARK: - OtherSceneSelectorView

/// 「その他」をタップしたときに表示するサブ選択シート。
/// 試験・勉強 / 重要な会議 / スピーチ / 日常計測に戻る の4選択肢を表示する。
private struct OtherSceneSelectorView: View {

    @Binding var selectedScene: MeasurementScene?
    @Binding var isPresented: Bool

    /// 「その他」シートで選べるサブ選択肢
    private let subScenes: [(scene: MeasurementScene, label: String)] = [
        (.study,   "試験・勉強"),
        (.meeting, "重要な会議"),
        (.speech,  "スピーチ"),
        (.daily,   "日常計測に戻る"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.10).ignoresSafeArea()

                VStack(spacing: 14) {
                    ForEach(subScenes, id: \.scene) { item in
                        Button {
                            selectedScene = item.scene
                            print("[Navigation] scene selected: \(item.scene.rawValue)")
                            isPresented = false
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.scene.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.cyan.opacity(0.85))
                                    .frame(width: 32)
                                Text(item.label)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.90))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.30))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
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
