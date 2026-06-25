// RecordDetailView.swift
// Records
//
// 保存済みGuideSessionRecordの詳細を表示する画面。
// HistoryViewのNavigationLinkで呼び出される。
// 未取得値は "未取得" と表示し、固定値は使用しない。

import SwiftUI

/// セッション記録の詳細レポート画面。
/// HistoryView から NavigationLink で遷移する。
struct RecordDetailView: View {

    let record: GuideSessionRecord

    // MARK: - Helpers

    private var durationLabel: String {
        let m = record.durationSeconds / 60
        let s = record.durationSeconds % 60
        return s == 0 ? "\(m)分" : "\(m)分\(s)秒"
    }

    private var dateTimeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d（E）HH:mm"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: record.startedAt)
    }

    private var scoreDelta: Double? {
        guard let after = record.after else { return nil }
        return after.score - record.before.score
    }

    private func hrText(_ value: Double?) -> String {
        guard let v = value else { return "未取得" }
        return String(format: "%.0f bpm", v)
    }

    private func hrvText(_ value: Double?) -> String {
        guard let v = value else { return "未取得" }
        return String(format: "%.0f ms", v)
    }

    private func scoreText(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            MindWaveTheme.backgroundGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // ── 基本情報 ──────────────────────────────────────
                    detailBlock {
                        detailRow("実施日時",   dateTimeLabel)
                        detailRow("場面",       record.scene.displayName)
                        detailRow("ガイド",     record.exercise.title)
                        detailRow("所要時間",   durationLabel)
                        if record.before.isMockData {
                            detailRow("データ種別", "Mockデータ")
                        }
                    }

                    // ── 前後スコア ────────────────────────────────────
                    detailBlock {
                        HStack(spacing: 0) {
                            scoreColumn("セッション前", score: record.before.score)
                            Divider().background(Color.white.opacity(0.12)).frame(width: 1)
                            scoreColumn("セッション後", score: record.after?.score)
                        }
                        .padding(.vertical, 4)

                        if let delta = scoreDelta {
                            Divider().background(Color.white.opacity(0.08))
                            HStack(spacing: 6) {
                                Text("変化")
                                    .font(.system(size: 12))
                                    .foregroundStyle(MindWaveTheme.textTertiary)
                                Spacer()
                                Text(String(format: "%+.1f", delta))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(deltaColor(delta))
                                Text(deltaSummary(delta))
                                    .font(.system(size: 11))
                                    .foregroundStyle(MindWaveTheme.textTertiary)
                            }
                        }
                    }

                    // ── 心拍数・HRV ───────────────────────────────────
                    detailBlock {
                        detailRow("前 心拍数",     hrText(record.before.heartRate))
                        detailRow("後 心拍数",     hrText(record.after?.heartRate))
                        Divider().background(Color.white.opacity(0.06))
                        detailRow("前 HRV (SDNN)", hrvText(record.before.hrv))
                        detailRow("後 HRV (SDNN)", hrvText(record.after?.hrv))

                        HStack(spacing: 5) {
                            Image(systemName: record.hrvUpdated ? "checkmark.circle.fill" : "minus.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(record.hrvUpdated ? MindWaveTheme.accent.opacity(0.7) : .white.opacity(0.20))
                            Text(record.hrvUpdated ? "HRVが更新されました" : "HRVは今回更新されませんでした")
                                .font(.system(size: 10, weight: .light))
                                .foregroundStyle(MindWaveTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    // ── 感情メモ ──────────────────────────────────────
                    detailBlock {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("感情メモ")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MindWaveTheme.textTertiary)
                            if let memo = record.emotionMemo, !memo.isEmpty {
                                Text(memo)
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundStyle(MindWaveTheme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text("（メモなし）")
                                    .font(.system(size: 13, weight: .light))
                                    .foregroundStyle(MindWaveTheme.textTertiary)
                            }
                        }
                    }

                    // ── 免責注記 ──────────────────────────────────────
                    Text("これは医療診断ではありません。\n数値は計測環境により変動します。参考値としてご確認ください。")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(MindWaveTheme.textTertiary.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .navigationTitle("詳細レポート")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            print("[Record] detail opened: \(record.id.uuidString.prefix(8))")
        }
    }

    // MARK: - Helpers

    private func deltaSummary(_ delta: Double) -> String {
        if delta < -5  { return "（下がりました）" }
        if delta > 5   { return "（上がりました）" }
        return "（ほぼ変化なし）"
    }

    private func deltaColor(_ delta: Double) -> Color {
        if delta < -3 { return MindWaveTheme.accent }
        if delta > 3  { return Color(red: 0.90, green: 0.45, blue: 0.20) }
        return MindWaveTheme.textSecondary
    }

    // MARK: - Sub Views

    private func detailBlock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) { content() }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(MindWaveTheme.textSecondary)
        }
    }

    private func scoreColumn(_ label: String, score: Double?) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MindWaveTheme.textTertiary)
            if let s = score {
                Text(scoreText(s))
                    .font(.system(size: 32, weight: .thin, design: .rounded))
                    .foregroundStyle(MindWaveTheme.stressColor(score: s))
            } else {
                Text("未取得")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(MindWaveTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    let snap = GuideSnapshot(
        timestamp: Date(),
        score: 68, confidence: 0.72,
        state: .overTense,
        heartRate: 85, hrv: 44,
        isMockData: true,
        heartRateSampleDate: Date(), hrvSampleDate: Date()
    )
    NavigationStack {
        RecordDetailView(record: GuideSessionRecord(
            id: UUID(), startedAt: Date(),
            scene: .interview, exercise: .ripple,
            durationSeconds: 180,
            before: snap, after: nil,
            hrvUpdated: false,
            emotionMemo: "少し緊張が残っているが落ち着いてきた。"
        ))
    }
    .preferredColorScheme(.dark)
}
