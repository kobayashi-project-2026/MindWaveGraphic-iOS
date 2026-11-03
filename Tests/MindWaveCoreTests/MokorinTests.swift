// MokorinTests.swift
// もこりんとの会話による状況整理（ボタン・文章・提案と修正・確定前に測定しない・外部AI・フォールバック・データ保護）のテスト。
// MW_E2E_BASE_URL / MW_E2E_CLIENT_TOKEN があれば、ローカルの server（--stub-openai）との E2E も行う。

import Foundation

/// テスト用のクライアント
final class FakeContextClient: ContextAssistClient, @unchecked Sendable {
    var requests: [ContextAssistRequestDTO] = []
    var handler: (ContextAssistRequestDTO) async throws -> ContextAssistResponseDTO

    init(handler: @escaping (ContextAssistRequestDTO) async throws -> ContextAssistResponseDTO) { self.handler = handler }

    func send(_ request: ContextAssistRequestDTO) async throws -> ContextAssistResponseDTO {
        requests.append(request)
        return try await handler(request)
    }

    static func returning(reply: String, scene: String?, conditions: [String] = [], clarify: Bool = false,
                          question: String? = nil, provider: String = "openai", delay: Duration = .zero) -> FakeContextClient {
        FakeContextClient { req in
            if delay != .zero { try await Task.sleep(for: delay) }
            return ContextAssistResponseDTO(
                schemaVersion: 1, requestId: req.requestId, conversationId: req.conversationId, provider: provider,
                model: "test-model", generatedAt: Date(),
                result: ContextAssistResultDTO(reply: reply, sceneCandidate: scene, conditionCandidates: conditions,
                                               needsClarification: clarify, clarificationQuestion: question),
                usage: nil)
        }
    }
}

enum MokorinTests {
    typealias T = TestHarness

    static let config = RemoteInsightConfiguration(baseURL: URL(string: "https://ctx.example.test")!,
                                                   clientToken: "test-client-token-0123456789", timeout: 2)

    /// 外部AIを使わない（未同意）もこりん
    static func localVM(initial: MeasurementContext = .default, inApp: Bool = false, name: String = #function) -> MokorinContextViewModel {
        let store = ChatTextConsentStore(defaults: T.freshDefaults("moko-local-\(name)"))
        return MokorinContextViewModel(initialContext: initial, isInAppEdit: inApp, consentStore: store,
                                       configurationProvider: { config }, clientFactory: { _ in FakeContextClient.returning(reply: "x", scene: nil) })
    }

    static func remoteVM(client: FakeContextClient, name: String = #function) -> MokorinContextViewModel {
        let store = ChatTextConsentStore(defaults: T.freshDefaults("moko-remote-\(name)"))
        store.setConsented(true)
        return MokorinContextViewModel(consentStore: store, configurationProvider: { config }, clientFactory: { _ in client })
    }

    static func run() async {
        T.suite("Mokorin / 端末内の判定（キーワード）")
        interpreter()
        T.suite("Mokorin / 会話フロー（ボタン・端末内）")
        await localFlow()
        T.suite("Mokorin / 外部AI（構造化候補）・フォールバック・データ保護")
        await remoteFlow()
        T.suite("Mokorin / 契約")
        contract()
        T.suite("Mokorin / 友達のキャラクター（WKWebView）の制御")
        await webCharacter()
        T.suite("Mokorin / 音声対話（1ターンずつ・テスト用の音声入出力）")
        await voice()
        await e2e()
    }

    // MARK: - 端末内の判定

    static func interpreter() {
        T.test("面接の文章 → interview、階段 → stairs、曖昧な「緊張しています」→ 場面なし") {
            T.expectEqual(MokorinKeywordInterpreter.interpret("これから就職活動の面接があって、少し緊張しています").scene, .interview)
            T.expectEqual(MokorinKeywordInterpreter.interpret("さっき階段を上ってきました").conditions, [.stairs])
            let vague = MokorinKeywordInterpreter.interpret("少し緊張しています")
            T.expect(vague.scene == nil && vague.conditions.isEmpty, "ambiguous")
        }
        T.test("複数の身体状態・「特になし」と他の状態は同時にならない") {
            T.expectEqual(MokorinKeywordInterpreter.interpret("走ってきて、コーヒーも飲んだ").conditions, [.running, .caffeine])
            T.expectEqual(MokorinKeywordInterpreter.interpret("特にないです").conditions, [.none])
            T.expectEqual(MokorinKeywordInterpreter.interpret("座っていたけど階段を上った").conditions, [.stairs])
        }
    }

    // MARK: - 会話フロー（端末内）

