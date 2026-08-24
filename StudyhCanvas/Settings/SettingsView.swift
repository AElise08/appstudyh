import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var aiSettings: AISettings
    @State private var dataMessage: String?

    var body: some View {
        Form {
            Section("IA pedagógica") {
                Picker("Provedor", selection: $aiSettings.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                Label(aiSettings.providerStatus, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if aiSettings.provider == .appleLocal {
                    Label(aiSettings.localModelStatus, systemImage: "apple.intelligence")
                        .foregroundStyle(.secondary)
                    Text("O modelo local é a opção inicial. Para desenhos selecionados, o app reconhece o texto localmente antes de pedir a orientação.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else if aiSettings.provider == .codexCLI || aiSettings.provider == .opencodeCLI {
                    TextField("Caminho do comando (opcional)", text: $aiSettings.commandPath)
                        .help("Deixe vazio para o Studyh procurar o comando instalado no Mac.")
                    if aiSettings.provider == .codexCLI {
                        TextField("Modelo do Codex (opcional)", text: $aiSettings.codexModel)
                        Text("Modelo ativo: \(aiSettings.codexModel.isEmpty ? "padrão do Codex CLI" : aiSettings.codexModel)")
                            .foregroundStyle(.secondary)
                        Label("Usa a sessão do Codex CLI, sem chave de API do Studyh.", systemImage: "terminal")
                        Text("No Terminal, execute “codex login” uma vez. O Studyh chama o Codex em modo efêmero e somente leitura; ele não altera seus arquivos.")
                    } else {
                        Label("OpenCode desabilitado", systemImage: "exclamationmark.shield")
                        Text("O CLI instalado não oferece um modo somente leitura verificável. Para impedir acesso de escrita ao computador, o Studyh não executará este backend.")
                            .foregroundStyle(.secondary)
                    }
                    Text("Se o comando estiver instalado fora dos caminhos padrão, informe o caminho completo acima.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    TextField("Endpoint (chat completions)", text: $aiSettings.endpoint)
                    SecureField("Chave secreta da API", text: $aiSettings.apiKey)
                    TextField("Nome do modelo", text: $aiSettings.model)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Como configurar")
                            .font(.headline)
                        Text("1. Crie uma chave de projeto na plataforma do provedor.\n2. Cole a chave acima.\n3. Informe o endpoint e o nome exato do modelo.\n\nPara OpenAI, o endpoint é https://api.openai.com/v1/chat/completions. A assinatura do ChatGPT não inclui créditos da API.")
                        Link("Abrir página de chaves da OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Text("As respostas seguem o contrato pedagógico do Studyh: explicar e guiar sem entregar a solução completa.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Dados") {
                HStack {
                    Button("Criar backup agora") { createBackup() }
                    Button("Exportar dados…") { exportData() }
                    Button("Restaurar backup…") { restoreBackup() }
                    Button("Abrir pasta de dados") {
                        NSWorkspace.shared.open(store.dataDirectoryURL)
                    }
                }
                Text("A restauração valida todos os workspaces e cria um backup do estado atual antes de substituir qualquer dado.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let dataMessage {
                    Text(dataMessage)
                        .font(.callout)
                        .foregroundStyle(dataMessage.hasPrefix("Erro") ? .red : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 680, height: 560)
        .padding()
    }

    private func createBackup() {
        do {
            let url = try store.createManualBackup()
            dataMessage = "Backup criado em \(url.lastPathComponent)."
        } catch {
            dataMessage = "Erro ao criar backup: \(error.localizedDescription)"
        }
    }

    private func exportData() {
        let panel = NSOpenPanel()
        panel.title = "Escolha onde exportar os dados do Studyh"
        panel.prompt = "Exportar"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do {
            let url = try store.exportSnapshot(to: parent)
            dataMessage = "Dados exportados para \(url.path)."
        } catch {
            dataMessage = "Erro ao exportar: \(error.localizedDescription)"
        }
    }

    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.title = "Escolha uma pasta de backup do Studyh"
        panel.prompt = "Restaurar"
        panel.directoryURL = store.backupsDirectoryURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            try store.restoreBackup(from: directory)
            dataMessage = "Backup restaurado. O estado anterior foi preservado em um novo backup."
        } catch {
            dataMessage = "Erro ao restaurar: \(error.localizedDescription)"
        }
    }
}

struct AIOnboardingView: View {
    @EnvironmentObject private var aiSettings: AISettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Seu primeiro estudo no Studyh", systemImage: "graduationcap.fill")
                .font(.title.bold())
            Text("O app acompanha um ciclo simples. Você mantém o controle do material, da tentativa e do que entra na revisão.")
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                onboardingStep("1", "Material", "Adicione um PDF, EPUB ou slides.", "doc.badge.plus")
                onboardingStep("2", "Tentativa", "Leia, escreva uma nota ou desenhe.", "pencil.and.outline")
                onboardingStep("3", "Orientação", "Peça uma pista ou explicação à IA.", "apple.intelligence")
                onboardingStep("4", "Revisão", "Pratique questões e flashcards.", "arrow.triangle.2.circlepath")
            }

            Divider()
            Text("IA pedagógica").font(.headline)
            Text("Escolha como o Studyh deve orientar suas tentativas. Isso pode ser alterado depois nos Ajustes.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Provedor", selection: $aiSettings.provider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .pickerStyle(.radioGroup)
            Text(aiSettings.providerStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Continuar") {
                    aiSettings.completeOnboarding()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 720)
    }

    private func onboardingStep(_ number: String, _ title: String, _ detail: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon).foregroundStyle(Color.accentColor)
                Text(number).font(.caption.bold()).foregroundStyle(.secondary)
            }
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
