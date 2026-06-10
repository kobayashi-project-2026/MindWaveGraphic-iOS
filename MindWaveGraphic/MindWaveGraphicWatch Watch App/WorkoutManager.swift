//
//  WorkoutManager.swift
//  MindWaveGraphicWatch Watch App
//
//  HKWorkoutSession + HKLiveWorkoutBuilder でWatch側から心拍数をリアルタイム取得し、
//  WatchConnectivity 経由でiPhoneに送信する。
//
//  送信戦略:
//    1. sendMessage（replyHandlerあり）→ iPhone起動中に低レイテンシ配信
//    2. updateApplicationContext     → 常に実行、最も確実なチャネル
//    3. transferUserInfo（fallback）  → sendMessage失敗時のキュー転送
//

import Foundation
import Combine
import HealthKit
import WatchConnectivity

// ─────────────────────────────────────────────────────────
// WorkoutManager
// Watch側の心拍ライブ取得の核。起動直後に WCSession もアクティベートする。
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

    // MARK: - 初期化（起動直後にWCSessionをアクティベートする）

    override init() {
        super.init()
        // WCSession は可能な限り早くアクティベートする。
        // onAppear 待ちではなく init() で呼ぶことで、計測開始前に接続が確立される。
        activateWCSession()
        statusMessage = "停止中"
    }

    // MARK: - WatchConnectivity アクティベート

    /// WCSessionをアクティベートする。
    /// init() から呼ばれる。setupWCSession() と同一処理。
    private func activateWCSession() {
        guard WCSession.isSupported() else {
            wcStatus = "WC非対応"
            print("[Watch WC] WatchConnectivity非対応デバイス")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        print("[Watch WC] WCSession activate 開始 (from init)")
    }

    /// 外部から呼ぶ用のラッパー（onAppear などから呼んでも二重activateにはならない）
    func setupWCSession() {
        print("[Watch WC] setupWCSession 呼び出し (WCSession状態: \(WCSession.default.activationState.rawValue))")
    }

    // MARK: - HealthKit 権限リクエスト

    /// HealthKit権限をリクエストする。HKWorkoutSession開始前に必ず呼ぶ。
    func requestAuthorization() async {
        // toShare: ワークアウト記録を保存するためにworkoutTypeが必要
        // read: 心拍数を読み取るためにheartRateが必要
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead:  Set<HKObjectType> = [HKQuantityType(.heartRate)]

        do {
            try await store.requestAuthorization(toShare: typesToShare, read: typesToRead)
            authStatus = "許可済み"
            print("[Watch HK] HealthKit権限取得完了")
        } catch {
            authStatus = "権限エラー"
            statusMessage = "HealthKit権限エラー"
            print("[Watch HK] 権限取得エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - ワークアウト開始

    /// HKWorkoutSessionを開始し、心拍数のリアルタイム取得を始める。
    func startWorkout() async {
        guard !isRunning else { return }

        let config = HKWorkoutConfiguration()
        // activityType = .other（汎用）でセッションを作成する
        config.activityType = .other
        config.locationType = .unknown

        do {
            let newSession = try HKWorkoutSession(healthStore: store, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()

            session = newSession
            builder = newBuilder

            // デリゲートを設定する
            newSession.delegate = self
            newBuilder.delegate = self

            // HKLiveWorkoutDataSource を設定すると、watchOS が自動で
            // activityType に応じたデータ（心拍数など）を収集してくれる。
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: config
            )

            // セッション開始
            newSession.startActivity(with: Date())

            // データ収集開始（コールバックを Continuation でラップ）
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                newBuilder.beginCollection(withStart: Date()) { _, error in
                    if let error { cont.resume(throwing: error) }
                    else         { cont.resume() }
                }
            }

            isRunning     = true
            statusMessage = "計測中 ❤️"
            print("[Watch HK] ワークアウトセッション開始")
            print("[Watch WC] 現在の isReachable: \(WCSession.default.isReachable)")

        } catch {
            statusMessage = "開始エラー: \(error.localizedDescription)"
            print("[Watch HK] セッション開始エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - ワークアウト停止

    /// セッションを終了し、ワークアウトデータをHealthKitに保存する。
    func stopWorkout() {
        guard isRunning, let session, let builder else { return }

        session.end()
        builder.endCollection(withEnd: Date()) { [weak self] _, _ in
            builder.finishWorkout { _, _ in
                Task { @MainActor [weak self] in
                    self?.isRunning     = false
                    self?.statusMessage = "停止しました"
                    self?.session       = nil
                    self?.builder       = nil
                    print("[Watch HK] ワークアウトセッション終了")
                }
            }
        }
    }

    // MARK: - iPhone へ心拍数送信（3チャネル戦略）

    /// 心拍数をWatchConnectivity経由でiPhoneに送信する。
    ///
    /// チャネル優先度:
    ///   1. sendMessage (replyHandler付き) → リアルタイム、iPhoneが起動中に確実
    ///   2. updateApplicationContext       → 常に実行、最も確実な補助チャネル
    ///   3. transferUserInfo               → sendMessage失敗時のフォールバック
    private func sendHeartRateToiPhone(_ heartRate: Double) {
        let now = Date().timeIntervalSince1970
        let payload: [String: Any] = [
            "type":      "heartRate",
            "heartRate": heartRate,
            "timestamp": now
        ]

        // isReachable を更新する
        isWCReachable = WCSession.default.isReachable

        print("[Watch WC] 送信試行: \(String(format: "%.0f", heartRate)) bpm | reachable=\(isWCReachable) | activationState=\(WCSession.default.activationState.rawValue)")

        // ── チャネル1: sendMessage（replyHandlerあり = より確実な配信）──────
        // replyHandlerをnilにすると watchOS で配信が不安定になるため非nilを使う。
        if isWCReachable {
            WCSession.default.sendMessage(payload, replyHandler: { reply in
                // iPhone側からの返信を受け取った = 送信成功
                print("[Watch WC] sendMessage 成功（reply: \(reply)）: \(String(format: "%.0f", heartRate)) bpm")
                Task { @MainActor [weak self] in
                    self?.lastSendError = ""
                }
            }, errorHandler: { [weak self] error in
                // sendMessage 失敗 → transferUserInfo にフォールバック
                print("[Watch WC] sendMessage 失敗 → transferUserInfo: \(error.localizedDescription)")
                WCSession.default.transferUserInfo(payload)
                Task { @MainActor [weak self] in
                    self?.lastSendError = "SM: \(error.localizedDescription)"
                }
            })
        } else {
            // iPhoneに到達不可 → transferUserInfo でキュー転送
            print("[Watch WC] iPhone到達不可 → transferUserInfo")
            WCSession.default.transferUserInfo(payload)
        }

        // ── チャネル2: updateApplicationContext（常に実行・最も確実）─────────
        // updateApplicationContext は最新値のみ保持するが、
        // WCSession が established であれば iPhoneが次に起動したときに確実に届く。
        do {
            try WCSession.default.updateApplicationContext(payload)
            print("[Watch WC] updateApplicationContext 成功: \(String(format: "%.0f", heartRate)) bpm")
        } catch {
            print("[Watch WC] updateApplicationContext 失敗: \(error.localizedDescription)")
        }

        // 送信カウンタ・表示を更新する
        sendCount    += 1
        lastSentHR    = String(format: "%.0f bpm (送信#\(sendCount))", heartRate)
        statusMessage = String(format: "送信中: %.0f bpm（%d回）", heartRate, sendCount)

        print("[Watch WC] sent heartRate: \(String(format: "%.0f", heartRate)) bpm (合計\(sendCount)回)")
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {

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
        print("[Watch HK] セッション状態変化: \(fromState.rawValue) → \(toState.rawValue) (\(label))")
        Task { @MainActor [self] in
            if toState == .ended || toState == .stopped {
                isRunning     = false
                statusMessage = label
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("[Watch HK] セッションエラー: \(error.localizedDescription)")
        Task { @MainActor [self] in
            isRunning     = false
            statusMessage = "エラー: \(error.localizedDescription)"
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    /// 新しいデータが届いたときに呼ばれる（心拍数更新の主役）
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
            print("[Watch HK] 心拍統計取得失敗")
            return
        }

        print("[Watch HK] 心拍取得: \(String(format: "%.0f", hr)) bpm → iPhoneへ送信")

        // MainActor でUI更新 + iPhoneへ送信
        Task { @MainActor [self] in
            currentHeartRate = hr
            sendHeartRateToiPhone(hr)
        }
    }
}

// MARK: - WCSessionDelegate

extension WorkoutManager: WCSessionDelegate {

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
            print("[Watch WC] アクティベーションエラー: \(error.localizedDescription)")
        } else {
            print("[Watch WC] アクティベーション完了: \(label)")
        }
        Task { @MainActor [self] in
            wcStatus = label
        }
    }
}
