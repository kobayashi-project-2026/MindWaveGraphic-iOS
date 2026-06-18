import SwiftUI

// ─────────────────────────────────────────────────────────
// StarfieldGraphicView
// GraphicInput.score (0-100) を3D星空の動きで可視化する。
//
// ■ score → 状態マッピング
//   score 0-32  (underAroused):   星が中心へ収束・奥へ引く。青〜青紫。沈静・エネルギー不足
//   score 33-69 (optimalTension): 緩やかな流れ。白〜シアン。安定・落ち着き
//   score 70-100 (overTense):     星が手前へ加速・軌跡が長い。オレンジ〜赤。過緊張・乱れ
//
// ■ score → signed stress 変換（フェーズB-4 仕様）
//   let signedStress = ((score - 50) / 50) * 6   // -6..6
//   score 0 → -6,  score 25 → -3,  score 50 → 0,  score 75 → +3,  score 100 → +6
//
// ■ confidence: 星・軌跡の透明度にのみ反映。速度や状態は変更しない。
//
// ■ 数値オーバーレイ: #if DEBUG でのみ表示。
//   本番Releaseで非表示にするには #if DEBUG ブロックをコメントアウトするだけでよい。
//
// ■ HealthKit / WatchConnectivity / ViewModel は一切参照しない。
// ─────────────────────────────────────────────────────────
/// 3D星空でGraphicInput.scoreを可視化するView。
/// HealthKit / WatchConnectivity / ViewModel は参照しない。
///
/// - Parameters:
///   - input: スコア・confidence・状態を含む入力値
///   - showsParameterOverlay: true のとき数値オーバーレイを表示。
///     本番で非表示にするには TeamGraphicView 側で false を渡すだけでよい。
///     現段階（実測確認中）は true を使用すること。
struct StarfieldGraphicView: View {
    let input: GraphicInput
    /// 数値オーバーレイ表示フラグ。デフォルトtrue（確認段階）。
    /// 本番非表示にするときは TeamGraphicView で false に変更する。
    var showsParameterOverlay: Bool = true

    // 800個の星。初回のみ生成し、フレームごとに再生成しない。
    @State private var stars: [Star] = StarfieldGraphicView.buildStars()

    // MARK: - Derived values

    // フェーズB-4: score 0-100 → signed stress -6..6
    private var signedStress: Double {
        let clamped = min(100, max(0, input.score))
        return ((clamped - 50) / 50) * 6
    }
    private var intensity: Double { abs(signedStress) / 6 }   // 0..1

