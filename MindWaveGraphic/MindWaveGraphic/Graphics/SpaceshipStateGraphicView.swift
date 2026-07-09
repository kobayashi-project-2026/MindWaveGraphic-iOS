import SwiftUI

// MARK: - Layer config
// 設計方針:
//   Far  : 500星・低速点群 → 宇宙の奥行き感
//   Mid  : 180星・中速ストリーク → 前進する動き
//   Near :  80星・高速ストリーク → ワープ感
//
// 色: 基本は白/淡青/シアン（宇宙らしい色）
//     暖色は ALERT以降の限定アクセント（最大15%）
//     虹色・多色ビームは廃止

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

private let kFar = StarLayer(
    count: 560, xRange: 1900, yRange: 1500, zDepth: 9000,
    baseSpd: 0.35, strSpd:  10.0,
    dotMul: 0.46, brightFl: 0.080, brightDp: 1.85,
    trailRatio: 0.013
)
private let kMid = StarLayer(
    count: 200, xRange:  920, yRange:  720, zDepth: 5000,
    baseSpd: 0.80, strSpd:  60.0,
    dotMul: 1.05, brightFl: 0.105, brightDp: 2.05,
    trailRatio: 0.24
)
// Near: 宇宙船ワープ近景層
private let kNear = StarLayer(
    count:  90, xRange:  380, yRange:  295, zDepth: 1800,
    baseSpd: 1.30, strSpd: 160.0,
    dotMul: 1.90, brightFl: 0.148, brightDp: 2.60,
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
            warpVignette
        }
    }

    // MARK: - 宇宙背景

    private var spaceBackground: some View {
        let t = rawIntensity

        // ベース: 常に深い宇宙黒〜濃紺
        let topR: Double = t < 0.68 ? t * 0.014 : 0.0095 + (t - 0.68) * 0.065
        let topG: Double = t < 0.68 ? t * 0.010 : 0.0068 + (t - 0.68) * 0.025
        let topB: Double = max(0.07, 0.14 - t * 0.06)

        let botR: Double = t < 0.68 ? t * 0.006 : 0.0041 + (t - 0.68) * 0.030
        let botG: Double = t < 0.68 ? t * 0.004 : 0.0027 + (t - 0.68) * 0.010
        let botB: Double = max(0.028, 0.065 - t * 0.030)

        return ZStack {
            // 宇宙背景グラデーション（ほぼ黒〜濃紺）
            LinearGradient(
                colors: [
                    Color(red: topR, green: topG, blue: topB),
                    Color(red: botR, green: botG, blue: botB)
                ],
                startPoint: .top, endPoint: .bottom
            )

            // ALERT以降: 消失点付近に控えめな暖色大気
            // → 宇宙の「熱感」として演出（ネオンにしない）
            if t > 0.60 {
                let ap = (t - 0.60) / 0.40
                RadialGradient(
                    colors: [
                        Color(red: ap * 0.20, green: ap * 0.010, blue: 0.0).opacity(0.30),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.36),
                    startRadius: 0,
                    endRadius: 200
                )
            }

            // ALERT周辺: 外縁に赤みのわずかな染み（宇宙の深紅ネビュラ感）
            if t > 0.58 {
                let ep = (t - 0.58) / 0.42
                RadialGradient(
                    colors: [
                        .clear,
                        Color(red: 0.45 * ep, green: 0.0, blue: 0.04 * ep).opacity(0.38)
                    ],
                    center: UnitPoint(x: 0.5, y: 0.5),
                    startRadius: 60,
                    endRadius: 360
                )
            }

            // OVERLOAD: 深紅アンビエント（宇宙の危機感）
            if t > 0.78 {
                let op = (t - 0.78) / 0.22
                Color(red: 0.055 * op, green: 0.0, blue: 0.0).opacity(0.35 * op)
            }
        }
    }

    // MARK: - ワープビネット（エッジ暗化 + 四隅暗化で奥行き感）

    private var warpVignette: some View {
        let t = rawIntensity
        return ZStack {
            // メインビネット（消失点から外縁への暗化）
            RadialGradient(
                colors: [
                    .clear,
                    .clear,
                    Color.black.opacity(0.12 + t * 0.46)
                ],
                center: UnitPoint(x: 0.5, y: 0.36),
                startRadius: 80,
                endRadius: 350
            )
            // 四隅コーナービネット（コックピット窓感）
            RadialGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.20 + t * 0.28)
                ],
                center: .center,
                startRadius: 200,
                endRadius: 400
            )
            .blendMode(.multiply)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 1.4), value: t)
    }
}

