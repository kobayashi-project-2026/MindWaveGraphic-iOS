//
//  HealthKitManager.swift
//  MindWaveGraphic
//

import Foundation
import HealthKit

// ─────────────────────────────────────────────────────────
// HealthMetricResultKind
// 実際のHKQuantitySampleか集計値かを区別する。
// discreteSample: UUID・startDate・endDate を持つ実サンプル
// aggregateFallback: 30分平均等の集計値（UUID・endDateなし）
// unavailable: 値なし
// ─────────────────────────────────────────────────────────
enum HealthMetricResultKind {
    case discreteSample
    case aggregateFallback
    case unavailable
}

// ─────────────────────────────────────────────────────────
// HealthMetricFetchResult
// HealthKitから1つの指標を取得した結果をまとめる構造体。
// ─────────────────────────────────────────────────────────
struct HealthMetricFetchResult {
    /// 取得できた値。取得失敗の場合は nil。
    let value: Double?
    /// 取得方法（例: "最新実サンプル", "直近30分平均"）
    let source: String
    /// 診断・ログ用メッセージ
    let message: String
    /// HealthKitサンプル自体の記録時刻（startDate）。集計値はnil。
    let sampleDate: Date?
    /// サンプルのUUID文字列（新旧判定に使う。nilは集計値など識別子がない場合）
    let sampleIdentifier: String?
    /// サンプルの終了時刻（HRVのendDate診断用。集計値はnil）
    let sampleEndDate: Date?
    /// サンプルのSource名（診断用。nilは集計値など）
    let sourceName: String?
    /// サンプルのBundleIdentifier（診断用）
    let sourceBundleIdentifier: String?
    /// 結果の種別（実サンプル / 集計フォールバック / 取得不能）
    let kind: HealthMetricResultKind

    var isSuccess: Bool { value != nil }

    /// 既存コード互換のinit。新規フィールドはデフォルト値あり。
    init(value: Double?, source: String, message: String,
         sampleDate: Date?, sampleIdentifier: String?,
         sampleEndDate: Date? = nil,
         sourceName: String? = nil,
         sourceBundleIdentifier: String? = nil,
         kind: HealthMetricResultKind = .aggregateFallback) {
        self.value = value
        self.source = source
        self.message = message
        self.sampleDate = sampleDate
        self.sampleIdentifier = sampleIdentifier
        self.sampleEndDate = sampleEndDate
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.kind = kind
    }
}

// MARK: - HRV診断サンプル型

/// HRV診断クエリの1件分の詳細情報。
/// 架空の値は含まない。HealthKitから読み取った実データのみ。
struct HRVDiagnosticSample {
    let valueMilliseconds: Double
    let startDate: Date
    let endDate: Date
    let uuid: UUID
    let sourceName: String
    let sourceBundleIdentifier: String
    let deviceName: String?
}

// ─────────────────────────────────────────────────────────
// HRVObserverPhase / HRVObserverBatch
// AnchoredObjectQueryの1 callbackをViewModelへ渡す型。
// resultsHandler / updateHandler それぞれに1 Batchを生成する。
// サンプル0件・全件除外・エラー時も必ずBatchを送信する。
// ─────────────────────────────────────────────────────────
enum HRVObserverPhase: String {
    case initial = "initial"
    case update  = "update"
}

struct HRVObserverBatch {
    let phase: HRVObserverPhase
    let callbackDate: Date
    let rawSampleCount: Int
    let acceptedResults: [HealthMetricFetchResult]
    let duplicateRejectedCount: Int
    let staleRejectedCount: Int
    let errorDescription: String?
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

