import SwiftUI

// グラフィックチームが変更するのはこのファイルの登録1行だけ。
// 他のファイル（ViewModel、HealthKitManager等）は変更不要。

typealias GraphicRenderer = @MainActor (GraphicInput) -> AnyView

enum GraphicPlugin {
    // ▼ グラフィックチームはここを1行変更する
    //   変更前: AnyView(PlaceholderGraphicView(input: input))
    //   変更後: AnyView(TeamGraphicView(input: input))
    static let current: GraphicRenderer = { input in
        AnyView(PlaceholderGraphicView(input: input))
    }
}
