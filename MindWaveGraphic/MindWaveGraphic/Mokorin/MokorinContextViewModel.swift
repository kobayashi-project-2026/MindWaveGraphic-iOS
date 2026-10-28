// MokorinContextViewModel.swift
// Mokorin
//
// 測定前の状況選択（ContextCalibrationView）で、もこりんとの会話を管理する。
// AI 相談（ChatViewModel）とは別の会話状態を持ち、画面を閉じると破棄される（保存しない）。
//
// 進行:
//   STEP 1 scene     : 場面を確認する（ボタン or 文章）
//   STEP 2 condition : 身体状態を確認する（ボタンで複数選択→「これで決定」 or 文章）
//   STEP 3 review    : 内容をまとめて確認する（選択はいつでも変更できる）
//   STEP 4/5         : 利用者が「この状況で測定する」を押す → ContextCalibrationView.applyAndProceed()（既存処理）
//
// 規則:
// - AI・端末内判定の結果は「提案」として選択に反映し、画面で確認・変更できる。測定はこのクラスからは開始しない
// - 外部AIは「文章送信の同意（ChatTextConsentStore）」かつサーバー設定がある場合だけ使う。失敗したら端末内の判定で続ける
// - 心拍・HRV などの計測データは送らない（送る項目自体がない）
// - ログには件数・段階・結果の種類だけを出す（会話本文は出さない）

import Foundation
import Combine

@MainActor
final class MokorinContextViewModel: ObservableObject {

    enum Step: Equatable {
        case scene, condition, review

        var code: ContextAssistStepCode {
            switch self {
            case .scene: return .scene
            case .condition: return .condition
            case .review: return .review
            }
        }
    }

    /// 発言の出どころ（画面で区別して表示する）
    enum Origin: Equatable {
        case user
        /// 実際の OpenAI
        case openAI(model: String)
        /// ローカル開発用スタブ（実際の AI ではない）
        case stub(model: String)
        /// 端末内の定型文
        case fixed
    }

    enum Speaker: Equatable { case mokorin, user }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let speaker: Speaker
        let text: String
        let origin: Origin
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var step: Step = .scene
    @Published private(set) var selectedScene: ContextScene
    @Published private(set) var selectedConditions: Set<BodyCondition>
    /// もこりん（AI・端末内判定）が提案し、利用者がまだ変更していない項目
    @Published private(set) var suggestedScene: ContextScene? = nil
    @Published private(set) var suggestedConditions: Set<BodyCondition> = []
    @Published private(set) var hasSceneAnswer: Bool
    @Published private(set) var hasConditionAnswer: Bool
    @Published var draft: String = ""
    @Published private(set) var isSending = false
    /// 外部AIに接続できなかった理由など（画面に小さく表示）
    @Published private(set) var notice: String? = nil
    @Published private(set) var isTextConsented: Bool
    @Published private(set) var conversationId = UUID()
    /// もこりんの表情・動作（MokorinWebView へ渡す）。外部AIの応答があればその値、なければ固定の規則
    @Published private(set) var pose = MokorinPose()

    private let initialContext: MeasurementContext
    private let isInAppEdit: Bool
    private let consentStore: ChatTextConsentStore
    private let configurationProvider: () -> RemoteInsightConfiguration?
    private let clientFactory: (RemoteInsightConfiguration) -> ContextAssistClient

    /// - Parameters:
    ///   - initialContext: メインアプリ内からの再設定では現在の状況、初回は既定値
    ///   - isInAppEdit: メインアプリ内（共通メニュー）から開いたか
    init(initialContext: MeasurementContext = .default,
         isInAppEdit: Bool = false,
         consentStore: ChatTextConsentStore = ChatTextConsentStore(),
         configurationProvider: @escaping () -> RemoteInsightConfiguration? = { RemoteInsightConfiguration.load() },
         clientFactory: @escaping (RemoteInsightConfiguration) -> ContextAssistClient = { RemoteContextAssistClient(configuration: $0) }) {
        self.initialContext = initialContext
        self.isInAppEdit = isInAppEdit
        self.consentStore = consentStore
        self.configurationProvider = configurationProvider
        self.clientFactory = clientFactory
        self.selectedScene = initialContext.scene
        self.selectedConditions = initialContext.conditions.isEmpty ? [.none] : initialContext.conditions
        // メインアプリ内の再設定は現在の状況を「回答済み」として始める
        self.hasSceneAnswer = isInAppEdit
        self.hasConditionAnswer = isInAppEdit
        self.isTextConsented = consentStore.isConsented
        start()
    }

    // MARK: - 状態

    /// 外部AIを使えるか（同意＋サーバー設定）
    var usesRemoteAI: Bool { isTextConsented && configurationProvider() != nil }
    var isServerConfigured: Bool { configurationProvider() != nil }

