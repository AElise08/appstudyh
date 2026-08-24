import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var aiSettings: AISettings
    @Environment(\.undoManager) private var undoManager
    @StateObject private var canvas = CanvasController()
    @StateObject private var focusTimer = FocusTimerController()
    @State private var renameDraft = ""
    @State private var aiTask: Task<Void, Never>?
    @State private var appMode: AppMode = .study
    @State private var pendingDestructiveAction: PendingDestructiveAction?
    @State private var renameTask: Task<Void, Never>?
    @State private var examEditorTarget: ExamEditorTarget?
    @State private var taskEditorTarget: TaskEditorTarget?
    @State private var showGlobalSearch = false
    @State private var exportMessage: String?
    @State private var vaultImporting = false
    @State private var showWidgets = false
    @State private var selectedNotebookID: UUID?
    @State private var notebookLayout: NotebookLayout = .only
    @State private var showAIOnboarding = false

    struct ExamEditorTarget: Identifiable {
        let id = UUID()
        let workspaceID: UUID
        var examDraft: Date?
        var presentationDraft: Date?
    }

    struct TaskEditorTarget: Identifiable {
        let id = UUID()
        let workspaceID: UUID
        var taskID: UUID?
        var title = ""
        var dueDate: Date
        var priority: StudyTaskPriority = .normal
    }

    private let ai = AIClient()
    private let focusTicks = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .onAppear {
            renameDraft = store.selectedWorkspace?.name ?? ""
            selectDefaultMaterial()
            showAIOnboarding = !aiSettings.hasCompletedAIOnboarding
        }
        .onChange(of: store.selectedID) { _, _ in
            aiTask?.cancel()
            canvas.aiBusy = false
            renameDraft = store.selectedWorkspace?.name ?? ""
            canvas.selectedNodeIDs = []
            canvas.selectedInkStrokeIDs = []
            canvas.inspectedNodeID = nil
            canvas.aiPanelText = ""
            canvas.aiError = nil
            selectedNotebookID = nil
            selectDefaultMaterial()
        }
        .onChange(of: appMode) { _, mode in
            guard mode == .desk,
                  let scale = store.selectedWorkspace?.cameraScale,
                  scale < 0.6 else { return }
            store.updateSelected { canvas.zoom(by: 0.6 / max(0.01, scale), in: &$0) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.persistNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StudyhCanvasCommand"))) { note in
            guard let command = note.object as? String else { return }
            handleCanvasCommand(command)
        }
        .onReceive(focusTicks) { date in
            if let completion = focusTimer.tick(at: date) {
                completeFocusSession(completion)
            }
        }
        .alert(item: $pendingDestructiveAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text(action.buttonTitle)) {
                    performDestructiveAction(action)
                },
                secondaryButton: .cancel(Text("Cancelar"))
            )
        }
        .sheet(item: $examEditorTarget) { _ in
            deadlineEditor
        }
        .sheet(item: $taskEditorTarget) { _ in
            taskEditor
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchView(workspaces: store.workspaces, onOpen: openSearchResult)
        }
        .sheet(isPresented: $showAIOnboarding) {
            AIOnboardingView().environmentObject(aiSettings)
        }
        .alert(
            "Obsidian",
            isPresented: Binding(
                get: { exportMessage != nil },
                set: { if !$0 { exportMessage = nil } }
            )
        ) {
            Button("OK") { exportMessage = nil }
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Matérias")
                    .font(.headline)
                Spacer()
                Button {
                    store.createWorkspace()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Nova matéria")
                .accessibilityLabel("Nova matéria")
            }
            .padding(12)

            List {
                Section("Matérias") {
                    ForEach(prioritizedWorkspaces) { workspace in
                        Button {
                            store.selectedID = workspace.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workspace.name)
                                    if let progress = subjectProgress(workspace) {
                                        HStack(spacing: 6) {
                                            ProgressView(value: progress.fraction ?? 0)
                                                .progressViewStyle(.linear)
                                                .frame(width: 72)
                                            Text(progress.label)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if let date = workspace.examDate {
                                        Text("Prova · \(examLabel(date))")
                                            .font(.caption2)
                                            .foregroundStyle(examColor(date))
                                    }
                                    if let date = workspace.presentationDate {
                                        Text("Apresentação · \(examLabel(date))")
                                            .font(.caption2)
                                            .foregroundStyle(examColor(date))
                                    }
                                }
                                Spacer()
                                if store.selectedID == workspace.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            store.selectedID == workspace.id
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                        .contextMenu {
                            Button("Definir prova / apresentação…") {
                                examEditorTarget = ExamEditorTarget(
                                    workspaceID: workspace.id,
                                    examDraft: workspace.examDate,
                                    presentationDraft: workspace.presentationDate
                                )
                            }
                            if workspace.examDate != nil || workspace.presentationDate != nil {
                                Button("Remover datas", role: .destructive) {
                                    store.updateSelectedByID(workspace.id) { ws in
                                        ws.examDate = nil
                                        ws.presentationDate = nil
                                    }
                                }
                            }
                            Button("Apagar", role: .destructive) {
                                pendingDestructiveAction = .workspace(workspace.id, workspace.name)
                            }
                        }
                    }
                }

                Section("Materiais") {
                    ForEach(studyMaterials) { node in
                        Button {
                            activateMaterial(node.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: node.kind.icon)
                                    Text(node.title)
                                        .lineLimit(1)
                                    Spacer()
                                    if canvas.activeStudyNodeID == node.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let progress = materialProgress(node) {
                                    HStack(spacing: 6) {
                                        if let fraction = progress.fraction {
                                            ProgressView(value: fraction)
                                                .progressViewStyle(.linear)
                                                .frame(width: 72)
                                        }
                                        Text(progress.label)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remover material", role: .destructive) {
                                let impact = store.selectedWorkspace?.removalImpact(for: [node.id]) ?? WorkspaceRemovalImpact()
                                pendingDestructiveAction = .material(node.id, node.title, impact)
                            }
                        }
                    }
                }

                if !recentHistory.isEmpty {
                    Section("Histórico") {
                        ForEach(recentHistory) { entry in
                            if let node = studyMaterials.first(where: { $0.id == entry.nodeID }) {
                                Button {
                                    activateMaterial(node.id)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(node.title).lineLimit(1)
                                            Text(historyLabel(entry, node: node))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            HStack(spacing: 8) {
                Button(action: openMaterial) { Label("Abrir", systemImage: "doc.badge.plus") }
                Button(action: openGuide) { Image(systemName: "globe") }
                    .help("Abrir pesquisa")
                    .accessibilityLabel("Abrir pesquisa")
                Button(action: openYouTube) { Image(systemName: "play.rectangle") }
                    .help("Abrir YouTube")
                    .accessibilityLabel("Abrir YouTube")
            }
            .controlSize(.small)
            .padding(10)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if store.selectedWorkspace != nil {
            VStack(spacing: 0) {
                if let message = store.saveState.failureMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(message)
                            .font(.callout)
                            .lineLimit(2)
                        Spacer()
                        Button("Tentar salvar") {
                            store.persistNow()
                        }
                        Button("Abrir pasta de dados") {
                            NSWorkspace.shared.open(store.dataDirectoryURL)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.14))
                }
                primaryToolbar
                studyJourneyBar
                HStack(spacing: 0) {
                    modeContent
                    if showWidgets, let workspace = store.selectedWorkspace {
                        Divider()
                        StudyWidgetsSidebar(
                            workspace: workspace,
                            activeMaterial: activeStudyMaterial,
                            timer: focusTimer,
                            onShowProgress: { appMode = .progress },
                            onClose: { showWidgets = false }
                        )
                        .frame(width: 260)
                    }
                }
            }
        } else {
            VStack(spacing: 14) {
                ContentUnavailableView("Nenhum workspace", systemImage: "square.dashed")
                if let message = store.saveState.failureMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                    Button("Abrir pasta de dados") {
                        NSWorkspace.shared.open(store.dataDirectoryURL)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch appMode {
        case .study:
            studyContent(showsAssistant: true)
        case .desk:
            VStack(spacing: 0) {
                canvasToolbar
                deskCanvas
            }
        case .notebook:
            notebookContent
        case .progress:
            ProgressDashboardView(
                workspace: workspaceBinding,
                onOpenMaterial: activateMaterial,
                onOpenTask: openProgressTask,
                onToggleTask: toggleProgressTask,
                onReviewQuestion: reviewQuestionLater,
                onReviewFlashcards: reviewFlashcardsLater,
                onCreateTask: startTaskEditor,
                onToggleStudyTask: toggleStudyTask,
                onEditStudyTask: editStudyTask,
                onDeleteStudyTask: requestDeleteStudyTask,
                onEditDeadlines: openDeadlineEditor,
                onExportHTML: exportReviewHTML
            )
        }
    }

    private func studyContent(showsAssistant: Bool) -> some View {
        StudyDeskView(
            workspace: workspaceBinding,
            activeNodeID: $canvas.activeStudyNodeID,
            onOpenMaterial: openMaterial,
            onOpenGuide: openGuide,
            onOpenYouTube: openYouTube,
            onSelectMaterial: activateMaterial,
            showsAssistantPanel: showsAssistant
        )
    }

    private var deskCanvas: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                InfiniteCanvasView(
                    workspace: workspaceBinding,
                    canvas: canvas,
                    onOpenNode: openDeskNode
                )
                LassoAIBar(
                    canvas: canvas,
                    selectedCount: canvas.selectedNodeIDs.count + canvas.selectedInkStrokeIDs.count,
                    onRun: runAI
                )
                .padding(.bottom, 18)
            }

            if let node = inspectedNodeBinding {
                Divider()
                NodeInspector(node: node) {
                    canvas.inspectedNodeID = nil
                }
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 620)
            }
        }
    }

    private var notebookContent: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Layout do caderno", selection: $notebookLayout) {
                    ForEach(NotebookLayout.allCases) { layout in
                        Label(layout.label, systemImage: layout.icon).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 470)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)

            switch notebookLayout {
            case .only:
                NotebookWorkspaceView(
                    workspace: workspaceBinding,
                    selectedNotebookID: $selectedNotebookID,
                    onOpenMaterial: openNotebookMaterial
                )
            case .study:
                HSplitView {
                    studyContent(showsAssistant: false).frame(minWidth: 500)
                    NotebookWorkspaceView(
                        workspace: workspaceBinding,
                        selectedNotebookID: $selectedNotebookID,
                        compact: true,
                        onOpenMaterial: openNotebookMaterial
                    )
                    .frame(minWidth: 430)
                }
            case .desk:
                VStack(spacing: 0) {
                    canvasToolbar
                    HSplitView {
                        deskCanvas.frame(minWidth: 500)
                        NotebookWorkspaceView(
                            workspace: workspaceBinding,
                            selectedNotebookID: $selectedNotebookID,
                            compact: true,
                            onOpenMaterial: openNotebookMaterial
                        )
                        .frame(minWidth: 430)
                    }
                }
            }
        }
    }

    private var primaryToolbar: some View {
        HStack(spacing: 10) {
            TextField("Nome da matéria", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onSubmit { store.renameSelected(renameDraft) }
                .onChange(of: renameDraft) { _, value in scheduleRename(value) }
            Picker("Modo", selection: $appMode) {
                Text("Estudar").tag(AppMode.study)
                Text("Mesa").tag(AppMode.desk)
                Text("Caderno").tag(AppMode.notebook)
                Text("Progresso").tag(AppMode.progress)
            }
            .pickerStyle(.segmented)
            .frame(width: 350)
            Spacer()
            Button {
                showGlobalSearch = true
            } label: {
                Label("Pesquisar", systemImage: "magnifyingglass")
            }
            .controlSize(.small)
            .keyboardShortcut("f", modifiers: [.command])
            Button {
                showWidgets.toggle()
            } label: {
                Image(systemName: showWidgets ? "sidebar.right" : "sidebar.right")
            }
            .help(showWidgets ? "Ocultar widgets" : "Mostrar widgets")
            .accessibilityLabel(showWidgets ? "Ocultar widgets" : "Mostrar widgets")
            Menu {
                if store.selectedWorkspace?.obsidianVaultBookmark != nil {
                    Button("Atualizar \(store.selectedWorkspace?.obsidianVaultName ?? "vault")", action: updateConnectedVault)
                }
                Button("Conectar vault…", action: connectVault)
                Divider()
                Button("Exportar notas para Obsidian…", action: exportToObsidian)
            } label: {
                if vaultImporting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Obsidian", systemImage: "externaldrive.connected.to.line.below")
                }
            }
            .controlSize(.small)
            .disabled(vaultImporting)
            Label(store.saveState.label, systemImage: store.saveState.symbolName)
                .font(.caption)
                .foregroundStyle(saveStateColor)
                .help(saveStateHelp)
                .accessibilityLabel("Estado do salvamento: \(store.saveState.label)")
            SettingsLink {
                Label(
                    "IA: \(aiSettings.provider.label)",
                    systemImage: aiSettings.provider == .appleLocal ? "apple.intelligence" :
                        (aiSettings.provider == .openAICompatible ? "network" : "terminal")
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var studyJourneyBar: some View {
        let workspace = store.selectedWorkspace
        let hasMaterial = workspace?.nodes.contains(where: \CanvasNode.isStudyMaterial) == true
        let hasAttempt = workspace?.studyActivityEvents?.contains(where: { $0.kind == .createdNote }) == true
            || workspace?.nodes.contains(where: { !($0.inkStrokes ?? []).isEmpty }) == true
        let hasGuidance = workspace?.studyArtifacts?.contains(where: {
            [.summary, .assistantMessage, .feedback].contains($0.kind)
        }) == true
        let hasReview = workspace?.studyActivityEvents?.contains(where: {
            $0.kind == .reviewedFlashcard || $0.kind == .reviewedQuestion
        }) == true

        return HStack(spacing: 12) {
            journeyStep("1", "Material", complete: hasMaterial)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            journeyStep("2", "Tentativa", complete: hasAttempt)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            journeyStep("3", "Orientação", complete: hasGuidance)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            journeyStep("4", "Revisão", complete: hasReview)
            Spacer()
            Button(action: nextJourneyAction) {
                Label(
                    nextJourneyLabel,
                    systemImage: hasReview ? "chart.line.uptrend.xyaxis" : "arrow.right.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.055))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fluxo de estudo")
    }

    private func journeyStep(_ number: String, _ title: String, complete: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(complete ? Color.green : Color.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(complete ? .secondary : .primary)
        }
    }

    private var nextJourneyLabel: String {
        guard let workspace = store.selectedWorkspace else { return "Criar matéria" }
        if !workspace.nodes.contains(where: \CanvasNode.isStudyMaterial) { return "Adicionar material" }
        if workspace.studyActivityEvents?.contains(where: { $0.kind == .createdNote }) != true,
           !workspace.nodes.contains(where: { !($0.inkStrokes ?? []).isEmpty }) { return "Fazer uma tentativa" }
        if workspace.studyArtifacts?.contains(where: { [.summary, .assistantMessage, .feedback].contains($0.kind) }) != true {
            return "Pedir orientação"
        }
        if workspace.studyActivityEvents?.contains(where: { $0.kind == .reviewedFlashcard || $0.kind == .reviewedQuestion }) != true {
            return "Revisar agora"
        }
        return "Ver progresso"
    }

    private func nextJourneyAction() {
        guard let workspace = store.selectedWorkspace else {
            store.createWorkspace()
            return
        }
        if !workspace.nodes.contains(where: \CanvasNode.isStudyMaterial) {
            openMaterial()
        } else if workspace.studyActivityEvents?.contains(where: { $0.kind == .createdNote }) != true,
                  !workspace.nodes.contains(where: { !($0.inkStrokes ?? []).isEmpty }) {
            appMode = .study
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                NotificationCenter.default.post(name: Notification.Name("StudyhCanvasCommand"), object: "newStudyNote")
            }
        } else if workspace.studyArtifacts?.contains(where: { [.summary, .assistantMessage, .feedback].contains($0.kind) }) != true {
            appMode = .study
        } else {
            appMode = .progress
        }
    }

    private var saveStateColor: Color {
        switch store.saveState {
        case .saved: return .secondary
        case .saving: return .orange
        case .failed: return .red
        }
    }

    private var saveStateHelp: String {
        switch store.saveState {
        case .saved(let date):
            return "Último salvamento: \(date.formatted(date: .omitted, time: .standard))"
        case .saving:
            return "Gravando os dados locais"
        case .failed(let message):
            return message
        }
    }

    private func scheduleRename(_ value: String) {
        renameTask?.cancel()
        renameTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            store.renameSelected(value)
        }
    }

    private var deadlineEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Provas e apresentações").font(.title2.bold())
                    Text("Ative somente as datas que fazem parte desta matéria.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            deadlineRow(
                title: "Prova",
                icon: "doc.text",
                defaultDaysFromNow: 7,
                date: editorDateBinding(\.examDraft)
            )
            deadlineRow(
                title: "Apresentação",
                icon: "rectangle.on.rectangle",
                defaultDaysFromNow: 14,
                date: editorDateBinding(\.presentationDraft)
            )

            Divider()
            HStack {
                Button("Limpar datas") {
                    examEditorTarget?.examDraft = nil
                    examEditorTarget?.presentationDraft = nil
                }
                .disabled(examEditorTarget?.examDraft == nil && examEditorTarget?.presentationDraft == nil)
                Spacer()
                Button("Cancelar") { examEditorTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { saveDeadlineEditor() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var taskEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(taskEditorTarget?.taskID == nil ? "Nova tarefa" : "Editar tarefa").font(.title2.bold())
                    Text("A tarefa fica em Meu Progresso e não cria cartões na Mesa.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Título").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Ex.: Fazer lista 3 de Cálculo", text: Binding(
                    get: { taskEditorTarget?.title ?? "" },
                    set: { taskEditorTarget?.title = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Prazo").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    DatePicker(
                        "Prazo",
                        selection: Binding(
                            get: { taskEditorTarget?.dueDate ?? Date() },
                            set: { taskEditorTarget?.dueDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Prioridade").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Prioridade", selection: Binding(
                        get: { taskEditorTarget?.priority ?? .normal },
                        set: { taskEditorTarget?.priority = $0 }
                    )) {
                        ForEach(StudyTaskPriority.allCases) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancelar") { taskEditorTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button(taskEditorTarget?.taskID == nil ? "Criar tarefa" : "Salvar alterações", action: saveTaskEditor)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(taskEditorTarget?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func deadlineRow(
        title: String,
        icon: String,
        defaultDaysFromNow: Int,
        date: Binding<Date?>
    ) -> some View {
        let enabled = Binding(
            get: { date.wrappedValue != nil },
            set: { isEnabled in
                date.wrappedValue = isEnabled
                    ? Calendar.current.date(byAdding: .day, value: defaultDaysFromNow, to: Date())
                    : nil
            }
        )
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: enabled) {
                Label(title, systemImage: icon).font(.headline)
            }
            if date.wrappedValue != nil {
                HStack {
                    DatePicker(
                        "Data",
                        selection: Binding(
                            get: { date.wrappedValue ?? Date() },
                            set: { date.wrappedValue = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.field)
                    Spacer()
                    Text(relativeDateLabel(date.wrappedValue))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 28)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func editorDateBinding(_ keyPath: WritableKeyPath<ExamEditorTarget, Date?>) -> Binding<Date?> {
        Binding(
            get: { examEditorTarget?[keyPath: keyPath] },
            set: { value in
                guard var target = examEditorTarget else { return }
                target[keyPath: keyPath] = value
                examEditorTarget = target
            }
        )
    }

    private func relativeDateLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        if days == 0 { return "Hoje" }
        if days == 1 { return "Amanhã" }
        if days > 1 { return "Em \(days) dias" }
        return "Há \(-days) dias"
    }

    private func saveDeadlineEditor() {
        guard let target = examEditorTarget else { return }
        store.updateSelectedByID(target.workspaceID) { workspace in
            workspace.examDate = target.examDraft.map { Calendar.current.startOfDay(for: $0) }
            workspace.presentationDate = target.presentationDraft.map { Calendar.current.startOfDay(for: $0) }
        }
        examEditorTarget = nil
    }

    private func createFrameFromSelection() {
        guard let workspace = store.selectedWorkspace else { return }
        let selectedIDs = canvas.selectedNodeIDs
        let rects = workspace.nodes.filter { selectedIDs.contains($0.id) }.map(\.frame.cgRect)
        guard var bounds = rects.first else { return }
        for rect in rects.dropFirst() { bounds = bounds.union(rect) }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
        let padding: CGFloat = 36
        bounds = bounds.insetBy(dx: -padding, dy: -padding)
        let count = (workspace.frames?.count ?? 0) + 1
        let frame = StudyFrame(
            title: "Quadro \(count)",
            rect: CanvasRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
        )
        updateWorkspaceUndoably(actionName: "Criar quadro") { target in
            var frames = target.frames ?? []
            frames.append(frame)
            target.frames = frames
        }
    }

    private var canvasToolbar: some View {
        HStack(spacing: 10) {
                Button {
                    updateWorkspaceUndoably(actionName: "Adicionar nota") { workspace in
                        canvas.addNode(kind: .note, in: &workspace)
                    }
                } label: {
                    Label("Nota", systemImage: "note.text.badge.plus")
                }

                Button {
                    createFrameFromSelection()
                } label: {
                    Label("Quadro", systemImage: "rectangle.dashed")
                }
                .disabled(canvas.selectedNodeIDs.isEmpty)
                .help("Criar um quadro nomeado ao redor da seleção")
                .accessibilityLabel("Criar quadro com a seleção")

                Button {
                    updateWorkspaceUndoably(actionName: "Organizar mesa") { workspace in
                        canvas.organize(in: &workspace)
                    }
                } label: {
                    Label("Organizar", systemImage: "rectangle.3.group")
                }
                .disabled(store.selectedWorkspace?.nodes.isEmpty != false)

                Button {
                    store.updateSelected { canvas.frameAll(in: &$0) }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Enquadrar todos os cartões")
                .accessibilityLabel("Enquadrar todos os cartões")
                .disabled(store.selectedWorkspace?.nodes.isEmpty != false)

                Divider().frame(height: 18)

                Picker("Ferramenta", selection: $canvas.tool) {
                    Text("Mover").tag(CanvasController.CanvasTool.select)
                    Text("Lasso").tag(CanvasController.CanvasTool.lasso)
                    Text("Desenhar").tag(CanvasController.CanvasTool.draw)
                    Text("Borracha").tag(CanvasController.CanvasTool.erase)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)

                if canvas.tool == .draw {
                    Label("Folha livre", systemImage: "pencil.and.scribble")
                        .foregroundStyle(.secondary)
                    Picker("Cor", selection: $canvas.inkColor) {
                        ForEach(CanvasInkColor.allCases) { color in
                            Label(color.label, systemImage: "circle.fill")
                                .foregroundStyle(color.color)
                                .tag(color)
                        }
                    }
                    .frame(width: 110)

                    Button {
                        updateWorkspaceUndoably(actionName: "Remover último traço") { workspace in
                            if workspace.inkStrokes?.isEmpty == false {
                                workspace.inkStrokes?.removeLast()
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(store.selectedWorkspace?.inkStrokes?.isEmpty != false)
                    .help("Desfazer último traço")

                    Button {
                        pendingDestructiveAction = .drawing
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(store.selectedWorkspace?.inkStrokes?.isEmpty != false)
                    .help("Limpar desenho")
                    .accessibilityLabel("Limpar desenho")
                }

                Spacer()
                Button {
                    requestDeleteSelection()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(canvas.selectedNodeIDs.isEmpty && canvas.selectedInkStrokeIDs.isEmpty)
                .help("Apagar seleção")
                Button {
                    canvas.inspectedNodeID = canvas.selectedNodeIDs.first
                } label: {
                    Image(systemName: "rectangle.trailinghalf.inset.filled")
                }
                .disabled(canvas.selectedNodeIDs.count != 1)
                .help("Abrir ao lado")
                Text(String(format: "%.0f%%", (store.selectedWorkspace?.cameraScale ?? 1) * 100))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("Zoom do canvas")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func openDeskNode(_ nodeID: UUID) {
        guard let workspace = store.selectedWorkspace,
              let deskNode = workspace.nodes.first(where: { $0.id == nodeID }) else { return }
        if deskNode.isStudyMaterial {
            activateMaterial(deskNode.id)
            return
        }
        if let path = deskNode.sourceURL,
           deskNode.obsidian?.attachmentType != nil,
           deskNode.obsidian?.attachmentType != "canvas-text",
           deskNode.obsidian?.attachmentType != "canvas-link" {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        guard let materialID = deskNode.sourceMaterialID,
              let material = workspace.nodes.first(where: { $0.id == materialID }) else {
            canvas.inspectedNodeID = nodeID
            return
        }
        store.updateSelected { workspace in
            guard let index = workspace.nodes.firstIndex(where: { $0.id == materialID }) else { return }
            switch workspace.nodes[index].kind {
            case .epub:
                if let page = deskNode.sourcePageIndex { workspace.nodes[index].epubPageIndex = page }
            case .pdf:
                if let page = deskNode.sourcePageIndex { workspace.nodes[index].pdfPageIndex = page }
                workspace.nodes[index].pdfNavigationQuote = deskNode.sourceQuote
            case .web:
                if let url = deskNode.sourceURL { workspace.nodes[index].webURL = url }
                workspace.nodes[index].webNavigationQuote = deskNode.sourceQuote
            case .slides:
                if let page = deskNode.sourcePageIndex { workspace.nodes[index].slidesPageIndex = page }
                workspace.nodes[index].slidesNavigationQuote = deskNode.sourceQuote
            case .note, .calc:
                break
            }
        }
        activateMaterial(material.id)
        if material.kind == .epub,
           let annotationID = deskNode.sourceArtifactID,
           material.epubAnnotations?.contains(where: { $0.id == annotationID }) == true {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                NotificationCenter.default.post(
                    name: .studyhOpenEPUBAnnotation,
                    object: nil,
                    userInfo: ["nodeID": materialID, "annotationID": annotationID]
                )
            }
        }
    }

    private var workspaceBinding: Binding<Workspace> {
        Binding(
            get: {
                store.selectedWorkspace ?? Workspace(name: "")
            },
            set: { updated in
                store.updateSelected { current in
                    current = updated
                }
            }
        )
    }

    private var studyMaterials: [CanvasNode] {
        store.selectedWorkspace?.nodes.filter(\.isStudyMaterial) ?? []
    }

    private var activeStudyMaterial: CanvasNode? {
        guard let activeID = canvas.activeStudyNodeID else { return nil }
        return store.selectedWorkspace?.nodes.first { $0.id == activeID }
    }

    private func completeFocusSession(_ completion: FocusTimerCompletion) {
        store.updateSelectedByID(completion.workspaceID) { workspace in
            var sessions = workspace.focusSessions ?? []
            sessions.append(StudyFocusSession(
                startedAt: completion.startedAt,
                endedAt: completion.endedAt,
                plannedMinutes: completion.plannedMinutes,
                completedMinutes: completion.completedMinutes,
                intention: completion.intention,
                materialID: completion.materialID
            ))
            workspace.focusSessions = Array(sessions.suffix(1_000))
        }
    }

    private var prioritizedWorkspaces: [Workspace] {
        let now = Date()
        func nearestDeadline(_ ws: Workspace) -> Date {
            let dates = [ws.examDate, ws.presentationDate].compactMap { $0 }.filter { $0 > now }
            return dates.min() ?? .distantFuture
        }
        return store.workspaces.sorted { nearestDeadline($0) < nearestDeadline($1) }
    }

    private func examLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "hoje" }
        if calendar.isDateInTomorrow(date) { return "amanhã" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func examColor(_ date: Date) -> Color {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 99
        if days <= 1 { return .red }
        if days <= 7 { return .orange }
        return .secondary
    }

    private var recentHistory: [StudyHistoryEntry] {
        Array((store.selectedWorkspace?.studyHistory ?? []).reversed().prefix(8))
    }

    private struct MaterialProgress {
        let label: String
        let fraction: Double?
    }

    private func materialProgress(_ node: CanvasNode) -> MaterialProgress? {
        switch node.kind {
        case .epub:
            let page = max(0, node.epubPageIndex ?? 0)
            let total = max(1, node.epubPageCount ?? 1)
            return MaterialProgress(
                label: "pág. \(page + 1)/\(total)",
                fraction: node.epubPageCount == nil ? nil : Double(page + 1) / Double(total)
            )
        case .pdf:
            let total = max(1, node.pdfPageCount ?? 1)
            return MaterialProgress(
                label: node.pdfPageCount == nil ? "pág. \(node.pdfPageIndex + 1)" : "pág. \(node.pdfPageIndex + 1)/\(total)",
                fraction: node.pdfPageCount.map { Double(node.pdfPageIndex + 1) / Double(max(1, $0)) }
            )
        case .web:
            return MaterialProgress(label: "pesquisa", fraction: nil)
        case .slides:
            let page = max(0, node.slidesPageIndex ?? 0)
            let total = max(1, node.slidesPages?.count ?? 1)
            return MaterialProgress(
                label: "slide \(page + 1)/\(total)",
                fraction: Double(page + 1) / Double(total)
            )
        case .note, .calc:
            return nil
        }
    }

    private func subjectProgress(_ workspace: Workspace) -> MaterialProgress? {
        var completed = 0
        var total = 0
        for node in workspace.nodes {
            switch node.kind {
            case .epub:
                guard let count = node.epubPageCount, count > 0 else { continue }
                completed += min(count, max(1, (node.epubPageIndex ?? 0) + 1))
                total += count
            case .pdf:
                guard let count = node.pdfPageCount, count > 0 else { continue }
                completed += min(count, max(1, node.pdfPageIndex + 1))
                total += count
            case .slides:
                guard let count = node.slidesPages?.count, count > 0 else { continue }
                completed += min(count, max(1, (node.slidesPageIndex ?? 0) + 1))
                total += count
            case .web, .note, .calc:
                continue
            }
        }
        guard total > 0 else { return nil }
        let fraction = Double(completed) / Double(total)
        return MaterialProgress(label: "posição \(Int((fraction * 100).rounded()))%", fraction: fraction)
    }

    private func historyLabel(_ entry: StudyHistoryEntry, node: CanvasNode) -> String {
        let location: String
        switch node.kind {
        case .epub: location = "pág. \((entry.pageIndex ?? node.epubPageIndex ?? 0) + 1)"
        case .pdf: location = "pág. \((entry.pageIndex ?? node.pdfPageIndex) + 1)"
        case .web: location = "pesquisa"
        case .slides: location = "slide \((entry.pageIndex ?? node.slidesPageIndex ?? 0) + 1)"
        case .note, .calc: location = "material"
        }
        return "\(location) · \(entry.openedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func activateMaterial(_ id: UUID) {
        guard let workspace = store.selectedWorkspace,
              let node = workspace.nodes.first(where: { $0.id == id }) else { return }
        store.updateSelected { workspace in
            let page: Int?
            switch node.kind {
            case .epub: page = node.epubPageIndex
            case .pdf: page = node.pdfPageIndex
            case .slides: page = node.slidesPageIndex
            case .web, .note, .calc: page = nil
            }
            var history = workspace.studyHistory ?? []
            history.removeAll { $0.nodeID == id }
            history.append(StudyHistoryEntry(nodeID: id, pageIndex: page))
            workspace.studyHistory = Array(history.suffix(50))
            var events = workspace.studyActivityEvents ?? []
            events.append(StudyActivityEvent(kind: .openedMaterial, nodeID: id))
            workspace.studyActivityEvents = Array(events.suffix(2_000))
        }
        canvas.activeStudyNodeID = id
        let showsStudy = appMode == .study || (appMode == .notebook && notebookLayout == .study)
        if !showsStudy {
            appMode = .study
        }
    }

    private func openSearchResult(_ result: StudySearchResult) {
        store.selectedID = result.workspaceID
        switch result.destination {
        case .notebook(let notebookID):
            selectedNotebookID = notebookID
            notebookLayout = .only
            appMode = .notebook
        case .artifact(let artifactID, let sourceNodeID):
            if let sourceNodeID {
                navigateToSearchMaterial(sourceNodeID, result: result)
            } else {
                appMode = .study
            }
            postSearchNotification(.studyhOpenStudyNote, userInfo: ["artifactID": artifactID])
        case .annotation(let nodeID, let annotationID):
            navigateToSearchMaterial(nodeID, result: result)
            postSearchNotification(
                .studyhOpenEPUBAnnotation,
                userInfo: ["nodeID": nodeID, "annotationID": annotationID]
            )
        case .material(let nodeID):
            navigateToSearchMaterial(nodeID, result: result)
        case .canvasNode(let nodeID):
            appMode = .desk
            canvas.selectedNodeIDs = [nodeID]
            canvas.inspectedNodeID = nodeID
        }
    }

    private func navigateToSearchMaterial(_ nodeID: UUID, result: StudySearchResult) {
        guard let workspace = store.workspaces.first(where: { $0.id == result.workspaceID }),
              workspace.nodes.contains(where: { $0.id == nodeID && $0.isStudyMaterial }) else { return }
            store.updateSelectedByID(result.workspaceID) { workspace in
                guard let index = workspace.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
                switch workspace.nodes[index].kind {
                case .epub:
                    if let page = result.pageIndex { workspace.nodes[index].epubPageIndex = page }
                case .pdf:
                    if let page = result.pageIndex { workspace.nodes[index].pdfPageIndex = page }
                    workspace.nodes[index].pdfNavigationQuote = result.quote
                case .web:
                    if let url = result.sourceURL { workspace.nodes[index].webURL = url }
                    workspace.nodes[index].webNavigationQuote = result.quote
                case .slides:
                    if let page = result.pageIndex { workspace.nodes[index].slidesPageIndex = page }
                    workspace.nodes[index].slidesNavigationQuote = result.quote
                case .note, .calc:
                    break
                }
            }
        canvas.activeStudyNodeID = nodeID
        appMode = .study
    }

    private func postSearchNotification(_ name: Notification.Name, userInfo: [AnyHashable: Any]) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
    }

    private func openNotebookMaterial(_ id: UUID, page: Int?) {
        store.updateSelected { workspace in
            guard let index = workspace.nodes.firstIndex(where: { $0.id == id }) else { return }
            switch workspace.nodes[index].kind {
            case .pdf: if let page { workspace.nodes[index].pdfPageIndex = page }
            case .epub: if let page { workspace.nodes[index].epubPageIndex = page }
            case .slides: if let page { workspace.nodes[index].slidesPageIndex = page }
            case .web, .note, .calc: break
            }
        }
        activateMaterial(id)
    }

    private func exportReviewHTML() {
        guard let workspace = store.selectedWorkspace else { return }
        let html = StudyHTMLExporter.export(workspace: workspace)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "Studyh - \(workspace.name).html"
        panel.title = "Exportar revisão"
        panel.prompt = "Exportar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Revisão exportada para \(url.lastPathComponent). Abra em qualquer navegador ou envie para o celular."
        } catch {
            exportMessage = "Não foi possível exportar: \(error.localizedDescription)"
        }
    }

    private func exportToObsidian() {
        let panel = NSOpenPanel()
        panel.title = "Escolha a pasta do vault do Obsidian"
        panel.prompt = "Exportar"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let destination = try ObsidianExporter.export(store.workspaces, to: url)
            exportMessage = "Notas exportadas para \(destination.path). O arquivo “Studyh Index.md” liga matérias e materiais."
        } catch {
            exportMessage = "Não foi possível exportar: \(error.localizedDescription)"
        }
    }

    private func connectVault() {
        let panel = NSOpenPanel()
        panel.title = "Escolha o vault do Obsidian"
        panel.prompt = "Conectar"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importVault(at: url)
    }

    private func updateConnectedVault() {
        guard let bookmark = store.selectedWorkspace?.obsidianVaultBookmark else {
            connectVault()
            return
        }
        var stale = false
        let url = (try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )) ?? (try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ))
        guard let url else {
            exportMessage = "Não consegui acessar o vault anterior. Escolha a pasta novamente."
            return
        }
        importVault(at: url)
    }

    private func importVault(at url: URL) {
        guard let previous = store.selectedWorkspace else { return }
        let workspaceID = previous.id
        vaultImporting = true
        Task { @MainActor in
            await Task.yield()
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
                vaultImporting = false
            }
            do {
                var updated = previous
                let summary = try ObsidianImporter.importVault(at: url, into: &updated)
                store.updateSelectedByID(workspaceID) {
                    $0 = updated
                    canvas.frameAll(in: &$0)
                }
                canvas.registerWorkspaceUndo(
                    from: previous,
                    in: store,
                    undoManager: undoManager,
                    actionName: "Importar vault"
                )
                if store.selectedID == workspaceID {
                    appMode = .desk
                }
                exportMessage = "Vault “\(url.lastPathComponent)” conectado: \(summary.message)"
            } catch {
                exportMessage = "Não foi possível importar o vault: \(error.localizedDescription)"
            }
        }
    }

    private func openProgressTask(_ nodeID: UUID) {
        appMode = .desk
        canvas.selectedNodeIDs = [nodeID]
        canvas.inspectedNodeID = nodeID
    }

    private func toggleProgressTask(_ task: MarkdownTask) {
        store.updateSelected { workspace in
            guard let index = workspace.nodes.firstIndex(where: { $0.id == task.nodeID }) else { return }
            workspace.nodes[index].noteBody = MarkdownTaskParser.toggled(task, in: workspace.nodes[index].noteBody)
            if !task.isCompleted {
                var events = workspace.studyActivityEvents ?? []
                events.append(StudyActivityEvent(kind: .completedTask, nodeID: task.nodeID))
                workspace.studyActivityEvents = Array(events.suffix(2_000))
            }
        }
    }

    private func openDeadlineEditor() {
        guard let workspace = store.selectedWorkspace else { return }
        examEditorTarget = ExamEditorTarget(
            workspaceID: workspace.id,
            examDraft: workspace.examDate,
            presentationDraft: workspace.presentationDate
        )
    }

    private func startTaskEditor() {
        guard let workspace = store.selectedWorkspace else { return }
        taskEditorTarget = TaskEditorTarget(
            workspaceID: workspace.id,
            taskID: nil,
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )
    }

    private func editStudyTask(_ task: StudyTask) {
        guard let workspace = store.selectedWorkspace else { return }
        taskEditorTarget = TaskEditorTarget(
            workspaceID: workspace.id,
            taskID: task.id,
            title: task.title,
            dueDate: task.dueDate,
            priority: task.priority
        )
    }

    private func saveTaskEditor() {
        guard let target = taskEditorTarget else { return }
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.updateSelectedByID(target.workspaceID) { workspace in
            var tasks = workspace.studyTasks ?? []
            if let taskID = target.taskID,
               let index = tasks.firstIndex(where: { $0.id == taskID }) {
                tasks[index].title = title
                tasks[index].dueDate = Calendar.current.startOfDay(for: target.dueDate)
                tasks[index].priority = target.priority
            } else {
                tasks.append(StudyTask(
                    title: title,
                    dueDate: Calendar.current.startOfDay(for: target.dueDate),
                    priority: target.priority
                ))
            }
            workspace.studyTasks = tasks
        }
        taskEditorTarget = nil
    }

    private func toggleStudyTask(_ task: StudyTask) {
        store.updateSelected { workspace in
            guard let index = workspace.studyTasks?.firstIndex(where: { $0.id == task.id }) else { return }
            workspace.studyTasks?[index].isCompleted.toggle()
            if !task.isCompleted {
                var events = workspace.studyActivityEvents ?? []
                events.append(StudyActivityEvent(kind: .completedTask))
                workspace.studyActivityEvents = Array(events.suffix(2_000))
            }
        }
    }

    private func requestDeleteStudyTask(_ task: StudyTask) {
        pendingDestructiveAction = .studyTask(task.id, task.title)
    }

    private func deleteStudyTask(_ id: UUID) {
        updateWorkspaceUndoably(actionName: "Excluir tarefa") { workspace in
            workspace.studyTasks?.removeAll { $0.id == id }
        }
    }

    private func reviewQuestionLater(_ artifact: StudyArtifact) {
        openStudyArtifact(artifact, notification: .studyhReviewQuestion)
    }

    private func reviewFlashcardsLater(_ artifact: StudyArtifact) {
        openStudyArtifact(artifact, notification: .studyhReviewFlashcards)
    }

    private func openStudyArtifact(_ artifact: StudyArtifact, notification: Notification.Name) {
        guard let nodeID = artifact.sourceNodeID,
              store.selectedWorkspace?.nodes.contains(where: { $0.id == nodeID }) == true else { return }
        activateMaterial(nodeID)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            NotificationCenter.default.post(
                name: notification,
                object: nil,
                userInfo: ["artifactID": artifact.id]
            )
        }
    }

    private func moveToAdjacentMaterial(_ delta: Int) {
        guard !studyMaterials.isEmpty else { return }
        let current = canvas.activeStudyNodeID.flatMap { id in studyMaterials.firstIndex(where: { $0.id == id }) } ?? 0
        let next = min(max(0, current + delta), studyMaterials.count - 1)
        activateMaterial(studyMaterials[next].id)
    }

    private func selectDefaultMaterial() {
        guard let workspace = store.selectedWorkspace else { return }
        if let active = canvas.activeStudyNodeID,
           workspace.nodes.contains(where: { $0.id == active && $0.isStudyMaterial }) {
            return
        }
        canvas.activeStudyNodeID = workspace.nodes.first(where: \.isStudyMaterial)?.id
    }

    private func openMaterial() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.pdf]
        if let epubType = UTType(filenameExtension: "epub") {
            types.append(epubType)
        }
        if let pptxType = UTType(filenameExtension: "pptx") {
            types.append(pptxType)
        }
        panel.allowedContentTypes = types
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch url.pathExtension.lowercased() {
        case "epub": importEPUB(url)
        case "pptx", "ppt": importSlides(url)
        default: importPDF(url)
        }
    }

    private func importSlides(_ url: URL) {
        guard let pages = SlidesImporter.extractPages(from: url) else {
            canvas.aiError = "Não foi possível ler os slides de \(url.lastPathComponent)."
            return
        }
        let id = UUID()
        store.updateSelected { workspace in
            workspace.nodes.append(CanvasNode(
                id: id,
                kind: .slides,
                title: url.deletingPathExtension().lastPathComponent,
                frame: .default(for: .slides, origin: CGPoint(x: 100, y: 100)),
                zIndex: (workspace.nodes.map(\.zIndex).max() ?? 0) + 1,
                slidesPages: pages,
                slidesPageIndex: 0
            ))
        }
        activateMaterial(id)
    }

    private func importPDF(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        let id = UUID()
        store.updateSelected { workspace in
            workspace.nodes.append(CanvasNode(
                id: id,
                kind: .pdf,
                title: url.deletingPathExtension().lastPathComponent,
                frame: .default(for: .pdf, origin: CGPoint(x: 80, y: 80)),
                zIndex: (workspace.nodes.map(\.zIndex).max() ?? 0) + 1,
                pdfBookmark: bookmark
            ))
        }
        activateMaterial(id)
    }

    private func importEPUB(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        let id = UUID()
        store.updateSelected { workspace in
            workspace.nodes.append(CanvasNode(
                id: id,
                kind: .epub,
                title: url.deletingPathExtension().lastPathComponent,
                frame: .default(for: .epub, origin: CGPoint(x: 80, y: 80)),
                zIndex: (workspace.nodes.map(\.zIndex).max() ?? 0) + 1,
                epubBookmark: bookmark
            ))
        }
        activateMaterial(id)
    }

    private func openGuide() {
        addWebMaterial(title: "Pesquisa", url: "https://www.google.com")
    }

    private func openYouTube() {
        addWebMaterial(title: "YouTube", url: "https://www.youtube.com")
    }

    private func addWebMaterial(title: String, url: String) {
        let id = UUID()
        store.updateSelected { workspace in
            workspace.nodes.append(CanvasNode(
                id: id,
                kind: .web,
                title: title,
                frame: .default(for: .web, origin: CGPoint(x: 120, y: 120)),
                zIndex: (workspace.nodes.map(\.zIndex).max() ?? 0) + 1,
                webURL: url
            ))
        }
        activateMaterial(id)
    }

    private func removeMaterial(_ id: UUID) {
        updateWorkspaceUndoably(actionName: "Remover material") { workspace in
            workspace.removeNodesPreservingDependentContent([id])
        }
        if canvas.activeStudyNodeID == id { selectDefaultMaterial() }
    }

    private func updateWorkspaceUndoably(
        actionName: String,
        _ change: (inout Workspace) -> Void
    ) {
        guard let previous = store.selectedWorkspace else { return }
        store.updateSelected(change)
        canvas.registerWorkspaceUndo(
            from: previous,
            in: store,
            undoManager: undoManager,
            actionName: actionName
        )
    }

    private func deleteSelection() {
        updateWorkspaceUndoably(actionName: "Excluir seleção") { workspace in
            canvas.deleteSelected(from: &workspace)
        }
    }

    private func requestDeleteSelection() {
        let materialCount = store.selectedWorkspace?.nodes.filter {
            canvas.selectedNodeIDs.contains($0.id) && $0.isStudyMaterial
        }.count ?? 0
        if materialCount > 0 {
            let impact = store.selectedWorkspace?.removalImpact(for: canvas.selectedNodeIDs) ?? WorkspaceRemovalImpact()
            pendingDestructiveAction = .selectionWithMaterials(materialCount, impact)
        } else {
            deleteSelection()
        }
    }

    private func performDestructiveAction(_ action: PendingDestructiveAction) {
        switch action {
        case let .workspace(id, _):
            let previousWorkspaces = store.workspaces
            let previousSelection = store.selectedID
            store.deleteWorkspace(id)
            canvas.registerStoreUndo(
                workspaces: previousWorkspaces,
                selectedID: previousSelection,
                in: store,
                undoManager: undoManager,
                actionName: "Excluir workspace"
            )
        case let .material(id, _, _):
            removeMaterial(id)
        case let .studyTask(id, _):
            deleteStudyTask(id)
        case .drawing:
            updateWorkspaceUndoably(actionName: "Limpar desenho") { workspace in
                workspace.inkStrokes = []
                canvas.selectedInkStrokeIDs = []
            }
        case .selectionWithMaterials:
            deleteSelection()
        }
    }

    private func handleCanvasCommand(_ command: String) {
        guard store.selectedWorkspace != nil else { return }
        switch command {
        case "globalSearch":
            showGlobalSearch = true
        case "exportObsidian":
            exportToObsidian()
        case "previousMaterial":
            moveToAdjacentMaterial(-1)
        case "nextMaterial":
            moveToAdjacentMaterial(1)
        case "newStudyNote":
            appMode = .study
        case "organizeDesk":
            appMode = .desk
            updateWorkspaceUndoably(actionName: "Organizar mesa") { canvas.organize(in: &$0) }
        case "frameDesk":
            appMode = .desk
            store.updateSelected { canvas.frameAll(in: &$0) }
        case "connectVault":
            connectVault()
        case "showProgress":
            appMode = .progress
        case "newTask":
            appMode = .progress
            startTaskEditor()
        case "select", "lasso", "draw", "erase":
            appMode = .desk
            canvas.tool = CanvasController.CanvasTool(rawValue: command) ?? .select
        case "zoomIn":
            store.updateSelected { canvas.zoom(by: 1.2, in: &$0) }
        case "zoomOut":
            store.updateSelected { canvas.zoom(by: 1 / 1.2, in: &$0) }
        case "zoomReset":
            store.updateSelected { workspace in
                canvas.zoom(by: 1 / workspace.cameraScale, in: &workspace)
            }
        case "delete":
            if !canvas.selectedNodeIDs.isEmpty || !canvas.selectedInkStrokeIDs.isEmpty {
                requestDeleteSelection()
            }
        default:
            break
        }
    }

    private var inspectedNodeBinding: Binding<CanvasNode>? {
        guard let id = canvas.inspectedNodeID,
              store.selectedWorkspace?.nodes.contains(where: { $0.id == id }) == true else { return nil }
        return Binding(
            get: {
                store.selectedWorkspace?.nodes.first(where: { $0.id == id })
                    ?? CanvasNode(kind: .note, frame: .default(for: .note, origin: .zero))
            },
            set: { updated in
                store.updateSelected { workspace in
                    guard let index = workspace.nodes.firstIndex(where: { $0.id == id }) else { return }
                    workspace.nodes[index] = updated
                }
            }
        )
    }

    private func runAI(_ mode: AIMode) {
        guard let workspace = store.selectedWorkspace else { return }
        let workspaceID = workspace.id
        let selected = workspace.nodes.filter { canvas.selectedNodeIDs.contains($0.id) }
        let selectedInk = (workspace.inkStrokes ?? []).filter {
            canvas.selectedInkStrokeIDs.contains($0.id)
        }
        let context = PedagogicalPrompt.context(
            selectedNodes: selected,
            surroundingNodes: workspace.nodes.filter { !canvas.selectedNodeIDs.contains($0.id) }
        )

        canvas.aiBusy = true
        canvas.aiError = nil
        canvas.lastAIMode = mode
        aiTask?.cancel()
        aiTask = Task {
            do {
                let inkImage = await Task.detached(priority: .userInitiated) {
                    CanvasInkSnapshot.pngData(from: selectedInk)
                }.value
                let selection = [
                    context.selection,
                    selectedInk.isEmpty ? "" : "[Desenho selecionado pelo laço — consulte a imagem anexada.]"
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
                let text = try await ai.complete(
                    mode: mode,
                    selection: selection,
                    surrounding: context.surrounding,
                    settings: aiSettings,
                    imageData: inkImage
                )
                guard !Task.isCancelled, store.selectedID == workspaceID else { return }
                canvas.aiPanelText = text
            } catch {
                guard !Task.isCancelled, store.selectedID == workspaceID else { return }
                canvas.aiError = error.localizedDescription
            }
            canvas.aiBusy = false
        }
    }
}

private enum AppMode: Hashable {
    case study
    case desk
    case notebook
    case progress
}

private enum NotebookLayout: String, CaseIterable, Identifiable {
    case only
    case study
    case desk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .only: return "Só caderno"
        case .study: return "Com Estudar"
        case .desk: return "Com Mesa"
        }
    }

    var icon: String {
        switch self {
        case .only: return "book.closed"
        case .study: return "book.pages"
        case .desk: return "square.grid.2x2"
        }
    }
}

private enum PendingDestructiveAction: Identifiable {
    case workspace(UUID, String)
    case material(UUID, String, WorkspaceRemovalImpact)
    case studyTask(UUID, String)
    case drawing
    case selectionWithMaterials(Int, WorkspaceRemovalImpact)

    var id: String {
        switch self {
        case let .workspace(id, _): return "workspace-\(id)"
        case let .material(id, _, _): return "material-\(id)"
        case let .studyTask(id, _): return "study-task-\(id)"
        case .drawing: return "drawing"
        case .selectionWithMaterials: return "selection-with-materials"
        }
    }

    var title: String {
        switch self {
        case .workspace: return "Excluir workspace?"
        case .material: return "Remover material?"
        case .studyTask: return "Excluir tarefa?"
        case .drawing: return "Limpar todo o desenho?"
        case .selectionWithMaterials: return "Excluir seleção com materiais?"
        }
    }

    var message: String {
        switch self {
        case let .workspace(_, name): return "O workspace “\(name)” será excluído. Você poderá desfazer esta ação."
        case let .material(_, title, impact):
            return removalMessage(title: "O material “\(title)” será removido.", impact: impact)
        case let .studyTask(_, title): return "A tarefa “\(title)” será excluída. Você poderá desfazer esta ação."
        case .drawing: return "Todos os traços deste workspace serão removidos. Você poderá desfazer esta ação."
        case let .selectionWithMaterials(count, impact):
            let title = count == 1 ? "A seleção contém um material." : "A seleção contém \(count) materiais."
            return removalMessage(title: title, impact: impact)
        }
    }

    var buttonTitle: String {
        switch self {
        case .workspace: return "Excluir"
        case .material: return "Remover"
        case .studyTask: return "Excluir"
        case .drawing: return "Limpar"
        case .selectionWithMaterials: return "Excluir"
        }
    }

    private func removalMessage(title: String, impact: WorkspaceRemovalImpact) -> String {
        guard impact.linkedRecordCount > 0 else { return "\(title) Você poderá desfazer esta ação." }
        return "\(title) \(impact.linkedRecordCount) registro(s) vinculado(s) serão preservados sem o vínculo com o material. Você poderá desfazer esta ação."
    }
}

private struct NodeInspector: View {
    @Binding var node: CanvasNode
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: node.kind.icon)
                    .foregroundStyle(.secondary)
                TextField("Título", text: $node.title)
                    .textFieldStyle(.plain)
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Fechar visualização lateral")
            }
            .padding(12)
            .background(.bar)

            NodeContentView(node: $node)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
