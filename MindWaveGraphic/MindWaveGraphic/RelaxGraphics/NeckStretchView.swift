import SwiftUI

struct NeckStretchView: View {
    var onBack: (() -> Void)? = nil
    var previewTime: TimeInterval? = nil
    var body: some View { MWExerciseScreen(exercise: .neck, onBack: onBack, previewTime: previewTime) }
}

enum MWNeckProgram {
    static let guide = MWGuide(
        title: "首のストレッチ", subtitle: "肩を水平に保ち、首の横をゆっくり伸ばします。",
        instructions: "正面を向き、手で引かずに耳を肩へ近づけます。図は鏡の向きです。痛みや違和感がある場合は中止してください。",
        duration: "左右で22秒")
    static let cycle = MWCycle([3, 5, 3, 3, 5, 3])

    static func frame(at time: TimeInterval, reduced: Bool) -> MWFrame {
        let beat = MWBeat(cycle, time: time)
        let side: Double = beat.index < 3 ? 1 : -1
        let sideName = side > 0 ? "右" : "左"
        let amount: Double
        let title: String
        let direction: Double
        switch beat.index % 3 {
        case 0:
            amount = reduced ? 1 : beat.eased
            title = sideName + "へゆっくり傾ける"
            direction = side
        case 1:
            amount = 1
            title = sideName + "へ傾けたまま呼吸する"
            direction = 0
        default:
            amount = reduced ? 0 : 1 - beat.eased
            title = "ゆっくり正面に戻す"
            direction = -side
        }
        return MWFrame(step: beat.index, title: title, target: .neck, intensity: amount,
                       tilt: side * 0.30 * amount, arrowAlpha: reduced ? 1 : beat.cueOpacity, cue: direction)
    }
}

struct MWNeckPreview: PreviewProvider {
    static var previews: some View {
        Group {
            NeckStretchView().previewDisplayName("首・ライブ")
            NeckStretchView(previewTime: 4).previewDisplayName("右へ傾けて保持")
        }
    }
}
