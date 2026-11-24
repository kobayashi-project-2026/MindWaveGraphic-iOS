# Mind Wave Graphic アーキテクチャ（2026-10-28 統合版）

iPhone アプリ・Apple Watch アプリ・AIインサイト中継サーバーの構成と、モジュール間の責務・データの流れをまとめる。
JSON の詳細は `docs/DATA_CONTRACTS.md`、OpenAI 連携は `docs/OPENAI_SETUP.md`、スコア式は `docs/FORMULA.md`。

## 1. 全体構成

```text
┌──────────── Apple Watch ────────────┐        ┌──────────────────────── iPhone ────────────────────────┐
│ WorkoutManager                      │  WC    │ WatchConnectivityManager ─▶ WatchHeartRatePayload      │
│  HKWorkoutSession / LiveBuilder     │ ─────▶ │        (3チャネル受信・契約検証)        │               │
│  心拍 → {type,heartRate,timestamp,  │ 辞書   │ HealthKitManager ─(HR・HRV・7日平均)─┐ │               │
│          schemaVersion}             │        │                                       ▼ ▼               │
└─────────────────────────────────────┘        │ MindWaveViewModel.ingest（全データの共通入口）          │
                                               │   ├ ActiveSampleSelector（優先順位・鮮度・重複）       │
                                               │   ├ PersonalBaselineStore（個人ベースライン）           │
                                               │   ├ MindAnalyzer = StressScoreAnalyzerV1                 │
                                               │   │     （StressScoreCalculator を使用）               │
                                               │   └▶ MindAnalysisResult(+metadata) ─▶ GraphicInput      │
                                               │                     │                    │              │
                                               │                     │        GraphicPlugin → Spaceship  │
                                               │                     ▼                                   │
                                               │ GuideFlowView（場面→呼吸→再測定→結果）                │
                                               │   ├ GuideSnapshot（実測/Mock・source 付き）            │
                                               │   ├ InsightService ─ Local（既存エンジン）             │
                                               │   │               └ Remote ──HTTPS──▶ server/ ─▶ OpenAI│
                                               │   └ ユーザーが保存を選んだ時だけ GuideHistoryStore     │
                                               │        （v3 JSON 正本 + v2 互換）→ HistoryView         │
                                               └──────────────────────────────────────────────────────────┘
```

## 2. 画面遷移（状態の持ち主は2つだけ）

| 範囲 | 状態の持ち主 | 内容 |
|---|---|---|
| 認証フロー | `AppFlowState.authStatus` | logoSplash → accountGuidance → topMenu → signUp/logIn → contextCalibration → mainApp |
| メインアプリ内 | `AppNavigationManager` | `selectedTab`（home/guide/history）と `activeModal`（状況確認・設定・結果確認・フィードバック） |

- `MainTabView` は独自のタブ状態を持たず、`navManager` から導出した `Binding<Int>` を `HomeView`・`GuideView`・`CockpitLeverNav` に渡す（既存 View の引数は変更なし）
- 共通メニュー（`GlobalMenuBarModifier`）・コックピットのレバー・ガイド保存後の自動遷移は、すべて `AppNavigationManager` を更新する
- 長寿命オブジェクト（`MindWaveViewModel`・`GuideHistoryStore`・`AppNavigationManager`）は `AppRootContainerView` が所有する。ログアウトや状況選択で `MainTabView` が作り直されても、計測や履歴は作り直されない

### チームが定義した8画面と実装の対応

| AppScreen | 実装 | 表示方式 |
|---|---|---|
| title（タイトル） | `PureLogoSplashView`（認証フロー先頭）へ戻る＝ログアウト。確認ダイアログあり、ライブ計測停止・履歴は保持 | 確認 → authStatus 変更 |
| dialogue（対話・状況確認） | `ContextCalibrationView`（メインアプリ内編集モード `onComplete`） | モーダル |
| tensionGraphic（緊張グラフィック） | `HomeView`（コックピット + `GraphicHostView`） | タブ0 |
| improvement（改善・ワーク） | `GuideView` → `GuideFlowView` | タブ1 |
| confirmation（確認） | 直近記録の `RecordDetailView`。記録がなければ案内画面 | モーダル |
| feedback（フィードバック） | 直近記録の `FeedbackRecordView`（メモ編集、`updateEmotionMemo`）。記録がなければ案内 | モーダル |
| pastLogs（過去ログ） | `HistoryView` | タブ2 |
| settings（設定） | `SettingsView`（Home の歯車も同じ経路） | モーダル |

以前の `AppRootContainerView` が参照していた `TitleView`・`DialogueView`・`ConfirmationView`・`FeedbackView`・`NewRecordListView` はリポジトリに存在しなかったため、上表のとおり既存画面へ対応付けた。専用画面が後から追加された場合は `AppModalDestinationView` の該当 case を差し替える。

