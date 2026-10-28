# AI 相談（OpenAI 複数往復会話）のセットアップ

構成は docs/OPENAI_CHAT_ARCHITECTURE.md、テスト結果は docs/OPENAI_CHAT_TEST_REPORT.md。
**APIキーの値は、このドキュメント・ソースコード・Git・チャット・スクリーンショットに書かないこと。**

---

## 0. 現状と、実通信までに必要な操作

| 段階 | 状態 |
|---|---|
| LEVEL 1: iPhone 上でチャット画面が動作する | 完了（シミュレーター） |
| LEVEL 2: 自前サーバー＋OpenAI スタブで複数往復の会話 | 完了（自動テスト＋シミュレーター画面で 3 往復） |
| LEVEL 3: 実際の OpenAI API と通信し、前の会話を踏まえた回答が返る | **未実施**（APIキー・課金の承認がないため） |

LEVEL 3 の確認に必要な操作（統合責任者が行う）: §1 → §2 → §4 → §5。所要 15〜30 分、OpenAI の利用料は数円程度（§5 の目安）。

## 1. OpenAI API アカウントの準備

1. https://platform.openai.com にサインインし、組織（Organization）とプロジェクト（Project）を作る。研究室・チームで使う場合は個人ではなく組織のプロジェクトを使う
2. **課金設定が必要**: Settings → Billing で支払い方法を登録し、クレジットを購入する（API は ChatGPT の有料プランとは別課金）。クレジットがないと API は 429（`insufficient_quota`）を返す
3. 使いすぎ防止: Settings → Limits（プロジェクトの Usage limits）で月の上限額と通知を設定する
4. 使用モデル `gpt-6-luna` がプロジェクトで利用可能か、Limits → Models で確認する

## 2. APIキーの発行と安全な設定

1. プロジェクトの API keys で **プロジェクト単位のキー**を発行する（権限は可能なら Responses の書き込みのみに制限）
2. 表示されたキーは一度しか見られない。パスワードマネージャーに保存し、**Slack・メール・Git・スクリーンショットに貼らない**
3. ローカル開発: `server/.dev.vars`（`.gitignore` 済み）に書く

```bash
cd server
cp .dev.vars.example .dev.vars
# エディタで .dev.vars を開き、OPENAI_API_KEY= の右に貼り付ける
# CLIENT_TOKENS= には、次のコマンドで作ったランダム文字列を入れる（アプリとサーバーで同じ値を使う）
openssl rand -hex 24
git status --short   # .dev.vars が表示されない（追跡されない）ことを確認
```

4. 本番（Cloudflare）: `npx wrangler@4 secret put OPENAI_API_KEY` で登録する（wrangler.toml には書かない）
5. キーが漏れた疑いがあれば、すぐに OpenAI の画面で失効（Revoke）して作り直す

## 3. ローカルサーバーの起動（スタブ・課金なし）

Node.js 22.18 以上が必要（TypeScript をそのまま実行する）。

```bash
cd server
npm install        # 型チェック用 typescript のみ
npm test           # 38 件（OpenAI へは送信しない）
CLIENT_TOKENS=dev-token-0123456789abcdef npm run dev:stub
# → [dev-server] STUB MODE: OpenAI へは送信しません
curl -s http://127.0.0.1:8787/v1/health
```

スタブの返答は先頭に「（スタブ応答・実際のAIではありません）」が付き、アプリには「スタブ応答（stub-model）・実際のAIではありません」と表示される。
返答は受け取った履歴の件数・最初の相談・直前の質問を機械的に引用するだけで、AI の生成ではない（履歴が順番どおり届いていることの確認用）。
異常系: `STUB_OPENAI_MODE=timeout|http_429|http_401|http_500|invalid_json|refusal|prohibited`

## 4. iPhone シミュレーターの接続

DEBUG ビルドだけが環境変数で接続先を受け付ける（本番アプリに開発用の設定は埋め込まれない）。

**Xcode から起動する場合**: Scheme → Edit Scheme → Run → Arguments → Environment Variables に追加

| 名前 | 値 |
|---|---|
| `MW_INSIGHT_BASE_URL` | `http://127.0.0.1:8787`（https 以外は localhost / 127.0.0.1 のみ許可） |
| `MW_INSIGHT_CLIENT_TOKEN` | `.dev.vars` の `CLIENT_TOKENS` と同じ値 |

**コマンドで起動する場合**（ビルド済みアプリをインストール後）:

```bash
SIMCTL_CHILD_MW_INSIGHT_BASE_URL=http://127.0.0.1:8787 \
SIMCTL_CHILD_MW_INSIGHT_CLIENT_TOKEN=<CLIENT_TOKENS と同じ値> \
xcrun simctl launch --terminate-running-process booted com.kobayashiproject2026.mindwavegraphic
```

