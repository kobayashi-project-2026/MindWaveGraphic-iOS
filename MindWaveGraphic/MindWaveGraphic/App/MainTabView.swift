// MainTabView.swift
// App
//
// 認証後に表示される3タブのメインナビゲーション。
// AppRootView の authStatus = .mainApp で表示される。
//
// タブ構成：
//   tag 0: 計測      (HomeView)       ← 既存Mind Wave Graphic・WatchConnectivity
//   tag 1: 場面選択  (GuideView)      ← 既存シーン選択・呼吸ガイドフロー
//   tag 2: 履歴      (HistoryView)    ← 既存GuideHistoryStore表示
//
// 初期表示は「場面選択（tag 1）」とする。
//
// 状態オブジェクトの設計：
//   MindWaveViewModel と GuideHistoryStore をここで1回だけ生成し、
//   .environmentObject() で各タブへ共有する。
//   HomeView・GuideView・HistoryView は @EnvironmentObject で受け取り、
//   新規生成しない。これにより HealthKit Observer、Watch連携、
//   HRV Observer の重複起動を防ぐ。
//
// selectedTab は GuideView / GuideFlowView の「履歴へ保存後に tab 2 へ遷移」
// および HomeView の「整える → tab 1」へ同じ Binding で渡す。
// タグ番号は既存 ContentView と互換（Guide=1, History=2）なため変更不要。
//
// SettingsView は今回タブに含めない（フェーズ6で歯車ボタンからSheet接続予定）。

import SwiftUI

struct MainTabView: View {

    // MARK: - 状態所有（各1インスタンス）

    /// 心拍・HRV・GraphicInput・Watch連携をすべて管理するViewModel。
    /// このMainTabViewだけで生成し、@EnvironmentObjectで全タブへ共有する。
    @StateObject private var viewModel = MindWaveViewModel()

    /// ガイドセッション履歴ストア。
    /// GuideFlowViewとHistoryViewが同一インスタンスを参照する。
    @StateObject private var historyStore = GuideHistoryStore()

    /// 初期表示は「場面選択（tag 1）」。
    @State private var selectedTab = 1

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {

            // ── タブ0：計測 ──────────────────────────────────────
            // 既存HomeViewをそのまま使用。
            // StarfieldGraphicView・HRV・Watch心拍・Mock/実測モードを維持する。
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "bolt.shield.fill")
                    Text("計測")
                }
                .tag(0)

            // ── タブ1：場面選択 ──────────────────────────────────
            // 既存GuideViewをそのまま使用。
            // 呼吸ガイドフロー・GuideFlowView・GuideSessionViewを維持する。
            GuideView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "cpu")
                    Text("場面選択")
                }
                .tag(1)

            // ── タブ2：履歴 ──────────────────────────────────────
            // 既存HistoryViewをそのまま使用。
            // GuideHistoryStore・GuideSessionRecordを維持する。
            HistoryView()
                .tabItem {
                    Image(systemName: "terminal.fill")
                    Text("履歴")
                }
                .tag(2)
        }
        // 全タブへ共有（各ViewはEnvironmentObjectで受け取る）
        .environmentObject(viewModel)
        .environmentObject(historyStore)
        .tint(MindWaveTheme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: selectedTab) { _, newValue in
            // タブ遷移の構造化ログ
            switch newValue {
            case 0:  print("[Navigation] main tab changed: measurement")
            case 1:  print("[Navigation] main tab changed: sceneSelection")
            case 2:  print("[Navigation] main tab changed: history")
            default: print("[Navigation] main tab changed: unknown(\(newValue))")
            }
        }
        .onAppear {
            // タブバーの外観設定（MindWaveテーマに準拠）
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 0.95)
            UITabBar.appearance().standardAppearance   = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

#Preview {
    MainTabView()
}
