// MokorinResultExplainer.swift
// Mokorin
//
// 測定結果・記録を、もこりんが話す説明に変える（端末内・決定的）。既存の値を読むだけで、計算は変えない。
//
// - 「確認済みの事実」（記録にある値・本人が話したこと）、「解釈」（可能性として）、「不足しているデータ」、「注意点」を分ける
// - HR・HRV から気持ちや病気を断定しない。HRV がない記録で HRV の話をしない
// - 過去との比較は、同じ場面・デモデータ以外・心拍がある記録だけ。記録がなければ「まだ比べられない」
// - 回数を数えるだけで、統計的な傾向とは言わない
// 外部 AI には送らない（ChatViewModel では端末内の発言として扱い、送信履歴から除く）。

import Foundation

/// 説明の対象（GuideFlowView の結果、または保存済みの記録）
struct MokorinResultInput: Equatable {
    var recordID: UUID?
    var startedAt: Date
    var scene: MeasurementScene
    var exerciseTitle: String
    var durationSeconds: Int
    var before: GuideSnapshot
    var after: GuideSnapshot?
    var selfReportBefore: SelfReportLevel?
    var selfReportAfter: SelfReportLevel?

    init(recordID: UUID? = nil, startedAt: Date, scene: MeasurementScene, exerciseTitle: String, durationSeconds: Int,
         before: GuideSnapshot, after: GuideSnapshot?, selfReportBefore: SelfReportLevel? = nil, selfReportAfter: SelfReportLevel? = nil) {
        self.recordID = recordID
        self.startedAt = startedAt
        self.scene = scene
        self.exerciseTitle = exerciseTitle
        self.durationSeconds = durationSeconds
        self.before = before
        self.after = after
        self.selfReportBefore = selfReportBefore
        self.selfReportAfter = selfReportAfter
    }

    init(record: GuideSessionRecord) {
        self.init(recordID: record.id, startedAt: record.startedAt, scene: record.scene, exerciseTitle: record.exercise.title,
                  durationSeconds: record.durationSeconds, before: record.before, after: record.after,
                  selfReportBefore: record.selfReportBefore, selfReportAfter: record.selfReportAfter)
    }

    /// デモ（Mock）データを含むか
    var usesDemoData: Bool { before.isMockData || (after?.isMockData ?? false) }
}

/// もこりんの説明（画面では会話として順に出す）
struct MokorinBrief: Equatable {
    enum Purpose: Equatable { case result, review }

    var purpose: Purpose
    /// 最初のひとこと
    var opening: String
    /// 確認済みの事実
    var facts: [String]
    /// 解釈（可能性）
    var interpretation: [String]
    /// 取れなかったデータ
    var missing: [String]
    /// 結果を見るときの注意
    var cautions: [String]
    /// 過去の記録との比較（記録がなければ「まだ比べられない」）
    var comparison: [String]
    /// 比べられる過去の記録があるか
    var hasComparableHistory: Bool
    var advice: MokorinAdviceResult
    var usesDemoData: Bool

    /// 最初の吹き出し（ひとこと＋主な事実＋不足）
    var firstMessage: String {
        var lines: [String] = [opening]
        if usesDemoData, let demo = cautions.first { lines.append(demo) }
        lines.append(contentsOf: facts.prefix(3))
        lines.append(contentsOf: missing.prefix(1))
        return lines.joined(separator: "\n")
    }
}

extension MokorinTopic {
    /// ガイドで選んだ場面（MeasurementScene）からの話題
    static func from(guideScene: MeasurementScene) -> MokorinTopic {
        switch guideScene {
        case .interview: return .interview
        case .speech:    return .presentation
        case .meeting:   return .work
        case .study:     return .exam
        case .sports:    return .sports
        case .social:    return .important
        case .daily:     return .rest
        case .other:     return .unknown
        }
    }
}

enum MokorinResultExplainer {

    /// 本人の会話の内容を結果に使ってよいか（同じ流れの測定前 6 時間以内の会話だけ）
    static func memoryApplies(_ memory: MokorinSessionMemory?, to input: MokorinResultInput) -> MokorinSessionMemory? {
        guard let memory else { return nil }
        let gap = input.startedAt.timeIntervalSince(memory.capturedAt)
        return (gap >= -60 && gap <= 6 * 3600) ? memory : nil
    }

