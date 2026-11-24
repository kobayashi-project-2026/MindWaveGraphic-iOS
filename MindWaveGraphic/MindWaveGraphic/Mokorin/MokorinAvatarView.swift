// MokorinAvatarView.swift
// Mokorin
//
// 送付された mokorin_2.html の SVG ベクターイラスト（双葉・もこもこ体・小さな足・ハート・頬・尻尾）を
// SwiftUI ネイティブ描画で完全再現したもこりん表示コンポーネント。
// アプリ全画面の MokorinAvatarView が即座にこのキャラクターに切り替わる。

import SwiftUI

struct MokorinAvatarView: View {
    var size: CGFloat = 64
    var pose: MokorinPose = MokorinPose()

    @State private var isBreathing = false
    @State private var actionProgress: CGFloat = 0
    @State private var mouthOpen = false

    var body: some View {
        NativeMokorinCharacterView(
            emotion: pose.emotion,
            isBreathing: isBreathing,
            mouthOpen: mouthOpen
        )
        .frame(width: size, height: size)
        // アクション（wave / jump / nod）アニメーション
        .offset(y: jumpOffset + nodOffset)
        .rotationEffect(.degrees(waveAngle), anchor: .bottom)
        .scaleEffect(x: 1.0, y: isBreathing ? 1.025 : 0.985, anchor: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
            updateSpeakingAnimation(pose.speaking)
        }
        .onChange(of: pose.actionID) { _, _ in
            triggerAction(pose.action)
        }
        .onChange(of: pose.speaking) { _, speaking in
            updateSpeakingAnimation(speaking)
        }
        .accessibilityElement()
        .accessibilityLabel("もこりん")
        .accessibilityValue(Self.emotionDescription(pose.emotion))
        .accessibilityIdentifier("mokorin_avatar")
    }

    private var jumpOffset: CGFloat {
        guard pose.action == .jump else { return 0 }
        return -sin(actionProgress * .pi) * (size * 0.14)
    }

    private var nodOffset: CGFloat {
        guard pose.action == .nod else { return 0 }
        return sin(actionProgress * .pi * 2) * (size * 0.04)
    }

    private var waveAngle: Double {
        guard pose.action == .wave else { return 0 }
        return sin(Double(actionProgress) * .pi * 4) * 7.0
    }

    private func triggerAction(_ action: MokorinAction?) {
        guard action != nil else { return }
        actionProgress = 0
        withAnimation(.easeInOut(duration: 1.1)) {
            actionProgress = 1.0
        }
    }

    private func updateSpeakingAnimation(_ speaking: Bool) {
        if speaking {
            withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) {
                mouthOpen = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                mouthOpen = false
            }
        }
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

// MARK: - NativeMokorinCharacterView (mokorin_2.html SVG 1:1 再現)

private struct NativeMokorinCharacterView: View {
    let emotion: MokorinEmotion
    let isBreathing: Bool
    let mouthOpen: Bool

    // SVG viewBox="0 0 220 260" を正方形枠内で中央配置する変換ヘルパー
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 220.0, geo.size.height / 260.0)
            let offsetX = (geo.size.width - 220.0 * s) / 2.0
            let offsetY = (geo.size.height - 260.0 * s) / 2.0

