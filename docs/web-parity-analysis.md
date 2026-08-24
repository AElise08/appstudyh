# Studyh Web: análise de paridade

## Diagnóstico

O protótipo anterior em HTML único era apenas um protótipo de interações, não uma versão web do
Studyh local. Ele reproduz nomes e algumas atividades, mas não os quatro
fundamentos do produto nativo:

1. o material original como superfície principal de estudo;
2. a proveniência entre material, trecho, nota, caderno e Mesa;
3. a Mesa espacial como modo primário;
4. persistência local versionada e conservadora.

Por isso, adicionar PDF e EPUB como texto extraído não resolve a diferença: o
arquivo perde layout, imagens, fórmulas, destaques, posição e navegação exata.

## Especificação observada no app local

### Estrutura principal

- Matérias ordenadas pelo prazo mais próximo.
- Modos Estudar, Mesa, Caderno e Progresso.
- Jornada Material -> Tentativa -> Orientação -> Revisão.
- Materiais PDF, EPUB, PPTX, web, Google Acadêmico e YouTube.
- Histórico de materiais e busca global entre matérias.
- Widgets Pomodoro, Hoje e Sessão.

Referências: `StudyhCanvas/ContentView.swift`,
`StudyhCanvas/Study/StudyWidgetsSidebar.swift` e
`StudyhCanvas/Study/GlobalSearchView.swift`.

### Estudar

- Leitor real do material, não uma conversão para texto simples.
- PDF paginado com seleção, busca, OCR e retorno ao trecho.
- EPUB paginado com tamanho da fonte, tema, destaques, notas e retorno ao
  trecho.
- Abas de materiais sem descarregar leitores inativos.
- Nota autoral com material, página, citação e URL de origem.
- IA com explicação, pergunta livre, flashcards e questões.
- Conversas e resultados da IA persistidos como artefatos.
- Contexto da IA limitado conforme a fonte e a posição de leitura.

Referências: `StudyhCanvas/Study/StudyDeskView.swift`,
`StudyhCanvas/Nodes/PDFNodeView.swift`, `StudyhCanvas/Nodes/WebNodeView.swift` e
`StudyhCanvas/Models/WorkspaceModels.swift`.

### Mesa

- Canvas infinito com pan e zoom.
- Nós movíveis, redimensionáveis e selecionáveis.
- Notas, materiais, desenhos, conexões e frames nomeados.
- Caneta, borracha, laço, minimapa, organização e enquadramento.
- Proveniência para abrir um cartão no material e trecho exatos.
- IA Verificar, Explicar e Próximo sobre seleção e desenho.

Referências: `StudyhCanvas/Canvas/InfiniteCanvasView.swift`,
`StudyhCanvas/Canvas/CanvasController.swift` e
`StudyhCanvas/AI/PedagogicalPrompt.swift`.

### Caderno

- Vários cadernos com conteúdo rico e texto pesquisável.
- Layouts Só caderno, Com Estudar e Com Mesa.
- Vínculo opcional com material e posição, com Abrir fonte.
- Conversão do parágrafo atual em flashcard, tarefa ou questão.

Referência: `StudyhCanvas/Study/NotebookWorkspaceView.swift`.

### Progresso

- Posição de leitura separada de cobertura realmente visitada.
- Planejamento de hoje e próxima ação prioritária.
- Retenção, prática diária, tarefas, prazos e sessões de foco.
- Lista, tabela e Kanban.
- Cobertura por frame da Mesa.
- Associação, caça-palavras e exportação HTML de revisão.

Referências: `StudyhCanvas/Study/ProgressDashboardView.swift` e
`StudyhCanvas/Study/ProgressMetrics.swift`.

### Persistência

- Documentos com versão de esquema.
- IDs estáveis e relações explícitas.
- Salvamento atômico, backups, recuperação e lixeira.
- Versão futura ou arquivo ilegível bloqueia sobrescrita destrutiva.
- Exclusão de material preserva e desvincula o trabalho derivado.
- Credenciais ficam fora dos documentos de estudo e backups.

Referências: `StudyhCanvas/Persistence/WorkspaceStore.swift`,
`StudyhCanvas/Models/WorkspaceModels.swift` e `scripts/run-e2e-tests.sh`.

## Diferenças críticas na web atual

| Área | Web atual | App local | Decisão |
| --- | --- | --- | --- |
| Persistência | Um objeto sem versão em `localStorage` | Documentos versionados, backups e recuperação | Substituir por IndexedDB e snapshots transacionais |
| Credenciais | Chave de API dentro do estado e do backup | Chave separada no Keychain | Remover credenciais do domínio e dos backups |
| Materiais | PDF/EPUB achatados em texto | Leitores reais e posição exata | Substituir o leitor |
| Notas | Cópia automática do trecho | Texto autoral com citação e origem | Substituir o fluxo de notas |
| IA | Chat efêmero | Artefatos persistidos e vinculados | Persistir e tipar resultados |
| Mesa | Ausente | Modo principal completo | Implementar como subsistema próprio |
| Caderno | HTML `contenteditable` sem origem | Documento rico, origem e layouts combinados | Substituir o editor e o modelo |
| Busca | Só matéria atual, sem navegação | Global, filtrada e com destinos tipados | Substituir o índice e as rotas |
| Revisão | Algoritmo diferente | SRS testado e IDs estáveis | Portar o algoritmo nativo |
| Mobile | Sidebar apenas desaparece | Não aplicável no Mac | Criar navegação móvel real |

