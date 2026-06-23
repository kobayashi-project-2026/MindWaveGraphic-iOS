// AccountGuidanceView.swift
// Authentication
//
// ログイン/新規登録 または ゲスト利用を選ぶ案内画面。
// ロゴ画面から自動遷移した後に表示される。

import SwiftUI

// MARK: - AccountGuidanceView

/// アカウント案内画面。2つの選択肢を提示する。
struct AccountGuidanceView: View {

    var flowState: AppFlowState

    var body: some View {
        ZStack {
            CyberGridBackground()

            VStack(spacing: 0) {

                Spacer()

                // ヘッダー
                VStack(spacing: 10) {
                    Text("MIND WAVE")
                        .font(.system(size: 28, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(AuthDesign.textPrimary)
                        .tracking(5)

                    Text("GRAPHIC")
                        .font(.system(size: 13, weight: .light, design: .monospaced))
                        .foregroundStyle(AuthDesign.accent)
                        .tracking(8)
                }
                .padding(.bottom, 48)

                // 説明テキスト
                Text("計測を開始するには\nアカウントの選択が必要です")
                    .font(AuthDesign.captionFont)
                    .foregroundStyle(AuthDesign.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.bottom, 40)

                // ボタン群
                VStack(spacing: 14) {

                    // ログイン / 新規登録
                    Button {
                        flowState.authStatus = .topMenu
                        print("[Navigation] accountGuidance -> topMenu")
                    } label: {
                        Text("ログイン / 新規登録")
                            .font(AuthDesign.buttonFont)
                            .foregroundStyle(AuthDesign.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: AuthDesign.buttonHeight)
                            .background(AuthDesign.accentFill,
                                        in: RoundedRectangle(cornerRadius: AuthDesign.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: AuthDesign.cornerRadius)
                                    .strokeBorder(AuthDesign.accent.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    // ゲスト利用
                    Button {
                        flowState.isGuestUser = true
                        flowState.authStatus  = .mainApp
                        print("[Navigation] guest -> mainApp")
                    } label: {
                        Text("ログインせずに利用する（ゲスト）")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AuthDesign.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: AuthDesign.buttonHeight)
                            .background(AuthDesign.secondaryFill,
                                        in: RoundedRectangle(cornerRadius: AuthDesign.cornerRadius))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AuthDesign.horizontalPadding)

                Spacer()
                Spacer()
            }
        }
    }
}

#Preview {
    AccountGuidanceView(flowState: AppFlowState())
}
