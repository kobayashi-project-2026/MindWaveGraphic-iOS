// MokorinAdviceEngine.swift
// Mokorin
//
// もこりんの「その人の状況に合った次の行動」の提案（端末内・決定的）。
//
// 方針（docs/MOKORIN_PERSONALIZED_ADVICE.md）:
// - 本人が話したこと（場面・身体状態・予定の言葉）と、存在する記録だけを根拠にする。推測で補わない
// - 提案は任意で試せる日常の準備・セルフケアに限る。診断・病名・治療の話はしない
// - 深刻な体の症状が話されたら提案をやめ、近くの人・医療機関への相談を案内する
// - 一般論を並べない。状況ごとに 1〜2 個、理由（どの発言に基づくか）を添える
// - 「試してみた？」は 1 回だけ（会話の側で管理する）

import Foundation

// MARK: - 測定前の会話で理解した内容

/// 測定前の会話でもこりんが理解した内容。メモリ上だけに置き、保存・外部送信しない（ログアウト・やり直しで消える）
nonisolated struct MokorinSessionMemory: Equatable, Sendable {
    /// 本人の主観的な緊張（自己申告。計測値ではなく、スコア計算に使わない）
    var tension: SubjectiveTension?
    var scene: ContextScene
    var conditions: Set<BodyCondition>
    /// 本人が話した予定の短い言葉（既存の場面に分類しきれない内容: 試験・初対面など）。40 文字まで
    var situationNote: String?
    /// 疲れている・しんどいと本人が話した
    var mentionedFatigue: Bool = false
    /// 本人が今は測定を望まなかった
    var declinedMeasurement: Bool = false
    var capturedAt: Date = Date()

    static let maxNoteChars = 40

    static func clippedNote(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return t.count > maxNoteChars ? String(t.prefix(maxNoteChars)) : t
    }
}

// MARK: - 話題（既存の場面より細かい、提案・言い回し用の分類）

/// 提案と言い回しを選ぶための話題。既存の JSON 契約の場面（ContextScene）は変えず、本人の言葉から細かく分ける
nonisolated enum MokorinTopic: String, CaseIterable, Sendable {
    case interview, presentation, exam, sports, important, firstMeeting, work, rest, unknown

    /// 本人の言葉を優先し、なければ既存の場面から決める
    static func detect(text: String?, scene: ContextScene?) -> MokorinTopic {
        if let text, let t = fromWords(text) { return t }
        switch scene {
        case .interview: return .interview
        case .sports:    return .sports
        case .important: return .important
        case .work:      return .work
        case .calm:      return .rest
        case .other, nil: return .unknown
        }
    }

    /// 言葉だけから決める（見つからなければ nil）。具体的なものを先に判定する
    static func fromWords(_ text: String) -> MokorinTopic? {
        let table: [(MokorinTopic, [String])] = [
            (.presentation, ["発表", "プレゼン", "スピーチ", "ゼミ"]),
            (.interview,    ["面接", "面談"]),
            (.exam,         ["試験", "テスト", "受験", "検定"]),
            (.sports,       ["試合", "大会", "競技", "レース", "部活"]),
            (.firstMeeting, ["初対面", "はじめて会う", "初めて会う", "初めての人", "知らない人"]),
            (.important,    ["デート", "大切な", "大事な", "約束"]),
            (.work,         ["仕事", "作業", "勉強", "会議", "課題", "レポート"]),
        ]
        // 訂正（「面接じゃなくて発表」）では後ろに出てきた言葉を優先する
        return table.compactMap { topic, words -> (MokorinTopic, String.Index)? in
            words.compactMap { text.range(of: $0, options: .backwards)?.lowerBound }.max().map { (topic, $0) }
        }.max(by: { $0.1 < $1.1 })?.0
    }

    /// 会話で使う短い言い方（「〜の前なんだね」）
    var lead: String {
        switch self {
        case .interview:    return "面接前なんだね。"
        case .presentation: return "発表の前なんだね。"
        case .exam:         return "試験の前なんだね。"
        case .sports:       return "試合や大会の前なんだね。"
        case .important:    return "大切な予定の前なんだね。"
        case .firstMeeting: return "初めての人と会うんだね。"
        case .work:         return "作業や集中の時間なんだね。"
        case .rest:         return "落ち着いているときなんだね。"
        case .unknown:      return "教えてくれてありがとう。"
        }
    }

    var shortLabel: String {
        switch self {
        case .interview:    return "面接前"
        case .presentation: return "発表の前"
        case .exam:         return "試験の前"
        case .sports:       return "試合や大会の前"
        case .important:    return "大切な予定の前"
        case .firstMeeting: return "初めての人と会う前"
        case .work:         return "作業や集中のとき"
        case .rest:         return "安静にしているとき"
        case .unknown:      return "その他の場面"
        }
    }
}

// MARK: - 提案

/// 1 つの提案（任意で試せる行動）
nonisolated struct MokorinAdvice: Equatable, Identifiable, Sendable {
    let id: String
    /// 提案の文（短い話し言葉）
    let text: String
    /// 何に基づく提案か（確認済みの事実）
    let basis: String
    /// 1 回だけ尋ねる確認（nil = 確認しない）
    let followUp: String?
}

nonisolated enum MokorinAdviceResult: Equatable, Sendable {
    /// 状況に合った提案（1〜2 個）
    case advice([MokorinAdvice])
    /// 深刻な症状が話されたため、提案せず相談を案内する
    case seekHelp(String)

    var items: [MokorinAdvice] {
        if case .advice(let a) = self { return a }
        return []
    }
}

