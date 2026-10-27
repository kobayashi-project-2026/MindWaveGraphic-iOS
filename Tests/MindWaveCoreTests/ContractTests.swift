// ContractTests.swift
// Contracts の encode/decode・後方互換・検証規則のテスト

import Foundation

enum ContractTests {
    typealias T = TestHarness

    static func run() {
        T.suite("Contracts / Watch payload")
        watchPayload()
        T.suite("Contracts / Date & null")
        datesAndNulls()
        T.suite("Contracts / Measurement & Context")
        measurement()
        T.suite("Contracts / Analysis & Graphic")
        analysis()
        T.suite("Contracts / Session & History")
        session()
        T.suite("Contracts / Insight")
        insight()
        T.suite("Contracts / Golden fixtures (docs/DATA_CONTRACTS.md)")
        golden()
    }

    // MARK: - Watch

    static func watchPayload() {
        T.test("旧Watch形式(schema v0)を受信できる") {
            let msg: [String: Any] = ["type": "heartRate", "heartRate": 72.0, "timestamp": 1_761_600_000.5]
            guard case .success(let p) = WatchHeartRatePayload.decode(msg) else { return T.fail("decode failed") }
            T.expectEqual(p.heartRateBpm, 72.0)
            T.expectEqual(p.schemaVersion, 0)
            T.expect(T.sameInstant(p.measuredAt, Date(timeIntervalSince1970: 1_761_600_000.5)), "timestamp")
        }
        T.test("v1 辞書の往復") {
            let p = WatchHeartRatePayload(heartRateBpm: 88, measuredAt: Date(timeIntervalSince1970: 1_761_600_123))
            guard case .success(let back) = WatchHeartRatePayload.decode(p.dictionary) else { return T.fail("decode failed") }
            T.expectEqual(back, p)
            T.expectEqual(p.dictionary["schemaVersion"] as? Int, 1)
        }
        T.test("NSNumber(Int) の心拍も受け付ける") {
            let msg: [String: Any] = ["type": "heartRate", "heartRate": NSNumber(value: 70), "timestamp": NSNumber(value: 1_761_600_000)]
            guard case .success(let p) = WatchHeartRatePayload.decode(msg) else { return T.fail("decode failed") }
            T.expectEqual(p.heartRateBpm, 70)
        }
        T.test("不正な辞書は理由を区別して拒否する") {
            T.expect(WatchHeartRatePayload.decode(["heartRate": 70.0, "timestamp": 1.0]) == .failure(.typeMissingOrNotHeartRate), "type")
            T.expect(WatchHeartRatePayload.decode(["type": "heartRate", "timestamp": 1.0]) == .failure(.heartRateMissingOrWrongType), "hr")
            T.expect(WatchHeartRatePayload.decode(["type": "heartRate", "heartRate": "70", "timestamp": 1.0]) == .failure(.heartRateMissingOrWrongType), "hr type")
            T.expect(WatchHeartRatePayload.decode(["type": "heartRate", "heartRate": 70.0]) == .failure(.timestampMissingOrWrongType), "ts")
            T.expect(WatchHeartRatePayload.decode(["type": "heartRate", "heartRate": 70.0, "timestamp": 1.0, "schemaVersion": 99]) == .failure(.unsupportedSchemaVersion(99)), "future version")
        }
        T.test("範囲判定") {
            T.expect(!WatchHeartRatePayload(heartRateBpm: 0, measuredAt: Date()).isPlausible, "0 bpm")
            T.expect(!WatchHeartRatePayload(heartRateBpm: 300, measuredAt: Date()).isPlausible, "300 bpm")
            T.expect(WatchHeartRatePayload(heartRateBpm: 60, measuredAt: Date()).isPlausible, "60 bpm")
        }
    }

    // MARK: - 日時・null

