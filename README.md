# Mind Wave Graphic

## プロジェクト名
Mind Wave Graphic（マインドウェーブグラフィック）

## 目的
心拍数（Heart Rate）と心拍変動（HRV: Heart Rate Variability）という2つの生体指標をもとに、個人の心理的な「ゆらぎ」（緊張・不安定の度合い）を0〜100のスコアとして推定し、SwiftUIでグラフィックとして可視化する。

単なる数値の表示にとどまらず、心理状態の変化をビジュアルで直感的に伝えることを目指す。

## 使用データ
| データ種別 | 取得方法 | 備考 |
|-----------|---------|------|
| 心拍数（Heart Rate） | Apple Watch + HealthKit | bpm単位 |
| 心拍変動（HRV: SDNN） | Apple Watch + HealthKit | ms単位 |
| 個人の平均値 | 平常時の過去データ | 基準値として使用 |

> 初期MVPではダミーデータを使用し、HealthKit連携なしで動作確認を行う。

## スコア計算の概要
心拍上昇率とHRV低下率を組み合わせて「緊張不安定度」（0〜100）を算出する。

```
心拍上昇率 = (現在の心拍数 - 平均心拍数) / 平均心拍数
HRV低下率  = (平均HRV - 現在のHRV) / 平均HRV
緊張不安定度 = 50 + 100 × ((心拍上昇率 + HRV低下率) / 2)
→ 最終的に 0〜100 の範囲にclamp
```

詳細な式の説明と設計理由は [docs/FORMULA.md](docs/FORMULA.md) を参照。

## 開発方針
- 絶対値ではなく、**個人の平均からの変化率**で判断する
- 最初は **Apple Watch + iPhone + HealthKit** で実装する
- HealthKit連携前に、**ダミーデータを用いたMVP**から始める
- 将来的にはスマホカメラ（rPPG等）を用いたスマホ1台完結の構成も検討する

## 初期MVPの範囲
- [ ] ダミーの心拍数・HRVデータを入力し、スコアを計算する
- [ ] 計算結果をSwiftUIで表示する（数値 + 簡単なグラフィック）
- [ ] HealthKit連携なしで動作確認できる状態にする

## 今後の予定
1. ダミーデータMVPの完成・動作確認
2. HealthKit連携の実装（Apple Watch → iPhone → アプリ）
3. 平常時データの収集と個人平均値の確立
4. 緊張場面でのデータ収集と主観評価との照合
5. グラフィック表現の改善
6. スマホ1台化の技術調査（rPPGなど）

## リポジトリ構成
```
mind-wave-graphic/
├── README.md               # このファイル
├── .gitignore
├── docs/
│   ├── PROJECT_OVERVIEW.md # プロジェクト全体概要
│   ├── FORMULA.md          # スコア計算式の詳細
│   ├── HEALTHKIT_NOTES.md  # HealthKit連携方針
│   ├── ROLE_ASSIGNMENT.md  # 担当分担
│   └── EXPERIMENT_PLAN.md  # 実験・検証計画
└── data/
    └── README.md           # データ管理ルール
```

## 関連ドキュメント
- [開発環境セットアップ](docs/DEVELOPMENT_SETUP.md)
- [プロジェクト概要](docs/PROJECT_OVERVIEW.md)
- [スコア計算式](docs/FORMULA.md)
- [HealthKit連携方針](docs/HEALTHKIT_NOTES.md)
- [担当分担](docs/ROLE_ASSIGNMENT.md)
- [実験計画](docs/EXPERIMENT_PLAN.md)
