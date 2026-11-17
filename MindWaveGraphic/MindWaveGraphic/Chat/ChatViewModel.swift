// ChatViewModel.swift
// Chat
//
// AI 相談画面の状態。会話履歴はこのオブジェクト（メモリ上）だけが持ち、端末・サーバー・OpenAI に保存しない。
//
// 動作の規則:
// - 送信中は次の送信を受け付けない（連打・同時送信の防止）
// - 外部AIが使えない（未同意・サーバー未設定）ときは、端末内の定型アドバイスで応答する
// - 外部AIへの送信に失敗したら、利用者の発言に「失敗」を付け、端末内の定型アドバイスを代わりに表示する。
//   再送信すると代替の返答を取り除いて外部AIへ送り直す（会話の順序は保たれる）
// - 端末内の定型アドバイスは AI の発言ではないため、外部AIへ送る履歴には含めない
// - リセットで会話 ID を作り直し、送信中の応答が後から届いても破棄する
// - 測定前の会話（STEP 0〜6）で分かったことと、この画面で本人が話したこと（端末内のキーワード抽出）を
//   learned にまとめ、外部AIへの補足（context.check_in。列挙値のみ）と改善方法の推薦に使う（2026-11-17）
// - 直前の発言の訂正（入力欄へ戻す）・取り消し（一つ前へ戻る）ができる

