// MokorinCockpitPopup.swift
// Home
//
// グラフィック画面（HomeView）の右端からひょこっと横スライドで登場し、
// 吹き出しで語りかけるもこりん演出＆過緊張時の上部通知バナー。
// アラート以上（過緊張状態）のときは常時表示を継続する。

import SwiftUI
import Combine

/// 画面右端からひょこっと横から登場・退場するもこりんと吹き出し
struct MokorinCockpitPopupView: View {
    let isHyperTension: Bool
    let score: Double
    let onTapNavigateToGuide: () -> Void

    @State private var isVisible = false
    @State private var speechText = "いい調子だね！このペースでいこう！"
    @State private var mokorinPose = MokorinPose()
    @State private var hideTask: Task<Void, Never>?

    // 約25秒おきに時々ひょっこり出てくるタイマー（通常時のみ使用）
    private let periodicTimer = Timer.publish(every: 25, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Spacer(minLength: 10)

            // 左上の白い吹き出し（画像イメージに合わせた緑枠＋右向きしっぽ）
            Button(action: onTapNavigateToGuide) {
                SpeechBubbleWithTail(text: speechText, isAlert: isHyperTension)
            }
            .buttonStyle(.plain)
            .offset(y: -52)

            // 二回り大きくしたもこりん（96 → 136）
            MokorinAvatarView(size: 136, pose: mokorinPose)
                .frame(width: 136, height: 136)
                .onTapGesture {
                    if isHyperTension {
                        onTapNavigateToGuide()
                    } else {
                        dismissSmoothly()
                    }
                }
        }
        .padding(.trailing, 6)
        // 右画面外からひょこっと横スライドで登場・退場
        .offset(x: isVisible ? 0 : 340)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.48, dampingFraction: 0.78), value: isVisible)
        .onAppear {
            mokorinPose = mokorinPose.with(.happy, .wave)
            if isHyperTension {
                triggerAppearance(forceHyperAlert: true)
            } else {
                // 起動2秒後に一度挨拶でひょこっと登場
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    triggerAppearance(forceHyperAlert: isHyperTension)
                }
            }
        }
        .onChange(of: isHyperTension) { _, hyper in
            if hyper {
                // アラート以上になったら即座に登場し、そのまま常時表示する
                triggerAppearance(forceHyperAlert: true)
            } else {
                // アラートが解除されたら数秒後にスッと退場させる
                scheduleAutoHide(after: 3_000_000_000)
            }
        }
        .onReceive(periodicTimer) { _ in
            // 通常時でまだ表示されていなければ時々ひょっこり顔を出す
            if !isHyperTension && !isVisible {
                triggerAppearance(forceHyperAlert: false)
            }
        }
        .onDisappear {
            hideTask?.cancel()
        }
    }

    private func triggerAppearance(forceHyperAlert: Bool) {
        hideTask?.cancel()

        if forceHyperAlert {
            speechText = "緊張しているね！\n一緒に改善してみようか！"
            mokorinPose = mokorinPose.with(.calm, .wave)
        } else {
            let calmMessages = [
                "いい調子だね！\nリラックスできてるよ！",
                "深呼吸してみようか！\nゆっくり吸って〜吐いて〜",
                "宇宙の星がきれいだね！\n無理せずいこうね！"
            ]
            speechText = calmMessages.randomElement() ?? calmMessages[0]
            mokorinPose = mokorinPose.with(.happy, .wave)
        }

        withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
            isVisible = true
        }

        // アラート以上（過緊張）のときは自動退場せず常時出し続ける！
        if !forceHyperAlert {
            scheduleAutoHide(after: 5_500_000_000)
        }
    }

    private func scheduleAutoHide(after nanoseconds: UInt64) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // 退場直前にアラート状態になっていたら引っ込めない
                if !isHyperTension {
                    dismissSmoothly()
                }
            }
        }
    }

    private func dismissSmoothly() {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.42)) {
            isVisible = false
        }
    }
}

/// 理想画像に合わせた白背景・緑枠・しっぽ付き吹き出し
private struct SpeechBubbleWithTail: View {
    let text: String
    let isAlert: Bool

    private var borderColor: Color {
        isAlert
            ? Color(red: 0.36, green: 0.68, blue: 0.44)
            : Color(red: 0.30, green: 0.75, blue: 0.85)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(text)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.12, green: 0.15, blue: 0.18))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 2.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)

            // 右下の吹き出ししっぽ
            BubbleTailShape()
                .fill(Color.white.opacity(0.96))
                .frame(width: 18, height: 14)
                .overlay(
                    BubbleTailBorderShape()
                        .stroke(borderColor, lineWidth: 2.5)
                )
                .offset(x: -14, y: 12)
        }
        .padding(.bottom, 12)
    }
}

private struct BubbleTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.65, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct BubbleTailBorderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.65, y: 0))
        return path
    }
}

/// 過緊張時に画面上部へ降りてくる通知バナー
struct HyperTensionTopBanner: View {
    let isVisible: Bool
    let onTapGuide: () -> Void

    var body: some View {
        if isVisible {
            Button(action: onTapGuide) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MindWaveCyberTheme.orange)

                    Text("過緊張状態を検知しました — 「整える」で落ち着こう")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(red: 0.22, green: 0.08, blue: 0.05).opacity(0.92))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(MindWaveCyberTheme.orange.opacity(0.8), lineWidth: 1.2)
                )
                .shadow(color: MindWaveCyberTheme.orange.opacity(0.45), radius: 10, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
