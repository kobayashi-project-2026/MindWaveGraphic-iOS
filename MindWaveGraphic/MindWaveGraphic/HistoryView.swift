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
                        colors: [Color(red: 0.02, green: 0.06, blue: 0.20).opacity(0.52), .clear],
                        startPoint: .bottom, endPoint: .top
                    )
                    .frame(height: 170)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea(edges: .bottom)
                // サイドフレーム（リベット付きコックピットストラット）
                HStack(spacing: 0) {
                    Canvas { ctx, size in
                        let sh = size.height
                        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: sh)),
                                 with: .color(Color.cyan.opacity(0.05)))
                        var el = Path()
                        el.move(to: CGPoint(x: size.width - 0.5, y: sh * 0.06))
                        el.addLine(to: CGPoint(x: size.width - 0.5, y: sh * 0.94))
                        ctx.stroke(el, with: .color(Color.cyan.opacity(0.28)), lineWidth: 0.7)
                        for i in 0..<4 {
                            let y = sh * (0.18 + Double(i) * 0.22)
                            ctx.fill(Path(ellipseIn: CGRect(x: size.width - 5.5, y: y - 2, width: 4, height: 4)),
                                     with: .color(Color.cyan.opacity(0.32)))
                            ctx.fill(Path(ellipseIn: CGRect(x: size.width - 4.5, y: y - 1, width: 2, height: 2)),
                                     with: .color(Color.black.opacity(0.45)))
                        }
                    }
                    .frame(width: 20)
                    Spacer()
                    Canvas { ctx, size in
                        let sh = size.height
                        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: sh)),
                                 with: .color(Color.cyan.opacity(0.05)))
                        var el = Path()
                        el.move(to: CGPoint(x: 0.5, y: sh * 0.06))
                        el.addLine(to: CGPoint(x: 0.5, y: sh * 0.94))
                        ctx.stroke(el, with: .color(Color.cyan.opacity(0.28)), lineWidth: 0.7)
                        for i in 0..<4 {
                            let y = sh * (0.18 + Double(i) * 0.22)
                            ctx.fill(Path(ellipseIn: CGRect(x: 1.5, y: y - 2, width: 4, height: 4)),
                                     with: .color(Color.cyan.opacity(0.32)))
                            ctx.fill(Path(ellipseIn: CGRect(x: 2.5, y: y - 1, width: 2, height: 2)),
                                     with: .color(Color.black.opacity(0.45)))
                        }
                    }
                    .frame(width: 20)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        pageHeader
                            .padding(.top, 16)
                        AITrendPanel(records: historyStore.records)
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
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.45))
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
                    .fill(Color(red: 0.03, green: 0.06, blue: 0.16).opacity(0.80))
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.06), .clear],
                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.20)
                    ))
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.cyan.opacity(0.12), lineWidth: 4)
                    .blur(radius: 4)
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.cyan.opacity(0.32), lineWidth: 1.0)

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
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(Color.cyan.opacity(0.60))
                            .shadow(color: Color.cyan.opacity(0.35), radius: 12)
                    }

                    VStack(spacing: 8) {
                        Text("NO MISSION DATA")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.50))
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
                            .foregroundStyle(Color.cyan.opacity(0.65))
                            .tracking(1.5)
                    }
                    .padding(.bottom, 5)

                    // サブステータス行
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.cyan.opacity(0.10))
                            .frame(height: 0.5)
                        Text("  AWAITING BIOMETRIC INPUT  ")
                            .font(.system(size: 6.5, weight: .light, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.16))
                            .tracking(0.8)
                            .fixedSize()
                        Rectangle()
                            .fill(Color.cyan.opacity(0.10))
                            .frame(height: 0.5)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                // コーナーHUDブラケット（ターミナルパネル四隅マーカー）
                Canvas { ctx, size in
                    let m: CGFloat = 9
                    let l: CGFloat = 14
                    let corners: [(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat)] = [
                        (m, m, 1, 1), (size.width - m, m, -1, 1),
                        (m, size.height - m, 1, -1), (size.width - m, size.height - m, -1, -1)
                    ]
                    for c in corners {
                        var ph = Path()
                        ph.move(to: CGPoint(x: c.x, y: c.y))
                        ph.addLine(to: CGPoint(x: c.x + c.dx * l, y: c.y))
                        ctx.stroke(ph, with: .color(Color.cyan.opacity(0.50)), lineWidth: 1.0)
                        var pv = Path()
                        pv.move(to: CGPoint(x: c.x, y: c.y))
                        pv.addLine(to: CGPoint(x: c.x, y: c.y + c.dy * l))
                        ctx.stroke(pv, with: .color(Color.cyan.opacity(0.50)), lineWidth: 1.0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .allowsHitTesting(false)
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
                    Text(record.exercise.timingLabel)
                        .font(.system(size: 9, weight: .light, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.50))
                        .tracking(0.5)
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

                // 体感バッジ (selfReport あれば表示)
                if record.selfReportBefore != nil || record.selfReportAfter != nil {
                    HStack(spacing: 4) {
                        if let sr = record.selfReportBefore {
                            selfReportBadge(label: "前:\(sr.shortLabel)", color: sr.accentColor)
                        }
                        if let sr = record.selfReportAfter {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.white.opacity(0.22))
                            selfReportBadge(label: "後:\(sr.shortLabel)", color: sr.accentColor)
                        }
                    }
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

    private func selfReportBadge(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
            .foregroundStyle(color.opacity(0.72))
            .tracking(0.4)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.08))
                    .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.6))
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

