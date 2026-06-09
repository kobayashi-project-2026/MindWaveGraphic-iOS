//
//  HealthKitManager.swift
//  MindWaveGraphic
//

import Foundation
import HealthKit

// ─────────────────────────────────────────────────────────
// HealthMetricFetchResult
// HealthKitから1つの指標を取得した結果をまとめる構造体。
// 取得成否・取得元（最新1件か平均か）・メッセージ・時刻を保持する。
// ─────────────────────────────────────────────────────────
struct HealthMetricFetchResult {
    /// 取得できた値。取得失敗の場合は nil。
    let value: Double?
    /// どの方法で取得したかを示す文字列（例: "最新1件", "直近5分平均"）
    let source: String
    /// 診断表示・ログ用のメッセージ
    let message: String
    /// サンプルの取得時刻（未取得の場合は nil）
    let sampleDate: Date?

    /// 取得に成功したか
    var isSuccess: Bool { value != nil }
}

// ─────────────────────────────────────────────────────────
// HealthKitManager
// HealthKitへの読み取り専用アクセスをまとめたクラス。
// 書き込みは行わない。
//
// 取得対象：
//   - heartRate（心拍数、bpm）
//   - heartRateVariabilitySDNN（心拍変動SDNN、ms）
//
// HealthKitは、Apple Watchで記録されたデータが
// iPhoneのヘルスケアアプリに同期されている場合のみ取得できる。
// データが存在しない場合は nil を返す。アプリはクラッシュしない。
// ─────────────────────────────────────────────────────────
final class HealthKitManager {

    private let store = HKHealthStore()

    // 心拍数の型（単位: count/min = bpm）
    private let heartRateType = HKQuantityType(.heartRate)

