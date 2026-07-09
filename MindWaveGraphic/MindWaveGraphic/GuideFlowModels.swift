//
//  GuideFlowModels.swift
//  MindWaveGraphic
//
//  ガイドフローで使用する型定義とデータモデル。
//  参考コードから「シーン選択→ガイド→再測定→結果→保存」という遷移の考え方を採用し、
//  現在の実データパイプラインと既存のSwiftUIコンポーネントへ合わせて再設計。
//
//  重要：
//  - ダミーBPMや架空の改善結果は使用しない
//  - HRVは毎回更新されるとは限らないため必須条件にしない
//  - 保存はユーザーが選択したときだけ行う
//  - 実データとMockデータを区別する
//  - ログイン遷移は未実装（参考コードの認証ロジックは採用しない）
//

import Foundation
import SwiftUI
import Combine

// MARK: - Constants

/// ガイドフローの定数。1か所で管理することで変更を容易にする。
enum GuideFlowConstants {
    /// 再測定を完了とみなす最低Watch心拍受信件数
    static let minWatchSamplesForRemeasurement = 3
    /// 再測定の最大待機時間（秒）。サンプルが不足しても強制完了する。
    static let maxRemeasurementSeconds = 30
}

// MARK: - MeasurementScene

/// ガイドを行うシーンの選択肢。スコア計算式には影響しない。
/// 参考コードの文字列ベース管理を型安全な enum に置き換えた。
enum MeasurementScene: String, CaseIterable, Identifiable {
    case interview = "interview"
    case study     = "study"
    case sports    = "sports"
    case social    = "social"
    case daily     = "daily"
    case other     = "other"
    // フェーズ4で追加。保存データとの互換性：GuideHistoryStoreはメモリ内保存のため影響なし。
    case meeting   = "meeting"   // 重要な会議
    case speech    = "speech"    // スピーチ

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .interview: return "面接・プレゼン前"
        case .study:     return "試験・勉強中"
        case .sports:    return "試合・競技前"
        case .social:    return "デート・対人場面"
        case .daily:     return "日常"
        case .other:     return "その他"
        case .meeting:   return "重要な会議"
        case .speech:    return "スピーチ"
        }
    }

    var icon: String {
        switch self {
        case .interview: return "person.2.fill"
        case .study:     return "book.fill"
        case .sports:    return "figure.run"
        case .social:    return "heart.fill"
        case .daily:     return "house.fill"
        case .other:     return "ellipsis.circle.fill"
        case .meeting:   return "calendar.badge.clock"
        case .speech:    return "mic.fill"
        }
    }

    /// シーンごとのおすすめガイド（ユーザーは任意に変更できる）
    var recommendedExercise: GuideExercise {
        switch self {
        case .interview, .speech: return .breathing478
        case .sports:             return .box
        case .social, .meeting:   return .box
        case .study:              return .breathing214
        case .daily, .other:      return .breathing478
        }
    }
}

// MARK: - RegulationFlowStep

/// ガイドフローの現在段階。Int ベースの状態管理を避けて型安全にする。
/// 参考コードの currentStep: Int を置き換えた。
enum RegulationFlowStep: Equatable {
    case sceneSelection
    case exerciseSelection
    case session
    case remeasurement
    case result
}

// MARK: - GuideSnapshot

/// ガイド前後の実測値スナップショット。
/// 架空の値は使用しない。HRV未取得は nil として保持する。
/// isMockData = true のときはMockモード中の計測であることを示す。
struct GuideSnapshot: Equatable {
    /// スナップショットを取得した時刻
    let timestamp: Date
    /// GraphicInput.score (0-100)
    let score: Double
    /// GraphicInput.confidence (0-1)
    let confidence: Double
    /// GraphicInput.state
    let state: MindState
    /// 最新Watch心拍数（未受信の場合 nil）
    let heartRate: Double?
    /// 最新HRV SDNN ms（未取得の場合 nil）
    let hrv: Double?
    /// MindWaveViewModelのMockモードON中だったか
    let isMockData: Bool
    /// 心拍サンプルの記録時刻（診断用）
    let heartRateSampleDate: Date?
    /// HRVサンプルの記録時刻（診断用）
    let hrvSampleDate: Date?
}

// MARK: - GuideSessionRecord

/// 履歴に保存される1ガイドセッションの記録。
/// 実施日時は Date() を使用し、固定日時は使用しない。
struct GuideSessionRecord: Identifiable, Equatable {
    let id: UUID
    /// セッション開始時刻
    let startedAt: Date
    /// 選択したシーン
    let scene: MeasurementScene
    /// 実施したガイド
    let exercise: GuideExercise
    /// ガイド時間（秒）
    let durationSeconds: Int
    /// ガイド前の実測データ
    let before: GuideSnapshot
    /// ガイド後の実測データ（再測定を中断した場合は nil）
    let after: GuideSnapshot?
    /// 再測定中にHRV Observerで新規サンプルを受信したか
    let hrvUpdated: Bool
    /// ユーザーが入力した感情メモ（任意・空の場合は nil）
    let emotionMemo: String?

    /// 既存呼び出し元との後方互換を保つカスタムinit。
    /// emotionMemo はデフォルト nil なので、フェーズ4までの保存コードは変更不要。
    init(id: UUID, startedAt: Date, scene: MeasurementScene,
         exercise: GuideExercise, durationSeconds: Int,
         before: GuideSnapshot, after: GuideSnapshot?,
         hrvUpdated: Bool, emotionMemo: String? = nil) {
        self.id             = id
        self.startedAt      = startedAt
        self.scene          = scene
        self.exercise       = exercise
        self.durationSeconds = durationSeconds
        self.before         = before
        self.after          = after
        self.hrvUpdated     = hrvUpdated
        self.emotionMemo    = emotionMemo
    }
}

// MARK: - GuideHistoryStore

/// ガイドセッション履歴のメモリ内ストア。
/// 現時点では永続化未実装（メモリ内のみ）。
/// UserDefaults / SwiftDataへの移行は次フェーズで対応する。
/// ContentViewでEnvironmentObjectとして注入し、GuideFlowViewとHistoryViewが共有する。
final class GuideHistoryStore: ObservableObject {
    @Published private(set) var records: [GuideSessionRecord] = []

    /// セッション記録を先頭へ追加する。
    func add(_ record: GuideSessionRecord) {
        records.insert(record, at: 0)
        MindWaveDebugLogger.log(.flow, "record saved id=\(record.id.uuidString.prefix(8)) scene=\(record.scene.rawValue)")
    }
}
