import Foundation

struct MarkdownTask: Identifiable, Equatable {
    var id: String { "\(nodeID.uuidString):\(lineNumber)" }
    let nodeID: UUID
    let lineNumber: Int
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
}

enum MarkdownTaskParser {
    static func tasks(in body: String, nodeID: UUID) -> [MarkdownTask] {
        let lines = body.components(separatedBy: .newlines)
        var fenced = false
        var result: [MarkdownTask] = []
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenced.toggle()
                continue
            }
            guard !fenced,
                  let expression = try? NSRegularExpression(pattern: #"^\s*[-*+]\s+\[([ xX])\]\s+(.+)$"#),
                  let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let stateRange = Range(match.range(at: 1), in: line),
                  let titleRange = Range(match.range(at: 2), in: line) else { continue }
            let rawTitle = String(line[titleRange])
            result.append(MarkdownTask(
                nodeID: nodeID,
                lineNumber: index,
                title: removingDueDate(from: rawTitle),
                isCompleted: line[stateRange].lowercased() == "x",
                dueDate: dueDate(in: rawTitle)
            ))
        }
        return result
    }

    static func toggled(_ task: MarkdownTask, in body: String) -> String {
        var lines = body.components(separatedBy: .newlines)
        guard lines.indices.contains(task.lineNumber) else { return body }
        let replacement = task.isCompleted ? "[ ]" : "[x]"
        lines[task.lineNumber] = lines[task.lineNumber].replacingOccurrences(
            of: #"\[[ xX]\]"#,
            with: replacement,
            options: .regularExpression,
            range: lines[task.lineNumber].startIndex..<lines[task.lineNumber].endIndex
        )
        return lines.joined(separator: "\n")
    }

    private static func dueDate(in title: String) -> Date? {
        let patterns = [#"📅\s*(\d{4}-\d{2}-\d{2})"#, #"@due\((\d{4}-\d{2}-\d{2})\)"#]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let range = Range(match.range(at: 1), in: title) else { continue }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: String(title[range])) { return date }
        }
        return nil
    }

    private static func removingDueDate(from title: String) -> String {
        title.replacingOccurrences(of: #"\s*(?:📅\s*\d{4}-\d{2}-\d{2}|@due\(\d{4}-\d{2}-\d{2}\))"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MaterialProgressSnapshot: Identifiable {
    let id: UUID
    let title: String
    let kind: NodeKind
    let completed: Int?
    let total: Int?
    let noteCount: Int
    let dueCards: Int
    let covered: Int?

    var fraction: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

struct WorkspaceProgressSnapshot {
    let completedUnits: Int
    let totalUnits: Int
    let materials: [MaterialProgressSnapshot]
    let tasks: [MarkdownTask]
    let noteCount: Int
    let markingCount: Int
    let deckCount: Int
    let flashcardCount: Int
    let dueCount: Int
    let newCount: Int
    let questionCount: Int
    let activitiesToday: Int
    let focusedMinutesToday: Int
    let recentActivity: [StudyActivityEvent]
    let coveredUnits: Int
    let coverableUnits: Int
    let practiceToday: Int
    let retentionFraction: Double?

    var fraction: Double? {
        totalUnits > 0 ? Double(completedUnits) / Double(totalUnits) : nil
    }

    var coverageFraction: Double? {
        coverableUnits > 0 ? Double(coveredUnits) / Double(coverableUnits) : nil
    }
}

struct FlashcardPlanItem: Equatable {
    let artifactID: UUID
    let due: Int
    let new: Int

    var total: Int { due + new }
}

enum ProgressMetrics {
    static let dailyNewCardLimit = 20

    static func snapshot(for workspace: Workspace, now: Date = Date(), calendar: Calendar = .current) -> WorkspaceProgressSnapshot {
        let artifacts = workspace.studyArtifacts ?? []
        let reviews = workspace.flashcardReviews ?? []
        var completedUnits = 0
        var totalUnits = 0
        var materialSnapshots: [MaterialProgressSnapshot] = []
        var allTasks: [MarkdownTask] = []
        var flashcardCount = 0
        var dueCount = 0
        var newCount = 0
        var coveredUnits = 0
        var coverableUnits = 0

        for deck in artifacts where deck.kind == .flashcards {
            let counts = flashcardCounts(for: deck, reviews: reviews, now: now)
            flashcardCount += counts.total
            dueCount += counts.due
            newCount += counts.new
        }

        for node in workspace.nodes {
            if node.kind == .note { allTasks += MarkdownTaskParser.tasks(in: node.noteBody, nodeID: node.id) }
            guard node.isStudyMaterial else { continue }
            let progress: (Int?, Int?)
            switch node.kind {
            case .epub:
                progress = (node.epubPageCount.map { min($0, (node.epubPageIndex ?? 0) + 1) }, node.epubPageCount)
            case .pdf:
                progress = (node.pdfPageCount.map { min($0, node.pdfPageIndex + 1) }, node.pdfPageCount)
            case .slides:
                let total = node.slidesPages?.count
                progress = (total.map { min($0, (node.slidesPageIndex ?? 0) + 1) }, total)
            case .web:
                progress = (nil, nil)
            case .note, .calc:
                progress = (nil, nil)
            }
            if let completed = progress.0, let total = progress.1, total > 0 {
                completedUnits += completed
                totalUnits += total
            }
            let covered = node.visitedUnitIndices.map { indices in
                Set(indices.filter { $0 >= 0 && $0 < (progress.1 ?? 0) }).count
            }
            if let covered, let total = progress.1, total > 0 {
                coveredUnits += covered
                coverableUnits += total
            }
            let nodeArtifacts = artifacts.filter { $0.sourceNodeID == node.id }
            let decks = nodeArtifacts.filter { $0.kind == .flashcards }
            let nodeDue = decks.reduce(0) { result, deck in
                result + flashcardCounts(for: deck, reviews: reviews, now: now).due
            }
            materialSnapshots.append(MaterialProgressSnapshot(
                id: node.id,
                title: node.title,
                kind: node.kind,
                completed: progress.0,
                total: progress.1,
                noteCount: nodeArtifacts.filter { $0.kind == .note }.count + (node.epubAnnotations ?? []).filter { $0.note?.isEmpty == false }.count,
                dueCards: nodeDue,
                covered: covered
            ))
        }

        let activities = (workspace.studyActivityEvents ?? []).sorted { $0.occurredAt > $1.occurredAt }
        return WorkspaceProgressSnapshot(
            completedUnits: completedUnits,
            totalUnits: totalUnits,
            materials: materialSnapshots,
            tasks: allTasks,
            noteCount: artifacts.filter { $0.kind == .note }.count + workspace.nodes.filter {
                $0.kind == .note && $0.sourceArtifactKind != .flashcards && !$0.noteBody.isEmpty
            }.count,
            markingCount: workspace.nodes.reduce(0) { $0 + ($1.epubAnnotations?.count ?? 0) },
            deckCount: artifacts.filter { $0.kind == .flashcards }.count,
            flashcardCount: flashcardCount,
            dueCount: dueCount,
            newCount: newCount,
            questionCount: artifacts.filter { $0.kind == .question }.count,
            activitiesToday: activities.filter { calendar.isDate($0.occurredAt, inSameDayAs: now) }.count,
            focusedMinutesToday: (workspace.focusSessions ?? [])
                .filter { calendar.isDate($0.endedAt, inSameDayAs: now) }
                .reduce(0) { $0 + $1.completedMinutes },
            recentActivity: Array(activities.prefix(12)),
            coveredUnits: coveredUnits,
            coverableUnits: coverableUnits,
            practiceToday: activities.filter {
                calendar.isDate($0.occurredAt, inSameDayAs: now)
                    && ($0.kind == .reviewedFlashcard || $0.kind == .reviewedQuestion)
            }.count,
            retentionFraction: retentionFraction(reviews: reviews)
        )
    }

    static func retentionFraction(reviews: [FlashcardReview]) -> Double? {
        let rated = reviews.compactMap(\.lastRating)
        guard !rated.isEmpty else { return nil }
        let successful = rated.filter { $0 == .good || $0 == .easy }.count
        return Double(successful) / Double(rated.count)
    }

    static func flashcardCounts(
        for artifact: StudyArtifact,
        reviews: [FlashcardReview],
        now: Date = Date()
    ) -> (total: Int, due: Int, new: Int) {
        let cards = StudyFlashcard.parseDeck(artifact.body) ?? []
        var due = 0
        var new = 0
        for card in cards {
            let review = reviews.first {
                ($0.key == card.id || $0.key == card.legacyID || $0.key == card.legacyFullID)
                    && $0.sourceNodeID == artifact.sourceNodeID
                    && ($0.deckID == artifact.id || $0.deckID == nil)
            }
            if let review {
                if review.dueAt <= now { due += 1 }
            } else {
                new += 1
            }
        }
        return (cards.count, due, new)
    }

    static func flashcardPlan(
        artifacts: [StudyArtifact],
        reviews: [FlashcardReview],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [FlashcardPlanItem] {
        let introducedToday = reviews.filter { review in
            let first = review.firstReviewedAt ?? review.lastReviewedAt
            return first.map { calendar.isDate($0, inSameDayAs: now) } == true
        }.count
        var remainingNew = max(0, dailyNewCardLimit - introducedToday)
        return artifacts
            .filter { $0.kind == .flashcards }
            .sorted { $0.createdAt < $1.createdAt }
            .map { artifact in
                let counts = flashcardCounts(for: artifact, reviews: reviews, now: now)
                let allowedNew = min(counts.new, remainingNew)
                remainingNew -= allowedNew
                return FlashcardPlanItem(artifactID: artifact.id, due: counts.due, new: allowedNew)
            }
    }
}
