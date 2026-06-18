//
//  HealthKitManager.swift
//  MindWaveGraphic
//

import Foundation
import HealthKit

// ─────────────────────────────────────────────────────────
// HealthMetricFetchResult
// HealthKitから1つの指標を取得した結果をまとめる構造体。
// ─────────────────────────────────────────────────────────
struct HealthMetricFetchResult {
    /// 取得できた値。取得失敗の場合は nil。
    let value: Double?
    /// 取得方法（例: "最新1件", "直近5分平均"）
    let source: String
    /// 診断・ログ用メッセージ
    let message: String
    /// HealthKitサンプル自体の記録時刻（fetchした時刻ではない）
    /// これにより「新しいデータが来たか」「前回と同じサンプルか」を判定できる。
    let sampleDate: Date?
    /// サンプルのUUID文字列（新旧判定に使う。nilは平均値など識別子がない場合）
    let sampleIdentifier: String?

    var isSuccess: Bool { value != nil }
}

// ─────────────────────────────────────────────────────────
// HealthKitManager
// 読み取り専用。書き込みは行わない。
// 対象: heartRate / heartRateVariabilitySDNN
// ─────────────────────────────────────────────────────────
final class HealthKitManager {

    private let store = HKHealthStore()
    private let heartRateType = HKQuantityType(.heartRate)
    private let hrvType       = HKQuantityType(.heartRateVariabilitySDNN)

    private var hrvObserverQuery: HKObserverQuery?

