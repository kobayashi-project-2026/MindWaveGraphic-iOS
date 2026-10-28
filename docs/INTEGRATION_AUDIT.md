# 統合品質監査レポート（2026-10-28）

夜間統合作業（`docs/OVERNIGHT_INTEGRATION_REPORT.md`）の報告内容を、コード・Git 履歴・テストで独立に検証した結果。
「ビルド成功」「自動テスト成功」「シミュレーターで表示確認」「実機で確認」を区別して記載する。

---

## 1. 監査対象ブランチ・コミット

| 項目 | 内容 |
|---|---|
| ブランチ | `feature/overnight-integration-20261028`（ローカルのみ・未 push） |
| 監査開始時の HEAD | `627b95d`（作業ツリーはクリーン） |
| 比較基点 | `0be98a3` = `fix/build-navigation-20261028` の HEAD（夜間作業の分岐元） |
| main との関係 | main（`b64c9af`）は分岐元の祖先。`main..0be98a3` にはメンバーの 73 コミットが含まれるため、**main との差分を夜間作業の差分とはみなしていない** |

夜間作業の 6 コミット（すべて存在を確認）:

| SHA | 内容 |
|---|---|
| `b2ef615` | 未コミットだった 4 ファイルの保全（MainTabView / MindWaveGraphicApp / AppNavigationManager / AppRootContainerView） |
| `fd567f8` | ナビゲーション統合 |
| `29f9353` | JSON 契約 |
| `7f8e967` | データパイプライン（Selector / Baseline / Analyzer） |
| `c2aa6f6` | InsightProvider と OpenAI 中継サーバー |
| `627b95d` | 最終検証・ドキュメント |

この監査で追加したコミット:

| SHA | 内容 |
|---|---|
| `2cd6b8c` | fix(test-script): ビルド失敗が「テスト失敗(1)」として報告される不具合（前回の原因不明の exit=1 の原因） |
| `e243607` | fix(pipeline): Mock デモシナリオのスコアをシナリオの平常値で算出（統合前と同じ） |
| `721298b` | fix(history): v2 にしかない履歴が上書きで消える不具合 |
| `86379ab` | fix(server): OpenAI 応答本文の受信中もタイムアウトを適用 |
| `7cd3b5c` | test(pipeline): スコア 38 固定の既存挙動を特性テストで明示 |
| （このレポートを含むコミット） | docs: 監査レポート・仕様書の訂正 |

## 2. 変更ファイルの監査結果

`git diff 0be98a3 627b95d`: 66 ファイル、+5476 / −175 行。

| 確認項目 | 結果 |
|---|---|
| ファイル削除 | **0 件** |
| `#if false` 等による無効化 | **なし**（追加行を検索して確認） |
| ダミーの成功応答・固定の架空計測値 | **なし** |
| `project.pbxproj` | **変更なし**（テストは `scripts/run_ios_core_tests.sh` で swiftc 直接ビルド） |
| main・他メンバーのブランチ | **変更なし**（push・reset・clean も未実施） |
| テストのためだけに変えた本番挙動 | なし。`GuideHistoryStore(defaults:)`・`MindWaveViewModel(analyzer:baselineStore:)` は既定値が従来と同じ注入口。`LocalMindWaveAIEngine` の `private` 解除は LocalInsightProvider から使うため（ロジック不変） |
| DEBUG 専用フック | `INITIAL_SCREEN`（MainTabView）を追加。既存の `SKIP_ONBOARDING` / `INITIAL_TAB` / `GUIDE_PHASE` は維持 |
| 呼び出されないモジュール | `MindWaveViewModel.computeConfidence`（Analyzer へ移行、参照として残置）、`GuideHistoryStore.exportJSON()`、`MeasurementSampleDTO`、`GraphicInputDTO`（§7） |
| 重複した状態管理 | なし（§6） |
| 意図しない依存関係 | なし。iOS は外部パッケージ追加なし。server は devDependencies（typescript, @types/node）のみ |

### 統合前から挙動が変わった点（夜間作業で意図的に変更）

