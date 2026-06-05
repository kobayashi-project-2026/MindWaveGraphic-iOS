# HealthKit連携方針

## 使用するHealthKitデータ型

### 心拍数（Heart Rate）
- **識別子**：`HKQuantityTypeIdentifier.heartRate`
- **単位**：bpm（beats per minute）
- **取得元**：Apple Watch（バックグラウンド・フォアグラウンド両方で取得可能）
- **用途**：現在の心拍数と個人平均の比較による心拍上昇率の算出

### 心拍変動（HRV: SDNN）
- **識別子**：`HKQuantityTypeIdentifier.heartRateVariabilitySDNN`
- **単位**：ミリ秒（ms）
- **取得元**：Apple WatchのHRV測定機能（主に深呼吸セッション・睡眠中に自動取得）
- **用途**：現在のHRVと個人平均の比較によるHRV低下率の算出

---

## 各指標の選定理由

### heartRateVariabilitySDNN を使う理由
Apple WatchがHealthKitを通じて標準提供するHRV指標がSDNNであるため、追加の処理なしに取得できる。実装の複雑さを抑えつつ、緊張状態の変化を捉えることができる。

### RMSSDは将来的な検討とする理由
RMSSDは副交感神経活動をより直接的に反映するとされ、ストレス評価研究でよく使われる指標である。ただし、Apple WatchのHealthKitから直接取得できるのはSDNNであるため、RMSSDを使うには生のRRデータを取得・加工する必要がある。実装コストが高いため、まず使えるSDNNで進め、将来的に精度改善の必要が生じた段階でRMSSDへの移行を検討する。

---

## 実装状況（フェーズ2開始）

HealthKit連携の土台を `HealthKitManager.swift` と `MindWaveViewModel.swift` として追加した。

### 読み取るデータ型
- `HKQuantityTypeIdentifier.heartRate`（心拍数、bpm）
- `HKQuantityTypeIdentifier.heartRateVariabilitySDNN`（HRV、ms）

### 書き込みは行わない
- `toShare` は空の Set を渡す

### HealthKitデータが取得できない場合の挙動
- Apple Watch未接続・データなしの場合は `MindSampleScenario` のデモデータにフォールバックする
- UIには `デモデータで表示中` と必ず表示する
- アプリは落ちない（HealthKit未接続でも動作する）

### Apple Watch との接続構成
- Apple Watch → HealthKitに心拍数・HRVを記録
- iPhone上の HealthKitStore → `HealthKitManager` → `MindWaveViewModel` → UI

### 権限設定
- `NSHealthShareUsageDescription` を build settings に追加済み
- `MindWaveGraphic.entitlements` に `com.apple.developer.healthkit` を追加済み
- **Xcode で Signing & Capabilities の HealthKit Capability を手動追加が必要**（下記参照）

---

## 開発フェーズとHealthKit

### フェーズ1：ダミーデータMVP（完了）
HealthKit連携なしで、ハードコードしたダミーの心拍数・HRV値を使い、スコア計算とUI表示を確認する。

**ダミーデータMVPを先に作る理由：**
- HealthKit連携にはApple Developerアカウントと実機（Apple Watch + iPhone）が必要
- HealthKitの利用許可申請・テストが開発の早い段階でボトルネックになることを避ける
- 計算式やグラフィック表現の妥当性をまず確認してから、データ取得部分を繋げる
- チーム内で発表・共有する際に、デバイスがなくても動作確認できる

### フェーズ2：HealthKit連携実装
- Apple WatchからiPhoneへの心拍・HRVデータの取得フローを実装する
- HealthKitの利用許可リクエストをアプリに組み込む
- フェーズ1のスコア計算・UI部分を、実データと接続する

---

## デバイス構成
```
Apple Watch
    ↓ 心拍数・HRV測定
HealthKit（iPhone内）
    ↓ HKHealthStore経由でデータ取得
iPhone（このアプリ）
    ↓ スコア計算・グラフィック表示
```

## スマホ1台化は将来構想として扱う
現段階では Apple Watch + iPhone + HealthKit を前提とする。将来的には、スマホカメラを用いたrPPG（Remote Photoplethysmography）技術により、Apple Watchなしでスマホ1台から心拍・HRVを推定する構成を検討する。ただし、rPPGは照明条件・肌色・動きに大きく影響されるため、精度の確保が課題となる。

---

## HealthKit利用時の注意事項
- `Info.plist` に `NSHealthShareUsageDescription`（読み取り用途の説明文）を記載する必要がある
- HealthKitのデータ取得には、ユーザーからの明示的な許可が必要
- シミュレータではHealthKitデータを利用できないため、実機テストが必要
- 取得したデータはHealthKitの利用規約に従って扱う（第三者送信の制限等）
