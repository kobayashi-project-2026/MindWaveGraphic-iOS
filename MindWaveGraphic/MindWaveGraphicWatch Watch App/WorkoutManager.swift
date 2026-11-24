//
//  WorkoutManager.swift
//  MindWaveGraphicWatch Watch App
//
// Watch側の心拍リアルタイム取得と iPhone 送信を担う ViewModel。
//
// HKWorkoutSession を使う理由:
//   watchOS でバックグラウンド・常時表示中も心拍を取得し続けるには
//   HKWorkoutSession が必須。アクティブなセッションがないと心拍更新が止まる。
//
// データフロー:
//   HKLiveWorkoutBuilder → workoutBuilder(_:didCollectDataOf:) で心拍受信
//   → sendHeartRateToiPhone() で WatchConnectivity 3チャネル送信
//
// 送信戦略: sendHeartRateToiPhone の3チャネル（詳細はその関数コメント参照）。
//
// 計測停止:
//   stopWorkout() が HKWorkoutSession を終了し、HealthKit へデータを保存する。
//
// UI:
//   Published プロパティを ContentView が監視して表示する。
//   ContentView は WorkoutManager の内部実装を知らない。
//

import Foundation
import Combine
import HealthKit
import WatchConnectivity

// ─────────────────────────────────────────────────────────
// WorkoutManager
// ─────────────────────────────────────────────────────────
@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    // MARK: - 状態

    /// ワークアウトセッション実行中か
    @Published var isRunning: Bool           = false
    /// 現在の心拍数（bpm）
    @Published var currentHeartRate: Double  = 0
    /// iPhone送信回数
    @Published var sendCount: Int            = 0
    /// 状態メッセージ（UIに表示する）
    @Published var statusMessage: String     = "起動中..."
    /// WCSession接続状態
    @Published var wcStatus: String         = "初期化中"
    /// HealthKit権限状態
    @Published var authStatus: String       = "未許可"
    /// 最後に送信した心拍のサマリー（診断用）
    @Published var lastSentHR: String       = "--"
    /// 最後の送信エラー（診断用）
    @Published var lastSendError: String    = ""
    /// iPhoneへの到達可能状態
    @Published var isWCReachable: Bool      = false

    // MARK: - Private

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // MARK: - 初期化

    /// アプリ起動時（@StateObject 生成時）に呼ばれる。
    /// WCSession を onAppear 待ちではなく init() で即座にアクティベートすることで
    /// 計測開始前から接続を確立できる。
    override init() {
        super.init()
        activateWCSession()
        statusMessage = "停止中"
    }

    // MARK: - WatchConnectivity アクティベート

    /// WCSession をアクティベートする。init() から呼ばれる。
    /// activate() は冪等なので onAppear などから重複して呼んでも安全。
    private func activateWCSession() {
        guard WCSession.isSupported() else {
            wcStatus = "WC非対応"
            WatchDebugLogger.log("ERROR", "WatchConnectivity not supported")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        WatchDebugLogger.log("WC", "session activation requested")
    }

    /// 外部から呼ぶ用のラッパー（onAppear などから呼んでも二重activateにはならない）
    func setupWCSession() {
        WatchDebugLogger.log("WC", "setupWCSession called — activation state=\(WCSession.default.activationState.rawValue)")
    }

    // MARK: - HealthKit 権限リクエスト

    /// HealthKit権限をリクエストする。HKWorkoutSession開始前に必ず呼ぶ。
    /// ContentView の .task 修飾子から呼ばれる。
    func requestAuthorization() async {
        // toShare: ワークアウト記録を保存するためにworkoutTypeが必要
        // read: 心拍数を読み取るためにheartRateが必要
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead:  Set<HKObjectType> = [HKQuantityType(.heartRate)]

        do {
            try await store.requestAuthorization(toShare: typesToShare, read: typesToRead)
            authStatus = "許可済み"
            WatchDebugLogger.log("HK", "authorization granted")
        } catch {
            authStatus = "権限エラー"
            statusMessage = "HealthKit権限エラー"
            WatchDebugLogger.log("ERROR", "HealthKit authorization error: \(error.localizedDescription)")
        }
    }

    // MARK: - ワークアウト開始

    /// HKWorkoutSession を開始し、HKLiveWorkoutBuilder で心拍の収集を始める。
    /// startActivity → beginCollection の順に呼ぶ必要がある。
    /// 成功後に isRunning = true となり、ContentView が計測中UIを表示する。
    func startWorkout() async {
        guard !isRunning else { return }
        WatchDebugLogger.log("WORKOUT", "start requested")

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown

        do {
            let newSession = try HKWorkoutSession(healthStore: store, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()

            session = newSession
            builder = newBuilder

            newSession.delegate = self
            newBuilder.delegate = self

            // HKLiveWorkoutDataSource を設定すると、watchOS が自動で
            // activityType に応じたデータ（心拍数など）を収集してくれる。
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: config
            )

            newSession.startActivity(with: Date())

            // データ収集開始（コールバックを Continuation でラップ）
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                newBuilder.beginCollection(withStart: Date()) { _, error in
                    if let error { cont.resume(throwing: error) }
                    else         { cont.resume() }
                }
            }

            WatchDebugLogger.log("WORKOUT", "session started reachable=\(WCSession.default.isReachable)")
            WatchDebugLogger.log("WORKOUT", "builder collection started")

            isRunning     = true
            statusMessage = "計測中 ❤️"

        } catch {
            statusMessage = "開始エラー: \(error.localizedDescription)"
            WatchDebugLogger.log("ERROR", "workout start error: \(error.localizedDescription)")
        }
    }

    // MARK: - ワークアウト停止

    /// セッションを終了し、ワークアウトデータをHealthKitに保存する。
    /// isRunning と builder が存在する場合のみ実行する。
    func stopWorkout() {
        guard isRunning, let session, let builder else { return }
        WatchDebugLogger.log("WORKOUT", "stop requested")

        session.end()
        builder.endCollection(withEnd: Date()) { [weak self] _, _ in
            builder.finishWorkout { _, _ in
                Task { @MainActor [weak self] in
                    self?.isRunning     = false
                    self?.statusMessage = "停止しました"
                    self?.session       = nil
                    self?.builder       = nil
                    WatchDebugLogger.log("WORKOUT", "session ended")
                }
            }
        }
    }

    // MARK: - iPhone へ心拍数送信（3チャネル戦略）

    /// 心拍数を WatchConnectivity 経由でiPhoneに送信する。
    ///
    /// チャネル1: sendMessage（replyHandlerあり）
    ///   isReachable の場合のみ実行。reply が届けば送信確認。失敗時は transferUserInfo へフォールバック。
    /// チャネル2: updateApplicationContext
    ///   常に実行。最新値を1件保持。エラー時のみログを出す。
    /// チャネル3: transferUserInfo
    ///   sendMessage 失敗時 or isReachable=false 時のキュー転送フォールバック。
    private func sendHeartRateToiPhone(_ heartRate: Double) {
        let now = Date().timeIntervalSince1970
        // iPhone 側 Contracts/WatchPayloadContract.swift（schema v1）と対応。
        // 既存3キーは変更しない。schemaVersion は追加キーのため旧iPhoneアプリでも無視されるだけで互換。
        let payload: [String: Any] = [
            "type":          "heartRate",
            "heartRate":     heartRate,
            "timestamp":     now,
            "schemaVersion": 1
        ]

        isWCReachable = WCSession.default.isReachable
        WatchDebugLogger.log("WC", "sendMessage attempt bpm=\(Int(heartRate)) reachable=\(isWCReachable)")

        // ── チャネル1: sendMessage（replyHandlerあり = より確実な配信）──────
        // replyHandlerをnilにすると watchOS で配信が不安定になるため非nilを使う。
        if isWCReachable {
            WCSession.default.sendMessage(payload, replyHandler: { reply in
                WatchDebugLogger.log("WC", "sendMessage reply received")
                Task { @MainActor [weak self] in
                    self?.lastSendError = ""
                }
            }, errorHandler: { [weak self] error in
                // sendMessage 失敗 → transferUserInfo にフォールバック
                WatchDebugLogger.log("WC", "sendMessage error → transferUserInfo fallback: \(error.localizedDescription)")
                WCSession.default.transferUserInfo(payload)
                Task { @MainActor [weak self] in
                    self?.lastSendError = "SM: \(error.localizedDescription)"
                }
            })
        } else {
            // iPhoneに到達不可 → transferUserInfo でキュー転送
            WatchDebugLogger.log("WC", "not reachable → transferUserInfo fallback")
            WCSession.default.transferUserInfo(payload)
        }

        // ── チャネル2: updateApplicationContext（常に実行・エラー時のみログ）──
        // updateApplicationContext は最新値のみ保持するが、
        // WCSession が established であれば iPhoneが次に起動したときに確実に届く。
        do {
            try WCSession.default.updateApplicationContext(payload)
        } catch {
            WatchDebugLogger.log("ERROR", "applicationContext error: \(error.localizedDescription)")
        }

        // 送信カウンタ・表示を更新する
        sendCount    += 1
        lastSentHR    = String(format: "%.0f bpm (送信#\(sendCount))", heartRate)
        statusMessage = String(format: "送信中: %.0f bpm（%d回）", heartRate, sendCount)
        WatchDebugLogger.log("WC", "sent count=\(sendCount)")
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {

    /// ワークアウトセッションの状態変化を受け取る。
    /// 終了・停止状態になったら isRunning を false にする。
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let label: String
        switch toState {
        case .running:    label = "計測中 ❤️"
        case .ended:      label = "終了"
        case .paused:     label = "一時停止"
        case .stopped:    label = "停止"
        case .notStarted: label = "未開始"
        case .prepared:   label = "準備中"
        @unknown default: label = "不明"
        }
        WatchDebugLogger.log("WORKOUT", "state changed \(fromState.rawValue) → \(toState.rawValue) (\(label))")
        Task { @MainActor [self] in
            if toState == .ended || toState == .stopped {
                isRunning     = false
                statusMessage = label
            }
        }
    }

    /// ワークアウトセッションがエラーで終了した場合に呼ばれる。
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        WatchDebugLogger.log("ERROR", "session error: \(error.localizedDescription)")
        Task { @MainActor [self] in
            isRunning     = false
            statusMessage = "エラー: \(error.localizedDescription)"
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    /// 新しいデータが届いたときに呼ばれる（心拍数更新の主役）。
    /// HKLiveWorkoutDataSource が心拍サンプルを収集するたびに発火する。
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // 心拍数が含まれていなければ処理しない
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }

        // 最新の心拍統計を取得する
        guard let stats = workoutBuilder.statistics(for: HKQuantityType(.heartRate)),
              let hr = stats.mostRecentQuantity()?.doubleValue(
                for: HKUnit.count().unitDivided(by: .minute())
              ) else {
            WatchDebugLogger.log("ERROR", "failed to get HR statistics from builder")
            return
        }

        WatchDebugLogger.log("HR", "sample bpm=\(Int(hr))")

        // MainActor でUI更新 + iPhoneへ送信
        Task { @MainActor [self] in
            currentHeartRate = hr
            sendHeartRateToiPhone(hr)
        }
    }
}

// MARK: - WCSessionDelegate

extension WorkoutManager: WCSessionDelegate {

    /// WCSession の activation 完了を受け取る。
    /// Watch では iOS のみ必須の sessionDidBecomeInactive / sessionDidDeactivate は不要。
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
            WatchDebugLogger.log("ERROR", "WC activation error: \(error.localizedDescription)")
        } else {
            WatchDebugLogger.log("WC", "session activated state=\(label)")
        }
        Task { @MainActor [self] in
            wcStatus = label
        }
    }
}
