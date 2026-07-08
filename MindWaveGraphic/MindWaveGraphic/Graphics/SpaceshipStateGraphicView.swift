import SwiftUI

// コックピット前方宇宙ビュー（visual refine 版）
// 近景: streak/light-ray primary（常に線として描画、泡なし）
// 中景: trail primary at medium+ speed
// 遠景: tiny sparkle dot + 白星に十字光芒
// 消失点グロー層追加、score連動アラート演出強化。
// 固定放射線防止: seed+time決定論的、wrapGate, nearJitter で多様化。

// MARK: - Layer config

private struct StarLayer {
    let count:      Int
    let xRange:     Double
    let yRange:     Double
    let zDepth:     Double
    let baseSpd:    Double
    let strSpd:     Double
    let dotMul:     Double
    let brightFl:   Double
    let brightDp:   Double
    let trailRatio: Double
}

// 速度設計 (alert-refine / warp-evolve 版)
// Near: low≈0.64 / mid≈4.0 / high≈22.6    longer trails, faster warp feel
// Mid:  low≈0.44 / mid≈2.66 / high≈14.8
// Far:  low≈0.20 / mid≈1.16 / high≈6.45
private let kFar = StarLayer(
    count: 320, xRange: 1900, yRange: 1500, zDepth: 9000,
    baseSpd: 0.28, strSpd: 10.00,
    dotMul: 0.48, brightFl: 0.068, brightDp: 1.80,
    trailRatio: 0.012
)
private let kMid = StarLayer(
    count: 180, xRange: 1100, yRange: 860, zDepth: 5200,
    baseSpd: 0.62, strSpd: 24.00,
    dotMul: 0.95, brightFl: 0.09, brightDp: 1.85,
    trailRatio: 0.14
)
private let kNear = StarLayer(
    count: 90, xRange: 560, yRange: 430, zDepth: 2400,
    baseSpd: 0.92, strSpd: 48.00,
    dotMul: 1.55, brightFl: 0.11, brightDp: 2.20,
    trailRatio: 0.30
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
                colors: [.clear, .clear, Color.black.opacity(0.44)],
                center: UnitPoint(x: 0.5, y: 0.40),
                startRadius: 72,
                endRadius: 255
            )
        }
    }

    private var spaceBackground: some View {
        let t = rawIntensity
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

            // 中程度以上: 消失点付近に暖色の空気（t>0.55 から）
            if t > 0.55 {
                let alertPhase = (t - 0.55) / 0.45
                RadialGradient(
                    colors: [
                        Color(red: alertPhase * 0.18, green: alertPhase * 0.018, blue: 0.0)
                            .opacity(0.26),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.36),
                    startRadius: 0,
                    endRadius: 215
                )
            }

            // ALERT以降: 周辺部に赤みの染み（強化版）
            if t > 0.58 {
                let extremePhase = (t - 0.58) / 0.42
                RadialGradient(
                    colors: [
                        .clear,
                        Color(red: 0.50 * extremePhase, green: 0.0, blue: 0.04 * extremePhase)
                            .opacity(0.42)
                    ],
                    center: UnitPoint(x: 0.5, y: 0.5),
                    startRadius: 62,
                    endRadius: 320
                )
            }

            // OVERLOAD: 外縁に深い深紅のリング（圧迫感）
            if t > 0.80 {
                let ovldPhase = (t - 0.80) / 0.20
                RadialGradient(
                    colors: [
                        .clear,
                        .clear,
                        Color(red: 0.70 * ovldPhase, green: 0.0, blue: 0.02)
                            .opacity(0.28 * ovldPhase)
                    ],
                    center: UnitPoint(x: 0.5, y: 0.5),
                    startRadius: 160,
                    endRadius: 370
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
        ZStack {
            vanishingPointGlow
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    let raw  = min(max(visualStress / 6.0, 0.0), 1.0)
                    let intn = pow(raw, 2.2)
                    let ms   = reduceMotion ? 0.08 : 1.0

                    // カメラドリフト（決定論的sinコンポジット）
                    let driftW   = (0.008 + intn * 0.088) * size.width
                    let driftH_c = (0.005 + intn * 0.060) * size.height
                    let cYaw = sin(t * 0.108) * driftW
                             + sin(t * 0.071 + 1.37) * driftW * 0.42
                             + sin(t * 0.047 + 0.88) * driftW * intn * 0.32
                    let cPitch = sin(t * 0.083 + 0.74) * driftH_c
                               + sin(t * 0.052 + 2.08) * driftH_c * 0.55
                               + sin(t * 0.038 + 1.55) * driftH_c * intn * 0.42
                    let vpX  = size.width  * 0.50 + (reduceMotion ? 0 : cYaw)
                    let vpY  = size.height * vpYRatio + (reduceMotion ? 0 : cPitch)
                    let diag = hypot(size.width, size.height)
                    let dt: Double = 0.016

                    // 残像閾値: 低=8.0pt(ほぼ点), 中=3.5pt, 高=0.5pt(ほぼ全星が尾を持つ)
                    let trailThresh: Double = reduceMotion ? 9999
                        : max(0.5, (1.0 - raw) * 7.0 + 0.5)
                    let wrapGate: Double = diag * 0.34

                    // グローバル色テーマ（score連動）
                    let globalHue: Double = {
                        if raw < 0.30 {
                            return 0.70 - (raw / 0.30) * 0.08
                        } else if raw < 0.65 {
                            return 0.62 - ((raw - 0.30) / 0.35) * 0.15
                        } else {
                            return 0.47
                        }
                    }()

                    // 暖色アクセント確率 (score>0.38 から出現, score=1.0 で最大90%)
                    let warmChance: Double = max(0.0, (raw - 0.38) / 0.62) * 0.90

                    // 輝度ブースト
                    let briBoost: Double = {
                        if raw < 0.50 { return 1.0 + raw * 0.60 }
                        else          { return 1.30 + (raw - 0.50) * 0.60 }
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

                            let sizeBoost = (isNearLyr || isMidLyr) ? (1.0 + raw * 0.28) : 1.0
                            let dotSz = min(5.8, max(0.5,
                                (0.5 + depthFrac * layer.dotMul * 2.5) * sizeBoost))

                            // 色計算
                            let hueFrac = sin(s * 43.71) * 0.5 + 0.5
                            let satFrac = cos(s * 29.13) * 0.5 + 0.5

                            let isWhite   = (Int(s) % 9 == 0)
                            let canBeWarm = !isWhite && (isNearLyr || isMidLyr)
                            let warmRand  = Double(Int(s * 31.7 + Double(li) * 7.3).magnitude % 100) / 100.0
                            let isWarm    = canBeWarm && warmRand < warmChance
                            let isRedWarm = isWarm && (Int(s * 7.3).magnitude % 5 < 3)

                            let hue: Double
                            let sat: Double
                            let bri: Double

                            if isRedWarm {
                                hue = 0.88 + hueFrac * 0.10
                                sat = 0.88 + min(0.12, warmChance * 0.4)
                                bri = 0.90 + hueFrac * 0.10
                            } else if isWarm {
                                hue = 0.04 + hueFrac * 0.08
                                sat = 0.92 + min(0.08, warmChance * 0.2)
                                bri = 0.88 + hueFrac * 0.12
                            } else if isWhite {
                                hue = globalHue + 0.01
                                sat = max(0, raw * 0.06)
                                bri = 1.0
                            } else {
                                let hueSpread = 0.050 + (1.0 - raw) * 0.020
                                hue = globalHue + (hueFrac - 0.5) * hueSpread
                                let satBase: Double
                                if raw < 0.50      { satBase = 0.12 + raw * 1.00 }
                                else if raw < 0.70 { satBase = 0.62 + (raw - 0.50) * 0.90 }
                                else               { satBase = 0.80 + (raw - 0.70) * 0.60 }
                                sat = min(1.0, satBase * (0.40 + satFrac * 0.60))
                                bri = (Int(s) % 5 == 0) ? 1.0 : (0.62 + hueFrac * 0.38)
                            }

                            let starCol = Color(
                                hue:        hue.truncatingRemainder(dividingBy: 1.0),
                                saturation: min(1.0, sat),
                                brightness: min(1.0, bri)
                            )

                            // ─── 近景: 横揺れジッター（高緊張時の乱流感）
                            // 同一オフセットを xj に適用 → 尾の方向は維持しつつ頭が揺れる
                            let nearJitter: CGFloat = isNearLyr && intn > 0.22
                                ? CGFloat(sin(t * (0.195 + sin(s * 4.35) * 0.105) + s * 2.82)
                                          * (intn - 0.22) * 11.5)
                                : 0
                            let xj = x + nearJitter  // jittered head position (near only)

                            // ─────────────────────────────────────────────────────
                            // レンダリング（3層分岐）
                            // ─────────────────────────────────────────────────────

                            if isNearLyr {
                                // ── NEAR: streak primary（常に線として描画）
                                let velSafe = max(velocity, 0.5)
                                let nx = dvx / velSafe
                                let ny = dvy / velSafe
                                // 最小長 3pt 保証、高速ワープ感のため伸長係数を引き上げ
                                let streakLen = max(3.0, min(velocity * 1.30, maxTrailPx))
                                let txEnd = xj - CGFloat(nx) * streakLen
                                let tyEnd = y  - CGFloat(ny) * streakLen

                                let sw = max(0.45, dotSz * 0.46 + intn * 1.15)

                                var stk = Path()
                                stk.move(to:    CGPoint(x: xj,    y: y))
                                stk.addLine(to: CGPoint(x: txEnd, y: tyEnd))

                                // 外側ソフトグロー（wider → より輝く尾）
                                ctx.stroke(stk, with: .color(starCol.opacity(alpha * 0.17)),
                                           lineWidth: sw * 5.5)
                                // 内側グロー
                                ctx.stroke(stk, with: .color(starCol.opacity(alpha * 0.52)),
                                           lineWidth: sw * 1.8)
                                // コア（薄く＝シャープ）
                                ctx.stroke(stk, with: .color(starCol.opacity(alpha * 0.96)),
                                           lineWidth: sw * 0.50)
                                // 先端ドット（明るい点光源）
                                let hr = max(0.45, dotSz * 0.38)
                                ctx.fill(
                                    Path(ellipseIn: CGRect(x: xj - hr, y: y - hr,
                                                           width: hr * 2, height: hr * 2)),
                                    with: .color(Color.white.opacity(alpha * 0.72))
                                )

                            } else if isMidLyr {
                                // ── MID: trail primary at medium+ speed

                                // ハロー（中強度以上で出現）
                                if raw > 0.20 {
                                    let haloFrac = max(0.0, (raw - 0.22) / 0.78)
                                    let haloR = dotSz * (0.50 + haloFrac * 1.55)
                                    ctx.fill(
                                        Path(ellipseIn: CGRect(x: x - haloR, y: y - haloR,
                                                               width: haloR * 2, height: haloR * 2)),
                                        with: .color(starCol.opacity(alpha * haloFrac * 0.25))
                                    )
                                }

                                // 中程度以上の速度でトレイル
                                if velocity > trailThresh * 0.42 {
                                    let capped = min(velocity, maxTrailPx)
                                    let scale  = capped / max(velocity, 1e-9)
                                    let txEnd  = x - dvx * scale
                                    let tyEnd  = y - dvy * scale
                                    var trail  = Path()
                                    trail.move(to:    CGPoint(x: x, y: y))
                                    trail.addLine(to: CGPoint(x: txEnd, y: tyEnd))
                                    let tw = max(0.35, dotSz * 0.38)
                                    ctx.stroke(trail, with: .color(starCol.opacity(alpha * 0.20)),
                                               lineWidth: tw * 3.5)
                                    let ta = alpha * (0.48 + intn * 0.42)
                                    ctx.stroke(trail, with: .color(starCol.opacity(ta)),
                                               lineWidth: tw)
                                }

                                // 星点
                                ctx.fill(
                                    Path(ellipseIn: CGRect(x: x - dotSz / 2, y: y - dotSz / 2,
                                                           width: dotSz, height: dotSz)),
                                    with: .color(starCol.opacity(alpha))
                                )

                            } else {
                                // ── FAR: tiny sparkle points

                                // 微小ハロー（高強度のみ）
                                if raw > 0.35 {
                                    let haloFrac = max(0.0, (raw - 0.35) / 0.65)
                                    let haloR = dotSz * (0.38 + haloFrac * 1.0)
                                    ctx.fill(
                                        Path(ellipseIn: CGRect(x: x - haloR, y: y - haloR,
                                                               width: haloR * 2, height: haloR * 2)),
                                        with: .color(starCol.opacity(alpha * haloFrac * 0.14))
                                    )
                                }

                                // 高強度時のトレイル（遠景でも流れる）
                                if velocity > trailThresh {
                                    let capped = min(velocity, maxTrailPx)
                                    let scale  = capped / max(velocity, 1e-9)
                                    let txEnd  = x - dvx * scale
                                    let tyEnd  = y - dvy * scale
                                    var trail  = Path()
                                    trail.move(to:    CGPoint(x: x, y: y))
                                    trail.addLine(to: CGPoint(x: txEnd, y: tyEnd))
                                    ctx.stroke(trail, with: .color(starCol.opacity(alpha * 0.38)),
                                               lineWidth: 0.45)
                                }

                                // 小さな点（リアルな星の点光源）
                                let tr = max(0.28, dotSz * 0.50)
                                ctx.fill(
                                    Path(ellipseIn: CGRect(x: x - tr, y: y - tr,
                                                           width: tr * 2, height: tr * 2)),
                                    with: .color(starCol.opacity(alpha))
                                )

                                // 白い明るい星に十字光芒（sparkle cross）
                                if isWhite && alpha > 0.28 && tr > 0.32 {
                                    let cl = tr * 3.2
                                    var vl = Path()
                                    vl.move(to: CGPoint(x: x, y: y - cl))
                                    vl.addLine(to: CGPoint(x: x, y: y + cl))
                                    var hl = Path()
                                    hl.move(to: CGPoint(x: x - cl * 1.7, y: y))
                                    hl.addLine(to: CGPoint(x: x + cl * 1.7, y: y))
                                    ctx.stroke(vl, with: .color(starCol.opacity(alpha * 0.28)),
                                               lineWidth: 0.32)
                                    ctx.stroke(hl, with: .color(starCol.opacity(alpha * 0.28)),
                                               lineWidth: 0.32)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 消失点グロー: 星が向かう中心点の光源感
    private var vanishingPointGlow: some View {
        let raw = min(max(visualStress / 6.0, 0.0), 1.0)
        return ZStack {
            // コアグロー（狭い白/シアン — 強化版）
            RadialGradient(
                colors: [
                    Color.white.opacity(0.092 + raw * 0.110),
                    Color.cyan.opacity(0.042 + raw * 0.055),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: vpYRatio),
                startRadius: 2,
                endRadius: 95
            )
            .blendMode(.screen)

            // 広いアンビエント（星雲感 — 強化版）
            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.055 + raw * 0.065),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: vpYRatio),
                startRadius: 18,
                endRadius: 220
            )
            .blendMode(.screen)

            // ALERT以降: 暖色（橙/赤）アラートグロー（強化版）
            if raw > 0.46 {
                let alertP = (raw - 0.46) / 0.54
                RadialGradient(
                    colors: [
                        Color(hue: 0.04, saturation: 0.95, brightness: 1.0)
                            .opacity(alertP * 0.145),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: vpYRatio),
                    startRadius: 0,
                    endRadius: 180
                )
                .blendMode(.screen)
            }

            // OVERLOAD: 赤/深紅コアフラッシュ
            if raw > 0.78 {
                let ovldP = (raw - 0.78) / 0.22
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.05, blue: 0.05)
                            .opacity(ovldP * 0.18),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: vpYRatio),
                    startRadius: 0,
                    endRadius: 90
                )
                .blendMode(.screen)
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
