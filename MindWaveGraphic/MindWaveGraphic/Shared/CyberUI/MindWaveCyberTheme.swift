// MindWaveCyberTheme.swift
// Shared/CyberUI
// 共通Cyber UIデザイントークン。既存MindWaveThemeとは別名前空間で共存する。

import SwiftUI

enum MindWaveCyberTheme {

    // MARK: - Colors

    static let background      = Color(red: 0.02, green: 0.02, blue: 0.08)
    static let panelBackground = Color(white: 1, opacity: 0.04)
    static let cyan            = Color(red: 0.25, green: 0.90, blue: 0.95)
    static let emerald         = Color(red: 0.20, green: 0.85, blue: 0.60)
    static let purple          = Color(red: 0.65, green: 0.35, blue: 0.95)
    static let orange          = Color(red: 0.95, green: 0.60, blue: 0.20)
    static let textPrimary     = Color.white
    static let textSecondary   = Color(white: 0.65)
    static let textTertiary    = Color(white: 0.38)
    static let borderColor     = Color(white: 1, opacity: 0.10)
    static let glowColor       = Color(red: 0.25, green: 0.90, blue: 0.95)

    // MARK: - Geometry

    static let cornerRadius: CGFloat    = 16
    static let panelRadius: CGFloat     = 14
    static let standardPadding: CGFloat = 20
    static let gridCellSize: CGFloat    = 44
    static let gridOpacity: Double      = 0.06
}
