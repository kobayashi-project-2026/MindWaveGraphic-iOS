import SwiftUI

// グラフィックチームが変更するのはこのファイルの登録1行だけ。
// 他のファイル（ViewModel、HealthKitManager等）は変更不要。

typealias GraphicRenderer = @MainActor (GraphicInput) -> AnyView

/// ホームのグラフィックの種類（2026-11-18 追加）
/// - haruka : HarukaSasaki-bit さんの宇宙グラフィック（HarukaSpaceGraphicView）。既定
/// - classic: 2026-11-17 までの宇宙船グラフィック（SpaceshipStateGraphicView）
/// 切り替え: UserDefaults の "mw_graphic_style"（"haruka" / "classic"）。DEBUG ビルドでは環境変数 MW_GRAPHIC_STYLE を優先する
enum GraphicStyle: String, CaseIterable, Sendable {
    case haruka, classic

    static let defaultsKey = "mw_graphic_style"

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        defaults: UserDefaults = .standard) -> GraphicStyle {
        #if DEBUG
        if let raw = environment["MW_GRAPHIC_STYLE"], let style = GraphicStyle(rawValue: raw) { return style }
        #endif
        if let raw = defaults.string(forKey: defaultsKey), let style = GraphicStyle(rawValue: raw) { return style }
        return .haruka
    }

    static var current: GraphicStyle { resolve() }
}

enum GraphicPlugin {
    // ▼ グラフィックチームはここを1行変更する
    //   変更前: AnyView(PlaceholderGraphicView(input: input))
    //   変更後: AnyView(TeamGraphicView(input: input))
    static let current: GraphicRenderer = { input in
        AnyView(TeamGraphicView(input: input))
    }
}
