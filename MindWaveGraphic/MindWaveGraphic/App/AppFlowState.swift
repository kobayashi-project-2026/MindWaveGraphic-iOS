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

    /// 測定前の会話でもこりんが理解した内容（結果の説明・提案で使う）。メモリのみ。保存・外部送信しない
    @Published var mokorinMemory: MokorinSessionMemory? = nil

    /// 改善の途中でホームへ戻ったときの状態（全体UI 24〜25 ページ「改善途中の状態」）。メモリのみ
    @Published var pendingImprovement: PendingImprovement? = nil

    /// 試作スコアの基準（HR0・SDNN0）。会話で緊張の強さ（S0）を聞いたあとの最初の計測値。メモリのみ
    @Published var prototypeBaseline: PrototypeBaseline? = nil

    /// 会話のあと「改善方法を見る」を選んだ（メイン画面で改善を開く）
    @Published var requestImprovement = false

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
        mokorinMemory       = nil
        pendingImprovement  = nil
        prototypeBaseline   = nil
        inputEmail          = ""
        inputPassword       = ""
        inputUsername       = ""
        authStatus          = .logoSplash
        print("[Navigation] returnToSplash")
    }
}


/// 途中でやめた改善（ガイド）の状態。ホームの「改善途中」表示と、改善での再開に使う
struct PendingImprovement: Equatable {
    let scene: MeasurementScene
    let exercise: GuideExercise
    let durationSeconds: Int
    let remainingSeconds: Int
    let savedAt: Date
}

/// 試作スコアの基準。どの会話（S0）に対する基準かを capturedFor で区別する
struct PrototypeBaseline: Equatable {
    let hr: TimedReading?
    let sdnn: TimedReading?
    /// 対応する会話の時刻（MokorinSessionMemory.capturedAt）
    let capturedFor: Date
}
