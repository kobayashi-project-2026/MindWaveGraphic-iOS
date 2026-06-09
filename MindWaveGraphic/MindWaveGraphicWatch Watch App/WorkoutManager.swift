//
//  WorkoutManager.swift
//  MindWaveGraphicWatch Watch App
//
//  HKWorkoutSession + HKLiveWorkoutBuilder でWatch側から心拍数をリアルタイム取得し、
//  WatchConnectivity 経由でiPhoneに送信する。
//

import Foundation
import HealthKit
import WatchConnectivity

// ─────────────────────────────────────────────────────────
// WorkoutManager
// Watch側の心拍ライブ取得の核。
//
// 流れ:
//   1. requestAuthorization() → HealthKit権限を取得
//   2. startWorkout()         → HKWorkoutSession開始 → HKLiveWorkoutBuilder開始
//   3. workoutBuilder(_:didCollectDataOf:) コールバックで心拍数を受け取る
//   4. sendHeartRateToiPhone() → WCSession.sendMessage or transferUserInfo
//   5. stopWorkout()           → セッション終了・ワークアウト保存
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
    @Published var statusMessage: String     = "停止中"
    /// WCSession接続状態
    @Published var wcStatus: String         = "未接続"
    /// HealthKit権限状態
    @Published var authStatus: String       = "未許可"

    // MARK: - Private

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // MARK: - HealthKit 権限リクエスト

    /// HealthKit権限をリクエストする。
    /// HKWorkoutSession開始前に必ず呼ぶ。
    func requestAuthorization() async {
        // toShare: ワークアウト記録を保存するためにworkoutTypeが必要
        // read: 心拍数を読み取るためにheartRateが必要
        // HKWorkoutType()はwatchOS 26.4で使用不可のため HKObjectType.workoutType() を使う
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead:  Set<HKObjectType> = [HKQuantityType(.heartRate)]

        do {
            try await store.requestAuthorization(toShare: typesToShare, read: typesToRead)
            authStatus = "許可済み"
            print("[Watch HK] HealthKit権限取得完了")
        } catch {
            authStatus = "権限エラー"
            statusMessage = "HealthKit権限エラー: \(error.localizedDescription)"
            print("[Watch HK] 権限取得エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - ワークアウト開始

    /// HKWorkoutSessionを開始し、心拍数のリアルタイム取得を始める。
    func startWorkout() async {
        guard !isRunning else { return }

        let config = HKWorkoutConfiguration()
        // activityType = .other（汎用）でセッションを作成する。
        // 心拍測定目的なので activiyType は何でもよい。
        config.activityType  = .other
        config.locationType  = .unknown

        do {
            let newSession = try HKWorkoutSession(healthStore: store, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()

            session = newSession
            builder = newBuilder

            // デリゲートを設定する
            newSession.delegate = self
            newBuilder.delegate = self

            // HKLiveWorkoutDataSource を設定すると、watchOS が自動で
            // 設定された activityType に応じたデータ（心拍数など）を収集してくれる。
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: config
            )

            // セッション開始
            newSession.startActivity(with: Date())

            // データ収集開始（コールバックベースをContinuationでラップする）
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                newBuilder.beginCollection(withStart: Date()) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            isRunning     = true
            statusMessage = "計測中 ❤️"
            print("[Watch HK] ワークアウトセッション開始")

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

    // MARK: - WatchConnectivity セットアップ

    /// WCSessionをアクティベートする。
    /// アプリ起動時に一度呼ぶ。
    func setupWCSession() {
        guard WCSession.isSupported() else {
            wcStatus = "WC非対応"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        print("[Watch WC] WCSession activate 開始")
    }

    // MARK: - iPhone へ心拍数送信

    /// 心拍数をWatchConnectivity経由でiPhoneに送信する。
    /// iPhoneが到達可能 → sendMessage（低レイテンシ）
    /// 到達不可          → transferUserInfo（バックグラウンド転送）
    private func sendHeartRateToiPhone(_ heartRate: Double) {
        let message: [String: Any] = [
            "type":      "heartRate",
            "heartRate": heartRate,
            "timestamp": Date().timeIntervalSince1970
        ]

        if WCSession.default.isReachable {
            // iPhoneアプリが起動中でリアルタイム送信できる
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                // sendMessageが失敗したらtransferUserInfoにフォールバックする
                WCSession.default.transferUserInfo(message)
                print("[Watch WC] sendMessage失敗 → transferUserInfo: \(error.localizedDescription)")
            }
        } else {
            // iPhoneが到達不可のときはキューに入れて後送する
            WCSession.default.transferUserInfo(message)
            print("[Watch WC] iPhone到達不可 → transferUserInfo使用")
        }

        sendCount    += 1
        statusMessage = String(format: "送信中: %.0f bpm（%d回）", heartRate, sendCount)
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {

    /// セッション状態変化（開始・一時停止・終了など）
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let label: String
        switch toState {
        case .running:   label = "計測中 ❤️"
        case .ended:     label = "終了"
        case .paused:    label = "一時停止"
        case .stopped:   label = "停止"
        case .notStarted: label = "未開始"
        case .prepared:  label = "準備中"
        @unknown default: label = "不明"
        }
        print("[Watch HK] セッション状態: \(label)")
        Task { @MainActor [self] in
            if toState == .ended || toState == .stopped {
                isRunning     = false
                statusMessage = label
            }
        }
    }

    /// セッションエラー
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

    /// イベント収集（必須メソッドだが今回は使わない）
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
              ) else { return }

        print("[Watch HK] 心拍受信: \(String(format: "%.0f", hr)) bpm")

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
        print("[Watch WC] アクティベーション: \(label)")
        Task { @MainActor [self] in
            wcStatus = label
        }
    }
}
