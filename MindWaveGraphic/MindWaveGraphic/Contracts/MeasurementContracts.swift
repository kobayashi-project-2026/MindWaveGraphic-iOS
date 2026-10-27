// MeasurementContracts.swift
// Contracts
//
// 計測サンプル（心拍・HRV）と測定コンテキストの JSON 契約。

import Foundation

// MARK: - データソース

/// JSON 上のデータソース表記（snake_case 固定）
nonisolated enum DataSourceCode: String, Codable, Equatable, Sendable, CaseIterable {
    case mock
    case watchLive   = "watch_live"
    case healthKit   = "health_kit"
    case unavailable

    init(_ source: MindDataSource) {
        switch source {
        case .mock:        self = .mock
        case .watchLive:   self = .watchLive
        case .healthKit:   self = .healthKit
        case .unavailable: self = .unavailable
        }
    }

    var domain: MindDataSource {
        switch self {
        case .mock:        return .mock
        case .watchLive:   return .watchLive
        case .healthKit:   return .healthKit
        case .unavailable: return .unavailable
        }
    }
}

// MARK: - 計測サンプル

/// 心拍・HRV の計測サンプル1件。
/// heart_rate_bpm / hrv_sdnn_ms の null は「未計測」。JSON には null として必ず出力する。
nonisolated struct MeasurementSampleDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int = MindWaveContract.schemaVersion
    /// データソース
    var source: DataSourceCode
    /// Mock 由来か（source == mock と必ず一致する）
    var isMock: Bool
    /// サンプルの代表時刻
    var measuredAt: Date
    /// 心拍数 bpm（null = 未計測）
    var heartRateBpm: Double?
    /// HRV SDNN ms（null = 未計測）
    var hrvSdnnMs: Double?
    /// 心拍サンプル自体の記録時刻（null = 不明 / 未計測）
    var heartRateMeasuredAt: Date?
    /// HRV サンプル自体の記録時刻（null = 不明 / 未計測）
    var hrvMeasuredAt: Date?
    /// Mock モード時のみ: 計算済みスコア 0〜100（実測では必ず null）
    var mockScore: Double?

    enum CodingKeys: String, CodingKey {
        case schemaVersion       = "schema_version"
        case source
        case isMock              = "is_mock"
        case measuredAt          = "measured_at"
        case heartRateBpm        = "heart_rate_bpm"
        case hrvSdnnMs           = "hrv_sdnn_ms"
        case heartRateMeasuredAt = "heart_rate_measured_at"
        case hrvMeasuredAt       = "hrv_measured_at"
        case mockScore           = "mock_score"
    }

    init(source: DataSourceCode, measuredAt: Date, heartRateBpm: Double?, hrvSdnnMs: Double?,
         heartRateMeasuredAt: Date? = nil, hrvMeasuredAt: Date? = nil, mockScore: Double? = nil) {
        self.source              = source
        self.isMock              = source == .mock
        self.measuredAt          = measuredAt
        self.heartRateBpm        = heartRateBpm
        self.hrvSdnnMs           = hrvSdnnMs
        self.heartRateMeasuredAt = heartRateMeasuredAt
        self.hrvMeasuredAt       = hrvMeasuredAt
        self.mockScore           = mockScore
    }

    /// 未計測を null として明示的に出力する（キー省略と区別するため）
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(source, forKey: .source)
        try c.encode(isMock, forKey: .isMock)
        try c.encode(measuredAt, forKey: .measuredAt)
        try c.encode(heartRateBpm, forKey: .heartRateBpm)
        try c.encode(hrvSdnnMs, forKey: .hrvSdnnMs)
        try c.encode(heartRateMeasuredAt, forKey: .heartRateMeasuredAt)
        try c.encode(hrvMeasuredAt, forKey: .hrvMeasuredAt)
        try c.encode(mockScore, forKey: .mockScore)
    }

    /// 値域と整合性の検証
    func validate() throws {
        guard MindWaveContract.isSupported(schemaVersion: schemaVersion) else {
            throw ContractError.unsupportedSchemaVersion(schemaVersion)
        }
        guard isMock == (source == .mock) else {
            throw ContractError.inconsistent("is_mock と source が一致しない")
        }
        if let hr = heartRateBpm, !(hr > 0 && hr <= 250) {
            throw ContractError.outOfRange(field: "heart_rate_bpm", value: hr)
        }
        if let hrv = hrvSdnnMs, !(hrv > 0 && hrv <= 500) {
            throw ContractError.outOfRange(field: "hrv_sdnn_ms", value: hrv)
        }
        if let score = mockScore {
            guard isMock else { throw ContractError.inconsistent("実測サンプルに mock_score がある") }
            guard (0...100).contains(score) else { throw ContractError.outOfRange(field: "mock_score", value: score) }
        }
    }
}

extension MeasurementSampleDTO {
    /// ドメインの MindWaveSample から生成する
    init(sample: MindWaveSample, heartRateMeasuredAt: Date? = nil, hrvMeasuredAt: Date? = nil) {
        self.init(
            source: DataSourceCode(sample.source),
            measuredAt: sample.timestamp,
            heartRateBpm: sample.heartRate,
            hrvSdnnMs: sample.hrv,
            heartRateMeasuredAt: heartRateMeasuredAt,
            hrvMeasuredAt: hrvMeasuredAt,
            mockScore: sample.source == .mock ? sample.contextScore : nil
        )
    }

    /// ドメインの MindWaveSample へ変換する
    var domainSample: MindWaveSample {
        MindWaveSample(
            heartRate: heartRateBpm,
            hrv: hrvSdnnMs,
            contextScore: isMock ? mockScore : nil,
            source: source.domain,
            timestamp: measuredAt
        )
    }
}

// MARK: - 測定コンテキスト

/// 測定前に選択した場面・身体状態
nonisolated struct MeasurementContextDTO: Codable, Equatable, Sendable {
    /// 場面（ContextScene.rawValue: calm / interview / sports / important / work / other）
    var scene: String
    /// 身体状態（BodyCondition.rawValue の配列。昇順ソート。"none" は空配列で表す）
    var bodyConditions: [String]
    /// スコア補正値の合計（参考情報。読み込み時は再計算するため信頼しない）
    var totalScoreOffset: Double

    enum CodingKeys: String, CodingKey {
        case scene
        case bodyConditions   = "body_conditions"
        case totalScoreOffset = "total_score_offset"
    }

    init(context: MeasurementContext) {
        scene            = context.scene.rawValue
        bodyConditions   = context.conditions.filter { $0 != .none }.map(\.rawValue).sorted()
        totalScoreOffset = context.totalScoreOffset
    }

    /// ドメインへ変換する。未知の値は安全側（calm / 特になし）に倒す。
    var domainContext: MeasurementContext {
        var ctx = MeasurementContext()
        ctx.scene = ContextScene(rawValue: scene) ?? .calm
        let conditions = Set(bodyConditions.compactMap(BodyCondition.init(rawValue:)))
        ctx.conditions = conditions.isEmpty ? [.none] : conditions
        return ctx
    }
}
