import SwiftUI

struct GlobalMenuBarModifier: ViewModifier {
    @EnvironmentObject var navManager: AppNavigationManager
    // 「確認」「フィードバック」は保存済みのガイド記録が必要なため、履歴の有無で有効/無効を切り替える
    @EnvironmentObject var historyStore: GuideHistoryStore

    func body(content: Content) -> some View {
        ZStack(alignment: .topTrailing) {
            // メインとなる画面コンテンツ
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // タイトル画面以外で右上に共通メニューバーを表示
            if navManager.currentScreen != .title {
                Menu {
                    Section("主要画面") {
                        menuButton(.dialogue, label: "対話（状況確認）")
                        menuButton(.tensionGraphic, label: "緊張グラフィック")
                        menuButton(.improvement, label: "改善（ワーク）")
                        menuButton(.aiChat, label: "AI相談")
                    }

                    Section("直近のセッション") {
                        menuButton(.confirmation, label: "結果の確認")
                        menuButton(.feedback, label: "フィードバック")
                    }

                    Section("記録・環境設定") {
                        menuButton(.pastLogs, label: "過去ログ確認")
                        menuButton(.settings, label: "設定")
                    }

                    Section {
                        Button(role: .destructive) {
                            navManager.navigate(to: .title)
                        } label: {
                            Label("タイトルへ戻る", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 2)
                        .padding(.top, 12)
                        .padding(.trailing, 18)
                }
                .accessibilityLabel("共通メニュー")
                .accessibilityIdentifier("global_menu_button")
                .padding(.top, 34) // Safe Area (Dynamic Island) 考慮
            }
        }
    }

    /// メニュー項目。現在表示中の画面にはチェックを付け、記録が必要な画面は記録がなければ無効化する。
    @ViewBuilder
    private func menuButton(_ screen: AppScreen, label: String) -> some View {
        let isCurrent = navManager.currentScreen == screen
        Button {
            navManager.navigate(to: screen)
        } label: {
            Label(label, systemImage: isCurrent ? "checkmark" : screen.iconName)
        }
        .disabled(screen.requiresSessionRecord && historyStore.records.isEmpty)
    }
}

extension View {
    /// 全画面の右上に共通メニューバーを付与するモディファイア
    func withGlobalMenuBar() -> some View {
        self.modifier(GlobalMenuBarModifier())
    }
}
