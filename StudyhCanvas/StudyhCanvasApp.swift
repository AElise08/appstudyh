import SwiftUI

@main
struct StudyhCanvasApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var aiSettings = AISettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(aiSettings)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Novo workspace") {
                    store.createWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Canvas") {
                Button("Ferramenta Mover") { postCanvasCommand("select") }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Ferramenta Lasso") { postCanvasCommand("lasso") }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Ferramenta Desenhar") { postCanvasCommand("draw") }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Ferramenta Borracha") { postCanvasCommand("erase") }
                    .keyboardShortcut("4", modifiers: [.command])
                Divider()
                Button("Ampliar") { postCanvasCommand("zoomIn") }
                    .keyboardShortcut("+", modifiers: [.command])
                Button("Reduzir") { postCanvasCommand("zoomOut") }
                    .keyboardShortcut("-", modifiers: [.command])
                Button("Zoom 100%") { postCanvasCommand("zoomReset") }
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
                Button("Apagar seleção") { postCanvasCommand("delete") }
                    .keyboardShortcut(.delete, modifiers: [.command])
            }
            CommandMenu("Estudo") {
                Button("Pesquisa global") { postCanvasCommand("globalSearch") }
                    .keyboardShortcut("f", modifiers: [.command])
                Button("Nova nota no material") { postCanvasCommand("newStudyNote") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Exportar para Obsidian…") { postCanvasCommand("exportObsidian") }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Conectar vault do Obsidian…") { postCanvasCommand("connectVault") }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Meu Progresso") { postCanvasCommand("showProgress") }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Nova tarefa…") { postCanvasCommand("newTask") }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("Material anterior") { postCanvasCommand("previousMaterial") }
                    .keyboardShortcut("[", modifiers: [.command, .option])
                Button("Próximo material") { postCanvasCommand("nextMaterial") }
                    .keyboardShortcut("]", modifiers: [.command, .option])
                Divider()
                Button("Organizar Mesa") { postCanvasCommand("organizeDesk") }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Enquadrar Mesa") { postCanvasCommand("frameDesk") }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(aiSettings)
        }
    }

    private func postCanvasCommand(_ command: String) {
        NotificationCenter.default.post(
            name: Notification.Name("StudyhCanvasCommand"),
            object: command
        )
    }
}
