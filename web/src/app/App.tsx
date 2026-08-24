import { Fragment, useCallback, useEffect, useMemo, useRef, useState, type ReactElement } from "react";
import { WorkspaceStore } from "../storage/store.js";
import { createCanvasNode } from "../domain/create.js";
import type { Workspace } from "../domain/types.js";
import { countPracticedToday } from "../features/estudar/study.js";
import { importMaterialFile } from "../features/files/extract.js";
import EstudarView from "../features/estudar/EstudarView.js";
import MesaView from "../features/mesa/MesaView.js";
import CadernoView from "../features/caderno/CadernoView.js";
import ProgressoView from "../features/progresso/ProgressoView.js";

type Mode = "estudar" | "mesa" | "caderno" | "progresso";
type Status = "loading" | "blocked" | "ready";

const MODES: readonly { id: Mode; label: string; icon: () => ReactElement }[] = [
  { id: "estudar", label: "Estudar", icon: IconBook },
  { id: "mesa", label: "Mesa", icon: IconGrid },
  { id: "caderno", label: "Caderno", icon: IconPencil },
  { id: "progresso", label: "Progresso", icon: IconChart },
];

const FIRST_WORKSPACE_NAME = "Minha primeira matéria";

interface JourneyStep {
  id: string;
  label: string;
  done: boolean;
  target: Mode;
}

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

function examCountdownLabel(examDate: string | null | undefined, now: Date): string | null {
  if (examDate === null || examDate === undefined) return null;
  const target = new Date(examDate).getTime();
  if (Number.isNaN(target)) return null;
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const days = Math.ceil((target - startOfToday) / 86_400_000);
  if (days > 1) return `Prova em ${days}d`;
  if (days === 1) return "Prova amanhã";
  if (days === 0) return "Prova hoje";
  return null;
}

