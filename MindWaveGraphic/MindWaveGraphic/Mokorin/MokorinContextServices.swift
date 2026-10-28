// MokorinContextServices.swift
// Mokorin
//
// もこりんの状況整理で使う通信と、外部AIを使えないときの端末内の判定。
// 画面・状態（MokorinContextViewModel）からはこのファイルの型だけを使う。

import Foundation

// MARK: - 通信

/// サーバーへの送信（テストではスタブに差し替える）
protocol ContextAssistClient: Sendable {
    func send(_ request: ContextAssistRequestDTO) async throws -> ContextAssistResponseDTO
}

/// 自前サーバーの POST /v1/context-assist を呼ぶ（接続・認証・エラー変換は AI 相談と共通の ServerJSONPoster）
struct RemoteContextAssistClient: ContextAssistClient {
    let configuration: RemoteInsightConfiguration
    var session: URLSession = .shared

    func send(_ body: ContextAssistRequestDTO) async throws -> ContextAssistResponseDTO {
        let data = try await ServerJSONPoster(configuration: configuration, session: session).post(path: "v1/context-assist", body: body)
        do {
            let decoded = try MindWaveContract.makeDecoder().decode(ContextAssistResponseDTO.self, from: data)
            try ContextAssistValidation.validate(decoded, expectedRequestId: body.requestId, expectedConversationId: body.conversationId)
            return decoded
        } catch {
            // 不正な JSON・未知の候補は採用しない
            throw InsightClientError.invalidResponse(String(describing: error))
        }
    }
}

// MARK: - 端末内の判定（外部AIを使えないとき）

/// 文章に含まれる言葉から、既存の場面・身体状態の候補を探す（AI ではない）。
/// 明確な言葉がある場合だけ候補にし、「緊張」「不安」だけでは場面を決めない。
/// 候補は画面に「提案」として表示し、利用者が確認・変更してから測定する。
nonisolated enum MokorinKeywordInterpreter {

    private static let sceneWords: [(ContextScene, [String])] = [
        (.interview, ["面接", "面談", "発表", "プレゼン", "スピーチ"]),
        (.sports,    ["試合", "大会", "競技", "レース"]),
        (.important, ["大切な", "大事な", "デート", "約束"]),
        (.work,      ["作業", "仕事", "勉強", "集中"]),
        (.calm,      ["安静", "リラックス", "のんびり"]),
    ]

    private static let conditionWords: [(BodyCondition, [String])] = [
        (.running,   ["走って", "走った", "ランニング"]),
        (.stairs,    ["階段", "移動", "歩いて"]),
        (.smoking,   ["たばこ", "タバコ", "煙草", "喫煙"]),
        (.caffeine,  ["コーヒー", "カフェイン", "エナジードリンク"]),
        (.sleepLack, ["寝不足", "睡眠不足", "眠れなかった", "あまり寝て"]),
        (.afterMeal, ["食後", "ご飯を食べ", "食べた", "昼食後"]),
        (.none,      ["特にない", "特になし", "座って", "何もしていない"]),
    ]

    static func interpret(_ text: String) -> (scene: ContextScene?, conditions: Set<BodyCondition>) {
        let scene = sceneWords.first { _, words in words.contains { text.contains($0) } }?.0
        var conditions = Set(conditionWords.filter { _, words in words.contains { text.contains($0) } }.map(\.0))
        if conditions.contains(.none) && conditions.count > 1 { conditions.remove(.none) }
        return (scene, conditions)
    }
}

// MARK: - もこりんの定型文（外部AIを使えないとき・ボタンで答えたとき）

nonisolated enum MokorinScript {
    static let greeting = "こんにちは！今はどんな状況かな？下のボタンで選んでも、文章で教えてくれても大丈夫だよ。"

    static func greetingForEdit(current: MeasurementContext) -> String {
        "今の状況を教えてね。いまは「\(current.scene.displayName)」になっているよ。変わったところはある？"
    }

    static let askScene = "教えてくれてありがとう。どんな場面の前かな？（面接や発表、試合、大切な予定など）下のボタンからも選べるよ。"

    static func askCondition(scene: ContextScene) -> String {
        "\(sceneLead(scene))今は移動してきたところ？それとも座って落ち着いている？当てはまるものを下から選んでね。"
    }

    static let askConditionAgain = "からだの状態を教えてね。走ってきた・階段を上った・コーヒーを飲んだなど、当てはまるものがなければ「特になし」を選んでね。"

    static func summary(scene: ContextScene, conditions: Set<BodyCondition>) -> String {
        "教えてくれてありがとう。\(sceneShort(scene))で、\(conditionPhrase(conditions))なんだね。この状況で測定してみようか？"
    }

    private static func sceneLead(_ scene: ContextScene) -> String {
        switch scene {
        case .interview: return "面接や発表の前なんだね。緊張するよね。"
        case .sports:    return "試合や大会の前なんだね。"
        case .important: return "大切な予定の前なんだね。"
        case .work:      return "作業や集中の時間なんだね。"
        case .calm:      return "落ち着いているときなんだね。"
        case .other:     return "教えてくれてありがとう。"
        }
    }

    static func sceneShort(_ scene: ContextScene) -> String {
        switch scene {
        case .interview: return "面接や発表の前"
        case .sports:    return "試合や大会の前"
        case .important: return "大切な予定の前"
        case .work:      return "作業や集中のとき"
        case .calm:      return "安静にしているとき"
        case .other:     return "その他の場面"
        }
    }

    static func conditionPhrase(_ conditions: Set<BodyCondition>) -> String {
        let ordered = BodyCondition.allCases.filter { conditions.contains($0) && $0 != .none }
        if ordered.isEmpty { return "からだは特に変わりない状態" }
        let phrases: [String] = ordered.map {
            switch $0 {
            case .running:   return "走ってきた直後"
            case .stairs:    return "階段や移動の直後"
            case .smoking:   return "喫煙のあと"
            case .caffeine:  return "カフェインをとったあと"
            case .sleepLack: return "睡眠不足ぎみ"
            case .afterMeal: return "食事のあと"
            case .none:      return ""
            }
        }
        return phrases.joined(separator: "、")
    }
}

// MARK: - もこりんの表情・動作（外部AIを使わないとき）

/// 定型文で応答するときの表情・動作の決め方（AI の判断ではない、固定の規則）。
/// 外部AIの応答には emotion / action が含まれるので、そちらを優先する。
nonisolated enum MokorinExpressionRules {
    static let greeting: (MokorinEmotion, MokorinAction) = (.happy, .wave)

    static func forReply(step: MokorinContextViewModel.Step, userText: String?, conditions: Set<BodyCondition>) -> (MokorinEmotion, MokorinAction) {
        let text = userText ?? ""
        if ["つらい", "悲しい", "しんどい", "落ち込"].contains(where: { text.contains($0) }) { return (.sad, .nod) }
        if conditions.contains(.sleepLack) || ["眠い", "ねむい", "寝不足"].contains(where: { text.contains($0) }) { return (.sleepy, .nod) }
        if step == .review { return (.happy, .nod) }
        return (.calm, .nod)
    }
}
