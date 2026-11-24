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
                case .tension: c.applyAcuteTension(.moderate, at: now)
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

        T.suite("STEP 3.5 / 急性スコアの本人回答")
        T.test("3択は指定文言の順番で、Q0を整数へ丸めず保持する") {
            T.expectEqual(CheckInSlot.tension.question, "今、どのくらい緊張やストレスを感じている？")
            T.expectEqual(CheckInSlot.tension.question(variant: 5), CheckInSlot.tension.question)
            T.expectEqual(CheckInSlot.tension.options.map(\.label), ["少し感じる", "ある程度感じる", "とても強く感じる"])
            T.expectEqual(AcuteTensionChoice.allCases.map(\.q0), [100.0 / 60.0, 5.0, 500.0 / 60.0])
            for choice in AcuteTensionChoice.allCases {
                var c = MokorinCheckIn()
                c.applyAcuteTension(choice, at: now)
                T.expectEqual(c.acuteQ0, choice.q0)
                T.expect(c.tension == nil, "旧0〜100回答を作らない")
            }
        }
        T.test("STEP 3の感情・旧数値・AIの推定からQ0を作らず、質問上限後でも3.5を先に尋ねる") {
            for feeling in FeelingKind.allCases {
                var c = MokorinCheckIn()
                var e = CheckInExtraction()
                e.emotion = feeling
                e.tension = 75
                c.apply(e, source: .inferred, at: now)
                c.asked = Array(repeating: .cause, count: MokorinCheckIn.questionBudget)
                T.expect(c.acuteQ0 == nil, "気持ち・旧数値から推測しない")
                T.expectEqual(c.nextSlot(), .tension, "3.5を飛ばさない")
            }
        }
        T.test("STEP 3.5は明示した回答だけを使い、推定由来の値は不採用") {
            var c = MokorinCheckIn()
            c.acuteTension = .init(value: .strong, source: .inferred, updatedAt: now, confidence: 1)
            T.expect(c.acuteQ0 == nil && !c.isKnown(.tension), "inferredは本人の回答ではない")
            c.applyAcuteTension(.slight, at: now)
            T.expectEqual(c.acuteQ0, 100.0 / 60.0)
            c.applyAcuteTension(.strong, at: now)
            T.expectEqual(c.acuteQ0, 500.0 / 60.0, "訂正は小数のまま上書き")
            var skip = CheckInExtraction()
            skip.declined = [.tension]
            c.apply(skip, at: now)
            T.expect(c.acuteQ0 == nil && c.isSettled(.tension), "明示スキップは欠損のまま")
        }
        T.test("STEP 3・4・5の質問文と選択肢は変えない") {
            T.expectEqual(CheckInSlot.emotion.question, "今の気持ちに一番近いものはどれ？")
            T.expectEqual(CheckInSlot.cause.question, "今、一番気になっていることはある？")
            T.expectEqual(CheckInSlot.body.question, "今、体に何か変化はある？いくつでも教えてね。")
            T.expectEqual(CheckInSlot.emotion.options, FeelingKind.allCases.map { .emotion($0) })
            T.expectEqual(CheckInSlot.cause.options, WorryCause.allCases.map { .cause($0) })
            T.expectEqual(CheckInSlot.body.options, BodySignal.allCases.map { .body($0) })
        }
        T.test("画面の回答順はSTEP3→3.5→4。戻る・やり直すとQ0も取り消す") {
            let vm = localStep35VM("order")
            answerThroughEmotion(vm)
            T.expectEqual(vm.askedSlot, .tension)
            T.expectEqual(vm.quickReplies.map(\.label), ["少し感じる", "ある程度感じる", "とても強く感じる"])
            vm.answer(options: [.acuteTension(.strong)])
            T.expectEqual(vm.checkIn.acuteQ0, 500.0 / 60.0)
            T.expectEqual(vm.sessionMemory.checkIn?.acuteQ0, 500.0 / 60.0)
            T.expectEqual(vm.askedSlot, .cause)
            vm.goBack()
            T.expect(vm.checkIn.acuteQ0 == nil, "戻るで取消")
            T.expectEqual(vm.askedSlot, .tension)
            vm.answer(options: [.acuteTension(.slight)])
            T.expectEqual(vm.checkIn.acuteQ0, 100.0 / 60.0)
            vm.restart()
            T.expect(vm.checkIn.acuteQ0 == nil, "やり直しで取消")
        }
        T.test("3.5以外の画面や複数選択からの回答はQ0を変更しない") {
            let vm = localStep35VM("stale-options")
            vm.answer(options: [.acuteTension(.strong)])
            T.expect(vm.checkIn.acuteQ0 == nil, "別の質問では受け付けない")
            answerThroughEmotion(vm)
            vm.answer(options: [.acuteTension(.slight), .acuteTension(.strong)])
            T.expect(vm.checkIn.acuteQ0 == nil, "単一選択だけ")
            vm.skipQuestion()
            T.expect(vm.checkIn.acuteQ0 == nil, "スキップは欠損")
            T.expect(vm.askedSlot != .tension, "明示スキップなら次へ")
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

    static func runStep35Async() async {
        T.suite("STEP 3.5 / 文字・音声・AI経路")
        await T.test("数値・曖昧な緊張表現・開始希望でQ0を作らず、完全一致の本人回答だけを採用する") {
            let vm = localStep35VM("text")
            answerThroughEmotion(vm)
            for text in ["75", "すごく緊張してる", "測定したい"] {
                await vm.submit(text)
                T.expect(vm.checkIn.acuteQ0 == nil, "未回答: \(text)")
                T.expectEqual(vm.askedSlot, .tension, "3択または明示スキップを待つ")
            }
            await vm.submit(" ある程度感じる ")
            T.expectEqual(vm.checkIn.acuteQ0, 5.0)
            T.expectEqual(vm.askedSlot, .cause)
        }
        await T.test("AIがSTEP4の質問・推定緊張度・readyを返しても、3.5だけを表示しQ0を推測しない") {
            let consent = ChatTextConsentStore(defaults: T.freshDefaults("step35-remote"))
            consent.setConsented(true)
            let configuration = RemoteInsightConfiguration(baseURL: URL(string: "https://example.invalid")!, clientToken: "test")
            let client = Step35RemoteClient()
            let vm = MokorinContextViewModel(consentStore: consent, configurationProvider: { configuration }, clientFactory: { _ in client })
            vm.answer(options: [.condition(.energetic)])
            vm.answer(options: [.situation(.presentation)])
            vm.answer(options: [.timing(.soon)])
            T.expectEqual(vm.askedSlot, .emotion)
            await vm.submit("不安です")
            T.expectEqual(vm.askedSlot, .tension)
            T.expectEqual(vm.currentTurn?.text, CheckInSlot.tension.question, "AIのSTEP4質問を同時表示しない")
            T.expectEqual(vm.latestMokorinMessage?.origin, .fixed)
            T.expect(vm.checkIn.acuteQ0 == nil && !vm.checkIn.declined.contains(.tension), "AIの数値・skipを採用しない")
            await vm.submit("とても強く感じる")
            T.expectEqual(vm.checkIn.acuteQ0, 500.0 / 60.0, "本人の完全一致ラベルを小数で保存")
            T.expectEqual(vm.askedSlot, .cause)
        }
    }

    private struct Step35RemoteClient: ContextAssistClient {
        func send(_ request: ContextAssistRequestDTO) async throws -> ContextAssistResponseDTO {
            ContextAssistResponseDTO(schemaVersion: 1, requestId: request.requestId, conversationId: request.conversationId,
                provider: "openai", model: "test", generatedAt: Date(),
                result: ContextAssistResultDTO(reply: "今、一番気になっていることはある？", sceneCandidate: nil,
                    conditionCandidates: [], needsClarification: true, clarificationQuestion: "体の変化もある？",
                    userIntent: "ready", checkIn: ContextAssistCheckInResultDTO(emotion: "anxious", tensionLevel: 100, declined: ["tension"])),
                usage: nil)
        }
    }

    static func localStep35VM(_ name: String) -> MokorinContextViewModel {
        MokorinContextViewModel(consentStore: ChatTextConsentStore(defaults: T.freshDefaults("step35-" + name)),
                                configurationProvider: { nil })
    }

    static func answerThroughEmotion(_ vm: MokorinContextViewModel) {
        vm.answer(options: [.condition(.energetic)])
        vm.answer(options: [.situation(.presentation)])
        vm.answer(options: [.timing(.soon)])
        vm.answer(options: [.emotion(.anxious)])
    }
}