| # | 変更 | 影響 |
|---|---|---|
| 1 | 実測で心拍が未計測のとき、直前の `currentHeartRate`（デモ初期値の場合あり）ではなくベースライン値（=心拍項は平常扱い）で算出 | デモ値が実測スコアに混入しなくなった |
| 2 | **鮮度判定を追加**: HealthKit 心拍 30 分・HRV 6 時間を超えた値はスコアに使わない（統合前は期間無制限） | **HRV が 6 時間以上更新されないと 38 固定になる頻度が統合前より増える**（§9） |
| 3 | Watch 時刻が端末時刻より 60 秒以上未来なら不採用（統合前は制限なし） | 時計ずれ対策 |
| 4 | HRV の集計フォールバック値（30分/24時間平均）をスコアに使わない | `fetchBestCurrentHRV` は期間無制限で実サンプルを先に探すため、実際にはほぼ到達しない経路 |
| 5 | 個人ベースライン: HealthKit 7日平均がないとき、アプリが蓄積した実測（30件・3日以上）を使う | 参照値 65/45 から個人値へ切り替わる時点でスコアが変わる（§14） |
| 6 | ガイドのスナップショットに記録する実測値を「スコアに使った鮮度内の値」に限定 | 古い値を現在値として保存しなくなった |
| 7 | AI 学習ログ（HistoryView の傾向パネル）から Mock を含む記録を除外 | 表示件数が減る場合がある |

## 3. 発見した不具合

| # | 重大度 | 内容 | 状態 |
|---|---|---|---|
| F1 | 中 | **前回の原因不明の exit=1 の原因**。テストスクリプトはコンパイラが `error:` 行を出さずに終了すると、`set -euo pipefail` 下の `grep` 不一致で終了コード 1（＝「テスト失敗」）になっていた。前回 20:33 開始の実行は `ios exit=1` の直後に `RESULT` 行がなく（テストは実行されていない）、20:43 に停滞したコンパイラプロセスを手動で停止していた。同じ構造のスクリプトで再現 | 修正 `2cd6b8c` |
| F2 | **高** | **履歴のデータ消失**。v3 JSON が存在すると v2 を読まず、次回保存で v2 を上書き。移行期間中に他メンバーのブランチのビルド（v2 のみ読み書き）で追加した記録が消える。既存テスト「v3 が v2 より優先される」がこの挙動を前提にしていた | 修正 `721298b` |
| F3 | 低 | Mock デモシナリオのスコアを参照値 65/45 固定で算出（統合前はシナリオの平常値）。現行シナリオは全て 65/45 のため数値は一致していた潜在不具合 | 修正 `e243607` |
| F4 | 中 | サーバーが OpenAI 応答ヘッダー受信後にタイマーを解除しており、本文の受信が止まると無期限に待つ。修正前のコードで新規テストが 40 秒以上停止することを確認 | 修正 `86379ab` |
| F5 | 中（報告の誤り） | 前回報告の「JSON 契約 8 種を実際の入出力に接続済み（B: COMPLETE）」は過大。`MeasurementSampleDTO`・`GraphicInputDTO` は本体から未使用、`AnalysisResultDTO` はデバッグ表示のみ。また「Watch 心拍だけではグラフィックが変化しない」は不正確（ホームの表示補正で 100 bpm 以上は変化する。§9）。DATA_CONTRACTS.md §5 の例（HRV missing なのに score 52.4）も実挙動と矛盾 | 文書を訂正 |
| F6 | 中（既存） | ホームの表示補正 `heartRateVisualFloor` は、Mock モード中でも・何時間前の値でも `latestWatchHeartRate` を使う。Mock 表示に実測心拍が混ざり、古い心拍で色が変わり続ける（表示のみ。研究スコア・保存値には影響しない） | 未修正（メンバーの表示方針。§14） |
| F7 | 低（既存） | 未知の場面・エクササイズを含む記録は読み込み時に読み飛ばされ、次回保存でその形式から消える（v2 は統合前から同じ挙動） | 未修正（記録のみ） |
| F8 | 低（既存） | 状況確認で場面を変更しても即時には再計算せず、次のサンプル受信時に反映 | 未修正（記録のみ） |
| F9 | 設計注意 | Watch 辞書の `schemaVersion` が iPhone の対応版より新しいと受信を拒否する。Watch アプリだけ先に更新すると心拍が届かなくなる | 記録のみ |
| F10 | 低 | `GET /v1/health` は認証なしで `openai_configured` / `auth_configured`（真偽値のみ）を返す | 記録のみ（秘密値は含まない） |

### 環境に関する所見（ストレージ整理は実施していない）

- **デスクトップが iCloud 同期の対象で、ファイル本体がクラウドへ退避（dataless）されている**。`server/node_modules` の 81 件、`.git` 内（オブジェクト・ログ・hooks 等）を含む 673 件を確認。TypeScript の型チェックはファイルのダウンロード待ちで約 4 分かかった。前回の `.git/index.lock` 書き込みタイムアウトもこれが原因の可能性が高い。**iCloud 同期フォルダ上の Git リポジトリは破損の危険がある**ため、リポジトリを同期対象外の場所へ置くことを推奨する（判断は統合責任者に委ねる）。`git fsck` の結果は §5
- シミュレーターの端末が全て削除されていた（ランタイム iOS 26.5 / watchOS 26.5 は残存）。テストのため **iPhone 17 Pro の端末を 1 台新規作成**（`Audit iPhone 17 Pro`, UDID `CCF087A9-DF30-46F6-98F4-74AD62C7730C`）。削除は行っていない
- 空き容量は監査開始時 16 GB、途中で 33 GB に増加（ユーザー側の整理によるもの）。容量不足によるビルド・テスト失敗は今回は発生していない

