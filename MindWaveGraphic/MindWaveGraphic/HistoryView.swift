//
//  HistoryView.swift
//  MindWaveGraphic
//
//  参考写真レイアウトへ全面再設計。
//  NavigationStack・履歴ロジック・RecordDetailViewへの遷移は変更しない。
//  心拍数・HRV・スコアの固定値は使用しない。実データのみ表示する。
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
                    VStack(alignment: .leading, spacing: 20) {

                        // ── 大見出し ──────────────────────────────────
                        historyHeader
                            .padding(.top, 16)

                        if historyStore.records.isEmpty {
                            emptyState
                        } else {
                            recordsList
                        }

                        // カスタムタブバー対応の下余白
                        Spacer().frame(height: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .onAppear { print("[ReferenceUI] history appeared") }
        }
    }

    // MARK: - ログ履歴一覧 見出し

    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ログ履歴一覧")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(MindWaveCyberTheme.textPrimary)
            HStack(spacing: 8) {
                Text("SESSION LOG")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.cyan.opacity(0.65))
                    .tracking(1.5)
                Text("·")
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                Text("\(historyStore.records.count) 件")
                    .font(.system(size: 10, weight: .light, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
        }
    }

    // MARK: - 空状態（シンプル）

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
            Text("保存された記録はまだありません")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
            Text("ガイドを実施して「レポートを確認して保存」を選ぶと、ここに表示されます")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(MindWaveCyberTheme.textTertiary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    // MARK: - 記録一覧

    private var recordsList: some View {
        VStack(spacing: 8) {
            ForEach(historyStore.records) { record in
                NavigationLink(destination: RecordDetailView(record: record)) {
                    SimpleRecordCard(record: record)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(record.exercise.title) \(record.scene.displayName)")
                .accessibilityHint("タップして詳細を表示します")
            }
        }
    }
}

// MARK: - SimpleRecordCard（横長・シンプル）

private struct SimpleRecordCard: View {
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

    var body: some View {
        HStack(spacing: 14) {

            // ── 左: ガイド名・日時・場面 ──────────────────────────
            VStack(alignment: .leading, spacing: 5) {

                HStack(spacing: 6) {
                    Image(systemName: record.exercise.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(MindWaveCyberTheme.cyan.opacity(0.8))
                    Text(record.exercise.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MindWaveCyberTheme.textPrimary)
                    if record.before.isMockData {
                        Text("MOCK")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(MindWaveCyberTheme.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(MindWaveCyberTheme.orange.opacity(0.15))
                                    .overlay(Capsule().strokeBorder(MindWaveCyberTheme.orange.opacity(0.35), lineWidth: 1))
                            )
                    }
                }

                Text(dateString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)

                HStack(spacing: 5) {
                    Image(systemName: record.scene.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                    Text(record.scene.displayName)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(MindWaveCyberTheme.textSecondary)
                    Text("·")
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                    Text(durationLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MindWaveCyberTheme.textTertiary)
                }
            }

            Spacer()

            // ── 右: 前後値 ────────────────────────────────────────
            rightValueArea

            // ── シェブロン ────────────────────────────────────────
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(MindWaveCyberTheme.textTertiary)
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

    // 右カラム: 心拍数またはスコアの前後変化
    @ViewBuilder
    private var rightValueArea: some View {
        if let beforeHR = record.before.heartRate,
           let afterHR  = record.after?.heartRate {
            // 前後心拍数が揃っている場合
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f → %.0f", beforeHR, afterHR))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                Text("BPM")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
        } else if let after = record.after {
            // 心拍数がなく、後スコアがある場合
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f → %.0f", record.before.score, after.score))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textPrimary)
                Text("SCORE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
        } else {
            // 後測定なし
            VStack(alignment: .trailing, spacing: 2) {
                Text("—")
                    .font(.system(size: 22, weight: .thin, design: .rounded))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
                Text("未取得")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(MindWaveCyberTheme.textTertiary)
            }
        }
    }
}

// MARK: - MiniWave（未使用・削除禁止）

private struct MiniWave: View {
    let amplitude: Double
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let w   = size.width
            let h   = size.height
            let mid = h * 0.5
            var line = Path()
            var first = true
            for x in stride(from: 0.0, through: w, by: 1.5) {
                let y  = mid + sin(x / w * .pi * 4.5 + 0.4) * amplitude * h * 0.40
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
