# iPhone 実機から AI サーバーへ接続する方式と、Xcode スキームの設定

作成: 2026-11-04 / ブランチ `feature/mokorin-voice-ui-20261028`
**この文書の「承認が必要」の項目は未実施。インターネットへの公開・デプロイ・ATS の変更はしていない。**

## 1. 現状

- 開発用サーバー（`server/scripts/dev-server.ts`）は `127.0.0.1`（この Mac の中だけ）で待ち受ける
- `127.0.0.1` は「その端末自身」を指す。シミュレーターは Mac 上で動くので届くが、**実機の iPhone では iPhone 自身を指すため届かない**。アプリはこの場合に送信せず「実機では 127.0.0.1 は iPhone 自身を指す」と表示する（`ServerConnectionDiagnostics`）
- アプリの接続先の設定（`RemoteInsightConfiguration`）は https、または http のループバック（localhost / 127.0.0.1）だけを許可。iOS の ATS（App Transport Security）は既定のまま
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

## 4. A の準備状況と、承認が必要な残りの変更

### 実施済み（サーバー側・既定では無効）

`dev-server.ts` に LAN で待ち受ける**明示的な**設定を追加した（`scripts/dev-host.ts`、テスト済み）:

```bash
# 既定（変更なし）: 127.0.0.1 のみ
npm run dev
# 実機で試すときだけ（Mac のプライベート IP を指定。0.0.0.0・グローバル IP・ホスト名は拒否）
DEV_LAN_ACCESS=1 HOST=192.168.x.x npm run dev
```

`DEV_LAN_ACCESS=1` がない、またはプライベート IP（10.x / 172.16–31.x / 192.168.x）以外を指定すると起動しない。起動時に「LAN MODE: http（暗号化なし）」の警告を表示する。

### 承認が必要な残りの変更（アプリ側・未実施）

| 変更 | 内容 | 理由 |
|---|---|---|
| ATS の例外 | `NSAppTransportSecurity` → `NSAllowsLocalNetworking = YES`（ローカルネットワークへの http だけを許可。インターネットへの http は引き続き禁止）。**DEBUG ビルドだけ**に入れる | LAN の http は ATS で遮断されるため。生成 Info.plist の設定項目では辞書を指定できないため、DEBUG 用の Info.plist の追加が必要になる見込み |
| ローカルネットワークの権限 | `NSLocalNetworkUsageDescription`（例:「同じ Wi-Fi の開発用サーバーに接続するために使用します」） | iOS 14 以降、LAN の機器への接続時に許可ダイアログが必要 |
| 接続先の許可 | `RemoteInsightConfiguration.load` で、**DEBUG ビルドに限り** http のプライベート IP を許可（現在は https とループバックのみ） | 上記と合わせて LAN の開発サーバーに接続するため |

どれも DEBUG ビルド限定で、リリースビルドの通信規則は変えない。実施の可否を判断してほしい。

## 5. C（デプロイ）の前に必要な作業（承認後）

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
