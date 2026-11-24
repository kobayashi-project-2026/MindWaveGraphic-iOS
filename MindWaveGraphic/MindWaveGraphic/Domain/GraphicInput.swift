import Foundation

// グラフィックチームへ渡す唯一の入力型。
// HealthKit / WatchConnectivity / ViewModel への参照を一切持たない。
nonisolated struct GraphicInput: Equatable, Sendable {
    /// 緊張不安定度スコア 0〜100
    let score: Double
    /// 推定の確からしさ 0〜1
    let confidence: Double
    let state: MindState

    static let neutral = GraphicInput(score: 50, confidence: 0, state: .optimalTension)
}
