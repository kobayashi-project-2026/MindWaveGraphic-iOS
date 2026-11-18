// HarukaSpaceGraphicView.swift
// Graphics
//
// 宇宙グラフィック。制作: HarukaSasaki-bit さん（GitHub ブランチ feature/HarukaSasaki-bit-space、
// 2967634「Update spaceship state graphic effects」の SpaceshipStateGraphicView.swift にある
// StarfieldView・LightningView・MocorinSeatView）を、本番の GraphicInput で動くように移植したもの。
//
// 移植で変えたこと（元の見た目・動きの式はそのまま使う）:
// - 入力: 元の @State のスコアと Slider ではなく、GraphicInput.score（0〜100）を受け取る。Slider はプレビューだけ
// - 隕石: 元は画像 "inseki" を描くが、画像がリポジトリにないため Canvas の図形（岩の形・クレーター・尾）で描く
// - コックピット: 元は画像 "cockpit" を重ねるが、画像がないためホーム既存の CockpitFrameCanvas をそのまま使う（この View では描かない）
// - 「STATUS : NORMAL / TENSION」の文字は出さない（未計測を「NORMAL」と断定しないため。状態はホームの状態カードが表示する）
// - 未計測（GraphicDataStatus.unmeasured）は待機の表示: 星はゆっくり流れるだけで、隕石・雷・軌跡を出さない
// - 視差効果を減らす（Reduce Motion）が ON のときは、星の速さを抑え、雷は点滅させずに薄く表示し、画面のフラッシュを出さない
// - 星の色と中心の光をスコアに合わせて変える（低い: 青白い / 中: 白 / 高い: 暖色）。中心の光は既存グラフィックの考え方を残したもの
//
// データの取得・計算はしない（GraphicInput と表示用の状態だけを受け取る。Graphics/README.md の決まり）。

import SwiftUI

// MARK: - 表示用のデータの状態

/// グラフィックに渡す「値の出どころ」。GraphicInput は変えずに、ホームから環境値で渡す
enum GraphicDataStatus: Equatable, Sendable {
    /// 計測していない（値は既定の 50）。待機の表示にする
    case unmeasured
    /// デモ用の値（Mock・シミュレーターのデモ）
    case demo
    /// 本人の評価からの試作スコア
    case prototype
    /// 実測
    case measured
}

private struct GraphicDataStatusKey: EnvironmentKey {
    static let defaultValue: GraphicDataStatus = .measured
}

extension EnvironmentValues {
    var graphicDataStatus: GraphicDataStatus {
        get { self[GraphicDataStatusKey.self] }
        set { self[GraphicDataStatusKey.self] = newValue }
    }
}

// MARK: - 本体

struct HarukaSpaceGraphicView: View {
    let input: GraphicInput

    @Environment(\.graphicDataStatus) private var dataStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isStandby: Bool { dataStatus == .unmeasured }
    /// 演出に使うスコア（待機中は 0 = いちばん静か。値そのものは表示しない）
    private var score: Double { isStandby ? 0 : min(100, max(0, input.score)) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                HarukaStarfieldCanvas(score: score, confidence: input.confidence,
                                      standby: isStandby, reduceMotion: reduceMotion)

                if !isStandby {
                    HarukaLightningCanvas(score: score, reduceMotion: reduceMotion)
                }

                // もこりんの座席（元の位置: 幅 0.7・高さ 0.8。ホームでは下部をダッシュボードが覆うため少し上げる）
                HarukaMocorinSeatView(pose: mokorinPose)
                    .scaleEffect(min(1.1, max(0.8, geo.size.width / 393)))
                    .position(x: geo.size.width * 0.74, y: geo.size.height * 0.70)
                    .accessibilityHidden(true)
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var mokorinPose: MokorinPose {
        if isStandby { return MokorinPose(emotion: .sleepy) }
        return MokorinPose(emotion: input.state == .overTense ? .calm : .happy)
    }

    private var accessibilityText: String {
        if isStandby { return "宇宙のグラフィック。計測前のため待機中" }
        switch input.state {
        case .underAroused: return "宇宙のグラフィック。星がゆっくり流れている"
        case .optimalTension: return "宇宙のグラフィック。星と隕石が流れている"
        case .overTense: return "宇宙のグラフィック。星が速く流れ、雷が光っている"
        }
    }
}

// MARK: - 星空・隕石（元: StarfieldView）

struct HarukaStarfieldCanvas: View {
    let score: Double
    let confidence: Double
    let standby: Bool
    let reduceMotion: Bool

