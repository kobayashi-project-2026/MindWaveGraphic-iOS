// AccountGuidanceView.swift
// Authentication
//
// アプリ起動直後のタイトル画面（UI最終版）。

import SwiftUI

struct AccountGuidanceView: View {
    var flowState: AppFlowState

    // 既存の本物のもこりん用ポーズ状態
    @State private var mokorinPose = MokorinPose(emotion: .happy, action: .wave, actionID: 1)

    // アニメーション状態
    @State private var floating = false
    @State private var orbit = false
    @State private var pulse = false
    @State private var starsOn = false
    @State private var logoGlow = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 宇宙グラデーション背景
                LinearGradient(
                    colors: [
                        Color(titleHex: "03051C"),
                        Color(titleHex: "10134C"),
                        Color(titleHex: "292A80"),
                        Color(titleHex: "050820")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // 星雲グロー
                Circle()
                    .fill(Color.blue.opacity(0.35))
                    .frame(width: 260)
                    .blur(radius: 100)
                    .offset(x: -130, y: 180)

                Circle()
                    .fill(Color.purple.opacity(0.4))
                    .frame(width: 230)
                    .blur(radius: 90)
                    .offset(x: 140, y: -180)

                // きらめく星空
                ForEach(0..<55, id: \.self) { i in
                    Circle()
                        .fill(.white)
                        .frame(width: i % 4 == 0 ? 3 : 1.5)
                        .opacity((i % 2 == 0) == starsOn ? 0.9 : 0.25)
                        .position(
                            x: geo.size.width * CGFloat(i * 37 % 97) / 100,
                            y: geo.size.height * CGFloat(i * 61 % 97) / 100
                        )
                }

                VStack(spacing: 10) {
                    Spacer()

                    // 心拍波形
                    TitleHeartbeatShape()
                        .stroke(
                            LinearGradient(
                                colors: [.cyan, .white, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(
                                lineWidth: 3,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(width: 130, height: 42)
                        .shadow(color: .cyan, radius: 12)
                        .scaleEffect(pulse ? 1.08 : 0.92)
                        .opacity(pulse ? 1 : 0.55)

                    // もこりん（既存の本物 MokorinAvatarView をそのまま使用）
                    ZStack {
                        // 惑星の軌道リング
                        ZStack {
                            Ellipse()
                                .stroke(
                                    LinearGradient(
                                        colors: [.clear, .cyan, .white, .purple, .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 290, height: 65)

                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 9, height: 9)
                                .shadow(color: .cyan, radius: 10)
                                .offset(x: 145)
                        }
                        .rotationEffect(.degrees(orbit ? 15 : -15))
                        .offset(y: 45)

                        MokorinAvatarView(size: 175, pose: mokorinPose)
                            .frame(width: 175, height: 175)
                            .offset(y: floating ? -10 : 10)
                            .shadow(color: .purple.opacity(0.65), radius: 22)
                            .onTapGesture {
                                mokorinPose = MokorinPose(
                                    emotion: .happy,
                                    action: .jump,
                                    actionID: mokorinPose.actionID + 1
                                )
                            }
                    }
                    .frame(height: 195)

                    // タイトルロゴ（MindWaveGraphic）
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
                                        Color(titleHex: "A8F5FF"),
                                        Color(titleHex: "B4A4FF"),
                                        Color(titleHex: "F0D9FF")
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .cyan.opacity(0.8), radius: 12)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)

                    Text("YOUR MIND, YOUR UNIVERSE")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(4)
                        .foregroundColor(.white.opacity(0.65))

                    Text("今の揺らぎを、宇宙に変える")
                        .font(.system(size: 13, weight: .light))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.82))
                        .padding(.top, 2)

                    Spacer()

                    // ステータス表示
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.cyan)
                            .frame(width: 5, height: 5)

                        Text("CONNECTING TO YOUR UNIVERSE")
                            .font(.system(size: 8))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.65))
                    }

                    // ボタン群（既存の画面遷移・機能はそのまま維持）
                    VStack(spacing: 12) {
                        // ゲスト利用（主CTA：状況確認画面へ）
                        Button {
                            flowState.isGuestUser = true
                            flowState.authStatus = .contextCalibration
                            print("[Navigation] guest -> contextCalibration")
                        } label: {
                            HStack(spacing: 12) {
                                Text("はじめる")
                                    .font(.title3)
                                    .bold()

                                Image(systemName: "arrow.right")
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 15)
                            .frame(maxWidth: 270)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(titleHex: "5959FF"),
                                        Color(titleHex: "A659FF")
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: .purple.opacity(0.8), radius: 20)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("launch_primary_start_button")

                        // ログイン（セカンダリ）
                        Button {
                            flowState.authStatus = .topMenu
                            print("[Navigation] accountGuidance -> topMenu")
                        } label: {
                            Text("ログイン / アカウント登録")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.65))
                                .padding(.vertical, 10)
                                .frame(maxWidth: 270)
                                .background(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("launch_login_button")
                    }
                    .padding(.top, 6)

                    // フッター注記
                    Text("医療診断ではありません。数値は参考値です。")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                floating = true
                logoGlow = true
            }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                orbit = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                starsOn = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                mokorinPose = MokorinPose(emotion: .happy, action: .wave, actionID: 2)
            }
        }
    }
}

// MARK: - 心拍波形シェイプ

private struct TitleHeartbeatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let points: [CGPoint] = [
            CGPoint(x: 0.00, y: 0.55),
            CGPoint(x: 0.18, y: 0.55),
            CGPoint(x: 0.27, y: 0.48),
            CGPoint(x: 0.35, y: 0.62),
            CGPoint(x: 0.45, y: 0.10),
            CGPoint(x: 0.55, y: 0.90),
            CGPoint(x: 0.65, y: 0.43),
            CGPoint(x: 0.75, y: 0.55),
            CGPoint(x: 1.00, y: 0.55)
        ]

        let converted = points.map {
            CGPoint(x: rect.width * $0.x, y: rect.height * $0.y)
        }

        path.move(to: converted[0])
        path.addLines(Array(converted.dropFirst()))
        return path
    }
}

private extension Color {
    init(titleHex: String) {
        let hex = titleHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    AccountGuidanceView(flowState: AppFlowState())
}
