// MeasurementContext.swift
// Domain
//
// 測定前の場面・身体状態を表すモデル。
// スコア補正の入力として StressScoreCalculator へ渡す。
// 医療的断定表現は一切含まない。

import Foundation

// MARK: - MeasurementScene (測定場面)

/// 測定時の場面カテゴリ。単一選択。
enum ContextScene: String, CaseIterable, Identifiable, Codable {
    case calm      = "calm"
    case interview = "interview"
    case sports    = "sports"
    case important = "important"
    case work      = "work"
    case other     = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm:      return "安静"
        case .interview: return "面接 / 発表前"
        case .sports:    return "試合 / 大会前"
        case .important: return "大切な予定前"
        case .work:      return "作業 / 集中"
        case .other:     return "その他"
        }
    }

    var icon: String {
        switch self {
        case .calm:      return "leaf"
        case .interview: return "person.2"
        case .sports:    return "figure.run"
        case .important: return "heart"
        case .work:      return "laptopcomputer"
        case .other:     return "ellipsis.circle"
        }
    }

    // スコア補正係数。正 = スコアを上げる方向。負 = スコアを下げる（心拍上昇を緩和）。
    // 値はすべて推計値であり、医学的根拠ではない。
    var scoreOffset: Double {
        switch self {
        case .calm:      return 0.0     // 補正なし
        case .interview: return  2.5    // 緊張感をわずかに強調
        case .sports:    return  1.5    // 軽い強調
        case .important: return  2.0
        case .work:      return  0.0
        case .other:     return  0.0
        }
    }
}

// MARK: - BodyCondition (身体状態)

/// 測定時の身体状態フラグ。複数選択可。
enum BodyCondition: String, CaseIterable, Identifiable, Codable {
    case running    = "running"
    case stairs     = "stairs"
    case smoking    = "smoking"
    case caffeine   = "caffeine"
    case sleepLack  = "sleep_lack"
    case afterMeal  = "after_meal"
    case none       = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .running:   return "走ってきた"
        case .stairs:    return "階段 / 移動直後"
        case .smoking:   return "喫煙後"
        case .caffeine:  return "カフェイン摂取後"
        case .sleepLack: return "睡眠不足"
        case .afterMeal: return "食後"
        case .none:      return "特になし"
        }
    }

    var icon: String {
        switch self {
        case .running:   return "figure.run"
        case .stairs:    return "arrow.up.right"
        case .smoking:   return "smoke"
        case .caffeine:  return "cup.and.saucer"
        case .sleepLack: return "moon.zzz"
        case .afterMeal: return "fork.knife"
        case .none:      return "checkmark.circle"
        }
    }

    // 心拍上昇を「緊張」として過剰解釈しないための補正（負値 = スコアを下げる）。
    // 身体的な心拍上昇と精神的緊張を分けることが目的。推計値、医療診断ではない。
    var hrCorrectionOffset: Double {
        switch self {
        case .running:   return -14.0   // 運動後の心拍上昇はストレス寄与を低く見積もる
        case .stairs:    return  -9.0   // 移動直後も同様
        case .smoking:   return  -7.0   // カフェインと同傾向
        case .caffeine:  return  -7.0
        case .sleepLack: return  -3.0   // 疲労による微補正（下げすぎない）
        case .afterMeal: return  -2.0
        case .none:      return   0.0
        }
    }
}

// MARK: - MeasurementContext

/// 測定コンテキスト全体。AppFlowStateが保持し、ScoreCalculatorへ渡す。
struct MeasurementContext: Equatable, Codable {
    var scene:      ContextScene          = .calm
    var conditions: Set<BodyCondition>    = [.none]

    // デフォルト（選択なし）
    static let `default` = MeasurementContext()

    // 全補正値の合計。各身体状態の hrCorrectionOffset + 場面の scoreOffset
    var totalScoreOffset: Double {
        let bodyOffset = conditions
            .filter { $0 != .none }
            .map    { $0.hrCorrectionOffset }
            .reduce(0, +)
        return bodyOffset + scene.scoreOffset
    }

    var isDefault: Bool {
        scene == .calm && (conditions == [.none] || conditions.isEmpty)
    }

    var summaryLabel: String {
        if isDefault { return "— " }
        var parts: [String] = [scene.displayName]
        let extras = conditions.filter { $0 != .none }.map { $0.displayName }
        if !extras.isEmpty { parts.append(contentsOf: extras) }
        return parts.joined(separator: " · ")
    }
}
