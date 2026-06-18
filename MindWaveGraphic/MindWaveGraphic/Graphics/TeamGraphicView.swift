import SwiftUI

// グラフィックチームが実装するViewのテンプレートです。
//
// ▼ 受け取れる入力（input プロパティ）
//   - input.score      : Double     0〜100（0=完全リラックス / 100=最高緊張）
//   - input.confidence : Double     0〜1（推定の確からしさ。低いほど不確実）
//   - input.state      : MindState  3状態
//
// ▼ 3状態の意味
//   - .underAroused    落ちすぎている（緊張が足りない状態）
//   - .optimalTension  いい緊張状態（最適パフォーマンスゾーン）
//   - .overTense       悪い緊張状態（過緊張・ストレス）
//
// ▼ 禁止事項
//   - HealthKit / WatchConnectivity に直接アクセスしない
//   - View内でデータ取得処理（startWorkout / fetch等）を開始しない
//   - ViewModel / HealthKitManager を参照しない
//
// ▼ アニメーションについて
//   - inputが変化するたびにbodyが再評価されます
//   - アニメーションはinputの変化に対して実装してください
//   - 例: .animation(.easeInOut(duration: 0.5), value: input.score)
//
// ▼ 差し替え方法（完成時に1行だけ変更）
//   Graphics/GraphicPlugin.swift を開き、以下の1行を変更する:
//   変更前: AnyView(PlaceholderGraphicView(input: input))
//   変更後: AnyView(TeamGraphicView(input: input))
//
// ▼ 外部チームが変更してよい範囲
//   - TeamGraphicView の body の内容すべて
//   - Privateな関数・計算プロパティの追加
//   - Graphicsフォルダ内への追加ファイル
//   - GraphicPlugin.swift の登録1行
struct TeamGraphicView: View {
    let input: GraphicInput

    var body: some View {
        StarfieldGraphicView(input: input)
    }
}

#Preview {
    ZStack {
        MindWaveTheme.backgroundGradient.ignoresSafeArea()
        TeamGraphicView(input: GraphicInput(score: 55, confidence: 0.8, state: .optimalTension))
            .padding()
    }
    .preferredColorScheme(.dark)
}
