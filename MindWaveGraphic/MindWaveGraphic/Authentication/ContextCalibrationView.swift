// ContextCalibrationView.swift
// Authentication
//
// 測定前コンテキスト選択画面。
// 場面カテゴリ（単一）と身体状態（複数）を選んでスコア補正に活かす。
// 「あとで選ぶ」でスキップしてデフォルトコンテキストのままmainAppへ進める。
//
// 2026-10-28: もこりんとの会話で状況を整理できるようにした（Mokorin/、docs/MOKORIN_CONTEXT_INTEGRATION.md）。
// 2026-10-28 改訂: もこりん中心の音声対話型 UI に変更（docs/MOKORIN_VOICE_UI.md）。
// - 画面中央に大きなもこりん、その下に最新の会話と選択肢、下部にマイク・文字入力。確定したら測定ボタン
// - 場面・身体状態の一覧（既存のボタン UI）はシートにまとめ、必要なときだけ「一覧から選ぶ」で開く（機能は削除していない）
// 2026-11-04 改訂: 常設の「選択を編集」「履歴」・説明文・要約行を削除。訂正は会話で、履歴は吹き出しの長押しから
// - 会話・選択の状態は MokorinContextViewModel、音声は MokorinVoiceController が持つ（この View は表示と既存の確定処理だけ）
// - 既存の「特になし」の排他・applyAndProceed()・「あとで選ぶ」「変更しない」はそのまま
// - 測定は利用者が「この状況で測定する」を押したときだけ始まる

import SwiftUI

// MARK: - ContextCalibrationView

struct ContextCalibrationView: View {

    @ObservedObject var flowState: AppFlowState

    /// メインアプリ内（共通メニュー「対話（状況確認）」）から開いた場合の完了コールバック。
    /// nil のときは従来どおり認証フローの一部として mainApp へ進む。
    /// 指定時は計測ViewModelを作り直さないよう authStatus を変更せず、呼び出し元がモーダルを閉じる。
    var onComplete: (() -> Void)? = nil

    /// メインアプリ内から開いたか
    private var isInAppEdit: Bool { onComplete != nil }

    /// もこりんとの会話と、場面・身体状態の選択状態
    @StateObject private var mokorin: MokorinContextViewModel
    /// 音声入力・読み上げ（1ターンずつ）
    @StateObject private var voice = MokorinVoiceController.makeForApp()
    @FocusState private var isInputFocused: Bool
    @State private var isEditing = false
    @State private var isHistoryPresented = false
    /// 「ほかの答え・答えない」（今の質問の全部の選択肢。複数選べる項目はまとめて決定）
    @State private var isAllOptionsPresented = false
    @State private var multiSelection: Set<CheckInOption> = []
    /// 読み上げ済みの最後のもこりんの発言（同じ発言を二度読まない）
    @State private var lastSpokenMessageID: UUID? = nil
    @Environment(\.scenePhase) private var scenePhase

    private let accent = Color(red: 0.35, green: 0.75, blue: 0.95)

    init(flowState: AppFlowState, onComplete: (() -> Void)? = nil) {
        self._flowState = ObservedObject(wrappedValue: flowState)
        self.onComplete = onComplete
        // メインアプリ内から開いた場合は現在の状況を初期表示する
        self._mokorin = StateObject(wrappedValue: MokorinContextViewModel(
            initialContext: flowState.measurementContext,
            isInAppEdit: onComplete != nil
        ))
    }

