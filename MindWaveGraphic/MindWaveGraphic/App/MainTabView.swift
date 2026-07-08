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
    @State       private var selectedTab  = 0
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

    // MARK: - ミッションバー（洗練されたタブバー）

    private let items: [(label: String, icon: String, activeIcon: String)] = [
        ("ホーム",   "waveform.path.ecg",  "waveform.path.ecg"),
        ("整える",   "wind",               "wind"),
        ("履歴",     "clock",              "clock.fill"),
    ]

    private let tabIdentifiers = ["tab_home", "tab_guide", "tab_history"]

    private var missionBar: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { idx in
                let active = selectedTab == idx
                Button {
                    selectedTab = idx
                } label: {
                    VStack(spacing: 3) {
                        // アイコン（アクティブ時は発光）
                        Image(systemName: active ? items[idx].activeIcon : items[idx].icon)
                            .font(.system(size: 18, weight: active ? .semibold : .light))
                            .foregroundStyle(active ? Color.cyan : Color.white.opacity(0.35))
                            .shadow(color: active ? Color.cyan.opacity(0.75) : .clear, radius: 7)

                        // 選択インジケーター（ライン＋ドット）
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(active ? Color.cyan : Color.clear)
                                .frame(width: 14, height: 1.5)
                            if active {
                                Circle()
                                    .fill(Color.cyan)
                                    .frame(width: 2.5, height: 2.5)
                                    .shadow(color: Color.cyan, radius: 3)
                            } else {
                                Color.clear.frame(width: 5.5, height: 2.5)
                            }
                        }
                        .frame(height: 3)

                        Text(items[idx].label)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(active ? Color.cyan.opacity(0.85) : Color.white.opacity(0.26))
                            .tracking(0.3)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.20), value: active)
                .accessibilityLabel(items[idx].label)
                .accessibilityIdentifier(tabIdentifiers[idx])
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(height: 60)
        .background(
            ZStack {
                // ベース素材
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                // 深い紺グラデーション
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.06, blue: 0.18).opacity(0.90),
                                Color(red: 0.02, green: 0.03, blue: 0.10).opacity(0.92)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                // 上端シアンエッジライン（パネルとの一体化）
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.50), Color.cyan.opacity(0.10)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 1.0)
                    .blur(radius: 0.5)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // 外枠ライン
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.25), Color.white.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )

                // 左右端メカニカルアクセント
                HStack {
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.cyan.opacity(0.35))
                            .frame(width: 6, height: 1.5)
                        Spacer()
                    }
                    .frame(width: 16)
                    Spacer()
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.cyan.opacity(0.35))
                            .frame(width: 6, height: 1.5)
                        Spacer()
                    }
                    .frame(width: 16)
                }
            }
            .shadow(color: Color.cyan.opacity(0.10), radius: 12, x: 0, y: -3)
            .shadow(color: .black.opacity(0.65), radius: 24, x: 0, y: 12)
        )
    }
}

#Preview {
    MainTabView()
}