    static func localFlow() async {
        await T.test("もこりんが最初に「今、緊張してる？」と聞く（定型文と表示）") {
            let vm = localVM()
            T.expectEqual(vm.messages.count, 1)
            T.expectEqual(vm.messages[0].text, "こんにちは。今、緊張してる？")
            T.expectEqual(vm.messages[0].origin, .fixed)
            T.expectEqual(vm.step, .tension)
            T.expect(!vm.usesRemoteAI, "未同意なので外部AIを使わない")
        }
        await T.test("ボタンだけで: 場面を1つ選ぶ → 身体状態を複数選ぶ → 決定 → 確認") {
            let vm = localVM()
            vm.selectScene(.interview)
            T.expectEqual(vm.step, .condition)
            T.expect(vm.messages.last?.text.contains("移動してきたところ") == true, "asks condition")
            vm.toggleCondition(.stairs); vm.toggleCondition(.caffeine)
            T.expectEqual(vm.selectedConditions, [.stairs, .caffeine])
            vm.confirmConditions()
            T.expectEqual(vm.step, .review)
            T.expect(vm.messages.last?.text.contains("この状況で測定してみようか") == true, "summary")
            T.expectEqual(vm.measurementContext.scene, .interview)
            T.expectEqual(vm.measurementContext.conditions, [.stairs, .caffeine])
        }
        await T.test("「特になし」の排他制御（既存の画面と同じ規則）") {
            let vm = localVM()
            T.expectEqual(vm.selectedConditions, [.none])
            vm.toggleCondition(.running)
            T.expectEqual(vm.selectedConditions, [.running])
            vm.toggleCondition(.none)
            T.expectEqual(vm.selectedConditions, [.none])
            vm.toggleCondition(.smoking); vm.toggleCondition(.smoking)
            T.expectEqual(vm.selectedConditions, [.none], "全部外すと特になしに戻る")
        }
        await T.test("文章（端末内）: 体験の例どおり 面接 → 階段 → 確認。提案として表示され、測定はまだ始まらない") {
            let vm = localVM()
            await vm.submit("これから就職活動の面接があって、少し緊張しています")
            T.expectEqual(vm.selectedScene, .interview)
            T.expectEqual(vm.suggestedScene, .interview)
            T.expectEqual(vm.step, .condition)
            T.expect(vm.messages.last?.text.contains("面接前なんだね") == true, "empathy + condition question")
            await vm.submit("さっき階段を上ってきました")
            T.expectEqual(vm.selectedConditions, [.stairs])
            T.expectEqual(vm.step, .review)
            T.expect(vm.messages.last?.text.contains("階段を上った直後") == true, "summary")
            T.expect(vm.messages.allSatisfy { $0.origin == .user || $0.origin == .fixed }, "端末内は定型文と表示")
        }
        await T.test("「緊張しています」だけでは場面を決めず、予定を尋ねる。場面の段階で曖昧なら追加で質問する") {
            let vm = localVM()
            await vm.submit("少し緊張しています")
            T.expectEqual(vm.step, .scene)
            T.expectEqual(vm.subjectiveTension, .slight)
            T.expect(!vm.hasSceneAnswer && vm.suggestedScene == nil, "not decided")
            T.expect(vm.messages.last?.text.contains("何か予定があるの") == true, "asks plans")
            await vm.submit("うーん")
            T.expectEqual(vm.step, .scene)
            T.expect(vm.messages.last?.text.contains("面接や試合、作業など") == true, "clarification")
        }
        await T.test("提案を修正できる: 場面を別のボタンに変えると提案表示が消え、確認のまとめも更新") {
            let vm = localVM()
            await vm.submit("面接の前で、さっき階段を上ってきました")
            T.expectEqual(vm.step, .review)
            vm.selectScene(.sports)
            T.expectEqual(vm.selectedScene, .sports)
            T.expect(vm.suggestedScene == nil, "suggestion cleared")
            T.expect(vm.messages.last?.text.contains("試合や大会の前") == true, "summary refreshed")
            vm.toggleCondition(.running)
            T.expectEqual(vm.measurementContext.conditions, [.stairs, .running])
            T.expect(vm.suggestedConditions.isEmpty, "conditions suggestion cleared")
        }
        await T.test("メインアプリ内からの再設定: 現在の状況で始まり、変更しなければそのまま") {
            var ctx = MeasurementContext(); ctx.scene = .work; ctx.conditions = [.sleepLack]
            let vm = localVM(initial: ctx, inApp: true)
            T.expect(vm.messages[0].text.contains("作業 / 集中"), "edit greeting")
            T.expectEqual(vm.measurementContext.scene, .work)
            T.expectEqual(vm.measurementContext.conditions, [.sleepLack])
            vm.selectScene(.interview)
            T.expectEqual(vm.step, .review, "回答済みなので確認へ")
        }
        await T.test("体験の例（端末内の定型文）: かなり緊張 → 就活の面接 → 階段 → まとめ。主観的な緊張は MeasurementContext に入らない") {
            let vm = localVM()
            await vm.submit("かなり緊張してる")
            T.expectEqual(vm.subjectiveTension, .high)
            T.expectEqual(vm.messages.last?.text, "そっか。何か予定があるの？")
            T.expectEqual(vm.pose.emotion, .calm); T.expectEqual(vm.pose.action, .nod)
            await vm.submit("これから就活の面接なんだ")
            T.expectEqual(vm.messages.last?.text, "面接前なんだね。今は落ち着いて座ってる？それとも移動してきたところ？")
            await vm.submit("さっき階段を上ってきた")
            T.expectEqual(vm.messages.last?.text, "教えてくれてありがとう。面接前で、階段を上った直後なんだね。この状況で測定してみようか？")
            T.expectEqual(vm.step, .review)
            T.expectEqual(vm.measurementContext.scene, .interview)
            T.expectEqual(vm.measurementContext.conditions, [.stairs])
        }
        await T.test("選択肢だけで: 今は落ち着いてる → 特に予定はない → 座って落ち着いてる → 確認（緊張していなくても測定できる）") {
            let vm = localVM()
            T.expectEqual(vm.quickReplies.map(\.label), ["少し緊張してる", "かなり緊張してる", "今は落ち着いてる"])
            vm.tap(.tension(.calm))
            T.expectEqual(vm.messages.last?.text, "落ち着いているんだね。何か予定はある？")
            T.expectEqual(vm.pose.emotion, .happy)
            T.expect(vm.quickReplies.contains(.noPlan), "scene chips")
            vm.tap(.noPlan)
            T.expectEqual(vm.step, .condition)
            vm.tap(.condition(.none))
            T.expectEqual(vm.step, .review)
            T.expectEqual(vm.measurementContext.scene, .calm)
            T.expectEqual(vm.measurementContext.conditions, [.none])
        }
        await T.test("身体状態の選択肢: 1回のタップで答えて確認へ。複数の状態は話す・一覧で選ぶ（既定の「特になし」は外れる）") {
            let vm = localVM()
            vm.tap(.tension(.slight)); vm.tap(.scene(.sports))
            T.expectEqual(vm.step, .condition)
            vm.tap(.condition(.stairs))
            T.expectEqual(vm.selectedConditions, [.stairs])
            T.expectEqual(vm.step, .review)
            let vm2 = localVM(name: "multi")
            vm2.tap(.tension(.slight)); vm2.tap(.scene(.sports))
            await vm2.submit("走ってきたし、コーヒーも飲んだ")
            T.expectEqual(vm2.selectedConditions, [.running, .caffeine])
            T.expectEqual(vm2.step, .review)
        }
        await T.test("選択肢は最大3つ。一覧は外部AIなし・はっきりしない答えのあとだけ。確認段階では出さない") {
            let vm = localVM()
            T.expect(vm.quickReplies.count <= 3, "tension")
            vm.tap(.tension(.high))
            T.expect(vm.quickReplies.count <= 3 && vm.quickReplies.contains(.showList), "local → 一覧あり")
            vm.tap(.noPlan)
            T.expect(vm.quickReplies.count <= 3, "condition")
            vm.tap(.condition(.none))
            T.expectEqual(vm.quickReplies, [])
            let unclear = FakeContextClient.returning(reply: "そっか。何か予定があるの？", scene: nil)
            let r = remoteVM(client: unclear)
            r.tap(.tension(.slight))
            T.expectEqual(r.step, .scene)
            T.expect(!r.quickReplies.contains(.showList) && r.quickReplies.count == 3, "AI ありで最初は一覧を出さない")
            await r.submit("うーん")
            T.expect(r.quickReplies.contains(.showList) && r.quickReplies.count == 3, "はっきりしないと一覧を案内")
        }
        await T.test("会話での訂正: 最新の発言を優先（面接じゃなくて試合 / 面接って言ったけど実際はゼミの発表 / 階段じゃなくて走ってきた）") {
            let i = MokorinKeywordInterpreter.self
            T.expectEqual(i.interpret("面接じゃなくて試合だった").scene, .sports)
            T.expectEqual(i.interpret("試合って言ったけど、実際はゼミの発表だった").scene, .interview)
            let c = i.interpret("階段じゃなくて走ってきた")
            T.expectEqual(c.conditions, [.running])
            let vm = localVM()
            await vm.submit("かなり緊張してる")
            await vm.submit("これから面接なんだ")
            T.expectEqual(vm.selectedScene, .interview)
            await vm.submit("面接って言ったけど、実際は試合だった")
            T.expectEqual(vm.selectedScene, .sports, "最新の発言を優先")
        }
        await T.test("緊張の答えが2回はっきりしなくても先へ進む（同じ質問を繰り返さない）") {
            let vm = localVM()
            await vm.submit("うーん")
            T.expectEqual(vm.step, .tension)
            await vm.submit("よくわからない")
            T.expectEqual(vm.step, .scene)
        }
        await T.test("選択の編集（シート）: 発言を増やさずに変更し、「完了」で確認へ") {
            let vm = localVM()
            let count = vm.messages.count
            vm.editScene(.work); vm.editCondition(.afterMeal); vm.editCondition(.none); vm.editCondition(.smoking)
            T.expectEqual(vm.messages.count, count)
            T.expectEqual(vm.selectedConditions, [.smoking])
            vm.finishManualEdit()
            T.expectEqual(vm.step, .review)
            T.expectEqual(vm.measurementContext.scene, .work)
        }
        await T.test("シナリオA: かなり緊張してる → これから面接なんだ → 階段を上ってきた（high / interview / stairs）") {
            let vm = localVM()
            await vm.submit("かなり緊張してる")
            await vm.submit("これから面接なんだ")
            await vm.submit("階段を上ってきた")
            T.expectEqual(vm.subjectiveTension, .high)
            T.expectEqual(vm.step, .review)
            T.expectEqual(vm.measurementContext.scene, .interview)
            T.expectEqual(vm.measurementContext.conditions, [.stairs])
            T.expectEqual(vm.messages.filter { $0.speaker == .user }.count, 3, "会話の順序を保持")
            T.expect(vm.messages.last?.text.contains("この状況で測定してみようか") == true, "確認")
        }
        await T.test("シナリオB: 今は落ち着いてる → 特に予定はない → 座っている（calm / 安静 / 特になし）") {
            let vm = localVM()
            await vm.submit("今は落ち着いてる")
            T.expectEqual(vm.subjectiveTension, .calm)
            T.expectEqual(vm.messages.last?.text, "落ち着いているんだね。何か予定はある？")
            await vm.submit("特に予定はない")
            T.expectEqual(vm.step, .condition)
            await vm.submit("座っている")
            T.expectEqual(vm.step, .review)
            T.expectEqual(vm.measurementContext.scene, .calm, "予定なし＝既存の「安静」")
            T.expectEqual(vm.measurementContext.conditions, [.none])
        }
        await T.test("シナリオC: 緊張してるけど、理由がよくわからない → 場面を確定せず予定を尋ねる。測定不能にならない") {
            let vm = localVM()
            await vm.submit("緊張してるけど、理由がよくわからない")
            T.expectEqual(vm.subjectiveTension, .slight)
            T.expectEqual(vm.step, .scene)
            T.expect(!vm.hasSceneAnswer && vm.suggestedScene == nil, "場面は確定しない")
            T.expectEqual(vm.messages.last?.text, "そっか。何か予定があるの？")
            await vm.submit("わからない")
            T.expectEqual(vm.step, .scene, "曖昧なら同じ段階で尋ねる")
            T.expect(!vm.hasSceneAnswer, "推測で確定しない")
            T.expect(vm.quickReplies.contains(.showList) && vm.quickReplies.contains(.noPlan), "選択肢・一覧で先へ進める")
            vm.tap(.scene(.other))
            vm.tap(.condition(.none))
            T.expectEqual(vm.step, .review)
            T.expectEqual(vm.measurementContext.scene, .other)
        }
        await T.test("送信中の二重送信: 文字の連打・送信中の選択肢タップは無視（外部AI・待ち時間あり）") {
            let client = FakeContextClient.returning(reply: "そっか。何か予定があるの？", scene: nil, delay: .milliseconds(200))
            let vm = remoteVM(client: client)
            vm.draft = "かなり緊張してる"; vm.send()
            vm.draft = "もう一度"; vm.send()
            vm.tap(.tension(.calm))
            try await Task.sleep(for: .milliseconds(400))
            T.expectEqual(client.requests.count, 1)
            T.expectEqual(vm.messages.filter { $0.speaker == .user }.count, 1)
        }
        await T.test("やり直し: 会話と選択を最初の状態に戻し、会話IDを更新") {
            let vm = localVM()
            await vm.submit("面接の前です")
            let before = vm.conversationId
            vm.restart()
            T.expectEqual(vm.messages.count, 1)
            T.expectEqual(vm.step, .tension)
            T.expect(vm.subjectiveTension == nil, "tension cleared")
            T.expectEqual(vm.selectedScene, MeasurementContext.default.scene)
            T.expect(vm.conversationId != before, "new conversation")
        }
    }

