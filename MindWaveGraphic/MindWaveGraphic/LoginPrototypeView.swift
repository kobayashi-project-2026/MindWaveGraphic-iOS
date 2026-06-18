//
//  LoginPrototypeView.swift
//  MindWaveGraphic
//
//  ログイン画面の UI プロトタイプ。
//  本物の認証基盤（サーバー・Sign in with Apple 等）はまだ未接続。
//  ログインボタン押下時は成功扱いせず「未接続」メッセージを表示する。
//  パスワードを UserDefaults やその他ローカルストレージに保存しない。
//
//  次フェーズで本物のログインを接続する場合の変更点:
//  1. AuthService（または Firebase Auth 等）をインポートする
//  2. loginAction() 内でサーバー認証を呼び出す
//  3. 成功時に UserDefaults に認証トークン（パスワードではない）を保存する
//  4. AccountView のゲスト表示をログイン済み表示に切り替える
//

import SwiftUI

/// ログイン UI プロトタイプ。認証基盤未接続のため送信しない。
/// パスワードは保存せず、送信ボタン押下時に「未接続」アラートを表示する。
struct LoginPrototypeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showUnavailableAlert = false

    private var isInputValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
        && email.contains("@")
        && password.count >= 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // アイコン
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(MindWaveTheme.accent)
                        .padding(.top, 16)

                    Text("ログイン")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(MindWaveTheme.textPrimary)

                    // 未接続バナー
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text("認証基盤は次フェーズで接続されます。\nこの画面は UI プロトタイプです。")
                            .font(.system(size: 11))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)))

                    // メール入力
                    VStack(alignment: .leading, spacing: 6) {
                        Text("メールアドレス")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                        TextField("example@email.com", text: $email)
                            .font(.system(size: 15))
                            .foregroundStyle(MindWaveTheme.textPrimary)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.06)))
                    }

                    // パスワード入力
                    VStack(alignment: .leading, spacing: 6) {
                        Text("パスワード")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                        SecureField("パスワード", text: $password)
                            .font(.system(size: 15))
                            .foregroundStyle(MindWaveTheme.textPrimary)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.06)))
                        Text("※ パスワードは保存されません")
                            .font(.system(size: 10))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                    }

                    // ログインボタン（送信しない・未接続メッセージを表示）
                    Button {
                        showUnavailableAlert = true
                    } label: {
                        Text("ログイン")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(isInputValid ? .black : MindWaveTheme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isInputValid
                                          ? MindWaveTheme.accent
                                          : MindWaveTheme.accent.opacity(0.25))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isInputValid)
                    .alert("認証基盤に未接続", isPresented: $showUnavailableAlert) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("サーバー認証は次フェーズで接続されます。現在は送信しません。パスワードは保存されていません。")
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
            .background(MindWaveTheme.background.ignoresSafeArea())
            .navigationTitle("ログイン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(MindWaveTheme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    LoginPrototypeView()
}
