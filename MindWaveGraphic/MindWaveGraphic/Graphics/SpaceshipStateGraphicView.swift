import SwiftUI
struct ContentView: View {

    @State private var stress: Double = 0.0
    @State private var shipOffset: CGFloat = 0
    @State private var shipX: CGFloat = -300
    var body: some View {

        ZStack {

            Color.black
                .ignoresSafeArea()

            StarfieldView(stress: stress)

            if stress <= -3 {
                Image("ship")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180)
                    .offset(
                           x: shipX,
                           y: shipOffset
                       )
            }
            Image("cockpit")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: -30)   // ← 左へ30pt
                .scaleEffect(x: 1.15, y: 1.1)   // 横だけ15%拡大
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // ステータス表示
                       Text(abs(stress) < 3 ? "STATUS : NORMAL" : "STATUS : TENSION")
                           .font(.system(size: 14, weight: .medium, design: .monospaced))
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
                                   .stroke(Color.white.opacity(0.5), lineWidth: 1)
                           )
                           .offset(y: 200)
            VStack {

                Spacer()

                Text(String(format: "Stress %.1f", stress))
                    .foregroundColor(.white)
                    .font(.title)

                Slider(
                    value: $stress,
                    in: -6...6,
                    step: 0.5
                )
                .frame(width: 300)    // ← 好きな幅にする
                .padding(.horizontal)

                Spacer()
                    .frame(height: 50)
            }
        }
        .task {

            shipX = -265

            while true {

                // 左→右
                withAnimation(.linear(duration: 5)) {
                    shipX = 265
                }

                try? await Task.sleep(for: .seconds(8))

                // 右→左
                withAnimation(.linear(duration: 5)) {
                    shipX = -265
                }

                try? await Task.sleep(for: .seconds(8))
            }
        }
    }
}

struct StarfieldView: View {

    let stress: Double

    var body: some View {

        TimelineView(.animation) { timeline in

            Canvas { context, size in
                let inseki = context.resolve(Image("inseki"))
                let time =
                    timeline.date.timeIntervalSinceReferenceDate

                let intensity =
                    abs(stress) / 6.0

                let speed =
                    0.2 + intensity * 2.5

                let centerX = size.width / 2
                let centerY = size.height / 2

                // 通常の星
                for i in 0..<800 {

                    let seed = Double(i)

                    let x3d =
                        sin(seed * 12.9898) * 300

                    let y3d =
                        cos(seed * 78.233) * 300

                    var z =
                        1000 -
                        (time * 200 * speed + seed * 17)
                        .truncatingRemainder(
                            dividingBy: 1000
                        )

                    if z < 1 {
                        z = 1
                    }

                    let perspective =
                        400 / z

                    let x =
                        centerX +
                        x3d * perspective

                    let y =
                        centerY +
                        y3d * perspective

                    let starSize =
                        min(
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

                    if intensity > 0.3 {

                        let trail =
                            starSize * intensity * 10

                        var path = Path()

                        path.move(
                            to: CGPoint(
                                x: x,
                                y: y
                            )
                        )

                        path.addLine(
                            to: CGPoint(
                                x: centerX +
                                x3d * (400 / (z + trail)),
                                y: centerY +
                                y3d * (400 / (z + trail))
                            )
                        )

                        context.stroke(
                            path,
                            with: .color(
                                .white.opacity(0.8)
                            ),
                            lineWidth:
                                starSize * 0.5
                        )
                    }
                }
                let bigStarCount: Int

                if stress < 3 {

                    bigStarCount = 0

                } else if stress < 5 {

                    bigStarCount = 20

                } else {

                    bigStarCount = 40
                }

                for i in 0..<bigStarCount {

                    let seed = Double(i * 137 + 1000)

                    let x3d =
                        sin(seed * 15.23) * 350

                    let y3d =
                        cos(seed * 92.11) * 350

                    var z =
                        1200 -
                        (time * 250 * speed + seed * 50)
                        .truncatingRemainder(
                            dividingBy: 1200
                        )

                    if z < 1 {
                        z = 1
                    }

                    let perspective =
                        500 / z

                    let x =
                        centerX +
                        x3d * perspective

                    let y =
                        centerY +
                        y3d * perspective

                    let size =
                        min(
                            max(8,
                                perspective * 80),
                            100
                        )

                    _ = CGRect(
                        x: x,
                        y: y,
                        width: size,
                        height: size
                    )
                    let correctedAngle = Double.pi / 6

                    context.drawLayer { layer in

                        layer.translateBy(
                            x: x + size / 2,
                            y: y + size / 2
                        )

                        if x > centerX {

                            layer.scaleBy(
                                x: -1,
                                y: 1
                            )
                        }

                        layer.rotate(
                            by: .radians(correctedAngle)
                        )

                        layer.draw(
                            inseki,
                            in: CGRect(
                                x: -size / 2,
                                y: -size / 2,
                                width: size,
                                height: size
                            )
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

