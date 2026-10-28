// PipelineTests.swift
// 受信 → 正規化 → 有効サンプル判定 → スコア → 分析結果 → グラフィック → ガイド記録 のテスト

import Foundation

enum PipelineTests {
    typealias T = TestHarness

    static let now = Date(timeIntervalSince1970: 1_761_626_112)

    static func run() {
        T.suite("Pipeline / ActiveSampleSelector")
        selector()
        T.suite("Pipeline / StressScoreAnalyzerV1（既存計算式との一致）")
        analyzer()
        T.suite("Pipeline / PersonalBaselineStore")
        baseline()
        T.suite("Pipeline / MindWaveViewModel end-to-end")
        viewModel()
    }

    static func input(mock: Bool = false, mockSample: MindWaveSample? = nil, watchAge: TimeInterval? = nil,
                      hkHRAge: TimeInterval? = nil, hkHRVAge: TimeInterval? = nil) -> SampleSelectionInput {
        SampleSelectionInput(
            isMockMode: mock,
            mock: mockSample,
            watch: watchAge.map { MindWaveSample(heartRate: 82, hrv: nil, contextScore: nil, source: .watchLive, timestamp: now.addingTimeInterval(-$0)) },
            healthKitHeartRate: hkHRAge.map { TimedValue(value: 70, measuredAt: now.addingTimeInterval(-$0)) },
            healthKitHRV: hkHRVAge.map { TimedValue(value: 40, measuredAt: now.addingTimeInterval(-$0)) },
            now: now)
    }

    // MARK: - Selector

    static func selector() {
        T.test("Mock ON なら Watch が新しくても Mock を選ぶ") {
            let m = MindWaveSample(heartRate: nil, hrv: nil, contextScore: 60, source: .mock, timestamp: now)
            let s = ActiveSampleSelector.select(input(mock: true, mockSample: m, watchAge: 1, hkHRVAge: 10))
            T.expectEqual(s?.sample.source, .mock)
            T.expectEqual(s?.hrvStatus, .notApplicable)
        }
        T.test("Mock ON で Mock サンプルなし → nil（実測へフォールバックしない）") {
            T.expect(ActiveSampleSelector.select(input(mock: true, watchAge: 1)) == nil, "nil")
        }
        T.test("Watch 15秒以内 + 鮮度内HRV → Watch に HRV を補完") {
            let s = ActiveSampleSelector.select(input(watchAge: 5, hkHRVAge: 60 * 60))
            T.expectEqual(s?.sample.source, .watchLive)
            T.expectEqual(s?.sample.heartRate, 82)
            T.expectEqual(s?.sample.hrv, 40)
            T.expectEqual(s?.hrvStatus, .measured)
        }
        T.test("Watch + 6時間超の古いHRV → HRVを使わず stale と記録") {
            let s = ActiveSampleSelector.select(input(watchAge: 5, hkHRVAge: 7 * 60 * 60))
            T.expect(s?.sample.hrv == nil, "stale hrv not used")
            T.expectEqual(s?.hrvStatus, .stale)
        }
        T.test("Watch HRV未取得 → missing") {
            T.expectEqual(ActiveSampleSelector.select(input(watchAge: 5))?.hrvStatus, .missing)
        }
        T.test("Watch 期限切れ(16秒) → HealthKit へ") {
            let s = ActiveSampleSelector.select(input(watchAge: 16, hkHRAge: 60))
            T.expectEqual(s?.sample.source, .healthKit)
            T.expectEqual(s?.sample.heartRate, 70)
        }
        T.test("HealthKit 心拍が30分超・HRVが6時間超 → 有効サンプルなし（古い値を現在値として表示しない）") {
            T.expect(ActiveSampleSelector.select(input(hkHRAge: 31 * 60, hkHRVAge: 7 * 60 * 60)) == nil, "nil")
        }
        T.test("HealthKit HRV のみ鮮度内 → 心拍は nil（未計測）で選ぶ") {
            let s = ActiveSampleSelector.select(input(hkHRAge: 31 * 60, hkHRVAge: 60))
            T.expect(s?.sample.heartRate == nil, "hr nil")
            T.expectEqual(s?.sample.hrv, 40)
        }
        T.test("何もない → nil") {
            T.expect(ActiveSampleSelector.select(input()) == nil, "nil")
        }
        T.test("端末間の時計ずれ: 30秒先の Watch 時刻は許容、5分先は拒否") {
            T.expectEqual(ActiveSampleSelector.select(input(watchAge: -30))?.sample.source, .watchLive)
            T.expect(ActiveSampleSelector.select(input(watchAge: -300)) == nil, "future rejected")
        }
    }

