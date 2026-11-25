import SwiftUI

struct ShoulderStretchView: View {
    // Pass a dismissal action when the host uses a custom cockpit navigation bar.
    var onBack: (() -> Void)? = nil
    var previewTime: TimeInterval? = nil

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = MWPlaybackClock()
    @State private var visible = false
    @State private var paused = false

    // An explicit initializer also exposes the no-argument entry point to existing callers.
    init(onBack: (() -> Void)? = nil, previewTime: TimeInterval? = nil) {
        self.onBack = onBack
        self.previewTime = previewTime
    }

    private var running: Bool {
        visible && scenePhase == .active && !paused && previewTime == nil
    }

    private func syncClock() {
        clock.setRunning(running, at: ProcessInfo.processInfo.systemUptime)
    }

    var body: some View {
        ZStack {
            MWCockpitBackground()
            GeometryReader { geometry in
                timeline(size: geometry.size)
            }
        }
        .onAppear { visible = true; syncClock() }
        .onDisappear { visible = false; syncClock() }
        .onChange(of: scenePhase) { _ in syncClock() }
        .preferredColorScheme(.dark)
    }

    private func timeline(size: CGSize) -> some View {
        let interval: TimeInterval = reduceMotion ? 0.25 : 1.0 / 30.0
        let schedule: AnimationTimelineSchedule = .animation(minimumInterval: interval, paused: !running)
        return TimelineView(schedule) { _ in
            screen(sample: currentSample, size: size)
        }
    }

    private var currentSample: MWShoulderSample {
        let elapsed = previewTime ?? clock.elapsed(at: ProcessInfo.processInfo.systemUptime)
        return MWShoulderSample(elapsed: elapsed)
    }

    private func screen(sample: MWShoulderSample, size: CGSize) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                MWCockpitHeader(phase: sample.phase.rawValue,
                                count: MWShoulderPhase.allCases.count, onBack: onBack)
                MWExerciseHeading(number: "01", title: "肩のストレッチ",
                                  subtitle: "肩まわりのこわばりをほぐし、リラックスしましょう。")
                Spacer(minLength: 0)
                instrument(sample, size: size)
                Spacer(minLength: 0)
                instructionPanel
                MWCockpitRail(lower: true).frame(height: 18)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: size.height)
        }
    }

    private var instructionPanel: some View {
        MWInstructionPanel(
            instructions: "肩をゆっくりすくめて、\nストンと力を抜いて下ろします。\nこれを数回繰り返しましょう。",
            duration: "約1〜2分", paused: paused, togglePause: togglePause
        )
    }

    private func togglePause() {
        paused.toggle()
        syncClock()
    }

    private func instrument(_ sample: MWShoulderSample, size: CGSize) -> some View {
        let available: CGFloat = min(size.width - 72, size.height * 0.41)
        let diameter: CGFloat = max(140, min(350, available))
        // Reduce Motion retains Japanese instructions and direction, with one still pose per step.
        let lift: Double = reduceMotion ? (sample.phase == .lift ? 0.82 : 0.0) : sample.lift
        return VStack(spacing: 12) {
            MWHologramFrame {
                MWBodyWireframe(pose: MWBodyPose(shoulderLift: CGFloat(lift)),
                                direction: sample.phase.direction,
                                arrowOpacity: reduceMotion ? 1 : sample.arrowOpacity,
                                glow: lift)
            }
            .frame(width: diameter, height: diameter)
            phaseLabel(sample.phase)
        }
    }

    private func phaseLabel(_ phase: MWShoulderPhase) -> some View {
        let counter = String(format: "%02d / %02d", phase.rawValue + 1, MWShoulderPhase.allCases.count)
        return HStack(spacing: 9) {
            Text(counter)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(MWCockpit.tint)
            Text(phase.title).font(.subheadline.weight(.medium))
                .foregroundStyle(MWCockpit.primary)
            if paused {
                Text("一時停止中").font(.caption2).foregroundStyle(MWCockpit.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#Preview {
    ShoulderStretchView()
}
