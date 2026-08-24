import SwiftUI
import AppKit
import PDFKit
import WebKit
import UniformTypeIdentifiers
import Vision
import Darwin

extension Notification.Name {
    static let studyhOpenEPUBAnnotation = Notification.Name("StudyhOpenEPUBAnnotation")
    static let studyhReviewQuestion = Notification.Name("StudyhReviewQuestion")
    static let studyhReviewFlashcards = Notification.Name("StudyhReviewFlashcards")
    static let studyhOpenStudyNote = Notification.Name("StudyhOpenStudyNote")
}

struct PDFNodeView: View {
    @Binding var node: CanvasNode

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(node.pdfBookmark == nil ? "Escolher PDF…" : "Trocar PDF…") { pickPDF() }
                Spacer()
                Text(node.pdfBookmark == nil ? "Nenhum arquivo" : "pág. \(node.pdfPageIndex + 1)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(8)
            .background(.bar)

            PDFKitView(
                bookmark: node.pdfBookmark,
                pageIndex: $node.pdfPageIndex,
                selectedText: $node.pdfSelectedText,
                visibleText: $node.pdfVisibleText,
                fullText: $node.pdfText,
                pageCount: $node.pdfPageCount,
                navigationQuote: $node.pdfNavigationQuote,
                onBookmarkRenewed: { node.pdfBookmark = $0 }
            )
        }
    }

    private func pickPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            node.pdfBookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            node.title = url.deletingPathExtension().lastPathComponent
            node.pdfPageIndex = 0
        } catch {
            node.title = "PDF (falha ao abrir)"
        }
    }
}