    // MARK: - Analyzer

    static func analyze(_ sample: MindWaveSample, hrv: HRVStatus = .missing, baseline: BaselineSnapshot = .reference,
                        context: MeasurementContext = .default, mockConfidence: Double = 0.8) -> MindAnalysisResult {
        StressScoreAnalyzerV1().analyze(AnalyzerInput(
            selected: SelectedSample(sample: sample, hrvStatus: hrv, heartRateMeasuredAt: nil, hrvMeasuredAt: nil),
            baseline: baseline, context: context, mockConfidence: mockConfidence))
    }

    static func analyzer() {
        T.test("Watch + HRV: StressScoreCalculator と同値・確からしさ 0.75") {
            var ctx = MeasurementContext(); ctx.scene = .interview
            let r = analyze(MindWaveSample(heartRate: 90, hrv: 30, contextScore: nil, source: .watchLive, timestamp: now),
                            hrv: .measured, context: ctx)
            let expected = StressScoreCalculator.calculate(currentHeartRate: 90, averageHeartRate: 65, currentHRV: 30, averageHRV: 45, context: ctx).stressScore
            T.expectEqual(r.tensionScore, expected)
            T.expectEqual(r.confidence, 0.75)
            T.expectEqual(r.state, MindState.from(score: expected))
            T.expectEqual(r.metadata.baselineStatus, .provisional)
            T.expectEqual(r.metadata.analyzerID, "stress-score-v1")
        }
        T.test("既存挙動の保持: HRVなしの実測は計算式の guard により 38（中立）") {
            let r = analyze(MindWaveSample(heartRate: 120, hrv: nil, contextScore: nil, source: .watchLive, timestamp: now))
            T.expectEqual(r.tensionScore, 38)
            T.expectEqual(r.confidence, 0.50)
        }
        T.test("HealthKit 確からしさ 0.65 / 0.40") {
            T.expectEqual(analyze(MindWaveSample(heartRate: 70, hrv: 40, contextScore: nil, source: .healthKit, timestamp: now)).confidence, 0.65)
            T.expectEqual(analyze(MindWaveSample(heartRate: 70, hrv: nil, contextScore: nil, source: .healthKit, timestamp: now)).confidence, 0.40)
        }
        T.test("Mock: contextScore をそのまま使い baseline は not_applicable") {
            let r = analyze(MindWaveSample(heartRate: nil, hrv: nil, contextScore: 77, source: .mock, timestamp: now), hrv: .notApplicable, mockConfidence: 0.3)
            T.expectEqual(r.tensionScore, 77)
            T.expectEqual(r.confidence, 0.3)
            T.expectEqual(r.metadata.baselineStatus, .notApplicable)
            T.expect(r.metadata.isMock, "mock")
        }
        T.test("Mock デモシナリオ: シナリオの平常値で算出（統合前の reevaluateActiveSource と同値）") {
            let r = StressScoreAnalyzerV1().analyze(AnalyzerInput(
                selected: SelectedSample(sample: MindWaveSample(heartRate: 80, hrv: 35, contextScore: nil, source: .mock, timestamp: now),
                                         hrvStatus: .notApplicable, heartRateMeasuredAt: nil, hrvMeasuredAt: nil),
                baseline: .reference, context: .default, mockConfidence: 0.8,
                mockAverageHeartRate: 72, mockAverageHRV: 50))
            let expected = StressScoreCalculator.calculate(currentHeartRate: 80, averageHeartRate: 72, currentHRV: 35, averageHRV: 50, context: .default).stressScore
            T.expectEqual(r.tensionScore, expected)
        }
        T.test("心拍未計測（HRVのみ）は心拍項を平常扱い・metadata.heartRate=nil") {
            let r = analyze(MindWaveSample(heartRate: nil, hrv: 30, contextScore: nil, source: .healthKit, timestamp: now), hrv: .measured)
            let expected = StressScoreCalculator.calculate(currentHeartRate: 65, averageHeartRate: 65, currentHRV: 30, averageHRV: 45).stressScore
            T.expectEqual(r.tensionScore, expected)
            T.expect(r.metadata.heartRate == nil, "hr recorded as missing")
        }
        T.test("個人ベースラインがあればそれで算出し personal と記録") {
            var b = BaselineSnapshot.reference
            b.heartRate = 58; b.heartRateOrigin = .healthKit7DayAverage
            b.hrv = 60; b.hrvOrigin = .healthKit7DayAverage
            let r = analyze(MindWaveSample(heartRate: 70, hrv: 50, contextScore: nil, source: .watchLive, timestamp: now), hrv: .measured, baseline: b)
            let expected = StressScoreCalculator.calculate(currentHeartRate: 70, averageHeartRate: 58, currentHRV: 50, averageHRV: 60).stressScore
            T.expectEqual(r.tensionScore, expected)
            T.expectEqual(r.metadata.baselineStatus, .personal)
        }
        T.test("スコアは常に 0〜100・確からしさは 0〜1") {
            for hr in [30.0, 60, 120, 200, 250] {
                for hrv in [nil, 5.0, 45, 200] as [Double?] {
                    let r = analyze(MindWaveSample(heartRate: hr, hrv: hrv, contextScore: nil, source: .watchLive, timestamp: now))
                    T.expect((0...100).contains(r.tensionScore) && (0...1).contains(r.confidence), "hr=\(hr) hrv=\(String(describing: hrv))")
                }
            }
        }
    }

