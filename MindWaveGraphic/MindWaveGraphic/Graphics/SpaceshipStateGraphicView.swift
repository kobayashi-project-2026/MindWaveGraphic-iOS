
import SwiftUI

struct ContentView: View {
    // MARK: - 赤色の演出の強さ

    private var redOverlayOpacity: Double {
        if score <= 60 {
            return 0
        } else {
            return min((score - 60) / 40 * 0.3, 0.3)
        }
    }
    
    private var backgroundColor: Color {
        if score <= 30 {
            return Color.blue
        } else if score <= 60 {
            return Color.black
        } else {
            return Color.red
        }
    }

    @State private var score: Double = 0

    var body: some View {

        GeometryReader { geometry in

            ZStack {

                // MARK: - 背景
                backgroundColor
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 1.0), value: score)
                // MARK: - 星空・隕石
                StarfieldView(score: score)

                // MARK: - 雷
                LightningView(score: score)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: score < 80)) { timeline in
                    
                    let shakeX: CGFloat = score >= 80
                    ? CGFloat(sin(timeline.date.timeIntervalSinceReferenceDate * 35) * 8)
                    : 0
                    
                    Image("cockpit")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .offset(x: shakeX, y: 40)
                        .scaleEffect(x: 1.30, y: 1.4)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                
                // MARK: - もこりん用の椅子
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: score < 80)) { timeline in

                    let shakeX: CGFloat = score >= 80
                        ? CGFloat(sin(timeline.date.timeIntervalSinceReferenceDate * 35) * 4)
                        : 0

                    MocorinSeatView()
                        .offset(x: shakeX)
                }
                    .position(
                        x: geometry.size.width * 0.7,
                        y: geometry.size.height * 0.8
                    )

                // MARK: - ステータス表示
                Text(score < 50
                     ? "STATUS : NORMAL"
                     : "STATUS : TENSION")
                    .font(.system(
                        size: 14,
                        weight: .medium,
                        design: .monospaced
                    ))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                Color.white.opacity(0.5),
                                lineWidth: 1
                            )
                    )
                    .offset(y: 200)

                // MARK: - スコア操作
                VStack {

                    Spacer()

                    Text(String(format: "Stress %.0f", score))
                        .foregroundColor(.white)
                        .font(.title)

                    Slider(
                        value: $score,
                        in: 0...100,
                        step: 1
                    )
                    .frame(width: 300)
                    .padding(.horizontal)

                    Spacer()
                        .frame(height: 50)
                }
            // ★ここに追加する！
                Color.red
                    .opacity(redOverlayOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 1.0), value: score)
            }
        }
    }
}


// MARK: - もこりん用の椅子

struct MocorinSeatView: View {

    var body: some View {

        ZStack {

            // 背もたれ
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    Color(
                        red: 0.85,
                        green: 0.88,
                        blue: 0.91
                    )
                )
                .frame(width: 90, height: 85)
                .offset(y: -15)

            // 背もたれの縁
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    Color.cyan.opacity(0.5),
                    lineWidth: 2
                )
                .frame(width: 90, height: 85)
                .offset(y: -15)

            // 左右の肘掛け
            HStack(spacing: 75) {

                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 13, height: 35)

                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 13, height: 35)
            }
            .offset(y: 15)

            // 座面
            RoundedRectangle(cornerRadius: 15)
                .fill(
                    Color(
                        red: 0.96,
                        green: 0.82,
                        blue: 0.79
                    )
                )
                .frame(width: 100, height: 25)
                .offset(y: 27)
        }
        .frame(width: 120, height: 120)
    }
}


// MARK: - Starfield

struct StarfieldView: View {

    let score: Double

    private var intensity: Double {
        score / 100.0
    }

    private var speed: Double {
        0.2 + intensity * 2.5
    }

    private var bigStarCount: Int {

        if score < 33 {
            return 0
        } else if score < 70 {
            return 20
        } else {
            return 40
        }
    }

