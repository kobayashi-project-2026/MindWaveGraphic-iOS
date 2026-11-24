// InsightContracts.swift
// Contracts
//
// iOS アプリ ⇄ 自前APIサーバー（server/）間の AIインサイト JSON 契約。
// OpenAI API はサーバー側だけが呼ぶ。iOS は OpenAI の形式を知らない。
//
// データ最小化の方針:
// - 送るのは「ガイド1回分の要約」だけ。生の時系列・HRV実数値・メモ本文・日時・端末ID・氏名・メールは送らない
// - 心拍は整数に丸め、HRV は増減の方向（up/down/flat/unknown）だけを送る
// - Mock データを含むセッションは送信しない（request 生成時に拒否する）

import Foundation

// MARK: - リクエスト

/// 外部送信の同意情報
nonisolated struct InsightConsentDTO: Codable, Equatable, Sendable {
    /// 外部AIへの要約送信に同意済みか（false のリクエストはサーバーが拒否する）
    var externalAIConsented: Bool
    /// 同意した設定のバージョン（同意文言を変えたら上げる）
    var consentVersion: Int

    enum CodingKeys: String, CodingKey {
        case externalAIConsented = "external_ai_consented"
        case consentVersion      = "consent_version"
    }
}

/// ガイド前後の要約（丸め済み）
nonisolated struct InsightMeasurementSummaryDTO: Codable, Equatable, Sendable {
    var state: MindStateCode
    /// スコア 0〜100（整数に丸め）
    var score: Int
    /// 心拍 bpm（整数に丸め。null = 未計測）
    var heartRateBpm: Int?

    enum CodingKeys: String, CodingKey {
        case state, score
        case heartRateBpm = "heart_rate_bpm"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state, forKey: .state)
        try c.encode(score, forKey: .score)
        try c.encode(heartRateBpm, forKey: .heartRateBpm)
    }
}

/// HRV の変化方向
nonisolated enum HRVTrendCode: String, Codable, Equatable, Sendable {
    case up, down, flat, unknown
}

/// セッション要約
nonisolated struct InsightSessionSummaryDTO: Codable, Equatable, Sendable {
    /// MeasurementScene.rawValue
    var scene: String
    /// GuideExercise.rawValue
    var exercise: String
    var durationSeconds: Int
    var completed: Bool
    var before: InsightMeasurementSummaryDTO
    /// 再測定なし = null
    var after: InsightMeasurementSummaryDTO?
    var hrvTrend: HRVTrendCode
    /// 主観的緊張度 0〜3（null = 未入力）
    var selfReportBefore: Int?
    var selfReportAfter: Int?
    /// 計測の確からしさ 0〜1（小数1桁に丸め）
    var confidence: Double

    enum CodingKeys: String, CodingKey {
        case scene, exercise
        case durationSeconds  = "duration_seconds"
        case completed, before, after
        case hrvTrend         = "hrv_trend"
        case selfReportBefore = "self_report_before"
        case selfReportAfter  = "self_report_after"
        case confidence
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scene, forKey: .scene)
        try c.encode(exercise, forKey: .exercise)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(completed, forKey: .completed)
        try c.encode(before, forKey: .before)
        try c.encode(after, forKey: .after)
        try c.encode(hrvTrend, forKey: .hrvTrend)
        try c.encode(selfReportBefore, forKey: .selfReportBefore)
        try c.encode(selfReportAfter, forKey: .selfReportAfter)
        try c.encode(confidence, forKey: .confidence)
    }
}

/// POST /v1/insights のリクエスト本文
nonisolated struct InsightRequestDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int = MindWaveContract.schemaVersion
    /// 冪等性・ログ突合せ用のランダムID（ユーザーを特定しない）
    var requestId: UUID
    /// 応答言語（現在は "ja-JP" 固定）
    var locale: String = "ja-JP"
    var consent: InsightConsentDTO
    var session: InsightSessionSummaryDTO

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId     = "request_id"
        case locale, consent, session
    }
}

// MARK: - レスポンス

/// 表示トーン（AIDisplayTone と対応）
nonisolated enum InsightToneCode: String, Codable, Equatable, Sendable, CaseIterable {
    case calm, focus, alert, ovld
}

/// インサイト本文
nonisolated struct InsightBodyDTO: Codable, Equatable, Sendable {
    var title: String
    var summary: String
    var analysis: String
    var recommendation: String
    var nextAction: String
    var caution: String
    var confidenceLabel: String
    var tone: InsightToneCode

    enum CodingKeys: String, CodingKey {
        case title, summary, analysis, recommendation
        case nextAction      = "next_action"
        case caution
        case confidenceLabel = "confidence_label"
        case tone
    }
}

/// POST /v1/insights のレスポンス本文
nonisolated struct InsightResponseDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var requestId: UUID
    /// "openai" など、生成したプロバイダ
    var provider: String
    /// 使用モデル名（サーバーが返す。表示・記録用）
    var model: String?
    var generatedAt: Date
    var insight: InsightBodyDTO

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId     = "request_id"
        case provider, model
        case generatedAt   = "generated_at"
        case insight
    }
}

/// サーバーのエラー応答本文
nonisolated struct InsightErrorDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var requestId: UUID?
    var error: String
    var message: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId     = "request_id"
        case error, message
    }
}

// MARK: - 検証

/// AI応答の内容検証。サーバー（server/src/contract.ts の validateInsightBody）と同じ規則をクライアントでも再確認する。
nonisolated enum InsightValidation {

    /// 各フィールドの最大文字数
    static let maxLengths: [String: Int] = [
        "title": 40, "summary": 160, "analysis": 300, "recommendation": 200,
        "next_action": 120, "caution": 160, "confidence_label": 40
    ]

    /// 医療的断定と受け取られうる表現（免責文の「医療的な診断ではありません」は許可する）
    static let prohibitedPhrases: [String] = [
        "診断結果", "と診断", "治療", "病気", "疾患", "障害", "うつ病", "不安障害",
        "パニック", "処方", "服薬", "副交感神経", "自律神経"
    ]

    static func validate(_ response: InsightResponseDTO, expectedRequestId: UUID) throws {
        guard MindWaveContract.isSupported(schemaVersion: response.schemaVersion) else {
            throw ContractError.unsupportedSchemaVersion(response.schemaVersion)
        }
        guard response.requestId == expectedRequestId else {
            throw ContractError.inconsistent("request_id が一致しない")
        }
        let b = response.insight
        let fields: [(String, String)] = [
            ("title", b.title), ("summary", b.summary), ("analysis", b.analysis),
            ("recommendation", b.recommendation), ("next_action", b.nextAction),
            ("caution", b.caution), ("confidence_label", b.confidenceLabel)
        ]
        for (name, value) in fields {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ContractError.missingField(name) }
            if let limit = maxLengths[name], trimmed.count > limit {
                throw ContractError.outOfRange(field: name, value: Double(trimmed.count))
            }
            if let phrase = prohibitedPhrases.first(where: { trimmed.contains($0) }) {
                throw ContractError.inconsistent("禁止表現を含む field=\(name) phrase=\(phrase)")
            }
        }
    }
}