export default function App() {
  const storeRef = useRef<WorkspaceStore | null>(null);
  if (storeRef.current === null) storeRef.current = new WorkspaceStore();
  const store = storeRef.current;

  const [status, setStatus] = useState<Status>("loading");
  const [blockReason, setBlockReason] = useState<string | null>(null);
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [selectedWorkspaceId, setSelectedWorkspaceId] = useState<string | null>(null);
  const [mode, setMode] = useState<Mode>("estudar");
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [newMaterialTitle, setNewMaterialTitle] = useState("");
  const [nameDraft, setNameDraft] = useState("");
  const [editingName, setEditingName] = useState(false);
  const loadStartedRef = useRef(false);

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
        let list = sortWorkspaces(result.workspaces);
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

  const sorted = useMemo(() => sortWorkspaces(workspaces), [workspaces]);
  const selected = useMemo(
    () => workspaces.find((w) => w.id === selectedWorkspaceId) ?? null,
    [workspaces, selectedWorkspaceId],
  );

  useEffect(() => {
    if (!editingName) setNameDraft(selected?.name ?? "");
  }, [selected?.name, editingName]);

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

  const journey: JourneyStep[] = useMemo(() => {
    if (selected === null) return [];
    const artifacts = selected.studyArtifacts ?? [];
    const reviews = selected.flashcardReviews ?? [];
    const now = new Date();
    return [
      {
        id: "material",
        label: "Material",
        done: selected.nodes.length > 0,
        target: "estudar",
      },
      {
        id: "tentativa",
        label: "Tentativa",
        done:
          artifacts.some((a) => a.kind === "note") ||
          selected.nodes.some((n) => (n.visitedUnitIndices ?? []).length > 0),
        target: "estudar",
      },
      {
        id: "orientacao",
        label: "Orientação",
        done: artifacts.some(
          (a) => a.kind === "flashcards" || a.kind === "question" || a.kind === "assistantMessage",
        ),
        target: "estudar",
      },
      {
        id: "revisao",
        label: "Revisão",
        done:
          reviews.length > 0 ||
          countPracticedToday(reviews, now) > 0,
        target: "progresso",
      },
    ];
  }, [selected]);

  const handleCreateWorkspace = useCallback(async () => {
    try {
      const created = await store.createWorkspace("Nova matéria");
      setWorkspaces((prev) => sortWorkspaces([...prev, created]));
      setSelectedWorkspaceId(created.id);
      setMode("estudar");
      setDrawerOpen(false);
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

  const commitName = useCallback(() => {
    setEditingName(false);
    if (selected === null) return;
    const trimmed = nameDraft.trim();
    if (trimmed.length === 0 || trimmed === selected.name) {
      setNameDraft(selected.name);
      return;
    }
    mutateWorkspace(selected.id, (ws) => ({
      ...ws,
      name: trimmed,
      updatedAt: new Date().toISOString(),
    }));
  }, [mutateWorkspace, nameDraft, selected]);

  const openAddMaterial = useCallback(() => {
    setNewMaterialTitle("");
    setMaterialFile(null);
    setExtractError(null);
    setModalOpen(true);
  }, []);

  const [materialFile, setMaterialFile] = useState<File | null>(null);
  const [extracting, setExtracting] = useState(false);
  const [extractError, setExtractError] = useState<string | null>(null);
  const [dropzoneOver, setDropzoneOver] = useState(false);
  const materialInputRef = useRef<HTMLInputElement | null>(null);

  const acceptMaterialFile = useCallback((file: File | undefined | null) => {
    if (file === undefined || file === null) return;
    setMaterialFile(file);
    setExtractError(null);
  }, []);

  const handleSaveAttachment = useCallback(
    (id: string, blob: Blob) => {
      void store.saveAttachment(id, blob).catch(() => undefined);
    },
    [store],
  );

  const handleLoadAttachment = useCallback(
    (id: string) => store.getAttachment(id),
    [store],
  );

  const handleAddMaterial = useCallback(async () => {
    if (selected === null) return;
    const file = materialFile;
    const title = newMaterialTitle.trim();

    if (file !== null) {
      setExtracting(true);
      setExtractError(null);
      try {
        const result = await importMaterialFile(file);
        const joined = result.pages.join("\n---\n");
        const node = createCanvasNode({
          kind: result.kind,
          title: title.length > 0 ? title : result.title,
          noteBody: result.kind === "note" ? joined : "",
          pdfText: result.kind === "pdf" ? joined : null,
          pdfPageCount: result.kind === "pdf" ? result.pageCount : null,
          epubText: result.kind === "epub" ? joined : null,
          epubPageCount: result.kind === "epub" ? result.pageCount : null,
        });
        mutateWorkspace(selected.id, (ws) => ({
          ...ws,
          nodes: [...ws.nodes, node],
          updatedAt: new Date().toISOString(),
        }));
        handleSaveAttachment(node.id, file);
        setModalOpen(false);
        setNewMaterialTitle("");
        setMaterialFile(null);
      } catch (err) {
        setExtractError(err instanceof Error ? err.message : String(err));
      } finally {
        setExtracting(false);
      }
      return;
    }

    const node = createCanvasNode({ kind: "note", title: title || "Nota" });
    mutateWorkspace(selected.id, (ws) => ({
      ...ws,
      nodes: [...ws.nodes, node],
      updatedAt: new Date().toISOString(),
    }));
    setModalOpen(false);
    setNewMaterialTitle("");
  }, [handleSaveAttachment, materialFile, mutateWorkspace, newMaterialTitle, selected]);

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

  const importInputRef = useRef<HTMLInputElement | null>(null);
  const [importing, setImporting] = useState(false);

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
        window.alert(
          `Falha ao importar backup: ${err instanceof Error ? err.message : String(err)}`,
        );
      } finally {
        setImporting(false);
      }
    },
    [store],
  );

  if (status === "loading") {
    return (
      <div className="app">
        <div className="spinner-wrap">Carregando…</div>
      </div>
    );
  }

  if (status === "blocked") {
    return (
      <div className="app">
        <div className="banner">
          <strong>Armazenamento bloqueado.</strong> Nenhuma alteração será feita nos seus dados.
          {"\n"}
          {blockReason}
        </div>
      </div>
    );
  }

  const now = new Date();

  const sidebar = (
    <>
      <div className="sidebar__brand">Studyh</div>
      <div className="sidebar__list-label">Matérias</div>
      <ul className="sidebar__list">
        {sorted.map((ws) => (
          <li key={ws.id}>
            <div className={`sidebar__item${ws.id === selectedWorkspaceId ? " is-selected" : ""}`}>
              <button
                type="button"
                className="sidebar__item-btn"
                onClick={() => {
                  setSelectedWorkspaceId(ws.id);
                  setEditingName(false);
                  setMode("estudar");
                  setDrawerOpen(false);
                }}
              >
                <span className="sidebar__check" aria-hidden="true">
                  <IconCheck />
                </span>
                <span className="sidebar__name">{ws.name}</span>
                <span className="sidebar__countdown">{examCountdownLabel(ws.examDate, now)}</span>
              </button>
              <button
                type="button"
                className="sidebar__delete"
                aria-label={`Excluir ${ws.name}`}
                title={`Excluir ${ws.name}`}
                onClick={() => void handleDeleteWorkspace(ws)}
              >
                <IconClose />
              </button>
            </div>
          </li>
        ))}
      </ul>
      <button type="button" className="btn btn--primary btn--full" onClick={() => void handleCreateWorkspace()}>
        <IconPlus />
        Nova matéria
      </button>
      <div className="sidebar__footer">
        <button type="button" className="btn" onClick={handleExport}>
          Exportar
        </button>
        <button
          type="button"
          className="btn"
          disabled={importing}
          onClick={() => importInputRef.current?.click()}
        >
          Importar
        </button>
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
    </>
  );

  return (
    <div className="app">
      {drawerOpen && (
        <div
          className="drawer-backdrop"
          onClick={() => setDrawerOpen(false)}
          aria-hidden="true"
        />
      )}
      <aside className={`sidebar${drawerOpen ? " is-open" : ""}`}>{sidebar}</aside>

      <div className="main">
        <header className="topbar">
          <button
            type="button"
            className="btn btn--ghost hamburger"
            aria-label="Abrir lista de matérias"
            onClick={() => setDrawerOpen(true)}
          >
            <IconMenu />
          </button>
          {editingName && selected !== null ? (
            <input
              className="workspace-name"
              value={nameDraft}
              autoFocus
              aria-label="Nome da matéria"
              onChange={(event) => setNameDraft(event.target.value)}
              onBlur={commitName}
              onKeyDown={(event) => {
                if (event.key === "Enter") commitName();
                if (event.key === "Escape") {
                  setEditingName(false);
                  setNameDraft(selected.name);
                }
              }}
            />
          ) : (
            <input
              className="workspace-name"
              value={nameDraft}
              readOnly={!selected}
              placeholder={selected === null ? "" : undefined}
              aria-label="Nome da matéria"
              onChange={(event) => {
                setEditingName(true);
                setNameDraft(event.target.value);
              }}
            />
          )}
          <nav className="tabs" aria-label="Modos">
            {MODES.map((m) => (
              <button
                key={m.id}
                type="button"
                className={`tab${mode === m.id ? " is-active" : ""}`}
                onClick={() => setMode(m.id)}
              >
                <m.icon />
                <span>{m.label}</span>
              </button>
            ))}
          </nav>
          <div className="topbar__spacer" aria-hidden="true" />
        </header>

        {journey.length > 0 && (
          <nav className="journey" aria-label="Trilha de estudo">
            {journey.map((step, index) => (
              <Fragment key={step.id}>
                {index > 0 && <span className="journey__connector" aria-hidden="true" />}
                <button
                  type="button"
                  className={`journey__step${step.done ? " is-done" : " is-pending"}`}
                  aria-current={mode === step.target ? "step" : undefined}
                  onClick={() => setMode(step.target)}
                >
                  <span className="journey__dot" aria-hidden="true">
                    {step.done ? <IconCheck /> : index + 1}
                  </span>
                  <span className="journey__label">{step.label}</span>
                </button>
              </Fragment>
            ))}
          </nav>
        )}

        <section className="content">
          {selected === null ? (
            <div className="empty-state">Selecione ou crie uma matéria para começar.</div>
          ) : mode === "estudar" ? (
            <EstudarView
              workspace={selected}
              onChange={handleChange}
              onAddMaterial={openAddMaterial}
              onSaveAttachment={handleSaveAttachment}
              onLoadAttachment={handleLoadAttachment}
            />
          ) : mode === "mesa" ? (
            <MesaView workspace={selected} onChange={handleChange} />
          ) : mode === "caderno" ? (
            <CadernoView workspace={selected} onChange={handleChange} />
          ) : (
            <ProgressoView workspace={selected} onChange={handleChange} onNavigate={() => setMode("estudar")} />
          )}
        </section>

        <nav className="bottombar" aria-label="Modos">
          {MODES.map((m) => (
            <button
              key={m.id}
              type="button"
              className={`tab${mode === m.id ? " is-active" : ""}`}
              aria-label={m.label}
              onClick={() => setMode(m.id)}
            >
              <m.icon />
            </button>
          ))}
        </nav>
      </div>

      {modalOpen && selected !== null && (
        <div
          className="modal-backdrop"
          role="presentation"
          onClick={(event) => {
            if (event.target === event.currentTarget) setModalOpen(false);
          }}
        >
          <form
            className="modal"
            onSubmit={(event) => {
              event.preventDefault();
              void handleAddMaterial();
            }}
          >
            <h2>Novo material</h2>
            <input
              autoFocus
              value={newMaterialTitle}
              placeholder="Título do material"
              aria-label="Título do material"
              onChange={(event) => setNewMaterialTitle(event.target.value)}
            />
            <div
              className={`files-dropzone${dropzoneOver ? " is-over" : ""}`}
              role="button"
              tabIndex={0}
              onClick={() => materialInputRef.current?.click()}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === " ") materialInputRef.current?.click();
              }}
              onDragOver={(event) => {
                event.preventDefault();
                setDropzoneOver(true);
              }}
              onDragLeave={() => setDropzoneOver(false)}
              onDrop={(event) => {
                event.preventDefault();
                setDropzoneOver(false);
                acceptMaterialFile(event.dataTransfer.files?.[0] ?? null);
              }}
            >
              {materialFile === null ? (
                <>
                  <strong>Arraste um arquivo ou clique para escolher</strong>
                  <small>PDF, EPUB, TXT ou MD · o texto fica disponível para estudo offline</small>
                </>
              ) : (
                <>
                  <strong>{materialFile.name}</strong>
                  <small>Arquivo pronto. Ajuste o título se quiser e clique em Importar.</small>
                </>
              )}
            </div>
            <input
              ref={materialInputRef}
              type="file"
              accept=".pdf,.epub,.txt,.md,application/pdf,application/epub+zip,text/plain,text/markdown"
              hidden
              onChange={(event) => {
                const file = event.target.files?.[0];
                event.target.value = "";
                acceptMaterialFile(file);
              }}
            />
            {extractError !== null && <p className="files-error">{extractError}</p>}
            <div className="modal__actions">
              <button type="button" className="btn" onClick={() => setModalOpen(false)}>
                Cancelar
              </button>
              <button type="submit" className="btn btn--primary" disabled={extracting}>
                {extracting ? "Extraindo…" : materialFile !== null ? "Importar" : "Criar nota"}
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}

