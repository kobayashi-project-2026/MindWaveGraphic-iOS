// SessionContracts.swift
// Contracts
//
// ガイドセッション記録と履歴文書の JSON 契約。
// 旧形式（UserDefaults "mindwave.guideHistory.v2" の辞書配列）からの移行は GuideHistoryStore が担当する。

import Foundation

/// ガイド前後のスナップショット
nonisolated struct GuideSnapshotDTO: Codable, Equatable, Sendable {
    var capturedAt: Date
    var score: Double
    var confidence: Double
    var state: MindStateCode
    /// 心拍 bpm（null = 未計測）
    var heartRateBpm: Double?
    /// HRV SDNN ms（null = 未計測）
    var hrvSdnnMs: Double?
    var isMock: Bool
    var heartRateMeasuredAt: Date?
    var hrvMeasuredAt: Date?
    /// 取得時のデータソース（旧データは null = 不明。is_mock で Mock かどうかは判別できる）
    var source: DataSourceCode?

    enum CodingKeys: String, CodingKey {
        case capturedAt          = "captured_at"
        case score, confidence, state
        case heartRateBpm        = "heart_rate_bpm"
        case hrvSdnnMs           = "hrv_sdnn_ms"
        case isMock              = "is_mock"
        case heartRateMeasuredAt = "heart_rate_measured_at"
        case hrvMeasuredAt       = "hrv_measured_at"
        case source
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(capturedAt, forKey: .capturedAt)
        try c.encode(score, forKey: .score)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(state, forKey: .state)
        try c.encode(heartRateBpm, forKey: .heartRateBpm)
        try c.encode(hrvSdnnMs, forKey: .hrvSdnnMs)
        try c.encode(isMock, forKey: .isMock)
        try c.encode(heartRateMeasuredAt, forKey: .heartRateMeasuredAt)
        try c.encode(hrvMeasuredAt, forKey: .hrvMeasuredAt)
        try c.encode(source, forKey: .source)
    }
}

/// セッションに紐づくAIインサイトの要約（保存用）
nonisolated struct SessionInsightDTO: Codable, Equatable, Sendable {
    var title: String?
    var summary: String?
    var recommendation: String?
    /// 生成したエンジンのバージョン（例: "local-1.1"）
    var engineVersion: String?

    enum CodingKeys: String, CodingKey {
        case title, summary, recommendation
        case engineVersion = "engine_version"
    }

    var isEmpty: Bool {
        title == nil && summary == nil && recommendation == nil && engineVersion == nil
    }
}

/// ガイドセッション記録1件
nonisolated struct GuideSessionRecordDTO: Codable, Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    /// MeasurementScene.rawValue
    var scene: String
    /// GuideExercise.rawValue
    var exercise: String
    var durationSeconds: Int
    var before: GuideSnapshotDTO
    /// 再測定なし = null
    var after: GuideSnapshotDTO?
    var hrvUpdated: Bool
    var emotionMemo: String?
    /// 主観的緊張度 0〜3（SelfReportLevel.rawValue。null = 未入力）
    var selfReportBefore: Int?
    var selfReportAfter: Int?
    var aiInsight: SessionInsightDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt        = "started_at"
        case scene, exercise
        case durationSeconds  = "duration_seconds"
        case before, after
        case hrvUpdated       = "hrv_updated"
        case emotionMemo      = "emotion_memo"
        case selfReportBefore = "self_report_before"
        case selfReportAfter  = "self_report_after"
        case aiInsight        = "ai_insight"
    }

    /// Mock 計測を含む記録か（AI学習・傾向分析から除外する）
    var containsMockData: Bool {
        before.isMock || (after?.isMock ?? false)
    }
}

