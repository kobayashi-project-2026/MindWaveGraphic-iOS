//
//  HealthKitManager.swift
//  MindWaveGraphic
//

import Foundation
import HealthKit

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
    /// falseの場合はHealthKit関連の処理を全てスキップする。
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

    // MARK: - Recent Heart Rate

    /// 直近 minutes 分間の平均心拍数（bpm）を取得する。
    /// Apple Watchを装着・接続中であれば心拍数は数分おきに記録される。
    /// 取得できない場合は (nil, 理由メッセージ) を返す。
    func fetchRecentHeartRate(minutes: Int = 30) async -> (value: Double?, message: String) {
        let result = await fetchRecentAverage(
            type: heartRateType,
            unit: HKUnit.count().unitDivided(by: .minute()),
            minutes: minutes
        )
        if let v = result {
            let msg = "直近\(minutes)分の平均: \(String(format: "%.1f", v)) bpm"
            print("[HealthKit] \(msg)")
            return (v, msg)
        } else {
            let msg = "直近\(minutes)分の心拍データなし（Apple Watch未装着・未同期の可能性）"
            print("[HealthKit] \(msg)")
            return (nil, msg)
        }
    }

    // MARK: - Recent HRV (段階的フォールバック)

    /// Apple WatchのHRV（SDNN, ms）を取得する。
    /// HRVはApple Watchの深呼吸セッションや睡眠中にしか記録されないことが多いため、
    /// 直近30分 → 直近24時間 → 全期間最新値 の順にフォールバックして取得を試みる。
    /// それでも取れない場合は (nil, 理由) を返す。アプリはクラッシュしない。
    func fetchRecentHRV() async -> (value: Double?, message: String) {
        // Step1: 直近30分のHRVを試みる
        if let v = await fetchRecentAverage(
            type: hrvType,
            unit: .secondUnit(with: .milli),
            minutes: 30
        ) {
            let msg = "直近30分: \(String(format: "%.1f", v)) ms"
            print("[HealthKit] HRV（\(msg)）")
            return (v, msg)
        }

        // Step2: 直近24時間を試みる（Apple WatchのHRVは睡眠中に記録されることが多い）
        if let v = await fetchRecentAverage(
            type: hrvType,
            unit: .secondUnit(with: .milli),
            minutes: 60 * 24
        ) {
            let msg = "直近24時間: \(String(format: "%.1f", v)) ms"
            print("[HealthKit] HRV（\(msg)）")
            return (v, msg)
        }

        // Step3: 全期間で最新の1件を取得する
        if let v = await fetchLatest(type: hrvType, unit: .secondUnit(with: .milli)) {
            let msg = "最新記録: \(String(format: "%.1f", v)) ms"
            print("[HealthKit] HRV（\(msg)）")
            return (v, msg)
        }

        // 全て失敗した場合 → HRVデータなし
        let msg = "HRVデータなし（Apple WatchのHRV測定が必要）"
        print("[HealthKit] \(msg)")
        return (nil, msg)
    }

    // MARK: - Average Heart Rate (個人ベースライン)

    /// 過去 days 日間の平均心拍数（bpm）を返す。
    /// この値をスコア計算の個人ベースライン（averageHeartRate）として使用する。
    /// 取得できない場合は nil。
    func fetchAverageHeartRate(days: Int = 7) async -> Double? {
        let result = await fetchAverage(
            type: heartRateType,
            unit: HKUnit.count().unitDivided(by: .minute()),
            days: days
        )
        if let v = result {
            print("[HealthKit] \(days)日平均心拍数: \(String(format: "%.1f", v)) bpm")
        } else {
            print("[HealthKit] \(days)日平均心拍数：データなし（HealthKitに記録がない可能性）")
        }
        return result
    }

    /// 過去 days 日間の平均HRV・SDNN（ms）を返す。
    /// この値をスコア計算の個人ベースライン（averageHRV）として使用する。
    /// 取得できない場合は nil。
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

    // MARK: - Private: 最新の1サンプルを取得

    /// HealthKitから最新の1サンプルを取得する汎用関数。
    private func fetchLatest(type: HKQuantityType, unit: HKUnit) async -> Double? {
        let store = self.store
        return await withCheckedContinuation { continuation in
            // 開始日時の降順でソートし、最新の1件のみ取得する
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

    /// 直近 minutes 分間のサンプルを取得して平均を返す。
    private func fetchRecentAverage(type: HKQuantityType, unit: HKUnit, minutes: Int) async -> Double? {
        let now   = Date()
        let start = Calendar.current.date(byAdding: .minute, value: -minutes, to: now) ?? now
        return await fetchAverageBetween(type: type, unit: unit, start: start, end: now)
    }

    // MARK: - Private: 過去N日の平均を取得

    /// 過去 days 日間のサンプルを取得して平均を返す。
    private func fetchAverage(type: HKQuantityType, unit: HKUnit, days: Int) async -> Double? {
        let now   = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return await fetchAverageBetween(type: type, unit: unit, start: start, end: now)
    }

    // MARK: - Private: 期間指定の平均取得（共通処理）

    /// start〜end の期間に記録されたサンプルの平均値を返す。
    /// サンプルが0件の場合は nil を返す。
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
