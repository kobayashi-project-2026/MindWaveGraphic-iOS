// MokorinCompanionView.swift
// Mokorin
//
// 結果の説明・記録の振り返り・提案を、もこりんとの会話として表示するシート（共通部品）。
// 結果画面（GuideFlowView）と記録の詳細（RecordDetailView）から、利用者が求めたときだけ開く。
// 見た目は既存の黒背景・青系アクセント、キャラクターは友達の原本（MokorinAvatarView）。

import SwiftUI

struct MokorinCompanionView: View {
    @StateObject private var model: MokorinCompanionViewModel
    let title: String
    let onClose: () -> Void

    @FocusState private var inputFocused: Bool
    private let accent = Color(red: 0.35, green: 0.75, blue: 0.95)

    init(title: String, model: @autoclosure @escaping () -> MokorinCompanionViewModel, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model())
        self.title = title
        self.onClose = onClose
    }

    private var chat: ChatViewModel { model.chat }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                MokorinAvatarView(size: 120, pose: model.pose)
                    .padding(.top, 4)
                conversation
                if !model.quickReplies.isEmpty && !chat.isSending { quickReplies }
                consentRow
                inputRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onClose).accessibilityIdentifier("mokorin_companion_close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { model.restart() } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("会話を消して最初から")
                        .accessibilityIdentifier("mokorin_companion_restart")
                }
            }
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .task { await runDebugHooks() }
        #endif
    }

    // MARK: - 会話

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(chat.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if chat.isSending {
                        HStack(spacing: 6) {
                            ProgressView().tint(accent)
                            Text("考え中…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                        }
                        .accessibilityElement(children: .combine)
                        .id("sending")
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(chat.messages.last?.id, anchor: .bottom) }
            }
        }
        .accessibilityIdentifier("mokorin_companion_conversation")
    }

    private func bubble(_ message: ChatViewModel.Message) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                if !isUser, let label = originLabel(message.origin) {
                    Text(label).font(.system(size: 9)).foregroundStyle(isStub(message.origin) ? Color.orange.opacity(0.9) : .white.opacity(0.35))
                }
                if case .failed(let reason) = message.status {
                    Text(reason).font(.system(size: 10)).foregroundStyle(.orange.opacity(0.85))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isUser ? accent.opacity(0.16) : Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(isUser ? 0 : 0.10), lineWidth: 1))
            )
            if !isUser { Spacer(minLength: 24) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "あなた：\(message.text)" : "もこりん（\(originLabel(message.origin) ?? "")）：\(message.text)")
    }

    private func originLabel(_ origin: ChatViewModel.Origin) -> String? {
        switch origin {
        case .user:              return nil
        case .openAI(let model): return "OpenAI（\(model)）"
        case .stub(let model):   return "スタブ応答（\(model)）・実際のAIではありません"
        case .local(let reason): return reason
        }
    }

    private func isStub(_ origin: ChatViewModel.Origin) -> Bool {
        if case .stub = origin { return true }
        return false
    }

    // MARK: - 選択肢・入力

    private var quickReplies: some View {
        HStack(spacing: 8) {
            ForEach(model.quickReplies, id: \.self) { reply in
                Button(reply.label) { model.tap(reply) }
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().strokeBorder(accent.opacity(0.6), lineWidth: 0.8))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mokorin_companion_reply_\(reply)")
            }
        }
    }

    @ViewBuilder
    private var consentRow: some View {
        if chat.isServerConfigured && !chat.isTextConsented {
            HStack(spacing: 8) {
                Text("自由な質問を AI に聞くには同意が必要です。送るのは入力した文章だけで、測定値は送りません。")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Button("AIと話す") { chat.setTextConsent(true) }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(accent))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mokorin_companion_consent")
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("もこりんに聞く", text: Binding(get: { chat.draft }, set: { chat.draft = $0 }), axis: .vertical)
                .lineLimit(1...3)
                .focused($inputFocused)
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .submitLabel(.send)
                .onSubmit { model.send() }
                .accessibilityIdentifier("mokorin_companion_input")
            Button { model.send() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                    .foregroundStyle(chat.canSend ? accent : Color.white.opacity(0.2))
            }
            .buttonStyle(.plain)
            .disabled(!chat.canSend)
            .accessibilityLabel("送信")
            .accessibilityIdentifier("mokorin_companion_send")
        }
    }

    #if DEBUG
    /// シミュレーター検証用: MW_COMPANION_TAPS="meaning||compare||advice" で選択肢を順に押す
    private func runDebugHooks() async {
        guard let script = ProcessInfo.processInfo.environment["MW_COMPANION_TAPS"] else { return }
        for name in script.components(separatedBy: "||") {
            try? await Task.sleep(for: .seconds(1.2))
            let all: [MokorinCompanionViewModel.Reply] = [.meaning, .compare, .advice, .tried, .later]
            if let reply = all.first(where: { "\($0)" == name }) { model.tap(reply) }
        }
    }
    #endif
}
