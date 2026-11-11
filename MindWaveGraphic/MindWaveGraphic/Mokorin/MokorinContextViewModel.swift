// MokorinContextViewModel.swift
// Mokorin
//
// 測定前の状況選択（ContextCalibrationView）で、もこりんとの会話を管理する。
// AI 相談（ChatViewModel）とは別の会話状態を持ち、画面を閉じると破棄される（保存しない）。
//
// 2026-11-11 改訂: 会話の中心を STEP 0〜6（MokorinCheckIn）にした。あいさつのあと、必要な項目だけを 1 つずつ尋ね
// （答え済み・答えたくない項目は尋ねない）、そろったらまとめて測定・改善へ。「一つ前の会話へ戻る」で直前の答えを取り消せる。
// 深刻な体の症状の言葉は外部AIへ送らず、端末内で受診・相談を案内する。以下の段階（Step）は画面の互換のために残し、
// 尋ねている項目から計算する（sleep/activity/condition/body → condition、situation/timing → scene、ほか → tension）。
//
// 進行（2026-10-28 改訂）:
//   STEP 0 tension   : 「こんにちは。今、緊張してる？」— 本人の主観（自己申告）。計測した緊張スコアではない
//   STEP 1 scene     : 「何か予定があるの？」— 場面（ContextScene）
//   STEP 2 condition : 「今は落ち着いて座ってる？それとも移動してきたところ？」— 身体状態（BodyCondition、複数可）
//   STEP 3 review    : 内容をまとめて「この状況で測定してみようか？」（選択はいつでも変更できる）
//   STEP 4/5         : 利用者が「この状況で測定する」を押す → ContextCalibrationView.applyAndProceed()（既存処理）
//
// 段階は3つの「回答済み」フラグ（緊張・場面・身体状態）から常に計算する（途中で止まらないように）。
//
// 規則:
// - 回答方法は 音声（MokorinVoiceController が文字にして submit）・文字入力・選択肢のタップ のどれでもよい
// - AI・端末内判定の結果は「提案」として選択に反映し、画面で確認・変更できる。測定はこのクラスからは開始しない
// - すでに答えた内容は聞き直さない（1つの発言に複数の情報があれば、まとめて先へ進む）
// - 主観的な緊張は会話の進行と表情にだけ使い、MeasurementContext・計算・保存データには入れない
// - 外部AIは「文章送信の同意（ChatTextConsentStore）」かつサーバー設定がある場合だけ使う。
//   失敗したら黙って端末内の判定に切り替えず、「もう一度送る」「AIなしで続ける」を選んでもらう（2026-11-04 改訂）
// - 選択肢は必要なときだけ最大3つ。訂正は会話で（「面接じゃなくて試合だった」）。一覧は必要なときだけ
// - 心拍・HRV などの計測データは送らない（送る項目自体がない）
// - ログには件数・段階・結果の種類だけを出す（会話本文は出さない）

import Foundation
import Combine

@MainActor
final class MokorinContextViewModel: ObservableObject {

