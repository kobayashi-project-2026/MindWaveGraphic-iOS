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
    /// GuideFlowView から保存されたガイドセッション記録。MainTabViewから EnvironmentObject で共有。
    @EnvironmentObject var historyStore: GuideHistoryStore

    var body: some View {
        // NavigationStack: GuideRecordCard → RecordDetailView へのNavigation遷移を有効にする
        NavigationStack {
            ZStack {
                MindWaveTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {

                        Text("履歴")
                            .font(.system(size: 30, weight: .ultraLight))
                            .foregroundStyle(MindWaveTheme.textPrimary)
                            .tracking(2)
                            .padding(.top, 12)

                        // 実際に保存された記録のみ表示。ダミーデータは本番UIに出さない。
                        if historyStore.records.isEmpty {
                            guideRecordsEmptyState
                        } else {
                            guideRecordsSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Guide Records

    private var guideRecordsEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(MindWaveTheme.textTertiary)
            Text("まだガイド記録はありません")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(MindWaveTheme.textSecondary)
            Text("ガイドを実施して「レポートを確認して保存」を選ぶと、ここに表示されます")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(MindWaveTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var guideRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ガイド記録")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
                .tracking(1.2)
                .textCase(.uppercase)

            // NavigationLink: タップで RecordDetailView へ遷移
            ForEach(historyStore.records) { record in
                NavigationLink(destination: RecordDetailView(record: record)) {
                    GuideRecordCard(record: record)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - GuideRecordCard

/// GuideFlowView で保存されたガイドセッションの1件表示。
/// nilの値を0で代用しない。Mock記録は明示する。
private struct GuideRecordCard: View {
    let record: GuideSessionRecord

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: record.startedAt)
    }

    private var durationLabel: String {
        let m = record.durationSeconds / 60
        let s = record.durationSeconds % 60
        return s == 0 ? "\(m)分" : "\(m)分\(s)秒"
    }

    private var scoreDelta: Double? {
        guard let after = record.after else { return nil }
        return after.score - record.before.score
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ヘッダー行
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: record.exercise.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.cyan.opacity(0.7))
                    Text(record.exercise.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MindWaveTheme.textPrimary)
                }
                Spacer()
                Text(dateString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MindWaveTheme.textTertiary)
            }

            // シーン + 時間 + Mock表示
            HStack(spacing: 8) {
                Text(record.scene.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(MindWaveTheme.textSecondary)
                Text("·")
                    .foregroundStyle(MindWaveTheme.textTertiary)
                Text(durationLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(MindWaveTheme.textSecondary)
                if record.before.isMockData {
                    Text("Mock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.75))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.12)))
                }
            }

            Divider().background(Color.white.opacity(0.07))

            // スコア比較
            HStack(spacing: 0) {
                scoreColumn("前", score: record.before.score, hr: record.before.heartRate)
                Spacer()
                if let delta = scoreDelta {
                    VStack(spacing: 2) {
                        Text(String(format: "%+.1f", delta))
                            .font(.system(size: 16, weight: .thin, design: .rounded))
                            .foregroundStyle(delta < 0 ? Color.cyan.opacity(0.8) : delta > 0 ? Color.orange.opacity(0.75) : .white.opacity(0.4))
                        Image(systemName: delta < 0 ? "arrow.down" : delta > 0 ? "arrow.up" : "minus")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                }
                if let after = record.after {
                    scoreColumn("後", score: after.score, hr: after.heartRate)
                } else {
                    Text("再測定なし")
                        .font(.system(size: 11))
                        .foregroundStyle(MindWaveTheme.textTertiary)
                }
            }

            // HRV更新状態
            HStack(spacing: 4) {
                Image(systemName: record.hrvUpdated ? "checkmark.circle.fill" : "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(record.hrvUpdated ? Color.cyan.opacity(0.6) : .white.opacity(0.20))
                Text(record.hrvUpdated ? "HRV更新あり" : "HRVは今回更新されませんでした")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(.white.opacity(0.30))
            }
        }
        .padding(14)
        .darkCard()
    }

    private func scoreColumn(_ label: String, score: Double, hr: Double?) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
            Text(String(format: "%.0f", score))
                .font(.system(size: 28, weight: .thin, design: .rounded))
                .foregroundStyle(MindWaveTheme.stressColor(score: score))
            if let hr {
                Text(String(format: "%.0f bpm", hr))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                Text("---")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.20))
            }
        }
        .frame(width: 72)
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
        .environmentObject(GuideHistoryStore())
        .preferredColorScheme(.dark)
}
