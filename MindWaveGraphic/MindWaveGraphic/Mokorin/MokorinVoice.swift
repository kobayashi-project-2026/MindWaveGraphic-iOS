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
    case denied(String)
    case unavailable(String)
}

/// 音声 → 文字
nonisolated protocol MokorinSpeechInput: AnyObject {
    /// マイク・音声認識の権限を確認し、必要なら許可を求める（初回だけ OS の確認が表示される）
    func requestAvailability() async -> MokorinVoiceAvailability
    /// 録音と認識を始める。途中経過・確定した文字・エラーを返す
    func start(onPartial: @escaping (String) -> Void,
               onFinal: @escaping (String) -> Void,
               onError: @escaping (String) -> Void) throws
    /// 録音を終えて、確定した文字を onFinal で返す
    func stop()
    /// 録音を取り消す（onFinal を呼ばない）
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
        case preparing
        /// 録音中（途中の認識結果）
        case listening(String)
        /// 認識した文字をもこりんへ送っている
        case processing
        /// 読み上げ中
        case speaking
    }

    @Published private(set) var state: State = .idle
    /// 最後に表示する問題（権限がない・認識できなかった等）。文字入力で続けられることを添えて表示する
    @Published private(set) var problem: String? = nil
    /// 返答を読み上げるか（初めてマイクを使ったときに ON になる。画面のボタンで切り替えられる）
    @Published var speaksReplies = false

    private let input: MokorinSpeechInput
    private let output: MokorinSpeechOutput
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

    var isListening: Bool { if case .listening = state { return true } else { return false } }
    var partialTranscript: String { if case .listening(let t) = state { return t } else { return "" } }

    /// マイクボタン。状態に応じて 開始 / 終了して送信 / 読み上げ停止→開始
    func micTapped() async {
        switch state {
        case .listening:
            input.stop()          // 確定した文字は onFinal で届く
        case .processing, .preparing:
            return
        case .speaking:
            output.stop()
            finishSpeaking()
            await startListening()
        case .idle:
            await startListening()
        }
    }

    /// 録音中の取り消し（画面を閉じる・アプリが背面に回るとき）
    func cancelAll() {
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
        state = .preparing
        let availability = await input.requestAvailability()
        switch availability {
        case .available:
            break
        case .denied(let message), .unavailable(let message):
            problem = message
            state = .idle
            MindWaveDebugLogger.log(.insight, "mokorin voice unavailable")
            return
        }
        // 初めて声で話したら、返答も読み上げる
        speaksReplies = true
        do {
            state = .listening("")
            try input.start(
                onPartial: { [weak self] text in
                    Task { @MainActor in
                        guard let self, self.isListening else { return }
                        self.state = .listening(text)
                    }
                },
                onFinal: { [weak self] text in
                    Task { @MainActor in await self?.deliver(text) }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        guard let self else { return }
                        self.problem = message
                        self.state = .idle
                    }
                })
            MindWaveDebugLogger.log(.insight, "mokorin voice listening")
        } catch {
            problem = "音声入力を開始できませんでした。文字入力か選択肢で答えてね。"
            state = .idle
        }
    }

    private func deliver(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            problem = "うまく聞き取れなかったよ。もう一度マイクを押すか、文字で教えてね。"
            state = .idle
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

/// SFSpeechRecognizer（日本語）＋ AVAudioEngine。話し終えて約1.8秒無音なら自動で終了する。
/// 録音を始めて8秒間何も聞き取れなければ終了する（押したまま話さなかった場合に録音を続けないため）。最長30秒
/// 音声・認識のコールバックは別スレッドで届くため nonisolated とし、状態の更新はメインスレッドで行う
nonisolated final class SpeechRecognizerInput: NSObject, MokorinSpeechInput, @unchecked Sendable {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var limitTimer: Timer?
    private var latestText = ""
    private var finished = false
    private var onFinal: ((String) -> Void)?

    /// 話し終えたと判断する無音の長さ（日本語の言いよどみで途中送信しないよう 1.8 秒）
    static let silenceSeconds: TimeInterval = 1.8
    static let noSpeechSeconds: TimeInterval = 8
    static let maxSeconds: TimeInterval = 30

    func requestAvailability() async -> MokorinVoiceAvailability {
        guard let recognizer, recognizer.isAvailable else {
            return .unavailable("この端末では今は音声認識を使えません。文字入力か選択肢で答えてね。")
        }
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else {
            return .denied("音声認識が許可されていません（設定アプリ → Mind Wave で変更できます）。文字入力か選択肢で答えてね。")
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else {
            return .denied("マイクが許可されていません（設定アプリ → Mind Wave で変更できます）。文字入力か選択肢で答えてね。")
        }
        return .available
    }

    func start(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void, onError: @escaping (String) -> Void) throws {
        cancel()
        guard let recognizer else { throw NSError(domain: "MokorinVoice", code: 1) }
        finished = false
        latestText = ""
        self.onFinal = onFinal

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 端末内で認識できる場合は、音声を外部（Apple のサーバー）へ送らない
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.latestText = text
                    onPartial(text)
                    self.restartSilenceTimer()
                    if result.isFinal { self.finish() }
                }
            }
            if error != nil {
                DispatchQueue.main.async {
                    if self.latestText.isEmpty && !self.finished {
                        self.teardown()
                        self.finished = true
                        onError("うまく聞き取れなかったよ。もう一度マイクを押すか、文字で教えてね。")
                    } else {
                        self.finish()
                    }
                }
            }
        }
        DispatchQueue.main.async {
            self.limitTimer = Timer.scheduledTimer(withTimeInterval: Self.maxSeconds, repeats: false) { [weak self] _ in self?.finish() }
            // 話し始めるまでの待ち時間（話し始めると無音判定の 1.5 秒に置き換わる）
            self.restartSilenceTimer(interval: Self.noSpeechSeconds)
        }
    }

    func stop() {
        DispatchQueue.main.async { self.finish() }
    }

    func cancel() {
        finished = true
        onFinal = nil
        task?.cancel()
        teardown()
    }

    private func restartSilenceTimer(interval: TimeInterval = SpeechRecognizerInput.silenceSeconds) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in self?.finish() }
    }

    /// 録音を止めて、確定した文字を1回だけ返す
    private func finish() {
        guard !finished else { return }
        finished = true
        request?.endAudio()
        task?.finish()
        let text = latestText
        let callback = onFinal
        onFinal = nil
        teardown()
        callback?(text)
    }

    private func teardown() {
        silenceTimer?.invalidate(); silenceTimer = nil
        limitTimer?.invalidate(); limitTimer = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
