// AppRootView.swift
// App
//
// アプリのルートView。AppFlowState.authStatusに応じて認証画面とメインアプリを切り替える。
//
// 設計方針：
// - 認証前画面（logoSplash 〜 logIn）はこのファイルで管理する画面群
// - mainAppになったとき、既存のContentView（4タブ・Watch・HRV）をそのまま表示する
// - 既存ContentViewは一切変更しない
//
// 将来Firebase接続時は AppFlowState の内部処理を変更するだけで対応できる。

import SwiftUI

/// アプリ全体のルートView。
/// AuthStatusのswitchによって認証前画面と既存メインアプリを切り替える。
struct AppRootView: View {

    /// アプリ全体で1つだけ生成するフロー状態
    @StateObject private var flowState = AppFlowState()

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SKIP_ONBOARDING"] == "1" {
                // PureLogoSplashViewを生成しないことでタイマーが発火せず authStatus が上書きされない
                MainTabView()
                    .environmentObject(flowState)
                    .onAppear { flowState.isGuestUser = true }
            } else {
                authFlow
            }
            #else
            authFlow
            #endif
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: flowState.authStatus)
    }

    @ViewBuilder
    private var authFlow: some View {
        switch flowState.authStatus {

        case .logoSplash:
            // ロゴ画面：起動直後に表示し、約1.5秒後に自動遷移
            PureLogoSplashView(flowState: flowState)

        case .accountGuidance:
            // アカウント案内：ログイン/新規登録 または ゲスト利用の選択
            AccountGuidanceView(flowState: flowState)

        case .topMenu:
            // 方法選択：新規登録 or 登録済みでログイン
            TopMenuView(flowState: flowState)

        case .signUp:
            // 新規登録画面（現段階は本番認証未接続）
            SignUpView(flowState: flowState)

        case .logIn:
            // ログイン画面（現段階は本番認証未接続）
            LogInView(flowState: flowState)

        case .contextCalibration:
            // 測定前コンテキスト選択：場面・身体状態を選んでスコア補正に利用する
            ContextCalibrationView(flowState: flowState)

        case .mainApp:
            // フェーズ3：3タブのMainTabViewへ切り替え。
            // MindWaveViewModel / GuideHistoryStore / AppNavigationManager は AppRootContainerView から受け取る。
            MainTabView()
                .environmentObject(flowState)
        }
    }
}

#Preview {
    // 計測ViewModel・履歴・画面遷移は AppRootContainerView が所有するため、コンテナ経由でプレビューする
    AppRootContainerView()
}
