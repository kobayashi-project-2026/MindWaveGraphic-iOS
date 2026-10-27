// InsightTests.swift
// InsightProvider（ローカル/リモート切替・フォールバック・通信エラー・タイムアウト）のテスト。
// 通信は URLProtocol のスタブで再現する（外部へは送信しない）。
// 環境変数 MW_E2E_BASE_URL / MW_E2E_CLIENT_TOKEN があれば、ローカルの server（--stub-openai）との E2E も行う。

import Foundation

/// URLSession の通信を差し替えるスタブ
nonisolated final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var body: Data = Data()
        var delay: TimeInterval = 0
    }
    nonisolated(unsafe) static var reply: (URLRequest, Data) -> Reply = { _, _ in Reply() }
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var callCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(request)
        Self.lastRequest = request
        Self.lastBody = body
        Self.callCount += 1
        let r = Self.reply(request, body)
        let deliver = { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: r.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if r.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + r.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

enum InsightTests {
    typealias T = TestHarness

    static let config = RemoteInsightConfiguration(baseURL: URL(string: "https://insight.example.test")!,
                                                   clientToken: "test-client-token-0123456789", timeout: 2)

    static func makeInput(mock: Bool = false, afterHRV: Double? = 46) -> InsightSessionInput {
        let before = GuideSnapshot(timestamp: Date(), score: 72.4, confidence: 0.75, state: .overTense, heartRate: 96.4,
                                   hrv: 40, isMockData: mock, heartRateSampleDate: Date(), hrvSampleDate: Date(), dataSource: .watchLive)
        let after = GuideSnapshot(timestamp: Date(), score: 47.6, confidence: 0.75, state: .optimalTension, heartRate: nil,
                                  hrv: afterHRV, isMockData: mock, heartRateSampleDate: nil, hrvSampleDate: nil, dataSource: .watchLive)
        let ctx = MindWaveAIContext(scene: .interview, breathingMethod: .breathing478, currentHeartRate: 90, state: .optimalTension,
                                    sessionElapsed: 180, sessionCompleted: true, beforeHeartRate: 96.4, afterHeartRate: nil,
                                    beforeState: .overTense, afterState: .optimalTension, selfReportBefore: .significantTension,
                                    selfReportAfter: nil, baselineHeartRate: nil, source: "local")
        return InsightSessionInput(context: ctx, before: before, after: after, durationSeconds: 180)
    }

    /// サーバー応答（契約どおり）。request_id はリクエストからエコーする
    static func okReply(_ request: URLRequest, _ body: Data, title: String = "呼吸でペースが整いました") -> StubURLProtocol.Reply {
        let req = try? MindWaveContract.makeDecoder().decode(InsightRequestDTO.self, from: body)
        let response = ContractTests.makeInsightResponse(id: req?.requestId ?? UUID(), title: title)
        var r = StubURLProtocol.Reply()
        r.body = (try? MindWaveContract.makeEncoder().encode(response)) ?? Data()
        return r
    }

    static func run() async {
        T.suite("Insight / リクエスト生成（データ最小化）")
        builder()
        T.suite("Insight / RemoteInsightProvider（スタブ通信）")
        await remote()
        T.suite("Insight / InsightService（切替・フォールバック）")
        await service()
        T.suite("Insight / 設定")
        configuration()
        await e2e()
    }

    static func builder() {
        T.test("Mock を含むセッションは送信用リクエストを作らない") {
            T.expectThrows("mock") { _ = try InsightRequestBuilder.makeRequest(makeInput(mock: true)) }
        }
        T.test("丸め・HRV は方向のみ・未計測は null") {
            let req = try InsightRequestBuilder.makeRequest(makeInput())
            T.expectEqual(req.session.before.score, 72)
            T.expectEqual(req.session.before.heartRateBpm, 96)
            T.expect(req.session.after?.heartRateBpm == nil, "after hr nil")
            T.expectEqual(req.session.after?.score, 48)
            T.expectEqual(req.session.hrvTrend, .up)
            T.expectEqual(req.session.selfReportBefore, 2)
            T.expect(req.consent.externalAIConsented, "consent flag")
            let json = String(data: try MindWaveContract.makeEncoder().encode(req), encoding: .utf8)!
            T.expect(!json.contains("40") || !json.contains("hrv_sdnn"), "no raw hrv")
            T.expect(!json.contains("captured_at") && !json.contains("memo"), "no timestamps/memo")
        }
        T.test("HRV の変化方向") {
            T.expectEqual(InsightRequestBuilder.hrvTrend(before: 40, after: 46), .up)
            T.expectEqual(InsightRequestBuilder.hrvTrend(before: 40, after: 33), .down)
            T.expectEqual(InsightRequestBuilder.hrvTrend(before: 40, after: 41.5), .flat)
            T.expectEqual(InsightRequestBuilder.hrvTrend(before: nil, after: 41.5), .unknown)
        }
    }

    static func remote() async {
        let provider = RemoteInsightProvider(configuration: config, session: StubURLProtocol.session())

        await T.test("正常応答: POST /v1/insights・Bearer 認証・応答の検証・生成元バージョン") {
            StubURLProtocol.reply = { req, body in okReply(req, body) }
            let generated = try await provider.generateInsight(makeInput())
            T.expectEqual(generated.insight.title, "呼吸でペースが整いました")
            T.expectEqual(generated.providerVersion, "remote:openai:test-model")
            let req = StubURLProtocol.lastRequest
            T.expectEqual(req?.httpMethod, "POST")
            T.expectEqual(req?.url?.path, "/v1/insights")
            T.expectEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer test-client-token-0123456789")
            let sent = try MindWaveContract.makeDecoder().decode(InsightRequestDTO.self, from: StubURLProtocol.lastBody ?? Data())
            T.expectEqual(sent.session.scene, "interview")
        }
        await T.test("HTTP 503 → httpStatus(503, not_configured)") {
            StubURLProtocol.reply = { _, _ in
                StubURLProtocol.Reply(status: 503, body: Data(#"{"schema_version":1,"request_id":null,"error":"not_configured","message":"x"}"#.utf8))
            }
            do { _ = try await provider.generateInsight(makeInput()); T.fail("expected error") }
            catch let e as InsightClientError { T.expectEqual(e, .httpStatus(503, errorCode: "not_configured")) }
        }
        await T.test("契約違反の応答（禁止表現）→ invalidResponse") {
            StubURLProtocol.reply = { req, body in okReply(req, body, title: "病気の兆候です") }
            do { _ = try await provider.generateInsight(makeInput()); T.fail("expected error") }
            catch let e as InsightClientError { T.expect(e.logCode == "invalid_response", "\(e)") }
        }
        await T.test("request_id が一致しない応答 → invalidResponse") {
            StubURLProtocol.reply = { _, _ in
                var r = StubURLProtocol.Reply()
                r.body = (try? MindWaveContract.makeEncoder().encode(ContractTests.makeInsightResponse(id: UUID()))) ?? Data()
                return r
            }
            do { _ = try await provider.generateInsight(makeInput()); T.fail("expected error") }
            catch let e as InsightClientError { T.expectEqual(e.logCode, "invalid_response") }
        }
        await T.test("タイムアウト → timeout") {
            var short = config
            short.timeout = 0.3
            let slow = RemoteInsightProvider(configuration: short, session: StubURLProtocol.session())
            StubURLProtocol.reply = { req, body in var r = okReply(req, body); r.delay = 2; return r }
            do { _ = try await slow.generateInsight(makeInput()); T.fail("expected timeout") }
            catch let e as InsightClientError { T.expectEqual(e, .timeout) }
        }
    }

    static func service() async {
        func makeService(consent: Bool, configured: Bool, session: URLSession = StubURLProtocol.session()) -> InsightService {
            let defaults = T.freshDefaults("insight-consent-\(consent)-\(configured)")
            let store = InsightConsentStore(defaults: defaults)
            store.setConsented(consent)
            return InsightService(consentStore: store,
                                  configurationProvider: { configured ? config : nil },
                                  remoteFactory: { RemoteInsightProvider(configuration: $0, session: session) })
        }

        await T.test("同意なし → 通信せずローカル") {
            StubURLProtocol.callCount = 0
            let outcome = await makeService(consent: false, configured: true).generate(makeInput())
            T.expect(!outcome.usedRemote, "local")
            T.expectEqual(outcome.providerVersion, "local-v1")
            T.expectEqual(outcome.fallbackReason, "consent_missing")
            T.expectEqual(StubURLProtocol.callCount, 0)
        }
        await T.test("サーバー未設定 → ローカル") {
            let outcome = await makeService(consent: true, configured: false).generate(makeInput())
            T.expectEqual(outcome.fallbackReason, "not_configured")
        }
        await T.test("Mock データ → 同意があっても送信しない") {
            StubURLProtocol.callCount = 0
            let outcome = await makeService(consent: true, configured: true).generate(makeInput(mock: true))
            T.expectEqual(outcome.fallbackReason, "contains_mock_data")
            T.expectEqual(StubURLProtocol.callCount, 0)
        }
        await T.test("リモート成功 → リモートの結果") {
            StubURLProtocol.reply = { req, body in okReply(req, body) }
            let outcome = await makeService(consent: true, configured: true).generate(makeInput())
            T.expect(outcome.usedRemote, "remote")
            T.expectEqual(outcome.providerVersion, "remote:openai:test-model")
        }
        await T.test("リモート失敗（500）→ ローカルへフォールバックし必ず結果を返す") {
            StubURLProtocol.reply = { _, _ in StubURLProtocol.Reply(status: 500, body: Data("oops".utf8)) }
            let outcome = await makeService(consent: true, configured: true).generate(makeInput())
            T.expect(!outcome.usedRemote, "fallback")
            T.expectEqual(outcome.providerVersion, "local-v1")
            T.expectEqual(outcome.fallbackReason, "http_500_unknown")
            T.expect(!outcome.insight.title.isEmpty, "local insight present")
        }
        await T.test("ローカル結果は既存エンジンと同一") {
            let input = makeInput()
            let a = InsightService(consentStore: InsightConsentStore(defaults: T.freshDefaults("ins-local"))).localInsight(input.context).insight
            let b = LocalMindWaveAIEngine.generate(context: input.context)
            T.expectEqual(a.title, b.title)
            T.expectEqual(a.recommendation, b.recommendation)
        }
    }

    static func configuration() {
        T.test("設定: HTTPS は可・localhost 以外の HTTP は不可・トークン必須") {
            let d = T.freshDefaults("insight-config")
            T.expect(RemoteInsightConfiguration.load(defaults: d, environment: [:]) == nil, "empty")
            d.set("https://api.example.com", forKey: RemoteInsightConfiguration.baseURLKey)
            T.expect(RemoteInsightConfiguration.load(defaults: d, environment: [:]) == nil, "no token")
            d.set("token-0123456789abcdef", forKey: RemoteInsightConfiguration.clientTokenKey)
            T.expect(RemoteInsightConfiguration.load(defaults: d, environment: [:]) != nil, "https ok")
            d.set("http://api.example.com", forKey: RemoteInsightConfiguration.baseURLKey)
            T.expect(RemoteInsightConfiguration.load(defaults: d, environment: [:]) == nil, "plain http rejected")
            d.set("http://127.0.0.1:8787", forKey: RemoteInsightConfiguration.baseURLKey)
            T.expect(RemoteInsightConfiguration.load(defaults: d, environment: [:]) != nil, "localhost http ok")
        }
        T.test("同意は版が一致したときだけ有効") {
            let d = T.freshDefaults("insight-consent-version")
            let store = InsightConsentStore(defaults: d)
            T.expect(!store.isConsented, "default off")
            store.setConsented(true)
            T.expect(store.isConsented, "on")
            d.set(0, forKey: InsightConsentStore.defaultsKey)
            T.expect(!store.isConsented, "old version invalid")
        }
    }

    /// ローカルの server（node scripts/dev-server.ts --stub-openai）との E2E
    static func e2e() async {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["MW_E2E_BASE_URL"], let url = URL(string: base),
              let token = env["MW_E2E_CLIENT_TOKEN"] else {
            print("\n=== Insight / E2E (skipped: MW_E2E_BASE_URL 未設定) ===")
            return
        }
        T.suite("Insight / E2E with local server (\(base))")
        let cfg = RemoteInsightConfiguration(baseURL: url, clientToken: token, timeout: 10)
        await T.test("iOS → server → OpenAI スタブ → 検証済みインサイト") {
            let generated = try await RemoteInsightProvider(configuration: cfg).generateInsight(makeInput())
            T.expect(!generated.insight.title.isEmpty, "title")
            T.expect(generated.providerVersion.hasPrefix("remote:openai:"), generated.providerVersion)
        }
        await T.test("誤ったトークン → 401 → InsightService はローカルへフォールバック") {
            let badCfg = RemoteInsightConfiguration(baseURL: url, clientToken: "wrong-token-0123456789", timeout: 10)
            let store = InsightConsentStore(defaults: T.freshDefaults("e2e-consent"))
            store.setConsented(true)
            let service = InsightService(consentStore: store, configurationProvider: { badCfg },
                                         remoteFactory: { RemoteInsightProvider(configuration: $0) })
            let outcome = await service.generate(makeInput())
            T.expectEqual(outcome.fallbackReason, "http_401_unauthorized")
            T.expect(!outcome.usedRemote, "fallback")
        }
    }
}
