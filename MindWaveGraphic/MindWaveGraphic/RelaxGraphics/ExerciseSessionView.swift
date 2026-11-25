import SwiftUI

/// Shared cockpit for the three additional routines; time advances only during active playback.
struct MWExerciseScreen: View {
    let exercise: MWExercise
    let onBack: (() -> Void)?
    let previewTime: TimeInterval?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = MWPlaybackClock()
    @State private var visible = false
    @State private var paused = false

    init(exercise: MWExercise, onBack: (() -> Void)? = nil, previewTime: TimeInterval? = nil) {
        self.exercise = exercise
        self.onBack = onBack
        self.previewTime = previewTime
    }

    private var running: Bool { visible && scenePhase == .active && !paused && previewTime == nil }

    private func syncClock() {
        clock.setRunning(running, at: ProcessInfo.processInfo.systemUptime)
    }

    var body: some View {
        ZStack {
            MWCockpitBackground()
            GeometryReader { geometry in timeline(size: geometry.size) }
        }
        .onAppear { visible = true; syncClock() }
        .onDisappear { visible = false; syncClock() }
        .onChange(of: scenePhase) { _ in syncClock() }
        .preferredColorScheme(.dark)
    }

    private func timeline(size: CGSize) -> some View {
        let interval: TimeInterval = reduceMotion ? 0.25 : 1.0 / 30.0
        let schedule: AnimationTimelineSchedule = .animation(minimumInterval: interval, paused: !running)
        return TimelineView(schedule) { _ in screen(currentFrame, size: size) }
    }

    private var currentFrame: MWFrame {
        let elapsed = previewTime ?? clock.elapsed(at: ProcessInfo.processInfo.systemUptime)
        return exercise.frame(at: elapsed, reduced: reduceMotion)
    }

    private func screen(_ frame: MWFrame, size: CGSize) -> some View {
        let guide = exercise.guide
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                MWCockpitHeader(phase: frame.step, count: exercise.steps, onBack: onBack)
                MWExerciseHeading(number: exercise.number, title: guide.title, subtitle: guide.subtitle)
                Spacer(minLength: 0)
                instrument(frame, size: size)
                Spacer(minLength: 0)
                MWInstructionPanel(instructions: guide.instructions, duration: guide.duration,
                                   paused: paused, togglePause: togglePlayback)
                MWCockpitRail(lower: true).frame(height: 18)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: size.height)
        }
    }

    private func togglePlayback() {
        paused.toggle()
        syncClock()
    }

    private func instrument(_ frame: MWFrame, size: CGSize) -> some View {
        let available: CGFloat = min(size.width - 72, size.height * 0.41)
        let diameter: CGFloat = max(140, min(350, available))
        return VStack(spacing: 12) {
            MWHologramFrame { MWProgramFigure(frame: frame) }
                .frame(width: diameter, height: diameter)
            if let seconds = frame.seconds {
                HStack(spacing: 12) {
                    MWHandDetail(grip: CGFloat(frame.grip))
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(MWCockpit.tint.opacity(0.035)))
                        .overlay(Circle().strokeBorder(MWCockpit.tint.opacity(0.20)))
                    phaseLabel(frame)
                    MWPhaseGauge(seconds: seconds, remaining: frame.remainingFraction, grip: CGFloat(frame.grip))
                        .frame(width: 44, height: 44)
                }
            } else {
                phaseLabel(frame)
            }
        }
    }

    private func phaseLabel(_ frame: MWFrame) -> some View {
        let counter = String(format: "%02d / %02d", frame.step + 1, exercise.steps)
        return VStack(spacing: 4) {
            Text(counter).font(.system(.caption2, design: .monospaced)).foregroundStyle(MWCockpit.tint)
            Text(frame.title).font(.subheadline.weight(.medium)).foregroundStyle(MWCockpit.primary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if paused { Text("一時停止中").font(.caption2).foregroundStyle(MWCockpit.muted) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct MWProgramFigure: View {
    let frame: MWFrame
    var body: some View {
        let pose = MWBodyPose(shoulderLift: CGFloat(frame.lift), neckTilt: CGFloat(frame.tilt),
                              chestOpen: CGFloat(frame.chestOpen), armGrip: CGFloat(frame.grip))
        MWBodyWireframe(pose: pose, direction: frame.arrow, arrowOpacity: frame.arrowAlpha,
                        glow: frame.intensity, target: frame.target, lateralCue: CGFloat(frame.cue),
                        showHands: frame.target == .arms)
    }
}
