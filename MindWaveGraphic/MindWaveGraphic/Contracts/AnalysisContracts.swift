// AnalysisContracts.swift
// Contracts
//
// ストレス（緊張不安定度）スコアの分析結果とグラフィック入力の JSON 契約。
// スコアは医学的診断ではなく参考値。is_medical_diagnosis は常に false。

import Foundation

/// JSON 上の状態表記
nonisolated enum MindStateCode: String, Codable, Equatable, Sendable, CaseIterable {
    case underAroused   = "under_aroused"
    case optimalTension = "optimal_tension"
    case overTense      = "over_tense"

    init(_ state: MindState) {
        switch state {
        case .underAroused:   self = .underAroused
        case .optimalTension: self = .optimalTension
        case .overTense:      self = .overTense
        }
    }

    var domain: MindState {
        switch self {
        case .underAroused:   return .underAroused
        case .optimalTension: return .optimalTension
        case .overTense:      return .overTense
        }
    }
}

/// 分析に使った入力の要約
nonisolated struct AnalysisInputsDTO: Codable, Equatable, Sendable {
    /// 心拍 bpm（null = 未計測）
    var heartRateBpm: Double?
    /// HRV SDNN ms（null = 未計測、または stale でスコアに使っていない）
    var hrvSdnnMs: Double?
    /// measured / missing / stale / not_applicable
    var hrvStatus: String
    /// personal / provisional / not_applicable
    var baselineStatus: String
    /// スコア算出に使った平常時心拍・HRV（null = 使っていない）
    var baselineHeartRateBpm: Double?
    var baselineHrvSdnnMs: Double?

    enum CodingKeys: String, CodingKey {
        case heartRateBpm         = "heart_rate_bpm"
        case hrvSdnnMs            = "hrv_sdnn_ms"
        case hrvStatus            = "hrv_status"
        case baselineStatus       = "baseline_status"
        case baselineHeartRateBpm = "baseline_heart_rate_bpm"
        case baselineHrvSdnnMs    = "baseline_hrv_sdnn_ms"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(heartRateBpm, forKey: .heartRateBpm)
        try c.encode(hrvSdnnMs, forKey: .hrvSdnnMs)
        try c.encode(hrvStatus, forKey: .hrvStatus)
        try c.encode(baselineStatus, forKey: .baselineStatus)
        try c.encode(baselineHeartRateBpm, forKey: .baselineHeartRateBpm)
        try c.encode(baselineHrvSdnnMs, forKey: .baselineHrvSdnnMs)
    }
}

/// 分析結果1件
nonisolated struct AnalysisResultDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int = MindWaveContract.schemaVersion
    var analyzerId: String
    var analyzerVersion: String
    /// 元サンプルの時刻
    var analyzedAt: Date
    var source: DataSourceCode
    var isMock: Bool
    /// 緊張不安定度スコア 0〜100
    var tensionScore: Double
    /// 推定の確からしさ 0〜1
    var confidence: Double
    var state: MindStateCode
    var inputs: AnalysisInputsDTO
    var context: MeasurementContextDTO?
    /// 医学的診断ではないことの明示（常に false）
    var isMedicalDiagnosis: Bool = false

    enum CodingKeys: String, CodingKey {
        case schemaVersion      = "schema_version"
        case analyzerId         = "analyzer_id"
        case analyzerVersion    = "analyzer_version"
        case analyzedAt         = "analyzed_at"
        case source
        case isMock             = "is_mock"
        case tensionScore       = "tension_score"
        case confidence
        case state
        case inputs
        case context
        case isMedicalDiagnosis = "is_medical_diagnosis"
    }

    func validate() throws {
        guard MindWaveContract.isSupported(schemaVersion: schemaVersion) else {
            throw ContractError.unsupportedSchemaVersion(schemaVersion)
        }
        guard (0...100).contains(tensionScore) else { throw ContractError.outOfRange(field: "tension_score", value: tensionScore) }
        guard (0...1).contains(confidence) else { throw ContractError.outOfRange(field: "confidence", value: confidence) }
        guard isMock == (source == .mock) else { throw ContractError.inconsistent("is_mock と source が一致しない") }
        guard !isMedicalDiagnosis else { throw ContractError.inconsistent("is_medical_diagnosis は常に false") }
    }
}

extension AnalysisResultDTO {
    init(result: MindAnalysisResult, context: MeasurementContext?) {
        let m = result.metadata
        self.init(
            analyzerId: m.analyzerID,
            analyzerVersion: m.analyzerVersion,
            analyzedAt: result.timestamp,
            source: DataSourceCode(m.source),
            isMock: m.isMock,
            tensionScore: result.tensionScore,
            confidence: result.confidence,
            state: MindStateCode(result.state),
            inputs: AnalysisInputsDTO(
                heartRateBpm: m.heartRate,
                hrvSdnnMs: m.hrv,
                hrvStatus: m.hrvStatus.rawValue,
                baselineStatus: m.baselineStatus.rawValue,
                baselineHeartRateBpm: m.baselineHeartRate,
                baselineHrvSdnnMs: m.baselineHRV
            ),
            context: context.map(MeasurementContextDTO.init(context:))
        )
    }
}

/// グラフィックチームへ渡す入力（GraphicInput と同じ3項目）
nonisolated struct GraphicInputDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int = MindWaveContract.schemaVersion
    var score: Double
    var confidence: Double
    var state: MindStateCode

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case score, confidence, state
    }

    init(input: GraphicInput) {
        score      = input.score
        confidence = input.confidence
        state      = MindStateCode(input.state)
    }

    /// 値域外は clamp してドメインへ変換する（グラフィック側で範囲外を扱わなくてよいように）
    var domainInput: GraphicInput {
        GraphicInput(
            score: min(100, max(0, score)),
            confidence: min(1, max(0, confidence)),
            state: state.domain
        )
    }
}
