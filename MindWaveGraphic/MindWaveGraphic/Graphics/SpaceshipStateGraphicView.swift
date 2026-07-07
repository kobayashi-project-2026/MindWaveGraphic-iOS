import SwiftUI

// コックピット前方宇宙ビュー。
// 星粒子のみ。固定長線・ワープ線・中央光源なし。
// score 0→100 で 低(深藍) / 中(シアン〜緑) / 高(シアン + 赤/マゼンタ) へ劇的に変化。
// 速度比: 低:中:高 ≈ 1:5.5:16 （近景 pow(2.2) カーブ）

// MARK: - Layer config

private struct StarLayer {
    let count:      Int
    let xRange:     Double
    let yRange:     Double
    let zDepth:     Double
    let baseSpd:    Double   // score=0時の速度係数
    let strSpd:     Double   // score=100追加係数 (intensity×strSpd)
    let dotMul:     Double
    let brightFl:   Double
    let brightDp:   Double
    let trailRatio: Double   // 最大残像長/対角線
}

// 速度設計 pow(2.2) カーブ
//   intensity: s=15→0.016, s=50→0.218, s=85→0.699
// Near: low≈0.39 / mid≈2.21 / high≈6.54  ratio: 1.0 / 5.7× / 16.8×
// Mid:  low≈0.23 / mid≈1.24 / high≈3.65
// Far:  low≈0.12 / mid≈0.63 / high≈1.83

// 速度設計 (改訂版): 低=1.5x, 中=2.2x, 高=3.2x 比で飛躍感を強調。
// 残像: Far=点, Mid=短尾(中~高), Near=長尾(低でも短尾あり)。
// 固定放射線にならないよう trailRatio は wrapGate 依存の速度判定で制限される。
private let kFar = StarLayer(
    count: 320, xRange: 1900, yRange: 1500, zDepth: 9000,
    baseSpd: 0.18, strSpd: 4.50,
    dotMul: 0.52, brightFl: 0.07, brightDp: 1.80,
    trailRatio: 0.004
)
private let kMid = StarLayer(
    count: 180, xRange: 1100, yRange: 860, zDepth: 5200,
    baseSpd: 0.38, strSpd: 11.50,
    dotMul: 1.05, brightFl: 0.09, brightDp: 1.85,
    trailRatio: 0.048
)
private let kNear = StarLayer(
    count: 90, xRange: 560, yRange: 430, zDepth: 2400,
    baseSpd: 0.56, strSpd: 22.00,
    dotMul: 1.70, brightFl: 0.12, brightDp: 2.20,
    trailRatio: 0.105
)
private let kLayers: [StarLayer] = [kFar, kMid, kNear]
private let kFocal: Double = 430

// MARK: - Outer view

struct SpaceshipStateGraphicView: View {
    let input: GraphicInput
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var rawIntensity: Double { min(max(input.score / 100.0, 0.0), 1.0) }

    var body: some View {
        ZStack {
            spaceBackground
                .animation(.easeInOut(duration: 1.6), value: rawIntensity)
            StarFieldView(visualStress: rawIntensity * 6.0, reduceMotion: reduceMotion)
            // エッジビネット（映画的奥行き）
            RadialGradient(
                colors: [.clear, .clear, Color.black.opacity(0.38)],
                center: UnitPoint(x: 0.5, y: 0.40),
                startRadius: 75,
                endRadius: 245
            )
        }
    }

    private var spaceBackground: some View {
        let t = rawIntensity
        // 低: 深い藍-青
        // 中: 濃い青-シアン
        // 高: 暗いシアン + 微細な暖色ヒント
        let topR: Double = t < 0.65 ? t * 0.025 : 0.016 + (t - 0.65) * 0.08
        let topG: Double = t < 0.50 ? t * 0.025 : 0.012 + (t - 0.50) * 0.055
        let topB: Double = 0.14 - t * 0.035
        let botR: Double = t < 0.65 ? t * 0.012 : 0.008 + (t - 0.65) * 0.04
        let botG: Double = t < 0.50 ? t * 0.012 : 0.006 + (t - 0.50) * 0.025
        let botB: Double = 0.068 - t * 0.018

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: topR, green: topG, blue: topB),
                    Color(red: botR, green: botG, blue: botB)
                ],
                startPoint: .top, endPoint: .bottom
            )
            // 高緊張時: 中央付近に微細な暖色ハロー（空気感を変える）
            if t > 0.72 {
                RadialGradient(
                    colors: [
                        Color(red: (t - 0.72) / 0.28 * 0.10, green: 0.0, blue: (t - 0.72) / 0.28 * 0.005)
                            .opacity(0.18),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: 160
                )
            }
        }
    }
}

// MARK: - Canvas

private struct StarFieldView: View {
    let visualStress: Double
    let reduceMotion: Bool
    private let vpYRatio: Double = 0.38

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let raw  = min(max(visualStress / 6.0, 0.0), 1.0)
                // pow(2.2): 低を「穏やか」に抑え、高を「爆発的」に速くする
                let intn = pow(raw, 2.2)
                let ms   = reduceMotion ? 0.08 : 1.0

