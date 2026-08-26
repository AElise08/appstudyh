import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { WorkspaceStore } from "../storage/store.js";
import { createCanvasNode } from "../domain/create.js";
import type { NodeKind, Workspace } from "../domain/types.js";
import { importMaterialFile, stripFileName, isEpubFile } from "../features/files/extract.js";
import { probePdfFile } from "../features/files/pdfProbe.js";
import { probeEpubFile } from "../features/files/epubProbe.js";
import { nextNodePlacement, spreadOverlappingNodes } from "../board/placement.js";
import BoardView from "../board/BoardView.js";
import MobileHome, { useIsMobile } from "../board/MobileHome.js";
import ReaderView from "../reader/ReaderView.js";
import ReviewQueue from "../review/ReviewQueue.js";
import MatterSwitch from "./MatterSwitch.js";
import LassoBar from "../ai/LassoBar.js";
import { runTutor } from "../ai/client.js";
import { isAIConfigured, loadAISettings, saveAISettings, type AISettings } from "../ai/settings.js";
import { joinedNodeContext, nodeContextExcerpt } from "../board/nodeContext.js";
import { MAX_SELECTION_CHARS, MAX_SURROUNDING_CHARS, type AIMode } from "../ai/prompt.js";
import "./matter.css";

type Status = "loading" | "blocked" | "ready";
type Screen = "board" | "reader" | "review";

const FIRST_WORKSPACE_NAME = "Minha primeira matéria";

function sortWorkspaces(list: Workspace[]): Workspace[] {
  return [...list].sort((a, b) => {
    const ad = a.examDate ?? null;
    const bd = b.examDate ?? null;
    if (ad !== null && bd !== null && ad !== bd) return ad.localeCompare(bd);
    if (ad !== null) return -1;
    if (bd !== null) return 1;
    return 0;
  });
}

