# もこりん原本コードの由来

- 受け取り: 2026-10-28、統合責任者から `~/Downloads/mokorin_friend_source.zip`（友達が作成したもこりんのキャラクターコード）
- zip の SHA-256: `0e31b7041199f462976622f89bdf63ebb8ba5a0b0689677c97412dfc9c31e82f`
- `third_party/mokorin_friend_source/` は zip の内容を**改変せず**そのまま保存したもの（`diff -r` で一致を確認）。**このフォルダは編集しないこと**

| ファイル | SHA-256 |
|---|---|
| app.py | c266d86d0a65f22bb439c1688d3449ebe0f05e0c12d4e28276404b9dddce30de |
| package-lock.json | 48aacdd9bfda5aaa1587330631fe934f8d45dda91c9e56273419e7aa5f55da97 |
| README.md | b8781761d1fe8cf6966cbf16f091fcedd059aa9bdb79120d042d632b7691b1c6 |
| static/script.js | 7f52d411d42dbb50268bf979bc03f28e14d628c4d5399ec4cc6a7b6b28eac8ff |
| static/style.css | 4077220807ee53062c4204f8b40ff81fcd84cc51003358b2900e37b911b1b9ab |
| templates/index.html | 40c938ddf2b182b5bac6b6ef9e2182460d2a6a899a5a31feae2fa1e2d620a0b8 |

アプリに組み込んだのは統合先のコピー（`MindWaveGraphic/MindWaveGraphic/Mokorin/Web/`）。差分と理由は docs/MOKORIN_WEBVIEW_INTEGRATION.md。
`app.py`（Flask）は実行・組み込みせず、返答形式 `{dialogue, emotion, action}` と許可値の仕様だけを既存の Node サーバー（server/）に取り込んだ。