    var body: some View {

        TimelineView(.animation) { timeline in

            Canvas { context, size in

                let inseki = context.resolve(Image("inseki"))

                let time = timeline.date.timeIntervalSinceReferenceDate

                let centerX = size.width / 2
                let centerY = size.height / 2

                // MARK: - 通常の星
                for i in 0..<800 {

                    let seed = Double(i)

                    let x3d = CGFloat(
                        sin(seed * 12.9898) * 300
                    )

                    let y3d = CGFloat(
                        cos(seed * 78.233) * 300
                    )

                    var z = 1000 - (
                        time * 200 * speed + seed * 17
                    ).truncatingRemainder(dividingBy: 1000)

                    if z < 1 {
                        z = 1
                    }

                    let perspective = CGFloat(400 / z)

                    let x = centerX + x3d * perspective
                    let y = centerY + y3d * perspective

                    let starSize = min(
                        max(1, perspective * 4),
                        4
                    )

                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: starSize,
                        height: starSize
                    )

                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white)
                    )

                    // MARK: - 星の軌跡
                    if intensity > 0.3 {

                        let trail = starSize * CGFloat(intensity) * 10

                        var path = Path()

                        path.move(
                            to: CGPoint(x: x, y: y)
                        )

                        path.addLine(
                            to: CGPoint(
                                x: centerX + x3d * CGFloat(
                                    400 / (z + Double(trail))
                                ),
                                y: centerY + y3d * CGFloat(
                                    400 / (z + Double(trail))
                                )
                            )
                        )

                        context.stroke(
                            path,
                            with: .color(.white.opacity(0.8)),
                            lineWidth: starSize * 0.5
                        )
                    }
                }

                // MARK: - 隕石
                for i in 0..<bigStarCount {

                    let seed = Double(i * 137 + 1000)

                    let x3d = CGFloat(
                        sin(seed * 15.23) * 350
                    )

                    let y3d = CGFloat(
                        cos(seed * 92.11) * 350
                    )

                    var z = 1200 - (
                        time * (250 + intensity * 400)
                        + seed * 50
                    ).truncatingRemainder(dividingBy: 1200)

                    if z < 1 {
                        z = 1
                    }

                    let perspective = CGFloat(500 / z)

                    let x = centerX + x3d * perspective
                    let y = centerY + y3d * perspective

                    let meteorSize = min(
                        max(8, perspective * 80),
                        100
                    )

                    let correctedAngle = Double.pi / 6

                    context.drawLayer { layer in

                        layer.translateBy(
                            x: x + meteorSize / 2,
                            y: y + meteorSize / 2
                        )

                        if x > centerX {
                            layer.scaleBy(x: -1, y: 1)
                        }

                        layer.rotate(
                            by: .radians(correctedAngle)
                        )

                        layer.draw(
                            inseki,
                            in: CGRect(
                                x: -meteorSize / 2,
                                y: -meteorSize / 2,
                                width: meteorSize,
                                height: meteorSize
                            )
                        )
                    }
                }
            }
        }
    }
}



// MARK: - Lightning

struct LightningView: View {

    let score: Double

