//
//  MindWaveGraphicWatchApp.swift
//  MindWaveGraphicWatch Watch App
//

import SwiftUI

@main
struct MindWaveGraphicWatch_Watch_AppApp: App {

    /// WorkoutManager をシングルソースとして管理し、
    /// ContentView に environmentObject として注入する。
    @StateObject private var workoutManager = WorkoutManager()

    init() {
        // アプリ起動時にWatchConnectivity（WCSession）をアクティベートする
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
                .onAppear {
                    // WCSession はアプリ表示後にセットアップする
                    workoutManager.setupWCSession()
                }
        }
    }
}