// MARK: - Canvas StarFieldView

private struct StarFieldView: View {
    let visualStress: Double
    let reduceMotion: Bool

    private let vpYRatio: Double = 0.35

    var body: some View {
        ZStack {
            vanishingPointGlow
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    renderStars(ctx: ctx, size: size, t: t)
                }
            }
        }
    }

    // MARK: - Star rendering

    private func renderStars(ctx: GraphicsContext, size: CGSize, t: Double) {
        let raw  = min(max(visualStress / 6.0, 0.0), 1.0)
        let intn = raw * raw  // quadratic response
        let ms   = reduceMotion ? 0.05 : 1.0

        // カメラドリフト（高ストレスで揺れ増加）
        let driftW = (0.005 + intn * 0.075) * size.width
        let driftH = (0.003 + intn * 0.050) * size.height
        let cYaw = sin(t * 0.105) * driftW
                 + sin(t * 0.068 + 1.37) * driftW * 0.42
        let cPitch = sin(t * 0.080 + 0.74) * driftH
                   + sin(t * 0.049 + 2.08) * driftH * 0.55
        let vpX  = size.width  * 0.50 + (reduceMotion ? 0 : cYaw)
        let vpY  = size.height * vpYRatio + (reduceMotion ? 0 : cPitch)
        let diag = hypot(size.width, size.height)
        let dt: Double = 0.016

        let warpGate: Double = diag * 0.50
        let trailThresh: Double = reduceMotion ? 9999 : max(0.5, (1.0 - raw) * 5.0 + 0.5)

        // ─── 色方針 ─────────────────────────────────
        // globalHue: 常に青〜シアン域 (0.60–0.66)
        // ALERT以降でも amber/yellow には行かない
        let globalHue: Double = {
            if raw < 0.40      { return 0.655 }               // 深青
            else if raw < 0.68 { return 0.655 - (raw - 0.40) / 0.28 * 0.045 } // 青→シアン
            else               { return 0.610 }               // シアン固定
        }()

        // 暖色アクセント: ALERT 以降で出現、最大18% (宇宙の警戒色として限定使用)
        // CALM/FOCUSでは絶対ゼロ、ALERTから徐々に増加
        let warmChance: Double = max(0.0, (raw - 0.60) / 0.40) * 0.18

        // 輝度ブースト（ストレス上昇で星が明るくなる）
        let briBoost: Double = 1.0 + raw * 0.60

        var seedIdx = 0

        for layer in kLayers {
            let spdMult    = (layer.baseSpd + intn * layer.strSpd) * ms
            let maxTrailPx = diag * layer.trailRatio
            let isNear     = (layer.count == kNear.count)
            let isMid      = (layer.count == kMid.count)

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
                guard velocity < warpGate else { continue }

                let depthFrac = max(0.0, 1.0 - z / layer.zDepth)
                let alpha = min(0.97,
                    (layer.brightFl + depthFrac * layer.brightDp * layer.brightFl * 12.0)
                    * briBoost)

                let sizeBoost = (isNear || isMid) ? (1.0 + raw * 0.30) : 1.0
                let dotSz = min(5.5, max(0.40,
                    (0.42 + depthFrac * layer.dotMul * 2.5) * sizeBoost))

                // ─── 色計算 ──────────────────────────────────
                let hueFrac = sin(s * 43.71) * 0.5 + 0.5
                let satFrac = cos(s * 29.13) * 0.5 + 0.5

                // 白い明星: 約25%（real star colors are mostly white）
                let isWhite = (Int(s * 100) % 4 == 0)

                // 暖色アクセント: near/midのみ、ALERT以降の限定割り当て
                let canBeWarm = !isWhite && (isNear || isMid)
                let warmRand = Double(abs(Int(s * 31.7 + Double(li) * 7.3)) % 100) / 100.0
                let isWarm = canBeWarm && warmRand < warmChance
                let isRedHot = isWarm && (abs(Int(s * 7.3)) % 3 == 0)

                let hue:  Double
                let sat:  Double
                let bri:  Double

                if isRedHot {
                    // 暖色アクセント: 赤〜橙 (ALERT感を演出)
                    hue = 0.92 + hueFrac * 0.08   // 赤〜赤紫
                    sat = 0.85 + hueFrac * 0.10
                    bri = 0.92 + hueFrac * 0.06
                } else if isWarm {
                    // 暖色アクセント: 橙
                    hue = 0.06 + hueFrac * 0.08   // 橙
                    sat = 0.88 + hueFrac * 0.08
                    bri = 0.90 + hueFrac * 0.08
                } else if isWhite {
                    // 白〜わずかに青い明星
                    hue = globalHue + 0.01
                    sat = max(0, raw * 0.05)       // ほぼ純白
                    bri = 1.0
                } else {
                    // 一般星: 淡青〜白（彩度を抑えて宇宙らしい色に）
                    let hueVariance = 0.030 + (1.0 - raw) * 0.015
                    hue = globalHue + (hueFrac - 0.5) * hueVariance
                    sat = 0.20 + satFrac * 0.32    // 0.20–0.52: 淡青〜白（宇宙色）
                    bri = 0.70 + hueFrac * 0.30    // 0.70–1.0
                }

                let starCol = Color(
                    hue:        hue.truncatingRemainder(dividingBy: 1.0),
                    saturation: min(1.0, sat),
                    brightness: min(1.0, bri)
                )

                // ─── レンダリング ─────────────────────────────────

                if isNear {
                    // ── NEAR: ストレス感応型ワープストリーク
                    // CALM: 点が主役、細いコアのみ (ネオン棒にしない)
                    // OVERLOAD: ストリーク + 外グロー全開
                    let velSafe = max(velocity, 0.5)
                    let nx = dvx / velSafe
                    let ny = dvy / velSafe

                    let stretchFactor = 1.2 + intn * 2.6   // calm:1.2x → OVERLOAD:3.8x
                    let streakLen = max(4.0, min(velocity * stretchFactor, maxTrailPx * 1.8))

                    let sw = max(0.45, dotSz * 0.40 + intn * 1.20)

                    if streakLen > 5.0 && velocity > 1.8 {
                        let txEnd = x - CGFloat(nx) * streakLen
                        let tyEnd = y - CGFloat(ny) * streakLen
                        var stk = Path()
                        stk.move(to:    CGPoint(x: x, y: y))
                        stk.addLine(to: CGPoint(x: txEnd, y: tyEnd))

                        // 外側ハロー: FOCUS以上で段階的に出現 (CALM時はゼロ)
                        let outerGlow = min(1.0, max(0.0, (intn - 0.09) / 0.28))
                        if outerGlow > 0.02 {
                            ctx.stroke(stk, with: .color(starCol.opacity(alpha * 0.055 * outerGlow)),
                                       lineWidth: sw * 8.0)
                        }
                        // 中間グロー: わずかなストレスから徐々に
                        let midGlow = min(1.0, max(0.25, intn / 0.35))
                        ctx.stroke(stk, with: .color(starCol.opacity(alpha * 0.22 * midGlow)),
                                   lineWidth: sw * 2.0)
                        // シャープコア（常時）
                        ctx.stroke(stk, with: .color(starCol.opacity(alpha * 0.90)),
                                   lineWidth: sw * 0.48)
                    }

                    // 先端点光源（常に表示 - CALM時はこれが「星」の主役）
                    let hr = max(0.60, dotSz * 0.52)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - hr, y: y - hr,
                                               width: hr * 2, height: hr * 2)),
                        with: .color(Color.white.opacity(alpha * 0.97))
                    )
                    // 小さなハロー（点の輝き感）
                    let haloR = hr * (1.8 + intn * 2.0)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - haloR, y: y - haloR,
                                               width: haloR * 2, height: haloR * 2)),
                        with: .color(starCol.opacity(alpha * (0.08 + intn * 0.14)))
                    )

                } else if isMid {
                    // ── MID: 中速ストリーク（明確に移動が見える）

                    // 中速度以上でストリーク（低ストレスでも short trail）
                    if velocity > 1.5 {
                        let capped = min(velocity * (1.4 + intn * 2.4), maxTrailPx)
                        let scale  = capped / max(velocity, 1e-9)
                        let txEnd  = x - dvx * scale
                        let tyEnd  = y - dvy * scale
                        var trail  = Path()
                        trail.move(to:    CGPoint(x: x, y: y))
                        trail.addLine(to: CGPoint(x: txEnd, y: tyEnd))
                        let tw = max(0.32, dotSz * 0.34)
                        // 外グロー（FOCUS以上で）
                        if intn > 0.06 {
                            ctx.stroke(trail, with: .color(starCol.opacity(alpha * 0.10 * min(1, intn/0.25))),
                                       lineWidth: tw * 4.0)
                        }
                        ctx.stroke(trail, with: .color(starCol.opacity(alpha * (0.38 + intn * 0.50))),
                                   lineWidth: tw)
                    }

                    // 星点
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - dotSz / 2, y: y - dotSz / 2,
                                               width: dotSz, height: dotSz)),
                        with: .color(starCol.opacity(alpha))
                    )

                } else {
                    // ── FAR: 星点群（宇宙の背景星）

                    // 速度十分でわずかなトレイル
                    if velocity > trailThresh {
                        let capped = min(velocity * (1.1 + intn * 1.2), maxTrailPx)
                        let scale  = capped / max(velocity, 1e-9)
                        var trail  = Path()
                        trail.move(to:    CGPoint(x: x, y: y))
                        trail.addLine(to: CGPoint(x: x - dvx * scale, y: y - dvy * scale))
                        ctx.stroke(trail, with: .color(starCol.opacity(alpha * 0.38)),
                                   lineWidth: 0.45)
                    }

                    let tr = max(0.28, dotSz * 0.48)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - tr, y: y - tr,
                                               width: tr * 2, height: tr * 2)),
                        with: .color(starCol.opacity(alpha))
                    )

                    // 明星: 十字光芒（白い星のみ、控えめ）
                    if isWhite && alpha > 0.32 && tr > 0.30 {
                        let cl = tr * 3.2
                        var vl = Path()
                        vl.move(to: CGPoint(x: x, y: y - cl))
                        vl.addLine(to: CGPoint(x: x, y: y + cl))
                        var hl = Path()
                        hl.move(to: CGPoint(x: x - cl * 1.7, y: y))
                        hl.addLine(to: CGPoint(x: x + cl * 1.7, y: y))
                        ctx.stroke(vl, with: .color(starCol.opacity(alpha * 0.28)), lineWidth: 0.32)
                        ctx.stroke(hl, with: .color(starCol.opacity(alpha * 0.28)), lineWidth: 0.32)
                    }
                }
            }
        }
    }

    // MARK: - 消失点グロー

    private var vanishingPointGlow: some View {
        let raw = min(max(visualStress / 6.0, 0.0), 1.0)

        return ZStack {
            // ── コア白熱（消失点の引力感）
            RadialGradient(
                colors: [
                    Color.white.opacity(0.52 + raw * 0.38),   // calm:0.52 → OVERLOAD:0.90
                    Color.white.opacity(0.20 + raw * 0.18),
                    Color.cyan.opacity(0.14 + raw * 0.16),
                    Color.cyan.opacity(0.04 + raw * 0.06),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: vpYRatio),
                startRadius: 0,
                endRadius: 72
            )
            .blendMode(.screen)

            // シアンアンビエント（星雲状、常時）
            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.12 + raw * 0.18),
                    Color.blue.opacity(0.06 + raw * 0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: vpYRatio),
                startRadius: 20,
                endRadius: 280
            )
            .blendMode(.screen)

            // コア周辺のブリリアント（高輝度白熱点）
            RadialGradient(
                colors: [
                    Color.white.opacity(0.18 + raw * 0.28),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: vpYRatio),
                startRadius: 0,
                endRadius: 22
            )
            .blendMode(.screen)

            // ALERT: 橙アクセント（消失点のみ、控えめ）
            if raw > 0.58 {
                let ap = (raw - 0.58) / 0.42
                RadialGradient(
                    colors: [
                        Color(hue: 0.065, saturation: 0.92, brightness: 1.0)
                            .opacity(ap * 0.22),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: vpYRatio),
                    startRadius: 0,
                    endRadius: 150
                )
                .blendMode(.screen)
            }

            // OVERLOAD: 赤コアフラッシュ（宇宙船警報）
            if raw > 0.78 {
                let op = (raw - 0.78) / 0.22
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.10, blue: 0.05).opacity(op * 0.48),
                        Color(red: 0.65, green: 0.0,  blue: 0.0).opacity(op * 0.20),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: vpYRatio),
                    startRadius: 0,
                    endRadius: 110
                )
                .blendMode(.screen)
            }
        }
    }
}

// MARK: - Preview

#Preview("score 10/40/72/92") {
    ScrollView {
        VStack(spacing: 6) {
            ForEach([10, 40, 72, 92] as [Int], id: \.self) { score in
                VStack(spacing: 2) {
                    Text("score \(score)")
                        .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.4))
                    ZStack {
                        Color(red: 0, green: 0.008, blue: 0.05)
                        SpaceshipStateGraphicView(
                            input: GraphicInput(score: Double(score), confidence: 0.9,
                                                state: .optimalTension)
                        )
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }.padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
