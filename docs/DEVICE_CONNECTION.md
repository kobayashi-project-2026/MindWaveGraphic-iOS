# iPhone 実機から AI サーバーへ接続する方式と、Xcode スキームの設定

作成: 2026-11-04 / 更新: 2026-11-04（A を Debug ビルド限定で実装）/ ブランチ `feature/mokorin-voice-ui-20261028`
**インターネットへの公開・デプロイはしていない。Release ビルドの通信規則は変えていない。**

## 1. 現状

- 開発用サーバー（`server/scripts/dev-server.ts`）は `127.0.0.1`（この Mac の中だけ）で待ち受ける
- `127.0.0.1` は「その端末自身」を指す。シミュレーターは Mac 上で動くので届くが、**実機の iPhone では iPhone 自身を指すため届かない**。アプリはこの場合に送信せず「実機では 127.0.0.1 は iPhone 自身を指す」と表示する（`ServerConnectionDiagnostics`）
- アプリの接続先の設定（`RemoteInsightConfiguration`）は https、または http のループバック（localhost / 127.0.0.1）を許可。**Debug ビルドに限り**、プライベート IP（10.x / 172.16–31.x / 192.168.x）と `.local` への http も許可（§4）
- Release ビルドの ATS（App Transport Security）は既定のまま
- OpenAI の APIキーはサーバー（`server/.dev.vars` / Cloudflare Secrets）だけが持つ。アプリには入れない

## 2. 方式の比較

| 観点 | A. 同じ Wi-Fi（Mac の LAN アドレス） | B. HTTPS トンネル（例: Cloudflare Tunnel の一時 URL） | C. Cloudflare Workers に HTTPS でデプロイ |
|---|---|---|---|
| セキュリティ | インターネットには出ない。ただし **http（暗号化なし）** のため、同じ Wi-Fi の他の機器から会話本文・クライアントトークンを盗み見られうる。信頼できる自宅などの Wi-Fi 限定 | 通信は HTTPS。ただし **手元の開発サーバーがインターネットに公開される**（URL を知る人は誰でもアクセスを試せる）。認証・回数制限が開発サーバーの簡易版のまま | HTTPS・Cloudflare の基盤。APIキーは Secrets。ただし**公開エンドポイント**になるため、本物の利用者認証と全体の回数制限が必須 |
| 安定性 | Mac が起動していて同じ Wi-Fi にいる間だけ。**大学などの Wi-Fi は端末間通信を遮断していることが多い** | Mac とトンネルが動いている間だけ。一時 URL は起動のたびに変わる | 常時。Mac 不要 |
| 開発の容易さ | サーバー側は準備済み（下記）。アプリ側に ATS の例外・ローカルネットワーク権限・接続先の許可の追加が必要 | トンネルの導入が必要。アプリ側は https なので ATS の変更は不要 | Wrangler でデプロイ。サーバーのコードはそのまま動く設計。認証の追加実装が必要 |
| 費用 | 無料 | 無料（Cloudflare の一時トンネル等） | 無料枠あり（Workers は 1 日 10 万リクエストまで無料、2026-11 時点の公開情報。要確認）。OpenAI の利用料は別 |
| APIキーの保護 | Mac の `.dev.vars` | Mac の `.dev.vars` | Cloudflare Secrets |
| 認証 | 共通のクライアントトークン（LAN 内のみ） | 共通のクライアントトークン → 公開には不十分 | **利用者ごとの認証が必要**（例: Sign in with Apple / Firebase の ID トークンをサーバーで検証、App Attest）。固定の開発用トークンでは公開しない |
| 実機への導入 | Mac の IP を Xcode の環境変数に設定してビルド | トンネルの URL を環境変数に設定 | デプロイ先の URL を設定（本番はビルド設定で） |
| 公開時の拡張性 | なし（開発専用） | なし（開発専用） | そのまま本番の構成になる |

## 3. 推奨

