// PureLogoSplashView.swift
// Authentication
//
// アプリ起動直後に表示されるロゴ画面（UI最終版）。
// 約1.5秒後に自動的にAccountGuidanceViewへ遷移する。

import SwiftUI

struct PureLogoSplashView: View {
    var flowState: AppFlowState

    @State private var pulse: Bool = false
    @State private var logoGlow: Bool = false

    var body: some View {
        ZStack {
            // 宇宙グラデーション背景（タイトル画面と統一）
            LinearGradient(
                colors: [
                    Color(splashHex: "03051C"),
                    Color(splashHex: "10134C"),
                    Color(splashHex: "292A80"),
                    Color(splashHex: "050820")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 星雲グロー
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 240)
                .blur(radius: 90)
                .offset(x: -110, y: 150)

            Circle()
                .fill(Color.purple.opacity(0.35))
                .frame(width: 220)
                .blur(radius: 85)
                .offset(x: 120, y: -150)

            // 既存の星空アニメーション
            LaunchStarfieldBG()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // アプリ名ロゴ（グラデーション＋ネオングロー）
                VStack(spacing: 10) {
                    ZStack {
                        Text("MindWaveGraphic")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .tracking(-1.2)
                            .foregroundColor(.cyan)
                            .blur(radius: logoGlow ? 22 : 8)
                            .opacity(0.8)

                        Text("MindWaveGraphic")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .tracking(-1.2)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        .white,
                                        Color(splashHex: "A8F5FF"),
                                        Color(splashHex: "B4A4FF"),
                                        Color(splashHex: "F0D9FF")
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .cyan.opacity(0.8), radius: 12)
                    }
                    .padding(.horizontal, 16)

                    Text("YOUR MIND, YOUR UNIVERSE")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(4)
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()

                // 下部ローディングドット
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.cyan.opacity(pulse ? 0.9 : 0.25))
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
        .onAppear {
            pulse = true
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                logoGlow = true
            }
        }
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

private extension Color {
    init(splashHex: String) {
        let hex = splashHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    PureLogoSplashView(flowState: AppFlowState())
}
