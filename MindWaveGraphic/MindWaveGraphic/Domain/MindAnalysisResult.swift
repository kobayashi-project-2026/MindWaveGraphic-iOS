import Foundation

// 生体データとGraphicInputの間に置く解析結果型。
// tensionScore / confidence は必ずclamp済みで格納される。
struct MindAnalysisResult: Equatable, Sendable {
    /// 緊張不安定度スコア 0〜100（clamp済み）
    let tensionScore: Double
    /// 推定の確からしさ 0〜1（clamp済み）
    let confidence: Double
    let state: MindState
    let timestamp: Date
}
