//
//  HandAcupressureGuideView.swift
//  MindWaveGraphic
//
//  手のひら・手首にある代表的なリラックスツボを
//  タップで確認したり、順番にガイドしてもらいながら
//  押せるSwiftUIビュー（ディープネイビー＆シアンテーマ）。
//
//  ※ ここで示すツボの位置・効果は一般的なセルフケアの目安であり、
//     医療的な診断・治療を目的としたものではありません。
//     体調に不安がある場合は医療機関にご相談ください。
//

import SwiftUI
import UIKit

// MARK: - モデル

struct PressurePoint: Identifiable {
    let id = UUID()
    let name: String          // 日本語名
    let reading: String       // 読み仮名
    let code: String          // 経穴コード(参考)
    let position: CGPoint     // 手の図の中での位置(0〜1の割合)
    let effect: String        // 効果の説明
    let howTo: String         // 押し方
}

let handPressurePoints: [PressurePoint] = [
    PressurePoint(
        name: "労宮",
        reading: "ろうきゅう",
        code: "PC8",
        position: CGPoint(x: 0.583, y: 0.553),
        effect: "手のひらの中央。軽く握ったとき中指の先が触れるあたり。気持ちを落ち着かせ、緊張や興奮を鎮めるといわれます。",
        howTo: "反対の親指で、心地よい強さで5秒押して離す ×5回"
    ),
    PressurePoint(
        name: "合谷",
        reading: "ごうこく",
        code: "LI4",
        position: CGPoint(x: 0.395, y: 0.480),
        effect: "親指と人差し指の骨が合わさる少し人差し指寄りのくぼみ。万能のツボとも呼ばれ、肩こり・頭のこわばり・ストレス緩和によく使われます。",
        howTo: "反対の親指で骨の下に向かって、やや強めに5秒×5回"
    ),
    PressurePoint(
        name: "神門",
        reading: "しんもん",
        code: "HT7",
        position: CGPoint(x: 0.646, y: 0.745),
        effect: "手首の横じわ、小指側のくぼみ。自律神経のバランスを整え、不安や寝つきの悪さのケアに使われます。",
        howTo: "反対の親指で軽く3〜5秒押す ×5回"
    ),
    PressurePoint(
        name: "内関",
        reading: "ないかん",
        code: "PC6",
        position: CGPoint(x: 0.517, y: 0.877),
        effect: "手首の横じわから指幅3本分ひじ側、2本の腱の間。胸のつかえや緊張、乗り物酔いのケアによく使われます。",
        howTo: "反対の親指で5秒押して離す ×5回"
    )
]

// MARK: - カラーパレット（アプリの宇宙・コックピットテーマに統一）

private enum AcupressureTheme {
    static let bgTop       = Color(red: 0.035, green: 0.065, blue: 0.16)
    static let bgBottom    = Color(red: 0.012, green: 0.020, blue: 0.065)
    static let cardFill    = Color(red: 0.030, green: 0.055, blue: 0.14)
    static let accentCyan  = Color(hue: 0.55, saturation: 0.88, brightness: 0.96)
    static let deepBlue    = Color(hue: 0.62, saturation: 0.90, brightness: 0.92)
    static let iceBlue     = Color(red: 0.72, green: 0.92, blue: 1.0)
}

// MARK: - 背景(深宇宙にゆっくり漂う青い光のぼかし)

private struct AcupressureAmbientBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AcupressureTheme.bgTop, AcupressureTheme.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geo in
                Circle()
                    .fill(AcupressureTheme.accentCyan.opacity(0.18))
                    .frame(width: 260, height: 260)
                    .blur(radius: 75)
                    .offset(x: drift ? -40 : 30, y: drift ? 40 : -10)
                    .position(x: geo.size.width * 0.15, y: geo.size.height * 0.18)

                Circle()
                    .fill(AcupressureTheme.deepBlue.opacity(0.24))
                    .frame(width: 300, height: 300)
                    .blur(radius: 85)
                    .offset(x: drift ? 30 : -30, y: drift ? -30 : 40)
                    .position(x: geo.size.width * 0.90, y: geo.size.height * 0.50)

                Circle()
                    .fill(Color.blue.opacity(0.20))
                    .frame(width: 240, height: 240)
                    .blur(radius: 75)
                    .offset(x: drift ? -20 : 40, y: drift ? 20 : -30)
                    .position(x: geo.size.width * 0.30, y: geo.size.height * 0.90)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - 手のイラスト(画像 "hand" があれば使用、なければ青いHUD手のひらイラストを描画)

