import SwiftUI

/// Geometry is expressed in a front-facing 240 × 252 coordinate system, x = 0 at the sternum.
/// Each cubic stores its two controls followed by its endpoint.
private struct MWCurve {
    let start: CGPoint
    let segments: [(CGPoint, CGPoint, CGPoint)]

    init(_ x: CGFloat, _ y: CGFloat, _ cubics: [[Int]]) {
        start = CGPoint(x: x, y: y)
        segments = cubics.map { s in
            precondition(s.count == 6)
            return (CGPoint(x: CGFloat(s[0]), y: CGFloat(s[1])), CGPoint(x: CGFloat(s[2]), y: CGFloat(s[3])),
                    CGPoint(x: CGFloat(s[4]), y: CGFloat(s[5])))
        }
    }

    func path(_ transform: (CGPoint) -> CGPoint, closed: Bool = false) -> Path {
        var path = Path()
        path.move(to: transform(start))
        for (first, second, end) in segments {
            path.addCurve(to: transform(end), control1: transform(first), control2: transform(second))
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// Matched landmarks keep fingertip and knuckle positions continuous while the hand closes.
    func morph(to other: MWCurve, fraction: CGFloat, project: (CGPoint) -> CGPoint) -> Path {
        precondition(segments.count == other.segments.count)
        func point(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let x = a.x + (b.x - a.x) * fraction
            let y = a.y + (b.y - a.y) * fraction
            return project(CGPoint(x: x, y: y))
        }
        var line = Path()
        line.move(to: point(start, other.start))
        for (relaxed, flexed) in zip(segments, other.segments) {
            let c1 = point(relaxed.0, flexed.0)
            let c2 = point(relaxed.1, flexed.1)
            line.addCurve(to: point(relaxed.2, flexed.2), control1: c1, control2: c2)
        }
        return line
    }
}

struct MWBodyPose {
    var shoulderLift: CGFloat = 0

    var neckTilt: CGFloat = 0
    var chestOpen: CGFloat = 0
    var armGrip: CGFloat = 0

    private func ramp(_ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    // The sternum lifts forward while the deltoids settle back. Project a small component
    // of depth into x, so the movement stays readable in a nearly frontal view.
    private func openChest(_ p: CGPoint) -> CGPoint {
        let x = abs(p.x), y = p.y
        let side: CGFloat = p.x < 0 ? -1 : 1
        let rib = ramp((y - 86) / 23) * (1 - ramp((y - 151) / 55))
        let arm = ramp((x - 51) / 23) * ramp((y - 90) / 22)
        let shoulder = ramp((x - 17) / 42) * ramp((y - 84) / 18) * (1 - ramp((y - 125) / 52))
        let center = 1 - ramp(x / 70)
        let forward: CGFloat = 8 * rib * center - 13 * shoulder - 7 * arm
        let width: CGFloat = rib * min(x, 55) * 0.11 + arm * (4 + 10 * ramp((y - 123) / 105))
        let dx: CGFloat = side * width + 0.24 * forward
        let dy: CGFloat = -6 * rib * center + 3.0 * shoulder - 1.8 * arm
        return CGPoint(x: p.x + dx * chestOpen, y: y + dy * chestOpen)
    }

    func armPoint(_ p: CGPoint) -> CGPoint {
        guard armGrip != 0 else { return p }
        let x = abs(p.x), y = p.y
        let side: CGFloat = p.x < 0 ? -1 : 1
        let segment = ramp((x - 55) / 13) * ramp((y - 152) / 35)
        let forearm = max(0, 1 - abs(y - 199) / 47)
        let wrist = ramp((y - 174) / 74)
        let axis: CGFloat = 73 + 0.16 * (y - 175)
        let bulge = max(-1, min(1, (x - axis) / 8)) * 2.2 * forearm
        let dx: CGFloat = (bulge - 7 * wrist) * segment
        return CGPoint(x: p.x + side * dx * armGrip, y: y - 5 * wrist * segment * armGrip)
    }

    func rotateHead(_ p: CGPoint) -> CGPoint {
        guard neckTilt != 0 else { return p }
        let y = p.y - 92
        let c = cos(neckTilt), s = sin(neckTilt)
        return CGPoint(x: p.x * c - y * s, y: 92 + p.x * s + y * c)
    }

    func deform(_ p: CGPoint) -> CGPoint {
        if chestOpen != 0 { return openChest(p) }
        if armGrip != 0 { return armPoint(p) }
        if neckTilt != 0 && p.y < 98 {
            let t: CGFloat = min(1, (98 - p.y) / 20)
            let blend: CGFloat = t * t * (3 - 2 * t)
            let head = rotateHead(p)
            return CGPoint(x: p.x + blend * (head.x - p.x), y: p.y + blend * (head.y - p.y))
        }
        // Collar, deltoid and upper-arm vertices share one smooth displacement field.
        let u = (abs(p.x) - 57) / 39
        let v = (p.y - 107) / 38
        let squaredDistance: CGFloat = u * u + v * v
        let weight = CGFloat(exp(-Double(squaredDistance)))
        let inward: CGFloat = p.x < 0 ? 1 : -1
        let displacement: CGFloat = shoulderLift * weight
        let lateral: CGFloat = inward * min(abs(p.x) / 22, 1) * 3
        return CGPoint(x: p.x + lateral * displacement, y: p.y - 20 * displacement)
    }
}

private enum MWAnatomy {
    // Head has a rounded crown, narrowing jaw and a short chin. All head curves use the same rigid transform.
    static let head = MWCurve(0, 15, [
        [15,15,24,26,24,42], [24,53,21,62,16,68], [11,73,6,78,0,78],
        [-6,78,-11,73,-16,68], [-21,62,-24,53,-24,42], [-24,26,-15,15,0,15]
    ])
    static let headMesh: [MWCurve] = [
        MWCurve(-22,31, [[-10,36,10,36,22,31]]),
        MWCurve(-24,45, [[-11,51,11,51,24,45]]),
        MWCurve(-20,60, [[-8,65,8,65,20,60]]),
        MWCurve(-6,16, [[-15,28,-17,57,-6,75]]),
        MWCurve(9,17, [[19,31,18,57,8,74]])
    ]

    // One continuous body from the jaw to each wrist; the relaxed waist has its own contour.
    static let body = MWCurve(-13,71, [
        [-13,76,-12,82,-18,87], [-27,94,-45,97,-58,100],
        [-69,102,-78,108,-81,123], [-84,138,-86,161,-89,183],
        [-91,200,-94,223,-94,248], [-94,248,-79,248,-77,248],
        [-74,225,-69,205,-65,188], [-61,175,-59,160,-57,147],
        [-55,161,-55,177,-52,193], [-50,209,-49,225,-50,248],
        [-17,249,17,249,50,248], [49,225,50,209,52,193],
        [55,177,55,161,57,147], [59,160,61,175,65,188],
        [69,205,74,225,77,248], [79,248,94,248,94,248],
        [94,223,91,200,89,183], [86,161,84,138,81,123],
        [78,108,69,102,58,100], [45,97,27,94,18,87],
        [12,82,13,76,13,71]
    ])
    // The clavicle, deltoid and lateral ribs bend independently on each side.
    static let sideMesh: [MWCurve] = [
        MWCurve(3,110, [[17,108,38,98,58,102]]),
        MWCurve(36,100, [[47,112,51,129,52,147],[54,172,41,203,39,242]]),
        MWCurve(66,102, [[56,115,55,134,57,147]]),
        MWCurve(78,114, [[74,121,65,126,58,125]]),
        MWCurve(84,143, [[76,151,66,154,58,151]]),
        MWCurve(88,171, [[81,179,72,182,64,181]]),
        MWCurve(79,124, [[73,155,68,182,76,212]]),
        MWCurve(12,77, [[12,87,9,94,6,100]])
    ]
    static let chestMesh: [MWCurve] = [
        MWCurve(-55,126, [[-37,134,-15,136,0,133],[15,136,37,134,55,126]]),
        MWCurve(-56,150, [[-35,157,-15,161,0,159],[15,161,35,157,56,150]]),
        MWCurve(-54,177, [[-23,186,23,186,54,177]]),
        MWCurve(-50,205, [[-19,214,19,214,50,205]]),
        MWCurve(0,111, [[-1,136,2,159,0,182],[0,198,0,221,0,242]])
    ]
    static let shoulder = MWCurve(18,87, [[27,94,45,97,58,100],[69,102,78,108,81,123]])
    static let neckEdge = MWCurve(13,71, [[13,76,12,82,18,87],[21,90,25,92,29,93]])
    static let forearm = MWCurve(88,183, [[91,202,94,229,94,248]])
    // Rib arcs for the local chest highlight; all use the same displacement as the body surface.
    static let pectoral = MWCurve(4,124, [[17,129,39,129,53,122]])
    static let forearmSeam = MWCurve(66,182, [[68,193,73,218,77,243]])

}

struct MWBodyWireframe: View {
    var pose: MWBodyPose
    var direction: MWArrowDirection?
    var arrowOpacity: Double
    var glow: Double
    var target: MWTarget = .shoulders
    var lateralCue: CGFloat = 0
    var showHands = false

    var body: some View {
        Canvas { context, size in
            render(context, size: size)
        }
        .mask(bottomFade)
        .accessibilityHidden(true)
    }

    private var bottomFade: LinearGradient {
        let stops: [Gradient.Stop] = [
            .init(color: .white, location: 0),
            .init(color: .white, location: showHands ? 0.95 : 0.75),
            .init(color: .clear, location: showHands ? 1 : 0.985)
        ]
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private func render(_ context: GraphicsContext, size: CGSize) {
        let height: CGFloat = showHands ? 310 : 252
        let scale: CGFloat = min(size.width / 240, size.height / height)
        guard scale > 0 else { return }
        var ctx = context
        let y: CGFloat = (size.height - height * scale) / 2
        ctx.translateBy(x: size.width / 2, y: y)
        ctx.scaleBy(x: scale, y: scale)
        if showHands {
            ctx.drawLayer { bodyLayer in
                drawUpperBody(in: bodyLayer)
                // Fade just the cropped waist. The hands keep their full contrast.
                var eraser = bodyLayer
                eraser.blendMode = .destinationOut
                let bounds = CGRect(x: -55, y: 208, width: 110, height: 44)
                let fade = Gradient(colors: [.clear, .black])
                eraser.fill(Path(bounds), with: .linearGradient(fade, startPoint: CGPoint(x: 0, y: 208),
                                                                endPoint: CGPoint(x: 0, y: 247)))
            }
        } else {
            drawUpperBody(in: ctx)
        }
        drawHead(in: ctx)
        if target == .neck { drawNeck(in: ctx) }
        if target == .chest { drawChest(in: ctx) }
        if showHands {
            let sides: [CGFloat] = [-1, 1]
            for side in sides {
                drawForearm(in: ctx, side: side)
                MWHandDrawing.draw(in: ctx, grip: pose.armGrip) { point in
                    pose.armPoint(CGPoint(x: side * point.x, y: point.y))
                }
            }
        }
    }

    private func drawUpperBody(in ctx: GraphicsContext) {
        drawTorso(in: ctx)
        drawShoulder(in: ctx, side: -1)
        drawShoulder(in: ctx, side: 1)
    }

    private func wire(_ path: Path, in context: GraphicsContext, alpha: Double, width: CGFloat) {
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        context.stroke(path, with: .color(MWCockpit.tint.opacity(alpha)), style: style)
    }

    private func drawTorso(in ctx: GraphicsContext) {
        let outline = MWAnatomy.body.path(pose.deform)
        let cyan = MWCockpit.tint
        let fill = Gradient(colors: [cyan.opacity(0.16), cyan.opacity(0.035), cyan.opacity(0.12)])
        let start = CGPoint(x: -85, y: 100)
        let end = CGPoint(x: 85, y: 137)
        ctx.fill(outline, with: .linearGradient(fill, startPoint: start, endPoint: end))
        wire(outline, in: ctx, alpha: 0.72, width: 0.95)
        for curve in MWAnatomy.chestMesh {
            wire(curve.path(pose.deform), in: ctx, alpha: 0.33, width: 0.72)
        }
    }

    private func drawShoulder(in ctx: GraphicsContext, side: CGFloat) {
        func projected(_ p: CGPoint) -> CGPoint {
            pose.deform(CGPoint(x: side * p.x, y: p.y))
        }
        for curve in MWAnatomy.sideMesh {
            wire(curve.path(projected), in: ctx, alpha: 0.43, width: 0.74)
        }
        guard target == .shoulders else { return }
        let cap = MWAnatomy.shoulder.path(projected)
        let haloOpacity: Double = 0.12 + 0.43 * glow
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.6))
            let style = StrokeStyle(lineWidth: 4, lineCap: .round)
            layer.stroke(cap, with: .color(MWCockpit.tint.opacity(haloOpacity)), style: style)
        }
        wire(cap, in: ctx, alpha: 0.46 + 0.50 * glow, width: 1.4)
        if let direction {
            let anchor = projected(CGPoint(x: 82, y: 109))
            let center = CGPoint(x: anchor.x + side * 15, y: anchor.y)
            let arrow = MWMotionArrow.path(center: center, length: 22, direction: direction)
            wire(arrow, in: ctx, alpha: arrowOpacity * 0.93, width: 1.8)
        }
    }

    private func drawHead(in ctx: GraphicsContext) {
        let head = MWAnatomy.head.path(pose.rotateHead, closed: true)
        let cyan = MWCockpit.tint
        let fill = Gradient(colors: [cyan.opacity(0.21), cyan.opacity(0.045), cyan.opacity(0.12)])
        let start = CGPoint(x: -24, y: 26)
        let end = CGPoint(x: 23, y: 57)
        ctx.fill(head, with: .linearGradient(fill, startPoint: start, endPoint: end))
        wire(head, in: ctx, alpha: 0.77, width: 0.95)
        for curve in MWAnatomy.headMesh {
            wire(curve.path(pose.rotateHead), in: ctx, alpha: 0.35, width: 0.72)
        }
    }

    private func drawNeck(in ctx: GraphicsContext) {
        if glow > 0 {
            // When the ear moves left, highlight the lengthening right side of the neck.
            let side: CGFloat = pose.neckTilt < 0 ? 1 : -1
            let edge = MWAnatomy.neckEdge.path({ point in
                pose.deform(CGPoint(x: point.x * side, y: point.y))
            })
            highlight(edge, in: ctx)
        }
        guard lateralCue != 0 else { return }
        // Place the arc beside the tilted head, even on the way back to centre.
        let side: CGFloat = pose.neckTilt == 0 ? lateralCue : (pose.neckTilt > 0 ? 1 : -1)
        let crown = pose.rotateHead(CGPoint(x: 0, y: 33))
        let inner = CGPoint(x: crown.x + side * 25, y: crown.y - 16)
        let outer = CGPoint(x: crown.x + side * 45, y: crown.y + 1)
        let bend = CGPoint(x: crown.x + side * 40, y: crown.y - 13)
        let outward = lateralCue == side
        let cue = MWGuideArrow.curve(from: outward ? inner : outer, via: bend,
                                     to: outward ? outer : inner)
        wire(cue, in: ctx, alpha: arrowOpacity, width: 1.6)
    }

    private func highlight(_ line: Path, in ctx: GraphicsContext) {
        let light = MWCockpit.tint.opacity(0.36 * glow)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 2))
            layer.stroke(line, with: .color(light), lineWidth: 4)
        }
        wire(line, in: ctx, alpha: 0.95 * glow, width: 1.35)
    }

    private func drawChest(in ctx: GraphicsContext) {
        let sides: [CGFloat] = [-1, 1]
        let shell = MWAnatomy.body.path(pose.deform)
        var surface = ctx
        surface.clip(to: shell)
        for side in sides {
            func projected(_ p: CGPoint) -> CGPoint {
                pose.deform(CGPoint(x: side * p.x, y: p.y))
            }
            let center = projected(CGPoint(x: 27, y: 125))
            let tint = MWCockpit.tint.opacity(0.13 * glow)
            let wash = Gradient(colors: [tint, .clear])
            surface.fill(shell, with: .radialGradient(wash, center: center, startRadius: 2, endRadius: 31))
            if glow > 0 {
                let arc = MWAnatomy.pectoral.path(projected)
                wire(arc, in: ctx, alpha: glow * 0.83, width: 1.15)
            }
            if lateralCue != 0 {
                let inside = projected(CGPoint(x: 30, y: 116))
                let bend = projected(CGPoint(x: 50, y: 120))
                let outside = projected(CGPoint(x: 69, y: 109))
                let outward = lateralCue > 0
                let arrow = MWGuideArrow.curve(from: outward ? inside : outside, via: bend,
                                               to: outward ? outside : inside)
                wire(arrow, in: ctx, alpha: arrowOpacity * 0.9, width: 1.6)
            }
        }
    }

    private func drawForearm(in ctx: GraphicsContext, side: CGFloat) {
        func point(_ p: CGPoint) -> CGPoint { pose.armPoint(CGPoint(x: side * p.x, y: p.y)) }
        let color = MWHandDrawing.color(grip: pose.armGrip)
        let outer = MWAnatomy.forearm.path(point)
        let inner = MWAnatomy.forearmSeam.path(point)
        let style = StrokeStyle(lineWidth: 1.25, lineCap: .round)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 2))
            layer.stroke(outer, with: .color(color.opacity(0.16 + 0.18 * glow)), lineWidth: 3.8)
        }
        ctx.stroke(outer, with: .color(color.opacity(0.75)), style: style)
        ctx.stroke(inner, with: .color(color.opacity(0.46)), lineWidth: 0.8)
    }
}