struct EPUBNodeView: View {
    @Binding var node: CanvasNode
    @State private var book: EPUBBook?
    @State private var currentPage = 0
    @State private var pageCount = 1
    @State private var extracting = false
    @State private var loadError: String?
    @State private var selectedText = ""
    @State private var noteDraft = ""
    @State private var showingNoteEditor = false
    @State private var importingAppleBooks = false
    @State private var importMessage: String?
    @State private var showingAnnotations = false
    @State private var annotationNavigationRequest: EPUBAnnotationNavigation?
    @State private var loadedBookmark: Data?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(node.epubBookmark == nil ? "Escolher EPUB…" : "Trocar EPUB…") { pickEPUB() }
                Spacer()
                if extracting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparando texto…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let book {
                    Button {
                        currentPage = max(0, currentPage - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentPage == 0)

                    Text("pág. \(currentPage + 1) de \(pageCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button {
                        currentPage = min(pageCount - 1, currentPage + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(currentPage >= pageCount - 1)

                    Divider().frame(height: 16)

                    Button("A−") { changeFontSize(by: -2) }
                        .disabled((node.epubFontSize ?? 20) <= 14)
                        .help("Diminuir letra")
                    Button("A+") { changeFontSize(by: 2) }
                        .disabled((node.epubFontSize ?? 20) >= 34)
                        .help("Aumentar letra")

                    Menu {
                        ForEach(EPUBReaderTheme.allCases) { theme in
                            Button {
                                node.epubTheme = theme
                            } label: {
                                if (node.epubTheme ?? .automatic) == theme {
                                    Label(theme.label, systemImage: "checkmark")
                                } else {
                                    Text(theme.label)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                    }
                    .help("Aparência da página")

                    if let annotations = node.epubAnnotations, !annotations.isEmpty {
                        Button {
                            showingAnnotations.toggle()
                        } label: {
                            Label("\(annotations.count)", systemImage: "bookmark.fill")
                        }
                        .popover(isPresented: $showingAnnotations, arrowEdge: .bottom) {
                            EPUBAnnotationList(
                                annotations: annotations,
                                onOpen: { id in
                                    annotationNavigationRequest = EPUBAnnotationNavigation(annotationID: id)
                                    showingAnnotations = false
                                },
                                onDelete: deleteAnnotation,
                                onRecolor: recolorAnnotation
                            )
                        }
                        .help("Marcações e notas")
                    }

                    Button {
                        importFromAppleBooks(book)
                    } label: {
                        if importingAppleBooks {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Livros", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(importingAppleBooks)
                    .help("Importar marcações e progresso do Apple Books")
                } else if node.epubBookmark == nil {
                    Text("Nenhum arquivo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if loadError != nil {
                    Label("Não foi possível ler", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(8)
            .background(.bar)

            if let book {
                EPUBReaderWebView(
                    documentURL: book.documentURL,
                    bookDirectory: book.directory,
                    pageIndex: $currentPage,
                    pageCount: $pageCount,
                    selectedText: $selectedText,
                    visibleText: $node.epubVisibleText,
                    fontSize: node.epubFontSize ?? 20,
                    theme: node.epubTheme ?? .automatic,
                    annotations: node.epubAnnotations ?? [],
                    annotationNavigationRequest: annotationNavigationRequest,
                    onHighlight: { quote, color in
                        addAnnotation(quote: quote, note: nil, color: color)
                    },
                    onAddNote: { quote in
                        selectedText = quote
                        noteDraft = ""
                        showingNoteEditor = true
                    },
                    onDeleteAnnotation: deleteAnnotation,
                    onRecolorAnnotation: recolorAnnotation
                )
                .overlay(alignment: .leading) {
                    PageEdgeButton(systemImage: "chevron.left", action: previousPage)
                        .disabled(currentPage == 0)
                }
                .overlay(alignment: .trailing) {
                    PageEdgeButton(systemImage: "chevron.right", action: nextPage)
                        .disabled(currentPage >= pageCount - 1)
                }
            } else if let loadError {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "EPUB indisponível",
                        systemImage: "books.vertical",
                        description: Text(loadError)
                    )
                    Button("Escolher outro EPUB…") { pickEPUB() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Color.clear
            }
        }
        .task(id: node.epubBookmark) {
            guard let bookmark = node.epubBookmark else {
                book = nil
                loadedBookmark = nil
                return
            }
            if loadedBookmark == bookmark, book != nil { return }
            book = nil
            currentPage = node.epubPageIndex ?? 0
            pageCount = max(1, node.epubPageCount ?? 1)
            loadError = nil
            extracting = true
            if let loaded = await EPUBBookLoader.load(from: bookmark) {
                guard !Task.isCancelled else { return }
                book = loaded
                node.epubText = loaded.text
                if let renewedBookmark = loaded.renewedBookmark {
                    loadedBookmark = renewedBookmark
                    node.epubBookmark = renewedBookmark
                } else {
                    loadedBookmark = bookmark
                }
            } else {
                guard !Task.isCancelled else { return }
                node.epubText = nil
                loadError = "O arquivo parece inválido ou protegido por DRM."
            }
            extracting = false
        }
        .onChange(of: currentPage) { _, page in
            node.epubPageIndex = page
        }
        .onChange(of: node.epubPageIndex) { _, page in
            guard let page, page != currentPage else { return }
            currentPage = min(max(0, page), max(0, pageCount - 1))
        }
        .onChange(of: pageCount) { _, count in
            node.epubPageCount = count
        }
        .overlay(alignment: .topTrailing) {
            if showingNoteEditor {
                selectionNoteEditor
                    .padding(10)
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showingNoteEditor)
        .onReceive(NotificationCenter.default.publisher(for: .studyhOpenEPUBAnnotation)) { notification in
            guard notification.userInfo?["nodeID"] as? UUID == node.id,
                  let annotationID = notification.userInfo?["annotationID"] as? UUID else { return }
            annotationNavigationRequest = EPUBAnnotationNavigation(annotationID: annotationID)
        }
        .alert(
            "Importação do Apple Books",
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )
        ) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var selectionNoteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.caption.weight(.bold))
                Text("Nota")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    showingNoteEditor = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black.opacity(0.65))
                .accessibilityLabel("Fechar nota")
            }
            Text("“\(selectedText)”")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $noteDraft)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(height: 64)
                if noteDraft.isEmpty {
                    Text("Escreva o que quer guardar deste trecho…")
                        .foregroundStyle(Color.black.opacity(0.35))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Spacer()
                Button("Salvar") {
                    addAnnotation(note: noteDraft, color: .yellow)
                    showingNoteEditor = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(9)
        .frame(width: 218)
        .foregroundStyle(.black)
        .background(
            Color(red: 1.0, green: 0.93, blue: 0.55).opacity(0.96),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
    }

    private func pickEPUB() {
        let panel = NSOpenPanel()
        if let epubType = UTType(filenameExtension: "epub") {
            panel.allowedContentTypes = [epubType]
        }
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            node.epubBookmark = bookmark
            node.epubText = nil
            node.title = url.deletingPathExtension().lastPathComponent
        } catch {
            node.title = "EPUB (falha ao abrir)"
        }
    }

    private func previousPage() {
        currentPage = max(0, currentPage - 1)
    }

    private func nextPage() {
        currentPage = min(pageCount - 1, currentPage + 1)
    }

    private func changeFontSize(by delta: Double) {
        node.epubFontSize = min(34, max(14, (node.epubFontSize ?? 20) + delta))
    }

    private func addAnnotation(
        quote suppliedQuote: String? = nil,
        note: String?,
        color: EPUBHighlightColor
    ) {
        let quote = (suppliedQuote ?? selectedText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { return }
        var annotations = node.epubAnnotations ?? []
        annotations.append(EPUBAnnotation(
            quote: quote,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color
        ))
        node.epubAnnotations = annotations
        selectedText = ""
    }

    private func deleteAnnotation(_ id: UUID) {
        node.epubAnnotations?.removeAll { $0.id == id }
    }

    private func recolorAnnotation(_ id: UUID, color: EPUBHighlightColor) {
        guard let index = node.epubAnnotations?.firstIndex(where: { $0.id == id }) else { return }
        node.epubAnnotations?[index].color = color
    }

    private func importFromAppleBooks(_ book: EPUBBook) {
        importingAppleBooks = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try AppleBooksImporter.loadAnnotations(
                        epubIdentifiers: book.identifiers,
                        title: book.title
                    )
                }.value
                var saved = node.epubAnnotations ?? []
                let existingIDs = Set(saved.map(\.id))
                let newAnnotations = result.annotations.filter { !existingIDs.contains($0.id) }
                saved.append(contentsOf: newAnnotations)
                node.epubAnnotations = saved
                var progressUpdated = false
                if let progress = result.readingProgress, pageCount > 1 {
                    let importedPage = min(
                        pageCount - 1,
                        max(0, Int((progress * Double(pageCount - 1)).rounded()))
                    )
                    if importedPage != currentPage {
                        currentPage = importedPage
                        progressUpdated = true
                    }
                }
                let progressMessage = progressUpdated
                    ? " O progresso de leitura também foi atualizado."
                    : " Nenhum progresso de leitura novo foi aplicado."
                importMessage = "Importei \(newAnnotations.count) nova(s) marcação(ões) de “\(result.bookTitle)”.\(progressMessage)"
            } catch {
                importMessage = error.localizedDescription
            }
            importingAppleBooks = false
        }
    }
}

private struct EPUBAnnotationNavigation: Equatable {
    let token = UUID()
    let annotationID: UUID
}

private struct EPUBAnnotationList: View {
    let annotations: [EPUBAnnotation]
    let onOpen: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onRecolor: (UUID, EPUBHighlightColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Marcações")
                .font(.headline)
                .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(annotations) { annotation in
                        Button {
                            onOpen(annotation.id)
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(displayColor(annotation.color ?? .yellow))
                                    .frame(width: 9, height: 9)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(annotation.quote)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let note = annotation.note, !note.isEmpty {
                                        Label(note, systemImage: "note.text")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        .contextMenu {
                            Menu("Mudar cor") {
                                ForEach(EPUBHighlightColor.allCases) { color in
                                    Button(color.label) { onRecolor(annotation.id, color) }
                                }
                            }
                            Button("Excluir", role: .destructive) { onDelete(annotation.id) }
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 360, height: 430)
    }

    private func displayColor(_ color: EPUBHighlightColor) -> Color {
        switch color {
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .purple: return .purple
        }
    }
}

private struct PageEdgeButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .frame(width: 42, height: 92)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(10)
        .help(systemImage.contains("left") ? "Página anterior" : "Próxima página")
        .accessibilityLabel(systemImage.contains("left") ? "Página anterior" : "Próxima página")
    }
}

private struct EPUBReaderWebView: NSViewRepresentable {
    let documentURL: URL
    let bookDirectory: URL
    @Binding var pageIndex: Int
    @Binding var pageCount: Int
    @Binding var selectedText: String
    @Binding var visibleText: String?
    let fontSize: Double
    let theme: EPUBReaderTheme
    let annotations: [EPUBAnnotation]
    let annotationNavigationRequest: EPUBAnnotationNavigation?
    let onHighlight: (String, EPUBHighlightColor) -> Void
    let onAddNote: (String) -> Void
    let onDeleteAnnotation: (UUID) -> Void
    let onRecolorAnnotation: (UUID, EPUBHighlightColor) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "pagination")
        configuration.userContentController.add(context.coordinator, name: "pageChange")
        configuration.userContentController.add(context.coordinator, name: "selection")
        configuration.userContentController.add(context.coordinator, name: "contextMenu")
        configuration.userContentController.add(context.coordinator, name: "pageContext")
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.paginationScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedURL != documentURL {
            load(into: view, coordinator: context.coordinator)
        } else {
            context.coordinator.applyPreferences(in: view)
            context.coordinator.applyAnnotations(in: view)
            context.coordinator.navigateToAnnotationIfNeeded(in: view)
            if context.coordinator.displayedPage != pageIndex {
                context.coordinator.show(page: pageIndex, in: view)
            }
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "pagination")
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "pageChange")
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "selection")
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "contextMenu")
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "pageContext")
    }

