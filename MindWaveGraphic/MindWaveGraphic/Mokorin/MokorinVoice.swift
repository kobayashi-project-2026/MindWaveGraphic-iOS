// MokorinVoice.swift
// Mokorin
//
// もこりんとの音声対話（1ターンずつ）。
//   マイクボタン → 音声を文字に変換（Speech、日本語。端末内で認識できる場合は端末内のみ）→ 話し終えたら送信
//   → もこりんの返答 → 読み上げ（AVSpeechSynthesizer）。次の発話は利用者がもう一度マイクボタンを押したときだけ始まる
//
// 守ること:
// - 利用者がマイクボタンを押すまで録音しない。自動で次の録音を始めない（リアルタイム双方向音声ではない）
// - 読み上げ中は録音しない（もこりん自身の声を認識しないため）。マイクを押したら読み上げを止めてから録音する
// - マイク・音声認識が使えない・許可されない・失敗したときは理由を表示し、文字入力・選択肢で続けられる
// - 音声データや認識結果をログに出さない（状態と文字数だけ）

import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - 抽象化（テストでは差し替える）

/// 音声入力の権限・利用可否
nonisolated enum MokorinVoiceAvailability: Equatable, Sendable {
    case available
    /// 使えない理由（マイク・音声認識の権限なし、認識サービスが使えない）
    case unavailable(MokorinVoiceFailure)
}

/// 音声 → 文字
nonisolated protocol MokorinSpeechInput: AnyObject {
    /// 音声認識・マイクの権限を確認し、必要なら許可を求める（初回だけ OS の確認が表示される）。
    /// 許可の確認が終わるまで録音は始めない
    func requestAvailability() async -> MokorinVoiceAvailability
    /// 録音と認識を始める。途中経過は onPartial、終わったら onFinish を 1 回だけ呼ぶ（メインスレッド）。
    /// 録音を始められなければ throw（onFinish は呼ばない）
    func start(onPartial: @escaping (String) -> Void,
               onFinish: @escaping (MokorinRecognitionOutcome) -> Void) throws
    /// 録音を終えて、聞き取った文字を確定する（話していなければ取り消し扱い）
    func stop()
    /// 録音を取り消す（onFinish に .cancelled を返すか、何も返さない）
    func cancel()
}

/// 文字 → 音声
nonisolated protocol MokorinSpeechOutput: AnyObject {
    var onFinish: (() -> Void)? { get set }
    var isSpeaking: Bool { get }
    func speak(_ text: String)
    func stop()
}

// MARK: - 状態管理

@MainActor
final class MokorinVoiceController: ObservableObject {

    enum State: Equatable {
        case idle
        /// 権限の確認・録音の準備中（マイクのボタンは押せない）
        case preparing
        /// 録音中（途中の認識結果）
        case listening(String)
        /// 認識した文字をもこりんへ送っている
        case processing
        /// 読み上げ中
        case speaking
    }

    @Published private(set) var state: State = .idle
    /// 最後に起きた問題（原因ごとの文言）。nil = 問題なし。文字入力はいつでも使える
    @Published private(set) var problem: String? = nil
    @Published private(set) var lastFailure: MokorinVoiceFailure? = nil
    /// 返答を読み上げるか（初めてマイクを使ったときに ON になる。画面のボタンで切り替えられる）
    @Published var speaksReplies = false

    private let input: MokorinSpeechInput
    private let output: MokorinSpeechOutput
    /// 今の録音を表す番号。古い録音の結果（遅れて届いたコールバック）を捨てるために使う
    private var listenToken = UUID()
    /// 認識した文字を会話へ送る（MokorinContextViewModel.submit）
    var onUtterance: ((String) async -> Void)?
    /// 読み上げ中の口の動きなど
    var onSpeakingChanged: ((Bool) -> Void)?