            ZStack(alignment: .topLeading) {
                // 1. 尻尾（体の後ろ・右下）
                MokorinTailShape()
                    .fill(Color(hex: 0xFFFAF0))
                    .overlay(
                        MokorinTailShape()
                            .stroke(Color(hex: 0xD5BEA1), style: StrokeStyle(lineWidth: 2.0 * s, lineJoin: .round))
                    )

                // 2. 双葉（sprout）
                MokorinSproutView(scale: s, isBreathing: isBreathing)

                // 3. 足（左右）
                MokorinLeftFootShape()
                    .fill(Color(hex: 0xFFFAF0))
                    .overlay(
                        MokorinLeftFootShape()
                            .stroke(Color(hex: 0xD5BEA1), style: StrokeStyle(lineWidth: 1.8 * s, lineJoin: .round))
                    )

                MokorinRightFootShape()
                    .fill(Color(hex: 0xFFFAF0))
                    .overlay(
                        MokorinRightFootShape()
                            .stroke(Color(hex: 0xD5BEA1), style: StrokeStyle(lineWidth: 1.8 * s, lineJoin: .round))
                    )

                // 4. もこもこの体（body）
                MokorinBodyShape()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: 0xFFFEFA), location: 0.0),
                                .init(color: Color(hex: 0xFFFAF0), location: 0.65),
                                .init(color: Color(hex: 0xF5E9D8), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: UnitPoint(x: 0.8, y: 1.0)
                        )
                    )
                    .shadow(color: Color.black.opacity(0.14), radius: 2.5 * s, y: 1.5 * s)
                    .overlay(
                        MokorinBodyShape()
                            .stroke(Color(hex: 0xD5BEA1), style: StrokeStyle(lineWidth: 2.1 * s, lineJoin: .round))
                    )

                // 体の柔らかいハイライト光
                MokorinBodyLightShape()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.85), Color.white.opacity(0.0)],
                            center: UnitPoint(x: 0.35, y: 0.25),
                            startRadius: 0,
                            endRadius: 140 * s
                        )
                    )
                    .opacity(0.7)

                // 5. 顔パーツ（目・頬・鼻・口）
                MokorinFaceView(emotion: emotion, scale: s, mouthOpen: mouthOpen)

                // 6. 胸のハート
                MokorinHeartShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFD0C4), Color(hex: 0xF2A99D)],
                            startPoint: .topLeading,
                            endPoint: UnitPoint(x: 0.8, y: 1.0)
                        )
                    )
                    .overlay(
                        MokorinHeartShape()
                            .stroke(Color(hex: 0xE7A99B), style: StrokeStyle(lineWidth: 1.5 * s, lineJoin: .round))
                    )

                // 7. 両手（ハートを抱えるクリーム色の手）
                MokorinLeftArmShape()
                    .fill(Color(hex: 0xFFFAF0))
                    .overlay(
                        MokorinLeftArmShape()
                            .stroke(Color(hex: 0xD5BEA1), style: StrokeStyle(lineWidth: 2.0 * s, lineJoin: .round))
                    )

                MokorinRightArmShape()
                    .fill(Color(hex: 0xFFFAF0))
                    .overlay(
                        MokorinRightArmShape()
                            .stroke(Color(hex: 0xD5BEA1), style: StrokeStyle(lineWidth: 2.0 * s, lineJoin: .round))
                    )
            }
            .frame(width: 220 * s, height: 260 * s)
            .offset(x: offsetX, y: offsetY)
        }
    }
}

// MARK: - 双葉コンポーネント

private struct MokorinSproutView: View {
    let scale: CGFloat
    let isBreathing: Bool

    var body: some View {
        ZStack {
            // 茎
            Path { p in
                p.move(to: CGPoint(x: 110 * scale, y: 75 * scale))
                p.addCurve(
                    to: CGPoint(x: 110 * scale, y: 27 * scale),
                    control1: CGPoint(x: 109 * scale, y: 57 * scale),
                    control2: CGPoint(x: 110 * scale, y: 42 * scale)
                )
            }
            .stroke(Color(hex: 0x819B58), style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round))

            // 左の葉
            MokorinLeftLeafShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xBDCF8B), Color(hex: 0x829D51)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    MokorinLeftLeafShape()
                        .stroke(Color(hex: 0x91A56D), lineWidth: 1.2 * scale)
                )

            // 左葉脈
            Path { p in
                p.move(to: CGPoint(x: 108 * scale, y: 35 * scale))
                p.addQuadCurve(to: CGPoint(x: 84 * scale, y: 14 * scale), control: CGPoint(x: 96 * scale, y: 25 * scale))
            }
            .stroke(Color(hex: 0x81975C).opacity(0.6), lineWidth: 1.1 * scale)

            // 右の葉
            MokorinRightLeafShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xBDCF8B), Color(hex: 0x829D51)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    MokorinRightLeafShape()
                        .stroke(Color(hex: 0x91A56D), lineWidth: 1.2 * scale)
                )

            // 右葉脈
            Path { p in
                p.move(to: CGPoint(x: 115 * scale, y: 38 * scale))
                p.addQuadCurve(to: CGPoint(x: 145 * scale, y: 9 * scale), control: CGPoint(x: 130 * scale, y: 24 * scale))
            }
            .stroke(Color(hex: 0x81975C).opacity(0.6), lineWidth: 1.1 * scale)
        }
        .rotationEffect(.degrees(isBreathing ? 2.5 : -2.5), anchor: UnitPoint(x: 0.5, y: 0.28))
    }
}