    // MARK: - 外部AI

    static func remoteFlow() async {
        await T.test("外部AI: 構造化候補を提案として反映し、OpenAI の返答として表示。要求に会話と現在の選択を含む") {
            let client = FakeContextClient.returning(reply: "面接前なんだね。緊張するよね。今は移動してきたところ？", scene: "interview")
            let vm = remoteVM(client: client)
            await vm.submit("これから就職活動の面接があって、少し緊張しています")
            T.expectEqual(vm.selectedScene, .interview)
            T.expectEqual(vm.suggestedScene, .interview)
            T.expectEqual(vm.step, .condition)
            T.expectEqual(vm.messages.last?.origin, .openAI(model: "test-model"))
            let req = client.requests[0]
            T.expectEqual(req.step, .tension)
            T.expectEqual(req.messages.map(\.role), [.assistant, .user])
            T.expect(req.current.scene == nil && req.current.conditions.isEmpty, "未回答は null / 空")
        }
        await T.test("外部AI: 2回目は会話履歴（もこりんの返答を含む）と回答済みの場面を送る。確認段階でまとめを出す") {
            var turn = 0
            let client = FakeContextClient { req in
                turn += 1
                let result = turn == 1
                    ? ContextAssistResultDTO(reply: "面接前なんだね。今は移動してきたところ？", sceneCandidate: "interview", conditionCandidates: [], needsClarification: false, clarificationQuestion: nil)
                    : ContextAssistResultDTO(reply: "階段を上ってきたんだね。", sceneCandidate: nil, conditionCandidates: ["stairs"], needsClarification: false, clarificationQuestion: nil)
                return ContextAssistResponseDTO(schemaVersion: 1, requestId: req.requestId, conversationId: req.conversationId,
                                                provider: "openai", model: "m", generatedAt: Date(), result: result, usage: nil)
            }
            let vm = remoteVM(client: client)
            await vm.submit("面接があります")
            await vm.submit("さっき階段を上ってきました")
            let second = client.requests[1]
            T.expectEqual(second.step, .condition)
            T.expectEqual(second.current.scene, "interview")
            T.expectEqual(second.messages.count, 4)
            T.expect(second.messages.contains { $0.role == .assistant && $0.content.contains("面接前なんだね") }, "AI reply in history")
            T.expectEqual(vm.step, .review)
            T.expectEqual(vm.measurementContext.conditions, [.stairs])
            T.expect(vm.messages.last?.text.contains("この状況で測定してみようか") == true, "summary appended")
        }
        await T.test("外部AI: 曖昧なときは追加質問を表示し、場面は決めない") {
            let client = FakeContextClient.returning(reply: "そうなんだね。", scene: nil, clarify: true, question: "どんな場面の前かな？")
            let vm = remoteVM(client: client)
            await vm.submit("うーん")
            T.expectEqual(vm.step, .tension, "緊張も場面も分からないので同じ段階のまま")
            T.expect(vm.messages.last?.text.contains("どんな場面の前かな？") == true, "question shown")
        }
        await T.test("スタブの返答は「スタブ」と表示（本物の AI として扱わない）。質問がない返答には定型の次の質問を添える") {
            let vm = remoteVM(client: .returning(reply: "（スタブ応答）", scene: "sports", provider: "openai-stub"))
            await vm.submit("試合の前です")
            T.expectEqual(vm.messages[vm.messages.count - 2].origin, .stub(model: "test-model"))
            T.expectEqual(vm.messages.last?.origin, .fixed)
            T.expect(vm.messages.last?.text.contains("移動してきたところ") == true, "next question")
        }
        await T.test("未知の候補・通信失敗: 採用せず、黙って切り替えない。「もう一度送る」「AIなしで続ける」を出す（定型文を AI として見せない）") {
            let bad = FakeContextClient.returning(reply: "ok", scene: "office_party")
            let vm = remoteVM(client: bad)
            await vm.submit("面接の前です")
            T.expectEqual(vm.failedText, "面接の前です")
            T.expect(vm.notice?.contains("うまくつながらなかった") == true, "notice")
            T.expectEqual(vm.quickReplies, [.retry, .continueWithoutAI])
            T.expect(!vm.hasSceneAnswer, "未知の候補は採用しない")
            T.expectEqual(vm.messages.last?.speaker, .user, "定型文を勝手に返さない")
            vm.continueWithoutAI()
            T.expect(vm.failedText == nil && vm.notice == nil, "cleared")
            T.expectEqual(vm.selectedScene, .interview, "端末内の判定で続行")
            T.expectEqual(vm.messages.last?.origin, .fixed, "端末内の定型文と表示")
            let down = FakeContextClient { _ in throw InsightClientError.transport(code: -1004) }
            let vm2 = remoteVM(client: down)
            await vm2.submit("少し緊張しています")
            T.expect(vm2.notice?.contains("サーバーに接続できませんでした") == true, "transport notice")
            vm2.selectScene(.important); vm2.toggleCondition(.none); vm2.confirmConditions()
            T.expectEqual(vm2.step, .review)
            T.expectEqual(vm2.measurementContext.scene, .important)
        }
        await T.test("通信失敗 → もう一度送る: 利用者の操作でだけ再送し、成功したら会話を続ける（自動再送しない）") {
            let calls = Counter()
            let flaky = FakeContextClient { req in
                let n = calls.increment()
                if n == 1 { throw InsightClientError.transport(code: -1001) }
                return try await FakeContextClient.returning(reply: "面接なんだね。今は座ってる？", scene: "interview").send(req)
            }
            let vm = remoteVM(client: flaky)
            await vm.submit("これから面接")
            T.expectEqual(calls.value, 1, "自動再送しない")
            T.expect(vm.failedText != nil, "failed")
            await vm.retryFailed()
            T.expectEqual(calls.value, 2)
            T.expect(vm.failedText == nil, "recovered")
            T.expectEqual(vm.selectedScene, .interview)
            T.expectEqual(vm.messages.filter { $0.speaker == .user }.count, 1, "発言は二重にならない")
        }
        await T.test("送信の取り消し: 送った発言を外し、後から届いた応答は捨てる") {
            let slow = FakeContextClient.returning(reply: "面接なんだね。今は座ってる？", scene: "interview", delay: .milliseconds(300))
            let vm = remoteVM(client: slow)
            let before = vm.messages.count
            let task = Task { await vm.submit("これから面接") }
            try? await Task.sleep(for: .milliseconds(50))
            T.expect(vm.isSending, "sending")
            vm.cancelPending()
            T.expect(!vm.isSending, "cancelled")
            await task.value
            T.expectEqual(vm.messages.count, before, "応答を反映しない")
            T.expect(!vm.hasSceneAnswer, "候補も反映しない")
            T.expectEqual(vm.notice, "送信を取り消したよ。")
        }
        await T.test("同意なし: 会話本文を外部へ送らない（クライアントを呼ばない）") {
            let client = FakeContextClient.returning(reply: "x", scene: "interview")
            let store = ChatTextConsentStore(defaults: T.freshDefaults("moko-noconsent"))
            let vm = MokorinContextViewModel(consentStore: store, configurationProvider: { config }, clientFactory: { _ in client })
            await vm.submit("面接の前で、心拍が速い気がします")
            T.expectEqual(client.requests.count, 0)
        }
        await T.test("心拍・HRV を送らない: 要求 JSON に計測値の項目がない") {
            let client = FakeContextClient.returning(reply: "x", scene: "interview")
            let vm = remoteVM(client: client)
            await vm.submit("面接の前です")
            let json = String(data: try MindWaveContract.makeEncoder().encode(client.requests[0]), encoding: .utf8)!
            for key in ["heart", "hrv", "score", "bpm", "measurement"] { T.expect(!json.contains(key), "no \(key)") }
        }
        await T.test("連打・やり直し中の応答: 送信中は無視、やり直し後に届いた応答は破棄") {
            let client = FakeContextClient.returning(reply: "面接前なんだね", scene: "interview", delay: .milliseconds(200))
            let vm = remoteVM(client: client)
            vm.draft = "面接です"; vm.send()
            vm.draft = "もう一度"; vm.send()
            try await Task.sleep(for: .milliseconds(50))
            vm.restart()
            try await Task.sleep(for: .milliseconds(300))
            T.expectEqual(client.requests.count, 1)
            T.expectEqual(vm.messages.count, 1, "late reply discarded")
            T.expect(vm.suggestedScene == nil, "not applied")
        }
    }

