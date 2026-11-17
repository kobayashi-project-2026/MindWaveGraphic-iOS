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
    }

    // MARK: - 外部AI

    static func remoteFlow() async {
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
            let input = FakeSpeechInput(); input.availability = .unavailable(.microphoneDenied)
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
            T.expect(vc.problem?.contains("声が聞こえなかった") == true, "retry message")
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
        T.test("開発用サーバーの設定（DevServer.local.xcconfig → Info.plist）: ホーム画面から起動しても接続先が残る。実機ではスキームの 127.0.0.1 より LAN を優先") {
            let d = T.freshDefaults("dev-info")
            let info: [String: Any] = ["MWDevServerHost": "192.168.11.31", "MWDevServerPort": "8788", "MWDevClientToken": "tok-lan"]
            let fromInfo = RemoteInsightConfiguration.load(defaults: d, environment: [:], info: info, isSimulator: false)
            T.expectEqual(fromInfo?.baseURL.absoluteString, "http://192.168.11.31:8788")
            T.expectEqual(fromInfo?.clientToken, "tok-lan")
            let loopEnv = ["MW_INSIGHT_BASE_URL": "http://127.0.0.1:8787", "MW_INSIGHT_CLIENT_TOKEN": "tok-sim"]
            let device = RemoteInsightConfiguration.load(defaults: d, environment: loopEnv, info: info, isSimulator: false)
            T.expectEqual(device?.baseURL.absoluteString, "http://192.168.11.31:8788", "実機: LAN を優先")
            T.expectEqual(device?.clientToken, "tok-lan")
            let sim = RemoteInsightConfiguration.load(defaults: d, environment: loopEnv, info: info, isSimulator: true)
            T.expectEqual(sim?.baseURL.absoluteString, "http://127.0.0.1:8787", "シミュレーター: スキームを優先")
            let unset: [String: Any] = ["MWDevServerHost": "", "MWDevClientToken": "$(MW_DEV_CLIENT_TOKEN)"]
            T.expect(RemoteInsightConfiguration.load(defaults: d, environment: [:], info: unset, isSimulator: false) == nil, "未設定なら接続しない")
        }
        await T.test("吹き出し: AI の返答に定型の質問を添えても、AI の返答を隠さず1つにまとめて表示") {
            let client = FakeContextClient.returning(reply: "面接前なんだね。", scene: "interview")
            let vm = remoteVM(client: client)
            vm.tap(.tension(.high))
            await vm.submit("これから面接")
            let turn = vm.currentTurn
            T.expect(turn?.text.hasPrefix("面接前なんだね。") == true, "AI の返答が先頭")
            T.expect(turn?.text.contains("？") == true, "次の質問も同じ吹き出し")
            T.expectEqual(turn?.origin, .openAI(model: "test-model"))
            T.expect(turn?.hasFixedFollowUp == true, "定型文が含まれることを表示")
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
    /// 権限確認の待ち時間（遅延の再現）
    var availabilityDelay: Duration = .zero
    var finalText = "面接の前です"
    var startError: Error? = nil
    var startCount = 0
    var stopCount = 0
    var cancelCount = 0
    var stopBeforeStart = false
    weak var output: FakeSpeechOutput?
    private var onPartial: ((String) -> Void)?
    /// 開始ごとの終了コールバック（古い録音の遅れたコールバックの再現に使う）
    private(set) var finishes: [(MokorinRecognitionOutcome) -> Void] = []

    func requestAvailability() async -> MokorinVoiceAvailability {
        if availabilityDelay != .zero { try? await Task.sleep(for: availabilityDelay) }
        return availability
    }
    func start(onPartial: @escaping (String) -> Void, onFinish: @escaping (MokorinRecognitionOutcome) -> Void) throws {
        startCount += 1
        stopBeforeStart = FakeSpeechOutput.lastStopTime != nil
        if let startError { throw startError }
        self.onPartial = onPartial
        finishes.append(onFinish)
    }
    func partial(_ text: String) { onPartial?(text) }
    /// 録音を終える（finalText を確定として返す）
    func stop() { stopCount += 1; finishes.last?(.transcript(finalText)) }
    func cancel() { cancelCount += 1 }
    /// n 回目（0 始まり）の録音の終了を、あとから届ける
    func finish(_ outcome: MokorinRecognitionOutcome, session index: Int? = nil) {
        let i = index ?? finishes.count - 1
        guard finishes.indices.contains(i) else { return }
        finishes[i](outcome)
    }
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
