// ContextCalibrationView.swift
// Authentication
//
// 測定前コンテキスト選択画面。
// 場面カテゴリ（単一）と身体状態（複数）を選んでスコア補正に活かす。
// 「あとで選ぶ」でスキップしてデフォルトコンテキストのままmainAppへ進める。
//
// 2026-10-28: もこりんとの会話で状況を整理できるようにした（Mokorin/、docs/MOKORIN_CONTEXT_INTEGRATION.md）。
// - 会話・選択の状態は MokorinContextViewModel が持つ（この View は表示と既存の確定処理だけを担当）
// - 既存のボタン操作・「特になし」の排他・applyAndProceed()・「あとで選ぶ」「変更しない」はそのまま
// - もこりんの提案は選択に反映されるだけで、測定は利用者が「この状況で測定する」を押したときだけ始まる

import SwiftUI

// MARK: - ContextCalibrationView

struct ContextCalibrationView: View {

    @ObservedObject var flowState: AppFlowState

    /// メインアプリ内（共通メニュー「対話（状況確認）」）から開いた場合の完了コールバック。
    /// nil のときは従来どおり認証フローの一部として mainApp へ進む。
    /// 指定時は計測ViewModelを作り直さないよう authStatus を変更せず、呼び出し元がモーダルを閉じる。
    var onComplete: (() -> Void)? = nil

    /// メインアプリ内から開いたか
    private var isInAppEdit: Bool { onComplete != nil }

    /// もこりんとの会話と、場面・身体状態の選択状態
    @StateObject private var mokorin: MokorinContextViewModel
    @FocusState private var isInputFocused: Bool

    private let accent = Color(red: 0.35, green: 0.75, blue: 0.95)
    private let conversationBottomID = "mokorin_conversation_bottom"

    init(flowState: AppFlowState, onComplete: (() -> Void)? = nil) {
        self._flowState = ObservedObject(wrappedValue: flowState)
        self.onComplete = onComplete
        // メインアプリ内から開いた場合は現在の状況を初期表示する（以前の onAppear と同じ内容）
        self._mokorin = StateObject(wrappedValue: MokorinContextViewModel(
            initialContext: flowState.measurementContext,
            isInAppEdit: onComplete != nil
        ))
    }

    private var selectedScene: ContextScene { mokorin.selectedScene }
    private var selectedConditions: Set<BodyCondition> { mokorin.selectedConditions }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LaunchStarfieldBG()
                .ignoresSafeArea()

