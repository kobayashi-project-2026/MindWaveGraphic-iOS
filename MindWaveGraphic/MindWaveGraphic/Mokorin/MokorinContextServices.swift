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
        (.interview, ["面接", "面談", "発表", "プレゼン", "スピーチ", "ゼミ"]),
        (.sports,    ["試合", "大会", "競技", "レース"]),
        (.important, ["大切な", "大事な", "デート", "約束", "初対面", "初めて会う", "はじめて会う"]),
        (.work,      ["作業", "仕事", "勉強", "集中", "試験", "テスト", "受験", "会議"]),
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

    /// 訂正を表す言い回し（「面接じゃなくて試合」「面接って言ったけど、実際は発表」など）
    private static let correctionMarkers = ["じゃなくて", "ではなくて", "ではなく", "じゃなく", "って言ったけど", "と言ったけど",
                                            "っていうか", "というか", "間違えた", "訂正", "実際は", "本当は"]

    /// 文章から場面・身体状態を読み取る。訂正の言い回しがあれば、その後ろの内容（最新の発言）を優先する
    static func interpret(_ text: String) -> (scene: ContextScene?, conditions: Set<BodyCondition>) {
        if let range = correctionMarkers.compactMap({ text.range(of: $0, options: .backwards) }).max(by: { $0.upperBound < $1.upperBound }) {
            let corrected = interpretRaw(String(text[range.upperBound...]))
            if corrected.scene != nil || !corrected.conditions.isEmpty { return corrected }
        }
        return interpretRaw(text)
    }

    private static func interpretRaw(_ text: String) -> (scene: ContextScene?, conditions: Set<BodyCondition>) {
        // 複数の場面の言葉があるときは、最後に出てきたものを採る（後から言い直したことを優先）
        var scene = sceneWords.compactMap { scene, words -> (ContextScene, String.Index)? in
            let positions = words.compactMap { text.range(of: $0, options: .backwards)?.lowerBound }
            return positions.max().map { (scene, $0) }
        }.max(by: { $0.1 < $1.1 })?.0
        // 「予定は特にない」は安静として扱う（場面の段階での答え）
        if scene == nil, ["予定はない", "予定は特にない", "特に予定", "何もない"].contains(where: { text.contains($0) }) { scene = .calm }
        var conditions = Set(conditionWords.filter { _, words in words.contains { text.contains($0) } }.map(\.0))
        if conditions.contains(.none) && conditions.count > 1 { conditions.remove(.none) }
        return (scene, conditions)
    }

    /// 発言の意図（端末内の判定）。サーバーの user_intent と同じ分類
    static func interpretIntent(_ text: String) -> MokorinUserIntent {
        if ["測りたくない", "測定しない", "測定したくない", "やめておく", "今日はいい", "測らなくていい",
            "終わりにしたい", "終わりたい", "もういい", "会話を終え", "やめたい", "話すのをやめ"].contains(where: text.contains) { return .declineMeasurement }
        if ["もう測りたい", "測定を始めて", "早く測りたい", "すぐ測りたい", "測定したい"].contains(where: text.contains) { return .ready }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("？") || t.hasSuffix("?") { return .question }
        return .answer
    }

    /// 主観的な緊張（自己申告）を読み取る。はっきりした言葉がなければ nil
    static func interpretTension(_ text: String) -> SubjectiveTension? {
        let negated = ["緊張してない", "緊張していない", "緊張はしてない", "緊張はない", "緊張しない"]
        if negated.contains(where: { text.contains($0) }) || ["落ち着いて", "大丈夫", "リラックス"].contains(where: { text.contains($0) }) {
            return .calm
        }
        let tense = ["緊張", "ドキドキ", "どきどき", "不安"].contains(where: { text.contains($0) })
        guard tense else { return nil }
        if ["かなり", "すごく", "とても", "めちゃ", "すごい", "やばい"].contains(where: { text.contains($0) }) { return .high }
        if ["少し", "ちょっと", "やや", "少々"].contains(where: { text.contains($0) }) { return .slight }
        return .slight
    }
}

// MARK: - もこりんの定型文（外部AIを使えないとき・ボタンで答えたとき）