enum MWMotionArrow {
    static func path(center: CGPoint, length: CGFloat, direction: MWArrowDirection) -> Path {
        let sign: CGFloat = direction == .up ? -1 : 1
        let tip = CGPoint(x: center.x, y: center.y + sign * length / 2)
        var p = Path()
        p.move(to: CGPoint(x: center.x, y: center.y - sign * length / 2))
        p.addLine(to: tip)
        p.move(to: CGPoint(x: tip.x - 4.5, y: tip.y - sign * 5))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x + 4.5, y: tip.y - sign * 5))
        return p
    }
}

private enum MWGuideArrow {
    static func curve(from start: CGPoint, via control: CGPoint, to end: CGPoint) -> Path {
        let dx = end.x - control.x, dy = end.y - control.y
        let length = max(0.001, hypot(dx, dy))
        let ux = dx / length, uy = dy / length
        let base = CGPoint(x: end.x - ux * 5.5, y: end.y - uy * 5.5)
        var p = Path()
        p.move(to: start)
        p.addQuadCurve(to: end, control: control)
        p.move(to: CGPoint(x: base.x - uy * 3.2, y: base.y + ux * 3.2))
        p.addLine(to: end)
        p.addLine(to: CGPoint(x: base.x + uy * 3.2, y: base.y - ux * 3.2))
        return p
    }
}

