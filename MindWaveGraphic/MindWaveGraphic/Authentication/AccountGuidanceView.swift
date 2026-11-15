// AccountGuidanceView.swift
// Authentication
//
// アプリ起動直後のファーストビュー（動画デザイン準拠）。

import SwiftUI

struct AccountGuidanceView: View {
    var flowState: AppFlowState

    @State private var mokorinPose = MokorinPose(emotion: .happy, action: .wave, actionID: 1)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 背景星アニメーション
            LaunchStarfieldBG()
                .ignoresSafeArea()

            // コックピットHUDフレーム
            LaunchHUDFrame()
                .ignoresSafeArea()

            // コンテンツ
            VStack(spacing: 0) {
                Spacer()
                    .frame(minHeight: 36)

                // 上部ステータスライン ＋ 心電図波形アイコン
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(AuthDesign.accent)
                            .frame(width: 20, height: 1)
                        Text("BIOMETRIC NAVIGATION SYSTEM")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(AuthDesign.accent.opacity(0.75))
                            .tracking(1.5)
                        Rectangle()
                            .fill(AuthDesign.accent)
                            .frame(width: 20, height: 1)
                    }

                    // 心電図波形アクセント
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(AuthDesign.accent.opacity(0.35))
                            .frame(width: 48, height: 1)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(AuthDesign.accent.opacity(0.85))
                        Rectangle()
                            .fill(AuthDesign.accent.opacity(0.35))
                            .frame(width: 48, height: 1)
                    }
                }
                .padding(.bottom, 16)

                // もこりんキャラクター
                MokorinAvatarView(size: 155, pose: mokorinPose)
                    .frame(width: 155, height: 155)
                    .padding(.bottom, 12)
                    .onTapGesture {
                        mokorinPose = MokorinPose(
                            emotion: .happy,
                            action: .jump,
                            actionID: mokorinPose.actionID + 1
                        )
                    }

                // タイトルロゴ
                VStack(spacing: 8) {
                    Text("MIND WAVE")
                        .font(.system(size: 38, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .tracking(8)

                    Text("GRAPHIC")
                        .font(.system(size: 15, weight: .light, design: .monospaced))
                        .foregroundStyle(AuthDesign.accent)
                        .tracking(10)
                }

                // キャッチコピー
                VStack(spacing: 8) {
                    Text("今の揺らぎを、宇宙に変える")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .tracking(1)

                    HStack(spacing: 12) {
                        Text("● HealthKit")
                        Text("● Apple Watch")
                        Text("● Real-time Pulse")
                    }
                    .font(.system(size: 10, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.32))
                }
                .padding(.top, 22)
                .padding(.bottom, 38)

                // ボタン群（機能・遷移先は既存のまま維持）
                VStack(spacing: 12) {
                    // ゲスト利用（主CTA）
                    Button {
                        flowState.isGuestUser = true
                        flowState.authStatus  = .contextCalibration
                        print("[Navigation] guest -> contextCalibration")
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 16, weight: .light))
                            Text("計測をはじめる")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: AuthDesign.buttonHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AuthDesign.cornerRadius)
                                .fill(AuthDesign.accent)
                                .shadow(color: AuthDesign.accent.opacity(0.45), radius: 16, y: 4)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("launch_primary_start_button")

                    // ログイン（セカンダリ）
                    Button {
                        flowState.authStatus = .topMenu
                        print("[Navigation] accountGuidance -> topMenu")
                    } label: {
                        Text("ログイン / アカウント登録")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .frame(height: AuthDesign.buttonHeight)
                            .background(
                                RoundedRectangle(cornerRadius: AuthDesign.cornerRadius)
                                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("launch_login_button")
                }
                .padding(.horizontal, AuthDesign.horizontalPadding)

                Spacer()

                // フッター注記
                Text("医療診断ではありません。数値は参考値です。")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.22))
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                mokorinPose = MokorinPose(emotion: .happy, action: .wave, actionID: 2)
            }
        }
    }
}

#Preview {
    AccountGuidanceView(flowState: AppFlowState())
}

// MARK: - LaunchHUDFrame
private struct LaunchHUDFrame: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Canvas { ctx, _ in
                let accent = GraphicsContext.Shading.color(
                    Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.25)
                )
                let lineW: CGFloat = 0.7

                var topLine = Path()
                topLine.move(to:    CGPoint(x: w * 0.08, y: 44))
                topLine.addLine(to: CGPoint(x: w * 0.92, y: 44))
                ctx.stroke(topLine, with: accent, lineWidth: lineW)

                var botLine = Path()
                botLine.move(to:    CGPoint(x: w * 0.08, y: h - 44))
                botLine.addLine(to: CGPoint(x: w * 0.92, y: h - 44))
                ctx.stroke(botLine, with: accent, lineWidth: lineW)

                func corner(_ ox: CGFloat, _ oy: CGFloat, _ sx: CGFloat, _ sy: CGFloat) {
                    var p = Path()
                    p.move(to:    CGPoint(x: ox,           y: oy + 16 * sy))
                    p.addLine(to: CGPoint(x: ox,           y: oy))
                    p.addLine(to: CGPoint(x: ox + 16 * sx, y: oy))
                    ctx.stroke(p, with: accent, lineWidth: 1.2)
                }
                corner(18, 58, 1, 1)
                corner(w - 18, 58, -1, 1)
                corner(18, h - 58, 1, -1)
                corner(w - 18, h - 58, -1, -1)
            }
            .frame(width: w, height: h)
        }
    }
}
