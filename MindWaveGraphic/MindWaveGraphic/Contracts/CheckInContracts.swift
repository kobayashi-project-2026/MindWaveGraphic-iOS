// CheckInContracts.swift
// Contracts
//
// /v1/context-assist の会話の情報（STEP 0〜6）。2026-11-11 追加。どちらも省略可能（古いサーバー・古いアプリと互換）。
// - 要求 current.check_in: これまでに分かっている項目（列挙値の文字列）・答えたくない項目・尋ねた項目・次に尋ねる候補
// - 応答 result.check_in: 今回の発言から取り出した項目。未知の値は採用しない（画面は止めない）

import Foundation

/// 要求: これまでに分かっている情報（本人の発言・選択からのもの。HealthKit の値は送らない）
nonisolated struct ContextAssistCheckInDTO: Codable, Equatable, Sendable {
    var sleep: String?
    var activity: String?
    var condition: String?
    var situation: String?
    var timing: String?
    var emotion: String?
    var tensionLevel: Int?
    var causes: [String]
    var bodySignals: [String]
    var support: String?
    var declined: [String]
    var asked: [String]
    /// 次に尋ねる候補（優先順）。AI はこの先頭を 1 つだけ尋ねる
    var remainingSlots: [String]

    enum CodingKeys: String, CodingKey {
        case sleep, activity, condition, situation, timing, emotion, causes, support, declined, asked
        case tensionLevel = "tension_level", bodySignals = "body_signals", remainingSlots = "remaining_slots"
    }

    init(_ c: MokorinCheckIn) {
        sleep = c.sleep?.value.rawValue
        activity = c.activity?.value.rawValue
        condition = c.condition?.value.rawValue
        situation = c.situation?.value.rawValue
        timing = c.timing?.value.rawValue
        emotion = c.emotion?.value.rawValue
        tensionLevel = c.tension?.value
        causes = (c.causes?.value ?? []).map(\.rawValue).sorted()
        bodySignals = (c.body?.value ?? []).map(\.rawValue).sorted()
        support = c.support?.value.rawValue
        declined = c.declined.map(\.rawValue).sorted()
        asked = c.asked.map(\.rawValue)
        remainingSlots = MokorinCheckIn.priority.filter { !c.isSettled($0) && c.isRelevant($0) }.map(\.rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var k = encoder.container(keyedBy: CodingKeys.self)
        try k.encode(sleep, forKey: .sleep); try k.encode(activity, forKey: .activity); try k.encode(condition, forKey: .condition)
        try k.encode(situation, forKey: .situation); try k.encode(timing, forKey: .timing); try k.encode(emotion, forKey: .emotion)
        try k.encode(tensionLevel, forKey: .tensionLevel); try k.encode(causes, forKey: .causes); try k.encode(bodySignals, forKey: .bodySignals)
        try k.encode(support, forKey: .support); try k.encode(declined, forKey: .declined); try k.encode(asked, forKey: .asked)
        try k.encode(remainingSlots, forKey: .remainingSlots)
    }
}

/// 応答: 今回の発言から AI が取り出した項目（すべて省略可能。未知の値は無視）
nonisolated struct ContextAssistCheckInResultDTO: Codable, Equatable, Sendable {
    var sleep: String? = nil
    var activity: String? = nil
    var condition: String? = nil
    var situation: String? = nil
    var timing: String? = nil
    var emotion: String? = nil
    var tensionLevel: Int? = nil
    var causes: [String]? = nil
    var bodySignals: [String]? = nil
    var support: String? = nil
    var declined: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case sleep, activity, condition, situation, timing, emotion, causes, support, declined
        case tensionLevel = "tension_level", bodySignals = "body_signals"
    }

    /// AI の値（正しい列挙値のものだけ）を優先し、ない項目は端末内の抽出で補う
    func merged(over local: CheckInExtraction) -> CheckInExtraction {
        var e = local
        if let v = sleep.flatMap(SleepAmount.init(rawValue:)) { e.sleep = v; e.tentative.remove(.sleep) }
        if let v = activity.flatMap(ActivityLevel.init(rawValue:)) { e.activity = v }
        if let v = condition.flatMap(DailyCondition.init(rawValue:)) { e.condition = v }
        if let v = situation.flatMap(SituationKind.init(rawValue:)) { e.situation = v }
        if let v = timing.flatMap(EventTiming.init(rawValue:)) { e.timing = v }
        if let v = emotion.flatMap(FeelingKind.init(rawValue:)) { e.emotion = v }
        if let v = tensionLevel, (0...100).contains(v) { e.tension = v; e.tentative.remove(.tension) }
        let c = Set((causes ?? []).compactMap(WorryCause.init(rawValue:)))
        if !c.isEmpty { e.causes = c }
        let b = Set((bodySignals ?? []).compactMap(BodySignal.init(rawValue:)))
        if !b.isEmpty { e.body = MokorinCheckIn.consistentBody(b) }
        if let v = support.flatMap(SupportWish.init(rawValue:)) { e.support = v }
        e.declined.formUnion((declined ?? []).compactMap(CheckInSlot.init(rawValue:)))
        return e
    }
}
