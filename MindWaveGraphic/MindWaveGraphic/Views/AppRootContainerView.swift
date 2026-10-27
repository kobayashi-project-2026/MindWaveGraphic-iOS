import SwiftUI

/// 認証フローと共通ナビゲーションを接続するルートコンテナ。
///
/// 以前のバージョンでは AppScreen ごとに TitleView / DialogueView などを switch で表示していたが、
/// それらの画面はリポジトリに存在しなかった。現在は同じ意図（8画面を共通メニューから行き来する）を、
/// 既存実装の画面へ対応付ける形で実現している。対応表は AppNavigationManager.swift の AppScreen を参照。
///
/// このViewが長寿命のオブジェクトを所有する理由:
/// - MindWaveViewModel : 計測（Watch受信・HealthKit監視）を認証画面の切り替えで作り直さないため
/// - GuideHistoryStore  : 履歴ストアを1インスタンスに保つため
/// - AppNavigationManager : メインアプリ内の画面遷移の唯一の情報源
struct AppRootContainerView: View {

    // 画面遷移管理（チームが追加した仕組みを、メインアプリ内の唯一の遷移状態として使う）
    @StateObject private var navManager = AppNavigationManager()

    // 計測パイプライン。ここで1回だけ生成し、全画面へ共有する
    @StateObject private var viewModel = MindWaveViewModel()

    // ガイドセッション履歴。ガイド・履歴・共通メニュー（確認/フィードバック）で共有する
    @StateObject private var historyStore = GuideHistoryStore()

    var body: some View {
        // 既存のログイン・状況選択・メインアプリの流れを維持する
        AppRootView()
            .environmentObject(navManager)
            .environmentObject(viewModel)
            .environmentObject(historyStore)
    }
}
