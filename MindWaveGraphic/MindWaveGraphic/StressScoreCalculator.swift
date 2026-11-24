//
//  StressScoreCalculator.swift
//  MindWaveGraphic
//

import Foundation

/// スコア計算の出力値
nonisolated struct StressScoreResult: Equatable, Sendable {
    /// 心拍上昇率：(currentHR - avgHR) / avgHR。正の値ほど心拍が上昇している
    let heartRateIncreaseRate: Double
    /// HRV低下率：(avgHRV - currentHRV) / avgHRV。正の値ほどHRVが低下（ゆらぎ増加）
    let hrvDecreaseRate: Double
    /// 心理的ゆらぎスコア（0〜100）。
    /// 38付近が平常時、高いほど緊張・過負荷状態。低いほど落ち着き・深呼吸状態。
    let stressScore: Double
}

nonisolated struct StressScoreCalculator {

    /// 心理的ゆらぎスコアを算出する。
    /// 個人の平常時平均からの変化率を使い個人差を補正する。
    /// オプションでMeasurementContextによる状況補正を適用できる。
    ///
    /// スコア設計:
    ///   raw = 38 + 85 × (hrIncreaseRate + hrvDecreaseRate) / 2
    ///   平常時（両率=0）→ 約38（READY相当）
    ///   軽度上昇 → 46–55（FOCUS相当）
    ///   中等度 → 60–75（ALERT相当）
    ///   高ストレス → 80–100（OVERLOAD相当）
    ///   運動・喫煙等の身体的心拍上昇はcontextOffsetで緩和する。
    ///   これは医療診断ではなく、参考値として扱う。
    ///
    /// - Parameters:
    ///   - currentHeartRate: 現在の心拍数（bpm）
    ///   - averageHeartRate: 個人の平常時平均心拍数（bpm）
    ///   - currentHRV: 現在のHRV・SDNN（ms）
    ///   - averageHRV: 個人の平常時平均HRV・SDNN（ms）
    ///   - context: 測定コンテキスト（nil = デフォルト補正なし）
    /// - Returns: 各変化率とスコア（0〜100）を含む StressScoreResult
    static func calculate(
        currentHeartRate: Double,
        averageHeartRate: Double,
        currentHRV: Double,
        averageHRV: Double,
        context: MeasurementContext? = nil
    ) -> StressScoreResult {
        // 平均値が0以下の場合は計算不能のため中立値38を返す（50から変更）
        guard averageHeartRate > 0, averageHRV > 0 else {
            return StressScoreResult(heartRateIncreaseRate: 0, hrvDecreaseRate: 0, stressScore: 38)
        }

        // 心拍上昇率：平常時より高いほど正の値になる
        let hrIncreaseRate = (currentHeartRate - averageHeartRate) / averageHeartRate

        // HRV低下率：HRVはゆらぎ増加で低下するため「低下した分」を正の値として扱う
        let hrvDecreaseRate = (averageHRV - currentHRV) / averageHRV

        // 基本スコア計算。アンカーを38に設定（旧: 50）。
        // Why: 50だと平常時に50が出てしまい、低スコア帯(0〜30)がほぼ到達不能だった。
        //      38アンカーにより、平常時に28〜45帯が出やすくなる。
        let raw = 38.0 + 85.0 * ((hrIncreaseRate + hrvDecreaseRate) / 2.0)

        // コンテキスト補正を適用（身体的心拍上昇を緊張スコアに過剰計上しない）。
        // Why: 走った後やカフェイン後の心拍上昇は精神的緊張と区別できないが、
        //      ユーザーが申告した場合は補正してより実態に近いスコアを提供する。
        let contextOffset = context?.totalScoreOffset ?? 0.0
        let adjusted = raw + contextOffset

        // 0〜100にclamp
        let score = min(100.0, max(0.0, adjusted))

        return StressScoreResult(
            heartRateIncreaseRate: hrIncreaseRate,
            hrvDecreaseRate:       hrvDecreaseRate,
            stressScore:           score
        )
    }
}

// MARK: - 急性緊張の研究用試作エンジン

/// 急性緊張の研究用試作スコア（未検証）。診断や確定的な緊張評価には使用しない。
/// S(t) = clamp(10 * Q0 + 0.5772094747906776 * (HRmean(t) - HRmean(start)), 0, 100)
/// 添付資料に記載された係数の由来（元データの再検証は未実施）：GalaxyPPG 23人、主観的ストレス水準(1〜7) ~
///   切片 + HRの安静時からの変化量(bpm) の単回帰。
///   HR係数 = 0.03463256848744 (rating points/bpm)。
///   1〜7尺度→0〜100換算で *100/6 = 0.5772094747906776 points/bpm。
/// この係数を同じ人の時間変化に転用することは未検証の仮定。
/// SDNNは更新間隔と時間窓の問題のため本版スコアには含めない。
/// 年齢・睡眠・安静時HRはこの係数の学習に使用していないので式に加えない。

nonisolated enum MWAcuteScoreStatus: String, Equatable, Sendable {
    case inactive = "inactive"
    case awaitingBaseline = "awaiting_baseline"
    case liveExperimental = "live_experimental_unvalidated"
    case staleHR = "stale_hr_holding_last_score"
    case exerciseExcluded = "exercise_excluded"
}

nonisolated struct MWAcuteScoreResult: Equatable, Sendable {
    let score: Double
    let status: MWAcuteScoreStatus
    let baselineHeartRate: Double?
    let currentMeanHeartRate: Double?
    let hrAdjustmentPoints: Double
    let coefficient: Double
}

