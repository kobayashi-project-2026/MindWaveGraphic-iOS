import Foundation

/// Each interval includes its start and excludes its end. The final interval wraps to zero.
struct MWCycle {
    let durations: [TimeInterval]
    let duration: TimeInterval

    init(_ durations: [TimeInterval]) {
        precondition(!durations.isEmpty && durations.allSatisfy { $0 > 0 && $0.isFinite })
        self.durations = durations
        self.duration = durations.reduce(0, +)
    }

    func position(at elapsed: TimeInterval) -> (index: Int, fraction: Double) {
        var cursor = max(0, elapsed).truncatingRemainder(dividingBy: duration)
        for (index, length) in durations.enumerated() {
            if cursor < length { return (index, cursor / length) }
            cursor -= length
        }
        return (0, 0)
    }
}

enum MWArrowDirection { case up, down }

enum MWShoulderPhase: Int, CaseIterable {
    case lift, release, rest

    var title: String {
        switch self {
        case .lift: return "肩をゆっくりすくめる"
        case .release: return "力を抜いて、肩を下ろす"
        case .rest: return "肩を休める"
        }
    }

    var direction: MWArrowDirection? {
        switch self {
        case .lift: return .up
        case .release: return .down
        case .rest: return nil
        }
    }
}

struct MWShoulderSample {
    static let cycle = MWCycle([3, 2.5, 2.5])
    let phase: MWShoulderPhase
    let lift: Double
    let arrowOpacity: Double

    init(elapsed: TimeInterval) {
        let position = Self.cycle.position(at: elapsed)
        let phase = MWShoulderPhase.allCases[position.index]
        self.phase = phase
        let t = position.fraction
        // Zero velocity at both ends of each movement, including the loop boundary.
        let eased = t * t * (3 - 2 * t)
        switch phase {
        case .lift: lift = eased
        case .release: lift = 1 - eased
        case .rest: lift = 0
        }
        arrowOpacity = phase == .rest ? 0 : min(1, min(t, 1 - t) * 8)
    }
}

/// Session time advances only while the screen is visible and the scene is active.
struct MWPlaybackClock {
    private var accumulated: TimeInterval = 0
    private var startedAt: TimeInterval?

    func elapsed(at now: TimeInterval) -> TimeInterval {
        accumulated + (startedAt.map { max(0, now - $0) } ?? 0)
    }

    mutating func setRunning(_ running: Bool, at now: TimeInterval) {
        if running {
            if startedAt == nil { startedAt = now }
        } else if startedAt != nil {
            accumulated = elapsed(at: now)
            startedAt = nil
        }
    }
}
