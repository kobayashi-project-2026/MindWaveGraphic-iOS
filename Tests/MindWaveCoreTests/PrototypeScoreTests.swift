// PrototypeScoreTests.swift
// 主観評価＋HR・SDNN の試作スコア（subjective_hr_sdnn_prototype_v1）。ケース A〜J（2026-11-11 の指定）

import Foundation

enum PrototypeScoreTests {
    typealias T = TestHarness
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func input(s0: Double? = 50, hr0: Double? = 70, hr: Double? = 80, sd0: Double? = 50, sd: Double? = 45,
                      hrAt: TimeInterval = 30, sdAt: TimeInterval = 30, now: TimeInterval = 40) -> PrototypeTensionInput {
        PrototypeTensionInput(subjectiveBaseline: s0,
                              baselineHR: hr0.map { TimedReading(value: $0, measuredAt: t0) },
                              currentHR: hr.map { TimedReading(value: $0, measuredAt: t0.addingTimeInterval(hrAt)) },
                              baselineSDNN: sd0.map { TimedReading(value: $0, measuredAt: t0) },
                              currentSDNN: sd.map { TimedReading(value: $0, measuredAt: t0.addingTimeInterval(sdAt)) },
                              now: t0.addingTimeInterval(now))
    }

    static func run() {
        T.suite("試作スコア（主観評価＋HR・SDNN）")
        T.test("ケースA: S0=50, HR 70→80, SDNN 50→45 → 60.55（係数 0.77 / 0.57）") {
            let r = PrototypeTensionScore.calculate(input())
            T.expect(abs((r.score ?? -1) - 60.55) < 1e-9, "score=\(String(describing: r.score))")
            T.expectEqual(r.status, .complete)
            T.expectEqual(r.model.rawValue, "subjective_hr_sdnn_prototype_v1")
            T.expect(abs((r.hrTerm ?? 0) - 7.7) < 1e-9 && abs((r.sdnnTerm ?? 0) - 2.85) < 1e-9, "terms")
            T.expectEqual(PrototypeTensionScore.hrCoefficient, 0.77)
            T.expectEqual(PrototypeTensionScore.sdnnCoefficient, 0.57)
        }
        T.test("ケースB: HR・SDNN が初期値から変わらなければ S(t)=S0") {
            T.expectEqual(PrototypeTensionScore.calculate(input(s0: 37, hr: 70, sd: 50)).score, 37)
        }
        T.test("ケースC・D: 上限 100・下限 0") {
            T.expectEqual(PrototypeTensionScore.calculate(input(s0: 95, hr: 120, sd: 20)).score, 100)
            T.expectEqual(PrototypeTensionScore.calculate(input(s0: 5, hr: 55, sd: 90)).score, 0)
        }
        T.test("ケースE: HR 欠損時は HR を補完しない（SDNN だけの部分情報）") {
            let r = PrototypeTensionScore.calculate(input(hr: nil))
            T.expect(r.hrTerm == nil, "HR の項なし")
            T.expectEqual(r.status, .partialSDNNOnly)
            T.expect(abs((r.score ?? -1) - 52.85) < 1e-9, "50 + 2.85")
            T.expect(r.excluded.contains("hr_missing"), "理由")
        }
        T.test("ケースF: SDNN 欠損時は SDNN を補完しない（HR だけの部分情報）。両方なしは本人の評価のみ") {
            let r = PrototypeTensionScore.calculate(input(sd: nil))
            T.expect(r.sdnnTerm == nil, "SDNN の項なし")
            T.expectEqual(r.status, .partialHROnly)
            T.expect(abs((r.score ?? -1) - 57.7) < 1e-9, "50 + 7.7")
            let none = PrototypeTensionScore.calculate(input(hr0: nil, hr: nil, sd0: nil, sd: nil))
            T.expectEqual(none.status, .subjectiveOnly)
            T.expectEqual(none.score, 50)
        }
        T.test("ケースG: S0 未設定ではスコアを確定しない（0 にもしない）") {
            let r = PrototypeTensionScore.calculate(input(s0: nil))
            T.expect(r.score == nil, "nil")
            T.expectEqual(r.status, .unavailable)
            T.expect(PrototypeTensionScore.calculate(input(s0: 120)).score == nil, "範囲外の S0 も確定しない")
        }
        T.test("ケースH: 古い値・基準より前の値を最新値として使わない。異常値は除外") {
            let stale = PrototypeTensionScore.calculate(input(hrAt: 30, now: 30 + 61))
            T.expect(stale.hrTerm == nil && stale.excluded.contains("hr_stale"), "HR が 60 秒より古い")
            T.expect(stale.sdnnTerm != nil, "SDNN は 600 秒以内なので使う")
            let older = PrototypeTensionScore.calculate(input(hrAt: -10, now: 20))
            T.expect(older.hrTerm == nil && older.excluded.contains("hr_older_than_baseline"), "基準より前")
            let bad = PrototypeTensionScore.calculate(input(hr: 400, sd: 0))
            T.expect(bad.excluded.contains("hr_invalid") && bad.excluded.contains("sdnn_invalid"), "異常値")
            T.expectEqual(bad.status, .subjectiveOnly)
        }
        T.test("ケースI: 過去の記録の互換性（記録の形式は変えず、従来の方式として識別できる）") {
            T.expectEqual(TensionScoreModel(rawValue: "stress_score_calculator_v1"), .legacyStressScoreV1)
            T.expect(TensionScoreModel.legacyStressScoreV1 != PrototypeTensionScore.model, "別の方式")
        }
        T.test("ケースJ: 前後で計算方式が違うときは数値を直接比べず、違いを明示する") {
            let diff = TensionScoreComparison.describe(before: (60, .legacyStressScoreV1), after: (40, .subjectiveHRSDNNPrototypeV1))
            T.expect(diff.contains("計算方式が違う"), diff)
            let same = TensionScoreComparison.describe(before: (60, .subjectiveHRSDNNPrototypeV1), after: (48, .subjectiveHRSDNNPrototypeV1))
            T.expect(same.contains("60 → 48") && same.contains("気持ちの変化と同じとは限りません"), same)
            T.expect(TensionScoreComparison.describe(before: (nil, .subjectiveHRSDNNPrototypeV1), after: (40, .subjectiveHRSDNNPrototypeV1)).contains("比較できません"), "欠損")
        }
        T.test("結果画面の入力: ガイド前を基準・ガイド後を時刻 t。HRV がない記録では SDNN を補わない（例: S0=75, HR 115→101 → 64.22・HR のみ）") {
            let t = Date()
            let before = GuideSnapshot(timestamp: t, score: 72, confidence: 0.8, state: .overTense, heartRate: 115, hrv: nil,
                                       isMockData: false, heartRateSampleDate: t, hrvSampleDate: nil)
            let after = GuideSnapshot(timestamp: t.addingTimeInterval(90), score: 52, confidence: 0.8, state: .optimalTension, heartRate: 101, hrv: nil,
                                      isMockData: false, heartRateSampleDate: t.addingTimeInterval(85), hrvSampleDate: nil)
            let input = PrototypeScoreInputBuilder.make(s0: 75, before: before, after: after)
            T.expect(input.baselineSDNN == nil && input.currentSDNN == nil, "SDNN は作らない")
            let r = PrototypeTensionScore.calculate(input)
            T.expect(abs((r.score ?? -1) - 64.22) < 1e-9, "\(String(describing: r.score))")
            T.expectEqual(r.status, .partialHROnly)
            T.expect(PrototypeTensionScore.calculate(PrototypeScoreInputBuilder.make(s0: 75, before: before, after: nil)).hrTerm == nil, "ガイド後がなければ補正なし")
            T.expectEqual(SubjectiveScale.from(.significantTension), 75)
            T.expect(SubjectiveScale.from(nil) == nil, "未回答は nil")
        }
        T.test("JSON の evaluation: 欠損は null・model_version・score_status を出す") {
            let ok = String(data: try! JSONEncoder().encode(TensionEvaluationDTO(PrototypeTensionScore.calculate(input()))), encoding: .utf8)!
            T.expect(ok.contains("\"model_version\":\"subjective_hr_sdnn_prototype_v1\"") && ok.contains("\"stress_score\":60.55"), ok)
            let none = String(data: try! JSONEncoder().encode(TensionEvaluationDTO(PrototypeTensionScore.calculate(input(s0: nil)))), encoding: .utf8)!
            T.expect(none.contains("\"stress_score\":null") && none.contains("\"score_status\":\"unavailable\""), none)
        }
        acuteEngineRegression()
        acuteViewModelRegression()
    }
}

