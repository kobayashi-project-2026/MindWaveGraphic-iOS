// CyberGridShape.swift
// Shared
//
// 認証前画面の背景に使用するグリッドパターン。
// SwiftUI の Shape プロトコルを実装し、background モディファイアで使用する。
// 既存のStarfieldGraphicViewとは独立したコンポーネント。

import SwiftUI

// MARK: - CyberGridShape

/// 等間隔のグリッドラインを描画するShape。
/// 認証前画面（ロゴ〜ログイン）の背景として使用する。
struct CyberGridShape: Shape {

    /// グリッドセルの1辺のサイズ（ポイント）
    var cellSize: CGFloat = 40

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 縦線
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += cellSize
        }

        // 横線
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += cellSize
        }

        return path
    }
}

// MARK: - CyberGridBackground

/// CyberGridShapeをViewとして使いやすくしたラッパー。
/// 背景グラデーション + グリッドラインを重ねて表示する。
struct CyberGridBackground: View {

    var body: some View {
        ZStack {
            // 基本背景
            AuthDesign.background
                .ignoresSafeArea()

            // グリッドオーバーレイ
            CyberGridShape(cellSize: 44)
                .stroke(AuthDesign.gridLine, lineWidth: 0.5)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    CyberGridBackground()
        .preferredColorScheme(.dark)
}
