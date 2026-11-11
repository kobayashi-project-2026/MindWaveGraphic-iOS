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
    }
}
