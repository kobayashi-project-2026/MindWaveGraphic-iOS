// MokorinCheckInTests.swift
// 会話で集める情報（STEP 0〜6）・次の質問の選択・改善方法の推薦（パターン A〜E）。2026-11-11

import Foundation

enum MokorinCheckInTests {
    typealias T = TestHarness
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func checkIn(_ texts: [(String, CheckInSlot?)]) -> MokorinCheckIn {
        var c = MokorinCheckIn()
        for (text, asked) in texts {
            if let asked { c.asked.append(asked) }
            c.apply(CheckInExtractor.extract(text, asked: asked), at: now)
        }
        return c
    }

    static func run() {
        T.suite("もこりん / 会話の情報（STEP 0〜6）")
        T.test("アプリ内から開いたあいさつ: 場面が未設定なら「安静」などと断定せず、質問も重ねない") {
            let fresh = MokorinScript.greetingForEdit(current: .default)
            T.expect(!fresh.contains("安静") && !fresh.contains("？"), "未設定の場面に触れない・質問はこの後の 1 つだけ")
            var ctx = MeasurementContext()
            ctx.scene = .interview
            T.expect(MokorinScript.greetingForEdit(current: ctx).contains(ContextScene.interview.displayName), "設定済みの場面は伝える")
        }
        T.test("1 つの発言から複数の項目を取り出す: 明日・面接・不安・睡眠不足（推定）・動悸") {
            let e = CheckInExtractor.extract("明日面接があって、不安であまり寝られなかった。今は心臓がドキドキしてる。", asked: nil)
            T.expectEqual(e.situation, .interviewExam)
            T.expectEqual(e.timing, .tomorrowOrLater)
            T.expectEqual(e.emotion, .anxious)
            T.expectEqual(e.sleep, .h3to5)
            T.expect(e.tentative.contains(.sleep), "時間ははっきりしないので確かさを下げる")
            T.expectEqual(e.body, [.heartPounding])
            T.expect(e.tension == nil, "緊張の強さは言っていないので決めない")
        }
        T.test("最初から緊張を決めつけない: 「今は落ち着いてる」は緊張 0、感情は決めない") {
            let e = CheckInExtractor.extract("今は落ち着いてる", asked: nil)
            T.expectEqual(e.tension, 0)
            T.expect(e.emotion == nil, "emotion")
        }
        T.test("緊張の強さ（S0）: 言葉と数で受け取る。曖昧なら確かさを下げる。イライラは緊張の強さにしない") {
            T.expectEqual(CheckInExtractor.extract("かなり緊張してる", asked: nil).tension, 75)
            T.expectEqual(CheckInExtractor.extract("少し緊張", asked: nil).tension, 20)
            T.expectEqual(CheckInExtractor.extract("70くらいかな", asked: .tension).tension, 70)
            T.expectEqual(CheckInExtractor.extract("７０", asked: .tension).tension, 70)
            let vague = CheckInExtractor.extract("緊張してる", asked: nil)
            T.expect(vague.tension == 50 && vague.tentative.contains(.tension), "曖昧")
            let irritated = CheckInExtractor.extract("イライラしてる", asked: nil)
            T.expectEqual(irritated.emotion, .irritated)
            T.expect(irritated.tension == nil, "イライラ ≠ 緊張")
        }
        T.test("身体反応は複数。「特にない」と具体的な症状は同時に持たない") {
            T.expectEqual(CheckInExtractor.extract("心臓がドキドキして、手もちょっと震える", asked: .body).body, [.heartPounding, .trembling])
            T.expectEqual(CheckInExtractor.extract("特にない", asked: .body).body, [.none])
            T.expectEqual(MokorinCheckIn.consistentBody([.none, .trembling]), [.trembling])
        }
        T.test("睡眠: 時間の数・覚えていない（尋ねたときだけ）") {
            T.expectEqual(CheckInExtractor.extract("6時間くらい寝た", asked: nil).sleep, .h5to7)
            T.expectEqual(CheckInExtractor.extract("2時間", asked: .sleep).sleep, .under3)
            T.expectEqual(CheckInExtractor.extract("覚えてないな", asked: .sleep).sleep, .unknown)
        }
        T.test("訂正: 後ろの内容を優先し、前の値を上書きする") {
            var c = checkIn([("明日面接がある", nil)])
            c.apply(CheckInExtractor.extract("やっぱり面接じゃなくて発表だった", asked: nil), at: now)
            T.expectEqual(c.situation?.value, .presentation)
        }
        T.test("答えたくない項目はスキップし、二度と尋ねない") {
            var c = MokorinCheckIn()
            c.asked = [.sleep]
            c.apply(CheckInExtractor.extract("それは答えたくない", asked: .sleep), at: now)
            T.expect(c.declined.contains(.sleep), "declined")
            T.expect(c.nextSlot() != .sleep, "尋ねない")
        }
        T.test("次の質問: 答え済みは尋ねない。必要な項目（場面・気持ち・緊張・希望）がそろえば終わる。上限 7 問") {
            var c = checkIn([("明日面接があって、不安であまり寝られなかった。今は心臓がドキドキしてる。", nil)])
            var asked: [CheckInSlot] = []
            while let next = c.nextSlot() {
                T.expect(!c.isKnown(next), "答え済みを尋ねない: \(next)")
                T.expect(!asked.contains(next), "同じ質問を繰り返さない: \(next)")
                asked.append(next); c.asked.append(next)
                switch next {
                case .tension: c.apply(CheckInExtractor.extract("70", asked: .tension), at: now)
                case .support: c.apply(CheckInExtractor.extract("落ち着きたい", asked: .support), at: now)
                default: c.apply(CheckInExtractor.extract("わからない", asked: next), at: now)
                }
                if asked.count > 10 { break }
            }
            T.expect(c.isReadyToSuggest, "ready")
            T.expect(asked.count <= MokorinCheckIn.questionBudget, "上限: \(asked)")
            T.expect(!asked.contains(.situation) && !asked.contains(.emotion) && !asked.contains(.sleep) && !asked.contains(.body), "発言で答えた項目は尋ねない: \(asked)")
        }
        T.test("体調が悪いときは質問を続けず、休息を推薦する") {
            let c = checkIn([("今日は体調が悪い", nil)])
            T.expect(c.nextSlot() == nil && c.isReadyToSuggest, "stop")
            T.expectEqual(MokorinMethodAdvisor.recommend(c).map(\.method), [.rest])
        }
        T.test("既存の MeasurementContext への対応（場面の分類は既存の値だけ）") {
            let c = checkIn([("明日の発表、さっき走ってきた、あまり眠れなかった", nil)])
            let ctx = c.measurementContext(base: .default)
            T.expectEqual(ctx.scene, .interview)
            T.expectEqual(ctx.conditions, [.running, .sleepLack])
        }

        T.suite("もこりん / 改善方法の推薦（パターン A〜E）")
        T.test("A 緊張が強い: 呼吸＋筋弛緩。息苦しさがあれば息を長く止める方法を推薦しない") {
            let a = checkIn([("これから面接、かなり緊張してる、失敗しそう、心臓がドキドキ、落ち着きたい", nil)])
            let m = MokorinMethodAdvisor.recommend(a).map(\.method)
            T.expect(m.contains(.breathing214) || m.contains(.breathing478), "呼吸: \(m)")
            T.expect(m.count <= 2, "最大 2")
            let breathless = checkIn([("これから面接、かなり緊張、息が苦しい、落ち着きたい", nil)])
            let mb = MokorinMethodAdvisor.recommend(breathless).map(\.method)
            T.expect(!mb.contains(.breathing478) && !mb.contains(.box), "息止めを避ける: \(mb)")
        }
        T.test("B 考えすぎ: 心配ごとの整理と冒頭の練習（発表・明日以降）") {
            let b = checkIn([("明日発表があって不安、うまく話せるか心配、整理したい", nil)])
            T.expectEqual(MokorinMethodAdvisor.recommend(b).map(\.method), [.worrySort, .openingPractice])
        }
        T.test("C 気持ちの切り替え: グラウンディング＋（体がこわばっていれば）ストレッチ") {
            let c = checkIn([("友達と会う前で焦ってる、周りと比べてしまう、肩に力が入ってる、気分転換したい", nil)])
            T.expectEqual(MokorinMethodAdvisor.recommend(c).map(\.method), [.grounding, .stretch])
        }
        T.test("D 状態が分からない: 状態の確認と対話") {
            var d = checkIn([("特に予定はないけど落ち着かない", nil)])
            d.apply(CheckInExtractor.extract("よくわからない", asked: .emotion), at: now)
            T.expectEqual(MokorinMethodAdvisor.recommend(d).map(\.method), [.stateCheck, .talkMore])
        }
        T.test("E 自信をつけたい: 強みの振り返り＋回答の練習（面接）。本人の希望で推薦が変わる") {
            let e = checkIn([("明日面接、自信がない、自信をつけたい", nil)])
            T.expectEqual(MokorinMethodAdvisor.recommend(e).map(\.method), [.strengthReview, .answerPractice])
            let calm = checkIn([("明日面接、自信がない、落ち着きたい", nil)])
            T.expect(MokorinMethodAdvisor.recommend(calm).map(\.method) != MokorinMethodAdvisor.recommend(e).map(\.method), "希望で変わる")
        }
        T.test("睡眠不足は休憩を先に。推薦には必ず理由がある。緊張していなければ無理に勧めない") {
            let s = checkIn([("これから試験、ほとんど寝てない、落ち着きたい", nil)])
            let r = MokorinMethodAdvisor.recommend(s)
            T.expectEqual(r.first?.method, .shortBreak)
            T.expect(r.allSatisfy { !$0.reason.isEmpty }, "理由")
            let relaxed = checkIn([("今は落ち着いてる", nil)])
            T.expect(MokorinMethodAdvisor.recommend(relaxed).isEmpty, "勧めない")
        }
        T.test("これからすぐは短く（60 秒）、明日以降は練習も（180 秒）") {
            let soon = MokorinMethodAdvisor.recommend(checkIn([("これから面接、かなり緊張", nil)]))
            T.expectEqual(soon.first?.suggestedSeconds, 60)
            let later = MokorinMethodAdvisor.recommend(checkIn([("明日発表があって不安、整理したい", nil)]))
            T.expectEqual(later.first?.suggestedSeconds, 180)
        }
    }
}
