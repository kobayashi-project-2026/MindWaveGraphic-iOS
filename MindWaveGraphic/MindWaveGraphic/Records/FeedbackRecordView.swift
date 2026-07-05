// FeedbackRecordView.swift
// Records
//
// 既存ロジックを維持したUI統合：Cyber UIデザインを適用。
// 保存処理・isSaving多重防止・onSaveコールバック・キャンセル・200文字制限は変更しない。

import SwiftUI

struct FeedbackRecordView: View {

    // MARK: - セッションデータ（変更なし）

    let before: GuideSnapshot
    let after: GuideSnapshot?
    let scene: MeasurementScene
    let exercise: GuideExercise
    let durationSeconds: Int

    let onSave: (String) -> Void
    let onCancel: () -> Void

    // MARK: - State（変更なし）

    @State private var emotionMemo: String = ""
    @State private var showDiscardAlert = false
    @FocusState private var isMemoFocused: Bool
    @State private var isSaving = false

    // MARK: - Helpers（変更なし）

    private var scoreDelta: Double? {
        guard let after else { return nil }
        return after.score - before.score
    }

    private var durationLabel: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return s == 0 ? "\(m)分" : "\(m)分\(s)秒"
    }

    private var dateTimeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d HH:mm"
        return f.string(from: before.timestamp)
    }

    private func scoreText(_ value: Double) -> String { String(format: "%.0f", value) }
    private func hrText(_ value: Double?) -> String {
        guard let v = value else { return "未取得" }
        return String(format: "%.0f bpm", v)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                MindWaveCyberBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        // ── レポートヘッダー ──────────────────────────
                        MindWaveCyberPanel(title: "SESSION REPORT") {
                            VStack(spacing: 8) {
                                cyberRow("実施日時",   dateTimeLabel)
                                Divider().background(MindWaveCyberTheme.borderColor)
                                cyberRow("場面",       scene.displayName)
                                Divider().background(MindWaveCyberTheme.borderColor)
                                cyberRow("ガイド",     exercise.title)
                                Divider().background(MindWaveCyberTheme.borderColor)
                                cyberRow("所要時間",   durationLabel)
                                if before.isMockData {
                                    Divider().background(MindWaveCyberTheme.borderColor)
                                    cyberRow("データ種別", "Mockデータ")
                                }
                            }
                        }

                        // ── 前後スコア比較 ────────────────────────────
                        MindWaveCyberPanel(title: "SCORE DELTA") {
                            HStack(spacing: 0) {
                                cyberScoreColumn("セッション前", score: before.score)
                                Divider().background(MindWaveCyberTheme.borderColor).frame(width: 1)
                                cyberScoreColumn("セッション後", score: after?.score)
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
                                        .foregroundStyle(scoreChangeColor(delta))
                                    Text(scoreChangeSummary(delta))
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                                }
                                .padding(.top, 6)
                            }
                        }

                        // ── 心拍数・HRV ───────────────────────────────
                        MindWaveCyberPanel(title: "BIOMETRICS", accentColor: MindWaveCyberTheme.emerald) {
                            VStack(spacing: 8) {
                                cyberRow("前 心拍数", hrText(before.heartRate))
                                Divider().background(MindWaveCyberTheme.borderColor)
                                cyberRow("後 心拍数", hrText(after?.heartRate))
                            }
                        }

                        // ── 感情メモ ──────────────────────────────────
                        MindWaveCyberPanel(title: "EMOTION MEMO") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextEditor(text: $emotionMemo)
                                    .focused($isMemoFocused)
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 80)
                                    .onChange(of: emotionMemo) { _, v in
                                        if v.count > 200 { emotionMemo = String(v.prefix(200)) }
                                    }

                                HStack {
                                    Text("体感や気持ちをメモ（未記入でも保存できます）")
                                        .font(.system(size: 10, weight: .light))
                                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                                    Spacer()
                                    Text("\(emotionMemo.count) / 200")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                                }
                            }
                        }

                        // 免責注記
                        Text("これは医療診断ではありません。\n数値は計測環境により変動します。参考値としてご確認ください。")
                            .font(.system(size: 10, weight: .light))
                            .foregroundStyle(MindWaveCyberTheme.textTertiary.opacity(0.7))
                            .multilineTextAlignment(.center)

                        // ── ボタン（保存処理は変更なし）─────────────
                        VStack(spacing: 10) {
                            // 保存ボタン（多重タップ防止：isSavingで二重保存を防ぐ）
                            Button {
                                guard !isSaving else { return }
                                isSaving = true
                                isMemoFocused = false
                                let trimmed = emotionMemo.trimmingCharacters(in: .whitespacesAndNewlines)
                                onSave(trimmed)
                            } label: {
                                HStack(spacing: 8) {
                                    if isSaving {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .scaleEffect(0.8)
                                            .tint(.black)
                                    }
                                    Text(isSaving ? "保存中..." : "保存する")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .foregroundStyle(isSaving ? MindWaveCyberTheme.textTertiary : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(isSaving
                                              ? MindWaveCyberTheme.cyan.opacity(0.30)
                                              : MindWaveCyberTheme.cyan)
                                        .shadow(color: isSaving ? .clear : MindWaveCyberTheme.cyan.opacity(0.40),
                                                radius: 10)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                            .accessibilityLabel("記録を保存して履歴へ移動する")
                            .accessibilityHint(isSaving ? "保存中です" : "タップして記録を保存します")

                            // キャンセルボタン（保存しない）
                            Button {
                                onCancel()
                            } label: {
                                Text("キャンセル")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(MindWaveCyberTheme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(MindWaveCyberTheme.panelBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .strokeBorder(MindWaveCyberTheme.borderColor, lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("保存せずに結果画面へ戻る")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("記録確認")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("戻る") { onCancel() }
                        .foregroundStyle(MindWaveCyberTheme.cyan)
                }
            }
            .onTapGesture { isMemoFocused = false }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Score Helpers（変更なし）

    private func scoreChangeSummary(_ delta: Double) -> String {
        if delta < -5 { return "（下がりました）" }
        if delta > 5  { return "（上がりました）" }
        return "（ほぼ変化なし）"
    }

    private func scoreChangeColor(_ delta: Double) -> Color {
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
        score: 72, confidence: 0.70,
        state: .overTense,
        heartRate: 88, hrv: 42,
        isMockData: true,
        heartRateSampleDate: Date(),
        hrvSampleDate: Date()
    )
    let snapAfter = GuideSnapshot(
        timestamp: Date(),
        score: 51, confidence: 0.72,
        state: .optimalTension,
        heartRate: 75, hrv: 48,
        isMockData: true,
        heartRateSampleDate: Date(),
        hrvSampleDate: Date()
    )
    FeedbackRecordView(
        before: snap, after: snapAfter,
        scene: .interview, exercise: .ripple,
        durationSeconds: 60,
        onSave: { _ in },
        onCancel: {}
    )
}