1. **短期（自分の iPhone で試す・承認後）: A（同じ Wi-Fi）を DEBUG ビルド限定で使う。** インターネットに何も公開せず、無料で、既存のサーバーをそのまま使える。条件: 自宅など信頼できる Wi-Fi、テスト中だけサーバーを LAN で起動、終わったら停止、CLIENT_TOKENS を定期的に変更
2. **公開前（チーム・被験者に配る段階）: C（Cloudflare Workers）。** 既存のサーバーは Workers 用に作ってあるため再利用できる。ただしデプロイの前に、利用者ごとの認証・全体の回数制限・OpenAI の使用上限を実装・設定する（下記 §5）
3. **B は推奨しない**（開発サーバーをインターネットに公開することになり、認証が簡易なまま）。大学の Wi-Fi などで A が使えず、C の準備が間に合わない場合の一時的な手段としてのみ、承認を得て短時間使う

## 4. A（同じ Wi-Fi）: 実装済み・Debug ビルド限定

### アプリ側（2026-11-04 承認・実装）

| 変更 | 内容 | Release への影響 |
|---|---|---|
| ATS の例外 | `MindWaveGraphic/DebugInfo.plist`（同期フォルダの外）に `NSAllowsLocalNetworking = YES` と、プライベート IP の範囲 `192.168.0.0/16`・`10.0.0.0/8`・`172.16.0.0/12` だけの `NSExceptionAllowsInsecureHTTPLoads`。`NSAllowsArbitraryLoads` は使わない（インターネットへの http は引き続き禁止） | iOS アプリの **Debug 構成だけ** `INFOPLIST_FILE = DebugInfo.plist`。Release 構成は生成 Info.plist のみ（`xcodebuild -showBuildSettings -configuration Release` で `INFOPLIST_FILE` なしを確認済み） |
| ローカルネットワークの権限 | `NSLocalNetworkUsageDescription`:「開発中の動作確認で、同じ Wi-Fi にある Mac の開発用サーバーに接続するために使用します。」 | 同上（Debug のみ） |
| 接続先の許可 | `RemoteInsightConfiguration.load` で `#if DEBUG` のときだけ `ServerConnectionDiagnostics.isPrivateLANHost` の http を許可（テストあり） | Release ではコードごと無効 |

- 接続先はコードに書かない。各自が Xcode スキームの環境変数で設定する（§6）
- APIキーは iPhone に入れない（Mac の `server/.dev.vars` だけ）

### サーバー側

```bash
# 既定（変更なし）: 127.0.0.1 のみ
npm run dev
# 実機で試すときだけ。この Mac のプライベート IP を自動で選び、設定すべき URL を表示する
npm run dev:lan          # 実通信（OpenAI の利用料が発生）
npm run dev:lan:stub     # STUB（無料）
# IP を自分で指定する場合（0.0.0.0・グローバル IP・ホスト名は拒否）
DEV_LAN_ACCESS=1 HOST=192.168.x.x npm run dev
```

`DEV_LAN_ACCESS=1` がない、またはプライベート IP 以外では起動しない。起動時に「LAN MODE: http（暗号化なし）」の警告と、iPhone 側に設定する `MW_INSIGHT_BASE_URL` を表示する。

### iPhone 実機での手順

1. Mac と iPhone を**同じ信頼できる Wi-Fi**（自宅など）につなぐ。大学などの Wi-Fi は端末間通信が遮断されていることが多い
2. Mac で `cd server && npm run dev:lan:stub`（まず無料の STUB で確認）。表示された `http://<MacのIP>:8787` を控える
3. Xcode → Edit Scheme → Run → Environment Variables に `MW_INSIGHT_BASE_URL=http://<MacのIP>:8787` と `MW_INSIGHT_CLIENT_TOKEN`（`.dev.vars` の CLIENT_TOKENS と同じ値）を設定し、**Debug** で iPhone にインストール
4. 初回の接続時に「ローカルネットワーク上のデバイスの検出と接続」の許可を求められるので「許可」。拒否した場合は 設定 → プライバシーとセキュリティ → ローカルネットワーク で変更できる
5. 状況選択でもこりんに話しかけ、「外部AIを使う」に同意。返答の下に「スタブ」/「OpenAI（…）」の表示が出れば接続成功。つながらない場合は「もう一度送る」「AIなしで続ける」が出る
6. 終わったら Mac のサーバーを Ctrl+C で止める

### 注意（必ず守る）

- **LAN の http は暗号化されない。** 同じ Wi-Fi の他の機器から、会話本文とクライアントトークンを盗み見られうる。信頼できる Wi-Fi 内だけで使う
- 個人情報・実際の健康データをテストで話さない（架空の内容で確認する）
- Mac のサーバーをインターネットへ公開しない（ルーターのポート開放・トンネルはしない）
- 開発用の CLIENT_TOKENS を本番用に使わない。定期的に変更する
- Release ビルド・TestFlight・App Store 版では LAN の http は使えない（意図どおり）

