//
//  WatchConnectivityManager.swift
//  MindWaveGraphic
//
//  Apple WatchからWatchConnectivityで受信した心拍数をViewModelに橋渡しする。
//  シングルトンとして使い、App起動時にactivateする。
//
//  受信チャネル:
//    - didReceiveMessage          → Watch側 sendMessage（リアルタイム）
//    - didReceiveUserInfo         → Watch側 transferUserInfo（キュー転送）
//    - didReceiveApplicationContext → Watch側 updateApplicationContext（最確実）
//

import Foundation
import Combine
import WatchConnectivity

// ─────────────────────────────────────────────────────────
// WatchConnectivityManager
// WCSessionのDelegate。Watch → iPhone の心拍数メッセージを受信し、
// onHeartRateReceived コールバック経由でViewModelへ通知する。
// ─────────────────────────────────────────────────────────
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    // MARK: - シングルトン

    static let shared = WatchConnectivityManager()

    // MARK: - Published プロパティ（UIに表示する状態）

    /// Watchから受信した最新心拍数（nil = 未受信）
    @Published var latestWatchHeartRate: Double?      = nil
    /// 最新心拍サンプルのWatch側記録時刻
    @Published var latestWatchHeartRateDate: Date?    = nil
    /// 受信したメッセージ総数（全チャネル合計）
    @Published var watchMessageCount: Int             = 0
    /// WCSession接続状態ラベル
    @Published var watchConnectionStatusLabel: String = "未接続"
    /// 最後に受信したWatch心拍のサマリー
    @Published var lastWatchMessage: String           = "まだ受信していません"
    /// 最後に受信したペイロードの診断テキスト（デバッグ表示用）
    @Published var lastPayloadDebug: String           = "---"
    /// 最後に受信したチャネル名
    @Published var lastReceiveChannel: String         = "---"

    // MARK: - コールバック（ViewModelが受信して心拍を即時反映する）

    /// Watch心拍受信時に呼ばれる。引数: (heartRate bpm, sampleDate)
    var onHeartRateReceived: ((Double, Date) -> Void)?

    // MARK: - 初期化

    private override init() {
        super.init()
    }

    // MARK: - セットアップ（App起動時に呼ぶ）

    /// WCSessionをアクティベートする。
    func setup() {
        guard WCSession.isSupported() else {
            print("[WatchConnectivity iPhone] WatchConnectivity非対応デバイス")
            watchConnectionStatusLabel = "WatchConnectivity非対応"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        print("[WatchConnectivity iPhone] WCSession activate 開始")
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    // ── アクティベーション完了 ─────────────────────────────────────────
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let label: String
        switch activationState {
        case .activated:    label = "接続済み"
        case .inactive:     label = "非アクティブ"
        case .notActivated: label = "未アクティブ"
        @unknown default:   label = "不明"
        }
        if let error {
            print("[WatchConnectivity iPhone] アクティベーションエラー: \(error.localizedDescription)")
        } else {
            print("[WatchConnectivity iPhone] アクティベーション完了: \(label) | isPaired=\(session.isPaired) | isWatchAppInstalled=\(session.isWatchAppInstalled)")
        }
        Task { @MainActor [self] in
            watchConnectionStatusLabel = label
        }
    }

    // ── iOSのみ必須: セッション非アクティブ ────────────────────────────
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WatchConnectivity iPhone] セッション非アクティブ")
        Task { @MainActor [self] in
            watchConnectionStatusLabel = "非アクティブ"
        }
    }

    // ── iOSのみ必須: セッション非アクティブ化（Watch切替後などに再activate）
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchConnectivity iPhone] セッション非アクティブ化 → 再activate")
        WCSession.default.activate()
        Task { @MainActor [self] in
            watchConnectionStatusLabel = "再アクティブ化中"
        }
    }

    // ── リアルタイムメッセージ受信（Watch側 sendMessage, replyHandler: nil）
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        print("[WatchConnectivity iPhone] didReceiveMessage（replyHandlerなし）")
        handleIncomingMessage(message, channel: "sendMessage")
    }

    // ── リアルタイムメッセージ受信（Watch側 sendMessage, replyHandlerあり）
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        print("[WatchConnectivity iPhone] didReceiveMessage（replyHandlerあり）")
        handleIncomingMessage(message, channel: "sendMessage+reply")
        replyHandler(["status": "ok", "received": true])
    }

    // ── バックグラウンド転送受信（Watch側 transferUserInfo）
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        print("[WatchConnectivity iPhone] didReceiveUserInfo")
        handleIncomingMessage(userInfo, channel: "transferUserInfo")
    }

    // ── アプリコンテキスト受信（Watch側 updateApplicationContext）
    // これが最も確実なチャネル。Watch側が updateApplicationContext を呼ぶと
    // iPhone側のこのデリゲートが呼ばれる。
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        print("[WatchConnectivity iPhone] didReceiveApplicationContext")
        handleIncomingMessage(applicationContext, channel: "appContext")
    }

    // MARK: - 共通メッセージ処理

    /// Watch から届いたメッセージを解析し、心拍数をコールバック経由でViewModelへ渡す。
    private nonisolated func handleIncomingMessage(
        _ message: [String: Any],
        channel: String
    ) {
        // type: "heartRate" のメッセージのみ処理する
        guard let type      = message["type"] as? String, type == "heartRate",
              let hr        = message["heartRate"] as? Double,
              let timestamp = message["timestamp"] as? TimeInterval else {
            print("[WatchConnectivity iPhone] 未知フォーマット (\(channel)): keys=\(message.keys.joined(separator: ","))")
            return
        }

        let sampleDate = Date(timeIntervalSince1970: timestamp)
        let summary    = String(format: "%.0f bpm", hr)
        let debugText  = String(format: "%.0f bpm | %@ | %@", hr, channel, formatTime(sampleDate))

        // このログが必ず出ることを確認する
        print("[WatchConnectivity] received heartRate: \(summary) via \(channel) at \(formatTime(sampleDate))")

        // MainActor でUIプロパティを更新し、ViewModelのコールバックを呼ぶ
        Task { @MainActor [self] in
            latestWatchHeartRate     = hr
            latestWatchHeartRateDate = sampleDate
            watchMessageCount       += 1
            lastWatchMessage         = summary
            lastPayloadDebug         = debugText
            lastReceiveChannel       = channel
            onHeartRateReceived?(hr, sampleDate)
        }
    }

    // ログ用時刻フォーマット
    private nonisolated func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
