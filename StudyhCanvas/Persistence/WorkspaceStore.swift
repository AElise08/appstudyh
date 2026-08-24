import Foundation
import Combine

@MainActor
final class WorkspaceStore: ObservableObject {
    private struct BackupManifest: Codable {
        var createdAt: Date
        var workspaceCount: Int
        var complete: Bool
    }

    enum SaveState: Equatable {
        case saved(Date)
        case saving
        case failed(String)

        var label: String {
            switch self {
            case .saved: return "Salvo"
            case .saving: return "Salvando"
            case .failed: return "Falha ao salvar"
            }
        }

        var symbolName: String {
            switch self {
            case .saved: return "checkmark.circle"
            case .saving: return "arrow.triangle.2.circlepath"
            case .failed: return "exclamationmark.triangle"
            }
        }

        var failureMessage: String? {
            guard case let .failed(message) = self else { return nil }
            return message
        }
    }

    @Published var workspaces: [Workspace] = []
    @Published private(set) var saveState: SaveState = .saved(Date())
    @Published var selectedID: UUID? {
        didSet {
            if oldValue != selectedID, !isLoading { persistSoon() }
        }
    }

    private let fileManager = FileManager.default
    private var saveTask: Task<Void, Never>?
    private var isLoading = false
    private var lastBackupAt: Date?
    private var hasUnresolvedLoadFailure = false
    private var dirtyWorkspaceIDs: Set<UUID> = []

    private enum LoadOutcome {
        case loaded
        case firstLaunch
        case failed(String)
    }

    private enum WorkspaceDecodeOutcome {
        case loaded(Workspace)
        case incompatible(String)
        case failed
    }

    private struct ScanRecovery {
        var workspaces: [Workspace]
        var hasFailures: Bool
    }

    var selectedWorkspace: Workspace? {
        workspaces.first(where: { $0.id == selectedID })
    }

    var selectedIndex: Int? {
        workspaces.firstIndex(where: { $0.id == selectedID })
    }

    init() {
        let outcome = load()
        if case .firstLaunch = outcome {
            createWorkspace(named: "Minha primeira matéria")
        }
    }

    private var rootURL: URL {
        if let override = ProcessInfo.processInfo.environment["STUDYH_DATA_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Studyh", isDirectory: true)
    }

    private var indexURL: URL {
        rootURL.appendingPathComponent("index.json")
    }

    private var backupsURL: URL {
        rootURL.appendingPathComponent("Backups", isDirectory: true)
    }

    var dataDirectoryURL: URL { rootURL }
    var backupsDirectoryURL: URL { backupsURL }

