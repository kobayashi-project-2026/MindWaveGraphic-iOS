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
        await T.test("もこりんが最初に場面を質問する（定型文と表示）") {
            let vm = localVM()
            T.expectEqual(vm.messages.count, 1)
            T.expect(vm.messages[0].text.contains("どんな状況かな"), "greeting")
            T.expectEqual(vm.messages[0].origin, .fixed)
            T.expectEqual(vm.step, .scene)
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
            T.expect(vm.messages.last?.text.contains("面接や発表の前なんだね") == true, "empathy + condition question")
            await vm.submit("さっき階段を上ってきました")
            T.expectEqual(vm.selectedConditions, [.stairs])
            T.expectEqual(vm.step, .review)
            T.expect(vm.messages.last?.text.contains("階段や移動の直後") == true, "summary")
            T.expect(vm.messages.allSatisfy { $0.origin == .user || $0.origin == .fixed }, "端末内は定型文と表示")
        }
        await T.test("曖昧な文章では場面を決めず、追加で質問する（同じ段階のまま）") {
            let vm = localVM()
            await vm.submit("少し緊張しています")
            T.expectEqual(vm.step, .scene)
            T.expect(!vm.hasSceneAnswer && vm.suggestedScene == nil, "not decided")
            T.expect(vm.messages.last?.text.contains("どんな場面の前かな") == true, "clarification")
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
        await T.test("やり直し: 会話と選択を最初の状態に戻し、会話IDを更新") {
            let vm = localVM()
            await vm.submit("面接の前です")
            let before = vm.conversationId
            vm.restart()
            T.expectEqual(vm.messages.count, 1)
            T.expectEqual(vm.step, .scene)
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
            T.expectEqual(req.step, .scene)
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
            let client = FakeContextClient.returning(reply: "緊張しているんだね。", scene: nil, clarify: true, question: "どんな場面の前かな？")
            let vm = remoteVM(client: client)
            await vm.submit("少し緊張しています")
            T.expectEqual(vm.step, .scene)
            T.expect(vm.messages.last?.text.contains("どんな場面の前かな？") == true, "question shown")
        }
        await T.test("スタブの返答は「スタブ」と表示（本物の AI として扱わない）。質問がない返答には定型の次の質問を添える") {
            let vm = remoteVM(client: .returning(reply: "（スタブ応答）", scene: "sports", provider: "openai-stub"))
            await vm.submit("試合の前です")
            T.expectEqual(vm.messages[vm.messages.count - 2].origin, .stub(model: "test-model"))
            T.expectEqual(vm.messages.last?.origin, .fixed)
            T.expect(vm.messages.last?.text.contains("移動してきたところ") == true, "next question")
        }
        await T.test("未知の候補・通信失敗: 採用せず、理由を表示して端末内の判定で続ける（手動でも測定できる）") {
            let bad = FakeContextClient.returning(reply: "ok", scene: "office_party")
            let vm = remoteVM(client: bad)
            await vm.submit("面接の前です")
            T.expect(vm.notice?.contains("外部AIに接続できなかった") == true, "notice")
            T.expectEqual(vm.selectedScene, .interview, "端末内の判定で続行")
            T.expectEqual(vm.messages.last?.origin, .fixed)
            let down = FakeContextClient { _ in throw InsightClientError.transport(code: -1004) }
            let vm2 = remoteVM(client: down)
            await vm2.submit("少し緊張しています")
            T.expect(vm2.notice?.contains("サーバーに接続できませんでした") == true, "transport notice")
            vm2.selectScene(.important); vm2.toggleCondition(.none); vm2.confirmConditions()
            T.expectEqual(vm2.step, .review)
            T.expectEqual(vm2.measurementContext.scene, .important)
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
        }
    }
}
