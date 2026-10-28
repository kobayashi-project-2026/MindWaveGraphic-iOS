# 統合状況（2026-10-28 時点）

> 監査（docs/INTEGRATION_AUDIT.md）で訂正した箇所と、AI 相談機能（docs/OPENAI_CHAT_ARCHITECTURE.md）を反映済み。

ブランチ: `feature/overnight-integration-20261028`（ローカルのみ・未 push）
凡例: ✅ 実装・自動検証済み / 🟡 実装済み・人による確認が必要 / ⛔ 未実装・ブロック

「ビルド成功」と「機能として統合済み」は区別して記載する。

## 1. 画面・ナビゲーション

| 機能 | 状態 | 根拠・備考 |
|---|---|---|
| スプラッシュ → 案内 → 状況選択 → ホーム | 🟡 | シミュレーターで案内画面まで起動を目視。以降のタップ操作は未自動化（既存コードは変更なし） |
| ホーム／整える／履歴タブ（レバー操作） | 🟡 | Binding を `AppNavigationManager` 経由に変更。双方向の整合はテスト済み、実機のタップは要確認 |
| 共通メニュー → 各画面 | ✅/🟡 | 遷移ロジックはテスト 8 件、設定・状況確認・結果確認（記録なし）・タイトル確認はシミュレーターで描画確認 |
| 状態管理の二重化解消 | ✅ | 認証は AppFlowState、メイン内は AppNavigationManager のみ |
| 状況確認（メインアプリ内） | 🟡 | 計測を作り直さずにコンテキストを更新。「変更しない」で閉じる |
| 結果確認／フィードバック（直近記録） | 🟡 | 記録なし時の案内は描画確認済み。記録ありの表示・メモ保存は単体テストのみ |
| タイトルへ戻る（ログアウト） | 🟡 | 確認ダイアログを描画確認。ライブ計測停止・履歴保持 |
| 存在しない5画面（TitleView 等） | ✅ | 参照を除去し、既存画面へ対応付け（`docs/ARCHITECTURE.md` §2） |

## 2. 計測・データパイプライン

| 機能 | 状態 | 根拠・備考 |
|---|---|---|
| Watch 心拍送信（3チャネル） | 🟡 | 既存実装を維持し、`schemaVersion: 1` を追加。**実機ペアリングでの受信は未検証** |
| Watch 受信の契約検証（v0/v1 互換） | ✅ | テスト 5 件 |
| HealthKit HR/HRV 取得・HRV observer | 🟡 | 既存実装を維持。**実機・実データでは未検証**（シミュレーターに HealthKit データなし） |
| 有効サンプルの優先順位・鮮度・重複 | ✅ | テスト 10 件 + ViewModel E2E |
| スコア算出（既存式と同値） | ✅ | Analyzer と StressScoreCalculator の一致をテスト |
| 個人ベースライン | ✅ | HealthKit7日平均 → 蓄積 → 参照値(provisional)。テスト 7 件 |
| Mock と実測の分離 | ✅ | 分析結果・スナップショット・履歴・AI学習・外部送信で区別（テスト多数） |
| グラフィック更新 | ✅ | GraphicInput の値はテストで確認。描画はホーム画面のスクリーンショットで確認 |
| ガイドへの接続（スナップショット・source・ベースライン） | ✅/🟡 | 単体テスト済み。実ガイドの通し操作は要確認 |

## 3. JSON 契約

| 対象 | 状態 |
|---|---|
| Watch → iPhone 辞書 | ✅ 実装・接続（受信処理で使用） |
| 計測サンプル・測定コンテキスト | 🟡 実装・テストのみ。`MeasurementSampleDTO` は本体から未使用、測定コンテキストは分析結果 JSON（デバッグ表示）内のみ |
| 分析結果・グラフィック入力 | 🟡 分析結果はデバッグ診断画面の表示のみ。`GraphicInputDTO` は本体から未使用 |
| ガイドセッション・履歴 | ✅ 実装・接続（UserDefaults v3 正本、旧 v2 からの自動移行、v2 互換書き込み、v2 のみの記録の取り込み＝監査で修正） |
| AIインサイト要求/応答 | ✅ 実装・接続（iOS ⇄ server、E2E 成功） |
| 個人ベースライン保存 | ✅ 実装・接続 |

## 4. AI

| 機能 | 状態 | 備考 |
|---|---|---|
| ローカルAI（既存） | ✅ | ロジック変更なし（`private` を外しただけ）。同一結果をテストで確認 |
| InsightProvider 抽象化・フォールバック | ✅ | テスト 16 件 |
| 外部送信の同意設定 | 🟡 | 設定画面にトグル追加（既定 OFF）。操作は要確認 |
| サーバー（Cloudflare Worker） | ✅ | テスト 23 件・型チェック OK（監査で本文受信中のタイムアウトを修正） |
| iOS ⇄ ローカルサーバー E2E（OpenAI スタブ） | ✅ | 2 件成功 |
| **OpenAI 実API通信** | ⛔ | APIキーなし・課金のため未実施 |
| **デプロイ** | ⛔ | Cloudflare の権限なし |
| ユーザー単位の認証 | ⛔ | アプリの認証がモックのため。クライアントトークンで代替中 |