    init(input: MokorinSpeechInput = SpeechRecognizerInput(), output: MokorinSpeechOutput = SpeechSynthesizerOutput()) {
        self.input = input
        self.output = output
        output.onFinish = { [weak self] in
            Task { @MainActor in self?.finishSpeaking() }
        }
    }

    /// アプリで使う音声コントローラー。DEBUG ビルドで MW_MOKORIN_FAKE_VOICE があれば、マイクを使わない模擬入力にする
    static func makeForApp() -> MokorinVoiceController {
        #if DEBUG
        if let scripted = MokorinScriptedSpeechInput.fromEnvironment() { return MokorinVoiceController(input: scripted) }
        #endif
        return MokorinVoiceController()
    }

    var isListening: Bool { if case .listening = state { return true } else { return false } }
    var partialTranscript: String { if case .listening(let t) = state { return t } else { return "" } }

    /// マイクボタン。状態に応じて 開始 / 終了して送信 / 読み上げ停止→開始
    func micTapped() async {
        switch state {
        case .listening:
            input.stop()          // 結果は onFinish で届く
        case .processing, .preparing:
            return                // 多重に開始しない
        case .speaking:
            output.stop()
            finishSpeaking()
            await startListening()
        case .idle:
            await startListening()
        }
    }

    /// 録音中の取り消し（画面を閉じる・アプリが背面に回るとき）。エラーは表示しない
    func cancelAll() {
        listenToken = UUID()      // 以降に届く今の録音の結果は捨てる
        if isListening || state == .preparing { input.cancel() }
        if output.isSpeaking { output.stop() }
        setSpeaking(false)
        state = .idle
    }

    /// もこりんの返答を読み上げる（ON のときだけ。録音中・処理中は読まない）
    func speakReply(_ text: String) {
        guard speaksReplies, state == .idle || state == .processing, !text.isEmpty else { return }
        state = .speaking
        setSpeaking(true)
        output.speak(text)
    }

    func stopSpeaking() {
        guard state == .speaking else { return }
        output.stop()
        finishSpeaking()
    }

    // MARK: - 内部

    private func startListening() async {
        problem = nil
        lastFailure = nil
        let token = UUID()
        listenToken = token
        state = .preparing
        let availability = await input.requestAvailability()
        // 許可の確認中に取り消された（画面を閉じた等）
        guard listenToken == token, state == .preparing else { return }
        if case .unavailable(let failure) = availability {
            fail(failure)
            return
        }
        // 初めて声で話したら、返答も読み上げる
        speaksReplies = true
        do {
            try input.start(
                onPartial: { [weak self] text in
                    Task { @MainActor in
                        guard let self, self.listenToken == token, self.isListening else { return }
                        self.state = .listening(text)
                    }
                },
                onFinish: { [weak self] outcome in
                    Task { @MainActor in await self?.handle(outcome, token: token) }
                })
            // start が成功した（録音が始まった）ときだけ「聞いています」にする
            if listenToken == token, state == .preparing { state = .listening("") }
        } catch {
            fail(.engineStartFailed)
        }
    }

    private func handle(_ outcome: MokorinRecognitionOutcome, token: UUID) async {
        // 古い録音の結果は捨てる（新しい録音・取り消しのあとに遅れて届いたもの）
        guard listenToken == token, isListening || state == .preparing else { return }
        switch outcome {
        case .transcript(let text):
            await deliver(text)
        case .failure(let failure):
            fail(failure)
        case .cancelled:
            state = .idle
        }
    }

    private func fail(_ failure: MokorinVoiceFailure) {
        lastFailure = failure
        problem = failure.message
        state = .idle
        MindWaveDebugLogger.log(.insight, "mokorin voice failure=\(failure.rawValue)")
    }

    private func deliver(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail(.noSpeech)
            return
        }
        state = .processing
        MindWaveDebugLogger.log(.insight, "mokorin voice utterance chars=\(trimmed.count)")
        await onUtterance?(trimmed)
        if state == .processing { state = .idle }
    }

    private func finishSpeaking() {
        setSpeaking(false)
        if state == .speaking { state = .idle }
    }

    private func setSpeaking(_ speaking: Bool) {
        onSpeakingChanged?(speaking)
    }
}