// MARK: - 顔パーツ（表情連動）

private struct MokorinFaceView: View {
    let emotion: MokorinEmotion
    let scale: CGFloat
    let mouthOpen: Bool

    private let darkBrown = Color(hex: 0x594536)
    private let noseBrown = Color(hex: 0x80604C)
    private let cheekPink = Color(hex: 0xF8C9B7)

    var body: some View {
        ZStack {
            // 頬（左・右）
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [cheekPink.opacity(emotion == .happy ? 0.85 : 0.65), cheekPink.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 17 * scale
                    )
                )
                .frame(width: 34 * scale, height: 24 * scale)
                .position(x: 65 * scale, y: 145 * scale)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [cheekPink.opacity(emotion == .happy ? 0.85 : 0.65), cheekPink.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 17 * scale
                    )
                )
                .frame(width: 34 * scale, height: 24 * scale)
                .position(x: 157 * scale, y: 151 * scale)

            // 目（表情によって切り替え）
            switch emotion {
            case .happy:
                // にっこりアーチ目
                happyEye(cx: 78, cy: 125)
                happyEye(cx: 143, cy: 129)

            case .sleepy:
                // とろんとした半目ライン
                sleepyEye(cx: 78, cy: 126)
                sleepyEye(cx: 143, cy: 130)

            case .sad:
                // 少し垂れ眉＋うるうる目
                normalEye(cx: 78, cy: 126)
                normalEye(cx: 143, cy: 130)
                sadBrow(cx: 78, cy: 112, isLeft: true)
                sadBrow(cx: 143, cy: 116, isLeft: false)

            case .calm:
                // SVG 標準のつぶらな瞳＋ハイライト
                normalEye(cx: 78, cy: 125)
                normalEye(cx: 143, cy: 129)
            }

            // 鼻
            Ellipse()
                .fill(noseBrown)
                .frame(width: 7.0 * scale, height: 5.4 * scale)
                .position(x: 110 * scale, y: 135 * scale)

            // 口（ω型のやさしい猫口 ＋ 読み上げ時の口パク）
            if mouthOpen {
                Ellipse()
                    .fill(Color(hex: 0xE58E82))
                    .overlay(Ellipse().stroke(noseBrown, lineWidth: 1.8 * scale))
                    .frame(width: 12 * scale, height: 10 * scale)
                    .position(x: 110 * scale, y: 144 * scale)
            } else {
                Path { p in
                    // 左カーブ: M110 138 C109 146 99 148 94 142
                    p.move(to: CGPoint(x: 110 * scale, y: 138 * scale))
                    p.addCurve(
                        to: CGPoint(x: 94 * scale, y: 142 * scale),
                        control1: CGPoint(x: 109 * scale, y: 146 * scale),
                        control2: CGPoint(x: 99 * scale, y: 148 * scale)
                    )
                    // 右カーブ: M110 138 C111 146 121 148 126 142
                    p.move(to: CGPoint(x: 110 * scale, y: 138 * scale))
                    p.addCurve(
                        to: CGPoint(x: 126 * scale, y: 142 * scale),
                        control1: CGPoint(x: 111 * scale, y: 146 * scale),
                        control2: CGPoint(x: 121 * scale, y: 148 * scale)
                    )
                }
                .stroke(noseBrown, style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round))
            }
        }
    }

    @ViewBuilder
    private func normalEye(cx: CGFloat, cy: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(darkBrown)
                .frame(width: 14.4 * scale, height: 20.0 * scale)
                .position(x: cx * scale, y: cy * scale)

            Ellipse()
                .fill(Color(hex: 0xFFFDF7))
                .frame(width: 4.6 * scale, height: 5.6 * scale)
                .position(x: (cx + 2) * scale, y: (cy - 4) * scale)
        }
    }

    @ViewBuilder
    private func happyEye(cx: CGFloat, cy: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: (cx - 8) * scale, y: (cy + 2) * scale))
            p.addQuadCurve(
                to: CGPoint(x: (cx + 8) * scale, y: (cy + 2) * scale),
                control: CGPoint(x: cx * scale, y: (cy - 9) * scale)
            )
        }
        .stroke(darkBrown, style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round))
    }

    @ViewBuilder
    private func sleepyEye(cx: CGFloat, cy: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: (cx - 8) * scale, y: cy * scale))
            p.addQuadCurve(
                to: CGPoint(x: (cx + 8) * scale, y: cy * scale),
                control: CGPoint(x: cx * scale, y: (cy + 4) * scale)
            )
        }
        .stroke(darkBrown, style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))
    }

    @ViewBuilder
    private func sadBrow(cx: CGFloat, cy: CGFloat, isLeft: Bool) -> some View {
        Path { p in
            p.move(to: CGPoint(x: (cx - 7) * scale, y: (cy + (isLeft ? 2 : -2)) * scale))
            p.addLine(to: CGPoint(x: (cx + 7) * scale, y: (cy + (isLeft ? -2 : 2)) * scale))
        }
        .stroke(darkBrown.opacity(0.75), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
    }
}

