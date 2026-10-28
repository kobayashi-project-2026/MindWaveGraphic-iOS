# AI 相談（OpenAI 複数往復会話）の構成

iPhone アプリ上で、利用者が緊張や不安について文章で相談し、OpenAI が会話の流れを踏まえて答える機能の設計。
状態: **LEVEL 2（自前サーバー＋OpenAI スタブで複数往復を確認）まで完成。LEVEL 3（実際の OpenAI との通信）は未実施**（docs/OPENAI_CHAT_TEST_REPORT.md）。

---

## 1. 通信経路

```
iPhone アプリ（AIChatView → ChatViewModel → RemoteChatClient）
   │  POST /v1/chat   Authorization: Bearer <クライアントトークン>
   │  本文: 直近の会話（最大12件）・選んだ場面・同意情報（JSON、ChatRequestDTO）
   ▼
自前サーバー（server/、Cloudflare Workers）
   │  認証(401) → レート制限(429) → サイズ(413) → 契約検証(400) → 計測データの可否(403) → APIキー確認(503)
   │  会話を Responses API の input に順番どおり並べる（instructions に安全方針）
   │  POST https://api.openai.com/v1/responses   Authorization: Bearer <OPENAI_API_KEY>（サーバーだけが持つ）
   │  store: false / max_output_tokens / reasoning.effort
   ▼
OpenAI Responses API
   │  output_text・usage・status（completed / incomplete）
   ▼
自前サーバー
   │  本文の取り出し・検証（空・長さ・医療的断定表現・拒否）、usage をログに記録（本文は記録しない）
   │  200: { reply: { text, truncated }, provider, model, usage }
   ▼
iPhone アプリ
      返答を表示。出どころを必ず表示する:
      「OpenAI（モデル名）」/「スタブ応答・実際のAIではありません」/「端末内の定型アドバイス（AIではありません）」
```

| 層 | ファイル |
|---|---|
| 画面 | `MindWaveGraphic/MindWaveGraphic/Chat/AIChatView.swift` |
| 会話状態 | `Chat/ChatViewModel.swift` |
| 通信・代替応答・同意・送信可否・履歴の上限 | `Chat/ChatServices.swift` |
| JSON 契約（iOS） | `Contracts/ChatContracts.swift` |
| サーバー入口 | `server/src/index.ts`（`/v1/chat`） |
| 会話処理・OpenAI 呼び出し | `server/src/chat.ts` |
| レート制限 | `server/src/ratelimit.ts` |
| ローカル用スタブ | `server/scripts/stub-openai.ts`（本番の Worker からは読み込まない） |

既存の単発アドバイス（ガイド結果のインサイト、`POST /v1/insights`）は変更せず、接続先とクライアントトークン（`RemoteInsightConfiguration`）を共用する。

## 2. 画面遷移

- 入口: 「整える」タブの「AIに相談する」カード、または共通メニュー「AI相談」
- どちらも `AppNavigationManager.navigate(to: .aiChat)` → `AppModal.aiChat` としてシートで表示（`AppModalDestinationView`）。新しいナビゲーション状態は作っていない
- 会話状態 `ChatViewModel` は `AppRootContainerView` が所有し、画面を閉じても起動中は保持する。**「タイトルへ戻る」（ログアウト）で必ず消去**する

## 3. 会話状態の保持

| 項目 | 方針 |
|---|---|
| 保持する場所 | **iPhone アプリのメモリ上のみ**（`ChatViewModel.messages`）。端末のストレージ・サーバー・外部データベースには保存しない |
| OpenAI への渡し方 | 毎回、直近の会話を Responses API の `input` に user / assistant の順で並べて送る（公式資料の「手動で履歴を渡す」方式） |
| OpenAI 側の保存 | `store: false`。`previous_response_id`・Conversations API（無期限保存）は使わない |
| 履歴の上限 | 最大 12 件（直近 6 往復）、利用者の1発言 500 字、AI の発言 1500 字、合計 8000 字。超える分は古い順に送らない（アプリ・サーバー両方で制限） |
| 会話の区別 | 会話ごとに `conversation_id`（UUID）を付ける。リセットで作り直し、リセット前に送った要求の応答が後から届いても破棄する |
| 同時送信 | 送信中は次の送信を受け付けない（ボタン無効化＋状態で二重に防止） |
| 失敗時 | 利用者の発言に「外部AIに届きませんでした」を付け、端末内の定型アドバイスを表示。「再送信」で代替の返答を取り除いて送り直す。端末内アドバイスは AI の発言ではないため、外部へ送る履歴に含めない |
| 別の利用者との混在 | 会話はアプリ起動中のメモリのみ。ログアウト時に消去。サーバーは会話を保持しない（リクエスト単位で完結） |

## 4. 外部へ送信される情報