// ---------- Icons ----------

const ICON_PROPS = {
  width: 18,
  height: 18,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round",
  strokeLinejoin: "round",
  "aria-hidden": true,
} as const;

function IconBook() {
  return (
    <svg {...ICON_PROPS}>
      <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z" />
      <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z" />
    </svg>
  );
}

function IconGrid() {
  return (
    <svg {...ICON_PROPS}>
      <rect x="3" y="3" width="7" height="7" rx="1" />
      <rect x="14" y="3" width="7" height="7" rx="1" />
      <rect x="14" y="14" width="7" height="7" rx="1" />
      <rect x="3" y="14" width="7" height="7" rx="1" />
    </svg>
  );
}

function IconPencil() {
  return (
    <svg {...ICON_PROPS}>
      <path d="M12 20h9" />
      <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z" />
    </svg>
  );
}

function IconChart() {
  return (
    <svg {...ICON_PROPS}>
      <path d="M18 20V10" />
      <path d="M12 20V4" />
      <path d="M6 20v-6" />
    </svg>
  );
}

function IconPlus() {
  return (
    <svg {...ICON_PROPS}>
      <path d="M12 5v14" />
      <path d="M5 12h14" />
    </svg>
  );
}

function IconMenu() {
  return (
    <svg {...ICON_PROPS}>
      <path d="M3 6h18" />
      <path d="M3 12h18" />
      <path d="M3 18h18" />
    </svg>
  );
}

function IconCheck() {
  return (
    <svg width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden={true}>
      <path d="M20 6 9 17l-5-5" />
    </svg>
  );
}

function IconClose() {
  return (
    <svg width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden={true}>
      <path d="M18 6 6 18" />
      <path d="m6 6 12 12" />
    </svg>
  );
}
