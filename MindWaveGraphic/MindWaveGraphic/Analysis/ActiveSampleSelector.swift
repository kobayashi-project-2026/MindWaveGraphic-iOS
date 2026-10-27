// ActiveSampleSelector.swift
// Analysis
//
// 受信済みの Mock / Watch / HealthKit の値から「いまスコアに使う1サンプル」を選ぶ純粋ロジック。
// MindWaveViewModel.selectActiveSample の優先順位を維持したまま、鮮度判定を明示的に行う。
//
// 優先順位（既存どおり）:
//   1. Mock モード ON → Mock サンプル
//   2. Watch 心拍が watchLiveExpiry（15秒）以内 → Watch（HRV は HealthKit から補完）
//   3. HealthKit の心拍・HRV（それぞれ鮮度内のものだけ）
//   4. いずれもない → nil（グラフィックは neutral）
//
// 鮮度規則（追加）:
// - HealthKit 心拍は 30 分以内（HealthKitManager.fetchBestCurrentHeartRate の最大探索幅と同じ）
// - HRV は 6 時間以内。Apple Watch の HRV 自動計測は数時間おきのため、短くしすぎると常に未使用になる
// - 鮮度切れの値は「計測値」として使わず、hrvStatus = .stale として記録する

import Foundation

/// 計測時刻付きの値
nonisolated struct TimedValue: Equatable, Sendable {
    let value: Double
    let measuredAt: Date
}

/// 選択の入力
nonisolated struct SampleSelectionInput: Sendable {
    var isMockMode: Bool
    var mock: MindWaveSample?
    /// Watch から受信した最新心拍サンプル（hrv は常に nil）
    var watch: MindWaveSample?
    /// HealthKit から取得した最新心拍（実サンプル）
    var healthKitHeartRate: TimedValue?
    /// HealthKit から取得した最新 HRV（実サンプル discreteSample のみ）
    var healthKitHRV: TimedValue?
    var now: Date
}

/// 選択結果
nonisolated struct SelectedSample: Equatable, Sendable {
    let sample: MindWaveSample
    let hrvStatus: HRVStatus
    let heartRateMeasuredAt: Date?
    let hrvMeasuredAt: Date?
}

nonisolated enum ActiveSampleSelector {

    /// Watch ライブデータの有効期限（MindWaveViewModel.watchLiveExpirySeconds と同値）
    static let watchLiveExpiry: TimeInterval = 15
    /// HealthKit 心拍を「現在値」とみなす上限
    static let healthKitHeartRateFreshness: TimeInterval = 30 * 60
    /// HRV を「現在値」とみなす上限
    static let hrvFreshness: TimeInterval = 6 * 60 * 60

    static func select(_ input: SampleSelectionInput) -> SelectedSample? {
        if input.isMockMode {
            guard let mock = input.mock else { return nil }
            return SelectedSample(sample: mock, hrvStatus: .notApplicable,
                                  heartRateMeasuredAt: mock.heartRate == nil ? nil : mock.timestamp,
                                  hrvMeasuredAt: nil)
        }

        let freshHRV = fresh(input.healthKitHRV, limit: hrvFreshness, now: input.now)
        let hrvStatus: HRVStatus = freshHRV != nil ? .measured : (input.healthKitHRV != nil ? .stale : .missing)

        if let watch = input.watch, isFresh(watch.timestamp, limit: watchLiveExpiry, now: input.now) {
            // Watch に HRV はないため、鮮度内の HealthKit HRV で補完する（source は watchLive を維持）
            return SelectedSample(
                sample: MindWaveSample(heartRate: watch.heartRate, hrv: freshHRV?.value, contextScore: nil,
                                       source: .watchLive, timestamp: watch.timestamp),
                hrvStatus: hrvStatus,
                heartRateMeasuredAt: watch.timestamp,
                hrvMeasuredAt: freshHRV?.measuredAt
            )
        }

        let freshHR = fresh(input.healthKitHeartRate, limit: healthKitHeartRateFreshness, now: input.now)
        guard freshHR != nil || freshHRV != nil else { return nil }
        let timestamp = [freshHR?.measuredAt, freshHRV?.measuredAt].compactMap { $0 }.max() ?? input.now
        return SelectedSample(
            sample: MindWaveSample(heartRate: freshHR?.value, hrv: freshHRV?.value, contextScore: nil,
                                   source: .healthKit, timestamp: timestamp),
            hrvStatus: hrvStatus,
            heartRateMeasuredAt: freshHR?.measuredAt,
            hrvMeasuredAt: freshHRV?.measuredAt
        )
    }

    private static func isFresh(_ date: Date, limit: TimeInterval, now: Date) -> Bool {
        // 未来時刻（端末間の時計ずれ）は 60 秒まで許容する
        let age = now.timeIntervalSince(date)
        return age <= limit && age >= -60
    }

    private static func fresh(_ value: TimedValue?, limit: TimeInterval, now: Date) -> TimedValue? {
        guard let value, isFresh(value.measuredAt, limit: limit, now: now) else { return nil }
        return value
    }
}
