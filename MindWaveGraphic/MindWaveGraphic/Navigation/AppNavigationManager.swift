import SwiftUI
import Combine

/// アプリ全体の遷移対象画面の定義
///
/// チームが定義した8画面を、既存実装の画面へ次のように対応付ける。
/// - title          : 認証フロー先頭（PureLogoSplashView）へ戻る＝ログアウト
/// - dialogue       : 状況確認（ContextCalibrationView）をモーダル表示
/// - tensionGraphic : ホームタブ（HomeView：コックピット緊張グラフィック）
/// - improvement    : 整えるタブ（GuideView → GuideFlowView）
/// - confirmation   : 直近ガイドセッションの結果確認（RecordDetailView）
/// - feedback       : 直近ガイドセッションへの感想メモ（FeedbackRecordView）
/// - pastLogs       : 履歴タブ（HistoryView）
/// - settings       : 設定（SettingsView）をモーダル表示
enum AppScreen: String, CaseIterable, Identifiable {
    case title = "タイトル"
    case dialogue = "対話（状況確認）"
    case tensionGraphic = "緊張グラフィック"
    case improvement = "改善（ワーク）"
    case confirmation = "確認"
    case feedback = "フィードバック"
    case pastLogs = "過去ログ確認"
    case settings = "設定"

    var id: String { rawValue }

    /// SF Symbols のアイコン名
    var iconName: String {
        switch self {
        case .title: return "house.fill"
        case .dialogue: return "bubble.left.and.bubble.right.fill"
        case .tensionGraphic: return "waveform.path.ecg"
        case .improvement: return "sparkles"
        case .confirmation: return "checkmark.circle.fill"
        case .feedback: return "square.and.pencil"
        case .pastLogs: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }

    /// この画面がメインタブの1つである場合、そのタブ
    var mainTab: MainTab? {
        switch self {
        case .tensionGraphic: return .home
        case .improvement:    return .guide
        case .pastLogs:       return .history
        default:              return nil
        }
    }

    /// この画面がモーダル表示である場合、そのモーダル種別
    var modal: AppModal? {
        switch self {
        case .dialogue:     return .contextCalibration
        case .confirmation: return .latestRecordConfirmation
        case .feedback:     return .latestRecordFeedback
        case .settings:     return .settings
        default:            return nil
        }
    }

    /// 直近のガイドセッション記録がないと開けない画面か
    var requiresSessionRecord: Bool {
        self == .confirmation || self == .feedback
    }
}

/// メインアプリの3タブ。rawValue は既存の selectedTab(Int) と同じ値を保つ。
/// HomeView / GuideView / CockpitLeverNav は Binding<Int> のまま利用できる。
enum MainTab: Int, CaseIterable {
    case home    = 0
    case guide   = 1
    case history = 2

    var screen: AppScreen {
        switch self {
        case .home:    return .tensionGraphic
        case .guide:   return .improvement
        case .history: return .pastLogs
        }
    }
}

/// メインアプリ上に重ねて表示する画面
enum AppModal: String, Identifiable {
    case contextCalibration
    case settings
    case latestRecordConfirmation
    case latestRecordFeedback

    var id: String { rawValue }

    var screen: AppScreen {
        switch self {
        case .contextCalibration:       return .dialogue
        case .settings:                 return .settings
        case .latestRecordConfirmation: return .confirmation
        case .latestRecordFeedback:     return .feedback
        }
    }
}

/// メインアプリ内の画面遷移状態を一元管理する。
///
/// 状態の持ち主の分担:
/// - 認証フロー（スプラッシュ〜状況選択〜mainApp）: AppFlowState.authStatus
/// - mainApp 内のタブ・モーダル: このクラス（唯一の情報源）
/// MainTabView の selectedTab はこのクラスから導出する Binding であり、独自に状態を持たない。
@MainActor
final class AppNavigationManager: ObservableObject {

    /// 現在選択中のメインタブ
    @Published private(set) var selectedTab: MainTab

    /// 表示中のモーダル（nil = タブ画面のみ）
    @Published var activeModal: AppModal? = nil

    /// タイトルへ戻る（ログアウト）確認ダイアログの表示状態
    @Published var isTitleReturnConfirmationPresented = false

    init(initialTab: MainTab = AppNavigationManager.launchTab()) {
        self.selectedTab = initialTab
    }

    /// 現在ユーザーに見えている画面（モーダル優先）
    var currentScreen: AppScreen {
        activeModal?.screen ?? selectedTab.screen
    }

    /// 共通メニュー等から画面へ移動する
    func navigate(to screen: AppScreen) {
        MindWaveDebugLogger.log(.navigation, "navigate request to=\(screen) from=\(currentScreen)")
        if let tab = screen.mainTab {
            activeModal = nil
            select(tab)
        } else if let modal = screen.modal {
            activeModal = modal
        } else if screen == .title {
            // 計測中のデータを失う操作のため、必ず確認を挟む
            isTitleReturnConfirmationPresented = true
        }
    }

    /// タブを選択する（CockpitLeverNav・GuideFlowView からの Binding 経由も含む）
    func select(_ tab: MainTab) {
        guard selectedTab != tab else { return }
        MindWaveDebugLogger.log(.navigation, "tab selected \(selectedTab) -> \(tab)")
        selectedTab = tab
    }

    /// 既存Viewが使う Int 型の selectedTab を受け取る。未知の値は無視する。
    func selectTab(index: Int) {
        guard let tab = MainTab(rawValue: index) else {
            MindWaveDebugLogger.log(.error, "[Navigation] unknown tab index=\(index) ignored")
            return
        }
        select(tab)
    }

    /// モーダルを閉じる
    func dismissModal() {
        guard activeModal != nil else { return }
        MindWaveDebugLogger.log(.navigation, "modal dismissed \(String(describing: activeModal))")
        activeModal = nil
    }

    /// ログアウト（タイトルへ戻る）時にメインアプリ内の遷移状態を初期化する
    func resetForSignOut() {
        activeModal = nil
        isTitleReturnConfirmationPresented = false
        selectedTab = .home
        MindWaveDebugLogger.log(.navigation, "navigation reset for sign-out")
    }

    /// 起動時のタブ。既存の INITIAL_TAB 環境変数（シミュレーター検証用）を尊重する。
    nonisolated static func launchTab() -> MainTab {
        if let raw = ProcessInfo.processInfo.environment["INITIAL_TAB"],
           let index = Int(raw),
           let tab = MainTab(rawValue: index) {
            return tab
        }
        return .home
    }
}