    // MARK: - 契約

    static func contract() {
        T.test("リクエストの JSON: snake_case・未回答の scene は null を出力") {
            let req = ContextAssistRequestDTO(requestId: UUID(), conversationId: UUID(), step: .scene,
                                              messages: [ChatMessageDTO(role: .user, content: "面接です")],
                                              current: ContextAssistCurrentDTO(scene: nil, conditions: []))
            let json = String(data: try MindWaveContract.makeEncoder().encode(req), encoding: .utf8)!
            for key in ["\"schema_version\":1", "\"conversation_id\"", "\"step\":\"scene\"", "\"scene\":null", "\"conditions\":[]"] {
                T.expect(json.contains(key), key)
            }
        }
        T.test("応答の検証: 未知の候補・request_id 不一致は拒否、特になしと他の状態は特になしを外す") {
            let rid = UUID(), cid = UUID()
            func response(scene: String?, conds: [String]) -> ContextAssistResponseDTO {
                ContextAssistResponseDTO(schemaVersion: 1, requestId: rid, conversationId: cid, provider: "openai", model: "m", generatedAt: Date(),
                                         result: ContextAssistResultDTO(reply: "ok", sceneCandidate: scene, conditionCandidates: conds, needsClarification: false, clarificationQuestion: nil), usage: nil)
            }
            try ContextAssistValidation.validate(response(scene: "interview", conds: ["stairs"]), expectedRequestId: rid, expectedConversationId: cid)
            T.expectThrows("unknown scene") { try ContextAssistValidation.validate(response(scene: "party", conds: []), expectedRequestId: rid, expectedConversationId: cid) }
            T.expectThrows("unknown condition") { try ContextAssistValidation.validate(response(scene: nil, conds: ["flying"]), expectedRequestId: rid, expectedConversationId: cid) }
            T.expectThrows("rid") { try ContextAssistValidation.validate(response(scene: nil, conds: []), expectedRequestId: UUID(), expectedConversationId: cid) }
            T.expectEqual(try response(scene: nil, conds: ["none", "stairs"]).result.typedCandidates().conditions, [.stairs])
        }
    }