アプリでの操作: 「整える」タブ →「AIに相談する」（または右上の共通メニュー →「AI相談」）→ 同意カードの「同意して外部AIを使う」→ 文章を入力して送信。
同意は設定画面の「AI相談の文章を外部AIへ送信」で取り消せる。

検証用（DEBUG のみ）: `MW_CHAT_TEST_CONSENT=1|0`（同意あり／なしにする）、`MW_CHAT_AUTOPLAY="文1||文2"`（画面表示後に順番に送信）、`INITIAL_SCREEN=aiChat`、`SKIP_ONBOARDING=1`。

## 5. 実際の OpenAI で複数往復の会話を確認する（課金あり・統合責任者の承認後に実施）

```bash
cd server
npm run dev        # .dev.vars の OPENAI_API_KEY を使う
# → [dev-server] REAL MODE: OpenAI API へ実際に送信します（API 利用料が発生します）。モデル=gpt-6-luna
curl -s http://127.0.0.1:8787/v1/health      # "openai_configured":true を確認
```

シミュレーターを §4 のとおり接続し、AI相談で次の順に送る:

1. 「面接前で緊張しています」
2. 「さっき言っていた呼吸法を詳しく教えて」
3. （任意）「何回くらい繰り返せばいい？」

確認すること:

| 確認項目 | 合格の条件 |
|---|---|
| 返答の出どころ | 吹き出しの上が「OpenAI（gpt-6-luna…）」。「スタブ応答」「端末内の定型アドバイス」ではない |
| 文脈の理解 | 2 回目の返答が、1 回目で AI が提案した呼吸法を具体的に説明している（固定文ではない） |
| 安全性 | 診断・病名の断定、薬の指示がない |
| サーバーログ | `chat_request` の `outcome:"ok"`、`input_tokens` / `output_tokens` が記録され、会話本文が出ていない |
| 異常系（任意） | サーバーを止めて送信 →「サーバーに接続できませんでした」＋端末内アドバイス＋再送信ボタン。サーバー再起動後に再送信で OpenAI の返答に置き換わる |

自動 E2E で確認する場合（同じく課金あり）:

```bash
CLIENT_TOKENS=<値> npm --prefix server run dev &
SIMCTL_CHILD_MW_E2E_BASE_URL=http://127.0.0.1:8787 SIMCTL_CHILD_MW_E2E_CLIENT_TOKEN=<値> scripts/run_ios_core_tests.sh
```

※ Chat の E2E テストはスタブの返答形式（「利用者 2 件・AI 1 件」）を検証するため、実 API では失敗するのが正常。実 API の確認は上の画面操作で行う。

費用の目安（`gpt-6-luna`: 入力 $0.10 / 出力 $0.50 per 1M tokens、2026-10-28 時点）: 1 往復あたり入力 約 1,000〜4,000 トークン・出力 最大 600 トークンで、**1 往復 約 $0.0007 以下（0.1 円程度）**。3 往復の確認で 1 円未満。料金は変わるため、実施前に公式の料金ページを確認すること。

結果は docs/OPENAI_CHAT_TEST_REPORT.md の「LEVEL 3」欄に、日時・モデル名・確認者・合否を記録する（会話本文や APIキーは記録しない）。

## 6. Cloudflare へのデプロイ前に必要な作業（現時点ではデプロイしない）

1. **利用者単位の認証**: アプリのログインを本番の認証（例: Firebase Authentication）に接続し、サーバーで ID トークンを検証する。共通のクライアントトークンだけで公開しない
2. **全体共有のレート制限と 1 日の上限**: Cloudflare の Rate Limiting バインディングまたは Durable Objects で、利用者ごと・全体の上限を設ける（現在の制限はインスタンス単位）
3. **OpenAI の Usage limits**: プロジェクトの月額上限と通知
4. **Secrets の登録**: `wrangler secret put OPENAI_API_KEY` / `CLIENT_TOKENS`（または認証方式に合わせた設定）
5. **アプリの接続先**: 本番 URL（https）をビルド設定（xcconfig）で指定する仕組みを作る（現在は DEBUG の環境変数と UserDefaults のみ）
6. **プライバシー**: 外部送信の説明・プライバシーポリシー・App Store のプライバシー表示を更新する。計測データの送信を有効化する場合は別途同意画面を設け、`CHAT_ALLOW_MEASUREMENT_CONTEXT` と `ChatBiometricPolicy` を同時に変更する
7. **品質評価**: 実 API で代表的な相談（面接・発表・試合・睡眠・危機的な内容）を試し、医療的断定や不適切な返答がないことを研究担当と確認する
8. デプロイ: `npx wrangler@4 deploy` → `/v1/health` で確認
