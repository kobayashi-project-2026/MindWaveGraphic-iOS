// RemoteInsightProvider.swift
// Insights
//
// 自前APIサーバー（server/ の Cloudflare Worker）へ POST /v1/insights を送る。
// アプリは OpenAI の APIキーを持たない。サーバーへの認証は「クライアントトークン」（Bearer）で行う。
// ※ クライアントトークンは端末から取り出せるため、本番ではユーザー認証（Firebase ID トークン等）か
//   App Attest に置き換えること（docs/OPENAI_SETUP.md「今後の課題」）。

import Foundation

/// サーバー接続設定
nonisolated struct RemoteInsightConfiguration: Equatable {
    let baseURL: URL
    let clientToken: String
    /// 1リクエストのタイムアウト（秒）。サーバー側 OpenAI タイムアウト(15秒)より少し長くする
    var timeout: TimeInterval = 20

    /// UserDefaults のキー（設定画面・デバッグ用。トークンをソースコードに書かないこと）
    static let baseURLKey = "mindwave.insight.baseURL"
    static let clientTokenKey = "mindwave.insight.clientToken"

    /// 設定を読み込む。DEBUG ビルドでは環境変数（MW_INSIGHT_BASE_URL / MW_INSIGHT_CLIENT_TOKEN）を優先する。
    /// どちらかが欠けていれば nil（= リモート無効）。
    static func load(defaults: UserDefaults = .standard,
                     environment: [String: String] = ProcessInfo.processInfo.environment) -> RemoteInsightConfiguration? {
        var urlText = defaults.string(forKey: baseURLKey)
        var token = defaults.string(forKey: clientTokenKey)
        #if DEBUG
        if let v = environment["MW_INSIGHT_BASE_URL"], !v.isEmpty { urlText = v }
        if let v = environment["MW_INSIGHT_CLIENT_TOKEN"], !v.isEmpty { token = v }
        #endif
        guard let urlText, let url = URL(string: urlText), let scheme = url.scheme,
              let token, !token.isEmpty else { return nil }
        // 本番通信は HTTPS のみ。ローカル開発サーバー（localhost / 127.0.0.1）だけ HTTP を許可する
        let isLocalHost = url.host == "localhost" || url.host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && isLocalHost) else { return nil }
        return RemoteInsightConfiguration(baseURL: url, clientToken: token)
    }
}

/// 通信・検証エラー
enum InsightClientError: Error, Equatable {
    case timeout
    case transport(code: Int)
    case httpStatus(Int, errorCode: String?)
    case invalidResponse(String)
    case containsMockData

    /// ログ用の短いコード（ユーザーデータは含めない）
    var logCode: String {
        switch self {
        case .timeout:                     return "timeout"
        case .transport(let code):         return "transport_\(code)"
        case .httpStatus(let s, let code): return "http_\(s)_\(code ?? "unknown")"
        case .invalidResponse:             return "invalid_response"
        case .containsMockData:            return "contains_mock_data"
        }
    }
}

/// ガイド結果 → 送信用の最小要約へ変換する
enum InsightRequestBuilder {

    static func makeRequest(_ input: InsightSessionInput, requestId: UUID = UUID()) throws -> InsightRequestDTO {
        guard !input.containsMockData else { throw InsightClientError.containsMockData }
        let ctx = input.context
        return InsightRequestDTO(
            requestId: requestId,
            consent: InsightConsentDTO(externalAIConsented: true, consentVersion: InsightConsentStore.currentConsentVersion),
            session: InsightSessionSummaryDTO(
                scene: ctx.scene.rawValue,
                exercise: ctx.breathingMethod.rawValue,
                durationSeconds: input.durationSeconds,
                completed: ctx.sessionCompleted,
                before: summary(input.before),
                after: input.after.map { summary($0) },
                hrvTrend: hrvTrend(before: input.before.hrv, after: input.after?.hrv),
                selfReportBefore: ctx.selfReportBefore?.rawValue,
                selfReportAfter: ctx.selfReportAfter?.rawValue,
                confidence: (((input.after ?? input.before).confidence) * 10).rounded() / 10
            )
        )
    }

    private static func summary(_ s: GuideSnapshot) -> InsightMeasurementSummaryDTO {
        InsightMeasurementSummaryDTO(
            state: MindStateCode(s.state),
            score: Int(s.score.rounded()),
            heartRateBpm: s.heartRate.map { Int($0.rounded()) }
        )
    }

    /// HRV は実数値を送らず、変化の方向だけを送る（±2ms 以内は flat）
    static func hrvTrend(before: Double?, after: Double?) -> HRVTrendCode {
        guard let before, let after else { return .unknown }
        let delta = after - before
        if delta > 2 { return .up }
        if delta < -2 { return .down }
        return .flat
    }
}

/// サーバー経由のリモートAI
struct RemoteInsightProvider: InsightProvider {
    let configuration: RemoteInsightConfiguration
    var session: URLSession = .shared

    func generateInsight(_ input: InsightSessionInput) async throws -> GeneratedInsight {
        let request = try InsightRequestBuilder.makeRequest(input)
        let response = try await send(request)
        // 保存値: "remote:<provider>:<model>"
        return GeneratedInsight(insight: Self.makeInsight(from: response.insight),
                                providerVersion: "remote:\(response.provider):\(response.model ?? "unknown")")
    }

    /// 送信して検証済みのレスポンスを返す
    func send(_ body: InsightRequestDTO) async throws -> InsightResponseDTO {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/insights"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.clientToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try MindWaveContract.makeEncoder().encode(body)

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch let error as URLError {
            throw error.code == .timedOut ? InsightClientError.timeout : InsightClientError.transport(code: error.code.rawValue)
        }

        guard let http = urlResponse as? HTTPURLResponse else {
            throw InsightClientError.invalidResponse("not http")
        }
        let decoder = MindWaveContract.makeDecoder()
        guard http.statusCode == 200 else {
            let code = (try? decoder.decode(InsightErrorDTO.self, from: data))?.error
            throw InsightClientError.httpStatus(http.statusCode, errorCode: code)
        }
        let decoded: InsightResponseDTO
        do {
            decoded = try decoder.decode(InsightResponseDTO.self, from: data)
            try InsightValidation.validate(decoded, expectedRequestId: body.requestId)
        } catch {
            throw InsightClientError.invalidResponse(String(describing: error))
        }
        return decoded
    }

    /// 契約の本文 → 既存の表示モデル
    static func makeInsight(from b: InsightBodyDTO) -> MindWaveAIInsight {
        let tone: AIDisplayTone
        switch b.tone {
        case .calm:  tone = .calm
        case .focus: tone = .focus
        case .alert: tone = .alert
        case .ovld:  tone = .ovld
        }
        return MindWaveAIInsight(
            title: b.title, summary: b.summary, analysis: b.analysis,
            recommendation: b.recommendation, nextAction: b.nextAction, caution: b.caution,
            confidenceLabel: b.confidenceLabel, displayTone: tone,
            shouldShowOnHome: false, shouldShowInSession: false,
            shouldShowInResult: true, shouldShowInHistory: true
        )
    }
}