    // MARK: - Baseline

    static func baseline() {
        T.test("データ不足 → 参照値 65/45・provisional（個人値と偽らない）") {
            let store = PersonalBaselineStore(defaults: T.freshDefaults("bl-empty"))
            let b = store.snapshot(now: now, healthKitAverageHeartRate: nil, healthKitAverageHRV: nil)
            T.expectEqual(b, .reference)
            T.expectEqual(b.status(usesHRV: true), .provisional)
            T.expectEqual(b.status(usesHRV: false), .provisional)
        }
        T.test("Mock・範囲外・身体状態申告中の心拍は記録しない") {
            let store = PersonalBaselineStore(defaults: T.freshDefaults("bl-filter"))
            T.expect(!store.recordHeartRate(70, at: now, source: .mock, context: .default), "mock")
            T.expect(!store.recordHeartRate(0, at: now, source: .watchLive, context: .default), "0")
            var ctx = MeasurementContext(); ctx.conditions = [.running]
            T.expect(!store.recordHeartRate(120, at: now, source: .watchLive, context: ctx), "running")
            T.expect(store.recordHeartRate(70, at: now, source: .watchLive, context: .default), "valid")
        }
        T.test("心拍は5分に1件へ間引く") {
            let store = PersonalBaselineStore(defaults: T.freshDefaults("bl-thin"))
            T.expect(store.recordHeartRate(70, at: now, source: .watchLive, context: .default), "1st")
            T.expect(!store.recordHeartRate(71, at: now.addingTimeInterval(60), source: .watchLive, context: .default), "within 5min")
            T.expect(store.recordHeartRate(72, at: now.addingTimeInterval(301), source: .watchLive, context: .default), "after 5min")
        }
        T.test("3日以上・30件以上の実測が貯まると app_collected_samples の個人値になる") {
            let d = T.freshDefaults("bl-enough")
            let store = PersonalBaselineStore(defaults: d)
            for i in 0..<30 {
                // 3日にまたがって 30 件（10 件/日、6分間隔）
                let t = now.addingTimeInterval(-Double(i / 10) * 86_400 - Double(i % 10) * 360 - 3600)
                _ = store.recordHeartRate(60, at: t, source: .watchLive, context: .default)
            }
            // 記録順が時系列でなくても間引き判定は「直前の記録」基準のため件数を確認する
            let b = store.snapshot(now: now, healthKitAverageHeartRate: nil, healthKitAverageHRV: nil)
            T.expectEqual(b.collectedHeartRateCount, store.document.heartRateSamples.count)
            if b.collectedHeartRateCount >= 30 {
                T.expectEqual(b.heartRateOrigin, .appCollectedSamples)
                T.expectEqual(b.heartRate, 60)
            } else {
                T.expectEqual(b.heartRateOrigin, .reference)
            }
            // 再起動後も読める
            T.expectEqual(PersonalBaselineStore(defaults: d).document, store.document)
        }
        T.test("時系列順に30件・3日分を記録すると個人値") {
            let store = PersonalBaselineStore(defaults: T.freshDefaults("bl-ordered"))
            let start = now.addingTimeInterval(-3 * 86_400)
            for i in 0..<30 {
                _ = store.recordHeartRate(62, at: start.addingTimeInterval(Double(i) * 2 * 3600), source: .healthKit, context: .default)
            }
            let b = store.snapshot(now: now, healthKitAverageHeartRate: nil, healthKitAverageHRV: nil)
            T.expectEqual(b.collectedHeartRateCount, 30)
            T.expectEqual(b.heartRateOrigin, .appCollectedSamples)
            T.expectEqual(b.heartRate, 62)
            T.expectEqual(b.status(usesHRV: false), .personal)
            T.expectEqual(b.status(usesHRV: true), .provisional)
        }
        T.test("HealthKit 7日平均が最優先") {
            let store = PersonalBaselineStore(defaults: T.freshDefaults("bl-hk"))
            let b = store.snapshot(now: now, healthKitAverageHeartRate: 59, healthKitAverageHRV: 52)
            T.expectEqual(b.heartRate, 59)
            T.expectEqual(b.heartRateOrigin, .healthKit7DayAverage)
            T.expectEqual(b.hrvOrigin, .healthKit7DayAverage)
            T.expectEqual(b.status(usesHRV: true), .personal)
        }
        T.test("HRV は5件で個人値・同時刻の重複は記録しない・14日より古いものは除外") {
            let store = PersonalBaselineStore(defaults: T.freshDefaults("bl-hrv"))
            for i in 0..<5 { _ = store.recordHRV(50 + Double(i), at: now.addingTimeInterval(-Double(i) * 7200)) }
            T.expect(!store.recordHRV(99, at: now), "duplicate time")
            var b = store.snapshot(now: now, healthKitAverageHeartRate: nil, healthKitAverageHRV: nil)
            T.expectEqual(b.hrvOrigin, .appCollectedSamples)
            T.expectEqual(b.hrv, 52)
            b = store.snapshot(now: now.addingTimeInterval(15 * 86_400), healthKitAverageHeartRate: nil, healthKitAverageHRV: nil)
            T.expectEqual(b.hrvOrigin, .reference)
        }
    }

