// AIChatView.swift
// Chat
//
// AI 相談画面。「整える」タブのカード、または共通メニュー「AI相談」から
// AppNavigationManager のモーダル（AppModal.aiChat）として開く。
// 返答の出どころ（OpenAI / スタブ / 端末内の定型アドバイス）を必ず表示し、取り違えないようにする。

import SwiftUI

struct AIChatView: View {
    @ObservedObject var chat: ChatViewModel
    /// 改善方法の画面を開く（推薦のカードから。nil のときはボタンを出さない）
    var onOpenImprovement: (() -> Void)? = nil
    let onClose: () -> Void

    @State private var isResetConfirmationPresented = false
    @FocusState private var isInputFocused: Bool
    /// もこりんの表情・動作（固定の規則。返答の文章は変更しない）
    @State private var mokorinPose = MokorinPose()
    /// 音声入力（状況確認の会話と同じ仕組み。DEBUG では MW_MOKORIN_FAKE_VOICE でマイクを使わない模擬入力）
    @StateObject private var voice = MokorinVoiceController.makeForApp()
    @Environment(\.scenePhase) private var scenePhase

    private let bottomAnchorID = "chat_bottom_anchor"

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // キーボード表示中・小さい画面（iPhone SE など）で会話が始まったら、もこりんを横並びにして会話の表示を広くとる
                let compactHero = isInputFocused || geo.size.height < 560 || (!chat.messages.isEmpty && geo.size.height < 700)

