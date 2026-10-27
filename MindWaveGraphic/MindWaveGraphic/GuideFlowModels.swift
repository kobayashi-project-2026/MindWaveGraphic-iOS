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
    let startedAt: Date
    let scene: MeasurementScene
    let exercise: GuideExercise
    let durationSeconds: Int
    let before: GuideSnapshot
    let after: GuideSnapshot?
    let hrvUpdated: Bool
    let emotionMemo: String?
    // AI学習用フィールド（optional — 既存データとの互換性を保つ）
    let selfReportBefore:       SelfReportLevel?
    let selfReportAfter:        SelfReportLevel?
    let aiInsightTitle:         String?
    let aiInsightSummary:       String?
    let aiInsightRecommendation: String?
    let localAIVersion:         String?

    init(id: UUID, startedAt: Date, scene: MeasurementScene,
         exercise: GuideExercise, durationSeconds: Int,
         before: GuideSnapshot, after: GuideSnapshot?,
         hrvUpdated: Bool, emotionMemo: String? = nil,
         selfReportBefore: SelfReportLevel? = nil,
         selfReportAfter: SelfReportLevel? = nil,
         aiInsightTitle: String? = nil,
         aiInsightSummary: String? = nil,
         aiInsightRecommendation: String? = nil,
         localAIVersion: String? = nil) {
        self.id                     = id
        self.startedAt              = startedAt
        self.scene                  = scene
        self.exercise               = exercise
        self.durationSeconds        = durationSeconds
        self.before                 = before
        self.after                  = after
        self.hrvUpdated             = hrvUpdated
        self.emotionMemo            = emotionMemo
        self.selfReportBefore       = selfReportBefore
        self.selfReportAfter        = selfReportAfter
        self.aiInsightTitle         = aiInsightTitle
        self.aiInsightSummary       = aiInsightSummary
        self.aiInsightRecommendation = aiInsightRecommendation
        self.localAIVersion         = localAIVersion
    }
}

// MARK: - GuideHistoryStore

/// ガイドセッション履歴ストア。UserDefaultsでローカル永続化。
final class GuideHistoryStore: ObservableObject {
    @Published private(set) var records: [GuideSessionRecord] = []

    private let defaultsKey = "mindwave.guideHistory.v2"

    init() { load() }

    func add(_ record: GuideSessionRecord) {
        records.insert(record, at: 0)
        save()
        MindWaveDebugLogger.log(.flow, "record saved id=\(record.id.uuidString.prefix(8)) scene=\(record.scene.rawValue)")
    }

