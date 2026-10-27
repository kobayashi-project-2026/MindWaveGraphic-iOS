//
//  MindWaveDebugLogger.swift
//  MindWaveGraphic
//

// DEBUGビルド限定の構造化ログ出力ユーティリティ。
// Releaseビルドでは log() の呼び出しそのものがコンパイル後に残らない (#if DEBUG)。
// ファイル保存・ネットワーク送信・OSLog移行は行わない。

enum MindWaveLogCategory: String {
    case lifecycle = "LIFECYCLE"
    case pipeline  = "PIPELINE"
    case source    = "SOURCE"
    case watch     = "WATCH"
    case healthKit = "HEALTHKIT"
    case mock      = "MOCK"
    case analysis  = "ANALYSIS"
    case graphic   = "GRAPHIC"
    case error     = "ERROR"
    case flow      = "FLOW"      // ガイドフロー遷移ログ
    case navigation = "NAV"      // 画面遷移（AppNavigationManager）ログ
    case contract  = "CONTRACT"  // JSON契約の encode/decode ログ
    case baseline  = "BASELINE"  // 個人ベースライン更新ログ
    case insight   = "INSIGHT"   // AIインサイト（ローカル/リモート）ログ
}

enum MindWaveDebugLogger {
    nonisolated static func log(
        _ category: MindWaveLogCategory,
        _ message: @autoclosure () -> String
    ) {
#if DEBUG
        print("[MindWave][\(category.rawValue)] \(message())")
#endif
    }
}
