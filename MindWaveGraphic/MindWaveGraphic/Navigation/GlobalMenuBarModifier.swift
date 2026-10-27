import SwiftUI

struct GlobalMenuBarModifier: ViewModifier {
    @EnvironmentObject var navManager: AppNavigationManager

    func body(content: Content) -> some View {
        ZStack(alignment: .topTrailing) {
            // メインとなる画面コンテンツ
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // タイトル画面以外で右上に共通メニューバーを表示
            if navManager.currentScreen != .title {
                Menu {
                    Section("主要画面") {
                        Button {
                            navManager.navigate(to: .dialogue)
                        } label: {
                            Label("対話画面", systemImage: AppScreen.dialogue.iconName)
                        }

                        Button {
                            navManager.navigate(to: .tensionGraphic)
                        } label: {
                            Label("緊張グラフィック", systemImage: AppScreen.tensionGraphic.iconName)
                        }
                    }

                    Section("記録・環境設定") {
                        Button {
                            navManager.navigate(to: .pastLogs)
                        } label: {
                            Label("過去ログ確認", systemImage: AppScreen.pastLogs.iconName)
                        }

                        Button {
                            navManager.navigate(to: .settings)
                        } label: {
                            Label("設定", systemImage: AppScreen.settings.iconName)
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
                .padding(.top, 34) // Safe Area (Dynamic Island) 考慮
            }
        }
    }
}

extension View {
    /// 全画面の右上に共通メニューバーを付与するモディファイア
    func withGlobalMenuBar() -> some View {
        self.modifier(GlobalMenuBarModifier())
    }
}