    /// 既存記録の感想メモだけを更新する（共通メニュー「フィードバック」から使用）。
    /// 計測値・AIインサイト等の他フィールドは変更しない。空文字は「メモなし」として保存する。
    @discardableResult
    func updateEmotionMemo(id: UUID, memo: String) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            MindWaveDebugLogger.log(.error, "[History] memo update target not found id=\(id.uuidString.prefix(8))")
            return false
        }
        let r = records[index]
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        records[index] = GuideSessionRecord(
            id: r.id, startedAt: r.startedAt, scene: r.scene, exercise: r.exercise,
            durationSeconds: r.durationSeconds, before: r.before, after: r.after,
            hrvUpdated: r.hrvUpdated,
            emotionMemo: trimmed.isEmpty ? nil : String(trimmed.prefix(200)),
            selfReportBefore: r.selfReportBefore, selfReportAfter: r.selfReportAfter,
            aiInsightTitle: r.aiInsightTitle, aiInsightSummary: r.aiInsightSummary,
            aiInsightRecommendation: r.aiInsightRecommendation, localAIVersion: r.localAIVersion
        )
        save()
        MindWaveDebugLogger.log(.flow, "record memo updated id=\(id.uuidString.prefix(8)) hasMemo=\(!trimmed.isEmpty)")
        return true
    }

    // MARK: Persistence (Codable-free — stores raw values as dicts)

    private func save() {
        let dicts = records.map { r -> [String: Any] in
            var d: [String: Any] = [
                "id":              r.id.uuidString,
                "startedAt":       r.startedAt.timeIntervalSince1970,
                "scene":           r.scene.rawValue,
                "exercise":        r.exercise.rawValue,
                "durationSeconds": r.durationSeconds,
                "hrvUpdated":      r.hrvUpdated,
                "before":          encodeSnapshot(r.before)
            ]
            if let after = r.after        { d["after"]        = encodeSnapshot(after) }
            if let m = r.emotionMemo      { d["emotionMemo"]  = m }
            if let v = r.selfReportBefore { d["srBefore"]     = v.rawValue }
            if let v = r.selfReportAfter  { d["srAfter"]      = v.rawValue }
            if let v = r.aiInsightTitle   { d["aiTitle"]      = v }
            if let v = r.aiInsightSummary { d["aiSummary"]    = v }
            if let v = r.aiInsightRecommendation { d["aiRec"] = v }
            if let v = r.localAIVersion   { d["aiVersion"]    = v }
            return d
        }
        UserDefaults.standard.set(dicts, forKey: defaultsKey)
    }

    private func load() {
        guard let dicts = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: Any]] else { return }
        records = dicts.compactMap { d -> GuideSessionRecord? in
            guard
                let idStr   = d["id"]              as? String,
                let id      = UUID(uuidString: idStr),
                let ts      = d["startedAt"]        as? Double,
                let scRaw   = d["scene"]            as? String,
                let scene   = MeasurementScene(rawValue: scRaw),
                let exRaw   = d["exercise"]         as? String,
                let exercise = GuideExercise(rawValue: exRaw),
                let dur     = d["durationSeconds"]  as? Int,
                let hrv     = d["hrvUpdated"]       as? Bool,
                let bDict   = d["before"]           as? [String: Any],
                let before  = decodeSnapshot(bDict)
            else { return nil }

            let after:  GuideSnapshot?    = (d["after"] as? [String: Any]).flatMap(decodeSnapshot)
            let srBef:  SelfReportLevel?  = (d["srBefore"]  as? Int).flatMap(SelfReportLevel.init)
            let srAft:  SelfReportLevel?  = (d["srAfter"]   as? Int).flatMap(SelfReportLevel.init)

            return GuideSessionRecord(
                id: id, startedAt: Date(timeIntervalSince1970: ts),
                scene: scene, exercise: exercise, durationSeconds: dur,
                before: before, after: after, hrvUpdated: hrv,
                emotionMemo:            d["emotionMemo"] as? String,
                selfReportBefore:       srBef,
                selfReportAfter:        srAft,
                aiInsightTitle:         d["aiTitle"]   as? String,
                aiInsightSummary:       d["aiSummary"] as? String,
                aiInsightRecommendation: d["aiRec"]    as? String,
                localAIVersion:         d["aiVersion"] as? String
            )
        }
    }

    private func encodeSnapshot(_ s: GuideSnapshot) -> [String: Any] {
        var d: [String: Any] = [
            "timestamp":  s.timestamp.timeIntervalSince1970,
            "score":      s.score,
            "confidence": s.confidence,
            "state":      s.state.rawValue,
            "isMock":     s.isMockData
        ]
        if let v = s.heartRate             { d["heartRate"] = v }
        if let v = s.hrv                   { d["hrv"]       = v }
        if let v = s.heartRateSampleDate   { d["hrDate"]    = v.timeIntervalSince1970 }
        if let v = s.hrvSampleDate         { d["hrvDate"]   = v.timeIntervalSince1970 }
        return d
    }

    private func decodeSnapshot(_ d: [String: Any]) -> GuideSnapshot? {
        guard
            let ts    = d["timestamp"]  as? Double,
            let score = d["score"]      as? Double,
            let conf  = d["confidence"] as? Double,
            let stRaw = d["state"]      as? String,
            let state = MindState(rawValue: stRaw),
            let mock  = d["isMock"]     as? Bool
        else { return nil }
        return GuideSnapshot(
            timestamp:           Date(timeIntervalSince1970: ts),
            score:               score,
            confidence:          conf,
            state:               state,
            heartRate:           d["heartRate"] as? Double,
            hrv:                 d["hrv"]       as? Double,
            isMockData:          mock,
            heartRateSampleDate: (d["hrDate"]  as? Double).map { Date(timeIntervalSince1970: $0) },
            hrvSampleDate:       (d["hrvDate"] as? Double).map { Date(timeIntervalSince1970: $0) }
        )
    }
}