    var canSend: Bool { !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 確定した場合に保存する内容（既存の MeasurementContext。applyAndProceed() が使う）
    var measurementContext: MeasurementContext {
        var ctx = MeasurementContext()
        ctx.scene = selectedScene
        ctx.conditions = selectedConditions
        return ctx
    }

    // MARK: - 操作（ボタン）

    /// 場面ボタン（単一選択）
    func selectScene(_ scene: ContextScene) {
        selectedScene = scene
        suggestedScene = nil
        let wasAnswered = hasSceneAnswer
        hasSceneAnswer = true
        if step == .scene {
            appendUser("場面は「\(scene.displayName)」です")
            advance(fixedReply: true)
            applyRuleExpression(userText: nil)
        } else if !wasAnswered || step == .review {
            refreshSummaryIfReviewing()
        }
    }

    /// 身体状態ボタン（複数選択。「特になし」は排他）— 既存の ContextCalibrationView と同じ規則
    func toggleCondition(_ cond: BodyCondition) {
        if cond == .none {
            selectedConditions = [.none]
        } else {
            selectedConditions.remove(.none)
            if selectedConditions.contains(cond) {
                selectedConditions.remove(cond)
                if selectedConditions.isEmpty { selectedConditions = [.none] }
            } else {
                selectedConditions.insert(cond)
            }
        }
        suggestedConditions.removeAll()
        if step == .review { refreshSummaryIfReviewing() }
    }

    /// 身体状態の段階で「これで決定」
    func confirmConditions() {
        guard step == .condition else { return }
        hasConditionAnswer = true
        let names = BodyCondition.allCases.filter { selectedConditions.contains($0) }.map(\.displayName).joined(separator: "・")
        appendUser("からだの状態は「\(names)」です")
        advance(fixedReply: true)
        applyRuleExpression(userText: nil)
    }

    // MARK: - 操作（文章）

    func setTextConsent(_ consented: Bool) {
        consentStore.setConsented(consented)
        isTextConsented = consentStore.isConsented
    }

    /// 入力欄の文章を送る（送信中は無視）
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !text.isEmpty else { return }
        draft = ""
        isSending = true
        Task { await perform(text) }
    }

    /// 文章を送り、もこりんの返答が表示されるまで待つ（テスト・検証フック用）
    func submit(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !text.isEmpty else { return }
        isSending = true
        await perform(text)
    }

    /// 会話をやり直す（選択も最初の状態に戻す）
    func restart() {
        messages = []
        draft = ""
        notice = nil
        isSending = false
        step = .scene
        selectedScene = initialContext.scene
        selectedConditions = initialContext.conditions.isEmpty ? [.none] : initialContext.conditions
        suggestedScene = nil
        suggestedConditions = []
        hasSceneAnswer = isInAppEdit
        hasConditionAnswer = isInAppEdit
        conversationId = UUID()
        start()
        MindWaveDebugLogger.log(.insight, "mokorin restart")
    }

    // MARK: - 内部

    private func start() {
        appendMokorin(isInAppEdit ? MokorinScript.greetingForEdit(current: initialContext) : MokorinScript.greeting, origin: .fixed)
        pose = pose.with(MokorinExpressionRules.greeting.0, MokorinExpressionRules.greeting.1)
    }

    /// 定型文で応答したときの表情・動作
    private func applyRuleExpression(userText: String?) {
        let e = MokorinExpressionRules.forReply(step: step, userText: userText, conditions: selectedConditions)
        pose = pose.with(e.0, e.1)
    }

