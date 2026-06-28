// MainTabView.swift
// App

import SwiftUI

struct MainTabView: View {

    // MARK: - 状態

    @StateObject private var viewModel    = MindWaveViewModel()
    @StateObject private var historyStore = GuideHistoryStore()
    @State       private var selectedTab  = 0

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
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
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 76).allowsHitTesting(false)
            }

            missionBar
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .environmentObject(viewModel)
        .environmentObject(historyStore)
        .preferredColorScheme(.dark)
        .onChange(of: selectedTab) { _, newValue in
            print("[UI][Tab] selected index=\(newValue)")
        }
    }

    // MARK: - ミッションバー（洗練されたタブバー）

    private let items: [(label: String, icon: String, activeIcon: String)] = [
        ("ホーム",   "waveform.path.ecg",  "waveform.path.ecg"),
        ("整える",   "wind",               "wind"),
        ("履歴",     "clock",              "clock.fill"),
    ]

    private var missionBar: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { idx in
                let active = selectedTab == idx
                Button {
                    selectedTab = idx
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: active ? items[idx].activeIcon : items[idx].icon)
                            .font(.system(size: 17, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.cyan : Color.white.opacity(0.38))

                        // 選択インジケーター
                        RoundedRectangle(cornerRadius: 1)
                            .fill(active ? Color.cyan : Color.clear)
                            .frame(width: 18, height: 1.5)
                            .shadow(color: active ? Color.cyan.opacity(0.7) : .clear, radius: 3)

                        Text(items[idx].label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(active ? Color.cyan.opacity(0.80) : Color.white.opacity(0.28))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.22), value: active)
                .accessibilityLabel(items[idx].label)
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.04, green: 0.05, blue: 0.12).opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                )
                .overlay(
                    // 上部アクセントライン
                    VStack {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.cyan.opacity(0.20))
                            .frame(height: 1)
                        Spacer()
                    }
                )
                .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 8)
        )
    }
}

#Preview {
    MainTabView()
}