## 4. 実施した修正

| 修正 | 原因 | 影響範囲 | 変更 | 検証 |
|---|---|---|---|---|
| F1 `2cd6b8c` | `grep` 不一致が `set -e`/`pipefail` で終了コード化 | テストスクリプトのみ | `{ grep …; } \|\| tail … \|\| true` | 同構造の再現スクリプトで 1 → 2 を確認、構文チェック、以後の全実行 |
| F2 `721298b` | v3 優先読み込みで v2 を参照しない | `GuideHistoryStore.load()` | v2 のみの記録を id で取り込み、同 id は v3 優先、取り込み時は v3 を再保存 | 新テスト（他ブランチ追加 → 再読み込み → 保存後も両形式に残る） |
| F3 `e243607` | Analyzer が平常値を固定参照 | Mock・`contextScore` なしの経路のみ | `AnalyzerInput.mockAverageHeartRate/HRV` を追加し ViewModel から渡す | 新テスト（シナリオ平常値 72/50 で計算式と一致） |
| F4 `86379ab` | タイマー解除が早い | server の OpenAI 呼び出し | 本文読み込み完了までタイマー維持、打ち切りは `upstream_timeout` | 新テスト（本文停止 → 50ms で 504 相当）。修正前は停止 |
| F5 文書 | 実装との不一致 | docs | DATA_CONTRACTS.md（接続状況表・§5 例・§8 読み込み手順）、INTEGRATION_STATUS.md、OVERNIGHT_INTEGRATION_REPORT.md に訂正注記 | 目視 |

**研究用計算式（`StressScoreCalculator`）は変更していない。** iPhone・Watch への影響は §5 のクリーンビルドで確認。

## 5. テスト結果とログ保存先

ログは `build/audit-logs/`（`.gitignore` の `build/` 配下のためコミットされない）。実行ごとに別ファイル。

### ビルド（Xcode、クリーンビルド、署名なし）

| スキーム | 結果 | Swift コンパイラ警告 | ログ |
|---|---|---|---|
| MindWaveGraphiciOSOnly（iPhone） | BUILD SUCCEEDED | 0 | `clean-build-MindWaveGraphiciOSOnly.log` |
| MindWaveGraphicWatch Watch App | BUILD SUCCEEDED | 0 | `clean-build-MindWaveGraphicWatch_Watch_App.log` |
| MindWaveGraphic（iPhone + Watch） | BUILD SUCCEEDED | 0 | `clean-build-MindWaveGraphic.log` |

各ログの `warning:` 2 件は Xcode のツール（appintentsmetadataprocessor）の「AppIntents 未使用のためメタデータ抽出を省略」という情報メッセージで、コードの警告ではない。

### iOS ロジックテスト（`scripts/run_ios_core_tests.sh`、iOS 26.5 シミュレーター上で実行）

| 実行 | コード | 結果 | ログ |
|---|---|---|---|
| run1 | F3 修正後 | 91/91（E2E なし） | `ios-tests-run1-*.log` |
| run2 | F2・F3 修正後、E2E あり | 93/93 | `ios-tests-run2-e2e-*.log` |
| run3 | コミット後、E2E あり | 93/93 | `ios-tests-run3-e2e-postcommit-*.log` |
| 反復 1〜5 | 同じ実行ファイルを 5 回 | 5 回とも 93/93 | `ios-tests-repeat{1..5}-*.log` |
| CPU 全コア負荷下 1〜2 | 同上 | 2 回とも 93/93 | `ios-tests-cpuload{1,2}-*.log` |
| run4 | スコア 38 特性テスト追加後 | 92/92（E2E なし） | `ios-tests-run4-score38-*.log` |
| final | 最終コード、E2E あり | **94/94** | `ios-tests-final-e2e-100131.log` |

計 12 回、失敗 0。タイミング依存の失敗（タイムアウトのテスト等）は負荷下でも再現しなかった。
**前回の exit=1 はテストの失敗ではなく F1（スクリプトの終了コード誤り）であり、再現条件（コンパイラの強制終了）も特定済み。**

検証した条件の内訳（最終実行）:

