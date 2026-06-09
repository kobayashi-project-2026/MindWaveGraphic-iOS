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
            ContentView()
        }
    }
}
