// ChatServices.swift
// Chat
//
// AI 相談の通信・代替応答・同意・送信可否の判定。画面（AIChatView）と状態（ChatViewModel）からは
// このファイルの型だけを使い、OpenAI の形式には依存しない（OpenAI はサーバーだけが呼ぶ）。
// 構成: docs/OPENAI_CHAT_ARCHITECTURE.md

import Foundation

// MARK: - 通信

/// サーバーへの送信（テストではスタブに差し替える）
protocol ChatRemoteClient: Sendable {
    func send(_ request: ChatRequestDTO) async throws -> ChatResponseDTO
}

/// 自前サーバーの POST /v1/chat を呼ぶ。接続先・クライアントトークンは単発インサイトと共通
/// （RemoteInsightConfiguration）。アプリは OpenAI の APIキーを持たない。
struct RemoteChatClient: ChatRemoteClient {
    let configuration: RemoteInsightConfiguration
    var session: URLSession = .shared

    func send(_ body: ChatRequestDTO) async throws -> ChatResponseDTO {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.clientToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try MindWaveContract.makeEncoder().encode(body)

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch let error as URLError {
            throw error.code == .timedOut ? InsightClientError.timeout : InsightClientError.transport(code: error.code.rawValue)
        }
        guard let http = urlResponse as? HTTPURLResponse else { throw InsightClientError.invalidResponse("not http") }
        let decoder = MindWaveContract.makeDecoder()
        guard http.statusCode == 200 else {
            let code = (try? decoder.decode(InsightErrorDTO.self, from: data))?.error
            throw InsightClientError.httpStatus(http.statusCode, errorCode: code)
        }
        do {
            let decoded = try decoder.decode(ChatResponseDTO.self, from: data)
            try ChatResponseValidation.validate(decoded, expectedRequestId: body.requestId, expectedConversationId: body.conversationId)
            return decoded
        } catch {
            throw InsightClientError.invalidResponse(String(describing: error))
        }
    }
}

extension InsightClientError {
    /// 画面に出す短い説明（技術的な詳細・利用者のデータは含めない）
    var chatUserMessage: String {
        switch self {
        case .timeout:
            return "応答に時間がかかりすぎたため中断しました。"
        case .transport:
            return "サーバーに接続できませんでした。通信環境を確認してください。"
        case .httpStatus(429, _):
            return "AIへのリクエストが混み合っています。少し待ってから再送信してください。"
        case .httpStatus(401, _):
            return "サーバーの認証に失敗しました（アプリの接続設定を確認してください）。"
        case .httpStatus(503, _):
            return "サーバーにAIが設定されていません（APIキー未設定）。"
        case .httpStatus(504, _):
            return "AIの応答がタイムアウトしました。"
        case .httpStatus(let status, _):
            return "AIの応答を取得できませんでした（\(status)）。"
        case .invalidResponse:
            return "AIから想定外の応答が返りました。"
        case .containsMockData:
            return "送信できないデータが含まれています。"
        }
    }
}

// MARK: - 端末内の代替応答

/// 外部AIを使えない・失敗したときの、端末内の定型アドバイス。
/// AI が生成した文章ではないため、画面では必ず「端末内の定型アドバイス」と表示する。
nonisolated enum LocalChatResponder {

    static func reply(to text: String, scene: ContextScene?) -> String {
        let t = text
        if containsAny(t, ["死にたい", "消えたい", "自殺", "自傷"]) {
            return "とてもつらい気持ちを話してくれてありがとうございます。ひとりで抱え込まず、身近な人や専門の相談窓口に今すぐ相談してください。命の危険を感じるときは、ためらわず119番に連絡してください。"
        }
        if containsAny(t, ["呼吸", "息"]) {
            return "4-7-8呼吸を試してみましょう。①口から息を吐き切る ②鼻から4秒かけて吸う ③7秒息を止める ④口から8秒かけてゆっくり吐く。これを3〜4回くり返します。苦しく感じたら秒数を短くして大丈夫です。「整える」の呼吸ガイドでも一緒に練習できます。"
        }
        if containsAny(t, ["面接", "面談"]) || scene == .interview && !containsAny(t, ["試合", "発表", "プレゼン"]) {
            return "面接前に緊張するのは、それだけ真剣に向き合っている証拠です。直前は、ゆっくり長く息を吐く呼吸を数回行い、最初のあいさつと自己紹介の一文だけを声に出して確認しておくと落ち着きやすくなります。"
        }
        if containsAny(t, ["発表", "プレゼン", "スピーチ"]) {
            return "発表の不安には、準備を「最初の30秒」に絞るのがおすすめです。冒頭の一言を決めて数回声に出して練習し、本番直前は吐く息を長くする呼吸を3回ほど行ってみてください。"
        }
        if containsAny(t, ["試合", "大会", "本番"]) || scene == .sports {
            return "本番前は、いつものルーティン（深呼吸、ストレッチ、合言葉など）を1つ決めて実行すると、気持ちを切り替えやすくなります。吐く息を長めにする呼吸も試してみてください。"
        }
        if containsAny(t, ["眠れ", "寝れ", "睡眠"]) {
            return "眠る前は画面の光を避け、ゆっくり長く吐く呼吸を続けてみてください。眠れない状態が続いてつらい場合は、医師など専門家に相談することをおすすめします。"
        }
        return "お話しくださりありがとうございます。まずは、ゆっくり息を吐くことを意識した呼吸を数回してみましょう。緊張している場面や、気になっていることをもう少し詳しく教えていただければ、一緒に対策を考えます。"
    }

    private static func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }
}