// MARK: - 実装: 音声認識（Speech）

/// 録音を始められなかった段階（診断用）
nonisolated enum MokorinVoiceStartError: Error, Equatable {
    case recognizerMissing
    case audioSession(code: Int)
    case noInput
    case invalidFormat
    case engineStart(code: Int)
}

/// 最初の音声バッファを 1 回だけ知らせる（音声スレッドから呼ばれる）
nonisolated final class MokorinFirstBufferFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    /// 初回だけ true
    func fire() -> Bool { lock.lock(); defer { lock.unlock() }; if fired { return false }; fired = true; return true }
}

/// SFSpeechRecognizer（日本語）＋ AVAudioEngine。判断（無発話 8 秒・話し終え 1.8 秒・最長 30 秒・エラーの分類）は
/// MokorinRecognitionSession が行う。音声・認識のコールバックは別スレッドで届くため nonisolated とし、
/// 状態の更新はすべてメインスレッドで行う。各コールバックはセッション ID を持ち、今のセッション以外のものは捨てる
nonisolated final class SpeechRecognizerInput: NSObject, MokorinSpeechInput, @unchecked Sendable {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var session: MokorinRecognitionSession?
    private var onPartial: ((String) -> Void)?
    private var onFinish: ((MokorinRecognitionOutcome) -> Void)?
    private var tapInstalled = false

    /// 話し終えたと判断する無音の長さ（MokorinRecognitionSession.Timing と同じ値）
    static let silenceSeconds: TimeInterval = MokorinRecognitionSession.Timing().silence
    static let noSpeechSeconds: TimeInterval = MokorinRecognitionSession.Timing().noSpeech
    static let maxSeconds: TimeInterval = MokorinRecognitionSession.Timing().maximum

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func requestAvailability() async -> MokorinVoiceAvailability {
        // 1) 音声認識の許可（確認が終わるまで録音しない）
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        // 2) マイクの許可
        let mic = await AVAudioApplication.requestRecordPermission()
        // 3) 認識サービスの利用可否（許可のあとに確認する）
        let available = recognizer?.isAvailable ?? false
        MindWaveDebugLogger.log(.insight, "mokorin voice availability speechAuth=\(speech.rawValue) mic=\(mic) recognizer=\(recognizer != nil) available=\(available) onDevice=\(recognizer?.supportsOnDeviceRecognition ?? false)")
        guard speech == .authorized else { return .unavailable(.speechDenied) }
        guard mic else { return .unavailable(.microphoneDenied) }
        guard available else { return .unavailable(.recognizerUnavailable) }
        return .available
    }

    func start(onPartial: @escaping (String) -> Void, onFinish: @escaping (MokorinRecognitionOutcome) -> Void) throws {
        cancel()   // 前の録音を片付ける（前のセッションの結果は ID が違うので捨てられる）
        guard let recognizer else { throw MokorinVoiceStartError.recognizerMissing }
        var newSession = MokorinRecognitionSession(now: Self.now())
        let id = newSession.id
        let tag = String(id.uuidString.prefix(8))
        self.onPartial = onPartial
        self.onFinish = onFinish

        // オーディオセッション
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            log(tag, "stage=audio_session failed code=\((error as NSError).code)")
            teardown(deactivate: true)
            throw MokorinVoiceStartError.audioSession(code: (error as NSError).code)
        }
        guard audio.isInputAvailable else {
            log(tag, "stage=input failed no_input")
            teardown(deactivate: true)
            throw MokorinVoiceStartError.noInput
        }

        // 入力の形式（サンプルレート 0 などでは録音できない）
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            log(tag, "stage=format failed rate=\(format.sampleRate) ch=\(format.channelCount)")
            teardown(deactivate: true)
            throw MokorinVoiceStartError.invalidFormat
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 端末内で認識できる場合は、音声を外部（Apple のサーバー）へ送らない
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let first = MokorinFirstBufferFlag()
        if tapInstalled { inputNode.removeTap(onBus: 0) }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            if first.fire() {
                DispatchQueue.main.async { self?.event(id) { s in s.audioReceived(); return nil } }
            }
        }
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            log(tag, "stage=engine_start failed code=\((error as NSError).code)")
            teardown(deactivate: true)
            throw MokorinVoiceStartError.engineStart(code: (error as NSError).code)
        }
        newSession.engineStarted(at: Self.now())
        session = newSession
        log(tag, "stage=listening rate=\(Int(format.sampleRate)) onDevice=\(request.requiresOnDeviceRecognition)")

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error as NSError?
            DispatchQueue.main.async {
                guard let self else { return }
                if let text {
                    self.event(id) { s in s.result(text, isFinal: isFinal, at: Self.now()) }
                    if self.session?.id == id { self.onPartial?(text) }
                }
                if let nsError {
                    self.event(id) { s in s.error(domain: nsError.domain, code: nsError.code) }
                }
            }
        }
        scheduleTimer()
    }

    func stop() {
        DispatchQueue.main.async {
            guard let id = self.session?.id else { return }
            self.event(id) { s in s.stopRequested() }
        }
    }

    func cancel() {
        if let id = session?.id {
            event(id) { s in s.cancelRequested() }
        } else {
            teardown(deactivate: false)
        }
    }

    // MARK: - 内部（メインスレッド）

    /// 今のセッションへの出来事。終わったら片付けて onFinish を 1 回だけ呼ぶ
    private func event(_ id: UUID, _ change: (inout MokorinRecognitionSession) -> MokorinRecognitionOutcome?) {
        guard var current = session, current.id == id else { return }   // 古いセッションのコールバックは捨てる
        let outcome = change(&current)
        session = current
        if let outcome {
            finish(current, outcome)
        } else {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate(); timer = nil
        guard let current = session, let deadline = current.nextDeadline else { return }
        let id = current.id
        timer = Timer.scheduledTimer(withTimeInterval: max(0.05, deadline - Self.now()), repeats: false) { [weak self] _ in
            self?.event(id) { s in s.tick(at: Self.now()) }
        }
    }

    private func finish(_ ended: MokorinRecognitionSession, _ outcome: MokorinRecognitionOutcome) {
        let tag = String(ended.id.uuidString.prefix(8))
        let elapsed = Int((Self.now() - ended.createdAt) * 1000)
        let err = ended.lastError.map { "\($0.domain)/\($0.code)" } ?? "-"
        log(tag, "end reason=\(ended.endReason ?? "-") audio=\(ended.receivedAudio) results=\(ended.resultCount) speech=\(ended.hasSpeech) error=\(err) elapsedMs=\(elapsed)")
        session = nil
        switch outcome {
        case .transcript: request?.endAudio(); task?.finish()
        case .failure, .cancelled: request?.endAudio(); task?.cancel()
        }
        let callback = onFinish
        onFinish = nil
        onPartial = nil
        teardown(deactivate: true)
        callback?(outcome)
    }

    private func teardown(deactivate: Bool) {
        timer?.invalidate(); timer = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request = nil
        task = nil
        if deactivate { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    /// 診断ログ（DEBUG のみ）。音声・認識した文字・トークンは記録しない
    private func log(_ tag: String, _ message: String) {
        MindWaveDebugLogger.log(.insight, "mokorin voice session=\(tag) \(message)")
    }
}

// MARK: - 実装: 読み上げ（AVSpeechSynthesizer）

/// デリゲートは別スレッドで呼ばれることがあるため nonisolated（受け取り側でメインスレッドへ移す）
nonisolated final class SpeechSynthesizerOutput: NSObject, MokorinSpeechOutput, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }   // 二重再生しない
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish?()
    }
}
