//
//  MindWaveGraphicApp.swift
//  MindWaveGraphic
//

import SwiftUI

@main
struct MindWaveGraphicApp: App {

    init() {
        // アプリ起動時にWatchConnectivityをアクティベートする。
        // これによりApple Watchアプリからの心拍数メッセージを受信できるようになる。
        WatchConnectivityManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            // フェーズ2：認証フローを挿入。
            // mainApp状態になると AppRootView が既存の ContentView を表示する。
            // ContentView 本体は一切変更していない。
            AppRootView()
        }
    }
}
