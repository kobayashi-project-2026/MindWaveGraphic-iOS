# 友達のもこりん（HTML/CSS/JavaScript）の WKWebView 統合

ブランチ: `feature/mokorin-context-20261028`（ローカルのみ・未 push）。ログ・スクリーンショット: `build/mokorin-web-logs/`（Git 管理外）。
**OpenAI との実通信は行っていない。** 外部AIの経路はローカルの OpenAI スタブでのみ確認した。

## 1. 受け取ったコードと保存

- 受け取り: `~/Downloads/mokorin_friend_source.zip`（指示のフォルダ `~/Downloads/mokorin_friend_source/` は存在せず、同名の zip があった）
- 原本: `third_party/mokorin_friend_source/` に**改変せず**保存（zip と `diff -r` で一致、SHA-256 は `third_party/PROVENANCE-mokorin.md`）
- 統合先のコピー: `MindWaveGraphic/MindWaveGraphic/Mokorin/Web/mokorin.html` / `mokorin.css` / `mokorin.js`（アプリに同梱。ビルド成果物の .app 直下に入ることを確認）

## 2. 元コードのどこを再利用したか

| 原本のファイル | 再利用した部分 | 統合先での変更 |
|---|---|---|
| `templates/index.html` | もこりん本体のマークアップ（`#character.mocorin` と `.sprout` / `.body` / `.cheek` / `.eyes` / `.mouth`）、`#emotion`、`#dialogue` | CSS・JS の参照を `/static/...` から相対パスへ。見出し・説明文・操作ボタンを削除（SwiftUI から制御するため）。縮小用の `#fit` で包む。`#emotion`・`#dialogue` は既定で非表示 |
| `static/style.css` | **キャラクターの形・色・芽・顔・ほっぺ・口、表情（happy / sad / sleepy の差分）、アニメーション（float / jump / wave / nod の keyframes と適用クラス）をすべてそのまま**（`.body` 〜 `#character.nod` の範囲は原本と一致することを diff で確認。違いは削除したボタンの定義のみ） | body を透明背景・スクロールなしに（アプリの暗い背景に重ねる）。`.app` / `h1` / ボタンの定義を削除。`#character` の margin を 0 に。視差効果を減らす設定では浮遊を止める |
| `static/script.js` | 表情の許可値と表示名（HAPPY ✨ / RELAX ☁️ / SAD 💧 / SLEEPY 🌙）、`setEmotion` のクラス切り替え、`setAction` の許可値・クラスの付け直し（`offsetWidth` による再生）・2.5 秒後の解除、固定セリフ 4 種 | **`setEmotion` がセリフを固定文で上書きする処理を分離**（AI の返答が消えないように）。セリフは新しい `setDialogue`（textContent で設定）。固定セリフは `getDefaultLine` で参照のみ。表示サイズへの縮小と、アプリへの準備完了通知を追加 |
| `app.py`（Flask） | 返答形式 `{dialogue, emotion, action}`、許可値（happy/calm/sad/sleepy、wave/jump/nod）、不正な値のときの既定値（calm / nod） | **Flask は実行・組み込みしない。** 仕様だけを既存の Node サーバーの `POST /v1/context-assist` に取り込んだ（`emotion` / `action` を Structured Outputs の enum で追加）。モデル名 `gpt-4.1-mini` は使わず、既存設定（`gpt-6-luna`）を使用 |
| `README.md` / `package-lock.json` | 参照のみ（package-lock は空） | — |

## 3. 構成

```
SwiftUI（ContextCalibrationView / AIChatView）
   └ MokorinAvatarView(pose:)
        └ MokorinWebView（UIViewRepresentable / WKWebView）
             ├ loadFileURL(mokorin.html)  … 同梱ファイルのみ。外部への移動は拒否
             ├ JS → アプリ: { type: "ready" } のみ
             └ アプリ → JS: setEmotion('<enum>') / setAction('<enum>') / setDialogue(<JSON 文字列>)
```

- `MokorinPose`（emotion・action・actionID・dialogue）を SwiftUI から渡す。準備完了前の指示は最後の状態だけ覚えて、準備後に反映する。`actionID` が増えたときだけ動作を再生する
- セリフは SwiftUI の吹き出しで表示する（キャラクター自身の吹き出しは既定で非表示。`showsDialogue: true` で表示可能）
- 同梱ファイルが見つからない場合だけ、以前の簡易イラストを代わりに表示する

## 4. 表情・動作を決めるもの

