import SwiftUI

// MARK: - Design principle (imageUI.png reference)
//
// ■ 「星が速く流れる宇宙」を実現する
//    × 「白い棒が中央から伸びる」→ 廃止
//    ○ 「青い細い線が中央から外へ移動する（先端明・末尾暗）」
//
// ■ Perspective Starfield アルゴリズム
//    各星: seed から決定論的な baseX/Y/Z + speed
//    time × score × speed で z を更新 → z↓ = 手前 = 大きく速く
//    screenXY = perspective projection (消失点中心)
//    streak = prevScreenXY → currentScreenXY (速度の残像)
//
// ■ Tapered rendering (先端→末尾グラデーション)
//    先端 (現在位置): 明るい・細い
//    末尾 (旧位置):  暗い・なし
//    先端に大きな丸なし → 「棒に球」の廃止
//
// ■ 色方針
//    60% blue (hue 0.625-0.655)
//    25% cyan (hue 0.580-0.620)
//    10% white
//     5% warm accent (ALERT+ のみ)

private struct StarLayer {
    let count:      Int
    let xRange:     Double
    let yRange:     Double
    let zDepth:     Double
    let baseSpd:    Double  // CALM時基本速度
    let strSpd:     Double  // ストレス加算速度
    let sizeMul:    Double
    let brightFl:   Double
    let brightDp:   Double
    let trailRatio: Double  // maxTrailPx = diag * trailRatio
}

// ── 層設定 ──────────────────────────────────────────────────────
// Far:  宇宙の奥行き・高密度点群・極低速
// Mid:  中景ストリーク・はっきり動く
// Near: 近景ワープ・高速ストリーク・星が見えて移動している
// ─────────────────────────────────────────────────────────────
private let kFar = StarLayer(
    count: 1000, xRange: 2600, yRange: 1600, zDepth: 9500,
    baseSpd: 0.40, strSpd: 14.0,
    sizeMul: 0.42, brightFl: 0.090, brightDp: 2.10,
    trailRatio: 0.012
)
private let kMid = StarLayer(
    count: 240, xRange: 1280, yRange:  780, zDepth: 5500,
    baseSpd: 0.92, strSpd: 66.0,
    sizeMul: 0.92, brightFl: 0.098, brightDp: 2.20,
    trailRatio: 0.18
)
private let kNear = StarLayer(
    count: 110, xRange:  420, yRange:  330, zDepth: 2200,
    baseSpd: 1.48, strSpd: 178.0,
    sizeMul: 1.65, brightFl: 0.140, brightDp: 2.80,
    trailRatio: 0.30
)
private let kLayers: [StarLayer] = [kFar, kMid, kNear]
private let kFocal: Double = 440.0

// MARK: - Outer View

struct SpaceshipStateGraphicView: View {
    let input: GraphicInput
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var rawIntensity: Double { min(max(input.score / 100.0, 0.0), 1.0) }

    var body: some View {
        ZStack {
            spaceBackground
                .animation(.easeInOut(duration: 1.8), value: rawIntensity)
            StarFieldCanvas(visualStress: rawIntensity * 6.0, reduceMotion: reduceMotion)
            warpVignette
        }
    }

    // MARK: - Space background

