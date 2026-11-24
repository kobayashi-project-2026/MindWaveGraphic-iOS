# もこりん：友達提供の原本コード

このフォルダは、ChatGPTの会話でユーザーが貼り付けたコードを、Claude Codeが実ファイルとして読めるように再構成したものです。ユーザーが貼り付けたコード以外の画像や音声素材は含みません。

## 元コードとファイル配置

- `templates/index.html` : HTML（もこりんの表示・操作ボタン）
- `static/style.css` : CSS（外見とアニメーション）
- `static/script.js` : JavaScript（表情と動き）
- `app.py` : Python Flaskサーバー案（OpenAIの呼び出し口）
- `package-lock.json` : ユーザーが貼り付けた空のロックファイル

この配置はFlaskの `render_template('index.html')` と `/static/...` に合わせたものです。元のチャットに書かれた各コード片は、原則そのまま保存しています。READMEは補足説明として追加しました。

## Claude Codeへの注意点

1. もこりんの形・色・芽・顔・CSSアニメーションは元の実装を優先すること。キャラクターを新たに捏造しない。
2. iOSで使う場合、`WKWebView` からローカルHTMLを読み込むと、`/static/...` というルート絶対パスは解決できないことがある。統合先に複製したファイルで相対パス等へ調整し、原本には変更を加えない。
3. `setEmotion()` は `dialogue.textContent` を固定文で上書きする。OpenAI返信文と表情制御は分離し、原本を保持したまま統合先のコピーで修正する。
4. このHTML/JSにはユーザーの自由入力欄と `/chat` への `fetch` 呼び出しがない。`app.py` のAPIエンドポイントはHTMLに接続されていない。
5. Flaskの `debug=True` は開発用であり、本番運用は不可。Mind Wave Graphic本体の既存Node.js/Cloudflare Workersサーバーと重複させず、必要な仕様（セリフ・表情・動作）のみ利用すること。
6. APIキー、課金、外部デプロイ、HRV計算式の変更は別途承認が必要。
