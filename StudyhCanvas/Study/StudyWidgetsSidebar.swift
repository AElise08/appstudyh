import SwiftUI

struct FocusTimerCompletion {
    let workspaceID: UUID
    let materialID: UUID?
    let startedAt: Date
    let endedAt: Date
    let plannedMinutes: Int
    let completedMinutes: Int
    let intention: String
}

@MainActor
final class FocusTimerController: ObservableObject {
    @Published var selectedMinutes = 25
    @Published var remainingSeconds = 25 * 60
    @Published var isRunning = false
    @Published var intention = ""
    private var startedAt: Date?
    private var deadline: Date?
    private var workspaceID: UUID?
    private var materialID: UUID?

    func start(workspaceID: UUID, materialID: UUID?, at now: Date = Date()) {
        if startedAt == nil || remainingSeconds <= 0 {
            remainingSeconds = selectedMinutes * 60
            startedAt = now
            self.workspaceID = workspaceID
            self.materialID = materialID
        }
        deadline = now.addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true
    }

    func pause(at now: Date = Date()) {
        refreshRemaining(at: now)
        isRunning = false
        deadline = nil
    }

    func reset() {
        isRunning = false
        remainingSeconds = selectedMinutes * 60
        startedAt = nil
        deadline = nil
        workspaceID = nil
        materialID = nil
    }

    func changeDuration() {
        guard !isRunning else { return }
        remainingSeconds = selectedMinutes * 60
        startedAt = nil
        deadline = nil
    }

    func tick(at now: Date = Date()) -> FocusTimerCompletion? {
        guard isRunning, let deadline else { return nil }
        refreshRemaining(at: now)
        guard remainingSeconds == 0,
               let startedAt,
               let workspaceID else { return nil }
        isRunning = false
        let completion = FocusTimerCompletion(
            workspaceID: workspaceID,
            materialID: materialID,
            startedAt: startedAt,
            endedAt: deadline,
            plannedMinutes: selectedMinutes,
            completedMinutes: selectedMinutes,
            intention: intention.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        self.startedAt = nil
        self.deadline = nil
        self.workspaceID = nil
        self.materialID = nil
        return completion
    }

    private func refreshRemaining(at now: Date) {
        guard let deadline else { return }
        remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    var timeLabel: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
}

struct StudyWidgetsSidebar: View {
    let workspace: Workspace
    let activeMaterial: CanvasNode?
    @ObservedObject var timer: FocusTimerController
    let onShowProgress: () -> Void
    let onClose: () -> Void

    private var snapshot: WorkspaceProgressSnapshot {
        ProgressMetrics.snapshot(for: workspace)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Widgets").font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("Ocultar widgets")
                    .accessibilityLabel("Ocultar widgets")
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.bar)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    pomodoro
                    today
                    session
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var pomodoro: some View {
        widgetCard("Pomodoro", icon: "timer") {
            TextField("O que você vai terminar?", text: $timer.intention)
                .textFieldStyle(.roundedBorder)
            Picker("Duração", selection: $timer.selectedMinutes) {
                Text("25 min").tag(25)
                Text("45 min").tag(45)
                Text("60 min").tag(60)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(timer.isRunning)
            .onChange(of: timer.selectedMinutes) { _, _ in timer.changeDuration() }
            Text(timer.timeLabel)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            HStack {
                Button(timer.isRunning ? "Pausar" : "Iniciar") {
                    if timer.isRunning {
                        timer.pause()
                    } else {
                        timer.start(workspaceID: workspace.id, materialID: activeMaterial?.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Reiniciar", action: timer.reset)
                    .disabled(timer.remainingSeconds == timer.selectedMinutes * 60 && !timer.isRunning)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var today: some View {
        widgetCard("Hoje", icon: "calendar") {
            widgetMetric("Flashcards devidos", value: snapshot.dueCount, color: .orange)
            widgetMetric("Flashcards novos", value: min(snapshot.newCount, ProgressMetrics.dailyNewCardLimit), color: .blue)
            widgetMetric("Tarefas abertas", value: openTaskCount, color: .blue)
            if let deadline = nearestDeadline {
                Divider()
                HStack {
                    Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deadline.label).font(.caption.weight(.semibold))
                        Text(deadline.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            Button("Abrir Meu Progresso", action: onShowProgress)
                .buttonStyle(.link)
        }
    }

    private var session: some View {
        widgetCard("Sessão", icon: "book.pages") {
            HStack(alignment: .top) {
                Image(systemName: activeMaterial?.kind.icon ?? "minus.circle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(activeMaterial?.title ?? "Nenhum material aberto")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(timer.isRunning ? "Pomodoro em andamento" : "Tempo focado hoje: \(focusedMinutesToday) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !timer.intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                Text(timer.intention)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func widgetCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }

    private func widgetMetric(_ label: String, value: Int, color: Color) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)").font(.headline).monospacedDigit().foregroundStyle(color)
        }
    }

    private var openTaskCount: Int {
        (workspace.studyTasks ?? []).filter { !$0.isCompleted }.count
            + snapshot.tasks.filter { !$0.isCompleted }.count
    }

    private var nearestDeadline: (label: String, date: Date)? {
        [("Prova", workspace.examDate), ("Apresentação", workspace.presentationDate)]
            .compactMap { label, date in date.map { (label, $0) } }
            .sorted { $0.1 < $1.1 }
            .first
    }

    private var focusedMinutesToday: Int {
        (workspace.focusSessions ?? [])
            .filter { Calendar.current.isDateInToday($0.endedAt) }
            .reduce(0) { $0 + $1.completedMinutes }
    }
}
