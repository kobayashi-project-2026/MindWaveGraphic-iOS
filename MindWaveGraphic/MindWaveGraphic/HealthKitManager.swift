//
//  HealthKitManager.swift
//  MindWaveGraphic
//

import Foundation
import HealthKit

/// HealthKitからの読み取り専用アクセスを管理する。
/// 書き込みは行わない。対象データは heartRate と heartRateVariabilitySDNN のみ。
final class HealthKitManager {

    private let store = HKHealthStore()

    // 読み取る量的データ型
    private let heartRateType = HKQuantityType(.heartRate)
    private let hrvType       = HKQuantityType(.heartRateVariabilitySDNN)

    // MARK: - Availability

    /// このデバイスでHealthKitが利用可能か（シミュレータ・非Apple端末ではfalse）
    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    /// 心拍数・HRVの読み取り許可をリクエストする。書き込み権限は要求しない。
    func requestAuthorization() async throws {
        guard Self.isAvailable else { return }
        let readTypes: Set<HKObjectType> = [heartRateType, hrvType]
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Latest Values

    /// 最新の心拍数（bpm）を返す。取得できない場合は nil。
    func fetchLatestHeartRate() async -> Double? {
        await fetchLatest(type: heartRateType,
                          unit: HKUnit.count().unitDivided(by: .minute()))
    }

    /// 最新のHRV・SDNN（ms）を返す。取得できない場合は nil。
    /// RMSSDは現段階では使用しない（SDNN を Apple Watch 標準指標として採用）。
    func fetchLatestHRV() async -> Double? {
        await fetchLatest(type: hrvType, unit: .secondUnit(with: .milli))
    }

    // MARK: - Averages

    /// 過去 days 日間の平均心拍数（bpm）を返す。
    func fetchAverageHeartRate(days: Int = 7) async -> Double? {
        await fetchAverage(type: heartRateType,
                           unit: HKUnit.count().unitDivided(by: .minute()),
                           days: days)
    }

    /// 過去 days 日間の平均HRV・SDNN（ms）を返す。
    func fetchAverageHRV(days: Int = 7) async -> Double? {
        await fetchAverage(type: hrvType,
                           unit: .secondUnit(with: .milli),
                           days: days)
    }

    // MARK: - Private Helpers

    private func fetchLatest(type: HKQuantityType, unit: HKUnit) async -> Double? {
        let store = self.store
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func fetchAverage(type: HKQuantityType, unit: HKUnit, days: Int) async -> Double? {
        let now   = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let pred  = HKQuery.predicateForSamples(withStart: start, end: now)
        let store = self.store

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
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