    private var intensity: Double { score / 100.0 }

    /// 元の式: 0.2 + intensity * 2.5。待機中・Reduce Motion では遅くする
    private var speed: Double {
        if standby { return 0.12 }
        let base = 0.2 + intensity * 2.5
        return reduceMotion ? base * 0.3 : base
    }

    /// 元の式: 33 未満 0 個・70 未満 20 個・それ以上 40 個（MindState の境界と同じ）
    private var meteorCount: Int {
        if standby { return 0 }
        if score < 33 { return 0 }
        if score < 70 { return 20 }
        return 40
    }

    /// 星の色（低い: 青白い → 中: 白 → 高い: 暖色）
    private var starColor: Color {
        if score < 33 { return Color(red: 0.78, green: 0.88, blue: 1.0) }
        if score < 70 { return .white }
        return Color(red: 1.0, green: 0.86, blue: 0.74)
    }

    /// 中心の光の色（既存グラフィックの緊張度の色の考え方: 青 → 水色・緑 → 黄 → 赤）
    private var coreColor: Color {
        let t = intensity
        if standby { return Color(red: 0.35, green: 0.45, blue: 0.75) }
        if t < 0.33 { return Color(hue: 0.62, saturation: 0.75, brightness: 0.95) }
        if t < 0.70 { return Color(hue: 0.62 - (t - 0.33) / 0.37 * 0.45, saturation: 0.75, brightness: 0.98) }
        return Color(hue: max(0, 0.13 - (t - 0.70) / 0.30 * 0.13), saturation: 0.9, brightness: 1.0)
    }