// MARK: - AI Trend Panel (AI Learning Log)

private struct AITrendPanel: View {
    let records: [GuideSessionRecord]

    private var pattern: PersonalAIPattern {
        LocalAIPatternAnalyzer.analyze(records: records)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── ヘッダーバー
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.cyan.opacity(0.55))
                Text("AI LEARNING LOG")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.55))
                    .tracking(1.8)
                Rectangle()
                    .fill(Color.cyan.opacity(0.14))
                    .frame(height: 0.5)
                Text(pattern.dataQualityNote)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.35))
                    .tracking(0.6)
            }
            .padding(.bottom, 10)

            // ── 学習進捗インジケーター (ドット3つ)
            learningProgressBar
                .padding(.bottom, 12)

            // ── メトリクス行
            HStack(spacing: 12) {
                if let ex = pattern.preferredExercise {
                    aiMetric(
                        label: "よく使う呼吸",
                        value: ex.title,
                        accent: Color.cyan.opacity(0.80)
                    )
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 0.6, height: 28)
                }

                aiMetric(
                    label: "落ち着き傾向",
                    value: pattern.sessionCount < 2 ? "学習中" :
                           (pattern.calmAfterRatio > 0.5 ? "あり" : "継続中"),
                    accent: pattern.calmAfterRatio > 0.5
                        ? Color(hue: 0.62, saturation: 0.78, brightness: 0.90)
                        : Color.white.opacity(0.50)
                )

                if let scene = pattern.dominantScene {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 0.6, height: 28)
                    aiMetric(
                        label: "主な場面",
                        value: scene.displayName,
                        accent: Color.white.opacity(0.65)
                    )
                }
            }
            .padding(.bottom, 12)

            // ── パターンテキスト（複数行）
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(pattern.patternLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(Color.cyan.opacity(0.35))
                            .padding(.top, 2)
                        Text(line)
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.50))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2.5)
                    }
                }
            }

            // ── LOCAL AI 説明フッター
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.top, 12)
                .padding(.bottom, 8)

            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.white.opacity(0.20))
                Text("ローカル分析のみ — 外部サーバーへの送信なし")
                    .font(.system(size: 7.5, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.22))
                    .tracking(0.4)
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.02, green: 0.05, blue: 0.14).opacity(0.92))
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.cyan.opacity(0.06), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.cyan.opacity(0.22), lineWidth: 0.8)
                // 上端ハイライト
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.10), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 20)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        )
    }

    private var learningProgressBar: some View {
        let n = records.count
        let steps = [1, 3, 7]
        return HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, threshold in
                let filled = n >= threshold
                HStack(spacing: 3) {
                    Circle()
                        .fill(filled ? Color.cyan.opacity(0.70) : Color.white.opacity(0.12))
                        .frame(width: 5, height: 5)
                    Text(i == 0 ? "初回" : i == 1 ? "3回" : "7回")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(filled ? Color.cyan.opacity(0.55) : Color.white.opacity(0.22))
                }
            }
            Spacer()
            Text("\(n)セッション記録済")
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.30))
        }
    }

    private func aiMetric(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.28))
                .tracking(0.5)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(GuideHistoryStore())
        .preferredColorScheme(.dark)
}
