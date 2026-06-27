// MainTabView.swift
// App

import SwiftUI

struct MainTabView: View {

    // MARK: - 状態

    @StateObject private var viewModel    = MindWaveViewModel()
    @StateObject private var historyStore = GuideHistoryStore()
    @State       private var selectedTab  = 0   // 初期タブ: ホーム

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {

            // コンテンツ（システムTabBarは .toolbar(.hidden) で非表示）
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: $selectedTab)
                    .tag(0)
                    .toolbar(.hidden, for: .tabBar)
                GuideView(selectedTab: $selectedTab)
                    .tag(1)
                    .toolbar(.hidden, for: .tabBar)
                HistoryView()
                    .tag(2)
                    .toolbar(.hidden, for: .tabBar)
            }
            // カスタムタブバー分の余白（allowsHitTesting(false)でタッチ遮断を防ぐ）
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 80).allowsHitTesting(false)
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
            print("[UI][Tab] selected index=\(newValue)")
        }
    }

    // MARK: - カスタムタブバー

    private var customTabBar: some View {
        let items: [(label: String, icon: String, activeIcon: String)] = [
            ("ホーム",   "waveform.path.ecg",  "waveform.path.ecg"),
            ("整える",   "wind",               "wind"),
            ("履歴",     "clock",              "clock.fill"),
        ]

        return HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { idx in
                let isSelected = selectedTab == idx
                Button {
                    selectedTab = idx
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: isSelected ? items[idx].activeIcon : items[idx].icon)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                        Text(items[idx].label)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? Color.cyan : Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[idx].label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(Color(red: 0.04, green: 0.05, blue: 0.12).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.50), radius: 20, x: 0, y: 8)
        )
    }
}

#Preview {
    MainTabView()
}
