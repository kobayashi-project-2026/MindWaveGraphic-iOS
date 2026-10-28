// ChatContracts.swift
// Contracts
//
// iOS アプリ ⇄ 自前APIサーバー（server/src/chat.ts）間の AI 相談（POST /v1/chat）の JSON 契約。
// 片方を変更したら、もう片方・docs/OPENAI_CHAT_ARCHITECTURE.md・テストを同時に更新すること。
//
// データ最小化の方針:
// - 送るのは「利用者が入力した文章と直近の会話」「利用者が選んだ場面」だけ
// - 計測の要約（context.measurement）は、利用者の同意と本物の利用者認証が揃うまで常に null
// - 端末ID・氏名・メール・日時・メモは送らない

import Foundation

/// 発言者
nonisolated enum ChatRoleCode: String, Codable, Equatable, Sendable {
    case user, assistant
}

/// 1 発言
nonisolated struct ChatMessageDTO: Codable, Equatable, Sendable {
    var role: ChatRoleCode
    var content: String
}

/// 計測の要約（数値ではなく分類のみ）。現在は送信しない（ChatBiometricPolicy）
nonisolated struct ChatMeasurementContextDTO: Codable, Equatable, Sendable {
    var source: DataSourceCode
    var isMock: Bool
    var state: MindStateCode?
    var hrvStatus: String
    var baselineStatus: String
    var dataAgeSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case source, state
        case isMock         = "is_mock"
        case hrvStatus      = "hrv_status"
        case baselineStatus = "baseline_status"
        case dataAgeSeconds = "data_age_seconds"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source, forKey: .source)
        try c.encode(isMock, forKey: .isMock)
        try c.encode(state, forKey: .state)
        try c.encode(hrvStatus, forKey: .hrvStatus)
        try c.encode(baselineStatus, forKey: .baselineStatus)
        try c.encode(dataAgeSeconds, forKey: .dataAgeSeconds)
    }
}

/// 会話の補足情報
nonisolated struct ChatContextDTO: Codable, Equatable, Sendable {
    /// 状況確認で選んだ場面（ContextScene.rawValue）。未選択は null
    var scene: String?
    var measurement: ChatMeasurementContextDTO?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scene, forKey: .scene)
        try c.encode(measurement, forKey: .measurement)
    }
}

/// 同意情報（計測の要約の送信に対する同意）
nonisolated struct ChatConsentDTO: Codable, Equatable, Sendable {
    var biometricContextConsented: Bool
    var consentVersion: Int

    enum CodingKeys: String, CodingKey {
        case biometricContextConsented = "biometric_context_consented"
        case consentVersion            = "consent_version"
    }
}

/// POST /v1/chat リクエスト
nonisolated struct ChatRequestDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int = MindWaveContract.schemaVersion
    var requestId: UUID
    /// アプリ起動中の1つの会話を表す ID（リセットで作り直す。端末・利用者の識別には使わない）
    var conversationId: UUID
    var locale: String = "ja-JP"
    /// 古い順。最後は必ず user
    var messages: [ChatMessageDTO]
    var context: ChatContextDTO
    var consent: ChatConsentDTO

    enum CodingKeys: String, CodingKey {
        case schemaVersion  = "schema_version"
        case requestId      = "request_id"
        case conversationId = "conversation_id"
        case locale, messages, context, consent
    }
}

/// 利用量（監視用）
nonisolated struct ChatUsageDTO: Codable, Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens     = "input_tokens"
        case outputTokens    = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case totalTokens     = "total_tokens"
    }
}

/// 返答本文
nonisolated struct ChatReplyDTO: Codable, Equatable, Sendable {
    var text: String
    /// 出力トークン上限で途中終了した
    var truncated: Bool
}

/// POST /v1/chat の 200 レスポンス
nonisolated struct ChatResponseDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var requestId: UUID
    var conversationId: UUID
    /// "openai" = 実際の OpenAI / "openai-stub" = ローカル開発用スタブ（実際の AI ではない）
    var provider: String
    var model: String
    var generatedAt: Date
    var reply: ChatReplyDTO
    var usage: ChatUsageDTO?

    enum CodingKeys: String, CodingKey {
        case schemaVersion  = "schema_version"
        case requestId      = "request_id"
        case conversationId = "conversation_id"
        case provider, model, reply, usage
        case generatedAt    = "generated_at"
    }

    /// スタブ（実際の AI ではない）による返答か
    var isStub: Bool { provider != "openai" }
}

/// 上限（server/src/chat.ts の CHAT_DEFAULTS と同じ値）
nonisolated enum ChatLimits {
    static let maxMessages = 12
    static let maxUserChars = 500
    static let maxAssistantChars = 1500
    static let maxTotalChars = 8000
    static let maxReplyChars = 1500
}

/// 応答の検証（サーバーでも検証済みだが、アプリ側でも確認する）
nonisolated enum ChatResponseValidation {
    static func validate(_ r: ChatResponseDTO, expectedRequestId: UUID, expectedConversationId: UUID) throws {
        guard MindWaveContract.isSupported(schemaVersion: r.schemaVersion) else { throw ContractError.unsupportedSchemaVersion(r.schemaVersion) }
        guard r.requestId == expectedRequestId else { throw ContractError.inconsistent("request_id mismatch") }
        guard r.conversationId == expectedConversationId else { throw ContractError.inconsistent("conversation_id mismatch") }
        let text = r.reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ContractError.inconsistent("reply empty") }
        guard text.count <= ChatLimits.maxReplyChars else { throw ContractError.inconsistent("reply too long") }
        guard r.provider == "openai" || r.provider == "openai-stub" else { throw ContractError.inconsistent("unknown provider") }
    }
}
