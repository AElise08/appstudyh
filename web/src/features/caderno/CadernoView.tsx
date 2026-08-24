import { useCallback, useEffect, useRef, useState } from "react";
import type { Notebook, Workspace } from "../../domain/types";
import { createTask, newUUID } from "../../domain/create";
import {
  extractQuestionText,
  extractTaskTitle,
  selectParagraphAround,
  splitParagraphToCard,
} from "./convert";
import "./caderno.css";

export interface ViewProps {
  workspace: Workspace;
  onChange: (next: Workspace) => void;
}

const SAVE_DEBOUNCE_MS = 400;
const TOAST_MS = 2600;

function tomorrowISO(): string {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  return date.toISOString();
}

export default function CadernoView({ workspace, onChange }: ViewProps) {
  const notebooks = workspace.notebooks ?? [];
  const [selectedId, setSelectedId] = useState<string | null>(notebooks[0]?.id ?? null);
  const [bodyDraft, setBodyDraft] = useState("");
  const [creating, setCreating] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const toastTimerRef = useRef<number | undefined>(undefined);

  const notebook: Notebook | null = notebooks.find((item) => item.id === selectedId) ?? null;

  useEffect(() => {
    setBodyDraft(notebooks.find((item) => item.id === selectedId)?.plainText ?? "");
    setError(null);
  }, [selectedId]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!notebook || bodyDraft === notebook.plainText) return;
    const timer = setTimeout(() => {
      patchNotebook(notebook.id, { plainText: bodyDraft });
    }, SAVE_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }); // re-run on every render; guarded by the equality check above

  useEffect(() => () => window.clearTimeout(toastTimerRef.current), []);

  const touchWorkspace = useCallback(
    (patch: Partial<Pick<Workspace, "notebooks" | "studyArtifacts" | "studyTasks">>): Workspace => ({
      ...workspace,
      ...patch,
      updatedAt: new Date().toISOString(),
    }),
    [workspace],
  );

  function patchNotebook(id: string, patch: Partial<Pick<Notebook, "title" | "plainText">>): void {
    onChange(
      touchWorkspace({
        notebooks: notebooks.map((item) =>
          item.id === id ? { ...item, ...patch, updatedAt: new Date().toISOString() } : item,
        ),
      }),
    );
  }

  function showToast(message: string): void {
    window.clearTimeout(toastTimerRef.current);
    setToast(message);
    toastTimerRef.current = window.setTimeout(() => setToast(null), TOAST_MS);
  }

  function handleCreate(): void {
    const title = newTitle.trim();
    if (title.length === 0) return;
    const now = new Date().toISOString();
    const created: Notebook = {
      id: newUUID(),
      title,
      plainText: "",
      createdAt: now,
      updatedAt: now,
    };
    onChange(touchWorkspace({ notebooks: [...notebooks, created] }));
    setSelectedId(created.id);
    setNewTitle("");
    setCreating(false);
  }

  function handleDelete(target: Notebook): void {
    if (!window.confirm(`Excluir o caderno “${target.title}”? Esta ação não pode ser desfeita.`)) {
      return;
    }
    const remaining = notebooks.filter((item) => item.id !== target.id);
    onChange(touchWorkspace({ notebooks: remaining }));
    if (selectedId === target.id) setSelectedId(remaining[0]?.id ?? null);
  }

  function commitRename(): void {
    const target = notebooks.find((item) => item.id === renamingId);
    setRenamingId(null);
    if (!target) return;
    const trimmed = renameDraft.trim();
    if (trimmed.length === 0 || trimmed === target.title) return;
    patchNotebook(target.id, { title: trimmed });
  }

  function paragraphAtCaret(): string | null {
    const element = textareaRef.current;
    if (!element) return null;
    const caret = element.selectionStart ?? element.value.length;
    return selectParagraphAround(element.value, caret)?.text ?? null;
  }

  function runConversion(kind: "flashcards" | "task" | "question"): void {
    setError(null);
    if (!notebook) return;
    const paragraph = paragraphAtCaret();
    if (paragraph === null) {
      setError("Posicione o cursor dentro de um parágrafo.");
      return;
    }

    if (kind === "flashcards") {
      const split = splitParagraphToCard(paragraph);
      if (split === null) {
        setError(
          "Não foi possível dividir em Frente/Verso. Use uma linha nova, “ — ” ou “: ” entre frente e verso.",
        );
        return;
      }
      const artifact = {
        id: newUUID(),
        kind: "flashcards" as const,
        body: `Frente: ${split.front}\nVerso: ${split.back}`,
        createdAt: new Date().toISOString(),
        sourceNodeID: null,
      };
      onChange(
        touchWorkspace({ studyArtifacts: [...(workspace.studyArtifacts ?? []), artifact] }),
      );
      showToast("Flashcard adicionado ao baralho.");
      return;
    }

    if (kind === "task") {
      const title = extractTaskTitle(paragraph);
      if (title === null) {
        setError("O parágrafo está vazio.");
        return;
      }
      const task = createTask(title, tomorrowISO(), "normal");
      onChange(touchWorkspace({ studyTasks: [...(workspace.studyTasks ?? []), task] }));
      showToast("Tarefa criada com vencimento para amanhã.");
      return;
    }

    const questionBody = extractQuestionText(paragraph);
    if (questionBody === null) {
      setError("O parágrafo está vazio.");
      return;
    }
    const artifact = {
      id: newUUID(),
      kind: "question" as const,
      body: questionBody,
      createdAt: new Date().toISOString(),
      sourceNodeID: null,
    };
    onChange(touchWorkspace({ studyArtifacts: [...(workspace.studyArtifacts ?? []), artifact] }));
    showToast("Questão registrada nos materiais de estudo.");
  }

  return (
    <div className="caderno">
      <aside className="caderno__sidebar">
        <div className="caderno__sidebar-header">
          <span className="caderno__sidebar-label">Cadernos</span>
          <button
            type="button"
            className="caderno__new-btn"
            onClick={() => {
              setCreating(true);
              setNewTitle("");
            }}
          >
            + Novo caderno
          </button>
        </div>

        {creating && (
          <form
            className="caderno__create"
            onSubmit={(event) => {
              event.preventDefault();
              handleCreate();
            }}
          >
            <input
              autoFocus
              className="caderno__input"
              value={newTitle}
              placeholder="Título do caderno"
              aria-label="Título do novo caderno"
              onChange={(event) => setNewTitle(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Escape") setCreating(false);
              }}
            />
            <div className="caderno__create-actions">
              <button type="button" className="caderno__ghost-btn" onClick={() => setCreating(false)}>
                Cancelar
              </button>
              <button type="submit" className="caderno__primary-btn">
                Criar
              </button>
            </div>
          </form>
        )}

        <ul className="caderno__list">
          {notebooks.map((item) => (
            <li key={item.id} className="caderno__list-item">
              {renamingId === item.id ? (
                <input
                  autoFocus
                  className="caderno__input"
                  value={renameDraft}
                  aria-label="Renomear caderno"
                  onChange={(event) => setRenameDraft(event.target.value)}
                  onBlur={commitRename}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") commitRename();
                    if (event.key === "Escape") setRenamingId(null);
                  }}
                />
              ) : (
                <>
                  <button
                    type="button"
                    className={`caderno__item-btn${item.id === selectedId ? " is-selected" : ""}`}
                    onDoubleClick={() => {
                      setRenamingId(item.id);
                      setRenameDraft(item.title);
                    }}
                    onClick={() => setSelectedId(item.id)}
                    title="Duplo clique para renomear"
                  >
                    <span className="caderno__item-title">{item.title}</span>
                  </button>
                  <button
                    type="button"
                    className="caderno__delete-btn"
                    aria-label={`Excluir ${item.title}`}
                    onClick={() => handleDelete(item)}
                  >
                    Excluir
                  </button>
                </>
              )}
            </li>
          ))}
          {notebooks.length === 0 && (
            <li className="caderno__list-empty">Nenhum caderno ainda.</li>
          )}
        </ul>
      </aside>

      <section className="caderno__editor">
        {notebook === null ? (
          <div className="caderno__empty">Selecione ou crie um caderno para começar a escrever.</div>
        ) : (
          <>
            <input
              className="caderno__title"
              value={notebook.title}
              aria-label="Título do caderno"
              placeholder="Sem título"
              onChange={(event) => patchNotebook(notebook.id, { title: event.target.value })}
            />

            <div className="caderno__convert-bar" role="toolbar" aria-label="Converter parágrafo">
              <span className="caderno__convert-label">Converter parágrafo:</span>
              <button type="button" className="caderno__convert-btn" onClick={() => runConversion("flashcards")}>
                → Flashcard
              </button>
              <button type="button" className="caderno__convert-btn" onClick={() => runConversion("task")}>
                → Tarefa
              </button>
              <button type="button" className="caderno__convert-btn" onClick={() => runConversion("question")}>
                → Questão
              </button>
            </div>

            {error !== null && (
              <p className="caderno__error" role="alert">
                {error}
              </p>
            )}

            <textarea
              ref={textareaRef}
              className="caderno__body"
              value={bodyDraft}
              placeholder="Escreva suas anotações. Um parágrafo por ideia facilita converter em flashcards, tarefas e questões."
              aria-label="Corpo do caderno"
              onChange={(event) => {
                setError(null);
                setBodyDraft(event.target.value);
              }}
            />

            {toast !== null && (
              <div className="caderno__toast" role="status">
                {toast}
              </div>
            )}
          </>
        )}
      </section>
    </div>
  );
}
