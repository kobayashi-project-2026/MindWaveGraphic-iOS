// NavigationTests.swift
// AppNavigationManager の遷移が一方向・双方向で矛盾しないことのテスト

import Foundation

enum NavigationTests {
    typealias T = TestHarness

    static func run() {
        T.suite("Navigation")

        T.test("全画面は タブ / モーダル / タイトル のいずれか1つにだけ対応する") {
            for screen in AppScreen.allCases {
                let kinds = [screen.mainTab != nil, screen.modal != nil, screen == .title].filter { $0 }.count
                T.expectEqual(kinds, 1, "\(screen)")
            }
        }

        T.test("タブ⇄画面・モーダル⇄画面の対応が可逆") {
            for tab in MainTab.allCases { T.expectEqual(tab.screen.mainTab, tab) }
            for screen in AppScreen.allCases {
                if let modal = screen.modal { T.expectEqual(modal.screen, screen) }
            }
            // 既存 selectedTab(Int) の値を変えていないこと
            T.expectEqual(MainTab.home.rawValue, 0)
            T.expectEqual(MainTab.guide.rawValue, 1)
            T.expectEqual(MainTab.history.rawValue, 2)
        }

        T.test("メニュー→タブ遷移: currentScreen と selectedTab が一致") {
            let nav = AppNavigationManager(initialTab: .home)
            T.expectEqual(nav.currentScreen, .tensionGraphic)
            nav.navigate(to: .improvement)
            T.expectEqual(nav.selectedTab, .guide)
            T.expectEqual(nav.currentScreen, .improvement)
            nav.navigate(to: .pastLogs)
            T.expectEqual(nav.selectedTab, .history)
            T.expect(nav.activeModal == nil, "no modal")
        }

        T.test("タブ操作（Binding 経由）→メニュー表示位置が追従（逆方向）") {
            let nav = AppNavigationManager(initialTab: .home)
            nav.selectTab(index: 2)   // GuideFlowView の保存後遷移と同じ操作
            T.expectEqual(nav.currentScreen, .pastLogs)
            nav.selectTab(index: 1)   // CockpitLeverNav の「整える」
            T.expectEqual(nav.currentScreen, .improvement)
            nav.selectTab(index: 7)   // 未知の値は無視
            T.expectEqual(nav.selectedTab, .guide)
        }

        T.test("モーダルはタブを変えず、閉じると元のタブへ戻る") {
            let nav = AppNavigationManager(initialTab: .history)
            nav.navigate(to: .settings)
            T.expectEqual(nav.activeModal, .settings)
            T.expectEqual(nav.currentScreen, .settings)
            T.expectEqual(nav.selectedTab, .history)
            nav.dismissModal()
            T.expectEqual(nav.currentScreen, .pastLogs)
            nav.navigate(to: .dialogue)
            T.expectEqual(nav.activeModal, .contextCalibration)
            nav.navigate(to: .confirmation)
            T.expectEqual(nav.activeModal, .latestRecordConfirmation)
            nav.navigate(to: .feedback)
            T.expectEqual(nav.activeModal, .latestRecordFeedback)
        }

        T.test("モーダル表示中にタブ画面を選ぶとモーダルが閉じる（記録なし画面の『整えるへ移動』）") {
            let nav = AppNavigationManager(initialTab: .home)
            nav.navigate(to: .confirmation)
            nav.navigate(to: .improvement)
            T.expect(nav.activeModal == nil, "modal closed")
            T.expectEqual(nav.currentScreen, .improvement)
        }

        T.test("タイトルへ戻るは確認を挟み、即座には遷移しない") {
            let nav = AppNavigationManager(initialTab: .guide)
            nav.navigate(to: .title)
            T.expect(nav.isTitleReturnConfirmationPresented, "confirmation shown")
            T.expectEqual(nav.selectedTab, .guide)
            nav.resetForSignOut()
            T.expect(!nav.isTitleReturnConfirmationPresented, "reset flag")
            T.expectEqual(nav.selectedTab, .home)
            T.expect(nav.activeModal == nil, "no modal")
        }

        T.test("記録が必要な画面の判定") {
            T.expect(AppScreen.confirmation.requiresSessionRecord, "confirmation")
            T.expect(AppScreen.feedback.requiresSessionRecord, "feedback")
            T.expect(!AppScreen.settings.requiresSessionRecord, "settings")
        }
    }
}
