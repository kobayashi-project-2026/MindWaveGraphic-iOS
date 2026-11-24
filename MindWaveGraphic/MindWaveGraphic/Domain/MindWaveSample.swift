import Foundation

// データソースを区別するenum。1か所で管理する。
nonisolated enum MindDataSource: String, Equatable, Sendable {
    case mock
    case watchLive
    case healthKit
    case unavailable
}

// Watch / HealthKit / Mock の生体データを共通化する型。
// HealthKitオブジェクト・WCSessionへの参照を持たない。
nonisolated struct MindWaveSample: Equatable, Sendable {
    let heartRate: Double?
    let hrv: Double?
    // Mockモードなどで計算済みスコアを直接渡す場合に使う。
    // nil のときは StressScoreCalculator で算出する。
    let contextScore: Double?
    let source: MindDataSource
    let timestamp: Date
}
