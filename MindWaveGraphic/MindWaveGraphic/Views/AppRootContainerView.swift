import SwiftUI

struct AppRootContainerView: View {
    @StateObject private var navManager = AppNavigationManager()
    @EnvironmentObject var viewModel: MindWaveViewModel
    @StateObject private var historyStore = GuideHistoryStore() // 過去ログ管理ストア

    var body: some View {
        Group {
            switch navManager.currentScreen {
            case .title:
                TitleView()
            case .dialogue:
                DialogueView()
            case .tensionGraphic:
                LiveWaveView() // コックピット緊張グラフィック画面
            case .improvement:
                GuideView() // 改善（ワーク）画面[cite: 3]
            case .confirmation:
                ConfirmationView()
            case .feedback:
                FeedbackView()
            case .pastLogs:
                // 過去ログ確認画面[cite: 3, 4]
                NewRecordListView(records: .constant(historyStore.records))
            case .settings:
                // 設定画面[cite: 3]
                SettingsView()
                    .environmentObject(viewModel)
            }
        }
        .environmentObject(navManager)
        .environmentObject(historyStore)
        .withGlobalMenuBar() // 全画面の右上に共通メニューバーを配置
        .preferredColorScheme(.dark)
    }
}
