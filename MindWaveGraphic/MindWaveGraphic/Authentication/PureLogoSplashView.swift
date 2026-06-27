// PureLogoSplashView.swift
// Authentication
//
// アプリ起動直後に表示されるロゴ画面。
// 約1.5秒後に自動的にAccountGuidanceViewへ遷移する。
// .task モディファイアを使うことで、Viewが消えたとき自動的にキャンセルされる。

import SwiftUI

// MARK: - PureLogoSplashView

/// 起動ロゴ画面。pulseアニメーション後に自動遷移する。
struct PureLogoSplashView: View {

    var flowState: AppFlowState

    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            CyberGridBackground()

            VStack(spacing: 20) {

                Spacer()

                // ロゴマーク
                ZStack {
                    Circle()
                        .stroke(AuthDesign.accent.opacity(0.3), lineWidth: 1)
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulse ? 1.25 : 1.0)
                        .opacity(pulse ? 0 : 0.6)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false),
                                   value: pulse)

                    Circle()
                        .fill(AuthDesign.accent.opacity(0.12))
                        .frame(width: 80, height: 80)

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(AuthDesign.accent)
                }

                // アプリ名
                VStack(spacing: 6) {
                    Text("MIND WAVE")
                        .font(AuthDesign.logoFont)
                        .foregroundStyle(AuthDesign.textPrimary)
                        .tracking(6)

                    Text("GRAPHIC")
                        .font(.system(size: 13, weight: .light, design: .monospaced))
                        .foregroundStyle(AuthDesign.accent)
                        .tracking(8)
                }

                Spacer()

                // ローディングインジケーター
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(AuthDesign.accent.opacity(pulse ? 0.8 : 0.3))
                            .frame(width: 5, height: 5)
                            .animation(.easeInOut(duration: 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(i) * 0.2),
                                       value: pulse)
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear { pulse = true }
        .task {
            // Viewが消えると自動キャンセルされるため、画面破棄後に遷移は起きない
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                flowState.authStatus = .accountGuidance
                print("[Navigation] logoSplash -> accountGuidance")
            }
        }
    }
}

#Preview {
    PureLogoSplashView(flowState: AppFlowState())
}
