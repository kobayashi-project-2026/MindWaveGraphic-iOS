// ContextCalibrationView.swift
// Authentication
//
// 測定前コンテキスト選択画面。
// 場面カテゴリ（単一）と身体状態（複数）を選んでスコア補正に活かす。
// 「あとで選ぶ」でスキップしてデフォルトコンテキストのままmainAppへ進める。

import SwiftUI

// MARK: - ContextCalibrationView

struct ContextCalibrationView: View {

    @ObservedObject var flowState: AppFlowState

    @State private var selectedScene: ContextScene = .calm
    @State private var selectedConditions: Set<BodyCondition> = [.none]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LaunchStarfieldBG()
                .ignoresSafeArea()

            // スクロールコンテンツ。CTAはsafeAreaInsetで分離し、タップ干渉を完全に防ぐ。
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    header
                        .padding(.top, 54)
                        .padding(.bottom, 20)
                    sceneSection
                    bodySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            // CTAをスクロールエリアの外（画面下部固定）に配置
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionButtonsPanel
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.6))
                    .frame(width: 14, height: 1)
                Text("CONTEXT CALIBRATION")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.7))
                    .tracking(1.5)
                Rectangle()
                    .fill(Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.6))
                    .frame(width: 14, height: 1)
            }
            Text("今の状況を教えてください")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.white)
            Text("より正確なゆらぎを読み取るために使います")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Color.white.opacity(0.42))
        }
    }

    // MARK: - Scene Section

    private var sceneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("場面", hint: "ひとつ選んでください")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(ContextScene.allCases) { scene in
                    sceneCard(scene)
                }
            }
        }
    }

    private func sceneCard(_ scene: ContextScene) -> some View {
        let selected = selectedScene == scene
        return Button {
            selectedScene = scene
        } label: {
            HStack(spacing: 10) {
                Image(systemName: scene.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.black : Color(red: 0.35, green: 0.75, blue: 0.95))
                    .frame(width: 20)
                Text(scene.displayName)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Color.black : Color.white.opacity(0.80))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected
                          ? Color(red: 0.35, green: 0.75, blue: 0.95)
                          : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                selected
                                ? Color.clear
                                : Color.white.opacity(0.14),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
        .accessibilityIdentifier("context_scene_\(scene.rawValue)")
    }

    // MARK: - Body Section

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("身体状態", hint: "複数選択可")

            VStack(spacing: 8) {
                ForEach(BodyCondition.allCases) { cond in
                    conditionRow(cond)
                }
            }
        }
    }

    private func conditionRow(_ cond: BodyCondition) -> some View {
        let selected = selectedConditions.contains(cond)
        return Button {
            if cond == .none {
                // 「特になし」を選んだら他をすべて外す
                selectedConditions = [.none]
            } else {
                // 「特になし」を外して、対象をトグル
                selectedConditions.remove(.none)
                if selected {
                    selectedConditions.remove(cond)
                    if selectedConditions.isEmpty { selectedConditions = [.none] }
                } else {
                    selectedConditions.insert(cond)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cond.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected
                                     ? Color(red: 0.35, green: 0.75, blue: 0.95)
                                     : Color.white.opacity(0.38))
                    .frame(width: 22)
                Text(cond.displayName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(selected ? 0.92 : 0.55))
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected
                                     ? Color(red: 0.35, green: 0.75, blue: 0.95)
                                     : Color.white.opacity(0.18))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(selected ? 0.09 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                selected
                                ? Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.4)
                                : Color.white.opacity(0.10),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.13), value: selected)
        .accessibilityIdentifier("context_body_\(cond.rawValue)")
    }

    // MARK: - Action Buttons Panel (safeAreaInset底部固定)

    private var actionButtonsPanel: some View {
        VStack(spacing: 0) {
            // スクロールコンテンツとの視覚的セパレーター
            LinearGradient(
                colors: [Color.clear,
                         Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.10)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 0.7)

            VStack(spacing: 10) {
                Button {
                    applyAndProceed()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 15))
                        Text("この状況で測定する")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 0.35, green: 0.75, blue: 0.95))
                            .shadow(color: Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.35),
                                    radius: 12, y: 4)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("context_primary_start_button")

                Button {
                    flowState.measurementContext = .default
                    flowState.authStatus = .mainApp
                    print("[Navigation] context skipped -> mainApp")
                } label: {
                    Text("あとで選ぶ")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("context_skip_button")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(
            ZStack {
                Color.black.opacity(0.90)
                LinearGradient(
                    colors: [Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.0),
                             Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.80)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String, hint: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color(red: 0.35, green: 0.75, blue: 0.95))
                .frame(width: 2, height: 14)
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
            Text(hint)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    private func applyAndProceed() {
        var ctx = MeasurementContext()
        ctx.scene      = selectedScene
        ctx.conditions = selectedConditions
        flowState.measurementContext = ctx
        flowState.authStatus = .mainApp
        print("[Navigation] context set: scene=\(selectedScene.rawValue) -> mainApp")
    }
}

// MARK: - LaunchStarfieldBG (shared between AccountGuidanceView and ContextCalibrationView)

/// 軽量静的星背景。ContextCalibrationとAccountGuidanceで共有できる簡略版。
struct LaunchStarfieldBG: View {
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = tl.date.timeIntervalSinceReferenceDate
                let cx = size.width  * 0.5
                let cy = size.height * 0.45
                for i in 0..<200 {
                    let s     = Double(i)
                    let sx    = sin(s * 12.9898 + 0.73) * 0.88
                    let sy    = cos(s * 78.233  + 0.31) * 0.88
                    let phase = abs(sin(s * 7.13 + 2.1)) * 0.5 + 0.5
                    let szd   = max(0.012, abs(sin(s * 43.71)) * 0.95 + 0.012)
                    var rawZ  = szd - t * 0.032 * (0.5 + phase * 0.5)
                    rawZ = rawZ.truncatingRemainder(dividingBy: 1.0)
                    if rawZ <= 0 { rawZ += 1.0 }
                    let z  = max(0.008, rawZ)
                    let sc = 1.0 / z
                    let px = sx * sc * size.width  * 0.52 + cx
                    let py = sy * sc * size.height * 0.52 + cy
                    guard px > -20, px < size.width  + 20,
                          py > -20, py < size.height + 20 else { continue }
                    let near   = max(0, 1.0 - z)
                    let radius = max(0.18, near * 1.6)
                    let op     = min(0.70, near * 1.4)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: px - radius, y: py - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(Color(red: 0.60 + near * 0.28, green: 0.78, blue: 1.0).opacity(op))
                    )
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContextCalibrationView(flowState: AppFlowState())
}
