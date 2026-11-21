// MokorinMethodAdvisor.swift
// Mokorin
//
// 会話で集めた情報（MokorinCheckIn）から、改善方法を最大 2 つ推薦する（端末内・決定的。理由を必ず付ける）。
// 代表パターン（2026-11-11 の指定）:
//   A 緊張が強い → 無理のない呼吸・筋弛緩
//   B 考えすぎ → 不安の言語化・「準備できること／変えられないこと」の整理・冒頭の練習・追加の対話
//   C 気持ちを切り替えたい → グラウンディング・肩や首のストレッチ・短い休憩
//   D 自分の状態が分からない → 状態の確認（HR・SDNN は参考）・言葉にする対話
//   E 自信をつけたい → できたことの振り返り・強みの言語化・短い練習
// 安全: 体調が悪いときは休息を優先し、息苦しさがあるときは息を止める時間が長い呼吸法（4-7-8・BOX）を推薦しない。
// 本人は推薦以外の方法も自由に選べる（画面側）。AI はこの推薦の理由の説明・言い換えを担い、方法の選択はここで決める。

import Foundation

/// 改善方法。ガイド（タイマーとグラフィック）があるものは呼吸法の 3 つ。ほかはもこりんが手順を案内する
nonisolated enum ImprovementMethod: String, CaseIterable, Codable, Sendable {
    case breathing478, box, breathing214
    case muscleRelaxation = "muscle_relaxation", stretch, grounding, shortBreak = "short_break"
    case worrySort = "worry_sort", openingPractice = "opening_practice", strengthReview = "strength_review"
    case answerPractice = "answer_practice", stateCheck = "state_check", talkMore = "talk_more", rest

    var title: String {
        switch self {
        case .breathing478: return "4-7-8 呼吸"
        case .box: return "ボックス呼吸"
        case .breathing214: return "2-1-4 呼吸（ゆっくり吐く）"
        case .muscleRelaxation: return "筋弛緩（力を入れて抜く）"
        case .stretch: return "肩・首のストレッチ"
        case .grounding: return "まわりに意識を向ける（グラウンディング）"
        case .shortBreak: return "30〜90秒の小休憩"
        case .worrySort: return "心配ごとを整理する"
        case .openingPractice: return "冒頭の30秒を練習する"
        case .strengthReview: return "できたこと・強みを振り返る"
        case .answerPractice: return "回答を短く練習する"
        case .stateCheck: return "今の状態を確かめる"
        case .talkMore: return "もこりんと話して整理する"
        case .rest: return "休む"
        }
    }

    /// 息を止める時間が長い（息苦しさ・めまいがあるときは推薦しない）
    var hasLongBreathHold: Bool { self == .breathing478 || self == .box }

    /// もこりんが案内する短い手順（ガイドのない方法）
    var steps: [String] {
        switch self {
        case .muscleRelaxation: return ["両手をぎゅっと5秒にぎる", "ふっと力を抜いて10秒感じる", "肩でも同じように2回くり返す"]
        case .stretch: return ["肩をゆっくり3回まわす", "首を左右にゆっくり倒す", "胸をひらいて深く息を吐く"]
        case .grounding: return ["見えるものを5つ数える", "聞こえる音を3つ探す", "足の裏が床についている感覚を確かめる"]
        case .shortBreak: return ["画面から目を離す", "30〜90秒、ゆっくり座るか少し歩く"]
        case .worrySort: return ["気になることを1つずつ書き出す", "「今準備できること」と「今は変えられないこと」に分ける", "準備できることを1つだけ選ぶ"]
        case .openingPractice: return ["最初の一言を決める", "冒頭の30秒を声に出して1回言ってみる"]
        case .strengthReview: return ["これまでにできたことを1つ思い出す", "自分の強みを一言で言ってみる"]
        case .answerPractice: return ["聞かれそうな質問を1つ選ぶ", "30秒で答えを声に出してみる"]
        case .stateCheck: return ["今の気持ちを一言で言ってみる", "体で気になるところがあるか確かめる"]
        case .talkMore: return ["気になっていることを、もこりんに話してみる"]
        case .rest: return ["無理をせず、座るか横になって休む"]
        default: return []
        }
    }
}

nonisolated struct MethodRecommendation: Equatable, Sendable {
    let method: ImprovementMethod
    /// なぜこの方法か（短く。本人が話したことに基づく）
    let reason: String
    /// 推奨の実施時間（秒）。本人が変えられる
    let suggestedSeconds: Int
}

