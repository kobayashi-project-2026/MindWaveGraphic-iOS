// ContextAssistContracts.swift
// Contracts
//
// もこりんとの会話による「測定前の状況整理」（POST /v1/context-assist）の JSON 契約。
// サーバー側の正本: server/src/context.ts。片方を変えたら、もう片方・docs/MOKORIN_CONTEXT_INTEGRATION.md・テストを同時に更新する。
//
// - AI が返すのは「候補」だけ。確定・測定開始はアプリ上で利用者が行う
// - 候補は ContextScene / BodyCondition の rawValue に限定。未知の値を含む応答は採用しない
// - 心拍・HRV などの計測データを送る項目はない

import Foundation

/// 会話の段階（アプリ側の進行）
nonisolated enum ContextAssistStepCode: String, Codable, Equatable, Sendable {
    case scene, condition, review
}

/// 画面で現在選ばれている内容
nonisolated struct ContextAssistCurrentDTO: Codable, Equatable, Sendable {
    /// ContextScene.rawValue（未回答は null）
    var scene: String?
    /// BodyCondition.rawValue
    var conditions: [String]

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scene, forKey: .scene)
        try c.encode(conditions, forKey: .conditions)
    }
}

/// POST /v1/context-assist リクエスト
nonisolated struct ContextAssistRequestDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int = MindWaveContract.schemaVersion
    var requestId: UUID
    var conversationId: UUID
    var locale: String = "ja-JP"
    var step: ContextAssistStepCode
    /// 古い順。最後は必ず user（ChatMessageDTO を共用）
    var messages: [ChatMessageDTO]
    var current: ContextAssistCurrentDTO

    enum CodingKeys: String, CodingKey {
        case schemaVersion  = "schema_version"
        case requestId      = "request_id"
        case conversationId = "conversation_id"
        case locale, step, messages, current
    }
}

/// AI が整理した候補（サーバーで検証済み。アプリでも enum へ変換できることを確認する）
nonisolated struct ContextAssistResultDTO: Codable, Equatable, Sendable {
    var reply: String
    var sceneCandidate: String?
    var conditionCandidates: [String]
    var needsClarification: Bool
    var clarificationQuestion: String?
    /// もこりんの表情（happy / calm / sad / sleepy）。古いサーバーでは無い。不正な値は無視して calm
    var emotion: String? = nil
    /// もこりんの動作（wave / jump / nod）。不正な値は無視して nod
    var action: String? = nil

    enum CodingKeys: String, CodingKey {
        case reply, emotion, action
        case sceneCandidate        = "scene_candidate"
        case conditionCandidates   = "condition_candidates"
        case needsClarification    = "needs_clarification"
        case clarificationQuestion = "clarification_question"
    }

    /// 表情・動作は見た目だけのため、不正・欠落は既定値にする（候補の採否には影響させない。原本 app.py と同じ既定値）
    var typedExpression: (emotion: MokorinEmotion, action: MokorinAction) {
        (emotion.flatMap(MokorinEmotion.init(rawValue:)) ?? .calm, action.flatMap(MokorinAction.init(rawValue:)) ?? .nod)
    }

    /// 既存の enum に変換した候補。未知の値があれば throw（採用しない）
    func typedCandidates() throws -> (scene: ContextScene?, conditions: Set<BodyCondition>) {
        var scene: ContextScene? = nil
        if let raw = sceneCandidate {
            guard let s = ContextScene(rawValue: raw) else { throw ContractError.inconsistent("unknown scene_candidate") }
            scene = s
        }
        var conditions = Set<BodyCondition>()
        for raw in conditionCandidates {
            guard let c = BodyCondition(rawValue: raw) else { throw ContractError.inconsistent("unknown condition_candidate") }
            conditions.insert(c)
        }
        // 「特になし」と他の状態は同時に選べない（既存の画面の規則と同じ）
        if conditions.contains(.none) && conditions.count > 1 { conditions.remove(.none) }
        return (scene, conditions)
    }
}

/// POST /v1/context-assist の 200 レスポンス
nonisolated struct ContextAssistResponseDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var requestId: UUID
    var conversationId: UUID
    /// "openai" = 実際の OpenAI / "openai-stub" = ローカル開発用スタブ（実際の AI ではない）
    var provider: String
    var model: String
    var generatedAt: Date
    var result: ContextAssistResultDTO
    var usage: ChatUsageDTO?

    enum CodingKeys: String, CodingKey {
        case schemaVersion  = "schema_version"
        case requestId      = "request_id"
        case conversationId = "conversation_id"
        case provider, model, result, usage
        case generatedAt    = "generated_at"
    }

    var isStub: Bool { provider != "openai" }
}

/// 上限（server/src/context.ts の CONTEXT_LIMITS と同じ値）
nonisolated enum ContextAssistLimits {
    static let maxMessages = 12
    static let maxUserChars = 300
    static let maxAssistantChars = 300
    static let maxReplyChars = 160
}

nonisolated enum ContextAssistValidation {
    static func validate(_ r: ContextAssistResponseDTO, expectedRequestId: UUID, expectedConversationId: UUID) throws {
        guard MindWaveContract.isSupported(schemaVersion: r.schemaVersion) else { throw ContractError.unsupportedSchemaVersion(r.schemaVersion) }
        guard r.requestId == expectedRequestId else { throw ContractError.inconsistent("request_id mismatch") }
        guard r.conversationId == expectedConversationId else { throw ContractError.inconsistent("conversation_id mismatch") }
        guard r.provider == "openai" || r.provider == "openai-stub" else { throw ContractError.inconsistent("unknown provider") }
        let reply = r.result.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty, reply.count <= ContextAssistLimits.maxReplyChars else { throw ContractError.inconsistent("reply length") }
        _ = try r.result.typedCandidates()
    }
}
