// MokorinCheckIn.swift
// Mokorin
//
// もこりんの会話で集める情報（STEP 0〜6）と、次に尋ねる質問の選択（2026-11-11）。
// - 1 回に尋ねるのは 1 つ。答え済み・答えたくない項目は尋ねない
// - 1 つの発言から複数の項目を取り出す（例:「明日面接があって、不安であまり寝られなかった。今は心臓がドキドキしてる」）
// - 値には出どころ（本人・HealthKit・推定）、更新時刻、確かさを付ける。訂正は新しい値で上書きする
// - 必要な項目（場面・気持ち・緊張の強さ・してみたいこと）がそろったら質問を終える。それ以外は質問の上限まで
// - 主観的な緊張の強さ（S0）は試作スコアの初期値に使う。感情の種類とは別に保持する（イライラ＝強い緊張とはしない）
// AI（/v1/context-assist）は返答の言い回しと抽出を担い、どの項目を尋ねるかの候補はこのモデルが決める（同じ質問を繰り返さない）。

import Foundation

// MARK: - 項目と選択肢

nonisolated enum CheckInSlot: String, CaseIterable, Codable, Sendable {
    case sleep, activity, condition, situation, timing, emotion, tension, cause, body, support

    var question: String {
        switch self {
        case .sleep:     return "昨日はどのくらい眠れた？"
        case .activity:  return "今日はどのくらい体を動かした？"
        case .condition: return "今の体調はどう？"
        case .situation: return "今、どんな場面にいる？"
        case .timing:    return "その出来事はいつ頃？"
        case .emotion:   return "今の気持ちに一番近いものはどれ？"
        case .tension:   return "緊張の強さはどのくらい？0（全く緊張していない）から100（とても強い）で教えてね。"
        case .cause:     return "今、一番気になっていることはある？"
        case .body:      return "今、体に何か変化はある？いくつでも教えてね。"
        case .support:   return "今、どんなことをしてみたい？"
        }
    }

    /// 選択肢（すべて。画面には先頭から最大 3 つと「その他・自分の言葉で」を出す）
    var options: [CheckInOption] {
        switch self {
        case .sleep:     return SleepAmount.allCases.map { .sleep($0) }
        case .activity:  return ActivityLevel.allCases.map { .activity($0) }
        case .condition: return DailyCondition.allCases.map { .condition($0) }
        case .situation: return SituationKind.allCases.map { .situation($0) }
        case .timing:    return EventTiming.allCases.map { .timing($0) }
        case .emotion:   return FeelingKind.allCases.map { .emotion($0) }
        case .tension:   return [0, 20, 50, 75, 100].map { .tension($0) }
        case .cause:     return WorryCause.allCases.map { .cause($0) }
        case .body:      return BodySignal.allCases.map { .body($0) }
        case .support:   return SupportWish.allCases.map { .support($0) }
        }
    }

    /// 複数選べる項目
    var allowsMultiple: Bool { self == .cause || self == .body }
}

nonisolated enum SleepAmount: String, CaseIterable, Codable, Sendable {
    case under3 = "under_3h", h3to5 = "3_5h", h5to7 = "5_7h", h7to9 = "7_9h", over9 = "over_9h", unknown
    var label: String {
        switch self {
        case .under3: return "3時間未満"
        case .h3to5: return "3〜5時間"
        case .h5to7: return "5〜7時間"
        case .h7to9: return "7〜9時間"
        case .over9: return "9時間以上"
        case .unknown: return "あまり覚えていない"
        }
    }
    var reaction: String {
        switch self {
        case .under3: return "かなり睡眠が短かったんだね。今日は疲れを感じやすいかもしれないね。"
        case .h3to5: return "少し短めだったんだね。無理しすぎないようにしようね。"
        case .h5to7: return "なるほど。そのくらい眠れたんだね。"
        case .h7to9: return "しっかり眠れたんだね。"
        case .over9: return "たっぷり眠れたんだね。"
        case .unknown: return "正確には覚えていないんだね。無理に思い出さなくても大丈夫だよ。"
        }
    }
    var isShort: Bool { self == .under3 || self == .h3to5 }
}