    static func explain(_ input: MokorinResultInput, history: [GuideSessionRecord],
                        memory rawMemory: MokorinSessionMemory?, purpose: MokorinBrief.Purpose = .result,
                        recentUserText: String = "") -> MokorinBrief {
        let memory = memoryApplies(rawMemory, to: input)
        var facts: [String] = []
        var interpretation: [String] = []
        var missing: [String] = []
        var cautions: [String] = []

        facts.append("場面は「\(input.scene.displayName)」、ガイドは \(input.exerciseTitle)（\(input.durationSeconds)秒）だったよ。")

        // 心拍
        let hrBefore = input.before.heartRate, hrAfter = input.after?.heartRate
        switch (hrBefore, hrAfter) {
        case let (b?, a?):
            let d = Int((a - b).rounded())
            facts.append("心拍はガイド前 \(Int(b.rounded())) → ガイド後 \(Int(a.rounded())) bpm（\(signed(d))）。")
            if d <= -3 {
                interpretation.append("ガイドのあとで心拍が下がっているね。落ち着く方向に変化した可能性があるよ。")
            } else if d >= 3 {
                interpretation.append("ガイドのあとで心拍が上がっているね。体を動かした・話したなど、いろいろな理由が考えられるよ。")
            } else {
                interpretation.append("心拍には大きな変化はなかったよ。")
            }
        case let (b?, nil):
            facts.append("心拍はガイド前 \(Int(b.rounded())) bpm。")
            missing.append("ガイド後の心拍は取れなかったから、前後の比較はできないよ。")
        case let (nil, a?):
            facts.append("心拍はガイド後 \(Int(a.rounded())) bpm。")
            missing.append("ガイド前の心拍は取れなかったから、前後の比較はできないよ。")
        case (nil, nil):
            missing.append("この記録では心拍が取れていないよ。")
        }

        // 緊張スコア（アプリの既存の計算値）
        if let after = input.after {
            let d = Int((after.score - input.before.score).rounded())
            facts.append("緊張スコア（アプリの計算値・0〜100）は \(Int(input.before.score.rounded())) → \(Int(after.score.rounded()))（\(signed(d))）。")
            if d <= -5 { interpretation.append("スコアも下がっていて、数値の上では落ち着いた方向だね。") }
            else if d >= 5 { interpretation.append("スコアは上がっているね。測ったときの状況も合わせて見てみよう。") }
        } else {
            facts.append("緊張スコア（アプリの計算値・0〜100）は \(Int(input.before.score.rounded()))。")
        }

        // HRV（ある場合だけ話す）
        switch (input.before.hrv, input.after?.hrv) {
        case let (b?, a?): facts.append("HRV（SDNN）は \(Int(b.rounded())) → \(Int(a.rounded())) ms。")
        case let (b?, nil): facts.append("HRV（SDNN）はガイド前 \(Int(b.rounded())) ms。")
        case let (nil, a?): facts.append("HRV（SDNN）はガイド後 \(Int(a.rounded())) ms。")
        case (nil, nil): missing.append("HRV はこの記録では取れていないから、心拍とスコアだけで見ているよ。")
        }

        // 本人の感覚（自己申告）
        if let b = input.selfReportBefore, let a = input.selfReportAfter {
            facts.append("気持ちは本人の感覚で「\(b.label)」→「\(a.label)」。")
            if a.rawValue < b.rawValue, let hb = hrBefore, let ha = hrAfter, ha - hb > -3 {
                interpretation.append("体感では楽になったみたい。数値と感覚がそろわないこともあるよ。")
            }
        }

        // 測定前に本人が話したこと（同じ流れの会話だけ）
        if let memory {
            let said = memory.conditions.filter { $0 != .none }
            if let note = memory.situationNote { facts.append("測定前に「\(note)」と話していたね。") }
            if !said.isEmpty {
                facts.append("測定前に「\(MokorinScript.conditionPhrase(said))」と話していたね。")
            }
            if memory.conditions.contains(.running) || memory.conditions.contains(.stairs) {
                cautions.append("動いた直後は心拍が上がりやすいから、その影響もあるかもしれないよ。")
            }
            if memory.conditions.contains(.caffeine) || memory.conditions.contains(.smoking) {
                cautions.append("カフェインや喫煙のあとは心拍に影響することがあるよ。")
            }
        }

        // 注意
        if input.usesDemoData { cautions.insert("この記録はデモ用のデータだから、実際の体の状態ではないよ。", at: 0) }
        let confidence = input.after?.confidence ?? input.before.confidence
        if confidence < 0.5 { cautions.append("計測の信頼度が低め（\(Int((confidence * 100).rounded()))%）だから、参考程度に見てね。") }
        cautions.append("これは医療的な診断ではないし、気持ちを決めつけるものでもないよ。")

        let (comparison, comparable) = compare(input, history: history)
        let conversationTopic = memory.map { MokorinTopic.detect(text: $0.situationNote, scene: $0.scene) }
        let fromConversation = conversationTopic != nil && conversationTopic != .unknown
        let advice = MokorinAdviceEngine.advise(MokorinAdviceInput(
            topic: fromConversation ? conversationTopic! : MokorinTopic.from(guideScene: input.scene),
            conditions: memory?.conditions ?? [], tension: memory?.tension,
            mentionedFatigue: memory?.mentionedFatigue ?? false, recentUserText: recentUserText,
            selectedSceneLabel: fromConversation ? nil : input.scene.displayName))

        return MokorinBrief(purpose: purpose,
                            opening: purpose == .result ? "今回の測定結果を一緒に見てみよう。" : "この記録を一緒に振り返ってみよう。",
                            facts: facts, interpretation: interpretation, missing: missing, cautions: cautions,
                            comparison: comparison, hasComparableHistory: comparable, advice: advice,
                            usesDemoData: input.usesDemoData)
    }

