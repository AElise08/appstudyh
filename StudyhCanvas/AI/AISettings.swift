import Foundation
import Combine
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AISettings: ObservableObject {
    @Published var provider: AIProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider) }
    }
    @Published var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: Keys.endpoint) }
    }
    @Published var apiKey: String {
        didSet { scheduleAPIKeySave() }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }
    @Published var commandPath: String {
        didSet { UserDefaults.standard.set(commandPath, forKey: Keys.commandPath) }
    }
    @Published var codexModel: String {
        didSet { UserDefaults.standard.set(codexModel, forKey: Keys.codexModel) }
    }
    @Published var opencodeModel: String {
        didSet { UserDefaults.standard.set(opencodeModel, forKey: Keys.opencodeModel) }
    }
    @Published private(set) var hasCompletedAIOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedAIOnboarding, forKey: Keys.hasCompletedAIOnboarding) }
    }

    private var apiKeySaveTask: Task<Void, Never>?

    private func scheduleAPIKeySave() {
        apiKeySaveTask?.cancel()
        apiKeySaveTask = Task { [apiKey] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            KeychainAPIKey.save(apiKey)
        }
    }

    private enum Keys {
        static let endpoint = "studyh.ai.endpoint"
        static let provider = "studyh.ai.provider"
        static let legacyAPIKey = "studyh.ai.apiKey"
        static let model = "studyh.ai.model"
        static let commandPath = "studyh.ai.commandPath"
        static let codexModel = "studyh.ai.codexModel"
        static let opencodeModel = "studyh.ai.opencodeModel"
        static let hasCompletedAIOnboarding = "studyh.ai.hasCompletedOnboarding"
    }

    init() {
        let savedProvider = AIProvider(rawValue: UserDefaults.standard.string(forKey: Keys.provider) ?? "")
        provider = savedProvider ?? (Self.codexExecutableURL() == nil ? .appleLocal : .codexCLI)
        endpoint = UserDefaults.standard.string(forKey: Keys.endpoint)
            ?? "https://api.openai.com/v1/chat/completions"
        let legacyKey = UserDefaults.standard.string(forKey: Keys.legacyAPIKey) ?? ""
        apiKey = KeychainAPIKey.load() ?? legacyKey
        if !legacyKey.isEmpty {
            KeychainAPIKey.save(legacyKey)
            UserDefaults.standard.removeObject(forKey: Keys.legacyAPIKey)
        }
        model = UserDefaults.standard.string(forKey: Keys.model) ?? "gpt-4.1-mini"
        commandPath = UserDefaults.standard.string(forKey: Keys.commandPath) ?? ""
        codexModel = UserDefaults.standard.string(forKey: Keys.codexModel) ?? ""
        opencodeModel = UserDefaults.standard.string(forKey: Keys.opencodeModel) ?? ""
        hasCompletedAIOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedAIOnboarding)
    }

    var localModelStatus: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Disponível neste Mac. Funciona sem chave e sem enviar o texto para um servidor."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Ative o Apple Intelligence nos Ajustes do Sistema."
            case .unavailable(.modelNotReady):
                return "O modelo da Apple ainda está sendo preparado ou baixado."
            case .unavailable(.deviceNotEligible):
                return "Este Mac não é compatível com o modelo local da Apple."
            @unknown default:
                return "O modelo local da Apple não está disponível agora."
            }
        }
        #endif
        return "Requer macOS 26 ou posterior e Apple Intelligence."
    }

    var providerStatus: String {
        switch provider {
        case .appleLocal:
            return localModelStatus
        case .codexCLI:
            return Self.codexExecutableURL() == nil
                ? "Codex CLI não encontrado. Informe o caminho em Ajustes."
                : "Codex CLI encontrado. O login será confirmado na primeira solicitação."
        case .opencodeCLI:
            return "OpenCode está desabilitado nesta versão."
        case .openAICompatible:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Informe uma chave de API para usar este provedor."
                : "API configurada para \(endpoint)."
        }
    }

    func completeOnboarding() {
        hasCompletedAIOnboarding = true
    }

    private static func codexExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

}

enum AIProvider: String, CaseIterable, Identifiable {
    case appleLocal
    case codexCLI
    case opencodeCLI
    case openAICompatible

    var id: String { rawValue }
    var label: String {
        switch self {
        case .appleLocal: return "Apple local"
        case .codexCLI: return "Codex CLI"
        case .opencodeCLI: return "OpenCode CLI"
        case .openAICompatible: return "API externa"
        }
    }

    var commandName: String? {
        switch self {
        case .codexCLI: return "codex"
        case .opencodeCLI: return "opencode"
        default: return nil
        }
    }

}

private enum KeychainAPIKey {
    private static let service = "tech.studyh.canvas"
    private static let account = "pedagogical-api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            SecItemDelete(identity as CFDictionary)
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(trimmed.utf8)]
        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = Data(trimmed.utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

enum AIMode: String, CaseIterable, Identifiable {
    case check
    case explain
    case nextStep = "next"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .check: return "Verificar"
        case .explain: return "Explicar"
        case .nextStep: return "Próximo"
        }
    }

    var help: String {
        switch self {
        case .check: return "Alerta erros de raciocínio, unidade ou resultado. Sem gabarito."
        case .explain: return "Explica o conceito da seleção, sem resolver o exercício."
        case .nextStep: return "Só o próximo passo e uma pergunta para você tentar."
        }
    }
}