nonisolated enum ActivityLevel: String, CaseIterable, Codable, Sendable {
    case exercised, light, usual, little
    var label: String {
        switch self {
        case .exercised: return "ランニングや運動をした"
        case .light: return "散歩など軽く体を動かした"
        case .usual: return "普段通りに生活した"
        case .little: return "ほとんど動いていない"
        }
    }
}

nonisolated enum DailyCondition: String, CaseIterable, Codable, Sendable {
    case energetic, slightlyTired = "slightly_tired", veryTired = "very_tired", sluggish, unwell
    var label: String {
        switch self {
        case .energetic: return "元気！"
        case .slightlyTired: return "少し疲れている"
        case .veryTired: return "かなり疲れている"
        case .sluggish: return "体がだるい"
        case .unwell: return "体調が悪い"
        }
    }
    var isTired: Bool { self == .slightlyTired || self == .veryTired || self == .sluggish }
}

nonisolated enum SituationKind: String, CaseIterable, Codable, Sendable {
    case presentation, interviewExam = "interview_exam", communication, importantEvent = "important_event", restless, other
    var label: String {
        switch self {
        case .presentation: return "発表・プレゼン"
        case .interviewExam: return "面接・試験"
        case .communication: return "人とのコミュニケーション"
        case .importantEvent: return "大事な予定・イベント"
        case .restless: return "特に予定はないけど落ち着かない"
        case .other: return "その他"
        }
    }
    /// 既存の場面（MeasurementContext.scene）への対応。既存の分類は変えない
    var contextScene: ContextScene {
        switch self {
        case .presentation, .interviewExam: return .interview
        case .communication, .importantEvent: return .important
        case .restless: return .calm
        case .other: return .other
        }
    }
    var isEvent: Bool { self != .restless }
}

nonisolated enum EventTiming: String, CaseIterable, Codable, Sendable {
    case soon, today, tomorrowOrLater = "tomorrow_or_later", finished, notSpecific = "not_specific"
    var label: String {
        switch self {
        case .soon: return "これからすぐ"
        case .today: return "今日中"
        case .tomorrowOrLater: return "明日以降"
        case .finished: return "すでに終わった"
        case .notSpecific: return "いつというわけではない"
        }
    }
}

nonisolated enum FeelingKind: String, CaseIterable, Codable, Sendable {
    case tense, anxious, rushed, unconfident, irritated, unsure
    var label: String {
        switch self {
        case .tense: return "緊張している"
        case .anxious: return "不安・心配"
        case .rushed: return "焦っている"
        case .unconfident: return "自信がない"
        case .irritated: return "イライラしている"
        case .unsure: return "自分でもよく分からない"
        }
    }
}

nonisolated enum WorryCause: String, CaseIterable, Codable, Sendable {
    case failure, othersView = "others_view", speaking, outcome, ability, comparison, unknown, other
    var label: String {
        switch self {
        case .failure: return "失敗してしまいそう"
        case .othersView: return "人からどう思われるか気になる"
        case .speaking: return "うまく話せるか不安"
        case .outcome: return "結果がどうなるか心配"
        case .ability: return "自分の実力が足りない気がする"
        case .comparison: return "周りと比べてしまう"
        case .unknown: return "何が不安なのか分からない"
        case .other: return "その他"
        }
    }
}

