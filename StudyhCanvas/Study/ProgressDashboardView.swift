import SwiftUI

struct ProgressDashboardView: View {
    @Binding var workspace: Workspace
    let onOpenMaterial: (UUID) -> Void
    let onOpenTask: (UUID) -> Void
    let onToggleTask: (MarkdownTask) -> Void
    let onReviewQuestion: (StudyArtifact) -> Void
    let onReviewFlashcards: (StudyArtifact) -> Void
    let onCreateTask: () -> Void
    let onToggleStudyTask: (StudyTask) -> Void
    let onEditStudyTask: (StudyTask) -> Void
    let onDeleteStudyTask: (StudyTask) -> Void
    let onEditDeadlines: () -> Void
    var onExportHTML: () -> Void = {}

    private enum TaskViewMode {
        case list
        case table
        case kanban
    }

    @State private var taskViewMode: TaskViewMode = .list

    private var snapshot: WorkspaceProgressSnapshot {
        ProgressMetrics.snapshot(for: workspace)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                overview
                frameProgress
                todayPlan
                taskList
                reviewAgain
                lightPractice
                dailyNotes
                materials
                production
                recent
            }
            .padding(24)
            .frame(maxWidth: 1050, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var frameProgress: some View {
        if !snapshot.frameSnapshots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quadros da mesa").font(.title2.bold())
                ForEach(snapshot.frameSnapshots) { frame in
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.dashed")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(frame.title).font(.subheadline.weight(.semibold))
                            if frame.total > 0, let fraction = frame.fraction {
                                ProgressView(value: fraction).frame(maxWidth: 260)
                            }
                        }
                        Spacer()
                        if frame.total > 0 {
                            Text("\(frame.covered) de \(frame.total) unidades cobertas")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Nenhum material mensurável")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meu Progresso")
                    .font(.largeTitle.bold())
                Text(workspace.name)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Button(action: onCreateTask) {
                    Label("Nova tarefa", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    onExportHTML()
                } label: {
                    Label("Exportar revisão", systemImage: "safari")
                }
                .help("Gera uma página HTML com flashcards e questões para revisar em qualquer navegador")
                Button("Provas e datas", action: onEditDeadlines)
            }
        }
    }

