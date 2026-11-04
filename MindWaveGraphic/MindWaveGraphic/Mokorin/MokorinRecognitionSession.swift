// MokorinRecognitionSession.swift
// Mokorin
//
// 音声認識 1 回分（マイクを押してから終わるまで）の判断。音声・認識の実装（Speech / AVAudioEngine）から切り離し、
// 時刻を引数で受け取るため、テストでは仮想の時計で 8 秒・1.8 秒の判定を確かめられる。
//
// 2026-11-05 の修正（実機で「マイクを押した直後に『うまく聞き取れなかった』」の対策。docs/MOKORIN_VOICE_UI.md）:
// - 無発話（8 秒）・話し終え（1.8 秒）の判定は、録音が実際に始まってから（engineStarted）だけ数える
// - 空の途中結果では「話し始めた」とみなさない（以前は空の結果でも 8 秒 → 1.8 秒に切り替わり、すぐ終わることがあった）
// - 認識のエラーを種類で分ける（取り消し・無発話・利用不可・その他）。取り消しはエラー表示にしない
// - 一度終わったら、その後に届いた結果・エラーは無視する（呼び出し側はセッション ID で古いコールバックも捨てる）

import Foundation

/// 音声入力が使えなかった・失敗した理由（画面の文言と 1 対 1）
nonisolated enum MokorinVoiceFailure: String, Equatable, Sendable {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable
    case noSpeech
    case engineStartFailed
    case recognitionFailed

    var message: String {
        switch self {
        case .microphoneDenied:      return "マイクの使用が許可されていないよ。設定アプリ → Mind Wave で変更できるよ。文字でも話せるよ。"
        case .speechDenied:          return "音声認識の使用が許可されていないよ。設定アプリ → Mind Wave で変更できるよ。文字でも話せるよ。"
        case .recognizerUnavailable: return "今は音声認識を使えないみたい。文字で教えてね。"
        case .noSpeech:              return "声が聞こえなかったよ。もう一度試してみてね。"
        case .engineStartFailed:     return "マイクを開始できなかったよ。もう一度試してね。"
        case .recognitionFailed:     return "うまく聞き取れなかったよ。もう一度試すか、文字で教えてね。"
        }
    }
}

/// 1 回の録音の結果
nonisolated enum MokorinRecognitionOutcome: Equatable, Sendable {
    /// 確定した文字（空ではない）
    case transcript(String)
    case failure(MokorinVoiceFailure)
    /// 利用者による取り消し・話さずに終了（エラーを表示しない）
    case cancelled
}

/// 認識エラーの種類（Speech のエラードメインとコードから決める）
nonisolated enum MokorinRecognitionErrorKind: Equatable, Sendable {
    case cancelled, noSpeech, unavailable, other

    /// 公開されているエラーコードと、Speech が実際に返すことが知られているコードの対応。
    /// 未知のコードは other（「うまく聞き取れなかった」）にする
    static func classify(domain: String, code: Int) -> MokorinRecognitionErrorKind {
        switch (domain, code) {
        case ("kAFAssistantErrorDomain", 1110):            return .noSpeech      // No speech detected
        case ("kAFAssistantErrorDomain", 216),
             ("kAFAssistantErrorDomain", 209),
             ("kLSRErrorDomain", 301):                       return .cancelled     // 要求の取り消し・終了
        case ("kAFAssistantErrorDomain", 1700),
             ("kLSRErrorDomain", 201),
             ("kLSRErrorDomain", 102):                       return .unavailable   // Siri・音声入力が無効、端末内の認識の準備がない
        case (NSURLErrorDomain, _):                          return .unavailable   // サーバー認識での通信不可
        default:                                             return .other
        }
    }
}

