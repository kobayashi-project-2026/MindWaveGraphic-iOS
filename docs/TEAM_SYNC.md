# 共同開発の更新手順とチーム統合の記録

## 正式な開発ブランチ

| 項目 | 内容 |
|---|---|
| リポジトリ | https://github.com/kobayashi-project-2026/MindWaveGraphic-iOS |
| 共有開発ブランチ | `feature/mokorin-voice-ui-20261028` |
| 2026-11-17 の統合 | PR #8（`integration/team-sync-20261117`）で共有開発ブランチへマージ済み。検証での修正は `fix/team-sync-verification-20261117` の PR #9。STEP 4 は `feature/mokorin-ai-ui-step4-20261117` の PR |
| main | 保護ブランチ。直接 push・force push はしない。PR とレビューで更新する |

最新のコミット SHA は GitHub のブランチ画面か `git log -1 origin/feature/mokorin-voice-ui-20261028` で確認する。

## 最新コードの取得

```sh
cd ~/Developer/mind-wave-graphic          # iCloud 管理の ~/Desktop 側は使わない
git status                                 # 未コミットの変更がないか確認
git fetch origin --prune
git switch feature/mokorin-voice-ui-20261028
git pull --ff-only                         # 失敗したら下の「分岐している場合」へ
```

## 未コミット変更の保護

```sh
git stash push -u -m "作業途中 $(date +%Y%m%d-%H%M)"   # 取り出しは git stash pop
# もしくは作業ブランチでコミットしておく
git switch -c wip/<名前>-<日付> && git add -A && git commit -m "wip"
```

`server/.dev.vars`（API キー）は Git 管理外。`git add -A` でも追加されないが、コミット前に `scripts/check-secrets.sh` を実行する。

## 各自の feature ブランチへ最新版を取り込む

```sh
git switch <自分のブランチ>
git fetch origin
git merge origin/feature/mokorin-voice-ui-20261028
```

共有済みのブランチでは rebase・force push をしない（他のメンバーの履歴が壊れるため）。

## コンフリクトが起きたら

1. `git status` で対象ファイルを確認する
2. 両方の実装を読み、機能を両方残す形で手で直す（`--ours` / `--theirs` を機械的に選ばない）
3. iOS のビルドとテストを通す（下記）
4. `git add <ファイル>` → `git commit`
5. 判断に迷うときは中断して相談する: `git merge --abort`

## Xcode と検証

- 開くプロジェクト: `~/Developer/mind-wave-graphic/MindWaveGraphic/MindWaveGraphic.xcodeproj`
- スキーム: `MindWaveGraphic`（iPhone）、`MindWaveGraphicWatch Watch App`（Apple Watch）
- iOS ロジックのテスト: シミュレーターを起動して `scripts/run_ios_core_tests.sh`
- サーバー: `cd server && npm ci && npm test && npx tsc --noEmit`（OpenAI へは送信しない）

## 2026-11-17 のチーム統合の記録

### 取り込んだもの
- 共有ブランチの PR #4〜#7（ne241033-znt）: コックピットのレバー「対話」、ホームのもこりんのポップアップと過緊張バナー、改善画面の点滅、AI 相談画面の星空、起動・タイトル画面、もこりんの SVG 統一、中断時のリセット
- ローカルの 15 コミット: AI 会話 STEP 0〜6、改善方法の推薦（パターン A〜E）、試作スコア、5 画面の改修、サーバーの `/v1/context-assist`

### 競合の解決
| ファイル | 解決 |
|---|---|
| `GuideView.swift`（相手側で削除） | 削除を採用。改善タブは `GuideFlowView` を直接表示。ローカルの「途中の改善から再開」「会話の場面の引き継ぎ」は `GuideFlowView` に移植 |
| `GuideFlowView.swift` | 会話ベースの推薦一覧を維持し、会話がないときは PR #5 の緊張スコア判定を使う。推薦のポップアップは上部の推薦と重複するため不採用 |
| `HomeView.swift` | PR #5 のもこりんと過緊張バナーを採用（ローカルの小さなもこりん・5 秒バナーと重複するため）。実測値のときだけ表示する条件を追加。状態カード・改善途中の再開は維持。レバーは「改善」表記と大きな文字に PR #5 の点滅を追加 |
| `ContextCalibrationView.swift` | ローカルの STEP 0〜6 を維持（PR #7 の STEP 1〜3 の質問・選択肢は同じ内容で含まれ、自由入力・スキップ・訂正・戻る・推薦への引き継ぎがあるため）。共通の星空背景 `LaunchStarfieldBG` は PR #7 の最終デザインを採用 |

