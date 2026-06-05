//
//  MindWaveViewModel.swift
//  MindWaveGraphic
//

import Foundation
import Combine

/// HealthKit実データとデモデータを切り替えながら、スコア計算の入力値を管理する。
/// UIはこのViewModelのみを参照し、データ元を意識しない。
@MainActor
final class MindWaveViewModel: ObservableObject {

    // MARK: - Published（UIが参照する値）

    @Published var currentHeartRate: Double = 58
    @Published var averageHeartRate: Double = 65
    @Published var currentHRV: Double       = 52
    @Published var averageHRV: Double       = 45

    @Published var isUsingDemoData: Bool      = true
    @Published var dataSourceLabel: String    = "デモデータで表示中"
    @Published var authorizationStatusMessage = "HealthKit：未許可"

    // MARK: - Computed Score

    /// StressScoreCalculator を使って緊張不安定度を算出する
    var stressResult: StressScoreResult {
        StressScoreCalculator.calculate(
            currentHeartRate: currentHeartRate,
            averageHeartRate: averageHeartRate,
            currentHRV: currentHRV,
            averageHRV: averageHRV
        )
    }

    // MARK: - Private

    private let hkManager = HealthKitManager()

    // MARK: - Init

    init() {
        loadDemoScenario(index: 0)  // 起動時はデモデータ（平常時）を表示
    }

    // MARK: - Demo Data

    /// 開発確認用デモシナリオを読み込む。HealthKitデータが取れない場合のフォールバックにも使う。
    func loadDemoScenario(index: Int) {
        guard index < MindSampleScenario.allScenarios.count else { return }
        let s = MindSampleScenario.allScenarios[index]
        currentHeartRate = s.currentHeartRate
        averageHeartRate = s.averageHeartRate
        currentHRV       = s.currentHRV
        averageHRV       = s.averageHRV
        isUsingDemoData  = true
        dataSourceLabel  = "デモデータで表示中"
    }

    // MARK: - HealthKit Authorization

    /// HealthKitの読み取り許可をリクエストする。
    /// 許可が取れた場合はHealthKitデータの取得を試みる。
    func requestHealthKitAuthorization() async {
        guard HealthKitManager.isAvailable else {
            authorizationStatusMessage = "HealthKit：このデバイスでは利用不可"
            return
        }
        do {
            try await hkManager.requestAuthorization()
            authorizationStatusMessage = "HealthKit：許可済み"
            await fetchHealthKitData()
        } catch {
            authorizationStatusMessage = "HealthKit：リクエスト失敗"
        }
    }

    // MARK: - HealthKit Fetch

    /// HealthKitから心拍数・HRV（最新値と7日平均）を取得する。
    /// いずれかの値が取れない場合はデモデータにフォールバックする。
    func fetchHealthKitData() async {
        guard HealthKitManager.isAvailable else { return }

        async let hrTask    = hkManager.fetchLatestHeartRate()
        async let avgHRTask = hkManager.fetchAverageHeartRate(days: 7)
        async let hrvTask   = hkManager.fetchLatestHRV()
        async let avgHRVTask = hkManager.fetchAverageHRV(days: 7)

        let (hr, avgHR, hrv, avgHRV) = await (hrTask, avgHRTask, hrvTask, avgHRVTask)

        if let hr, let avgHR, let hrv, let avgHRV {
            currentHeartRate = hr
            averageHeartRate = avgHR
            currentHRV       = hrv
            averageHRV       = avgHRV
            isUsingDemoData  = false
            dataSourceLabel  = "HealthKitデータで表示中"
        } else {
            // Apple Watch未接続・データなしの場合はデモデータにフォールバック
            loadDemoScenario(index: 0)
        }
    }
}