| 情報 | 送信 | 条件 |
|---|---|---|
| 利用者が入力した文章・この画面の直近の会話 | ○ | 「入力した文章を外部AIへ送る」同意（AI相談画面の同意カード、設定画面で取り消し可能）＋サーバー設定あり |
| 状況確認で選んだ場面（安静・面接など） | ○ | 同上 |
| 計測の要約（データソース・Mock か・状態・HRV の状態・ベースラインの状態・データの古さ。**数値は含めない**） | **×（現在は送らない）** | 外部AI同意 **かつ** 本物の利用者認証（`ChatBiometricPolicy`）**かつ** サーバーの `CHAT_ALLOW_MEASUREMENT_CONTEXT=true`。現在のログインはモックのため、アプリ・サーバーの両方で無効 |
| 心拍・HRV の値、分析履歴、ガイドの記録、メモ、日時、端末ID、氏名、メール | × | 送信する経路自体がない |

未同意・サーバー未設定でも、端末内の定型アドバイス（呼吸法・面接・発表・試合などの一般的なセルフケア）で相談できる。

## 5. 利用者認証

| 段階 | 現状 | 本番公開前に必要なこと |
|---|---|---|
| アプリ → サーバー | 共通のクライアントトークン（Bearer）。端末から取り出せるため、**公開アプリの認証としては不十分** | 利用者単位の認証（例: Firebase Authentication の ID トークンをサーバーで検証）、または App Attest。トークンごと・利用者ごとのレート制限と 1 日の上限 |
| サーバー → OpenAI | OpenAI APIキー（Cloudflare Secrets。アプリ・Git には置かない） | プロジェクト単位のキー、利用上限（Usage limits）の設定 |
| 計測データの送信 | 無効 | 利用者認証の導入後に、同意画面・プライバシーポリシーを整えて有効化を判断 |

## 6. 安全・費用の管理

- **医療的な扱い**: instructions で診断・病名の断定・治療や薬の指示を禁止し、心配な症状は専門家への相談を勧める。自傷や命の危険を示す内容には相談窓口・119 への連絡を勧める。サーバーは明らかな断定表現（「と診断します」等）を含む返答を拒否し、アプリは全画面に「医療的な診断ではありません」と表示する
- **費用**: 既定モデル `gpt-6-luna`（公式の低コストモデル。入力 $0.10 / 出力 $0.50 per 1M tokens、2026-10-28 確認）、`reasoning.effort = low`、`max_output_tokens = 600`（推論分を含む）。履歴の上限で入力も制限する。出力上限に達した返答は `truncated` として「途中で終わっています」と表示
- **呼び出し回数**: トークン単位で 1 分 20 回（インスタンス単位の簡易制限）。**本番前に Cloudflare の Rate Limiting／Durable Objects による全体共有の制限が必要**
- **ログ**: サーバーは `event / outcome / status / request_id / latency_ms / model / messages / input_tokens / output_tokens / reasoning_tokens` のみ記録。会話本文・場面・トークン・APIキーは記録しない。アプリのログも件数・モデル名・失敗コードのみ
- **キー未設定**: サーバーは 503 `not_configured` を返し、アプリは「サーバーにAIが設定されていません（APIキー未設定）」と表示して端末内アドバイスに切り替える。アプリはキーがなくてもビルドできる

## 7. エラーの扱い

| サーバーの応答 | 原因 | アプリの表示 |
|---|---|---|
| 401 `unauthorized` | クライアントトークン不一致 | 「サーバーの認証に失敗しました」＋端末内アドバイス |
| 429 `rate_limited` / `upstream_rate_limited` | サーバーまたは OpenAI の回数制限 | 「混み合っています。少し待ってから再送信」 |
| 400 / 413 | 契約違反・本文が大きすぎる | 「AIの応答を取得できませんでした」 |
| 403 `measurement_context_disabled` / `consent_required` | 計測データを送ろうとした（現在のアプリは送らない） | 同上 |
| 502 `upstream_error` / `upstream_auth_error` / `invalid_upstream_response` / `upstream_refusal` | OpenAI の失敗・キー不正・不正な応答・拒否・禁止表現 | 「AIの応答を取得できませんでした」／「想定外の応答」 |
| 503 `not_configured` | サーバーに APIキーがない | 「APIキー未設定」 |
| 504 `upstream_timeout` | OpenAI のタイムアウト（15 秒、本文受信まで含む） | 「タイムアウトしました」 |
| 接続できない | サーバー停止・通信環境 | 「サーバーに接続できませんでした」 |
| アプリ側タイムアウト（20 秒） | — | 「応答に時間がかかりすぎたため中断しました」 |

いずれの場合も会話は壊れず、端末内の定型アドバイスを表示し、再送信できる。