nonisolated enum BodySignal: String, CaseIterable, Codable, Sendable {
    case heartPounding = "heart_pounding", shallowBreath = "shallow_breath", trembling, tenseMuscles = "tense_muscles", foggy, none, unsure
    var label: String {
        switch self {
        case .heartPounding: return "心臓がドキドキする"
        case .shallowBreath: return "呼吸が浅い・苦しい"
        case .trembling: return "手足が震える"
        case .tenseMuscles: return "体に力が入っている"
        case .foggy: return "頭がぼーっとする"
        case .none: return "特に体の変化はない"
        case .unsure: return "自分ではよく分からない"
        }
    }
    /// 「特にない」「分からない」は具体的な症状と同時に選べない
    var isExclusive: Bool { self == .none || self == .unsure }
}

nonisolated enum SupportWish: String, CaseIterable, Codable, Sendable {
    case calmDown = "calm_down", organize, confidence, refresh, findMethod = "find_method", unsure
    var label: String {
        switch self {
        case .calmDown: return "とにかく落ち着きたい"
        case .organize: return "不安の原因を整理したい"
        case .confidence: return "自信をつけたい"
        case .refresh: return "気分転換したい"
        case .findMethod: return "自分に合った方法を知りたい"
        case .unsure: return "まだよく分からない"
        }
    }
}

/// 画面の選択肢 1 つ
nonisolated enum CheckInOption: Hashable, Sendable {
    case sleep(SleepAmount), activity(ActivityLevel), condition(DailyCondition), situation(SituationKind)
    case timing(EventTiming), emotion(FeelingKind), tension(Int), cause(WorryCause), body(BodySignal), support(SupportWish)

    var label: String {
        switch self {
        case .sleep(let v): return v.label
        case .activity(let v): return v.label
        case .condition(let v): return v.label
        case .situation(let v): return v.label
        case .timing(let v): return v.label
        case .emotion(let v): return v.label
        case .tension(let v): return MokorinCheckIn.tensionLabel(v)
        case .cause(let v): return v.label
        case .body(let v): return v.label
        case .support(let v): return v.label
        }
    }
}

// MARK: - 値（出どころ・時刻・確かさ）

nonisolated enum CheckInSource: String, Codable, Sendable {
    /// 本人の発言・選択
    case user
    /// HealthKit・Apple Watch の記録（権限と鮮度を確認したもの）
    case healthKit = "health_kit"
    /// 会話からの推定（確かさが低い）
    case inferred
}

nonisolated struct CheckInValue<V: Equatable & Sendable>: Equatable, Sendable {
    var value: V
    var source: CheckInSource
    var updatedAt: Date
    /// 0〜1。言葉がはっきりしないときは低い
    var confidence: Double
}

/// 1 つの発言から取り出した内容（ない項目は nil / 空）
nonisolated struct CheckInExtraction: Equatable, Sendable {
    var sleep: SleepAmount?
    var activity: ActivityLevel?
    var condition: DailyCondition?
    var situation: SituationKind?
    var situationNote: String?
    var timing: EventTiming?
    var emotion: FeelingKind?
    var tension: Int?
    var causes: Set<WorryCause> = []
    var body: Set<BodySignal> = []
    var support: SupportWish?
    /// 答えたくないと言った項目
    var declined: Set<CheckInSlot> = []
    /// はっきりしない言葉から推定した項目（確かさを下げる）
    var tentative: Set<CheckInSlot> = []

    var isEmpty: Bool {
        sleep == nil && activity == nil && condition == nil && situation == nil && timing == nil && emotion == nil
            && tension == nil && causes.isEmpty && body.isEmpty && support == nil && declined.isEmpty
    }
}

// MARK: - 会話の状態