// A paired contour keeps an identifiable thumb and four knuckles in both poses.
// The wrist stays attached at x=77...94, y=248. The HUD close-up reuses these exact curves.
private enum MWHandDrawing {
    static let opened = MWCurve(94,248, [
        [94,253,97,258,98,263], [99,268,102,273,101,275],
        [100,277,98,276,95,270], [96,275,99,281,97,282],
        [95,284,93,278,91,274], [92,280,94,286,92,287],
        [89,289,88,280,86,276], [86,281,87,285,85,285],
        [82,286,81,278,80,270], [78,266,77,264,76,263],
        [74,265,72,269,70,269], [67,269,70,263,71,259],
        [72,254,76,252,77,248]
    ])
    static let closed = MWCurve(94,248, [
        [95,251,98,254,98,258], [99,261,100,263,98,265],
        [97,266,96,266,95,265], [95,267,94,269,92,269],
        [91,270,90,269,89,268], [89,270,87,271,85,270],
        [84,270,83,269,82,268], [81,270,79,269,78,268],
        [76,267,75,264,75,261], [75,260,74,259,74,258],
        [73,258,73,260,72,260], [70,259,71,256,72,254],
        [73,252,76,250,77,248]
    ])
    static let openFolds: [MWCurve] = [
        MWCurve(75,262, [[78,261,80,260,81,257]]),
        MWCurve(81,266, [[85,265,91,264,95,261]]),
        MWCurve(80,253, [[82,253,86,254,88,255]])
    ]
    static let closedFolds: [MWCurve] = [
        MWCurve(73,257, [[77,254,81,256,86,259]]),
        MWCurve(77,262, [[81,261,87,261,95,260]]),
        MWCurve(78,253, [[82,253,85,254,87,255]])
    ]

