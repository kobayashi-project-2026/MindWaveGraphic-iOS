// MokorinImprovementViews.swift
// Mokorin
//
// 改善（ガイド）の流れで使う、もこりんの小さな部品（2026-11-11、改善資料 3〜4 ページ・全体UI 14〜27 ページ）。
// - MokorinRecommendationPanel: 方法の選択画面で、会話の内容からのおすすめ（理由つき）とガイドのない方法の手順
// - MokorinSessionHint: 実施中、終わりのタイミングを小さく知らせる（時間の経過だけで判断。数値から体の状態を断定しない）
// - PrototypeScorePanel: 結果で、本人の緊張の評価（前後）と試作スコア（主観評価＋HR・SDNN）を表示
// - MokorinReflectionView: 実践後の振り返り（5 つの答え）

import SwiftUI

private let accent = Color(red: 0.35, green: 0.75, blue: 0.95)

// MARK: - おすすめ

struct MokorinRecommendationPanel: View {
    let recommendations: [MethodRecommendation]
    /// おすすめのガイド（呼吸法）。なければ nil
    let recommendedExercise: GuideExercise?
    let onTalk: () -> Void

    private var bubble: String {
        if let ex = recommendedExercise { return "どれにする？\(ex.title) 呼吸法がおすすめだよ！" }
        return "どれにする？好きな方法を選んでね。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                MokorinAvatarView(size: 56, pose: MokorinPose().with(.happy, .nod))
                VStack(alignment: .leading, spacing: 3) {
                    Text(bubble).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    if let reason = recommendations.first(where: { $0.method.guideExercise != nil })?.reason ?? recommendations.first?.reason {
                        Text(reason).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mokorin_recommendation")
            // ガイドのない方法（もこりんが手順を案内）
            ForEach(recommendations.filter { $0.method.guideExercise == nil }, id: \.method) { rec in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(rec.method.steps.enumerated()), id: \.offset) { i, step in
                            Text("\(i + 1). \(step)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        }
                        Text("目安 \(rec.suggestedSeconds / 60 > 0 ? "\(rec.suggestedSeconds / 60)分" : "\(rec.suggestedSeconds)秒")（自分のペースで大丈夫）")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ほかのおすすめ: \(rec.method.title)").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                        Text(rec.reason).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .tint(accent)
            }
            Button(action: onTalk) {
                Label("AI相談（もこりんと話す）", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("状況を話し直すと、おすすめが更新されます")
            .accessibilityIdentifier("mokorin_talk_button")
        }
    }
}

// MARK: - 実施中

struct MokorinSessionHint: View {
    /// 残り時間（秒）と予定の長さ
    let remaining: Int
    let total: Int
    let isRunning: Bool

    /// 終わりが近いとき（残り 2 割以下・最後の 10 秒以上）だけ出す
    static func shouldShow(remaining: Int, total: Int, isRunning: Bool) -> Bool {
        isRunning && total > 0 && remaining > 0 && Double(remaining) <= max(10, Double(total) * 0.2)
    }

    var body: some View {
        if Self.shouldShow(remaining: remaining, total: total, isRunning: isRunning) {
            HStack(alignment: .bottom, spacing: 4) {
                Text("いい感じになってきたね！\nそろそろ終わっても平気そう！")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.55)))
                MokorinAvatarView(size: 48, pose: MokorinPose().with(.happy, nil))
            }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("もこりん：いい感じになってきたね。そろそろ終わっても平気そう")
            .accessibilityIdentifier("mokorin_session_hint")
        }
    }
}

// MARK: - 結果: 主観評価と試作スコア

/// 本人の緊張の評価（0〜100）の選択肢（試作の表示尺度。医学的な区分ではない）
enum SubjectiveScale {
    static let values = [0, 20, 50, 75, 100]

