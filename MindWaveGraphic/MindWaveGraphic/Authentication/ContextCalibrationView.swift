// ContextCalibrationView.swift
// Authentication
//
// 測定前コンテキスト選択・状況確認画面（STEP 1〜3）
// ・もこりんを大きく表示し、挨拶と設問を1つの「もこりんの吹き出し」に統合
// ・選択肢をタップすると、もこりんのリアクションを表示したあと自動で次の設問へ進行
// ・STEP 1〜3の回答・自由相談の内容を flowState.measurementContext に保存し、
//   その後の測定や AI 相談画面（AIChatView）でも状況を記憶・引き継ぎ

import SwiftUI

// MARK: - 質問データモデル

private struct CalibrationQuestion {
    let prompt: String
    let options: [String]
    let responses: [String]
}

// MARK: - 吹き出し用しっぽシェイプ

private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 10, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 10, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - メイン画面（対話・状況確認画面）

struct ContextCalibrationView: View {
    var flowState: AppFlowState
    var onComplete: (() -> Void)? = nil

    // 現在のSTEP：1（身体の状態）〜 3（サポート選択）
    @State private var currentStep = 1

    // 質問の進行状況
    @State private var questionIndex = 0
    @State private var selectedAnswer: Int? = nil

    // 自動遷移タスク（連打・戻る操作時のキャンセル用）
    @State private var autoAdvanceTask: Task<Void, Never>? = nil

    // 回答インデックスとテキストの保存
    @State private var step1Indices: [Int] = []
    @State private var step2Indices: [Int] = []
    @State private var step1Answers: [String] = []
    @State private var step2Answers: [String] = []

    // STEP3で選んだサポート
    @State private var selectedSupport: Int? = nil

    // 本物の MokorinAvatarView 用のポーズ状態
    @State private var mascotPose = MokorinPose().with(.calm, .wave)

    // 自由相談（テキスト入力＆音声）
    @State private var consultText: String = ""
    @State private var consultHistory: [String] = []
    @State private var consultResponse: String? = nil
    @StateObject private var voice = MokorinVoiceController()
    @FocusState private var isConsultFocused: Bool

    // STEP1：身体の状態（挨拶と設問を統合したもこりんのセリフ）
    private let step1Questions: [CalibrationQuestion] = [
        CalibrationQuestion(
            prompt: "こんにちは！今日もおつかれさま！\nまずは身体の状態から…昨日はどのくらい眠れた？",
            options: ["3時間未満", "3〜5時間", "5〜7時間", "7〜9時間", "9時間以上", "あまり覚えていない"],
            responses: [
                "そっか、かなり睡眠時間が少なかったんだね。今日は疲れを感じやすいかもしれないね。",
                "少し睡眠が足りなかったかもしれないね。今日は無理しすぎないようにしよう！",
                "なるほど！睡眠時間はそのくらいだったんだね。起きたときはスッキリしてた？",
                "しっかり眠れたんだね！朝は気持ちよく起きられた？",
                "結構長く眠れたんだね！疲れがたまっていたのかな？",
                "そっか、正確には覚えていないんだね！大丈夫だよ。"
            ]
        ),
        CalibrationQuestion(
            prompt: "今日はどのくらい体を動かしたかな？",
            options: ["ランニングや運動をした", "散歩など軽く体を動かした", "普段通りに生活した", "ほとんど動いていない"],
            responses: [
                "おお！今日は体を動かしたんだね！運動した後って体の状態も変わるよね。",
                "少し体を動かしたんだね！いいね！",
                "なるほど！今日はいつも通りの一日だったんだね。",
                "そっか、今日はゆっくり過ごしていたんだね！"
            ]
        ),
        CalibrationQuestion(
            prompt: "今の体調はどうかな？無理せず教えてね。",
            options: ["元気！", "少し疲れている", "かなり疲れている", "体がだるい", "体調が悪い"],
            responses: [
                "いいね！今日は調子がよさそうだね！",
                "少し疲れがあるんだね。今の体調も大切にしながら進めていこう！",
                "結構疲れがたまっているんだね。無理せず自分のペースでいこうね。",
                "体がだるいんだね。少し休める時間があるといいね。",
                "そっか、体調がよくないんだね。まずは体を大切にしてね。無理に何かを試さなくても大丈夫だよ。"
            ]
        )
    ]