| 区分 | 主な検証内容 |
|---|---|
| JSON 契約 | 全型の往復、snake_case、UTC ミリ秒、null の明示出力、キー欠落＝null、未来の schema_version 拒否、不正 JSON・範囲外・未知列挙値、Watch 辞書 v0/v1・Int/Double、仕様書の例（ゴールデン） |
| 履歴 | v2 → v3 移行（v2 保持）、壊れた v3 からの復元、**v2 のみの記録の取り込み**、メモ更新、Mock 除外、エクスポート |
| ナビゲーション | タブ ⇄ Int Binding、モーダル遷移、タイトル遷移の確認フラグ、サインアウト時の初期化、未知のタブ番号の無視 |
| パイプライン | 優先順位（Mock / Watch 15 秒 / HealthKit 30 分・6 時間）、時計ずれ、Analyzer と計算式の一致（**Mock シナリオ含む**）、**スコア 38 の特性**、ベースライン（記録規則・間引き・保持期間・決定順）、ViewModel の通し動作 |
| AI | データ最小化（Mock 不送信・丸め・HRV は方向のみ・メモ/日時なし）、HTTP エラー・不正応答・request_id 不一致・タイムアウト、同意なし・未設定・Mock でのローカルフォールバック、設定の https 制限、E2E（ローカルサーバー＋OpenAI スタブ: 成功・トークン不一致 401） |

### サーバー（`server/`、Node v24.22.1 をスクラッチ領域の公式配布版で実行。システムには未インストール）

| 実行 | 結果 | ログ |
|---|---|---|
| run1（F4 修正後） | 23/23 | `server-tests-run1.log` |
| run2（コミット後） | 23/23 | `server-tests-run2-postcommit.log` |
| TypeScript 型チェック | エラー 0（iCloud の退避ファイル待ちで約 4 分） | `server-tsc-run1.log` |
| 修正前コードでの F4 再現 | 新テストが停止（40 秒超で手動停止） | `server-old-code-repro.log` |
| ローカルサーバーのログ | リクエスト内容（心拍・場面）・トークンを含まないことを確認 | `dev-server-stub*.log` |

### Git 整合性

`git fsck --no-dangling`: **エラーなし（exit 0）**。ただし iCloud から退避オブジェクトをダウンロードしながらの実行で約 5 分 36 秒かかった（`git-fsck.log`）

## 6. ナビゲーションの検証結果

### 責務

| 型 | 責務 | 状態の持ち主 |
|---|---|---|
| `MindWaveGraphicApp` | WatchConnectivity 初期化、`AppRootContainerView` を表示 | なし |
| `AppRootContainerView` | 長寿命オブジェクトの所有（`AppNavigationManager` / `MindWaveViewModel` / `GuideHistoryStore`） | 上記 3 つ |
| `AppRootView` | 認証フロー（スプラッシュ → 案内 → ログイン/ゲスト → 状況確認 → mainApp）の切り替え | `AppFlowState.authStatus` |
| `AppNavigationManager` | mainApp 内のタブ・モーダル・タイトル確認ダイアログ | `selectedTab` / `activeModal` / `isTitleReturnConfirmationPresented` |
| `MainTabView` | 3 タブの表示、`selectedTab` を navManager から導出した Binding で既存 View に渡す、モーダル・ダイアログの表示 | 独自の遷移状態なし |
| `GlobalMenuBarModifier` | 右上の共通メニュー。`navManager.navigate(to:)` を呼ぶだけ | なし |

### 二重管理・書き戻しの調査

- `selectedTab` への書き込みは全て `selectedTabBinding` → `navManager.selectTab(index:)` を経由する（HomeView のレバー 3 か所、GuideFlowView の完了時 2 か所）。`ContentView` の `@State selectedTab` は表示されない旧画面
- `MainTabView` の `onChange` は 2 つのみ: `flowState.measurementContext` → ViewModel への反映、`navManager.selectedTab` → 切替演出とログ。**いずれも遷移状態を書き戻さない**
- 共通メニューからタブへ移動するとき `activeModal = nil` を先に設定し、モーダルとタブの状態が食い違わない
- 旧 `HomeView` の設定シート（`showSettingsSheet`）は削除し、共通メニューと同じ `activeModal` で開く（設定画面の二重表示経路の解消）

### 計測状態・保存途中のデータ

- ViewModel と履歴はコンテナが所有するため、認証フローの切り替え・状況確認・モーダル表示で作り直されない（コードで確認）
- タブ切り替え中もガイドの状態は TabView の子として保持される（コードで確認、実機未確認）
- 「タイトルへ戻る」は確認後にライブ計測を停止し、履歴は保持する。**MainTabView が破棄されるため、実施中・未保存のガイドセッションは失われる**。確認ダイアログの文言は「ライブ計測は停止」「履歴は削除されない」のみで、未保存のガイドに触れていない（改善提案。§15）

