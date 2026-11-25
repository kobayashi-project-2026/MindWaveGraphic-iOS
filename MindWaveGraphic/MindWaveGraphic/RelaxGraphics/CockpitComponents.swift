import SwiftUI

enum MWCockpit {
    static let deep = Color(red: 0.027, green: 0.048, blue: 0.084)
    static let tint = Color(red: 0.36, green: 0.88, blue: 0.94)
    static let primary = Color(red: 0.90, green: 0.95, blue: 0.98)
    static let muted = Color(red: 0.64, green: 0.73, blue: 0.80)
}

struct MWCockpitBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [MWCockpit.deep, Color(red: 0.047, green: 0.083, blue: 0.135)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                drawStars(in: context, size: size)
                drawPlanet(in: context, size: size)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drawStars(in context: GraphicsContext, size: CGSize) {
        for index in 0..<56 {
            let column: Int = (index * 157 + 19) % 379
            let rowSeed: Int = index * index * 13
            let row: Int = (rowSeed + 71 * index + 8) % 613
            let x: CGFloat = CGFloat(column) / 379 * size.width
            let y: CGFloat = CGFloat(row) / 613 * size.height
            let bright = index.isMultiple(of: 8)
            let diameter: CGFloat = bright ? 1.5 : 0.9
            let opacity: Double = bright ? 0.32 : 0.19
            let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(opacity)))
        }
    }

    private func drawPlanet(in context: GraphicsContext, size: CGSize) {
        let radius: CGFloat = max(size.width * 0.92, size.height * 0.55)
        let rect = CGRect(x: size.width / 2 - radius, y: size.height * 0.64,
                          width: 2 * radius, height: 2 * radius)
        let disc = Path(ellipseIn: rect)
        let surface = Color(red: 0.063, green: 0.15, blue: 0.22)
        let gradient = Gradient(colors: [surface, MWCockpit.deep])
        let start = CGPoint(x: rect.midX, y: rect.minY)
        let end = CGPoint(x: rect.midX, y: size.height * 1.17)
        context.fill(disc, with: .linearGradient(gradient, startPoint: start, endPoint: end))
        context.stroke(disc, with: .color(MWCockpit.tint.opacity(0.12)), lineWidth: 0.7)
    }
}

struct MWCockpitRail: View {
    var lower = false
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * w, y: lower ? h - y * h : y * h)
            }
            var rail = Path()
            rail.move(to: point(0, 0.14))
            let vertices: [(CGFloat, CGFloat)] = [(0.16, 0.14), (0.28, 0.92), (0.72, 0.92),
                                                  (0.84, 0.14), (1, 0.14)]
            for (x, y) in vertices {
                rail.addLine(to: point(x, y))
            }
            ctx.stroke(rail, with: .color(MWCockpit.tint.opacity(0.35)), lineWidth: 0.8)
            var light = Path()
            light.move(to: point(0.39, 0.92))
            light.addLine(to: point(0.61, 0.92))
            ctx.stroke(light, with: .color(MWCockpit.tint.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

struct MWCockpitHeader: View {
    var phase: Int
    var count: Int
    var onBack: (() -> Void)?

    var body: some View {
        ZStack {
            MWCockpitRail()
            VStack(spacing: 5) {
                Text("RELAX MODE").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(3)
                HStack(spacing: 5) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle().fill(MWCockpit.tint.opacity(i == phase ? 1 : 0.24))
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .foregroundStyle(MWCockpit.tint)
            .accessibilityHidden(true)
            if let onBack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("戻る")
                    Spacer()
                }
                .foregroundStyle(MWCockpit.tint)
            }
        }
        .frame(height: 50)
    }
}

struct MWExerciseHeading: View {
    let number: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 13) {
            Text(number)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(MWCockpit.tint)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 10).fill(MWCockpit.tint.opacity(0.055)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MWCockpit.tint.opacity(0.35)))
            Rectangle().fill(MWCockpit.tint.opacity(0.35)).frame(width: 1, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(MWCockpit.primary)
                Text(subtitle).font(.caption).foregroundStyle(MWCockpit.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MWHologramFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [MWCockpit.tint.opacity(0.06), .clear],
                                          center: .center, startRadius: 2, endRadius: 170))
            Circle().strokeBorder(MWCockpit.tint.opacity(0.15), lineWidth: 0.8)
            Circle().inset(by: 7)
                .stroke(MWCockpit.tint.opacity(0.16),
                        style: StrokeStyle(lineWidth: 0.8, dash: [1, 9]))
            content().padding(5)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct MWInstructionPanel: View {
    let instructions: String
    let duration: String
    let paused: Bool
    let togglePause: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("やり方").font(.caption.bold())
                .foregroundStyle(MWCockpit.deep)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(MWCockpit.tint))
            Text(instructions).font(.subheadline).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(MWCockpit.primary)
            Rectangle().fill(MWCockpit.tint.opacity(0.13)).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text("目安時間").font(.caption).foregroundStyle(MWCockpit.muted)
                Text(duration).font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: togglePause) {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13))
                        .frame(width: 44, height: 44)
                        .background(Circle().strokeBorder(MWCockpit.tint.opacity(0.25)).padding(5))
                }
                .accessibilityLabel(paused ? "アニメーションを再開" : "アニメーションを一時停止")
            }
            .foregroundStyle(MWCockpit.tint)
        }
        .padding(.horizontal, 18).padding(.top, 15).padding(.bottom, 7)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.08, green: 0.15, blue: 0.22).opacity(0.84)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MWCockpit.tint.opacity(0.26)))
    }
}