    // MARK: - Availability

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard Self.isAvailable else {
            print("[HealthKit] このデバイスではHealthKitを使用できません")
            return
        }
        let readTypes: Set<HKObjectType> = [heartRateType, hrvType]
        print("[HealthKit] 権限リクエスト開始")
        try await store.requestAuthorization(toShare: [], read: readTypes)
        print("[HealthKit] 権限リクエスト完了")
    }

    // MARK: - Best Current Heart Rate（段階的フォールバック）

    /// 最善の現在心拍数を取得する。
    /// 最新1件 → 直近1分 → 直近5分 → 直近30分 の順でフォールバック。
    ///
    /// 最新1件では sampleDate に HealthKit サンプル自体の記録時刻を入れる。
    /// これにより「前回と同じサンプルを読んでいるだけか」の判定ができる。
    func fetchBestCurrentHeartRate() async -> HealthMetricFetchResult {
        let unit = HKUnit.count().unitDivided(by: .minute())

        // ① 最新の1サンプル（サンプル自体の記録時刻 + UUID を取得する）
        if let s = await fetchLatestSample(type: heartRateType, unit: unit) {
            let msg = "latest HR: \(String(format: "%.1f", s.value)) bpm"
            print("[HealthKit] \(msg) (recorded: \(formatDate(s.sampleDate)))")
            return HealthMetricFetchResult(
                value: s.value, source: "最新1件",
                message: msg, sampleDate: s.sampleDate, sampleIdentifier: s.identifier
            )
        }

        // ② 直近1分の平均
        if let v = await fetchRecentAverage(type: heartRateType, unit: unit, minutes: 1) {
            let msg = "HR 直近1分平均: \(String(format: "%.1f", v)) bpm"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近1分平均", message: msg,
                                          sampleDate: Date(), sampleIdentifier: nil)
        }

        // ③ 直近5分の平均
        if let v = await fetchRecentAverage(type: heartRateType, unit: unit, minutes: 5) {
            let msg = "HR 直近5分平均: \(String(format: "%.1f", v)) bpm"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近5分平均", message: msg,
                                          sampleDate: Date(), sampleIdentifier: nil)
        }

        // ④ 直近30分の平均
        if let v = await fetchRecentAverage(type: heartRateType, unit: unit, minutes: 30) {
            let msg = "HR 直近30分平均: \(String(format: "%.1f", v)) bpm"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近30分平均", message: msg,
                                          sampleDate: Date(), sampleIdentifier: nil)
        }

        let msg = "心拍取得失敗（Apple Watch未接続または未同期）"
        print("[HealthKit] \(msg)")
        return HealthMetricFetchResult(value: nil, source: "none", message: msg,
                                      sampleDate: nil, sampleIdentifier: nil)
    }

    // MARK: - Best Current HRV（段階的フォールバック）

    /// 最善のHRV値を取得する。
    /// HRVは深呼吸・睡眠中のみ記録されるため直近30分→24時間→最新1件でフォールバック。
    func fetchBestCurrentHRV() async -> HealthMetricFetchResult {
        let unit = HKUnit.secondUnit(with: .milli)

        // ① 直近30分（最もリアルタイムに近い）
        if let v = await fetchRecentAverage(type: hrvType, unit: unit, minutes: 30) {
            let msg = "HRV 直近30分: \(String(format: "%.1f", v)) ms"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近30分", message: msg,
                                          sampleDate: Date(), sampleIdentifier: nil)
        }

        // ② 直近24時間（睡眠中のHRVを捕捉）
        if let v = await fetchRecentAverage(type: hrvType, unit: unit, minutes: 60 * 24) {
            let msg = "HRV 直近24時間: \(String(format: "%.1f", v)) ms"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近24時間", message: msg,
                                          sampleDate: Date(), sampleIdentifier: nil)
        }

        // ③ 全期間の最新1件（記録時刻 + UUID を取得する）
        if let s = await fetchLatestSample(type: hrvType, unit: unit) {
            let msg = "HRV 最新記録: \(String(format: "%.1f", s.value)) ms"
            print("[HealthKit] \(msg) (recorded: \(formatDate(s.sampleDate)))")
            return HealthMetricFetchResult(
                value: s.value, source: "最新記録",
                message: msg, sampleDate: s.sampleDate, sampleIdentifier: s.identifier
            )
        }

        let msg = "HRVデータなし（Apple WatchのHRV測定が必要）"
        print("[HealthKit] \(msg)")
        return HealthMetricFetchResult(value: nil, source: "none", message: msg,
                                      sampleDate: nil, sampleIdentifier: nil)
    }

    // MARK: - Average（個人ベースライン）

    func fetchAverageHeartRate(days: Int = 7) async -> Double? {
        let v = await fetchAverage(type: heartRateType,
                                   unit: HKUnit.count().unitDivided(by: .minute()), days: days)
        if let v { print("[HealthKit] \(days)日平均HR: \(String(format: "%.1f", v)) bpm") }
        else       { print("[HealthKit] \(days)日平均HR：データなし") }
        return v
    }

    func fetchAverageHRV(days: Int = 7) async -> Double? {
        let v = await fetchAverage(type: hrvType, unit: .secondUnit(with: .milli), days: days)
        if let v { print("[HealthKit] \(days)日平均HRV: \(String(format: "%.1f", v)) ms") }
        else       { print("[HealthKit] \(days)日平均HRV：データなし") }
        return v
    }

    // MARK: - Private: 最新1サンプル（value + sampleDate + identifier）

    /// fetchした時刻ではなく、HealthKitに記録されたサンプル自体の startDate を返す。
    /// sampleIdentifier（UUID）は、前回と同じサンプルか判定するために使う。
    private func fetchLatestSample(
        type: HKQuantityType, unit: HKUnit
    ) async -> (value: Double, sampleDate: Date, identifier: String)? {
        let store = self.store
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil,
                                      limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    print("[HealthKit] fetchLatestSample エラー: \(error.localizedDescription)")
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value  = sample.quantity.doubleValue(for: unit)
                let date   = sample.startDate
                let id     = sample.uuid.uuidString
                continuation.resume(returning: (value, date, id))
            }
            store.execute(query)
        }
    }

    // MARK: - Private: 直近N分の平均

    private func fetchRecentAverage(type: HKQuantityType, unit: HKUnit, minutes: Int) async -> Double? {
        let now   = Date()
        let start = Calendar.current.date(byAdding: .minute, value: -minutes, to: now) ?? now
        return await fetchAverageBetween(type: type, unit: unit, start: start, end: now)
    }

    // MARK: - Private: 過去N日の平均

    private func fetchAverage(type: HKQuantityType, unit: HKUnit, days: Int) async -> Double? {
        let now   = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return await fetchAverageBetween(type: type, unit: unit, start: start, end: now)
    }

    // MARK: - Private: 期間指定の平均（共通処理）

    private func fetchAverageBetween(type: HKQuantityType, unit: HKUnit,
                                     start: Date, end: Date) async -> Double? {
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        let store = self.store
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: pred,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    print("[HealthKit] fetchAverage エラー: \(error.localizedDescription)")
                }
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let total = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                continuation.resume(returning: total / Double(samples.count))
            }
            store.execute(query)
        }
    }

    // MARK: - HRV Observer

    /// 最新HRVサンプルを HealthMetricFetchResult として返す。
    /// sampleIdentifier（UUID）が含まれるため重複検知に使用できる。
    func fetchLatestHRVSample() async -> HealthMetricFetchResult {
        let unit = HKUnit.secondUnit(with: .milli)
        if let s = await fetchLatestSample(type: hrvType, unit: unit) {
            let msg = "HRV 最新サンプル: \(String(format: "%.1f", s.value)) ms"
            return HealthMetricFetchResult(
                value: s.value,
                source: "最新サンプル",
                message: msg,
                sampleDate: s.sampleDate,
                sampleIdentifier: s.identifier
            )
        }
        return HealthMetricFetchResult(
            value: nil,
            source: "none",
            message: "HRVサンプルなし",
            sampleDate: nil,
            sampleIdentifier: nil
        )
    }

    /// HealthKit HRVの新規サンプル追加を監視する。
    /// 新しいサンプルが保存されるたびに handler が呼ばれる。
    /// handler はバックグラウンドスレッドから呼ばれるため、呼び出し側で MainActor dispatch が必要。
    func startHRVObserver(handler: @escaping (HealthMetricFetchResult) -> Void) {
        guard Self.isAvailable else { return }

        // 既存オブザーバーを停止してから再登録
        if let existing = hrvObserverQuery {
            store.stop(existing)
        }

        let query = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self else { completionHandler(); return }
            if let error = error {
                MindWaveDebugLogger.log(.error, "HRV observer error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            Task {
                let result = await self.fetchLatestHRVSample()
                handler(result)
                // HealthKitへ処理完了を通知（background delivery使用時に必要）
                completionHandler()
            }
        }
        hrvObserverQuery = query
        store.execute(query)
        MindWaveDebugLogger.log(.healthKit, "HRV observer started")
    }

    /// HRV observerを停止する。
    func stopHRVObserver() {
        if let query = hrvObserverQuery {
            store.stop(query)
            hrvObserverQuery = nil
            MindWaveDebugLogger.log(.healthKit, "HRV observer stopped")
        }
    }

    // MARK: - Private: ログ用日時フォーマット

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