    static func color(grip: CGFloat) -> Color {
        let t = Double(grip)
        return Color(red: 0.36 + 0.61 * t, green: 0.88 - 0.16 * t, blue: 0.94 - 0.53 * t)
    }

    static func draw(in ctx: GraphicsContext, grip: CGFloat, project: (CGPoint) -> CGPoint) {
        let outline = opened.morph(to: closed, fraction: grip, project: project)
        let tint = color(grip: grip)
        ctx.fill(outline, with: .color(tint.opacity(0.10 + 0.05 * Double(grip))))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.6))
            layer.stroke(outline, with: .color(tint.opacity(0.24)), lineWidth: 2.6)
        }
        let style = StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
        ctx.stroke(outline, with: .color(tint.opacity(0.86)), style: style)
        for (a, b) in zip(openFolds, closedFolds) {
            let fold = a.morph(to: b, fraction: grip, project: project)
            ctx.stroke(fold, with: .color(tint.opacity(0.52)), lineWidth: 0.7)
        }
    }
}

struct MWHandDetail: View {
    let grip: CGFloat

    var body: some View {
        Canvas { context, size in
            let scale: CGFloat = min(size.width / 47, size.height / 50)
            var ctx = context
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.scaleBy(x: scale, y: scale)
            MWHandDrawing.draw(in: ctx, grip: grip) { p in
                CGPoint(x: p.x - 85, y: p.y - 267)
            }
        }
        .accessibilityHidden(true)
    }
}

struct MWPhaseGauge: View {
    let seconds: Int
    let remaining: Double
    let grip: CGFloat

    var body: some View {
        ZStack {
            Circle().strokeBorder(MWCockpit.tint.opacity(0.14), lineWidth: 2)
            Circle().inset(by: 1).trim(from: 0, to: CGFloat(remaining))
                .stroke(MWHandDrawing.color(grip: grip), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(seconds)秒").font(.system(.caption, design: .monospaced))
                .monospacedDigit().foregroundStyle(MWCockpit.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("この動作の残り時間")
        .accessibilityValue("\(seconds)秒")
    }
}