let handImageAspect: CGFloat = 720.0 / 1040.0

private struct HandIllustration: View {
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // 手の後ろのやわらかい青い光(ハロー)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AcupressureTheme.accentCyan.opacity(0.26),
                                AcupressureTheme.deepBlue.opacity(0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: w * 0.65
                        )
                    )
                    .frame(width: w * 1.4, height: w * 1.4)
                    .position(x: w * 0.5, y: h * 0.48)

                if UIImage(named: "hand") != nil {
                    // 手の輪郭ににじむシアンのグロー
                    Image("hand")
                        .resizable()
                        .scaledToFit()
                        .colorMultiply(AcupressureTheme.accentCyan)
                        .blur(radius: 14)
                        .opacity(0.55)
                        .frame(width: w, height: h)

                    // 実写の手
                    Image("hand")
                        .resizable()
                        .scaledToFit()
                        .frame(width: w, height: h)
                } else {
                    // 画像未登録時でも座標(労宮/合谷/神門/内関)にピタッと合う青いホログラムの手
                    BlueHologramHandShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AcupressureTheme.accentCyan.opacity(0.16),
                                    AcupressureTheme.deepBlue.opacity(0.10)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: w, height: h)

                    BlueHologramHandShape()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AcupressureTheme.iceBlue.opacity(0.85),
                                    AcupressureTheme.accentCyan.opacity(0.65)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2.0
                        )
                        .shadow(color: AcupressureTheme.accentCyan.opacity(0.75), radius: 8)
                        .frame(width: w, height: h)

                    // 手のひら・手首のしわ（ホログラム細部ライン）
                    HandPalmLinesShape()
                        .stroke(AcupressureTheme.accentCyan.opacity(0.32), lineWidth: 1.2)
                        .frame(width: w, height: h)
                }
            }
            .scaleEffect(breathe ? 1.015 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
        }
    }
}

/// 労宮(0.583, 0.553)・合谷(0.395, 0.480)・神門(0.646, 0.745)・内関(0.517, 0.877)の座標に合わせた左手ひらシルエット
private struct BlueHologramHandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: w * x, y: h * y)
        }

        var path = Path()
        // 手首左下からスタート
        path.move(to: p(0.42, 0.96))
        // 前腕左〜親指付け根
        path.addCurve(to: p(0.38, 0.68), control1: p(0.42, 0.85), control2: p(0.41, 0.74))
        // 親指外側〜先端
        path.addCurve(to: p(0.18, 0.45), control1: p(0.30, 0.61), control2: p(0.21, 0.52))
        path.addCurve(to: p(0.24, 0.40), control1: p(0.16, 0.41), control2: p(0.20, 0.38))
        // 親指内側〜合谷のくぼみ(0.395, 0.480)
        path.addCurve(to: p(0.39, 0.47), control1: p(0.30, 0.43), control2: p(0.35, 0.48))
        // 人差し指
        path.addCurve(to: p(0.41, 0.14), control1: p(0.39, 0.34), control2: p(0.39, 0.21))
        path.addCurve(to: p(0.48, 0.14), control1: p(0.42, 0.10), control2: p(0.47, 0.10))
        path.addLine(to: p(0.49, 0.36))
        // 中指
        path.addCurve(to: p(0.54, 0.08), control1: p(0.50, 0.24), control2: p(0.51, 0.13))
        path.addCurve(to: p(0.61, 0.09), control1: p(0.55, 0.04), control2: p(0.60, 0.05))
        path.addLine(to: p(0.60, 0.36))
        // 薬指
        path.addCurve(to: p(0.67, 0.13), control1: p(0.62, 0.25), control2: p(0.64, 0.17))
        path.addCurve(to: p(0.73, 0.15), control1: p(0.69, 0.10), control2: p(0.73, 0.11))
        path.addLine(to: p(0.69, 0.40))
        // 小指
        path.addCurve(to: p(0.78, 0.24), control1: p(0.72, 0.32), control2: p(0.75, 0.27))
        path.addCurve(to: p(0.83, 0.27), control1: p(0.80, 0.21), control2: p(0.84, 0.23))
        // 小指外側〜手のひら右縁〜神門(0.646, 0.745)付近
        path.addCurve(to: p(0.73, 0.66), control1: p(0.81, 0.41), control2: p(0.78, 0.55))
        path.addCurve(to: p(0.65, 0.76), control1: p(0.70, 0.71), control2: p(0.67, 0.74))
        // 手首右側〜右下(内関 0.517, 0.877 を含む手首幅)
        path.addCurve(to: p(0.63, 0.96), control1: p(0.64, 0.83), control2: p(0.63, 0.90))
        path.closeSubpath()
        return path
    }
}

