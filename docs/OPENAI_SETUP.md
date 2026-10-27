# OpenAI API 連携セットアップ

Mind Wave Graphic は、ガイド結果の「振り返り（AIインサイト）」を外部AI（OpenAI）で生成できる。
**OpenAI の APIキーは iOS アプリにも GitHub にも置かない。** アプリ → 自前APIサーバー（`server/`、Cloudflare Workers）→ OpenAI の順で呼び出す。

```text
iOS (GuideFlowView)
  └ InsightService ── 条件を満たさない/失敗 ──▶ LocalInsightProvider（既存のローカルAI・通信なし）
        │ 同意あり・サーバー設定あり・実測データのみ
        ▼
  RemoteInsightProvider ── POST /v1/insights（Bearer クライアントトークン、要約のみ）
        ▼
  server/ (Cloudflare Worker)  認証 → 契約検証 → 同意確認 → OpenAI Responses API（Structured Outputs, strict, store:false）
        ▼                       → 出力の型・文字数・禁止表現を検証 → 免責文を固定文言で上書き
  iOS で再検証（InsightValidation）→ 表示・履歴へ保存（localAIVersion = "remote:openai:<model>"）
```

## 1. 検証状況（2026-10-28 時点）

| 項目 | 状態 |
|---|---|
| サーバー実装（認証・検証・OpenAI 呼び出し・エラー処理・タイムアウト） | 実装済み・ローカルテスト 22 件成功 |
| iOS 実装（抽象化・リモート/ローカル切替・フォールバック・同意設定） | 実装済み・シミュレーターでテスト成功 |
| iOS ⇄ ローカルサーバー（OpenAI スタブ）E2E | 成功（シミュレーター → `127.0.0.1:8787`） |
| **OpenAI 実API との通信** | **未検証**（APIキーなし・課金を伴うため未実施） |
| **Cloudflare へのデプロイ** | **未実施**（アカウント権限なし） |

## 2. 必要な環境変数（サーバー）

| 名前 | 種別 | 説明 |
|---|---|---|
| `OPENAI_API_KEY` | secret | OpenAI の APIキー。**`wrangler secret put` で登録。ファイルに書かない** |
| `CLIENT_TOKENS` | secret | iOS アプリが送る Bearer トークン（カンマ区切りで複数可、各16文字以上）。未設定なら全リクエスト 401 |
| `OPENAI_MODEL` | var | 使用モデル。既定 `gpt-4o-mini`（Structured Outputs 対応モデルを指定） |
| `OPENAI_TIMEOUT_MS` | var | OpenAI 呼び出しのタイムアウト。既定 15000 |
| `OPENAI_BASE_URL` | var | 既定 `https://api.openai.com/v1`。通常は変更しない |

## 3. ローカルで動かす（APIキー不要）

Node.js 22.18 以上（TypeScript をそのまま実行できるバージョン）が必要。

```bash
cd server
npm install            # 型チェック用の typescript だけが入る（実行時依存なし）
npm test               # 契約・OpenAI 呼び出し・ハンドラーのテスト（OpenAI へは送信しない）
npm run typecheck

# OpenAI スタブで起動（課金なし）
CLIENT_TOKENS=dev-token-0123456789abcdef npm run dev:stub
# 異常系の再現: STUB_OPENAI_MODE=timeout|http_500|refusal|invalid_json|prohibited
curl -s http://127.0.0.1:8787/v1/health
```

### iOS シミュレーターから接続する

DEBUG ビルドでは環境変数で接続先を指定できる（ソースにトークンを書かない）。

```bash
SIMCTL_CHILD_MW_INSIGHT_BASE_URL=http://127.0.0.1:8787 \
SIMCTL_CHILD_MW_INSIGHT_CLIENT_TOKEN=dev-token-0123456789abcdef \
xcrun simctl launch --terminate-running-process booted com.kobayashiproject2026.mindwavegraphic
```

その後、アプリの「設定 → PRIVACY → 外部AIで振り返りを生成」を ON にし、**Mock OFF（実測）** でガイドを完了すると、結果画面のインサイトがサーバー経由の内容に置き換わる（Mock 計測中は送信しない）。
Xcode から起動する場合は Scheme → Run → Arguments → Environment Variables に同じ名前（`SIMCTL_CHILD_` なし）で設定する。

### E2E テスト

```bash
CLIENT_TOKENS=e2e-token-0123456789abcd npm --prefix server run dev:stub &
SIMCTL_CHILD_MW_E2E_BASE_URL=http://127.0.0.1:8787 \
SIMCTL_CHILD_MW_E2E_CLIENT_TOKEN=e2e-token-0123456789abcd \
scripts/run_ios_core_tests.sh
```

## 4. 実際の OpenAI で動かす（ローカル）

```bash
cd server
cp .dev.vars.example .dev.vars   # .dev.vars は .gitignore 済み
# .dev.vars に OPENAI_API_KEY と CLIENT_TOKENS を記入
npm run dev                      # ※ 実API呼び出しは課金される
```

## 5. デプロイ手順（Cloudflare Workers）

```bash
cd server
npx wrangler@4 login
npx wrangler@4 secret put OPENAI_API_KEY
npx wrangler@4 secret put CLIENT_TOKENS
npx wrangler@4 deploy
curl -s https://<worker-subdomain>.workers.dev/v1/health
```

iOS アプリ側の設定（本番）: UserDefaults キー `mindwave.insight.baseURL`（https のみ）と `mindwave.insight.clientToken`。
現状は設定画面に入力欄がなく、DEBUG の環境変数でのみ指定できる（§7 の課題）。

## 6. セキュリティ・プライバシーの設計

- APIキーはサーバーの secret のみ。レスポンス・ログ・`/v1/health` に出さない（テストで確認）
- 送信は「ガイド1回分の丸めた要約」のみ。サーバーは未知のキーを含むリクエストを 400 で拒否する（メモ・日時・HRV 実数値・個人情報が混入しても OpenAI へ渡らない）
- 外部送信の条件: ①設定画面で同意（既定 OFF・同意文言の版管理あり）②サーバー設定あり ③Mock データを含まない。サーバー側も `external_ai_consented=false` を 403 で拒否
- OpenAI 呼び出しは `store: false`
- モデル出力は strict JSON Schema ＋サーバーと iOS の二重検証（文字数・禁止表現・`request_id` 一致）。免責文はサーバーが固定文言で上書き
- サーバーログは request_id・結果・HTTP ステータス・所要時間のみ
- タイムアウト: OpenAI 15 秒（サーバー）/ リクエスト全体 20 秒（iOS）。失敗時は必ずローカルAIの結果を表示

## 7. 今後の課題

1. **ユーザー認証**: 現在の Bearer クライアントトークンはアプリから取り出せる。本番前に Firebase Authentication の ID トークン検証、または App Attest に置き換える（アプリの認証画面も現在はモック）
2. **レート制限**: Cloudflare の Rate Limiting バインディング等で、トークン/ユーザーごとの上限を設ける
3. **接続先の設定 UI**: 本番 URL をビルド設定（xcconfig）か設定画面で指定できるようにする
4. **プロンプト評価**: 実API で出力品質・禁止表現の発生率を評価してから有効化する