| 画面・状況 | 決め方 |
|---|---|
| 状況選択（外部AIあり） | サーバーの `emotion` / `action`（AI が返答に合わせて選ぶ。不正な値は calm / nod） |
| 状況選択（定型文） | 固定の規則（`MokorinExpressionRules`）: あいさつ happy + wave、質問 calm + nod、確認 happy + nod、睡眠不足 sleepy、「つらい」等 sad |
| AI 相談 | 固定の規則: 表示時 happy + wave、考え中 calm、返答でうなずく、失敗で sad（`/v1/chat` は変更していないため AI は表情を返さない） |

いずれも返答の文章は変更しない（固定セリフで上書きしない）。

## 5. 安全性

- WKWebView は同梱ファイルだけを読み込み、それ以外への移動は `decidePolicyFor` で拒否
- JavaScript へ渡すのは enum の許可値と、`JSONSerialization` で文字列リテラル化したセリフだけ（引用符・改行・HTML を含んでもコードとして実行されない。テストで確認）
- キャラクターはタップを受け付けない表示専用。VoiceOver では「もこりん、うれしそう」等として読み上げる
- 数値計算・HealthKit・WatchConnectivity・計算式は変更なし。APIキーはアプリにない

## 6. 検証結果

### ビルド（クリーンビルド、Swift 6 の分離警告の修正後）

| スキーム | 結果 | Swift 警告 | ログ |
|---|---|---|---|
| MindWaveGraphiciOSOnly（iPhone） | BUILD SUCCEEDED | 0 | `final-clean-build-MindWaveGraphiciOSOnly-*.log` |
| MindWaveGraphicWatch Watch App | BUILD SUCCEEDED | 0 | `final-clean-build-MindWaveGraphicWatch_Watch_App-*.log` |
| MindWaveGraphic（iPhone＋Watch） | BUILD SUCCEEDED | 0 | `clean-build-MindWaveGraphic-*.log` |

ビルド成果物の .app 直下に `mokorin.html` / `mokorin.css` / `mokorin.js` が同梱されることを確認。

修正した警告: `MokorinExpressionRules`（nonisolated）がメインアクター分離の `MokorinContextViewModel.Step` の `Equatable` を使っていた（Swift 6 ではエラーになる）→ `Step` を `nonisolated` にした。修正前のビルド（iPhone / Watch 各 2 件の警告）はやり直した。

### 自動テスト

| 対象 | 結果 | ログ |
|---|---|---|
| iOS ロジックテスト（既存 140 件＋キャラクター制御 7 件、ローカルサーバー＋OpenAI スタブとの E2E 込み） | **147/147** | `ios-tests-final-e2e-*.log` |
| サーバー（既存 45 件＋表情・動作 2 件＋統合先 JS の疑似 DOM テスト 5 件） | **52/52**、TypeScript 型チェック エラー 0 | `server-tests-final-*.log`, `server-tsc-*.log` |

JS テストでは、原本の `setEmotion` がセリフを固定文で上書きすること、統合先では上書きしないこと、`setAction` が原本どおり 2.5 秒で解除されることを確認した。

### シミュレーター（iPhone 17 Pro / iOS 26.5、`build/mokorin-web-logs/screens/`）

| 確認内容 | ファイル |
|---|---|
| 表情 4 種（happy / calm / sad / sleepy）と動作（nod の傾き）を一覧表示。友達のデザイン（芽・ほっぺ・顔・クリーム色の体）のまま表示 | `gallery-3.png`（DEBUG の `MW_MOKORIN_GALLERY=1`） |
| WKWebView の初回準備中（約 3 秒、キャラクターが表示されない） | `gallery-1.png` |
| 状況選択（初回）: もこりん（happy + wave） | `ctx-greeting.png` |
| 状況選択（スタブ経由）: 返答はそのまま表示、「睡眠不足」を含む回答でまとめまで進む | `ctx-stub.png` |
| AI 相談（スタブ経由 2 往復）: 上部にもこりん | `chat-stub.png` |

**未確認**: 実機での表示・負荷、アニメーションの滑らかさ（静止画のみ）、タップ・キーボード操作、VoiceOver。

## 7. 既知の課題

1. **初回表示の遅れ**: アプリ起動後、最初の WKWebView の準備に約 3 秒かかり、その間キャラクターが表示されない（2 回目以降は速い）。必要なら、起動時に WebView を先に用意する、または準備完了まで簡易イラストを表示する対応を検討する
2. 状況選択の画面では、会話が増えるとスクロールでもこりんが画面外へ出る（表情の変化が見えにくい）。固定ヘッダーにするかはデザイン担当と相談
3. AI 相談の表情は固定の規則で、AI が選んだものではない（`/v1/chat` を変えないため）。AI に表情を選ばせる場合は `/v1/chat` に任意項目を追加する設計変更が必要
4. 原本 README の注意どおり、Flask の `/chat` は HTML から呼ばれていなかった。統合では Node サーバーのみを使う