    private var starOpacity: Double {
        standby ? 0.5 : 0.75 + 0.25 * min(1, max(0, confidence))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerX = size.width / 2
                let centerY = size.height / 2

                // 中心の光
                let coreRadius = min(size.width, size.height) * (0.22 + intensity * 0.18)
                context.fill(
                    Path(ellipseIn: CGRect(x: centerX - coreRadius, y: centerY - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
                    with: .radialGradient(Gradient(colors: [coreColor.opacity(standby ? 0.18 : 0.38), coreColor.opacity(0)]),
                                          center: CGPoint(x: centerX, y: centerY), startRadius: 0, endRadius: coreRadius))

                // 通常の星（元: 800 個・奥から手前へ）
                for i in 0..<800 {
                    let seed = Double(i)
                    let x3d = CGFloat(sin(seed * 12.9898) * 300)
                    let y3d = CGFloat(cos(seed * 78.233) * 300)
                    var z = 1000 - (time * 200 * speed + seed * 17).truncatingRemainder(dividingBy: 1000)
                    if z < 1 { z = 1 }
                    let perspective = CGFloat(400 / z)
                    let x = centerX + x3d * perspective
                    let y = centerY + y3d * perspective
                    let starSize = min(max(1, perspective * 4), 4)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: starSize, height: starSize)),
                                 with: .color(starColor.opacity(starOpacity)))

                    // 星の軌跡（元: intensity > 0.3）
                    if !standby, intensity > 0.3 {
                        let trail = Double(starSize) * intensity * 10
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: centerX + x3d * CGFloat(400 / (z + trail)),
                                                 y: centerY + y3d * CGFloat(400 / (z + trail))))
                        context.stroke(path, with: .color(starColor.opacity(0.8 * starOpacity)), lineWidth: starSize * 0.5)
                    }
                }

                // 隕石（元: 画像 "inseki"。画像がないため図形で描く）
                for i in 0..<meteorCount {
                    let seed = Double(i * 137 + 1000)
                    let x3d = CGFloat(sin(seed * 15.23) * 350)
                    let y3d = CGFloat(cos(seed * 92.11) * 350)
                    let meteorSpeed = reduceMotion ? (250 + intensity * 400) * 0.3 : 250 + intensity * 400
                    var z = 1200 - (time * meteorSpeed + seed * 50).truncatingRemainder(dividingBy: 1200)
                    if z < 1 { z = 1 }
                    let perspective = CGFloat(500 / z)
                    let x = centerX + x3d * perspective
                    let y = centerY + y3d * perspective
                    let meteorSize = min(max(8, perspective * 80), 100)
                    let center = CGPoint(x: x + meteorSize / 2, y: y + meteorSize / 2)
                    Self.drawMeteor(in: &context, center: center, size: meteorSize, seed: i,
                                    vanishing: CGPoint(x: centerX, y: centerY), heat: intensity, flip: x > centerX)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// 隕石の図形: でこぼこの岩・クレーター・中心（奥）側へのびる尾。seed で形を固定する
    static func drawMeteor(in context: inout GraphicsContext, center: CGPoint, size: CGFloat, seed: Int,
                           vanishing: CGPoint, heat: Double, flip: Bool) {
        let r = size / 2
        // 尾（奥＝中心の方向へ。緊張が高いほど赤みが強い）
        let dx = vanishing.x - center.x, dy = vanishing.y - center.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        let tailLength = min(len, size * (0.7 + 0.5 * CGFloat(heat)))
        let tailEnd = CGPoint(x: center.x + dx / len * tailLength, y: center.y + dy / len * tailLength)
        var tail = Path()
        tail.move(to: center)
        tail.addLine(to: tailEnd)
        let tailColor = Color(red: 1.0, green: 0.55 + 0.3 * (1 - heat), blue: 0.25)
        context.stroke(tail, with: .linearGradient(Gradient(colors: [tailColor.opacity(0.35), tailColor.opacity(0)]),
                                                   startPoint: center, endPoint: tailEnd),
                       style: StrokeStyle(lineWidth: size * 0.18, lineCap: .round))

        context.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            if flip { layer.scaleBy(x: -1, y: 1) }
            layer.rotate(by: .radians(Double.pi / 6))   // 元の correctedAngle
            // 岩の輪郭（9 点。seed ごとに半径を変える）
            var rock = Path()
            let points = 9
            for k in 0..<points {
                let angle = Double(k) / Double(points) * 2 * Double.pi
                let jitter = 0.78 + 0.22 * abs(sin(Double(seed * 31 + k * 17) * 1.7))
                let p = CGPoint(x: CGFloat(cos(angle) * jitter) * r, y: CGFloat(sin(angle) * jitter) * r * 0.86)
                if k == 0 { rock.move(to: p) } else { rock.addLine(to: p) }
            }
            rock.closeSubpath()
            layer.fill(rock, with: .linearGradient(
                Gradient(colors: [Color(red: 0.62, green: 0.55, blue: 0.48), Color(red: 0.30, green: 0.25, blue: 0.22)]),
                startPoint: CGPoint(x: -r, y: -r), endPoint: CGPoint(x: r, y: r)))
            layer.stroke(rock, with: .color(Color(red: 0.18, green: 0.14, blue: 0.12).opacity(0.8)), lineWidth: max(0.5, r * 0.06))
            // クレーター
            for (cx, cy, cr) in [(-0.30, -0.15, 0.20), (0.25, 0.20, 0.15), (0.05, -0.38, 0.10)] {
                let rect = CGRect(x: CGFloat(cx) * r - CGFloat(cr) * r, y: CGFloat(cy) * r - CGFloat(cr) * r,
                                  width: CGFloat(cr) * r * 2, height: CGFloat(cr) * r * 2)
                layer.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.22, green: 0.18, blue: 0.16).opacity(0.75)))
            }
            // 光の当たる縁
            layer.stroke(Path(ellipseIn: CGRect(x: -r * 0.7, y: -r * 0.75, width: r * 0.9, height: r * 0.6)),
                         with: .color(.white.opacity(0.12)), lineWidth: max(0.5, r * 0.08))
        }
    }
}

// MARK: - 雷（元: LightningView）

struct HarukaLightningCanvas: View {
    let score: Double
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                // 元: 70 以上で表示
                guard score >= 70 else { return }
                // Reduce Motion では点滅させず、時刻を固定して薄く描く
                let time = reduceMotion ? 0.05 : timeline.date.timeIntervalSinceReferenceDate

                let count: Int
                let interval: Double
                let duration: Double
                let lineWidth: CGFloat
                if score < 80 {
                    count = 32; interval = 1.2; duration = 0.28; lineWidth = 1.5
                } else if score < 90 {
                    count = 24; interval = 1.0; duration = 0.30; lineWidth = 2.5
                } else {
                    count = 20; interval = 0.75; duration = 0.35; lineWidth = 4.0
                }
                let lightningColor: Color = score < 80 ? .cyan : (score < 90 ? .purple : .white)
                let length: CGFloat = score < 80 ? size.height * 0.15 : (score < 90 ? size.height * 0.30 : size.height * 0.48)