## 3. データパイプライン

| 段階 | 実装 | 主な規則 |
|---|---|---|
| 受信 | `WatchConnectivityManager` / `HealthKitManager` | Watch は `WatchHeartRatePayload` で検証（v0/v1 互換） |
| 正規化 | `MindWaveSample`（Domain） | 未計測は nil。0 で代用しない |
| 重複排除 | `applyWatchHeartRate`（timestamp 単調増加）、`updateHRVState`（UUID・endDate） | 既存実装を維持 |
| 有効サンプル判定 | `ActiveSampleSelector` | Mock → Watch(15秒) → HealthKit(心拍30分・HRV6時間)。古い値は使わない |
| ベースライン | `PersonalBaselineStore` | HealthKit7日平均 → アプリ蓄積 → 参照値(provisional) |
| スコア算出 | `MindAnalyzer`（`StressScoreAnalyzerV1`） | 既存計算式と同値（テストで確認） |
| 分析結果 | `MindAnalysisResult` + `AnalysisMetadata` | source / analyzer / hrv_status / baseline_status |
| グラフィック | `GraphicInput` → `GraphicPlugin.current` | グラフィックチームの変更点は従来どおり1行 |
| ガイド | `GuideFlowView` / `LocalMindWaveAIEngine` / `InsightService` | スナップショットは鮮度内の実測値と source を記録 |
| 保存 | `GuideHistoryStore` | ユーザーが保存を選んだ時のみ。v3 JSON + v2 互換 |
| 学習・傾向 | `LocalAIPatternAnalyzer`（`realMeasurementRecords`） | Mock を含む記録は除外 |

## 4. 拡張ポイント

| 追加したいもの | 変更する場所 | 既存コードへの影響 |
|---|---|---|
| 新しいスコア評価方式 | `MindAnalyzer` に準拠した型を追加し、`MindWaveViewModel(analyzer:)` に渡す | なし（結果 JSON の `analyzer_id` で区別） |
| 新しい計測ソース | `MindDataSource` / `DataSourceCode` に case 追加 → `ingest` → `ActiveSampleSelector` に優先順位を追加 | 契約の列挙値追加（schema_version は据え置き可） |
| 新しいグラフィック | `GraphicPlugin.current` の1行 | なし |
| 新しい AI プロバイダ | `InsightProvider` に準拠した型を追加し `InsightService(remoteFactory:)` へ | なし |
| 新しい画面 | `AppScreen` に case → `mainTab`/`modal` の対応 → `AppModalDestinationView` | ナビゲーションテストが対応漏れを検出 |
| JSON 項目追加 | `Contracts/*.swift` と `server/src/contract.ts`、`DATA_CONTRACTS.md` | 任意項目の追加は後方互換。必須化・意味変更は schema_version を上げる |

## 5. ディレクトリ

```text
MindWaveGraphic/MindWaveGraphic/
  App/            AppRootView, AppFlowState, MainTabView
  Views/          AppRootContainerView（長寿命オブジェクトの所有者）
  Navigation/     AppNavigationManager, GlobalMenuBarModifier, AppModalDestinationView
  Authentication/ 認証フロー各画面, ContextCalibrationView
  Domain/         MindWaveSample, MindAnalysisResult, AnalysisMetadata, GraphicInput, MindState, MeasurementContext
  Contracts/      JSON 契約（Codable, schema_version）
  Analysis/       ActiveSampleSelector, PersonalBaseline, MindAnalyzer
  Insights/       InsightProvider, InsightService, RemoteInsightProvider
  Graphics/       GraphicPlugin, TeamGraphicView, SpaceshipStateGraphicView ほか
  Records/        RecordDetailView, FeedbackRecordView
  （直下）         MindWaveViewModel, HealthKitManager, WatchConnectivityManager, Guide*/History*/Home* ほか
MindWaveGraphic/MindWaveGraphicWatch Watch App/   WorkoutManager ほか
server/           Cloudflare Worker（TypeScript, 実行時依存なし）
Tests/MindWaveCoreTests/   iOS ロジックテスト（scripts/run_ios_core_tests.sh で実行）
```

## 6. テストの実行

```bash
scripts/run_ios_core_tests.sh      # 起動中の iOS シミュレーターでロジックテスト（project.pbxproj 変更なし）
cd server && npm test              # サーバー
```

Xcode のテストターゲットは追加していない（共有の `project.pbxproj` を変更しないため）。将来 XCTest ターゲットを追加する場合は、`Tests/MindWaveCoreTests` のテストを移植できる。