    nonisolated enum Step: Equatable, Sendable {
        case tension, scene, condition, review

        var code: ContextAssistStepCode {
            switch self {
            case .tension: return .tension
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
    @Published private(set) var step: Step = .tension
    @Published private(set) var selectedScene: ContextScene
    @Published private(set) var selectedConditions: Set<BodyCondition>
    /// もこりん（AI・端末内判定）が提案し、利用者がまだ変更していない項目
    @Published private(set) var suggestedScene: ContextScene? = nil
    @Published private(set) var suggestedConditions: Set<BodyCondition> = []
    @Published private(set) var hasSceneAnswer: Bool
    @Published private(set) var hasConditionAnswer: Bool
    /// 緊張の質問を終えたか
    @Published private(set) var hasTensionAnswer = false
    /// 本人の主観的な緊張（自己申告。計測値ではない）
    @Published private(set) var subjectiveTension: SubjectiveTension? = nil
    @Published var draft: String = ""
    @Published private(set) var isSending = false
    /// 外部AIに接続できなかった理由など（画面に小さく表示）
    @Published private(set) var notice: String? = nil
    @Published private(set) var isTextConsented: Bool
    @Published private(set) var conversationId = UUID()
    /// もこりんの表情・動作（MokorinWebView へ渡す）。外部AIの応答があればその値、なければ固定の規則
    @Published private(set) var pose = MokorinPose()
    /// 外部AIに届かなかった発言（再送・AIなしで続ける の対象）。nil = 失敗なし
    @Published private(set) var failedText: String? = nil
    /// 今の段階で、はっきりしない答えが続いた回数（一覧を案内する目安）
    @Published private(set) var unclearCountInStep = 0
    /// 本人が話した予定の短い言葉（既存の場面に分類しきれない内容: 試験・初対面など）。メモリのみ
    @Published private(set) var situationNote: String? = nil
    /// 疲れている・しんどいと話した
    @Published private(set) var mentionedFatigue = false
    /// 今は測定を望まないと話した（説得せず「測定しないで終える」を出す）
    @Published private(set) var declinedMeasurement = false
    /// 会話で集めた情報（STEP 0〜6）。メモリのみ
    @Published private(set) var checkIn = MokorinCheckIn()
    /// 今尋ねている項目（nil = あいさつ・まとめ）
    @Published private(set) var askedSlot: CheckInSlot? = nil
    /// 深刻な症状の言葉があった（改善の推薦を止め、相談を案内する）
    @Published private(set) var safetyStop = false

    /// 「一つ前の会話へ戻る」ための、利用者の発言の直前の状態
    private struct Snapshot {
        let messages: [Message]
        let checkIn: MokorinCheckIn
        let askedSlot: CheckInSlot?
        let step: Step
        let selectedScene: ContextScene
        let selectedConditions: Set<BodyCondition>
        let hasSceneAnswer: Bool
        let hasConditionAnswer: Bool
        let hasTensionAnswer: Bool
        let subjectiveTension: SubjectiveTension?
        let situationNote: String?
        let mentionedFatigue: Bool
        let declinedMeasurement: Bool
        let safetyStop: Bool
        let unclearCountInStep: Int
    }
    private var undoStack: [Snapshot] = []

    /// 一つ前の会話へ戻れるか
    var canGoBack: Bool { !undoStack.isEmpty }

    /// 答えた（またはとばした）項目の順番。タップでその質問へ戻れる（全体UI 5〜7 ページ）
    var answeredTrail: [CheckInSlot] {
        undoStack.compactMap(\.askedSlot).reduce(into: [CheckInSlot]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// 指定した項目を尋ねていたところまで戻る（その後の答え・推薦も取り消す）
    func goBack(to slot: CheckInSlot) {
        guard undoStack.contains(where: { $0.askedSlot == slot }) else { return }
        while let last = undoStack.last {
            let target = last.askedSlot == slot
            goBack()
            if target { break }
        }
    }

    /// 推薦する改善方法（会話の内容から。本人は推薦以外も選べる）
    var recommendations: [MethodRecommendation] { safetyStop ? [] : MokorinMethodAdvisor.recommend(checkIn) }

    /// 提案・言い回し用の話題（本人の言葉を優先し、なければ既存の場面）
    var topic: MokorinTopic { MokorinTopic.detect(text: situationNote, scene: hasSceneAnswer ? selectedScene : nil) }

    /// 測定前の会話で理解した内容（結果の説明・提案で使う。メモリのみ・外部へ送らない）
    var sessionMemory: MokorinSessionMemory {
        MokorinSessionMemory(tension: subjectiveTension, scene: selectedScene, conditions: selectedConditions,
                             situationNote: situationNote ?? checkIn.situationNote, mentionedFatigue: mentionedFatigue || checkIn.condition?.value.isTired == true,
                             declinedMeasurement: declinedMeasurement, capturedAt: Date(), checkIn: checkIn)
    }

    private let initialContext: MeasurementContext
    private let isInAppEdit: Bool
    private let consentStore: ChatTextConsentStore
    private let configurationProvider: () -> RemoteInsightConfiguration?
    private let clientFactory: (RemoteInsightConfiguration) -> ContextAssistClient
    /// 身体状態の選択肢を利用者が操作したか（選択中の表示・既定値の扱いに使う）
    private var conditionsTouched = false
    /// 緊張の段階で、はっきりしない答えに聞き直した回数（何度も同じことを聞かないため）
    private var tensionRetries = 0
    /// 送信中の要求の識別子（取り消し・やり直しの後に届いた応答を破棄するため）
    private var activeRequestID: UUID? = nil

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

    /// 確定した場合に保存する内容（既存の MeasurementContext。applyAndProceed() が使う）。主観的な緊張は含めない
    var measurementContext: MeasurementContext {
        var ctx = MeasurementContext()
        ctx.scene = selectedScene
        ctx.conditions = selectedConditions
        return ctx
    }

    /// 最新のもこりんの発言（画面中央の吹き出し）
    var latestMokorinMessage: Message? { messages.last { $0.speaker == .mokorin } }

    /// 画面中央に出す「もこりんの今回の発言」。直前の利用者の発言のあとの返答をまとめる
    /// （AI の返答に端末内の定型の質問を添えた場合も、AI の返答が隠れないように1つの吹き出しにする）
    struct Turn: Equatable {
        let id: UUID
        let text: String
        /// 最初の発言の出どころ（AI の返答なら openAI / stub）
        let origin: Origin
        /// AI の返答のあとに端末内の定型文を添えたか
        let hasFixedFollowUp: Bool
    }

    var currentTurn: Turn? {
        let start = (messages.lastIndex { $0.speaker == .user }).map { $0 + 1 } ?? 0
        var replies = messages[start...].filter { $0.speaker == .mokorin }
        if replies.isEmpty, let last = latestMokorinMessage { replies = [last] }
        guard let first = replies.first, let last = replies.last else { return nil }
        return Turn(id: last.id,
                    text: replies.map(\.text).joined(separator: "\n"),
                    origin: first.origin,
                    hasFixedFollowUp: first.origin != .fixed && replies.dropFirst().contains { $0.origin == .fixed })
    }
    /// 最新の利用者の発言（音声認識の結果の確認用）
    var latestUserMessage: Message? { messages.last { $0.speaker == .user } }

    /// 段階に応じた選択肢。会話の補助として最大3つだけ（それ以外は話す・入力する）。
    /// 一覧は、外部AIを使わないとき・はっきりしない答えが続いたときだけ案内する
    var quickReplies: [MokorinQuickReply] {
        if failedText != nil { return [.retry, .continueWithoutAI] }
        if declinedMeasurement { return [.skipMeasurement, .keepTalking] }
        if safetyStop { return [] }
        if let slot = askedSlot, step != .review { return Self.chipOptions(for: slot).map { .checkIn($0) } }
        let offerList = !usesRemoteAI || unclearCountInStep >= 1
        switch step {
        case .tension:
            return [.tension(.slight), .tension(.high), .tension(.calm)]
        case .scene:
            return [.scene(.interview), .noPlan] + (offerList ? [.showList] : [.scene(.work)])
        case .condition:
            return [.condition(.none), .condition(.stairs)] + (offerList ? [.showList] : [.condition(.running)])
        case .review:
            return []
        }
    }

    /// 質問ごとに画面へ出す選択肢（最大 3 つ。ほかの答えは「ほかの答え」の一覧・音声・文字で）
    static func chipOptions(for slot: CheckInSlot) -> [CheckInOption] {
        switch slot {
        case .sleep:     return [.sleep(.h5to7), .sleep(.h7to9), .sleep(.h3to5)]
        case .activity:  return [.activity(.usual), .activity(.light), .activity(.exercised)]
        case .condition: return [.condition(.energetic), .condition(.slightlyTired), .condition(.veryTired)]
        case .situation: return [.situation(.presentation), .situation(.interviewExam), .situation(.restless)]
        case .timing:    return [.timing(.soon), .timing(.today), .timing(.tomorrowOrLater)]
        case .emotion:   return [.emotion(.tense), .emotion(.anxious), .emotion(.unsure)]
        case .tension:   return [.tension(20), .tension(50), .tension(75)]
        case .cause:     return [.cause(.failure), .cause(.speaking), .cause(.unknown)]
        case .body:      return [.body(.heartPounding), .body(.none), .body(.unsure)]
        case .support:   return [.support(.calmDown), .support(.organize), .support(.refresh)]
        }
    }

    /// 選択肢が「選択中」か（身体状態の複数選択の表示用）
    func isSelected(_ reply: MokorinQuickReply) -> Bool {
        if case .condition(let c) = reply, c != .none, step == .condition, conditionsTouched { return selectedConditions.contains(c) }
        return false
    }

    // MARK: - 操作（選択肢・編集画面）

    /// 選択肢をタップしたとき
    func tap(_ reply: MokorinQuickReply) {
        guard !isSending else { return }
        switch reply {
        case .retry:
            Task { await retryFailed() }
            return
        case .continueWithoutAI:
            continueWithoutAI()
            return
        case .showList, .skipMeasurement:
            return   // 一覧（編集シート）・測定しないで終える は画面側で処理する
        case .checkIn(let option):
            answer(options: [option])
            return
        case .keepTalking:
            declinedMeasurement = false
            appendUser(reply.label)
            advance(userText: nil)
            return
        default:
            break
        }
        failedText = nil
        switch reply {
        case .tension(let t):
            appendUser(t.replyLabel)
            subjectiveTension = t
            hasTensionAnswer = true
            advance(userText: t.replyLabel, tensionJustAnswered: true)
        case .scene(let s):
            selectScene(s)
        case .noPlan:
            appendUser(reply.label)
            situationNote = nil
            selectedScene = .calm
            suggestedScene = nil
            hasSceneAnswer = true
            hasTensionAnswer = true
            advance(userText: reply.label)
        case .condition(.none):
            selectedConditions = [.none]
            suggestedConditions = []
            conditionsTouched = true
            hasConditionAnswer = true
            hasTensionAnswer = true
            appendUser(reply.label)
            advance(userText: reply.label)
        case .condition(let c):
            // 会話の選択肢は1回のタップで答える（複数の状態は話す・入力する、または一覧で選ぶ）
            selectedConditions = [c]
            suggestedConditions = []
            conditionsTouched = true
            hasConditionAnswer = true
            hasTensionAnswer = true
            appendUser(reply.label)
            advance(userText: reply.label)
        case .confirmConditions:
            confirmConditions()
        case .retry, .continueWithoutAI, .showList, .skipMeasurement, .keepTalking, .checkIn:
            break
        }
    }

    /// 選択肢で答える（複数選択の項目は複数可）。外部AIへは送らず、端末内で次の質問へ進む
    func answer(options: [CheckInOption]) {
        guard !isSending, !options.isEmpty else { return }
        pushUndo()
        failedText = nil
        var e = CheckInExtraction()
        for o in options {
            switch o {
            case .sleep(let v): e.sleep = v
            case .activity(let v): e.activity = v
            case .condition(let v): e.condition = v
            case .situation(let v): e.situation = v
            case .timing(let v): e.timing = v
            case .emotion(let v): e.emotion = v
            case .tension(let v): e.tension = v
            case .cause(let v): e.causes.insert(v)
            case .body(let v): e.body.insert(v)
            case .support(let v): e.support = v
            }
        }
        e.body = MokorinCheckIn.consistentBody(e.body)
        appendUser(options.map(\.label).joined(separator: "、"))
        let changed = checkIn.apply(e, at: Date())
        syncFromCheckIn()
        continueCheckIn(changed: changed, userText: nil)
    }

    /// この質問には答えない（スキップ）
    func skipQuestion() {
        guard !isSending, let slot = askedSlot else { return }
        pushUndo()
        appendUser("この質問はとばす")
        checkIn.declined.insert(slot)
        continueCheckIn(changed: [], userText: nil)
    }

    /// 一つ前の会話へ戻る（直前の答えを取り消し、その質問からやり直す。集めた情報・推薦も元に戻る）
    func goBack() {
        if isSending { cancelPending(silently: true) }
        guard let s = undoStack.popLast() else { return }
        messages = s.messages
        checkIn = s.checkIn
        askedSlot = s.askedSlot
        step = s.step
        selectedScene = s.selectedScene
        selectedConditions = s.selectedConditions
        hasSceneAnswer = s.hasSceneAnswer
        hasConditionAnswer = s.hasConditionAnswer
        hasTensionAnswer = s.hasTensionAnswer
        subjectiveTension = s.subjectiveTension
        situationNote = s.situationNote
        mentionedFatigue = s.mentionedFatigue
        declinedMeasurement = s.declinedMeasurement
        safetyStop = s.safetyStop
        unclearCountInStep = s.unclearCountInStep
        failedText = nil
        notice = nil
        setPose(.calm, .nod)
        MindWaveDebugLogger.log(.insight, "mokorin go back remaining=\(undoStack.count)")
    }

    /// 場面（単一選択）
    func selectScene(_ scene: ContextScene) {
        // ボタンで選び直したら、以前に話した予定の言葉（別の場面かもしれない）は使わない
        if scene != selectedScene { situationNote = nil }
        selectedScene = scene
        suggestedScene = nil
        hasSceneAnswer = true
        if step == .scene || step == .tension {
            hasTensionAnswer = true
            appendUser("場面は「\(scene.displayName)」です")
            advance(userText: nil)
        } else {
            refreshSummaryIfReviewing()
        }
    }

    /// 身体状態（複数選択。「特になし」は排他）— 既存の ContextCalibrationView と同じ規則
    func toggleCondition(_ cond: BodyCondition) {
        if !conditionsTouched && step == .condition && cond != .none {
            // 会話中の最初の選択では、既定値の「特になし」を外してその状態だけを選ぶ
            selectedConditions = []
        }
        conditionsTouched = true
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
        advance(userText: nil)
    }

    /// 編集画面で場面を選ぶ（会話には発言を追加しない。「完了」で確認へ進む）
    func editScene(_ scene: ContextScene) {
        if scene != selectedScene { situationNote = nil }
        selectedScene = scene
        suggestedScene = nil
    }

    /// 編集画面で身体状態を切り替える（「特になし」の排他は既存の規則と同じ。会話には発言を追加しない）
    func editCondition(_ cond: BodyCondition) {
        conditionsTouched = true
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
    }

    /// 編集画面（場面・身体状態の一覧）で選び終えたとき。内容を回答済みにして確認へ進む
    func finishManualEdit() {
        failedText = nil
        unclearCountInStep = 0
        hasTensionAnswer = true
        hasSceneAnswer = true
        hasConditionAnswer = true
        suggestedScene = nil
        suggestedConditions = []
        if step != .review {
            step = .review
            appendMokorin(MokorinScript.summary(scene: selectedScene, conditions: selectedConditions), origin: .fixed)
            setPose(.happy, .nod)
        } else {
            refreshSummaryIfReviewing()
        }
    }

    // MARK: - 操作（文章・音声）

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
        failedText = nil
        Task { await perform(text) }
    }

    /// 文章（音声認識の結果を含む）を送り、もこりんの返答が表示されるまで待つ
    func submit(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !text.isEmpty else { return }
        isSending = true
        failedText = nil
        await perform(text)
    }

    /// 外部AIに届かなかった発言を送り直す（利用者の操作でだけ。自動では再送しない）
    func retryFailed() async {
        guard !isSending, let text = failedText else { return }
        failedText = nil
        isSending = true
        await requestReply(for: text)
    }

    /// 外部AIを使わずに、届かなかった発言を端末内の判定で処理して会話を続ける
    func continueWithoutAI() {
        guard !isSending, let text = failedText else { return }
        failedText = nil
        notice = nil
        replyLocally(to: text, previous: step)
    }

    /// 送信中の要求を取り消す（届いた応答は破棄し、送った発言も会話から外す）
    func cancelPending(silently: Bool = false) {
        guard isSending else { return }
        activeRequestID = nil
        isSending = false
        if let last = messages.last, last.speaker == .user { messages.removeLast() }
        if !undoStack.isEmpty, !silently { undoStack.removeLast() }
        if !silently { notice = "送信を取り消したよ。" }
        MindWaveDebugLogger.log(.insight, "mokorin request cancelled")
    }

    /// 会話をやり直す（選択も最初の状態に戻す）
    func restart() {
        messages = []
        draft = ""
        notice = nil
        isSending = false
        selectedScene = initialContext.scene
        selectedConditions = initialContext.conditions.isEmpty ? [.none] : initialContext.conditions
        suggestedScene = nil
        suggestedConditions = []
        hasSceneAnswer = isInAppEdit
        hasConditionAnswer = isInAppEdit
        hasTensionAnswer = false
        subjectiveTension = nil
        conditionsTouched = false
        tensionRetries = 0
        failedText = nil
        unclearCountInStep = 0
        situationNote = nil
        mentionedFatigue = false
        declinedMeasurement = false
        checkIn = MokorinCheckIn()
        askedSlot = nil
        safetyStop = false
        undoStack = []
        activeRequestID = nil
        conversationId = UUID()
        start()
        MindWaveDebugLogger.log(.insight, "mokorin restart")
    }

    /// 読み上げ中の口の動き
    func setSpeaking(_ speaking: Bool) {
        guard pose.speaking != speaking else { return }
        var next = pose
        next.speaking = speaking
        pose = next
    }

    // MARK: - 内部

    private func start() {
        // あいさつ（緊張していると決めつけない）＋最初の質問（STEP 1）。自由に話しても、選択肢で答えてもよい
        askedSlot = checkIn.nextSlot()
        if let slot = askedSlot { checkIn.asked.append(slot) }
        step = stepFor(askedSlot)
        let greeting = isInAppEdit ? MokorinScript.greetingForEdit(current: initialContext) : MokorinScript.greeting
        appendMokorin([greeting, askedSlot?.question].compactMap { $0 }.joined(separator: "\n"), origin: .fixed)
        setPose(MokorinExpressionRules.greeting.0, MokorinExpressionRules.greeting.1)
    }

    /// 尋ねている項目から、画面の段階（互換用）を決める
    private func stepFor(_ slot: CheckInSlot?) -> Step {
        guard let slot else { return checkIn.isReadyToSuggest ? .review : .tension }
        switch slot {
        case .sleep, .activity, .condition, .body: return .condition
        case .situation, .timing: return .scene
        case .emotion, .tension, .cause, .support: return .tension
        }
    }

    private func pushUndo() {
        undoStack.append(Snapshot(messages: messages, checkIn: checkIn, askedSlot: askedSlot, step: step,
                                  selectedScene: selectedScene, selectedConditions: selectedConditions,
                                  hasSceneAnswer: hasSceneAnswer, hasConditionAnswer: hasConditionAnswer,
                                  hasTensionAnswer: hasTensionAnswer, subjectiveTension: subjectiveTension,
                                  situationNote: situationNote, mentionedFatigue: mentionedFatigue,
                                  declinedMeasurement: declinedMeasurement, safetyStop: safetyStop,
                                  unclearCountInStep: unclearCountInStep))
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    /// 会話の情報を、既存の場面・身体状態・主観的な緊張（互換）へ反映する
    private func syncFromCheckIn() {
        if let s = checkIn.situation?.value {
            selectedScene = s.contextScene
            suggestedScene = s.contextScene
            hasSceneAnswer = true
            if let note = checkIn.situationNote { situationNote = note }
        }
        let ctx = checkIn.measurementContext(base: MeasurementContext(scene: selectedScene, conditions: [.none]))
        if ctx.conditions != [.none] {
            selectedConditions = ctx.conditions
            suggestedConditions = ctx.conditions
            conditionsTouched = true
        }
        if checkIn.isSettled(.body) || checkIn.isSettled(.condition) || checkIn.isSettled(.activity) { hasConditionAnswer = true }
        if let t = checkIn.tension?.value {
            subjectiveTension = t < 10 ? .calm : (t < 62 ? .slight : .high)
            hasTensionAnswer = true
        }
        if checkIn.condition?.value.isTired == true { mentionedFatigue = true }
    }

    /// 発言・選択のあと: 反応 → 次の質問、またはまとめ（端末内の定型文）
    private func continueCheckIn(changed: Set<CheckInSlot>, userText: String?) {
        let wasAsked = askedSlot
        // 尋ねた項目に答えがなかった: 1 回だけ聞き直し、2 回目はとばす（同じ質問を繰り返さない）
        if let slot = wasAsked, !changed.contains(slot), !checkIn.isSettled(slot) {
            if unclearCountInStep == 0 {
                unclearCountInStep = 1
                appendMokorin(MokorinScript.checkInClarify(slot, gotOther: !changed.isEmpty), origin: .fixed)
                setPose(.calm, .nod)
                return
            }
            checkIn.declined.insert(slot)
        }
        unclearCountInStep = 0
        let reaction = MokorinScript.checkInReaction(changed: changed, checkIn: checkIn, turn: undoStack.count)
        askedSlot = checkIn.nextSlot()
        if let slot = askedSlot {
            checkIn.asked.append(slot)
            step = stepFor(slot)
            appendMokorin([reaction, slot.question].compactMap { $0 }.joined(separator: "\n"), origin: .fixed)
            setPose(checkIn.condition?.value.isTired == true ? .sleepy : .calm, .nod)
        } else {
            markReadyWithCurrentSelection()
            step = .review
            // まとめは「教えてくれてありがとう。」で始まるため、一般的な相づちは重ねない（具体的な反応だけ添える）
            let specific = reaction.flatMap { MokorinScript.genericAcks.contains($0) ? nil : $0 }
            appendMokorin([specific, MokorinScript.checkInSummary(checkIn, recommendations: recommendations)].compactMap { $0 }.joined(separator: "\n"), origin: .fixed)
            setPose(checkIn.needsRestFirst ? .sad : .happy, .nod)
        }
    }

    private func setPose(_ emotion: MokorinEmotion, _ action: MokorinAction?) {
        pose = pose.with(emotion, action)
    }

    private func computeStep() -> Step {
        if !hasTensionAnswer { return .tension }
        if !hasSceneAnswer { return .scene }
        if !hasConditionAnswer { return .condition }
        return .review
    }

    /// 緊張の段階での発言を処理する（はっきりしない答えは1回だけ聞き直し、2回目は先へ進む）
    private func handleTensionAnswer(tension: SubjectiveTension?, otherInfo: Bool) {
        guard step == .tension else { return }
        if let tension { subjectiveTension = tension }
        if tension != nil || otherInfo || tensionRetries >= 1 {
            hasTensionAnswer = true
        } else {
            tensionRetries += 1
        }
    }

    private func perform(_ rawText: String) async {
        let text = String(rawText.prefix(ContextAssistLimits.maxUserChars))
        pushUndo()
        appendUser(text)
        notice = nil
        if MokorinAdviceEngine.mentionsFatigue(text) { mentionedFatigue = true }
        declinedMeasurement = false
        // 深刻な体の症状の言葉は外部AIへ送らず、端末内で相談を案内する（改善の推薦は止める）
        if MokorinAdviceEngine.mentionsSeriousSymptom(text) {
            safetyStop = true
            askedSlot = nil
            step = .review
            appendMokorin(MokorinAdviceEngine.seekHelpMessage, origin: .fixed)
            setPose(.sad, .nod)
            isSending = false
            return
        }
        if usesRemoteAI {
            await requestReply(for: text)
        } else {
            // 外部AIを使わない設定（未同意・サーバー未設定）: 端末内の定型文で応答（画面に「端末内の定型文」と表示）
            replyLocally(to: text, previous: step)
            isSending = false
        }
    }

    /// 外部AIへ送る（直前に追加した利用者の発言を含む会話履歴）
    private func requestReply(for text: String) async {
        guard let configuration = configurationProvider() else {
            replyLocally(to: text, previous: step)
            isSending = false
            return
        }
        let conversation = conversationId
        let requestID = UUID()
        activeRequestID = requestID
        let previous = step
        let request = makeRequest()
        do {
            let response = try await clientFactory(configuration).send(request)
            // やり直し・取り消しの後に届いた応答は破棄する
            guard conversation == conversationId, activeRequestID == requestID else { return }
            // 候補の検証（未知の値は throw → 下の catch で失敗として扱う）を済ませてから要求を完了にする
            let candidates = try response.result.typedCandidates()
            activeRequestID = nil
            let askedBefore = askedSlot
            // 会話の情報: AI の抽出（あれば）を優先し、端末内の抽出で補う（どちらも本人の発言から）
            var extraction = CheckInExtractor.extract(text, asked: askedBefore)
            if let ai = response.result.checkIn { extraction = ai.merged(over: extraction) }
            let checkInChanged = checkIn.apply(extraction, at: Date())
            syncFromCheckIn()
            let changed = applyCandidates(scene: candidates.scene, conditions: candidates.conditions) || !checkInChanged.isEmpty
            handleTensionAnswer(tension: response.result.typedTension, otherInfo: changed)
            if let note = response.result.situationNote.flatMap(MokorinSessionMemory.clippedNote) {
                situationNote = note
            } else if candidates.scene != nil {
                situationNote = MokorinSessionMemory.clippedNote(text)
            }
            let intent = response.result.typedIntent
            if intent == .declineMeasurement { declinedMeasurement = true }
            if intent == .ready { markReadyWithCurrentSelection(); askedSlot = nil }
            if intent != .ready {
                if let slot = askedBefore, !checkInChanged.contains(slot), intent == .answer { checkIn.declined.insert(slot) }
                askedSlot = checkIn.nextSlot()
                if let slot = askedSlot { checkIn.asked.append(slot) }
            }
            step = intent == .ready || askedSlot == nil ? .review : stepFor(askedSlot)
            unclearCountInStep = (step == previous && !changed && response.result.typedTension == nil) ? unclearCountInStep + 1 : 0
            let origin: Origin = response.isStub ? .stub(model: response.model) : .openAI(model: response.model)
            var reply = response.result.reply
            if response.result.needsClarification, let q = response.result.clarificationQuestion, !reply.contains(q) {
                reply += "\n" + q
            }
            appendMokorin(reply, origin: origin)
            // 外部AIが選んだ表情・動作（不正な値は calm / nod）。返答文は固定文で上書きしない
            let expression = response.result.typedExpression
            setPose(expression.emotion, expression.action)
            // 返答に次の質問・確認が含まれない場合は、段階に合わせた定型の質問を添える（会話が止まらないように）
            let asksSomething = reply.contains("？") || reply.contains("?")
            switch declinedMeasurement ? nil : step {
            case .review? where !reply.contains("測定") && !reply.contains("やってみ"):
                appendMokorin(MokorinScript.checkInSummary(checkIn, recommendations: recommendations), origin: .fixed)
            case _? where !asksSomething:
                if let slot = askedSlot { appendMokorin(slot.question, origin: .fixed) }
            default:
                break
            }
            MindWaveDebugLogger.log(.insight, "mokorin remote provider=\(response.provider) step=\(step) scene=\(candidates.scene != nil) conditions=\(candidates.conditions.count) tension=\(response.result.typedTension != nil)")
            isSending = false
        } catch {
            guard conversation == conversationId, activeRequestID == requestID else { return }
            activeRequestID = nil
            let clientError = error as? InsightClientError
            // 黙って端末内の判定に切り替えず、利用者に「もう一度送る」か「AIなしで続ける」を選んでもらう
            failedText = text
            notice = "うまくつながらなかったよ（\(clientError?.chatUserMessage ?? "不明なエラー")）"
            setPose(.sad, .nod)
            MindWaveDebugLogger.log(.insight, "mokorin remote failed reason=\(clientError?.logCode ?? "unknown_error")")
            isSending = false
        }
    }

    /// 端末内の判定で応答する（外部AIを使わないとき・利用者が「AIなしで続ける」を選んだとき）
    private func replyLocally(to text: String, previous: Step) {
        let intent = MokorinKeywordInterpreter.interpretIntent(text)
        if intent == .declineMeasurement {
            // 説得しない。選択はそのまま残し、「測定しないで終える」を出す
            declinedMeasurement = true
            appendMokorin(MokorinScript.declineAck, origin: .fixed)
            setPose(.calm, .nod)
            return
        }
        let extraction = CheckInExtractor.extract(text, asked: askedSlot)
        let changed = checkIn.apply(extraction, at: Date())
        syncFromCheckIn()
        if intent == .question && changed.isEmpty {
            // 質問・雑談には答えられないことを正直に伝え、今の質問に戻る（同じ項目のまま）
            let again = askedSlot?.question
            appendMokorin([MokorinScript.cannotAnswerLocally(canEnableAI: isServerConfigured && !isTextConsented), again].compactMap { $0 }.joined(separator: "\n"), origin: .fixed)
            setPose(.calm, .nod)
            return
        }
        if intent == .ready {
            markReadyWithCurrentSelection()
            askedSlot = nil
            step = .review
            appendMokorin(MokorinScript.checkInSummary(checkIn, recommendations: recommendations), origin: .fixed)
            setPose(.happy, .nod)
            return
        }
        continueCheckIn(changed: changed, userText: text)
        MindWaveDebugLogger.log(.insight, "mokorin local step=\(step) changed=\(changed.count) next=\(askedSlot?.rawValue ?? "none")")
    }

    /// 候補を「提案」として選択に反映する（利用者は画面で変更できる）。何か反映したら true
    @discardableResult
    private func applyCandidates(scene: ContextScene?, conditions: Set<BodyCondition>) -> Bool {
        var changed = false
        if let scene {
            selectedScene = scene
            suggestedScene = scene
            hasSceneAnswer = true
            changed = true
        }
        if !conditions.isEmpty {
            selectedConditions = conditions
            suggestedConditions = conditions
            hasConditionAnswer = true
            conditionsTouched = true
            changed = true
        }
        return changed
    }

    /// 段階を進め、定型文で次の質問または確認を出し、表情を決める
    private func advance(userText: String?, clarifyIfUnchanged: Bool = false, tensionJustAnswered: Bool = false) {
        let previous = step
        step = computeStep()
        switch step {
        case .tension:
            appendMokorin(MokorinScript.askTensionAgain, origin: .fixed)
        case .scene:
            let unknownReason = tensionJustAnswered && subjectiveTension != .calm && (userText?.contains("わから") ?? false)
            appendMokorin(previous == .scene && clarifyIfUnchanged ? MokorinScript.askScene
                          : unknownReason ? MokorinScript.askSceneUnknownReason
                          : MokorinScript.askScene(after: tensionJustAnswered ? subjectiveTension : nil), origin: .fixed)
        case .condition:
            appendMokorin(previous == .condition && clarifyIfUnchanged ? MokorinScript.askConditionAgain
                                                                       : MokorinScript.askCondition(topic: topic, fatigue: mentionedFatigue), origin: .fixed)
        case .review:
            appendMokorin(MokorinScript.summary(topic: topic, conditions: selectedConditions), origin: .fixed)
        }
        let e = MokorinExpressionRules.forReply(step: step, userText: userText, conditions: selectedConditions,
                                                tension: tensionJustAnswered ? subjectiveTension : nil)
        setPose(e.0, e.1)
    }

    /// 「もう測りたい」: 未確認の項目は聞かずに、今の選択のまとめへ進む（まとめで本人が確認・変更できる）
    private func markReadyWithCurrentSelection() {
        hasTensionAnswer = true
        hasSceneAnswer = true
        hasConditionAnswer = true
    }

    /// 確認段階で選択を変えたら、まとめを更新する（直前のまとめを置き換え、会話を増やしすぎない）
    private func refreshSummaryIfReviewing() {
        guard step == .review else { return }
        let summary = MokorinScript.summary(topic: topic, conditions: selectedConditions)
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
                conditions: hasConditionAnswer ? BodyCondition.allCases.filter { selectedConditions.contains($0) }.map(\.rawValue) : [],
                tension: subjectiveTension?.rawValue,
                checkIn: ContextAssistCheckInDTO(checkIn),
                nextSlot: askedSlot?.rawValue
            )
        )
    }

    #if DEBUG
    /// レイアウト確認用（DEBUG のみ）: もこりんの発言を表示に追加する（段階・選択は変えない）
    func debugAppendMokorinMessage(_ text: String) {
        appendMokorin(text, origin: .fixed)
    }
    #endif

    private func appendUser(_ text: String) {
        messages.append(Message(speaker: .user, text: text, origin: .user))
    }

    private func appendMokorin(_ text: String, origin: Origin) {
        messages.append(Message(speaker: .mokorin, text: text, origin: origin))
    }
}
