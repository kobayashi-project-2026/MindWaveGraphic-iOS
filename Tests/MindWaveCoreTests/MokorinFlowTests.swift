// MokorinFlowTests.swift
// 測定前の会話（2026-11-11 改訂: STEP 0〜6 を必要な項目だけ尋ねる）の画面の状態。
// 以前の「緊張 → 場面 → 身体状態」の固定順のテストを置き換える（同じ観点: ボタンだけ・文章・訂正・やり直し・外部AI・失敗・表情）

import Foundation

enum MokorinFlowTests {
    typealias T = TestHarness

    static func local(_ name: String = #function, inApp: Bool = false, initial: MeasurementContext = .default) -> MokorinContextViewModel {
        MokorinTests.localVM(initial: initial, inApp: inApp, name: "flow-\(name)")
    }

    /// 選択肢の先頭を選び続けて、まとめまで進める（質問の数を返す）
    @discardableResult
    static func tapThrough(_ vm: MokorinContextViewModel, limit: Int = 12) -> [CheckInSlot] {
        var asked: [CheckInSlot] = []
        while let slot = vm.askedSlot, vm.step != .review, asked.count < limit {
            asked.append(slot)
            guard case .checkIn(let o)? = vm.quickReplies.first else { break }
            vm.tap(.checkIn(o))
        }
        return asked
    }

    static func aiClient(reply: String, checkIn: ContextAssistCheckInResultDTO?, scene: String? = nil,
                         intent: String? = nil, provider: String = "openai") -> FakeContextClient {
        FakeContextClient { req in
            ContextAssistResponseDTO(schemaVersion: 1, requestId: req.requestId, conversationId: req.conversationId, provider: provider,
                                     model: "test-model", generatedAt: Date(),
                                     result: ContextAssistResultDTO(reply: reply, sceneCandidate: scene, conditionCandidates: [],
                                                                    needsClarification: false, clarificationQuestion: nil,
                                                                    userIntent: intent, checkIn: checkIn),
                                     usage: nil)
        }
    }

