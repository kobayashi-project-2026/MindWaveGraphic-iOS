import SwiftUI

// グラフィック差し込み口。GraphicInputだけを受け取り、
// GraphicPlugin.current へ委譲する。データ取得・計算は行わない。
struct GraphicHostView: View {
    let input: GraphicInput

    var body: some View {
        GraphicPlugin.current(input)
    }
}

#Preview {
    GraphicHostView(input: .neutral)
        .preferredColorScheme(.dark)
        .padding()
}
