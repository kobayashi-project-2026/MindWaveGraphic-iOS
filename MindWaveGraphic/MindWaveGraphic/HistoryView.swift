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
                    .stroke(Color.cyan.opacity(0.038), lineWidth: 0.5)
                    .ignoresSafeArea()
                // 下部コックピットパネル反射グロー
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [Color(red: 0.02, green: 0.06, blue: 0.20).opacity(0.40), .clear],
                        startPoint: .bottom, endPoint: .top
                    )
                    .frame(height: 150)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea(edges: .bottom)
                // サイドエッジ
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.07), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 18)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.cyan.opacity(0.07)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 18)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

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
        VStack(alignment: .leading, spacing: 5) {
            // HUD ラベル行
            HStack(spacing: 8) {
                Text("MISSION LOG")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.55))
                    .tracking(1.8)
                Rectangle()
                    .fill(Color.cyan.opacity(0.18))
                    .frame(height: 0.6)
                    .frame(maxWidth: .infinity)
                if !historyStore.records.isEmpty {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.cyan.opacity(0.65))
                            .frame(width: 3.5, height: 3.5)
                            .shadow(color: Color.cyan.opacity(0.80), radius: 3)
                        Text("\(historyStore.records.count) REC")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.55))
                            .tracking(1.0)
                    }
                } else {
                    Text("STANDBY")
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.22))
                        .tracking(1.2)
                }
            }
            Text("履歴")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)
            Text("過去のセッションを確認します")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.32))
                .tracking(0.1)
        }
    }

    // MARK: - 空状態

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)

            // 透明パネル枠（ターミナル画面感）
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.03, green: 0.05, blue: 0.12).opacity(0.60))
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.04), .clear],
                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.20)
                    ))
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.cyan.opacity(0.18), lineWidth: 0.8)

                VStack(spacing: 20) {
                    // パネル上端バー
                    HStack(spacing: 6) {
                        Text("SYS")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.40))
                            .tracking(1.5)
                        Rectangle()
                            .fill(Color.cyan.opacity(0.14))
                            .frame(height: 0.5)
                        Text("LOG")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.40))
                            .tracking(1.5)
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                    // レーダースキャン風アイコン
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(Color.cyan.opacity(0.06 + Double(i) * 0.03), lineWidth: 0.7)
                                .frame(width: CGFloat(44 + i * 22), height: CGFloat(44 + i * 22))
                        }
                        Circle()
                            .fill(Color.cyan.opacity(0.05))
                            .frame(width: 44, height: 44)
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 26, weight: .ultraLight))
                            .foregroundStyle(Color.cyan.opacity(0.40))
                    }

                    VStack(spacing: 8) {
                        Text("NO MISSION DATA")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.28))
                            .tracking(2.2)
                        Text("「整える」タブから呼吸ガイドを実施し、\nセッション終了後に保存すると記録されます。")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.30))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }

                    // ステータス行
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.cyan.opacity(0.55))
                            .frame(width: 4, height: 4)
                            .shadow(color: Color.cyan.opacity(0.70), radius: 3)
                        Text("LOG CHANNEL READY")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.40))
                            .tracking(1.5)
                    }
                    .padding(.bottom, 18)
                }
            }
            .padding(.horizontal, 4)

            Spacer().frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
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

    private func stateLabel(for score: Double) -> String {
        switch score {
        case ..<25: return "CALM"
        case ..<55: return "FOCUS"
        case ..<78: return "ALERT"
        default:    return "OVLD"
        }
    }

    private func stateColor(for score: Double) -> Color {
        switch score {
        case ..<25: return Color(hue: 0.62, saturation: 0.80, brightness: 0.88)
        case ..<55: return Color(hue: 0.48, saturation: 0.85, brightness: 0.90)
        case ..<78: return Color(hue: 0.08, saturation: 0.92, brightness: 0.98)
        default:    return Color(hue: 0.01, saturation: 0.96, brightness: 1.0)
        }
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
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.04, green: 0.06, blue: 0.11))
                // 上端ハイライトリップ
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.045), .clear],
                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)
                    ))
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                // ステートカラー左エッジ（計器パネル感）
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(stateColor(for: record.before.score).opacity(0.72))
                        .frame(width: 2.5)
                        .shadow(color: stateColor(for: record.before.score).opacity(0.45), radius: 5)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        )
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
                    Text(stateLabel(for: record.before.score))
                        .foregroundStyle(stateColor(for: record.before.score).opacity(0.55))
                    Image(systemName: after.score < record.before.score ? "arrow.down" : "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(after.score < record.before.score
                                         ? Color(red: 0.20, green: 0.85, blue: 0.60)
                                         : Color.white.opacity(0.35))
                    Text(stateLabel(for: after.score))
                        .foregroundStyle(stateColor(for: after.score))
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("STATE")
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
