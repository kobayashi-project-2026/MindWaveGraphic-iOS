// ChatTests.swift
// AI 相談（契約・履歴の上限・生体データの送信防止・通信エラー・複数往復・リセット・連打・フォールバック）のテスト。
// 通信は URLProtocol のスタブ／テスト用クライアントで再現する（外部へは送信しない）。
// MW_E2E_BASE_URL / MW_E2E_CLIENT_TOKEN があれば、ローカルの server（--stub-openai）との複数往復 E2E も行う。

import Foundation

/// テスト用クライアント。受け取ったリクエストを記録し、handler の結果を返す
final class FakeChatClient: ChatRemoteClient, @unchecked Sendable {
    var requests: [ChatRequestDTO] = []
    var handler: (ChatRequestDTO) async throws -> ChatResponseDTO

    init(handler: @escaping (ChatRequestDTO) async throws -> ChatResponseDTO) {
        self.handler = handler
    }

    func send(_ request: ChatRequestDTO) async throws -> ChatResponseDTO {
        requests.append(request)
        return try await handler(request)
    }

    /// 受け取った最後の発言を引用して返す（provider は指定）
    static func echo(provider: String = "openai", delay: Duration = .zero) -> FakeChatClient {
        FakeChatClient { req in
            if delay != .zero { try await Task.sleep(for: delay) }
            return ChatResponseDTO(schemaVersion: 1, requestId: req.requestId, conversationId: req.conversationId,
                                   provider: provider, model: "test-model", generatedAt: Date(),
                                   reply: ChatReplyDTO(text: "返答: \(req.messages.last?.content ?? "")", truncated: false), usage: nil)
        }
    }
}

enum ChatTests {
    typealias T = TestHarness

    static let config = RemoteInsightConfiguration(baseURL: URL(string: "https://chat.example.test")!,
                                                   clientToken: "test-client-token-0123456789", timeout: 2)

    static func makeVM(client: FakeChatClient, consent: Bool = true, configured: Bool = true,
                       scene: ContextScene? = .interview, name: String = #function) -> ChatViewModel {
        let store = ChatTextConsentStore(defaults: T.freshDefaults("chat-\(name)-\(consent)"))
        store.setConsented(consent)
        return ChatViewModel(consentStore: store,
                             configurationProvider: { configured ? config : nil },
                             clientFactory: { _ in client },
                             sceneProvider: { scene })
    }

    /// 送信中が終わるまで待つ（最大2秒）
    static func waitIdle(_ vm: ChatViewModel) async {
        for _ in 0..<200 where vm.isSending { try? await Task.sleep(for: .milliseconds(10)) }
    }

    static func run() async {
        T.suite("Chat / 契約")
        contract()
        T.suite("Chat / 履歴の上限・生体データの送信防止・端末内アドバイス")
        policy()
        T.suite("Chat / RemoteChatClient（スタブ通信）")
        await remote()
        T.suite("Chat / ChatViewModel（複数往復・リセット・連打・フォールバック）")
        await viewModel()
        await e2e()
    }

    // MARK: - 契約

    static func contract() {
        T.test("リクエスト: snake_case・scene/measurement の null を省略せず出力") {
            let req = ChatRequestDTO(requestId: UUID(), conversationId: UUID(),
                                     messages: [ChatMessageDTO(role: .user, content: "面接前で緊張しています")],
                                     context: ChatContextDTO(scene: nil, measurement: nil),
                                     consent: ChatConsentDTO(biometricContextConsented: false, consentVersion: 1))
            let json = String(data: try MindWaveContract.makeEncoder().encode(req), encoding: .utf8)!
            for key in ["\"schema_version\":1", "\"conversation_id\"", "\"request_id\"", "\"locale\":\"ja-JP\"",
                        "\"scene\":null", "\"measurement\":null", "\"biometric_context_consented\":false", "\"role\":\"user\""] {
                T.expect(json.contains(key), "json contains \(key)")
            }
        }
        T.test("レスポンス: 復号・スタブ判定・request_id 不一致は拒否") {
            let rid = UUID(), cid = UUID()
            let body = """
            {"schema_version":1,"request_id":"\(rid.uuidString)","conversation_id":"\(cid.uuidString)","provider":"openai-stub",
             "model":"stub-model","generated_at":"2026-10-28T04:40:00.000Z","reply":{"text":"こんにちは","truncated":false},
             "usage":{"input_tokens":1,"output_tokens":2,"reasoning_tokens":0,"total_tokens":3}}
            """
            let r = try MindWaveContract.makeDecoder().decode(ChatResponseDTO.self, from: Data(body.utf8))
            T.expect(r.isStub, "stub")
            T.expectEqual(r.usage?.outputTokens, 2)
            try ChatResponseValidation.validate(r, expectedRequestId: rid, expectedConversationId: cid)
            T.expectThrows("request id mismatch") { try ChatResponseValidation.validate(r, expectedRequestId: UUID(), expectedConversationId: cid) }
            T.expectThrows("conversation mismatch") { try ChatResponseValidation.validate(r, expectedRequestId: rid, expectedConversationId: UUID()) }
        }
    }

