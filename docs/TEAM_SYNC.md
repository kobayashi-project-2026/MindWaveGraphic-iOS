# 共同開発の更新手順とチーム統合の記録

## 正式な開発ブランチ

| 項目 | 内容 |
|---|---|
| リポジトリ | https://github.com/kobayashi-project-2026/MindWaveGraphic-iOS |
| 共有開発ブランチ | `feature/mokorin-voice-ui-20261028` |
| 統合ブランチ（2026-11-17） | `integration/team-sync-20261117`（共有開発ブランチへの PR で取り込む） |
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
- `MokorinEdgeGuide.swift`: ホームで使わなくなったが、ファイルは残している