    // MARK: - 友達のキャラクター（WKWebView）の制御

    static func webCharacter() async {
        T.test("表情・動作は原本と同じ許可値（happy/calm/sad/sleepy、wave/jump/nod）") {
            T.expectEqual(MokorinEmotion.allCases.map(\.rawValue), ["happy", "calm", "sad", "sleepy"])
            T.expectEqual(MokorinAction.allCases.map(\.rawValue), ["wave", "jump", "nod"])
        }
        T.test("JavaScript 呼び出し: enum の値だけを使い、セリフは JSON 文字列にして渡す（コードとして解釈されない）") {
            T.expectEqual(MokorinWebScript.setEmotion(.sleepy), "setEmotion('sleepy')")
            T.expectEqual(MokorinWebScript.setAction(.jump), "setAction('jump')")
            let tricky = "こんにちは'); alert(1); ('\n\"<b>"
            let script = MokorinWebScript.setDialogue(tricky)
            T.expect(script.hasPrefix("setDialogue(\"") && script.hasSuffix("\")"), script)
            // JSON として読み戻すと元の文字列になる
            let inner = String(script.dropFirst("setDialogue(".count).dropLast())
            let decoded = try JSONSerialization.jsonObject(with: Data("[\(inner)]".utf8)) as? [String]
            T.expectEqual(decoded?.first, tricky)
        }
        T.test("pose: 動作を指定するたびに actionID が増え、同じ動作も再生し直せる") {
            let p0 = MokorinPose()
            let p1 = p0.with(.happy, .nod)
            let p2 = p1.with(.happy, .nod)
            T.expectEqual(p1.actionID, 1); T.expectEqual(p2.actionID, 2)
            T.expectEqual(p2.with(.sad, nil).actionID, 2, "表情だけの変更では動作を再生しない")
        }
        T.test("同梱リソース: mokorin.html が見つからなくてもクラッシュせず代替表示（テスト実行ファイルにはリソースがない）") {
            T.expect(MokorinWebView.resourceURL == nil || MokorinWebView.resourceURL?.lastPathComponent == "mokorin.html", "resource lookup")
        }
        await T.test("会話の表情: 最初は happy + wave、端末内の定型文は規則で決める（睡眠不足は sleepy、確認は happy）") {
            let vm = localVM()
            T.expectEqual(vm.pose.emotion, .happy); T.expectEqual(vm.pose.action, .wave)
            await vm.submit("面接があります")
            T.expectEqual(vm.pose.emotion, .calm); T.expectEqual(vm.pose.action, .nod)
            await vm.submit("寝不足です")
            T.expectEqual(vm.pose.emotion, .sleepy)
            let vm2 = localVM()
            vm2.selectScene(.interview); vm2.toggleCondition(.stairs); vm2.confirmConditions()
            T.expectEqual(vm2.pose.emotion, .happy)
        }
        await T.test("外部AIの表情・動作を使い、返答文はそのまま表示（固定セリフで上書きしない）。不正な値は calm / nod") {
            let client = FakeContextClient { req in
                ContextAssistResponseDTO(schemaVersion: 1, requestId: req.requestId, conversationId: req.conversationId, provider: "openai",
                                         model: "m", generatedAt: Date(),
                                         result: ContextAssistResultDTO(reply: "面接前なんだね！応援してるよ。今は移動してきたところ？", sceneCandidate: "interview",
                                                                        conditionCandidates: [], needsClarification: false, clarificationQuestion: nil,
                                                                        emotion: "happy", action: "jump"), usage: nil)
            }
            let vm = remoteVM(client: client)
            await vm.submit("面接があります")
            T.expectEqual(vm.pose.emotion, .happy); T.expectEqual(vm.pose.action, .jump)
            T.expectEqual(vm.messages.last?.text, "面接前なんだね！応援してるよ。今は移動してきたところ？")
            let bad = ContextAssistResultDTO(reply: "x", sceneCandidate: nil, conditionCandidates: [], needsClarification: true,
                                             clarificationQuestion: nil, emotion: "angry", action: "dance")
            T.expect(bad.typedExpression == (.calm, .nod), "fallback")
        }
        T.test("古いサーバー（emotion / action なし）の応答も読める") {
            let json = #"{"reply":"x","scene_candidate":null,"condition_candidates":[],"needs_clarification":true,"clarification_question":null}"#
            let r = try MindWaveContract.makeDecoder().decode(ContextAssistResultDTO.self, from: Data(json.utf8))
            T.expect(r.emotion == nil && r.typedExpression == (.calm, .nod), "defaults")
        }
    }