    private func workspaceURL(_ id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).json")
    }

    @discardableResult
    private func load() -> LoadOutcome {
        isLoading = true
        defer { isLoading = false }
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            let message = "Não foi possível abrir a pasta de dados: \(error.localizedDescription)"
            saveState = .failed(message)
            return .failed(message)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard fileManager.fileExists(atPath: indexURL.path) else {
            let recovered = recoverByScanning(decoder: decoder)
            if recovered.hasFailures {
                workspaces = recovered.workspaces
                selectedID = recovered.workspaces.first?.id
                hasUnresolvedLoadFailure = true
                let message = "Alguns arquivos de workspace não puderam ser lidos. Nenhum dado será sobrescrito."
                saveState = .failed(message)
                return .failed(message)
            }
            if recovered.workspaces.isEmpty {
                workspaces = []
                return .firstLaunch
            }
            workspaces = recovered.workspaces
            selectedID = recovered.workspaces.first?.id
            saveState = .failed("O índice estava ausente. Seus workspaces foram recuperados; revise-os antes de continuar.")
            persistNow()
            return .loaded
        }

        let index: WorkspaceIndex
        do {
            index = try decoder.decode(WorkspaceIndex.self, from: Data(contentsOf: indexURL))
        } catch {
            if let indexError = error as? WorkspaceIndexError,
               case .unsupportedSchemaVersion = indexError {
                hasUnresolvedLoadFailure = true
                let message = "\(indexError.localizedDescription) O arquivo original foi preservado e a gravação foi bloqueada."
                saveState = .failed(message)
                return .failed(message)
            }
            let scanned = recoverByScanning(decoder: decoder)
            if scanned.hasFailures {
                workspaces = scanned.workspaces
                selectedID = scanned.workspaces.first?.id
                hasUnresolvedLoadFailure = true
                let message = "O índice está danificado e alguns workspaces não puderam ser lidos. Nenhum dado foi sobrescrito."
                saveState = .failed(message)
                return .failed(message)
            }
            if !scanned.workspaces.isEmpty {
                workspaces = scanned.workspaces
                selectedID = scanned.workspaces.first?.id
                saveState = .failed("O índice estava danificado. Seus workspaces foram recuperados dos arquivos principais.")
                persistNow()
                return .loaded
            }
            if let recovered = recoverLatestBackup(decoder: decoder) {
                workspaces = recovered.workspaces
                selectedID = recovered.selectedID ?? recovered.workspaces.first?.id
                saveState = .failed("O índice principal estava danificado. Uma cópia de segurança foi recuperada.")
                persistNow()
                return .loaded
            }
            workspaces = []
            selectedID = nil
            let message = "O índice está danificado e não foi possível recuperar os workspaces. Nenhum dado foi sobrescrito."
            hasUnresolvedLoadFailure = true
            saveState = .failed(message)
            return .failed(message)
        }

        var loaded: [Workspace] = []
        var failedIDs: [UUID] = []
        var incompatibleMessages: [String] = []
        for id in index.workspaceIDs {
            switch decodeWorkspace(id, decoder: decoder) {
            case let .loaded(workspace):
                loaded.append(workspace)
            case let .incompatible(message):
                incompatibleMessages.append(message)
                failedIDs.append(id)
            case .failed:
                failedIDs.append(id)
            }
        }
        workspaces = loaded
        selectedID = index.selectedID ?? workspaces.first?.id
        if !failedIDs.isEmpty {
            hasUnresolvedLoadFailure = true
            if let incompatibility = incompatibleMessages.first {
                saveState = .failed("\(incompatibility) O arquivo original foi preservado e a gravação foi bloqueada.")
            } else {
                saveState = .failed("\(failedIDs.count) workspace(s) não puderam ser lidos. Os arquivos originais foram preservados.")
            }
            return .failed("Falha ao carregar workspaces")
        }
        saveState = .saved(Date())
        return .loaded
    }

    func createWorkspace(named name: String? = nil) {
        let label = name ?? "Workspace \(workspaces.count + 1)"
        let workspace = Workspace(name: label)
        workspaces.append(workspace)
        dirtyWorkspaceIDs.insert(workspace.id)
        selectedID = workspace.id
        persistSoon()
    }

    func deleteWorkspace(_ id: UUID) {
        do {
            _ = try createManualBackup()
            let previousWorkspaces = workspaces
            let previousSelection = selectedID
            workspaces.removeAll { $0.id == id }
            if selectedID == id {
                selectedID = workspaces.first?.id
            }
            persistNow()
            guard case .saved = saveState else {
                workspaces = previousWorkspaces
                selectedID = previousSelection
                return
            }
            try moveWorkspaceFilesToTrash([id], reason: "Delete")
        } catch {
            saveState = .failed("Não foi possível apagar o workspace com segurança: \(error.localizedDescription)")
        }
    }

    func restoreStoreState(_ restoredWorkspaces: [Workspace], selectedID restoredSelection: UUID?) {
        let removedIDs = Set(workspaces.map(\.id)).subtracting(restoredWorkspaces.map(\.id))
        markAllWorkspacesDirty()
        workspaces = restoredWorkspaces
        selectedID = restoredSelection
        dirtyWorkspaceIDs.formUnion(restoredWorkspaces.map(\.id))
        persistNow()
        guard case .saved = saveState else { return }
        do {
            try moveWorkspaceFilesToTrash(removedIDs, reason: "Undo")
        } catch {
            saveState = .failed("Os dados foram salvos, mas arquivos removidos não puderam ser movidos para a Lixeira interna: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createManualBackup() throws -> URL {
        try createSnapshot(in: backupsURL, prefix: "Manual")
    }

    @discardableResult
    func exportSnapshot(to parentURL: URL) throws -> URL {
        try createSnapshot(in: parentURL, prefix: "Studyh-Export")
    }

    func restoreBackup(from directory: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backupIndexURL = directory.appendingPathComponent("index.json")
        let index = try decoder.decode(WorkspaceIndex.self, from: Data(contentsOf: backupIndexURL))
        guard !index.workspaceIDs.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var restored: [Workspace] = []
        for id in index.workspaceIDs {
            let url = directory.appendingPathComponent("\(id.uuidString).json")
            let workspace = try WorkspaceDocumentCodec.decode(Data(contentsOf: url), using: decoder)
            guard workspace.id == id else { throw CocoaError(.fileReadCorruptFile) }
            restored.append(workspace)
        }

        _ = try createManualBackup()
        let staleURLs = workspaceDataURLs()
        workspaces = restored
        selectedID = index.selectedID.flatMap { selected in
            restored.contains(where: { $0.id == selected }) ? selected : nil
        } ?? restored.first?.id
        hasUnresolvedLoadFailure = false
        dirtyWorkspaceIDs = Set(restored.map(\.id))
        persistNow()
        guard case .saved = saveState else {
            throw CocoaError(.fileWriteUnknown)
        }

        let restoredIDs = Set(restored.map(\.id))
        let stale = staleURLs.filter {
            guard let id = UUID(uuidString: $0.deletingPathExtension().lastPathComponent) else { return false }
            return !restoredIDs.contains(id)
        }
        if !stale.isEmpty {
            let trash = rootURL.appendingPathComponent("Trash", isDirectory: true)
                .appendingPathComponent(backupName(prefix: "Restore"), isDirectory: true)
            try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
            for url in stale {
                try fileManager.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
            }
        }
    }

    func renameSelected(_ name: String) {
        guard let index = selectedIndex else { return }
        guard workspaces[index].name != name else { return }
        workspaces[index].name = name
        workspaces[index].updatedAt = Date()
        dirtyWorkspaceIDs.insert(workspaces[index].id)
        persistSoon()
    }

    func updateSelected(_ mutate: (inout Workspace) -> Void) {
        guard let index = selectedIndex else { return }
        mutate(&workspaces[index])
        workspaces[index].updatedAt = Date()
        dirtyWorkspaceIDs.insert(workspaces[index].id)
        persistSoon()
    }

    func updateSelectedByID(_ id: UUID, _ mutate: (inout Workspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        mutate(&workspaces[index])
        workspaces[index].updatedAt = Date()
        dirtyWorkspaceIDs.insert(id)
        persistSoon()
    }

    func markAllWorkspacesDirty() {
        dirtyWorkspaceIDs.formUnion(workspaces.map(\.id))
    }

    func persistSoon() {
        guard !hasUnresolvedLoadFailure else {
            saveState = .failed("Há workspaces que não puderam ser carregados. A gravação foi bloqueada para não sobrescrever o índice.")
            return
        }
        saveState = .saving
        guard saveTask == nil else { return }
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                saveTask = nil
                return
            }
            persistNow()
            saveTask = nil
        }
    }

    func persistNow() {
        guard !hasUnresolvedLoadFailure else {
            saveState = .failed("Há workspaces que não puderam ser carregados. A gravação foi bloqueada para não sobrescrever o índice.")
            return
        }
        saveState = .saving
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try createBackupIfNeeded()
            let dirty = dirtyWorkspaceIDs.isEmpty ? Set(workspaces.map(\.id)) : dirtyWorkspaceIDs
            for workspace in workspaces where dirty.contains(workspace.id) {
                let data = try WorkspaceDocumentCodec.encode(workspace, using: encoder)
                try data.write(to: workspaceURL(workspace.id), options: .atomic)
            }
            dirtyWorkspaceIDs.removeAll()
            let index = WorkspaceIndex(workspaceIDs: workspaces.map(\.id), selectedID: selectedID)
            try encoder.encode(index).write(to: indexURL, options: .atomic)
            saveState = .saved(Date())
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    private func decodeWorkspace(_ id: UUID, decoder: JSONDecoder) -> WorkspaceDecodeOutcome {
        do {
            let data = try Data(contentsOf: workspaceURL(id))
            return .loaded(try WorkspaceDocumentCodec.decode(data, using: decoder))
        } catch let error as WorkspaceDocumentError {
            if case .unsupportedSchemaVersion = error {
                return .incompatible(error.localizedDescription)
            }
            return .failed
        } catch {
            return .failed
        }
    }

    private func recoverByScanning(decoder: JSONDecoder) -> ScanRecovery {
        var recovered: [Workspace] = []
        var hasFailures = false
        for url in workspaceDataURLs() {
            do {
                let data = try Data(contentsOf: url)
                recovered.append(try WorkspaceDocumentCodec.decode(data, using: decoder))
            } catch {
                hasFailures = true
            }
        }
        recovered.sort { $0.updatedAt > $1.updatedAt }
        return ScanRecovery(workspaces: recovered, hasFailures: hasFailures)
    }

    private func workspaceDataURLs() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
            .filter { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
    }

    private func recoverLatestBackup(decoder: JSONDecoder) -> (workspaces: [Workspace], selectedID: UUID?)? {
        for directory in backupDirectoriesNewestFirst() {
            let manifestURL = directory.appendingPathComponent("manifest.json")
            if fileManager.fileExists(atPath: manifestURL.path) {
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? decoder.decode(BackupManifest.self, from: data),
                      manifest.complete else { continue }
            }
            let backupIndexURL = directory.appendingPathComponent("index.json")
            guard let data = try? Data(contentsOf: backupIndexURL),
                  let index = try? decoder.decode(WorkspaceIndex.self, from: data),
                  !index.workspaceIDs.isEmpty else { continue }
            var recovered: [UUID: Workspace] = [:]
            for id in index.workspaceIDs {
                let url = directory.appendingPathComponent("\(id.uuidString).json")
                if let data = try? Data(contentsOf: url),
                   let workspace = try? WorkspaceDocumentCodec.decode(data, using: decoder) {
                    recovered[id] = workspace
                }
            }
            if recovered.count == index.workspaceIDs.count {
                let ordered = index.workspaceIDs.compactMap { recovered[$0] }
                return (ordered, index.selectedID)
            }
        }
        return nil
    }

    private func createBackupIfNeeded(force: Bool = false) throws {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        if !force, let lastBackupAt, Date().timeIntervalSince(lastBackupAt) < 300 { return }

        try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        let staging = backupsURL.appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        let destination = backupsURL.appendingPathComponent(backupName(prefix: "Automatic"), isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: indexURL, to: staging.appendingPathComponent("index.json"))
            var copied = 0
            for workspace in workspaces {
                let source = workspaceURL(workspace.id)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent))
                    copied += 1
                }
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let manifest = BackupManifest(createdAt: Date(), workspaceCount: copied, complete: true)
            try encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        lastBackupAt = Date()
        pruneBackups(keeping: 20)
    }

    private func createSnapshot(in parentURL: URL, prefix: String) throws -> URL {
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let staging = parentURL.appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        let destination = parentURL.appendingPathComponent(backupName(prefix: prefix), isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            for workspace in workspaces {
                let data = try WorkspaceDocumentCodec.encode(workspace, using: encoder)
                try data.write(to: staging.appendingPathComponent("\(workspace.id.uuidString).json"), options: .atomic)
            }
            let index = WorkspaceIndex(workspaceIDs: workspaces.map(\.id), selectedID: selectedID)
            try encoder.encode(index).write(to: staging.appendingPathComponent("index.json"), options: .atomic)
            let manifest = BackupManifest(createdAt: Date(), workspaceCount: workspaces.count, complete: true)
            try encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try fileManager.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func backupName(prefix: String) -> String {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return "\(prefix)-\(timestamp)-\(UUID().uuidString.prefix(8))"
    }

    private func moveWorkspaceFilesToTrash(_ ids: Set<UUID>, reason: String) throws {
        let existing = ids.map(workspaceURL).filter { fileManager.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        let trash = rootURL.appendingPathComponent("Trash", isDirectory: true)
            .appendingPathComponent(backupName(prefix: reason), isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        for source in existing {
            try fileManager.moveItem(at: source, to: trash.appendingPathComponent(source.lastPathComponent))
        }
    }

    private func backupDirectoriesNewestFirst() -> [URL] {
        let directories = (try? fileManager.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return directories.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if left != right { return left > right }
            return lhs.lastPathComponent > rhs.lastPathComponent
        }
    }

    private func pruneBackups(keeping limit: Int) {
        for directory in backupDirectoriesNewestFirst().dropFirst(limit) {
            try? fileManager.removeItem(at: directory)
        }
    }

}