    static func datesAndNulls() {
        T.test("日時は UTC ISO8601 ミリ秒付きで出力") {
            let dto = GraphicInputDTO(input: GraphicInput(score: 10, confidence: 0.5, state: .underAroused))
            _ = dto
            let s = ContractDateFormatter.string(from: Date(timeIntervalSince1970: 1_761_626_112.123))
            T.expectEqual(s, "2025-10-28T04:35:12.123Z")
        }
        T.test("ミリ秒なし・UNIX秒の日時も読める") {
            struct W: Codable { let d: Date }
            let dec = MindWaveContract.makeDecoder()
            let a = try dec.decode(W.self, from: Data(#"{"d":"2025-10-28T04:35:12Z"}"#.utf8))
            let b = try dec.decode(W.self, from: Data(#"{"d":1761626112}"#.utf8))
            T.expect(T.sameInstant(a.d, b.d), "same instant")
            T.expectThrows("不正な日時") { _ = try dec.decode(W.self, from: Data(#"{"d":"yesterday"}"#.utf8)) }
        }
        T.test("未計測は null として明示出力される") {
            let dto = MeasurementSampleDTO(source: .watchLive, measuredAt: Date(), heartRateBpm: 70, hrvSdnnMs: nil)
            let json = String(data: try MindWaveContract.makeEncoder().encode(dto), encoding: .utf8)!
            T.expect(json.contains(#""hrv_sdnn_ms":null"#), "hrv null present: \(json)")
            T.expect(json.contains(#""mock_score":null"#), "mock_score null present")
        }
        T.test("キー欠落も null と同じく未計測として読める") {
            let json = #"{"schema_version":1,"source":"health_kit","is_mock":false,"measured_at":"2026-10-28T00:00:00.000Z"}"#
            let dto = try MindWaveContract.makeDecoder().decode(MeasurementSampleDTO.self, from: Data(json.utf8))
            T.expect(dto.heartRateBpm == nil && dto.hrvSdnnMs == nil, "nil values")
            try dto.validate()
        }
    }

    // MARK: - 計測

    static func measurement() {
        T.test("実測サンプルの往復とドメイン変換") {
            let sample = MindWaveSample(heartRate: 76, hrv: 41.5, contextScore: nil, source: .watchLive, timestamp: Date())
            let dto = MeasurementSampleDTO(sample: sample)
            let data = try MindWaveContract.makeEncoder().encode(dto)
            let back = try MindWaveContract.makeDecoder().decode(MeasurementSampleDTO.self, from: data)
            try back.validate()
            let domain = back.domainSample
            T.expectEqual(domain.heartRate, 76)
            T.expectEqual(domain.hrv, 41.5)
            T.expectEqual(domain.source, .watchLive)
            T.expect(domain.contextScore == nil, "real sample has no context score")
            T.expect(!back.isMock, "not mock")
        }
        T.test("Mock サンプルは is_mock=true・mock_score を保持") {
            let sample = MindWaveSample(heartRate: nil, hrv: nil, contextScore: 64, source: .mock, timestamp: Date())
            let dto = MeasurementSampleDTO(sample: sample)
            T.expect(dto.isMock, "is mock")
            T.expectEqual(dto.mockScore, 64)
            try dto.validate()
        }
        T.test("実測に contextScore があっても mock_score へ出さない") {
            let sample = MindWaveSample(heartRate: 70, hrv: nil, contextScore: 50, source: .healthKit, timestamp: Date())
            T.expect(MeasurementSampleDTO(sample: sample).mockScore == nil, "no mock score")
        }
        T.test("検証: is_mock 不一致・範囲外・実測の mock_score を拒否") {
            var a = MeasurementSampleDTO(source: .watchLive, measuredAt: Date(), heartRateBpm: 70, hrvSdnnMs: nil)
            a.isMock = true
            T.expectThrows("is_mock mismatch") { try a.validate() }
            let b = MeasurementSampleDTO(source: .watchLive, measuredAt: Date(), heartRateBpm: 0, hrvSdnnMs: nil)
            T.expectThrows("hr 0") { try b.validate() }
            let c = MeasurementSampleDTO(source: .healthKit, measuredAt: Date(), heartRateBpm: 70, hrvSdnnMs: 900)
            T.expectThrows("hrv 900") { try c.validate() }
            var d = MeasurementSampleDTO(source: .healthKit, measuredAt: Date(), heartRateBpm: 70, hrvSdnnMs: nil)
            d.mockScore = 30
            T.expectThrows("mock score on real") { try d.validate() }
            var e = MeasurementSampleDTO(source: .watchLive, measuredAt: Date(), heartRateBpm: 70, hrvSdnnMs: nil)
            e.schemaVersion = 2
            T.expectThrows("future schema") { try e.validate() }
        }
        T.test("測定コンテキストの往復・未知値は安全側") {
            var ctx = MeasurementContext()
            ctx.scene = .interview
            ctx.conditions = [.caffeine, .running]
            let dto = MeasurementContextDTO(context: ctx)
            T.expectEqual(dto.bodyConditions, ["caffeine", "running"])
            T.expectEqual(dto.domainContext, ctx)
            T.expectEqual(dto.totalScoreOffset, ctx.totalScoreOffset)
            let unknown = MeasurementContextDTO(context: .default)
            T.expectEqual(unknown.bodyConditions, [])
            T.expectEqual(unknown.domainContext, .default)
            var weird = dto
            weird.scene = "space_travel"
            weird.bodyConditions = ["levitating"]
            T.expectEqual(weird.domainContext, .default)
        }
    }

    // MARK: - 分析

    static func analysis() {
        T.test("分析結果 DTO は metadata を反映し検証を通る") {
            var meta = AnalysisMetadata()
            meta.source = .watchLive
            meta.analyzerID = "stress-score-v1"
            meta.analyzerVersion = "1.0"
            meta.heartRate = 80
            meta.hrvStatus = .missing
            meta.baselineStatus = .provisional
            let result = MindAnalysisResult(tensionScore: 55, confidence: 0.5, state: .optimalTension, timestamp: Date(), metadata: meta)
            let dto = AnalysisResultDTO(result: result, context: .default)
            try dto.validate()
            T.expectEqual(dto.source, .watchLive)
            T.expect(!dto.isMock, "not mock")
            T.expect(!dto.isMedicalDiagnosis, "not diagnosis")
            T.expectEqual(dto.inputs.hrvStatus, "missing")
            let json = String(data: try MindWaveContract.makeEncoder().encode(dto), encoding: .utf8)!
            T.expect(json.contains(#""hrv_sdnn_ms":null"#), "hrv null")
            let back = try MindWaveContract.makeDecoder().decode(AnalysisResultDTO.self, from: Data(json.utf8))
            T.expectEqual(back.tensionScore, 55)
            T.expectEqual(back.state, .optimalTension)
        }
        T.test("分析結果の検証: 範囲外・診断フラグ") {
            let base = AnalysisResultDTO(result: MindAnalysisResult(tensionScore: 10, confidence: 0.2, state: .underAroused, timestamp: Date()), context: nil)
            var a = base; a.tensionScore = 120
            T.expectThrows("score > 100") { try a.validate() }
            var b = base; b.confidence = -0.1
            T.expectThrows("confidence < 0") { try b.validate() }
            var c = base; c.isMedicalDiagnosis = true
            T.expectThrows("diagnosis true") { try c.validate() }
        }
        T.test("状態コードの対応が全ケースで可逆") {
            for s in MindState.allCases { T.expectEqual(MindStateCode(s).domain, s) }
            for s in [MindDataSource.mock, .watchLive, .healthKit, .unavailable] { T.expectEqual(DataSourceCode(s).domain, s) }
        }
        T.test("グラフィック入力は範囲外を clamp") {
            var dto = GraphicInputDTO(input: GraphicInput(score: 50, confidence: 0.5, state: .optimalTension))
            dto.score = 140; dto.confidence = 3
            T.expectEqual(dto.domainInput.score, 100)
            T.expectEqual(dto.domainInput.confidence, 1)
        }
    }

    // MARK: - セッション

    static func makeSnapshot(score: Double, hr: Double?, hrv: Double?, mock: Bool, source: MindDataSource? = nil) -> GuideSnapshot {
        GuideSnapshot(timestamp: Date(timeIntervalSince1970: 1_761_600_000.25), score: score, confidence: 0.75,
                      state: MindState.from(score: score), heartRate: hr, hrv: hrv, isMockData: mock,
                      heartRateSampleDate: hr == nil ? nil : Date(timeIntervalSince1970: 1_761_599_990),
                      hrvSampleDate: nil, dataSource: source)
    }

    static func makeRecord(mock: Bool = false, memo: String? = nil) -> GuideSessionRecord {
        GuideSessionRecord(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 1_761_600_000.25), scene: .interview,
            exercise: .breathing478, durationSeconds: 180,
            before: makeSnapshot(score: 72, hr: 96, hrv: nil, mock: mock, source: mock ? .mock : .watchLive),
            after: makeSnapshot(score: 48, hr: 84, hrv: 38.2, mock: mock, source: mock ? .mock : .watchLive),
            hrvUpdated: true, emotionMemo: memo, selfReportBefore: .significantTension, selfReportAfter: .slightTension,
            aiInsightTitle: "落ち着きが戻りつつあります", aiInsightSummary: "要約", aiInsightRecommendation: "推奨",
            localAIVersion: "local-1.1")
    }

    static func session() {
        T.test("セッション記録の往復（全フィールド）") {
            let r = makeRecord(memo: "少し楽になった")
            let data = try MindWaveContract.makeEncoder().encode(GuideSessionRecordDTO(record: r))
            let dto = try MindWaveContract.makeDecoder().decode(GuideSessionRecordDTO.self, from: data)
            guard let back = dto.domainRecord else { return T.fail("domain conversion failed") }
            T.expectEqual(back.id, r.id)
            T.expect(T.sameInstant(back.startedAt, r.startedAt), "startedAt")
            T.expectEqual(back.scene, r.scene)
            T.expectEqual(back.exercise, r.exercise)
            T.expectEqual(back.durationSeconds, 180)
            T.expectEqual(back.before.heartRate, 96)
            T.expect(back.before.hrv == nil, "before hrv nil preserved")
            T.expectEqual(back.after?.hrv, 38.2)
            T.expectEqual(back.after?.dataSource, .watchLive)
            T.expectEqual(back.emotionMemo, "少し楽になった")
            T.expectEqual(back.selfReportBefore, .significantTension)
            T.expectEqual(back.aiInsightTitle, r.aiInsightTitle)
            T.expectEqual(back.localAIVersion, "local-1.1")
            T.expect(!dto.containsMockData, "real record")
        }
        T.test("Mock を含む記録を判別できる") {
            T.expect(GuideSessionRecordDTO(record: makeRecord(mock: true)).containsMockData, "mock record")
        }
        T.test("AIインサイトなし・after なしの記録") {
            var r = makeRecord()
            r = GuideSessionRecord(id: r.id, startedAt: r.startedAt, scene: .daily, exercise: .box, durationSeconds: 60,
                                   before: r.before, after: nil, hrvUpdated: false)
            let dto = GuideSessionRecordDTO(record: r)
            T.expect(dto.aiInsight == nil, "no insight object")
            let json = String(data: try MindWaveContract.makeEncoder().encode(dto), encoding: .utf8)!
            let back = try MindWaveContract.makeDecoder().decode(GuideSessionRecordDTO.self, from: Data(json.utf8))
            T.expect(back.after == nil, "after nil")
            T.expect(back.domainRecord != nil, "convertible")
        }
        T.test("未知の場面・エクササイズは domainRecord=nil（クラッシュしない）") {
            var dto = GuideSessionRecordDTO(record: makeRecord())
            dto.scene = "moon_landing"
            T.expect(dto.domainRecord == nil, "unknown scene")
        }
        T.test("履歴文書: 壊れた1件を読み飛ばして残りを読む") {
            let good = GuideSessionRecordDTO(record: makeRecord())
            let goodJSON = String(data: try MindWaveContract.makeEncoder().encode(good), encoding: .utf8)!
            let json = #"{"schema_version":1,"saved_at":"2026-10-28T00:00:00.000Z","records":[\#(goodJSON),{"id":"broken"},\#(goodJSON)]}"#
            let doc = try MindWaveContract.makeDecoder().decode(GuideHistoryDocument.self, from: Data(json.utf8))
            T.expectEqual(doc.records.count, 2)
            T.expectEqual(doc.skippedRecordCount, 1)
        }
        T.test("履歴文書: 未来の schema_version は拒否") {
            let json = #"{"schema_version":9,"saved_at":"2026-10-28T00:00:00.000Z","records":[]}"#
            T.expectThrows("future schema") {
                _ = try MindWaveContract.makeDecoder().decode(GuideHistoryDocument.self, from: Data(json.utf8))
            }
        }
    }

    // MARK: - Insight

    static func makeInsightResponse(id: UUID, title: String = "呼吸でペースが整いました") -> InsightResponseDTO {
        InsightResponseDTO(
            schemaVersion: 1, requestId: id, provider: "openai", model: "test-model", generatedAt: Date(),
            insight: InsightBodyDTO(title: title, summary: "ガイド後に心拍が下がりました。", analysis: "面接前の場面で4-7-8呼吸を3分行いました。",
                                    recommendation: "本番5分前にもう1セット試してください。", nextAction: "次は再測定まで行いましょう。",
                                    caution: "これは医療的な診断ではなく、セルフケアの参考情報です。",
                                    confidenceLabel: "確からしさ: 中", tone: .focus))
    }

    static func insight() {
        T.test("リクエストに禁止データ（メモ・日時・HRV実数値）が含まれない") {
            let req = InsightRequestDTO(
                requestId: UUID(), consent: InsightConsentDTO(externalAIConsented: true, consentVersion: 1),
                session: InsightSessionSummaryDTO(
                    scene: "interview", exercise: "breathing478", durationSeconds: 180, completed: true,
                    before: InsightMeasurementSummaryDTO(state: .overTense, score: 72, heartRateBpm: 96),
                    after: InsightMeasurementSummaryDTO(state: .optimalTension, score: 48, heartRateBpm: nil),
                    hrvTrend: .up, selfReportBefore: 2, selfReportAfter: nil, confidence: 0.8))
            let json = String(data: try MindWaveContract.makeEncoder().encode(req), encoding: .utf8)!
            for banned in ["memo", "started_at", "hrv_sdnn_ms", "email", "name", "device"] {
                T.expect(!json.contains(banned), "request must not contain \(banned)")
            }
            T.expect(json.contains(#""heart_rate_bpm":null"#), "after hr null explicit")
            T.expect(json.contains(#""self_report_after":null"#), "self report null explicit")
        }
        T.test("正常なレスポンスは検証を通る（免責文の『診断ではなく』は許可）") {
            let id = UUID()
            let r = makeInsightResponse(id: id)
            let data = try MindWaveContract.makeEncoder().encode(r)
            let back = try MindWaveContract.makeDecoder().decode(InsightResponseDTO.self, from: data)
            try InsightValidation.validate(back, expectedRequestId: id)
        }
        T.test("レスポンス検証: request_id 不一致・禁止表現・長さ超過・空欄") {
            let id = UUID()
            T.expectThrows("id mismatch") { try InsightValidation.validate(makeInsightResponse(id: UUID()), expectedRequestId: id) }
            T.expectThrows("prohibited") { try InsightValidation.validate(makeInsightResponse(id: id, title: "自律神経が乱れています"), expectedRequestId: id) }
            T.expectThrows("too long") { try InsightValidation.validate(makeInsightResponse(id: id, title: String(repeating: "あ", count: 41)), expectedRequestId: id) }
            T.expectThrows("empty") { try InsightValidation.validate(makeInsightResponse(id: id, title: "  "), expectedRequestId: id) }
        }
    }

    // MARK: - ドキュメントの例と一致するか

    static func golden() {
        T.test("DATA_CONTRACTS.md の計測サンプル例を読める") {
            let json = """
            {"schema_version":1,"source":"watch_live","is_mock":false,"measured_at":"2026-10-28T04:35:12.123Z",
             "heart_rate_bpm":78,"hrv_sdnn_ms":null,"heart_rate_measured_at":"2026-10-28T04:35:12.123Z",
             "hrv_measured_at":null,"mock_score":null}
            """
            let dto = try MindWaveContract.makeDecoder().decode(MeasurementSampleDTO.self, from: Data(json.utf8))
            try dto.validate()
            T.expectEqual(dto.heartRateBpm, 78)
        }
        T.test("DATA_CONTRACTS.md のインサイト応答例を読める") {
            let json = """
            {"schema_version":1,"request_id":"6F1C2D3E-4B5A-4C6D-8E7F-9A0B1C2D3E4F","provider":"openai","model":"gpt-4o-mini",
             "generated_at":"2026-10-28T04:40:00.000Z",
             "insight":{"title":"呼吸でペースが整いました","summary":"ガイド後に心拍が下がりました。",
              "analysis":"面接前の場面で4-7-8呼吸を3分行い、状態が高緊張から中間域へ移りました。",
              "recommendation":"本番の5分前にもう1セット行うと落ち着いて臨めます。","next_action":"次回は再測定まで行い変化を記録しましょう。",
              "caution":"これは医療的な診断ではなく、セルフケアの参考情報です。","confidence_label":"確からしさ: 中","tone":"focus"}}
            """
            let dto = try MindWaveContract.makeDecoder().decode(InsightResponseDTO.self, from: Data(json.utf8))
            try InsightValidation.validate(dto, expectedRequestId: UUID(uuidString: "6F1C2D3E-4B5A-4C6D-8E7F-9A0B1C2D3E4F")!)
        }
    }
}
