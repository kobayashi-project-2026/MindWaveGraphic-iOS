// MindWaveDesignSystem.swift
// Shared
//
// 認証前画面で使用するデザイン定数。
// 既存のMindWaveTheme（accent, textPrimary等）と衝突しないよう、
// AuthUI専用の定数のみをここで定義する。
// 既存MindWaveThemeに存在しないAuthUI専用の定数のみここで定義する。

import SwiftUI

// MARK: - 認証UI専用デザイン定数

enum AuthDesign {

    // MARK: - Colors

    /// 認証画面背景：ほぼ真黒（既存MindWaveTheme.backgroundに準拠）
    static let background = Color(red: 0.04, green: 0.04, blue: 0.10)

    /// 認証画面アクセント：既存MindWaveTheme.accentと同じシアン系
    /// ※ 既存accentをそのまま利用（重複定義しない）
    static var accent: Color { MindWaveTheme.accent }

    /// ボタン背景に使うシアン半透明
    static let accentFill   = Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.15)

    /// ゲストボタン用：アクセントより暗いグレーシアン
    static let secondaryFill = Color.white.opacity(0.08)

    /// テキスト：既存MindWaveTheme.textPrimaryに準拠（白）
    static var textPrimary: Color { MindWaveTheme.textPrimary }

    /// テキスト：既存MindWaveTheme.textSecondaryに準拠（グレー）
    static var textSecondary: Color { MindWaveTheme.textSecondary }

    /// グリッドライン色
    static let gridLine = Color.white.opacity(0.06)

    // MARK: - Typography

    /// ロゴ用フォント
    static let logoFont = Font.system(size: 36, weight: .ultraLight, design: .monospaced)

    /// 見出しフォント
    static let headingFont = Font.system(size: 22, weight: .light, design: .default)

    /// ボタンフォント
    static let buttonFont = Font.system(size: 15, weight: .medium)

    /// キャプションフォント
    static let captionFont = Font.system(size: 11, weight: .light)

    // MARK: - Dimensions

    /// 標準ボタン高さ
    static let buttonHeight: CGFloat = 52

    /// 標準角丸
    static let cornerRadius: CGFloat = 14

    /// 標準横パディング
    static let horizontalPadding: CGFloat = 28
}