nonisolated struct MokorinRecognitionSession: Sendable {
    struct Timing: Equatable, Sendable {
        /// 録音が始まってから、何も聞き取れないまま終える時間
        var noSpeech: TimeInterval = 8
        /// 話し終えたと判断する無音（日本語の言いよどみで途中送信しないよう 1.8 秒）
        var silence: TimeInterval = 1.8
        /// 最長の録音時間
        var maximum: TimeInterval = 30
    }

    enum Phase: Equatable, Sendable { case starting, listening, done }

    let id: UUID
    let timing: Timing
    let createdAt: TimeInterval
    private(set) var phase: Phase = .starting
    private(set) var listeningSince: TimeInterval?
    /// 最後に新しい文字を聞き取った時刻（nil = まだ話していない）
    private(set) var lastSpeechAt: TimeInterval?
    private(set) var text = ""
    private(set) var receivedAudio = false
    private(set) var resultCount = 0
    private(set) var outcome: MokorinRecognitionOutcome?
    /// 診断用（DEBUG ログ）: 終わった理由
    private(set) var endReason: String?
    private(set) var lastError: (domain: String, code: Int)?

    init(id: UUID = UUID(), timing: Timing = Timing(), now: TimeInterval) {
        self.id = id
        self.timing = timing
        self.createdAt = now
    }

    var hasSpeech: Bool { lastSpeechAt != nil }

    /// 録音（AudioEngine）が始まった。ここから無発話・最長の時間を数える
    mutating func engineStarted(at now: TimeInterval) {
        guard phase == .starting else { return }
        phase = .listening
        listeningSince = now
    }

    /// 録音を始められなかった
    mutating func engineFailed() -> MokorinRecognitionOutcome? {
        end(.failure(.engineStartFailed), reason: "engine_start_failed")
    }

    /// 最初の音声バッファが届いた（診断用）
    mutating func audioReceived() {
        receivedAudio = true
    }

    /// 認識の途中結果・確定結果
    mutating func result(_ raw: String, isFinal: Bool, at now: TimeInterval) -> MokorinRecognitionOutcome? {
        guard phase != .done else { return nil }
        resultCount += 1
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空の結果では「話し始めた」とみなさない（無発話の 8 秒を 1.8 秒に縮めない）
        if !trimmed.isEmpty && trimmed != text {
            text = trimmed
            lastSpeechAt = now
        }
        guard isFinal else { return nil }
        return text.isEmpty ? end(.failure(.noSpeech), reason: "final_empty") : end(.transcript(text), reason: "final")
    }

    /// 認識のエラー。すでに聞き取った文字があれば、それを確定して送る
    mutating func error(domain: String, code: Int) -> MokorinRecognitionOutcome? {
        guard phase != .done else { return nil }
        lastError = (domain, code)
        if !text.isEmpty { return end(.transcript(text), reason: "error_after_speech") }
        switch MokorinRecognitionErrorKind.classify(domain: domain, code: code) {
        case .cancelled:   return end(.cancelled, reason: "error_cancelled")
        case .noSpeech:    return end(.failure(.noSpeech), reason: "error_no_speech")
        case .unavailable: return end(.failure(.recognizerUnavailable), reason: "error_unavailable")
        case .other:       return end(.failure(.recognitionFailed), reason: "error_other")
        }
    }

    /// 利用者がマイクを押して終えた。話していなければエラーにせず取り消し扱い
    mutating func stopRequested() -> MokorinRecognitionOutcome? {
        guard phase != .done else { return nil }
        return text.isEmpty ? end(.cancelled, reason: "user_stop_without_speech") : end(.transcript(text), reason: "user_stop")
    }

    /// 取り消し（画面を閉じる・背面に回る・別の録音を始める）
    mutating func cancelRequested() -> MokorinRecognitionOutcome? {
        guard phase != .done else { return nil }
        return end(.cancelled, reason: "cancel")
    }

    /// 次に判定すべき時刻（タイマーはこの時刻に tick を呼ぶ）。録音前・終了後は nil
    var nextDeadline: TimeInterval? {
        guard phase == .listening, let since = listeningSince else { return nil }
        let maxAt = since + timing.maximum
        if let spoke = lastSpeechAt { return min(spoke + timing.silence, maxAt) }
        return min(since + timing.noSpeech, maxAt)
    }

    /// 時刻を進めて判定する
    mutating func tick(at now: TimeInterval) -> MokorinRecognitionOutcome? {
        guard phase == .listening, let since = listeningSince else { return nil }
        if now - since >= timing.maximum {
            return text.isEmpty ? end(.failure(.noSpeech), reason: "max_no_speech") : end(.transcript(text), reason: "max")
        }
        if let spoke = lastSpeechAt {
            return now - spoke >= timing.silence ? end(.transcript(text), reason: "silence") : nil
        }
        return now - since >= timing.noSpeech ? end(.failure(.noSpeech), reason: "no_speech_timeout") : nil
    }

    private mutating func end(_ result: MokorinRecognitionOutcome, reason: String) -> MokorinRecognitionOutcome? {
        guard phase != .done else { return nil }
        phase = .done
        outcome = result
        endReason = reason
        return result
    }
}