            // スクロールコンテンツ。CTAはsafeAreaInsetで分離し、タップ干渉を完全に防ぐ。
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        header
                            .padding(.top, 54)
                        mokorinSection
                        confirmationCard
                        sceneSection
                        bodySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: mokorin.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(conversationBottomID, anchor: .bottom) }
                }
            }
            #if DEBUG
            .task { await runMokorinDebugHooks() }
            #endif
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
            mokorin.selectScene(scene)
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
                if mokorin.suggestedScene == scene { suggestionBadge(onSelected: selected) }
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

            // 会話の「身体状態」の段階では、選び終えたらもこりんに伝える
            if mokorin.step == .condition {
                Button {
                    mokorin.confirmConditions()
                } label: {
                    Text("身体状態はこれで決定")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mokorin_confirm_conditions")
            }
        }
    }

    private func conditionRow(_ cond: BodyCondition) -> some View {
        let selected = selectedConditions.contains(cond)
        return Button {
            // 「特になし」の排他を含む選択規則は MokorinContextViewModel.toggleCondition（従来と同じ規則）
            mokorin.toggleCondition(cond)
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
                if mokorin.suggestedConditions.contains(cond) && selected { suggestionBadge(onSelected: false) }
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
                mokorinInputRow

                // 測定する内容を、ボタンの直前に常に表示する（小さい画面で確認エリアが隠れても分かるように）
                Text("場面：\(selectedScene.displayName)　身体状態：\(BodyCondition.allCases.filter { selectedConditions.contains($0) }.map(\.displayName).joined(separator: " / "))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(mokorin.step == .review ? 0.85 : 0.45))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("mokorin_summary_line")

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
                    if let onComplete {
                        // メインアプリ内：現在のコンテキストを変更せずに閉じる
                        print("[Navigation] context edit cancelled (in-app)")
                        onComplete()
                        return
                    }
                    flowState.measurementContext = .default
                    flowState.authStatus = .mainApp
                    print("[Navigation] context skipped -> mainApp")
                } label: {
                    Text(isInAppEdit ? "変更しない" : "あとで選ぶ")
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
                // 入力欄を追加して高くなったため、後ろのボタンが透けないよう不透明度を上げている（旧 0.90）
                Color.black.opacity(0.97)
                LinearGradient(
                    colors: [Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.0),
                             Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.80)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - もこりんとの会話

    private var mokorinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                // 友達が作成したもこりん（WKWebView）。表情・動作は会話に合わせて MokorinContextViewModel が決める
                MokorinAvatarView(size: 84, pose: mokorin.pose)
                VStack(alignment: .leading, spacing: 2) {
                    Text("もこりん")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text(mokorin.usesRemoteAI ? "外部AI（サーバー経由）で会話中" : "端末内の定型文で案内中")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
                if mokorin.messages.count > 1 {
                    Button("やり直す") { mokorin.restart() }
                        .font(.system(size: 11))
                        .foregroundStyle(accent.opacity(0.8))
                        .accessibilityIdentifier("mokorin_restart")
                }
            }

            ForEach(mokorin.messages) { message in
                MokorinBubble(message: message, accent: accent)
            }
            if mokorin.isSending {
                HStack(spacing: 6) {
                    ProgressView().tint(accent)
                    Text("もこりんが考え中…").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
                }
                .accessibilityElement(children: .combine)
            }
            if let notice = mokorin.notice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mokorin.isServerConfigured && !mokorin.isTextConsented {
                consentRow
            }
            Color.clear.frame(height: 1).id(conversationBottomID)
        }
    }

    private var consentRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("もこりんとの会話に外部AI（OpenAI）を使うと、入力した文章だけをサーバー経由で送ります。心拍などの計測データは送りません。")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            Button("外部AIを使う（同意する）") { mokorin.setTextConsent(true) }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent)
                .accessibilityIdentifier("mokorin_consent_accept")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    /// 選択結果の確認エリア（ここに表示された内容で測定する）
    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("確認", hint: mokorin.step == .review ? "この内容で測定できます" : "会話やボタンで選ぶと更新されます")
            confirmationRow(title: "場面",
                            value: mokorin.hasSceneAnswer ? selectedScene.displayName : "\(selectedScene.displayName)（未回答・初期値）",
                            suggested: mokorin.suggestedScene != nil)
            confirmationRow(title: "身体状態",
                            value: BodyCondition.allCases.filter { selectedConditions.contains($0) }.map(\.displayName).joined(separator: " / ")
                                + (mokorin.hasConditionAnswer ? "" : "（未回答・初期値）"),
                            suggested: !mokorin.suggestedConditions.isEmpty)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(mokorin.step == .review ? 0.09 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(mokorin.step == .review ? 0.5 : 0.15), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mokorin_confirmation_card")
    }

    private func confirmationRow(title: String, value: String, suggested: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if suggested {
                Text("もこりんの提案・変更できます")
                    .font(.system(size: 9))
                    .foregroundStyle(accent.opacity(0.85))
            }
        }
    }

    private func suggestionBadge(onSelected: Bool) -> some View {
        Text("提案")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(onSelected ? Color.black.opacity(0.7) : accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().strokeBorder(onSelected ? Color.black.opacity(0.4) : accent.opacity(0.6), lineWidth: 0.8))
            .accessibilityLabel("もこりんの提案")
    }

    /// 自由入力欄（キーボード表示中も safeAreaInset で入力欄と送信ボタンが上に移動する）
    private var mokorinInputRow: some View {
        HStack(spacing: 8) {
            TextField("もこりんに状況を伝える", text: $mokorin.draft, axis: .vertical)
                .lineLimit(1...3)
                .focused($isInputFocused)
                .font(.system(size: 14))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .onChange(of: mokorin.draft) { _, v in
                    if v.count > ContextAssistLimits.maxUserChars { mokorin.draft = String(v.prefix(ContextAssistLimits.maxUserChars)) }
                }
                .submitLabel(.send)
                .onSubmit { mokorin.send() }
                .accessibilityLabel("もこりんへの返答")
                .accessibilityIdentifier("mokorin_input_field")
            Button {
                mokorin.send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(mokorin.canSend ? accent : Color.white.opacity(0.2))
            }
            .buttonStyle(.plain)
            .disabled(!mokorin.canSend)
            .accessibilityLabel("送信")
            .accessibilityIdentifier("mokorin_send_button")
        }
    }

    #if DEBUG
    /// シミュレーター検証用（DEBUG のみ）: MW_CHAT_TEST_CONSENT=1|0、MW_MOKORIN_AUTOPLAY="文1||文2"（画面表示後に順番に送信）、
    /// MW_MOKORIN_AUTO_CONFIRM=1（送信後に applyAndProceed() を呼ぶ）
    private func runMokorinDebugHooks() async {
        let env = ProcessInfo.processInfo.environment
        if env["MW_CHAT_TEST_CONSENT"] == "1" { mokorin.setTextConsent(true) }
        if env["MW_CHAT_TEST_CONSENT"] == "0" { mokorin.setTextConsent(false) }
        guard let script = env["MW_MOKORIN_AUTOPLAY"], mokorin.messages.count == 1 else { return }
        for line in script.components(separatedBy: "||") where !line.isEmpty {
            try? await Task.sleep(for: .seconds(1))
            await mokorin.submit(line)
        }
        // MW_MOKORIN_AUTO_CONFIRM=1: 利用者が「この状況で測定する」を押した場合と同じ既存処理を呼ぶ（検証用）
        if env["MW_MOKORIN_AUTO_CONFIRM"] == "1" {
            try? await Task.sleep(for: .seconds(2))
            applyAndProceed()
        }
    }
    #endif

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
        // 利用者が確認した選択（もこりんの提案を含む）を既存の MeasurementContext として保存する
        let ctx = mokorin.measurementContext
        flowState.measurementContext = ctx
        if let onComplete {
            // メインアプリ内：authStatus は mainApp のまま。MainTabView が onChange で ViewModel へ反映する
            print("[Navigation] context updated in-app: scene=\(selectedScene.rawValue)")
            onComplete()
            return
        }
        flowState.authStatus = .mainApp
        print("[Navigation] context set: scene=\(ctx.scene.rawValue) conditions=\(ctx.conditions.map(\.rawValue).sorted()) -> mainApp")
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
