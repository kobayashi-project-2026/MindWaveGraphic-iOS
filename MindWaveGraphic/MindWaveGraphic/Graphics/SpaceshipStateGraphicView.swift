import SwiftUI

// コックピット内部から前方を見る視点。
// 宇宙船の外観は表示しない。前進感を持つ青いワープ光線が主役。
// 星・光線ともにseedベース決定論的アニメーション（random不使用）。
// Reduce Motion有効時は速度と軌跡長を低減する。

struct SpaceshipStateGraphicView: View {
    let input: GraphicInput
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visualStress: Double {
        min(max(input.score / 100.0, 0.0), 1.0) * 6.0
    }

    var body: some View {
        ZStack {
            // ディープスペース背景グラデーション
            LinearGradient(
                colors: [
                    Color(red: 0.00, green: 0.03, blue: 0.14),
                    Color(red: 0.00, green: 0.01, blue: 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            WarpFieldView(visualStress: visualStress, reduceMotion: reduceMotion)
        }
    }
}

// MARK: - ワープフィールド

private struct WarpFieldView: View {
    let visualStress: Double
    let reduceMotion: Bool
    private let vpYRatio: Double = 0.44  // 消失点位置（グラフィック高さ比）

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let intensity   = visualStress / 6.0
                let motionScale = reduceMotion ? 0.25 : 1.0
                let vpX = size.width  / 2
                let vpY = size.height * vpYRatio

                // ワープ速度（score連動、Reduce Motion時は低速）
                let warpSpeed = (0.28 + intensity * 2.2) * motionScale

                // ── 遠景の星（白、低速）
                let starSpeed = (0.06 + intensity * 0.35) * motionScale
                for i in 0..<280 {
                    let s = Double(i)
                    let x3d = sin(s * 12.9898) * 280
                    let y3d = cos(s * 78.233)  * 280
                    var z = 9000 - (t * 50 * starSpeed + s * 43)
                        .truncatingRemainder(dividingBy: 9000)
                    if z < 1 { z = 1 }
                    let p   = 400 / z
                    let x   = vpX + x3d * p
                    let y   = vpY + y3d * p
                    let sz  = min(max(0.25, p * 1.8), 1.4)
                    let alp = min(max(0.05, p * 0.38), 0.45)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - sz/2, y: y - sz/2,
                                               width: sz, height: sz)),
                        with: .color(.white.opacity(alp))
                    )
                }

                // ── ワープ光線（電気ブルー）
                // Reduce Motion時は軌跡を短くする
                let baseTrail = reduceMotion ? 0.15 : 0.5
                let stressTrail = reduceMotion ? 4.0 : 14.0

                for i in 0..<220 {
                    let s = Double(i)
                    let x3d = sin(s * 12.9898) * 300
                    let y3d = cos(s * 78.233)  * 300
                    var z = 3500 - (t * 180 * warpSpeed + s * 27)
                        .truncatingRemainder(dividingBy: 3500)
                    if z < 1 { z = 1 }
                    let p     = 400 / z
                    let x     = vpX + x3d * p
                    let y     = vpY + y3d * p
                    let phase = 1.0 - z / 3500.0

                    // 尾の終点（消失点方向）
                    let trailFactor = baseTrail + intensity * stressTrail
                    let zTail = z * (1.0 + trailFactor)
                    let pTail = 400 / max(zTail, 1)
                    let xTail = vpX + x3d * pTail
                    let yTail = vpY + y3d * pTail

                    let alpha = min(max(0.08, phase * 0.88), 0.82)
                    let lineW = 0.3 + phase * 2.0

                    var ray = Path()
                    ray.move(to: CGPoint(x: xTail, y: yTail))
                    ray.addLine(to: CGPoint(x: x,     y: y))

                    // コア（電気ブルー）
                    ctx.stroke(ray,
                        with: .color(Color(hue: 0.572, saturation: 1.0,
                                          brightness: 1.0).opacity(alpha)),
                        lineWidth: lineW)
                    // グロー（シアン、広め低透明度）
                    ctx.stroke(ray,
                        with: .color(Color.cyan.opacity(alpha * 0.22)),
                        lineWidth: lineW * 4.0)
                }

                // ── 中心グロー（Reduce Motion時は小さめ）
                let glowR = CGFloat((reduceMotion ? 30 : 50) + intensity * 35)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: vpX - glowR, y: vpY - glowR,
                                           width: glowR * 2, height: glowR * 2)),
                    with: .color(Color.cyan.opacity(0.05 + intensity * 0.07))
                )
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SpaceshipStateGraphicView(
            input: GraphicInput(score: 65, confidence: 0.80, state: .optimalTension)
        )
    }
    .preferredColorScheme(.dark)
}
