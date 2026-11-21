# もこりん AI の構成（画面をまたぐ AI 体験）

作成: 2026-11-05 / ブランチ `feature/mokorin-voice-ui-20261028`
関連: [APP_NAVIGATION_AUDIT.md](APP_NAVIGATION_AUDIT.md)（画面遷移）、[MOKORIN_PERSONALIZED_ADVICE.md](MOKORIN_PERSONALIZED_ADVICE.md)（提案）、[MOKORIN_E2E_RESULTS.md](MOKORIN_E2E_RESULTS.md)（検証）

## 1. 方針

- 画面ごとに AI を作り直さない。**会話の通信は既存の 2 つの API だけ**を使う
  - 測定前の状況整理: `POST /v1/context-assist`（Structured Outputs）
  - 結果・振り返りでの自由な質問: `POST /v1/chat`（AI 相談と同じ）
- 測定値の説明・比較・提案は**端末内で決定的に作る**（既存の値を読むだけ。計算は変えない）。外部 AI には送らない
- もこりんは「必要なときだけ」出す。測定前は中央に大きく、測定中は 1 行、結果・振り返りは利用者がボタンを押したときだけシートで

## 2. 部品と責務

| 責務（依頼書の例） | 実際の型 | ファイル（`MindWaveGraphic/MindWaveGraphic/`） |
|---|---|---|
| 画面をまたぐ状態（Coordinator 相当） | `AppFlowState.mokorinMemory`（測定前の会話で理解した内容を、結果画面へ渡す） | `App/AppFlowState.swift` |
| 会話の状態（測定前） | `MokorinContextViewModel`（段階・候補・訂正・意図・話題・送信状態） | `Mokorin/MokorinContextViewModel.swift` |
| 会話の状態（結果・振り返り） | `MokorinCompanionViewModel`（説明の進み具合・選択肢・確認は 1 回だけ）＋既存の `ChatViewModel` | `Mokorin/MokorinCompanionViewModel.swift`、`Chat/ChatViewModel.swift` |
| ContextProvider（画面のデータ） | `MokorinResultInput`（`GuideSnapshot`・`GuideSessionRecord` から作る）、`MokorinSessionMemory` | `Mokorin/MokorinResultExplainer.swift`、`Mokorin/MokorinAdviceEngine.swift` |
| 説明の生成 | `MokorinResultExplainer`（事実・解釈・不足・注意・比較） | `Mokorin/MokorinResultExplainer.swift` |
| AdviceEngine | `MokorinAdviceEngine`・`MokorinTopic` | `Mokorin/MokorinAdviceEngine.swift` |
| MokorinView | `MokorinAvatarView`（友達の原本を WKWebView で表示）、`MokorinCompanionView`（シート）、`ContextCalibrationView`（測定前） | `Mokorin/`、`Authentication/` |
| AIService | 既存の `RemoteContextAssistClient`・`RemoteChatClient`（認証・タイムアウト・エラー分類は共通） | `Mokorin/MokorinContextServices.swift`、`Chat/ChatServices.swift` |

新しいクラスは `MokorinCompanionViewModel` だけ。説明・提案は状態を持たない関数（enum の static 関数）にして、テストしやすくした。

## 3. データの流れ

```mermaid
flowchart LR
  subgraph 測定前
    U1[利用者の発言] --> CVM[MokorinContextViewModel]
    CVM -->|同意時のみ: 会話本文・現在の選択| CA[/v1/context-assist/]
    CA -->|scene/conditions/tension\nsituation_note/user_intent| CVM
    CVM -->|この状況で測定する| FS[AppFlowState\nmeasurementContext・mokorinMemory]
  end
  subgraph 測定と保存（変更なし）
    FS --> VM[MindWaveViewModel\nHealthKit・Watch・StressScoreCalculator]
    VM --> GF[GuideFlowView] --> HS[(GuideHistoryStore)]
  end
  subgraph 結果・振り返り
    GF -->|GuideSnapshot 前後| RX[MokorinResultExplainer]
    HS -->|同じ場面の記録| RX
    FS -->|6時間以内の会話だけ| RX
    RX --> AE[MokorinAdviceEngine]
    RX --> COMP[MokorinCompanionViewModel]
    COMP -->|端末内の説明\norigin=local・送らない| CHAT[ChatViewModel]
    U2[利用者の質問] --> CHAT -->|同意時のみ: 利用者の発言と AI の返答だけ| CH[/v1/chat/]
  end
```

## 4. 会話状態の管理

- 測定前（`MokorinContextViewModel`）: 段階 tension → scene → condition → review は「回答済みか」から計算する。AI が場面・身体状態を返したら提案として反映し、本人が確認して測定へ進む
  - `situation_note`: 既存の場面に分類しきれない予定（試験・初対面など）を自由文で保持。**場面の列挙値は増やさない**（試験は `work`、初対面は `important` などの既存値に分類し、細かい違いは `MokorinTopic` で言い回し・提案に使う）
  - `user_intent`: `decline_measurement` なら説得せず「測定しないで終える」を出す。`ready` なら未確認の項目を聞かずにまとめへ。`question` は短く答えて話を戻す（AI なしのときは答えられないと正直に伝える）
  - 訂正は最新の発言を優先（端末内の判定・サーバーの指示の両方）
- 結果・振り返り（`MokorinCompanionViewModel`）: 最初の吹き出し（事実の要約と不足データ）→ 選択肢「どういう意味？」「前と比べる」「次にできること」（最大 3 つ、選んだものは消える）→ 提案のあとに 1 回だけ確認 → 自由な質問
- どちらもメモリのみ。シートを閉じる・「最初から」・ログアウトで消える。保存先は増やしていない

## 5. 外部 AI へ送るもの

| 経路 | 送るもの | 送らないもの |
|---|---|---|
| `/v1/context-assist` | 本人の同意後、測定前の会話の本文（直近 12 件・上限あり）、画面の現在の選択（場面・身体状態・主観的な緊張） | 心拍・HRV・スコア・記録 |
| `/v1/chat`（結果・振り返り） | 本人の同意後、本人が入力した質問と AI の返答、場面 | もこりんの端末内の説明（測定値を含む）、選択肢で選んだ言葉。計測要約は既存の `ChatBiometricPolicy` が許可したときだけ（現在は本物の利用者認証がないため送らない） |

サーバーのログには件数・状態・トークン数・エラー分類だけを記録し、会話本文は記録しない（既存のまま）。

## 6. API の互換性

- `/v1/context-assist` の結果に `situation_note`（string|null）と `user_intent`（answer / question / decline_measurement / ready）を追加（2026-11-05）
  - サーバー: Structured Outputs の strict のため schema では required。モデルの出力に無い・不正・長すぎる値は `null` / `answer` に置き換え、他の候補の採否には影響させない
  - アプリ: どちらも省略可能（古いサーバーでも動く）。未知の `user_intent` は `answer` として扱い、画面は止まらない
  - 既存の項目の意味は変えていない
- `/v1/chat` は変更なし

## 7. AI 未接続のとき

- 測定前: 端末内のキーワード判定と定型文で会話（「端末内の定型文」と表示）。通信失敗は「もう一度送る」「AIなしで続ける」
- 結果・振り返り: 説明・比較・提案はもともと端末内なので同じように使える。自由な質問は、説明から答えられるもの（比較・意味・次にできること・HRV）は答え、それ以外は既存の定型アドバイス（「端末内」と表示）
- どの状態でも測定と保存はできる（もこりんを経由しない）
