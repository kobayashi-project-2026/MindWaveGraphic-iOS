// MainTabView.swift
// App

import SwiftUI

struct MainTabView: View {

    // MARK: - レイアウト定数
    static let missionBarHeight: CGFloat       = 60
    static let missionBarBottomPad: CGFloat    = 18
    static let missionBarGap: CGFloat          = 14
    static let missionBarReservedHeight: CGFloat = 92  // height + bottomPad + gap

    // MARK: - 状態

    @StateObject private var viewModel    = MindWaveViewModel()
    @StateObject private var historyStore = GuideHistoryStore()
    @State       private var selectedTab  = Int(ProcessInfo.processInfo.environment["INITIAL_TAB"] ?? "0") ?? 0
    @EnvironmentObject private var flowState: AppFlowState

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: $selectedTab)
                    .tag(0)
                    .toolbar(.hidden, for: .tabBar)
                GuideView(selectedTab: $selectedTab)
                    .tag(1)
                    .toolbar(.hidden, for: .tabBar)
                HistoryView()
                    .tag(2)
                    .toolbar(.hidden, for: .tabBar)
            }
            .safeAreaInset(edge: .bottom) {
                // HomeView (tab 0) は下部コックピットパネルが自前でパディングを持つため0にする
                Color.clear
                    .frame(height: selectedTab == 0 ? 0 : MainTabView.missionBarReservedHeight)
                    .allowsHitTesting(false)
            }

            // HomeView (tab 0) ではmissionBarを非表示にする
            // HomeViewのCockpitNavLeverが代わりにナビゲーションを担当する
            if selectedTab != 0 {
                missionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .environmentObject(viewModel)
        .environmentObject(historyStore)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.measurementContext = flowState.measurementContext
        }
        .onChange(of: flowState.measurementContext) { _, newCtx in
            viewModel.measurementContext = newCtx
        }
        .onChange(of: selectedTab) { _, newValue in
            print("[UI][Tab] selected index=\(newValue)")
        }
    }

    // MARK: - Accent color (matches HomeView)

    private var scoreIntensity: Double {
        min(max(viewModel.graphicInput.score / 100.0, 0), 1)
    }

    private var accentColor: Color {
        let t = scoreIntensity
        if t < 0.35 { return Color(hue: 0.620, saturation: 0.92, brightness: 0.92) }
        if t < 0.62 {
            let p = (t - 0.35) / 0.27
            return Color(hue: 0.620 - p * 0.455, saturation: 0.92, brightness: 0.98)
        }
        let p = (t - 0.62) / 0.38
        return Color(hue: max(0, 0.165 - p * 0.165), saturation: 0.96, brightness: 1.0)
    }

    // MARK: - Cockpit navigation panel (same lever as HomeView)

    private var missionBar: some View {
        let ac = accentColor
        let si = scoreIntensity

        return ZStack {
            // ベース金属パネル
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.045, green: 0.075, blue: 0.18),
                        Color(red: 0.025, green: 0.042, blue: 0.10),
                        Color(red: 0.010, green: 0.018, blue: 0.055)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))

            // 上端ハイライトリップ
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.065), .clear],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.14)
                ))

            // アクセントボーダー
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(ac.opacity(0.36), lineWidth: 0.8)
                .animation(.easeInOut(duration: 1.0), value: si)

            // ALERT: 外周赤グロー
            if si > 0.58 {
                let t = min(1.0, (si - 0.58) / 0.42)
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(red: 0.96, green: 0.05, blue: 0.05).opacity(t * 0.62), lineWidth: 0.9)
                    .animation(.easeInOut(duration: 0.9), value: si)
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(red: 1.0, green: 0.04, blue: 0.04).opacity(t * 0.32), lineWidth: 2.5)
                    .blur(radius: 4)
                    .animation(.easeInOut(duration: 0.9), value: si)
            }

            VStack(spacing: 0) {
                // パネルリップライン（HomeViewの panelTopRip と同じ役割）
                Canvas { ctx, size in
                    let w = size.width
                    var main = Path()
                    main.move(to: CGPoint(x: w * 0.07, y: size.height - 1.0))
                    main.addLine(to: CGPoint(x: w * 0.93, y: size.height - 1.0))
                    ctx.stroke(main, with: .color(ac.opacity(0.60)), lineWidth: 1.2)
                    ctx.stroke(main, with: .color(ac.opacity(0.14)), lineWidth: 7)
                    for xf in [0.07, 0.35, 0.65, 0.93] as [Double] {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: w*xf - 2.2, y: size.height - 3.2, width: 4.4, height: 4.4)),
                            with: .color(ac.opacity(xf == 0.07 || xf == 0.93 ? 0.58 : 0.32))
                        )
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: w*xf - 1.0, y: size.height - 2.0, width: 2.2, height: 2.2)),
                            with: .color(Color.black.opacity(0.55))
                        )
                    }
                }
                .frame(height: 12)
                .animation(.easeInOut(duration: 1.0), value: si)

                // Home / 整える / 履歴 のレバー（HomeView と同一コンポーネント）
                CockpitLeverNav(selectedTab: $selectedTab, accentColor: ac)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
            }
        }
        .frame(height: 60)
        .shadow(color: ac.opacity(0.10), radius: 10, x: 0, y: -2)
        .shadow(color: .black.opacity(0.60), radius: 20, x: 0, y: 10)
    }
}

#Preview {
    MainTabView()
}
