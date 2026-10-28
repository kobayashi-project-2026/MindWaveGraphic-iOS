// MokorinBubble.swift
// Mokorin
//
// もこりんとの会話の吹き出し。もこりんの発言には出どころ（OpenAI / スタブ / 端末内の定型文）を必ず表示する。

import SwiftUI

struct MokorinBubble: View {
    let message: MokorinContextViewModel.Message
    let accent: Color

    private var isUser: Bool { message.speaker == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(isUser ? Color.black : Color.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isUser ? accent.opacity(0.85) : Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isStub ? Color.orange.opacity(0.6) : (isUser ? Color.clear : Color.white.opacity(0.12)), lineWidth: 1)
                    )
                if !isUser {
                    Text(originLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(isStub ? Color.orange.opacity(0.9) : Color.white.opacity(0.35))
                }
            }
            if !isUser { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "あなた：\(message.text)" : "もこりん（\(originLabel)）：\(message.text)")
    }

    private var isStub: Bool {
        if case .stub = message.origin { return true }
        return false
    }

    private var originLabel: String {
        switch message.origin {
        case .openAI(let model): return "OpenAI（\(model)）"
        case .stub(let model):   return "スタブ応答（\(model)）・実際のAIではありません"
        case .fixed:             return "端末内の定型文"
        case .user:              return ""
        }
    }
}