                // score連動カメラドリフト（決定論的sinコンポジット、毎フレーム乱数なし）
                // 低: ±5pt(安定), 中: ±18pt(優雅), 高: ±38pt(激しい蛇行)
                let driftW   = (0.008 + intn * 0.088) * size.width
                let driftH_c = (0.005 + intn * 0.060) * size.height
                // ヨー（左右）: 2周波基本 + 高score時に第3波（複雑な蛇行）
                let cYaw = sin(t * 0.108) * driftW
                         + sin(t * 0.071 + 1.37) * driftW * 0.42
                         + sin(t * 0.047 + 0.88) * driftW * intn * 0.32
                // ピッチ（上下）: 2周波基本 + 高score時に第3波（うねり感）
                let cPitch = sin(t * 0.083 + 0.74) * driftH_c
                           + sin(t * 0.052 + 2.08) * driftH_c * 0.55
                           + sin(t * 0.038 + 1.55) * driftH_c * intn * 0.42
                let vpX  = size.width  * 0.50 + (reduceMotion ? 0 : cYaw)
                let vpY  = size.height * vpYRatio + (reduceMotion ? 0 : cPitch)
                let diag = hypot(size.width, size.height)
                let dt: Double = 0.016

                // 残像閾値: 低=9.5pt(ほぼ点), 中=4.2pt, 高=0.8pt(ほぼ全星が尾を持つ)
                let trailThresh: Double = reduceMotion ? 9999
                    : max(0.5, (1.0 - raw) * 7.0 + 0.5)
                let wrapGate: Double = diag * 0.34

                // ── グローバル色テーマ（score連動）
                // 低 (0-0.30): 深藍-インディゴ  hue 0.70 → 0.62
                // 中 (0.30-0.65): 青-シアン-緑   hue 0.62 → 0.45
                // 高 (0.65-1.0):  緑-シアン固定  hue 0.47 (+ 暖色アクセント大量)
                let globalHue: Double = {
                    if raw < 0.30 {
                        return 0.70 - (raw / 0.30) * 0.08       // 0.70 → 0.62
                    } else if raw < 0.65 {
                        return 0.62 - ((raw - 0.30) / 0.35) * 0.15  // 0.62 → 0.47
                    } else {
                        return 0.47                              // シアン-緑 固定
                    }
                }()

                // 暖色アクセント確率 (score>0.55 から出現, score=1.0 で最大52%)
                // 近景・中景で危険感の赤/マゼンタ/アンバーが増加
                let warmChance: Double = max(0.0, (raw - 0.50) / 0.50) * 0.62

                // 輝度ブースト: 中scoreで最も美しく輝く(mid peak), 高scoreで強烈
                let briBoost: Double = {
                    if raw < 0.50 {
                        return 1.0 + raw * 0.60   // 低→中: 着実に明るく
                    } else {
                        return 1.30 + (raw - 0.50) * 0.60  // 中→高: さらに輝く
                    }
                }()

                var seedIdx = 0