## 4.5 AI 相談（OpenAI 複数往復会話、2026-10-28 追加）

| 機能 | 状態 | 根拠・備考 |
|---|---|---|
| 会話 API（`POST /v1/chat`、Responses API・store:false・履歴はアプリ保持） | ✅ | サーバーテスト（合計 38 件中 13 件が会話） |
| レート制限・出力上限・usage 記録・キー未設定時 503 | ✅ | 同上。レート制限はインスタンス単位（本番前に全体共有の制限が必要） |
| iPhone のチャット画面（入力・送信・作成中・エラー・再送信・リセット・出どころ表示） | ✅/🟡 | シミュレーターで表示と自動送信を確認。**手入力・キーボード操作・VoiceOver の読み上げは未確認** |
| 「整える」・共通メニューからの遷移（AppNavigationManager のモーダル） | ✅ | シミュレーターで表示確認、ナビゲーションテスト |
| 複数往復の文脈保持・連打防止・失敗時の代替応答・リセット | ✅ | iOS テスト（会話 24 件） |
| iOS ⇄ ローカルサーバー（OpenAI スタブ）の複数往復 | ✅ | 自動 E2E 3 往復＋シミュレーター画面で 3 往復（スタブと明示表示） |
| 計測データを OpenAI へ送らない（認証がモックのため） | ✅ | アプリ（ChatBiometricPolicy）とサーバー（403）の両方でテスト |
| **実際の OpenAI との会話（LEVEL 3）** | ⛔ | APIキー・課金の承認がないため未実施。手順: docs/OPENAI_CHAT_SETUP.md §5 |
| 利用者単位の認証・Cloudflare デプロイ | ⛔ | 本番公開前に必須（docs/OPENAI_CHAT_SETUP.md §6） |

## 5. 未接続のまま残しているメンバーのコード（削除していない）

| ファイル | 状態 | 判断が必要な点 |
|---|---|---|
| `ContentView.swift`（旧4タブ） | どこからも表示されない | MainTabView に置き換え済み。残すか削除かをチームで決定 |
| `LiveWaveView.swift` | プレビューのみ | 診断機能は DebugDiagnosticsView に移行済み |
| `Breathing/`（MindWaveBreathingGuideView ほか） | プレビューのみ | GuideFlowView の呼吸セッションと機能が重複。統合方針を決める |
| `Shared/CyberUI/MindWaveSyncTransitionView.swift` | プレビューのみ | ガイド開始時の演出として接続するか検討 |
| `Graphics/StarfieldGraphicView.swift` | プレビューのみ | GraphicPlugin の候補として残置 |
| `Graphics/PlaceholderGraphicView.swift` | プラグイン切替の予備 | 現状維持 |
| `GuideSessionView` 構造体（legacy wrapper） | プレビューのみ | `GuideExercise` 等は使用中のためファイルは必要 |
| `MindWaveViewModel.computeConfidence` | 呼び出しなし | Analyzer へ移行済み。参照として残置 |

## 6. 既知の課題（既存挙動・仕様判断が必要）

1. **HRV がない実測では、スコアが常に 38 になる**。`StressScoreCalculator` の `guard averageHRV > 0` による既存挙動。研究スコア・保存値は 38 固定。ホームの表示だけはメンバー実装の表示補正により心拍 100 bpm 以上で変化する（100 未満は変化しない）。鮮度 6 時間の導入で統合前より発生頻度が増える（docs/INTEGRATION_AUDIT.md §9）。指示に従い計算式は変更していない。心拍のみで評価する Analyzer を別途追加して切り替えるのが安全（研究担当の判断が必要）
2. `MindState`（3状態・閾値 32/69）と、計算式コメント・グラフィック側の表記（CALM/FOCUS/ALERT/OVLD）が一致していない
3. 場面の enum が `ContextScene`（状況選択）と `MeasurementScene`（ガイド）の2系統あり、連動していない
4. `project.pbxproj` に旧 Watch コンテナターゲット `MindWaveGraphicWatch`（bundle id `com.takakikeita.*`）が残っている
5. ストレージ空き容量が少なく（約 6 GB）、git の書き込みタイムアウトが2回発生した（再実行で成功）。監査時に、デスクトップの iCloud 同期により `.git` 内のファイルが退避（dataless）されていることを確認（docs/INTEGRATION_AUDIT.md §3）
