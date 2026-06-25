//
//  HistoryView.swift
//  MindWaveGraphic
//
//  既存ロジックを維持したUI統合：Cyber UIデザインを適用。
//  NavigationStack構造・履歴ロジック・新しい記録が先頭に来る順序は変更しない。
//

import SwiftUI

// MARK: - Dummy structures（未使用・削除禁止）

private struct SessionRecord: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let duration: String
    let score: Double
}

// MARK: - HistoryView

struct HistoryView: View {
    @EnvironmentObject var historyStore: GuideHistoryStore

    var body: some View {
        NavigationStack {
            ZStack {
                MindWaveCyberBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        // ログ形式ヘッダー
                        cyberHistoryHeader
                            .padding(.top, 12)

                        if historyStore.records.isEmpty {
                            cyberEmptyState
                        } else {
                            cyberRecordsSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
            .onAppear { print("[CyberUI] history appeared") }
        }
    }

    // MARK: - ログ形式ヘッダー

    private var cyberHistoryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(MindWaveCyberTheme.cyan)
                    .frame(width: 3, height: 22)
                    .shadow(color: MindWaveCyberTheme.cyan.opacity(0.8), radius: 6)
                Text("SESSION LOG")
                    .font(.system(size: 22, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                    .tracking(3)
            }
            HStack(spacing: 8) {
                Text("RECORDS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.cyan.opacity(0.7))
                    .tracking(1.5)
                Text("·")
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                Text("\(historyStore.records.count) ENTRIES")
                    .font(.system(size: 10, weight: .light, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                    .tracking(0.8)
            }
        }
    }

    // MARK: - 空状態

    private var cyberEmptyState: some View {
        MindWaveCyberPanel {
            VStack(spacing: 12) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                Text("まだガイド記録はありません")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(MindWaveCyberTheme.textSecondary)
                Text("ガイドを実施して「レポートを確認して保存」を選ぶと、ここに表示されます")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    // MARK: - 記録一覧

    private var cyberRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MindWaveCyberSectionHeader(title: "GUIDE RECORDS")
                .padding(.leading, 2)

            ForEach(historyStore.records) { record in
                NavigationLink(destination: RecordDetailView(record: record)) {
                    CyberGuideRecordCard(record: record)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(record.exercise.title) \(record.scene.displayName)")
                .accessibilityHint("タップして詳細を表示します")
            }
        }
    }
}

// MARK: - CyberGuideRecordCard

private struct CyberGuideRecordCard: View {
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

    private var deltaColor: Color {
        guard let delta = scoreDelta else { return MindWaveCyberTheme.textTertiary }
        if delta < 0 { return MindWaveCyberTheme.cyan }
        if delta > 0 { return MindWaveCyberTheme.orange }
        return MindWaveCyberTheme.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ヘッダー行
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: record.exercise.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(MindWaveCyberTheme.cyan.opacity(0.8))
                    Text(record.exercise.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MindWaveCyberTheme.textPrimary)
                }
                Spacer()
                Text(dateString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }

            // 場面・時間・Mock
            HStack(spacing: 8) {
                Image(systemName: record.scene.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                Text(record.scene.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(MindWaveCyberTheme.textSecondary)
                Text("·")
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                Text(durationLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textSecondary)
                if record.before.isMockData {
                    MindWaveCyberStatusBadge(label: "MOCK", isActive: false, color: MindWaveCyberTheme.orange)
                }
            }

            Divider()
                .background(MindWaveCyberTheme.borderColor)

            // スコア比較
            HStack(spacing: 0) {
                cyberScoreColumn("前", score: record.before.score, hr: record.before.heartRate)
                Spacer()
                if let delta = scoreDelta {
                    VStack(spacing: 2) {
                        Text(String(format: "%+.1f", delta))
                            .font(.system(size: 16, weight: .thin, design: .rounded))
                            .foregroundStyle(deltaColor)
                        Image(systemName: delta < 0 ? "arrow.down" : delta > 0 ? "arrow.up" : "minus")
                            .font(.system(size: 10))
                            .foregroundStyle(deltaColor.opacity(0.6))
                    }
                    Spacer()
                }
                if let after = record.after {
                    cyberScoreColumn("後", score: after.score, hr: after.heartRate)
                } else {
                    Text("再測定なし")
                        .font(.system(size: 11))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                }
            }

            // HRV更新
            HStack(spacing: 4) {
                Image(systemName: record.hrvUpdated ? "checkmark.circle.fill" : "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(record.hrvUpdated ? MindWaveCyberTheme.cyan.opacity(0.7) : .white.opacity(0.18))
                Text(record.hrvUpdated ? "HRV更新あり" : "HRVは今回更新されませんでした")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(.white.opacity(0.28))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: MindWaveCyberTheme.panelRadius)
                .fill(MindWaveCyberTheme.panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: MindWaveCyberTheme.panelRadius)
                        .strokeBorder(MindWaveCyberTheme.borderColor, lineWidth: 1)
                )
        )
    }

    private func cyberScoreColumn(_ label: String, score: Double, hr: Double?) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
            Text(String(format: "%.0f", score))
                .font(.system(size: 28, weight: .thin, design: .rounded))
                .foregroundStyle(MindWaveTheme.stressColor(score: score))
            if let hr {
                Text(String(format: "%.0f bpm", hr))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            } else {
                Text("未取得")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
        }
        .frame(width: 72)
    }
}

// MARK: - MiniWave（未使用・削除禁止）

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
        }
        .background(color.opacity(0.06))
    }
}

#Preview {
    HistoryView()
        .environmentObject(GuideHistoryStore())
        .preferredColorScheme(.dark)
}
