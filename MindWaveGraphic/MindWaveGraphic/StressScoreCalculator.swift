//
//  StressScoreCalculator.swift
//  MindWaveGraphic
//

import Foundation

/// スコア計算の出力値
struct StressScoreResult {
    /// 心拍上昇率：(currentHR - avgHR) / avgHR。正の値ほど心拍が上昇している
    let heartRateIncreaseRate: Double
    /// HRV低下率：(avgHRV - currentHRV) / avgHRV。正の値ほどHRVが低下（ストレス状態）
    let hrvDecreaseRate: Double
    /// 緊張不安定度スコア（0〜100）。50が個人平均、高いほど緊張・ストレス状態
    let stressScore: Double
}

struct StressScoreCalculator {

    /// 緊張不安定度スコアを算出する。
    /// 絶対値ではなく個人の平常時平均からの変化率を使うことで、個人差を補正する。
    ///
    /// - Parameters:
    ///   - currentHeartRate: 現在の心拍数（bpm）
    ///   - averageHeartRate: 個人の平常時平均心拍数（bpm）
    ///   - currentHRV: 現在のHRV・SDNN（ms）
    ///   - averageHRV: 個人の平常時平均HRV・SDNN（ms）
    /// - Returns: 各変化率とスコア（0〜100）を含む StressScoreResult
    static func calculate(
        currentHeartRate: Double,
        averageHeartRate: Double,
        currentHRV: Double,
        averageHRV: Double
    ) -> StressScoreResult {
        // 平均値が0以下の場合は計算不能のため中立値50を返す
        guard averageHeartRate > 0, averageHRV > 0 else {
            return StressScoreResult(heartRateIncreaseRate: 0, hrvDecreaseRate: 0, stressScore: 50)
        }

        // 心拍上昇率：平常時より高いほど正の値になる
        let hrIncreaseRate = (currentHeartRate - averageHeartRate) / averageHeartRate

        // HRV低下率：HRVはストレスで低下するため「低下した分」を正の値として扱う
        // これにより心拍上昇率と同じ方向（正 = ストレス）に揃える
        let hrvDecreaseRate = (averageHRV - currentHRV) / averageHRV

        // 2指標の平均を取り、スコアに変換
        // 平常時（両率=0）→ スコア50、緊張時（両率>0）→ スコア50超
        let raw = 50.0 + 100.0 * ((hrIncreaseRate + hrvDecreaseRate) / 2.0)

        // 0〜100にclamp
        let score = min(100.0, max(0.0, raw))

        return StressScoreResult(
            heartRateIncreaseRate: hrIncreaseRate,
            hrvDecreaseRate: hrvDecreaseRate,
            stressScore: score
        )
    }
}