    private func load(into view: WKWebView, coordinator: Coordinator) {
        coordinator.loadedURL = documentURL
        coordinator.displayedPage = 0
        view.loadFileURL(documentURL, allowingReadAccessTo: bookDirectory)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EPUBReaderWebView
        var loadedURL: URL?
        var displayedPage = 0
        var appliedFontSize: Double?
        var appliedTheme: EPUBReaderTheme?
        var appliedAnnotations = ""
        var contextQuote = ""
        var contextAnnotationID: UUID?
        var handledAnnotationNavigationToken: UUID?

        init(parent: EPUBReaderWebView) {
            self.parent = parent
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "pagination":
                guard let count = message.body as? Int else { return }
                // Images, highlights and reader preferences finish loading in stages.
                // WebKit can briefly report a tiny page count for a long book; do not
                // let that transient measurement destroy the saved reading position.
                let previousCount = max(1, parent.pageCount)
                if parent.pageIndex >= count,
                   previousCount > count,
                   count < max(2, previousCount / 2) {
                    return
                }
                parent.pageCount = max(1, count)
                if parent.pageIndex >= count {
                    parent.pageIndex = max(0, count - 1)
                }
                show(page: parent.pageIndex, in: message.webView)
            case "pageChange":
                guard let page = message.body as? Int else { return }
                parent.pageIndex = min(max(0, page), max(0, parent.pageCount - 1))
            case "selection":
                parent.selectedText = (message.body as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            case "contextMenu":
                guard let payload = message.body as? [String: Any],
                      let webView = message.webView else { return }
                showContextMenu(payload, in: webView)
            case "pageContext":
                let text = (message.body as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                parent.visibleText = text.isEmpty ? nil : text
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            appliedFontSize = nil
            appliedTheme = nil
            appliedAnnotations = ""
            applyPreferences(in: webView)
            applyAnnotations(in: webView)
            navigateToAnnotationIfNeeded(in: webView)
            show(page: parent.pageIndex, in: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let documentURL = parent.documentURL.standardizedFileURL
            let destination = url.standardizedFileURL
            let isReaderDocument = destination.isFileURL && destination.path == documentURL.path
            let isInitialLoad = navigationAction.navigationType == .other && isReaderDocument
            let isSameDocumentFragment = isReaderDocument && url.fragment != nil
            decisionHandler(isInitialLoad || isSameDocumentFragment ? .allow : .cancel)
        }

        func show(page: Int, in webView: WKWebView?) {
            guard let webView else { return }
            displayedPage = page
            webView.evaluateJavaScript("window.studyhGoToPage(\(page));")
        }

        func applyPreferences(in webView: WKWebView) {
            guard appliedFontSize != parent.fontSize || appliedTheme != parent.theme else { return }
            appliedFontSize = parent.fontSize
            appliedTheme = parent.theme
            let script = "window.studyhApplyPreferences(\(parent.fontSize), '\(parent.theme.rawValue)');"
            webView.evaluateJavaScript(script)
        }

        func applyAnnotations(in webView: WKWebView) {
            let fingerprint = parent.annotations.map {
                $0.id.uuidString + $0.quote + ($0.color?.rawValue ?? "yellow")
            }.joined()
            guard fingerprint != appliedAnnotations else { return }
            appliedAnnotations = fingerprint
            let items = parent.annotations.map { annotation in
                [
                    "id": annotation.id.uuidString,
                    "quote": annotation.quote,
                    "color": (annotation.color ?? .yellow).cssColor
                ]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: items),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.studyhRestoreHighlights(\(json));")
        }

        func navigateToAnnotationIfNeeded(in webView: WKWebView) {
            guard let request = parent.annotationNavigationRequest,
                  handledAnnotationNavigationToken != request.token else { return }
            handledAnnotationNavigationToken = request.token
            webView.evaluateJavaScript(
                "window.studyhGoToAnnotation('\(request.annotationID.uuidString)');"
            )
        }

        private func showContextMenu(_ payload: [String: Any], in webView: WKWebView) {
            contextQuote = (payload["text"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let rawID = payload["annotationID"] as? String {
                contextAnnotationID = UUID(uuidString: rawID)
            } else {
                contextAnnotationID = nil
            }

            let menu = NSMenu()
            if contextAnnotationID != nil {
                let colorItem = NSMenuItem(title: "Mudar cor", action: nil, keyEquivalent: "")
                let colors = NSMenu()
                for color in EPUBHighlightColor.allCases {
                    let item = NSMenuItem(
                        title: color.label,
                        action: #selector(recolorFromMenu(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = color.rawValue
                    colors.addItem(item)
                }
                colorItem.submenu = colors
                menu.addItem(colorItem)
                menu.addItem(.separator())
                let deleteItem = NSMenuItem(
                    title: "Excluir marcação",
                    action: #selector(deleteFromMenu(_:)),
                    keyEquivalent: ""
                )
                deleteItem.target = self
                menu.addItem(deleteItem)
            } else if !contextQuote.isEmpty {
                let highlightItem = NSMenuItem(title: "Destacar", action: nil, keyEquivalent: "")
                let colors = NSMenu()
                for color in EPUBHighlightColor.allCases {
                    let item = NSMenuItem(
                        title: color.label,
                        action: #selector(highlightFromMenu(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = color.rawValue
                    colors.addItem(item)
                }
                highlightItem.submenu = colors
                menu.addItem(highlightItem)
                let noteItem = NSMenuItem(
                    title: "Adicionar nota…",
                    action: #selector(addNoteFromMenu(_:)),
                    keyEquivalent: ""
                )
                noteItem.target = self
                menu.addItem(noteItem)
            }
            guard !menu.items.isEmpty else { return }
            let x = payload["x"] as? Double ?? 0
            let y = payload["y"] as? Double ?? 0
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: x, y: webView.bounds.height - y),
                in: webView
            )
        }

        @objc private func highlightFromMenu(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String,
                  let color = EPUBHighlightColor(rawValue: raw) else { return }
            parent.onHighlight(contextQuote, color)
        }

        @objc private func addNoteFromMenu(_ sender: NSMenuItem) {
            parent.onAddNote(contextQuote)
        }

        @objc private func recolorFromMenu(_ sender: NSMenuItem) {
            guard let id = contextAnnotationID,
                  let raw = sender.representedObject as? String,
                  let color = EPUBHighlightColor(rawValue: raw) else { return }
            parent.onRecolorAnnotation(id, color)
        }

        @objc private func deleteFromMenu(_ sender: NSMenuItem) {
            guard let id = contextAnnotationID else { return }
            parent.onDeleteAnnotation(id)
        }
    }

    private static let paginationScript = """
    (() => {
      let resizeTimer;
      window.studyhPaginate = function() {
        const width = Math.max(1, window.innerWidth);
        const book = document.getElementById('studyh-book');
        const total = Math.max(1, Math.ceil(book.scrollWidth / width));
        window.webkit.messageHandlers.pagination.postMessage(total);
      };
      window.studyhGoToPage = function(page) {
        const width = Math.max(1, window.innerWidth);
        const book = document.getElementById('studyh-book');
        book.scrollTo({ left: Math.max(0, page) * width, top: 0, behavior: 'instant' });
        setTimeout(window.studyhSendPageContext, 80);
      };
      window.studyhSendPageContext = function() {
        const parts = new Set();
        const width = Math.max(1, window.innerWidth);
        const height = Math.max(1, window.innerHeight);
        const xPoints = [0.18, 0.38, 0.58, 0.78].map(value => value * width);
        for (let y = 24; y < height - 16; y += 26) {
          for (const x of xPoints) {
            const element = document.elementFromPoint(x, y);
            const block = element?.closest('p, h1, h2, h3, h4, li, blockquote');
            const value = block?.innerText?.trim();
            if (value) parts.add(value);
          }
        }
        window.webkit.messageHandlers.pageContext.postMessage([...parts].join('\\n'));
      };
      window.studyhGoToAnnotation = function(annotationID) {
        const book = document.getElementById('studyh-book');
        const mark = book.querySelector(`mark[data-annotation-id="${annotationID}"]`);
        if (!mark) return;
        const bookBounds = book.getBoundingClientRect();
        const markBounds = mark.getBoundingClientRect();
        const absoluteLeft = book.scrollLeft + markBounds.left - bookBounds.left;
        const page = Math.max(0, Math.floor(absoluteLeft / Math.max(1, window.innerWidth)));
        window.webkit.messageHandlers.pageChange.postMessage(page);
        mark.animate(
          [{ outline: '3px solid transparent' }, { outline: '3px solid currentColor' }, { outline: '3px solid transparent' }],
          { duration: 900 }
        );
      };
      window.studyhApplyPreferences = function(fontSize, theme) {
        document.documentElement.dataset.studyhTheme = theme;
        document.getElementById('studyh-book').style.fontSize = fontSize + 'px';
        setTimeout(window.studyhPaginate, 60);
      };
      window.studyhRestoreHighlights = function(items) {
        const book = document.getElementById('studyh-book');
        book.querySelectorAll('mark.studyh-highlight').forEach(mark => {
          const parent = mark.parentNode;
          while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
          parent.removeChild(mark);
          parent.normalize();
        });
        const walker = document.createTreeWalker(book, NodeFilter.SHOW_TEXT);
        const nodes = [];
        let combined = '';
        while (walker.nextNode()) {
          nodes.push({ node: walker.currentNode, start: combined.length });
          combined += walker.currentNode.nodeValue;
        }
        let normalized = '';
        const positions = [];
        let previousWasSpace = false;
        for (let index = 0; index < combined.length; index++) {
          const isSpace = /\\s/.test(combined[index]);
          if (isSpace) {
            if (!previousWasSpace) {
              normalized += ' ';
              positions.push(index);
            }
          } else {
            normalized += combined[index];
            positions.push(index);
          }
          previousWasSpace = isSpace;
        }
        const nextOccurrence = new Map();
        const placements = [];
        for (const item of items) {
          const target = item.quote.replace(/\\s+/g, ' ').trim();
          if (!target) continue;
          const searchFrom = nextOccurrence.get(target) || 0;
          const normalizedStart = normalized.indexOf(target, searchFrom);
          if (normalizedStart < 0) continue;
          const start = positions[normalizedStart];
          const lastPosition = positions[normalizedStart + target.length - 1];
          if (start === undefined || lastPosition === undefined) continue;
          placements.push({ item, start, end: lastPosition + 1 });
          nextOccurrence.set(target, normalizedStart + target.length);
        }
        placements.sort((a, b) => b.start - a.start);
        for (const placement of placements) {
          const { item, start, end } = placement;
          const first = nodes.findLast ? nodes.findLast(entry => entry.start <= start) : nodes.filter(entry => entry.start <= start).pop();
          const last = nodes.findLast ? nodes.findLast(entry => entry.start < end) : nodes.filter(entry => entry.start < end).pop();
          if (!first || !last) continue;
          const range = document.createRange();
          range.setStart(first.node, start - first.start);
          range.setEnd(last.node, end - last.start);
          const mark = document.createElement('mark');
          mark.className = 'studyh-highlight';
          mark.dataset.annotationId = item.id;
          mark.style.setProperty('background-color', item.color || '#ffd95a', 'important');
          mark.appendChild(range.extractContents());
          range.insertNode(mark);
        }
        setTimeout(window.studyhPaginate, 60);
      };
      let wheelAccumulator = 0;
      let wheelTimer;
      const book = document.getElementById('studyh-book');
      book.addEventListener('wheel', event => {
        if (Math.abs(event.deltaX) <= Math.abs(event.deltaY) || Math.abs(event.deltaX) < 3) return;
        event.preventDefault();
        wheelAccumulator += event.deltaX;
        clearTimeout(wheelTimer);
        wheelTimer = setTimeout(() => { wheelAccumulator = 0; }, 180);
        if (Math.abs(wheelAccumulator) >= 36) {
          const current = Math.round(book.scrollLeft / Math.max(1, window.innerWidth));
          const target = current + (wheelAccumulator > 0 ? 1 : -1);
          wheelAccumulator = 0;
          window.webkit.messageHandlers.pageChange.postMessage(target);
        }
      }, { passive: false });
      document.addEventListener('keydown', event => {
        const current = Math.round(book.scrollLeft / Math.max(1, window.innerWidth));
        if (event.key === 'ArrowRight') {
          event.preventDefault();
          window.webkit.messageHandlers.pageChange.postMessage(current + 1);
        } else if (event.key === 'ArrowLeft') {
          event.preventDefault();
          window.webkit.messageHandlers.pageChange.postMessage(current - 1);
        }
      });
      document.addEventListener('selectionchange', () => {
        const text = window.getSelection()?.toString() || '';
        window.webkit.messageHandlers.selection.postMessage(text);
      });
      document.addEventListener('contextmenu', event => {
        const selection = window.getSelection()?.toString().trim() || '';
        const mark = event.target.closest?.('mark.studyh-highlight');
        if (!selection && !mark) return;
        event.preventDefault();
        window.webkit.messageHandlers.contextMenu.postMessage({
          x: event.clientX,
          y: event.clientY,
          text: selection || mark?.innerText || '',
          annotationID: mark?.dataset.annotationId || ''
        });
      });
      window.addEventListener('load', () => setTimeout(window.studyhPaginate, 80));
      window.addEventListener('resize', () => {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(window.studyhPaginate, 120);
      });
      setTimeout(window.studyhPaginate, 80);
    })();
    """
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private final class EPUBBook: @unchecked Sendable {
    let directory: URL
    let documentURL: URL
    let text: String
    let identifiers: [String]
    let title: String?
    let renewedBookmark: Data?

    init(
        directory: URL,
        documentURL: URL,
        text: String,
        identifiers: [String],
        title: String?,
        renewedBookmark: Data?
    ) {
        self.directory = directory
        self.documentURL = documentURL
        self.text = text
        self.identifiers = identifiers
        self.title = title
        self.renewedBookmark = renewedBookmark
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum EPUBBookLoader {
    private static let maxArchiveBytes = 200 * 1_024 * 1_024
    private static let maxExtractedBytes = 500 * 1_024 * 1_024
    private static let maxExtractedFiles = 10_000
    private static let maxSingleFileBytes = 50 * 1_024 * 1_024
    private static let maxChapterBytes = 10 * 1_024 * 1_024
    private static let maxReaderHTMLBytes = 50 * 1_024 * 1_024
    private static let maxChapters = 1_000
    private static let extractionTimeout: TimeInterval = 20

    static func load(from bookmark: Data) async -> EPUBBook? {
        let cancelled = CancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    // Security-scoped bookmarks are validated against the code
                    // identity that created them; after re-signing, resolution
                    // can fail even though the file is readable. Fall back to
                    // a plain resolution — the app is not sandboxed, so scope
                    // access is not required to read the archive.
                    var stale = false
                    var url = try? URL(
                        resolvingBookmarkData: bookmark,
                        options: [.withSecurityScope],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale
                    )
                    var usingScope = url != nil
                    if url == nil {
                        stale = false
                        url = try? URL(
                            resolvingBookmarkData: bookmark,
                            options: [],
                            relativeTo: nil,
                            bookmarkDataIsStale: &stale
                        )
                        usingScope = false
                    }
                    guard let url else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let accessed = usingScope && url.startAccessingSecurityScopedResource()
                    defer {
                        if accessed { url.stopAccessingSecurityScopedResource() }
                    }
                    let renewedBookmark = stale ? try? url.bookmarkData(
                        options: usingScope ? .withSecurityScope : [],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) : nil
                    continuation.resume(returning: loadSynchronously(
                        from: url,
                        renewedBookmark: renewedBookmark,
                        cancelled: cancelled
                    ))
                }
            }
        } onCancel: {
            cancelled.set()
        }
    }

    private static func loadSynchronously(
        from url: URL,
        renewedBookmark: Data?,
        cancelled: CancelFlag
    ) -> EPUBBook? {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("Studyh-EPUB-" + UUID().uuidString, isDirectory: true)
        do {
            let archiveSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard archiveSize > 0, archiveSize <= maxArchiveBytes, !cancelled.isSet else {
                return nil
            }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", url.path, directory.path]
            try process.run()
            let deadline = Date().addingTimeInterval(extractionTimeout)
            var nextSizeCheck = Date()
            while process.isRunning {
                let now = Date()
                let exceedsLimits = now >= nextSizeCheck && !extractionIsWithinLimits(directory)
                if cancelled.isSet || now >= deadline || exceedsLimits {
                    terminate(process)
                    try? manager.removeItem(at: directory)
                    return nil
                }
                if now >= nextSizeCheck {
                    nextSizeCheck = now.addingTimeInterval(0.25)
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                try? manager.removeItem(at: directory)
                return nil
            }
            guard extractionIsWithinLimits(directory), !cancelled.isSet else {
                try? manager.removeItem(at: directory)
                return nil
            }

            let package = packageContents(in: directory)
            let chapters = Array(package.chapters.prefix(maxChapters))
            guard !chapters.isEmpty else {
                try? manager.removeItem(at: directory)
                return nil
            }

            var sections: [String] = []
            var characterCount = 0
            for file in chapters where characterCount < 1_000_000 {
                guard !cancelled.isSet,
                      fileSize(of: file) <= maxChapterBytes,
                      let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let safeHTML = sanitize(bodyContent(from: source), relativeTo: file, in: directory)
                guard let data = safeHTML.data(using: .utf8),
                      let attributed = try? NSAttributedString(
                        data: data,
                        options: [
                            .documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue
                        ],
                        documentAttributes: nil
                      ) else { continue }
                let cleaned = clean(attributed.string)
                guard !cleaned.isEmpty else { continue }
                sections.append(cleaned)
                characterCount += cleaned.count
            }
            let text = String(sections.joined(separator: "\n\n").prefix(1_000_000))
            let documentURL = try makeReaderDocument(
                from: chapters,
                coverImage: package.coverImage,
                in: directory
            )
            return EPUBBook(
                directory: directory,
                documentURL: documentURL,
                text: text,
                identifiers: package.identifiers,
                title: package.title,
                renewedBookmark: renewedBookmark
            )
        } catch {
            try? manager.removeItem(at: directory)
            return nil
        }
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private static func extractionIsWithinLimits(_ directory: URL) -> Bool {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return false }
        var fileCount = 0
        var totalBytes = 0
        for case let file as URL in enumerator {
            guard file.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/"),
                  let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true else { return false }
            guard values.isRegularFile == true else { continue }
            let size = values.fileSize ?? 0
            fileCount += 1
            totalBytes += size
            if fileCount > maxExtractedFiles
                || size > maxSingleFileBytes
                || totalBytes > maxExtractedBytes {
                return false
            }
        }
        return true
    }

    private static func fileSize(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
    }

    private static func packageContents(in directory: URL) -> EPUBPackageContents {
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        guard let containerParser = XMLParser(contentsOf: containerURL) else {
            return EPUBPackageContents(chapters: fallbackChapters(in: directory))
        }
        let containerDelegate = EPUBContainerParser()
        containerParser.delegate = containerDelegate
        guard containerParser.parse(), let packagePath = containerDelegate.packagePath else {
            return EPUBPackageContents(chapters: fallbackChapters(in: directory))
        }

        let packageURL = directory.appendingPathComponent(packagePath).standardizedFileURL
        guard packageURL.path.hasPrefix(directory.path + "/"),
              let packageParser = XMLParser(contentsOf: packageURL) else {
            return EPUBPackageContents(chapters: fallbackChapters(in: directory))
        }
        let packageDelegate = EPUBPackageParser()
        packageParser.delegate = packageDelegate
        guard packageParser.parse() else {
            return EPUBPackageContents(chapters: fallbackChapters(in: directory))
        }

        let packageDirectory = packageURL.deletingLastPathComponent()
        let chapters = packageDelegate.spine.compactMap { id -> URL? in
            guard let href = packageDelegate.manifest[id]?.removingPercentEncoding
                ?? packageDelegate.manifest[id] else { return nil }
            let chapter = packageDirectory.appendingPathComponent(href).standardizedFileURL
            guard chapter.path.hasPrefix(directory.path + "/"),
                  FileManager.default.fileExists(atPath: chapter.path) else { return nil }
            return chapter
        }

        var coverImage: URL?
        if let coverID = packageDelegate.coverImageID,
           let href = packageDelegate.manifest[coverID]?.removingPercentEncoding
               ?? packageDelegate.manifest[coverID] {
            let candidate = packageDirectory.appendingPathComponent(href).standardizedFileURL
            if candidate.path.hasPrefix(directory.path + "/"),
               FileManager.default.fileExists(atPath: candidate.path),
               fileSize(of: candidate) <= maxSingleFileBytes {
                coverImage = candidate
            }
        }

        return EPUBPackageContents(
            chapters: chapters.isEmpty ? fallbackChapters(in: directory) : chapters,
            identifiers: packageDelegate.identifiers,
            title: packageDelegate.title,
            coverImage: coverImage
        )
    }

    private static func fallbackChapters(in directory: URL) -> [URL] {
        let extensions = Set(["xhtml", "html", "htm"])
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func makeReaderDocument(
        from chapters: [URL],
        coverImage: URL?,
        in directory: URL
    ) throws -> URL {
        var sections: [String] = []
        var contentBytes = 0

        if let coverImage {
            let src = escapeAttribute(coverImage.absoluteString)
            let coverSection = "<section class=\"studyh-cover\"><img src=\"\(src)\" alt=\"\"></section>"
            sections.append(coverSection)
            contentBytes += coverSection.utf8.count
        }

        for chapter in chapters where contentBytes < maxReaderHTMLBytes {
            guard fileSize(of: chapter) <= maxChapterBytes,
                  let source = try? String(contentsOf: chapter, encoding: .utf8) else { continue }
            let body = bodyContent(from: source)
            var sanitized = sanitize(body, relativeTo: chapter, in: directory)
            if let coverImage {
                sanitized = removeCoverDuplicate(sanitized, coverImageURL: coverImage)
            }
            guard !sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let section = "<section class=\"studyh-chapter\">"
                + sanitized
                + "</section>"
            let sectionBytes = section.utf8.count
            guard contentBytes + sectionBytes <= maxReaderHTMLBytes else { break }
            sections.append(section)
            contentBytes += sectionBytes
        }
        let content = sections.joined(separator: "\n")
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file:; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; font-src 'none'; media-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
          <style>
            :root { color-scheme: light dark; }
            html, body {
              margin: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: #ffffff;
              color: #191919;
            }
            body {
              box-sizing: border-box;
              padding: 32px 64px;
            }
            #studyh-book {
              height: calc(100vh - 64px);
              column-width: calc(100vw - 128px);
              column-gap: 128px;
              column-fill: auto;
              font-family: ui-serif, Georgia, "Times New Roman", serif;
              font-size: 20px;
              line-height: 1.62;
              text-align: left;
              overflow: hidden;
            }
            #studyh-book, #studyh-book * {
              color: inherit !important;
              background-color: transparent !important;
            }
            #studyh-book a, #studyh-book a * { color: #075fbd !important; }
            #studyh-book mark.studyh-highlight,
            #studyh-book mark.studyh-highlight * {
              background-color: #ffd95a !important;
              color: #17120a !important;
              border-radius: 2px;
            }
            .studyh-chapter { break-before: column; }
            .studyh-cover {
                break-before: auto;
                break-after: column;
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: calc(100vh - 128px);
            }
            .studyh-cover img {
                max-width: 100%;
                max-height: calc(100vh - 160px);
            }
            .studyh-chapter:first-child { break-before: auto; }
            h1, h2, h3 { line-height: 1.2; break-after: avoid; }
            p { orphans: 3; widows: 3; }
            img, svg { max-width: 100%; max-height: 72vh; object-fit: contain; }
            @media (prefers-color-scheme: dark) {
              html, body { background: #111111; color: #eeeeee; }
              #studyh-book a, #studyh-book a * { color: #7cb7ff !important; }
            }
            html[data-studyh-theme="light"],
            html[data-studyh-theme="light"] body {
              background: #ffffff !important;
              color: #191919 !important;
            }
            html[data-studyh-theme="dark"],
            html[data-studyh-theme="dark"] body {
              background: #111111 !important;
              color: #eeeeee !important;
            }
          </style>
        </head>
        <body><main id="studyh-book">\(content)</main></body>
        </html>
        """
        let documentURL = directory.appendingPathComponent("studyh-reader.html")
        try html.write(to: documentURL, atomically: true, encoding: .utf8)
        return documentURL
    }

    private static func removeCoverDuplicate(_ html: String, coverImageURL: URL) -> String {
        let src = escapeAttribute(coverImageURL.absoluteString)
        return replacing(
            #"(?i)<img\b[^>]*\bsrc\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: src) + #"["'][^>]*>"#,
            in: html,
            with: ""
        )
    }

    private static func bodyContent(from html: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)<body\b[^>]*>(.*?)</body>"#
        ) else { return html }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = expression.firstMatch(in: html, range: range),
              let bodyRange = Range(match.range(at: 1), in: html) else { return html }
        return String(html[bodyRange])
    }

    private static func sanitize(_ html: String, relativeTo chapter: URL, in directory: URL) -> String {
        var result = html
        result = replacing(
            #"(?is)<(script|iframe|object|style|audio|video|canvas|frameset)\b[^>]*>.*?</\1\s*>"#,
            in: result,
            with: ""
        )
        result = replacing(
            #"(?is)<\s*/?\s*(?:script|iframe|object|embed|frame|style|link|meta|base|form|input|button|textarea|select|option|audio|video|canvas)\b[^>]*>"#,
            in: result,
            with: ""
        )
        result = replacing(
            #"(?is)\s+(?:on[a-z0-9_-]+|srcdoc|style)\s*=\s*(?:\"[^\"]*\"|'[^']*'|[^\s>]+)"#,
            in: result,
            with: ""
        )
        result = sanitizeURLAttributes(in: result, relativeTo: chapter, directory: directory)
        return result
    }

    private static func sanitizeURLAttributes(
        in html: String,
        relativeTo chapter: URL,
        directory: URL
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)\b(src|href|poster|xlink:href|action|formaction)\s*=\s*([\"'])(.*?)\2"#
        ) else { return html }
        let mutable = NSMutableString(string: html)
        let matches = expression.matches(
            in: html,
            range: NSRange(location: 0, length: mutable.length)
        )
        for match in matches.reversed() {
            let attribute = mutable.substring(with: match.range(at: 1)).lowercased()
            let value = mutable.substring(with: match.range(at: 3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var replacement = ""
            if attribute == "href", value.hasPrefix("#") {
                replacement = "href=\"" + escapeAttribute(value) + "\""
            } else if attribute == "src",
                      !value.hasPrefix("//"),
                      URL(string: value)?.scheme == nil,
                      let resource = URL(string: value, relativeTo: chapter)?.absoluteURL.standardizedFileURL,
                      resource.path.hasPrefix(directory.standardizedFileURL.path + "/"),
                      FileManager.default.fileExists(atPath: resource.path),
                      fileSize(of: resource) <= maxSingleFileBytes {
                replacement = "src=\"" + escapeAttribute(resource.absoluteString) + "\""
            }
            mutable.replaceCharacters(in: match.range, with: replacement)
        }
        let quotedResult = mutable as String
        return replacing(
            #"(?i)\b(?:src|href|poster|xlink:href|action|formaction)\s*=\s*[^\s\"'=<>`]+"#,
            in: quotedResult,
            with: ""
        )
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value),
            withTemplate: replacement
        )
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func clean(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private struct EPUBPackageContents {
    var chapters: [URL]
    var identifiers: [String] = []
    var title: String?
    var coverImage: URL?
}

private final class EPUBContainerParser: NSObject, XMLParserDelegate {
    var packagePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "rootfile" {
            packagePath = attributeDict["full-path"]
        }
    }
}

private final class EPUBPackageParser: NSObject, XMLParserDelegate {
    var manifest: [String: String] = [:]
    var spine: [String] = []
    var identifiers: [String] = []
    var title: String?
    var coverImageID: String?
    private var metadataElement: String?
    private var metadataBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "identifier" || localName == "title" {
            metadataElement = localName
            metadataBuffer = ""
        } else if localName == "meta",
                  attributeDict["name"]?.lowercased() == "cover",
                  let content = attributeDict["content"], !content.isEmpty {
            coverImageID = content
        } else if elementName == "item",
           let id = attributeDict["id"],
           let href = attributeDict["href"] {
            manifest[id] = href
            let properties = (attributeDict["properties"] ?? "")
                .lowercased()
                .split(whereSeparator: { $0 == " " })
            if properties.contains("cover-image") {
                coverImageID = id
            }
        } else if elementName == "itemref", let id = attributeDict["idref"] {
            spine.append(id)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if metadataElement != nil { metadataBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard metadataElement == localName else { return }
        let value = metadataBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if localName == "identifier", !value.isEmpty {
            identifiers.append(value)
        } else if localName == "title", !value.isEmpty, title == nil {
            title = value
        }
        metadataElement = nil
        metadataBuffer = ""
    }
}

private struct PDFKitView: NSViewRepresentable {
    var bookmark: Data?
    @Binding var pageIndex: Int
    @Binding var selectedText: String
    @Binding var visibleText: String
    @Binding var fullText: String?
    @Binding var pageCount: Int?
    @Binding var navigationQuote: String?
    let onBookmarkRenewed: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.delegate = context.coordinator
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        context.coordinator.load(bookmark, into: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedBookmark != bookmark {
            context.coordinator.load(bookmark, into: view)
        } else {
            context.coordinator.navigate(to: pageIndex, in: view)
            context.coordinator.navigateToQuoteIfNeeded(in: view)
        }
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.stopAccess()
    }

    @MainActor
    final class Coordinator: NSObject, PDFViewDelegate {
        var parent: PDFKitView
        var loadedBookmark: Data?
        private var accessedURL: URL?
        private var isAccessingURL = false
        private var ocrTask: Task<Void, Never>?
        private var ocrPageIndex: Int?
        private var textGeneration = UUID()
        private var ocrCache: [Int: String] = [:]
        private var handledNavigationQuote: String?

        init(parent: PDFKitView) {
            self.parent = parent
        }

        func stopAccess() {
            ocrTask?.cancel()
            ocrTask = nil
            ocrPageIndex = nil
            textGeneration = UUID()
            ocrCache = [:]
            if isAccessingURL {
                accessedURL?.stopAccessingSecurityScopedResource()
            }
            accessedURL = nil
            isAccessingURL = false
        }

        func load(_ bookmark: Data?, into view: PDFView) {
            stopAccess()
            loadedBookmark = bookmark
            parent.selectedText = ""
            parent.visibleText = ""
            guard let bookmark else {
                view.document = nil
                return
            }
            var stale = false
            var url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            var usingScope = url != nil
            if url == nil {
                stale = false
                url = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                usingScope = false
            }
            guard let url else { return }
            if stale, let renewedBookmark = try? url.bookmarkData(
                options: usingScope ? .withSecurityScope : [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                loadedBookmark = renewedBookmark
                parent.onBookmarkRenewed(renewedBookmark)
            }
            isAccessingURL = usingScope && url.startAccessingSecurityScopedResource()
            accessedURL = url
            view.document = PDFDocument(url: url)
            parent.pageCount = view.document?.pageCount
            if parent.fullText == nil, let text = view.document?.string, !text.isEmpty {
                parent.fullText = String(text.prefix(1_000_000))
            }
            if let page = view.document?.page(at: parent.pageIndex) {
                view.go(to: page)
            }
            refreshText(from: view)
            navigateToQuoteIfNeeded(in: view)
        }

        func navigate(to index: Int, in view: PDFView) {
            guard let document = view.document,
                  let page = document.page(at: min(max(0, index), max(0, document.pageCount - 1))),
                  view.currentPage !== page else { return }
            view.go(to: page)
        }

        func navigateToQuoteIfNeeded(in view: PDFView) {
            let quote = parent.navigationQuote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !quote.isEmpty, handledNavigationQuote != quote,
                  let selection = view.document?.findString(quote, withOptions: .caseInsensitive).first else {
                if quote.isEmpty { handledNavigationQuote = nil }
                return
            }
            handledNavigationQuote = quote
            view.setCurrentSelection(selection, animate: true)
            view.go(to: selection)
            parent.navigationQuote = nil
        }

        @objc func selectionChanged(_ note: Notification) {
            guard let view = note.object as? PDFView else { return }
            parent.selectedText = view.currentSelection?.string ?? ""
            refreshText(from: view)
        }

        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView else { return }
            parent.selectedText = ""
            if let page = view.currentPage, let doc = view.document {
                parent.pageIndex = doc.index(for: page)
            }
            refreshText(from: view)
        }

        private func refreshText(from view: PDFView) {
            let nativeText = view.currentPage?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !nativeText.isEmpty {
                ocrTask?.cancel()
                ocrTask = nil
                ocrPageIndex = nil
                parent.visibleText = nativeText
                return
            }
            parent.visibleText = ""
            guard let document = view.document,
                  let page = view.currentPage,
                  let url = accessedURL else { return }
            let index = document.index(for: page)
            if let cached = ocrCache[index], !cached.isEmpty {
                parent.visibleText = cached
                return
            }
            guard ocrPageIndex != index else { return }
            ocrTask?.cancel()
            ocrPageIndex = index
            let generation = UUID()
            textGeneration = generation
            let work = Task.detached(priority: .userInitiated) {
                PDFPageOCR.recognize(pageAt: index, in: url)
            }
            ocrTask = Task { [weak self] in
                let text = await withTaskCancellationHandler {
                    await work.value
                } onCancel: {
                    work.cancel()
                }
                guard !Task.isCancelled else { return }
                guard let self,
                      self.textGeneration == generation,
                      self.ocrPageIndex == index else { return }
                if !text.isEmpty { self.ocrCache[index] = text }
                self.parent.visibleText = text
                self.ocrTask = nil
            }
        }
    }
}

private enum PDFPageOCR {
    static func recognize(pageAt index: Int, in url: URL) -> String {
        guard !Task.isCancelled,
              let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: index + 1) else { return "" }
        let bounds = page.getBoxRect(.cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return "" }
        let scale = min(2, 2_400 / max(bounds.width, bounds.height))
        let width = max(1, Int((bounds.width * scale).rounded(.up)))
        let height = max(1, Int((bounds.height * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return "" }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(page)
        guard !Task.isCancelled, let image = context.makeImage() else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["pt-BR", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image)
        try? handler.perform([request])
        guard !Task.isCancelled else { return "" }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        return String(text.prefix(100_000))
    }
}