    private var selectedScene: ContextScene { mokorin.selectedScene }
    private var selectedConditions: Set<BodyCondition> { mokorin.selectedConditions }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                LaunchStarfieldBG()
                    .opacity(0.55)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    header
                        .padding(.top, 8)
                    // もこりんの位置は返答の長さで動かさない（会話は下の領域でスクロール）。2026-11-11 改善資料 1 ページ
                    characterStage(size: characterSize(for: geo.size.height))
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            conversationArea.id("conversation")
                        }
                        .onChange(of: mokorin.messages.count) { _, _ in proxy.scrollTo("conversation", anchor: .top) }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, 20)
                .frame(width: geo.size.width)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
        .sheet(isPresented: $isEditing) { editSheet }
        .sheet(isPresented: $isHistoryPresented) { historySheet }
        .sheet(isPresented: $isAllOptionsPresented) { allOptionsSheet }
        .onAppear { connectVoice() }
        .onDisappear { voice.cancelAll() }
        // VoiceOver: 録音の開始と、音声入力の問題（原因ごとの文言）を読み上げで知らせる
        .onChange(of: voice.isListening) { _, listening in
            if listening { AccessibilityNotification.Announcement("聞いています。話し終えたら少し待つと送信します").post() }
        }
        .onChange(of: voice.problem) { _, problem in
            if let problem { AccessibilityNotification.Announcement(problem).post() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voice.cancelAll() }   // 背面に回ったら録音・読み上げを止める
        }
        .onChange(of: mokorin.messages.count) { _, _ in speakPendingReply() }
        .onChange(of: mokorin.isSending) { _, sending in if !sending { speakPendingReply() } }
        #if DEBUG
        .task { await runMokorinDebugHooks() }
        #endif
    }

    // MARK: - Header（必要最低限）

    private var header: some View {
        VStack(spacing: 6) {
            // 一つ前の会話へ戻る（左上）。履歴へ移らずに、直前の答えをその場でやり直す。戻れないときも場所は確保して位置を動かさない
            HStack {
                Button { voice.cancelAll(); mokorin.goBack() } label: {
                    Label("一つ前の会話へ戻る", systemImage: "chevron.left")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .opacity(mokorin.canGoBack ? 1 : 0)
                .disabled(!mokorin.canGoBack)
                .accessibilityHidden(!mokorin.canGoBack)
                .accessibilityHint("直前の答えを取り消して、ひとつ前の質問に戻ります")
                .accessibilityIdentifier("mokorin_go_back")
                Spacer()
            }
            // 操作の説明は置かず、もこりんの問いかけそのものを案内にする
            Text("今の状況を教えてください")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - 中央のもこりん

    private func characterSize(for height: CGFloat) -> CGFloat {
        if isInputFocused { return 110 }            // キーボード表示中は小さくして入力欄と会話を見えるようにする
        return min(240, max(150, height * 0.27))   // 小さい iPhone でも会話と選択肢が収まる大きさ
    }

    private func characterStage(size: CGFloat) -> some View {
        // もこりん本体の大きさだけでレイアウトし、光の演出は背景に置く（画面幅より広い光で全体が押し広げられないように）
        MokorinAvatarView(size: size, pose: displayedPose)
            .frame(maxWidth: .infinity)
            .frame(height: size * 1.05)
            .background {
                ZStack {
                    // 惑星の地平線のような青い光（完成イメージを参考にした演出。静止）
                    Ellipse()
                        .stroke(LinearGradient(colors: [.clear, accent.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1.2)
                        .frame(width: size * 2.2, height: size * 0.5)
                        .offset(y: size * 0.32)
                    RadialGradient(colors: [accent.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: size * 0.75)
                        .frame(width: size * 1.6, height: size * 1.1)
                        .offset(y: size * 0.1)
                }
                .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.25), value: size)
            .allowsHitTesting(false)
    }

    /// もこりんの状態（Idle / Listening / Thinking / Speaking / Error）を1つにまとめる
    private enum Activity { case idle, listening, thinking, speaking, error }

    private var activity: Activity {
        if voice.isListening || voice.state == .preparing { return .listening }
        if mokorin.isSending || voice.state == .processing { return .thinking }
        if voice.state == .speaking { return .speaking }
        if mokorin.failedText != nil || voice.problem != nil { return .error }
        return .idle
    }

    /// 表情・動作（会話の内容）に、聞き取り中・考え中の見た目を重ねる。読み上げ中の口は pose.speaking
    private var displayedPose: MokorinPose {
        var p = mokorin.pose
        switch activity {
        case .listening: p.activity = .listening
        case .thinking:  p.activity = .thinking
        default:         p.activity = .idle
        }
        return p
    }

    // MARK: - 会話（最新の発言・選択肢）

    private var conversationArea: some View {
        VStack(spacing: 10) {
            voiceStatus
            if let turn = mokorin.currentTurn {
                mokorinBubble(turn)
            }
            userEcho
            aiConsentPrompt
            quickReplies
            if let notice = voice.problem ?? mokorin.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mokorin_notice")
            }
        }
    }

    /// AI と話すための同意（サーバーが設定済みで未同意のときだけ）。小さなリンクにせず、会話のすぐ下に出す
    @ViewBuilder
    private var aiConsentPrompt: some View {
        if mokorin.isServerConfigured && !mokorin.isTextConsented && mokorin.failedText == nil {
            HStack(spacing: 10) {
                Text("AIと話すと、自由な言葉で答えられます。送るのは入力・話した文章だけで、計測データは送りません。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button("AIと話す") { mokorin.setTextConsent(true) }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(accent))
                    .buttonStyle(.plain)
                    .accessibilityHint("入力した文章だけをサーバー経由で OpenAI へ送ります。計測データは送りません")
                    .accessibilityIdentifier("mokorin_consent_accept")
            }
        }
    }

    private func mokorinBubble(_ message: MokorinContextViewModel.Turn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.text)
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(originLabel(message.origin) + (message.hasFixedFollowUp ? "・質問の一部は端末内の定型文" : ""))
                .font(.system(size: 9))
                .foregroundStyle(isStub(message.origin) ? Color.orange.opacity(0.9) : Color.white.opacity(0.3))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(isStub(message.origin) ? Color.orange.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1))
        )
        // 会話の履歴・やり直しは常設ボタンにせず、吹き出しの長押し（VoiceOver ではアクション）から
        .contextMenu {
            if mokorin.messages.count > 1 {
                Button("これまでの会話を見る", systemImage: "text.bubble") { isHistoryPresented = true }
                Button("最初からやり直す", systemImage: "arrow.counterclockwise") { voice.cancelAll(); mokorin.restart() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("もこりん（\(originLabel(message.origin))）：\(message.text)")
        .accessibilityAction(named: "これまでの会話を見る") { isHistoryPresented = true }
        .accessibilityAction(named: "最初からやり直す") { voice.cancelAll(); mokorin.restart() }
        .accessibilityIdentifier("mokorin_latest_message")
        .animation(.easeInOut(duration: 0.2), value: message.id)
    }

    private func originLabel(_ origin: MokorinContextViewModel.Origin) -> String {
        switch origin {
        case .openAI(let model): return "OpenAI（\(model)）"
        case .stub(let model):   return "スタブ応答（\(model)）・実際のAIではありません"
        case .fixed:             return "端末内の定型文"
        case .user:              return ""
        }
    }

    private func isStub(_ origin: MokorinContextViewModel.Origin) -> Bool {
        if case .stub = origin { return true }
        return false
    }

    /// 自分の最後の発言（音声の場合は認識結果の確認になる）。録音中は途中の認識結果
    @ViewBuilder
    private var userEcho: some View {
        let text: String? = voice.isListening
            ? (voice.partialTranscript.isEmpty ? "聞いています…" : voice.partialTranscript)
            : mokorin.latestUserMessage?.text
        if let text, mokorin.messages.count > 1 || voice.isListening {
            HStack {
                Spacer(minLength: 40)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(voice.isListening ? 0.7 : 0.6))
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(accent.opacity(voice.isListening ? 0.25 : 0.14)))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(voice.isListening ? "認識中：\(text)" : "あなた：\(text)")
        }
    }

    /// 状態の表示は1行だけ（待機中は表示しない。エラーは下の小さな文で伝える）
    @ViewBuilder
    private var voiceStatus: some View {
        switch activity {
        case .listening where voice.state == .preparing:
            statusPill("マイクを準備しています", icon: "mic", color: accent)
        case .listening: statusPill("聞いています", icon: "waveform", color: .red)
        case .thinking:  statusPill("考え中…", icon: "ellipsis", color: accent)
        case .speaking:  statusPill("話しています（マイクで止められます）", icon: "speaker.wave.2.fill", color: accent)
        case .idle, .error: EmptyView()
        }
    }

    private func statusPill(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11))
            .foregroundStyle(color.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .accessibilityIdentifier("mokorin_voice_status")
    }

    /// 段階に応じた選択肢（タップでも会話が進む）
    @ViewBuilder
    private var quickReplies: some View {
        let replies = mokorin.quickReplies
        if !replies.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(replies, id: \.self) { reply in
                    let selected = mokorin.isSelected(reply)
                    let isConfirm = reply == .confirmConditions || reply == .retry
                    Button {
                        switch reply {
                        case .showList:        isEditing = true
                        case .skipMeasurement: skipCalibration()
                        default:               mokorin.tap(reply)
                        }
                    } label: {
                        Text(reply.label)
                            .font(.system(size: 13, weight: isConfirm ? .semibold : .regular))
                            .foregroundStyle(selected || isConfirm ? Color.black : Color.white.opacity(0.88))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(selected || isConfirm ? accent : Color.white.opacity(0.05))
                            )
                            .overlay(Capsule().strokeBorder(Color.white.opacity(selected || isConfirm ? 0 : 0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(mokorin.isSending || voice.isListening)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("mokorin_reply_\(reply.label)")
                }
            }
        }
        // ほかの答え（全部の選択肢）・この質問はとばす
        if let slot = mokorin.askedSlot, mokorin.step != .review, mokorin.failedText == nil, !mokorin.declinedMeasurement {
            Button {
                multiSelection = []
                isAllOptionsPresented = true
            } label: {
                Text(slot.allowsMultiple ? "ほかの答え・複数選ぶ・答えない" : "ほかの答え・答えない")
                    .font(.system(size: 12))
                    .foregroundStyle(accent.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(mokorin.isSending || voice.isListening)
            .accessibilityIdentifier("mokorin_all_options")
        }
    }

    /// 今の質問の全部の選択肢（音声・文字でも答えられる。ここは補助）
    private var allOptionsSheet: some View {
        NavigationStack {
            List {
                if let slot = mokorin.askedSlot {
                    Section(slot.question) {
                        ForEach(slot.options, id: \.self) { option in
                            Button {
                                if slot.allowsMultiple {
                                    if multiSelection.contains(option) { multiSelection.remove(option) } else { multiSelection.insert(option) }
                                } else {
                                    isAllOptionsPresented = false
                                    mokorin.answer(options: [option])
                                }
                            } label: {
                                HStack {
                                    Text(option.label).foregroundStyle(.primary)
                                    Spacer()
                                    if multiSelection.contains(option) { Image(systemName: "checkmark").foregroundStyle(accent) }
                                }
                            }
                            .accessibilityAddTraits(multiSelection.contains(option) ? .isSelected : [])
                        }
                    }
                    Section {
                        Button("この質問は答えない") {
                            isAllOptionsPresented = false
                            mokorin.skipQuestion()
                        }
                        .accessibilityIdentifier("mokorin_skip_question")
                    }
                }
            }
            .navigationTitle("ほかの答え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { isAllOptionsPresented = false } }
                if mokorin.askedSlot?.allowsMultiple == true {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("決定") {
                            isAllOptionsPresented = false
                            mokorin.answer(options: Array(multiSelection))
                        }
                        .disabled(multiSelection.isEmpty)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    // MARK: - 下部（測定ボタン・マイク・文字入力）

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if mokorin.step == .review && mokorin.failedText == nil {
                // 測定する内容は、もこりんの確認の発言に含まれる（同じ内容を別の場所に重ねて表示しない）
                measureButton
            }
            inputRow
            footerRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.92).ignoresSafeArea(edges: .bottom))
    }

    private var measureButton: some View {
        Button {
            voice.cancelAll()
            applyAndProceed()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 15))
                Text("この状況で測定する")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(accent)
                    .shadow(color: accent.opacity(0.35), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("context_primary_start_button")
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            micButton
            HStack(spacing: 6) {
                TextField("メッセージを入力", text: $mokorin.draft, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($isInputFocused)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white)
                    .submitLabel(.send)
                    .onSubmit { mokorin.send() }
                    .onChange(of: mokorin.draft) { _, v in
                        if v.count > ContextAssistLimits.maxUserChars { mokorin.draft = String(v.prefix(ContextAssistLimits.maxUserChars)) }
                    }
                    .disabled(voice.isListening)
                    .accessibilityLabel("もこりんへの返答")
                    .accessibilityIdentifier("mokorin_input_field")
                Button {
                    mokorin.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(mokorin.canSend ? accent : Color.white.opacity(0.18))
                }
                .buttonStyle(.plain)
                .disabled(!mokorin.canSend)
                .accessibilityLabel("送信")
                .accessibilityIdentifier("mokorin_send_button")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
    }

    private var micButton: some View {
        // マイクが主要操作。状態に応じて 録音開始 / 録音を終えて送る / 送信の取り消し / 読み上げを止めて話す
        let listening = voice.isListening
        let thinking = activity == .thinking
        let icon: String = {
            if listening { return "stop.fill" }
            if thinking { return "xmark" }
            return "mic.fill"
        }()
        return Button {
            if thinking {
                mokorin.cancelPending()
                voice.cancelAll()
            } else {
                Task { await voice.micTapped() }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(listening ? Color.red.opacity(0.85) : accent.opacity(0.18))
                    .overlay(Circle().strokeBorder(listening ? Color.clear : accent.opacity(0.6), lineWidth: 1))
                if thinking {
                    ProgressView().tint(accent).scaleEffect(1.3)
                    Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(listening ? Color.white : accent)
                }
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .disabled(voice.state == .preparing)
        .accessibilityLabel(listening ? "録音を終えて送る" : thinking ? "送信を取り消す" : (voice.state == .speaking ? "読み上げを止めて話す" : "声で答える"))
        .accessibilityHint(thinking ? "もこりんへの送信を取り消します" : "押すと録音を始めます。話し終えると自動で送信します")
        .accessibilityIdentifier("mokorin_mic_button")
    }

    private var footerRow: some View {
        HStack(spacing: 16) {
            Button(isInAppEdit ? "変更しない" : "あとで選ぶ") { skipCalibration() }
            .accessibilityIdentifier("context_skip_button")
            Spacer()
            Button {
                voice.speaksReplies.toggle()
                if !voice.speaksReplies { voice.stopSpeaking() }
            } label: {
                Image(systemName: voice.speaksReplies ? "speaker.wave.2" : "speaker.slash")
            }
            .accessibilityLabel(voice.speaksReplies ? "読み上げをオフにする" : "読み上げをオンにする")
            .accessibilityIdentifier("mokorin_speaker_toggle")
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.white.opacity(0.45))
        .buttonStyle(.plain)
    }

    // MARK: - 音声

    private func connectVoice() {
        voice.onUtterance = { text in await mokorin.submit(text) }
        voice.onSpeakingChanged = { speaking in mokorin.setSpeaking(speaking) }
    }

    /// 直前の利用者の発言のあとに、もこりんが話した内容をまとめて読み上げる（ON のとき・1回だけ）
    private func speakPendingReply() {
        guard voice.speaksReplies, !mokorin.isSending else { return }
        guard let lastUserIndex = mokorin.messages.lastIndex(where: { $0.speaker == .user }) else { return }
        let replies = mokorin.messages[(lastUserIndex + 1)...].filter { $0.speaker == .mokorin }
        guard let last = replies.last, last.id != lastSpokenMessageID else { return }
        lastSpokenMessageID = last.id
        voice.speakReply(replies.map(\.text).joined(separator: "\n"))
    }

    // MARK: - 選択を編集（既存の場面・身体状態の一覧）

    private var editSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        sceneSection
                        bodySection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("場面と身体状態")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        mokorin.finishManualEdit()
                        isEditing = false
                    }
                    .accessibilityIdentifier("mokorin_edit_done")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var historySheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(mokorin.messages) { message in
                            MokorinBubble(message: message, accent: accent)
                        }
                        if mokorin.messages.count > 1 {
                            Button("会話をやり直す") {
                                mokorin.restart()
                                isHistoryPresented = false
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(accent)
                            .padding(.top, 8)
                            .accessibilityIdentifier("mokorin_restart")
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("もこりんとの会話")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { isHistoryPresented = false } }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Scene Section（編集シート）

    private var sceneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("場面", hint: "ひとつ選んでください")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(ContextScene.allCases) { scene in
                    sceneCard(scene)
                }
            }
        }
    }

    private func sceneCard(_ scene: ContextScene) -> some View {
        let selected = selectedScene == scene
        return Button {
            mokorin.editScene(scene)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: scene.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.black : Color(red: 0.35, green: 0.75, blue: 0.95))
                    .frame(width: 20)
                Text(scene.displayName)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Color.black : Color.white.opacity(0.80))
                Spacer()
                if mokorin.suggestedScene == scene { suggestionBadge(onSelected: selected) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected
                          ? Color(red: 0.35, green: 0.75, blue: 0.95)
                          : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                selected
                                ? Color.clear
                                : Color.white.opacity(0.14),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
        .accessibilityIdentifier("context_scene_\(scene.rawValue)")
    }

    // MARK: - Body Section

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("身体状態", hint: "複数選択可")

            VStack(spacing: 8) {
                ForEach(BodyCondition.allCases) { cond in
                    conditionRow(cond)
                }
            }

        }
    }

    private func conditionRow(_ cond: BodyCondition) -> some View {
        let selected = selectedConditions.contains(cond)
        return Button {
            // 「特になし」の排他を含む選択規則は MokorinContextViewModel.editCondition（従来と同じ規則）
            mokorin.editCondition(cond)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cond.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected
                                     ? Color(red: 0.35, green: 0.75, blue: 0.95)
                                     : Color.white.opacity(0.38))
                    .frame(width: 22)
                Text(cond.displayName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(selected ? 0.92 : 0.55))
                Spacer()
                if mokorin.suggestedConditions.contains(cond) && selected { suggestionBadge(onSelected: false) }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected
                                     ? Color(red: 0.35, green: 0.75, blue: 0.95)
                                     : Color.white.opacity(0.18))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(selected ? 0.09 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                selected
                                ? Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.4)
                                : Color.white.opacity(0.10),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.13), value: selected)
        .accessibilityIdentifier("context_body_\(cond.rawValue)")
    }

    private func suggestionBadge(onSelected: Bool) -> some View {
        Text("提案")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(onSelected ? Color.black.opacity(0.7) : accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().strokeBorder(onSelected ? Color.black.opacity(0.4) : accent.opacity(0.6), lineWidth: 0.8))
            .accessibilityLabel("もこりんの提案")
    }

    #if DEBUG
    /// シミュレーター検証用（DEBUG のみ）: MW_CHAT_TEST_CONSENT=1|0、MW_MOKORIN_AUTOPLAY="文1||文2"（画面表示後に順番に送信）、
    /// MW_MOKORIN_AUTO_CONFIRM=1（送信後に applyAndProceed() を呼ぶ）、MW_MOKORIN_AUTO_MIC=1（マイクボタンを1回押す）
    private func runMokorinDebugHooks() async {
        let env = ProcessInfo.processInfo.environment
        if env["MW_MOKORIN_FOCUS_INPUT"] == "1" {
            // 文字入力欄にフォーカスする（キーボード表示中のレイアウト確認用）
            try? await Task.sleep(for: .seconds(1.5))
            isInputFocused = true
        }
        if env["MW_MOKORIN_TEST_LONG_REPLY"] == "1" {
            // AI の返答の上限（160 文字）に近い長い発言を表示する（レイアウト確認用。会話の状態は変えない）
            mokorin.debugAppendMokorinMessage(String(repeating: "ゆっくり深呼吸して、肩の力を抜いてみようね。", count: 7))
        }
        if env["MW_MOKORIN_TEST_SPEAK"] == "1" {
            // 実際の読み上げ（AVSpeechSynthesizer）と口の動き・状態表示の確認用
            try? await Task.sleep(for: .seconds(2))
            voice.speaksReplies = true
            if let text = mokorin.currentTurn?.text { voice.speakReply(text) }
        }
        if env["MW_MOKORIN_AUTO_MIC"] == "1" {
            // マイクボタンを1回押したのと同じ（権限の確認表示・録音開始の検証用）
            try? await Task.sleep(for: .seconds(1.5))
            await voice.micTapped()
        }
        if env["MW_CHAT_TEST_CONSENT"] == "1" { mokorin.setTextConsent(true) }
        if env["MW_CHAT_TEST_CONSENT"] == "0" { mokorin.setTextConsent(false) }
        guard let script = env["MW_MOKORIN_AUTOPLAY"], mokorin.messages.count == 1 else { return }
        for line in script.components(separatedBy: "||") where !line.isEmpty {
            try? await Task.sleep(for: .seconds(1))
            await mokorin.submit(line)
        }
        // MW_MOKORIN_AUTO_CONFIRM=1: 利用者が「この状況で測定する」を押した場合と同じ既存処理を呼ぶ（検証用）
        if env["MW_MOKORIN_AUTO_CONFIRM"] == "1" {
            // 最後の返答と「この状況で測定する」を画面で確認できるよう、少し待ってから進む
            try? await Task.sleep(for: .seconds(6))
            applyAndProceed()
        }
    }
    #endif

    // MARK: - Helpers

    private func sectionLabel(_ title: String, hint: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color(red: 0.35, green: 0.75, blue: 0.95))
                .frame(width: 2, height: 14)
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
            Text(hint)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    /// 状況を変えずに閉じる（「あとで選ぶ」「変更しない」「測定しないで終える」）
    private func skipCalibration() {
        voice.cancelAll()
        if let onComplete {
            // メインアプリ内：現在のコンテキストを変更せずに閉じる
            print("[Navigation] context edit cancelled (in-app)")
            onComplete()
            return
        }
        flowState.measurementContext = .default
        flowState.mokorinMemory = nil
        flowState.authStatus = .mainApp
        print("[Navigation] context skipped -> mainApp")
    }

    private func applyAndProceed() {
        // 利用者が確認した選択（もこりんの提案を含む）を既存の MeasurementContext として保存する
        let ctx = mokorin.measurementContext
        flowState.measurementContext = ctx
        // 会話で理解した内容（本人の言葉の要約・主観的な緊張など）は、結果の説明・提案のためにメモリにだけ置く
        flowState.mokorinMemory = mokorin.sessionMemory
        if let onComplete {
            // メインアプリ内：authStatus は mainApp のまま。MainTabView が onChange で ViewModel へ反映する
            print("[Navigation] context updated in-app: scene=\(selectedScene.rawValue)")
            onComplete()
            return
        }
        flowState.authStatus = .mainApp
        print("[Navigation] context set: scene=\(ctx.scene.rawValue) conditions=\(ctx.conditions.map(\.rawValue).sorted()) -> mainApp")
    }
}

// MARK: - LaunchStarfieldBG (shared between AccountGuidanceView and ContextCalibrationView)

/// 軽量静的星背景。ContextCalibrationとAccountGuidanceで共有できる簡略版。
struct LaunchStarfieldBG: View {
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = tl.date.timeIntervalSinceReferenceDate
                let cx = size.width  * 0.5
                let cy = size.height * 0.45
                for i in 0..<200 {
                    let s     = Double(i)
                    let sx    = sin(s * 12.9898 + 0.73) * 0.88
                    let sy    = cos(s * 78.233  + 0.31) * 0.88
                    let phase = abs(sin(s * 7.13 + 2.1)) * 0.5 + 0.5
                    let szd   = max(0.012, abs(sin(s * 43.71)) * 0.95 + 0.012)
                    var rawZ  = szd - t * 0.032 * (0.5 + phase * 0.5)
                    rawZ = rawZ.truncatingRemainder(dividingBy: 1.0)
                    if rawZ <= 0 { rawZ += 1.0 }
                    let z  = max(0.008, rawZ)
                    let sc = 1.0 / z
                    let px = sx * sc * size.width  * 0.52 + cx
                    let py = sy * sc * size.height * 0.52 + cy
                    guard px > -20, px < size.width  + 20,
                          py > -20, py < size.height + 20 else { continue }
                    let near   = max(0, 1.0 - z)
                    let radius = max(0.18, near * 1.6)
                    let op     = min(0.70, near * 1.4)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: px - radius, y: py - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(Color(red: 0.60 + near * 0.28, green: 0.78, blue: 1.0).opacity(op))
                    )
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContextCalibrationView(flowState: AppFlowState())
}