    private var spaceBackground: some View {
        let t = rawIntensity

        // Base: 常に深宇宙黒〜濃紺
        let topB: Double = max(0.06, 0.12 - t * 0.045)
        let topR: Double = t < 0.65 ? t * 0.012 : 0.0078 + (t - 0.65) * 0.065
        let topG: Double = t < 0.65 ? t * 0.008 : 0.0052 + (t - 0.65) * 0.022

        let botB: Double = max(0.025, 0.055 - t * 0.022)
        let botR: Double = t < 0.65 ? t * 0.005 : 0.0033 + (t - 0.65) * 0.032
        let botG: Double = t < 0.65 ? t * 0.003 : 0.002 + (t - 0.65) * 0.010

        return ZStack {
            // ベース宇宙背景
            LinearGradient(
                colors: [
                    Color(red: topR, green: topG, blue: topB),
                    Color(red: botR, green: botG, blue: botB)
                ],
                startPoint: .top, endPoint: .bottom
            )

            // 常時ブルーネビュラ（ストレスに依存しない宇宙の奥行き）
            RadialGradient(
                colors: [
                    Color(hue: 0.638, saturation: 0.88, brightness: 0.78).opacity(0.07),
                    Color(hue: 0.645, saturation: 0.90, brightness: 0.72).opacity(0.03),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 30, endRadius: 220
            )
            .blendMode(.screen)

            // OVERLOAD: 消失点近傍にごく薄い暖色（控えめに）
            if t > 0.72 {
                let ap = (t - 0.72) / 0.28
                RadialGradient(
                    colors: [
                        Color(red: ap * 0.12, green: ap * 0.004, blue: 0).opacity(0.16),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.35),
                    startRadius: 0, endRadius: 140
                )
            }

            // ALERT 外縁: 薄い赤みのネビュラ
            if t > 0.58 {
                let ep = (t - 0.58) / 0.42
                RadialGradient(
                    colors: [.clear,
                             Color(red: 0.40 * ep, green: 0, blue: 0.04 * ep).opacity(0.30)],
                    center: UnitPoint(x: 0.5, y: 0.5),
                    startRadius: 70, endRadius: 370
                )
            }

            // OVERLOAD: 深紅アンビエント（宇宙の緊急感）
            if t > 0.80 {
                let op = (t - 0.80) / 0.20
                Color(red: 0.048 * op, green: 0, blue: 0).opacity(0.34 * op)
            }
        }
    }

    // MARK: - Warp vignette

    private var warpVignette: some View {
        let t = rawIntensity
        return ZStack {
            // 消失点起点の引力ビネット
            RadialGradient(
                colors: [.clear, .clear, Color.black.opacity(0.10 + t * 0.36)],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 85, endRadius: 360
            )
            // 四隅コーナー暗化（コックピット窓感）
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.18 + t * 0.20)],
                center: .center,
                startRadius: 195, endRadius: 395
            )
            .blendMode(.multiply)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 1.5), value: t)
    }
}

// MARK: - StarFieldCanvas

private struct StarFieldCanvas: View {
    let visualStress: Double
    let reduceMotion: Bool

    private let vpYRatio: Double = 0.34  // 消失点位置

