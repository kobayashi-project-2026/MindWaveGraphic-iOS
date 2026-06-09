//
//  WatchConnectivityManager.swift
//  MindWaveGraphic
//
//  Apple WatchからWatchConnectivityで受信した心拍数をViewModelに橋渡しする。
//  シングルトンとして使い、App起動時にactivateする。
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
    /// 受信したメッセージ総数
    @Published var watchMessageCount: Int             = 0
    /// WCSession接続状態ラベル
    @Published var watchConnectionStatusLabel: String = "未接続"
    /// 最後に受信したWatch心拍のサマリー
    @Published var lastWatchMessage: String           = "まだ受信していません"

    // MARK: - コールバック（ViewModelが受信して心拍を即時反映する）

    /// Watch心拍受信時に呼ばれる。引数: (heartRate bpm, sampleDate)
    /// ViewController/ViewModelがこのクロージャを設定する。
    var onHeartRateReceived: ((Double, Date) -> Void)?

    // MARK: - 初期化

    private override init() {
        super.init()
    }

    // MARK: - セットアップ（App起動時に呼ぶ）

    /// WCSessionをアクティベートする。
    /// このデバイスがWatchConnectivityに対応している場合のみ実行する。
    func setup() {
        guard WCSession.isSupported() else {
            print("[WC iPhone] WatchConnectivity非対応デバイス")
            watchConnectionStatusLabel = "WatchConnectivity非対応"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        print("[WC iPhone] WCSession activate 開始")
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    // アクティベーション完了
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
            print("[WC iPhone] アクティベーションエラー: \(error.localizedDescription)")
        } else {
            print("[WC iPhone] アクティベーション完了: \(label)")
        }
        Task { @MainActor [self] in
            watchConnectionStatusLabel = label
        }
    }

    // iOSのみ必須: セッションが非アクティブになった
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WC iPhone] セッション非アクティブ")
        Task { @MainActor [self] in
            watchConnectionStatusLabel = "非アクティブ"
        }
    }

    // iOSのみ必須: セッションが非アクティブ化した（Watch切替後などに再アクティベートが必要）
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[WC iPhone] セッション非アクティブ化 → 再アクティベート")
        WCSession.default.activate()
        Task { @MainActor [self] in
            watchConnectionStatusLabel = "再アクティブ化中"
        }
    }

    // リアルタイムメッセージ受信（Watch側が sendMessage で送った場合）
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        handleIncomingMessage(message)
    }

    // リアルタイムメッセージ受信（reply必須バージョン）
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleIncomingMessage(message)
        replyHandler(["status": "ok"])
    }

    // バックグラウンド転送受信（Watch側が transferUserInfo で送った場合）
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        handleIncomingMessage(userInfo)
    }

    // MARK: - 共通メッセージ処理

    /// Watch から届いたメッセージを解析し、心拍数をコールバック経由でViewModelへ渡す。
    private nonisolated func handleIncomingMessage(_ message: [String: Any]) {
        // type: "heartRate" のメッセージのみ処理する
        guard let type = message["type"] as? String, type == "heartRate",
              let hr = message["heartRate"] as? Double,
              let timestamp = message["timestamp"] as? TimeInterval else {
            print("[WC iPhone] 未知のメッセージ形式: \(message.keys.joined(separator: ", "))")
            return
        }

        let sampleDate = Date(timeIntervalSince1970: timestamp)
        let summary    = String(format: "Watch → %.0f bpm", hr)
        print("[WC iPhone] 心拍受信: \(summary) (at \(formatTime(sampleDate)))")

        // MainActor でUIプロパティを更新し、ViewModelのコールバックを呼ぶ
        Task { @MainActor [self] in
            latestWatchHeartRate     = hr
            latestWatchHeartRateDate = sampleDate
            watchMessageCount       += 1
            lastWatchMessage         = summary
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
