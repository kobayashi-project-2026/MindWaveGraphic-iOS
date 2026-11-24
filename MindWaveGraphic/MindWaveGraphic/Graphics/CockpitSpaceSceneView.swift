// CockpitSpaceSceneView.swift
// MindWaveGraphic

import SwiftUI
import UIKit

// MARK: - 新コックピット＆宇宙シーン統合ビュー
struct CockpitSpaceSceneView: View {
    /// アプリ側のリアルタイム緊張・ストレススコア (0〜100)
    let score: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. 宇宙の背景
                Color.black
                    .ignoresSafeArea()

                // 2. 3D星空・隕石（inseki アセットを使用）
                CustomStarfieldView(score: score)

                // 3. スコア70以上の雷エフェクト
                CustomLightningView(score: score)
            }
        }
    }
}
    

// MARK: - 3D星空・隕石
struct CustomStarfieldView: View {
    let score: Double

    private var intensity: Double { score / 100.0 }
    private var speed: Double { 0.2 + intensity * 2.5 }

    private var bigStarCount: Int {
        if score < 33 {
            return 0
        } else if score < 70 {
            return 10
        } else {
            return 22
        }
    }

    /// 白背景をピクセル単位で透明化した隕石 UIImage を生成
    private static let transparentMeteorUIImage: UIImage? = {
        guard let src = UIImage(named: "inseki")?.cgImage else { return nil }
        let width = src.width
        let height = src.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)

        guard let ctx = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(src, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 白に近いピクセル（R, G, B すべて 235 以上）を透明化
        for i in stride(from: 0, to: rawData.count, by: 4) {
            let r = rawData[i]
            let g = rawData[i + 1]
            let b = rawData[i + 2]
            if r > 235 && g > 235 && b > 235 {
                rawData[i] = 0
                rawData[i + 1] = 0
                rawData[i + 2] = 0
                rawData[i + 3] = 0
            }
        }

        guard let outCG = ctx.makeImage() else { return nil }
        return UIImage(cgImage: outCG)
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let inseki: GraphicsContext.ResolvedImage? = {
                    if let uiImg = Self.transparentMeteorUIImage {
                        return context.resolve(Image(uiImage: uiImg))
                    } else if UIImage(named: "inseki") != nil {
                        return context.resolve(Image("inseki"))
                    }
                    return nil
                }()

                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerX = size.width / 2
                let centerY = size.height / 2

                // 通常の星
                for i in 0..<800 {
                    let seed = Double(i)
                    let x3d = CGFloat(sin(seed * 12.9898) * 300)
                    let y3d = CGFloat(cos(seed * 78.233) * 300)

                    var z = 1000 - (time * 200 * speed + seed * 17).truncatingRemainder(dividingBy: 1000)
                    if z < 1 { z = 1 }

                    let perspective = CGFloat(400 / z)
                    let x = centerX + x3d * perspective
                    let y = centerY + y3d * perspective
                    let starSize = min(max(1, perspective * 4), 4)

                    let rect = CGRect(x: x, y: y, width: starSize, height: starSize)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))

                    // 星の軌跡
                    if intensity > 0.3 {
                        let trail = starSize * CGFloat(intensity) * 10
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(
                            to: CGPoint(
                                x: centerX + x3d * CGFloat(400 / (z + Double(trail))),
                                y: centerY + y3d * CGFloat(400 / (z + Double(trail)))
                            )
                        )
                        context.stroke(
                            path,
                            with: .color(.white.opacity(0.8)),
                            lineWidth: starSize * 0.5
                        )
                    }
                }

                // 隕石（白背景を除去済みの inseki 画像）
                for i in 0..<bigStarCount {
                    let seed = Double(i * 137 + 1000)
                    let x3d = CGFloat(sin(seed * 15.23) * 350)
                    let y3d = CGFloat(cos(seed * 92.11) * 350)

                    var z = 1200 - (time * (250 + intensity * 400) + seed * 50).truncatingRemainder(dividingBy: 1200)
                    if z < 1 { z = 1 }

                    let perspective = CGFloat(500 / z)
                    let x = centerX + x3d * perspective
                    let y = centerY + y3d * perspective
                    let meteorSize = min(max(10, perspective * 65), 76)
                    let correctedAngle = Double.pi / 6

                    if let inseki {
                        context.drawLayer { layer in
                            layer.translateBy(x: x + meteorSize / 2, y: y + meteorSize / 2)
                            if x > centerX {
                                layer.scaleBy(x: -1, y: 1)
                            }
                            layer.rotate(by: .radians(correctedAngle))
                            layer.draw(
                                inseki,
                                in: CGRect(
                                    x: -meteorSize / 2,
                                    y: -meteorSize / 2,
                                    width: meteorSize,
                                    height: meteorSize
                                )
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 雷エフェクト（スコア70以上）
struct CustomLightningView: View {
    let score: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard score >= 70 else { return }

                let time = timeline.date.timeIntervalSinceReferenceDate
                let count: Int = score < 80 ? 32 : (score < 90 ? 24 : 20)
                let interval: Double = score < 80 ? 1.2 : (score < 90 ? 1.0 : 0.75)
                let duration: Double = score < 80 ? 0.28 : (score < 90 ? 0.30 : 0.35)
                let lineWidth: CGFloat = score < 80 ? 1.5 : (score < 90 ? 2.5 : 4.0)
                let lightningColor: Color = score < 80 ? .cyan : (score < 90 ? .purple : .white)

                for i in 0..<count {
                    let seed = Double(i)
                    let phase = (time + seed * 0.173).truncatingRemainder(dividingBy: interval)
                    guard phase < duration else { continue }

                    let flash = sin(Double.pi * phase / duration)
                    let opacity = 0.35 + flash * 0.65

                    let positionType = i % 3
                    let startX: CGFloat = positionType == 0 ? size.width * 0.03 : (positionType == 1 ? size.width * 0.97 : size.width * 0.5)
                    let startY = CGFloat((seed * 83.7).truncatingRemainder(dividingBy: 100)) / 100 * size.height
                    let length: CGFloat = score < 80 ? size.height * 0.15 : (score < 90 ? size.height * 0.30 : size.height * 0.48)
                    let endY = min(startY + length, size.height)
                    let direction: CGFloat = positionType == 0 ? 1 : (positionType == 1 ? -1 : (i % 2 == 0 ? 1 : -1))
                    let endX = startX + direction * (positionType == 2 ? size.width * 0.12 : size.width * 0.18)
                    let currentWidth: CGFloat = positionType == 2 ? lineWidth * 1.3 : lineWidth

                    var path = Path()
                    path.move(to: CGPoint(x: startX, y: startY))
                    if i % 4 == 0 {
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    } else {
                        let p1 = CGPoint(x: startX + direction * 15, y: startY + length * 0.25)
                        let p2 = CGPoint(x: startX - direction * 5, y: startY + length * 0.50)
                        let p3 = CGPoint(x: startX + direction * 25, y: startY + length * 0.75)
                        path.addLine(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    }

                    context.stroke(path, with: .color(lightningColor.opacity(opacity * 0.25)), lineWidth: currentWidth * 5)
                    context.stroke(path, with: .color(lightningColor.opacity(opacity)), lineWidth: currentWidth)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
