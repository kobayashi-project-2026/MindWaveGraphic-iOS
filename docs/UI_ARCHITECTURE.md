# UI Architecture — MindWave Graphic

最終更新：2026-06-19

---

## 1. タブ構成（現在）

| タブ | View | tag | 役割 |
|---|---|---|---|
| ホーム | `HomeView` | 0 | 没入型計測メイン画面（旧Liveタブ統合済み） |
| ガイド | `GuideView` | 1 | 使い方・HRV説明 |
| 履歴 | `HistoryView` | 2 | 過去セッション記録（現在ダミーデータ） |
| 設定 | `SettingsView` | 3 | Account・表示設定・データとプライバシー |

削除されたタブ：**ライブ（旧 tag 1）** → HomeView に統合。

---

## 2. HomeへMoveしたLive機能

旧 `LiveWaveView` から以下を `HomeView` へ移動した。

| 機能 | 移動先 |
|---|---|
| GraphicHostView（Starfield 全画面） | `HomeView.body` ZStack 背景 |
| 計測開始・停止ボタン | `HomeView.measurementButton` |
| 心拍数・HRV表示 | `HomeView.biometricStrip` |
| LIVE ドット・状態 | `HomeView.topHUD` |
| Debug 展開 | `HomeView.showDebugSheet` → `DebugDiagnosticsView.swift` |
| Mock制御・デモシナリオ | `DebugDiagnosticsView.mockControlSection` |
| 全診断行 | `DebugDiagnosticsView` |

---

## 3. HomeのView階層

```
HomeView
├─ GraphicHostView.ignoresSafeArea()   ← Starfield 全画面背景
│   └─ GraphicPlugin.current(input)
│       └─ TeamGraphicView(input:)
│           └─ StarfieldGraphicView(input:, showsParameterOverlay:)
│               ├─ Canvas (800星, TimelineView)
│               └─ scoreOverlay (showsParameterOverlay が true のとき)
│
└─ VStack (UI オーバーレイ)
    ├─ topHUD
    │   ├─ "Mind Wave" + elapsed time
    │   ├─ LIVE ドット + statusLabel
    │   └─ profileButton → AccountView.sheet
    └─ bottomPanel
        ├─ state.displayName
        ├─ "HRV測定を待機中" (条件表示)
        ├─ biometricStrip (心拍 | HRV)
        ├─ measurementButton (toggleLiveMonitoring)
        └─ Debug ボタン (DEBUG のみ) → DebugDiagnosticsView.sheet
```

---

## 4. GraphicInputからStarfieldまで

```
MindWaveViewModel.graphicInput: GraphicInput
    ↓ (ContentView → EnvironmentObject)
HomeView
    ↓
GraphicHostView(input: viewModel.graphicInput)
    ↓ GraphicPlugin.current(input)
TeamGraphicView(input: input)
    @AppStorage("showsParameterOverlay")
    ↓
StarfieldGraphicView(input: input, showsParameterOverlay: bool)
    ├─ 800星アニメーション (Canvas + TimelineView)
    ├─ score → signedStress → speed/color
    └─ scoreOverlay (showsParameterOverlay = true のとき)
```

---

## 5. DebugとReleaseの分離

| 要素 | Debug | Release |
|---|---|---|
| Debug ボタン（Home） | 表示 (`#if DEBUG`) | 非表示 |
| DebugDiagnosticsView シート | 表示可 | シートは呼ばれない |
| 数値オーバーレイ（Starfield） | `showsParameterOverlay = true` | SettingsView で OFF 可 |
| Mock 制御 | DebugDiagnosticsView 内 | 非表示 |

---

## 6. Account UIの現在の範囲

| 機能 | 状態 |
|---|---|
| ローカル表示名の保存 (`@AppStorage`) | 実装済み |
| ゲスト/ログイン状態表示 | UI のみ（ゲスト固定） |
| メールログイン画面 (`LoginPrototypeView`) | UI プロトタイプ（送信しない） |
| Sign in with Apple | 未接続（UI に記載） |
| サーバー認証 | 未実装 |
| パスワードのローカル保存 | **禁止・未実装** |

---

## 7. 本物の認証で未実装の部分

- `LoginPrototypeView.loginAction()` は現在アラートを表示するだけ
- ネットワーク送信なし
- トークン保存なし
- `AccountView` はゲスト固定（`localDisplayName` のみ保存）

---

## 8. SettingsとAppStorage

| キー | 型 | 使用箇所 | 説明 |
|---|---|---|---|
| `showsParameterOverlay` | Bool | `TeamGraphicView`, `SettingsView` | Starfield 数値オーバーレイ |
| `localDisplayName` | String | `AccountView` | ローカル表示名 |
| `hapticFeedbackEnabled` | Bool | `SettingsView` (UI のみ) | 振動フィードバック（未接続） |
| `autoStartMeasurement` | Bool | `SettingsView` (UI のみ) | 自動計測開始（未接続） |
| `showHRVWaitingMessage` | Bool | `SettingsView` / `HomeView` | HRV 待機メッセージ |

---

## 9. 数値表示を消す方法

**現在（検証段階）：** `showsParameterOverlay = true`（デフォルト）

**本番で非表示にする方法：**  
SettingsView の「数値表示」トグルを OFF → `showsParameterOverlay = false` → 即時反映。  
コードを変更しなくても SettingsView から制御できる。

