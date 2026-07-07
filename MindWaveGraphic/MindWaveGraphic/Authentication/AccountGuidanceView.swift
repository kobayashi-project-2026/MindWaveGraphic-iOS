// AccountGuidanceView.swift
// Authentication
//
// アプリ起動直後のファーストビュー。
// Mind Wave Graphicの世界観（宇宙・コックピット・呼吸）を即伝える。

import SwiftUI

// MARK: - AccountGuidanceView

struct AccountGuidanceView: View {

    var flowState: AppFlowState

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
                    .frame(minHeight: 60)

                // タイトルブロック
                VStack(spacing: 8) {
                    // ステータスライン
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(AuthDesign.accent)
                            .frame(width: 20, height: 1)
                        Text("BIOMETRIC NAVIGATION SYSTEM")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(AuthDesign.accent.opacity(0.7))
                            .tracking(1.5)
                        Rectangle()
                            .fill(AuthDesign.accent)
                            .frame(width: 20, height: 1)
                    }
                    .padding(.bottom, 16)

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
                VStack(spacing: 6) {
                    Text("今の揺らぎを、航路に変える")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .tracking(1)

                    HStack(spacing: 12) {
                        Text("● HealthKit")
                        Text("● Apple Watch")
                        Text("● HRV")
                    }
                    .font(.system(size: 10, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.28))
                }
                .padding(.top, 28)
                .padding(.bottom, 52)

                // ボタン群
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
    }
}

// MARK: - LaunchHUDFrame

/// コックピット風HUDフレーム装飾。四隅と上下バー。
private struct LaunchHUDFrame: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Canvas { ctx, size in
                let accent = GraphicsContext.Shading.color(
                    Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.25)
                )
                let lineW: CGFloat = 0.7

                // 上部水平ライン
                var topLine = Path()
                topLine.move(to:    CGPoint(x: w * 0.08, y: 44))
                topLine.addLine(to: CGPoint(x: w * 0.92, y: 44))
                ctx.stroke(topLine, with: accent, lineWidth: lineW)

                // 下部水平ライン
                var botLine = Path()
                botLine.move(to:    CGPoint(x: w * 0.08, y: h - 44))
                botLine.addLine(to: CGPoint(x: w * 0.92, y: h - 44))
                ctx.stroke(botLine, with: accent, lineWidth: lineW)

                // 四隅ブラケット（左上）
                func corner(_ ox: CGFloat, _ oy: CGFloat, _ sx: CGFloat, _ sy: CGFloat) {
                    var p = Path()
                    p.move(to:    CGPoint(x: ox,          y: oy + 16 * sy))
                    p.addLine(to: CGPoint(x: ox,          y: oy))
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

// MARK: - Preview

#Preview {
    AccountGuidanceView(flowState: AppFlowState())
}