    // フェーズB-6: confidence は透明度にのみ使用
    private var confidenceOpacity: Double {
        let c = min(1, max(0, input.confidence))
        return 0.4 + c * 0.6
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black

            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    draw(ctx: ctx, size: size,
                         time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }

            // 数値オーバーレイ（showsParameterOverlay が true のとき表示）
            // 本番非表示は TeamGraphicView 側で showsParameterOverlay: false を渡す
            if showsParameterOverlay {
                scoreOverlay
            }
        }
    }

    // MARK: - Canvas 描画（フレームごと）

    private func draw(ctx: GraphicsContext, size: CGSize, time: TimeInterval) {
        let speed      = computeSpeed()
        let trailFrac  = intensity * 0.05        // 軌跡長（z差）
        let starColor  = baseColor()
        let cx         = size.width  / 2
        let cy         = size.height / 2

        for star in stars {
            // z: 0.005..1 (小=手前, 大=奥)
            // speed > 0 → z 減少（手前へ加速）
            // speed < 0 → z 増加（奥へ収束）
            var rawZ = star.z - time * speed * 0.4
            rawZ = rawZ.truncatingRemainder(dividingBy: 1.0)
            if rawZ <= 0 { rawZ += 1.0 }
            let z = max(0.005, rawZ)

            // 透視投影：z が小さいほど拡大・端へ広がる
            let scale = 1.0 / z
            let px = star.x * scale * size.width  * 0.5 + cx
            let py = star.y * scale * size.height * 0.5 + cy

            guard px > -30, px < size.width  + 30,
                  py > -30, py < size.height + 30 else { continue }

            // 手前ほど大きく・明るい
            let nearness    = max(0, 1.0 - z)
            let radius      = max(0.25, nearness * 2.4)
            let starOpacity = min(1.0, nearness * confidenceOpacity * 1.8)

            // 軌跡（intensity > 0.05 のみ描画）
            if intensity > 0.05 && trailFrac > 0.001 {
                // 軌跡は星より奥（大きいz）の位置。speed > 0 では trail が中心寄りに見える
                let trailZ     = min(1.0, z + trailFrac)
                let trailScale = 1.0 / trailZ
                let tx         = star.x * trailScale * size.width  * 0.5 + cx
                let ty         = star.y * trailScale * size.height * 0.5 + cy
                var path = Path()
                path.move(to: CGPoint(x: tx, y: ty))
                path.addLine(to: CGPoint(x: px, y: py))
                ctx.stroke(path,
                           with: .color(starColor.opacity(starOpacity * 0.25)),
                           lineWidth: max(0.2, radius * 0.4))
            }

            // 星本体
            let rect = CGRect(x: px - radius, y: py - radius,
                              width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: rect),
                     with: .color(starColor.opacity(starOpacity)))
        }
    }

    // MARK: - 速度計算

    /// stress < 0 (低): 奥へ収束（z増加）→ 負の速度
    /// stress = 0 (適): 穏やか
    /// stress > 0 (高): 手前へ加速（z減少）→ 正の速度
    private func computeSpeed() -> Double {
        if signedStress > 0 {
            return 0.08 + (signedStress / 6) * 0.52   // 0.08..0.60
        } else if signedStress < 0 {
            return -0.02 - (abs(signedStress) / 6) * 0.10  // -0.02..-0.12
        }
        return 0.03
    }

    // MARK: - 状態別カラー（フェーズB-5 仕様、控えめ）

    private func baseColor() -> Color {
        switch input.state {
        case .underAroused:
            // 青〜青紫：沈静・エネルギー不足
            return Color(red: 0.38, green: 0.45, blue: 0.92)
        case .optimalTension:
            // 白〜シアン：安定・最適
            return Color(red: 0.80, green: 0.92, blue: 1.00)
        case .overTense:
            // オレンジ〜赤：過緊張・乱れ
            return Color(red: 0.96, green: 0.46, blue: 0.18)
        }
    }

    // MARK: - 数値オーバーレイ（フェーズB-7）

    private var scoreOverlay: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f", input.score))
                    .font(.system(size: 20, weight: .thin, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .contentTransition(.numericText())
                Text("/ 100")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.28))
            }
            Text(String(format: "conf %.2f", min(1, max(0, input.confidence))))
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(0.22))
            Text(input.state.displayName)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(baseColor().opacity(0.45))
        }
        .animation(.easeInOut(duration: 0.4), value: input.score)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }

    // MARK: - 星データ生成（起動時1回のみ）

    private static func buildStars() -> [Star] {
        (0..<800).map { _ in
            Star(x: Double.random(in: -1...1),
                 y: Double.random(in: -1...1),
                 z: Double.random(in: 0.01...1.0))
        }
    }
}

// MARK: - Star

struct Star: Sendable {
    let x: Double   // -1..1 横方向（中心=0）
    let y: Double   // -1..1 縦方向（中心=0）
    let z: Double   // 0.01..1.0 奥行き（小=手前, 大=奥）
}

// MARK: - Preview

#Preview {
    StarfieldPreviewHarness()
}

// StarfieldPreviewHarness: Preview 専用。本番アプリには含まれない。
// score 0-100 / confidence 0-1 の Slider で視覚確認する。
private struct StarfieldPreviewHarness: View {
    @State private var score: Double      = 50
    @State private var confidence: Double = 0.75

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                StarfieldGraphicView(
                    input: GraphicInput(
                        score:      score,
                        confidence: confidence,
                        state:      MindState.from(score: score)
                    )
                )
                .frame(height: 220)

                VStack(spacing: 8) {
                    HStack {
                        Text("Score: \(String(format: "%.0f", score))")
                        Spacer()
                        Text("Confidence: \(String(format: "%.2f", confidence))")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.6))

                    Slider(value: $score,      in: 0...100)
                        .tint(.cyan)
                    Slider(value: $confidence, in: 0...1)
                        .tint(.orange)

                    // 5段階クイック確認ボタン（フェーズB-12）
                    HStack(spacing: 8) {
                        ForEach([0, 25, 50, 75, 100], id: \.self) { s in
                            Button(String(s)) {
                                score = Double(s)
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(0.12))
                            )
                        }
                    }
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
    }
}