// MARK: - SVG パス完全変換 Shapes (viewBox: 220 x 260)

private struct MokorinBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(110, 72))
        p.addCurve(to: pt(76, 75),   control1: pt(99, 64),   control2: pt(85, 65))
        p.addCurve(to: pt(45, 96),   control1: pt(61, 70),   control2: pt(47, 80))
        p.addCurve(to: pt(29, 131),  control1: pt(29, 102),  control2: pt(25, 116))
        p.addCurve(to: pt(20, 170),  control1: pt(14, 140),  control2: pt(12, 157))
        p.addCurve(to: pt(29, 205),  control1: pt(12, 184),  control2: pt(17, 198))
        p.addCurve(to: pt(54, 233),  control1: pt(25, 221),  control2: pt(38, 233))
        p.addCurve(to: pt(89, 237),  control1: pt(63, 244),  control2: pt(78, 244))
        p.addCurve(to: pt(124, 237), control1: pt(101, 244), control2: pt(115, 244))
        p.addCurve(to: pt(162, 235), control1: pt(137, 245), control2: pt(153, 243))
        p.addCurve(to: pt(192, 212), control1: pt(180, 240), control2: pt(195, 228))
        p.addCurve(to: pt(201, 176), control1: pt(207, 205), control2: pt(211, 189))
        p.addCurve(to: pt(195, 137), control1: pt(211, 162), control2: pt(205, 146))
        p.addCurve(to: pt(180, 99),  control1: pt(201, 120), control2: pt(193, 104))
        p.addCurve(to: pt(150, 76),  control1: pt(180, 83),  control2: pt(165, 72))
        p.addCurve(to: pt(110, 72),  control1: pt(139, 65),  control2: pt(122, 65))
        p.closeSubpath()
        return p
    }
}

private struct MokorinBodyLightShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(110, 76))
        p.addCurve(to: pt(52, 103),  control1: pt(88, 69),   control2: pt(62, 82))
        p.addCurve(to: pt(39, 173),  control1: pt(36, 124),  control2: pt(34, 150))
        p.addCurve(to: pt(72, 229),  control1: pt(31, 199),  control2: pt(48, 222))
        p.addCurve(to: pt(155, 229), control1: pt(96, 237),  control2: pt(133, 235))
        p.addCurve(to: pt(188, 179), control1: pt(179, 223), control2: pt(193, 202))
        p.addCurve(to: pt(170, 94),  control1: pt(198, 149), control2: pt(190, 113))
        p.addCurve(to: pt(110, 76),  control1: pt(154, 77),  control2: pt(130, 72))
        p.closeSubpath()
        return p
    }
}

private struct MokorinTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(170, 190))
        p.addCurve(to: pt(207, 204), control1: pt(184, 184), control2: pt(201, 190))
        p.addCurve(to: pt(187, 239), control1: pt(214, 220), control2: pt(204, 237))
        p.addCurve(to: pt(166, 222), control1: pt(176, 240), control2: pt(168, 232))
        p.addCurve(to: pt(170, 190), control1: pt(177, 218), control2: pt(181, 202))
        p.closeSubpath()
        return p
    }
}