// MARK: - PersonalAIPattern

/// ローカルセッション履歴から推定したユーザー個人の傾向。
struct PersonalAIPattern {
    let sessionCount:         Int
    let dominantScene:        MeasurementScene?
    let preferredExercise:    GuideExercise?
    let calmAfterRatio:       Double
    let highReactivityScenes: [MeasurementScene]
    let selfReportCaptureRate: Double
    let isEarlyStage:         Bool
    let patternLines:         [String]
    let dataQualityNote:      String
}

// MARK: - LocalAIPatternAnalyzer

/// GuideSessionRecordの履歴からPersonalAIPatternをローカルで推定する。
/// 外部通信なし・モデルなし・決定論的ロジックのみ。
enum LocalAIPatternAnalyzer {
    static func analyze(records: [GuideSessionRecord]) -> PersonalAIPattern {
        let n = records.count
        guard n > 0 else {
            return PersonalAIPattern(
                sessionCount: 0, dominantScene: nil, preferredExercise: nil,
                calmAfterRatio: 0, highReactivityScenes: [], selfReportCaptureRate: 0,
                isEarlyStage: true,
                patternLines: ["セッションを重ねると、呼吸の傾向が学習されます。"],
                dataQualityNote: "データ収集中"
            )
        }

        let recent = Array(records.prefix(10))

        // よく選ばれるシーン
        let sceneCounts = Dictionary(grouping: recent, by: \.scene).mapValues(\.count)
        let dominant = sceneCounts.max(by: { $0.value < $1.value })?.key

        // よく使う呼吸法
        let exCounts = Dictionary(grouping: recent, by: \.exercise).mapValues(\.count)
        let preferred = exCounts.max(by: { $0.value < $1.value })?.key

        // 呼吸後の落ち着き率
        let withAfter = recent.compactMap(\.after)
        let calmAfter = withAfter.filter { $0.score < 55 }.count
        let calmRatio = withAfter.isEmpty ? 0.0 : Double(calmAfter) / Double(withAfter.count)

        // 反応が高まりやすい場面
        let highBefore = recent.filter { $0.before.score >= 65 }
        let highScenes = Array(Set(highBefore.map(\.scene)))

        // selfReport収集率
        let srCount = recent.filter { $0.selfReportBefore != nil || $0.selfReportAfter != nil }.count
        let srRate = Double(srCount) / Double(recent.count)

        let isEarly = n < 3

        // パターン文の生成
        var lines: [String] = []

        if isEarly {
            lines.append("セッションが増えると傾向が具体的になります。")
        } else {
            if let ex = preferred, calmRatio > 0.5 {
                lines.append("\(ex.title)後に落ち着く方向へ変化しやすい傾向があります。")
            }
            if let sc = dominant, highScenes.contains(sc) {
                lines.append("\(sc.displayName)の場面で反応が高まりやすい傾向があります。")
            } else if let sc = dominant {
                lines.append("\(sc.displayName)の場面でよく使用されています。")
            }
            if calmRatio > 0.7 {
                lines.append("呼吸後に落ち着く傾向が安定して見られます。")
            } else if calmRatio > 0.4 {
                lines.append("呼吸前後の変化はまちまちです。継続的なケアで傾向がつかみやすくなります。")
            }
        }
        if srRate < 0.3 && n >= 2 {
            lines.append("呼吸後の体感入力が増えると、提案がより個人化されます。")
        }
        if lines.isEmpty {
            lines.append("引き続きセッションを重ねると傾向が見えてきます。")
        }

        let quality: String
        switch n {
        case 0..<3:   quality = "学習データ収集中（\(n)/3）"
        case 3..<6:   quality = "傾向を分析中"
        default:      quality = "パターン安定"
        }

        return PersonalAIPattern(
            sessionCount:         n,
            dominantScene:        dominant,
            preferredExercise:    preferred,
            calmAfterRatio:       calmRatio,
            highReactivityScenes: highScenes,
            selfReportCaptureRate: srRate,
            isEarlyStage:         isEarly,
            patternLines:         lines,
            dataQualityNote:      quality
        )
    }
}

