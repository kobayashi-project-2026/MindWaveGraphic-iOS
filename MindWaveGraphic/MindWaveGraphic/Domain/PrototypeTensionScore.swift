// PrototypeTensionScore.swift
// Domain
//
// 主観評価＋HR・SDNN による「試作の緊張スコア」（検証用の表示式。医学的に妥当性が確立された推定器ではない）。
//
//   S(t) = clip( S0 + 0.77 × (HRt − HR0) − 0.57 × (SDNNt − SDNN0), 0, 100 )
//
//   S0    : 本人が申告した初期緊張スコア（0〜100。Mind Wave Graphic の試作上の尺度）
//   HR0   : 計測開始時の基準心拍数 / HRt  : 時刻 t の心拍数
//   SDNN0 : 計測開始時の基準 SDNN    / SDNNt: 時刻 t の SDNN
//
// 係数 0.77・0.57 は 2026-11-11 に利用者が指定した試作の値（変更しない）。
// 資料（10月21日）の GalaxyPPG 23 人の回帰式 ŷ = 5.7815 + 0.04617×ΔHR − 0.03440×SDNN は、SDNN の絶対値を使う別の式で、
// R² = 0.234 と説明力も限られる。この試作式と同じ検証済みモデルとして扱わない。
//
// 既存の StressScoreCalculator（stress_score_calculator_v1）は変更しない。結果には必ずモデルのバージョンを付け、
// 過去の記録がどの方式によるものかを区別できるようにする。
//
// 欠損の扱い（0 と混同しない・値を作らない）:
// - S0 がない → スコアを出さない（unavailable）
// - HR が欠損・古い・異常 → HR の補正を計算しない（項は nil）
// - SDNN が欠損・古い・異常 → SDNN の補正を計算しない
// - 両方の補正がない → 本人の申告スコアを参考として返す（subjective_only）
// - 片方だけ → 部分的な情報であることを状態で示す（partial_hr_only / partial_sdnn_only）

import Foundation

/// スコアの計算方式（記録・表示・JSON の model_version に使う）
nonisolated enum TensionScoreModel: String, Codable, Equatable, Sendable {
    /// 既存の StressScoreCalculator（HR・HRV の変化率と身体状態の補正）。過去の記録はすべてこの方式
    case legacyStressScoreV1 = "stress_score_calculator_v1"
    /// 主観評価＋HR・SDNN の試作式（2026-11-11）
    case subjectiveHRSDNNPrototypeV1 = "subjective_hr_sdnn_prototype_v1"

    var displayName: String {
        switch self {
        case .legacyStressScoreV1:          return "従来の計算方式（HR・HRV の変化率）"
        case .subjectiveHRSDNNPrototypeV1:  return "試作の計算方式（本人の評価＋HR・SDNN）"
        }
    }
}

/// 時刻つきの測定値（欠損は nil で表し、0 を入れない）
nonisolated struct TimedReading: Equatable, Sendable {
    let value: Double
    let measuredAt: Date
}

nonisolated struct PrototypeTensionInput: Equatable, Sendable {
    /// 本人が申告した初期緊張スコア S0（0〜100）。未回答は nil
    var subjectiveBaseline: Double?
    var baselineHR: TimedReading?
    var currentHR: TimedReading?
    var baselineSDNN: TimedReading?
    var currentSDNN: TimedReading?
    /// 計算する時刻（古さの判定に使う）
    var now: Date
}

nonisolated struct PrototypeTensionResult: Equatable, Sendable {
    nonisolated enum Status: String, Codable, Equatable, Sendable {
        /// HR・SDNN の両方の補正を含む
        case complete
        /// HR の補正だけ（SDNN は欠損・古い・異常）
        case partialHROnly = "partial_hr_only"
        /// SDNN の補正だけ
        case partialSDNNOnly = "partial_sdnn_only"
        /// 補正なし。本人の申告スコアをそのまま参考として表示
        case subjectiveOnly = "subjective_only"
        /// 本人の申告がないためスコアを出さない
        case unavailable
    }

    /// 0〜100。unavailable のときは nil（0 にしない）
    let score: Double?
    let status: Status
    let model: TensionScoreModel
    let subjectiveBaseline: Double?
    /// 0.77 × (HRt − HR0)。計算しなかった場合は nil
    let hrTerm: Double?
    /// −0.57 × (SDNNt − SDNN0)。計算しなかった場合は nil
    let sdnnTerm: Double?
    /// 補正に使わなかった理由（診断・表示用。例: "hr_missing", "sdnn_stale"）
    let excluded: [String]
    /// 計算に使った HR・SDNN の測定時刻（表示用）
    let hrMeasuredAt: Date?
    let sdnnMeasuredAt: Date?

    /// 画面の短い説明（暫定・部分情報であることを伝える）
    var statusLabel: String {
        switch status {
        case .complete:        return "本人の評価＋心拍・SDNN（試作）"
        case .partialHROnly:   return "本人の評価＋心拍のみ（SDNN なし・暫定）"
        case .partialSDNNOnly: return "本人の評価＋SDNN のみ（心拍なし・暫定）"
        case .subjectiveOnly:  return "本人の評価のみ（生体情報なし・参考）"
        case .unavailable:     return "本人の評価がないため表示できません"
        }
    }
}