                for layer in kLayers {
                    let spdMult    = (layer.baseSpd + intn * layer.strSpd) * ms
                    let maxTrailPx = diag * layer.trailRatio
                    let isNearLyr  = (layer.count == 90)
                    let isMidLyr   = (layer.count == 180)

                    for li in 0..<layer.count {
                        let s     = Double(seedIdx)
                        let phOff = Double(li) * (layer.zDepth / Double(layer.count))
                        seedIdx  += 1

                        let x3d = sin(s * 12.9898 + 0.731) * layer.xRange
                        let y3d = cos(s * 78.233  + 0.314) * layer.yRange

                        var z = layer.zDepth
                            - (t * 62.0 * spdMult + phOff)
                              .truncatingRemainder(dividingBy: layer.zDepth)
                        if z < 1 { z = 1 }
                        var zPrev = layer.zDepth
                            - ((t - dt) * 62.0 * spdMult + phOff)
                              .truncatingRemainder(dividingBy: layer.zDepth)
                        if zPrev < 1 { zPrev = 1 }

                        let p     = kFocal / z
                        let pPrev = kFocal / zPrev
                        let x     = vpX + x3d * p
                        let y     = vpY + y3d * p
                        let xPrev = vpX + x3d * pPrev
                        let yPrev = vpY + y3d * pPrev

                        let dvx      = x - xPrev
                        let dvy      = y - yPrev
                        let velocity = hypot(dvx, dvy)
                        guard velocity < wrapGate else { continue }

                        let depthFrac = max(0.0, 1.0 - z / layer.zDepth)
                        let alpha = min(0.96,
                            (layer.brightFl + depthFrac * layer.brightDp * layer.brightFl * 12.0)
                            * briBoost)

                        let sizeBoost = (isNearLyr || isMidLyr) ? (1.0 + raw * 0.30) : 1.0
                        let dotSz = min(5.8, max(0.5,
                            (0.5 + depthFrac * layer.dotMul * 2.5) * sizeBoost))

                        // ── 色計算
                        let hueFrac = sin(s * 43.71) * 0.5 + 0.5
                        let satFrac = cos(s * 29.13) * 0.5 + 0.5

                        let isWhite   = (Int(s) % 9 == 0)
                        // 暖色アクセント: 近景・中景のみ（遠景は常にクール）
                        let canBeWarm = !isWhite && (isNearLyr || isMidLyr)
                        let warmRand  = Double(Int(s * 31.7 + Double(li) * 7.3).magnitude % 100) / 100.0
                        let isWarm    = canBeWarm && warmRand < warmChance
                        // 赤/マゼンタ系 vs オレンジ/アンバー系を 60:40 で分配
                        let isRedWarm = isWarm && (Int(s * 7.3).magnitude % 5 < 3)

                        let hue: Double
                        let sat: Double
                        let bri: Double

                        if isRedWarm {
                            // 赤〜マゼンタ: 緊張感・警戒色
                            hue = 0.88 + hueFrac * 0.10   // 0.88-0.98
                            sat = 0.88 + min(0.12, warmChance * 0.4)
                            bri = 0.90 + hueFrac * 0.10
                        } else if isWarm {
                            // オレンジ〜アンバー: エネルギー感
                            hue = 0.04 + hueFrac * 0.08   // 0.04-0.12
                            sat = 0.92 + min(0.08, warmChance * 0.2)
                            bri = 0.88 + hueFrac * 0.12
                        } else if isWhite {
                            // 白星: わずかに色調
                            hue = globalHue + 0.01
                            sat = max(0, raw * 0.06)
                            bri = 1.0
                        } else {
                            // メイン星: globalHueに誘導
                            let hueSpread = 0.050 + (1.0 - raw) * 0.020
                            hue = globalHue + (hueFrac - 0.5) * hueSpread
                            // 中scoreで最も彩度が高く（最も美しい状態）
                            // low: 深藍・低彩度  mid: 鮮やかシアン/エメラルド  high: シアン+暖色
                            let satBase: Double
                            if raw < 0.50 {
                                satBase = 0.12 + raw * 1.00  // 0.12→0.62
                            } else if raw < 0.70 {
                                satBase = 0.62 + (raw - 0.50) * 0.90  // 0.62→0.80 (mid peak)
                            } else {
                                satBase = 0.80 + (raw - 0.70) * 0.60  // 0.80→0.92
                            }
                            sat = min(1.0, satBase * (0.40 + satFrac * 0.60))
                            bri = (Int(s) % 5 == 0) ? 1.0 : (0.62 + hueFrac * 0.38)
                        }

                        let starCol = Color(
                            hue:        hue.truncatingRemainder(dividingBy: 1.0),
                            saturation: min(1.0, sat),
                            brightness: min(1.0, bri)
                        )

                        // 近景・中景の高速星にハロー（輝き感・mid以上で出現）
                        if (isNearLyr || (isMidLyr && raw > 0.25)) && raw > 0.20 {
                            let haloFrac = max(0, (raw - 0.38) / 0.62)
                            let haloMul: Double = isNearLyr ? 3.2 : 1.8
                            let haloR    = dotSz * (0.6 + haloFrac * haloMul)
                            ctx.fill(
                                Path(ellipseIn: CGRect(
                                    x: x - haloR, y: y - haloR,
                                    width: haloR * 2, height: haloR * 2
                                )),
                                with: .color(starCol.opacity(alpha * haloFrac * 0.32))
                            )
                        }

                        // 残像 (速度依存)
                        if velocity > trailThresh {
                            let capped     = min(velocity, maxTrailPx)
                            let scale      = capped / max(velocity, 1e-9)
                            let txEnd      = x - dvx * scale
                            let tyEnd      = y - dvy * scale
                            var trail      = Path()
                            trail.move(to:    CGPoint(x: x,     y: y))
                            trail.addLine(to: CGPoint(x: txEnd, y: tyEnd))
                            // 高速時に残像が明るくなる（緊張感演出）
                            let trailAlpha = alpha * (0.32 + intn * 0.55)
                            ctx.stroke(
                                trail,
                                with: .color(starCol.opacity(trailAlpha)),
                                lineWidth: max(0.4, dotSz * 0.42)
                            )
                        }

                        // 星点
                        ctx.fill(
                            Path(ellipseIn: CGRect(
                                x: x - dotSz / 2, y: y - dotSz / 2,
                                width: dotSz, height: dotSz
                            )),
                            with: .color(starCol.opacity(alpha))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("score 10/45/80") {
    ScrollView {
        VStack(spacing: 8) {
            ForEach([10, 45, 80] as [Int], id: \.self) { score in
                VStack(spacing: 2) {
                    Text("score \(score)")
                        .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.4))
                    ZStack {
                        Color(red: 0, green: 0.01, blue: 0.06)
                        SpaceshipStateGraphicView(
                            input: GraphicInput(score: Double(score), confidence: 0.8, state: .optimalTension)
                        )
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }.padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
