// MokorinVoiceTests.swift
// 音声認識の判断（MokorinRecognitionSession、仮想の時計）と、音声コントローラーの状態管理（模擬入力）。
// 2026-11-05: 実機で「マイクを押した直後に『うまく聞き取れなかった』」の回帰を防ぐ。実機・実音声は使わない

import Foundation

enum MokorinVoiceTests {
    typealias T = TestHarness
    typealias S = MokorinRecognitionSession

    /// 仮想の時刻 0 で録音を開始したセッション
    static func listening() -> S {
        var s = S(now: 0)
        s.engineStarted(at: 0)
        return s
    }

    static func run() async {
        T.suite("音声 / 認識 1 回分の判断（仮想の時計）")
        session()
        T.suite("音声 / コントローラーの状態管理（模擬入力）")
        await controller()
    }

    // MARK: - 判断

    static func session() {
        T.test("回帰: マイクを押した直後（録音開始の直後）には終わらない。無発話は 8 秒たってから「声が聞こえなかった」") {
            var s = listening()
            T.expectEqual(s.tick(at: 0.01), nil)
            T.expectEqual(s.tick(at: 1.9), nil, "1.8 秒では終わらない（まだ話していない）")
            T.expectEqual(s.tick(at: 7.9), nil)
            T.expectEqual(s.nextDeadline, 8)
            T.expectEqual(s.tick(at: 8.0), .failure(.noSpeech))
            T.expectEqual(s.endReason, "no_speech_timeout")
        }
        T.test("回帰: 空の途中結果では「話し始めた」とみなさず、1.8 秒で終わらない") {
            var s = listening()
            T.expectEqual(s.result("", isFinal: false, at: 0.2), nil)
            T.expectEqual(s.result("  ", isFinal: false, at: 0.4), nil)
            T.expect(!s.hasSpeech, "まだ話していない")
            T.expectEqual(s.nextDeadline, 8)
            T.expectEqual(s.tick(at: 2.5), nil)
        }
        T.test("録音が始まるまでは時間を数えない（権限確認・準備が遅くても無発話にしない）") {
            var s = S(now: 0)
            T.expectEqual(s.nextDeadline, nil)
            T.expectEqual(s.tick(at: 100), nil)
            s.engineStarted(at: 100)
            T.expectEqual(s.nextDeadline, 108)
        }
        T.test("話し終えて 1.8 秒で確定。発話中の短い沈黙（1.8 秒未満）では確定しない") {
            var s = listening()
            _ = s.result("かなり", isFinal: false, at: 1.0)
            T.expectEqual(s.tick(at: 2.0), nil)
            _ = s.result("かなり緊張", isFinal: false, at: 2.5)    // 1.5 秒の沈黙のあと続けた
            T.expectEqual(s.tick(at: 4.0), nil)
            _ = s.result("かなり緊張してる", isFinal: false, at: 4.1)
            T.expectEqual(s.nextDeadline ?? -1, 4.1 + 1.8, accuracy: 0.0001)
            T.expectEqual(s.tick(at: 5.95), .transcript("かなり緊張してる"))
        }
        T.test("同じ文字の途中結果が続いても、話し終えの時刻は延ばさない") {
            var s = listening()
            _ = s.result("面接", isFinal: false, at: 1.0)
            _ = s.result("面接", isFinal: false, at: 2.0)
            T.expectEqual(s.tick(at: 2.85), .transcript("面接"))
        }
        T.test("確定結果がすぐ返る・遅れて返る。確定のあとに届いた結果・エラーは無視") {
            var s = listening()
            T.expectEqual(s.result("これから面接", isFinal: true, at: 0.5), .transcript("これから面接"))
            T.expectEqual(s.result("別の文", isFinal: true, at: 0.6), nil)
            T.expectEqual(s.error(domain: "kAFAssistantErrorDomain", code: 216), nil)
            var late = listening()
            _ = late.result("階段", isFinal: false, at: 1.0)
            T.expectEqual(late.result("階段を上ってきた", isFinal: true, at: 2.5), .transcript("階段を上ってきた"))
        }
        T.test("確定結果が空なら無発話") {
            var s = listening()
            T.expectEqual(s.result("", isFinal: true, at: 1), .failure(.noSpeech))
        }
        T.test("エラーの種類で分ける: 取り消しは表示しない・無発話・利用不可・その他。話したあとのエラーは聞き取った文字を送る") {
            func run(_ domain: String, _ code: Int) -> MokorinRecognitionOutcome? { var s = listening(); return s.error(domain: domain, code: code) }
            T.expectEqual(run("kAFAssistantErrorDomain", 216), .cancelled)
            T.expectEqual(run("kLSRErrorDomain", 301), .cancelled)
            T.expectEqual(run("kAFAssistantErrorDomain", 1110), .failure(.noSpeech))
            T.expectEqual(run("kLSRErrorDomain", 201), .failure(.recognizerUnavailable))
            T.expectEqual(run("kAFAssistantErrorDomain", 1700), .failure(.recognizerUnavailable))
            T.expectEqual(run("kAFAssistantErrorDomain", 1101), .failure(.recognitionFailed))
            T.expectEqual(run("SomeNewDomain", 42), .failure(.recognitionFailed), "未知のコードでも止まらない")
            var spoke = listening()
            _ = spoke.result("面接", isFinal: false, at: 1)
            T.expectEqual(spoke.error(domain: "kAFAssistantErrorDomain", code: 1101), .transcript("面接"))
        }
        T.test("利用者が終えた: 話していれば送る、話していなければエラーにしない。取り消しも表示しない") {
            var a = listening(); _ = a.result("試合", isFinal: false, at: 1)
            T.expectEqual(a.stopRequested(), .transcript("試合"))
            var b = listening()
            T.expectEqual(b.stopRequested(), .cancelled)
            var c = listening()
            T.expectEqual(c.cancelRequested(), .cancelled)
            T.expectEqual(c.stopRequested(), nil, "終わったあとは何もしない")
        }
        T.test("録音を始められなかった・最長 30 秒") {
            var s = S(now: 0)
            T.expectEqual(s.engineFailed(), .failure(.engineStartFailed))
            var m = listening()
            var t = 0.0
            while t < 29 { t += 1.0; _ = m.result("話し続けている\(Int(t))", isFinal: false, at: t) }
            T.expectEqual(m.tick(at: 30.0), .transcript("話し続けている29"))
        }
        T.test("画面の文言は原因と 1 対 1（同じ文言を使い回さない）") {
            let all: [MokorinVoiceFailure] = [.microphoneDenied, .speechDenied, .recognizerUnavailable, .noSpeech, .engineStartFailed, .recognitionFailed]
            T.expectEqual(Set(all.map(\.message)).count, all.count)
            T.expect(MokorinVoiceFailure.microphoneDenied.message.hasPrefix("マイクの使用が許可されていないよ。"), "mic")
            T.expect(MokorinVoiceFailure.speechDenied.message.hasPrefix("音声認識の使用が許可されていないよ。"), "speech")
            T.expectEqual(MokorinVoiceFailure.recognizerUnavailable.message, "今は音声認識を使えないみたい。文字で教えてね。")
            T.expectEqual(MokorinVoiceFailure.noSpeech.message, "声が聞こえなかったよ。もう一度試してみてね。")
            T.expectEqual(MokorinVoiceFailure.engineStartFailed.message, "マイクを開始できなかったよ。もう一度試してね。")
        }
    }