private struct MokorinLeftLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(109, 39))
        p.addCurve(to: pt(77, 8),   control1: pt(91, 35),  control2: pt(76, 21))
        p.addCurve(to: pt(110, 34), control1: pt(94, 5),   control2: pt(107, 18))
        p.addCurve(to: pt(109, 39), control1: pt(111, 37), control2: pt(110, 39))
        p.closeSubpath()
        return p
    }
}

private struct MokorinRightLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(111, 38))
        p.addCurve(to: pt(151, 3),  control1: pt(112, 20), control2: pt(127, 5))
        p.addCurve(to: pt(116, 43), control1: pt(154, 22), control2: pt(139, 39))
        p.addCurve(to: pt(111, 38), control1: pt(113, 43), control2: pt(111, 41))
        p.closeSubpath()
        return p
    }
}

private struct MokorinLeftFootShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(48, 226))
        p.addCurve(to: pt(53, 247), control1: pt(42, 231), control2: pt(43, 242))
        p.addCurve(to: pt(81, 240), control1: pt(63, 252), control2: pt(78, 248))
        p.addCurve(to: pt(68, 230), control1: pt(83, 233), control2: pt(76, 228))
        p.addCurve(to: pt(48, 226), control1: pt(60, 225), control2: pt(53, 223))
        p.closeSubpath()
        return p
    }
}

private struct MokorinRightFootShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(139, 240))
        p.addCurve(to: pt(166, 247), control1: pt(142, 248), control2: pt(156, 252))
        p.addCurve(to: pt(170, 227), control1: pt(176, 242), control2: pt(177, 232))
        p.addCurve(to: pt(150, 230), control1: pt(164, 224), control2: pt(156, 228))
        p.addCurve(to: pt(139, 240), control1: pt(143, 228), control2: pt(137, 233))
        p.closeSubpath()
        return p
    }
}

private struct MokorinHeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(110, 204))
        p.addCurve(to: pt(76, 166),  control1: pt(101, 198), control2: pt(76, 183))
        p.addCurve(to: pt(110, 165), control1: pt(76, 151),  control2: pt(93, 148))
        p.addCurve(to: pt(144, 166), control1: pt(127, 148), control2: pt(144, 151))
        p.addCurve(to: pt(110, 204), control1: pt(144, 183), control2: pt(119, 198))
        p.closeSubpath()
        return p
    }
}

private struct MokorinLeftArmShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(77, 163))
        p.addCurve(to: pt(87, 186), control1: pt(84, 168), control2: pt(89, 178))
        p.addCurve(to: pt(68, 195), control1: pt(85, 195), control2: pt(77, 199))
        p.addCurve(to: pt(61, 177), control1: pt(60, 192), control2: pt(57, 185))
        p.addCurve(to: pt(77, 163), control1: pt(65, 170), control2: pt(71, 165))
        p.closeSubpath()
        return p
    }
}

private struct MokorinRightArmShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220.0
        let sy = rect.height / 260.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var p = Path()
        p.move(to: pt(143, 163))
        p.addCurve(to: pt(133, 186), control1: pt(136, 168), control2: pt(131, 178))
        p.addCurve(to: pt(152, 195), control1: pt(135, 195), control2: pt(143, 199))
        p.addCurve(to: pt(159, 177), control1: pt(160, 192), control2: pt(163, 185))
        p.addCurve(to: pt(143, 163), control1: pt(155, 170), control2: pt(149, 165))
        p.closeSubpath()
        return p
    }
}

// MARK: - Color Hex Helper

private extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

#Preview {
    VStack(spacing: 20) {
        MokorinAvatarView(size: 160, pose: MokorinPose(emotion: .calm))
        HStack(spacing: 16) {
            MokorinAvatarView(size: 80, pose: MokorinPose(emotion: .happy))
            MokorinAvatarView(size: 80, pose: MokorinPose(emotion: .sad))
            MokorinAvatarView(size: 80, pose: MokorinPose(emotion: .sleepy))
        }
    }
    .padding()
    .background(Color.black)
}
