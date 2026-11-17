// MokorinAITests.swift
// もこりんの結果の説明・振り返り・個別提案・会話の追加機能（2026-11-05）

import Foundation

enum MokorinAITests {
    typealias T = TestHarness

    static func snap(_ hr: Double?, score: Double = 60, hrv: Double? = nil, mock: Bool = false, at date: Date = Date(),
                     confidence: Double = 0.8) -> GuideSnapshot {
        GuideSnapshot(timestamp: date, score: score, confidence: confidence, state: .optimalTension, heartRate: hr, hrv: hrv,
                      isMockData: mock, heartRateSampleDate: hr == nil ? nil : date, hrvSampleDate: hrv == nil ? nil : date)
    }

    static func record(_ scene: MeasurementScene, daysAgo: Double, before: Double?, after: Double?, mock: Bool = false) -> GuideSessionRecord {
        let date = Date().addingTimeInterval(-daysAgo * 86400)
        return GuideSessionRecord(id: UUID(), startedAt: date, scene: scene, exercise: .breathing478, durationSeconds: 60,
                                  before: snap(before, mock: mock, at: date), after: after.map { snap($0, score: 50, mock: mock, at: date) },
                                  hrvUpdated: false)
    }

    static func input(before: Double? = 84, after: Double? = 77, hrv: Double? = nil, mock: Bool = false,
                      scene: MeasurementScene = .interview, confidence: Double = 0.8) -> MokorinResultInput {
        MokorinResultInput(startedAt: Date(), scene: scene, exerciseTitle: "4-7-8", durationSeconds: 60,
                           before: snap(before, score: 64, hrv: hrv, mock: mock, confidence: confidence),
                           after: after.map { snap($0, score: 52, hrv: hrv.map { $0 + 6 }, mock: mock, confidence: confidence) })
    }

    static let diagnosisWords = ["不安障害", "うつ", "病気です", "と診断", "治療が必要", "異常です"]

    static func allText(_ b: MokorinBrief) -> String {
        (b.facts + b.interpretation + b.missing + b.cautions + b.comparison + b.advice.items.map(\.text)).joined(separator: "\n")
    }

    static func run() async {
        T.suite("もこりん / 結果の説明（端末内・既存の値を読むだけ）")
        explainer()
        T.suite("もこりん / 個別提案")
        advice()
        T.suite("もこりん / 結果・振り返りの会話")
        await companion()
        T.suite("もこりん / 測定前の会話の追加（意図・話題・メモリ）")
        await conversation()
    }

    // MARK: - 説明

