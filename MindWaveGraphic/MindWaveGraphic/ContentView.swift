//
//  ContentView.swift
//  MindWaveGraphic
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MindWaveViewModel()
    @State private var selectedTab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 0.96)
        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {

            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(0)

            LiveWaveView()
                .tabItem { Label("ライブ", systemImage: "waveform") }
                .tag(1)

            GuideView()
                .tabItem { Label("ガイド", systemImage: "wind") }
                .tag(2)

            HistoryView()
                .tabItem { Label("履歴", systemImage: "clock.fill") }
                .tag(3)
        }
        .environmentObject(viewModel)
        .tint(MindWaveTheme.accent)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
