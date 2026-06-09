# ライブモニタリング設計方針

## フェーズ1：デモデータ（実装済み）
デモシナリオを切り替えて波形・スコアを確認する。HealthKit不要。

---

## フェーズ2：iPhone HealthKit ポーリング（実装済み・限界確認済み）

### 仕組み
```
Apple Watch → iPhoneのヘルスケアアプリ（HealthKit）← HealthKitManager（ポーリング）← MindWaveViewModel → LiveWaveView
```

1. Apple Watchが心拍数・HRVをiPhoneのHealthKitに同期する
2. iPhoneアプリが `HealthKitManager` を通じてHealthKitを定期的に読み取る（5秒間隔）
3. 取得した値を `MindWaveViewModel` のプロパティに反映する
4. `LiveWaveView` が `viewModel.stressResult` の変化に応じて波形を更新する

### iPhone HealthKitポーリングの限界（実機確認済み）
| 問題 | 原因 |
|------|------|
| 同じサンプルを読み続ける | HealthKit はPush型ではなく、Watchからの同期タイミングをOSが制御する |
| 安静時は数分おきにしか更新されない | Apple Watchが心拍をHealthKitに保存する頻度が低い |
| `sameSampleCount` が増え続ける | 新規サンプルが来るまでUUIDが変わらない |

**結論**: iPhone HealthKitポーリング単体ではリアルタイム心拍は取得できない。

---

## フェーズ3：watchOSアプリ + WatchConnectivity（現在の実装）

### 実装方針
- **心拍数の主役**: Apple WatchのHKWorkoutSession（リアルタイム秒単位）
- **HRV**: iPhone HealthKitの最新値（補助値・リアルタイムではない）
- iPhone HealthKitポーリングはバックアップとして残す

### データフロー
```
Apple Watch
  ├─ HKWorkoutSession + HKLiveWorkoutBuilder
  │      ↓ workoutBuilder(_:didCollectDataOf:)
  │   WorkoutManager.sendHeartRateToiPhone()
  │      ↓ WCSession.sendMessage / transferUserInfo
  │
iPhone
  ├─ WatchConnectivityManager.handleIncomingMessage()
  │      ↓ onHeartRateReceived コールバック
  │   MindWaveViewModel.applyWatchHeartRate()
  │      ↓ currentHeartRate 即時更新 + livePulseTrigger += 1
  │
LiveWaveView
  └─ 波形パルス反応（pulseBoost）
```

### 実装ファイル

#### Watch側
| ファイル | 役割 |
|---------|------|
| `WorkoutManager.swift` | HKWorkoutSession管理・心拍取得・WCSession送信 |
| `ContentView.swift` | Watch UI（心拍表示・計測開始/停止） |
| `MindWaveGraphicWatchApp.swift` | WorkoutManagerのDI・WCSessionセットアップ |
| `MindWaveGraphicWatch.entitlements` | HealthKit権限 |

#### iPhone側
| ファイル | 役割 |
|---------|------|
| `WatchConnectivityManager.swift` | WCSession受信・ViewModelへコールバック |
| `MindWaveViewModel.swift` | applyWatchHeartRate()でUI反映 |
| `MindWaveGraphicApp.swift` | WCSession起動時アクティベート |

### Watch → iPhone 送信データ形式
```swift
[
    "type":      "heartRate",
    "heartRate": Double,   // bpm
    "timestamp": Double    // Date().timeIntervalSince1970
]
```

### ViewModelの動作
Watch心拍受信時（`applyWatchHeartRate` が呼ばれたとき）:
- `currentHeartRate` を即時更新
- `livePulseTrigger += 1` → LiveWaveViewの波形パルスが発火
- `isNewHeartRateSample = true` → 新規サンプルインジケーターが点灯
- `sameSampleCount = 0` → 同一サンプル連続カウントをリセット
- `dataSourceLabel = "Watchライブ心拍 / HealthKit HRV"`

### HRVの扱い
- HRV（SDNN）はリアルタイム計算が困難（複数のNN間隔が必要）
- iPhone HealthKitの直近値を補助的に使う
- HRVはスコア計算に使うが、主役は心拍数

---

## フェーズ4（将来）：短時間HRVのWatch側計算

### 目標
RMSSDなど短時間HRVをWatch側で計算し、WatchConnectivityで送信する。

### 必要作業
- WorkoutManagerにNN間隔（RR間隔）の計算を追加
- `HKQuantityType(.heartRateVariabilitySDNN)` のライブ統計取得

---

## 実装済みの安全策

| ケース | 対処 |
|--------|------|
| Watch未起動 | HealthKitポーリングにフォールバック。デモデータ維持。 |
| WCSession到達不可 | `transferUserInfo` でバックグラウンド転送 |
| HealthKit未許可 | アプリは落ちない、デモデータで継続 |
| 心拍数取得失敗 | デモデータにフォールバック |
| HRV取得失敗 | 心拍だけWatch受信、HRVはHealthKit最新値またはデモ値 |

---

## 実機確認手順

1. iPhoneにアプリをインストール（MindWaveGraphicスキーム）
2. Apple WatchにWatchアプリをインストール（MindWaveGraphicWatch Watch Appスキーム）
3. Apple WatchのMind Waveアプリを開き「計測開始」をタップ
4. iPhoneのHomeタブ「Watch ライブ心拍」カードで受信回数が増えることを確認
5. iPhoneのライブタブで波形が拍動に合わせて反応することを確認

### ビルド確認コマンド
```bash
# iOSターゲット
xcodebuild -scheme MindWaveGraphic -destination 'generic/platform=iOS' build

# watchOSターゲット  
xcodebuild -scheme "MindWaveGraphicWatch Watch App" -destination 'generic/platform=watchOS' build
```
