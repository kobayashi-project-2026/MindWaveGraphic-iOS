//
//  WatchDebugLogger.swift
//  MindWaveGraphicWatch Watch App
//

// Watch target 専用のDEBUGログユーティリティ。
// iPhone側の MindWaveDebugLogger と同等の役割だが、Watch target にのみ含まれる。
// Releaseビルドでは log() 内の print() がコンパイルされない (#if DEBUG)。

enum WatchDebugLogger {
    nonisolated static func log(_ category: String, _ message: @autoclosure () -> String) {
#if DEBUG
        print("[MindWaveWatch][\(category)] \(message())")
#endif
    }
}