## 5. C（Cloudflare Workers）の設計案（調査・設計のみ。デプロイしていない）

既存のサーバー（`server/src`）は Workers の `fetch` ハンドラとして動く作りのため、ロジックはそのまま使える。公開エンドポイントになるため、次をそろえるまでデプロイしない。
**開発用の仮のトークンだけで、誰でも使える公開 AI サーバーにはしない。**

| 項目 | 設計 |
|---|---|
| 利用者ごとの認証 | Sign in with Apple（または Firebase Authentication）の ID トークンを Workers で検証（署名・発行者・有効期限・audience）。App Attest で正規アプリからの要求かを確認。共通の CLIENT_TOKENS は開発環境だけ |
| 回数制限 | Workers の Rate Limiting バインディングで利用者ごと（例: 1 分 10 回）と全体の上限。利用者ごとの 1 日の上限は Durable Objects または KV で数える |
| 秘密情報 | `wrangler secret put OPENAI_API_KEY`。ファイル・リポジトリ・アプリには置かない。キーは定期的に再発行 |
| 予算上限 | OpenAI プロジェクトの月額上限と通知。サーバー側でも出力トークンの上限（現行: 状況整理 500・相談 600）と、1 日の総トークンの上限を超えたら停止 |
| 異常検知 | 401/429/5xx の件数・トークン使用量を集計し、急増したら通知（Workers Analytics Engine / Logpush） |
| ログのプライバシー | 現行どおり、件数・状態・トークン数・エラー分類だけを記録。会話本文・トークン・キー・個人を特定する情報は記録しない。`store: false` を維持 |
| 開発・本番の分離 | `wrangler.toml` の環境（`env.dev` / `env.production`）で別の Worker・別の Secrets・別の OpenAI プロジェクト。アプリの接続先は xcconfig で構成ごとに設定（Release は https の本番 URL のみ） |
| 計測データ | 心拍・HRV は送らない（現行の契約どおり）。主観的な緊張はスコア計算に使わない |

### デプロイ前に必要な作業（承認後）

1. 利用者ごとの認証（Sign in with Apple または Firebase Authentication の ID トークンをサーバーで検証）と、App Attest による正規アプリの確認
2. 全体共有の回数制限（Cloudflare の Rate Limiting バインディング / Durable Objects）と、利用者ごとの 1 日の上限
3. OpenAI プロジェクトの使用上限（月額）と通知、APIキーの定期的な再発行（現在のキーは 7 日で失効）
4. `wrangler secret put OPENAI_API_KEY`（キーはファイルに書かない）
5. アプリの本番の接続先を、ビルド設定（xcconfig）で https の URL に設定する仕組み
6. プライバシーポリシー・App Store のプライバシー表示（入力した文章を外部 AI に送ること）

## 6. Xcode スキームの設定（チーム向け）

- 共有スキームのフォルダ `MindWaveGraphic.xcodeproj/xcshareddata/xcschemes/` は **Git で共有しない**（`.gitignore` で除外）。ローカルの開発用 URL とクライアントトークンを含むため
- Xcode は共有スキームがなくてもスキームを自動で作るので、ビルドには影響しない
- AI の接続を試す人は、自分のスキームで設定する: Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables

| 名前 | 値 |
|---|---|
| `MW_INSIGHT_BASE_URL` | シミュレーター: `http://127.0.0.1:8787`（STUB）/ `http://127.0.0.1:8789`（実通信の確認用に別ポートで起動した場合） |
| `MW_INSIGHT_CLIENT_TOKEN` | `server/.dev.vars` の `CLIENT_TOKENS` と同じ値（各自のもの。共有・コミットしない） |

- コミット前の確認: `scripts/check-secrets.sh`（ステージ済みのファイルに、APIキーの形式・`.dev.vars`・トークン入りのスキーム・`.dev.vars` の実際の値が含まれていないかを調べる。値は表示しない）。pre-commit フックとして使う場合は `ln -s ../../scripts/check-secrets.sh .git/hooks/pre-commit`（各自の任意設定）