                for i in 0..<count {
                    let seed = Double(i)
                    let phase = (time + seed * 0.173).truncatingRemainder(dividingBy: interval)
                    guard phase < duration else { continue }
                    let flash = sin(Double.pi * phase / duration)
                    let opacity = (0.35 + flash * 0.65) * (reduceMotion ? 0.45 : 1)

                    // 出る場所（左・右・中央）
                    let positionType = i % 3
                    let startX: CGFloat = positionType == 0 ? size.width * 0.03 : (positionType == 1 ? size.width * 0.97 : size.width * 0.5)
                    let startY = CGFloat((seed * 83.7).truncatingRemainder(dividingBy: 100)) / 100 * size.height
                    let endY = min(startY + length, size.height)
                    let direction: CGFloat = positionType == 0 ? 1 : (positionType == 1 ? -1 : (i % 2 == 0 ? 1 : -1))
                    let endX = startX + direction * (positionType == 2 ? size.width * 0.12 : size.width * 0.18)
                    let currentWidth: CGFloat = positionType == 2 ? lineWidth * 1.3 : lineWidth

                    var path = Path()
                    path.move(to: CGPoint(x: startX, y: startY))
                    if i % 4 == 0 {
                        // 真っ直ぐな雷
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    } else {
                        // 枝分かれする雷
                        let p1 = CGPoint(x: startX + direction * 15, y: startY + length * 0.25)
                        let p2 = CGPoint(x: startX - direction * 5, y: startY + length * 0.50)
                        let p3 = CGPoint(x: startX + direction * 25, y: startY + length * 0.75)
                        path.addLine(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: CGPoint(x: endX, y: endY))
                        if score >= 80 {
                            var branch = Path()
                            branch.move(to: p2)
                            branch.addLine(to: CGPoint(x: p2.x + direction * 35, y: p2.y + length * 0.12))
                            context.stroke(branch, with: .color(lightningColor.opacity(opacity * 0.8)), lineWidth: currentWidth * 0.7)
                        }
                    }
                    context.stroke(path, with: .color(lightningColor.opacity(opacity * 0.25)), lineWidth: currentWidth * 5)
                    context.stroke(path, with: .color(lightningColor.opacity(opacity)), lineWidth: currentWidth)
                }

                // 90 以上の画面フラッシュ（約 1.1 回/秒・弱い白。Reduce Motion では出さない）
                if score >= 90, !reduceMotion {
                    let flashPhase = time.truncatingRemainder(dividingBy: 0.9)
                    if flashPhase < 0.12 {
                        context.fill(Path(CGRect(origin: .zero, size: size)),
                                     with: .color(.white.opacity((1 - flashPhase / 0.12) * 0.16)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - もこりんの座席（元: MocorinSeatView）

/// 元の座席の形・色はそのまま。友達制作のもこりん（MokorinAvatarView。原本は変更しない）を座らせる
struct HarukaMocorinSeatView: View {
    var pose: MokorinPose = MokorinPose(emotion: .happy)

    var body: some View {
        ZStack {
            // 背もたれ
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(red: 0.85, green: 0.88, blue: 0.91))
                .frame(width: 90, height: 85)
                .offset(y: -15)
            // 背もたれの縁
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                .frame(width: 90, height: 85)
                .offset(y: -15)
            // もこりん（背もたれの前・座面の上）
            MokorinAvatarView(size: 62, pose: pose)
                .frame(width: 62, height: 62)
                .offset(y: -6)
            // 左右の肘掛け
            HStack(spacing: 75) {
                Capsule().fill(Color.black.opacity(0.8)).frame(width: 13, height: 35)
                Capsule().fill(Color.black.opacity(0.8)).frame(width: 13, height: 35)
            }
            .offset(y: 15)
            // 座面
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(red: 0.96, green: 0.82, blue: 0.79))
                .frame(width: 100, height: 25)
                .offset(y: 27)
        }
        .frame(width: 120, height: 120)
    }
}

// MARK: - プレビュー（スライダーはプレビュー専用。本番の入力には使わない）

#if DEBUG
private struct HarukaSpacePreviewHarness: View {
    @State private var score: Double = 50
    @State private var standby = false

    var body: some View {
        ZStack(alignment: .bottom) {
            HarukaSpaceGraphicView(input: GraphicInput(score: score, confidence: 0.85, state: MindState.from(score: score)))
                .environment(\.graphicDataStatus, standby ? .unmeasured : .demo)
                .ignoresSafeArea()
            VStack {
                Toggle("未計測", isOn: $standby)
                Text(String(format: "score %.0f", score))
                Slider(value: $score, in: 0...100, step: 1)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    HarukaSpacePreviewHarness()
}
#endif
