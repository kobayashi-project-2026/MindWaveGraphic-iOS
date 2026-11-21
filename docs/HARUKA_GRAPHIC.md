# 宇宙グラフィック（制作: HarukaSasaki-bit さん）の採用

ホームの緊張グラフィックに、**HarukaSasaki-bit さんが制作した宇宙グラフィック**を採用した（2026-11-18）。
元のコード: ブランチ `feature/HarukaSasaki-bit-space` の 2967634「Update spaceship state graphic effects」
（`Graphics/SpaceshipStateGraphicView.swift` の StarfieldView・LightningView・MocorinSeatView）。
元のブランチは変更していない。移植先: `Graphics/HarukaSpaceGraphicView.swift`。

## 採用した要素
| 要素 | 元 | 本番での動き |
|---|---|---|
| 星空（800 個・奥から手前へ流れる・軌跡） | StarfieldView | 速さ = 0.2 + スコア/100 × 2.5（元の式）。スコア 30 超で軌跡。色: 低い=青白い / 中=白 / 高い=暖色 |
| 隕石 | StarfieldView | 33 未満 0 個・70 未満 20 個・70 以上 40 個（元の式）。速さもスコアで変わる |
| 雷 | LightningView | 70 以上で表示。80 未満=水色・短い / 90 未満=紫・枝分かれ / 90 以上=白・長い＋弱い画面フラッシュ（元の式） |
| もこりんの座席 | MocorinSeatView | 元の形・色のまま。友達制作のもこりん（`MokorinAvatarView`。原本は変更しない）を座らせる |

## 採用できなかった要素・置き換え
- **画像 `inseki`（隕石）・`cockpit`・`ship`**: リポジトリ（全ブランチの履歴）に画像がない。隕石は Canvas の図形（でこぼこの岩・クレーター・尾）で描いた。
  コックピットはホーム既存の `CockpitFrameCanvas`（窓枠）をそのまま使う。画像を受け取ったら Assets.xcassets に追加して置き換えられる
- **「STATUS : NORMAL / TENSION」の表示**: 未計測を NORMAL と断定しないため出さない（状態はホームの状態カードが表示）
- **Slider・@State のスコア**: 本番の入力には使わない。`#Preview` の確認用だけに残した

## 本番のデータとの接続
- 入力は `GraphicInput`（score 0〜100・confidence・state）だけ。`GraphicHostView` → `GraphicPlugin` → `TeamGraphicView` → `HarukaSpaceGraphicView`
- 値の出どころ（`GraphicDataStatus`: 未計測 / デモ / 試作スコア / 実測）はホームが環境値で渡す。GraphicInput・計算式・HealthKit・WatchConnectivity は変更していない
- 未計測: 星がゆっくり流れるだけの待機表示（隕石・雷・軌跡なし）
- confidence が低いほど星を少し暗くする
- 視差効果を減らす（Reduce Motion）: 星を遅くし、雷は点滅させずに薄く表示、画面のフラッシュなし

## 切り替え
- 既定: 新しいグラフィック（`haruka`）
- 従来の宇宙船グラフィックに戻す: UserDefaults の `mw_graphic_style` を `classic`
  - シミュレーター: `xcrun simctl spawn "Audit iPhone 17 Pro" defaults write com.kobayashiproject2026.mindwavegraphic mw_graphic_style classic`（戻すときは `defaults delete ... mw_graphic_style`）
  - DEBUG ビルドの起動時: 環境変数 `MW_GRAPHIC_STYLE=classic`（設定より優先）
- 従来のグラフィックのときは、状態カードに小さなもこりんを表示する（新しいグラフィックでは座席に座っているため出さない）

## スコア別の確認（シミュレーター）
シミュレーターのデモ値（既存の `sim_demo_override_enabled` / `sim_demo_score`）で確認:
`xcrun simctl spawn "Audit iPhone 17 Pro" defaults write com.kobayashiproject2026.mindwavegraphic sim_demo_override_enabled -bool YES` と
`... sim_demo_score -float 85` → アプリを起動し直す（デモ値。実測ではない）。終わったら `-bool NO`。
