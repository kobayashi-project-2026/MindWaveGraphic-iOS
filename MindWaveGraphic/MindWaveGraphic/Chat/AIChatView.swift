// AIChatView.swift
// Chat
//
// AI 相談画面。「整える」タブのカード、または共通メニュー「AI相談」から
// AppNavigationManager のモーダル（AppModal.aiChat）として開く。
// 返答の出どころ（OpenAI / スタブ / 端末内の定型アドバイス）を必ず表示し、取り違えないようにする。

import SwiftUI

struct AIChatView: View {
    @ObservedObject var chat: ChatViewModel
    let onClose: () -> Void

    @State private var isResetConfirmationPresented = false
    @FocusState private var isInputFocused: Bool
    /// もこりんの表情・動作（固定の規則。返答の文章は変更しない）
    @State private var mokorinPose = MokorinPose()

    private let bottomAnchorID = "chat_bottom_anchor"

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let mokorinStageHeight = max(150, geo.size.height * 0.25)

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
                        // 上部 3/4：ステータス＆会話リスト
                        statusBanner
                        messageList
                            .frame(maxHeight: .infinity)

                        // パターンA：会話リストの下に入力バー
                        inputBar

                        // 下部 1/4：もこりん専用ステージ（大きく動いてしゃべるスペース）
                        mokorinStage(height: mokorinStageHeight)
                    }
                }
            }
            .navigationTitle("AI相談")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onClose)
                        .accessibilityIdentifier("chat_close_button")
                }
                ToolbarItem(placement: .primaryAction) {
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
                Button("リセットする", role: .destructive) { chat.reset() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この画面の会話はすべて消去されます（端末にもサーバーにも保存していません）。")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            chat.refreshConsent()
            mokorinPose = mokorinPose.with(.happy, .wave)
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
            }
        }
    }

    // MARK: - 下部 1/4：もこりん専用ステージ

    private func mokorinStage(height: CGFloat) -> some View {
        let avatarSize = min(height * 0.88, 148)

        return HStack(alignment: .center, spacing: 12) {
            MokorinAvatarView(size: avatarSize, pose: mokorinPose)
                .frame(width: avatarSize, height: avatarSize)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(chat.isSending ? MindWaveCyberTheme.orange : MindWaveCyberTheme.cyan)
                        .frame(width: 6, height: 6)
                    Text("MOKORIN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.cyan.opacity(0.85))
                        .tracking(1.2)
                }

                Text(mokorinSpeechText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.03, green: 0.07, blue: 0.18).opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(MindWaveCyberTheme.cyan.opacity(0.32), lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(height: height)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color(red: 0.02, green: 0.05, blue: 0.14).opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MindWaveCyberTheme.cyan.opacity(0.18))
                .frame(height: 0.5)
        }
    }

    /// 現在の状況に応じたもこりんのセリフ
    private var mokorinSpeechText: String {
        if chat.isSending {
            return "うーん、どうやって整理しようかな…ちょっと待ってね！"
        }
        if chat.lastFailureMessage != nil {
            return "あれれ、うまく届かなかったみたい…もう一回送ってみようか？"
        }
        if let lastAssistant = chat.messages.last(where: { $0.role == .assistant }) {
            return lastAssistant.text
        }
        if chat.messages.isEmpty {
            return "今の緊張や気になっていること、なんでも話してね。一緒に整理しよう！"
        }
        return "うんうん、聞いてるよ！"
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
                    if chat.messages.isEmpty { emptyState }
                    ForEach(chat.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                    if chat.isSending { typingIndicator }
                    if let failure = chat.lastFailureMessage, !chat.isSending { failureRow(failure) }
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("緊張や不安について、気軽に相談してください。")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MindWaveCyberTheme.textPrimary)
            Text("例:「面接前で緊張しています」「明日のプレゼンが不安です」")
                .font(.system(size: 12))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12)))
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
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
                TextField("メッセージを入力", text: $chat.draft, axis: .vertical)
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
                .disabled(!chat.canSend)
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
}

/// 1 件の発言
private struct ChatBubble: View {
    let message: ChatViewModel.Message

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
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
            if !isUser { Spacer(minLength: 40) }
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
