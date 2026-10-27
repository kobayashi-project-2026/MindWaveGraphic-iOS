// 未完成の新ナビゲーションを一時的に無効化

import SwiftUI

/// 認証フローと共通ナビゲーションを接続するルートコンテナ
struct AppRootContainerView: View {

    // チームが追加した画面遷移管理を保持する
    @StateObject private var navManager = AppNavigationManager()

    var body: some View {
        // 既存のログイン・状況選択・メインアプリの流れを維持する
        AppRootView()
            .environmentObject(navManager)
    }
}
