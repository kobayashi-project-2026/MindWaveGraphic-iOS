//
//  AccountView.swift
//  MindWaveGraphic
//
//  アカウント表示・ログイン入口の UIプロトタイプ。
//  本物のサーバー認証・Sign in with Apple はまだ接続していない。
//  ログイン成功を偽装せず、パスワードを保存しない。
//  次フェーズで認証基盤を接続する場合の変更点は LoginPrototypeView を参照。
//

import SwiftUI

/// アカウントシート。SettingsView・Home の Profile ボタンから呼ばれる。
/// 現時点ではゲスト表示と LoginPrototypeView への入口だけを提供する。
/// 本物の認証は未実装。ログイン状態を偽装しない。
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("localDisplayName") private var localDisplayName = ""
    @State private var showLoginSheet = false
    @State private var editingName = ""
    @State private var isEditingName = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // プロフィールアイコン
                    ZStack {
                        Circle()
                            .fill(MindWaveTheme.accent.opacity(0.15))
                            .frame(width: 80, height: 80)
                        if localDisplayName.isEmpty {
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(MindWaveTheme.accent.opacity(0.7))
                        } else {
                            Text(String(localDisplayName.prefix(1)).uppercased())
                                .font(.system(size: 36, weight: .light, design: .rounded))
                                .foregroundStyle(MindWaveTheme.accent)
                        }
                    }

                    // 表示名・ゲスト状態
                    VStack(spacing: 6) {
                        Text(localDisplayName.isEmpty ? "ゲスト" : localDisplayName)
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(MindWaveTheme.textPrimary)
                        Text("ログインすると複数デバイスでデータを同期できます")
                            .font(.system(size: 12))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                            .multilineTextAlignment(.center)
                    }

                    // 表示名の編集（ローカル保存のみ）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("表示名（ローカル）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MindWaveTheme.textTertiary)
                        HStack {
                            TextField("名前を入力", text: $editingName)
                                .font(.system(size: 15))
                                .foregroundStyle(MindWaveTheme.textPrimary)
                                .onAppear { editingName = localDisplayName }
                            Spacer()
                            Button("保存") {
                                localDisplayName = editingName
                                isEditingName = false
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MindWaveTheme.accent)
                            .disabled(editingName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                    }

                    Divider().background(Color.white.opacity(0.08))

                    // ログイン / Sign in with Apple（プロトタイプ）
                    VStack(spacing: 12) {
                        Button {
                            showLoginSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 13))
                                Text("メールでログイン")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(MindWaveTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)

                        // Sign in with Apple は次フェーズで接続
                        HStack {
                            Image(systemName: "applelogo")
                                .font(.system(size: 13))
                            Text("Sign in with Apple（次フェーズで接続予定）")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
                    }

                    // 注意書き
                    Text("※ 本物の認証基盤は次フェーズで接続します。\n現在はローカルの表示名のみ保存されます。")
                        .font(.system(size: 11))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .background(MindWaveTheme.background.ignoresSafeArea())
            .navigationTitle("アカウント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(MindWaveTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLoginSheet) {
            LoginPrototypeView()
        }
    }
}

#Preview {
    AccountView()
}
