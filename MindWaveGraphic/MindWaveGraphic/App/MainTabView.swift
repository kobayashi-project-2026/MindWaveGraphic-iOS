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

    // 計測ViewModelと履歴ストアは AppRootContainerView が所有する。
    // ログアウト→再ログインや状況選択でこのViewが作り直されても、計測状態・履歴を失わないため。
    @EnvironmentObject private var viewModel: MindWaveViewModel
    @EnvironmentObject private var historyStore: GuideHistoryStore
    @EnvironmentObject private var flowState: AppFlowState
    // メインアプリ内の画面遷移の唯一の情報源（タブ・モーダル）
    @EnvironmentObject private var navManager: AppNavigationManager

    /// 既存Viewが参照する Int 型のタブ番号（navManager から導出。独自の状態は持たない）
    private var selectedTab: Int { navManager.selectedTab.rawValue }

    /// HomeView / GuideView / CockpitLeverNav に渡す Binding。書き込みは navManager へ委譲する。
    private var selectedTabBinding: Binding<Int> {
        Binding(
            get: { navManager.selectedTab.rawValue },
            set: { navManager.selectTab(index: $0) }
        )
    }

    // タブ切替フラッシュ
    @State private var transitionOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: selectedTabBinding) {
                HomeView(selectedTab: selectedTabBinding)
                    .tag(0)
                    .toolbar(.hidden, for: .tabBar)
                GuideView(selectedTab: selectedTabBinding)
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

            // コックピットサイドエッジHUD（整える/履歴タブのみ）
            // 宇宙船の側壁がある感覚を演出する
            if selectedTab != 0 {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [accentColor.opacity(0.12), accentColor.opacity(0.04), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 16)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, accentColor.opacity(0.04), accentColor.opacity(0.12)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 16)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.30), value: selectedTab)
            }

            // タブ切替フラッシュ（レバー操作の "スキャン確認" 感）
            Color(hue: 0.62, saturation: 0.60, brightness: 0.90)
                .opacity(transitionOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // HomeView (tab 0) ではmissionBarを非表示にする
            // HomeViewのCockpitNavLeverが代わりにナビゲーションを担当する
            if selectedTab != 0 {
                missionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .withGlobalMenuBar()
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.measurementContext = flowState.measurementContext
            #if DEBUG
            // シミュレーター検証用（INITIAL_TAB と同様）: INITIAL_SCREEN=<AppScreen の case 名> で起動直後に遷移する
            if let name = ProcessInfo.processInfo.environment["INITIAL_SCREEN"],
               let screen = AppScreen.allCases.first(where: { "\($0)" == name }) {
                navManager.navigate(to: screen)
            }
            #endif
        }
        .onChange(of: flowState.measurementContext) { _, newCtx in
            viewModel.measurementContext = newCtx
        }
        .onChange(of: navManager.selectedTab) { old, newValue in
            MindWaveDebugLogger.log(.navigation, "tab visible index=\(newValue.rawValue)")
            guard old != newValue, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.07)) {
                transitionOpacity = 0.07
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.easeOut(duration: 0.24)) {
                    transitionOpacity = 0
                }
            }
        }
        // 共通メニューから開くモーダル。表示状態は navManager.activeModal のみで管理する
        .sheet(item: $navManager.activeModal) { modal in
            AppModalDestinationView(modal: modal)
                .environmentObject(viewModel)
                .environmentObject(historyStore)
                .environmentObject(flowState)
                .environmentObject(navManager)
        }
        // タイトルへ戻る＝ログアウト。計測中の表示がリセットされるため確認する
        .confirmationDialog(
            "タイトル画面へ戻りますか？",
            isPresented: $navManager.isTitleReturnConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("ログアウトしてタイトルへ戻る", role: .destructive) {
                returnToTitle()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ライブ計測は停止します。保存済みの履歴は削除されません。")
        }
    }

    /// タイトル（認証フロー先頭）へ戻る。履歴は保持し、ライブ計測だけ停止する。
    private func returnToTitle() {
        if viewModel.isLiveMonitoring {
            viewModel.stopLiveMonitoring()
        }
        navManager.resetForSignOut()
        flowState.returnToSplash()
        MindWaveDebugLogger.log(.navigation, "returned to title (sign-out)")
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
                CockpitLeverNav(selectedTab: selectedTabBinding, accentColor: ac)
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
        .environmentObject(AppFlowState())
        .environmentObject(AppNavigationManager())
        .environmentObject(MindWaveViewModel())
        .environmentObject(GuideHistoryStore())
}
