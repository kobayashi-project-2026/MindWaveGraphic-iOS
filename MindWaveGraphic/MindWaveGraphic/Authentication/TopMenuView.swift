// TopMenuView.swift
// Authentication
//
// 「新しくアカウントを作る」または「登録済みでログイン」を選ぶ画面。
// AccountGuidanceViewから「ログイン/新規登録」を押したときに表示される。

import SwiftUI

// MARK: - TopMenuView

/// アカウント作成 or ログインを選択する画面。
struct TopMenuView: View {

    var flowState: AppFlowState

    var body: some View {
        ZStack {
            CyberGridBackground()

            VStack(spacing: 0) {

                // 戻るボタン
                HStack {
                    Button {
                        flowState.authStatus = .accountGuidance
                        print("[Navigation] topMenu -> accountGuidance (back)")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .light))
                            Text("戻る")
                                .font(AuthDesign.captionFont)
                        }
                        .foregroundStyle(AuthDesign.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AuthDesign.horizontalPadding)
                    .padding(.top, 20)

                    Spacer()
                }

                Spacer()

                VStack(spacing: 10) {
                    Text("アカウントを選択")
                        .font(AuthDesign.headingFont)
                        .foregroundStyle(AuthDesign.textPrimary)
                        .tracking(1)

                    Text("利用方法を選んでください")
                        .font(AuthDesign.captionFont)
                        .foregroundStyle(AuthDesign.textSecondary)
                }
                .padding(.bottom, 48)

                // ボタン群
                VStack(spacing: 14) {

                    // 新規登録
                    Button {
                        flowState.authStatus = .signUp
                        print("[Navigation] topMenu -> signUp")
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16, weight: .light))
                            Text("新しくアカウントを作る")
                                .font(AuthDesign.buttonFont)
                        }
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

                    // 既存アカウントでログイン
                    Button {
                        flowState.authStatus = .logIn
                        print("[Navigation] topMenu -> logIn")
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "key.horizontal")
                                .font(.system(size: 16, weight: .light))
                            Text("登録済みアカウントでログイン")
                                .font(AuthDesign.buttonFont)
                        }
                        .foregroundStyle(AuthDesign.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: AuthDesign.buttonHeight)
                        .background(AuthDesign.secondaryFill,
                                    in: RoundedRectangle(cornerRadius: AuthDesign.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AuthDesign.cornerRadius)
                                .strokeBorder(AuthDesign.textSecondary.opacity(0.25), lineWidth: 1)
                        )
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
    TopMenuView(flowState: AppFlowState())
}
