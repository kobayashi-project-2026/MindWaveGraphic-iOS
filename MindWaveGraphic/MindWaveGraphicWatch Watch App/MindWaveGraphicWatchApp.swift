//
//  MindWaveGraphicWatchApp.swift
//  MindWaveGraphicWatch Watch App
//
//  WorkoutManager は init() 内で WCSession を即座にアクティベートする。
//  onAppear 待ちを排除して、起動直後から WatchConnectivity が動作するようにしている。
//

import SwiftUI

@main
struct MindWaveGraphicWatch_Watch_AppApp: App {

    /// WorkoutManager をシングルソースとして管理し、ContentView に注入する。
    /// @StateObject で生成される時点（init()）で WCSession がアクティベートされる。
    @StateObject private var workoutManager = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
        }
    }
}
