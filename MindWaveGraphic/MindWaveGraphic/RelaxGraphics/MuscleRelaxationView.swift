import SwiftUI

struct MuscleRelaxationView: View {
    var onBack: (() -> Void)? = nil
    var previewTime: TimeInterval? = nil
    var body: some View { MWExerciseScreen(exercise: .muscle, onBack: onBack, previewTime: previewTime) }
}

// Compatibility with callers of the earlier three-exercise demo.
typealias ProgressiveMuscleRelaxationView = MuscleRelaxationView

enum MWMuscleProgram {
    static let guide = MWGuide(
        title: "漸進的筋弛緩法", subtitle: "両手と前腕で、力を入れた感覚と抜いた感覚を比べます。",
        instructions: "両手は軽く握るだけで十分です。息を止めずに腕に少し力を入れ、手を開いてゆるめます。痛みや違和感がある場合は中止してください。",
        duration: "1周19秒")
    static let cycle = MWCycle([2, 5, 2, 10])

    static func frame(at time: TimeInterval, reduced: Bool) -> MWFrame {
        let beat = MWBeat(cycle, time: time)
        let amount: Double
        let title: String
        switch beat.index {
        case 0: amount = reduced ? 1 : beat.eased; title = "両手を軽く握り、腕に力を入れる"
        case 1: amount = 1; title = "軽く握ったまま、呼吸を続ける"
        case 2: amount = reduced ? 0 : 1 - beat.eased; title = "手を開き、腕の力を抜く"
        default: amount = 0; title = "手と腕をゆるめて休む"
        }
        return MWFrame(step: beat.index, title: title, target: .arms, intensity: amount,
                       grip: amount, seconds: beat.secondsLeft, remainingFraction: 1 - beat.fraction)
    }
}

struct MWMusclePreview: PreviewProvider {
    static var previews: some View {
        Group {
            MuscleRelaxationView().previewDisplayName("筋弛緩・ライブ")
            MuscleRelaxationView(previewTime: 4).previewDisplayName("両手を握る")
            MuscleRelaxationView(previewTime: 12).previewDisplayName("両手をゆるめる")
        }
    }
}