    // STEP2：今の状況（挨拶と設問を統合したもこりんのセリフ）
    private let step2Questions: [CalibrationQuestion] = [
        CalibrationQuestion(
            prompt: "身体の状態を教えてくれてありがとう！\n次は今の状況について…これからどんな予定がある？",
            options: ["面接・就職活動", "学校の発表・プレゼン", "人と会う予定", "大切な予定がある", "特に決まっていない"],
            responses: [
                "面接や就職活動があるんだね！大切な場面だから、少し緊張することもあるよね。",
                "発表やプレゼンがあるんだね！伝えたいことを落ち着いて話せるように準備しよう！",
                "誰かと会う予定があるんだね！どんな気持ちでいるのか、もう少し聞かせてね。",
                "大切な予定があるんだね。自分のペースで過ごせるように一緒に考えよう！",
                "そっか！特に決まっていなくても大丈夫だよ。今の気持ちを大切にしようね。"
            ]
        ),
        CalibrationQuestion(
            prompt: "その予定について、今どんな気持ち？",
            options: ["楽しみ！", "少し緊張している", "かなり不安", "楽しみだけど不安もある", "よく分からない"],
            responses: [
                "楽しみにしているんだね！その気持ちを大切にしていこう！",
                "少し緊張しているんだね。自然なことだから大丈夫だよ。",
                "かなり不安なんだね。無理に前向きにならなくてもいいよ。ゆっくり整理していこう。",
                "楽しみな気持ちと不安な気持ち、両方あるんだね。どちらも大切な気持ちだよ。",
                "自分でも気持ちが分からないことってあるよね。一緒に見つけていこう！"
            ]
        ),
        CalibrationQuestion(
            prompt: "今、一番気になっていることは何かな？",
            options: ["失敗しそうで不安", "うまく話せるか心配", "周りの目が気になる", "結果が気になる", "理由は分からない", "特にない"],
            responses: [
                "失敗することが気になっているんだね。失敗だけでなく、できていることにも目を向けてみよう！",
                "うまく話せるか心配なんだね。完璧に話そうとしなくても大丈夫だよ。",
                "周りの目が気になるんだね。自分が伝えたいことを大切にしてみよう。",
                "結果が気になるんだね。今できることに少しずつ集中していこう！",
                "理由が分からない不安もあるよね。まずは気持ちをそのまま受け止めてみよう。",
                "今は特に気になることはないんだね！いい状態で過ごせるといいね。"
            ]
        )
    ]

    private var activeQuestions: [CalibrationQuestion] {
        currentStep == 1 ? step1Questions : step2Questions
    }

    private let supportOptions = [
        "深呼吸でリラックスする",
        "不安な気持ちを整理する",
        "気分転換をする",
        "自分に自信をつける"
    ]

    private let supportDescriptions = [
        "ゆっくり息を吸って、ゆっくり吐いてみよう。呼吸に意識を向けることで、少し落ち着く時間をつくろう。",
        "今感じている不安を一つずつ整理してみよう。何が気になっているのか、言葉にするだけでも大丈夫だよ。",
        "好きな音楽を聴いたり、少し体を動かしたりして、いったん気持ちを切り替えてみよう。",
        "これまで頑張ってきたことや、自分ができていることを思い出してみよう。自分の良いところにも目を向けてみてね。"
    ]