private struct HandPalmLinesShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: w * x, y: h * y)
        }

        var path = Path()
        // 手首の横じわ（神門ライン）
        path.move(to: p(0.43, 0.745))
        path.addQuadCurve(to: p(0.65, 0.745), control: p(0.54, 0.76))
        // 感情線・頭脳線風のホログラムガイド線
        path.move(to: p(0.46, 0.47))
        path.addQuadCurve(to: p(0.72, 0.45), control: p(0.60, 0.49))
        path.move(to: p(0.43, 0.51))
        path.addQuadCurve(to: p(0.68, 0.58), control: p(0.56, 0.53))
        return path
    }
}

// MARK: - ツボのマーカー(シアン波紋・HUD名前ラベル付き)

private struct PressurePointMarker: View {
    let point: PressurePoint
    let isActive: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @State private var ripple = false
    @State private var idleGlow = false

    private var highlighted: Bool { isActive || isSelected }

    var body: some View {
        ZStack {
            Circle()
                .fill(AcupressureTheme.accentCyan.opacity(0.38))
                .frame(width: 34, height: 34)
                .blur(radius: 6)
                .scaleEffect(idleGlow ? 1.25 : 0.85)
                .opacity(highlighted ? 0 : 1)

            if highlighted {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(AcupressureTheme.accentCyan.opacity(0.80), lineWidth: 2.2)
                        .frame(width: 24, height: 24)
                        .scaleEffect(ripple ? 2.8 : 1.0)
                        .opacity(ripple ? 0 : 0.9)
                        .animation(
                            .easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.75),
                            value: ripple
                        )
                }
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: highlighted
                            ? [Color.white, AcupressureTheme.accentCyan]
                            : [Color.white, AcupressureTheme.iceBlue],
                        center: .center,
                        startRadius: 1,
                        endRadius: 12
                    )
                )
                .frame(width: highlighted ? 24 : 20, height: highlighted ? 24 : 20)
                .overlay(Circle().stroke(AcupressureTheme.accentCyan, lineWidth: 2))
                .shadow(
                    color: AcupressureTheme.accentCyan.opacity(highlighted ? 0.95 : 0.55),
                    radius: highlighted ? 8 : 3
                )

            if highlighted {
                Text(point.name)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AcupressureTheme.cardFill.opacity(0.92))
                            .overlay(
                                Capsule()
                                    .strokeBorder(AcupressureTheme.accentCyan.opacity(0.85), lineWidth: 1.0)
                            )
                    )
                    .shadow(color: AcupressureTheme.accentCyan.opacity(0.55), radius: 5)
                    .offset(y: -30)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: highlighted)
        .contentShape(Circle().inset(by: -10))
        .onAppear {
            ripple = true
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                idleGlow = true
            }
        }
        .onTapGesture(perform: onTap)
    }
}

// MARK: - ツボ詳細カード

private struct PressurePointDetailCard: View {
    let point: PressurePoint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(point.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("(\(point.reading))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.60))
                Spacer()
                Text(point.code)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AcupressureTheme.accentCyan)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(AcupressureTheme.accentCyan.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(AcupressureTheme.accentCyan.opacity(0.45), lineWidth: 0.8)
                    )
                    .clipShape(Capsule())
            }

            Text(point.effect)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(3)

            Label(point.howTo, systemImage: "hand.point.up.left.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AcupressureTheme.accentCyan)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AcupressureTheme.cardFill.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [
                            AcupressureTheme.accentCyan.opacity(0.50),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: AcupressureTheme.accentCyan.opacity(0.12), radius: 10)
    }
}

