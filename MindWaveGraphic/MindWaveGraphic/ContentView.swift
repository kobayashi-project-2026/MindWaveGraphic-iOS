
import SwiftUI

/// アプリのルートView。TabViewで4画面（ホーム・ガイド・履歴・設定）を管理する。
/// MindWaveViewModelをStateObjectとして生成し、全子Viewへ EnvironmentObject で共有する。
/// GuideHistoryStoreもここで生成し、GuideFlowViewとHistoryViewが同じインスタンスを共有する。
/// 旧Liveタブは削除済み。ライブ計測機能はHomeViewへ統合されている。
struct ContentView: View {
    /// アプリ全体で1つだけ生成するViewModel。EnvironmentObjectで全タブへ共有する。
    @StateObject private var viewModel = MindWaveViewModel()
    /// ガイドセッション履歴。GuideFlowViewとHistoryViewが共有する。
    @StateObject private var historyStore = GuideHistoryStore()
    /// タブ選択状態。GuideFlowViewが保存後にHistoryタブへ遷移するために使う。
    @State private var selectedTab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 0.95)
        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // ホーム（旧Liveタブの計測機能を統合した没入型メイン画面）
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(0)

            // ガイド（シーン選択 → ガイド → 再測定 → 結果）
            GuideView(selectedTab: $selectedTab)
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
        .environmentObject(historyStore)
        .tint(MindWaveTheme.accent)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