    static func explainer() {
        T.test("事実・解釈・不足・注意を分ける。HRV がない記録では HRV を説明に使わず「取れていない」と伝える") {
            let b = MokorinResultExplainer.explain(input(), history: [], memory: nil)
            T.expect(b.facts.contains { $0.contains("84") && $0.contains("77") && $0.contains("-7") }, "心拍の事実")
            T.expect(b.interpretation.contains { $0.contains("下がって") && $0.contains("可能性") }, "解釈は可能性として")
            T.expect(!b.facts.contains { $0.contains("HRV") }, "HRV の値は出さない")
            T.expect(b.missing.contains { $0.contains("HRV") && $0.contains("取れていない") }, "不足を伝える")
            T.expect(b.cautions.contains { $0.contains("医療的な診断ではない") }, "診断ではない")
            for w in diagnosisWords { T.expect(!allText(b).contains(w), "診断の言葉なし: \(w)") }
            T.expect(b.firstMessage.hasPrefix("今回の測定結果を一緒に見てみよう。"), "最初のひとこと")
        }
        T.test("HRV がある記録だけ HRV の値を説明する") {
            let b = MokorinResultExplainer.explain(input(hrv: 40), history: [], memory: nil)
            T.expect(b.facts.contains { $0.contains("HRV（SDNN）は 40 → 46 ms") }, "HRV fact")
            T.expect(!b.missing.contains { $0.contains("HRV") }, "不足に入れない")
        }
        T.test("ガイド後の値がない: 前後の比較をせず、取れなかったことを伝える") {
            let b = MokorinResultExplainer.explain(input(after: nil), history: [], memory: nil)
            T.expect(b.missing.contains { $0.contains("ガイド後の心拍は取れなかった") }, "missing")
            T.expect(b.interpretation.isEmpty, "変化の解釈をしない")
        }
        T.test("過去の記録がない: 「まだ比べられない」。傾向を作らない") {
            let b = MokorinResultExplainer.explain(input(), history: [record(.sports, daysAgo: 2, before: 90, after: 80)], memory: nil)
            T.expect(!b.hasComparableHistory, "別の場面は比べない")
            T.expect(b.comparison.first?.contains("比べられない") == true, b.comparison.first ?? "")
        }
        T.test("同じ場面・デモ以外の記録とだけ比べる。3 回以上は回数を数えるだけ（傾向とは言わない）") {
            let history = [record(.interview, daysAgo: 1, before: 88, after: 80),
                           record(.interview, daysAgo: 0.5, before: 99, after: 70, mock: true),
                           record(.interview, daysAgo: 3, before: 85, after: 86),
                           record(.interview, daysAgo: 5, before: 90, after: 84)]
            let b = MokorinResultExplainer.explain(input(), history: history, memory: nil)
            T.expect(b.hasComparableHistory, "comparable")
            T.expect(b.comparison.first?.contains("88 → 80") == true, "直近の本物の記録（デモは除く）: \(b.comparison.first ?? "")")
            T.expect(b.comparison.contains { $0.contains("3 回のうち") && $0.contains("2 回") && $0.contains("傾向とは言い切れない") }, "数えるだけ")
        }
        T.test("デモデータ: 実際の体の状態ではないと先に伝え、過去とは比べない") {
            let b = MokorinResultExplainer.explain(input(mock: true), history: [record(.interview, daysAgo: 1, before: 88, after: 80)], memory: nil)
            T.expect(b.cautions.first?.contains("デモ用のデータ") == true, "demo first")
            T.expect(!b.hasComparableHistory, "no compare")
        }
        T.test("提案の根拠: 会話がないときは「話していた」と書かず、画面で選んだ場面を根拠にする。デモは最初の吹き出しで伝える") {
            let b = MokorinResultExplainer.explain(input(mock: true), history: [], memory: nil)
            T.expectEqual(b.advice.items.first?.basis, "場面に「面接・プレゼン前」を選んでいたから")
            T.expect(b.firstMessage.contains("デモ用のデータ"), "demo in first message")
            let talked = MokorinResultExplainer.explain(input(), history: [],
                memory: MokorinSessionMemory(tension: .high, scene: .interview, conditions: [.none], situationNote: "ゼミの発表"))
            T.expectEqual(talked.advice.items.first?.id, "presentation_opening")
            T.expectEqual(talked.advice.items.first?.basis, "発表の前と話していたから")
        }
        T.test("信頼度が低いときは参考程度と伝える") {
            let b = MokorinResultExplainer.explain(input(confidence: 0.3), history: [], memory: nil)
            T.expect(b.cautions.contains { $0.contains("信頼度が低め（30%）") }, "low confidence")
        }
        T.test("測定前の会話: 同じ流れ（6 時間以内）のときだけ使い、本人が話したことを事実として添える") {
            var memory = MokorinSessionMemory(tension: .high, scene: .interview, conditions: [.stairs], situationNote: "これから就活の面接")
            let b = MokorinResultExplainer.explain(input(), history: [], memory: memory)
            T.expect(b.facts.contains { $0.contains("「これから就活の面接」と話していた") }, "note")
            T.expect(b.cautions.contains { $0.contains("動いた直後") }, "階段の影響")
            memory.capturedAt = Date().addingTimeInterval(-86400)
            let old = MokorinResultExplainer.explain(input(), history: [], memory: memory)
            T.expect(!old.facts.contains { $0.contains("話していた") }, "前日の会話は使わない")
        }
    }

    // MARK: - 提案

