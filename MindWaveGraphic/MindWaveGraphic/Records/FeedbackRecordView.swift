// FeedbackRecordView.swift
// Records
//
// 呼吸セッション完了後に表示するフィードバック確認・保存画面。
// GuideFlowView の結果画面から sheet で呼ばれる。
//
// 設計方針：
// - 実際に取得できた値だけを表示し、未取得は "未取得" と表示する
// - ランダム値・固定値は使用しない
// - 感情メモは任意（空欄のまま保存可能）
// - 保存処理は onSave コールバック経由で GuideFlowView に委譲する
//   → 保存は GuideFlowView 内で1回だけ実行される
// - キャンセル時は保存せず結果画面へ戻る

import SwiftUI

/// フィードバック確認・保存画面。
/// GuideFlowView から onSave / onCancel コールバックを受け取り、
/// 保存の実行は GuideFlowView 側（saveWithMemo）に委譲する。
struct FeedbackRecordView: View {

    // MARK: - セッションデータ（GuideFlowViewから渡される）

    let before: GuideSnapshot
    let after: GuideSnapshot?
    let scene: MeasurementScene
    let exercise: GuideExercise
    let durationSeconds: Int
    let hrvUpdated: Bool

    // MARK: - コールバック（保存処理はGuideFlowViewが担当）

    /// 保存ボタン押下時に呼ばれる。emotionMemoを渡す。
    let onSave: (String) -> Void
    /// キャンセル時に呼ばれる。記録は保存しない。
    let onCancel: () -> Void

    // MARK: - State

    /// 感情メモ（任意・最大200文字）。空欄のまま保存可能。
    @State private var emotionMemo: String = ""
    @State private var showDiscardAlert = false
    @FocusState private var isMemoFocused: Bool
    /// 多重タップ防止フラグ。保存中はボタンを無効化する。
    @State private var isSaving = false

    // MARK: - Helpers

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

    private func scoreText(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private func hrText(_ value: Double?) -> String {
        guard let v = value else { return "未取得" }
        return String(format: "%.0f bpm", v)
    }

    private func hrvText(_ value: Double?) -> String {
        guard let v = value else { return "未取得" }
        return String(format: "%.0f ms", v)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                MindWaveTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // ── ヘッダー情報 ─────────────────────────────
                        infoBlock {
                            infoRow("実施日時",   dateTimeLabel)
                            infoRow("場面",       scene.displayName)
                            infoRow("ガイド",     exercise.title)
                            infoRow("所要時間",   durationLabel)
                            if before.isMockData {
                                infoRow("データ種別", "Mockデータ")
                            }
                        }

                        // ── 前後の緊張度スコア ────────────────────────
                        infoBlock {
                            HStack(spacing: 0) {
                                scoreColumn("セッション前", score: before.score)
                                Divider().background(Color.white.opacity(0.12)).frame(width: 1)
                                scoreColumn("セッション後", score: after?.score)
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
                                        .foregroundStyle(scoreChangeColor(delta))
                                    Text(scoreChangeSummary(delta))
                                        .font(.system(size: 11))
                                        .foregroundStyle(MindWaveTheme.textTertiary)
                                }
                            }
                        }

                        // ── 心拍数・HRV ───────────────────────────────
                        infoBlock {
                            infoRow("前 心拍数",  hrText(before.heartRate))
                            infoRow("後 心拍数",  hrText(after?.heartRate))
                            Divider().background(Color.white.opacity(0.06))
                            infoRow("前 HRV (SDNN)", hrvText(before.hrv))
                            infoRow("後 HRV (SDNN)", hrvText(after?.hrv))
                            if hrvUpdated {
                                Text("HRVが更新されました")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundStyle(MindWaveTheme.accent.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                Text("HRVは今回更新されませんでした")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundStyle(MindWaveTheme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }

                        // ── 感情メモ ──────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("感情メモ（任意）")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MindWaveTheme.textTertiary)
                                .padding(.leading, 4)

                            TextEditor(text: $emotionMemo)
                                .focused($isMemoFocused)
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(MindWaveTheme.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 88)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                        )
                                )
                                .onChange(of: emotionMemo) { _, v in
                                    // 最大200文字制限
                                    if v.count > 200 { emotionMemo = String(v.prefix(200)) }
                                }

                            HStack {
                                Text("体感や気持ちをメモ（未記入でも保存できます）")
                                    .font(.system(size: 10))
                                    .foregroundStyle(MindWaveTheme.textTertiary)
                                Spacer()
                                Text("\(emotionMemo.count) / 200")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(MindWaveTheme.textTertiary)
                            }
                        }

                        // ── 免責注記 ──────────────────────────────────
                        Text("これは医療診断ではありません。\n数値は計測環境により変動します。参考値としてご確認ください。")
                            .font(.system(size: 10, weight: .light))
                            .foregroundStyle(MindWaveTheme.textTertiary.opacity(0.7))
                            .multilineTextAlignment(.center)

                        // ── ボタン ────────────────────────────────────
                        VStack(spacing: 10) {
                            // 保存ボタン（多重タップ防止：isSaving で二重保存を防ぐ）
                            Button {
                                guard !isSaving else { return }
                                isSaving = true
                                isMemoFocused = false
                                // 前後の空白だけの場合は nil として渡す
                                let trimmed = emotionMemo.trimmingCharacters(in: .whitespacesAndNewlines)
                                onSave(trimmed)
                            } label: {
                                Text("保存する")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(isSaving ? MindWaveTheme.textTertiary : .black)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(isSaving ? Color.cyan.opacity(0.35) : Color.cyan.opacity(0.85)))
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                            .accessibilityLabel("記録を保存して履歴へ移動する")

                            // キャンセル（保存しない）
                            Button {
                                onCancel()
                            } label: {
                                Text("キャンセル")
                                    .font(.system(size: 14))
                                    .foregroundStyle(MindWaveTheme.textSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
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
                        .foregroundStyle(MindWaveTheme.accent)
                }
            }
            .onTapGesture { isMemoFocused = false }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Score Helpers

    private func scoreChangeSummary(_ delta: Double) -> String {
        if delta < -5  { return "（下がりました）" }
        if delta > 5   { return "（上がりました）" }
        return "（ほぼ変化なし）"
    }

    private func scoreChangeColor(_ delta: Double) -> Color {
        if delta < -3  { return MindWaveTheme.accent }
        if delta > 3   { return Color(red: 0.90, green: 0.45, blue: 0.20) }
        return MindWaveTheme.textSecondary
    }

    // MARK: - Sub Views

    private func infoBlock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) { content() }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            )
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
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
        durationSeconds: 60, hrvUpdated: false,
        onSave: { _ in },
        onCancel: {}
    )
}