    // MARK: - コントローラー

    static func wait() async { try? await Task.sleep(for: .milliseconds(40)) }

    static func controller() async {
        await T.test("権限の確認が終わるまで録音を始めない（確認の遅延）。その間のマイクの連打は無視") {
            let input = FakeSpeechInput(); input.availabilityDelay = .milliseconds(150)
            let vc = MokorinVoiceController(input: input, output: FakeSpeechOutput())
            let first = Task { await vc.micTapped() }
            try? await Task.sleep(for: .milliseconds(30))
            T.expectEqual(vc.state, .preparing)
            T.expectEqual(input.startCount, 0, "確認中は開始しない")
            await vc.micTapped(); await vc.micTapped()          // 連打
            await first.value
            T.expectEqual(input.startCount, 1, "多重に開始しない")
            T.expect(vc.isListening, "確認後に録音")
        }
        await T.test("権限がない: 原因ごとの文言を表示し、録音しない（音声認識・マイク・サービス）") {
            let cases: [(MokorinVoiceFailure, String)] = [(.speechDenied, "音声認識の使用"), (.microphoneDenied, "マイクの使用"), (.recognizerUnavailable, "今は音声認識を使えない")]
            for (failure, text) in cases {
                let input = FakeSpeechInput(); input.availability = .unavailable(failure)
                let vc = MokorinVoiceController(input: input, output: FakeSpeechOutput())
                await vc.micTapped()
                T.expectEqual(input.startCount, 0)
                T.expectEqual(vc.lastFailure, failure)
                T.expect(vc.problem?.contains(text) == true, vc.problem ?? "")
            }
        }
        await T.test("録音を開始できない（AudioEngine の失敗）: 「マイクを開始できなかった」。再試行できる") {
            let input = FakeSpeechInput(); input.startError = MokorinVoiceStartError.engineStart(code: -10868)
            let vc = MokorinVoiceController(input: input, output: FakeSpeechOutput())
            await vc.micTapped()
            T.expectEqual(vc.lastFailure, .engineStartFailed)
            T.expectEqual(vc.state, .idle)
            input.startError = nil
            await vc.micTapped()
            T.expect(vc.isListening, "再試行で録音")
            T.expect(vc.problem == nil, "前の問題は消える")
        }
        await T.test("回帰: 前の録音の遅れたコールバック（取り消しのエラーなど）が、新しい録音を止めない") {
            let input = FakeSpeechInput()
            let vc = MokorinVoiceController(input: input, output: FakeSpeechOutput())
            await vc.micTapped()                       // 1 回目
            vc.cancelAll()
            await vc.micTapped()                       // 2 回目
            T.expect(vc.isListening, "listening")
            input.finish(.failure(.recognitionFailed), session: 0)   // 1 回目のエラーが遅れて届く
            input.finish(.transcript("古い文"), session: 0)
            await wait()
            T.expect(vc.isListening, "新しい録音は続く")
            T.expect(vc.problem == nil, "古いエラーを表示しない")
        }
        await T.test("文字起こしが確定したら会話へ送る（日本語のまま）。送信中のマイクは無視") {
            let input = FakeSpeechInput()
            let vc = MokorinVoiceController(input: input, output: FakeSpeechOutput())
            var received: [String] = []
            vc.onUtterance = { text in received.append(text); try? await Task.sleep(for: .milliseconds(80)) }
            await vc.micTapped()
            input.partial("かなり緊張")
            await wait()
            T.expectEqual(vc.partialTranscript, "かなり緊張")
            input.finish(.transcript("かなり緊張してる"))
            await wait()
            T.expectEqual(vc.state, .processing)
            await vc.micTapped()                       // 送信中は無視
            T.expectEqual(input.startCount, 1)
            try? await Task.sleep(for: .milliseconds(100))
            T.expectEqual(received, ["かなり緊張してる"])
            T.expectEqual(vc.state, .idle)
        }
        await T.test("無発話・空の結果・認識エラーは原因どおりに表示し、取り消し・話さずに終えたときは表示しない") {
            let input = FakeSpeechInput()
            let vc = MokorinVoiceController(input: input, output: FakeSpeechOutput())
            await vc.micTapped(); input.finish(.failure(.noSpeech)); await wait()
            T.expectEqual(vc.problem, MokorinVoiceFailure.noSpeech.message)
            await vc.micTapped(); input.finish(.transcript("   ")); await wait()
            T.expectEqual(vc.lastFailure, .noSpeech, "空の文字は送らない")
            await vc.micTapped(); input.finish(.failure(.recognitionFailed)); await wait()
            T.expectEqual(vc.lastFailure, .recognitionFailed)
            await vc.micTapped(); input.finish(.cancelled); await wait()
            T.expect(vc.problem == nil && vc.state == .idle, "取り消しは表示しない")
        }
        await T.test("録音中に背面へ（cancelAll）: 録音を取り消し、エラーを出さない。あとから届いた結果は捨てる") {
            let input = FakeSpeechInput()
            let vc = MokorinVoiceController(input: input, output: FakeSpeechOutput())
            var received = 0
            vc.onUtterance = { _ in received += 1 }
            await vc.micTapped()
            vc.cancelAll()
            T.expectEqual(input.cancelCount, 1)
            input.finish(.transcript("届いてしまった文"))
            await wait()
            T.expectEqual(received, 0)
            T.expect(vc.problem == nil && vc.state == .idle, "idle")
        }
        await T.test("権限の確認中に画面を閉じた: 確認が終わっても録音を始めない") {
            let input = FakeSpeechInput(); input.availabilityDelay = .milliseconds(100)
            let vc = MokorinVoiceController(input: input, output: FakeSpeechOutput())
            let t = Task { await vc.micTapped() }
            try? await Task.sleep(for: .milliseconds(20))
            vc.cancelAll()
            await t.value
            T.expectEqual(input.startCount, 0)
            T.expectEqual(vc.state, .idle)
        }
        await T.test("読み上げ中の録音要求: 読み上げを止めてから録音。録音中は読み上げない") {
            let input = FakeSpeechInput(), output = FakeSpeechOutput()
            let vc = MokorinVoiceController(input: input, output: output)
            vc.speaksReplies = true
            vc.speakReply("面接前なんだね。")
            await vc.micTapped()
            T.expectEqual(output.stopCount, 1)
            T.expect(vc.isListening, "listening")
            vc.speakReply("録音中")
            T.expectEqual(output.spoken.count, 1)
        }
    }
}

extension TestHarness {
    /// 小数の比較（仮想の時計の時刻）
    static func expectEqual(_ a: Double, _ b: Double, accuracy: Double, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
        expect(abs(a - b) <= accuracy, "expected \(b) but got \(a) \(message)", file: file, line: line)
    }
}