---

## 10. ファイル別の役割

| ファイル | 役割 |
|---|---|
| `ContentView.swift` | ルートView。ViewModel生成・4タブ管理 |
| `HomeView.swift` | 没入型メイン画面。Starfield全画面 + 計測UI |
| `DebugDiagnosticsView.swift` | 診断シート。DEBUGビルドのみ使用 |
| `SettingsView.swift` | 設定画面。Account・表示設定・プライバシー |
| `AccountView.swift` | アカウントシート。LoginPrototypeView への入口 |
| `LoginPrototypeView.swift` | ログインUIプロトタイプ（未接続） |
| `LiveWaveView.swift` | 旧Liveタブ（参照なし・保持中） |
| `Graphics/StarfieldGraphicView.swift` | 3D星空アニメーション View |
| `Graphics/TeamGraphicView.swift` | GraphicPlugin の接続点。AppStorage 参照 |
| `Graphics/GraphicPlugin.swift` | グラフィック差し込み口（1行変更で差替可） |
| `MindWaveViewModel.swift` | 全データパイプラインの統括 |
| `HealthKitManager.swift` | HK HRV Observer 管理 |

---

## 11. 次フェーズで本物のログインを接続する変更点

1. `LoginPrototypeView.swift` の `loginAction()` に認証ライブラリ呼び出しを追加
2. 認証トークン（パスワードではない）を Keychain に保存
3. `AccountView.swift` のゲスト判定を認証状態に切り替え
4. `ContentView.swift` の `EnvironmentObject` に `AuthState` を追加
5. Sign in with Apple: `AuthenticationServices` フレームワークを追加（Capability追加が必要）

---

## 12. ガイドフロー（RegulationFlow）

### 概要

参考コードから「シーン選択 → ガイド → 再測定 → 結果 → 保存」という遷移の考え方を採用。
ダミーBPM・架空の改善結果・ログイン遷移は採用しない。

### タブ構成との関係

```
Home
└─ 「今の状態を整える」ボタン → selectedTab = 1（Guideタブへ移動）

Guide（タブ）
├─ 「シーンを選んで整える」→ GuideFlowView (fullScreenCover)
└─ クイックスタートカード → GuideSessionView (fullScreenCover) ※従来の直接アクセス
```

### フロー段階 (RegulationFlowStep)

```
sceneSelection → exerciseSelection → session → remeasurement → result
```

Int ベースの状態管理を避け、型安全な enum で管理。

### MeasurementScene

6種類のシーン。スコア計算式には影響しない。
```
interview / study / sports / social / daily / other
```

### ガイド前スナップショット (GuideSnapshot)

セッション開始前にViewModelから実値を取得。
- isMockData=true でMockモードを区別
- HRV未取得は nil（0で代用しない）
- heartRate は Watch受信値を優先、なければHealthKit値

### 再測定の完了条件

```
minWatchSamplesForRemeasurement = 3 件の新規Watch受信
または
maxRemeasurementSeconds = 30 秒経過
```

HRVは必須条件にしない（新規サンプル生成の保証がないため）。

### HRV更新状態の区別

- セッション前後で `latestHRVSampleDate` が変化した場合: `hrvUpdated = true`
- 変化なし: `hrvUpdated = false`（記録に明示）

### GuideHistoryStore

- `ObservableObject`、ContentViewで1回だけ生成
- EnvironmentObjectでGuideFlowView・HistoryViewが共有
- **現時点はメモリ内保存のみ（アプリ終了で消える）**
- UserDefaults / SwiftDataへの移行は次フェーズ

### 保存後の遷移

```
historyStore.add(record)
dismiss()
Task { @MainActor in selectedTab = 2 }  // HistoryタブへのTab切替
```

### 保存せず終了

```
dismiss()
Task { @MainActor in selectedTab = 0 }  // Homeへ戻る
```

### 再実施

```
before snapshot を取り直す
step = .session に戻る（シーン・ガイドは維持）
Timer・再測定カウンターをリセット
```

### 中断処理

すべての段階で `.alert` による中断確認。
中断時: `dismiss()` でGuideFlowViewを閉じる（HistoryStoreへは保存しない）。

---

## 13. 参考コードとの対応

| 参考コードの要素 | 採用 | 理由 |
|---|---|---|
| シーン選択→ガイド→結果の遷移フロー | ✓ 採用 | 流れの考え方として利用 |
| ランダム生成BPM | ✗ 不採用 | 架空データのため |
| 徐々に減るBPMアニメーション | ✗ 不採用 | 架空演出のため |
| 架空の「改善成功」表示 | ✗ 不採用 | 医療効果の断定のため |
| ログイン遷移 (Splash→Account→Main) | ✗ 不採用 | 認証基盤未接続のため |
| 架空のクラウド同期 | ✗ 不採用 | 未実装のため |
| 文字列ベースの状態管理 (currentStep: Int) | ✗ 不採用 | RegulationFlowStep enum で型安全に置換 |
| 固定日時・ダミー履歴 | ✗ 不採用 | Date()を使用し実データのみ保存 |

---

## 14. 将来のログイン遷移案

現在 Settings/Account/LoginPrototypeView にUIプロトタイプあり。
本物の認証を接続する場合の変更点は `docs/UI_ARCHITECTURE.md` のセクション11を参照。