    private var overview: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            metricCard("Posição", value: snapshot.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", detail: snapshot.totalUnits > 0 ? "posição atual nos materiais" : "Sem total mensurável", icon: "book.pages")
            metricCard("Cobertura", value: snapshot.coverageFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", detail: snapshot.coverableUnits > 0 ? "\(snapshot.coveredUnits) unidades distintas" : "Começa a contar ao abrir páginas", icon: "square.grid.3x3")
            metricCard("Prática hoje", value: "\(snapshot.practiceToday)", detail: "questões e flashcards revisados", icon: "pencil.and.list.clipboard")
            metricCard("Retenção atual", value: snapshot.retentionFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", detail: "última avaliação dos flashcards", icon: "brain.head.profile")
        }
    }

    private func metricCard(_ title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title.bold()).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private var todayPlan: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoje").font(.title2.bold())
                    Text(todaySummary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if hasStartableAction {
                    Button(action: startNextAction) {
                        Label("Começar próxima ação", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if let deadline = nearestDeadline {
                Button(action: onEditDeadlines) {
                    Label("\(deadline.label) · \(deadline.date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar.badge.exclamationmark")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered)
            }
            if let item = firstPlannedFlashcards {
                planRow(
                    title: flashcardPlanTitle(item.plan),
                    detail: materialTitle(for: item.artifact.sourceNodeID),
                    icon: "rectangle.on.rectangle",
                    tint: .orange
                ) { onReviewFlashcards(item.artifact) }
            }
            if let question = firstQuestionToReview {
                planRow(
                    title: "Rever uma questão anterior",
                    detail: questionPreview(question.body),
                    icon: "questionmark.circle",
                    tint: .blue
                ) { onReviewQuestion(question) }
            }
            ForEach(priorityStudyTasks.prefix(3)) { task in
                studyTaskPlanRow(task)
            }
            ForEach(priorityTasks.prefix(3)) { task in
                taskPlanRow(task)
            }
            if let material = continueMaterial {
                planRow(
                    title: "Continuar \(material.title)",
                    detail: material.fraction.map { "\(Int(($0 * 100).rounded()))% percorrido" } ?? "Retomar material",
                    icon: material.kind.icon,
                    tint: .green
                ) { onOpenMaterial(material.id) }
            }
            if todayActionCount == 0 {
                Label("Nada pendente agora.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tarefas").font(.title2.bold())
                Spacer()
                Picker("Visão", selection: $taskViewMode) {
                    Label("Lista", systemImage: "list.bullet").tag(TaskViewMode.list)
                    Label("Tabela", systemImage: "tablecells").tag(TaskViewMode.table)
                    Label("Quadro", systemImage: "rectangle.split.3x1").tag(TaskViewMode.kanban)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
                Button(action: onCreateTask) {
                    Label("Nova tarefa", systemImage: "plus")
                }
            }
            switch taskViewMode {
            case .list:
                listTaskRows
            case .table:
                taskTable
            case .kanban:
                taskKanban
            }
        }
    }

    @ViewBuilder
    private var listTaskRows: some View {
        if allStudyTasks.isEmpty && snapshot.tasks.isEmpty {
            Text("Crie uma tarefa para exercícios, listas, provas ou trabalhos.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(allStudyTasks) { task in
                studyTaskListRow(task)
            }
            ForEach(snapshot.tasks.sorted(by: taskSort)) { task in
                HStack(spacing: 10) {
                    Button { onToggleTask(task) } label: {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                    Button { onOpenTask(task.nodeID) } label: {
                        Text(task.title)
                            .strikethrough(task.isCompleted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Text(task.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "Do Obsidian")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .opacity(task.isCompleted ? 0.58 : 1)
            }
        }
    }

    private var taskTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allStudyTasks.isEmpty {
                Text("Nenhuma tarefa nativa. Tarefas do Obsidian aparecem na visualização em lista.")
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow {
                        Text("Tarefa")
                        Text("Prioridade")
                        Text("Prazo")
                        Text("Status")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                    Divider()
                    ForEach(allStudyTasks) { task in
                        GridRow {
                            Button { onEditStudyTask(task) } label: {
                                Text(task.title)
                                    .strikethrough(task.isCompleted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .gridColumnAlignment(.leading)
                            priorityBadge(task.priority)
                            Text(studyTaskDateLabel(task))
                                .foregroundStyle(studyTaskIsOverdue(task) && !task.isCompleted ? Color.red : Color.secondary)
                            Button { onToggleStudyTask(task) } label: {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isCompleted ? Color.green : priorityColor(task.priority))
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.callout)
                        .padding(.vertical, 7)
                        .opacity(task.isCompleted ? 0.58 : 1)
                        Divider()
                    }
                }
            }
        }
    }

    private var taskKanban: some View {
        VStack(alignment: .leading, spacing: 8) {
            let columns = StudyTaskBoard.columns(for: workspace.studyTasks ?? [])
            HStack(alignment: .top, spacing: 12) {
                ForEach([StudyTaskPriority.high, .normal, .low], id: \.self) { priority in
                    kanbanColumn(priority, tasks: columns[priority] ?? [])
                }
            }
            if (workspace.studyTasks ?? []).allSatisfy(\.isCompleted) || (workspace.studyTasks ?? []).isEmpty {
                Text("Arraste cartões entre as colunas para mudar a prioridade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func kanbanColumn(_ priority: StudyTaskPriority, tasks: [StudyTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(priority.label) · \(tasks.count)", systemImage: "flag.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(priorityColor(priority))
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.subheadline)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(studyTaskDateLabel(task))
                        .font(.caption2)
                        .foregroundStyle(studyTaskIsOverdue(task) ? Color.red : Color.secondary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                .draggable(task.id.uuidString)
                .contextMenu { studyTaskMenu(task) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first,
                  let id = UUID(uuidString: idString),
                  let index = workspace.studyTasks?.firstIndex(where: { $0.id == id }) else { return false }
            workspace.studyTasks?[index].priority = priority
            return true
        }
    }

    private func planRow(
        title: String,
        detail: String?,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func taskPlanRow(_ task: MarkdownTask) -> some View {
        HStack(spacing: 12) {
            Button { onToggleTask(task) } label: {
                Image(systemName: "circle")
                    .foregroundStyle(taskIsOverdue(task) ? Color.red : Color.purple)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            Button { onOpenTask(task.nodeID) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).font(.subheadline.weight(.semibold))
                        if let detail = taskDateLabel(task) {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private func studyTaskPlanRow(_ task: StudyTask) -> some View {
        HStack(spacing: 12) {
            Button { onToggleStudyTask(task) } label: {
                Image(systemName: "circle")
                    .foregroundStyle(priorityColor(task.priority))
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Button { onEditStudyTask(task) } label: {
                    Text(task.title).font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                Text(studyTaskDateLabel(task))
                    .font(.caption)
                    .foregroundStyle(studyTaskIsOverdue(task) ? .red : .secondary)
            }
            Spacer()
            priorityBadge(task.priority)
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .contextMenu { studyTaskMenu(task) }
    }

    private func studyTaskListRow(_ task: StudyTask) -> some View {
        HStack(spacing: 10) {
            Button { onToggleStudyTask(task) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.green : priorityColor(task.priority))
            }
            .buttonStyle(.plain)
            Button { onEditStudyTask(task) } label: {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            priorityBadge(task.priority)
            Text(studyTaskDateLabel(task))
                .font(.caption)
                .foregroundStyle(studyTaskIsOverdue(task) && !task.isCompleted ? .red : .secondary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .opacity(task.isCompleted ? 0.58 : 1)
        .contextMenu { studyTaskMenu(task) }
    }

    @ViewBuilder
    private func studyTaskMenu(_ task: StudyTask) -> some View {
        Button("Editar / reagendar") { onEditStudyTask(task) }
        Button("Excluir", role: .destructive) { onDeleteStudyTask(task) }
    }

    private func priorityBadge(_ priority: StudyTaskPriority) -> some View {
        Text(priority.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(priorityColor(priority))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(priorityColor(priority).opacity(0.12), in: Capsule())
    }

    private var materials: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Materiais").font(.title2.bold())
            ForEach(snapshot.materials) { material in
                Button { onOpenMaterial(material.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: material.kind.icon).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(material.title).font(.headline)
                            HStack {
                                if let fraction = material.fraction {
                                    ProgressView(value: fraction).frame(maxWidth: 260)
                                    Text("Posição \(Int((fraction * 100).rounded()))%")
                                } else {
                                    Text("Sem progresso mensurável")
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                            if let covered = material.covered, let total = material.total {
                                Text("Cobertura: \(covered) de \(total)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(material.noteCount) nota(s)").font(.caption).foregroundStyle(.secondary)
                        if material.dueCards > 0 { Text("\(material.dueCards) devidos").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                        Image(systemName: "arrow.right")
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private var reviewAgain: some View {
        let questions = (workspace.studyArtifacts ?? []).filter { $0.kind == .question }.sorted { $0.createdAt > $1.createdAt }
        let flashcards = (workspace.studyArtifacts ?? []).filter { $0.kind == .flashcards }.sorted { $0.createdAt > $1.createdAt }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rever depois").font(.title2.bold())
                Spacer()
                Text("Questões e flashcards salvos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if questions.isEmpty && flashcards.isEmpty {
                Text("As questões e os flashcards criados aparecerão aqui para revisão futura.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(questions.prefix(5))) { question in
                    Button { onReviewQuestion(question) } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(questionPreview(question.body)).lineLimit(2)
                                Text(question.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("Rever questão", systemImage: "arrow.right")
                                .font(.caption)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                ForEach(Array(flashcards.prefix(5))) { item in
                    Button { onReviewFlashcards(item) } label: {
                        HStack {
                            Image(systemName: "rectangle.on.rectangle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(StudyFlashcard.parseDeck(item.body)?.count ?? 0) flashcards")
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("Rever flashcards", systemImage: "arrow.right")
                                .font(.caption)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var lightPractice: some View {
        let vocabulary = WordSearchPuzzle.vocabulary(from: workspace.studyArtifacts ?? [])
        if vocabulary.count >= 3 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Prática leve").font(.title2.bold())
                WordSearchView(rawWords: vocabulary)
            }
        }
    }

    @ViewBuilder
    private var dailyNotes: some View {
        let notes = workspace.nodes.filter { $0.obsidian?.isDailyNote == true }
            .sorted { ($0.obsidian?.relativePath ?? "") > ($1.obsidian?.relativePath ?? "") }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Diário de estudo").font(.title2.bold())
                ForEach(notes.prefix(7)) { note in
                    Button { onOpenTask(note.id) } label: {
                        HStack {
                            Image(systemName: "calendar.day.timeline.left")
                            Text(note.title).frame(maxWidth: .infinity, alignment: .leading)
                            if let status = note.obsidian?.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                            Image(systemName: "arrow.right")
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var production: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Produção de estudo").font(.title2.bold())
            HStack(spacing: 18) {
                Label("\(snapshot.noteCount) notas", systemImage: "note.text")
                Label("\(snapshot.markingCount) marcações", systemImage: "highlighter")
                Label("\(snapshot.flashcardCount) flashcards", systemImage: "rectangle.on.rectangle")
                Label("\(snapshot.questionCount) questões", systemImage: "questionmark.circle")
            }.foregroundStyle(.secondary)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Atividade recente").font(.title2.bold())
            if snapshot.recentActivity.isEmpty {
                Text("As próximas ações de estudo aparecerão aqui.").foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.recentActivity) { event in
                    HStack {
                        Image(systemName: activityIcon(event.kind)).foregroundStyle(Color.accentColor)
                        Text(activityLabel(event.kind))
                        Spacer()
                        Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
        }
    }

    private var plannedFlashcardItems: [(artifact: StudyArtifact, plan: FlashcardPlanItem)] {
        let artifacts = workspace.studyArtifacts ?? []
        let reviews = workspace.flashcardReviews ?? []
        let planByID = Dictionary(uniqueKeysWithValues: ProgressMetrics.flashcardPlan(
            artifacts: artifacts,
            reviews: reviews
        ).map { ($0.artifactID, $0) })
        return artifacts
            .compactMap { artifact in planByID[artifact.id].map { (artifact, $0) } }
            .filter { $0.1.total > 0 }
            .sorted {
                if $0.1.due != $1.1.due { return $0.1.due > $1.1.due }
                return $0.0.createdAt < $1.0.createdAt
            }
    }

    private var firstPlannedFlashcards: (artifact: StudyArtifact, plan: FlashcardPlanItem)? {
        plannedFlashcardItems.first
    }

    private var questionsToReview: [StudyArtifact] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let reviews = (workspace.studyActivityEvents ?? [])
            .filter { $0.kind == .reviewedQuestion && $0.artifactID != nil }
        let lastReviewByQuestion = Dictionary(grouping: reviews, by: { $0.artifactID! })
            .mapValues { events in events.map(\.occurredAt).max()! }
        return (workspace.studyArtifacts ?? [])
            .filter {
                $0.kind == .question
                    && $0.createdAt < startOfToday
                    && lastReviewByQuestion[$0.id].map { !calendar.isDateInToday($0) } != false
            }
            .sorted {
                (lastReviewByQuestion[$0.id] ?? $0.createdAt) < (lastReviewByQuestion[$1.id] ?? $1.createdAt)
            }
    }

    private var firstQuestionToReview: StudyArtifact? {
        questionsToReview.first
    }

    private var firstPriorityTask: MarkdownTask? {
        priorityTasks.first
    }

    private var priorityTasks: [MarkdownTask] {
        snapshot.tasks.filter { !$0.isCompleted }.sorted(by: taskSort)
    }

    private var allStudyTasks: [StudyTask] {
        (workspace.studyTasks ?? []).sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            let leftPriority = priorityRank($0.priority)
            let rightPriority = priorityRank($1.priority)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return $0.dueDate < $1.dueDate
        }
    }

    private var priorityStudyTasks: [StudyTask] {
        allStudyTasks.filter { !$0.isCompleted }
    }

    private var openTaskCount: Int {
        priorityStudyTasks.count + snapshot.tasks.filter { !$0.isCompleted }.count
    }

    private var completedTaskCount: Int {
        allStudyTasks.filter(\.isCompleted).count + snapshot.tasks.filter(\.isCompleted).count
    }

    private var continueMaterial: MaterialProgressSnapshot? {
        let progressByID = Dictionary(uniqueKeysWithValues: snapshot.materials.map { ($0.id, $0) })
        for entry in (workspace.studyHistory ?? []).reversed() {
            if let material = progressByID[entry.nodeID], material.fraction.map({ $0 < 1 }) ?? true {
                return material
            }
        }
        return snapshot.materials.first { $0.fraction.map { $0 < 1 } ?? true }
    }

    private var todayActionCount: Int {
        (firstPlannedFlashcards == nil ? 0 : 1)
            + (firstQuestionToReview == nil ? 0 : 1)
            + (firstPriorityTask == nil && priorityStudyTasks.isEmpty ? 0 : 1)
            + (continueMaterial == nil ? 0 : 1)
    }

    private var hasStartableAction: Bool {
        if firstPlannedFlashcards != nil || firstQuestionToReview != nil { return true }
        return !priorityStudyTasks.isEmpty || firstPriorityTask != nil || continueMaterial != nil
    }

    private var todaySummary: String {
        var parts: [String] = []
        if snapshot.dueCount > 0 { parts.append("\(snapshot.dueCount) revisões devidas") }
        let plannedNew = plannedFlashcardItems.reduce(0) { $0 + $1.plan.new }
        if plannedNew > 0 { parts.append("\(plannedNew) flashcards novos") }
        if !questionsToReview.isEmpty { parts.append("\(questionsToReview.count) questões para rever") }
        if openTaskCount > 0 { parts.append("\(openTaskCount) tarefas abertas") }
        return parts.isEmpty ? "Seu plano está em dia" : parts.joined(separator: " · ")
    }

    private func startNextAction() {
        if let item = firstPlannedFlashcards {
            onReviewFlashcards(item.artifact)
        } else if let question = firstQuestionToReview {
            onReviewQuestion(question)
        } else if let task = priorityStudyTasks.first {
            onEditStudyTask(task)
        } else if let task = firstPriorityTask {
            onOpenTask(task.nodeID)
        } else if let material = continueMaterial {
            onOpenMaterial(material.id)
        }
    }

    private func flashcardPlanTitle(_ plan: FlashcardPlanItem) -> String {
        if plan.due > 0 && plan.new > 0 {
            return "Revisar \(plan.due) devido(s) e \(plan.new) novo(s)"
        }
        if plan.due > 0 { return "Revisar \(plan.due) flashcard(s) devido(s)" }
        return "Estudar \(plan.new) flashcard(s) novo(s)"
    }

    private func materialTitle(for nodeID: UUID?) -> String? {
        guard let nodeID else { return nil }
        return workspace.nodes.first { $0.id == nodeID }?.title
    }

    private func taskIsOverdue(_ task: MarkdownTask) -> Bool {
        guard let dueDate = task.dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    private func taskDateLabel(_ task: MarkdownTask) -> String? {
        guard let dueDate = task.dueDate else { return "Sem prazo definido" }
        let calendar = Calendar.current
        if taskIsOverdue(task) { return "Atrasada desde \(dueDate.formatted(date: .abbreviated, time: .omitted))" }
        if calendar.isDateInToday(dueDate) { return "Para hoje" }
        return "Prazo: \(dueDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private func studyTaskIsOverdue(_ task: StudyTask) -> Bool {
        task.dueDate < Calendar.current.startOfDay(for: Date())
    }

    private func studyTaskDateLabel(_ task: StudyTask) -> String {
        let calendar = Calendar.current
        if studyTaskIsOverdue(task) { return "Atrasada · \(task.dueDate.formatted(date: .abbreviated, time: .omitted))" }
        if calendar.isDateInToday(task.dueDate) { return "Hoje" }
        if calendar.isDateInTomorrow(task.dueDate) { return "Amanhã" }
        return task.dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func priorityRank(_ priority: StudyTaskPriority) -> Int {
        switch priority {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    private func priorityColor(_ priority: StudyTaskPriority) -> Color {
        switch priority {
        case .high: return .red
        case .normal: return .orange
        case .low: return .secondary
        }
    }

    private var nearestDeadline: (label: String, date: Date)? {
        [("Prova", workspace.examDate), ("Apresentação", workspace.presentationDate)]
            .compactMap { label, date in date.map { (label, $0) } }
            .sorted { $0.1 < $1.1 }
            .first
    }

    private func taskSort(_ lhs: MarkdownTask, _ rhs: MarkdownTask) -> Bool {
        (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
    }

    private func activityIcon(_ kind: StudyActivityKind) -> String {
        switch kind {
        case .openedMaterial: return "book"
        case .createdNote: return "note.text"
        case .reviewedFlashcard: return "rectangle.on.rectangle"
        case .reviewedQuestion: return "questionmark.circle"
        case .completedTask: return "checkmark.circle"
        }
    }

    private func activityLabel(_ kind: StudyActivityKind) -> String {
        switch kind {
        case .openedMaterial: return "Material aberto"
        case .createdNote: return "Nota criada"
        case .reviewedFlashcard: return "Flashcard revisado"
        case .reviewedQuestion: return "Questão revista"
        case .completedTask: return "Tarefa concluída"
        }
    }

    private func questionPreview(_ body: String) -> String {
        body.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.lowercased().hasPrefix("gabarito") }
            ?? "Questão salva"
    }
}

private struct WordSearchView: View {
    let rawWords: [String]
    @State private var puzzle: WordSearchPuzzle?
    @State private var found: Set<String> = []
    @State private var selectionStart: WordSearchPuzzle.Coordinate?
    @State private var wrongEnd: WordSearchPuzzle.Coordinate?
    @State private var dragStartCell: WordSearchPuzzle.Coordinate?
    @State private var dragCurrentCell: WordSearchPuzzle.Coordinate?
    @State private var pulseWord: String?
    @State private var revealAll = false

    private let cellSize: CGFloat = 30
    private let cellSpacing: CGFloat = 3
    private let palette: [Color] = [.blue, .orange, .purple, .green, .pink, .teal]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let puzzle {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        gridCard(puzzle)
                        sidePanel(puzzle)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        gridCard(puzzle)
                        sidePanel(puzzle)
                    }
                }
                if found.count == puzzle.placements.count {
                    completionBanner
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            } else {
                emptyHint
            }
        }
        .animation(.easeInOut(duration: 0.25), value: found)
        .padding(16)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            if puzzle == nil { generate() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Label("Caça-palavras dos flashcards", systemImage: "square.grid.3x3.middle.filled")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let puzzle {
                ProgressView(value: Double(found.count), total: Double(puzzle.placements.count))
                    .frame(width: 110)
                Text("\(found.count)/\(puzzle.placements.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                revealAll.toggle()
            } label: {
                Label("Revelar", systemImage: revealAll ? "eye.fill" : "eye")
            }
            .controlSize(.small)
            .help(revealAll ? "Esconder as palavras" : "Mostrar onde as palavras estão")
            Button {
                generate()
            } label: {
                Label("Novo", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
        }
    }

    private var cellStep: CGFloat { cellSize + cellSpacing }

    private func gridCard(_ puzzle: WordSearchPuzzle) -> some View {
        var foundOffsets: [WordSearchPuzzle.Coordinate: Int] = [:]
        for (offset, placement) in puzzle.placements.enumerated() where found.contains(placement.word) {
            for cell in placement.cells {
                foundOffsets[cell] = offset
            }
        }
        let previewLine = previewLine(in: puzzle)
        let gridWidth = CGFloat(puzzle.size) * cellStep - cellSpacing
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellSize), spacing: cellSpacing), count: puzzle.size),
            spacing: cellSpacing
        ) {
            ForEach(0..<(puzzle.size * puzzle.size), id: \.self) { index in
                let row = index / puzzle.size
                let col = index % puzzle.size
                let coordinate = WordSearchPuzzle.Coordinate(row: row, col: col)
                wordSearchCell(puzzle, coordinate: coordinate, row: row, col: col, foundOffset: foundOffsets[coordinate])
            }
        }
        .frame(width: gridWidth)
        .overlay {
            Canvas { context, _ in
                for (offset, placement) in puzzle.placements.enumerated() {
                    let color = palette[offset % palette.count]
                    let isFound = found.contains(placement.word)
                    if !isFound && !revealAll { continue }
                    guard let last = placement.cells.last else { continue }
                    var path = Path()
                    path.move(to: cellCenter(placement.start))
                    path.addLine(to: cellCenter(last))
                    context.stroke(
                        path,
                        with: .color(color.opacity(isFound ? 0.38 : 0.16)),
                        style: StrokeStyle(
                            lineWidth: cellSize * 0.72,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: isFound ? [] : [2, 6]
                        )
                    )
                }
                if let line = previewLine {
                    var path = Path()
                    path.move(to: cellCenter(line.start))
                    path.addLine(to: cellCenter(line.end))
                    context.stroke(
                        path,
                        with: .color(line.isValid ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.12)),
                        style: StrokeStyle(lineWidth: cellSize * 0.72, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .gesture(dragGesture(in: puzzle))
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
        )
    }

    private func wordSearchCell(
        _ puzzle: WordSearchPuzzle,
        coordinate: WordSearchPuzzle.Coordinate,
        row: Int,
        col: Int,
        foundOffset: Int?
    ) -> some View {
        let isStart = selectionStart == coordinate || dragStartCell == coordinate
        let isWrong = wrongEnd == coordinate
        let tint: Color? = foundOffset.map { palette[$0 % palette.count] }
        let fill: Color
        if let tint {
            fill = tint.opacity(0.18)
        } else if isStart {
            fill = Color.accentColor.opacity(0.3)
        } else if isWrong {
            fill = Color.red.opacity(0.22)
        } else {
            fill = Color.primary.opacity(0.08)
        }
        return Text(String(puzzle.grid[row][col]))
            .font(.system(.callout, design: .monospaced).weight(foundOffset != nil || isStart ? .bold : .regular))
            .foregroundStyle(tint ?? Color.primary)
            .frame(width: cellSize, height: cellSize)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
    }

    private func sidePanel(_ puzzle: WordSearchPuzzle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(puzzle.placements.enumerated().map { (word: $0.element.word, offset: $0.offset) }, id: \.word) { item in
                    let color = palette[item.offset % palette.count]
                    let isFound = found.contains(item.word)
                    let isPulsing = pulseWord == item.word
                    HStack(spacing: 5) {
                        Image(systemName: isFound ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(isFound ? color : Color.secondary)
                        Text(item.word)
                            .font(.caption.weight(.semibold))
                            .strikethrough(isFound)
                            .foregroundStyle(isFound ? color : Color.primary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(color.opacity(isFound ? 0.14 : 0.06)))
                    .overlay(Capsule().strokeBorder(color.opacity(isPulsing ? 0.9 : 0), lineWidth: 2))
                    .scaleEffect(isPulsing ? 1.12 : 1)
                    .animation(.spring(duration: 0.3), value: pulseWord)
                }
            }
            Text("Arraste pelas letras ou toque na primeira e na última — horizontal, vertical, diagonal e ao contrário.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var completionBanner: some View {
        Label("Todas as palavras encontradas — bom estudo!", systemImage: "party.popper.fill")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyHint: some View {
        Text("Os termos dos flashcards precisam ter pelo menos 4 letras para virar o caça-palavras.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func generate() {
        puzzle = WordSearchPuzzle.make(from: rawWords)
        found = []
        selectionStart = nil
        wrongEnd = nil
        dragStartCell = nil
        dragCurrentCell = nil
        pulseWord = nil
        revealAll = false
    }

    private func cellCenter(_ coordinate: WordSearchPuzzle.Coordinate) -> CGPoint {
        CGPoint(
            x: CGFloat(coordinate.col) * cellStep + cellSize / 2,
            y: CGFloat(coordinate.row) * cellStep + cellSize / 2
        )
    }

    private func cellAt(_ location: CGPoint, in puzzle: WordSearchPuzzle) -> WordSearchPuzzle.Coordinate? {
        let col = Int(location.x / cellStep)
        let row = Int(location.y / cellStep)
        guard row >= 0, row < puzzle.size, col >= 0, col < puzzle.size else { return nil }
        return WordSearchPuzzle.Coordinate(row: row, col: col)
    }

    private func previewLine(in puzzle: WordSearchPuzzle) -> (start: WordSearchPuzzle.Coordinate, end: WordSearchPuzzle.Coordinate, isValid: Bool)? {
        guard let start = dragStartCell, let end = dragCurrentCell, start != end else { return nil }
        let deltaRow = end.row - start.row
        let deltaCol = end.col - start.col
        let straight = deltaRow == 0 || deltaCol == 0 || abs(deltaRow) == abs(deltaCol)
        guard straight else { return nil }
        return (start, end, true)
    }

    private func dragGesture(in puzzle: WordSearchPuzzle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let cell = cellAt(value.location, in: puzzle)
                if dragStartCell == nil {
                    dragStartCell = cell
                }
                dragCurrentCell = cell ?? dragCurrentCell
            }
            .onEnded { value in
                guard let start = dragStartCell,
                      let end = cellAt(value.location, in: puzzle) else {
                    dragStartCell = nil
                    dragCurrentCell = nil
                    return
                }
                commitSelection(start: start, end: end, in: puzzle)
                dragStartCell = nil
                dragCurrentCell = nil
            }
    }

    private func commitSelection(start: WordSearchPuzzle.Coordinate, end: WordSearchPuzzle.Coordinate, in puzzle: WordSearchPuzzle) {
        if start == end {
            if let existing = selectionStart {
                if existing == start {
                    selectionStart = nil
                } else {
                    tryWord(from: existing, to: start, in: puzzle)
                }
            } else {
                selectionStart = start
            }
        } else {
            tryWord(from: start, to: end, in: puzzle)
        }
    }

    private func tryWord(from start: WordSearchPuzzle.Coordinate, to end: WordSearchPuzzle.Coordinate, in puzzle: WordSearchPuzzle) {
        selectionStart = nil
        wrongEnd = nil
        guard let word = puzzle.word(from: start, to: end) else {
            wrongEnd = end
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if wrongEnd == end { wrongEnd = nil }
            }
            return
        }
        guard !found.contains(word) else { return }
        found.insert(word)
        pulseWord = word
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if pulseWord == word { pulseWord = nil }
        }
    }
}
