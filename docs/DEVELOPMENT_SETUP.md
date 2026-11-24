# Mind Wave Graphic 開発手順

## 正しいプロジェクト
`/Users/takakikeita/Desktop/mind-wave-graphic/MindWaveGraphic/MindWaveGraphic.xcodeproj`

## GitHub
https://github.com/kobayashi-project-2026/MindWaveGraphic-iOS

## 使うScheme
`MindWaveGraphiciOSOnly`

他に `MindWaveGraphic`（iOS + Watch companion 込み）、`MindWaveGraphicWatch Watch App` のschemeも存在するが、
共同編集時に迷わないよう基本は `MindWaveGraphiciOSOnly` を使うこと。

## Xcodeで開いてはいけない古いパス
`/Users/takakikeita/Desktop/MindWaveGraphic-iOS`（存在する場合は別プロジェクトの残骸の可能性があるため開かない）

## 初回セットアップ
1. GitHubからclone
   ```
   git clone https://github.com/kobayashi-project-2026/MindWaveGraphic-iOS.git
   ```
2. Xcodeで `MindWaveGraphic/MindWaveGraphic.xcodeproj` を開く
3. Schemeを `MindWaveGraphiciOSOnly` にする
4. Simulatorまたは実機を選ぶ
5. Product → Clean Build Folder
6. Run

## Simulator実行時の注意
watchOSシミュレータのランタイムバージョンがXcodeのSDKバージョンと一致していないと、
Watch Appのアセットカタログのビルドで失敗することがある。
その場合は Xcode → Settings → Platforms から一致するwatchOS Simulatorランタイムを追加でインストールする。

## 実機Runで失敗した場合
- Signing & Capabilitiesを確認する
- Bundle IDを勝手に変えない
- Teamを勝手に変えない
- entitlementsエラーが出たら正しいプロジェクト（上記パス）を開いているか確認する

## やってはいけないこと
- Pictri関連プロジェクトと混ぜない
- studyboki関連プロジェクトと混ぜない
- APIキーを直書きしない
- force pushしない