    /// もこりんの吹き出しに表示する統合セリフ（挨拶＋設問／リアクション）
    private var speechBubbleText: String {
        if voice.isListening {
            let partial = voice.partialTranscript
            return partial.isEmpty ? "聴いているよ…そのまま話してね" : partial
        }
        if let problem = voice.problem {
            return problem
        }
        if let consultResponse {
            return consultResponse
        }
        if currentStep <= 2 {
            if questionIndex < activeQuestions.count {
                if let answer = selectedAnswer {
                    return activeQuestions[questionIndex].responses[answer]
                }
                return activeQuestions[questionIndex].prompt
            } else {
                return currentStep == 1
                    ? "身体の状態を教えてくれてありがとう！\n次は今の状況について聞かせてね。"
                    : "今の状況や気持ちを教えてくれてありがとう！\n次は一緒にぴったりなサポートを選ぼう！"
            }
        } else {
            if let selected = selectedSupport {
                return supportDescriptions[selected]
            }
            return "今の自分に合いそうなサポートを選んでね！\n下の欄から直接話しかけてくれても大丈夫だよ。"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.025, blue: 0.12),
                    Color(red: 0.06, green: 0.04, blue: 0.25),
                    Color(red: 0.12, green: 0.07, blue: 0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ▼ 1. 画面上部固定：コンパクトヘッダー ＋ 大きなもこりん ＋ 統合吹き出し ＋ 進行バー
                VStack(spacing: 6) {
                    header
                    fixedMascotSpeechArea
                    progressSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 8)

                // ▼ 2. 中央スクロール領域：選択肢カードのみ（タップで自動進行）
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            Color.clear
                                .frame(height: 1)
                                .id("top")

                            if currentStep <= 2 {
                                questionOptionsSection
                            } else {
                                supportOptionsSection
                            }

                            Color.clear
                                .frame(height: 12)
                                .id("bottom")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: currentStep) { _ in
                        consultResponse = nil
                        updateMascotPose()
                        withAnimation(.easeInOut) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                    .onChange(of: questionIndex) { _ in
                        consultResponse = nil
                        updateMascotPose()
                        withAnimation(.easeInOut) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }

                // ▼ 3. 画面下部固定：相談テキスト入力 ＋ 音声マイクバー
                consultBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            voice.onUtterance = { spokenText in
                processConsultation(spokenText)
            }
            voice.onSpeakingChanged = { speaking in
                var next = mascotPose
                next.speaking = speaking
                mascotPose = next
            }
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
            voice.cancelAll()
        }
    }

    // MARK: - ヘッダー（省スペース化）