                ZStack {
                    // 背景：コックピットグラフィック画面と全く同じ宇宙・星雲グラフィック
                    StarfieldGraphicView(
                                            input: GraphicInput(score: 50, confidence: 0.85, state: MindState.from(score: 50)),
                                            showsParameterOverlay: false
                                        )
                    .ignoresSafeArea()

                    // チャット文字が読みやすいようごく薄く暗めにする
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        // AIChatView.swift の VStack(spacing: 0) の先頭（mokorinHeader の上）に追加
                        HStack {
                            Button(action: onClose) {
                                HStack(spacing: 5) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("戻る")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                                .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.35), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Text("AI相談")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)

                            Spacer()

                            Button {
                                isResetConfirmationPresented = true
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(chat.messages.isEmpty ? .white.opacity(0.3) : .white)
                                    .padding(8)
                                    .background(Circle().fill(Color.white.opacity(0.10)))
                            }
                            .disabled(chat.messages.isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        statusBanner
                        // 全体UI 13・17・21: もこりんを会話の中心に大きく置く
                        mokorinHero(compact: compactHero, availableHeight: geo.size.height)
                        learnedStrip
                        messageList
                            .frame(maxHeight: .infinity)
                        quickReplyRow
                        inputBar
                    }
                }
            }
            .navigationTitle("AI相談")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { voice.cancelAll(); onClose() }
                        .accessibilityIdentifier("chat_close_button")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        voice.speaksReplies.toggle()
                        if !voice.speaksReplies { voice.stopSpeaking() }
                    } label: {
                        Image(systemName: voice.speaksReplies ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .accessibilityLabel(voice.speaksReplies ? "返答の読み上げをやめる" : "返答を読み上げる")
                    .accessibilityIdentifier("chat_speak_toggle")
                    Button {
                        isResetConfirmationPresented = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(chat.messages.isEmpty)
                    .accessibilityLabel("会話をリセット")
                    .accessibilityIdentifier("chat_reset_button")
                }
            }
            .confirmationDialog("会話をリセットしますか？", isPresented: $isResetConfirmationPresented, titleVisibility: .visible) {
                Button("リセットする", role: .destructive) { voice.cancelAll(); chat.reset() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この画面の会話はすべて消去されます（端末にもサーバーにも保存していません）。")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            chat.refreshConsent()
            mokorinPose = mokorinPose.with(.happy, .wave)
            voice.onUtterance = { text in await chat.submit(text) }
            voice.onSpeakingChanged = { speaking in mokorinPose.speaking = speaking }
        }
        .onDisappear { voice.cancelAll() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voice.cancelAll() }   // 背面に回ったら録音・読み上げを止める
        }
        // もこりんの表情・動作: 考え中は calm、返答が届いたら jump / nod、失敗は sad、リセットで手をふる
        .onChange(of: chat.isSending) { _, sending in
            if sending {
                mokorinPose = mokorinPose.with(.calm, nil)
            }
        }
        .onChange(of: chat.messages.count) { _, count in
            guard let last = chat.messages.last else {
                mokorinPose = mokorinPose.with(.happy, .wave)
                return
            }
            if last.role == .assistant, count > 0 {
                if chat.lastFailureMessage == nil {
                    mokorinPose = mokorinPose.with(.happy, .jump)
                } else {
                    mokorinPose = mokorinPose.with(.sad, .nod)
                }
                // 声で話したあとは返答も読み上げる（画面右上で切り替え）
                voice.speakReply(last.text)
            }
        }
    }
    // AIChatView.swift の VStack(spacing: 0) の先頭（mokorinHeader の上）に追加
   

    // MARK: - もこりん（会話の中心）

    private func mokorinHero(compact: Bool, availableHeight: CGFloat) -> some View {
        let avatarSize: CGFloat = compact ? 64 : min(150, max(104, availableHeight * 0.19))

        return Group {
            if compact {
                HStack(alignment: .center, spacing: 10) {
                    MokorinAvatarView(size: avatarSize, pose: mokorinPose)
                        .frame(width: avatarSize, height: avatarSize)
                    heroBubble(lineLimit: 3)
                }
            } else {
                VStack(spacing: 6) {
                    heroBubble(lineLimit: 4)
                        .frame(maxWidth: 340)
                    MokorinAvatarView(size: avatarSize, pose: mokorinPose)
                        .frame(width: avatarSize, height: avatarSize)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.25), value: compact)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("もこりん：\(mokorinSpeechText)")
        .accessibilityIdentifier("chat_mokorin_hero")
    }

    private func heroBubble(lineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(activityColor)
                    .frame(width: 6, height: 6)
                Text(activityLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(activityColor.opacity(0.9))
                    .tracking(1.2)
            }
            Text(mokorinSpeechText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MindWaveCyberTheme.textPrimary)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.03, green: 0.07, blue: 0.18).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(activityColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var activityLabel: String {
        if voice.isListening || voice.state == .preparing { return "LISTENING" }
        if chat.isSending || voice.state == .processing { return "THINKING" }
        if voice.state == .speaking { return "SPEAKING" }
        return "MOKORIN"
    }

    private var activityColor: Color {
        if voice.isListening || voice.state == .preparing { return .red }
        if chat.isSending || voice.state == .processing { return MindWaveCyberTheme.orange }
        return MindWaveCyberTheme.cyan
    }

    /// 現在の状況に応じたもこりんのセリフ（返答の全文は会話の履歴に表示する）
    private var mokorinSpeechText: String {
        if voice.isListening {
            return voice.partialTranscript.isEmpty ? "聞いてるよ。話し終えたら自動で送るね。" : "「\(voice.partialTranscript)」"
        }
        if voice.state == .preparing { return "マイクを準備しているよ…" }
        if let problem = voice.problem { return problem }
        if chat.isSending {
            return "うーん、どうやって整理しようかな…ちょっと待ってね！"
        }
        if chat.lastFailureMessage != nil {
            return "あれれ、うまく届かなかったみたい…もう一回送ってみようか？"
        }
        if let lastAssistant = chat.messages.last(where: { $0.role == .assistant }) {
            return Self.firstSentence(of: lastAssistant.text)
        }
        if let situation = chat.learned.situation?.value, situation.isEvent {
            return "さっき「\(situation.label)」のことを話してくれたね。気になっていること、なんでも聞いてね。"
        }
        return "今の緊張や気になっていること、なんでも話してね。一緒に整理しよう！"
    }

    /// 返答の最初の一文（もこりんの吹き出し用。全文は履歴にある）
    static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = trimmed.firstIndex(where: { "。！？!?\n".contains($0) }) {
            let sentence = String(trimmed[...end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count >= 4 { return sentence }
        }
        return trimmed
    }

    // MARK: - 会話から分かったこと

    @ViewBuilder
    private var learnedStrip: some View {
        let items = ChatCheckInSummary.items(chat.learned)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(chat.remoteUnavailableReason == nil ? "会話から分かったこと（外部AIにも伝えます）" : "会話から分かったこと（端末内で使います）")
                    .font(.system(size: 9))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(spacing: 4) {
                                Text(item.slot.shortLabel)
                                    .foregroundStyle(MindWaveCyberTheme.cyan)
                                Text(item.value)
                                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                            .overlay(Capsule().strokeBorder(MindWaveCyberTheme.cyan.opacity(0.3)))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("chat_learned_strip")
        }
    }

    // MARK: - 話しかけの例

    @ViewBuilder
    private var quickReplyRow: some View {
        if !chat.isSending, !voice.isListening, chat.draft.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chat.quickReplies, id: \.self) { reply in
                        Button {
                            Task { await chat.submit(reply) }
                        } label: {
                            Text(reply)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MindWaveCyberTheme.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(MindWaveCyberTheme.cyan.opacity(0.16)))
                                .overlay(Capsule().strokeBorder(MindWaveCyberTheme.cyan.opacity(0.45)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("chat_quick_replies")
        }
    }

    // MARK: - 状態の表示

    @ViewBuilder
    private var statusBanner: some View {
        if !chat.isServerConfigured {
            noticeRow(icon: "server.rack", text: ChatViewModel.RemoteUnavailableReason.notConfigured.message,
                      color: MindWaveCyberTheme.orange)
        } else if !chat.isTextConsented {
            consentCard
        }
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("外部AI（OpenAI）で相談しますか？")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MindWaveCyberTheme.textPrimary)
            Text("同意すると、入力した文章・この画面の直近の会話・状況確認で選んだ場面だけを、自前サーバー経由で OpenAI へ送ります。心拍・HRV などの計測データは送りません。会話は端末・サーバーに保存しません。")
                .font(.system(size: 11))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                chat.setTextConsent(true)
            } label: {
                Text("同意して外部AIを使う")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MindWaveCyberTheme.cyan)
            .accessibilityIdentifier("chat_consent_accept")
            Text("同意しない場合は、端末内の定型アドバイスで応答します（同意は設定画面の「AI相談・もこりんの文章を外部AIへ送信」でいつでも取り消せます）")
                .font(.system(size: 10))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: MindWaveCyberTheme.panelRadius).fill(MindWaveCyberTheme.panelBackground.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: MindWaveCyberTheme.panelRadius).strokeBorder(MindWaveCyberTheme.cyan.opacity(0.25)))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func noticeRow(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.35)))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 会話

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chat.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                        if message.id == chat.lastUserMessage?.id {
                            editRow
                        }
                    }
                    if chat.isSending { typingIndicator }
                    if let failure = chat.lastFailureMessage, !chat.isSending { failureRow(failure) }
                    if !chat.messages.isEmpty, !chat.isSending, let top = chat.recommendations.first {
                        recommendationCard(top, others: Array(chat.recommendations.dropFirst()))
                    }
                    Text("AIの回答は医療的な診断ではありません。体調が心配なときは医師などの専門家に相談してください。")
                        .font(.system(size: 9))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    Color.clear.frame(height: 1).id(bottomAnchorID)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: chat.isSending) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isInputFocused) { _, focused in if focused { scrollToBottom(proxy) } }
        }
    }

    /// 直前の発言の訂正・取り消し（一つ前へ戻る）
    private var editRow: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            Button {
                voice.cancelAll()
                chat.editLastUserMessage()
                isInputFocused = true
            } label: {
                Label("直す", systemImage: "pencil")
            }
            .accessibilityHint("直前の発言を入力欄に戻して、言い直せます")
            .accessibilityIdentifier("chat_edit_last")
            Button {
                voice.cancelAll()
                chat.undoLastExchange()
            } label: {
                Label("取り消す", systemImage: "arrow.uturn.backward")
            }
            .accessibilityHint("直前の発言ともこりんの返答を消して、一つ前に戻ります")
            .accessibilityIdentifier("chat_undo_last")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(MindWaveCyberTheme.textSecondary)
        .buttonStyle(.plain)
        .padding(.top, -6)
    }

    /// 会話の内容からのおすすめ（端末内の決まった規則。MokorinMethodAdvisor）
    private func recommendationCard(_ top: MethodRecommendation, others: [MethodRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("もこりんのおすすめ")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MindWaveCyberTheme.cyan)
            Text(top.method.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MindWaveCyberTheme.textPrimary)
            Text(top.reason)
                .font(.system(size: 12))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let next = others.first {
                Text("ほかに: \(next.method.title)")
                    .font(.system(size: 11))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
            if let onOpenImprovement {
                Button {
                    voice.cancelAll()
                    onOpenImprovement()
                } label: {
                    Label("改善方法を見る", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MindWaveCyberTheme.cyan)
                .accessibilityIdentifier("chat_open_improvement")
            }
            Text("会話の内容から端末内の決まった規則で選んでいます（AIの判断ではありません）。ほかの方法も自由に選べます。")
                .font(.system(size: 9))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.03, green: 0.09, blue: 0.2).opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MindWaveCyberTheme.cyan.opacity(0.45)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat_recommendation_card")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().tint(MindWaveCyberTheme.cyan)
            Text("回答を作成中…")
                .font(.system(size: 12))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AIが回答を作成中です")
        .accessibilityIdentifier("chat_typing_indicator")
    }

    private func failureRow(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MindWaveCyberTheme.orange)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if chat.canRetry {
                Button("再送信") { Task { await chat.retryLastFailed() } }
                    .buttonStyle(.bordered)
                    .tint(MindWaveCyberTheme.cyan)
                    .accessibilityHint("最後に失敗した発言を外部AIへ送り直します")
                    .accessibilityIdentifier("chat_retry_button")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MindWaveCyberTheme.orange.opacity(0.35)))
    }

    // MARK: - 入力欄

    private var inputBar: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 10) {
                micButton
                TextField(voice.isListening ? "聞いています…" : "メッセージを入力", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .font(.system(size: 15))
                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MindWaveCyberTheme.borderColor))
                    .onChange(of: chat.draft) { _, v in
                        if v.count > ChatLimits.maxUserChars { chat.draft = String(v.prefix(ChatLimits.maxUserChars)) }
                    }
                    .accessibilityLabel("相談内容")
                    .accessibilityIdentifier("chat_input_field")

                Button {
                    chat.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(chat.canSend ? MindWaveCyberTheme.cyan : Color.white.opacity(0.2))
                }
                .disabled(!chat.canSend || voice.isListening)
                .accessibilityLabel("送信")
                .accessibilityIdentifier("chat_send_button")
            }
            HStack {
                Text(chat.remoteUnavailableReason == nil ? "サーバー経由で外部AIに送信します" : "端末内の定型アドバイスで応答します")
                Spacer()
                Text("\(chat.draft.count)/\(ChatLimits.maxUserChars)")
            }
            .font(.system(size: 9))
            .foregroundStyle(MindWaveCyberTheme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    /// 声で話す（押すと録音、話し終えると自動で送信。録音中にもう一度押すと終えて送る）
    private var micButton: some View {
        let listening = voice.isListening
        return Button {
            isInputFocused = false
            Task { await voice.micTapped() }
        } label: {
            Image(systemName: listening ? "stop.fill" : "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(listening ? Color.white : MindWaveCyberTheme.cyan)
                .frame(width: 36, height: 36)
                .background(Circle().fill(listening ? Color.red.opacity(0.85) : MindWaveCyberTheme.cyan.opacity(0.16)))
                .overlay(Circle().strokeBorder(listening ? Color.clear : MindWaveCyberTheme.cyan.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .disabled(chat.isSending || voice.state == .preparing || voice.state == .processing)
        .accessibilityLabel(listening ? "録音を終えて送る" : "声で話す")
        .accessibilityHint("押すと録音を始めます。話し終えると自動で送信します")
        .accessibilityIdentifier("chat_mic_button")
    }
}

/// 1 件の発言
private struct ChatBubble: View {
    let message: ChatViewModel.Message

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isUser { Spacer(minLength: 40) }
            if !isUser {
                // もこりんの発言だと分かるように小さな顔を添える
                MokorinAvatarView(size: 26, pose: MokorinPose(emotion: .happy))
                    .frame(width: 26, height: 26)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser { originBadge }
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isUser ? MindWaveCyberTheme.cyan.opacity(0.28) : Color.black.opacity(0.55))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(borderColor))
                if message.truncated {
                    Text("文字数の上限に達したため、回答の途中で終わっています。")
                        .font(.system(size: 9))
                        .foregroundStyle(MindWaveCyberTheme.orange)
                }
                if case .local(let reason) = message.origin {
                    Text(reason)
                        .font(.system(size: 9))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                }
                statusLabel
            }
            if !isUser { Spacer(minLength: 24) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var borderColor: Color {
        switch message.origin {
        case .stub:  return MindWaveCyberTheme.orange.opacity(0.5)
        case .local: return Color.white.opacity(0.18)
        default:     return isUser ? MindWaveCyberTheme.cyan.opacity(0.35) : Color.white.opacity(0.12)
        }
    }

    @ViewBuilder
    private var originBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: badgeIcon)
            Text(badgeText)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(badgeColor)
    }

    private var badgeText: String {
        switch message.origin {
        case .openAI(let model): return "OpenAI（\(model)）"
        case .stub(let model):   return "スタブ応答（\(model)）・実際のAIではありません"
        case .local:             return "端末内の定型アドバイス（AIではありません）"
        case .user:              return ""
        }
    }

    private var badgeIcon: String {
        switch message.origin {
        case .openAI: return "sparkles"
        case .stub:   return "hammer"
        default:      return "iphone"
        }
    }

    private var badgeColor: Color {
        switch message.origin {
        case .openAI: return MindWaveCyberTheme.cyan
        case .stub:   return MindWaveCyberTheme.orange
        default:      return MindWaveCyberTheme.textSecondary
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch message.status {
        case .sending:
            Text("送信中…").font(.system(size: 9)).foregroundStyle(MindWaveCyberTheme.textTertiary)
        case .failed:
            Label("外部AIに届きませんでした", systemImage: "exclamationmark.circle")
                .font(.system(size: 9))
                .foregroundStyle(MindWaveCyberTheme.orange)
        case .sent:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        let speaker = isUser ? "あなた" : badgeText
        var text = "\(speaker)：\(message.text)"
        if case .failed = message.status { text += "。外部AIに届きませんでした" }
        return text
    }
}

#Preview {
    AIChatView(chat: ChatViewModel(configurationProvider: { nil }), onClose: {})
}
