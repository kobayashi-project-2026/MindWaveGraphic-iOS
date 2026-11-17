// ContextCalibrationView.swift
// Authentication
//
// 測定前コンテキスト選択・状況確認画面（STEP 1〜3）

import SwiftUI

// MARK: - 質問データモデル

private struct CalibrationQuestion {
    let title: String
    let options: [String]
    let responses: [String]
}

// MARK: - メイン画面（状況確認画面）

struct ContextCalibrationView: View {
    var flowState: AppFlowState
    var onComplete: (() -> Void)? = nil

    // 現在のSTEP：1（身体の状態）〜 3（サポート選択）
    @State private var currentStep = 1

    // 質問の進行状況
    @State private var questionIndex = 0
    @State private var selectedAnswer: Int? = nil

    // 回答の保存
    @State private var step1Answers: [String] = []
    @State private var step2Answers: [String] = []

    // STEP3で選んだサポート
    @State private var selectedSupport: Int? = nil

    // 既存の MokorinAvatarView 用のポーズ状態
    @State private var mascotPose = MokorinPose().with(.calm, .wave)

    // STEP1：身体の状態
    private let step1Questions: [CalibrationQuestion] = [
        CalibrationQuestion(
            title: "昨日はどのくらい眠れた？",
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
            title: "今日はどのくらい体を動かした？",
            options: ["ランニングや運動をした", "散歩など軽く体を動かした", "普段通りに生活した", "ほとんど動いていない"],
            responses: [
                "おお！今日は体を動かしたんだね！運動した後って体の状態も変わるよね。",
                "少し体を動かしたんだね！いいね！",
                "なるほど！今日はいつも通りの一日だったんだね。",
                "そっか、今日はゆっくり過ごしていたんだね！"
            ]
        ),
        CalibrationQuestion(
            title: "今の体調はどう？",
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

    // STEP2：今の状況
    private let step2Questions: [CalibrationQuestion] = [
        CalibrationQuestion(
            title: "これからどんなことをする予定？",
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
            title: "その予定について今どんな気持ち？",
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
            title: "今、一番気になっていることは？",
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

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        header

                        mascotArea

                        if currentStep <= 2 {
                            introductionBubble
                            progressSection
                            questionSection
                        } else {
                            supportSection
                        }

                        Color.clear
                            .frame(height: 20)
                            .id("bottom")
                    }
                    .padding(20)
                }
                .onChange(of: selectedAnswer) { _, newValue in
                    updateMascotPose()
                    if newValue != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                proxy.scrollTo("aiResponse", anchor: .center)
                            }
                        }
                    }
                }
                .onChange(of: currentStep) { _, _ in
                    updateMascotPose()
                    withAnimation(.easeInOut) {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
                .onChange(of: selectedSupport) { _, _ in
                    updateMascotPose()
                }
            }
        }
    }

    // MARK: ヘッダー

    private var header: some View {
        VStack(spacing: 5) {
            HStack {
                Button {
                    handleBackNavigation()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(8)
                }

                Spacer()

                Text("MindWave")
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .cyan, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Spacer()

                Button {
                    completeCalibrationAndProceed()
                } label: {
                    Text("スキップ")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.1)))
                }
            }

            Text("あなたの心に寄り添う時間")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 10)
        .id("top")
    }

    // MARK: もこりん表示（既存の本物 MokorinAvatarView をそのまま使用）

    private var mascotArea: some View {
        VStack(spacing: 5) {
            MokorinAvatarView(size: 165, pose: mascotPose)

            Text("もこりん")
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }

    // MARK: あいさつ

    private var introductionBubble: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("🌙")
                .font(.title2)

            Text(
                currentStep == 1
                ? "こんにちは！今日もおつかれさま！\nまずは今の身体の状態を一緒に確認してみよう！"
                : "身体の状態を教えてくれてありがとう！\n次は、今の状況や気持ちについて聞かせてね。"
            )
            .fixedSize(horizontal: false, vertical: true)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(.white)
        }
    }

    // MARK: STEP進行状況

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STEP \(currentStep) / 3")
                    .bold()

                Spacer()

                Text("\(min(questionIndex + 1, activeQuestions.count)) / \(activeQuestions.count)")
            }
            .font(.caption)
            .foregroundStyle(.cyan)

            GeometryReader { geometry in
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
                        .frame(
                            width: geometry.size.width
                                * CGFloat(min(questionIndex + 1, activeQuestions.count))
                                / CGFloat(activeQuestions.count)
                        )
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: STEP1・STEP2 質問画面

    private var questionSection: some View {
        Group {
            if questionIndex < activeQuestions.count {
                VStack(alignment: .leading, spacing: 15) {
                    Text(currentStep == 1 ? "身体の状態を知る" : "今の状況を知る")
                        .font(.headline)
                        .foregroundStyle(.cyan)

                    Text(activeQuestions[questionIndex].title)
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(activeQuestions[questionIndex].options.indices, id: \.self) { index in
                        Button {
                            withAnimation(.easeInOut) {
                                selectedAnswer = index
                            }
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
                            }
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(
                                selectedAnswer == index
                                ? Color.purple.opacity(0.4)
                                : Color.white.opacity(0.08)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(
                                        selectedAnswer == index
                                        ? Color.cyan
                                        : Color.white.opacity(0.2),
                                        lineWidth: 1
                                    )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 22))

                if let answer = selectedAnswer {
                    responseBubble(
                        text: activeQuestions[questionIndex].responses[answer]
                    )
                    .id("aiResponse")
                    .transition(.opacity)

                    Button {
                        moveToNextQuestion()
                    } label: {
                        HStack {
                            Text(questionIndex == activeQuestions.count - 1 ? "STEP \(currentStep) 完了" : "次の質問へ")
                            Image(systemName: "arrow.right")
                        }
                        .bold()
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .purple.opacity(0.5), radius: 12)
                    }
                }
            } else {
                stepCompletionSection
            }
        }
    }

    private func responseBubble(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("🌙")
                .font(.title2)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cyan.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var stepCompletionSection: some View {
        VStack(spacing: 18) {
            MokorinAvatarView(size: 165, pose: MokorinPose().with(.happy, .jump))

            Text("STEP \(currentStep) 完了！")
                .font(.title)
                .bold()
                .foregroundStyle(.cyan)

            Text(
                currentStep == 1
                ? "身体の状態を教えてくれてありがとう！次は今の状況について聞かせてね。"
                : "今の状況や気持ちを教えてくれてありがとう！次は、もこりんと一緒に自分に合ったサポートを選んでみよう！"
            )
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.easeInOut) {
                    if currentStep == 1 {
                        currentStep = 2
                        questionIndex = 0
                        selectedAnswer = nil
                    } else {
                        currentStep = 3
                        questionIndex = 0
                        selectedAnswer = nil
                    }
                }
            } label: {
                HStack {
                    Text("次へ進む")
                    Image(systemName: "arrow.right")
                }
                .bold()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .padding(.top, 10)
        }
        .padding(25)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    // MARK: STEP3 サポート選択

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("STEP 3 / 3")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.cyan)

                Text("もこりんからサポート")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)

                Text("今の自分に合いそうなサポートを選んでね！")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }

            ForEach(supportOptions.indices, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut) {
                        selectedSupport = index
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: supportIcon(for: index))
                            .font(.title2)
                            .foregroundStyle(.cyan)
                            .frame(width: 32)

                        Text(supportOptions[index])
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        Image(
                            systemName: selectedSupport == index
                            ? "checkmark.circle.fill"
                            : "circle"
                        )
                        .foregroundStyle(selectedSupport == index ? .cyan : .white.opacity(0.6))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(
                        selectedSupport == index
                        ? Color.purple.opacity(0.35)
                        : Color.white.opacity(0.08)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                selectedSupport == index ? Color.cyan : Color.white.opacity(0.2),
                                lineWidth: 1
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }

            if let selected = selectedSupport {
                responseBubble(text: supportDescriptions[selected])
                    .transition(.opacity)

                Button {
                    completeCalibrationAndProceed()
                } label: {
                    HStack {
                        Text("このサポートで計測をはじめる")
                        Image(systemName: "arrow.right")
                    }
                    .bold()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .purple.opacity(0.5), radius: 12)
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func supportIcon(for index: Int) -> String {
        switch index {
        case 0: return "wind"
        case 1: return "bubble.left.and.bubble.right"
        case 2: return "music.note"
        default: return "star"
        }
    }

    // MARK: もこりんポーズ更新 & 進行制御

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

    private func moveToNextQuestion() {
        guard let answer = selectedAnswer else { return }

        let answerText = activeQuestions[questionIndex].options[answer]

        if currentStep == 1 {
            step1Answers.append(answerText)
        } else {
            step2Answers.append(answerText)
        }

        withAnimation(.easeInOut) {
            questionIndex += 1
            selectedAnswer = nil
        }
    }

    private func handleBackNavigation() {
        withAnimation(.easeInOut) {
            if currentStep == 3 {
                currentStep = 2
                questionIndex = step2Questions.count - 1
                selectedAnswer = nil
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
                    onComplete()
                } else {
                    flowState.authStatus = .accountGuidance
                }
            }
        }
    }

    private func completeCalibrationAndProceed() {
        if let onComplete {
            onComplete()
        } else {
            flowState.authStatus = .mainApp
        }
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

// MARK: - プレビュー

#Preview {
    ContextCalibrationView(flowState: AppFlowState())
}