/// 履歴の保存文書
nonisolated struct GuideHistoryDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int = MindWaveContract.schemaVersion
    var savedAt: Date
    var records: [GuideSessionRecordDTO]
    /// 読み込み時に壊れていて読み飛ばした件数（保存はしない）
    var skippedRecordCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case savedAt       = "saved_at"
        case records
    }

    init(savedAt: Date, records: [GuideSessionRecordDTO]) {
        self.savedAt = savedAt
        self.records = records
    }

    /// 1件が壊れていても残りを読めるよう、要素ごとに decode する
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard MindWaveContract.isSupported(schemaVersion: schemaVersion) else {
            throw ContractError.unsupportedSchemaVersion(schemaVersion)
        }
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        var list = try c.nestedUnkeyedContainer(forKey: .records)
        var decoded: [GuideSessionRecordDTO] = []
        var skipped = 0
        while !list.isAtEnd {
            if let record = try? list.decode(GuideSessionRecordDTO.self) {
                decoded.append(record)
            } else {
                // 壊れた要素を読み飛ばして次へ進む
                _ = try? list.decode(DiscardedJSONValue.self)
                skipped += 1
            }
        }
        records = decoded
        skippedRecordCount = skipped
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(savedAt, forKey: .savedAt)
        try c.encode(records, forKey: .records)
    }
}

/// 読み飛ばし用（任意の JSON 値を消費する）
private nonisolated struct DiscardedJSONValue: Decodable {}

// MARK: - ドメイン ⇄ DTO 変換

extension GuideSnapshotDTO {
    init(snapshot s: GuideSnapshot) {
        self.init(
            capturedAt: s.timestamp, score: s.score, confidence: s.confidence,
            state: MindStateCode(s.state), heartRateBpm: s.heartRate, hrvSdnnMs: s.hrv,
            isMock: s.isMockData, heartRateMeasuredAt: s.heartRateSampleDate,
            hrvMeasuredAt: s.hrvSampleDate, source: s.dataSource.map(DataSourceCode.init)
        )
    }

    var domainSnapshot: GuideSnapshot {
        GuideSnapshot(
            timestamp: capturedAt, score: score, confidence: confidence, state: state.domain,
            heartRate: heartRateBpm, hrv: hrvSdnnMs, isMockData: isMock,
            heartRateSampleDate: heartRateMeasuredAt, hrvSampleDate: hrvMeasuredAt,
            dataSource: source?.domain
        )
    }
}

extension GuideSessionRecordDTO {
    init(record r: GuideSessionRecord) {
        let insight = SessionInsightDTO(
            title: r.aiInsightTitle, summary: r.aiInsightSummary,
            recommendation: r.aiInsightRecommendation, engineVersion: r.localAIVersion
        )
        self.init(
            id: r.id, startedAt: r.startedAt, scene: r.scene.rawValue, exercise: r.exercise.rawValue,
            durationSeconds: r.durationSeconds, before: GuideSnapshotDTO(snapshot: r.before),
            after: r.after.map(GuideSnapshotDTO.init(snapshot:)), hrvUpdated: r.hrvUpdated,
            emotionMemo: r.emotionMemo, selfReportBefore: r.selfReportBefore?.rawValue,
            selfReportAfter: r.selfReportAfter?.rawValue,
            aiInsight: insight.isEmpty ? nil : insight
        )
    }

    /// ドメインへ変換する。場面・エクササイズが未知の値（新しいアプリで追加された値など）の場合は nil。
    var domainRecord: GuideSessionRecord? {
        guard let scene = MeasurementScene(rawValue: scene),
              let exercise = GuideExercise(rawValue: exercise) else { return nil }
        return GuideSessionRecord(
            id: id, startedAt: startedAt, scene: scene, exercise: exercise,
            durationSeconds: durationSeconds, before: before.domainSnapshot,
            after: after?.domainSnapshot, hrvUpdated: hrvUpdated, emotionMemo: emotionMemo,
            selfReportBefore: selfReportBefore.flatMap(SelfReportLevel.init(rawValue:)),
            selfReportAfter: selfReportAfter.flatMap(SelfReportLevel.init(rawValue:)),
            aiInsightTitle: aiInsight?.title, aiInsightSummary: aiInsight?.summary,
            aiInsightRecommendation: aiInsight?.recommendation, localAIVersion: aiInsight?.engineVersion
        )
    }
}