nonisolated private struct MWTimedHR {
    let bpm: Double
    let measuredAt: Date
}

/// ViewModel内で単一セッションとして保持する。SwiftUI表示の更新はViewModel側で行う。
@MainActor
final class MWAcuteTensionEngine {
    // 添付指定の係数。以下の時間窓・サンプル数は工学的な暫定設計値。
    static let modelVersion = "galaxyppg_hr_only_anchor_exploratory_v1"
    static let hrCoefficientPointsPerBPM = 0.5772094747906776
    static let baselineSeconds: TimeInterval = 30
    static let movingAverageSeconds: TimeInterval = 30
    static let maxHRSampleAge: TimeInterval = 15
    static let minimumSamples = 3

    private var startDate: Date?
    private var initialScore: Double = 0
    private var exercisedRecently = false
    private var readings: [MWTimedHR] = []
    private var baselineHR: Double?
    private var lastLiveResult: MWAcuteScoreResult?
    private var sampleSource: String?

    var activeSource: String? { sampleSource }

    var hasActiveSession: Bool { startDate != nil }

    @discardableResult
    func begin(tensionRating: Double, exercisedRecently: Bool, at date: Date = Date()) -> Bool {
        guard tensionRating.isFinite, (0...10).contains(tensionRating), date.timeIntervalSince1970.isFinite else { return false }
        startDate = date
        initialScore = Double(tensionRating) * 10
        self.exercisedRecently = exercisedRecently
        readings = []
        baselineHR = nil
        lastLiveResult = nil
        sampleSource = nil
        return true
    }

    func finish() {
        startDate = nil
        readings = []
        baselineHR = nil
        lastLiveResult = nil
        sampleSource = nil
    }

    func pauseForExercise() { exercisedRecently = true }

    /// 実測HRと計測時刻を渡す。Mock値はこの関数へ渡さない。
    @discardableResult
    func ingestHeartRate(_ bpm: Double, measuredAt date: Date,
                         source: String = "watchLive", receivedAt now: Date = Date()) -> Bool {
        guard let startDate,
              bpm.isFinite, (35...220).contains(bpm),
              date.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              date >= startDate, date <= now,
              now.timeIntervalSince(date) <= Self.movingAverageSeconds,
              !source.isEmpty, sampleSource == nil || sampleSource == source,
              !readings.contains(where: { $0.measuredAt == date }) else { return false }
        sampleSource = source // 異なる取得経路の平均や同じ試料の二重計上を避ける。
        readings.append(MWTimedHR(bpm: bpm, measuredAt: date))
        readings.sort { $0.measuredAt < $1.measuredAt }
        let initialWindowEnd = startDate.addingTimeInterval(Self.baselineSeconds)
        let recentCutoff = now.addingTimeInterval(-Self.movingAverageSeconds)
        readings = readings.filter { $0.measuredAt <= initialWindowEnd || $0.measuredAt >= recentCutoff }
        return true
    }

    func evaluate(at now: Date = Date()) -> MWAcuteScoreResult? {
        guard let startDate, now.timeIntervalSince1970.isFinite, now >= startDate else { return nil }
        // 30秒ちょうどに新しい試料が来なくても、タイマーで基準を確定できる。
        let initialWindowEnd = startDate.addingTimeInterval(Self.baselineSeconds)
        if baselineHR == nil && now >= initialWindowEnd {
            let initial = readings.filter { $0.measuredAt <= initialWindowEnd && $0.measuredAt <= now }
            if initial.count >= Self.minimumSamples,
               let first = initial.first, let last = initial.last,
               last.measuredAt.timeIntervalSince(first.measuredAt) >= 15 {
                baselineHR = initial.map(\.bpm).reduce(0, +) / Double(initial.count)
            }
        }
        func value(_ score: Double, _ status: MWAcuteScoreStatus,
                   _ mean: Double? = nil) -> MWAcuteScoreResult {
            MWAcuteScoreResult(score: score, status: status,
                baselineHeartRate: baselineHR, currentMeanHeartRate: mean,
                hrAdjustmentPoints: score - initialScore,
                coefficient: Self.hrCoefficientPointsPerBPM)
        }
        if exercisedRecently { return value(initialScore, .exerciseExcluded) }
        guard let baselineHR else { return value(initialScore, .awaitingBaseline) }
        let fresh = readings.filter {
            let age = now.timeIntervalSince($0.measuredAt)
            return age >= 0 && age <= Self.movingAverageSeconds
        }
        let newestAge = readings.last.map { now.timeIntervalSince($0.measuredAt) } ?? .infinity
        guard newestAge >= 0, newestAge <= Self.maxHRSampleAge,
              fresh.count >= 1 else {
            if let lastLiveResult {
                return MWAcuteScoreResult(score: lastLiveResult.score,
                    status: .staleHR, baselineHeartRate: baselineHR,
                    currentMeanHeartRate: lastLiveResult.currentMeanHeartRate,
                    hrAdjustmentPoints: lastLiveResult.hrAdjustmentPoints,
                    coefficient: Self.hrCoefficientPointsPerBPM)
            }
            return value(initialScore, .staleHR)
        }
        let currentMean = fresh.map(\.bpm).reduce(0, +) / Double(fresh.count)
        let rawScore = initialScore + Self.hrCoefficientPointsPerBPM * (currentMean - baselineHR)
        let score = min(100, max(0, rawScore))
        let result = value(score, .liveExperimental, currentMean)
        lastLiveResult = result
        return result
    }
}
