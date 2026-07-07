import Foundation

// グラフィックチームと共有する3状態。
// 表示名・閾値はここだけで管理する。
enum MindState: String, CaseIterable, Equatable, Sendable {
    case underAroused
    case optimalTension
    case overTense

    // UI暫定閾値。研究確定後にここだけ変更する。
    // 0〜underArousedMax  : underAroused
    // underArousedMax+1〜optimalTensionMax : optimalTension
    // optimalTensionMax+1〜100 : overTense
    static let underArousedMax: Double = 32
    static let optimalTensionMax: Double = 69

    static func from(score: Double) -> MindState {
        switch score {
        case ...underArousedMax:   return .underAroused
        case ...optimalTensionMax: return .optimalTension
        default:                   return .overTense
        }
    }

    var displayName: String {
        switch self {
        case .underAroused:   return "CALM"
        case .optimalTension: return "READY"
        case .overTense:      return "ALERT"
        }
    }

    var displayNameJP: String {
        switch self {
        case .underAroused:   return "落ち着き"
        case .optimalTension: return "集中中間域"
        case .overTense:      return "高緊張"
        }
    }
}