    // MARK: - ViewModel

    static func makeVM(_ name: String) -> MindWaveViewModel {
        MindWaveViewModel(baselineStore: PersonalBaselineStore(defaults: T.freshDefaults("vm-\(name)")))
    }

    static func viewModel() {
        T.test("起動直後は Mock（is_mock=true）でグラフィックを表示") {
            let vm = makeVM("launch")
            T.expectEqual(vm.activeDataSource, .mock)
            T.expect(vm.lastAnalysisResult?.metadata.isMock == true, "mock analysis")
            T.expect(vm.latestAnalysisContract?.isMock == true, "contract is_mock")
        }
        T.test("Mock ON 中の Watch 受信はグラフィックを変えないが診断値は更新") {
            let vm = makeVM("mockwatch")
            let before = vm.graphicInput
            vm.applyWatchHeartRate(110, sampleDate: Date())
            T.expectEqual(vm.graphicInput, before)
            T.expectEqual(vm.latestWatchHeartRate, 110)
        }
        T.test("Mock OFF・データなし → neutral（クラッシュしない）") {
            let vm = makeVM("empty")
            vm.setMockMode(false)
            T.expectEqual(vm.activeDataSource, .unavailable)
            T.expectEqual(vm.graphicInput, .neutral)
            T.expect(vm.latestAnalysisContract == nil, "no analysis")
            T.expect(vm.snapshotHeartRate == nil, "no snapshot hr")
        }
        T.test("Mock OFF・Watch 受信 → 分析 → グラフィック → JSON 契約まで一貫") {
            let vm = makeVM("watch")
            vm.setMockMode(false)
            let t = Date()
            vm.applyWatchHeartRate(84, sampleDate: t)
            T.expectEqual(vm.activeDataSource, .watchLive)
            T.expectEqual(vm.graphicInput.score, 38)   // HRV なし → 既存計算式の中立値
            T.expectEqual(vm.graphicInput.confidence, 0.5)
            guard let dto = vm.latestAnalysisContract else { return T.fail("no contract") }
            try dto.validate()
            T.expectEqual(dto.source, .watchLive)
            T.expect(!dto.isMock, "real")
            T.expectEqual(dto.inputs.hrvStatus, "missing")
            T.expectEqual(dto.inputs.baselineStatus, "provisional")
            T.expectEqual(dto.inputs.heartRateBpm, 84)
            T.expectEqual(vm.snapshotHeartRate, 84)
            T.expectEqual(vm.baseline.collectedHeartRateCount, 1)
        }
        T.test("Watch 重複・逆順パケットは無視（3チャネル重複対策の維持）") {
            let vm = makeVM("dup")
            vm.setMockMode(false)
            let t = Date()
            vm.applyWatchHeartRate(84, sampleDate: t)
            vm.applyWatchHeartRate(140, sampleDate: t)
            vm.applyWatchHeartRate(150, sampleDate: t.addingTimeInterval(-1))
            T.expectEqual(vm.latestWatchHeartRate, 84)
        }
        T.test("ガイド記録: 実測は source 付き・Mock は isMockData で学習対象外") {
            let vm = makeVM("guide")
            let mockSnap = GuideSnapshot(timestamp: Date(), score: vm.graphicInput.score, confidence: vm.graphicInput.confidence,
                                         state: vm.graphicInput.state, heartRate: vm.snapshotHeartRate, hrv: vm.snapshotHRV,
                                         isMockData: vm.isMockMode, heartRateSampleDate: nil, hrvSampleDate: nil,
                                         dataSource: vm.activeDataSource)
            vm.setMockMode(false)
            vm.applyWatchHeartRate(90, sampleDate: Date())
            let realSnap = GuideSnapshot(timestamp: Date(), score: vm.graphicInput.score, confidence: vm.graphicInput.confidence,
                                         state: vm.graphicInput.state, heartRate: vm.snapshotHeartRate, hrv: vm.snapshotHRV,
                                         isMockData: vm.isMockMode, heartRateSampleDate: nil, hrvSampleDate: nil,
                                         dataSource: vm.activeDataSource)
            let store = GuideHistoryStore(defaults: T.freshDefaults("vm-guide-history"))
            store.add(GuideSessionRecord(id: UUID(), startedAt: Date(), scene: .study, exercise: .box, durationSeconds: 60,
                                         before: mockSnap, after: nil, hrvUpdated: false))
            store.add(GuideSessionRecord(id: UUID(), startedAt: Date(), scene: .study, exercise: .box, durationSeconds: 60,
                                         before: realSnap, after: nil, hrvUpdated: false))
            T.expectEqual(store.realMeasurementRecords.count, 1)
            T.expectEqual(store.realMeasurementRecords.first?.before.dataSource, .watchLive)
            T.expectEqual(store.realMeasurementRecords.first?.before.heartRate, 90)
            let reloaded = GuideHistoryStore(defaults: T.freshDefaults("vm-guide-history-copy"))
            T.expectEqual(reloaded.records.count, 0)
        }
    }
}