// MARK: - HR-only acute session regression
// The existing prototype tests above deliberately remain unchanged. The acute session is a
// separate score contract: exact subjective anchor + fixed experimental HR coefficient; no raw SDNN.
extension PrototypeScoreTests {
    static func acuteEngineRegression() {
        T.suite("急性緊張セッション / 実測HR平均と本人評価")
        func date(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
        func ingest(_ engine: MWAcuteTensionEngine, hr: Double, seconds: [TimeInterval]) {
            for second in seconds {
                T.expect(engine.ingestHeartRate(hr, measuredAt: date(second), receivedAt: date(second)), "実測HRを受理")
            }
        }
        T.test("初期0・10は0・100、端数の本人評価も丸めず10倍する") {
            for rating in [0.0, 4.0, 10.0, 100.0 / 60.0, 500.0 / 60.0] {
                let engine = MWAcuteTensionEngine()
                T.expect(engine.begin(tensionRating: rating, exercisedRecently: false, at: t0), "開始")
                T.expectEqual(engine.evaluate(at: t0)?.score, 10 * rating)
                T.expectEqual(engine.evaluate(at: t0)?.status, .awaitingBaseline)
            }
        }
        T.test("最初の30秒が完了するまで基準を確定しない。30秒ちょうどの受信は不要") {
            let engine = MWAcuteTensionEngine()
            engine.begin(tensionRating: 4, exercisedRecently: false, at: t0)
            ingest(engine, hr: 80, seconds: [0, 10, 20])
            T.expectEqual(engine.evaluate(at: date(29))?.status, .awaitingBaseline)
            T.expectEqual(engine.evaluate(at: date(29))?.score, 40)
            let result = engine.evaluate(at: date(30))
            T.expectEqual(result?.baselineHeartRate, 80)
            T.expectEqual(result?.score, 40)
        }
        T.test("HR 80→100では40 + 指定係数×20。生のSを出力し追加変換しない") {
            let engine = MWAcuteTensionEngine()
            engine.begin(tensionRating: 4, exercisedRecently: false, at: t0)
            ingest(engine, hr: 80, seconds: [0, 10, 20])
            _ = engine.evaluate(at: date(30))
            ingest(engine, hr: 100, seconds: [40, 50, 60, 70])
            guard let result = engine.evaluate(at: date(70)) else { return T.fail("結果なし") }
            T.expect(abs(result.score - (40 + 0.5772094747906776 * 20)) < 1e-10, "係数とHR差分")
            T.expectEqual(result.baselineHeartRate, 80)
            T.expectEqual(result.currentMeanHeartRate, 100)
            T.expectEqual(result.status, .liveExperimental)
            T.expectEqual(result.hrAdjustmentPoints, result.score - 40)
        }
        T.test("開始30秒以内のデータ不足を後のデータで置換しない") {
            let engine = MWAcuteTensionEngine()
            engine.begin(tensionRating: 4, exercisedRecently: false, at: t0)
            ingest(engine, hr: 100, seconds: [40, 50, 60])
            T.expectEqual(engine.evaluate(at: date(60))?.status, .awaitingBaseline)
            T.expect(engine.evaluate(at: date(60))?.baselineHeartRate == nil, "開始時基準なし")
            T.expectEqual(engine.evaluate(at: date(60))?.score, 40)
        }
        T.test("同じ実測時刻の再受信や短時間に偏った3件は30秒基準を作れない") {
            let duplicate = MWAcuteTensionEngine()
            duplicate.begin(tensionRating: 4, exercisedRecently: false, at: t0)
            T.expect(duplicate.ingestHeartRate(80, measuredAt: t0, receivedAt: t0), "初回")
            for _ in 0..<3 {
                T.expect(!duplicate.ingestHeartRate(120, measuredAt: t0, receivedAt: date(10)), "再受信を除外")
            }
            T.expect(duplicate.evaluate(at: date(30))?.baselineHeartRate == nil, "件数を水増ししない")
            let clustered = MWAcuteTensionEngine()
            clustered.begin(tensionRating: 4, exercisedRecently: false, at: t0)
            ingest(clustered, hr: 80, seconds: [0, 1, 2])
            T.expect(clustered.evaluate(at: date(30))?.baselineHeartRate == nil, "最低15秒の広がりが必要")
        }
        T.test("最新HRが15秒を超えたら最後のスコアを保持し、画面更新で鮮度を更新しない") {
            let engine = MWAcuteTensionEngine()
            engine.begin(tensionRating: 4, exercisedRecently: false, at: t0)
            ingest(engine, hr: 80, seconds: [0, 10, 20])
            _ = engine.evaluate(at: date(30))
            ingest(engine, hr: 100, seconds: [65])
            let live = engine.evaluate(at: date(65))!
            T.expectEqual(engine.evaluate(at: date(80))?.status, .liveExperimental)
            for second in [81.0, 100, 200] {
                let stale = engine.evaluate(at: date(second))
                T.expectEqual(stale?.status, .staleHR)
                T.expectEqual(stale?.score, live.score)
            }
        }
        T.test("未来・開始前・30秒より古いHRとNaN/無限大/範囲外を補正に入れない") {
            let engine = MWAcuteTensionEngine()
            engine.begin(tensionRating: 4, exercisedRecently: false, at: t0)
            T.expect(!engine.ingestHeartRate(80, measuredAt: date(1), receivedAt: t0), "未来")
            T.expect(!engine.ingestHeartRate(80, measuredAt: date(-1), receivedAt: t0), "開始前")
            T.expect(!engine.ingestHeartRate(80, measuredAt: t0, receivedAt: date(31)), "古い試料")
            for hr in [Double.nan, Double.infinity, 0, 34, 221] {
                T.expect(!engine.ingestHeartRate(hr, measuredAt: t0, receivedAt: t0), "異常HR")
            }
            T.expectEqual(engine.evaluate(at: date(30))?.score, 40)
        }
        T.test("WatchとHealthKitの異なる取得経路を同じ平均へ混ぜない") {
            let engine = MWAcuteTensionEngine()
            engine.begin(tensionRating: 4, exercisedRecently: false, at: t0)
            T.expect(engine.ingestHeartRate(80, measuredAt: t0, source: "watchLive", receivedAt: t0), "Watch")
            T.expect(!engine.ingestHeartRate(200, measuredAt: date(10), source: "healthKit:watch", receivedAt: date(10)), "経路変更を除外")
            T.expectEqual(engine.activeSource, "watchLive")
            T.expect(engine.evaluate(at: date(30))?.baselineHeartRate == nil, "二重計上しない")
        }
        T.test("開始時または途中の運動申告は生体補正を停止して本人評価へ戻す") {
            let engine = MWAcuteTensionEngine()
            engine.begin(tensionRating: 4, exercisedRecently: false, at: t0)
            ingest(engine, hr: 80, seconds: [0, 10, 20])
            _ = engine.evaluate(at: date(30))
            ingest(engine, hr: 100, seconds: [65])
            T.expect((engine.evaluate(at: date(65))?.score ?? 0) > 40, "補正前の変化")
            engine.pauseForExercise()
            T.expectEqual(engine.evaluate(at: date(65))?.score, 40)
            T.expectEqual(engine.evaluate(at: date(65))?.status, .exerciseExcluded)
            engine.begin(tensionRating: 0, exercisedRecently: true, at: t0)
            T.expectEqual(engine.evaluate(at: t0)?.score, 0)
            T.expectEqual(engine.evaluate(at: t0)?.status, .exerciseExcluded)
        }
        T.test("0〜100へ制限し、終了・再開始で前回のHRと基準を持ち越さない") {
            for (baseline, current, expected) in [(35.0, 220.0, 100.0), (220.0, 35.0, 0.0)] {
                let engine = MWAcuteTensionEngine()
                engine.begin(tensionRating: 4, exercisedRecently: false, at: t0)
                ingest(engine, hr: baseline, seconds: [0, 10, 20])
                _ = engine.evaluate(at: date(30))
                ingest(engine, hr: current, seconds: [65])
                T.expectEqual(engine.evaluate(at: date(65))?.score, expected)
                engine.finish()
                T.expect(engine.evaluate(at: date(65)) == nil && !engine.hasActiveSession, "終了")
                engine.begin(tensionRating: 6, exercisedRecently: false, at: date(70))
                T.expectEqual(engine.evaluate(at: date(70))?.score, 60)
                T.expect(engine.evaluate(at: date(70))?.baselineHeartRate == nil, "前回基準なし")
                T.expect(engine.activeSource == nil, "前回の取得元なし")
            }
        }
    }

    static func acuteViewModelRegression() {
        T.suite("急性緊張セッション / ViewModel → GraphicInput")
        func makeVM(_ name: String) -> MindWaveViewModel {
            MindWaveViewModel(baselineStore: PersonalBaselineStore(defaults: T.freshDefaults("acute-" + name)))
        }
        func sample(_ hr: Double, second: TimeInterval, id: String? = nil,
                    kind: HealthMetricResultKind = .discreteSample) -> HealthMetricFetchResult {
            let at = t0.addingTimeInterval(second)
            return HealthMetricFetchResult(value: hr, source: "急性テスト", message: "実測試料",
                sampleDate: at, sampleIdentifier: id ?? "acute-\(second)", sampleEndDate: at,
                sourceName: "Apple Watch", sourceBundleIdentifier: "test.watch", kind: kind)
        }
        func prepare(_ vm: MindWaveViewModel) {
            T.expect(vm.beginAcuteSession(tensionRating: 4, exercisedRecently: false, now: t0), "開始")
            vm.ingestRecentHealthKitHR([sample(80, second: 0), sample(80, second: 10), sample(80, second: 20)],
                                      now: t0.addingTimeInterval(30))
        }
        T.test("本人評価4→40、HR基準80→100のSがそのままGraphicInputへ届く") {
            let vm = makeVM("graphic")
            defer { vm.finishAcuteSession() }
            prepare(vm)
            T.expect(!vm.isMockMode && !vm.isUsingDemoData, "実測セッション")
            T.expectEqual(vm.graphicInput.score, 40)
            T.expectEqual(vm.acuteResult?.baselineHeartRate, 80)
            vm.ingestRecentHealthKitHR([sample(100, second: 65)], now: t0.addingTimeInterval(65))
            guard let result = vm.acuteResult else { return T.fail("急性スコアなし") }
            T.expect(abs(result.score - (40 + 0.5772094747906776 * 20)) < 1e-10, "生のS")
            T.expectEqual(vm.graphicInput.score, result.score)
            T.expectEqual(vm.lastAnalysisResult?.tensionScore, result.score)
            T.expectEqual(vm.graphicInput.state, MindState.from(score: result.score))
            T.expectEqual(vm.graphicInput.confidence, 0, "未検証のため精度を装わない")
        }
        T.test("SDNN観測で急性Sを変えず、SDNNの実測時刻を保存する") {
            let vm = makeVM("sdnn")
            defer { vm.finishAcuteSession() }
            prepare(vm)
            vm.ingestRecentHealthKitHR([sample(100, second: 65)], now: t0.addingTimeInterval(65))
            let before = vm.graphicInput.score
            let sdnnAt = Date().addingTimeInterval(-120)
            let sdnn = HealthMetricFetchResult(value: 55, source: "実測SDNN", message: "テスト",
                sampleDate: sdnnAt, sampleIdentifier: "acute-sdnn", sampleEndDate: sdnnAt,
                sourceName: "Apple Watch", sourceBundleIdentifier: "test.watch", kind: .discreteSample)
            vm.applyHRVObserverBatch(HRVObserverBatch(phase: .update, callbackDate: Date(),
                rawSampleCount: 1, acceptedResults: [sdnn], duplicateRejectedCount: 0,
                staleRejectedCount: 0, errorDescription: nil))
            vm.refreshAcuteScore(now: t0.addingTimeInterval(65))
            T.expectEqual(vm.graphicInput.score, before, "生SDNNを式へ足さない")
            T.expectEqual(vm.latestHRVSampleDate, sdnnAt, "表示更新時刻に置換しない")
        }
        T.test("セッション中のMock切替は拒否し、終了後は通常のMock操作へ戻る") {
            let vm = makeVM("mock")
            vm.setMockMode(true)
            vm.mockScore = 90
            vm.sendMockSample()
            prepare(vm)
            T.expectEqual(vm.graphicInput.score, 40)
            vm.setMockMode(true)
            vm.mockScore = 95
            vm.sendMockSample()
            T.expect(!vm.isMockMode && !vm.isUsingDemoData, "急性計測にデモを混入させない")
            T.expectEqual(vm.graphicInput.score, 40)
            vm.finishAcuteSession()
            vm.setMockMode(true)
            vm.sendMockSample()
            T.expect(vm.isMockMode && !vm.isAcuteSessionRunning, "終了後にMockを使用可能")
        }
        T.test("HealthKit同一時刻の再取得・未来試料・集計値は基準の件数を増やさない") {
            let vm = makeVM("invalid-hk")
            defer { vm.finishAcuteSession() }
            T.expect(vm.beginAcuteSession(tensionRating: 4, exercisedRecently: false, now: t0), "開始")
            let first = sample(80, second: 0)
            let aggregate = HealthMetricFetchResult(value: 120, source: "平均", message: "集計値",
                sampleDate: t0.addingTimeInterval(10), sampleIdentifier: nil, kind: .aggregateFallback)
            vm.ingestRecentHealthKitHR([first, first, sample(200, second: 31), aggregate], now: t0.addingTimeInterval(30))
            T.expect(vm.acuteResult?.baselineHeartRate == nil, "有効なのは1件だけ")
            T.expectEqual(vm.graphicInput.score, 40)
            T.expectEqual(vm.acuteResult?.status, .awaitingBaseline)
        }
        T.test("タイマーで古さを検出し最後のSを保持、運動で本人評価へ戻す") {
            let vm = makeVM("stale-exercise")
            defer { vm.finishAcuteSession() }
            prepare(vm)
            vm.ingestRecentHealthKitHR([sample(100, second: 65)], now: t0.addingTimeInterval(65))
            let live = vm.graphicInput.score
            vm.refreshAcuteScore(now: t0.addingTimeInterval(81))
            T.expectEqual(vm.acuteResult?.status, .staleHR)
            T.expectEqual(vm.graphicInput.score, live)
            vm.pauseAcuteCorrectionForExercise()
            vm.refreshAcuteScore(now: t0.addingTimeInterval(81))
            T.expectEqual(vm.graphicInput.score, 40)
            T.expectEqual(vm.acuteResult?.status, .exerciseExcluded)
        }
        T.test("Watchコールバックの実測HRも急性スコアへ接続し、終了後は停止する") {
            let vm = makeVM("watch")
            defer { vm.finishAcuteSession() }
            let start = Date().addingTimeInterval(-29)
            T.expect(vm.beginAcuteSession(tensionRating: 4, exercisedRecently: false, now: start), "開始")
            for offset in [0.0, 10, 20] {
                vm.applyWatchHeartRate(80, sampleDate: start.addingTimeInterval(offset))
            }
            vm.refreshAcuteScore(now: start.addingTimeInterval(30))
            T.expectEqual(vm.acuteResult?.baselineHeartRate, 80)
            vm.applyWatchHeartRate(100, sampleDate: Date())
            vm.refreshAcuteScore(now: start.addingTimeInterval(30))
            T.expect((vm.acuteResult?.score ?? 0) > 40, "Watchの変化が届く")
            T.expectEqual(vm.graphicInput.score, vm.acuteResult?.score)
            vm.finishAcuteSession()
            T.expect(!vm.isAcuteSessionRunning, "セッション終了")
            T.expect(vm.beginAcuteSession(tensionRating: 0, exercisedRecently: true), "センサーなしで再開始")
            T.expectEqual(vm.graphicInput.score, 0)
            T.expectEqual(vm.acuteResult?.status, .exerciseExcluded)
        }
        T.test("開始前からWatchライブ受信中ならHK先着でライブ経路を奪わない") {
            let vm = makeVM("watch-priority")
            defer { vm.finishAcuteSession() }
            let start = Date().addingTimeInterval(-10)
            vm.applyWatchHeartRate(80, sampleDate: start.addingTimeInterval(-1))
            vm.beginAcuteSession(tensionRating: 5, exercisedRecently: false, now: start)
            let hk = HealthMetricFetchResult(value: 90, source: "Watch", message: "HK先着",
                sampleDate: start, sampleIdentifier: "priority", sampleEndDate: start,
                sourceBundleIdentifier: "test.watch", kind: .discreteSample)
            vm.ingestRecentHealthKitHR([hk], now: start.addingTimeInterval(1))
            vm.applyWatchHeartRate(80, sampleDate: start.addingTimeInterval(2))
            T.expectEqual(vm.activeDataSource, .watchLive)
        }
        T.test("デモシナリオは急性計測の値を上書きせずMock解除時に実測SDNNを復元") {
            let vm = makeVM("demo-separation")
            defer { vm.finishAcuteSession() }
            let at = Date().addingTimeInterval(-10)
            let hrv = HealthMetricFetchResult(value: 47, source: "Watch", message: "実測SDNN",
                sampleDate: at, sampleIdentifier: "real-sdnn", sampleEndDate: at, kind: .discreteSample)
            vm.applyHRVObserverBatch(HRVObserverBatch(phase: .update, callbackDate: Date(),
                rawSampleCount: 1, acceptedResults: [hrv], duplicateRejectedCount: 0,
                staleRejectedCount: 0, errorDescription: nil))
            vm.setMockMode(true)
            vm.loadDemoScenario(index: 0)
            vm.setMockMode(false)
            T.expectEqual(vm.currentHRV, 47)
            T.expectEqual(vm.latestHRVSampleDate, at)
            T.expectEqual(vm.activeDataSource, .unavailable)
            T.expect(!vm.isUsingDemoData, "Mock OFF表示")
            vm.beginAcuteSession(tensionRating: 5, exercisedRecently: false)
            vm.loadDemoScenario(index: 1)
            T.expectEqual(vm.currentHRV, 47)
            T.expectEqual(vm.graphicInput.score, 50)
        }
    }
}