nonisolated struct MokorinCheckIn: Equatable, Sendable {
    var sleep: CheckInValue<SleepAmount>?
    var activity: CheckInValue<ActivityLevel>?
    var condition: CheckInValue<DailyCondition>?
    var situation: CheckInValue<SituationKind>?
    var situationNote: String?
    var timing: CheckInValue<EventTiming>?
    var emotion: CheckInValue<FeelingKind>?
    /// 主観的な緊張の強さ S0（0〜100。試作の表示尺度で、医学的な区分ではない）
    var tension: CheckInValue<Int>?
    var causes: CheckInValue<Set<WorryCause>>?
    var body: CheckInValue<Set<BodySignal>>?
    var support: CheckInValue<SupportWish>?
    /// 答えたくないと言った項目（尋ねない）
    var declined: Set<CheckInSlot> = []
    /// 尋ねた項目（同じ質問を繰り返さない）
    var asked: [CheckInSlot] = []
    /// 本人が測定・改善を望まない
    var declinedMeasurement = false

    /// 質問を終える前に必ず確かめる項目（推薦と試作スコアに必要）
    static let required: [CheckInSlot] = [.situation, .emotion, .tension, .support]
    /// 質問の優先順（STEP 1 → 6 の順を基本に、必要なものだけ）
    static let priority: [CheckInSlot] = [.sleep, .condition, .situation, .timing, .emotion, .tension, .body, .cause, .activity, .support]
    /// 1 回の会話で尋ねる質問の上限（くどくしない）
    static let questionBudget = 7

    static func tensionLabel(_ v: Int) -> String {
        switch v {
        case ..<10: return "0 全く緊張していない"
        case ..<35: return "20 少し緊張している"
        case ..<62: return "50 緊張している"
        case ..<88: return "75 かなり緊張している"
        default:    return "100 非常に強く緊張している"
        }
    }

    func isKnown(_ slot: CheckInSlot) -> Bool {
        switch slot {
        case .sleep: return sleep != nil
        case .activity: return activity != nil
        case .condition: return condition != nil
        case .situation: return situation != nil
        case .timing: return timing != nil
        case .emotion: return emotion != nil
        case .tension: return tension != nil
        case .cause: return !(causes?.value.isEmpty ?? true)
        case .body: return !(body?.value.isEmpty ?? true)
        case .support: return support != nil
        }
    }

    func isSettled(_ slot: CheckInSlot) -> Bool { isKnown(slot) || declined.contains(slot) }

    /// 体調が悪い・深刻な症状があるときは、質問を続けず休息を優先する
    var needsRestFirst: Bool { condition?.value == .unwell }

    /// その項目を尋ねる意味があるか（状況によって省く）
    func isRelevant(_ slot: CheckInSlot) -> Bool {
        switch slot {
        case .timing: return situation?.value.isEvent ?? true
        case .cause:  return emotion?.value != .irritated || situation?.value.isEvent == true
        default:      return true
        }
    }

    /// 次に尋ねる項目（nil = 質問を終えて提案へ）
    func nextSlot() -> CheckInSlot? {
        if needsRestFirst || declinedMeasurement { return nil }
        let remainingRequired = Self.required.filter { !isSettled($0) }
        let spare = Self.questionBudget - asked.count - remainingRequired.count
        for slot in Self.priority where !isSettled(slot) && !asked.contains(slot) && isRelevant(slot) {
            if Self.required.contains(slot) || spare > 0 { return slot }
        }
        return nil
    }

    /// 必要な項目がそろい、提案へ進める
    var isReadyToSuggest: Bool { Self.required.allSatisfy(isSettled) || needsRestFirst }

    /// 取り出した内容を反映する（訂正は新しい値で上書き）。反映した項目を返す
    @discardableResult
    mutating func apply(_ e: CheckInExtraction, source: CheckInSource = .user, at now: Date) -> Set<CheckInSlot> {
        var changed = Set<CheckInSlot>()
        func conf(_ slot: CheckInSlot) -> Double { e.tentative.contains(slot) ? 0.5 : 1 }
        if let v = e.sleep { sleep = .init(value: v, source: source, updatedAt: now, confidence: conf(.sleep)); changed.insert(.sleep) }
        if let v = e.activity { activity = .init(value: v, source: source, updatedAt: now, confidence: conf(.activity)); changed.insert(.activity) }
        if let v = e.condition { condition = .init(value: v, source: source, updatedAt: now, confidence: conf(.condition)); changed.insert(.condition) }
        if let v = e.situation { situation = .init(value: v, source: source, updatedAt: now, confidence: conf(.situation)); changed.insert(.situation) }
        if let note = e.situationNote { situationNote = note }
        if let v = e.timing { timing = .init(value: v, source: source, updatedAt: now, confidence: conf(.timing)); changed.insert(.timing) }
        if let v = e.emotion { emotion = .init(value: v, source: source, updatedAt: now, confidence: conf(.emotion)); changed.insert(.emotion) }
        if let v = e.tension { tension = .init(value: min(100, max(0, v)), source: source, updatedAt: now, confidence: conf(.tension)); changed.insert(.tension) }
        if !e.causes.isEmpty { causes = .init(value: e.causes, source: source, updatedAt: now, confidence: conf(.cause)); changed.insert(.cause) }
        if !e.body.isEmpty { body = .init(value: Self.consistentBody(e.body), source: source, updatedAt: now, confidence: conf(.body)); changed.insert(.body) }
        if let v = e.support { support = .init(value: v, source: source, updatedAt: now, confidence: conf(.support)); changed.insert(.support) }
        declined.formUnion(e.declined)
        declined.subtract(changed)
        return changed
    }

    /// 「特にない」「分からない」は具体的な症状と同時に持たない（具体的な症状を優先）
    static func consistentBody(_ s: Set<BodySignal>) -> Set<BodySignal> {
        let concrete = s.filter { !$0.isExclusive }
        if !concrete.isEmpty { return concrete }
        return s.contains(.none) ? [.none] : s
    }

    /// 既存の MeasurementContext（従来のスコアの補正）への対応。分からない項目は既定値のまま
    func measurementContext(base: MeasurementContext) -> MeasurementContext {
        var ctx = base
        if let s = situation?.value { ctx.scene = s.contextScene }
        var conds = Set<BodyCondition>()
        if activity?.value == .exercised { conds.insert(.running) }
        if sleep?.value.isShort == true { conds.insert(.sleepLack) }
        if !conds.isEmpty { ctx.conditions = conds }
        return ctx
    }
}

