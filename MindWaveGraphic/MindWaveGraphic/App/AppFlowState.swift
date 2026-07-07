// AppFlowState.swift
// App
//
// 認証フローの状態を管理するObservableObject。
// アプリ全体で1インスタンスのみ生成し、AppRootViewから各画面へ渡す。
//
// 将来のFirebase Authentication接続時は、このクラスの内部実装を変更するだけでよい。
// UIコード（各Viewファイル）は変更不要になるよう設計している。
//
// セキュリティ：inputEmail / inputPassword はメモリ上の一時状態のみ。
// UserDefaults, Keychain, AppStorage, ログ, ファイルへの書き込みは禁止。

import SwiftUI
import Combine

// MARK: - 認証フロー状態

/// 認証前後の画面遷移を管理するenum。
/// 将来Firebase接続時も、このenumは変更せずに内部処理だけ差し替える。
enum AuthStatus: Equatable {
    case logoSplash          // ロゴ画面（起動直後）
    case accountGuidance     // アカウント案内
    case topMenu             // ログイン方法選択
    case signUp              // 新規登録
    case logIn               // ログイン
    case contextCalibration  // 測定前コンテキスト選択（場面・身体状態）
    case mainApp             // メインアプリ
}

// MARK: - AppFlowState

/// 認証フローと仮ユーザー入力を保持するObservableObject。
/// @MainActorで全更新をメインスレッドで実行する。
@MainActor
final class AppFlowState: ObservableObject {

    /// 現在の認証フローの状態
    @Published var authStatus: AuthStatus = .logoSplash

    /// ゲストとしてメインアプリへ進んだか
    @Published var isGuestUser: Bool = false

    /// 測定コンテキスト（場面・身体状態）。contextCalibrationで選択、mainAppで参照。
    @Published var measurementContext: MeasurementContext = .default

    // ── メモリ上の一時入力（永続化・ログ出力 禁止） ──

    /// 入力中のメールアドレス（メモリ上のみ。送信・保存しない）
    @Published var inputEmail: String = ""

    /// 入力中のパスワード（メモリ上のみ。送信・保存しない）
    @Published var inputPassword: String = ""

    /// 入力中のユーザー名
    @Published var inputUsername: String = ""

    // MARK: - 遷移メソッド

    /// 全状態をクリアしてロゴ画面へ戻る。
    /// ログアウト・ゲスト終了時に使用する。
    func returnToSplash() {
        isGuestUser         = false
        measurementContext  = .default
        inputEmail          = ""
        inputPassword       = ""
        inputUsername       = ""
        authStatus          = .logoSplash
        print("[Navigation] returnToSplash")
    }
}