### シミュレーターでの表示確認（iPhone 17 Pro / iOS 26.5、DEBUG 起動フックで各画面を直接表示）

スプラッシュ、アカウント案内、ホーム（共通メニュー表示）、整えるタブ、履歴タブ（記録なし）、状況確認（メニュー内編集モード「変更しない」表示）、設定、結果確認（記録なしの案内）、タイトル確認ダイアログ、ガイド結果画面（Mock 時の「Mockモード中のデータを含みます」表示）の 10 画面。いずれも描画とメニューの有無が想定どおり。

**未確認**: タップ操作による連続した遷移（ログイン/ゲスト選択 → 状況確認 → ホーム、レバー操作、メニュー選択、ガイド開始 → 実施 → 結果 → メモ保存 → 履歴反映）。UI の自動操作手段がないため、コードとロジックテストでの確認にとどまる。

## 7. JSON 契約と実処理の対応表

| 契約 | 型定義 | 往復・不正入力テスト | 本体の処理経路での使用 | 判定 |
|---|---|---|---|---|
| Watch → iPhone 心拍辞書 `WatchHeartRatePayload` | ✅ | ✅ | ✅ iPhone 受信（`WatchConnectivityManager`）・Watch 送信に `schemaVersion: 1` | COMPLETE（実機通信は未確認） |
| 計測サンプル `MeasurementSampleDTO` | ✅ | ✅ | ❌ 未使用 | PARTIAL |
| 測定コンテキスト `MeasurementContextDTO` | ✅ | ✅ | △ `AnalysisResultDTO` 内のみ | PARTIAL |
| 分析結果 `AnalysisResultDTO` | ✅ | ✅ | △ デバッグ診断画面の表示のみ | PARTIAL |
| グラフィック入力 `GraphicInputDTO` | ✅ | ✅ | ❌ 未使用（グラフィックは Swift の `GraphicInput` を直接使用） | PARTIAL |
| ガイドセッション記録 `GuideSessionRecordDTO`（`GuideSnapshotDTO`・`SessionInsightDTO` を含む） | ✅ | ✅ | ✅ 履歴の保存・読み込み | COMPLETE |
| 履歴文書 `GuideHistoryDocument` | ✅ | ✅ | ✅ 履歴の保存・読み込み（`exportJSON()` は呼び出し元なし） | COMPLETE |
| AI インサイト `InsightRequestDTO` / `InsightResponseDTO` / `InsightErrorDTO` | ✅ | ✅ | ✅ 同意＋サーバー設定時の経路（E2E はローカルスタブのみ） | PARTIAL（OpenAI 実通信未確認） |

共通ルールの確認: Codable（`CodingKeys` で snake_case）、`schema_version` = 1（未来の版は拒否）、単位（bpm / SDNN ms / 0〜100 / 0〜1 / 秒）、UTC ISO8601 ミリ秒（読み込みはミリ秒なし・UNIX 秒も可）、`is_mock` と `source == mock` の一致検証、計測値の `null` は省略せず出力、旧形式（Watch v0・履歴 v2）との互換。docs/DATA_CONTRACTS.md と実装の不一致（§5 の例・§8 の読み込み手順・接続状況）は訂正済み。

## 8. データパイプラインの検証結果

| 段階 | 実装 | 自動テスト | 実機 |
|---|---|---|---|
| Watch 心拍の受信 | 既存 3 チャネル＋契約検証（v0/v1） | ✅ 辞書の検証 | ❌ 未確認 |
| HealthKit 心拍・HRV の取得・HRV observer | 既存実装（変更なし）＋計測時刻付きで保持 | △ ViewModel への入力のみ | ❌ 未確認（シミュレーターにデータなし） |
| 重複の除外 | Watch: タイムスタンプ単調増加、HRV: UUID・endDate（既存）、ベースライン: 5 分間引き・同時刻 HRV 除外 | ✅ | ❌ |
| 鮮度判定 | Watch 15 秒、HealthKit 心拍 30 分、HRV 6 時間 | ✅ | ❌ |
| 欠損値 | 心拍なし → ベースライン値（metadata.heartRate = nil）、HRV なし → 計算式の中立値 38（§9） | ✅ | ❌ |
| Mock の混入防止 | 分析（source/is_mock）、スナップショット、履歴の傾向分析、外部送信、ベースライン記録で区別 | ✅ | — |
| 測定コンテキスト | 状況確認 → AppFlowState → MainTabView → ViewModel → Analyzer（反映は次のサンプルから。F8） | ✅（Analyzer） | ❌ |
| 個人ベースライン | HealthKit 7日平均 → 蓄積（30件・3日） → 参照値（provisional と明示） | ✅ | ❌ |
| GraphicInput への変換 | score / confidence / state | ✅ | — |
| グラフィック表示 | ホームは `graphicInput` に表示補正（F6）を加えて描画 | ✅ 値のみ／描画はスクリーンショット | ❌ |
| ガイド → 履歴保存 | スナップショット（鮮度内の実測値・source）、AI インサイトの生成元バージョン | ✅ | ❌ |

