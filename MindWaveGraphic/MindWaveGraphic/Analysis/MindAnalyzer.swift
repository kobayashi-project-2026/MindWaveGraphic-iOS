// MindAnalyzer.swift
// Analysis
//
// 「選ばれたサンプル → 緊張不安定度スコア」の評価方式を差し替え可能にするインターフェース。
// 新しい評価方式（例: HRV のみ・機械学習モデル・サーバー評価）を追加するときは
// MindAnalyzer に準拠した型を作り、MindWaveViewModel(analyzer:) に渡す。既存の型は変更しない。

import Foundation

/// Analyzer への入力
nonisolated struct AnalyzerInput: Sendable {
    let selected: SelectedSample
    let baseline: BaselineSnapshot
    let context: MeasurementContext
    /// Mock モード時の確からしさ（デバッグ画面のスライダー値）
    let mockConfidence: Double
}

/// 評価方式のインターフェース
nonisolated protocol MindAnalyzer: Sendable {
    /// 結果 JSON の analyzer_id に入る識別子
    var analyzerID: String { get }
    var analyzerVersion: String { get }
    func analyze(_ input: AnalyzerInput) -> MindAnalysisResult
}

/// 現行方式: StressScoreCalculator（docs/FORMULA.md）をそのまま使う。
///
/// 既存の MindWaveViewModel.reevaluateActiveSource と同一の計算になるよう実装している:
/// - Mock: contextScore があればそのまま、なければサンプルの心拍・HRV と参照ベースラインで算出
/// - 実測: HRV がないときは averageHRV=0 を渡す（計算式の guard により中立値 38 になる＝既存挙動）
/// - 確からしさ: Mock=スライダー値 / Watch 0.75(HRVあり)・0.50 / HealthKit 0.65・0.40
///
/// 既存挙動から変えた点は1つだけ:
/// - 実測で心拍が未計測（HealthKit の HRV のみ）の場合、以前は直前の currentHeartRate（デモ初期値の場合あり）を
///   使っていた。現在は心拍項を平常と同じ（ベースライン値）として扱い、metadata.heartRate = nil で記録する。
nonisolated struct StressScoreAnalyzerV1: MindAnalyzer {
    let analyzerID = "stress-score-v1"
    let analyzerVersion = "1.0"

    func analyze(_ input: AnalyzerInput) -> MindAnalysisResult {
        let sample = input.selected.sample
        var meta = AnalysisMetadata()
        meta.source = sample.source
        meta.analyzerID = analyzerID
        meta.analyzerVersion = analyzerVersion
        meta.heartRate = sample.heartRate
        meta.hrv = sample.hrv
        meta.hrvStatus = input.selected.hrvStatus

        let rawScore: Double
        let confidence: Double
        if sample.source == .mock {
            meta.baselineStatus = .notApplicable
            if let score = sample.contextScore {
                rawScore = score
            } else {
                // デモシナリオ（loadDemoScenario）: 参照ベースラインで算出
                let ref = BaselineSnapshot.reference
                rawScore = StressScoreCalculator.calculate(
                    currentHeartRate: sample.heartRate ?? ref.heartRate,
                    averageHeartRate: ref.heartRate,
                    currentHRV: sample.hrv ?? 0,
                    averageHRV: sample.hrv != nil ? ref.hrv : 0,
                    context: input.context
                ).stressScore
            }
            confidence = input.mockConfidence
        } else {
            let usesHRV = sample.hrv != nil
            meta.baselineStatus = input.baseline.status(usesHRV: usesHRV)
            meta.baselineHeartRate = input.baseline.heartRate
            meta.baselineHRV = usesHRV ? input.baseline.hrv : nil
            rawScore = StressScoreCalculator.calculate(
                currentHeartRate: sample.heartRate ?? input.baseline.heartRate,
                averageHeartRate: input.baseline.heartRate,
                currentHRV: sample.hrv ?? 0,
                averageHRV: usesHRV ? input.baseline.hrv : 0,
                context: input.context
            ).stressScore
            switch sample.source {
            case .watchLive: confidence = usesHRV ? 0.75 : 0.50
            case .healthKit: confidence = usesHRV ? 0.65 : 0.40
            default:         confidence = 0
            }
        }

        let score = min(100, max(0, rawScore))
        return MindAnalysisResult(
            tensionScore: score,
            confidence: min(1, max(0, confidence)),
            state: MindState.from(score: score),
            timestamp: sample.timestamp,
            metadata: meta
        )
    }
}
