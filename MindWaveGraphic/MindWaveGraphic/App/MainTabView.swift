// MainTabView.swift
// App
//
// 参考写真に合わせたカスタム浮遊タブバーへ全面再設計。
// システムTabBarを使用せず、ZStack+カスタムピルバーで実装。
// ViewModelとGuideHistoryStoreは変更なし（1回だけ生成・EnvironmentObject共有）。
//
// タブ構成：
//   tag 0: リアルタイム計測  (HomeView)
//   tag 1: 作戦・場面選択    (GuideView)
//   tag 2: ログ履歴          (HistoryView)
//
// 初期表示は「作戦・場面選択（tag 1）」。
//

import SwiftUI

struct MainTabView: View {

    // MARK: - 状態所有（各1インスタンス）

    @StateObject private var viewModel     = MindWaveViewModel()
    @StateObject private var historyStore  = GuideHistoryStore()
    @State       private var selectedTab   = 1

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {

            // コンテンツ（TabView・システムタブバーなし）
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: $selectedTab)
                    .tag(0)
                GuideView(selectedTab: $selectedTab)
                    .tag(1)
                HistoryView()
                    .tag(2)
            }
            // カスタムタブバー分の安全エリアをコンテンツに追加
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 80)
            }

            // カスタム浮遊タブバー
            customTabBar
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .environmentObject(viewModel)
        .environmentObject(historyStore)
        .preferredColorScheme(.dark)
        .onChange(of: selectedTab) { _, newValue in
            switch newValue {
            case 0:  print("[Navigation] main tab changed: measurement")
            case 1:  print("[Navigation] main tab changed: sceneSelection")
            case 2:  print("[Navigation] main tab changed: history")
            default: print("[Navigation] main tab changed: unknown(\(newValue))")
            }
        }
    }

    // MARK: - カスタム浮遊タブバー

    private var customTabBar: some View {
        let items: [(label: String, icon: String, activeIcon: String)] = [
            ("リアルタイム計測", "bolt",     "bolt.fill"),
            ("作戦・場面選択",   "cpu",      "cpu"),
            ("ログ履歴",         "terminal", "terminal.fill"),
        ]

        return HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { idx in
                let isSelected = selectedTab == idx
                Button {
                    selectedTab = idx
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isSelected ? items[idx].activeIcon : items[idx].icon)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        Text(items[idx].label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(isSelected ? MindWaveCyberTheme.cyan : .white.opacity(0.50))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(MindWaveCyberTheme.cyan.opacity(isSelected ? 0.16 : 0))
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        MindWaveCyberTheme.cyan.opacity(isSelected ? 0.30 : 0),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .animation(.easeInOut(duration: 0.18), value: selectedTab)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(items[idx].label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(red: 0.04, green: 0.05, blue: 0.12).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
        )
    }
}

#Preview {
    MainTabView()
}