    static func advice() {
        let e = MokorinAdviceEngine.self
        T.test("状況ごとに違う具体的な提案（面接・発表・試験・試合・初対面・作業）。理由を添える") {
            let ids: [(MokorinTopic, String)] = [(.interview, "interview_first_answer"), (.presentation, "presentation_opening"),
                                                (.exam, "exam_first_question"), (.sports, "sports_warmup"),
                                                (.firstMeeting, "first_meeting_greeting"), (.work, "work_first_block")]
            var texts = Set<String>()
            for (topic, id) in ids {
                let items = e.advise(MokorinAdviceInput(topic: topic)).items
                T.expectEqual(items.first?.id, id, "\(topic)")
                T.expect(items.first?.basis.isEmpty == false, "basis")
                texts.insert(items.first?.text ?? "")
            }
            T.expectEqual(texts.count, ids.count, "一般論の繰り返しにしない")
            T.expect(e.advise(MokorinAdviceInput(topic: .presentation)).items.first?.text.contains("冒頭の30秒") == true, "発表")
            T.expect(e.advise(MokorinAdviceInput(topic: .sports)).items.first?.text.contains("ウォーミングアップ") == true, "試合")
        }
        T.test("疲れ・睡眠不足は休憩を先に。動いた直後は測り直しの注意。最大 2 個") {
            let items = e.advise(MokorinAdviceInput(topic: .interview, conditions: [.sleepLack, .running], mentionedFatigue: true)).items
            T.expectEqual(items.first?.id, "rest_break")
            T.expectEqual(items.count, 2)
            let run = e.advise(MokorinAdviceInput(topic: .rest, conditions: [.running])).items
            T.expect(run.contains { $0.id == "settle_before_measure" }, "running")
        }
        T.test("深刻な症状が話されたら提案をやめ、近くの人・医療機関への相談を案内する") {
            let r = e.advise(MokorinAdviceInput(topic: .interview, recentUserText: "さっきから胸が痛い"))
            guard case .seekHelp(let m) = r else { T.expect(false, "seekHelp"); return }
            T.expect(m.contains("医療機関") && m.contains("119"), "相談の案内")
            T.expect(r.items.isEmpty, "提案しない")
        }
        T.test("理由のわからない緊張は受け止める。落ち着いているときは行動を求めない") {
            T.expectEqual(e.advise(MokorinAdviceInput(topic: .unknown, tension: .high)).items.first?.id, "unknown_one_step")
            T.expect(e.advise(MokorinAdviceInput(topic: .unknown, tension: .calm)).items.isEmpty, "緊張していないなら提案なし")
            T.expectEqual(e.advise(MokorinAdviceInput(topic: .rest)).items.first?.id, "rest_keep")
        }
        T.test("話題: 本人の言葉を既存の場面より優先し、訂正では後ろの言葉を採る") {
            T.expectEqual(MokorinTopic.detect(text: "ゼミの発表がある", scene: .interview), .presentation)
            T.expectEqual(MokorinTopic.detect(text: "面接じゃなくて発表だった", scene: nil), .presentation)
            T.expectEqual(MokorinTopic.detect(text: "明日、英語の試験", scene: .work), .exam)
            T.expectEqual(MokorinTopic.detect(text: nil, scene: .sports), .sports)
            T.expectEqual(MokorinTopic.from(guideScene: .speech), .presentation)
        }
    }

    // MARK: - 結果・振り返りの会話

    static func companionVM(consent: Bool = false, client: FakeChatClient = .echo(), history: [GuideSessionRecord] = [],
                            name: String = #function) -> MokorinCompanionViewModel {
        let store = ChatTextConsentStore(defaults: T.freshDefaults("companion-\(name)"))
        store.setConsented(consent)
        let chat = ChatViewModel(consentStore: store, configurationProvider: { ChatTests.config }, clientFactory: { _ in client })
        let i = input()
        return MokorinCompanionViewModel(chat: chat) { recent in
            MokorinResultExplainer.explain(i, history: history, memory: nil, recentUserText: recent)
        }
    }

    static func companion() async {
        await T.test("結果画面から会話を開始: 最初の説明は端末内と表示。選択肢は最大 3 つ") {
            let vm = companionVM()
            T.expectEqual(vm.chat.messages.count, 1)
            T.expect(vm.chat.messages.first?.text.contains("84") == true, "事実を含む")
            if case .local = vm.chat.messages.first?.origin {} else { T.expect(false, "端末内") }
            T.expectEqual(vm.quickReplies, [.meaning, .compare, .advice])
        }
        await T.test("提案のあとに 1 回だけ「試してみた？」。答えたら選択肢を消し、二度と聞かない") {
            let vm = companionVM()
            vm.tap(.advice)
            T.expectEqual(vm.quickReplies, [.tried, .later])
            T.expect(vm.chat.messages.last?.text == "声に出してみた？", "面接の確認")
            vm.tap(.tried)
            T.expect(!vm.quickReplies.contains(.tried), "確認は1回だけ")
            T.expectEqual(vm.quickReplies, [.meaning, .compare])
        }
        await T.test("自由な質問を外部AIへ送るとき、端末内の説明（測定値）は送らない") {
            let client = FakeChatClient.echo()
            let vm = companionVM(consent: true, client: client)
            vm.tap(.meaning)
            vm.chat.draft = "緊張しやすいのはなぜ？"
            vm.send()
            for _ in 0..<50 where vm.chat.isSending { try? await Task.sleep(for: .milliseconds(20)) }
            let sent = client.requests.last?.messages ?? []
            T.expectEqual(sent.map(\.content), ["緊張しやすいのはなぜ？"], "利用者の発言だけ")
            T.expect(!sent.contains { $0.content.contains("bpm") }, "測定値を含まない")
            T.expect(client.requests.last?.context.measurement == nil, "計測要約も送らない（方針どおり）")
        }
        await T.test("深刻な症状の言葉: 外部AIへ送らず、すぐ相談を案内する") {
            let client = FakeChatClient.echo()
            let vm = companionVM(consent: true, client: client)
            vm.chat.draft = "息苦しいんだけど"
            vm.send()
            T.expect(client.requests.isEmpty, "送らない")
            T.expect(vm.chat.messages.last?.text.contains("医療機関") == true, "相談の案内")
        }
        await T.test("AI未接続: 端末内の説明から答えられる質問（比較・意味）には答える。過去の記録がなければ比べられないと伝える") {
            let vm = companionVM(consent: false)
            vm.chat.draft = "前回と比べてどう？"
            vm.send()
            T.expect(vm.chat.messages.last?.text.contains("比べられない") == true, vm.chat.messages.last?.text ?? "")
        }
        await T.test("会話のリセット: 最初の説明だけに戻り、確認の状態も消える") {
            let vm = companionVM()
            vm.tap(.advice); vm.tap(.meaning)
            vm.restart()
            T.expectEqual(vm.chat.messages.count, 1)
            T.expectEqual(vm.quickReplies, [.meaning, .compare, .advice])
        }
    }