// MARK: - 端末内の抽出（キーワード。AI を使わないとき・AI の結果の補助）

nonisolated enum CheckInExtractor {

    /// 発言から取り出す。asked は直前に尋ねた項目（「わからない」「特にない」「50」などの短い答えの解釈に使う）
    static func extract(_ raw: String, asked: CheckInSlot?) -> CheckInExtraction {
        let text = latestClause(raw)
        var e = CheckInExtraction()
        if ["答えたくない", "言いたくない", "スキップ", "パス", "飛ばして"].contains(where: text.contains), let asked {
            e.declined.insert(asked)
            return e
        }
        e.sleep = sleep(text, asked: asked, tentative: &e.tentative)
        e.activity = firstMatch(text, [
            (.exercised, ["ランニング", "走った", "走って", "運動した", "運動して", "筋トレ", "部活", "トレーニング"]),
            (.light, ["散歩", "歩いた", "歩いて", "階段", "軽く体", "ストレッチした"]),
            (.usual, ["普段通り", "いつも通り", "普通に生活"]),
            (.little, ["動いてない", "動いていない", "ずっと座", "ほとんど動", "寝てた", "家にいた"]),
        ])
        e.condition = firstMatch(text, [
            (.unwell, ["体調が悪", "具合が悪", "気分が悪", "頭が痛", "熱が", "吐き気", "お腹が痛"]),
            (.veryTired, ["かなり疲れ", "すごく疲れ", "とても疲れ", "くたくた", "へとへと", "疲れ切"]),
            (.sluggish, ["だるい", "だるさ"]),
            (.slightlyTired, ["少し疲れ", "ちょっと疲れ", "疲れてる", "疲れている", "疲れた"]),
            (.energetic, ["元気"]),
        ])
        let situation = firstMatch(text, [
            (SituationKind.presentation, ["発表", "プレゼン", "スピーチ", "ゼミ"]),
            (.interviewExam, ["面接", "面談", "試験", "テスト", "受験", "検定"]),
            (.communication, ["初対面", "人と話", "会話", "コミュニケーション", "友達と", "飲み会"]),
            (.importantEvent, ["大事な予定", "大切な予定", "イベント", "デート", "試合", "大会", "発表会", "本番"]),
            (.restless, ["予定はない", "予定はないけど", "特に予定", "落ち着かない"]),
        ], lastWins: true)
        if let situation {
            e.situation = situation
            if situation != .restless { e.situationNote = MokorinSessionMemory.clippedNote(raw) }
        } else if asked == .situation, !text.isEmpty, !isUnsure(text) {
            e.situation = .other
            e.situationNote = MokorinSessionMemory.clippedNote(raw)
        }
        e.timing = firstMatch(text, [
            (.finished, ["終わった", "終わって", "昨日の", "さっき終わ", "もう済んだ"]),
            (.soon, ["これから", "もうすぐ", "直前", "今から", "すぐ", "このあと", "この後"]),
            (.today, ["今日", "午後", "夕方", "今夜"]),
            (.tomorrowOrLater, ["明日", "明後日", "来週", "今度", "週末", "来月"]),
            (.notSpecific, ["いつというわけ", "特にいつ", "いつでもない"]),
        ])
        e.emotion = firstMatch(text, [
            (.irritated, ["イライラ", "いらいら", "むかつ", "腹が立"]),
            (.unconfident, ["自信がない", "自信ない", "自信が持て"]),
            (.rushed, ["焦", "あせって", "あせる"]),
            (.anxious, ["不安", "心配", "怖い", "こわい"]),
            (.tense, ["緊張"]),
        ])
        if e.emotion == nil, asked == .emotion, isUnsure(text) { e.emotion = .unsure }
        e.tension = tension(text, asked: asked, tentative: &e.tentative)
        e.causes = Set(allMatches(text, [
            (WorryCause.failure, ["失敗"]),
            (.othersView, ["どう思われ", "人の目", "評価され", "見られ"]),
            (.speaking, ["うまく話せ", "話せるか", "言葉が出", "噛み", "かみそう"]),
            (.outcome, ["結果", "合否", "落ちたら", "受からな"]),
            (.ability, ["実力", "準備不足", "力が足りな", "できる気がしな"]),
            (.comparison, ["比べ", "周りの人", "周りが"]),
        ]))
        if e.causes.isEmpty, asked == .cause, isUnsure(text) { e.causes = [.unknown] }
        var body = Set(allMatches(text, [
            (BodySignal.heartPounding, ["ドキドキ", "どきどき", "動悸", "心臓"]),
            (.shallowBreath, ["呼吸が浅", "息が浅", "息苦し", "息が苦し"]),
            (.trembling, ["震え", "震えて", "ふるえ", "震える"]),
            (.tenseMuscles, ["力が入", "こわば", "体が固", "肩が", "強ばっ"]),
            (.foggy, ["ぼーっと", "ぼんやり", "頭が回らな"]),
        ]))
        if body.isEmpty, asked == .body {
            if ["特にない", "特に変化", "変化はない", "何もない", "ない"].contains(where: text.contains) { body = [.none] }
            else if isUnsure(text) { body = [.unsure] }
        }
        e.body = MokorinCheckIn.consistentBody(body)
        e.support = firstMatch(text, [
            (.calmDown, ["落ち着きたい", "落ち着かせたい", "リラックスしたい", "落ち着ける方法"]),
            (.organize, ["整理", "まとめたい", "考えを"]),
            (.confidence, ["自信をつけ", "自信が欲し", "自信を持ちたい"]),
            (.refresh, ["気分転換", "切り替え", "リフレッシュ"]),
            (.findMethod, ["合った方法", "おすすめ", "何がいい", "方法を知りたい"]),
        ])
        if e.support == nil, asked == .support, isUnsure(text) { e.support = .unsure }
        return e
    }

    /// 訂正（「〜じゃなくて」「やっぱり」）があれば、その後ろを優先する（後ろに情報がなければ全体）
    static func latestClause(_ text: String) -> String {
        let markers = ["じゃなくて", "ではなくて", "ではなく", "じゃなく", "って言ったけど", "と言ったけど", "やっぱり", "訂正", "間違えた", "実際は", "本当は"]
        guard let r = markers.compactMap({ text.range(of: $0, options: .backwards) }).max(by: { $0.upperBound < $1.upperBound }) else { return text }
        let tail = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.count >= 2 ? tail : text
    }

    static func isUnsure(_ text: String) -> Bool {
        ["わからない", "分からない", "よく分からない", "よくわからない", "わかんない"].contains(where: text.contains)
    }

    private static func sleep(_ text: String, asked: CheckInSlot?, tentative: inout Set<CheckInSlot>) -> SleepAmount? {
        if let hours = number(before: ["時間"], in: text), text.contains("寝") || text.contains("眠") || asked == .sleep {
            switch hours {
            case ..<3: return .under3
            case ..<5: return .h3to5
            case ..<7: return .h5to7
            case ..<9: return .h7to9
            default: return .over9
            }
        }
        if ["徹夜", "寝てない", "寝ていない", "ほとんど寝", "全然寝"].contains(where: text.contains) { return .under3 }
        if ["あまり寝られ", "あまり眠れ", "寝不足", "睡眠不足", "眠れなかった", "寝られなかった"].contains(where: text.contains) {
            tentative.insert(.sleep)   // 時間ははっきりしない
            return .h3to5
        }
        if ["ぐっすり", "よく寝", "よく眠れ", "しっかり寝"].contains(where: text.contains) { tentative.insert(.sleep); return .h7to9 }
        if asked == .sleep, ["覚えてない", "覚えていない"].contains(where: text.contains) || isUnsure(text) { return .unknown }
        return nil
    }

    private static func tension(_ text: String, asked: CheckInSlot?, tentative: inout Set<CheckInSlot>) -> Int? {
        if asked == .tension, let n = number(before: ["", "くらい", "ぐらい", "点", "%"], in: text), (0...100).contains(n) { return Int(n) }
        if ["緊張してない", "緊張していない", "緊張はしてない", "全然緊張", "落ち着いてる", "落ち着いている"].contains(where: text.contains) { return 0 }
        guard text.contains("緊張") else { return nil }
        if ["非常に", "めちゃくちゃ", "ものすごく", "すごく強く", "限界"].contains(where: text.contains) { return 100 }
        if ["かなり", "すごく", "とても", "めちゃ"].contains(where: text.contains) { return 75 }
        if ["少し", "ちょっと", "やや", "少々"].contains(where: text.contains) { return 20 }
        tentative.insert(.tension)   // 強さがはっきりしない
        return 50
    }

    /// 「5時間」「70くらい」などの数（全角も可）
    private static func number(before suffixes: [String], in text: String) -> Double? {
        let normalized = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*(" + suffixes.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let r = Range(m.range(at: 1), in: normalized) else { return nil }
        return Double(normalized[r])
    }

    private static func firstMatch<V>(_ text: String, _ table: [(V, [String])], lastWins: Bool = false) -> V? {
        if lastWins {
            return table.compactMap { v, words -> (V, String.Index)? in
                words.compactMap { text.range(of: $0, options: .backwards)?.lowerBound }.max().map { (v, $0) }
            }.max(by: { $0.1 < $1.1 })?.0
        }
        return table.first { _, words in words.contains(where: text.contains) }?.0
    }

    private static func allMatches<V>(_ text: String, _ table: [(V, [String])]) -> [V] {
        table.filter { _, words in words.contains(where: text.contains) }.map(\.0)
    }
}
