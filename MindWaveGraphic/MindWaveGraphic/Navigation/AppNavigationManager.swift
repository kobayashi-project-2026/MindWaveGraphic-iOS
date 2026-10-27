import SwiftUI

/// アプリ全体の遷移対象画面の定義
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
}

/// 全画面の切り替え状態を管理するStateオブジェクト
final class AppNavigationManager: ObservableObject {
    @Published var currentScreen: AppScreen = .dialogue

    func navigate(to screen: AppScreen) {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentScreen = screen
        }
    }
}
