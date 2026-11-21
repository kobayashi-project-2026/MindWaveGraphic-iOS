# 実演ガイド（もこりん × 本物の OpenAI）

作成: 2026-11-05。実演は **A. Mac＋iPhone シミュレーター** を推奨（Mac の画面をそのまま共有する）。
B. iPhone 実機は [DEVICE_CONNECTION.md](DEVICE_CONNECTION.md)（同じ Wi-Fi・http は暗号化なし）。

## 前日まで

1. OpenAI Platform（Organization: MindWaveGraphic / Project: Mokorin-AI）で、API キーの**有効期限**と残高を確認する（キーの期限は API から取得できない）。自動チャージは OFF のまま
2. Xcode で `MindWaveGraphic` を **Debug** でシミュレーター（iPhone 17 Pro など）に一度実行し、アプリを入れておく
3. `scripts/demo.sh check` がすべて ✓ になることを確認（無料）

## 実演の直前（3 コマンド）

```bash
cd ~/Desktop/mind-wave-graphic
scripts/demo.sh start        # 確認 → REAL MODE サーバーを 127.0.0.1:8789 で起動（STUB なら止まる）
scripts/demo.sh launch       # 起動中のシミュレーターでアプリを開き、REAL MODE に接続
# 同意の場面も見せたいとき: DEMO_ASK_CONSENT=1 scripts/demo.sh launch
# 念のため本物の返答を 1 件だけ確かめたいとき（約 $0.0003）: scripts/demo.sh live-check
```

- API キー・トークンは画面に表示されない（値は伏せて確認し、アプリへは環境変数で直接渡す）
- 8787 番の古い STUB には接続しない。`demo.sh` は provider_mode が openai でないサーバーを使わない

## 実演の流れ（文字入力で 3 往復＋測定）

1. もこりんが「こんにちは。今、緊張してる？」と聞く（これは端末内の定型文と表示される）
2. （同意が未設定なら）「AIと話す」を押す
3. 入力欄に「かなり緊張してる」→ 返答の下に **OpenAI（gpt-6-luna）** と出ることを見せる
4. 「これから就活の面接があるんだ」→ 身体状態を聞かれる（同じ質問は繰り返さない）
5. 「さっき階段を上ってきた」→ まとめと「この状況で測定する」
6. 「この状況で測定する」→ ホームの「計測開始」へ
7. （任意）「整える」→ ガイド → 結果で「もこりんと結果を見る」（説明は端末内。測定値は外部へ送らない）

## 見分け方

| 吹き出しの下の表示 | 意味 |
|---|---|
| OpenAI（gpt-6-luna） | 本物の AI の返答 |
| スタブ応答（…）・実際のAIではありません（オレンジ） | STUB。実演を止めて `scripts/demo.sh start` からやり直す |
| 端末内の定型文 / 端末内の説明（AIではありません） | アプリ内の定型文・説明 |
| 「うまくつながらなかったよ（…）」＋「もう一度送る」「AIなしで続ける」 | 通信の失敗（自動で定型文に切り替えない） |

## トラブル時

| 症状 | 対処 |
|---|---|
| 「サーバーに接続できませんでした」 | `scripts/demo.sh check`。止まっていれば `scripts/demo.sh start` → アプリで「もう一度送る」 |
| 「サーバーの認証に失敗しました」 | `scripts/demo.sh launch` でアプリを開き直す（トークンを渡し直す） |
| `check` でキーが 401 | キーの期限切れ。Platform で新しいキーを作り `server/.dev.vars` を更新 |
| 返答が遅い | 通常 2〜3 秒。15 秒でタイムアウトし、失敗として表示される |

## 終わったら

```bash
scripts/demo.sh stop         # このスクリプトが起動した REAL MODE サーバーだけを止める
```

## 費用の目安

状況整理 1 往復 約 2,300 入力 / 100 出力トークン ≒ $0.0003（gpt-6-luna、$0.10 / $0.50 per 1M）。3 往復の実演 1 回 ≒ $0.001。