### 取り込まなかったもの
- `feature/HarukaSasaki-bit-space`（5ad5b65・0ff855c）: 本番のグラフィック `SpaceshipStateGraphicView` / `StarfieldGraphicView` を、名前の異なる試作（`ContentView`・`StarfildView`・`StarfieldView`）に置き換える内容。`ContentView` が重複してビルドできず、計測値（`GraphicInput`）との接続も失われる。画像アセット（ship / cockpit / inseki）も含まれていない。ブランチはそのまま残し、本番のグラフィックに接続する形で改めて取り込む
- PR #1〜#3（6 月）: 内容はすでに共有ブランチに含まれている（未統合のコミットなし）。PR 自体は開いたまま
- `MokorinEdgeGuide.swift`: ホームで使わなくなったため 2026-11-17 に削除（参照なし・同期フォルダのため Xcode 設定の変更不要）

## 2026-11-17 統合後の検証で直したこと

- アプリ内から会話を開いたとき、場面が未設定でも「いまは『安静』」と言っていた → 未設定なら場面に触れない自然なあいさつに。質問も重ねない
- AI（サーバー）経由で、会話の途中の質問（例「どんな方法がある？」）に答えると次の項目へ進み、聞いていた項目が抜けていた → 同じ質問に戻る（端末内の判定と同じ）。スタブも同じ動きに
- 改善タブで共通メニュー（≡）が浮いて内容（結果の「デモ値」など）と重なる → 改善タブでは上部バーの右端に置く
- 実施画面の内容が画面より高く、上部バー（×）がステータスバー・Dynamic Island の下に押し出される（iPhone SE・iPhone 17 Pro）→ 収まらないときだけスクロール、グラフィックの大きさを調整
- iPhone SE で吹き出しの末尾（今の質問）が切れる → 末尾から表示（前のあいさつは上へスクロール）。「この質問は答えない」をシートの下部に常に表示
- ホームの PULSE の固定値「72」がデモ値だと分からない → 実測がないときは「DEMO」と表示
- 「改善」の強調が、本人の評価（試作スコア）で緊張が高いときに出なくなっていた → 元の条件に戻す
- 使わなくなった `MokorinEdgeGuide.swift` を削除
- サーバー（スタブ）を使う E2E テストを追加・更新（`MW_E2E_BASE_URL` を設定したときだけ実行）

## 2026-11-17 STEP 4（もこりんの AI 相談・UI）

ブランチ `feature/mokorin-ai-ui-step4-20261117` → 共有開発ブランチへの PR。

- AI相談: もこりんを上部中央に大きく・音声入力・会話から分かったこと・話しかけの例・直前の発言の「直す」「取り消す」・会話の内容からのおすすめと「改善方法を見る」（docs/OPENAI_CHAT_ARCHITECTURE.md）
- `/v1/chat` に `context.check_in`（省略可能・列挙値のみ）を追加。測定前の会話（STEP 0〜6）とこの画面で本人が話したことを AI への補足に含める。スタブは届いた内容を返答で引用する（実際の OpenAI では未確認）
- ホーム: 状態のカードにもこりんと一言（計測データがあるときは PR #5 のポップアップ）
- 改善の方法選び: 見出しの呼吸法と違う方法（小休憩など）の理由を、その呼吸法の理由として表示していた → 方法名を添えて表示
- 改善ガイド: 開始前に「再開」と表示していた → 「START」。一時停止中の表示を追加。iPhone SE で START・一時停止が画面の下にはみ出していた → 収まる大きさに
- シミュレーター検証用（DEBUG）: `MW_CHAT_AUTO_OPEN_IMPROVEMENT=1`（AI相談 → 改善）、`MW_GUIDE_PAUSE_TEST=1`（`MW_FLOW_AUTOPILOT=1` と併用で 一時停止 → 再開）

## 2026-11-18 宇宙グラフィック（HarukaSasaki-bit さん）の採用

ブランチ `feature/haruka-graphic-demo-20261118`（安定版 1a4645b から）。HarukaSasaki-bit さんの星空・隕石・雷・もこりんの座席を
`Graphics/HarukaSpaceGraphicView.swift` に移植し、ホームの既定にした（GraphicInput で動く。従来のグラフィックにも切り替え可能）。
詳細・採用できなかった要素は docs/HARUKA_GRAPHIC.md。`feature/HarukaSasaki-bit-space` 自体はマージしていない（ContentView の重複などのため、グラフィックの部分だけを移植）。
