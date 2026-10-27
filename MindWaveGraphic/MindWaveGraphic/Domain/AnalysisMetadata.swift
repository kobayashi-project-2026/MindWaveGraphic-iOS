import Foundation

// 分析結果に付随するメタデータ。
// 「値がない」理由を区別し、Mock・固定値・古いデータを実測と混同しないために使う。

/// 分析時点のHRVの状態
nonisolated enum HRVStatus: String, Equatable, Sendable, CaseIterable {
    /// 鮮度内の実測HRVを使用した
    case measured
    /// 実測HRVが一度も得られていない
    case missing
    /// HRVはあるが鮮度上限を超えて古いため、スコアには使っていない
    case stale
    /// Mockモード（HRVを使わずMockスコアを直接使用）
    case notApplicable = "not_applicable"
}

/// 個人ベースライン（平常時の平均心拍・HRV）の状態
nonisolated enum BaselineStatus: String, Equatable, Sendable, CaseIterable {
    /// 本人の実測サンプルから算出した個人ベースラインを使用した
    case personal
    /// 実測サンプルが不足しており、暫定の参照値（個人の平常値ではない）を使用した
    case provisional
    /// Mockモード（ベースラインを使わない）
    case notApplicable = "not_applicable"
}

/// 分析結果に付ける付随情報。既存の MindAnalysisResult 初期化を壊さないよう、すべて既定値を持つ。
nonisolated struct AnalysisMetadata: Equatable, Sendable {
    /// 分析に使ったデータソース
    var source: MindDataSource = .unavailable
    /// 使用した Analyzer の識別子とバージョン
    var analyzerID: String = "unknown"
    var analyzerVersion: String = "0"
    /// 分析に使った実測値（nil = 未計測）
    var heartRate: Double? = nil
    var hrv: Double? = nil
    var hrvStatus: HRVStatus = .missing
    var baselineStatus: BaselineStatus = .provisional
    /// スコア算出に使ったベースライン値
    var baselineHeartRate: Double? = nil
    var baselineHRV: Double? = nil

    /// Mock由来か（学習・履歴分析から除外する判定に使う）
    var isMock: Bool { source == .mock }
}
