import SwiftUI
import AppKit

@MainActor
final class RichTextController: ObservableObject {
    weak var textView: NSTextView?

    func toggleBold() { toggleFontTrait(.boldFontMask) }
    func toggleItalic() { toggleFontTrait(.italicFontMask) }

    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange
        let current = range.location < textView.attributedString().length
            ? textView.attributedString().attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int
            : textView.typingAttributes[.underlineStyle] as? Int
        let value = current == NSUnderlineStyle.single.rawValue ? 0 : NSUnderlineStyle.single.rawValue
        if range.length > 0 {
            textView.textStorage?.addAttribute(.underlineStyle, value: value, range: range)
        }
        textView.typingAttributes[.underlineStyle] = value
    }

    func setFontSize(_ size: CGFloat) {
        guard let textView else { return }
        let font = NSFont.systemFont(ofSize: size)
        if textView.selectedRange.length > 0 {
            textView.textStorage?.addAttribute(.font, value: font, range: textView.selectedRange)
        }
        textView.typingAttributes[.font] = font
    }

    func insertPrefix(_ prefix: String) {
        guard let textView else { return }
        textView.insertText(prefix, replacementRange: textView.selectedRange)
    }

    func currentParagraph() -> String? {
        guard let textView else { return nil }
        let text = textView.string as NSString
        let selection = textView.selectedRange
        guard text.length > 0 else { return nil }
        var start = min(selection.location, text.length)
        var end = min(selection.location + max(selection.length, 0), text.length)
        if start == end && start > 0 && start == text.length { start -= 1 }
        while start > 0, text.character(at: start - 1) != 0x0A { start -= 1 }
        while end < text.length, text.character(at: end) != 0x0A { end += 1 }
        guard start < end else { return nil }
        let paragraph = text.substring(with: NSRange(location: start, length: end - start))
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let manager = NSFontManager.shared
        let range = textView.selectedRange
        let currentFont = (range.location < textView.attributedString().length
            ? textView.attributedString().attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            : nil) ?? textView.typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: 15)
        let removing = manager.traits(of: currentFont).contains(trait)
        let convert: (NSFont) -> NSFont = { font in
            removing
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
        }
        if range.length > 0 {
            textView.textStorage?.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: 15)
                textView.textStorage?.addAttribute(.font, value: convert(font), range: subrange)
            }
        }
        textView.typingAttributes[.font] = convert(currentFont)
    }
}

struct NotebookWorkspaceView: View {
    @Binding var workspace: Workspace
    @Binding var selectedNotebookID: UUID?
    var compact = false
    var onOpenMaterial: ((UUID, Int?) -> Void)?
    @StateObject private var editor = RichTextController()
    @State private var blockMessage: String?
    @State private var blockMessageSuccess = true

    private enum BlockConversionKind {
        case flashcard
        case task
        case question
    }

    var body: some View {
        Group {
            if compact {
                if let binding = selectedNotebookBinding {
                    notebookEditor(binding)
                } else {
                    emptyNotebook
                }
            } else {
                HSplitView {
                    notebookList
                        .frame(minWidth: 175, idealWidth: 210, maxWidth: 250)
                    if let binding = selectedNotebookBinding {
                        notebookEditor(binding)
                    } else {
                        emptyNotebook
                    }
                }
            }
        }
        .onAppear(perform: ensureNotebook)
        .onChange(of: workspace.id) { _, _ in
            selectedNotebookID = nil
            ensureNotebook()
        }
    }

    private var emptyNotebook: some View {
        ContentUnavailableView("Nenhum caderno", systemImage: "book.closed", description: Text("Crie um caderno para começar a escrever."))
    }

