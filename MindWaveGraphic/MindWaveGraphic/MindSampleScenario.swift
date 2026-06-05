//
//  MindSampleScenario.swift
//  MindWaveGraphic
//

import Foundation

/// HealthKit連携前の動作確認用ダミーシナリオ
struct MindSampleScenario: Identifiable {
    let id = UUID()
    let name: String
    let currentHeartRate: Double   // bpm
    let averageHeartRate: Double   // bpm（個人の平常時平均）
    let currentHRV: Double         // ms（SDNN）
    let averageHRV: Double         // ms（個人の平常時平均）
    let description: String

    // 期待スコア:
    //   平常時  → ≈ 37（落ち着き）
    //   軽い緊張 → ≈ 63（軽い緊張）
    //   強い緊張 → ≈ 95（強い緊張）
    static let allScenarios: [MindSampleScenario] = [
        MindSampleScenario(
            name: "平常時",
            currentHeartRate: 58,
            averageHeartRate: 65,
            currentHRV: 52,
            averageHRV: 45,
            description: "安静・リラックス状態。心拍が平均より低く、HRVが平均より高い。"
        ),
        MindSampleScenario(
            name: "軽い緊張",
            currentHeartRate: 72,
            averageHeartRate: 65,
            currentHRV: 38,
            averageHRV: 45,
            description: "軽度のストレス状態。心拍がやや上昇し、HRVがやや低下している。"
        ),
        MindSampleScenario(
            name: "強い緊張",
            currentHeartRate: 90,
            averageHeartRate: 65,
            currentHRV: 22,
            averageHRV: 45,
            description: "高ストレス状態。発表直前・試験直前などを想定。心拍が大幅に上昇し、HRVが大幅に低下。"
        )
    ]
}