nonisolated struct MokorinAdviceInput: Equatable, Sendable {
    var topic: MokorinTopic
    var conditions: Set<BodyCondition> = []
    var tension: SubjectiveTension? = nil
    var mentionedFatigue: Bool = false
    /// 本人の最近の発言（深刻な症状の確認に使う。保存しない）
    var recentUserText: String = ""
}

nonisolated enum MokorinAdviceEngine {

    static let seekHelpMessage = "体のつらさが強いときは、もこりんだけでは判断できないよ。無理をせず、近くの人や医療機関に相談してね。急に具合が悪くなったときは、迷わず救急（119）を呼んでね。"

    /// 深刻な体の症状・危険を示す言葉（提案をやめて相談を案内する）
    static func mentionsSeriousSymptom(_ text: String) -> Bool {
        ["胸が痛", "胸の痛", "胸が苦し", "息苦し", "息ができ", "呼吸が苦し", "気を失", "意識が", "めまいがひど", "倒れそう",
         "動悸が止まらな", "しびれ", "死にたい", "消えたい"].contains { text.contains($0) }
    }

    /// 疲れ・しんどさの言葉
    static func mentionsFatigue(_ text: String) -> Bool {
        ["疲れ", "つかれ", "しんどい", "だるい", "眠い", "ねむい", "へとへと", "くたくた"].contains { text.contains($0) }
    }

    /// 状況に合った提案を 1〜2 個返す
    static func advise(_ input: MokorinAdviceInput) -> MokorinAdviceResult {
        if mentionsSeriousSymptom(input.recentUserText) { return .seekHelp(seekHelpMessage) }
        var items: [MokorinAdvice] = []
        // 1) 疲れ・睡眠不足は無理をさせない提案を先にする
        if input.mentionedFatigue || input.conditions.contains(.sleepLack) {
            items.append(MokorinAdvice(id: "rest_break",
                                       text: "少し休憩できそう？無理をせず、今できることから考えよう。",
                                       basis: input.conditions.contains(.sleepLack) ? "睡眠不足と話していたから" : "疲れていると話していたから",
                                       followUp: "少し休めた？"))
        }
        // 2) 場面に合った準備
        if let scene = sceneAdvice(input.topic, tension: input.tension) { items.append(scene) }
        // 3) 測定の条件に関わる身体状態（計測値の見方の注意。行動の押しつけはしない）
        if input.conditions.contains(.running) || input.conditions.contains(.stairs) {
            items.append(MokorinAdvice(id: "settle_before_measure",
                                       text: "動いた直後は心拍が上がりやすいよ。測り直すなら、数分座って息が落ち着いてからにしてみよう。",
                                       basis: input.conditions.contains(.running) ? "走ってきたと話していたから" : "階段や移動のあとと話していたから",
                                       followUp: nil))
        } else if input.conditions.contains(.caffeine) {
            items.append(MokorinAdvice(id: "caffeine_note",
                                       text: "コーヒーなどのあとは心拍に影響することがあるよ。結果を見るときに思い出してね。",
                                       basis: "カフェインをとったと話していたから", followUp: nil))
        }
        // 同じ提案を重ねず、最大 2 個
        var seen = Set<String>()
        return .advice(Array(items.filter { seen.insert($0.id).inserted }.prefix(2)))
    }

    private static func sceneAdvice(_ topic: MokorinTopic, tension: SubjectiveTension?) -> MokorinAdvice? {
        switch topic {
        case .interview:
            return MokorinAdvice(id: "interview_first_answer",
                                 text: "最初に聞かれそうな質問への答えを、一度だけ声に出して言ってみよう。",
                                 basis: "面接の前と話していたから", followUp: "声に出してみた？")
        case .presentation:
            return MokorinAdvice(id: "presentation_opening",
                                 text: "冒頭の30秒だけ、声に出して練習しておくと話し始めやすくなるかもしれないね。",
                                 basis: "発表の前と話していたから", followUp: "冒頭、言ってみた？")
        case .exam:
            return MokorinAdvice(id: "exam_first_question",
                                 text: "始まったら、まず解けそうな問題を1つ見つけてから進めよう。",
                                 basis: "試験の前と話していたから", followUp: nil)
        case .sports:
            return MokorinAdvice(id: "sports_warmup",
                                 text: "ウォーミングアップはもう終わった？まだなら、いつもの準備から始めよう。",
                                 basis: "試合や大会の前と話していたから", followUp: "いつもの準備、できた？")
        case .important:
            return MokorinAdvice(id: "important_first_topic",
                                 text: "会ったら最初に話したいことを1つだけ決めておくと、始めやすいよ。",
                                 basis: "大切な予定の前と話していたから", followUp: nil)
        case .firstMeeting:
            return MokorinAdvice(id: "first_meeting_greeting",
                                 text: "最初のあいさつと、聞いてみたいことを1つだけ用意しておこう。",
                                 basis: "初めての人と会うと話していたから", followUp: nil)
        case .work:
            return MokorinAdvice(id: "work_first_block",
                                 text: "最初の25分だけ集中する、と区切って始めてみよう。",
                                 basis: "作業や勉強の前と話していたから", followUp: "区切って始められた？")
        case .rest:
            // 落ち着いているときは行動を求めない
            return MokorinAdvice(id: "rest_keep",
                                 text: "今の落ち着いた状態の記録も、あとで比べるときの参考になるよ。",
                                 basis: "落ち着いていると話していたから", followUp: nil)
        case .unknown:
            guard tension == .slight || tension == .high else { return nil }
            return MokorinAdvice(id: "unknown_one_step",
                                 text: "理由がはっきりしなくても大丈夫。ゆっくり3回呼吸して、今できることを1つだけ決めよう。",
                                 basis: "緊張していると話していたから", followUp: nil)
        }
    }
}
