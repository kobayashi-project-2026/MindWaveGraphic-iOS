//
//  MindWaveBreathingModels.swift
//  MindWaveGraphic
//
//  既存フローとは独立した追加UI：3モード呼吸ガイドのデータモデル。
//  GuideFlowModels・GuideFlowView とは接続しない。
//

import SwiftUI

// 呼吸の1フェーズ（吸う・止める・吐く）
struct MindWaveBreathPhase {
    let label: String
    let duration: TimeInterval
    let color: Color
}

// 3つの呼吸モード
enum MindWaveBreathingMode: CaseIterable, Identifiable {
    case fourSevenEight  // 4-7-8 リラックス
    case box             // BOX 集中力向上
    case twoOneFour      // 2-1-4 緊張緩和

    var id: Self { self }

    var displayName: String {
        switch self {
        case .fourSevenEight: return "4-7-8"
        case .box:            return "BOX"
        case .twoOneFour:     return "2-1-4"
        }
    }

    var purpose: String {
        switch self {
        case .fourSevenEight: return "リラックス"
        case .box:            return "集中力向上"
        case .twoOneFour:     return "緊張緩和"
        }
    }

    // 各モードのフェーズ定義
    var phases: [MindWaveBreathPhase] {
        switch self {
        case .fourSevenEight:
            // 吸う4秒・止める7秒・吐く8秒
            return [
                MindWaveBreathPhase(label: "吸う",   duration: 4, color: Color.cyan),
                MindWaveBreathPhase(label: "止める", duration: 7, color: Color.blue),
                MindWaveBreathPhase(label: "吐く",   duration: 8, color: Color(red: 0.35, green: 0.55, blue: 0.95)),
            ]
        case .box:
            // 吸う4秒・止める4秒・吐く4秒・止める4秒
            return [
                MindWaveBreathPhase(label: "吸う",   duration: 4, color: Color.cyan),
                MindWaveBreathPhase(label: "止める", duration: 4, color: Color.green),
                MindWaveBreathPhase(label: "吐く",   duration: 4, color: Color.teal),
                MindWaveBreathPhase(label: "止める", duration: 4, color: Color.mint),
            ]
        case .twoOneFour:
            // 吸う2秒・止める1秒・吐く4秒
            return [
                MindWaveBreathPhase(label: "吸う",   duration: 2, color: Color.cyan),
                MindWaveBreathPhase(label: "止める", duration: 1, color: Color.orange),
                MindWaveBreathPhase(label: "吐く",   duration: 4, color: Color.purple),
            ]
        }
    }
}