    private var header: some View {
        HStack(spacing: 8) {
            if currentStep == 1 && questionIndex == 0 && onComplete != nil {
                Button {
                    autoAdvanceTask?.cancel()
                    saveContextToFlowState()
                    voice.cancelAll()
                    onComplete?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("閉じる")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.14)))
                }
            } else {
                Button {
                    handleBackNavigation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.14)))
                }
            }

            Spacer()

            Text("MindWave")
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .cyan, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Spacer()

            // 音声読み上げON/OFF切替
            Button {
                voice.speaksReplies.toggle()
                if !voice.speaksReplies { voice.stopSpeaking() }
            } label: {
                Image(systemName: voice.speaksReplies ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(voice.speaksReplies ? .cyan : .white.opacity(0.6))
                    .padding(7)
                    .background(Circle().fill(.white.opacity(0.12)))
            }

            Button {
                completeCalibrationAndProceed()
            } label: {
                Text("スキップ")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
        }
    }

    // MARK: - 大きなもこりん＆しっぽ付き吹き出し（挨拶＋設問を統合）

    private var fixedMascotSpeechArea: some View {
        VStack(spacing: 0) {
            // もこりんを大きく主役表示
            MokorinAvatarView(size: 185, pose: mascotPose)
                .frame(width: 185, height: 170)

            // もこりんの口元へ向かう吹き出しのしっぽ
            SpeechBubbleTail()
                .fill(
                    (selectedAnswer != nil || consultResponse != nil || voice.isListening)
                    ? Color.cyan.opacity(0.18)
                    : Color.white.opacity(0.12)
                )
                .frame(width: 22, height: 10)
                .overlay(
                    SpeechBubbleTail()
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                )
                .zIndex(1)
                .offset(y: 1)

            // 吹き出し本体（挨拶と設問を統合）
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("もこりん")
                        .font(.caption2.bold())
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cyan.opacity(0.18)))

                    Spacer()

                    Text(stepCategoryBadge)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Text(speechBubbleText)
                    .font(.callout.weight(.medium))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                (selectedAnswer != nil || consultResponse != nil || voice.isListening)
                ? Color.cyan.opacity(0.16)
                : Color.white.opacity(0.11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.cyan.opacity(0.45), lineWidth: 1.2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var stepCategoryBadge: String {
        switch currentStep {
        case 1: return "身体の状態"
        case 2: return "今の状況"
        default: return "サポート選択"
        }
    }

    // MARK: - STEP進行状況バー

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("STEP \(currentStep) / 3")
                    .bold()

                Spacer()

                if currentStep <= 2 {
                    Text("\(min(questionIndex + 1, activeQuestions.count)) / \(activeQuestions.count)")
                } else {
                    Text("最終ステップ")
                }
            }
            .font(.caption2)
            .foregroundStyle(.cyan)

            GeometryReader { geometry in
                let progress: CGFloat = currentStep <= 2
                    ? CGFloat(min(questionIndex + 1, activeQuestions.count)) / CGFloat(activeQuestions.count)
                    : 1.0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)
        }
        .padding(.top, 2)
    }

    // MARK: - STEP1・STEP2 選択肢のみ（タップで自動進行）

    private var questionOptionsSection: some View {
        Group {
            if questionIndex < activeQuestions.count {
                VStack(spacing: 10) {
                    ForEach(activeQuestions[questionIndex].options.indices, id: \.self) { index in
                        Button {
                            selectOptionAndAutoAdvance(index)
                        } label: {
                            HStack {
                                Text(activeQuestions[questionIndex].options[index])
                                    .multilineTextAlignment(.leading)

                                Spacer()

                                Image(
                                    systemName: selectedAnswer == index
                                    ? "checkmark.circle.fill"
                                    : "circle"
                                )
                                .foregroundStyle(selectedAnswer == index ? .cyan : .white.opacity(0.55))
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .frame(maxWidth: .infinity)
                            .background(
                                selectedAnswer == index
                                ? Color.purple.opacity(0.42)
                                : Color.white.opacity(0.08)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        selectedAnswer == index
                                        ? Color.cyan
                                        : Color.white.opacity(0.18),
                                        lineWidth: 1
                                    )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 選択肢をタップした瞬間にリアクションを表示し、1.6秒後に自動で次の設問（または次のSTEP）へ進む
    private func selectOptionAndAutoAdvance(_ index: Int) {
        guard questionIndex < activeQuestions.count else { return }

        autoAdvanceTask?.cancel()
        consultResponse = nil

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedAnswer = index
        }
        updateMascotPose()
        voice.speakReply(activeQuestions[questionIndex].responses[index])

        autoAdvanceTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                advanceToNextQuestionOrStep()
            }
        }
    }

    private func advanceToNextQuestionOrStep() {
        guard let answer = selectedAnswer, questionIndex < activeQuestions.count else { return }
        let answerText = activeQuestions[questionIndex].options[answer]

        if currentStep == 1 {
            if step1Indices.count > questionIndex {
                step1Indices[questionIndex] = answer
                step1Answers[questionIndex] = answerText
            } else {
                step1Indices.append(answer)
                step1Answers.append(answerText)
            }
        } else {
            if step2Indices.count > questionIndex {
                step2Indices[questionIndex] = answer
                step2Answers[questionIndex] = answerText
            } else {
                step2Indices.append(answer)
                step2Answers.append(answerText)
            }
        }

        saveContextToFlowState()

        withAnimation(.easeInOut(duration: 0.25)) {
            if questionIndex + 1 < activeQuestions.count {
                questionIndex += 1
                selectedAnswer = nil
            } else if currentStep == 1 {
                currentStep = 2
                questionIndex = 0
                selectedAnswer = nil
            } else {
                currentStep = 3
                questionIndex = 0
                selectedAnswer = nil
            }
        }
    }

    // MARK: - STEP3 サポート選択肢のみ（タップで自動完了）

    private var supportOptionsSection: some View {
        VStack(spacing: 10) {
            ForEach(supportOptions.indices, id: \.self) { index in
                Button {
                    selectSupportAndAutoComplete(index)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: supportIcon(for: index))
                            .font(.body)
                            .foregroundStyle(.cyan)
                            .frame(width: 28)

                        Text(supportOptions[index])
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        Image(
                            systemName: selectedSupport == index
                            ? "checkmark.circle.fill"
                            : "circle"
                        )
                        .foregroundStyle(selectedSupport == index ? .cyan : .white.opacity(0.55))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(
                        selectedSupport == index
                        ? Color.purple.opacity(0.38)
                        : Color.white.opacity(0.08)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                selectedSupport == index ? Color.cyan : Color.white.opacity(0.18),
                                lineWidth: 1
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// STEP3のサポートを選んだら即座にもこりんの解説を表示し、1.8秒後に自動で計測画面へ進む
    private func selectSupportAndAutoComplete(_ index: Int) {
        autoAdvanceTask?.cancel()
        consultResponse = nil

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSupport = index
        }
        updateMascotPose()
        voice.speakReply(supportDescriptions[index])

        autoAdvanceTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                completeCalibrationAndProceed()
            }
        }
    }

    // MARK: - 下部固定：自由相談＆音声入力バー

    private var consultBar: some View {
        HStack(spacing: 8) {
            // 音声マイク入力ボタン
            Button {
                Task { await voice.micTapped() }
            } label: {
                Image(systemName: voice.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(voice.isListening ? .black : .cyan)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(voice.isListening ? Color.cyan : Color.white.opacity(0.14)))
            }

            TextField("もこりんに相談する・話しかける…", text: $consultText)
                .focused($isConsultFocused)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.10)))
                .onSubmit {
                    sendConsultation()
                }

            Button {
                sendConsultation()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        consultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .white.opacity(0.25)
                        : .cyan
                    )
            }
            .disabled(consultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
    }

    private func sendConsultation() {
        let trimmed = consultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        consultText = ""
        isConsultFocused = false
        processConsultation(trimmed)
    }

    private func processConsultation(_ text: String) {
        consultHistory.append(text)
        saveContextToFlowState()

        let reply: String
        if text.contains("眠") || text.contains("寝") || text.contains("疲") || text.contains("だる") {
            reply = "「\(text)」なんだね。無理しすぎなくて大丈夫だよ。今日はゆっくり深呼吸しながら自分のペースでいこうね。"
            mascotPose = mascotPose.with(.sleepy, .nod)
        } else if text.contains("緊張") || text.contains("不安") || text.contains("怖") || text.contains("面接") || text.contains("発表") {
            reply = "「\(text)」って感じているんだね。大切な場面だからこそ緊張するよね。もこりんがそばにいるから大丈夫だよ！"
            mascotPose = mascotPose.with(.sad, .wave)
        } else if text.contains("楽し") || text.contains("嬉") || text.contains("元気") {
            reply = "「\(text)」なんだね！その前向きな気持ち、とっても素敵だね！"
            mascotPose = mascotPose.with(.happy, .jump)
        } else {
            reply = "「\(text)」って教えてくれてありがとう！その気持ちも大切にもこりんが覚えておくね。"
            mascotPose = mascotPose.with(.happy, .nod)
        }

        withAnimation(.easeInOut) {
            consultResponse = reply
        }
        voice.speakReply(reply)
    }

    // MARK: - もこりんポーズ更新 & 進行制御

    private func updateMascotPose() {
        if currentStep == 3 {
            mascotPose = selectedSupport != nil
                ? mascotPose.with(.happy, .jump)
                : mascotPose.with(.happy, .wave)
            return
        }

        guard let answer = selectedAnswer else {
            mascotPose = mascotPose.with(.calm, .wave)
            return
        }

        let emotion: MokorinEmotion
        if currentStep == 1 && questionIndex == 0 {
            emotion = answer <= 1 ? .sleepy : (answer == 3 || answer == 4 ? .happy : .calm)
        } else if currentStep == 1 && questionIndex == 2 {
            emotion = answer == 0 ? .happy : (answer == 4 ? .sad : .calm)
        } else if currentStep == 2 && questionIndex == 1 {
            emotion = answer == 2 ? .sad : (answer == 0 ? .happy : .calm)
        } else {
            emotion = .calm
        }

        let action: MokorinAction = answer == 0 ? .jump : .nod
        mascotPose = mascotPose.with(emotion, action)
    }

    private func supportIcon(for index: Int) -> String {
        switch index {
        case 0: return "wind"
        case 1: return "bubble.left.and.bubble.right"
        case 2: return "music.note"
        default: return "star"
        }
    }

    private func handleBackNavigation() {
        autoAdvanceTask?.cancel()
        withAnimation(.easeInOut) {
            if currentStep == 3 {
                currentStep = 2
                questionIndex = step2Questions.count - 1
                selectedAnswer = nil
                selectedSupport = nil
            } else if currentStep == 2 {
                if questionIndex > 0 {
                    questionIndex -= 1
                    selectedAnswer = nil
                } else {
                    currentStep = 1
                    questionIndex = step1Questions.count - 1
                    selectedAnswer = nil
                }
            } else {
                if questionIndex > 0 {
                    questionIndex -= 1
                    selectedAnswer = nil
                } else if let onComplete {
                    saveContextToFlowState()
                    voice.cancelAll()
                    onComplete()
                } else {
                    saveContextToFlowState()
                    voice.cancelAll()
                    flowState.authStatus = .accountGuidance
                }
            }
        }
    }

    private func completeCalibrationAndProceed() {
        autoAdvanceTask?.cancel()
        saveContextToFlowState()
        voice.cancelAll()
        if let onComplete {
            onComplete()
        } else {
            flowState.authStatus = .mainApp
        }
    }

    /// STEP 1〜2の回答および自由相談の内容を AppFlowState.measurementContext に保存し、
    /// メイン画面の測定・AI相談画面（AIChatView）へ状況を引き継ぐ
    private func saveContextToFlowState() {
        var scene: ContextScene = .calm
        var conditions: Set<BodyCondition> = []

        // 1. STEP1（身体の状態）からの反映
        if let sleepIdx = step1Indices.first, (sleepIdx == 0 || sleepIdx == 1) {
            conditions.insert(.sleepLack)
        }
        if step1Indices.count >= 2 {
            let moveIdx = step1Indices[1]
            if moveIdx == 0 {
                conditions.insert(.running)
            } else if moveIdx == 1 {
                conditions.insert(.stairs)
            }
        }

        // 2. STEP2（今の状況）からの反映
        if let sceneIdx = step2Indices.first {
            switch sceneIdx {
            case 0, 1: scene = .interview
            case 2, 3: scene = .important
            default:   scene = .calm
            }
        }

        // 3. 自由相談・音声発話のキーワードも反映
        for text in consultHistory {
            let local = MokorinKeywordInterpreter.interpret(text)
            if let detectedScene = local.scene {
                scene = detectedScene
            }
            for cond in local.conditions where cond != .none {
                conditions.insert(cond)
            }
        }

        var ctx = MeasurementContext()
        ctx.scene = scene
        ctx.conditions = conditions.isEmpty ? [.none] : conditions
        flowState.measurementContext = ctx
    }
}

// MARK: - 共通星空背景（スプラッシュ・タイトル・ギャラリー等で参照）

struct LaunchStarfieldBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.025, blue: 0.12),
                    Color(red: 0.06, green: 0.04, blue: 0.25),
                    Color(red: 0.12, green: 0.07, blue: 0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geo in
                ForEach(0..<45, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(i % 3 == 0 ? 0.85 : 0.35))
                        .frame(width: i % 4 == 0 ? 2.5 : 1.5, height: i % 4 == 0 ? 2.5 : 1.5)
                        .position(
                            x: geo.size.width * CGFloat((i * 37) % 97) / 100.0,
                            y: geo.size.height * CGFloat((i * 61) % 97) / 100.0
                        )
                }
            }
        }
    }
}

#Preview {
    ContextCalibrationView(flowState: AppFlowState())
}