nonisolated enum MokorinMethodAdvisor {

    /// 推薦（最大 2 つ）。体調が悪いときは休息だけ
    static func recommend(_ c: MokorinCheckIn) -> [MethodRecommendation] {
        if c.needsRestFirst {
            return [MethodRecommendation(method: .rest, reason: "体調が悪いと話していたから、今は休むことを優先しよう", suggestedSeconds: 180)]
        }
        let soon = c.timing?.value == .soon
        let short = soon ? 60 : 180
        let breathless = c.body?.value.contains(.shallowBreath) == true
        let tenseBody = c.body?.value.contains(.tenseMuscles) == true
        let support = c.support?.value
        let emotion = c.emotion?.value
        let tension = c.tension?.value ?? -1
        let situation = c.situation?.value
        let causes = c.causes?.value ?? []
        var picks: [MethodRecommendation] = []
        func add(_ m: ImprovementMethod, _ reason: String, _ seconds: Int = short) {
            guard !picks.contains(where: { $0.method == m }) else { return }
            if breathless && m.hasLongBreathHold { return }      // 息苦しさがあるときは長く息を止めない
            picks.append(MethodRecommendation(method: m, reason: reason, suggestedSeconds: seconds))
        }
        func breathing(_ reason: String) {
            add(breathless ? .breathing214 : (soon ? .breathing214 : .breathing478),
                breathless ? reason + "。息苦しさがあるから、息を長く止めない方法にしたよ" : reason)
        }

        // 睡眠不足・強い疲れは、まず無理をしない休憩
        if c.sleep?.value.isShort == true || c.condition?.value == .veryTired {
            add(.shortBreak, c.sleep?.value.isShort == true ? "あまり眠れていないと話していたから、無理をしない休憩を先にしよう" : "かなり疲れていると話していたから、短く休もう", 90)
        }

        // 各パターン。本人の希望（してみたいこと）に合うパターンを先に評価し、希望を強く反映する
        let confidenceP = {
            add(.strengthReview, "自信をつけたいと話していたから、実際にできたことから確かめよう")
            if situation == .presentation { add(.openingPractice, "発表の前だから、話し始めを短く練習しておこう") }
            else if situation == .interviewExam { add(.answerPractice, "面接・試験の前だから、答えを短く練習しておこう") }
        }
        let organizeP = {
            add(.worrySort, "不安を整理したいと話していたから、準備できることと変えられないことに分けてみよう")
            if situation == .presentation && !soon { add(.openingPractice, "発表まで時間があるから、冒頭の30秒を練習しておこう") }
            else { add(.talkMore, "考えがまとまらないときは、言葉にすると整理しやすいよ") }
        }
        let refreshP = {
            add(.grounding, "気持ちを切り替えたいときは、まわりに意識を向けると今に戻りやすいよ")
            if tenseBody { add(.stretch, "体に力が入っていると話していたから、肩や首をほぐそう") }
            else { add(.shortBreak, "少し間をあけると切り替えやすいよ", 60) }
        }
        let calmP = {
            breathing(tension >= 75 ? "緊張が強いと話していたから、ゆっくり吐く呼吸で落ち着こう" : "落ち着きたいと話していたから、呼吸のペースを整えよう")
            add(tenseBody ? .stretch : .muscleRelaxation, tenseBody ? "体に力が入っていると話していたから、肩や首をほぐそう" : "力を入れて抜くと、体のこわばりに気づきやすいよ")
        }
        let unsureP = {
            add(.stateCheck, "今の状態がよく分からないときは、まず一言にしてみよう")
            add(.talkMore, "話しながら整理すると、自分の状態がつかみやすいよ")
        }
        switch support {
        case .confidence: confidenceP()
        case .organize: organizeP()
        case .refresh: refreshP()
        case .calmDown: calmP()
        case .unsure: unsureP()
        default: break
        }
        // E: 自信をつけたい
        if emotion == .unconfident || causes.contains(.ability) { confidenceP() }
        // B: 考えすぎ（不安の整理）
        if (emotion == .anxious && c.timing?.value == .tomorrowOrLater) || causes.contains(.speaking) && !soon { organizeP() }
        // C: 気持ちの切り替え
        if emotion == .irritated || emotion == .rushed || causes.contains(.comparison) { refreshP() }
        // A: 緊張が強い
        if tension >= 75 || c.body?.value.contains(.heartPounding) == true { calmP() }
        // D: 自分の状態が分からない
        if emotion == .unsure || situation == .restless { unsureP() }
        // 自分に合った方法を知りたい（ほかに手がかりがないとき）
        if picks.isEmpty && support == .findMethod {
            breathing("まずは手軽な呼吸法から試してみよう")
            add(.grounding, "呼吸が合わなければ、まわりに意識を向ける方法もあるよ")
        }
        // 緊張していない・改善を望まない
        if picks.isEmpty && (tension == 0 || c.declinedMeasurement) { return [] }
        if picks.isEmpty { breathing("今の状態を落ち着いて確かめるために、呼吸を整えてみよう") }
        return Array(picks.prefix(2))
    }
}

extension ImprovementMethod {
    /// 既存のガイド（GuideFlowView のタイマー・グラフィック）で実施できる呼吸法
    var guideExercise: GuideExercise? {
        switch self {
        case .breathing478: return .breathing478
        case .box: return .box
        case .breathing214: return .breathing214
        default: return nil
        }
    }

    static func from(_ exercise: GuideExercise) -> ImprovementMethod {
        switch exercise {
        case .breathing478: return .breathing478
        case .box: return .box
        case .breathing214: return .breathing214
        }
    }
}