// MARK: - AI Display Tone

/// AIインサイトの表示トーン。scoreの閾値に対応。
enum AIDisplayTone {
    case calm    // score < 25: hue 0.62 cyan-blue
    case focus   // score < 55: hue 0.48 teal-green
    case alert   // score < 78: hue 0.08 orange
    case ovld    // score ≥ 78: hue 0.01 red

    var color: Color {
        switch self {
        case .calm:  return Color(hue: 0.62, saturation: 0.78, brightness: 0.90)
        case .focus: return Color(hue: 0.48, saturation: 0.78, brightness: 0.90)
        case .alert: return Color(hue: 0.08, saturation: 0.88, brightness: 0.98)
        case .ovld:  return Color(hue: 0.01, saturation: 0.92, brightness: 1.00)
        }
    }
}

// MARK: - Self Report Level

/// セッション前後の主観的緊張度。ユーザーが4段階で報告する。
enum SelfReportLevel: Int, CaseIterable, Identifiable {
    case calm               = 0
    case slightTension      = 1
    case significantTension = 2
    case strongTension      = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .calm:               return "落ち着いている"
        case .slightTension:      return "少し緊張"
        case .significantTension: return "かなり緊張"
        case .strongTension:      return "強い緊張"
        }
    }

    var shortLabel: String {
        switch self {
        case .calm:               return "CALM"
        case .slightTension:      return "SLIGHT"
        case .significantTension: return "TENSE"
        case .strongTension:      return "HIGH"
        }
    }

    var accentColor: Color {
        switch self {
        case .calm:               return Color(hue: 0.62, saturation: 0.72, brightness: 0.88)
        case .slightTension:      return Color(hue: 0.48, saturation: 0.72, brightness: 0.88)
        case .significantTension: return Color(hue: 0.08, saturation: 0.82, brightness: 0.95)
        case .strongTension:      return Color(hue: 0.01, saturation: 0.92, brightness: 1.00)
        }
    }
}

// MARK: - MindWave AI Context

/// AIエンジンへ渡す全セッションコンテキスト。外部通信なし・完全ローカル。
struct MindWaveAIContext {
    let scene:             MeasurementScene
    let breathingMethod:   GuideExercise
    let currentHeartRate:  Double
    let state:             MindState
    let sessionElapsed:    Int
    let sessionCompleted:  Bool
    let beforeHeartRate:   Double?
    let afterHeartRate:    Double?
    let beforeState:       MindState?
    let afterState:        MindState?
    let selfReportBefore:  SelfReportLevel?
    let selfReportAfter:   SelfReportLevel?
    let baselineHeartRate: Double?
    let source:            String  // "local"
}

// MARK: - MindWave AI Insight

/// LocalMindWaveAIEngineが生成するインサイト。全画面で共通利用可能。
struct MindWaveAIInsight {
    let title:           String
    let summary:         String
    let analysis:        String
    let recommendation:  String
    let nextAction:      String
    let caution:         String
    let confidenceLabel: String
    let displayTone:     AIDisplayTone
    let shouldShowOnHome:    Bool
    let shouldShowInSession: Bool
    let shouldShowInResult:  Bool
    let shouldShowInHistory: Bool
}