nonisolated enum MokorinScript {
    /// 最初の質問（主観的な緊張）
    /// 最初のあいさつ（緊張していると決めつけない。2026-11-11 の指定）
    static let greeting = "こんにちは！今日もおつかれさま！今日はどんな感じ？まずは今の自分の状態を一緒に確認してみよう！"

    /// 尋ねた項目に答えがなかったとき（1 回だけ）
    static func checkInClarify(_ slot: CheckInSlot, gotOther: Bool) -> String {
        (gotOther ? "教えてくれてありがとう。" : "ごめんね、うまく受け取れなかったかも。")
            + "\(slot.question)\n下から選んでも、「答えない」でとばしても大丈夫だよ。"
    }

    /// 一般的な相づち（続けて同じものを使わない）
    static let genericAcks = ["そっか。", "なるほど。", "教えてくれてありがとう。", "うんうん。"]

    /// 答えへの反応（本人の言葉を受けて 1〜2 文。訂正は受け止める）。続ける質問とつなげやすい形にする
    static func composedReaction(changed: Set<CheckInSlot>, checkIn c: MokorinCheckIn, previous: MokorinCheckIn) -> String? {
        if changed.contains(.condition), c.condition?.value == .unwell {
            return "体調が悪いんだね。無理をしないで、今は休むことを優先しよう。"
        }
        var parts: [String] = []
        if changed.contains(.situation), let s = c.situation?.value {
            if let old = previous.situation?.value, old != s {
                parts.append("\(eventNoun(s, note: c.situationNote))だったんだね、了解！")
            } else if s == .restless {
                parts.append("予定はないけど、落ち着かないんだね。")
            } else {
                parts.append("\(timingPrefix(c.timing?.value, note: c.situationNote))\(eventNoun(s, note: c.situationNote))なんだね。")
            }
        } else if changed.contains(.timing), let t = c.timing?.value {
            parts.append(t == .finished ? "もう終わったことなんだね。" : "\(t.label)なんだね。")
        }
        if changed.contains(.sleep), let v = c.sleep?.value {
            if v.isShort { parts.append("睡眠も短かったみたいだね。") }
            else if v == .h7to9 || v == .over9 { parts.append("よく眠れたんだね。") }
        }
        if changed.contains(.condition), let v = c.condition?.value {
            switch v {
            case .energetic: parts.append("元気なんだね、よかった！")
            case .slightlyTired: parts.append("少し疲れてるんだね。")
            case .veryTired, .sluggish: parts.append("かなりしんどいんだね。無理しないでね。")
            case .unwell: break
            }
        }
        if changed.contains(.emotion), let v = c.emotion?.value {
            let t: [FeelingKind: String] = [.tense: "緊張してるんだね。", .anxious: "不安なんだね。", .rushed: "焦ってるんだね。",
                                            .unconfident: "自信が持てないんだね。", .irritated: "イライラしてるんだね。", .unsure: "よく分からない感じなんだね。それでも大丈夫だよ。"]
            if let line = t[v] { parts.append(line) }
        }
        if changed.contains(.tension), let t = c.tension?.value, !changed.contains(.emotion) {
            parts.append(t == 0 ? "今は落ち着いてるんだね。" : "緊張は\(t)くらいなんだね。")
        }
        if changed.contains(.cause), let causes = c.causes?.value, let first = WorryCause.allCases.first(where: causes.contains), first != .unknown {
            parts.append("「\(first.label)」が気になってるんだね。")
        }
        if changed.contains(.body), let b = c.body?.value {
            if b.contains(.shallowBreath) { parts.append("息が苦しいなら、無理はしないでね。") }
            else if b.contains(.heartPounding) { parts.append("胸がドキドキしてるんだね。") }
            else if b == [.none] { parts.append("体は落ち着いてるんだね。") }
        }
        if changed.contains(.support), let v = c.support?.value, v != .unsure {
            parts.append("「\(v.label)」だね。")
        }
        guard !parts.isEmpty else { return nil }
        // 長くしない（最初の 2 つ）。最後が「〜みたいだね。」なら、続く質問へ「〜みたいだけど、」でつなぐ
        return parts.prefix(2).joined()
    }

    /// 反応と質問をつなぐ（「睡眠も短かったみたいだね。」＋質問 →「睡眠も短かったみたいだけど、」＋質問）
    static func join(reaction: String?, question: String) -> String {
        guard let r = reaction else { return question }
        if r.hasSuffix("みたいだね。") { return String(r.dropLast(2)) + "けど、" + question }   // 「〜みたいだね。」→「〜みたいだけど、」
        return r + question
    }

    private static func timingPrefix(_ t: EventTiming?, note: String?) -> String {
        switch t {
        case .soon?: return "これから"
        case .today?: return "今日"
        case .tomorrowOrLater?: return (note?.contains("明日") ?? false) ? "明日" : "今度の"
        case .finished?: return "終わった"
        default: return ""
        }
    }

    private static func eventNoun(_ s: SituationKind, note: String?) -> String {
        let n = note ?? ""
        switch s {
        case .presentation: return "発表"
        case .interviewExam: return ["試験", "テスト", "受験"].contains(where: n.contains) ? "試験" : "面接"
        case .communication: return "人と会う予定"
        case .importantEvent: return ["試合", "大会"].contains(where: n.contains) ? "試合" : "大事な予定"
        case .restless: return "予定のない日"
        case .other: return "その予定"
        }
    }

    /// 答えへの短い反応（同じ相づちを続けない。睡眠・体調・気持ちには具体的に返す）
    static func checkInReaction(changed: Set<CheckInSlot>, checkIn c: MokorinCheckIn, turn: Int) -> String? {
        if changed.contains(.condition), let v = c.condition?.value {
            switch v {
            case .unwell: return "体調が悪いんだね。無理をしないで、今は休むことを優先しよう。"
            case .veryTired, .sluggish: return "かなりしんどいんだね。無理しないでね。"
            case .slightlyTired: return "少し疲れているんだね。"
            case .energetic: return "元気なんだね、よかった！"
            }
        }
        if changed.contains(.sleep), let v = c.sleep?.value { return v.reaction }
        if changed.contains(.emotion), let v = c.emotion?.value {
            switch v {
            case .irritated: return "イライラしているんだね。そういうときもあるよ。"
            case .unsure: return "自分でもよく分からないんだね。それでも大丈夫だよ。"
            case .unconfident: return "自信が持てないんだね。"
            case .rushed: return "焦っているんだね。"
            case .anxious: return "不安や心配があるんだね。"
            case .tense: return "緊張しているんだね。"
            }
        }
        if changed.contains(.body), c.body?.value.contains(.shallowBreath) == true {
            return "呼吸が浅い・苦しい感じがあるんだね。苦しさが強いときは、無理をせず休んでね。"
        }
        if changed.isEmpty { return nil }
        return genericAcks[abs(turn) % genericAcks.count]
    }

    /// 質問を終えたときのまとめ（推薦は理由つきで最大 2 つ。測定・改善へ進むかは本人が決める）
    static func checkInSummary(_ c: MokorinCheckIn, recommendations: [MethodRecommendation]) -> String {
        if c.needsRestFirst {
            return "今日は無理をしないで、休むことを優先しよう。つらさが強いときは、近くの人や医療機関に相談してね。"
        }
        var parts: [String] = []
        if let s = c.situation?.value, s != .other, s != .restless {
            parts.append(timingPrefix(c.timing?.value, note: c.situationNote) + eventNoun(s, note: c.situationNote) + "の前")
        }
        if let t = c.tension?.value { parts.append("緊張は\(t)くらい") }
        let head = parts.isEmpty ? "ありがとう、よく分かったよ。" : "ありがとう。" + parts.joined(separator: "で、") + "なんだね。"
        guard let first = recommendations.first else {
            return head + "今は特に何もしなくても大丈夫そう。測定してみようか？"
        }
        return head + "おすすめは「\(first.method.title)」だよ。測定するか、改善方法を見てみよう。"
    }

    /// アプリ内から会話を開いたときのあいさつ。続けて最初の質問を出すため、ここでは質問しない。
    /// 場面が未設定（既定値）のときは触れない（未計測を「安静」と断定しない）
    static func greetingForEdit(current: MeasurementContext) -> String {
        guard current != .default else {
            return "こんにちは！今の様子を一緒に確認しよう。"
        }
        return "こんにちは！前に聞いた場面は「\(current.scene.displayName)」だったね。変わったことがあれば教えてね。"
    }

    static let askTensionAgain = "教えてくれてありがとう。今の気持ちに近いのはどれかな？話しても、下から選んでも大丈夫だよ。"

    /// 緊張の答えを受けて場面を尋ねる
    static func askScene(after tension: SubjectiveTension?) -> String {
        switch tension {
        case .high, .slight: return "そっか。何か予定があるの？"
        case .calm:          return "落ち着いているんだね。何か予定はある？"
        case nil:            return "何か予定があるのかな？"
        }
    }

    static let askScene = "何か予定があるのかな？面接や試合、作業など、近いものを教えてね。"

    static func askCondition(scene: ContextScene) -> String {
        askCondition(topic: MokorinTopic.detect(text: nil, scene: scene), fatigue: false)
    }

    /// 話題に合わせて身体状態を尋ねる（試合ならウォーミングアップ、疲れていると話したら気づかう）
    static func askCondition(topic: MokorinTopic, fatigue: Bool) -> String {
        let care = fatigue ? "疲れているんだね。無理しないでね。" : ""
        let question = topic == .sports ? "ウォーミングアップで体を動かしたあと？それとも座って落ち着いてる？"
                                        : "今は落ち着いて座ってる？それとも移動してきたところ？"
        return care + topic.lead + question
    }

    /// 緊張の理由がわからないと話したとき
    static let askSceneUnknownReason = "理由がわからなくても大丈夫だよ。これから何か予定はある？"

    /// 測定を望まないとき（説得しない）
    static let declineAck = "わかった、ここまでにしよう。測らなくても大丈夫だよ。気が向いたら、また声をかけてね。"

    /// AI を使わないときでも答えられる、よくある質問（答えられなければ nil）
    static func localAnswer(to text: String) -> String? {
        if ["方法", "どうしたら", "どうすれば", "何をすれば", "なにをすれば"].contains(where: text.contains) {
            return "呼吸法（4-7-8・ボックス・2-1-4）や、肩や首のストレッチ、まわりに意識を向ける方法があるよ。話を聞いたら、今のあなたに合うものをおすすめするね。"
        }
        if text.contains("測定") || text.contains("計測") {
            return "測定では、心拍などを見ながら今の状態をグラフィックで表すよ。準備ができたら一緒に始めよう。"
        }
        if text.contains("もこりん") && (text.contains("誰") || text.contains("だれ") || text.contains("何者")) {
            return "もこりんは、緊張や気持ちの整理を手伝うキャラクターだよ。"
        }
        return nil
    }

    /// 外部AIを使わないときに質問・雑談をされた場合
    static func cannotAnswerLocally(canEnableAI: Bool) -> String {
        canEnableAI ? "ごめんね、今は質問にうまく答えられないんだ。「AIと話す」を押すと、自由な言葉で話せるよ。"
                    : "ごめんね、今は質問にうまく答えられないんだ。"
    }

    static let askConditionAgain = "からだの状態を教えてね。走ってきた・階段を上った・コーヒーを飲んだなど。特になければ「座って落ち着いてる」を選んでね。"

    static func summary(scene: ContextScene, conditions: Set<BodyCondition>) -> String {
        summary(topic: MokorinTopic.detect(text: nil, scene: scene), conditions: conditions)
    }

    static func summary(topic: MokorinTopic, conditions: Set<BodyCondition>) -> String {
        "教えてくれてありがとう。\(topic.shortLabel)で、\(conditionPhrase(conditions))なんだね。この状況で測定してみようか？"
    }

    private static func sceneLead(_ scene: ContextScene) -> String {
        switch scene {
        case .interview: return "面接前なんだね。"
        case .sports:    return "試合や大会の前なんだね。"
        case .important: return "大切な予定の前なんだね。"
        case .work:      return "作業や集中の時間なんだね。"
        case .calm:      return "落ち着いているときなんだね。"
        case .other:     return "教えてくれてありがとう。"
        }
    }

    static func sceneShort(_ scene: ContextScene) -> String {
        switch scene {
        case .interview: return "面接前"
        case .sports:    return "試合や大会の前"
        case .important: return "大切な予定の前"
        case .work:      return "作業や集中のとき"
        case .calm:      return "安静にしているとき"
        case .other:     return "その他の場面"
        }
    }

    static func conditionPhrase(_ conditions: Set<BodyCondition>) -> String {
        let ordered = BodyCondition.allCases.filter { conditions.contains($0) && $0 != .none }
        if ordered.isEmpty { return "落ち着いて座っている状態" }
        let phrases: [String] = ordered.map {
            switch $0 {
            case .running:   return "走ってきた直後"
            case .stairs:    return "階段を上った直後"
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

    /// 感情を決めつけすぎないよう、はっきりした言葉があるときだけ sad / sleepy / jump にする
    static func forReply(step: MokorinContextViewModel.Step, userText: String?, conditions: Set<BodyCondition>,
                         tension: SubjectiveTension? = nil) -> (MokorinEmotion, MokorinAction) {
        let text = userText ?? ""
        if ["つらい", "悲しい", "しんどい", "落ち込"].contains(where: { text.contains($0) }) { return (.sad, .nod) }
        if conditions.contains(.sleepLack) || ["眠い", "ねむい", "寝不足"].contains(where: { text.contains($0) }) { return (.sleepy, .nod) }
        if ["楽しみ", "がんばる", "頑張る", "わくわく", "ワクワク"].contains(where: { text.contains($0) }) { return (.happy, .jump) }
        if step == .review { return (.happy, .nod) }
        switch tension {
        case .high, .slight: return (.calm, .nod)
        case .calm:          return (.happy, .nod)
        case nil:            return (.calm, .nod)
        }
    }
}

// MARK: - 選択肢（クイック返信）

/// 会話の段階に応じて表示する選択肢。タップしても文章を入力したのと同じ扱いで会話が進む
nonisolated enum MokorinQuickReply: Hashable, Sendable {
    case tension(SubjectiveTension)
    case scene(ContextScene)
    /// 予定は特にない（安静）
    case noPlan
    case condition(BodyCondition)
    case confirmConditions
    /// 場面・身体状態の一覧（編集シート）を開く。必要なときだけ表示する
    case showList
    /// 外部AIに接続できなかった発言を送り直す
    case retry
    /// 外部AIを使わずに、端末内の判定で会話を続ける
    case continueWithoutAI
    /// 測定を望まないとき: 測定しないで会話を終える（「あとで選ぶ」と同じ処理）
    case skipMeasurement
    /// 測定を望まないと言ったあとで、やっぱり会話を続ける
    case keepTalking
    /// 会話の情報（STEP 0〜6）の選択肢
    case checkIn(CheckInOption)

    var label: String {
        switch self {
        case .showList:          return "一覧から選ぶ"
        case .retry:             return "もう一度送る"
        case .continueWithoutAI: return "AIなしで続ける"
        case .skipMeasurement:   return "測定しないで終える"
        case .keepTalking:       return "やっぱり続ける"
        case .checkIn(let o):    return o.label
        case .tension(let t): return t.replyLabel
        case .noPlan:         return "特に予定はない"
        case .scene(let s):
            switch s {
            case .interview: return "面接・発表"
            case .sports:    return "試合・大会"
            case .important: return "大切な予定"
            case .work:      return "作業・集中"
            case .calm:      return "安静"
            case .other:     return "その他"
            }
        case .condition(let c):
            switch c {
            case .none:      return "座って落ち着いてる"
            case .stairs:    return "階段・移動してきた"
            case .running:   return "走ってきた"
            case .caffeine:  return "カフェインをとった"
            case .sleepLack: return "寝不足"
            case .afterMeal: return "食後"
            case .smoking:   return "喫煙後"
            }
        case .confirmConditions: return "これで決定"
        }
    }
}