    var body: some View {

        TimelineView(.animation) { timeline in

            Canvas { context, size in

                guard score >= 70 else {
                    return
                }

                let time = timeline.date.timeIntervalSinceReferenceDate

                // MARK: - スコアによる設定

                let count: Int
                let interval: Double
                let duration: Double
                let lineWidth: CGFloat

                if score < 80 {
                    count = 32
                    interval = 1.2
                    duration = 0.28
                    lineWidth = 1.5

                } else if score < 90 {
                    count = 24
                    interval = 1.0
                    duration = 0.30
                    lineWidth = 2.5

                } else {
                    count = 20
                    interval = 0.75
                    duration = 0.35
                    lineWidth = 4.0
                }

                let lightningColor: Color

                if score < 80 {
                    lightningColor = .cyan
                } else if score < 90 {
                    lightningColor = .purple
                } else {
                    lightningColor = .white
                }

                // MARK: - 左右と中央の雷

                for i in 0..<count {

                    let seed = Double(i)

                    let phase = (time + seed * 0.173)
                        .truncatingRemainder(dividingBy: interval)

                    guard phase < duration else {
                        continue
                    }

                    let flash = sin(
                        Double.pi * phase / duration
                    )

                    let opacity = 0.35 + flash * 0.65

                    // 雷の出現場所を決める
                    let positionType = i % 3

                    let startX: CGFloat

                    if positionType == 0 {
                        // 左側
                        startX = size.width * 0.03

                    } else if positionType == 1 {
                        // 右側
                        startX = size.width * 0.97

                    } else {
                        // 中央
                        startX = size.width * 0.5
                    }

                    let startY = CGFloat(
                        (seed * 83.7).truncatingRemainder(dividingBy: 100)
                    ) / 100 * size.height

                    // 雷の長さ
                    let length: CGFloat

                    if score < 80 {
                        length = size.height * 0.15
                    } else if score < 90 {
                        length = size.height * 0.30
                    } else {
                        length = size.height * 0.48
                    }

                    let endY = min(
                        startY + length,
                        size.height
                    )

                    // 左右と中央で進む方向を変更
                    let direction: CGFloat

                    if positionType == 0 {
                        direction = 1
                    } else if positionType == 1 {
                        direction = -1
                    } else {
                        direction = i % 2 == 0 ? 1 : -1
                    }

                    let endX = startX + direction * (
                        positionType == 2
                        ? size.width * 0.12
                        : size.width * 0.18
                    )

                    // 中央の雷は少し太くする
                    let currentWidth: CGFloat =
                        positionType == 2
                        ? lineWidth * 1.3
                        : lineWidth

                    // 4本に1本は真っ直ぐな雷
                    let isStraight = i % 4 == 0

                    var path = Path()

                    path.move(
                        to: CGPoint(x: startX, y: startY)
                    )

                    if isStraight {

                        // 真っ直ぐな雷
                        path.addLine(
                            to: CGPoint(x: endX, y: endY)
                        )

                    } else {

                        // 枝分かれする雷
                        let p1 = CGPoint(
                            x: startX + direction * 15,
                            y: startY + length * 0.25
                        )

                        let p2 = CGPoint(
                            x: startX - direction * 5,
                            y: startY + length * 0.50
                        )

                        let p3 = CGPoint(
                            x: startX + direction * 25,
                            y: startY + length * 0.75
                        )

                        let p4 = CGPoint(
                            x: endX,
                            y: endY
                        )

                        path.addLine(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: p4)

                        // 80以上は枝分かれを追加
                        if score >= 80 {

                            var branch = Path()

                            branch.move(to: p2)

                            branch.addLine(
                                to: CGPoint(
                                    x: p2.x + direction * 35,
                                    y: p2.y + length * 0.12
                                )
                            )

                            context.stroke(
                                branch,
                                with: .color(
                                    lightningColor.opacity(opacity * 0.8)
                                ),
                                lineWidth: currentWidth * 0.7
                            )
                        }
                    }

                    // 雷のぼんやりした光
                    context.stroke(
                        path,
                        with: .color(
                            lightningColor.opacity(opacity * 0.25)
                        ),
                        lineWidth: currentWidth * 5
                    )

                    // 雷本体
                    context.stroke(
                        path,
                        with: .color(
                            lightningColor.opacity(opacity)
                        ),
                        lineWidth: currentWidth
                    )
                }

                // MARK: - 90以上の画面フラッシュ

                if score >= 90 {

                    let flashPhase = time
                        .truncatingRemainder(dividingBy: 0.9)

                    if flashPhase < 0.12 {

                        let flashOpacity = (
                            1 - flashPhase / 0.12
                        ) * 0.16

                        context.fill(
                            Path(
                                CGRect(
                                    origin: .zero,
                                    size: size
                                )
                            ),
                            with: .color(
                                .white.opacity(flashOpacity)
                            )
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}


// MARK: - Preview

#Preview {
    ContentView()
}