    private func perform(_ rawText: String) async {
        let text = String(rawText.prefix(ContextAssistLimits.maxUserChars))
        appendUser(text)
        notice = nil
        let conversation = conversationId

        if usesRemoteAI, let configuration = configurationProvider() {
            let request = makeRequest()
            do {
                let response = try await clientFactory(configuration).send(request)
                guard conversation == conversationId else { return }   // やり直し後に届いた応答は破棄
                let candidates = try response.result.typedCandidates()
                applyCandidates(scene: candidates.scene, conditions: candidates.conditions)
                let origin: Origin = response.isStub ? .stub(model: response.model) : .openAI(model: response.model)
                var reply = response.result.reply
                if response.result.needsClarification, let q = response.result.clarificationQuestion, !reply.contains(q) {
                    reply += "\n" + q
                }
                updateStep()
                appendMokorin(reply, origin: origin)
                // 外部AIが選んだ表情・動作（不正な値は calm / nod）。返答文は固定文で上書きしない
                let expression = response.result.typedExpression
                pose = pose.with(expression.emotion, expression.action)
                // 返答に次の質問・確認が含まれない場合は、段階に合わせた定型の質問を添える（会話が止まらないように）
                let asksSomething = reply.contains("？") || reply.contains("?")
                switch step {
                case .review where !reply.contains("測定"):
                    appendMokorin(MokorinScript.summary(scene: selectedScene, conditions: selectedConditions), origin: .fixed)
                case .scene where !asksSomething:
                    appendMokorin(MokorinScript.askScene, origin: .fixed)
                case .condition where !asksSomething:
                    appendMokorin(MokorinScript.askCondition(scene: selectedScene), origin: .fixed)
                default:
                    break
                }
                MindWaveDebugLogger.log(.insight, "mokorin remote provider=\(response.provider) step=\(step) scene=\(candidates.scene != nil) conditions=\(candidates.conditions.count)")
                isSending = false
                return
            } catch {
                guard conversation == conversationId else { return }
                let clientError = error as? InsightClientError
                notice = "外部AIに接続できなかったため、端末内の判定で続けます（\(clientError?.chatUserMessage ?? "不明なエラー")）"
                MindWaveDebugLogger.log(.insight, "mokorin remote failed -> local reason=\(clientError?.logCode ?? "unknown_error")")
            }
        }

        // 端末内の判定（外部AIを使わない・失敗した場合）
        let local = MokorinKeywordInterpreter.interpret(text)
        applyCandidates(scene: local.scene, conditions: local.conditions)
        advance(fixedReply: true, clarifyIfUnchanged: local.scene == nil && local.conditions.isEmpty)
        applyRuleExpression(userText: text)
        MindWaveDebugLogger.log(.insight, "mokorin local step=\(step) scene=\(local.scene != nil) conditions=\(local.conditions.count)")
        isSending = false
    }

    /// 候補を「提案」として選択に反映する（利用者は画面で変更できる）
    private func applyCandidates(scene: ContextScene?, conditions: Set<BodyCondition>) {
        if let scene {
            selectedScene = scene
            suggestedScene = scene
            hasSceneAnswer = true
        }
        if !conditions.isEmpty {
            selectedConditions = conditions
            suggestedConditions = conditions
            hasConditionAnswer = true
        }
    }

    private func updateStep() {
        if !hasSceneAnswer { step = .scene }
        else if !hasConditionAnswer { step = .condition }
        else { step = .review }
    }

    /// 段階を進め、定型文で次の質問または確認を出す
    private func advance(fixedReply: Bool, clarifyIfUnchanged: Bool = false) {
        let previous = step
        updateStep()
        guard fixedReply else { return }
        switch step {
        case .scene:
            appendMokorin(MokorinScript.askScene, origin: .fixed)
        case .condition:
            appendMokorin(previous == .condition && clarifyIfUnchanged ? MokorinScript.askConditionAgain
                                                                       : MokorinScript.askCondition(scene: selectedScene), origin: .fixed)
        case .review:
            appendMokorin(MokorinScript.summary(scene: selectedScene, conditions: selectedConditions), origin: .fixed)
        }
    }

    /// 確認段階で選択を変えたら、まとめを更新する（直前のまとめを置き換え、会話を増やしすぎない）
    private func refreshSummaryIfReviewing() {
        guard step == .review else { return }
        let summary = MokorinScript.summary(scene: selectedScene, conditions: selectedConditions)
        if let last = messages.last, last.speaker == .mokorin, last.origin == .fixed, last.text.hasPrefix("教えてくれてありがとう。") {
            messages.removeLast()
        }
        appendMokorin(summary, origin: .fixed)
    }

    private func makeRequest() -> ContextAssistRequestDTO {
        let history: [ChatMessageDTO] = messages.map {
            let limit = $0.speaker == .user ? ContextAssistLimits.maxUserChars : ContextAssistLimits.maxAssistantChars
            return ChatMessageDTO(role: $0.speaker == .user ? .user : .assistant, content: String($0.text.prefix(limit)))
        }
        var trimmed = Array(history.suffix(ContextAssistLimits.maxMessages))
        while let first = trimmed.first, first.role == .assistant, trimmed.count > 1, trimmed.count == ContextAssistLimits.maxMessages {
            trimmed.removeFirst()
        }
        return ContextAssistRequestDTO(
            requestId: UUID(),
            conversationId: conversationId,
            step: step.code,
            messages: trimmed,
            current: ContextAssistCurrentDTO(
                scene: hasSceneAnswer ? selectedScene.rawValue : nil,
                conditions: hasConditionAnswer ? BodyCondition.allCases.filter { selectedConditions.contains($0) }.map(\.rawValue) : []
            )
        )
    }

    private func appendUser(_ text: String) {
        messages.append(Message(speaker: .user, text: text, origin: .user))
    }

    private func appendMokorin(_ text: String, origin: Origin) {
        messages.append(Message(speaker: .mokorin, text: text, origin: origin))
    }
}
