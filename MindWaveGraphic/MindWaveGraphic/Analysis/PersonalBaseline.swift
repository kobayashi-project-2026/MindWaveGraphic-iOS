// PersonalBaseline.swift
// Analysis
//
// 個人ベースライン（平常時の平均心拍・HRV）の管理。
//
// 決定順（心拍・HRV それぞれ独立に判定）:
//   1. HealthKit の直近7日平均（既存実装 fetchAverageHeartRate/HRV(days: 7)。本人の HealthKit 履歴なので個人値）
//   2. アプリが受信した実測サンプルの平均（十分な件数がある場合のみ）
//   3. 参照値（心拍 65 bpm / HRV 45 ms。既存のデモシナリオと同じ値）→ status = provisional
//      ※ 参照値は「個人の平常値」ではない。UI・JSON・ログで必ず provisional と表示する。
//
// 記録規則:
// - 実測（Watch / HealthKit）のみ記録し、Mock は記録しない
// - 運動直後・喫煙・カフェインなど身体状態を申告している間の心拍は平常値を歪めるため記録しない
// - 心拍は 5 分に1件へ間引く（Watch は数秒ごとに届くため）
// - 直近 14 日・最大 500 件を保持

import Foundation

/// ベースライン値の出どころ
nonisolated enum BaselineOrigin: String, Equatable, Sendable {
    case healthKit7DayAverage = "health_kit_7day_average"
    case appCollectedSamples  = "app_collected_samples"
    case reference
}

/// スコア算出に使うベースライン
nonisolated struct BaselineSnapshot: Equatable, Sendable {
    /// 既存のデモシナリオ（MindSampleScenario）と同じ参照値。個人値ではない。
    static let referenceHeartRate: Double = 65
    static let referenceHRV: Double = 45

    var heartRate: Double
    var hrv: Double
    var heartRateOrigin: BaselineOrigin
    var hrvOrigin: BaselineOrigin
    /// アプリ内に蓄積された件数（診断表示用）
    var collectedHeartRateCount: Int = 0
    var collectedHRVCount: Int = 0

    static let reference = BaselineSnapshot(heartRate: referenceHeartRate, hrv: referenceHRV,
                                            heartRateOrigin: .reference, hrvOrigin: .reference)

    var heartRateStatus: BaselineStatus { heartRateOrigin == .reference ? .provisional : .personal }
    var hrvStatus: BaselineStatus { hrvOrigin == .reference ? .provisional : .personal }

    /// HRV を使うスコアでは両方、使わないスコアでは心拍のみが個人値のとき personal
    func status(usesHRV: Bool) -> BaselineStatus {
        let hrPersonal = heartRateStatus == .personal
        let hrvPersonal = hrvStatus == .personal
        return (hrPersonal && (!usesHRV || hrvPersonal)) ? .personal : .provisional
    }
}