    // MARK: - 方針

    static func policy() {
        T.test("履歴: 直近12件・先頭は利用者の発言・長文は上限で切る・合計文字数の上限") {
            let many = (0..<20).map { ChatMessageDTO(role: $0 % 2 == 0 ? .user : .assistant, content: "m\($0)") }
            let t = ChatHistoryPolicy.trimmed(many)
            T.expect(t.count <= ChatLimits.maxMessages, "count")
            T.expectEqual(t.first?.role, .user)
            T.expectEqual(t.last?.content, "m19")
            let long = [ChatMessageDTO(role: .user, content: String(repeating: "あ", count: 900))]
            T.expectEqual(ChatHistoryPolicy.trimmed(long).first?.content.count, ChatLimits.maxUserChars)
            let big = (0..<12).map { ChatMessageDTO(role: $0 % 2 == 0 ? .user : .assistant, content: String(repeating: "い", count: $0 % 2 == 0 ? 500 : 1500)) }
            let total = ChatHistoryPolicy.trimmed(big).reduce(0) { $0 + $1.content.count }
            T.expect(total <= ChatLimits.maxTotalChars, "total \(total)")
        }
        T.test("生体データ: 同意があっても本物の利用者認証がなければ送らない（現在は常に送らない）") {
            let result = MindAnalysisResult(tensionScore: 72, confidence: 0.75, state: .overTense, timestamp: Date(),
                                            metadata: { var m = AnalysisMetadata(); m.source = .watchLive; m.hrvStatus = .measured; return m }())
            T.expect(!ChatBiometricPolicy.isRealUserAuthenticated, "認証基盤がないため false")
            T.expect(ChatBiometricPolicy.measurementContext(from: result, now: Date(), consented: true) == nil, "consent only")
            T.expect(ChatBiometricPolicy.measurementContext(from: result, now: Date(), consented: false, authenticated: true) == nil, "auth only")
            let allowed = ChatBiometricPolicy.measurementContext(from: result, now: Date(), consented: true, authenticated: true)
            T.expectEqual(allowed?.source, .watchLive)
            T.expectEqual(allowed?.isMock, false)
            T.expectEqual(allowed?.state, .overTense)
        }
        T.test("端末内アドバイス: 呼吸の質問・危機的な内容（相談窓口・119 を案内）") {
            T.expect(LocalChatResponder.reply(to: "呼吸法を詳しく教えて", scene: nil).contains("4-7-8"), "breathing")
            T.expect(LocalChatResponder.reply(to: "消えたい", scene: nil).contains("119"), "crisis")
            T.expect(LocalChatResponder.reply(to: "緊張しています", scene: .interview).contains("面接"), "scene")
        }
    }

    // MARK: - 通信

