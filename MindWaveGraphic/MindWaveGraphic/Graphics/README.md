# グラフィックチーム向け実装ガイド

## 1. グラフィックチームが編集するファイル

| ファイル | 操作 |
|---|---|
| `Graphics/TeamGraphicView.swift` | グラフィック本体を実装する |
| `Graphics/GraphicPlugin.swift` | 完成時に登録1行を変更する |

他のファイル（ViewModel、HealthKitManager、WatchConnectivityManager等）は**変更不要・変更禁止**です。

---

## 2. 受け取れる入力

```swift
struct GraphicInput {
    let score: Double      // 緊張不安定度スコア
    let confidence: Double // 推定の確からしさ
    let state: MindState   // 3状態
}
```

---

## 3. 各値の範囲

| プロパティ | 型 | 範囲 | 説明 |
|---|---|---|---|
| `score` | Double | 0〜100 | 0=完全リラックス、100=最高緊張 |
| `confidence` | Double | 0〜1 | 低いほど推定が不確実（データ不足等） |
| `state` | MindState | 3値 | 下記参照 |

---

## 4. 3状態の意味

| state | displayName | 概要 |
|---|---|---|
| `.underAroused` | 落ちすぎている | 緊張が足りない。score 0〜32 |
| `.optimalTension` | いい緊張状態 | 最適パフォーマンスゾーン。score 33〜69 |
| `.overTense` | 悪い緊張状態 | 過緊張・ストレス。score 70〜100 |

※閾値は研究進捗に応じて `MindState.swift` で一元変更されます。

---

## 5. HealthKit・WatchConnectivityに触れてはいけない理由

グラフィックViewがHealthKitやWCSessionへ直接アクセスすると、以下の問題が発生します：

- **権限競合**: HealthKit権限の二重リクエスト、予期しないセッション競合
- **密結合**: データ変更のたびにグラフィックコードも修正が必要になる
- **テスト不能**: Mockデータでの動作確認ができなくなる

GraphicInputはすでに計算・正規化済みです。受け取ったままアニメーションに使ってください。

---

## 6. 差し替え方法（完成時の1手順）

`Graphics/GraphicPlugin.swift` を開き、以下の**1行だけ**変更します：

```swift
// 変更前
AnyView(PlaceholderGraphicView(input: input))

// 変更後
AnyView(TeamGraphicView(input: input))
```

これだけで本番グラフィックが差し込まれます。他のファイルは変更不要です。

---

## 7. SimulatorでMock確認する方法

1. iOS Simulatorでアプリを起動する
2. 「ライブ」タブを開く
3. 画面下部の「Debug」を展開する
4. 「Mockモード」セクションで以下を操作する：
   - **Mock ON/OFF**: Mockモードの切り替え
   - **状態選択**: underAroused / optimalTension / overTense
   - **Scoreスライダー**: 0〜100で直接指定
   - **Confidenceスライダー**: 0〜1で直接指定
   - **自動更新**: 5秒ごとに再送信（パイプライン疎通確認用）

Mock変更 → ingest() → MindAnalysisResult → GraphicInput → GraphicHostView → TeamGraphicView という経路でリアルタイムに反映されることを確認してください。

---

## 8. 実装してはいけない処理

```swift
// NG: HealthKit直接アクセス
import HealthKit
let store = HKHealthStore()

// NG: WatchConnectivity直接アクセス
import WatchConnectivity
WCSession.default.sendMessage(...)

// NG: ViewModelへの参照
@EnvironmentObject var viewModel: MindWaveViewModel

// NG: View内でのデータ取得開始
.onAppear { viewModel.startLiveMonitoring() }

// NG: GraphicInputを直接書き換える処理
```

---

## 9. 完成時にGraphicPluginの変更する1行

`Graphics/GraphicPlugin.swift` の `static let current` の戻り値:

```swift
// この1行を変更するだけ
AnyView(PlaceholderGraphicView(input: input))
↓
AnyView(TeamGraphicView(input: input))
```

---

## アーキテクチャ概要

```
Apple Watch / HealthKit / Mock
         ↓
  MindWaveSample（生体データ共通型）
         ↓
  ingest()（MindWaveViewModel）
         ↓
  StressScoreCalculator
         ↓
  MindAnalysisResult
         ↓
  GraphicInput（score / confidence / state のみ）
         ↓
  GraphicHostView → GraphicPlugin.current
         ↓
  TeamGraphicView（グラフィックチームが実装）
```
