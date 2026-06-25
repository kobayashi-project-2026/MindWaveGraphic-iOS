// RecordDetailView.swift
// Records
//
// 既存ロジックを維持したUI統合：Cyber UIデザインを適用。
// 表示データ・変化要約ロジック・deltaSummaryは変更しない。

import SwiftUI

struct RecordDetailView: View {

    let record: GuideSessionRecord

    // MARK: - Helpers（変更なし）

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
            MindWaveCyberBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {

                    // ── ログID風ヘッダー ──────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(MindWaveCyberTheme.cyan)
                                .frame(width: 2, height: 16)
                                .shadow(color: MindWaveCyberTheme.cyan.opacity(0.8), radius: 4)
                            Text("DETAIL REPORT")
                                .font(.system(size: 16, weight: .ultraLight, design: .monospaced))
                                .foregroundStyle(MindWaveCyberTheme.textPrimary)
                                .tracking(2)
                        }
                        Text("ID: \(record.id.uuidString.prefix(8).uppercased())")
                            .font(.system(size: 10, weight: .light, design: .monospaced))
                            .foregroundStyle(MindWaveCyberTheme.textTertiary)
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // ── 基本情報 ──────────────────────────────────────
                    MindWaveCyberPanel(title: "SESSION INFO") {
                        VStack(spacing: 8) {
                            cyberRow("実施日時",   dateTimeLabel)
                            Divider().background(MindWaveCyberTheme.borderColor)
                            cyberRow("場面",       record.scene.displayName)
                            Divider().background(MindWaveCyberTheme.borderColor)
                            cyberRow("ガイド",     record.exercise.title)
                            Divider().background(MindWaveCyberTheme.borderColor)
                            cyberRow("所要時間",   durationLabel)
                            if record.before.isMockData {
                                Divider().background(MindWaveCyberTheme.borderColor)
                                cyberRow("データ種別", "Mockデータ")
                            }
                        }
                    }

                    // ── 前後スコア ────────────────────────────────────
                    MindWaveCyberPanel(title: "SCORE COMPARISON") {
                        HStack(spacing: 0) {
                            cyberScoreColumn("セッション前", score: record.before.score)
                            Divider().background(MindWaveCyberTheme.borderColor).frame(width: 1)
                            cyberScoreColumn("セッション後", score: record.after?.score)
                        }
                        .padding(.vertical, 4)

                        if let delta = scoreDelta {
                            Divider().background(MindWaveCyberTheme.borderColor).padding(.top, 4)
                            HStack(spacing: 6) {
                                Text("変化")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                                Spacer()
                                Text(String(format: "%+.1f", delta))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(deltaColor(delta))
                                Text(deltaSummary(delta))
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                            }
                            .padding(.top, 6)
                        }
                    }

                    // ── 心拍数・HRV ───────────────────────────────────
                    MindWaveCyberPanel(title: "BIOMETRICS", accentColor: MindWaveCyberTheme.emerald) {
                        VStack(spacing: 8) {
                            cyberRow("前 心拍数",     hrText(record.before.heartRate))
                            Divider().background(MindWaveCyberTheme.borderColor)
                            cyberRow("後 心拍数",     hrText(record.after?.heartRate))
                            Divider().background(MindWaveCyberTheme.borderColor)
                            cyberRow("前 HRV (SDNN)", hrvText(record.before.hrv))
                            Divider().background(MindWaveCyberTheme.borderColor)
                            cyberRow("後 HRV (SDNN)", hrvText(record.after?.hrv))
                        }
                        HStack(spacing: 5) {
                            Image(systemName: record.hrvUpdated ? "checkmark.circle.fill" : "minus.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(record.hrvUpdated ? MindWaveCyberTheme.cyan.opacity(0.8) : MindWaveCyberTheme.textTertiary)
                            Text(record.hrvUpdated ? "HRVが更新されました" : "HRVは今回更新されませんでした")
                                .font(.system(size: 10, weight: .light))
                                .foregroundStyle(MindWaveCyberTheme.textTertiary)
                            Spacer()
                        }
                        .padding(.top, 8)
                    }

                    // ── 感情メモ ──────────────────────────────────────
                    MindWaveCyberPanel(title: "EMOTION MEMO", accentColor: MindWaveCyberTheme.purple) {
                        if let memo = record.emotionMemo, !memo.isEmpty {
                            Text(memo)
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(MindWaveCyberTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text("（メモなし）")
                                .font(.system(size: 13, weight: .light))
                                .foregroundStyle(MindWaveCyberTheme.textTertiary)
                        }
                    }

                    // ── 変化要約（変更なし）──────────────────────────
                    if let delta = scoreDelta {
                        MindWaveCyberPanel(title: "SUMMARY") {
                            HStack(spacing: 12) {
                                Image(systemName: delta < -5 ? "arrow.down.circle.fill" : delta > 5 ? "arrow.up.circle.fill" : "equal.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(deltaColor(delta))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(deltaSummary(delta))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(MindWaveCyberTheme.textPrimary)
                                    Text("緊張度が\(String(format: "%.1f", abs(delta)))ポイント\(delta < 0 ? "下がりました" : delta > 0 ? "上がりました" : "変化なし")")
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundStyle(MindWaveCyberTheme.textSecondary)
                                }
                            }
                        }
                    }

                    Text("これは医療診断ではありません。\n数値は計測環境により変動します。参考値としてご確認ください。")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary.opacity(0.6))
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

    // MARK: - Helpers（変更なし）

    private func deltaSummary(_ delta: Double) -> String {
        if delta < -5  { return "（下がりました）" }
        if delta > 5   { return "（上がりました）" }
        return "（ほぼ変化なし）"
    }

    private func deltaColor(_ delta: Double) -> Color {
        if delta < -3 { return MindWaveCyberTheme.cyan }
        if delta > 3  { return MindWaveCyberTheme.orange }
        return MindWaveCyberTheme.textSecondary
    }

    // MARK: - Sub Views

    private func cyberRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
                .tracking(0.5)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textSecondary)
        }
    }

    private func cyberScoreColumn(_ label: String, score: Double?) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
            if let s = score {
                Text(scoreText(s))
                    .font(.system(size: 32, weight: .thin, design: .rounded))
                    .foregroundStyle(MindWaveTheme.stressColor(score: s))
            } else {
                Text("未取得")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
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
