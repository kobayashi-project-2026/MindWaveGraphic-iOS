import SwiftUI

struct ChestStretchView: View {
    var onBack: (() -> Void)? = nil
    var previewTime: TimeInterval? = nil
    var body: some View { MWExerciseScreen(exercise: .chest, onBack: onBack, previewTime: previewTime) }
}

enum MWChestProgram {
    static let guide = MWGuide(
        title: "胸のストレッチ", subtitle: "肩を軽く後ろへ引き、胸の前を広げます。",
        instructions: "腕を体の横に下ろし、肩を少し後ろへ引きます。腰を反らさず、楽に呼吸しましょう。痛みや違和感がある場合は中止してください。",
        duration: "1周13秒")
    static let cycle = MWCycle([2, 3, 5, 3])

    static func frame(at time: TimeInterval, reduced: Bool) -> MWFrame {
        let beat = MWBeat(cycle, time: time)
        let amount: Double
        let title: String
        let direction: Double
        switch beat.index {
        case 0: amount = 0; title = "肩の力を抜く"; direction = 0
        case 1: amount = reduced ? 1 : beat.eased; title = "肩を後ろに引き、胸を開く"; direction = 1
        case 2: amount = 1; title = "胸を開いたまま呼吸する"; direction = 0
        default: amount = reduced ? 0 : 1 - beat.eased; title = "ゆっくり元の姿勢に戻す"; direction = -1
        }
        return MWFrame(step: beat.index, title: title, target: .chest, intensity: amount,
                       chestOpen: amount, arrowAlpha: reduced ? 1 : beat.cueOpacity, cue: direction)
    }
}

struct MWChestPreview: PreviewProvider {
    static var previews: some View {
        Group {
            ChestStretchView().previewDisplayName("胸・ライブ")
            ChestStretchView(previewTime: 6).previewDisplayName("胸を開いて保持")
        }
    }
}
