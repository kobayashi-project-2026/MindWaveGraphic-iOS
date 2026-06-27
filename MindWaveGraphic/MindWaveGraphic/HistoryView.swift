//
//  HistoryView.swift
//  MindWaveGraphic
//
//  履歴画面。実データのみ表示する。架空の値は使用しない。
//  RecordDetailViewへの遷移を維持する。
//

import SwiftUI

// MARK: - 未使用構造体（削除禁止）

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
                Color(red: 0.02, green: 0.02, blue: 0.06).ignoresSafeArea()
                CyberGridShape(cellSize: 44)
                    .stroke(Color.cyan.opacity(0.025), lineWidth: 0.5)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        pageHeader
                            .padding(.top, 16)
                        if historyStore.records.isEmpty {
                            emptyState
                        } else {
                            recordsList
                        }
                        Spacer().frame(height: 96)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarHidden(true)
            .onAppear { print("[UI][History] view_appeared") }
        }
    }

    // MARK: - ページヘッダー

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("履歴")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)
            HStack(spacing: 8) {
                Text("SESSION LOG")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.60))
                    .tracking(1.2)
                if !historyStore.records.isEmpty {
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.25))
                    Text("\(historyStore.records.count) 件")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
        }
    }

    // MARK: - 空状態

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 24)
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.20))
            VStack(spacing: 8) {
                Text("まだ記録がありません")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
                Text("「整える」タブから呼吸ガイドを実施し、\nセッション終了後に保存すると記録されます。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.30))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Spacer().frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: - 記録一覧

    private var recordsList: some View {
        VStack(spacing: 8) {
            ForEach(historyStore.records) { record in
                NavigationLink(destination: RecordDetailView(record: record)) {
                    SessionRecordCard(record: record)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(record.exercise.title)、\(record.scene.displayName)")
                .accessibilityHint("タップして詳細を表示します")
            }
        }
    }
}

// MARK: - セッション記録カード

private struct SessionRecordCard: View {
    let record: GuideSessionRecord

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "M/d  HH:mm"
        return f.string(from: record.startedAt)
    }

    private var durationLabel: String {
        let m = record.durationSeconds / 60
        let s = record.durationSeconds % 60
        return s == 0 ? "\(m)分" : "\(m)分\(s)秒"
    }

    var body: some View {
        HStack(spacing: 14) {

            // 左: メタ情報
            VStack(alignment: .leading, spacing: 5) {

                HStack(spacing: 6) {
                    Image(systemName: record.exercise.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.cyan.opacity(0.75))
                    Text(record.exercise.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                    if record.before.isMockData {
                        Text("DEMO")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.12))
                                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.30), lineWidth: 1))
                            )
                    }
                }

                Text(dateString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))

                HStack(spacing: 5) {
                    Image(systemName: record.scene.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.28))
                    Text(record.scene.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.42))
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.20))
                    Text(durationLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }

            Spacer()

            // 右: 前後変化
            changeIndicator

            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.22))
        }
        .padding(16)
        .frame(minHeight: 72)
        .background(Color(red: 0.05, green: 0.07, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    @ViewBuilder
    private var changeIndicator: some View {
        if let beforeHR = record.before.heartRate,
           let afterHR  = record.after?.heartRate {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Text(String(format: "%.0f", beforeHR))
                        .foregroundStyle(Color.white.opacity(0.50))
                    Image(systemName: afterHR < beforeHR ? "arrow.down" : "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(afterHR < beforeHR ? Color(red: 0.20, green: 0.85, blue: 0.60) : Color.white.opacity(0.35))
                    Text(String(format: "%.0f", afterHR))
                        .foregroundStyle(Color.white)
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                Text("BPM")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.30))
            }
        } else if let after = record.after {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Text(String(format: "%.0f", record.before.score))
                        .foregroundStyle(Color.white.opacity(0.50))
                    Image(systemName: after.score < record.before.score ? "arrow.down" : "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(after.score < record.before.score ? Color(red: 0.20, green: 0.85, blue: 0.60) : Color.white.opacity(0.35))
                    Text(String(format: "%.0f", after.score))
                        .foregroundStyle(Color.white)
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                Text("SCORE")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.30))
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text("—")
                    .font(.system(size: 20, weight: .thin, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.22))
                Text("未完了")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.22))
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
            let w = size.width, h = size.height, mid = h * 0.5
            var line = Path()
            var first = true
            for x in stride(from: 0.0, through: w, by: 1.5) {
                let y = mid + sin(x / w * .pi * 4.5 + 0.4) * amplitude * h * 0.40
                let pt = CGPoint(x: x, y: y)
                if first { line.move(to: pt); first = false } else { line.addLine(to: pt) }
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
