// InsightProvider.swift
// Insights
//
// ガイド結果の「振り返り（AIインサイト）」生成の抽象化。
// - LocalInsightProvider : 既存の LocalMindWaveAIEngine（GuideFlowView.swift）をそのまま使う。通信なし
// - RemoteInsightProvider: 自前APIサーバー（server/）経由で外部AIを使う。OpenAI の APIキーはサーバーだけが持つ
// - InsightService       : 送信可否の判定とフォールバック（失敗時は必ずローカル結果を返す）
//
// 外部送信の条件（すべて満たす場合のみ）:
//   1. ユーザーが設定画面で外部AI送信に同意している（InsightConsentStore）
//   2. サーバーの URL とクライアント認証トークンが設定されている（RemoteInsightConfiguration）
//   3. セッションに Mock データを含まない

import Foundation

/// インサイト生成の入力（ガイド1回分）
struct InsightSessionInput {
    /// 既存ローカルエンジンへの入力
    let context: MindWaveAIContext
    let before: GuideSnapshot
    let after: GuideSnapshot?
    let durationSeconds: Int

    /// Mock 計測を含むか（含む場合は外部送信しない）
    var containsMockData: Bool {
        before.isMockData || (after?.isMockData ?? false)
    }
}

/// 生成結果
struct InsightOutcome {
    let insight: MindWaveAIInsight
    /// 保存用の生成元識別子（GuideSessionRecord.localAIVersion に保存）例: "local-v1" / "remote:openai:gpt-4o-mini"
    let providerVersion: String
    let usedRemote: Bool
    /// リモートを使わなかった・失敗した理由（ログ・診断用。ユーザー入力値は含めない）
    let fallbackReason: String?
}

/// 生成されたインサイトと生成元
struct GeneratedInsight {
    let insight: MindWaveAIInsight
    let providerVersion: String
}

/// インサイト生成方式のインターフェース。新しい方式はこれに準拠させて InsightService に渡す。
protocol InsightProvider {
    func generateInsight(_ input: InsightSessionInput) async throws -> GeneratedInsight
}

/// 既存のローカルAI（ルールベース・端末内のみ）
struct LocalInsightProvider: InsightProvider {
    /// 既存の保存値 "local-v1" を維持する
    let providerVersion = "local-v1"

    func generateInsight(_ input: InsightSessionInput) async throws -> GeneratedInsight {
        GeneratedInsight(insight: LocalMindWaveAIEngine.generate(context: input.context), providerVersion: providerVersion)
    }

    /// 同期版（既存の呼び出し箇所と同じ結果）
    func generateNow(_ context: MindWaveAIContext) -> MindWaveAIInsight {
        LocalMindWaveAIEngine.generate(context: context)
    }
}

// MARK: - 同意

/// 外部AIへの要約送信の同意（端末内に保存）
nonisolated struct InsightConsentStore {
    static let defaultsKey = "mindwave.insight.externalConsent.v1"
    /// 同意文言を変更したら上げる（古い版の同意は無効になる）
    static let currentConsentVersion = 1

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isConsented: Bool {
        defaults.integer(forKey: Self.defaultsKey) == Self.currentConsentVersion
    }

    func setConsented(_ consented: Bool) {
        if consented {
            defaults.set(Self.currentConsentVersion, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
        MindWaveDebugLogger.log(.insight, "external AI consent \(consented ? "granted" : "revoked") version=\(Self.currentConsentVersion)")
    }
}

// MARK: - 送信可否とフォールバック

/// リモートを使えない理由
enum InsightRemoteIneligibility: String {
    case consentMissing   = "consent_missing"
    case notConfigured    = "not_configured"
    case containsMockData = "contains_mock_data"
}

@MainActor
final class InsightService {

    static let shared = InsightService()

    private let local = LocalInsightProvider()
    private let consentStore: InsightConsentStore
    private let configurationProvider: () -> RemoteInsightConfiguration?
    private let remoteFactory: (RemoteInsightConfiguration) -> InsightProvider

    init(consentStore: InsightConsentStore = InsightConsentStore(),
         configurationProvider: @escaping () -> RemoteInsightConfiguration? = { RemoteInsightConfiguration.load() },
         remoteFactory: @escaping (RemoteInsightConfiguration) -> InsightProvider = { RemoteInsightProvider(configuration: $0) }) {
        self.consentStore = consentStore
        self.configurationProvider = configurationProvider
        self.remoteFactory = remoteFactory
    }

    /// リモートを使えるか。使えない場合は理由を返す。
    func remoteIneligibility(for input: InsightSessionInput) -> InsightRemoteIneligibility? {
        if input.containsMockData { return .containsMockData }
        if !consentStore.isConsented { return .consentMissing }
        if configurationProvider() == nil { return .notConfigured }
        return nil
    }

    /// サーバー設定があるか（設定画面の表示用）
    var isRemoteConfigured: Bool { configurationProvider() != nil }

    /// 同期のローカル結果（既存の即時表示用）
    func localInsight(_ context: MindWaveAIContext) -> InsightOutcome {
        InsightOutcome(insight: local.generateNow(context), providerVersion: local.providerVersion,
                       usedRemote: false, fallbackReason: nil)
    }

    /// 条件を満たせばリモート、満たさない・失敗した場合はローカルの結果を返す（必ず結果を返す）
    func generate(_ input: InsightSessionInput) async -> InsightOutcome {
        if let reason = remoteIneligibility(for: input) {
            MindWaveDebugLogger.log(.insight, "remote skipped reason=\(reason.rawValue)")
            return InsightOutcome(insight: local.generateNow(input.context), providerVersion: local.providerVersion,
                                  usedRemote: false, fallbackReason: reason.rawValue)
        }
        guard let configuration = configurationProvider() else {
            return InsightOutcome(insight: local.generateNow(input.context), providerVersion: local.providerVersion,
                                  usedRemote: false, fallbackReason: InsightRemoteIneligibility.notConfigured.rawValue)
        }
        let remote = remoteFactory(configuration)
        let started = Date()
        do {
            let generated = try await remote.generateInsight(input)
            MindWaveDebugLogger.log(.insight, "remote succeeded provider=\(generated.providerVersion) latencyMs=\(Int(Date().timeIntervalSince(started) * 1000))")
            return InsightOutcome(insight: generated.insight, providerVersion: generated.providerVersion, usedRemote: true, fallbackReason: nil)
        } catch {
            let reason = (error as? InsightClientError)?.logCode ?? "unknown_error"
            MindWaveDebugLogger.log(.insight, "remote failed -> local fallback reason=\(reason) latencyMs=\(Int(Date().timeIntervalSince(started) * 1000))")
            return InsightOutcome(insight: local.generateNow(input.context), providerVersion: local.providerVersion,
                                  usedRemote: false, fallbackReason: reason)
        }
    }
}
