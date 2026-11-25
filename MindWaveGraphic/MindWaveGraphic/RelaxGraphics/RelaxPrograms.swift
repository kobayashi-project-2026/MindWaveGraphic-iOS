import Foundation

enum MWTarget { case shoulders, neck, chest, arms }

/// One sample drives geometry, light, direction and remaining time. Screen right is the user's right.
struct MWFrame {
    let step: Int
    let title: String
    let target: MWTarget
    var intensity: Double = 0
    var lift: Double = 0
    var tilt: Double = 0
    var chestOpen: Double = 0
    var grip: Double = 0
    var arrow: MWArrowDirection? = nil
    var arrowAlpha: Double = 0
    var cue: Double = 0
    var seconds: Int? = nil
    var remainingFraction: Double = 1
}

struct MWGuide {
    let title: String
    let subtitle: String
    let instructions: String
    let duration: String
}

/// MWCycle supplies the exact same interval to the drawing, caption and gauge.
struct MWBeat {
    let index: Int
    let fraction: Double
    let secondsLeft: Int

    init(_ cycle: MWCycle, time: TimeInterval) {
        let position = cycle.position(at: time)
        index = position.index
        fraction = position.fraction
        let remaining = cycle.durations[position.index] * (1 - position.fraction)
        secondsLeft = max(1, Int(ceil(remaining)))
    }

    var eased: Double { fraction * fraction * (3 - 2 * fraction) }
    var cueOpacity: Double { min(1, 8 * min(fraction, 1 - fraction)) }
}

enum MWExercise: Int, CaseIterable, Identifiable {
    case shoulder = 1, neck, chest, muscle
    var id: Int { rawValue }
    var number: String { String(format: "%02d", rawValue) }

    var guide: MWGuide {
        switch self {
        case .shoulder:
            return MWGuide(title: "肩のストレッチ", subtitle: "肩まわりのこわばりをほぐし、リラックスしましょう。",
                           instructions: "肩をゆっくりすくめて、ストンと力を抜いて下ろします。",
                           duration: "約1〜2分")
        case .neck: return MWNeckProgram.guide
        case .chest: return MWChestProgram.guide
        case .muscle: return MWMuscleProgram.guide
        }
    }

    var steps: Int {
        switch self {
        case .shoulder: return MWShoulderPhase.allCases.count
        case .neck: return MWNeckProgram.cycle.durations.count
        case .chest: return MWChestProgram.cycle.durations.count
        case .muscle: return MWMuscleProgram.cycle.durations.count
        }
    }

    func frame(at time: TimeInterval, reduced: Bool) -> MWFrame {
        switch self {
        case .shoulder:
            // Menu thumbnail only. The running shoulder screen uses its original clock and layout.
            let s = MWShoulderSample(elapsed: time)
            return MWFrame(step: s.phase.rawValue, title: s.phase.title, target: .shoulders,
                           intensity: s.lift, lift: s.lift, arrow: s.phase.direction, arrowAlpha: s.arrowOpacity)
        case .neck: return MWNeckProgram.frame(at: time, reduced: reduced)
        case .chest: return MWChestProgram.frame(at: time, reduced: reduced)
        case .muscle: return MWMuscleProgram.frame(at: time, reduced: reduced)
        }
    }
}