/// 個人ベースラインの保存・算出
nonisolated final class PersonalBaselineStore {

    static let defaultsKey = "mindwave.personalBaseline.v1"
    static let retention: TimeInterval = 14 * 24 * 60 * 60
    static let maxSamplesPerMetric = 500
    static let heartRateSamplingInterval: TimeInterval = 5 * 60
    static let minHeartRateSamples = 30
    static let minHeartRateDistinctDays = 3
    static let minHRVSamples = 5

    /// 保存形式（docs/DATA_CONTRACTS.md §9）
    nonisolated struct Document: Codable, Equatable {
        nonisolated struct Entry: Codable, Equatable {
            var value: Double
            var measuredAt: Date
            enum CodingKeys: String, CodingKey { case value; case measuredAt = "measured_at" }
        }
        var schemaVersion: Int = MindWaveContract.schemaVersion
        var heartRateSamples: [Entry] = []
        var hrvSamples: [Entry] = []
        enum CodingKeys: String, CodingKey {
            case schemaVersion    = "schema_version"
            case heartRateSamples = "heart_rate_samples"
            case hrvSamples       = "hrv_samples"
        }
    }

    private let defaults: UserDefaults
    private(set) var document: Document

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let doc = try? MindWaveContract.makeDecoder().decode(Document.self, from: data),
           MindWaveContract.isSupported(schemaVersion: doc.schemaVersion) {
            document = doc
        } else {
            document = Document()
        }
    }

    /// 実測心拍を記録する。記録した場合 true。
    @discardableResult
    func recordHeartRate(_ bpm: Double, at date: Date, source: MindDataSource, context: MeasurementContext) -> Bool {
        guard source == .watchLive || source == .healthKit else { return false }
        guard bpm > 0 && bpm <= 250 else { return false }
        guard context.conditions.allSatisfy({ $0 == .none }) else {
            MindWaveDebugLogger.log(.baseline, "heart rate not recorded: body condition declared")
            return false
        }
        if let last = document.heartRateSamples.last,
           date.timeIntervalSince(last.measuredAt) < Self.heartRateSamplingInterval {
            return false
        }
        document.heartRateSamples.append(.init(value: bpm, measuredAt: date))
        prune(now: date)
        persist()
        MindWaveDebugLogger.log(.baseline, "heart rate sample recorded count=\(document.heartRateSamples.count)")
        return true
    }

    /// 実測HRV（discreteSample）を記録する。同時刻の重複は記録しない。
    @discardableResult
    func recordHRV(_ ms: Double, at date: Date) -> Bool {
        guard ms > 0 && ms <= 500 else { return false }
        guard !document.hrvSamples.contains(where: { $0.measuredAt == date }) else { return false }
        document.hrvSamples.append(.init(value: ms, measuredAt: date))
        document.hrvSamples.sort { $0.measuredAt < $1.measuredAt }
        prune(now: max(date, document.hrvSamples.last?.measuredAt ?? date))
        persist()
        MindWaveDebugLogger.log(.baseline, "hrv sample recorded count=\(document.hrvSamples.count)")
        return true
    }

    /// 現在のベースラインを算出する
    func snapshot(now: Date, healthKitAverageHeartRate: Double?, healthKitAverageHRV: Double?) -> BaselineSnapshot {
        let window = now.addingTimeInterval(-Self.retention)
        let hrs  = document.heartRateSamples.filter { $0.measuredAt >= window && $0.measuredAt <= now.addingTimeInterval(60) }
        let hrvs = document.hrvSamples.filter { $0.measuredAt >= window && $0.measuredAt <= now.addingTimeInterval(60) }
        let calendar = Calendar(identifier: .gregorian)
        let distinctDays = Set(hrs.map { calendar.startOfDay(for: $0.measuredAt) }).count

        var snap = BaselineSnapshot.reference
        snap.collectedHeartRateCount = hrs.count
        snap.collectedHRVCount = hrvs.count

        if let avg = healthKitAverageHeartRate, avg > 0 {
            snap.heartRate = avg
            snap.heartRateOrigin = .healthKit7DayAverage
        } else if hrs.count >= Self.minHeartRateSamples && distinctDays >= Self.minHeartRateDistinctDays {
            snap.heartRate = hrs.map(\.value).reduce(0, +) / Double(hrs.count)
            snap.heartRateOrigin = .appCollectedSamples
        }

        if let avg = healthKitAverageHRV, avg > 0 {
            snap.hrv = avg
            snap.hrvOrigin = .healthKit7DayAverage
        } else if hrvs.count >= Self.minHRVSamples {
            snap.hrv = hrvs.map(\.value).reduce(0, +) / Double(hrvs.count)
            snap.hrvOrigin = .appCollectedSamples
        }
        return snap
    }

    private func prune(now: Date) {
        let window = now.addingTimeInterval(-Self.retention)
        document.heartRateSamples = Array(document.heartRateSamples.filter { $0.measuredAt >= window }.suffix(Self.maxSamplesPerMetric))
        document.hrvSamples = Array(document.hrvSamples.filter { $0.measuredAt >= window }.suffix(Self.maxSamplesPerMetric))
    }

    private func persist() {
        do {
            defaults.set(try MindWaveContract.makeEncoder().encode(document), forKey: Self.defaultsKey)
        } catch {
            MindWaveDebugLogger.log(.error, "[Baseline] encode failed: \(error)")
        }
    }
}