## 9. HRV 未取得時のスコア 38 問題

### 原因
`StressScoreCalculator.calculate` の冒頭 `guard averageHeartRate > 0, averageHRV > 0 else { return …stressScore: 38 }`。
`StressScoreAnalyzerV1`（統合前の `reevaluateActiveSource` と同じ）は、実測サンプルに HRV がないとき `averageHRV: 0` を渡すため、この guard で中立値 38 が返る。

### 38 になる条件
- 実測（Watch または HealthKit）で、**鮮度内（6 時間以内）の HealthKit HRV 実サンプルがない**とき
- 例: Watch の心拍ライブのみ、HealthKit の HRV 権限なし、HRV の自動計測が 6 時間以上ない

### 確認した事実（特性テスト `7cd3b5c` で固定）
- 心拍を 45〜200 bpm に変えても **38 のまま**（心拍は計算に使われない）
- 場面・身体状態の補正（`totalScoreOffset`）も **効かない**（guard が補正より先に返る）
- 個人ベースライン（参照値・HealthKit 7日平均）にも依存しない
- 状態は `optimal_tension`（READY）、確からしさは Watch 0.50 / HealthKit 0.40
- Mock: デモシナリオは HRV を持ち、スライダー（`contextScore`）経路は計算式を通らないため **Mock では再現しない**

### グラフィック・保存への影響
- 研究スコア（`graphicInput.score`）、ガイドの前後スナップショット、履歴、AI インサイトの入力は全て 38
- ホーム画面だけはメンバー実装の表示補正（心拍 100 以上で表示スコアの下限 55、115 以上で 72、130 以上で 85）により色・強度が変化する。**100 bpm 未満では変化しない**。この補正は表示のみで、保存値・研究スコアには反映されない

### 統合による頻度の変化（重要）
統合前は HealthKit の HRV 実サンプルを**期間無制限**で補完に使っていたため、38 になるのは「HRV が一度も取得できない」場合だけだった。夜間作業で鮮度 6 時間を導入したため、**HRV の更新間隔が 6 時間を超える時間帯は 38 になる**。鮮度の閾値自体が研究上のパラメーターであり、§14 で判断が必要。

### 対応案の比較（いずれも未実施。計算式は変更していない）

| 案 | 内容 | 利点 | 欠点 | 研究上のリスク |
|---|---|---|---|---|
| A. 評価不能とする | HRV がないときはスコアを出さず「HRV 待ち／評価不能」を表示・記録（`state` を未評価扱い） | 研究データの意味が明確。38（平常）と誤認されない。計算式を変えない | ライブ中にグラフィックが反応しない時間が残る。UI・JSON に「未評価」状態の追加が必要（`MindState` 3 状態の外） | 低。欠測は欠測として扱える。ただし欠測率が高いと研究データが不足する |
| B. 心拍のみの暫定評価を別方式で追加 | `MindAnalyzer` に心拍のみの Analyzer を追加し、`analyzer_id` で区別（例 `hr-only-v0`） | ライブで反応する。既存式と結果を区別して保存できる（基盤は実装済み） | 新しい評価式の設計・妥当性確認が必要。HRV ありの値と同じ尺度に見えてしまう | 中〜高。心拍上昇は運動・カフェイン等と区別できない。研究担当が式と閾値を承認するまで採用不可 |
| C. 直近の有効な結果を利用 | (C1) 最後の HRV ありスコアを保持して表示、または (C2) 古い HRV を鮮度切れ表示付きで補完に使う（C2 は統合前の挙動に近い） | 表示が途切れない。C2 は統合前と同等 | C1 は現在の状態を反映しない。C2 は数時間前の HRV と現在の心拍を混ぜた値になる | 中。「現在値」と記録すると時間のずれた値が研究データに混入する。`hrv_status = stale` と保持時間の記録が必須 |

**推奨（判断は研究担当）**: 研究データとしては A を基本とし、ライブ表示の反応性が必要なら B を「別方式・暫定」と明示して追加する。C を採る場合は、鮮度の閾値（現在 6 時間）を研究担当が決め、`hrv_status` と HRV の計測時刻を必ず記録する。

