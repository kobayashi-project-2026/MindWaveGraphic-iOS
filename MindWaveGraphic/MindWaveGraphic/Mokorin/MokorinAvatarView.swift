// MokorinAvatarView.swift
// Mokorin
//
// もこりんの表示コンポーネント。
// リポジトリにもこりんの画像アセットがない（2026-10-28 時点）ため、
// Assets.xcassets に「Mokorin」という名前の画像を追加すると自動でその画像を表示し、
// ない場合は差し替え前提の簡易イラスト（SwiftUI 図形）を表示する。
// キャラクターデザインの担当者が画像を追加するときは、このファイルの変更は不要。

import SwiftUI
import UIKit

struct MokorinAvatarView: View {
    var size: CGFloat = 64
    /// 返答作成中は軽く揺らす
    var isThinking: Bool = false

    /// 正式な画像アセット名
    static let assetName = "Mokorin"
    static var hasAsset: Bool { UIImage(named: assetName) != nil }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    var body: some View {
        Group {
            if Self.hasAsset {
                Image(Self.assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                MokorinPlaceholderShape()
            }
        }
        .frame(width: size, height: size)
        .offset(y: bob ? -3 : 0)
        .animation(isThinking && !reduceMotion ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : .default, value: bob)
        .onChange(of: isThinking) { _, thinking in bob = thinking && !reduceMotion }
        .accessibilityElement()
        .accessibilityLabel("もこりん")
        .accessibilityIdentifier("mokorin_avatar")
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
    MokorinAvatarView(size: 96).padding().background(Color.black)
}