nonisolated enum PrototypeTensionScore {
    static let model = TensionScoreModel.subjectiveHRSDNNPrototypeV1
    static let hrCoefficient = 0.77
    static let sdnnCoefficient = 0.57

    /// 値の妥当な範囲（範囲外は異常値として補正に使わない）
    static let validHR: ClosedRange<Double> = 25...250
    static let validSDNN: ClosedRange<Double> = 1...300
    /// 最新値として使える古さ。HR は届くたびに更新されるため短く、SDNN は約 120 秒間隔の更新を参考に余裕をもたせる
    static let maxHRAge: TimeInterval = 60
    static let maxSDNNAge: TimeInterval = 600

    static func calculate(_ input: PrototypeTensionInput) -> PrototypeTensionResult {
        guard let s0 = input.subjectiveBaseline, s0.isFinite, (0...100).contains(s0) else {
            return PrototypeTensionResult(score: nil, status: .unavailable, model: model, subjectiveBaseline: nil,
                                          hrTerm: nil, sdnnTerm: nil, excluded: ["subjective_missing"],
                                          hrMeasuredAt: nil, sdnnMeasuredAt: nil)
        }
        var excluded: [String] = []
        let hr = delta(input.baselineHR, input.currentHR, valid: validHR, maxAge: maxHRAge, now: input.now, name: "hr", excluded: &excluded)
        let sdnn = delta(input.baselineSDNN, input.currentSDNN, valid: validSDNN, maxAge: maxSDNNAge, now: input.now, name: "sdnn", excluded: &excluded)
        let hrTerm = hr.map { hrCoefficient * $0 }
        let sdnnTerm = sdnn.map { -sdnnCoefficient * $0 }
        let raw = s0 + (hrTerm ?? 0) + (sdnnTerm ?? 0)
        let status: PrototypeTensionResult.Status
        switch (hrTerm != nil, sdnnTerm != nil) {
        case (true, true):   status = .complete
        case (true, false):  status = .partialHROnly
        case (false, true):  status = .partialSDNNOnly
        case (false, false): status = .subjectiveOnly
        }
        return PrototypeTensionResult(score: min(100, max(0, raw)), status: status, model: model, subjectiveBaseline: s0,
                                      hrTerm: hrTerm, sdnnTerm: sdnnTerm, excluded: excluded,
                                      hrMeasuredAt: hrTerm == nil ? nil : input.currentHR?.measuredAt,
                                      sdnnMeasuredAt: sdnnTerm == nil ? nil : input.currentSDNN?.measuredAt)
    }

    /// 現在値 − 基準値。欠損・異常・古い・基準より前の測定値なら nil（理由を excluded に記録）
    private static func delta(_ baseline: TimedReading?, _ current: TimedReading?, valid: ClosedRange<Double>,
                              maxAge: TimeInterval, now: Date, name: String, excluded: inout [String]) -> Double? {
        guard let baseline, let current else { excluded.append("\(name)_missing"); return nil }
        guard baseline.value.isFinite, current.value.isFinite, valid.contains(baseline.value), valid.contains(current.value) else {
            excluded.append("\(name)_invalid"); return nil
        }
        // 基準より前の値を「時刻 t の値」として使わない（古い値と新しい値を同じ時刻の情報として扱わない）
        guard current.measuredAt >= baseline.measuredAt else { excluded.append("\(name)_older_than_baseline"); return nil }
        guard now.timeIntervalSince(current.measuredAt) <= maxAge else { excluded.append("\(name)_stale"); return nil }
        return current.value - baseline.value
    }
}

// MARK: - 比較・表示

nonisolated enum TensionScoreComparison {
    /// 改善前後のスコアの比較文。計算方式が違えば、数値を直接比べず違いを明示する
    static func describe(before: (score: Double?, model: TensionScoreModel),
                         after: (score: Double?, model: TensionScoreModel)) -> String {
        guard let b = before.score, let a = after.score else { return "前後どちらかのスコアがないため、比較できません。" }
        guard before.model == after.model else {
            return "前後で計算方式が違うため（\(before.model.displayName) と \(after.model.displayName)）、数値を直接比べられません。"
        }
        let d = Int((a - b).rounded())
        return d == 0 ? "スコアは前後で同じくらいです（\(Int(b.rounded()))）。"
                      : "スコアは \(Int(b.rounded())) → \(Int(a.rounded()))（\(d > 0 ? "+" : "")\(d)）。心拍などの変化は、気持ちの変化と同じとは限りません。"
    }
}

/// 送信用 JSON の evaluation（資料「10月21日 MindWave 送信用 JSON 構造の仕様案」の ④）。測定できない値は null
nonisolated struct TensionEvaluationDTO: Codable, Equatable, Sendable {
    var stressScore: Double?
    var state: String?
    var scoreStatus: String
    var modelVersion: String

    enum CodingKeys: String, CodingKey {
        case stressScore = "stress_score", state
        case scoreStatus = "score_status", modelVersion = "model_version"
    }

    /// 欠損は省略せず null として書き出す（資料の「測定できない値は null」）
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stressScore, forKey: .stressScore)
        try c.encode(state, forKey: .state)
        try c.encode(scoreStatus, forKey: .scoreStatus)
        try c.encode(modelVersion, forKey: .modelVersion)
    }

    init(_ result: PrototypeTensionResult) {
        stressScore = result.score.map { ($0 * 100).rounded() / 100 }
        state = nil
        scoreStatus = result.status.rawValue
        modelVersion = result.model.rawValue
    }
}