## 10. OpenAI 連携の検証結果

| 項目 | 実装 | 検証方法 | 結果 |
|---|---|---|---|
| InsightProvider 抽象化（Local / Remote / Service） | ✅ | ロジックテスト | ✅ |
| 既存ローカル AI の維持 | ✅ ロジック不変 | 同一結果のテスト | ✅ |
| リモートへの切り替え条件 | Mock を含む → 不可、同意なし → 不可、サーバー未設定 → 不可 | テスト | ✅ |
| iOS → 自前サーバー | https のみ（localhost のみ http）、Bearer トークン、タイムアウト 20 秒 | スタブ通信テスト＋ローカルサーバー E2E | ✅（ローカル） |
| サーバー → OpenAI | Responses API、Structured Outputs（strict JSON Schema）、`store: false`、免責文は固定文言で上書き | スタブ fetch による単体テスト | ✅（スタブのみ） |
| 構造化応答の検証 | サーバーとクライアントの二重検証（必須項目・文字数・禁止表現・tone・request_id） | テスト | ✅ |
| タイムアウト | iOS 20 秒、サーバー 15 秒（**本文受信中も有効に修正 F4**） | テスト | ✅ |
| 通信失敗・不正応答 | 401/400/403/413/502/503/504 → クライアントはローカルにフォールバック | テスト | ✅ |
| 機密情報 | API キーはサーバーの環境変数のみ（iOS・Git に記載なし、`.dev.vars` は gitignore・存在しない）。ログにリクエスト内容・トークンを出さない | コード確認＋ログ検索 | ✅ |
| 同意・認証 | 同意は既定 OFF・版管理あり。サーバーはクライアントトークン（未設定なら全拒否） | テスト | ✅。**ユーザー単位の認証は未実装**（アプリの認証がモックのため） |
| 実計測データの送信制限 | Mock を含むセッションは送らない。送る項目は丸めた心拍・スコア・状態・HRV の増減方向・場面・方法・自己評価のみ。メモ・日時・HRV の数値は送らない。サーバーは未知のキーを拒否 | テスト | ✅ |
| **OpenAI 実 API 通信** | — | 未実施（API キー・課金の許可なし） | **未検証** |
| **Cloudflare へのデプロイ** | wrangler 設定のみ | 未実施（権限なし） | **未検証** |

**スタブでの成功は、OpenAI 実通信の成功を意味しない。** 実際のモデルの応答が禁止表現・文字数の検証に通るかは未確認。

## 11. メンバーの実装保全状況

- 削除したファイルは 0 件。HealthKit・WatchConnectivity・HRV observer・認証画面・グラフィック・ガイド・履歴の既存ロジックは維持（変更は接続部分のみ。§2 の一覧）
- 未接続のまま残しているコード（削除していない）: `ContentView`（旧 4 タブ）、`LiveWaveView`、`Breathing/`、`MindWaveSyncTransitionView`、`StarfieldGraphicView`、`PlaceholderGraphicView`、`GuideSessionView`（legacy wrapper）、`computeConfidence`。扱いはチームで決める（docs/INTEGRATION_STATUS.md §5）
- メンバー実装の変更点: `HomeView` の設定シートを共通メニュー経由に変更、`ContextCalibrationView` にメニュー内編集モード（`onComplete`）を追加、`FeedbackRecordView` に `initialMemo` を追加、`GuideFlowView` のスナップショット・AI 呼び出しを接続。いずれも既定の呼び出し方では従来と同じ動作

## 12. 実機で未検証の項目

1. Apple Watch → iPhone の心拍受信（3 チャネル、`schemaVersion: 1` 追加後）
2. HealthKit の心拍・HRV 取得、HRV observer、7 日平均によるベースライン
3. Mock OFF で `source = watch_live` / `health_kit` になり、鮮度切れで切り替わること
4. HRV 未取得時に 38 で固定される実際の頻度（特に鮮度 6 時間の影響）
5. ガイド開始から保存・履歴反映までのタップ操作、レバー操作、共通メニュー操作
6. ログイン／ゲスト選択から状況確認・ホームまでのタップ操作
7. 設定画面の外部 AI 同意トグルの操作
8. OpenAI 実通信・Cloudflare 上での動作

## 13. マージを妨げる問題

