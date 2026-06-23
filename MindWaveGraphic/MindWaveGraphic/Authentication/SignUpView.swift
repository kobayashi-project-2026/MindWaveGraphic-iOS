// SignUpView.swift
// Authentication
//
// 新規アカウント登録画面。
// 現段階ではFirebase等の本番認証は未接続。
// 入力値はメモリ上のみ保持（UserDefaults等への書き込み禁止）。
// 「アカウントを登録する」を押すとLogInViewへ進む。

import SwiftUI

// MARK: - SignUpView

/// 新規アカウント登録画面（現段階：本番認証未接続）。
struct SignUpView: View {

    // @ObservedObject: inputUsername/inputEmail/inputPasswordへのバインディング生成に必要
    @ObservedObject var flowState: AppFlowState

    @State private var showValidationError = false

    // 入力バリデーション：全フィールドが空でないこと
    private var canSubmit: Bool {
        !flowState.inputUsername.trimmingCharacters(in: .whitespaces).isEmpty &&
        !flowState.inputEmail.trimmingCharacters(in: .whitespaces).isEmpty &&
        !flowState.inputPassword.isEmpty
    }

    var body: some View {
        ZStack {
            CyberGridBackground()

            ScrollView {
                VStack(spacing: 0) {

                    // 戻るボタン
                    HStack {
                        Button {
                            flowState.authStatus = .topMenu
                            print("[Navigation] signUp -> topMenu (back)")
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
                        Spacer()
                    }
                    .padding(.horizontal, AuthDesign.horizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 32)

                    // タイトル
                    VStack(spacing: 8) {
                        Text("アカウント作成")
                            .font(AuthDesign.headingFont)
                            .foregroundStyle(AuthDesign.textPrimary)

                        // 本番未接続の明示（過度に目立たない）
                        Text("※ 認証基盤は次フェーズで接続されます")
                            .font(.system(size: 10, weight: .light))
                            .foregroundStyle(AuthDesign.textSecondary.opacity(0.6))
                    }
                    .padding(.bottom, 36)

                    // 入力フォーム
                    VStack(spacing: 16) {

                        authField(
                            icon: "person",
                            placeholder: "ユーザー名",
                            text: $flowState.inputUsername,
                            isSecure: false
                        )

                        authField(
                            icon: "envelope",
                            placeholder: "メールアドレス",
                            text: $flowState.inputEmail,
                            isSecure: false,
                            keyboardType: .emailAddress
                        )

                        authField(
                            icon: "lock",
                            placeholder: "パスワード",
                            text: $flowState.inputPassword,
                            isSecure: true
                        )

                        // バリデーションエラー
                        if showValidationError {
                            Text("すべての項目を入力してください")
                                .font(AuthDesign.captionFont)
                                .foregroundStyle(Color.red.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, AuthDesign.horizontalPadding)
                    .padding(.bottom, 32)

                    // 登録ボタン
                    Button {
                        if canSubmit {
                            showValidationError = false
                            flowState.authStatus = .logIn
                            print("[Navigation] signUp -> logIn")
                        } else {
                            showValidationError = true
                        }
                    } label: {
                        Text("アカウントを登録する")
                            .font(AuthDesign.buttonFont)
                            .foregroundStyle(canSubmit ? AuthDesign.accent : AuthDesign.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: AuthDesign.buttonHeight)
                            .background(
                                canSubmit ? AuthDesign.accentFill : AuthDesign.secondaryFill,
                                in: RoundedRectangle(cornerRadius: AuthDesign.cornerRadius)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AuthDesign.cornerRadius)
                                    .strokeBorder(
                                        canSubmit ? AuthDesign.accent.opacity(0.45) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AuthDesign.horizontalPadding)
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - 共通入力フィールド

    @ViewBuilder
    private func authField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(AuthDesign.accent.opacity(0.7))
                .frame(width: 20)

            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(AuthDesign.textPrimary)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(AuthDesign.textPrimary)
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
            }
        }
        .padding(14)
        .background(AuthDesign.secondaryFill,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AuthDesign.textSecondary.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview {
    SignUpView(flowState: AppFlowState())
}
