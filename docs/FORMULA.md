# スコア計算式：緊張不安定度

## 概要
心拍数（HR）と心拍変動（HRV）の2指標を用いて、個人の平常時からのズレを0〜100のスコアとして表現する。

---

## 入力値
| 変数名 | 説明 | 単位 |
|--------|------|------|
| `currentHeartRate` | 現在（直近）の心拍数 | bpm |
| `averageHeartRate` | 個人の平常時平均心拍数 | bpm |
| `currentHRV` | 現在（直近）のHRV（SDNN） | ms |
| `averageHRV` | 個人の平常時平均HRV（SDNN） | ms |

> 「平常時平均」は、安静・非ストレス状態で収集した過去データの平均値を使用する。

---

## 心拍上昇率（Heart Rate Increase Rate）

```
heartRateIncreaseRate = (currentHeartRate - averageHeartRate) / averageHeartRate
```

- 現在の心拍数が平常時より高い → 正の値になる
- 平常時と同じ → 0
- 平常時より低い → 負の値になる

---

## HRV低下率（HRV Decrease Rate）

```
hrvDecreaseRate = (averageHRV - currentHRV) / averageHRV
```

- 現在のHRVが平常時より低い → 正の値になる（HRVが低い = ストレス状態）
- 平常時と同じ → 0
- 平常時より高い → 負の値になる（リラックス状態）

---

## 緊張不安定度（Stress Score）

```
stressScore = 50 + 100 × ((heartRateIncreaseRate + hrvDecreaseRate) / 2)
```

- 2指標の平均を取ることで、片方のノイズの影響を軽減する
- 平常時（両率ともに0）のとき → スコアは 50
- 緊張・ストレス時（両率ともに正）→ スコアは 50 より大きくなる
- リラックス時（両率ともに負）→ スコアは 50 より小さくなる

---

## 0〜100へのclamp

```
stressScore = max(0, min(100, stressScore))
```

- 計算式の結果が 0 未満になった場合は 0 に切り上げる
- 100 を超えた場合は 100 に切り下げる
- これにより、出力は常に 0〜100 の範囲に収まる

---

## 設計上の判断理由

### なぜ絶対値ではなく平均からの変化率を見るのか
個人によって、安静時の心拍数は40〜90bpm程度まで幅がある。例えば心拍数70bpmが「高い」かどうかは、その人の平常時が何bpmかによって全く異なる。絶対値では個人差を補正できないため、「その人自身の平常時からどれだけ変化しているか」という変化率を基準にする。

### なぜHRVは「上昇率」ではなく「低下率」を見るのか
HRVはリラックス・副交感神経優位のときに高くなり、ストレス・交感神経優位のときに低くなる指標である。つまり、HRVの低下がストレス・緊張を意味する。心拍上昇率と同じ方向（値が大きいほどストレス状態）に揃えるため、「低下率」として定義している。

### なぜ心拍とHRVの2指標を組み合わせるのか
心拍数だけでは運動や体動の影響を受けやすく、HRVだけではデータのノイズが大きい。2指標の平均を取ることで、それぞれの弱点を補い合い、より安定したスコアを算出できる。

---

## 現段階で使用するHRV指標
- **heartRateVariabilitySDNN**（HealthKitで取得できるHRV指標）
- SDNN（Standard Deviation of NN intervals）：NN間隔の標準偏差。Apple WatchのHealthKitではSDNNが標準で提供される。
- RMSSD（連続するNN間隔差の二乗平均平方根）は副交感神経活動との相関が強いとされ、将来的な検討候補とする。

---

## Swift実装イメージ（参考）

```swift
func calcStressScore(
    currentHR: Double,
    averageHR: Double,
    currentHRV: Double,
    averageHRV: Double
) -> Double {
    let hrIncreaseRate = (currentHR - averageHR) / averageHR
    let hrvDecreaseRate = (averageHRV - currentHRV) / averageHRV
    let score = 50 + 100 * ((hrIncreaseRate + hrvDecreaseRate) / 2)
    return max(0, min(100, score))
}
```