// MARK: - 同意

/// 「入力した文章を外部AI（サーバー経由の OpenAI）へ送る」ことへの同意（端末内に保存）。
/// 計測データの送信とは別の同意。未同意でも端末内の定型アドバイスで相談できる。
nonisolated struct ChatTextConsentStore {
    static let defaultsKey = "mindwave.chat.externalTextConsent.v1"
    /// 同意文言を変更したら上げる
    static let currentConsentVersion = 1

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isConsented: Bool {
        defaults.integer(forKey: Self.defaultsKey) == Self.currentConsentVersion
    }

    func setConsented(_ consented: Bool) {
        if consented {
            defaults.set(Self.currentConsentVersion, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
        MindWaveDebugLogger.log(.insight, "chat text consent \(consented ? "granted" : "revoked") version=\(Self.currentConsentVersion)")
    }
}

// MARK: - 計測データ（生体由来の情報）の送信可否

/// 計測の要約を会話に含めてよいかを判定する。
///
/// 条件: 利用者の明示的な同意（設定の外部AI同意）＋ 本物の利用者認証。
/// 現在のログイン機能はモック（本番認証未接続）のため `isRealUserAuthenticated` は常に false で、
/// 計測の要約は送信されない。認証を接続したら、ここを認証状態に置き換え、サーバーの
/// CHAT_ALLOW_MEASUREMENT_CONTEXT と合わせて有効化する（docs/OPENAI_CHAT_ARCHITECTURE.md）。
nonisolated enum ChatBiometricPolicy {

    /// 本物の利用者認証が完了しているか（現在は認証基盤がないため常に false）
    static let isRealUserAuthenticated = false

    static func measurementContext(from result: MindAnalysisResult?,
                                   now: Date,
                                   consented: Bool,
                                   authenticated: Bool = isRealUserAuthenticated) -> ChatMeasurementContextDTO? {
        guard consented, authenticated, let result else { return nil }
        let meta = result.metadata
        let age = max(0, Int(now.timeIntervalSince(result.timestamp)))
        return ChatMeasurementContextDTO(
            source: DataSourceCode(meta.source),
            isMock: meta.isMock,
            state: MindStateCode(result.state),
            hrvStatus: meta.hrvStatus.rawValue,
            baselineStatus: meta.baselineStatus.rawValue,
            dataAgeSeconds: min(age, 7 * 86_400)
        )
    }
}

// MARK: - 履歴の上限

/// 送信する履歴を、サーバーの上限（件数・文字数）に収まるよう直近から切り出す
nonisolated enum ChatHistoryPolicy {

    static func trimmed(_ messages: [ChatMessageDTO]) -> [ChatMessageDTO] {
        var result: [ChatMessageDTO] = []
        var total = 0
        for m in messages.reversed() {
            let limit = m.role == .user ? ChatLimits.maxUserChars : ChatLimits.maxAssistantChars
            let content = String(m.content.prefix(limit))
            guard result.count < ChatLimits.maxMessages, total + content.count <= ChatLimits.maxTotalChars else { break }
            result.insert(ChatMessageDTO(role: m.role, content: content), at: 0)
            total += content.count
        }
        // 先頭が AI の返答だけになるのを避ける（文脈の起点を利用者の発言にする）
        while let first = result.first, first.role == .assistant, result.count > 1 { result.removeFirst() }
        return result
    }
}