import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {

    /// 返答の出どころ（画面で区別して表示する）
    enum Origin: Equatable {
        case user
        /// 実際の OpenAI（モデル名）
        case openAI(model: String)
        /// ローカル開発用スタブ（実際の AI ではない）
        case stub(model: String)
        /// 端末内の定型アドバイス（理由）
        case local(reason: String)
    }

    enum Status: Equatable {
        case sent
        case sending
        case failed(String)
    }

    struct Message: Identifiable, Equatable {
        let id: UUID
        let role: ChatRoleCode
        let text: String
        let origin: Origin
        var status: Status
        var truncated: Bool = false
    }

    /// 外部AIを使えない理由
    enum RemoteUnavailableReason: Equatable {
        case notConfigured
        case consentMissing

        var message: String {
            switch self {
            case .notConfigured:  return "サーバーが未設定のため、端末内の定型アドバイスで応答します。"
            case .consentMissing: return "外部AIへの送信に同意していないため、端末内の定型アドバイスで応答します。"
            }
        }
    }

    @Published private(set) var messages: [Message] = []
    @Published var draft: String = ""
    @Published private(set) var isSending = false
    /// 直近の送信失敗（再送信ボタンの表示に使う）
    @Published private(set) var lastFailureMessage: String? = nil
    @Published private(set) var isTextConsented: Bool
    @Published private(set) var conversationId = UUID()
    /// 会話から分かったこと（測定前の会話 ＋ この画面で本人が話したこと）。メモリのみ。保存しない
    @Published private(set) var learned = MokorinCheckIn()

    private let consentStore: ChatTextConsentStore
    private let configurationProvider: () -> RemoteInsightConfiguration?
    private let clientFactory: (RemoteInsightConfiguration) -> ChatRemoteClient
    private var sceneProvider: () -> ContextScene?
    private var measurementProvider: () -> ChatMeasurementContextDTO?
    private var biometricConsentProvider: () -> Bool
    /// 測定前の会話（STEP 0〜6）で分かったこと
    private var checkInProvider: () -> MokorinCheckIn?

    init(consentStore: ChatTextConsentStore = ChatTextConsentStore(),
         configurationProvider: @escaping () -> RemoteInsightConfiguration? = { RemoteInsightConfiguration.load() },
         clientFactory: @escaping (RemoteInsightConfiguration) -> ChatRemoteClient = { RemoteChatClient(configuration: $0) },
         sceneProvider: @escaping () -> ContextScene? = { nil },
         measurementProvider: @escaping () -> ChatMeasurementContextDTO? = { nil },
         biometricConsentProvider: @escaping () -> Bool = { false },
         checkInProvider: @escaping () -> MokorinCheckIn? = { nil }) {
        self.consentStore = consentStore
        self.configurationProvider = configurationProvider
        self.clientFactory = clientFactory
        self.sceneProvider = sceneProvider
        self.measurementProvider = measurementProvider
        self.biometricConsentProvider = biometricConsentProvider
        self.checkInProvider = checkInProvider
        self.isTextConsented = consentStore.isConsented
        recomputeLearned()
    }

    /// 場面・計測の取得方法を設定する（画面表示時に AppFlowState / MindWaveViewModel と接続する）
    func configureContext(scene: @escaping () -> ContextScene?,
                          measurement: @escaping () -> ChatMeasurementContextDTO?,
                          biometricConsent: @escaping () -> Bool,
                          checkIn: @escaping () -> MokorinCheckIn? = { nil }) {
        sceneProvider = scene
        measurementProvider = measurement
        biometricConsentProvider = biometricConsent
        checkInProvider = checkIn
        recomputeLearned()
    }

    // MARK: - 状態

    /// 外部AIを使えない理由（nil = 使える）
    var remoteUnavailableReason: RemoteUnavailableReason? {
        if configurationProvider() == nil { return .notConfigured }
        if !isTextConsented { return .consentMissing }
        return nil
    }

    var isServerConfigured: Bool { configurationProvider() != nil }

    var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 直前の利用者の発言（訂正・取り消しの対象）。送信中は nil
    var lastUserMessage: Message? {
        guard !isSending else { return nil }
        return messages.last(where: { $0.role == .user && $0.origin == .user })
    }

    /// 会話から分かったことに基づく改善方法の推薦（最大 2 つ）。分かっていることがなければ空
    var recommendations: [MethodRecommendation] {
        guard ChatCheckInSummary.hasAnyInfo(learned) else { return [] }
        return MokorinMethodAdvisor.recommend(learned)
    }

    /// 入力欄の上に出す「話しかけの例」（タップするとそのまま送る）
    var quickReplies: [String] {
        ChatQuickReplies.make(learned: learned, hasReply: messages.contains { $0.role == .assistant })
    }

    /// 再送信できる失敗した発言があるか
    var canRetry: Bool {
        !isSending && remoteUnavailableReason == nil && messages.contains { if case .failed = $0.status { return true } else { return false } }
    }

    // MARK: - 操作

    /// 設定画面で同意が変更された場合に合わせる（画面表示時に呼ぶ）
    func refreshConsent() {
        isTextConsented = consentStore.isConsented
    }

    func setTextConsent(_ consented: Bool) {
        consentStore.setConsented(consented)
        isTextConsented = consentStore.isConsented
    }

    /// 入力欄の文章を送る（送信中は無視する）
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !text.isEmpty else { return }
        draft = ""
        // 同期的に送信中にしてから非同期処理を始める（連打で二重送信しないため）
        isSending = true
        Task { await perform(text) }
    }

    /// 文章を送り、返答（または代替の返答）が表示されるまで待つ。送信中なら何もしない
    func submit(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !text.isEmpty else { return }
        isSending = true
        await perform(text)
    }

    /// 送信処理の本体（呼び出し前に isSending = true にしておくこと）
    private func perform(_ rawText: String) async {
        let text = String(rawText.prefix(ChatLimits.maxUserChars))
        lastFailureMessage = nil
        let userMessage = Message(id: UUID(), role: .user, text: text, origin: .user, status: .sending)
        messages.append(userMessage)
        recomputeLearned()
        MindWaveDebugLogger.log(.insight, "chat send messages=\(messages.count)")
        await requestReply(for: userMessage.id)
    }

    /// 最後に失敗した発言を外部AIへ送り直す
    func retryLastFailed() async {
        guard !isSending, remoteUnavailableReason == nil,
              let index = messages.lastIndex(where: { if case .failed = $0.status { return true } else { return false } }) else { return }
        isSending = true
        lastFailureMessage = nil
        // 失敗時に表示した代替の返答（直後の端末内アドバイス）を取り除く
        let next = messages.index(after: index)
        if next < messages.count, case .local = messages[next].origin {
            messages.remove(at: next)
        }
        messages[index].status = .sending
        await requestReply(for: messages[index].id)
    }

    /// 端末内で作った発言（もこりんの結果の説明・選択肢で選んだ言葉）を追加する。
    /// 測定値を含みうるため、外部AIへ送る履歴には含めない（origin = .local）
    func appendLocalExchange(userText: String?, reply: String, reason: String) {
        if let userText {
            messages.append(Message(id: UUID(), role: .user, text: userText, origin: .local(reason: reason), status: .sent))
        }
        messages.append(Message(id: UUID(), role: .assistant, text: reply, origin: .local(reason: reason), status: .sent))
    }

    /// 直前の発言を取り消し、その返答も消す（一つ前へ戻る）。消した発言の文章を返す
    @discardableResult
    func undoLastExchange() -> String? {
        guard let target = lastUserMessage, let i = messages.firstIndex(where: { $0.id == target.id }) else { return nil }
        messages.removeSubrange(i...)
        lastFailureMessage = nil
        recomputeLearned()
        MindWaveDebugLogger.log(.insight, "chat undo messages=\(messages.count)")
        return target.text
    }

    /// 直前の発言を直す: 取り消して文章を入力欄に戻す
    func editLastUserMessage() {
        guard let text = undoLastExchange() else { return }
        draft = text
    }

    /// 会話を消去し、新しい会話として始める
    func reset() {
        messages = []
        draft = ""
        lastFailureMessage = nil
        isSending = false
        conversationId = UUID()
        recomputeLearned()
        MindWaveDebugLogger.log(.insight, "chat reset")
    }

    /// 改善方法を開くときに引き継ぐ、会話の内容（測定前の会話の記録に、この画面で分かったことを加える）
    func memoryForImprovement(base: MokorinSessionMemory?, context: MeasurementContext, now: Date = Date()) -> MokorinSessionMemory? {
        guard ChatCheckInSummary.hasAnyInfo(learned) else { return base }
        var memory = base ?? MokorinSessionMemory(tension: nil, scene: context.scene, conditions: context.conditions, situationNote: nil)
        memory.checkIn = learned
        if memory.situationNote == nil { memory.situationNote = learned.situationNote }
        memory.capturedAt = now
        return memory
    }

    /// 端末内のキーワード抽出で、この画面の発言から分かったことを加える。
    /// 測定前の会話で分かっている項目は上書きしない（選択肢で答えた内容のほうが確か）。
    /// 緊張の強さは試作スコアの基準になるため、この画面の発言からは決めない。はっきりしない抽出（tentative）は使わない
    private func recomputeLearned() {
        var c = checkInProvider() ?? MokorinCheckIn()
        let now = Date()
        for m in messages where m.role == .user && m.origin == .user {
            var e = CheckInExtractor.extract(m.text, asked: nil)
            e.tension = nil
            e.declined = []
            if c.isKnown(.sleep) || e.tentative.contains(.sleep) { e.sleep = nil }
            if c.isKnown(.activity) || e.tentative.contains(.activity) { e.activity = nil }
            if c.isKnown(.condition) || e.tentative.contains(.condition) { e.condition = nil }
            if c.isKnown(.situation) || e.tentative.contains(.situation) { e.situation = nil; e.situationNote = nil }
            if c.isKnown(.timing) || e.tentative.contains(.timing) { e.timing = nil }
            if c.isKnown(.emotion) || e.tentative.contains(.emotion) { e.emotion = nil }
            if c.isKnown(.cause) || e.tentative.contains(.cause) { e.causes = [] }
            if c.isKnown(.body) || e.tentative.contains(.body) { e.body = [] }
            if c.isKnown(.support) || e.tentative.contains(.support) { e.support = nil }
            c.apply(e, source: .user, at: now)
        }
        learned = c
    }

    // MARK: - 内部

    private func requestReply(for userMessageID: UUID) async {
        let conversation = conversationId
        let scene = sceneProvider()
        guard let userText = messages.first(where: { $0.id == userMessageID })?.text else { isSending = false; return }

        if let reason = remoteUnavailableReason {
            appendLocalReply(after: userMessageID, text: LocalChatResponder.reply(to: userText, scene: scene), reason: reason.message, failed: nil)
            isSending = false
            return
        }
        guard let configuration = configurationProvider() else { isSending = false; return }

        // 外部AIへ送る履歴: この発言までの利用者の発言と外部AIの返答（端末内アドバイスは除く）
        guard let upTo = messages.firstIndex(where: { $0.id == userMessageID }) else { isSending = false; return }
        let history: [ChatMessageDTO] = messages[...upTo].compactMap { m in
            switch m.origin {
            case .user, .openAI, .stub: return ChatMessageDTO(role: m.role, content: m.text)
            case .local: return nil
            }
        }
        let request = ChatRequestDTO(
            requestId: UUID(),
            conversationId: conversation,
            messages: ChatHistoryPolicy.trimmed(history),
            context: ChatContextDTO(scene: scene?.rawValue, measurement: measurementProvider(),
                                    checkIn: ChatCheckInSummary.contractValue(learned)),
            consent: ChatConsentDTO(biometricContextConsented: biometricConsentProvider(),
                                    consentVersion: InsightConsentStore.currentConsentVersion)
        )

        let started = Date()
        do {
            let response = try await clientFactory(configuration).send(request)
            // リセット後に届いた応答は破棄する（別の会話に混ざらないように）
            guard conversation == conversationId, messages.contains(where: { $0.id == userMessageID }) else { return }
            setStatus(.sent, for: userMessageID)
            let origin: Origin = response.isStub ? .stub(model: response.model) : .openAI(model: response.model)
            insert(Message(id: UUID(), role: .assistant, text: response.reply.text, origin: origin, status: .sent,
                           truncated: response.reply.truncated), after: userMessageID)
            MindWaveDebugLogger.log(.insight, "chat reply provider=\(response.provider) model=\(response.model) latencyMs=\(Int(Date().timeIntervalSince(started) * 1000)) outputTokens=\(response.usage?.outputTokens ?? -1)")
        } catch {
            guard conversation == conversationId, messages.contains(where: { $0.id == userMessageID }) else { return }
            let clientError = error as? InsightClientError
            let userFacing = clientError?.chatUserMessage ?? "AIの応答を取得できませんでした。"
            MindWaveDebugLogger.log(.insight, "chat remote failed -> local fallback reason=\(clientError?.logCode ?? "unknown_error")")
            appendLocalReply(after: userMessageID, text: LocalChatResponder.reply(to: userText, scene: scene),
                             reason: "外部AIに接続できなかったため、端末内の定型アドバイスを表示しています。", failed: userFacing)
            lastFailureMessage = userFacing
        }
        if conversation == conversationId { isSending = false }
    }

    private func appendLocalReply(after userMessageID: UUID, text: String, reason: String, failed: String?) {
        setStatus(failed.map { .failed($0) } ?? .sent, for: userMessageID)
        insert(Message(id: UUID(), role: .assistant, text: text, origin: .local(reason: reason), status: .sent), after: userMessageID)
    }

    private func setStatus(_ status: Status, for id: UUID) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].status = status
    }

    /// 対応する利用者の発言の直後に入れる（再送信時も順序を保つ）
    private func insert(_ message: Message, after id: UUID) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { messages.append(message); return }
        messages.insert(message, at: messages.index(after: i))
    }
}