    // MARK: - 音声対話

    static func voice() async {
        await T.test("マイク: 権限あり → 録音 → 途中経過 → 確定した文字を会話へ送る → 待機に戻る") {
            let input = FakeSpeechInput(), output = FakeSpeechOutput()
            let vc = MokorinVoiceController(input: input, output: output)
            var received: [String] = []
            vc.onUtterance = { received.append($0) }
            await vc.micTapped()
            T.expect(vc.isListening, "listening")
            T.expect(vc.speaksReplies, "声で話したら読み上げを ON")
            input.partial("面接")
            try await Task.sleep(for: .milliseconds(20))
            T.expectEqual(vc.partialTranscript, "面接")
            await vc.micTapped()   // 話し終えて送る
            try await Task.sleep(for: .milliseconds(30))
            T.expectEqual(received, ["面接の前です"])
            T.expectEqual(vc.state, .idle)
        }
        await T.test("権限がない・使えない: 録音せず理由を表示（文字入力で続けられる）") {
            let input = FakeSpeechInput(); input.availability = .denied("マイクが許可されていません")
            let vc = MokorinVoiceController(input: input, output: FakeSpeechOutput())
            await vc.micTapped()
            T.expectEqual(input.startCount, 0)
            T.expectEqual(vc.state, .idle)
            T.expect(vc.problem?.contains("マイク") == true, "problem shown")
        }
        await T.test("読み上げ中にマイク: 読み上げを止めてから録音（自分の声を認識しない）。録音中は読み上げない") {
            let input = FakeSpeechInput(), output = FakeSpeechOutput()
            let vc = MokorinVoiceController(input: input, output: output)
            vc.speaksReplies = true
            var speaking: [Bool] = []
            vc.onSpeakingChanged = { speaking.append($0) }
            vc.speakReply("そっか。何か予定があるの？")
            T.expectEqual(vc.state, .speaking)
            T.expectEqual(output.spoken, ["そっか。何か予定があるの？"])
            await vc.micTapped()
            T.expectEqual(output.stopCount, 1)
            T.expect(input.stopBeforeStart, "読み上げ停止の後に録音開始")
            T.expect(vc.isListening, "listening")
            vc.speakReply("録音中は読まない")
            T.expectEqual(output.spoken.count, 1)
            T.expectEqual(speaking, [true, false])
        }
        await T.test("読み上げ OFF のときは読まない・空の認識結果は送らない") {
            let input = FakeSpeechInput(), output = FakeSpeechOutput()
            let vc = MokorinVoiceController(input: input, output: output)
            vc.speakReply("こんにちは")
            T.expectEqual(output.spoken.count, 0)
            var received = 0
            vc.onUtterance = { _ in received += 1 }
            input.finalText = "  "
            await vc.micTapped(); await vc.micTapped()
            try await Task.sleep(for: .milliseconds(30))
            T.expectEqual(received, 0)
            T.expect(vc.problem?.contains("聞き取れなかった") == true, "retry message")
        }
        T.test("実機の接続診断: 実機で 127.0.0.1 / localhost は届かないと判定（シミュレーター・https の別ホストは対象外）") {
            let local = URL(string: "http://127.0.0.1:8787")!
            T.expect(ServerConnectionDiagnostics.isLoopbackUnreachable(local, isSimulator: false), "device + loopback")
            T.expect(!ServerConnectionDiagnostics.isLoopbackUnreachable(local, isSimulator: true), "simulator ok")
            T.expect(ServerConnectionDiagnostics.isLoopbackUnreachable(URL(string: "http://localhost:8787")!, isSimulator: false), "localhost")
            T.expect(!ServerConnectionDiagnostics.isLoopbackUnreachable(URL(string: "https://insight.example.com")!, isSimulator: false), "remote https")
            T.expect(InsightClientError.loopbackOnDevice.chatUserMessage.contains("iPhone 自身"), "clear message")
        }
        T.test("同じ Wi-Fi の開発用サーバー: プライベート IP・.local だけを LAN と判定。Debug でだけ http を許可（グローバル IP の http は不可）") {
            let lan = ServerConnectionDiagnostics.isPrivateLANHost
            for ok in ["http://192.168.1.20:8787", "http://10.0.0.5:8787", "http://172.20.3.4:8787", "http://my-mac.local:8787"] {
                T.expect(lan(URL(string: ok)!), ok)
            }
            for ng in ["http://172.32.0.1:8787", "http://8.8.8.8:8787", "http://example.com", "http://192.168.1:8787"] {
                T.expect(!lan(URL(string: ng)!), ng)
            }
            let d = T.freshDefaults("lan-config")
            let env = ["MW_INSIGHT_BASE_URL": "http://192.168.1.20:8787", "MW_INSIGHT_CLIENT_TOKEN": "t"]
            T.expect(RemoteInsightConfiguration.load(defaults: d, environment: env) != nil, "DEBUG: LAN http ok")
            T.expect(RemoteInsightConfiguration.load(defaults: d, environment: ["MW_INSIGHT_BASE_URL": "http://8.8.8.8:8787", "MW_INSIGHT_CLIENT_TOKEN": "t"]) == nil, "global http ng")
        }
        T.test("読み上げ中の口の動き: setSpeaking の呼び出し文") {
            T.expectEqual(MokorinWebScript.setSpeaking(true), "setSpeaking(true)")
            T.expectEqual(MokorinWebScript.setSpeaking(false), "setSpeaking(false)")
        }
    }