    /// 同じ場面の過去の記録との比較（事実だけ）
    static func compare(_ input: MokorinResultInput, history: [GuideSessionRecord]) -> ([String], Bool) {
        if input.usesDemoData { return (["デモ用のデータだから、過去の記録とは比べないよ。"], false) }
        let past = history
            .filter { $0.id != input.recordID && $0.scene == input.scene && $0.startedAt < input.startedAt }
            .filter { !$0.before.isMockData && !($0.after?.isMockData ?? false) && $0.before.heartRate != nil }
            .sorted { $0.startedAt > $1.startedAt }
        guard let last = past.first else {
            return (["「\(input.scene.displayName)」の前の記録はまだないから、比べられないよ。測るたびに比べられるようになるよ。"], false)
        }
        var lines: [String] = []
        let date = last.startedAt.formatted(.dateTime.month().day())
        if let b = last.before.heartRate, let a = last.after?.heartRate {
            lines.append("前回（\(date)）の同じ場面では、心拍は \(Int(b.rounded())) → \(Int(a.rounded())) bpm だったよ。")
        } else if let b = last.before.heartRate {
            lines.append("前回（\(date)）の同じ場面では、ガイド前の心拍が \(Int(b.rounded())) bpm だったよ。")
        }
        if let nowB = input.before.heartRate, let pastB = last.before.heartRate {
            let d: Int = Int((nowB - pastB).rounded())
            if d == 0 {
                lines.append("ガイド前の心拍は前回と同じくらいだね。")
            } else {
                let direction: String = d > 0 ? "高い" : "低い"
                lines.append("今回のガイド前の心拍は前回より \(abs(d)) bpm \(direction)ね。測ったときの状況が違うと、値も変わりやすいよ。")
            }
        }
        let withBoth: [GuideSessionRecord] = past.filter { $0.after?.heartRate != nil }
        if withBoth.count >= 3 {
            let lowered: Int = withBoth.filter { (r: GuideSessionRecord) -> Bool in
                guard let a = r.after?.heartRate, let b = r.before.heartRate else { return false }
                return a - b <= -3
            }.count
            lines.append("これまでの同じ場面の \(withBoth.count) 回のうち、ガイドのあとに心拍が下がったのは \(lowered) 回だよ（数えただけで、傾向とは言い切れないよ）。")
        }
        return (lines, true)
    }

    private static func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : (v == 0 ? "±0" : "\(v)") }
}