export default function App() {
  const storeRef = useRef<WorkspaceStore | null>(null);
  if (storeRef.current === null) storeRef.current = new WorkspaceStore();
  const store = storeRef.current;

  const [status, setStatus] = useState<Status>("loading");
  const [blockReason, setBlockReason] = useState<string | null>(null);
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [selectedWorkspaceId, setSelectedWorkspaceId] = useState<string | null>(null);
  const [screen, setScreen] = useState<Screen>("board");
  const [readerNodeId, setReaderNodeId] = useState<string | null>(null);
  const [matterOpen, setMatterOpen] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [tutorOpen, setTutorOpen] = useState(false);
  const [aiLoading, setAiLoading] = useState(false);
  const [aiError, setAiError] = useState<string | null>(null);
  const [aiResponse, setAiResponse] = useState<string | null>(null);
  const [aiSettings, setAiSettings] = useState<AISettings>(() => loadAISettings());
  const [settingsOpen, setSettingsOpen] = useState(false);
  const isMobile = useIsMobile();
  const [boardSelection, setBoardSelection] = useState("");

  const [modalOpen, setModalOpen] = useState(false);
  const [newMaterialTitle, setNewMaterialTitle] = useState("");
  const [materialFile, setMaterialFile] = useState<File | null>(null);
  const [extracting, setExtracting] = useState(false);
  const [extractError, setExtractError] = useState<string | null>(null);
  const [importing, setImporting] = useState(false);
  const materialInputRef = useRef<HTMLInputElement | null>(null);
  const importInputRef = useRef<HTMLInputElement | null>(null);
  const loadStartedRef = useRef(false);
  const attachmentCacheRef = useRef(new Map<string, Blob>());
  const [attachmentVersion, setAttachmentVersion] = useState(0);

  useEffect(() => {
    if (loadStartedRef.current) return;
    loadStartedRef.current = true;
    void (async () => {
      try {
        const result = await store.loadAll();
        if (result.blocked) {
          setBlockReason(result.blockReason);
          setStatus("blocked");
          return;
        }
        const repaired: Workspace[] = [];
        for (const workspace of result.workspaces) {
          const spread = spreadOverlappingNodes(workspace.nodes);
          if (!spread.changed) {
            repaired.push(workspace);
            continue;
          }
          const next = {
            ...workspace,
            nodes: spread.nodes,
            updatedAt: new Date().toISOString(),
          };
          await store.writeNow(next);
          repaired.push(next);
        }

        let list = sortWorkspaces(repaired);
        if (list.length === 0) {
          const created = await store.createWorkspace(FIRST_WORKSPACE_NAME);
          list = [created];
        }
        setWorkspaces(list);
        const indexSelected = result.index?.selectedID ?? null;
        setSelectedWorkspaceId(
          indexSelected !== null && list.some((w) => w.id === indexSelected)
            ? indexSelected
            : (list[0]?.id ?? null),
        );
        setStatus("ready");
      } catch (err) {
        setBlockReason(err instanceof Error ? err.message : String(err));
        setStatus("blocked");
      }
    })();
  }, [store]);

  useEffect(() => {
    const onUnload = () => {
      void store.flush().catch(() => undefined);
    };
    window.addEventListener("pagehide", onUnload);
    return () => window.removeEventListener("pagehide", onUnload);
  }, [store]);

  const selected = useMemo(
    () => workspaces.find((w) => w.id === selectedWorkspaceId) ?? null,
    [workspaces, selectedWorkspaceId],
  );

  const readerNode = useMemo(
    () => selected?.nodes.find((node) => node.id === readerNodeId) ?? null,
    [readerNodeId, selected],
  );

  const mutateWorkspace = useCallback(
    (id: string, fn: (ws: Workspace) => Workspace) => {
      setWorkspaces((prev) => {
        const target = prev.find((w) => w.id === id);
        if (target === undefined) return prev;
        const next = fn(target);
        store.queue(next);
        return prev.map((w) => (w.id === id ? next : w));
      });
    },
    [store],
  );

  const handleChange = useCallback(
    (next: Workspace) => {
      mutateWorkspace(next.id, () => next);
    },
    [mutateWorkspace],
  );

  const openAddMaterial = useCallback(() => {
    setNewMaterialTitle("");
    setMaterialFile(null);
    setExtractError(null);
    setModalOpen(true);
  }, []);

  const handleAddNote = useCallback(() => {
    if (selected === null) return;
    const frame = nextNodePlacement(selected.nodes, "note");
    const node = createCanvasNode({ kind: "note", title: "Nota", frame });
    mutateWorkspace(selected.id, (ws) => ({
      ...ws,
      nodes: [...ws.nodes, node],
      updatedAt: new Date().toISOString(),
    }));
    setSelectedIds(new Set([node.id]));
  }, [mutateWorkspace, selected]);

  const handleLoadAttachment = useCallback(
    async (id: string) => {
      const cached = attachmentCacheRef.current.get(id);
      if (cached !== undefined) return cached;
      const blob = await store.getAttachment(id);
      if (blob !== null) attachmentCacheRef.current.set(id, blob);
      return blob;
    },
    [store],
  );

  const getAttachmentBlob = useCallback(
    (id: string) => attachmentCacheRef.current.get(id) ?? null,
    // attachmentVersion força re-render após import
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [attachmentVersion],
  );

  const handleCreateWorkspace = useCallback(async () => {
    try {
      const created = await store.createWorkspace("Nova matéria");
      setWorkspaces((prev) => sortWorkspaces([...prev, created]));
      setSelectedWorkspaceId(created.id);
      setMatterOpen(false);
    } catch (err) {
      window.alert(err instanceof Error ? err.message : String(err));
    }
  }, [store]);

  const handleDeleteWorkspace = useCallback(
    async (target: Workspace) => {
      const confirmed = window.confirm(`Excluir "${target.name}"? Esta ação não pode ser desfeita.`);
      if (!confirmed) return;
      try {
        await store.deleteWorkspace(target.id);
        const remaining = workspaces.filter((w) => w.id !== target.id);
        setWorkspaces(remaining);
        setSelectedWorkspaceId((current) =>
          current === target.id ? (remaining[0]?.id ?? null) : current,
        );
      } catch (err) {
        window.alert(err instanceof Error ? err.message : String(err));
      }
    },
    [store, workspaces],
  );

  const handleAddMaterial = useCallback(async () => {
    if (selected === null) return;
    const file = materialFile;
    const title = newMaterialTitle.trim();

    if (file !== null) {
      setExtracting(true);
      setExtractError(null);
      try {
        const lower = file.name.toLowerCase();
        let kind: NodeKind;
        let displayTitle = title.length > 0 ? title : stripFileName(file.name);
        let noteBody = "";
        let pdfText: string | null = null;
        let pdfPageCount: number | null = null;
        let epubText: string | null = null;
        let epubPageCount: number | null = null;
        let epubCoverDataUrl: string | null = null;

        if (lower.endsWith(".pdf") || file.type.toLowerCase() === "application/pdf") {
          kind = "pdf";
          try {
            const extracted = await importMaterialFile(file);
            pdfText = extracted.pages.join("\n---\n");
            pdfPageCount = extracted.pageCount;
            if (title.length === 0) displayTitle = extracted.title;
          } catch {
            const probe = await probePdfFile(file);
            pdfPageCount = probe.pageCount;
          }
        } else if (isEpubFile(file)) {
          kind = "epub";
          try {
            const extracted = await importMaterialFile(file);
            epubText = extracted.pages.join("\n---\n");
            epubPageCount = extracted.pageCount;
            if (extracted.kind === "epub") epubCoverDataUrl = extracted.coverDataUrl ?? null;
            if (title.length === 0) displayTitle = extracted.title;
          } catch {
            const probe = await probeEpubFile(file);
            epubPageCount = probe.pageCount;
            if (title.length === 0) displayTitle = probe.title;
          }
        } else {
          const extracted = await importMaterialFile(file);
          kind = extracted.kind;
          const joined = extracted.pages.join("\n---\n");
          if (title.length === 0) displayTitle = extracted.title;
          if (kind === "note") noteBody = joined;
          if (kind === "pdf") {
            pdfText = joined;
            pdfPageCount = extracted.pageCount;
          }
          if (kind === "epub") {
            epubText = joined;
            epubPageCount = extracted.pageCount;
            if (extracted.kind === "epub") epubCoverDataUrl = extracted.coverDataUrl ?? null;
          }
        }

        const frame = nextNodePlacement(selected.nodes, kind);
        const node = createCanvasNode({
          kind,
          title: displayTitle,
          frame,
          noteBody,
          pdfText,
          pdfPageCount,
          epubText,
          epubPageCount,
          epubCoverDataUrl,
        });

        await store.saveAttachment(node.id, file);
        attachmentCacheRef.current.set(node.id, file);
        setAttachmentVersion((v) => v + 1);

        mutateWorkspace(selected.id, (ws) => ({
          ...ws,
          nodes: [...ws.nodes, node],
          updatedAt: new Date().toISOString(),
        }));

        setModalOpen(false);
        setNewMaterialTitle("");
        setMaterialFile(null);
        setSelectedIds(new Set([node.id]));
      } catch (err) {
        setExtractError(err instanceof Error ? err.message : String(err));
      } finally {
        setExtracting(false);
      }
      return;
    }

    const frame = nextNodePlacement(selected.nodes, "note");
    const node = createCanvasNode({ kind: "note", title: title || "Nota", frame });
    mutateWorkspace(selected.id, (ws) => ({
      ...ws,
      nodes: [...ws.nodes, node],
      updatedAt: new Date().toISOString(),
    }));
    setModalOpen(false);
    setNewMaterialTitle("");
    setSelectedIds(new Set([node.id]));
  }, [materialFile, mutateWorkspace, newMaterialTitle, selected, store]);

  const handleDeleteNodes = useCallback(
    (nodeIds: string[]) => {
      if (selected === null || nodeIds.length === 0) return;
      const ids = new Set(nodeIds);
      for (const id of ids) {
        attachmentCacheRef.current.delete(id);
        void store.deleteAttachment(id).catch(() => undefined);
      }
      setAttachmentVersion((v) => v + 1);
      mutateWorkspace(selected.id, (ws) => ({
        ...ws,
        nodes: ws.nodes.filter((node) => !ids.has(node.id)),
        updatedAt: new Date().toISOString(),
      }));
      setSelectedIds(new Set());
    },
    [mutateWorkspace, selected, store],
  );

  const handleExport = useCallback(() => {
    try {
      const pkg = store.exportPackage(workspaces);
      const blob = new Blob([JSON.stringify(pkg, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = "studyh-backup.json";
      anchor.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      window.alert(err instanceof Error ? err.message : String(err));
    }
  }, [store, workspaces]);

  const handleImportFile = useCallback(
    async (file: File) => {
      setImporting(true);
      try {
        const pkg: unknown = JSON.parse(await file.text());
        const count = await store.importPackage(pkg);
        const refreshed = await store.loadAll();
        if (refreshed.blocked) {
          setBlockReason(refreshed.blockReason);
          setStatus("blocked");
          return;
        }
        const list = sortWorkspaces(refreshed.workspaces);
        setWorkspaces(list);
        setSelectedWorkspaceId((prevId) =>
          prevId !== null && list.some((w) => w.id === prevId) ? prevId : (list[0]?.id ?? null),
        );
        window.alert(`Importação concluída: ${count} matéria(s).`);
      } catch (err) {
        window.alert(`Falha ao importar backup: ${err instanceof Error ? err.message : String(err)}`);
      } finally {
        setImporting(false);
      }
    },
    [store],
  );

  const handleCreateCardFromQuote = useCallback(
    (quote: string, pageIndex: number, body: string) => {
      if (selected === null || readerNode === null) return;
      const node = createCanvasNode({
        kind: "note",
        title: "Trecho",
        noteBody: quote.length > 0 ? `> ${quote}\n\n${body}` : body,
        x: readerNode.frame.x + readerNode.frame.width + 24,
        y: readerNode.frame.y,
        sourcePageIndex: pageIndex,
        sourceQuote: quote.length > 0 ? quote : null,
      });
      mutateWorkspace(selected.id, (ws) => ({
        ...ws,
        nodes: [...ws.nodes, node],
        updatedAt: new Date().toISOString(),
      }));
      setSelectedIds(new Set([node.id]));
    },
    [mutateWorkspace, readerNode, selected],
  );

  const tutorSelectionText = useMemo(() => {
    const fromBoard = boardSelection.trim();
    if (fromBoard.length > 0) return fromBoard.slice(0, MAX_SELECTION_CHARS);
    if (selected === null || selectedIds.size === 0) return "";
    const nodes = selected.nodes.filter((node) => selectedIds.has(node.id));
    if (nodes.length === 1) return nodeContextExcerpt(nodes[0]!).slice(0, MAX_SELECTION_CHARS);
    return joinedNodeContext(nodes, MAX_SELECTION_CHARS);
  }, [boardSelection, selected, selectedIds]);

  const tutorSurrounding = useMemo(() => {
    if (selected === null) return "";
    const others = selected.nodes.filter((node) => !selectedIds.has(node.id));
    return joinedNodeContext(others, MAX_SURROUNDING_CHARS);
  }, [selected, selectedIds]);

  const runTutorMode = useCallback(
    async (mode: AIMode) => {
      if (!isAIConfigured(aiSettings)) {
        setAiError("Configure endpoint e chave de API em Ajustes.");
        setSettingsOpen(true);
        return;
      }
      setAiLoading(true);
      setAiError(null);
      setAiResponse(null);
      try {
        const text = await runTutor(aiSettings, mode, tutorSelectionText, tutorSurrounding);
        setAiResponse(text);
      } catch (err) {
        setAiError(err instanceof Error ? err.message : String(err));
      } finally {
        setAiLoading(false);
      }
    },
    [aiSettings, tutorSelectionText, tutorSurrounding],
  );

  useEffect(() => {
    const onSelectionChange = () => {
      setBoardSelection(window.getSelection()?.toString() ?? "");
    };
    document.addEventListener("selectionchange", onSelectionChange);
    return () => document.removeEventListener("selectionchange", onSelectionChange);
  }, []);

  if (status === "loading") {
    return (
      <div className="shell">
        <div className="shell__center">Carregando…</div>
      </div>
    );
  }

  if (status === "blocked") {
    return (
      <div className="shell">
        <div className="shell__banner">
          <strong>Armazenamento bloqueado.</strong>
          <p>{blockReason}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="shell">
      <header className="shell__chrome">
        <button type="button" className="shell__btn" onClick={() => setMatterOpen(true)}>
          {selected?.name ?? "Matérias"}
        </button>
        <div className="shell__spacer" />
        <button type="button" className="shell__btn" onClick={() => setSettingsOpen(true)}>
          Ajustes
        </button>
      </header>

      <main className="shell__main">
        {selected === null ? (
          <div className="shell__center">Selecione ou crie uma matéria.</div>
        ) : screen === "review" ? (
          <ReviewQueue
            workspace={selected}
            onChange={handleChange}
            onClose={() => setScreen("board")}
          />
        ) : screen === "reader" && readerNode !== null ? (
          <ReaderView
            workspace={selected}
            node={readerNode}
            onClose={() => {
              setScreen("board");
              setReaderNodeId(null);
            }}
            onChange={handleChange}
            onLoadAttachment={handleLoadAttachment}
            onCreateCardFromQuote={handleCreateCardFromQuote}
          />
        ) : isMobile ? (
          <MobileHome
            workspace={selected}
            onChange={handleChange}
            onOpenReader={(nodeId) => {
              setReaderNodeId(nodeId);
              setScreen("reader");
            }}
            onAddNote={handleAddNote}
            onAddMaterial={openAddMaterial}
            onLoadAttachment={handleLoadAttachment}
            getAttachmentBlob={getAttachmentBlob}
          />
        ) : (
          <BoardView
            workspace={selected}
            onChange={handleChange}
            selectedIds={selectedIds}
            onSelectionChange={setSelectedIds}
            onOpenReader={(nodeId) => {
              setReaderNodeId(nodeId);
              setScreen("reader");
            }}
            onAddMaterial={openAddMaterial}
            onLoadAttachment={handleLoadAttachment}
            getAttachmentBlob={getAttachmentBlob}
            onDeleteNodes={handleDeleteNodes}
          />
        )}
      </main>

      <nav className="shell__dock" aria-label="Navegação">
        <button
          type="button"
          className={`shell__dock-btn${screen === "board" ? " is-active" : ""}`}
          onClick={() => {
            setScreen("board");
            setReaderNodeId(null);
          }}
        >
          Lousa
        </button>
        <button
          type="button"
          className={`shell__dock-btn${screen === "review" ? " is-active" : ""}`}
          onClick={() => setScreen("review")}
        >
          Revisar
        </button>
      </nav>

      {tutorSelectionText.length > 0 && !tutorOpen && screen !== "reader" && (
        <button
          type="button"
          className="shell__tutor-fab"
          onClick={() => {
            setTutorOpen(true);
            setAiError(null);
            setAiResponse(null);
          }}
        >
          Tutor
        </button>
      )}

      <MatterSwitch
        open={matterOpen}
        workspaces={workspaces}
        selectedId={selectedWorkspaceId}
        onClose={() => setMatterOpen(false)}
        onSelect={setSelectedWorkspaceId}
        onCreate={() => void handleCreateWorkspace()}
        onDelete={(ws) => void handleDeleteWorkspace(ws)}
        onExport={handleExport}
        onImport={() => importInputRef.current?.click()}
        importing={importing}
      />

      {tutorOpen && (
        <LassoBar
          selectionText={tutorSelectionText}
          loading={aiLoading}
          error={aiError}
          response={aiResponse}
          onRun={(mode) => void runTutorMode(mode)}
          onClose={() => setTutorOpen(false)}
        />
      )}

      {modalOpen && (
        <>
          <div className="shell__overlay" onClick={() => setModalOpen(false)} />
          <div className="shell__modal" role="dialog" aria-label="Adicionar material">
            <h2>Adicionar à lousa</h2>
            <label className="shell__field">
              Título
              <input
                value={newMaterialTitle}
                onChange={(event) => setNewMaterialTitle(event.target.value)}
                placeholder="Opcional"
              />
            </label>
            <div className="shell__drop">
              <button type="button" onClick={() => materialInputRef.current?.click()}>
                {materialFile === null ? "Escolher PDF, EPUB ou texto" : materialFile.name}
              </button>
              <input
                ref={materialInputRef}
                type="file"
                accept=".pdf,.epub,.txt,.md,.markdown,application/pdf,application/epub+zip"
                hidden
                onChange={(event) => {
                  const file = event.target.files?.[0];
                  event.target.value = "";
                  if (file !== undefined) {
                    setMaterialFile(file);
                    setExtractError(null);
                  }
                }}
              />
            </div>
            {extractError !== null && <p className="shell__error">{extractError}</p>}
            <div className="shell__modal-actions">
              <button type="button" onClick={() => setModalOpen(false)}>
                Cancelar
              </button>
              <button
                type="button"
                className="shell__primary"
                disabled={extracting}
                onClick={() => void handleAddMaterial()}
              >
                {extracting ? "Importando…" : "Adicionar"}
              </button>
            </div>
          </div>
        </>
      )}

      {settingsOpen && (
        <>
          <div className="shell__overlay" onClick={() => setSettingsOpen(false)} />
          <div className="shell__modal" role="dialog" aria-label="Ajustes de IA">
            <h2>Tutor (IA)</h2>
            <p className="shell__hint">
              A chave fica só neste navegador. Em produção, use o proxy Cloudflare.
            </p>
            <label className="shell__field">
              Endpoint
              <input
                value={aiSettings.endpoint}
                onChange={(event) => setAiSettings({ ...aiSettings, endpoint: event.target.value })}
              />
            </label>
            <label className="shell__field">
              Modelo
              <input
                value={aiSettings.model}
                onChange={(event) => setAiSettings({ ...aiSettings, model: event.target.value })}
              />
            </label>
            <label className="shell__field">
              API key
              <input
                type="password"
                value={aiSettings.apiKey}
                onChange={(event) => setAiSettings({ ...aiSettings, apiKey: event.target.value })}
                placeholder="sk-…"
              />
            </label>
            <div className="shell__modal-actions">
              <button type="button" onClick={() => setSettingsOpen(false)}>
                Cancelar
              </button>
              <button
                type="button"
                className="shell__primary"
                onClick={() => {
                  saveAISettings(aiSettings);
                  setSettingsOpen(false);
                }}
              >
                Salvar
              </button>
            </div>
          </div>
        </>
      )}

      <input
        ref={importInputRef}
        type="file"
        accept="application/json,.json"
        hidden
        onChange={(event) => {
          const file = event.target.files?.[0];
          event.target.value = "";
          if (file !== undefined) void handleImportFile(file);
        }}
      />
    </div>
  );
}