| # | 内容 | 種類 |
|---|---|---|
| 1 | 実機で Watch / HealthKit → スコア → グラフィック → 履歴の経路を確認していない | 実機検証待ち |
| 2 | 鮮度 6 時間の導入で 38 固定の頻度が統合前より増える（§9）。研究担当の判断なしに main へ入れると、研究データの性質が変わる | 研究判断待ち |
| 3 | ナビゲーション・ホーム・状況確認画面の変更について、各画面の担当メンバーによるレビューが未実施 | レビュー待ち |
| 4 | リポジトリが iCloud 同期フォルダにあり、`.git` のファイルが退避されている（§3 環境所見）。push 前に `git fsck` で整合性を確認すること | 環境 |

OpenAI 実通信・デプロイ・ユーザー単位の認証は、外部 AI を既定 OFF・未設定のまま出荷するならマージの妨げにはならない（未設定ならローカル AI のみで動作する）。

## 14. 今後の研究判断が必要な項目

1. HRV 未取得時の扱い（§9 の A / B / C）
2. 鮮度の閾値（HealthKit 心拍 30 分、HRV 6 時間、Watch 15 秒）
3. 個人ベースラインの規則: アプリ蓄積へ切り替える件数（30 件・3 日）と、**面接・スピーチなど緊張しやすい場面の心拍も平常値として記録している点**（現在は身体状態の申告中のみ除外）
4. ホームの表示補正（心拍 100/115/130 bpm で表示スコアの下限を引き上げ）を研究スコアと別に残すか。Mock 中・古い心拍にも効く点（F6）の扱い
5. `MindState` の 3 状態・閾値（32/69）と、表示側の CALM/FOCUS/ALERT/OVLD 表記の統一
6. 確からしさ（confidence）の規則（Watch 0.75/0.50、HealthKit 0.65/0.40）を研究上どう使うか

## 15. 統合責任者が次に行うべき作業

1. この監査の差分（`627b95d..HEAD`）と夜間作業の差分（`0be98a3..627b95d`）をレビューする
2. `git fsck` の結果を確認し、リポジトリを iCloud 同期の対象外へ移すか判断する（移す場合は push 済みのリモートから clone し直すのが安全）
3. ブランチを push し、**ドラフト PR** として各画面の担当メンバーにレビューを依頼する（§16）
4. 実機で §12 の 1〜6 を確認する（Mock OFF、デバッグ診断画面の分析結果 JSON で `source`・`hrv_status`・`baseline_status` を確認）
5. 研究担当と §14 の 1〜3 を決める。決定後、B を採る場合は `MindAnalyzer` に新しい Analyzer を追加する（既存の Analyzer・計算式は変更しない）
6. OpenAI を使う場合は API キーを用意し、ローカルで実通信を確認してからデプロイする（docs/OPENAI_SETUP.md）
7. 改善提案: 「タイトルへ戻る」の確認文に「実施中のガイドは保存されません」を加える／状況確認の変更時に即時再計算する（F8）

---

## 総合判定

| 領域 | 判定 | 理由 |
|---|---|---|
| Git・変更差分 | **COMPLETE** | 6 コミットと全変更ファイルを確認。削除・無効化・ダミーなし |
| ナビゲーション | **PARTIAL** | 責務・二重管理なしをコードとテストで確認、10 画面の表示を確認。タップ操作の通し確認は未実施 |
| JSON 契約 | **PARTIAL** | 履歴・Watch・AI の契約は実処理で使用。`MeasurementSampleDTO`・`GraphicInputDTO` は未使用、分析結果はデバッグ表示のみ |
| データパイプライン | **PARTIAL** | ロジックはテスト済み、不具合 2 件を修正。実機データで未検証 |
| スコア 38 問題 | **BLOCKED** | 原因・条件・影響は特定済み。対応方針は研究判断が必要 |
| OpenAI 連携 | **PARTIAL** | iOS・サーバーの正常系・異常系はスタブで検証済み。OpenAI 実通信・デプロイは未実施（外部条件） |
| 再テスト・不具合修正 | **COMPLETE** | 前回の exit=1 の原因を特定・修正。12 回の実行で失敗 0。修正 4 件 |
| 実機検証 | **BLOCKED** | 実機・ペアリング済み Watch が必要 |

## 16. push・PR に関する推奨

- **ブランチの push とドラフト PR の作成: 推奨する。** 監査時点で `git fsck` はエラーなし（§5）。push 直前にも再確認するとよい。理由: ビルド・テストは全て成功し、データ消失（F2）を含む既知の不具合は修正済み。iCloud 上のローカルリポジトリだけに成果がある状態のほうが、破損・消失のリスクが高い。PR はレビュー用のドラフトとし、§13 の項目を PR 本文に明記する
- **main へのマージ: 現時点では推奨しない。** §13 の 1〜3（実機検証・鮮度とスコア 38 の研究判断・担当メンバーのレビュー）が完了してからにする
