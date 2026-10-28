// MokorinAvatarView.swift
// Mokorin
//
// もこりんの表示コンポーネント。
// 友達が作成したもこりん（HTML/CSS/JavaScript、third_party/mokorin_friend_source）を
// 統合先のコピー（Mokorin/Web/）から WKWebView で表示し、表情・動作を pose で制御する（MokorinWebView）。
// 同梱ファイルが見つからない場合だけ、差し替え前提の簡易イラストを表示する（キャラクターを作り替えるものではない）。

import SwiftUI

struct MokorinAvatarView: View {
    var size: CGFloat = 64
    var pose: MokorinPose = MokorinPose()

    /// 友達のキャラクターの表示準備ができたか（それまでは読み込み中の表示。キャラクターを別物に置き換えない）
    @State private var isWebReady = false

    var body: some View {
        Group {
            if MokorinWebView.resourceURL != nil {
                ZStack {
                    MokorinWebView(pose: pose, onReady: { isWebReady = true })
                        .opacity(isWebReady ? 1 : 0)
                    if !isWebReady {
                        ProgressView()
                            .tint(Color(red: 0.35, green: 0.75, blue: 0.95))
                            .accessibilityLabel("もこりんを読み込み中")
                    }
                }
                .animation(.easeIn(duration: 0.3), value: isWebReady)
            } else {
                MokorinPlaceholderShape()
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("もこりん")
        .accessibilityValue(Self.emotionDescription(pose.emotion))
        .accessibilityIdentifier("mokorin_avatar")
    }

    static func emotionDescription(_ e: MokorinEmotion) -> String {
        switch e {
        case .happy:  return "うれしそう"
        case .calm:   return "おだやか"
        case .sad:    return "かなしそう"
        case .sleepy: return "ねむそう"
        }
    }
}

/// 差し替え前提の簡易イラスト（ふわふわした丸いキャラクター）
private struct MokorinPlaceholderShape: View {
    private let accent = Color(red: 0.35, green: 0.75, blue: 0.95)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // もこもこの輪郭（小さな円を周囲に並べる）
                ForEach(0..<10, id: \.self) { i in
                    let angle = Double(i) / 10 * 2 * .pi
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: s * 0.34, height: s * 0.34)
                        .offset(x: cos(angle) * s * 0.30, y: sin(angle) * s * 0.30)
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: s * 0.72, height: s * 0.72)
                // 目
                HStack(spacing: s * 0.16) {
                    Capsule().fill(Color(red: 0.10, green: 0.14, blue: 0.28)).frame(width: s * 0.07, height: s * 0.11)
                    Capsule().fill(Color(red: 0.10, green: 0.14, blue: 0.28)).frame(width: s * 0.07, height: s * 0.11)
                }
                .offset(y: -s * 0.02)
                // ほっぺ
                HStack(spacing: s * 0.34) {
                    Circle().fill(Color.pink.opacity(0.35)).frame(width: s * 0.10)
                    Circle().fill(Color.pink.opacity(0.35)).frame(width: s * 0.10)
                }
                .offset(y: s * 0.08)
            }
            .frame(width: s, height: s)
            .shadow(color: accent.opacity(0.45), radius: s * 0.12)
        }
    }
}

#Preview {
    MokorinAvatarView(size: 120, pose: MokorinPose(emotion: .happy, action: .wave, actionID: 1)).padding().background(Color.black)
}
