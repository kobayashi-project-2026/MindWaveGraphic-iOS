// HistoryStoreTests.swift
// GuideHistoryStore の JSON 保存・旧形式からの移行・互換書き込みのテスト

import Foundation

enum HistoryStoreTests {
    typealias T = TestHarness

    /// 旧アプリ（v2）が保存していた形式の辞書を作る（GuideHistoryStore.saveLegacy と同じキー）
    static func legacyDict(id: UUID, mock: Bool) -> [String: Any] {
        [
            "id": id.uuidString, "startedAt": 1_761_600_000.0, "scene": "interview", "exercise": "breathing478",
            "durationSeconds": 180, "hrvUpdated": false,
            "before": ["timestamp": 1_761_600_000.0, "score": 70.0, "confidence": 0.5, "state": "overTense", "isMock": mock, "heartRate": 95.0],
            "after": ["timestamp": 1_761_600_200.0, "score": 45.0, "confidence": 0.5, "state": "optimalTension", "isMock": mock],
            "emotionMemo": "旧メモ", "srBefore": 2, "aiTitle": "旧タイトル", "aiVersion": "local-1.0"
        ]
    }

    static func run() {
        T.suite("GuideHistoryStore")

        T.test("旧形式(v2)の履歴を読み込み、v3 JSON を作成し、v2 は残す") {
            let d = T.freshDefaults("legacy")
            let id = UUID()
            d.set([legacyDict(id: id, mock: false)], forKey: "mindwave.guideHistory.v2")
            let store = GuideHistoryStore(defaults: d)
            T.expectEqual(store.records.count, 1)
            T.expectEqual(store.records.first?.id, id)
            T.expectEqual(store.records.first?.emotionMemo, "旧メモ")
            T.expectEqual(store.records.first?.before.heartRate, 95)
            T.expect(store.records.first?.after?.heartRate == nil, "missing hr stays nil")
            T.expect(d.data(forKey: GuideHistoryStore.jsonDefaultsKey) != nil, "v3 json created")
            T.expect(d.array(forKey: "mindwave.guideHistory.v2") != nil, "v2 kept")
        }

        T.test("追加すると v3 と v2 の両方へ保存され、再起動後も読める") {
            let d = T.freshDefaults("add")
            let store = GuideHistoryStore(defaults: d)
            let r = ContractTests.makeRecord(memo: "メモ")
            store.add(r)
            let legacy = d.array(forKey: "mindwave.guideHistory.v2") as? [[String: Any]]
            T.expectEqual(legacy?.count, 1)
            let reloaded = GuideHistoryStore(defaults: d)
            T.expectEqual(reloaded.records.count, 1)
            T.expectEqual(reloaded.records.first?.id, r.id)
            T.expectEqual(reloaded.records.first?.after?.hrv, 38.2)
            T.expectEqual(reloaded.records.first?.before.dataSource, .watchLive)
        }

        T.test("v3 JSON が壊れていても旧形式から復元する（データを消さない）") {
            let d = T.freshDefaults("corrupt")
            let id = UUID()
            d.set([legacyDict(id: id, mock: false)], forKey: "mindwave.guideHistory.v2")
            d.set(Data("not json".utf8), forKey: GuideHistoryStore.jsonDefaultsKey)
            let store = GuideHistoryStore(defaults: d)
            T.expectEqual(store.records.first?.id, id)
        }

        T.test("同じ id は v3 を優先し、v2 にしかない記録（他ブランチのビルドで追加）も取り込んで消さない") {
            let d = T.freshDefaults("priority")
            let store = GuideHistoryStore(defaults: d)
            let r = ContractTests.makeRecord()
            store.add(r)
            // 他ブランチの旧ビルドが v2 だけに記録を1件追加した想定（v2 = 既存 r ＋ 新規）
            var legacy = d.array(forKey: "mindwave.guideHistory.v2") as? [[String: Any]] ?? []
            let otherBranchID = UUID()
            legacy.insert(legacyDict(id: otherBranchID, mock: false), at: 0)
            d.set(legacy, forKey: "mindwave.guideHistory.v2")

            let reloaded = GuideHistoryStore(defaults: d)
            T.expectEqual(reloaded.records.count, 2)
            T.expectEqual(reloaded.records.first(where: { $0.id == r.id })?.before.dataSource, .watchLive, "v3 の項目を保持")
            T.expect(reloaded.records.contains { $0.id == otherBranchID }, "v2 のみの記録を取り込む")
            // 次の保存後も両形式に2件とも残る
            reloaded.add(ContractTests.makeRecord())
            T.expectEqual((d.array(forKey: "mindwave.guideHistory.v2") as? [[String: Any]])?.count, 3)
            T.expectEqual(GuideHistoryStore(defaults: d).records.count, 3)
        }

        T.test("感想メモの更新は他フィールドを変えない") {
            let d = T.freshDefaults("memo")
            let store = GuideHistoryStore(defaults: d)
            let r = ContractTests.makeRecord(memo: nil)
            store.add(r)
            T.expect(store.updateEmotionMemo(id: r.id, memo: "  よく眠れそう  "), "updated")
            let u = store.records[0]
            T.expectEqual(u.emotionMemo, "よく眠れそう")
            T.expectEqual(u.before, r.before)
            T.expectEqual(u.aiInsightTitle, r.aiInsightTitle)
            T.expect(store.updateEmotionMemo(id: r.id, memo: "   "), "cleared")
            T.expect(store.records[0].emotionMemo == nil, "empty -> nil")
            T.expect(!store.updateEmotionMemo(id: UUID(), memo: "x"), "unknown id")
        }

        T.test("realMeasurementRecords は Mock を含む記録を除外") {
            let d = T.freshDefaults("mockfilter")
            let store = GuideHistoryStore(defaults: d)
            store.add(ContractTests.makeRecord(mock: true))
            store.add(ContractTests.makeRecord(mock: false))
            T.expectEqual(store.records.count, 2)
            T.expectEqual(store.realMeasurementRecords.count, 1)
        }

        T.test("exportJSON は契約形式で読み戻せる") {
            let d = T.freshDefaults("export")
            let store = GuideHistoryStore(defaults: d)
            store.add(ContractTests.makeRecord())
            guard let data = store.exportJSON() else { return T.fail("no export") }
            let doc = try MindWaveContract.makeDecoder().decode(GuideHistoryDocument.self, from: data)
            T.expectEqual(doc.records.count, 1)
            T.expectEqual(doc.schemaVersion, 1)
        }
    }
}