    private var notebookList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cadernos").font(.headline)
                Spacer()
                Button(action: addNotebook) { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("Novo caderno")
            }
            .padding(10)
            Divider()
            List(selection: $selectedNotebookID) {
                ForEach(workspace.notebooks ?? []) { notebook in
                    Label(notebook.title, systemImage: "book.closed")
                        .tag(notebook.id)
                        .contextMenu {
                            Button("Excluir caderno", role: .destructive) { deleteNotebook(notebook.id) }
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func notebookEditor(_ notebook: Binding<StudyNotebook>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if compact {
                    Menu {
                        ForEach(workspace.notebooks ?? []) { item in
                            Button {
                                selectedNotebookID = item.id
                            } label: {
                                if item.id == selectedNotebookID {
                                    Label(item.title, systemImage: "checkmark")
                                } else {
                                    Text(item.title)
                                }
                            }
                        }
                        Divider()
                        Button("Novo caderno", action: addNotebook)
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                TextField("Nome do caderno", text: notebook.title)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                Spacer()
                Button { editor.toggleBold() } label: { Image(systemName: "bold") }
                Button { editor.toggleItalic() } label: { Image(systemName: "italic") }
                Button { editor.toggleUnderline() } label: { Image(systemName: "underline") }
                Divider().frame(height: 18)
                Button("Título") { editor.setFontSize(24) }
                Button("Texto") { editor.setFontSize(15) }
                Button { editor.insertPrefix("• ") } label: { Image(systemName: "list.bullet") }
                Button { editor.insertPrefix("☐ ") } label: { Image(systemName: "checklist") }
                Divider().frame(height: 18)
                Menu {
                    Button("Flashcard") { createBlock(.flashcard) }
                    Button("Tarefa") { createBlock(.task) }
                    Button("Questão") { createBlock(.question) }
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .help("Transformar o parágrafo atual em item de revisão")
                if let blockMessage {
                    Label(blockMessage, systemImage: blockMessageSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(blockMessageSuccess ? Color.green : Color.orange)
                        .lineLimit(2)
                        .frame(maxWidth: 320, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            HStack(spacing: 10) {
                Picker("Material vinculado", selection: notebook.sourceMaterialID) {
                    Text("Sem vínculo").tag(UUID?.none)
                    ForEach(workspace.nodes.filter(\.isStudyMaterial)) { material in
                        Text(material.title).tag(Optional(material.id))
                    }
                }
                .frame(maxWidth: 280)
                if notebook.wrappedValue.sourceMaterialID != nil {
                    Stepper(
                        "Posição \((notebook.wrappedValue.sourcePageIndex ?? 0) + 1)",
                        value: Binding(
                            get: { (notebook.wrappedValue.sourcePageIndex ?? 0) + 1 },
                            set: { notebook.wrappedValue.sourcePageIndex = max(0, $0 - 1) }
                        ),
                        in: 1...100_000
                    )
                    Button("Abrir fonte") {
                        guard let id = notebook.wrappedValue.sourceMaterialID else { return }
                        onOpenMaterial?(id, notebook.wrappedValue.sourcePageIndex)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.035))

            RichTextEditor(
                rtfData: notebook.rtfData,
                plainText: notebook.plainText,
                controller: editor
            )
        }
    }

    private func createBlock(_ kind: BlockConversionKind) {
        guard let paragraph = editor.currentParagraph() else {
            showBlockMessage("Clique dentro de um parágrafo do caderno antes de transformar.", success: false)
            return
        }
        let notebook = workspace.notebooks?.first { $0.id == selectedNotebookID }
        switch kind {
        case .flashcard:
            guard let body = NotebookBlockConverter.flashcardBody(from: paragraph) else {
                showBlockMessage("Escreva “pergunta — resposta” em uma linha ou duas.", success: false)
                return
            }
            var artifacts = workspace.studyArtifacts ?? []
            artifacts.append(StudyArtifact(
                kind: .flashcards,
                body: body,
                sourceNodeID: notebook?.sourceMaterialID,
                sourcePageIndex: notebook?.sourcePageIndex
            ))
            workspace.studyArtifacts = artifacts
            showBlockMessage("Flashcard criado — revise no Estudar ou em Meu Progresso.", success: true)
        case .task:
            guard let title = NotebookBlockConverter.taskTitle(from: paragraph) else {
                showBlockMessage("O parágrafo está vazio.", success: false)
                return
            }
            var tasks = workspace.studyTasks ?? []
            tasks.append(StudyTask(
                title: title,
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            ))
            workspace.studyTasks = tasks
            showBlockMessage("Tarefa criada — veja em Meu Progresso.", success: true)
        case .question:
            guard let body = NotebookBlockConverter.questionBody(from: paragraph) else {
                showBlockMessage("O parágrafo está vazio.", success: false)
                return
            }
            var artifacts = workspace.studyArtifacts ?? []
            artifacts.append(StudyArtifact(
                kind: .question,
                body: body,
                sourceNodeID: notebook?.sourceMaterialID,
                sourcePageIndex: notebook?.sourcePageIndex
            ))
            workspace.studyArtifacts = artifacts
            showBlockMessage("Questão criada — responda no Estudar.", success: true)
        }
    }

    private func showBlockMessage(_ message: String, success: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            blockMessage = message
            blockMessageSuccess = success
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if blockMessage == message {
                withAnimation(.easeInOut(duration: 0.2)) { blockMessage = nil }
            }
        }
    }

    private var selectedNotebookBinding: Binding<StudyNotebook>? {
        guard let id = selectedNotebookID,
              workspace.notebooks?.contains(where: { $0.id == id }) == true else { return nil }
        return Binding(
            get: { workspace.notebooks?.first(where: { $0.id == id }) ?? StudyNotebook(title: "Caderno") },
            set: { updated in
                guard let index = workspace.notebooks?.firstIndex(where: { $0.id == id }) else { return }
                var saved = updated
                saved.updatedAt = Date()
                workspace.notebooks?[index] = saved
            }
        )
    }

    private func ensureNotebook() {
        if workspace.notebooks?.isEmpty != false {
            addNotebook()
        } else if selectedNotebookID == nil || workspace.notebooks?.contains(where: { $0.id == selectedNotebookID }) != true {
            selectedNotebookID = workspace.notebooks?.first?.id
        }
    }

    private func addNotebook() {
        var notebooks = workspace.notebooks ?? []
        let notebook = StudyNotebook(title: "Caderno \(notebooks.count + 1)")
        notebooks.append(notebook)
        workspace.notebooks = notebooks
        selectedNotebookID = notebook.id
    }

    private func deleteNotebook(_ id: UUID) {
        workspace.notebooks?.removeAll { $0.id == id }
        selectedNotebookID = workspace.notebooks?.first?.id
    }
}

private struct RichTextEditor: NSViewRepresentable {
    @Binding var rtfData: Data?
    @Binding var plainText: String
    let controller: RichTextController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.allowsUndo = true
        textView.textContainerInset = CGSize(width: 38, height: 32)
        textView.backgroundColor = .textBackgroundColor
        textView.font = .systemFont(ofSize: 15)
        textView.minSize = CGSize(width: 0, height: 0)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        controller.textView = textView
        context.coordinator.load(rtfData, plainText: plainText, into: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        controller.textView = textView
        if context.coordinator.lastData != rtfData {
            context.coordinator.load(rtfData, plainText: plainText, into: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var lastData: Data?
        private var loading = false

        init(_ parent: RichTextEditor) { self.parent = parent }

        func load(_ data: Data?, plainText: String, into textView: NSTextView) {
            loading = true
            if let data,
               let attributed = try? NSAttributedString(
                   data: data,
                   options: [.documentType: NSAttributedString.DocumentType.rtf],
                   documentAttributes: nil
               ) {
                textView.textStorage?.setAttributedString(attributed)
            } else {
                textView.string = plainText
            }
            lastData = data
            loading = false
        }

        func textDidChange(_ notification: Notification) {
            guard !loading, let textView = notification.object as? NSTextView else { return }
            let range = NSRange(location: 0, length: textView.attributedString().length)
            let data = try? textView.attributedString().data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            lastData = data
            parent.rtfData = data
            parent.plainText = textView.string
        }
    }
}