    static func remote() async {
        let client = RemoteChatClient(configuration: config, session: StubURLProtocol.session())
        func request(_ text: String = "面接前で緊張しています") -> ChatRequestDTO {
            ChatRequestDTO(requestId: UUID(), conversationId: UUID(), messages: [ChatMessageDTO(role: .user, content: text)],
                           context: ChatContextDTO(scene: "interview", measurement: nil),
                           consent: ChatConsentDTO(biometricContextConsented: false, consentVersion: 1))
        }
        func okReply(_ req: URLRequest, _ body: Data, provider: String = "openai") -> StubURLProtocol.Reply {
            let r = try? MindWaveContract.makeDecoder().decode(ChatRequestDTO.self, from: body)
            var reply = StubURLProtocol.Reply()
            reply.body = Data("""
            {"schema_version":1,"request_id":"\(r?.requestId.uuidString ?? "")","conversation_id":"\(r?.conversationId.uuidString ?? "")",
             "provider":"\(provider)","model":"gpt-6-luna","generated_at":"2026-10-28T04:40:00.000Z",
             "reply":{"text":"ゆっくり息を吐いてみましょう。","truncated":false},"usage":null}
            """.utf8)
            return reply
        }
        func errorReply(_ status: Int, _ code: String) -> StubURLProtocol.Reply {
            var r = StubURLProtocol.Reply(); r.status = status
            r.body = Data("{\"schema_version\":1,\"request_id\":null,\"error\":\"\(code)\",\"message\":\"x\"}".utf8)
            return r
        }

        await T.test("成功: POST /v1/chat・Bearer 認証・応答の検証") {
            StubURLProtocol.reply = { req, body in okReply(req, body) }
            let res = try await client.send(request())
            T.expectEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/chat")
            T.expectEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-client-token-0123456789")
            T.expectEqual(res.provider, "openai")
            T.expect(!res.isStub, "real provider label")
        }
        for (status, code) in [(401, "unauthorized"), (429, "rate_limited"), (503, "not_configured"), (502, "invalid_upstream_response"), (504, "upstream_timeout")] {
            await T.test("HTTP \(status) \(code) → httpStatus") {
                StubURLProtocol.reply = { _, _ in errorReply(status, code) }
                do { _ = try await client.send(request()); T.fail("expected error") }
                catch let e as InsightClientError { T.expectEqual(e, .httpStatus(status, errorCode: code)); T.expect(!e.chatUserMessage.isEmpty, "message") }
            }
        }
        await T.test("不正な JSON 応答 → invalidResponse") {
            StubURLProtocol.reply = { _, _ in var r = StubURLProtocol.Reply(); r.body = Data("{not json".utf8); return r }
            do { _ = try await client.send(request()); T.fail("expected error") }
            catch let e as InsightClientError { T.expectEqual(e.logCode, "invalid_response") }
        }
        await T.test("タイムアウト → timeout") {
            var short = config; short.timeout = 0.3
            let slow = RemoteChatClient(configuration: short, session: StubURLProtocol.session())
            StubURLProtocol.reply = { req, body in var r = okReply(req, body); r.delay = 2; return r }
            do { _ = try await slow.send(request()); T.fail("expected timeout") }
            catch let e as InsightClientError { T.expectEqual(e, .timeout) }
        }
        await T.test("サーバー停止（接続拒否）→ transport") {
            let down = RemoteChatClient(configuration: RemoteInsightConfiguration(baseURL: URL(string: "http://127.0.0.1:9")!,
                                                                                  clientToken: "test-client-token-0123456789", timeout: 3),
                                        session: URLSession(configuration: .ephemeral))
            do { _ = try await down.send(request()); T.fail("expected error") }
            catch let e as InsightClientError {
                if case .transport = e {} else { T.fail("expected transport, got \(e)") }
            }
        }
    }

    // MARK: - ViewModel