    private var hrvAnchoredQuery: HKAnchoredObjectQuery?
    private var hrvQueryAnchor: HKQueryAnchor?
    private var isHRVMonitoringActive = false
    private var lastAcceptedHRVEndDate: Date?
    private var lastAcceptedHRVUUID: String?
    private(set) var hrvAcceptedCount = 0
    private(set) var hrvDuplicateCount = 0
    private(set) var hrvStaleCount = 0
    // callback回数・時刻（呼ばれた時点で計上、サンプル採否に関係なし）
    private(set) var initialCallbackCount: Int = 0
    private(set) var updateCallbackCount: Int  = 0
    private(set) var lastInitialCallbackDate: Date? = nil
    private(set) var lastUpdateCallbackDate: Date?  = nil
    // raw sample総数（acceptSample通過前）
    private(set) var initialRawSampleTotal: Int = 0
    private(set) var updateRawSampleTotal: Int  = 0
    // accepted sample総数（acceptSample通過後）
    private(set) var initialAcceptedTotal: Int = 0
    private(set) var updateAcceptedTotal: Int  = 0
    // 直近callback診断
    private(set) var lastCallbackRawCount: Int      = 0
    private(set) var lastCallbackHKMAcceptedCount: Int = 0
    private(set) var lastQueryError: String?        = nil

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
            return HealthMetricFetchResult(
                value: s.value, source: "最新1件",
                message: msg, sampleDate: s.sampleDate, sampleIdentifier: s.identifier,
                sampleEndDate: s.endDate, sourceName: s.sourceName, sourceBundleIdentifier: s.bundleID
            )
        }

        // ② 直近1分の平均
        if let v = await fetchRecentAverage(type: heartRateType, unit: unit, minutes: 1) {
            let msg = "HR 直近1分平均: \(String(format: "%.1f", v)) bpm"
            return HealthMetricFetchResult(value: v, source: "直近1分平均", message: msg,
                                          sampleDate: Date(), sampleIdentifier: nil)
        }

        // ③ 直近5分の平均
        if let v = await fetchRecentAverage(type: heartRateType, unit: unit, minutes: 5) {
            let msg = "HR 直近5分平均: \(String(format: "%.1f", v)) bpm"
            return HealthMetricFetchResult(value: v, source: "直近5分平均", message: msg,
                                          sampleDate: Date(), sampleIdentifier: nil)
        }

        // ④ 直近30分の平均
        if let v = await fetchRecentAverage(type: heartRateType, unit: unit, minutes: 30) {
            let msg = "HR 直近30分平均: \(String(format: "%.1f", v)) bpm"
            return HealthMetricFetchResult(value: v, source: "直近30分平均", message: msg,
                                          sampleDate: Date(), sampleIdentifier: nil)
        }

        let msg = "心拍取得失敗（Apple Watch未接続または未同期）"
        return HealthMetricFetchResult(value: nil, source: "none", message: msg,
                                      sampleDate: nil, sampleIdentifier: nil)
    }

    // MARK: - Best Current HRV（実サンプル優先・集計フォールバック）

    /// 最善のHRV値を取得する。
    /// 実HRVサンプルを最優先とし、なければ集計フォールバック。
    /// 順序: 最新実サンプル → 30分平均 → 24時間平均 → 取得不能
    func fetchBestCurrentHRV() async -> HealthMetricFetchResult {
        let unit = HKUnit.secondUnit(with: .milli)

        // ① 最新の実HRVサンプル（UUID・startDate・endDate あり）— 最優先
        if let s = await fetchLatestSample(type: hrvType, unit: unit) {
            let msg = "HRV最新実サンプル"
            return HealthMetricFetchResult(
                value: s.value, source: "最新実サンプル",
                message: msg, sampleDate: s.sampleDate, sampleIdentifier: s.identifier,
                sampleEndDate: s.endDate, sourceName: s.sourceName, sourceBundleIdentifier: s.bundleID,
                kind: .discreteSample
            )
        }

        // ② 直近30分平均（集計値・UUID なし）
        if let v = await fetchRecentAverage(type: hrvType, unit: unit, minutes: 30) {
            let msg = "HRV 直近30分平均: \(String(format: "%.1f", v)) ms"
            return HealthMetricFetchResult(value: v, source: "直近30分平均", message: msg,
                                          sampleDate: nil, sampleIdentifier: nil,
                                          kind: .aggregateFallback)
        }

        // ③ 直近24時間平均（集計値・UUID なし）
        if let v = await fetchRecentAverage(type: hrvType, unit: unit, minutes: 60 * 24) {
            let msg = "HRV 直近24時間平均: \(String(format: "%.1f", v)) ms"
            return HealthMetricFetchResult(value: v, source: "直近24時間平均", message: msg,
                                          sampleDate: nil, sampleIdentifier: nil,
                                          kind: .aggregateFallback)
        }

        let msg = "HRVデータなし（Apple WatchのHRV測定が必要）"
        return HealthMetricFetchResult(value: nil, source: "none", message: msg,
                                      sampleDate: nil, sampleIdentifier: nil,
                                      kind: .unavailable)
    }

    // MARK: - Average（個人ベースライン）

    func fetchAverageHeartRate(days: Int = 7) async -> Double? {
        let v = await fetchAverage(type: heartRateType,
                                   unit: HKUnit.count().unitDivided(by: .minute()), days: days)
        if let v { _ = v }  // 値はHealthMetricFetchResult.messageで管理
        return v
    }

    func fetchAverageHRV(days: Int = 7) async -> Double? {
        let v = await fetchAverage(type: hrvType, unit: .secondUnit(with: .milli), days: days)
        if let v { _ = v }  // 値はHealthMetricFetchResult.messageで管理
        return v
    }

    // MARK: - Private: 最新1サンプル（value + startDate + endDate + identifier + source）

    /// HealthKitに記録されたサンプル自体のstartDate・endDate・UUID・Sourceを返す。
    /// startDate降順（最新が先頭）・predicate=nil（全期間対象）・limit=1。
    /// HRVとheartRateの両方で使用する共通メソッド。
    private func fetchLatestSample(
        type: HKQuantityType, unit: HKUnit
    ) async -> (value: Double, sampleDate: Date, endDate: Date, identifier: String, sourceName: String, bundleID: String)? {
        let store = self.store
        return await withCheckedContinuation { continuation in
            // startDate降順：最新のサンプルが先頭になる。HRV SDNNのendDateでも同様に最新が取れる。
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil,
                                      limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    MindWaveDebugLogger.log(.error, "fetchLatestSample error type=\(type.identifier): \(error.localizedDescription)")
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    MindWaveDebugLogger.log(.healthKit, "fetchLatestSample no result type=\(type.identifier)")
                    continuation.resume(returning: nil)
                    return
                }
                let value  = sample.quantity.doubleValue(for: unit)
                let id     = sample.uuid.uuidString
                let src    = sample.sourceRevision.source
                continuation.resume(returning: (value, sample.startDate, sample.endDate, id, src.name, src.bundleIdentifier))
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
    /// 最新HRVサンプルを取得。endDate・Source・bundleIDも返す（診断・dedup用）。
    func fetchLatestHRVSample() async -> HealthMetricFetchResult {
        let unit = HKUnit.secondUnit(with: .milli)
        MindWaveDebugLogger.log(.healthKit, "initial HRV query started")
        if let s = await fetchLatestSample(type: hrvType, unit: unit) {
            let msg = "HRV 最新サンプル: \(String(format: "%.1f", s.value)) ms"
            MindWaveDebugLogger.log(.healthKit, "[HRV] initial sample loaded")
            return HealthMetricFetchResult(
                value: s.value,
                source: "最新サンプル",
                message: msg,
                sampleDate: s.sampleDate,
                sampleIdentifier: s.identifier,
                sampleEndDate: s.endDate,
                sourceName: s.sourceName,
                sourceBundleIdentifier: s.bundleID,
                kind: .discreteSample
            )
        }
        MindWaveDebugLogger.log(.healthKit, "initial HRV query completed count=0")
        return HealthMetricFetchResult(
            value: nil,
            source: "none",
            message: "HRVサンプルなし",
            sampleDate: nil,
            sampleIdentifier: nil,
            kind: .unavailable
        )
    }

    // MARK: - HRV診断Query（全期間・最大N件）

    /// HealthKit内のHRVサンプルを全期間で診断クエリする。
    /// predicate=nil（全期間）、source限定なし、endDate降順、最大limit件。
    /// 0件・エラー・サンプルありを明確に区別する。
    func diagnoseHRVSamples(limit: Int = 20) async -> (samples: [HRVDiagnosticSample], error: String?) {
        guard Self.isAvailable else {
            return ([], "HealthKit not available")
        }
        let unit   = HKUnit.secondUnit(with: .milli)
        let store  = self.store
        MindWaveDebugLogger.log(.healthKit, "HRV diagnostic started limit=\(limit)")

        return await withCheckedContinuation { continuation in
            // endDate降順：最新サンプルが先頭
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: hrvType, predicate: nil,
                                      limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    let msg = "\(error.localizedDescription)"
                    MindWaveDebugLogger.log(.error,
                        "HRV diagnostic query failed domain=\((error as NSError).domain) " +
                        "code=\((error as NSError).code) message=\(msg)")
                    continuation.resume(returning: ([], msg))
                    return
                }
                let cast = samples as? [HKQuantitySample] ?? []
                MindWaveDebugLogger.log(.healthKit, "HRV diagnostic completed count=\(cast.count) error=nil")
                let result = cast.enumerated().map { (i, s) -> HRVDiagnosticSample in
                    let val = s.quantity.doubleValue(for: unit)
                    let src = s.sourceRevision.source
                    MindWaveDebugLogger.log(.healthKit, "[HRV] diagnostic sample[\(i)] loaded")
                    return HRVDiagnosticSample(
                        valueMilliseconds: val,
                        startDate: s.startDate,
                        endDate: s.endDate,
                        uuid: s.uuid,
                        sourceName: src.name,
                        sourceBundleIdentifier: src.bundleIdentifier,
                        deviceName: s.device?.name
                    )
                }
                continuation.resume(returning: (result, nil))
            }
            store.execute(query)
        }
    }

    /// HRV新規サンプルを連続監視する（HKAnchoredObjectQuery）。
    /// resultsHandler: 起動時に既存サンプルを最新1件処理（anchor保持済みの場合は新着のみ）。
    /// updateHandler: 以降の新着サンプルが届くたびに呼ばれる。
    /// 二重起動ガード付き。anchor・重複状態は停止後も保持し再開時に再利用する。
    /// handler はバックグラウンドスレッドから呼ばれるため、呼び出し側で MainActor dispatch が必要。
    /// 1 callbackごとに HRVObserverBatch を生成して handler へ渡す。
    /// 0件・全除外・エラー時も必ず Batch を送信するため、A〜F の状態を区別できる。
    func startHRVObserver(handler: @escaping (HRVObserverBatch) -> Void) {
        guard Self.isAvailable else { return }
        guard !isHRVMonitoringActive else {
            MindWaveDebugLogger.log(.healthKit, "[HRV] monitor already active, skipping")
            return
        }

        isHRVMonitoringActive = true
        MindWaveDebugLogger.log(.healthKit, "[HRV] monitor starting type=HKAnchoredObjectQuery")

        let unit = HKUnit.secondUnit(with: .milli)

        let query = HKAnchoredObjectQuery(
            type: hrvType,
            predicate: nil,
            anchor: hrvQueryAnchor,          // 保持済みanchorを使用（nil=全履歴、非nil=差分のみ）
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            guard let self else { return }
            let callbackDate = Date()
            if let newAnchor { self.hrvQueryAnchor = newAnchor }

            self.initialCallbackCount += 1
            self.lastInitialCallbackDate = callbackDate

            if let error = error {
                self.lastQueryError = error.localizedDescription
                MindWaveDebugLogger.log(.error, "[HRV] initial callback error")
                self.lastCallbackRawCount = 0
                self.lastCallbackHKMAcceptedCount = 0
                let batch = HRVObserverBatch(
                    phase: .initial, callbackDate: callbackDate,
                    rawSampleCount: 0, acceptedResults: [],
                    duplicateRejectedCount: 0, staleRejectedCount: 0,
                    errorDescription: error.localizedDescription)
                handler(batch)
                return
            }

            let qs = (samples as? [HKQuantitySample]) ?? []
            let rawCount = qs.count
            self.initialRawSampleTotal += rawCount
            self.lastCallbackRawCount = rawCount
            self.lastQueryError = nil  // 正常callbackでエラー状態を解除
            MindWaveDebugLogger.log(.healthKit, "[HRV] initial callback rawCount=\(rawCount)")

            var accepted: [HealthMetricFetchResult] = []
            let dupeBefore  = self.hrvDuplicateCount
            let staleBefore = self.hrvStaleCount

            // endDate降順で最新1件だけ受理判定する（resultsHandler）
            if let latest = qs.sorted(by: { $0.endDate > $1.endDate }).first,
               self.acceptSample(latest) {
                accepted.append(self.makeHRVResult(from: latest, unit: unit))
            }

            let dupeCount  = self.hrvDuplicateCount - dupeBefore
            let staleCount = self.hrvStaleCount     - staleBefore
            self.initialAcceptedTotal += accepted.count
            self.lastCallbackHKMAcceptedCount = accepted.count

            MindWaveDebugLogger.log(.healthKit,
                "[HRV] initial callback acceptedCount=\(accepted.count)")

            let batch = HRVObserverBatch(
                phase: .initial, callbackDate: callbackDate,
                rawSampleCount: rawCount, acceptedResults: accepted,
                duplicateRejectedCount: dupeCount, staleRejectedCount: staleCount,
                errorDescription: nil)
            handler(batch)
        }

        query.updateHandler = { [weak self] _, samples, _, newAnchor, error in
            guard let self else { return }
            let callbackDate = Date()
            if let newAnchor { self.hrvQueryAnchor = newAnchor }

            self.updateCallbackCount += 1
            self.lastUpdateCallbackDate = callbackDate

            if let error = error {
                self.lastQueryError = error.localizedDescription
                MindWaveDebugLogger.log(.error, "[HRV] update callback error")
                self.lastCallbackRawCount = 0
                self.lastCallbackHKMAcceptedCount = 0
                let batch = HRVObserverBatch(
                    phase: .update, callbackDate: callbackDate,
                    rawSampleCount: 0, acceptedResults: [],
                    duplicateRejectedCount: 0, staleRejectedCount: 0,
                    errorDescription: error.localizedDescription)
                handler(batch)
                return
            }

            let qs = (samples as? [HKQuantitySample]) ?? []
            let rawCount = qs.count
            self.updateRawSampleTotal += rawCount
            self.lastCallbackRawCount = rawCount
            self.lastQueryError = nil  // 正常callbackでエラー状態を解除
            MindWaveDebugLogger.log(.healthKit, "[HRV] update callback rawCount=\(rawCount)")

            var accepted: [HealthMetricFetchResult] = []
            let dupeBefore  = self.hrvDuplicateCount
            let staleBefore = self.hrvStaleCount

            // endDate昇順で処理（古い順に採用判定）
            for sample in qs.sorted(by: { $0.endDate < $1.endDate }) {
                if self.acceptSample(sample) {
                    accepted.append(self.makeHRVResult(from: sample, unit: unit))
                }
            }

            let dupeCount  = self.hrvDuplicateCount - dupeBefore
            let staleCount = self.hrvStaleCount     - staleBefore
            self.updateAcceptedTotal += accepted.count
            self.lastCallbackHKMAcceptedCount = accepted.count

            MindWaveDebugLogger.log(.healthKit,
                "[HRV] update callback rawCount=\(rawCount) acceptedCount=\(accepted.count)")

            let batch = HRVObserverBatch(
                phase: .update, callbackDate: callbackDate,
                rawSampleCount: rawCount, acceptedResults: accepted,
                duplicateRejectedCount: dupeCount, staleRejectedCount: staleCount,
                errorDescription: nil)
            handler(batch)
        }

        hrvAnchoredQuery = query
        store.execute(query)
        MindWaveDebugLogger.log(.healthKit, "[WatchHRV] monitor started")
    }

    /// HRV監視を停止する。
    /// anchor・重複管理状態は保持し、同一セッション内の再開で過去サンプルを再処理しない。
    func stopHRVObserver() {
        if let query = hrvAnchoredQuery {
            store.stop(query)
            hrvAnchoredQuery = nil
        }
        isHRVMonitoringActive = false
        MindWaveDebugLogger.log(.healthKit, "[HRV] monitor stopped")
        // hrvQueryAnchor / lastAcceptedHRVEndDate / lastAcceptedHRVUUID は保持
    }

    // MARK: - Private: sample 受理判定

    /// UUID重複・古いendDateを除外し、受理の場合は計上して true を返す。
    @discardableResult
    private func acceptSample(_ sample: HKQuantitySample) -> Bool {
        let uuid = sample.uuid.uuidString

        if uuid == lastAcceptedHRVUUID {
            hrvDuplicateCount += 1
            MindWaveDebugLogger.log(.healthKit, "[HRV] HKM duplicate rejected")
            return false
        }

        if let lastDate = lastAcceptedHRVEndDate, sample.endDate <= lastDate {
            hrvStaleCount += 1
            MindWaveDebugLogger.log(.healthKit, "[HRV] HKM stale rejected")
            return false
        }

        lastAcceptedHRVUUID    = uuid
        lastAcceptedHRVEndDate = sample.endDate
        hrvAcceptedCount      += 1
        MindWaveDebugLogger.log(.healthKit, "[HRV] HKM accepted")
        return true
    }

    // MARK: - Private: HKQuantitySample → HealthMetricFetchResult 変換

    /// 鮮度判定に endDate を使用する（HRV は測定完了時刻が鮮度の基準）。
    private func makeHRVResult(from sample: HKQuantitySample, unit: HKUnit) -> HealthMetricFetchResult {
        let value = sample.quantity.doubleValue(for: unit)
        let src   = sample.sourceRevision.source
        return HealthMetricFetchResult(
            value:                  value,
            source:                 "AnchoredObserver",
            message:                "HRV anchored sample",
            sampleDate:             sample.endDate,
            sampleIdentifier:       sample.uuid.uuidString,
            sampleEndDate:          sample.endDate,
            sourceName:             src.name,
            sourceBundleIdentifier: src.bundleIdentifier,
            kind:                   .discreteSample
        )
    }

    // MARK: - Private: ログ用日時フォーマット

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
