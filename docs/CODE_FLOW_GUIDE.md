# MindWaveGraphic コードフロー解説

## 1. システム全体

```
Apple Watch / HealthKit / Mock
    ↓
MindWaveSample（生体データ共通型）
    ↓
MindWaveViewModel.ingest()
    ↓
selectActiveSample()（ソース選択・優先順位判定）
    ↓
StressScoreCalculator（tensionScore 算出）
    ↓
MindAnalysisResult（score / confidence / state）
    ↓
GraphicInput（グラフィック層への入力）
    ↓
GraphicHostView → GraphicPlugin.current
    ↓
グラフィックチームの View（TeamGraphicView）
```

---

## 2. Watch 経路

```
Apple Watch（WorkoutManager）
    ↓
WatchConnectivity（sendMessage / transferUserInfo / updateApplicationContext）
    ↓
iPhone WatchConnectivityManager.onHeartRateReceived
    ↓
MindWaveViewModel.applyWatchHeartRate()
    ↓
MindWaveSample（source: .watchLive）
    ↓
ingest()
```

Watch サンプルは Mock ON 中でも保存される。selectActiveSample で Mock が優先されるため、GraphicInput は Mock 値のまま維持される。

---

## 3. HealthKit 経路

```
HealthKit（HKHealthStore）
    ↓
HealthKitManager.fetchBestCurrentHeartRate / fetchBestCurrentHRV
    ↓
MindWaveViewModel.applyFetchedValues()
    ↓
MindWaveSample（source: .healthKit）
    ↓
ingest()
```

取得失敗時はデモデータへフォールバックせず、現状のアクティブソースで継続する。

---

## 4. Mock 経路

```
Debug UI（スライダー / シナリオ選択）
    ↓
MindWaveViewModel.sendMockSample()
    ↓
MindWaveSample（source: .mock, contextScore: mockScore）
    ↓
ingest()
```

contextScore が設定されている場合、StressScoreCalculator は呼ばれずそのままスコアとして使用される。

---

## 5. データソース優先順位

`selectActiveSample(now:)` の判定順序:

| 条件 | 採用ソース |
|---|---|
| `isMockMode == true` | Mock（`latestMockSample`） |
| Watch受信から15秒以内 | Watch（`latestWatchSample`） |
| Watch古い/未受信 | HealthKit（`latestHealthKitSample`） |
| いずれもなし | `nil` → unavailable → `GraphicInput.neutral` |

Watch にHRVがなくHealthKitにHRVがある場合、HRVだけを補完してsourceは`.watchLive`のまま返す。

---

## 6. GraphicInput

グラフィックチームが受け取る値:

| プロパティ | 型 | 範囲 | 説明 |
|---|---|---|---|
| `score` | Double | 0〜100 | 緊張不安定度スコア |
| `confidence` | Double | 0〜1 | 推定の確からしさ（0 = データなし） |
| `state` | MindState | 3値 | underAroused / optimalTension / overTense |

`GraphicInput.neutral`（`confidence: 0`）はデータ未受信を意味する。

グラフィックチームへ渡さない情報:

- 心拍数・HRV の生値
- HealthKit 型・WCSession
- ViewModel・HealthKitManager への参照
- デバッグ情報

---

## 7. 主要ファイルの役割

| ファイル | 役割 |
|---|---|
| `MindWaveViewModel.swift` | 全データ経路の統括。ingest・仲裁・GraphicInput 生成 |
| `MindWaveSample.swift` | Watch/HealthKit/Mock を統一する生体データ型 |
| `MindState.swift` | 3状態の定義と閾値（underAroused/optimalTension/overTense） |
| `MindAnalysisResult.swift` | 解析済みスコア・信頼度・状態の中間型 |
| `GraphicInput.swift` | グラフィック層への入力型（score/confidence/state のみ） |
| `WatchConnectivityManager.swift` | WatchConnectivity 受信・診断情報の管理 |
| `HealthKitManager.swift` | HKHealthStore へのアクセス・認証・データ取得 |
| `GraphicHostView.swift` | GraphicInput を受け取り GraphicPlugin に委譲するシム |
| `GraphicPlugin.swift` | グラフィック実装の差し込み口（登録1行変更で切替） |
| `TeamGraphicView.swift` | グラフィックチームが実装するView |

---

## 8. デバッグログの読み方

DEBUGビルドでのみ出力される。Releaseビルドでは全て無効。

フォーマット: `[MindWave][カテゴリ] メッセージ`

| カテゴリ | 内容 |
|---|---|
| `LIFECYCLE` | 初期化・ライブ監視の開始/停止 |
| `PIPELINE` | ingest でのサンプル受信・保存 |
| `SOURCE` | アクティブソースの切り替え・unavailable |
| `WATCH` | Watch心拍受信・期限タスク管理 |
| `HEALTHKIT` | HealthKit取得結果・ingest渡し・失敗 |
| `MOCK` | Mock ON/OFF・サンプル送信・自動更新 |
| `ANALYSIS` | score / confidence / state 確定値 |
| `GRAPHIC` | GraphicInput 更新 |
| `ERROR` | 認証失敗などのエラー |

---

## 9. 不具合別に確認するログ

### Watch心拍が届かない

```
[MindWave][WATCH] heart rate received ... が出ない
```

→ WatchConnectivityManager の接続状態を確認。Watch 側 WorkoutManager が起動しているか確認。

### Mockから実データへ戻らない

```
[MindWave][MOCK] mode OFF
[MindWave][SOURCE] active source changed mock -> watchLive  ← 出ない場合
```

→ Watch サンプルが届いているか（WATCH ログ）を確認。Watch期限切れでも届いていれば SOURCE が変わるはず。

### Active Sourceが切り替わらない

```
[MindWave][SOURCE] active source changed A -> B  ← 出ない
```

→ PIPELINE ログでサンプルが届いているか確認。届いていても SOURCE が変わらなければ selectActiveSample の条件（Mock ON？ Watch 期限切れ？）を疑う。

### scoreが更新されない

```
[MindWave][ANALYSIS] score=... ← 変化しない
```

→ PIPELINE で healthKit / watchLive サンプルが届いているか、hrv が "present" かを確認。

### グラフィックが変化しない

```
[MindWave][GRAPHIC] input updated ... ← 変化しない
```

→ ANALYSIS で score が変わっているのに GRAPHIC が変わらない場合は GraphicHostView → GraphicPlugin 経路を確認。

### 15秒後にWatchから切り替わらない

```
[MindWave][WATCH] expiry task scheduled ...
[MindWave][WATCH] sample expired after 15s, re-evaluating source
[MindWave][SOURCE] active source changed watchLive -> healthKit  ← または unavailable
```

→ `expiry task scheduled` が出ているのに `sample expired` が出ない場合、Task がキャンセルされている可能性がある（新しい Watch サンプルが15秒以内に届いた場合は `expiry task skipped` が出る）。
