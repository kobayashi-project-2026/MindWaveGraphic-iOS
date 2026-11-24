import SwiftUI

// ダッシュボードパネル上端の形状。上部コーナーを斜めカット。
struct CockpitPanelShape: Shape {
    var chamfer: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let c = chamfer
        var p = Path()
        p.move(to: CGPoint(x: 0,     y: c))
        p.addLine(to: CGPoint(x: c,     y: 0))
        p.addLine(to: CGPoint(x: w - c, y: 0))
        p.addLine(to: CGPoint(x: w,     y: c))
        p.addLine(to: CGPoint(x: w,     y: h))
        p.addLine(to: CGPoint(x: 0,     y: h))
        p.closeSubpath()
        return p
    }
}
