// MokorinScriptedSpeechInput.swift
// Mokorin
//
// DEBUG ビルド専用: マイクを使わずに音声入力の流れを画面で確かめるための模擬入力（シミュレーター検証用）。
// 実際の音声は使わない。判断は本物と同じ MokorinRecognitionSession（実時間のタイマー）で行う。
//
//   MW_MOKORIN_FAKE_VOICE=speech:かなり緊張してる   … 0.5 秒ごとに途中結果を出し、1.8 秒の無音で確定
//   MW_MOKORIN_FAKE_VOICE=silence                   … 何も聞こえず 8 秒で「声が聞こえなかったよ」
//   MW_MOKORIN_FAKE_VOICE=emptyPartial              … 空の途中結果だけ（直後に終わらず 8 秒待つことの確認）
//   MW_MOKORIN_FAKE_VOICE=error:<domain>:<code>     … 認識のエラー（例 kLSRErrorDomain:201）
//   MW_MOKORIN_FAKE_VOICE=denied-mic / denied-speech / unavailable / engine-fail

#if DEBUG
import Foundation

nonisolated final class MokorinScriptedSpeechInput: MokorinSpeechInput, @unchecked Sendable {
    private let script: String
    private var session: MokorinRecognitionSession?
    private var onPartial: ((String) -> Void)?
    private var onFinish: ((MokorinRecognitionOutcome) -> Void)?
    private var timers: [Timer] = []

    init(script: String) { self.script = script }

    static func fromEnvironment() -> MokorinScriptedSpeechInput? {
        ProcessInfo.processInfo.environment["MW_MOKORIN_FAKE_VOICE"].map(MokorinScriptedSpeechInput.init(script:))
    }

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func requestAvailability() async -> MokorinVoiceAvailability {
        try? await Task.sleep(for: .milliseconds(300))   // 権限確認の待ち時間の代わり
        switch script {
        case "denied-mic":    return .unavailable(.microphoneDenied)
        case "denied-speech": return .unavailable(.speechDenied)
        case "unavailable":   return .unavailable(.recognizerUnavailable)
        default:              return .available
        }
    }

    func start(onPartial: @escaping (String) -> Void, onFinish: @escaping (MokorinRecognitionOutcome) -> Void) throws {
        cancel()
        if script == "engine-fail" { throw MokorinVoiceStartError.engineStart(code: -1) }
        var s = MokorinRecognitionSession(now: Self.now())
        s.engineStarted(at: Self.now())
        session = s
        self.onPartial = onPartial
        self.onFinish = onFinish
        let id = s.id
        if script.hasPrefix("speech:") {
            let text = String(script.dropFirst("speech:".count))
            let steps = stride(from: 2, through: text.count, by: 2).map { String(text.prefix($0)) } + [text]
            for (i, partial) in steps.enumerated() {
                after(0.6 + Double(i) * 0.5, id) { s in s.result(partial, isFinal: false, at: Self.now()) }
            }
        } else if script == "emptyPartial" {
            after(0.3, id) { s in s.result("", isFinal: false, at: Self.now()) }
        } else if script.hasPrefix("error:") {
            let parts = script.split(separator: ":").map(String.init)
            let domain = parts.count > 1 ? parts[1] : "kAFAssistantErrorDomain"
            let code = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
            after(0.2, id) { s in s.error(domain: domain, code: code) }
        }
        schedule()
    }

    func stop() {
        guard let id = session?.id else { return }
        event(id) { s in s.stopRequested() }
    }

    func cancel() {
        if let id = session?.id { event(id) { s in s.cancelRequested() } }
    }

    private func after(_ seconds: TimeInterval, _ id: UUID, _ change: @escaping (inout MokorinRecognitionSession) -> MokorinRecognitionOutcome?) {
        timers.append(Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.event(id, change)
            if let text = self.session?.text, self.session?.id == id, !text.isEmpty { self.onPartial?(text) }
        })
    }

    private var tickTimer: Timer?

    private func schedule() {
        tickTimer?.invalidate()
        guard let s = session, let deadline = s.nextDeadline else { return }
        let id = s.id
        tickTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, deadline - Self.now()), repeats: false) { [weak self] _ in
            self?.event(id) { s in s.tick(at: Self.now()) }
        }
    }

    private func event(_ id: UUID, _ change: (inout MokorinRecognitionSession) -> MokorinRecognitionOutcome?) {
        guard var s = session, s.id == id else { return }
        let outcome = change(&s)
        session = s
        guard let outcome else { schedule(); return }
        session = nil
        tickTimer?.invalidate()
        timers.forEach { $0.invalidate() }
        timers = []
        let callback = onFinish
        onFinish = nil
        callback?(outcome)
    }
}
#endif
