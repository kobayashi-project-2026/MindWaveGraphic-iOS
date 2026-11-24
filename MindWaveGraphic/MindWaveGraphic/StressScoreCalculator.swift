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
