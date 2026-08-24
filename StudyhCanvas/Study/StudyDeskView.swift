import SwiftUI
import CryptoKit

struct StudyDeskView: View {
    @Binding var workspace: Workspace
    @Binding var activeNodeID: UUID?
    var onOpenMaterial: () -> Void
    var onOpenGuide: () -> Void
    var onOpenYouTube: () -> Void
    var showsAssistantPanel = true

    @EnvironmentObject private var aiSettings: AISettings
    @State private var query = ""
    @State private var answer = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var activeQuestionID: UUID?
    @State private var requestTask: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var retryAction: StudyAssistantAction?
    @State private var showNoteSheet = false
    @State private var noteDraft = ""
    @State private var editingNoteID: UUID?
    @State private var editingAnnotationID: UUID?
    @State private var showNotesList = false
    @State private var loadedMaterialIDs: Set<UUID> = []
    @State private var preloadTask: Task<Void, Never>?

    private let ai = AIClient()

    var body: some View {
        HStack(spacing: 0) {
            materialArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsAssistantPanel {
                Divider()
                assistantPanel
                    .frame(minWidth: 350, idealWidth: 410, maxWidth: 480)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { preloadMaterials() }
        .onChange(of: activeNodeID) { _, newID in
            cancelRequest()
            errorText = nil
            answer = ""
            showNoteSheet = false
            showNotesList = false
            if let newID { loadedMaterialIDs.insert(newID) }
            activeQuestionID = latestQuestion?.id
        }
        .onChange(of: workspace.id) { _, _ in
            cancelRequest()
            preloadTask?.cancel()
            loadedMaterialIDs = []
            errorText = nil
            answer = ""
            activeQuestionID = latestQuestion?.id
            preloadMaterials()
        }
        .onDisappear {
            cancelRequest()
            preloadTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StudyhCanvasCommand"))) { note in
            guard note.object as? String == "newStudyNote", activeNode != nil else { return }
            beginNewNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .studyhReviewQuestion)) { notification in
            guard let artifactID = notification.userInfo?["artifactID"] as? UUID,
                  artifacts.contains(where: { $0.id == artifactID && $0.kind == .question }) else { return }
            activeQuestionID = artifactID
            answer = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .studyhOpenStudyNote)) { notification in
            guard let artifactID = notification.userInfo?["artifactID"] as? UUID,
                  let note = workspace.studyArtifacts?.first(where: { $0.id == artifactID && $0.kind == .note }) else { return }
            editNote(note)
        }
    }

    private var noteLocatorText: String? {
        guard let node = activeNode else { return nil }
        return "\(node.title) · \(noteLocator(for: node))"
    }

