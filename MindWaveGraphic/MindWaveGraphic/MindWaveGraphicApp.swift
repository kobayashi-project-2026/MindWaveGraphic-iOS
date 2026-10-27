
import SwiftUI

@main
struct MindWaveGraphicApp: App {

    init() {
        // Apple Watchとの通信を初期化する
        WatchConnectivityManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            // 既存の認証・画面遷移フローを起動する
            AppRootContainerView()
        }
    }
}

