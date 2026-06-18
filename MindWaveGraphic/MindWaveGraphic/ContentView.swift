//
//  ContentView.swift
//  MindWaveGraphic
//
//  アプリのルートView。TabViewで4画面（ホーム・ガイド・履歴・設定）を管理する。
//  MindWaveViewModelをStateObjectとして生成し、全子Viewへ EnvironmentObject で共有する。
//  旧Liveタブは削除済み。ライブ計測機能はHomeViewへ統合されている。
//

import SwiftUI

struct ContentView: View {
    /// アプリ全体で1つだけ生成するViewModel。EnvironmentObjectで全タブへ共有する。
    @StateObject private var viewModel = MindWaveViewModel()

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 0.95)
        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            // ホーム（旧Liveタブの計測機能を統合した没入型メイン画面）
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(0)

            // ガイド（使い方・HRV説明）
            GuideView()
                .tabItem { Label("ガイド", systemImage: "wind") }
                .tag(1)

            // 履歴（過去セッション記録）
            HistoryView()
                .tabItem { Label("履歴", systemImage: "clock.fill") }
                .tag(2)

            // 設定（Account / 表示設定 / データとプライバシー）
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
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
