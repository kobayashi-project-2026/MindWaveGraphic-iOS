// MokorinWebView.swift
// Mokorin
//
// 友達が作成したもこりん（HTML/CSS/JavaScript）を WKWebView で表示し、SwiftUI から表情・動作・セリフを制御する。
// 表示するのは統合先のコピー（Mokorin/Web/mokorin.html・.css・.js）。原本は third_party/mokorin_friend_source（改変なし）。
//
// 安全のための制限:
// - 読み込むのはアプリに同梱したローカルファイルだけ。外部ページへの移動はすべて拒否する
// - JavaScript へ渡すのは enum の許可値と、JSON で文字列化したセリフだけ（任意のコードを組み立てない）
// - アプリ側で受け取るメッセージは「準備完了」だけ

import SwiftUI
import WebKit

/// もこりんの表情（原本 script.js の許可値と同じ）
nonisolated enum MokorinEmotion: String, CaseIterable, Codable, Sendable {
    case happy, calm, sad, sleepy
}

/// もこりんの動作（原本 script.js の許可値と同じ）
nonisolated enum MokorinAction: String, CaseIterable, Codable, Sendable {
    case wave, jump, nod
}

/// SwiftUI から渡すもこりんの状態。actionID を増やすと同じ動作をもう一度再生する
nonisolated struct MokorinPose: Equatable, Sendable {
    var emotion: MokorinEmotion = .calm
    var action: MokorinAction? = nil
    var actionID: Int = 0
    /// セリフ（showsDialogue のときだけキャラクターの吹き出しに表示）
    var dialogue: String? = nil

    /// 表情を変え、動作を1回再生した新しい状態
    func with(_ emotion: MokorinEmotion, _ action: MokorinAction?) -> MokorinPose {
        var next = self
        next.emotion = emotion
        if let action {
            next.action = action
            next.actionID += 1
        }
        return next
    }
}

/// JavaScript 呼び出し文の組み立て（テスト可能にするため分離）
nonisolated enum MokorinWebScript {
    static func setEmotion(_ e: MokorinEmotion) -> String { "setEmotion('\(e.rawValue)')" }
    static func setAction(_ a: MokorinAction) -> String { "setAction('\(a.rawValue)')" }

    /// セリフは JSON 文字列リテラルにして渡す（引用符・改行・HTML を含んでもコードとして解釈されない）
    static func setDialogue(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        let literal = String(array.dropFirst().dropLast())
        return "setDialogue(\(literal))"
    }

    static let showDialogue = "document.body.classList.add('show-dialogue')"
}

struct MokorinWebView: UIViewRepresentable {
    var pose: MokorinPose
    /// キャラクター自身の吹き出しにセリフを表示するか（既定は非表示。会話は SwiftUI の吹き出しで表示する）
    var showsDialogue: Bool = false

    /// 同梱した HTML（ない場合は nil → 呼び出し側で代替表示）
    static var resourceURL: URL? { Bundle.main.url(forResource: "mokorin", withExtension: "html") }

    func makeCoordinator() -> Coordinator { Coordinator(showsDialogue: showsDialogue) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptMessageHandler(context.coordinator), name: "mokorin")
        config.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        // キャラクターは表示専用（タップは SwiftUI 側のボタンで扱う）
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.accessibilityElementsHidden = true
        context.coordinator.webView = webView
        context.coordinator.pending = pose
        if let url = Self.resourceURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.apply(pose)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mokorin")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pending: MokorinPose
        private var isReady = false
        private var applied: MokorinPose? = nil
        private let showsDialogue: Bool

        init(showsDialogue: Bool) {
            self.showsDialogue = showsDialogue
            self.pending = MokorinPose()
        }

        /// 準備前は最後の状態だけ覚えておき、準備完了後にまとめて反映する
        func apply(_ pose: MokorinPose) {
            pending = pose
            guard isReady, let webView else { return }
            var scripts: [String] = []
            if applied?.emotion != pose.emotion { scripts.append(MokorinWebScript.setEmotion(pose.emotion)) }
            if let action = pose.action, applied?.actionID != pose.actionID { scripts.append(MokorinWebScript.setAction(action)) }
            if showsDialogue, applied?.dialogue != pose.dialogue { scripts.append(MokorinWebScript.setDialogue(pose.dialogue ?? "")) }
            applied = pose
            guard !scripts.isEmpty else { return }
            webView.evaluateJavaScript(scripts.joined(separator: ";")) { _, error in
                if error != nil { MindWaveDebugLogger.log(.error, "[Mokorin] web script failed") }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mokorin", (message.body as? [String: Any])?["type"] as? String == "ready" else { return }
            isReady = true
            if showsDialogue { webView?.evaluateJavaScript(MokorinWebScript.showDialogue) }
            applied = nil
            apply(pending)
        }

        /// 同梱ファイル以外への移動は拒否する
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, url.isFileURL,
                  let base = MokorinWebView.resourceURL?.deletingLastPathComponent(),
                  url.standardizedFileURL.path.hasPrefix(base.standardizedFileURL.path) else {
                MindWaveDebugLogger.log(.error, "[Mokorin] blocked navigation")
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// WKUserContentController が Coordinator を強参照して解放されなくなるのを防ぐ
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