    // MARK: - E2E（ローカルサーバー＋OpenAI スタブ）

    static func e2e() async {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["MW_E2E_BASE_URL"], let url = URL(string: base), let token = env["MW_E2E_CLIENT_TOKEN"] else {
            print("\n=== Mokorin / E2E (skipped: MW_E2E_BASE_URL 未設定) ===")
            return
        }
        T.suite("Mokorin / E2E with local server (\(base))")
        let cfg = RemoteInsightConfiguration(baseURL: url, clientToken: token, timeout: 10)
        await T.test("体験の例（面接 → 階段）: サーバー（スタブ）経由で候補を受け取り、確認段階へ。スタブと表示") {
            let store = ChatTextConsentStore(defaults: T.freshDefaults("moko-e2e"))
            store.setConsented(true)
            let vm = MokorinContextViewModel(consentStore: store, configurationProvider: { cfg },
                                             clientFactory: { RemoteContextAssistClient(configuration: $0, session: URLSession(configuration: .ephemeral)) })
            await vm.submit("これから就職活動の面接があって、少し緊張しています")
            T.expectEqual(vm.selectedScene, .interview)
            await vm.submit("さっき階段を上ってきました")
            T.expectEqual(vm.selectedConditions, [.stairs])
            T.expectEqual(vm.step, .review)
            T.expect(vm.messages.contains { if case .stub = $0.origin { return true }; return false }, "stub labelled")
            T.expect(vm.notice == nil, "no fallback: \(vm.notice ?? "")")
            T.expectEqual(vm.pose.action, .nod, "サーバーの action を反映")
        }
    }
}

