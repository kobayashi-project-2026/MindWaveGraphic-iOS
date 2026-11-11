// MokorinEdgeGuide.swift
// Mokorin
//
// ホームで、現在の評価に合わせて小さなもこりんが画面の端に現れ、短く案内する（2026-11-11、改善資料 2 ページ）。
// - 緊張が高い（既存の状態 overTense）とき: 「緊張しているね！一緒に改善してみようか！」→ 押すと改善へ
// - 適度な緊張・落ち着き: 短く伝えて数秒で隠れる（適切な緊張を保つ案内）
// - 状態の判定は既存の計算（GraphicInput.state）をそのまま使う。急な変化を医学的な緊急事態として扱わない
// - 大きなチャットは出さない。閉じるボタンで消せる

import SwiftUI

struct MokorinEdgeGuide: View {
    let state: MindState
    /// 計測データがあるときだけ出す
    let isActive: Bool
    let onImprove: () -> Void

    @State private var visible = false
    @State private var dismissedState: MindState?
    @State private var hideTask: Task<Void, Never>?

    static func message(for state: MindState) -> (text: String, actionable: Bool) {
        switch state {
        case .overTense:      return ("緊張しているね！\n一緒に改善してみようか！", true)
        case .optimalTension: return ("いい集中の状態だよ。\nこの調子を保っていこう！", false)
        case .underAroused:   return ("落ち着いているね。", false)
        }
    }

    var body: some View {
        let m = Self.message(for: state)
        ZStack(alignment: .bottomTrailing) {
            if visible && isActive && dismissedState != state {
                HStack(alignment: .bottom, spacing: 4) {
                    Button { if m.actionable { onImprove() } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.text)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.black.opacity(0.85))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if m.actionable {
                                Text("改善へ ›").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(red: 0.1, green: 0.45, blue: 0.7))
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.95)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("もこりん：\(m.text.replacingOccurrences(of: "\n", with: ""))")
                    .accessibilityHint(m.actionable ? "改善の画面へ移動します" : "")
                    .accessibilityIdentifier("mokorin_edge_message")
                    VStack(spacing: 2) {
                        Button {
                            dismissedState = state
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("もこりんの案内を閉じる")
                        MokorinAvatarView(size: 64, pose: MokorinPose().with(m.actionable ? .calm : .happy, .wave))
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: visible)
        .onAppear { show() }
        .onChange(of: state) { _, _ in dismissedState = nil; show() }
        .onChange(of: isActive) { _, _ in show() }
    }

    private func show() {
        hideTask?.cancel()
        visible = isActive
        guard isActive, !Self.message(for: state).actionable else { return }
        // 改善の案内でないときは数秒で隠れる（グラフィックを主役にする）
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { visible = false }
        }
    }
}
