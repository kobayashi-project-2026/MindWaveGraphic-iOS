//
//  WatchConnectivityManager.swift
//  MindWaveGraphic
//
// iPhone側WatchConnectivityの窓口。
// Watchから3チャネル（sendMessage / transferUserInfo / updateApplicationContext）で
// 心拍データを受信し、共通処理 handleIncomingMessage へ集約する。
// 受信した心拍を検証後、MainActor上で onHeartRateReceived コールバックを呼び
// MindWaveViewModel.applyWatchHeartRate へ渡す。
// グラフィック処理・HealthKit処理は行わない。
//

import Foundation
import Combine
import WatchConnectivity

// ─────────────────────────────────────────────────────────
// WatchConnectivityManager: シングルトン。setup() でセッション確立。
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

    // MARK: - WCSession 診断プロパティ（DebugDiagnosticsView 用）

    /// WCSession の isReachable（WatchConnectivity 非対応デバイスでは常に false）
    var isWatchReachable: Bool { WCSession.isSupported() && WCSession.default.isReachable }
    /// WCSession の isPaired（activation 前は false）
    var isWatchPaired: Bool { WCSession.isSupported() && WCSession.default.isPaired }
    /// WCSession の isWatchAppInstalled（activation 前は false）
    var isWatchAppInstalled: Bool { WCSession.isSupported() && WCSession.default.isWatchAppInstalled }
    /// WCSession の activationState をラベル文字列で返す
    var wcActivationStateLabel: String {
        guard WCSession.isSupported() else { return "非対応" }
        switch WCSession.default.activationState {
        case .activated:    return "activated"
        case .inactive:     return "inactive"
        case .notActivated: return "notActivated"
        @unknown default:   return "unknown"
        }
    }

    // MARK: - コールバック

    /// Watch心拍受信時に呼ばれる。MindWaveViewModel.subscribeToWatchHeartRate() で登録される。
    /// 引数: (heartRate bpm, sampleDate)
    var onHeartRateReceived: ((Double, Date) -> Void)?

    // MARK: - 初期化

    /// シングルトンのため外部からは呼べない。shared 経由で利用する。
    private override init() {
        super.init()
    }

    // MARK: - セッション開始（App起動時に1回呼ぶ）

    /// WCSession を activate する。WCSession.isSupported() が false のデバイスでは何もしない。
    /// MindWaveGraphicApp の init またはonAppear から1回だけ呼ぶこと。
    func setup() {
        guard WCSession.isSupported() else {
            MindWaveDebugLogger.log(.error, "WatchConnectivity not supported on this device")
            watchConnectionStatusLabel = "WatchConnectivity非対応"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        MindWaveDebugLogger.log(.watch, "WCSession activation requested")
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    // ── アクティベーション完了 ─────────────────────────────────────────
    /// WCSession の activation が完了したときに呼ばれる。
    /// 成功時は isPaired / isWatchAppInstalled / isReachable をログに残す。
    /// 失敗時は error カテゴリでログを出す。
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
            MindWaveDebugLogger.log(.error, "WCSession activation error: \(error.localizedDescription)")
        } else {
            MindWaveDebugLogger.log(.watch, "activation completed state=\(label) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
        }
        Task { @MainActor [self] in
            watchConnectionStatusLabel = label
        }
    }

    // ── リアルタイム到達可能性の変化 ──────────────────────────────────
    /// isReachable が変化したときだけ呼ばれる。値が変わったときのみログを出す。
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        MindWaveDebugLogger.log(.watch, "reachability changed reachable=\(session.isReachable)")
    }

    // ── iOSのみ必須: セッション非アクティブ ────────────────────────────
    /// Watch切替直前などに呼ばれる。reactivate前の中間状態。
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        MindWaveDebugLogger.log(.watch, "session became inactive")
        Task { @MainActor [self] in
            watchConnectionStatusLabel = "非アクティブ"
        }
    }

    // ── iOSのみ必須: セッション非アクティブ化完了 ──────────────────────
    /// sessionDidBecomeInactive の後に呼ばれる。新しいWatch用に再activateする。
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        MindWaveDebugLogger.log(.watch, "session deactivated → re-activating")
        WCSession.default.activate()
        Task { @MainActor [self] in
            watchConnectionStatusLabel = "再アクティブ化中"
        }
    }

    // ── リアルタイムメッセージ受信（Watch側 sendMessage, replyHandler: nil）
    /// Watch が sendMessage(replyHandler: nil) で送った場合に呼ばれる。
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        MindWaveDebugLogger.log(.watch, "received channel=sendMessage keys=\(message.keys.sorted().joined(separator: ","))")
        handleIncomingMessage(message, channel: "sendMessage")
    }

    // ── リアルタイムメッセージ受信（Watch側 sendMessage, replyHandlerあり）
    /// Watch が sendMessage(replyHandler:) で送った場合に呼ばれる。
    /// 受信確認として ["status": "ok", "received": true] を即時返す。
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        MindWaveDebugLogger.log(.watch, "received channel=sendMessage+reply keys=\(message.keys.sorted().joined(separator: ","))")
        handleIncomingMessage(message, channel: "sendMessage+reply")
        replyHandler(["status": "ok", "received": true])
        MindWaveDebugLogger.log(.watch, "reply sent channel=sendMessage+reply status=ok")
    }

    // ── バックグラウンド転送受信（Watch側 transferUserInfo）
    /// Watch が transferUserInfo で送ったデータが届いたときに呼ばれる。
    /// iPhone がバックグラウンドでも配信される。
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        MindWaveDebugLogger.log(.watch, "received channel=userInfo keys=\(userInfo.keys.sorted().joined(separator: ","))")
        handleIncomingMessage(userInfo, channel: "userInfo")
    }

    // ── アプリコンテキスト受信（Watch側 updateApplicationContext）
    /// Watch が updateApplicationContext を呼ぶと iPhone 側でここが呼ばれる。
    /// 最新状態を1件だけ保持するチャネル。
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        MindWaveDebugLogger.log(.watch, "received channel=applicationContext keys=\(applicationContext.keys.sorted().joined(separator: ","))")
        handleIncomingMessage(applicationContext, channel: "applicationContext")
    }

    // MARK: - 共通メッセージ処理

    /// Watch から届いたメッセージを3段階で検証し、心拍数をコールバック経由でViewModelへ渡す。
    /// 検証失敗の種別（typeキーなし・heartRateキーなし・timestamp変換失敗）をログで区別する。
    /// 範囲外の値は既存の有効範囲を変更せずログ警告のみ出す。
    private nonisolated func handleIncomingMessage(
        _ message: [String: Any],
        channel: String
    ) {
        // type: "heartRate" を確認する
        guard let type = message["type"] as? String, type == "heartRate" else {
            let keys = message.keys.sorted().joined(separator: ",")
            MindWaveDebugLogger.log(.error, "decode failed channel=\(channel) reason=type missing or not heartRate keys=\(keys)")
            return
        }
        // heartRate キーと型を確認する
        guard let hr = message["heartRate"] as? Double else {
            MindWaveDebugLogger.log(.error, "decode failed channel=\(channel) reason=heartRate key missing or wrong type")
            return
        }
        // timestamp キーと型を確認する
        guard let timestamp = message["timestamp"] as? TimeInterval else {
            MindWaveDebugLogger.log(.error, "decode failed channel=\(channel) reason=timestamp key missing or wrong type")
            return
        }

        // 範囲ログ（既存の有効範囲は変更しない）
        if hr <= 0 {
            MindWaveDebugLogger.log(.error, "decode warning channel=\(channel) bpm=\(hr) value ≤0")
        } else if hr > 250 {
            MindWaveDebugLogger.log(.error, "decode warning channel=\(channel) bpm=\(hr) unrealistic value >250")
        }

        let sampleDate = Date(timeIntervalSince1970: timestamp)
        let summary    = String(format: "%.0f bpm", hr)
        let debugText  = String(format: "%.0f bpm | %@ | %@", hr, channel, formatTime(sampleDate))

        // MainActor でUIプロパティを更新し、ViewModelのコールバックを呼ぶ
        Task { @MainActor [self] in
            latestWatchHeartRate     = hr
            latestWatchHeartRateDate = sampleDate
            watchMessageCount       += 1
            lastWatchMessage         = summary
            lastPayloadDebug         = debugText
            lastReceiveChannel       = channel
            MindWaveDebugLogger.log(.watch, "decoded channel=\(channel) bpm=\(Int(hr)) count=\(watchMessageCount)")
            MindWaveDebugLogger.log(.watch, "[PhoneLink] payload received channel=\(channel) fields=type,heartRate,timestamp bpm=\(Int(hr))")
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