## O que pode ser portado diretamente

- Modelo conceitual de Workspace, CanvasNode, StudyArtifact, StudyTask,
  StudyNotebook, FlashcardReview, ActivityEvent, StudyFrame e Connection.
- Jornada de quatro etapas.
- Regras de contexto por tipo de material.
- Contrato pedagógico Verificar, Explicar e Próximo.
- Parser e identidade estável dos flashcards.
- Algoritmo de repetição espaçada e limite global de 20 cartões novos por dia.
- Alternância de questão objetiva e resposta curta, ocultação do gabarito e
  detecção de repetição.
- Conversão de parágrafo do caderno.
- Métricas de posição, cobertura, prática e retenção.
- Prioridade da próxima ação.
- Parser de tarefas Markdown.
- Associação e caça-palavras em oito direções.
- Busca com normalização de português e destinos tipados.
- Exclusão referencialmente segura.
- Importação/exportação Obsidian e exportação HTML como regras de domínio.

Essas regras já possuem evidência em `scripts/logic-tests.swift` e devem ganhar
testes equivalentes em TypeScript.

## O que exige adaptação para o navegador

- PDF: PDF.js para renderização e extração; OCR em worker quando necessário.
- EPUB: leitor isolado, paginado e sanitizado; arquivo original separado do
  texto indexado.
- PPTX: extração de texto por slide em worker.
- Mesa: nós DOM transformados, SVG para frames/conexões e canvas sobreposto
  para tinta.
- Caderno: editor estruturado; HTML apenas como formato de saída.
- Arquivos: blobs em IndexedDB ou OPFS, nunca no `localStorage`.
- Obsidian: File System Access API onde disponível e ZIP como alternativa.
- Backup: pacote versionado com manifesto, documentos e anexos; sem segredos.
- Mobile: drawer de matérias, navegação inferior e uma superfície principal
  por vez.

## O que não pode ter paridade direta no navegador

- Apple Intelligence local.
- Codex CLI local e seu sandbox.
- Leitura direta do banco de dados do Apple Books.
- Security-scoped bookmarks do macOS.

A web deve conseguir representar e exibir os dados importados por essas
integrações, mesmo quando não puder executar a integração.

## Arquitetura proposta

### Aplicação

- React + TypeScript + Vite.
- Rotas tipadas por matéria, modo e destino.
- Componentes separados para shell, leitores, assistente, Mesa, Caderno e
  Progresso.
- Regras de domínio puras e testadas fora dos componentes.

### Dados

- Esquema compartilhável inspirado no `Workspace` Swift, com UUIDs e
  `schemaVersion`.
- IndexedDB para documentos, índices, snapshots e blobs.
- Migração explícita do protótipo `studyh-web-v2` apenas para dados válidos.
- Estado transitório de UI fora dos documentos persistidos.
- Credenciais e sessões excluídas de exportações.

### Navegação

- `/app/:workspaceId/study/:materialId`
- `/app/:workspaceId/desk`
- `/app/:workspaceId/notebook/:notebookId`
- `/app/:workspaceId/progress`
- Destinos carregam IDs e locadores de página, citação ou anotação.

### Materiais

- Arquivo original é o documento visual.
- Texto extraído é índice/contexto, nunca substituto visual.
- Posição, unidades visitadas, seleção e anotações são persistidas.

### IA

- Camada de provedor separada da UI.
- Artefatos persistidos antes/depois de cada operação.
- `AbortController` e identidade de requisição contra respostas obsoletas.
- Respostas estruturadas validadas.
- OAuth ChatGPT opcional, nunca a única forma de usar IA.

## Sequência de reconstrução

### Fase 1: fundação e Estudar

1. Criar aplicação TypeScript e esquema versionado.
2. IndexedDB, snapshots, migração e backup sem credenciais.
3. Shell desktop/mobile com matérias, modos, histórico e jornada.
4. Leitores reais de PDF, EPUB, texto e slides.
5. Notas autorais com página, citação e retorno à origem.
6. Artefatos persistidos de IA e contexto por fonte.

### Fase 2: Mesa e Caderno

1. Canvas infinito, nós, frames, conexões, tinta e laço.
2. Envio de notas e cartões com proveniência.
3. Caderno estruturado, layouts combinados e Abrir fonte.
4. Conversão de parágrafo.

### Fase 3: Progresso e recuperação

1. Portar SRS, métricas, tarefas, prazos e Pomodoro.
2. Busca global com navegação exata.
3. Associação, caça-palavras e exportação HTML.
4. Backups automáticos, importação transacional e recuperação.

### Fase 4: integrações

1. Obsidian por pasta/ZIP.
2. Web, Google Acadêmico e YouTube.
3. Pacote de intercâmbio Mac/web.
4. PWA e política offline.

## Código do protótipo que vale preservar

- Identidade visual escura como ponto de partida.
- Hierarquia compacta do bloco Hoje.
- Importação rápida de TXT/MD e texto colado.
- Conceito de leitor + assistente.
- Associação, caça-palavras e conversão de parágrafo, depois de alinhados aos
  testes do app local.
- Opção de endpoint OpenAI-compatible, com segredo fora do backup.

O restante do protótipo deve ser tratado como descartável. Em especial,
não devem continuar como fundação: estado global mutável, `localStorage`,
renderização por `innerHTML`, leitores de texto achatado, notas atuais, busca
atual, editor por `execCommand` e autenticação baseada em um booleano salvo.
