//
//  HistoryView.swift
//  MindWaveGraphic
//

import SwiftUI

// MARK: - Dummy Session Data

private struct SessionRecord: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let duration: String
    let score: Double
}

private let dummyHistory: [(day: String, records: [SessionRecord])] = [
    (
        day: "今日",
        records: [
            SessionRecord(title: "夜のセッション", time: "22:14", duration: "8分", score: 38)
        ]
    ),
    (
        day: "昨日",
        records: [
            SessionRecord(title: "午後のセッション", time: "15:30", duration: "5分", score: 62),
            SessionRecord(title: "朝のセッション",   time: "08:12", duration: "7分", score: 45)
        ]
    ),
    (
        day: "5月18日（土）",
        records: [
            SessionRecord(title: "夜のセッション", time: "23:01", duration: "10分", score: 88)
        ]
    )
]

// MARK: - History View

struct HistoryView: View {
    var body: some View {
        ZStack {
            MindWaveTheme.backgroundGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {

                    Text("履歴")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(MindWaveTheme.textPrimary)
                        .tracking(2)
                        .padding(.top, 12)

                    ForEach(dummyHistory, id: \.day) { section in
                        VStack(alignment: .leading, spacing: 10) {

                            Text(section.day)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(MindWaveTheme.textTertiary)
                                .tracking(1.2)
                                .textCase(.uppercase)

                            ForEach(section.records) { record in
                                SessionCard(record: record)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Session Card

private struct SessionCard: View {
    let record: SessionRecord

    private var color: Color   { MindWaveTheme.stressColor(score: record.score) }
    private var label: String  { MindWaveTheme.stressLabel(score: record.score) }
    private var amplitude: Double { 0.25 + record.score / 100.0 * 0.55 }

    var body: some View {
        HStack(spacing: 14) {

            // ミニ波形サムネイル
            MiniWave(amplitude: amplitude, color: color)
                .frame(width: 58, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MindWaveTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(record.time)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(MindWaveTheme.textSecondary)
                    Text("·")
                        .foregroundStyle(MindWaveTheme.textTertiary)
                    Text(record.duration)
                        .font(.system(size: 12))
                        .foregroundStyle(MindWaveTheme.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.0f", record.score))
                    .font(.system(size: 22, weight: .thin, design: .rounded))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color.opacity(0.75))
            }
        }
        .padding(14)
        .darkCard()
    }
}

// MARK: - Mini Waveform（静止ダミー波形）

private struct MiniWave: View {
    let amplitude: Double
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let mid = h * 0.5

            var line = Path()
            var first = true
            for x in stride(from: 0.0, through: w, by: 1.5) {
                let y = mid + sin(x / w * .pi * 4.5 + 0.4) * amplitude * h * 0.40
                let pt = CGPoint(x: x, y: y)
                if first { line.move(to: pt); first = false }
                else { line.addLine(to: pt) }
            }
            ctx.stroke(line, with: .color(color.opacity(0.75)), lineWidth: 1.5)

            var fill = line
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.addLine(to: CGPoint(x: 0, y: h))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(color.opacity(0.12)))
        }
        .background(color.opacity(0.06))
    }
}

#Preview {
    HistoryView()
        .preferredColorScheme(.dark)
}