// MARK: - テスト用の音声入出力

nonisolated final class FakeSpeechInput: MokorinSpeechInput, @unchecked Sendable {
    var availability: MokorinVoiceAvailability = .available
    var finalText = "面接の前です"
    var startCount = 0
    var stopBeforeStart = false
    weak var output: FakeSpeechOutput?
    private var onPartial: ((String) -> Void)?
    private var onFinal: ((String) -> Void)?

    func requestAvailability() async -> MokorinVoiceAvailability { availability }
    func start(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void, onError: @escaping (String) -> Void) throws {
        startCount += 1
        stopBeforeStart = FakeSpeechOutput.lastStopTime != nil
        self.onPartial = onPartial
        self.onFinal = onFinal
    }
    func partial(_ text: String) { onPartial?(text) }
    func stop() { let f = onFinal; onFinal = nil; f?(finalText) }
    func cancel() { onFinal = nil }
}

nonisolated final class FakeSpeechOutput: MokorinSpeechOutput, @unchecked Sendable {
    nonisolated(unsafe) static var lastStopTime: Date?
    var onFinish: (() -> Void)?
    var spoken: [String] = []
    var stopCount = 0
    var isSpeaking = false
    init() { FakeSpeechOutput.lastStopTime = nil }
    func speak(_ text: String) { spoken.append(text); isSpeaking = true }
    func stop() { stopCount += 1; isSpeaking = false; FakeSpeechOutput.lastStopTime = Date() }
}

/// テスト用の呼び出し回数（Sendable）
nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}