    static func viewModel() async {
        await T.test("複数往復: 2回目は1回目の発言と返答を順番どおり含み、同じ会話IDで送る") {
            let client = FakeChatClient.echo()
            let vm = makeVM(client: client)
            await vm.submit("明日のプレゼンが不安です")
            await vm.submit("具体的に何を準備すればいい？")
            T.expectEqual(client.requests.count, 2)
            let second = client.requests[1].messages
            T.expectEqual(second.map(\.role), [.user, .assistant, .user])
            T.expectEqual(second.first?.content, "明日のプレゼンが不安です")
            T.expectEqual(second.last?.content, "具体的に何を準備すればいい？")
            T.expectEqual(client.requests[0].conversationId, client.requests[1].conversationId)
            T.expectEqual(client.requests[1].context.scene, "interview")
            T.expectEqual(vm.messages.map(\.role), [.user, .assistant, .user, .assistant])
            T.expectEqual(vm.messages[1].origin, .openAI(model: "test-model"))
            T.expect(vm.messages.allSatisfy { $0.status == .sent }, "all sent")
        }
        await T.test("3往復でも会話の順序を保つ") {
            let client = FakeChatClient.echo()
            let vm = makeVM(client: client)
            for t in ["面接前で緊張しています", "さっき言っていた呼吸法を詳しく教えて", "何回くらい繰り返せばいい？"] { await vm.submit(t) }
            T.expectEqual(client.requests.last?.messages.count, 5)
            T.expectEqual(vm.messages.filter { $0.role == .user }.map(\.text), ["面接前で緊張しています", "さっき言っていた呼吸法を詳しく教えて", "何回くらい繰り返せばいい？"])
        }
        await T.test("スタブの返答は「スタブ」として区別する") {
            let vm = makeVM(client: FakeChatClient.echo(provider: "openai-stub"))
            await vm.submit("こんにちは")
            T.expectEqual(vm.messages.last?.origin, .stub(model: "test-model"))
        }
        await T.test("未同意・サーバー未設定: 外部へ送らず端末内アドバイスで応答する") {
            let c1 = FakeChatClient.echo()
            let noConsent = makeVM(client: c1, consent: false)
            await noConsent.submit("面接前で緊張しています")
            T.expectEqual(c1.requests.count, 0)
            T.expectEqual(noConsent.remoteUnavailableReason, .consentMissing)
            if case .local = noConsent.messages.last?.origin {} else { T.fail("local expected") }
            let c2 = FakeChatClient.echo()
            let noServer = makeVM(client: c2, configured: false)
            await noServer.submit("面接前で緊張しています")
            T.expectEqual(c2.requests.count, 0)
            T.expectEqual(noServer.remoteUnavailableReason, .notConfigured)
        }
        await T.test("同意の取り消し（設定画面で OFF）は次の表示で反映され、以後は外部へ送らない") {
            let client = FakeChatClient.echo()
            let defaults = T.freshDefaults("chat-revoke")
            let store = ChatTextConsentStore(defaults: defaults)
            store.setConsented(true)
            let vm = ChatViewModel(consentStore: store, configurationProvider: { config }, clientFactory: { _ in client })
            await vm.submit("1回目")
            ChatTextConsentStore(defaults: defaults).setConsented(false)   // 設定画面のトグルと同じ操作
            vm.refreshConsent()
            T.expectEqual(vm.remoteUnavailableReason, .consentMissing)
            await vm.submit("2回目")
            T.expectEqual(client.requests.count, 1)
        }
        await T.test("通信失敗: 発言は「失敗」、端末内アドバイスを表示。再送信で置き換わり、履歴に端末内アドバイスを含めない") {
            var fail = true
            let client = FakeChatClient { req in
                if fail { throw InsightClientError.httpStatus(429, errorCode: "rate_limited") }
                return try await FakeChatClient.echo().send(req)
            }
            let vm = makeVM(client: client)
            await vm.submit("面接前で緊張しています")
            T.expect({ if case .failed = vm.messages[0].status { return true }; return false }(), "failed")
            if case .local = vm.messages[1].origin {} else { T.fail("local fallback") }
            T.expect(vm.lastFailureMessage?.contains("混み合") == true, "429 message")
            T.expect(vm.canRetry, "can retry")
            fail = false
            await vm.retryLastFailed()
            T.expectEqual(vm.messages.count, 2)
            T.expectEqual(vm.messages[0].status, .sent)
            T.expectEqual(vm.messages[1].origin, .openAI(model: "test-model"))
            T.expect(vm.lastFailureMessage == nil, "cleared")
            // 失敗後に別の発言を送っても、端末内アドバイスは外部AIへの履歴に含めない
            fail = true
            await vm.submit("2つ目")
            fail = false
            await vm.submit("3つ目")
            let sent = client.requests.last!.messages
            T.expect(!sent.contains { $0.content.contains("端末内") || $0.content == vm.messages.first(where: { if case .local = $0.origin { return true }; return false })?.text }, "no local text")
            T.expectEqual(sent.map(\.content).filter { !$0.hasPrefix("返答") }, ["面接前で緊張しています", "2つ目", "3つ目"])
        }
        await T.test("連打: 送信中の2回目は無視し、リクエストは1件") {
            let client = FakeChatClient.echo(delay: .milliseconds(200))
            let vm = makeVM(client: client)
            vm.draft = "1回目"; vm.send()
            vm.draft = "2回目"; vm.send()
            T.expect(vm.isSending, "sending")
            T.expect(!vm.canSend, "cannot send while sending")
            await waitIdle(vm)
            T.expectEqual(client.requests.count, 1)
            T.expectEqual(vm.messages.filter { $0.role == .user }.count, 1)
            T.expectEqual(vm.draft, "2回目", "未送信の入力は残る")
        }
        await T.test("リセット: 会話を消去し新しい会話IDに。送信中の応答が後から届いても混ざらない") {
            let client = FakeChatClient.echo(delay: .milliseconds(200))
            let vm = makeVM(client: client)
            let before = vm.conversationId
            vm.draft = "古い会話"; vm.send()
            try await Task.sleep(for: .milliseconds(50))
            vm.reset()
            T.expect(vm.messages.isEmpty && !vm.isSending, "cleared")
            T.expect(vm.conversationId != before, "new conversation id")
            try await Task.sleep(for: .milliseconds(300))
            T.expect(vm.messages.isEmpty, "late reply discarded")
            await vm.submit("新しい会話")
            T.expectEqual(client.requests.last?.messages.map(\.content), ["新しい会話"])
            T.expectEqual(client.requests.last?.conversationId, vm.conversationId)
        }
        await T.test("生体データ: 外部AI同意ありでも、認証がないため context.measurement は常に null") {
            let client = FakeChatClient.echo()
            let vm = makeVM(client: client)
            let result = MindAnalysisResult(tensionScore: 72, confidence: 0.75, state: .overTense, timestamp: Date(), metadata: AnalysisMetadata())
            vm.configureContext(scene: { .interview },
                                measurement: { ChatBiometricPolicy.measurementContext(from: result, now: Date(), consented: true) },
                                biometricConsent: { true })
            await vm.submit("面接前で緊張しています")
            T.expect(client.requests.first?.context.measurement == nil, "measurement not sent")
            let json = String(data: try MindWaveContract.makeEncoder().encode(client.requests[0]), encoding: .utf8)!
            T.expect(!json.contains("heart") && !json.contains("hrv_sdnn") && !json.contains("score"), "no biometric values")
        }
        await T.test("出力上限で途中終了した返答は truncated として表示") {
            let client = FakeChatClient { req in
                ChatResponseDTO(schemaVersion: 1, requestId: req.requestId, conversationId: req.conversationId, provider: "openai",
                                model: "m", generatedAt: Date(), reply: ChatReplyDTO(text: "途中まで", truncated: true), usage: nil)
            }
            let vm = makeVM(client: client)
            await vm.submit("長い説明をして")
            T.expect(vm.messages.last?.truncated == true, "truncated")
        }
    }