// MARK: - メインビュー

struct HandAcupressureGuideView: View {

    enum Mode: String, CaseIterable {
        case free = "自由に見る"
        case guide = "順番にガイド"
    }

    @State private var mode: Mode = .free
    @State private var selectedPointID: PressurePoint.ID?
    @State private var guideIndex: Int = 0
    @State private var progress: CGFloat = 0
    @State private var timer: Timer?

    private let stepDuration: TimeInterval = 6.0

    var body: some View {
        ZStack {
            AcupressureAmbientBackground()

            ScrollView {
                VStack(spacing: 18) {

                    // 上部の戻るボタンと被らないよう余白を確保
                    Text("緊張緩和ストレッチ")
                        .font(.system(.title, design: .rounded).bold())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, AcupressureTheme.iceBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: AcupressureTheme.accentCyan.opacity(0.35), radius: 8)
                        .padding(.top, 42)

                    Text("手のひらのツボをやさしく押して、気持ちを落ち着けましょう")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Picker("モード", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: mode) { _, newValue in
                        if newValue == .guide {
                            startGuide()
                        } else {
                            stopGuide()
                        }
                    }

                    // 手のイラスト + マーカー
                    GeometryReader { geo in
                        ZStack {
                            HandIllustration()

                            ForEach(handPressurePoints) { point in
                                PressurePointMarker(
                                    point: point,
                                    isActive: mode == .guide && currentGuidePoint?.id == point.id,
                                    isSelected: selectedPointID == point.id,
                                    onTap: { tapped(point) }
                                )
                                .position(
                                    x: geo.size.width * point.position.x,
                                    y: geo.size.height * point.position.y
                                )
                            }
                        }
                    }
                    .frame(width: 290, height: 290 / handImageAspect)
                    .padding(.vertical, 6)

                    // ガイドモード中の進捗と案内
                    if mode == .guide, let current = currentGuidePoint {
                        VStack(spacing: 10) {
                            Text("\(guideIndex + 1) / \(handPressurePoints.count)  \(current.name)を押しましょう")
                                .font(.headline)
                                .foregroundStyle(.white)

                            ProgressView(value: progress)
                                .tint(AcupressureTheme.accentCyan)
                                .padding(.horizontal, 40)

                            Text(current.howTo)
                                .font(.subheadline)
                                .foregroundStyle(AcupressureTheme.iceBlue.opacity(0.8))
                        }
                    }

                    // 詳細カード
                    if let point = displayedPoint {
                        PressurePointDetailCard(point: point)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .animation(.easeInOut, value: point.id)
                    }

                    if mode == .free {
                        Text("ツボの丸をタップすると詳しい説明が表示されます")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Text("※ 医療的な診断・治療を目的としたものではありません")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 4)
                }
                .padding(.vertical)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: selectedPointID)
        .sensoryFeedback(.impact(weight: .light), trigger: guideIndex)
        .onDisappear { stopGuide() }
    }

    private var displayedPoint: PressurePoint? {
        if mode == .guide {
            return currentGuidePoint
        }
        return handPressurePoints.first { $0.id == selectedPointID }
    }

    private var currentGuidePoint: PressurePoint? {
        guard handPressurePoints.indices.contains(guideIndex) else { return nil }
        return handPressurePoints[guideIndex]
    }

    private func tapped(_ point: PressurePoint) {
        withAnimation {
            selectedPointID = (selectedPointID == point.id) ? nil : point.id
        }
    }

    private func startGuide() {
        guideIndex = 0
        progress = 0
        selectedPointID = nil
        runStep()
    }

    private func stopGuide() {
        timer?.invalidate()
        timer = nil
        progress = 0
    }

    private func runStep() {
        timer?.invalidate()
        progress = 0
        let interval: TimeInterval = 0.05
        var elapsed: TimeInterval = 0

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            elapsed += interval
            progress = min(CGFloat(elapsed / stepDuration), 1.0)

            if elapsed >= stepDuration {
                t.invalidate()
                advanceGuide()
            }
        }
    }

    private func advanceGuide() {
        if guideIndex < handPressurePoints.count - 1 {
            guideIndex += 1
            runStep()
        } else {
            mode = .free
            stopGuide()
        }
    }
}

#Preview {
    HandAcupressureGuideView()
}
