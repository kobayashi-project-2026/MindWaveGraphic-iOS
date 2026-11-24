// MokorinCompanionViewModel.swift
// Mokorin
//
// 結果画面・記録の詳細から呼び出す、もこりんとの会話（説明・比較・提案・質問）の状態。
//
// - 説明は MokorinResultExplainer が端末内で作る（測定値を含むため外部へ送らない）
// - 自由な質問は既存の ChatViewModel（POST /v1/chat）へ。同意がない・未設定なら端末内で答えられる範囲で答える
// - 選択肢は最大 3 つ。提案の確認（「試してみた？」）は 1 回だけ
// - 会話はメモリのみ。閉じる・やり直すで消える

import Foundation
import Combine

@MainActor
final class MokorinCompanionViewModel: ObservableObject {

    enum Reply: Hashable {
        case meaning, compare, advice, tried, later

        var label: String {
            switch self {
            case .meaning: return "どういう意味？"
            case .compare: return "前と比べる"
            case .advice:  return "次にできること"
            case .tried:   return "試してみた"
            case .later:   return "あとでやる"
            }
        }
    }

    static let localReason = "端末内の説明（AIではありません）"

    let chat: ChatViewModel
    @Published private(set) var brief: MokorinBrief
    @Published private(set) var shown: Set<Reply> = []
    @Published private(set) var pendingFollowUp: String? = nil
    @Published private(set) var pose = MokorinPose().with(.happy, .wave)

    private let makeBrief: (_ recentUserText: String) -> MokorinBrief
    private var followUpAsked = false
    private var cancellable: AnyCancellable?

    init(chat: ChatViewModel, makeBrief: @escaping (_ recentUserText: String) -> MokorinBrief) {
        self.chat = chat
        self.makeBrief = makeBrief
        self.brief = makeBrief("")
        // ChatViewModel の変化（返答の到着など）を画面へ伝える
        cancellable = chat.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        start()
    }

    private func start() {
        chat.appendLocalExchange(userText: nil, reply: brief.firstMessage, reason: Self.localReason)
    }

    /// 次に選べる選択肢（最大 3 つ）
    var quickReplies: [Reply] {
        if pendingFollowUp != nil { return [.tried, .later] }
        return [Reply.meaning, .compare, .advice].filter { !shown.contains($0) }
    }

    func tap(_ reply: Reply) {
        guard !chat.isSending else { return }
        switch reply {
        case .meaning:
            var lines: [String] = brief.interpretation
            lines.append(contentsOf: brief.missing.dropFirst())
            lines.append(contentsOf: brief.cautions)
            say(reply.label, lines.joined(separator: "\n"), emotion: .calm)
        case .compare:
            say(reply.label, brief.comparison.joined(separator: "\n"), emotion: brief.hasComparableHistory ? .happy : .calm)
        case .advice:
            switch brief.advice {
            case .seekHelp(let message):
                say(reply.label, message, emotion: .sad)
            case .advice(let items) where items.isEmpty:
                say(reply.label, "今は特に変えなくて大丈夫そうだよ。気になることがあったら、聞いてね。", emotion: .happy)
            case .advice(let items):
                let text = items.map { "\($0.text)（\($0.basis)）" }.joined(separator: "\n")
                say(reply.label, text, emotion: .happy)
                if !followUpAsked, let q = items.compactMap(\.followUp).first {
                    followUpAsked = true
                    pendingFollowUp = q
                    chat.appendLocalExchange(userText: nil, reply: q, reason: Self.localReason)
                }
            }
        case .tried:
            pendingFollowUp = nil
            say(reply.label, "いいね。少し変化はあった？話したくなったら、いつでも教えてね。", emotion: .happy)
        case .later:
            pendingFollowUp = nil
            say(reply.label, "うん、無理しなくて大丈夫だよ。", emotion: .calm)
        }
        shown.insert(reply)
    }

    /// 入力欄の文章を送る
    func send() {
        let text = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isSending else { return }
        // 深刻な症状は外部AIの返答を待たずに、相談を案内する（提案はしない）
        if MokorinAdviceEngine.mentionsSeriousSymptom(text) {
            chat.draft = ""
            brief = makeBrief(text)
            say(text, MokorinAdviceEngine.seekHelpMessage, emotion: .sad)
            return
        }
        // 外部AIを使えないときは、端末内で答えられる質問だけ説明から答える
        if chat.remoteUnavailableReason != nil, let local = localAnswer(to: text) {
            chat.draft = ""
            say(text, local, emotion: .calm)
            return
        }
        pendingFollowUp = nil
        setPose(.calm, .nod)
        chat.send()
    }

    /// 端末内の説明から答えられる質問（見つからなければ nil → ChatViewModel の定型アドバイス）
    func localAnswer(to text: String) -> String? {
        if ["比べ", "前回", "前と", "過去"].contains(where: text.contains) { shown.insert(.compare); return brief.comparison.joined(separator: "\n") }
        if text.uppercased().contains("HRV") {
            let hrvLines: [String] = brief.facts.filter { $0.contains("HRV") } + brief.missing.filter { $0.contains("HRV") }
            return hrvLines.joined(separator: "\n")
        }
        if ["心拍", "スコア", "数値", "結果"].contains(where: text.contains) && !["どう", "意味"].contains(where: text.contains) {
            return brief.facts.joined(separator: "\n")
        }
        if ["意味", "どういう", "大丈夫", "悪い", "良い", "いい？"].contains(where: text.contains) {
            shown.insert(.meaning)
            let lines: [String] = brief.interpretation + brief.cautions
            return lines.joined(separator: "\n")
        }
        if ["どうすれば", "何をすれば", "何すれば", "アドバイス", "提案", "次に"].contains(where: text.contains) {
            shown.insert(.advice)
            switch brief.advice {
            case .seekHelp(let m): return m
            case .advice(let items): return items.isEmpty ? "今は特に変えなくて大丈夫そうだよ。" : items.map(\.text).joined(separator: "\n")
            }
        }
        return nil
    }

    /// 会話を消して最初から
    func restart() {
        chat.reset()
        shown = []
        pendingFollowUp = nil
        followUpAsked = false
        brief = makeBrief("")
        setPose(.happy, .wave)
        start()
    }

    private func say(_ userText: String, _ reply: String, emotion: MokorinEmotion) {
        chat.appendLocalExchange(userText: userText, reply: reply, reason: Self.localReason)
        setPose(emotion, .nod)
    }

    private func setPose(_ emotion: MokorinEmotion, _ action: MokorinAction?) {
        pose = pose.with(emotion, action)
    }
}