    static func run() async {
        T.suite("もこりん / 測定前の会話（STEP 0〜6）")

        await T.test("あいさつ: 緊張していると決めつけず、最初の質問を 1 つだけ。端末内の定型文・happy + wave") {
            let vm = local()
            let first = vm.messages.first
            T.expect(first?.text.hasPrefix("こんにちは！今日もおつかれさま！今日はどんな感じ？まずは今の自分の状態を一緒に確認してみよう！") == true, first?.text ?? "")
            T.expect(!(first?.text.contains("緊張してる？") ?? true), "緊張を決めつけない")
            T.expectEqual(vm.askedSlot, .sleep)
            T.expectEqual(first?.origin, .fixed)
            T.expectEqual(vm.pose.emotion, .happy)
            T.expectEqual(vm.pose.action, .wave)
            T.expect(vm.quickReplies.count <= 3, "選択肢は最大 3")
        }
        await T.test("ボタンだけで: 質問は上限まで・重複なし → まとめと推薦 → 既存の MeasurementContext") {
            let vm = local()
            let asked = tapThrough(vm)
            T.expectEqual(vm.step, .review)
            T.expectEqual(Set(asked).count, asked.count, "同じ質問を繰り返さない: \(asked)")
            T.expect(asked.count <= MokorinCheckIn.questionBudget, "上限: \(asked)")
            T.expect(vm.messages.last?.text.contains("この状況で測定してみようか") == true, vm.messages.last?.text ?? "")
            T.expectEqual(vm.measurementContext.scene, .interview, "発表・プレゼン → 既存の interview")
            T.expectEqual(vm.quickReplies, [], "まとめでは選択肢を出さない")
        }
        await T.test("文章: 1 つの発言から複数の項目を取り、答え済みの質問はしない") {
            let vm = local()
            await vm.submit("明日面接があって、不安であまり寝られなかった。今は心臓がドキドキしてる。")
            let c = vm.checkIn
            T.expectEqual(c.situation?.value, .interviewExam)
            T.expectEqual(c.timing?.value, .tomorrowOrLater)
            T.expectEqual(c.emotion?.value, .anxious)
            T.expectEqual(c.body?.value, [.heartPounding])
            T.expect(c.sleep?.confidence == 0.5, "睡眠は推定（確かさ 0.5）")
            let next = vm.askedSlot
            T.expect(next != nil && ![.sleep, .situation, .timing, .emotion, .body].contains(next!), "次の質問: \(String(describing: next))")
            T.expectEqual(vm.measurementContext.scene, .interview)
            T.expect(vm.measurementContext.conditions.contains(.sleepLack), "睡眠不足は既存の身体状態へ")
        }
        await T.test("訂正: 発言で直すと情報と既存の場面が更新される") {
            let vm = local()
            await vm.submit("明日面接がある")
            await vm.submit("やっぱり面接じゃなくて発表だった")
            T.expectEqual(vm.checkIn.situation?.value, .presentation)
            T.expectEqual(vm.measurementContext.scene, .interview)
        }
        await T.test("一つ前の会話へ戻る: 直前の答えを取り消し、同じ質問からやり直す。推薦も更新される") {
            let vm = local()
            vm.tap(.checkIn(.sleep(.h7to9)))
            T.expect(vm.canGoBack, "戻れる")
            let afterFirst = vm.messages.count
            vm.goBack()
            T.expectEqual(vm.askedSlot, .sleep)
            T.expect(vm.checkIn.sleep == nil, "答えを取り消し")
            T.expect(vm.messages.count < afterFirst, "会話も戻る")
            T.expect(!vm.canGoBack, "最初まで戻った")
            vm.tap(.checkIn(.sleep(.under3)))
            T.expectEqual(vm.checkIn.sleep?.value, .under3)
            _ = tapThrough(vm)
            T.expectEqual(vm.recommendations.first?.method, .shortBreak, "睡眠不足に合わせて推薦が変わる")
        }
        await T.test("答えない（スキップ）・はっきりしない答えは 1 回だけ聞き直し、2 回目はとばす") {
            let vm = local()
            vm.skipQuestion()
            T.expect(vm.checkIn.declined.contains(.sleep), "declined")
            T.expect(vm.askedSlot != .sleep, "次の質問へ")
            let next = vm.askedSlot
            await vm.submit("うーん")
            T.expectEqual(vm.askedSlot, next, "1 回は同じ質問を聞き直す")
            T.expect(vm.messages.last?.text.contains("とばしても大丈夫") == true, "聞き直し")
            await vm.submit("うーん")
            T.expect(vm.askedSlot != next, "2 回目はとばす")
        }
        await T.test("深刻な症状の言葉: 外部AIへ送らず、相談を案内して推薦を止める") {
            let client = aiClient(reply: "x", checkIn: nil)
            let vm = MokorinTests.remoteVM(client: client)
            await vm.submit("さっきから胸が痛い")
            T.expect(client.requests.isEmpty, "送らない")
            T.expect(vm.messages.last?.text.contains("医療機関") == true, "相談の案内")
            T.expect(vm.safetyStop && vm.recommendations.isEmpty && vm.quickReplies.isEmpty, "推薦・選択肢を止める")
        }
        await T.test("外部AI: 返答はそのまま OpenAI として表示。AI の抽出を反映し、要求に会話の情報と次の質問を含む") {
            let client = aiClient(reply: "明日の面接なんだね。今の気持ちに近いのはどれ？",
                                  checkIn: ContextAssistCheckInResultDTO(situation: "interview_exam", timing: "tomorrow_or_later", tensionLevel: 75))
            let vm = MokorinTests.remoteVM(client: client)
            vm.tap(.checkIn(.sleep(.h5to7)))
            await vm.submit("明日面接で、かなり緊張してる")
            T.expectEqual(vm.messages.last?.origin, .openAI(model: "test-model"))
            T.expectEqual(vm.messages.last?.text, "明日の面接なんだね。今の気持ちに近いのはどれ？", "固定文で上書きしない")
            T.expectEqual(vm.checkIn.tension?.value, 75)
            T.expectEqual(vm.subjectiveTension, .high)
            let req = client.requests.last
            T.expectEqual(req?.current.checkIn?.sleep, "5_7h", "これまでの情報")
            T.expect(req?.current.nextSlot != nil, "次の質問")
            T.expect(req?.messages.last?.content == "明日面接で、かなり緊張してる", "会話")
        }
        await T.test("外部AI: 質問のない返答には次の質問を添える。不正な抽出値は採用せず止まらない") {
            let client = aiClient(reply: "そっか、教えてくれてありがとう。",
                                  checkIn: ContextAssistCheckInResultDTO(sleep: "lots", emotion: "dance", tensionLevel: 400))
            let vm = MokorinTests.remoteVM(client: client)
            await vm.submit("今日は普通かな")
            T.expect(vm.messages.last?.origin == .fixed && vm.messages.last?.text.hasSuffix("？") == true, "定型の次の質問")
            T.expect(vm.checkIn.emotion == nil && vm.checkIn.tension == nil, "未知・範囲外の値は採用しない")
        }
        await T.test("通信失敗: 「もう一度送る」「AIなしで続ける」→ 端末内の定型文で続ける") {
            let down = FakeContextClient { _ in throw InsightClientError.transport(code: -1004) }
            let vm = MokorinTests.remoteVM(client: down)
            await vm.submit("6時間くらい寝た")
            T.expectEqual(vm.quickReplies, [.retry, .continueWithoutAI])
            vm.continueWithoutAI()
            T.expectEqual(vm.checkIn.sleep?.value, .h5to7)
            T.expectEqual(vm.messages.last?.origin, .fixed)
        }
        await T.test("スタブの返答は「スタブ」と表示") {
            let vm = MokorinTests.remoteVM(client: aiClient(reply: "（スタブ）次はどう？", checkIn: nil, provider: "openai-stub"))
            await vm.submit("6時間くらい寝た")
            T.expectEqual(vm.messages.last { $0.speaker == .mokorin && $0.origin != .fixed }?.origin, .stub(model: "test-model"))
        }
        await T.test("AIなしで質問されたら、答えられないと伝えて同じ質問に戻る") {
            let vm = local()
            await vm.submit("もこりんって何が好き？")
            T.expect(vm.messages.last?.text.contains("質問にうまく答えられない") == true, "正直に")
            T.expectEqual(vm.askedSlot, .sleep)
        }
        await T.test("メインアプリ内からの再設定: 現在の状況で始まり、変更しなければそのまま") {
            let ctx = MeasurementContext(scene: .sports, conditions: [.running])
            let vm = local(inApp: true, initial: ctx)
            T.expect(vm.messages.first?.text.contains("試合") == true, "現在の状況を伝える")
            T.expectEqual(vm.measurementContext, ctx)
        }
        await T.test("会話の進み具合: 答えた項目を順に表示し、タップした項目の質問まで戻る（後の答えも取り消す）") {
            let vm = local()
            vm.tap(.checkIn(.sleep(.h7to9)))
            let second = vm.askedSlot!
            if case .checkIn(let o)? = vm.quickReplies.first { vm.tap(.checkIn(o)) }
            if case .checkIn(let o)? = vm.quickReplies.first { vm.tap(.checkIn(o)) }
            T.expectEqual(Array(vm.answeredTrail.prefix(2)), [.sleep, second])
            vm.goBack(to: second)
            T.expectEqual(vm.askedSlot, second)
            T.expectEqual(vm.answeredTrail, [.sleep], "後の答えは取り消し")
            T.expectEqual(vm.checkIn.sleep?.value, .h7to9, "前の答えは残る")
        }
        await T.test("やり直し: 会話・集めた情報・戻る履歴を消し、会話IDを更新") {
            let vm = local()
            await vm.submit("明日面接、かなり緊張")
            let id = vm.conversationId
            vm.restart()
            T.expect(vm.checkIn.situation == nil && !vm.canGoBack, "reset")
            T.expect(vm.conversationId != id, "new id")
            T.expectEqual(vm.messages.count, 1)
        }
        await T.test("会話の内容を結果・提案へ渡す（メモリのみ）: 緊張の強さ 75 → high、会話の情報を含む") {
            let vm = local()
            await vm.submit("明日面接、かなり緊張してる、あまり寝られなかった")
            let m = vm.sessionMemory
            T.expectEqual(m.tension, .high)
            T.expectEqual(m.checkIn?.tension?.value, 75)
            T.expectEqual(m.situationNote, "明日面接、かなり緊張してる、あまり寝られなかった")
        }
    }
}