    var body: some View {
        ZStack {
            vanishingPointGlow
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    renderAllStars(ctx: ctx, size: size, t: t)
                }
            }
        }
    }

    // MARK: - Vanishing point glow (消失点: 青/白 光源)

    private var vanishingPointGlow: some View {
        let raw = min(max(visualStress / 6.0, 0), 1)
        return ZStack {
            // ── コア白熱 (常時)
            RadialGradient(
                colors: [
                    Color.white.opacity(0.55 + raw * 0.35),
                    Color(hue: 0.62, saturation: 0.85, brightness: 1.0).opacity(0.28 + raw * 0.22),
                    Color(hue: 0.62, saturation: 0.95, brightness: 1.0).opacity(0.08 + raw * 0.12),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: vpYRatio),
                startRadius: 0, endRadius: 68
            )
            .blendMode(.screen)

            // ── 青アンビエント (星雲状)
            RadialGradient(
                colors: [
                    Color(hue: 0.62, saturation: 0.90, brightness: 0.95).opacity(0.14 + raw * 0.20),
                    Color(hue: 0.65, saturation: 0.95, brightness: 0.90).opacity(0.06 + raw * 0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: vpYRatio),
                startRadius: 18, endRadius: 280
            )
            .blendMode(.screen)

            // ── 超高輝度コア (ブリリアント)
            RadialGradient(
                colors: [Color.white.opacity(0.22 + raw * 0.30), .clear],
                center: UnitPoint(x: 0.5, y: vpYRatio),
                startRadius: 0, endRadius: 20
            )
            .blendMode(.screen)

            // ── OVERLOAD: 橙アクセント (消失点近傍のみ・極控えめ)
            if raw > 0.75 {
                let ap = (raw - 0.75) / 0.25
                RadialGradient(
                    colors: [
                        Color(hue: 0.065, saturation: 0.92, brightness: 1.0).opacity(ap * 0.12),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: vpYRatio),
                    startRadius: 0, endRadius: 90
                )
                .blendMode(.screen)
            }

            // ── OVERLOAD: 赤コアフラッシュ
            if raw > 0.80 {
                let op = (raw - 0.80) / 0.20
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.08, blue: 0.04).opacity(op * 0.44),
                        Color(red: 0.60, green: 0, blue: 0).opacity(op * 0.18),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: vpYRatio),
                    startRadius: 0, endRadius: 105
                )
                .blendMode(.screen)
            }
        }
    }

    // MARK: - Star rendering

    private func renderAllStars(ctx: GraphicsContext, size: CGSize, t: Double) {
        let raw   = min(max(visualStress / 6.0, 0.0), 1.0)
        let intn  = raw * raw  // quadratic
        let ms    = reduceMotion ? 0.04 : 1.0

        // カメラドリフト
        let dW = (0.004 + intn * 0.065) * size.width
        let dH = (0.003 + intn * 0.045) * size.height
        let cYaw   = sin(t * 0.104) * dW + sin(t * 0.067 + 1.37) * dW * 0.40
        let cPitch = sin(t * 0.079 + 0.74) * dH + sin(t * 0.048 + 2.08) * dH * 0.52
        let vpX = size.width  * 0.50 + (reduceMotion ? 0 : cYaw)
        let vpY = size.height * vpYRatio + (reduceMotion ? 0 : cPitch)
        let diag = hypot(size.width, size.height)
        let dt: Double = 0.016

        // 発散除去ゲート (z 再循環を起こした星を無視)
        let warpGate: Double = diag * 0.48

        // 輝度ブースト (ストレス上昇で星が明るくなる)
        let briBoost = 1.0 + raw * 0.55

        // ── 色設計 ─────────────────────────────────────────────
        // imageUI.png 参照: 全体を BLUE/CYAN 基調に
        // 深青 (hue 0.640): CALM
        // シアン寄り青 (hue 0.620): ALERT+
        let globalHue: Double = raw < 0.45 ? 0.640 : (raw < 0.70 ? 0.640 - (raw-0.45)/0.25*0.018 : 0.622)

        // 暖色アクセント (OVERLOAD のみ、最大 8%) ← blue dominant を保つ
        let warmChance: Double = max(0.0, (raw - 0.72) / 0.28) * 0.08

        var seedIdx = 0

        for layer in kLayers {
            let spdMult    = (layer.baseSpd + intn * layer.strSpd) * ms
            let maxTrailPx = diag * layer.trailRatio
            let isNear     = layer.count == kNear.count
            let isMid      = layer.count == kMid.count

            for li in 0..<layer.count {
                let s     = Double(seedIdx)
                let phOff = Double(li) * (layer.zDepth / Double(layer.count))
                seedIdx += 1

                // 3D位置 (seed決定論的)
                let x3d = sin(s * 12.9898 + 0.731) * layer.xRange
                let y3d = cos(s * 78.233  + 0.314) * layer.yRange

                // z: time × speed で前進、zDepth で周回
                var z = layer.zDepth
                    - (t * 62.0 * spdMult + phOff)
                      .truncatingRemainder(dividingBy: layer.zDepth)
                if z < 1 { z = 1 }
                var zPrev = layer.zDepth
                    - ((t - dt) * 62.0 * spdMult + phOff)
                      .truncatingRemainder(dividingBy: layer.zDepth)
                if zPrev < 1 { zPrev = 1 }

                // Perspective projection → screen位置
                let p      = kFocal / z
                let pPrev  = kFocal / zPrev
                let sx     = vpX + x3d * p
                let sy     = vpY + y3d * p
                let sxPrev = vpX + x3d * pPrev
                let syPrev = vpY + y3d * pPrev

                // 速度ベクトル (prev→current)
                let dvx      = sx - sxPrev
                let dvy      = sy - syPrev
                let velocity = hypot(dvx, dvy)

                // 再循環した星は描画をスキップ
                guard velocity < warpGate else { continue }

                // 奥行き係数 (0=遠景, 1=近景)
                let depthFrac = max(0.0, 1.0 - z / layer.zDepth)

                // alpha
                let alpha = min(0.96,
                    (layer.brightFl + depthFrac * layer.brightDp * layer.brightFl * 12.5) * briBoost)

                // dot size
                let sizeBoost = (isNear || isMid) ? (1.0 + raw * 0.28) : 1.0
                let dotSz = min(5.0, max(0.38,
                    (0.40 + depthFrac * layer.sizeMul * 2.8) * sizeBoost))

                // ── 色計算 ──────────────────────────────────────
                let hueFrac = sin(s * 43.71) * 0.5 + 0.5
                let satFrac = cos(s * 29.13) * 0.5 + 0.5

                // 白い明星: 約10% (少なめ、本物の宇宙感)
                let isWhiteStar = (abs(Int(s * 173.14)) % 10 == 0)

                // 暖色アクセント (ALERT+ near/midのみ)
                let canBeWarm = !isWhiteStar && (isNear || isMid)
                let warmRand  = Double(abs(Int(s * 31.7 + Double(li) * 7.3)) % 100) / 100.0
                let isWarm    = canBeWarm && warmRand < warmChance
                let isRedHot  = isWarm && (abs(Int(s * 7.3)) % 3 == 0)

                let starHue: Double
                let starSat: Double
                let starBri: Double

                if isRedHot {
                    starHue = 0.92 + hueFrac * 0.07    // 赤〜赤紫
                    starSat = 0.82 + hueFrac * 0.12
                    starBri = 0.90 + hueFrac * 0.08
                } else if isWarm {
                    starHue = 0.05 + hueFrac * 0.08    // 橙
                    starSat = 0.84 + hueFrac * 0.10
                    starBri = 0.88 + hueFrac * 0.10
                } else if isWhiteStar {
                    // 白い明星 (輝度最大、彩度ほぼゼロ)
                    starHue = globalHue
                    starSat = max(0, raw * 0.06)
                    starBri = 1.0
                } else {
                    // 一般星: blue / cyan (imageUI.pngに合わせて彩度高め)
                    // 60% deep blue, 40% cyan-blue
                    let isCyan = (abs(Int(s * 97.3)) % 5 < 2)  // 40% cyan
                    let hueVar = isCyan
                        ? (globalHue - 0.038 + hueFrac * 0.025)    // シアン寄り
                        : (globalHue + 0.002 + hueFrac * 0.012)    // 深青
                    starHue = hueVar
                    starSat = 0.60 + satFrac * 0.32   // 0.60–0.92: しっかりした青
                    starBri = 0.72 + hueFrac * 0.26   // 0.72–0.98
                }

                let starCol = Color(
                    hue:        starHue.truncatingRemainder(dividingBy: 1.0),
                    saturation: min(1.0, starSat),
                    brightness: min(1.0, starBri)
                )

                // ── レンダリング ──────────────────────────────────

                if isNear {
                    renderNearStar(ctx: ctx, x: sx, y: sy, dvx: dvx, dvy: dvy,
                                   velocity: velocity, maxTrailPx: maxTrailPx,
                                   dotSz: dotSz, alpha: alpha, intn: intn,
                                   starCol: starCol, starHue: starHue, starSat: starSat)

                } else if isMid {
                    renderMidStar(ctx: ctx, x: sx, y: sy, dvx: dvx, dvy: dvy,
                                  velocity: velocity, maxTrailPx: maxTrailPx,
                                  dotSz: dotSz, alpha: alpha, intn: intn,
                                  starCol: starCol, isWhiteStar: isWhiteStar)

                } else {
                    renderFarStar(ctx: ctx, x: sx, y: sy, dvx: dvx, dvy: dvy,
                                  velocity: velocity, maxTrailPx: maxTrailPx,
                                  dotSz: dotSz, alpha: alpha, intn: intn,
                                  starCol: starCol, isWhiteStar: isWhiteStar)
                }
            }
        }
    }

    // MARK: - Near star (テーパード細ストリーク・先端に大きな丸なし)

    private func renderNearStar(
        ctx: GraphicsContext,
        x: Double, y: Double,
        dvx: Double, dvy: Double,
        velocity: Double, maxTrailPx: Double,
        dotSz: Double, alpha: Double, intn: Double,
        starCol: Color, starHue: Double, starSat: Double
    ) {
        let velSafe = max(velocity, 0.6)
        let nx = dvx / velSafe
        let ny = dvy / velSafe

        // ストリーク長: ストレスに応じて伸びる (CALM: short, OVERLOAD: medium)
        // 最大を diag*trailRatio*1.5 でキャップ → 画面幅の ~40% 程度
        let stretchFactor = 0.88 + intn * 3.0   // 0.88x → 3.88x
        let streakLen = max(5.0, min(velocity * stretchFactor, maxTrailPx * 1.5))

        // ストリーク末尾座標
        let tx = x - CGFloat(nx) * streakLen
        let ty = y - CGFloat(ny) * streakLen

        // 中間点 (先端から 55%, 25% の位置)
        let tx55 = x - CGFloat(nx) * streakLen * 0.55
        let ty55 = y - CGFloat(ny) * streakLen * 0.55
        let tx25 = x - CGFloat(nx) * streakLen * 0.25
        let ty25 = y - CGFloat(ny) * streakLen * 0.25

        // 線幅: 細め (1.0-1.6px) ← imageUI.png は thin line
        let sw = max(0.45, 0.50 + intn * 0.80)

        // ── テーパードレンダリング ─────────────────────────────
        // 1. 外側ソフトグロー (全長, 極薄) - FOCUS以上で出現
        if intn > 0.08 {
            let gFade = min(1.0, (intn - 0.08) / 0.25)
            var fullPath = Path()
            fullPath.move(to:    CGPoint(x: x,  y: y))
            fullPath.addLine(to: CGPoint(x: tx, y: ty))
            ctx.stroke(fullPath, with: .color(starCol.opacity(alpha * 0.04 * gFade)),
                       lineWidth: sw * 4.2)
        }

        // 2. 全長コア (末尾, 最も暗い)
        var fullPath = Path()
        fullPath.move(to:    CGPoint(x: x,  y: y))
        fullPath.addLine(to: CGPoint(x: tx, y: ty))
        ctx.stroke(fullPath, with: .color(starCol.opacity(alpha * 0.18)),
                   lineWidth: sw * 0.80)

        // 3. 中間 55% (中程度の輝き)
        var midPath = Path()
        midPath.move(to:    CGPoint(x: x,    y: y))
        midPath.addLine(to: CGPoint(x: tx55, y: ty55))
        ctx.stroke(midPath, with: .color(starCol.opacity(alpha * 0.46)),
                   lineWidth: sw * 0.78)

        // 4. 先端 25% (最も明るい・白に近い)
        // 先端ほど白みがかる (desaturate for brightness)
        let tipSat = max(0.0, starSat - 0.42)
        let tipCol = Color(hue: starHue.truncatingRemainder(dividingBy: 1.0),
                           saturation: tipSat, brightness: 1.0)
        var tipPath = Path()
        tipPath.move(to:    CGPoint(x: x,    y: y))
        tipPath.addLine(to: CGPoint(x: tx25, y: ty25))
        ctx.stroke(tipPath, with: .color(tipCol.opacity(alpha * 0.88)),
                   lineWidth: sw * 0.68)

        // 5. 先端の微小輝点 (大きな丸ではなく、非常に小さい点)
        // 「星の位置」を示す最小限の点 (1.0-1.8px)
        let tipR = max(0.35, dotSz * 0.24)  // 点に見せる・棒に見えない
        ctx.fill(
            Path(ellipseIn: CGRect(x: x - tipR, y: y - tipR,
                                   width: tipR * 2, height: tipR * 2)),
            with: .color(Color.white.opacity(alpha * 0.88))
        )
    }

    // MARK: - Mid star (中速ストリーク)

    private func renderMidStar(
        ctx: GraphicsContext,
        x: Double, y: Double,
        dvx: Double, dvy: Double,
        velocity: Double, maxTrailPx: Double,
        dotSz: Double, alpha: Double, intn: Double,
        starCol: Color, isWhiteStar: Bool
    ) {
        // 速度に応じたストリーク
        if velocity > 1.2 {
            let len   = min(velocity * (1.3 + intn * 2.0), maxTrailPx)
            let scale = len / max(velocity, 1e-9)
            let txEnd = x - dvx * scale
            let tyEnd = y - dvy * scale
            let tw = max(0.30, dotSz * 0.32)

            var trail = Path()
            trail.move(to:    CGPoint(x: x,     y: y))
            trail.addLine(to: CGPoint(x: txEnd, y: tyEnd))

            // 外グロー (中程度ストレス以上)
            if intn > 0.05 {
                ctx.stroke(trail, with: .color(starCol.opacity(alpha * 0.08 * min(1, intn / 0.22))),
                           lineWidth: tw * 3.8)
            }
            // メインストリーク
            ctx.stroke(trail, with: .color(starCol.opacity(alpha * (0.32 + intn * 0.48))),
                       lineWidth: tw * 0.85)

            // 先端セグメント (明)
            let tipLen = len * 0.28
            let tipScale = tipLen / max(velocity, 1e-9)
            var tipTrail = Path()
            tipTrail.move(to:    CGPoint(x: x, y: y))
            tipTrail.addLine(to: CGPoint(x: x - dvx * tipScale, y: y - dvy * tipScale))
            ctx.stroke(tipTrail, with: .color(starCol.opacity(alpha * 0.72)),
                       lineWidth: tw * 0.72)
        }

        // 星点本体 (小さく)
        let r = max(0.28, dotSz * 0.40)
        ctx.fill(
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
            with: .color(starCol.opacity(alpha))
        )

        // 白い明星: 十字光芒 (細め)
        if isWhiteStar && alpha > 0.35 && r > 0.28 {
            let cl = r * 2.8
            var vl = Path()
            vl.move(to: CGPoint(x: x, y: y - cl))
            vl.addLine(to: CGPoint(x: x, y: y + cl))
            var hl = Path()
            hl.move(to: CGPoint(x: x - cl * 1.6, y: y))
            hl.addLine(to: CGPoint(x: x + cl * 1.6, y: y))
            ctx.stroke(vl, with: .color(starCol.opacity(alpha * 0.25)), lineWidth: 0.28)
            ctx.stroke(hl, with: .color(starCol.opacity(alpha * 0.25)), lineWidth: 0.28)
        }
    }

    // MARK: - Far star (背景点群)

    private func renderFarStar(
        ctx: GraphicsContext,
        x: Double, y: Double,
        dvx: Double, dvy: Double,
        velocity: Double, maxTrailPx: Double,
        dotSz: Double, alpha: Double, intn: Double,
        starCol: Color, isWhiteStar: Bool
    ) {
        // 速度が十分なら微細なトレイル
        if velocity > 2.0 {
            let len   = min(velocity * (1.0 + intn * 1.0), maxTrailPx)
            let scale = len / max(velocity, 1e-9)
            var trail = Path()
            trail.move(to:    CGPoint(x: x, y: y))
            trail.addLine(to: CGPoint(x: x - dvx * scale, y: y - dvy * scale))
            ctx.stroke(trail, with: .color(starCol.opacity(alpha * 0.35)), lineWidth: 0.42)
        }

        let r = max(0.25, dotSz * 0.44)
        ctx.fill(
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
            with: .color(starCol.opacity(alpha))
        )

        // 白い明星: 十字光芒 (非常に細め)
        if isWhiteStar && alpha > 0.30 && r > 0.28 {
            let cl = r * 3.0
            var vl = Path()
            vl.move(to: CGPoint(x: x, y: y - cl))
            vl.addLine(to: CGPoint(x: x, y: y + cl))
            var hl = Path()
            hl.move(to: CGPoint(x: x - cl * 1.6, y: y))
            hl.addLine(to: CGPoint(x: x + cl * 1.6, y: y))
            ctx.stroke(vl, with: .color(starCol.opacity(alpha * 0.22)), lineWidth: 0.28)
            ctx.stroke(hl, with: .color(starCol.opacity(alpha * 0.22)), lineWidth: 0.28)
        }
    }
}

// MARK: - Preview

#Preview("Warp States") {
    ScrollView {
        VStack(spacing: 6) {
            ForEach([8, 38, 68, 90] as [Int], id: \.self) { score in
                VStack(spacing: 2) {
                    Text("score \(score)")
                        .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.4))
                    ZStack {
                        Color(red: 0, green: 0.006, blue: 0.04)
                        SpaceshipStateGraphicView(
                            input: GraphicInput(score: Double(score), confidence: 0.9,
                                                state: .optimalTension)
                        )
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }.padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