    // MARK: - 測定前の会話の追加

    static func conversation() async {
        await T.test("測定を望まない: 説得せず受け止め、「測定しないで終える」「やっぱり続ける」を出す") {
            let vm = MokorinTests.localVM()
            await vm.submit("少し緊張してる")
            await vm.submit("今日は測りたくない")
            T.expect(vm.declinedMeasurement, "declined")
            T.expectEqual(vm.messages.last?.text, MokorinScript.declineAck)
            T.expectEqual(vm.quickReplies, [.skipMeasurement, .keepTalking])
            vm.tap(.keepTalking)
            T.expect(!vm.declinedMeasurement, "resume")
            T.expectEqual(vm.step, .scene, "同じ段階から続ける")
        }
        await T.test("「もう測りたい」: 未確認の項目は聞かずにまとめへ（まとめで確認・変更できる）。やり直しで会話の記憶も消える") {
            let vm = MokorinTests.localVM()
            await vm.submit("少し緊張してる")
            await vm.submit("もう測りたい")
            T.expectEqual(vm.step, .review)
            T.expect(vm.messages.last?.text.contains("測定") == true, "summary")
            await vm.submit("今日は測りたくない")
            vm.restart()
            T.expect(vm.situationNote == nil && !vm.declinedMeasurement && !vm.mentionedFatigue, "reset")
        }
        await T.test("外部AI: situation_note・user_intent を使う。測定を望まないときは定型の質問を足さない。不正な意図は answer") {
            let client = FakeContextClient { req in
                ContextAssistResponseDTO(schemaVersion: 1, requestId: req.requestId, conversationId: req.conversationId, provider: "openai",
                                         model: "test-model", generatedAt: Date(),
                                         result: ContextAssistResultDTO(reply: "わかった、無理しなくて大丈夫だよ。", sceneCandidate: nil,
                                                                        conditionCandidates: [], needsClarification: false, clarificationQuestion: nil,
                                                                        situationNote: "初対面の人と会う", userIntent: "decline_measurement"),
                                         usage: nil)
            }
            let vm = MokorinTests.remoteVM(client: client)
            vm.tap(.tension(.slight))
            await vm.submit("初対面の人と会うけど、今日は測りたくない")
            T.expect(vm.declinedMeasurement, "declined")
            T.expectEqual(vm.situationNote, "初対面の人と会う")
            T.expectEqual(vm.messages.last?.text, "わかった、無理しなくて大丈夫だよ。", "定型の質問を足さない")
            let json = #"{"reply":"x","scene_candidate":null,"condition_candidates":[],"needs_clarification":false,"clarification_question":null,"user_intent":"dance"}"#
            let dto = try JSONDecoder().decode(ContextAssistResultDTO.self, from: Data(json.utf8))
            T.expectEqual(dto.typedIntent, .answer, "未知の値で止まらない")
            T.expect(dto.situationNote == nil, "欠落は nil")
        }
        await T.test("外部AI: 質問（user_intent=question）に答えたあとは同じ質問に戻り、その項目を飛ばさない") {
            let client = FakeContextClient { req in
                ContextAssistResponseDTO(schemaVersion: 1, requestId: req.requestId, conversationId: req.conversationId, provider: "openai",
                                         model: "test-model", generatedAt: Date(),
                                         result: ContextAssistResultDTO(reply: "呼吸法やストレッチがあるよ。", sceneCandidate: nil,
                                                                        conditionCandidates: [], needsClarification: false, clarificationQuestion: nil,
                                                                        situationNote: nil, userIntent: "question"),
                                         usage: nil)
            }
            let vm = MokorinTests.remoteVM(client: client)
            let asked = vm.askedSlot
            await vm.submit("どんな方法がある？")
            T.expectEqual(vm.askedSlot, asked, "同じ質問に戻る")
            T.expect(asked.map { !vm.checkIn.declined.contains($0) } == true, "答えていない項目をスキップ扱いにしない")
            T.expect(vm.messages.last?.text == asked?.question, "定型の質問を添える: \(vm.messages.last?.text ?? "")")
        }
    }
}