    private var noteSheet: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.caption.weight(.bold))
                Text("Nota")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    showNoteSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black.opacity(0.65))
                .accessibilityLabel("Fechar nota")
            }
            if let locator = noteLocatorText {
                Text(locator)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let quote = noteEditorQuote, !quote.isEmpty {
                Text("“\(quote)”")
                    .font(.caption2.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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
                Button("Salvar") { saveNote() }
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

    private func noteLocator(for node: CanvasNode) -> String {
        switch node.kind {
        case .epub: return "pág. \((node.epubPageIndex ?? 0) + 1)"
        case .pdf: return "pág. \(node.pdfPageIndex + 1)"
        case .slides: return "slide \((node.slidesPageIndex ?? 0) + 1)"
        case .web:
            let host = URL(string: node.webURL)?.host ?? "web"
            return String(host)
        case .note, .calc: return "nota"
        }
    }

    private func saveNote() {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let editingNoteID,
           let index = workspace.studyArtifacts?.firstIndex(where: { $0.id == editingNoteID }) {
            let prefix = workspace.studyArtifacts?[index].body.components(separatedBy: "\n").first ?? ""
            workspace.studyArtifacts?[index].body = prefix.hasPrefix("[") ? "\(prefix)\n\(text)" : text
            workspace.studyArtifacts?[index].updatedAt = Date()
            finishNoteEditing()
            return
        }
        guard let node = activeNode else { return }
        if let annotationID = editingAnnotationID,
           let nodeIndex = workspace.nodes.firstIndex(where: { $0.id == node.id }),
           let annotationIndex = workspace.nodes[nodeIndex].epubAnnotations?.firstIndex(where: { $0.id == annotationID }) {
            workspace.nodes[nodeIndex].epubAnnotations?[annotationIndex].note = text
            finishNoteEditing()
            return
        }
        let body = "[\(node.title) · \(noteLocator(for: node))]\n\(text)"
        var artifacts = workspace.studyArtifacts ?? []
        artifacts.append(StudyArtifact(
            kind: .note,
            body: body,
            sourceNodeID: node.id,
            sourcePageIndex: notePageIndex(for: node),
            sourceQuote: selectedQuote(for: node),
            sourceURL: node.kind == .web ? node.webURL : nil
        ))
        workspace.studyArtifacts = artifacts
        var events = workspace.studyActivityEvents ?? []
        events.append(StudyActivityEvent(kind: .createdNote, nodeID: node.id))
        workspace.studyActivityEvents = Array(events.suffix(2_000))
        finishNoteEditing()
    }

    private var noteEditorQuote: String? {
        if let editingAnnotationID {
            return materialAnnotationNotes.first(where: { $0.id == editingAnnotationID })?.quote
        }
        if let editingNoteID {
            return materialNotes.first(where: { $0.id == editingNoteID })?.sourceQuote
        }
        return activeNode.flatMap(selectedQuote(for:))
    }

    private func selectedQuote(for node: CanvasNode) -> String? {
        let text: String
        switch node.kind {
        case .pdf: text = node.pdfSelectedText
        case .web: text = node.webSelectedText
        case .slides: text = node.slidesSelectedText ?? ""
        case .epub, .note, .calc: return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func beginNewNote() {
        editingNoteID = nil
        editingAnnotationID = nil
        noteDraft = ""
        showNotesList = false
        showNoteSheet = true
    }

    private func editNote(_ note: StudyArtifact) {
        editingNoteID = note.id
        editingAnnotationID = nil
        noteDraft = editableBody(note.body)
        showNotesList = false
        showNoteSheet = true
    }

    private func editAnnotationNote(_ annotation: EPUBAnnotation) {
        editingNoteID = nil
        editingAnnotationID = annotation.id
        noteDraft = annotation.note ?? ""
        showNotesList = false
        showNoteSheet = true
    }

    private func editableBody(_ body: String) -> String {
        let parts = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, parts[0].hasPrefix("[") { return String(parts[1]) }
        return body
    }

    private func finishNoteEditing() {
        editingNoteID = nil
        editingAnnotationID = nil
        noteDraft = ""
        showNoteSheet = false
    }

    private func notePageIndex(for node: CanvasNode) -> Int? {
        switch node.kind {
        case .epub: return node.epubPageIndex ?? 0
        case .pdf: return node.pdfPageIndex
        case .slides: return node.slidesPageIndex ?? 0
        case .web, .note, .calc: return nil
        }
    }

    private var materialNotes: [StudyArtifact] {
        guard let activeNodeID else { return [] }
        return (workspace.studyArtifacts ?? []).filter {
            $0.kind == .note && $0.sourceNodeID == activeNodeID
        }
    }

    private var materialAnnotationNotes: [EPUBAnnotation] {
        guard activeNode?.kind == .epub else { return [] }
        return (activeNode?.epubAnnotations ?? []).filter {
            !($0.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var materialNoteCount: Int {
        materialNotes.count + materialAnnotationNotes.count
    }

    private func deleteNote(_ id: UUID) {
        workspace.studyArtifacts?.removeAll { $0.id == id }
        if materialNoteCount == 0 { showNotesList = false }
    }

    private func deleteAnnotationNote(_ id: UUID) {
        guard let activeNodeID,
              let nodeIndex = workspace.nodes.firstIndex(where: { $0.id == activeNodeID }) else { return }
        workspace.nodes[nodeIndex].epubAnnotations?.removeAll { $0.id == id }
        if materialNoteCount == 0 { showNotesList = false }
    }

    private func openNote(_ note: StudyArtifact) {
        guard let activeNodeID,
              let nodeIndex = workspace.nodes.firstIndex(where: { $0.id == activeNodeID }) else { return }
        let page = note.sourcePageIndex ?? legacyPageIndex(in: note.body)
        switch workspace.nodes[nodeIndex].kind {
        case .epub:
            if let page { workspace.nodes[nodeIndex].epubPageIndex = page }
        case .pdf:
            if let page { workspace.nodes[nodeIndex].pdfPageIndex = page }
            workspace.nodes[nodeIndex].pdfNavigationQuote = note.sourceQuote
        case .slides:
            if let page { workspace.nodes[nodeIndex].slidesPageIndex = page }
            workspace.nodes[nodeIndex].slidesNavigationQuote = note.sourceQuote
        case .web:
            if let url = note.sourceURL { workspace.nodes[nodeIndex].webURL = url }
            workspace.nodes[nodeIndex].webNavigationQuote = note.sourceQuote
        case .note, .calc:
            return
        }
        showNotesList = false
    }

    private func legacyPageIndex(in body: String) -> Int? {
        guard let range = body.range(of: #"pág\.\s*(\d+)"#, options: .regularExpression) else { return nil }
        let value = body[range].split(whereSeparator: { !$0.isNumber }).last.flatMap { Int($0) }
        return value.map { max(0, $0 - 1) }
    }

    private func openAnnotationNote(_ id: UUID) {
        guard let activeNodeID else { return }
        showNotesList = false
        NotificationCenter.default.post(
            name: .studyhOpenEPUBAnnotation,
            object: nil,
            userInfo: ["nodeID": activeNodeID, "annotationID": id]
        )
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Notas do material", systemImage: "note.text")
                    .font(.headline.weight(.semibold))
                Text("\(materialNoteCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    beginNewNote()
                } label: {
                    Label("Nova", systemImage: "plus")
                }
                .controlSize(.small)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(materialNotes) { note in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Label("Nota", systemImage: "doc.text")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Button {
                                    editNote(note)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Editar nota")
                                Button(role: .destructive) {
                                    deleteNote(note.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Excluir nota")
                            }
                            Button {
                                openNote(note)
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if let quote = note.sourceQuote, !quote.isEmpty {
                                            Text("“\(quote)”")
                                                .font(.callout.italic())
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(editableBody(note.body))
                                        .font(.body)
                                        .lineSpacing(3)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    }
                    ForEach(materialAnnotationNotes) { annotation in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Label("Trecho selecionado", systemImage: "text.quote")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(annotation.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Button {
                                    editAnnotationNote(annotation)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Editar nota")
                                Button(role: .destructive) {
                                    deleteAnnotationNote(annotation.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Excluir nota")
                            }
                            Button {
                                openAnnotationNote(annotation.id)
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("“\(annotation.quote)”")
                                            .font(.callout.italic())
                                            .foregroundStyle(.secondary)
                                            .lineSpacing(2)
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Divider()
                                        Text(annotation.note ?? "")
                                            .font(.body)
                                            .lineSpacing(3)
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 480)
        }
        .padding(16)
        .frame(width: 440)
    }

    private var materialArea: some View {
        Group {
            if let node = activeNodeBinding {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: node.wrappedValue.kind.icon)
                            .foregroundStyle(.secondary)
                        TextField("Nome do material", text: node.title)
                            .textFieldStyle(.plain)
                            .font(.headline)
                        Spacer()
                        if materialNoteCount == 0 {
                            Button {
                                beginNewNote()
                            } label: {
                                Label("Adicionar nota", systemImage: "square.and.pencil")
                            }
                            .controlSize(.small)
                            .help("Adicionar uma nota ao material")
                        } else {
                            Button {
                                showNotesList.toggle()
                            } label: {
                                ZStack {
                                    Circle().fill(Color.yellow)
                                    Text("\(materialNoteCount)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.black)
                                }
                                .frame(width: 23, height: 23)
                            }
                            .buttonStyle(.plain)
                            .help("Abrir notas")
                            .popover(isPresented: $showNotesList) { notesList }

                            Button {
                                beginNewNote()
                            } label: {
                                Image(systemName: "plus")
                            }
                            .controlSize(.small)
                            .help("Adicionar nota")
                        }
                        Text(materialKindLabel(for: node.wrappedValue.kind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.bar)

                    materialViews
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView {
                    Label("Comece pelo material", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Abra o PDF ou EPUB da aula, ou um material de pesquisa. Ele ficará grande aqui, pronto para ler e estudar.")
                } actions: {
                    HStack {
                        Button(action: onOpenMaterial) {
                            Label("Abrir PDF ou EPUB", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        Button(action: onOpenGuide) {
                            Label("Pesquisar guia", systemImage: "globe")
                        }
                        Button(action: onOpenYouTube) {
                            Label("YouTube", systemImage: "play.rectangle")
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showNoteSheet {
                noteSheet
                    .padding(10)
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showNoteSheet)
    }

    private var materialViews: some View {
        ZStack {
            ForEach(workspace.nodes.filter { $0.isStudyMaterial && loadedMaterialIDs.contains($0.id) }) { material in
                if let binding = nodeBinding(material.id) {
                    NodeContentView(node: binding)
                        .opacity(activeNodeID == material.id ? 1 : 0)
                        .allowsHitTesting(activeNodeID == material.id)
                        .accessibilityHidden(activeNodeID != material.id)
                        .zIndex(activeNodeID == material.id ? 1 : 0)
                }
            }
            if let activeNodeID, !loadedMaterialIDs.contains(activeNodeID) {
                ProgressView("Abrindo material…")
            }
        }
    }

    private func nodeBinding(_ id: UUID) -> Binding<CanvasNode>? {
        guard workspace.nodes.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                workspace.nodes.first(where: { $0.id == id })
                    ?? CanvasNode(kind: .note, frame: .default(for: .note, origin: .zero))
            },
            set: { updated in
                guard let index = workspace.nodes.firstIndex(where: { $0.id == id }) else { return }
                workspace.nodes[index] = updated
            }
        )
    }

    private func preloadMaterials() {
        preloadTask?.cancel()
        let materialIDs = workspace.nodes
            .filter { $0.isStudyMaterial && ($0.kind == .web || $0.kind == .slides) }
            .map(\.id)
        if let activeNodeID { loadedMaterialIDs.insert(activeNodeID) }
        preloadTask = Task {
            for id in materialIDs where !loadedMaterialIDs.contains(id) {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                loadedMaterialIDs.insert(id)
            }
        }
    }

    private var assistantPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Studyh", systemImage: "apple.intelligence")
                    .font(.headline)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button {
                    clearConversation()
                } label: {
                    Label("Nova conversa", systemImage: "plus.message")
                }
                .controlSize(.small)
                .disabled(artifacts.isEmpty && activeQuestion == nil)
                .help("Limpar esta conversa sem apagar o material")
            }
            .padding(12)

            HStack(spacing: 7) {
                Button("Explicar página") { run(.summary) }
                Button("Flashcards") { run(.flashcards) }
                Button("Criar questão") { run(.question) }
            }
            .controlSize(.small)
            .disabled(activeNode == nil || busy)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if artifacts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Estude sem trocar de app")
                                    .font(.headline)
                                Text("Peça uma explicação simples da página, faça uma pergunta ou transforme o que já leu em revisão.")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }

                        ForEach(artifacts) { artifact in
                            ArtifactCard(
                                artifact: artifact,
                                reviews: workspace.flashcardReviews ?? [],
                                allowedNewCount: flashcardPlan.first { $0.artifactID == artifact.id }?.new ?? 0,
                                onReviewFlashcard: { key, legacyKey, legacyFullKey, nodeID, deckID, rating in
                                    reviewFlashcard(
                                        key,
                                        legacyKey: legacyKey,
                                        legacyFullKey: legacyFullKey,
                                        sourceNodeID: nodeID,
                                        deckID: deckID,
                                        rating: rating
                                    )
                                }
                            )
                                .id(artifact.id)
                        }

                        if let errorText {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 6) {
                                    Label(errorText, systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.red)
                                        .font(.callout)
                                    Spacer()
                                    Button {
                                        self.errorText = nil
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Dispensar erro")
                                }
                                HStack {
                                    if let retryAction {
                                        Button("Tentar novamente") { run(retryAction) }
                                    }
                                    SettingsLink { Label("Abrir Ajustes de IA", systemImage: "gearshape") }
                                    Spacer()
                                }
                                .controlSize(.small)
                            }
                            .padding(10)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: artifacts.count) { _, _ in
                    if let id = artifacts.last?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }

            if let question = activeQuestion {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Responda antes de verificar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            run(.question)
                        } label: {
                            Label("Criar nova questão", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(busy)
                        Button {
                            activeQuestionID = nil
                            answer = ""
                        } label: {
                            Label("Sair", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Fechar o modo de questão")
                    }
                    if let multipleChoice = MultipleChoiceQuestion.parse(question.body) {
                        Text(multipleChoice.stem)
                            .font(.callout.weight(.medium))
                        ForEach(multipleChoice.options) { option in
                            Button {
                                answer = option.label + ") " + option.text
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: answer.hasPrefix(option.label + ")")
                                          ? "largecircle.fill.circle"
                                          : "circle")
                                    Text(option.label + ") " + option.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text(visibleQuestionBody(question.body))
                            .font(.callout)
                            .lineLimit(4)
                        PromptTextField(text: $answer, placeholder: "Sua resposta…") { value in
                            answer = value
                            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { verify(question) }
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Verificar resposta") { verify(question) }
                            .buttonStyle(.borderedProminent)
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                    }
                }
                .padding(10)
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                PromptTextField(text: $query, placeholder: "Pergunte sobre o material…") { value in
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendQuestion(value)
                    }
                }
                Button("Enviar") { sendQuestion() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeNode == nil || busy)
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func materialKindLabel(for kind: NodeKind) -> String {
        switch kind {
        case .pdf: return "Página atual"
        case .epub: return "Livro"
        case .web: return "Pesquisa"
        case .slides: return "Slides"
        case .note: return "Nota"
        case .calc: return "Resolução"
        }
    }

    private var activeNode: CanvasNode? {
        guard let activeNodeID else { return nil }
        return workspace.nodes.first { $0.id == activeNodeID }
    }

    private var activeNodeBinding: Binding<CanvasNode>? {
        guard let id = activeNodeID,
              workspace.nodes.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                workspace.nodes.first(where: { $0.id == id })
                    ?? CanvasNode(kind: .note, frame: .default(for: .note, origin: .zero))
            },
            set: { updated in
                guard let index = workspace.nodes.firstIndex(where: { $0.id == id }) else { return }
                workspace.nodes[index] = updated
            }
        )
    }

    private var artifacts: [StudyArtifact] {
        let all = workspace.studyArtifacts ?? []
        guard let activeNodeID else { return all }
        return all.filter { $0.sourceNodeID == nil || $0.sourceNodeID == activeNodeID }
    }

    private var latestQuestion: StudyArtifact? {
        artifacts.last { $0.kind == .question }
    }

    private var activeQuestion: StudyArtifact? {
        guard let activeQuestionID else { return nil }
        return artifacts.first { $0.id == activeQuestionID && $0.kind == .question }
    }

    private func run(_ action: StudyAssistantAction) {
        guard let source = activeNode else { return }
        retryAction = action
        var context = studyContext(for: action, source: source)
        var previousQuestionBodies: [String] = []
        if action == .question {
            previousQuestionBodies = artifacts
                .filter { $0.kind == .question }
                .suffix(5)
                .map(\.body)
            if !previousQuestionBodies.isEmpty {
                let exclusion = previousQuestionBodies.enumerated()
                    .map { "\($0.offset + 1). \($0.element)" }
                    .joined(separator: "\n")
                // Put the exclusion before the long reading context: the CLI
                // prompt is bounded, so instructions at the end could be cut.
                context = "[Questões já usadas; crie uma diferente]\n\(exclusion)\n\n" + context
            }
            let nextFormat = previousQuestionBodies.count.isMultiple(of: 2)
                ? "múltipla escolha"
                : "resposta curta"
            context = "[Formato da próxima questão: \(nextFormat)]\n" + context
        }
        guard !context.isEmpty, context != source.webURL else {
            switch source.kind {
            case .pdf:
                errorText = "A página ainda não tem texto extraído. Aguarde um instante ou avance para uma página com texto."
            case .epub:
                errorText = "O texto do livro ainda está sendo preparado. Aguarde um instante e tente novamente."
            default:
                errorText = "Selecione texto na página com “Usar seleção” ou aguarde o carregamento."
            }
            return
        }
        busy = true
        errorText = nil
        let workspaceID = workspace.id
        let sourceID = source.id
        let token = UUID()
        requestID = token
        requestTask = Task {
            defer { finishRequest(token) }
            do {
                var response = try await ai.study(
                    action: action,
                    context: context,
                    settings: aiSettings
                )
                if action == .question,
                   isRepeatedQuestion(response, comparedTo: previousQuestionBodies) {
                    try Task.checkCancellation()
                    let retryContext = "[A questão gerada abaixo foi repetida. Ignore-a e crie outra sobre um aspecto diferente do material.]\n\(response)\n\n\(context)"
                    response = try await ai.study(
                        action: .question,
                        context: retryContext,
                        settings: aiSettings
                    )
                }
                try Task.checkCancellation()
                guard isCurrent(workspaceID: workspaceID, sourceID: sourceID, requestID: token) else { return }
                let kind: StudyArtifactKind
                switch action {
                case .summary: kind = .summary
                case .flashcards: kind = .flashcards
                case .question: kind = .question
                case .ask: kind = .assistantMessage
                }
                let artifact = StudyArtifact(
                    kind: kind,
                    body: response,
                    sourceNodeID: sourceID,
                    sourcePageIndex: action == .flashcards ? notePageIndex(for: source) : nil
                )
                append(artifact, workspaceID: workspaceID, sourceID: sourceID)
                if kind == .question {
                    activeQuestionID = artifact.id
                    answer = ""
                }
            } catch {
                if !Task.isCancelled,
                   isCurrent(workspaceID: workspaceID, sourceID: sourceID, requestID: token) {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func sendQuestion(_ submittedText: String? = nil) {
        let message = (submittedText ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        guard let source = activeNode else {
            errorText = "Escolha um material antes de fazer a pergunta."
            return
        }
        let workspaceID = workspace.id
        let sourceID = source.id
        let context = (source.kind == .epub ? source.epubQuestionContext : source.contextExcerpt)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        append(
            StudyArtifact(kind: .userMessage, body: message, sourceNodeID: sourceID),
            workspaceID: workspaceID,
            sourceID: sourceID
        )
        query = ""
        busy = true
        errorText = nil
        let token = UUID()
        requestID = token
        requestTask = Task {
            defer { finishRequest(token) }
            do {
                let response = try await ai.study(
                    action: .ask,
                    query: message,
                    context: context,
                    settings: aiSettings
                )
                try Task.checkCancellation()
                guard isCurrent(workspaceID: workspaceID, sourceID: sourceID, requestID: token) else { return }
                append(
                    StudyArtifact(kind: .assistantMessage, body: response, sourceNodeID: sourceID),
                    workspaceID: workspaceID,
                    sourceID: sourceID
                )
            } catch {
                if !Task.isCancelled,
                   isCurrent(workspaceID: workspaceID, sourceID: sourceID, requestID: token) {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func verify(_ question: StudyArtifact) {
        guard let source = activeNode else { return }
        let workspaceID = workspace.id
        let sourceID = source.id
        let attempt = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let multipleChoice = MultipleChoiceQuestion.parse(question.body),
           let correctLabel = multipleChoice.correctLabel,
           let selectedLabel = attempt.first.map({ String($0).uppercased() }),
           multipleChoice.options.contains(where: { $0.label == selectedLabel }) {
            let feedback: String
            if selectedLabel == correctLabel {
                feedback = "✓ Correto! Você marcou a alternativa \(selectedLabel)."
            } else {
                feedback = "✗ Ainda não. A alternativa \(selectedLabel) não corresponde ao trecho. Tente reler a explicação e escolher novamente."
            }
            append(
                StudyArtifact(kind: .feedback, body: feedback, sourceNodeID: sourceID),
                workspaceID: workspaceID,
                sourceID: sourceID
            )
            recordQuestionReview(question)
            return
        }

        busy = true
        errorText = nil
        let token = UUID()
        requestID = token
        requestTask = Task {
            defer { finishRequest(token) }
            do {
                let response = try await ai.study(
                    action: .ask,
                    query: "Avalie esta resposta de uma questão de estudo. Diga primeiro ‘Correto’ ou ‘Ainda não’. Explique em uma ou duas frases por quê, sem usar o formato Leitura/Alerta/Tente e sem tratar a resposta já enviada como se fosse apenas um cálculo a refazer. Questão:\n\(question.body)\n\nResposta escolhida pelo estudante:\n\(attempt)",
                    context: source.kind == .epub ? source.epubQuestionContext : source.contextExcerpt,
                    settings: aiSettings
                )
                try Task.checkCancellation()
                guard isCurrent(workspaceID: workspaceID, sourceID: sourceID, requestID: token) else { return }
                append(
                    StudyArtifact(kind: .feedback, body: response, sourceNodeID: sourceID),
                    workspaceID: workspaceID,
                    sourceID: sourceID
                )
                recordQuestionReview(question)
            } catch {
                if !Task.isCancelled,
                   isCurrent(workspaceID: workspaceID, sourceID: sourceID, requestID: token) {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func append(_ artifact: StudyArtifact, workspaceID: UUID, sourceID: UUID) {
        guard workspace.id == workspaceID,
              activeNodeID == sourceID,
              workspace.nodes.contains(where: { $0.id == sourceID }) else { return }
        var saved = workspace.studyArtifacts ?? []
        saved.append(artifact)
        workspace.studyArtifacts = saved
    }

    private func recordQuestionReview(_ question: StudyArtifact) {
        var events = workspace.studyActivityEvents ?? []
        events.append(StudyActivityEvent(
            kind: .reviewedQuestion,
            nodeID: question.sourceNodeID,
            artifactID: question.id
        ))
        workspace.studyActivityEvents = Array(events.suffix(2_000))
    }

    private func isCurrent(workspaceID: UUID, sourceID: UUID, requestID: UUID) -> Bool {
        workspace.id == workspaceID
            && activeNodeID == sourceID
            && self.requestID == requestID
            && workspace.nodes.contains(where: { $0.id == sourceID })
    }

    private func finishRequest(_ token: UUID) {
        guard requestID == token else { return }
        requestTask = nil
        requestID = nil
        busy = false
    }

    private func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        requestID = nil
        busy = false
    }

    private func reviewFlashcard(
        _ key: String,
        legacyKey: String,
        legacyFullKey: String,
        sourceNodeID: UUID?,
        deckID: UUID,
        rating: FlashcardRating
    ) {
        var reviews = workspace.flashcardReviews ?? []
        let now = Date()
        let existingIndex = reviews.firstIndex {
            ($0.key == key || $0.key == legacyKey || $0.key == legacyFullKey)
                && $0.sourceNodeID == sourceNodeID
                && ($0.deckID == deckID || $0.deckID == nil)
        }
        var review = existingIndex.map { reviews[$0] }
            ?? FlashcardReview(key: key, sourceNodeID: sourceNodeID, deckID: deckID)
        review.key = key
        review.deckID = deckID

        switch rating {
        case .hard:
            review.repetitions = 0
            review.intervalDays = 1
            review.easeFactor = max(1.3, review.easeFactor - 0.2)
        case .good:
            review.repetitions += 1
            review.intervalDays = review.repetitions <= 1
                ? 1
                : max(2, review.intervalDays * review.easeFactor)
        case .easy:
            review.repetitions += 1
            review.easeFactor += 0.15
            review.intervalDays = review.repetitions <= 1
                ? 4
                : max(4, review.intervalDays * review.easeFactor * 1.3)
        }
        review.lastRating = rating
        review.lastReviewedAt = now
        if review.firstReviewedAt == nil { review.firstReviewedAt = now }
        review.dueAt = now.addingTimeInterval(review.intervalDays * 86_400)

        if let existingIndex {
            reviews[existingIndex] = review
        } else {
            reviews.append(review)
        }
        workspace.flashcardReviews = reviews
        var events = workspace.studyActivityEvents ?? []
        events.append(StudyActivityEvent(kind: .reviewedFlashcard, nodeID: sourceNodeID, artifactID: deckID))
        workspace.studyActivityEvents = Array(events.suffix(2_000))
    }

    private var flashcardPlan: [FlashcardPlanItem] {
        ProgressMetrics.flashcardPlan(
            artifacts: workspace.studyArtifacts ?? [],
            reviews: workspace.flashcardReviews ?? []
        )
    }

    private func clearConversation() {
        guard let activeNodeID else { return }
        cancelRequest()
        let conversationKinds: Set<StudyArtifactKind> = [
            .summary, .userMessage, .assistantMessage, .question, .feedback
        ]
        workspace.studyArtifacts?.removeAll {
            $0.sourceNodeID == activeNodeID && conversationKinds.contains($0.kind)
        }
        activeQuestionID = nil
        answer = ""
        query = ""
        errorText = nil
    }

    private func studyContext(for action: StudyAssistantAction, source: CanvasNode) -> String {
        let context: String
        if action == .flashcards {
            context = source.flashcardContext
        } else if source.kind == .epub && action == .question {
            context = source.epubProgressContext
        } else {
            context = source.contextExcerpt
        }
        return context.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isRepeatedQuestion(_ candidate: String, comparedTo previous: [String]) -> Bool {
        guard let currentStem = questionStem(candidate) else { return false }
        let currentWords = normalizedQuestionWords(currentStem)
        guard currentWords.count >= 4 else { return false }
        return previous.contains { body in
            guard let oldStem = questionStem(body) else { return false }
            let oldWords = normalizedQuestionWords(oldStem)
            guard oldWords.count >= 4 else { return false }
            let overlap = currentWords.intersection(oldWords).count
            let denominator = min(currentWords.count, oldWords.count)
            return currentWords == oldWords || Double(overlap) / Double(denominator) >= 0.8
        }
    }

    private func questionStem(_ body: String) -> String? {
        if let multipleChoice = MultipleChoiceQuestion.parse(body) {
            return multipleChoice.stem
        }
        return body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.lowercased().hasPrefix("pergunta:") }
            .map { $0.replacingOccurrences(of: "Pergunta:", with: "", options: .caseInsensitive) }
    }

    private func normalizedQuestionWords(_ text: String) -> Set<String> {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "pt_BR")
        )
        let cleaned = folded.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        return Set(cleaned.split(separator: " ").map(String.init))
    }
}

private struct ArtifactCard: View {
    let artifact: StudyArtifact
    let reviews: [FlashcardReview]
    let allowedNewCount: Int
    let onReviewFlashcard: (String, String, String, UUID?, UUID, FlashcardRating) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(artifact.kind.label, systemImage: artifact.kind.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if artifact.kind == .flashcards,
               let cards = StudyFlashcard.parseDeck(artifact.body),
               !cards.isEmpty {
                FlashcardDeckView(
                    cards: cards,
                    reviews: reviews,
                    sourceNodeID: artifact.sourceNodeID,
                    deckID: artifact.id,
                    allowedNewCount: allowedNewCount,
                    onReview: onReviewFlashcard
                )
            } else if artifact.kind == .question,
                      let question = MultipleChoiceQuestion.parse(artifact.body) {
                QuestionArtifactView(question: question)
            } else if artifact.kind == .question {
                Text(visibleQuestionBody(artifact.body))
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                StudyRichText(artifact.body)
            }
        }
        .padding(11)
        .background(
            artifact.kind == .userMessage ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}

private struct PromptTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PromptTextField

        init(_ parent: PromptTextField) {
            self.parent = parent
        }

        @MainActor @objc func submit(_ sender: NSTextField) {
            parent.text = sender.stringValue
            parent.onSubmit(sender.stringValue)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.text = textView.string
                parent.onSubmit(textView.string)
                return true
            }
            return false
        }
    }
}

private struct StudyRichText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var bodyView: some View {
        let attributed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        return Text(attributed)
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View { bodyView }
}

struct StudyFlashcard: Identifiable {
    let front: String
    let back: String

    var id: String { flashcardKey(front: front, back: back) }
    var legacyID: String { legacyFlashcardKey(front: front) }
    var legacyFullID: String { legacyFlashcardKey(front: front, back: back) }

    static func parseDeck(_ body: String) -> [StudyFlashcard]? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)\*{0,2}Frente:\*{0,2}\s*(.*?)\s*\*{0,2}Verso:\*{0,2}\s*(.*?)(?=\n\s*\*{0,2}Frente:|\z)"#
        ) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let cards = expression.matches(in: body, range: range).compactMap { match -> StudyFlashcard? in
            guard let frontRange = Range(match.range(at: 1), in: body),
                  let backRange = Range(match.range(at: 2), in: body) else { return nil }
            let front = body[frontRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = body[backRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { return nil }
            return StudyFlashcard(front: front, back: back)
        }
        return cards.isEmpty ? nil : cards
    }
}

private struct FlashcardDeckView: View {
    let cards: [StudyFlashcard]
    let reviews: [FlashcardReview]
    let sourceNodeID: UUID?
    let deckID: UUID
    let allowedNewCount: Int
    let onReview: (String, String, String, UUID?, UUID, FlashcardRating) -> Void
    @State private var currentCardID: String?
    @State private var showingBack = false
    @State private var isOpen = true
    @State private var completed = false

    private var orderedCards: [StudyFlashcard] {
        let due = cards.filter { review(for: $0).map { $0.dueAt <= Date() } == true }
        let new = cards.filter { review(for: $0) == nil }.prefix(allowedNewCount)
        return due + new
    }

    private var currentIndex: Int {
        orderedCards.firstIndex { $0.id == currentCardID } ?? 0
    }

    private var currentCard: StudyFlashcard { orderedCards[currentIndex] }

    private var dueCount: Int {
        cards.filter { card in
            review(for: card).map { $0.dueAt <= Date() } ?? false
        }.count
    }

    private var newCount: Int {
        cards.filter { review(for: $0) == nil }.count
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Flashcards", systemImage: "rectangle.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    restartFlashcards()
                } label: {
                    Label("Refazer", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(isOpen ? "Fechar" : "Abrir") {
                    withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if isOpen {
                if completed {
                    VStack(spacing: 8) {
                        Label("Flashcards concluídos", systemImage: "checkmark.seal.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("Você passou por todos os \(cards.count) flashcards.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Rever flashcards", action: restartFlashcards)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } else if orderedCards.isEmpty {
                    Label("Nada para revisar agora", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                } else {
                    deckBody
                }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .onReceive(NotificationCenter.default.publisher(for: .studyhReviewFlashcards)) { notification in
            guard notification.userInfo?["artifactID"] as? UUID == deckID else { return }
            restartFlashcards()
        }
    }

    private var deckBody: some View {
        VStack(spacing: 10) {
            let currentReview = review(for: currentCard)
            HStack {
                Text(currentReview.map {
                    $0.dueAt <= Date()
                        ? "Para revisar agora"
                        : "Próxima: \($0.dueAt.formatted(date: .abbreviated, time: .omitted))"
                } ?? "Novo cartão")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(dueCount) devidos · \(allowedNewCount) novos hoje")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(showingBack ? "VERSO" : "FRENTE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(showingBack ? currentCard.back : currentCard.front)
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
                .multilineTextAlignment(.center)
            Button(showingBack ? "Ver pergunta" : "Virar cartão") {
                withAnimation(.easeInOut(duration: 0.2)) { showingBack.toggle() }
            }
            .buttonStyle(.borderedProminent)
            HStack(spacing: 6) {
                ForEach(FlashcardRating.allCases) { rating in
                    Button(rating.label) {
                        let isLast = currentIndex == orderedCards.count - 1
                        onReview(
                            currentCard.id,
                            currentCard.legacyID,
                            currentCard.legacyFullID,
                            sourceNodeID,
                            deckID,
                            rating
                        )
                        if isLast {
                            completed = true
                            showingBack = false
                        } else {
                            currentCardID = orderedCards[currentIndex + 1].id
                            showingBack = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!showingBack)
                    .accessibilityHint(showingBack ? "" : "Vire o cartão antes de avaliar")
                }
            }
            HStack {
                Button {
                    currentCardID = orderedCards[max(0, currentIndex - 1)].id
                    showingBack = false
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentIndex == 0)
                .accessibilityLabel("Cartão anterior")
                Spacer()
                Text("\(currentIndex + 1) de \(orderedCards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button {
                    currentCardID = orderedCards[min(orderedCards.count - 1, currentIndex + 1)].id
                    showingBack = false
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentIndex == orderedCards.count - 1)
                .accessibilityLabel("Próximo cartão")
            }
        }
    }

    private func review(for card: StudyFlashcard) -> FlashcardReview? {
        reviews.first {
            ($0.key == card.id || $0.key == card.legacyID || $0.key == card.legacyFullID)
                && $0.sourceNodeID == sourceNodeID
                && ($0.deckID == deckID || $0.deckID == nil)
        }
    }

    private func restartFlashcards() {
        isOpen = true
        completed = false
        currentCardID = orderedCards.first?.id
        showingBack = false
    }
}

private func flashcardKey(front: String, back: String) -> String {
    let joined = normalizedFlashcardText(front) + "\u{1F}" + normalizedFlashcardText(back)
    let digest = SHA256.hash(data: Data(joined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func legacyFlashcardKey(front: String, back: String) -> String {
    normalizedFlashcardText(front) + "\u{1F}" + normalizedFlashcardText(back)
}

private func legacyFlashcardKey(front: String) -> String {
    String(normalizedFlashcardText(front).prefix(240))
}

private func normalizedFlashcardText(_ text: String) -> String {
    text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func visibleQuestionBody(_ body: String) -> String {
    body.components(separatedBy: .newlines)
        .filter { line in
            let normalized = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .lowercased()
            return !normalized.hasPrefix("gabarito:")
                && !normalized.hasPrefix("gabarito interno:")
                && !normalized.hasPrefix("tipo: resposta curta")
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct QuestionArtifactView: View {
    let question: MultipleChoiceQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(question.stem)
                .font(.callout.weight(.medium))
            ForEach(question.options) { option in
                Text("\(option.label)) \(option.text)")
                    .font(.callout)
            }
        }
    }
}

private struct MultipleChoiceQuestion {
    struct Option: Identifiable {
        var id: String { label }
        let label: String
        let text: String
    }

    let stem: String
    let options: [Option]
    let correctLabel: String?

    static func parse(_ body: String) -> MultipleChoiceQuestion? {
        let lines = body.components(separatedBy: .newlines)
        var stemLines: [String] = []
        var options: [Option] = []
        var correctLabel: String?
        for rawLine in lines {
            let line = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
            guard !line.isEmpty else { continue }
            if let match = line.range(of: #"(?i)^(?:gabarito|resposta\s+correta)\s*:\s*([A-D])\b"#, options: .regularExpression) {
                let value = String(line[match])
                correctLabel = value
                    .split(separator: ":", maxSplits: 1)
                    .last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(1)
                    .uppercased()
                continue
            }
            if line.count > 3 {
                let label = String(line.prefix(1)).uppercased()
                let separator = line.dropFirst().first
                if ["A", "B", "C", "D"].contains(label), separator == ")" || separator == "." {
                    let text = line.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
                    options.append(Option(label: label, text: text))
                    continue
                }
            }
            if options.isEmpty {
                stemLines.append(line.replacingOccurrences(of: "Pergunta:", with: ""))
            }
        }
        guard options.count >= 2 else { return nil }
        return MultipleChoiceQuestion(
            stem: stemLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            options: options,
            correctLabel: correctLabel
        )
    }
}
