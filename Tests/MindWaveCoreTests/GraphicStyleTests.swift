// GraphicStyleTests.swift
// ホームのグラフィックの切り替え（HarukaSasaki-bit さんの宇宙グラフィック／従来の宇宙船グラフィック）のテスト。

import Foundation

enum GraphicStyleTests {
    typealias T = TestHarness

    static func run() {
        T.suite("Graphics / グラフィックの切り替え（GraphicStyle）")
        T.test("既定は HarukaSasaki-bit さんの宇宙グラフィック") {
            T.expectEqual(GraphicStyle.resolve(environment: [:], defaults: T.freshDefaults("graphic-default")), .haruka)
        }
        T.test("設定（mw_graphic_style）で従来のグラフィックに戻せる。未知の値は既定") {
            let d = T.freshDefaults("graphic-classic")
            d.set("classic", forKey: GraphicStyle.defaultsKey)
            T.expectEqual(GraphicStyle.resolve(environment: [:], defaults: d), .classic)
            d.set("unknown", forKey: GraphicStyle.defaultsKey)
            T.expectEqual(GraphicStyle.resolve(environment: [:], defaults: d), .haruka)
        }
        T.test("DEBUG では環境変数 MW_GRAPHIC_STYLE を設定より優先する") {
            let d = T.freshDefaults("graphic-env")
            d.set("classic", forKey: GraphicStyle.defaultsKey)
            T.expectEqual(GraphicStyle.resolve(environment: ["MW_GRAPHIC_STYLE": "haruka"], defaults: d), .haruka)
        }
    }
}