    // HRV（SDNN）の型（単位: ms）
    // Apple WatchはSDNNをHealthKitに記録する。
    // RMSSDは現段階では使用しない（Appleの標準実装に合わせてSDNNを採用）。
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)

    // MARK: - Availability

    /// このデバイスでHealthKitが利用可能か確認する。
    /// iOSシミュレータや非Apple端末ではfalseになる。
    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    /// 心拍数・HRVの読み取り許可をリクエストする。
    /// toShare（書き込み）は空にしているため、データの書き込みは一切行わない。
    func requestAuthorization() async throws {
        guard Self.isAvailable else {
            print("[HealthKit] このデバイスではHealthKitを使用できません")
            return
        }
        let readTypes: Set<HKObjectType> = [heartRateType, hrvType]
        print("[HealthKit] 読み取り権限をリクエストします（heartRate, heartRateVariabilitySDNN）")
        try await store.requestAuthorization(toShare: [], read: readTypes)
        print("[HealthKit] 権限リクエスト完了")
    }

    // MARK: - Best Current Heart Rate（段階的フォールバック）

    /// 現在の心拍数として使える最善の値を取得する。
    ///
    /// 取得優先順位：
    ///   1. 最新の1サンプル（時刻問わず最新）
    ///   2. 直近1分の平均
    ///   3. 直近5分の平均
    ///   4. 直近30分の平均
    ///
    /// 最新1件が取れない場合、Apple WatchからiPhoneへの同期が
    /// まだ完了していない可能性がある。段階的にフォールバックする。
    func fetchBestCurrentHeartRate() async -> HealthMetricFetchResult {
        let unit = HKUnit.count().unitDivided(by: .minute())

        // ① 最新の1サンプル（最もリアルタイムに近い）
        if let v = await fetchLatest(type: heartRateType, unit: unit) {
            let msg = "latest HR: \(String(format: "%.1f", v)) bpm"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "最新1件", message: msg, sampleDate: Date())
        }

        // ② 直近1分の平均（Apple Watchが直前に同期していれば取れる）
        if let v = await fetchRecentAverage(type: heartRateType, unit: unit, minutes: 1) {
            let msg = "HR 直近1分平均: \(String(format: "%.1f", v)) bpm"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近1分平均", message: msg, sampleDate: Date())
        }

        // ③ 直近5分の平均
        if let v = await fetchRecentAverage(type: heartRateType, unit: unit, minutes: 5) {
            let msg = "HR 直近5分平均: \(String(format: "%.1f", v)) bpm"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近5分平均", message: msg, sampleDate: Date())
        }

        // ④ 直近30分の平均
        if let v = await fetchRecentAverage(type: heartRateType, unit: unit, minutes: 30) {
            let msg = "HR 直近30分平均: \(String(format: "%.1f", v)) bpm"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近30分平均", message: msg, sampleDate: Date())
        }

        // 全て失敗 → Apple Watch未装着か未同期の可能性が高い
        let msg = "心拍取得失敗（Apple Watch未接続または未同期）"
        print("[HealthKit] \(msg)")
        return HealthMetricFetchResult(value: nil, source: "none", message: msg, sampleDate: nil)
    }

    // MARK: - Best Current HRV（段階的フォールバック）

    /// 現在のHRV（SDNN）として使える最善の値を取得する。
    ///
    /// 取得優先順位：
    ///   1. 直近30分
    ///   2. 直近24時間（睡眠中のHRVが入っていることが多い）
    ///   3. 全期間の最新値
    ///
    /// Apple WatchのHRVは深呼吸セッションや睡眠中に記録されるため、
    /// リアルタイム取得が難しい。最善の過去値を使う。
    func fetchBestCurrentHRV() async -> HealthMetricFetchResult {
        let unit = HKUnit.secondUnit(with: .milli)

        // ① 直近30分（最もリアルタイムに近い）
        if let v = await fetchRecentAverage(type: hrvType, unit: unit, minutes: 30) {
            let msg = "HRV 直近30分: \(String(format: "%.1f", v)) ms"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近30分", message: msg, sampleDate: Date())
        }

        // ② 直近24時間（睡眠中に記録されたHRVを捕捉）
        if let v = await fetchRecentAverage(type: hrvType, unit: unit, minutes: 60 * 24) {
            let msg = "HRV 直近24時間: \(String(format: "%.1f", v)) ms"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "直近24時間", message: msg, sampleDate: Date())
        }

        // ③ 全期間の最新1件
        if let v = await fetchLatest(type: hrvType, unit: unit) {
            let msg = "HRV 最新記録: \(String(format: "%.1f", v)) ms"
            print("[HealthKit] \(msg)")
            return HealthMetricFetchResult(value: v, source: "最新記録", message: msg, sampleDate: Date())
        }

        let msg = "HRVデータなし（Apple WatchのHRV測定が必要）"
        print("[HealthKit] \(msg)")
        return HealthMetricFetchResult(value: nil, source: "none", message: msg, sampleDate: nil)
    }

    // MARK: - Average Heart Rate（個人ベースライン）

    /// 過去 days 日間の平均心拍数（bpm）を返す。
    /// スコア計算の個人ベースライン（averageHeartRate）として使用する。
    func fetchAverageHeartRate(days: Int = 7) async -> Double? {
        let result = await fetchAverage(
            type: heartRateType,
            unit: HKUnit.count().unitDivided(by: .minute()),
            days: days
        )
        if let v = result {
            print("[HealthKit] \(days)日平均心拍数: \(String(format: "%.1f", v)) bpm")
        } else {
            print("[HealthKit] \(days)日平均心拍数：データなし")
        }
        return result
    }

    // MARK: - Average HRV（個人ベースライン）

    /// 過去 days 日間の平均HRV・SDNN（ms）を返す。
    /// スコア計算の個人ベースライン（averageHRV）として使用する。
    func fetchAverageHRV(days: Int = 7) async -> Double? {
        let result = await fetchAverage(
            type: hrvType,
            unit: .secondUnit(with: .milli),
            days: days
        )
        if let v = result {
            print("[HealthKit] \(days)日平均HRV: \(String(format: "%.1f", v)) ms")
        } else {
            print("[HealthKit] \(days)日平均HRV：データなし")
        }
        return result
    }

    // MARK: - Private: 最新1サンプルを取得

    private func fetchLatest(type: HKQuantityType, unit: HKUnit) async -> Double? {
        let store = self.store
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error {
                    print("[HealthKit] fetchLatest エラー: \(error.localizedDescription)")
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    // MARK: - Private: 直近N分の平均を取得

    private func fetchRecentAverage(type: HKQuantityType, unit: HKUnit, minutes: Int) async -> Double? {
        let now   = Date()
        let start = Calendar.current.date(byAdding: .minute, value: -minutes, to: now) ?? now
        return await fetchAverageBetween(type: type, unit: unit, start: start, end: now)
    }

    // MARK: - Private: 過去N日の平均を取得

    private func fetchAverage(type: HKQuantityType, unit: HKUnit, days: Int) async -> Double? {
        let now   = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return await fetchAverageBetween(type: type, unit: unit, start: start, end: now)
    }

    // MARK: - Private: 期間指定の平均（共通処理）

    private func fetchAverageBetween(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        let store = self.store

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error {
                    print("[HealthKit] fetchAverage エラー: \(error.localizedDescription)")
                }
                guard let samples = samples as? [HKQuantitySample],
                      !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let total = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                continuation.resume(returning: total / Double(samples.count))
            }
            store.execute(query)
        }
    }
}
