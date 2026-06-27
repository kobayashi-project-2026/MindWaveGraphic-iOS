//
//  MindWaveBreathingViewModel.swift
//  MindWaveGraphic
//
//  既存フローとは独立した追加UI：3モード呼吸ガイドの ViewModel。
//  HealthKit・WatchConnectivity・GuideSessionRecord とは接続しない。
//

import SwiftUI
import Combine

@MainActor
final class MindWaveBreathingViewModel: ObservableObject {
    @Published var mode: MindWaveBreathingMode = .fourSevenEight
    @Published var phaseIndex: Int = 0
    @Published var elapsed: TimeInterval = 0
    @Published var isRunning: Bool = false
    @Published var cycles: Int = 0

    // Combineで管理：cancellable が nil のときタイマー未起動
    private var cancellable: AnyCancellable?
    private let updateInterval: TimeInterval = 0.05

    // MARK: - 計算プロパティ

    var currentPhase: MindWaveBreathPhase {
        mode.phases[phaseIndex]
    }

    var progress: Double {
        guard currentPhase.duration > 0 else { return 0 }
        return min(elapsed / currentPhase.duration, 1.0)
    }

    var remainingSeconds: Int {
        max(0, Int(ceil(currentPhase.duration - elapsed)))
    }

    // MARK: - 操作

    func start() {
        guard !isRunning else { return }  // 二重起動禁止
        isRunning = true
        print("[Breathing] session started")
        scheduleTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        // タイマーを確実に破棄する
        cancellable?.cancel()
        cancellable = nil
        print("[Breathing] session stopped")
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    // モード変更時は停止・初期化してからモードを切り替える
    func changeMode(_ newMode: MindWaveBreathingMode) {
        stop()
        mode = newMode
        phaseIndex = 0
        elapsed = 0
        cycles = 0
        print("[Breathing] mode changed: \(newMode.displayName)")
    }

    func reset() {
        stop()
        phaseIndex = 0
        elapsed = 0
        cycles = 0
    }

    // MARK: - タイマー

    private func scheduleTimer() {
        // Combineの Publisher を使い [weak self] でメモリリークを防ぐ
        cancellable = Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        elapsed += updateInterval

        guard elapsed >= currentPhase.duration else { return }

        let nextIndex = phaseIndex + 1
        if nextIndex >= mode.phases.count {
            // 全フェーズ完了 → サイクルカウントしてリセット
            cycles += 1
            phaseIndex = 0
            print("[Breathing] cycle completed: \(cycles)")
        } else {
            phaseIndex = nextIndex
        }
        elapsed = 0
        print("[Breathing] phase changed: \(currentPhase.label)")
    }
}
