# Studyh Canvas

Workspace de estudo nativo para Mac: canvas infinito, PDFs, pesquisas, notas e folha de cálculo no mesmo espaço. A IA (Check / Explain / Next) verifica e guia sem entregar o gabarito.

## Baixar para testar

[Baixar o Studyh Canvas 0.2.0 para macOS](releases/StudyhCanvas-0.2.0-macOS-arm64.zip)

Requisitos: Mac com Apple Silicon (M1 ou posterior) e macOS 14 ou posterior.

1. Baixe e descompacte o arquivo ZIP.
2. Mova `StudyhCanvas.app` para a pasta Aplicativos.
3. No primeiro acesso, clique no app com o botão direito e escolha **Abrir**.

O aplicativo ainda não possui assinatura de distribuição da Apple. O botão direito em **Abrir** permite confirmar manualmente que deseja executar esta versão de teste.

## Desenvolvimento

O arquivo `StudyhCanvas.xcodeproj` é necessário apenas para desenvolver e compilar o código. Ele não é necessário para executar o aplicativo baixado acima.

```bash
open StudyhCanvas.xcodeproj
```

Requer macOS 14+, Xcode 15+, Apple Silicon recomendado.

## Configurar a IA

No app: **Studyh Canvas → Ajustes**.

- URL no formato OpenAI-compatible (`…/v1/chat/completions`)
- Chave da API
- Nome do modelo

O app envia o recorte do canvas (`check` | `explain` | `next`) e o contrato pedagógico do Studyh.

Dados locais ficam em `~/Library/Application Support/Studyh/`.