    /// 既存の体感入力（SelfReportLevel）からの対応（会話で強さを聞いていないときの代わり）
    static func from(_ level: SelfReportLevel?) -> Int? {
        switch level {
        case .calm?: return 0
        case .slightTension?: return 20
        case .significantTension?: return 75
        case .strongTension?: return 100
        case nil: return nil
        }
    }
}

enum PrototypeScoreInputBuilder {
    /// ガイドの前後のスナップショットから試作スコアの入力を作る（基準＝ガイド前、時刻 t＝ガイド後）。
    /// 測定値がない項目は nil のまま（0 にしない）。サンプルの時刻があればそれを使う
    static func make(s0: Int?, before: GuideSnapshot, after: GuideSnapshot?) -> PrototypeTensionInput {
        func hr(_ s: GuideSnapshot?) -> TimedReading? {
            guard let s, let v = s.heartRate else { return nil }
            return TimedReading(value: v, measuredAt: s.heartRateSampleDate ?? s.timestamp)
        }
        func sdnn(_ s: GuideSnapshot?) -> TimedReading? {
            guard let s, let v = s.hrv else { return nil }
            return TimedReading(value: v, measuredAt: s.hrvSampleDate ?? s.timestamp)
        }
        return PrototypeTensionInput(subjectiveBaseline: s0.map(Double.init), baselineHR: hr(before), currentHR: hr(after),
                                     baselineSDNN: sdnn(before), currentSDNN: sdnn(after),
                                     now: after?.timestamp ?? before.timestamp)
    }
}

struct PrototypeScorePanel: View {
    let s0: Int?
    @Binding var s0After: Int?
    let result: PrototypeTensionResult
    let usesDemoData: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("緊張の強さ（本人の評価・試作）").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            HStack {
                Text("前: \(s0.map(String.init) ?? "未回答")").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                Text("→ 今:").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                Menu {
                    ForEach(SubjectiveScale.values, id: \.self) { v in
                        Button(MokorinCheckIn.tensionLabel(v)) { s0After = v }
                    }
                } label: {
                    Text(s0After.map { "\($0)" } ?? "選ぶ").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                }
                .accessibilityLabel("今の緊張の強さを選ぶ")
                .accessibilityIdentifier("subjective_after_menu")
            }
            if let score = result.score {
                Text("試作スコア（終了時）: \(Int(score.rounded()))  ・\(result.statusLabel)")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                    .accessibilityIdentifier("prototype_score")
                if result.status != .complete, !result.excluded.isEmpty {
                    Text("使えなかった値: " + result.excluded.map(Self.excludedLabel).joined(separator: "、"))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
            } else {
                Text("会話で緊張の強さを聞いていないため、試作スコアは表示しません。").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Text((usesDemoData ? "デモ用のデータです。" : "") + "試作の表示式（本人の評価＋0.77×心拍の変化−0.57×SDNNの変化）で、医学的に検証された値ではありません。心拍の変化は気持ちの変化と同じとは限りません。")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    static func excludedLabel(_ code: String) -> String {
        switch code {
        case "hr_missing": return "心拍（未取得）"
        case "hr_stale": return "心拍（古い）"
        case "hr_invalid": return "心拍（範囲外）"
        case "hr_older_than_baseline": return "心拍（基準より前）"
        case "sdnn_missing": return "SDNN（未取得）"
        case "sdnn_stale": return "SDNN（古い）"
        case "sdnn_invalid": return "SDNN（範囲外）"
        case "sdnn_older_than_baseline": return "SDNN（基準より前）"
        default: return code
        }
    }
}

// MARK: - 振り返り

enum ReflectionAnswer: String, CaseIterable, Identifiable {
    case littleCalmer, muchCalmer, noChange, worse, unsure
    var id: String { rawValue }
    var label: String {
        switch self {
        case .littleCalmer: return "少し落ち着いた！"
        case .muchCalmer: return "かなり落ち着いた！"
        case .noChange: return "あまり変わらなかった"
        case .worse: return "逆に気になってしまった"
        case .unsure: return "よく分からない"
        }
    }
    /// もこりんの返事（改善を断定しない。合わなかった方法を続けさせない）
    func reply(alternative: ImprovementMethod?) -> String {
        switch self {
        case .littleCalmer: return "少し落ち着けたんだね。よかった！"
        case .muchCalmer: return "かなり落ち着けたんだね。自分に合う方法が見つかったかも！"
        case .noChange:
            return alternative.map { "そっか。別の方法「\($0.title)」も試してみる？" } ?? "そっか。合う方法は人それぞれだから、別の方法も試してみよう。"
        case .worse: return "無理に続けなくて大丈夫だよ。同じ方法はやめて、今日はゆっくりしよう。"
        case .unsure: return "分からなくても大丈夫。数値と気持ちが同じとは限らないよ。"
        }
    }
}

struct MokorinReflectionView: View {
    let alternative: ImprovementMethod?
    @Binding var answer: ReflectionAnswer?
    /// 次の改善方法を試す（ガイドのある方法のとき）
    var onTryNext: ((ImprovementMethod) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                MokorinAvatarView(size: 44, pose: MokorinPose().with(answer == .worse ? .sad : .happy, .nod))
                Text(answer.map { $0.reply(alternative: alternative) + "\n今日はいろいろ教えてくれてありがとう！またいつでも話しに来てね！" }
                     ?? "おつかれさま！実際にやってみてどうだった？")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mokorin_reflection_text")
            }
            // 次の改善方法の提案（合わなかったときは別の方法、合ったときも別の選択肢として）
            if let answer, answer != .worse, let next = alternative {
                Button { onTryNext?(next) } label: {
                    Text("次は「\(next.title)」を試す ›").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .disabled(onTryNext == nil || next.guideExercise == nil)
                .accessibilityIdentifier("reflection_try_next")
            }
            if answer == nil {
                FlowChips(items: ReflectionAnswer.allCases) { a in
                    Button(a.label) { answer = a }
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().strokeBorder(accent.opacity(0.6), lineWidth: 0.8))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reflection_\(a.rawValue)")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
}

/// 折り返して並べる選択肢
struct FlowChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(items) { content($0) } }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { ForEach(items.prefix(2)) { content($0) } }
                HStack(spacing: 6) { ForEach(items.dropFirst(2).prefix(2)) { content($0) } }
                HStack(spacing: 6) { ForEach(items.dropFirst(4)) { content($0) } }
            }
        }
    }
}
