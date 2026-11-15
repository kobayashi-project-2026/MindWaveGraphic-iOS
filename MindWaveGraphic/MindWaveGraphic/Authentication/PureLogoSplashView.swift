
// PureLogoSplashView.swift
// Authentication
//
// アプリ起動直後に表示されるロゴ画面。
// 約1.5秒後に自動的にAccountGuidanceViewへ遷移する。

import SwiftUI

struct PureLogoSplashView: View {
    var flowState: AppFlowState

    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 宇宙星空背景
            LaunchStarfieldBG()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // アプリ名ロゴ（動画通りアイコンなしのクリーンなタイポグラフィ）
                VStack(spacing: 12) {
                    Text("MIND WAVE")
                        .font(.system(size: 38, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .tracking(8)

                    Text("GRAPHIC")
                        .font(.system(size: 14, weight: .light, design: .monospaced))
                        .foregroundStyle(AuthDesign.accent)
                        .tracking(10)
                }

                Spacer()

                // 下部ローディングドット
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(AuthDesign.accent.opacity(pulse ? 0.85 : 0.25))
                            .frame(width: 5, height: 5)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.2),
                                value: pulse
                            )
                    }
                }
                .padding(.bottom, 56)
            }
        }
        .onAppear { pulse = true }
        .task {
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
