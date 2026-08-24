import SwiftUI
import WebKit

struct WebNodeView: View {
    @Binding var node: CanvasNode
    @State private var address: String = ""
    @State private var searchProvider: WebSearchProvider = .google
    @StateObject private var browser = WebNavigator()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!browser.canGoBack)
                    .help("Voltar")
                    .accessibilityLabel("Página anterior")
                Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!browser.canGoForward)
                    .help("Avançar")
                    .accessibilityLabel("Próxima página")
                Button {
                    address = searchProvider.homeURL
                    commitURL()
                } label: { Image(systemName: "house") }
                    .help("Página inicial")
                    .accessibilityLabel("Página inicial")
                Picker("Busca", selection: $searchProvider) {
                    ForEach(WebSearchProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 105)
                TextField("URL ou busca", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitURL)
                Button { commitURL() } label: { Image(systemName: "arrow.right") }
                    .help("Abrir endereço ou pesquisar")
                Button {
                    browser.captureSelection { node.webSelectedText = $0 }
                } label: {
                    Label("Usar seleção", systemImage: "text.viewfinder")
                }
                .help("Usar o texto selecionado na página como contexto do tutor")
            }
            .padding(8)
            .background(.bar)
            .onAppear {
                address = node.webURL
                searchProvider = node.webURL.contains("scholar.google") ? .scholar : .google
            }

            WebKitView(
                urlString: $node.webURL,
                selectedText: $node.webSelectedText,
                visibleText: Binding(
                    get: { node.webVisibleText ?? "" },
                    set: { node.webVisibleText = $0 }
                ),
                navigationQuote: $node.webNavigationQuote,
                navigator: browser
            )
        }
    }

    private func commitURL() {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, !value.contains("://") {
            if value.contains(" ") || !value.contains(".") {
                let q = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                value = searchProvider.searchURL(query: q)
            } else {
                value = "https://\(value)"
            }
        }
        node.webSelectedText = ""
        node.webURL = value
        address = value
    }
}

private struct WebKitView: NSViewRepresentable {
    @Binding var urlString: String
    @Binding var selectedText: String
    @Binding var visibleText: String
    @Binding var navigationQuote: String?
    @ObservedObject var navigator: WebNavigator

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "studyhSelection")
        config.userContentController.addUserScript(WKUserScript(
            source: "document.addEventListener('mouseup', () => window.webkit.messageHandlers.studyhSelection.postMessage(window.getSelection().toString()));",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        navigator.attach(view)
        context.coordinator.load(urlString, in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        navigator.attach(view)
        if context.coordinator.lastURL != urlString {
            context.coordinator.load(urlString, in: view)
        } else {
            context.coordinator.navigateToQuoteIfNeeded(in: view)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "studyhSelection")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebKitView
        var lastURL: String = ""
        var handledNavigationQuote: String?

        init(parent: WebKitView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "studyhSelection" else { return }
            parent.selectedText = (message.body as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func load(_ string: String, in view: WKWebView) {
            lastURL = string
            guard let url = URL(string: string) else { return }
            view.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, _ in
                let text = String((result as? String ?? "").prefix(20_000))
                DispatchQueue.main.async { self.parent.visibleText = text }
            }
            if let url = webView.url?.absoluteString {
                DispatchQueue.main.async {
                    self.parent.urlString = url
                    self.lastURL = url
                    self.parent.navigator.refreshNavigationState()
                }
            }
            navigateToQuoteIfNeeded(in: webView)
        }

        func navigateToQuoteIfNeeded(in webView: WKWebView) {
            let quote = parent.navigationQuote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !quote.isEmpty, handledNavigationQuote != quote,
                  let data = try? JSONEncoder().encode(quote),
                  let json = String(data: data, encoding: .utf8) else {
                if quote.isEmpty { handledNavigationQuote = nil }
                return
            }
            handledNavigationQuote = quote
            let script = """
            (() => {
              const quote = \(json);
              const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
              while (walker.nextNode()) {
                const node = walker.currentNode;
                const index = node.nodeValue.toLocaleLowerCase().indexOf(quote.toLocaleLowerCase());
                if (index < 0) continue;
                const range = document.createRange();
                range.setStart(node, index);
                range.setEnd(node, index + quote.length);
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                range.startContainer.parentElement?.scrollIntoView({behavior:'smooth', block:'center'});
                return true;
              }
              return window.find(quote, false, false, true, false, true, false);
            })();
            """
            webView.evaluateJavaScript(script)
            parent.navigationQuote = nil
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

private enum WebSearchProvider: String, CaseIterable, Identifiable {
    case google
    case scholar

    var id: String { rawValue }
    var label: String { self == .google ? "Google" : "Acadêmico" }
    var homeURL: String {
        self == .google ? "https://www.google.com" : "https://scholar.google.com"
    }

    func searchURL(query: String) -> String {
        switch self {
        case .google: return "https://www.google.com/search?q=\(query)"
        case .scholar: return "https://scholar.google.com/scholar?q=\(query)"
        }
    }
}

@MainActor
private final class WebNavigator: ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    private weak var webView: WKWebView?

    func attach(_ view: WKWebView) {
        guard webView !== view else { return }
        webView = view
        refreshNavigationState()
    }

    func goBack() {
        webView?.goBack()
        refreshNavigationState()
    }

    func goForward() {
        webView?.goForward()
        refreshNavigationState()
    }

    func refreshNavigationState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
    }

    func captureSelection(completion: @escaping (String) -> Void) {
        webView?.evaluateJavaScript("window.getSelection().toString()") { result, _ in
            let text = (result as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { completion(text) }
        }
    }
}
