import SwiftUI

/// 共通メニューから開くモーダル画面の振り分け。
/// 各画面は既存実装（ContextCalibrationView / SettingsView / RecordDetailView / FeedbackRecordView）を再利用する。
/// セッションデータが必要な「確認」「フィードバック」は、ガイドフローで保存された直近の記録を対象にする。
struct AppModalDestinationView: View {

    let modal: AppModal

    @EnvironmentObject private var flowState: AppFlowState
    @EnvironmentObject private var navManager: AppNavigationManager
    @EnvironmentObject private var historyStore: GuideHistoryStore

    var body: some View {
        switch modal {
        case .contextCalibration:
            // 対話（状況確認）：認証フローと同じ画面を、メインアプリ内編集モードで表示する
            ContextCalibrationView(flowState: flowState) {
                navManager.dismissModal()
            }

        case .settings:
            SettingsView()

        case .latestRecordConfirmation:
            if let record = historyStore.records.first {
                NavigationStack {
                    RecordDetailView(record: record)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("閉じる") { navManager.dismissModal() }
                            }
                        }
                }
                .preferredColorScheme(.dark)
            } else {
                NoSessionRecordView(purpose: "結果の確認") {
                    navManager.navigate(to: .improvement)
                } onClose: {
                    navManager.dismissModal()
                }
            }

        case .latestRecordFeedback:
            if let record = historyStore.records.first {
                FeedbackRecordView(
                    before: record.before,
                    after: record.after,
                    scene: record.scene,
                    exercise: record.exercise,
                    durationSeconds: record.durationSeconds,
                    onSave: { memo in
                        historyStore.updateEmotionMemo(id: record.id, memo: memo)
                        navManager.dismissModal()
                    },
                    onCancel: { navManager.dismissModal() },
                    initialMemo: record.emotionMemo ?? ""
                )
            } else {
                NoSessionRecordView(purpose: "フィードバックの記入") {
                    navManager.navigate(to: .improvement)
                } onClose: {
                    navManager.dismissModal()
                }
            }
        }
    }
}

/// 記録がまだ無いときの案内。架空の記録は表示せず、ガイド開始へ誘導する。
private struct NoSessionRecordView: View {
    let purpose: String
    let onStartGuide: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                MindWaveCyberBackground()
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(MindWaveCyberTheme.cyan.opacity(0.7))
                    Text("まだガイドの記録がありません")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                    Text("\(purpose)には、「整える」でガイドを1回完了して記録を保存してください。")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("整えるへ移動", action: onStartGuide)
                        .buttonStyle(.borderedProminent)
                        .tint(MindWaveCyberTheme.cyan)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onClose)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