    // MARK: - E2E（ローカルサーバー＋OpenAI スタブ）

    static func e2e() async {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["MW_E2E_BASE_URL"], let url = URL(string: base), let token = env["MW_E2E_CLIENT_TOKEN"] else {
            print("\n=== Chat / E2E (skipped: MW_E2E_BASE_URL 未設定) ===")
            return
        }
        T.suite("Chat / E2E with local server (\(base))")
        let cfg = RemoteInsightConfiguration(baseURL: url, clientToken: token, timeout: 10)
        await T.test("3往復: サーバー（スタブ）が毎回それまでの履歴を受け取り、provider=openai-stub と表示する") {
            let store = ChatTextConsentStore(defaults: T.freshDefaults("chat-e2e"))
            store.setConsented(true)
            let vm = ChatViewModel(consentStore: store, configurationProvider: { cfg },
                                   clientFactory: { RemoteChatClient(configuration: $0, session: URLSession(configuration: .ephemeral)) },
                                   sceneProvider: { .interview })
            await vm.submit("面接前で緊張しています")
            await vm.submit("さっき言っていた呼吸法を詳しく教えて")
            await vm.submit("何回くらい繰り返せばいい？")
            let replies = vm.messages.filter { $0.role == .assistant }
            T.expectEqual(replies.count, 3)
            T.expect(replies.allSatisfy { if case .stub = $0.origin { return true }; return false }, "all stub-labelled")
            T.expect(replies[1].text.contains("利用者 2 件・AI 1 件"), "2nd turn history: \(replies[1].text)")
            T.expect(replies[1].text.contains("面接前で緊張しています"), "2nd turn refers to 1st topic")
            T.expect(replies[2].text.contains("利用者 3 件・AI 2 件"), "3rd turn history")
            T.expect(replies[2].text.contains("場面"), "scene passed")
        }
    }
}
