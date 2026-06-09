# ライブモニタリング設計方針

## 現在の実装（フェーズ2.2：iPhoneポーリング）

### 仕組み
```
Apple Watch → iPhoneのヘルスケアアプリ（HealthKit）← HealthKitManager（ポーリング）← MindWaveViewModel → LiveWaveView
```

1. Apple Watchが心拍数・HRVをiPhoneのHealthKitに同期する
2. iPhoneアプリが `HealthKitManager` を通じてHealthKitを定期的に読み取る（5秒間隔）
3. 取得した値を `MindWaveViewModel` のプロパティに反映する
4. `LiveWaveView` が `viewModel.stressResult` の変化に応じて波形を更新する

### ポーリング間隔
- 現在：5秒（`liveUpdateInterval = 5`）
- Apple Watchの心拍測定頻度（安静時：数分ごと、運動時：数秒ごと）を考慮
- 5秒ポーリングでも、HealthKitに新しいサンプルがなければ値は変化しない
- その場合 `[Live] no new HealthKit sample` のログが出る

### なぜ完全にリアルタイムでないか
- HealthKit は Push 型のリアルタイムストリームではない
- Apple Watch がiPhoneに同期するタイミングはAppleの制御下にある
- 安静時の心拍は数分おきにしか記録されない
- HRV（SDNN）は深呼吸セッションや睡眠中にしか記録されないことが多い
- そのため、値は「最新で数分前のデータ」になる場合がある

---

## 次のフェーズ（フェーズ3：watchOSアプリ化）

### 目標
Apple Watchで測定した心拍数をリアルタイムに近い形でiPhoneアプリへ送信する。

### 技術的アプローチ

#### watchOSアプリ側
```swift
// HKWorkoutSessionを使って心拍数をリアルタイム取得する
let session = try HKWorkoutSession(healthStore: hkStore, configuration: config)
let builder = session.associatedWorkoutBuilder()
builder.dataSource = HKLiveWorkoutDataSource(healthStore: hkStore, workoutConfiguration: config)

// 心拍データが来たらdelegateで受け取る
func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf: Set<HKQuantityType>) {
    let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))
    // → WatchConnectivityでiPhoneに送信
}
```

#### WatchConnectivity（Apple Watch → iPhone）
```swift
// watchOS側：心拍数をiPhoneに送信する
WCSession.default.sendMessage(["heartRate": heartRate], replyHandler: nil)

// iOS側：受信して波形に反映する
func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    if let hr = message["heartRate"] as? Double {
        viewModel.applyRealtimeHeartRate(hr)
    }
}
```

### HRVのリアルタイム化について
- HRV（SDNN）のリアルタイム測定は技術的に難しい（測定に複数のNN間隔が必要）
- 短時間では心拍数（HR）を主指標として扱う
- HRVは過去の測定値（最新の記録）を補助指標として使う
- HRV のみで完全なリアルタイムスコアを出すことは現段階では難しい

### 実装の優先順位
1. **現在（フェーズ2.2）**: iPhone側HealthKitポーリング ← ここ
2. **フェーズ3**: watchOSアプリ + WatchConnectivityによるリアルタイム心拍送信
3. **フェーズ4**: RMSSD等の短時間HRV計算をwatchOS側で行い、HRVも準リアルタイム化

### 先生・チームへの説明
> 「現在のフェーズでは、Apple WatchがHealthKitに記録したデータをiPhoneが5秒ごとに読み取り、
> 心拍の変化を波形に反映させています。
> HealthKitの同期タイミングに依存するため、秒単位のリアルタイムではありませんが、
> 数秒〜数分単位で心拍の変化がグラフィックに現れます。
> 完全なリアルタイム化はApple Watch側にwatchOSアプリを追加することで実現できます。」

---

## 実装済みの安全策

| ケース | 対処 |
|--------|------|
| HealthKit未許可 | アプリは落ちない、デモデータで継続 |
| 心拍数取得失敗 | デモデータにフォールバック |
| HRV取得失敗 | 心拍だけリアルタイム、HRVはデモ値を維持 |
| 新規サンプルなし | 同じ値で波形を維持、Debug表示で状態確認可能 |
| アプリがバックグラウンドへ | ライブ画面を離れるとTaskを自動キャンセル |
