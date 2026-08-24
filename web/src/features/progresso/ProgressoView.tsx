import { useEffect, useMemo, useState } from "react";
import type { NodeKind, TaskPriority, Workspace } from "../../domain/types";
import { cardIdentity } from "../../domain/flashcards";
import {
  collectFlashcardRefs,
  coverageRatio,
  dueTodayCount,
  estimateUnitCount,
  nearestDeadline,
  nextAction,
  openTasks,
  type FlashcardRef,
} from "./metrics";
import "./progresso.css";

export interface ViewProps {
  workspace: Workspace;
  onChange: (next: Workspace) => void;
}

export interface ProgressoViewProps extends ViewProps {
  onNavigate?: (mode: "estudar") => void;
}

const KIND_LABELS: Record<NodeKind, string> = {
  note: "Nota",
  pdf: "PDF",
  epub: "EPUB",
  web: "Pesquisa",
  calc: "Resolução",
  slides: "Slides",
};

const PRIORITY_GROUPS: readonly { priority: TaskPriority; label: string }[] = [
  { priority: "high", label: "Alta" },
  { priority: "normal", label: "Normal" },
  { priority: "low", label: "Baixa" },
];

const ACTION_HINTS = {
  flashcards: "Flashcards esperando revisão hoje.",
  task: "Uma tarefa aberta está próxima.",
  material: "Continue de onde parou no material.",
} as const;

function formatDay(iso: string): string {
  return new Date(iso).toLocaleDateString("pt-BR");
}

function percent(ratio: number): number {
  return Math.round(ratio * 100);
}

export default function ProgressoView({ workspace, onChange, onNavigate }: ProgressoViewProps) {
  const [identities, setIdentities] = useState<Map<string, string>>(() => new Map());
  const now = useMemo(() => new Date(), []);
  const refs: FlashcardRef[] = useMemo(() => collectFlashcardRefs(workspace), [workspace]);
  const reviews = workspace.flashcardReviews ?? [];
  const tasks = workspace.studyTasks ?? [];

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const entries = await Promise.all(
        refs.map(async (ref) => [ref.sourceKey, await cardIdentity(ref.front, ref.back)] as const),
      );
      if (!cancelled) setIdentities(new Map(entries));
    })();
    return () => {
      cancelled = true;
    };
  }, [refs]);

  const metrics = useMemo(() => {
    const dueHoje = dueTodayCount(refs, identities, reviews, now);
    const abertas = openTasks(tasks);
    return {
      totalFlashcards: refs.length,
      dueHoje,
      tarefasAbertas: abertas.length,
      notas: (workspace.studyArtifacts ?? []).filter((a) => a.kind === "note").length,
      cadernos: (workspace.notebooks ?? []).length,
      prazo: nearestDeadline(workspace),
      action: nextAction({ refs, identities, reviews, tasks, now }),
    };
  }, [identities, now, refs, reviews, tasks, workspace]);

  function toggleTask(id: string): void {
    onChange({
      ...workspace,
      studyTasks: tasks.map((task) =>
        task.id === id ? { ...task, isCompleted: !task.isCompleted } : task,
      ),
      updatedAt: new Date().toISOString(),
    });
  }

  function deleteTask(id: string): void {
    onChange({
      ...workspace,
      studyTasks: tasks.filter((task) => task.id !== id),
      updatedAt: new Date().toISOString(),
    });
  }

  const grouped = PRIORITY_GROUPS.map((group) => ({
    ...group,
    tasks: tasks.filter((task) => task.priority === group.priority),
  })).filter((group) => group.tasks.length > 0);

  return (
    <div className="progresso">
      <section className="progresso__today progresso__card">
        <h2 className="progresso__card-title">Hoje</h2>
        <div className="progresso__today-grid">
          <div className="progresso__stat">
            <span className="progresso__stat-value">{metrics.dueHoje}</span>
            <span className="progresso__stat-label">cartas para hoje</span>
          </div>
          <div className="progresso__stat">
            <span className="progresso__stat-value">{metrics.tarefasAbertas}</span>
            <span className="progresso__stat-label">tarefas abertas</span>
          </div>
          <div className="progresso__stat">
            <span className="progresso__stat-value">
              {metrics.prazo === null ? "—" : formatDay(metrics.prazo)}
            </span>
            <span className="progresso__stat-label">próxima prova/apresentação</span>
          </div>
        </div>
        <p className="progresso__hint">{ACTION_HINTS[metrics.action]}</p>
        <button
          type="button"
          className="progresso__cta"
          onClick={() => onNavigate?.("estudar")}
        >
          Começar próxima ação
        </button>
      </section>

      <section className="progresso__metrics">
        <div className="progresso__metric progresso__card">
          <span className="progresso__metric-value">{metrics.totalFlashcards}</span>
          <span className="progresso__metric-label">Total flashcards</span>
        </div>
        <div className="progresso__metric progresso__card">
          <span className="progresso__metric-value">{metrics.dueHoje}</span>
          <span className="progresso__metric-label">Due hoje</span>
        </div>
        <div className="progresso__metric progresso__card">
          <span className="progresso__metric-value">{metrics.tarefasAbertas}</span>
          <span className="progresso__metric-label">Tarefas abertas</span>
        </div>
        <div className="progresso__metric progresso__card">
          <span className="progresso__metric-value">{metrics.notas}</span>
          <span className="progresso__metric-label">Notas</span>
        </div>
        <div className="progresso__metric progresso__card">
          <span className="progresso__metric-value">{metrics.cadernos}</span>
          <span className="progresso__metric-label">Cadernos</span>
        </div>
      </section>

      <section className="progresso__tasks progresso__card">
        <h2 className="progresso__card-title">Tarefas</h2>
        {grouped.length === 0 ? (
          <p className="progresso__empty-line">Nenhuma tarefa registrada.</p>
        ) : (
          grouped.map((group) => (
            <div key={group.priority} className="progresso__task-group">
              <span className={`progresso__chip progresso__chip--${group.priority}`}>
                {group.label}
              </span>
              <ul className="progresso__task-list">
                {group.tasks.map((task) => (
                  <li key={task.id} className={`progresso__task${task.isCompleted ? " is-done" : ""}`}>
                    <label className="progresso__task-main">
                      <input
                        type="checkbox"
                        checked={task.isCompleted}
                        onChange={() => toggleTask(task.id)}
                      />
                      <span className="progresso__task-title">{task.title}</span>
                      <time className="progresso__task-due">{formatDay(task.dueDate)}</time>
                    </label>
                    <button
                      type="button"
                      className="progresso__task-delete"
                      aria-label={`Excluir ${task.title}`}
                      onClick={() => deleteTask(task.id)}
                    >
                      Excluir
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          ))
        )}
      </section>

      <section className="progresso__materials progresso__card">
        <h2 className="progresso__card-title">Materiais</h2>
        {workspace.nodes.length === 0 ? (
          <p className="progresso__empty-line">Nenhum material na mesa.</p>
        ) : (
          <ul className="progresso__material-list">
            {workspace.nodes.map((node) => {
              const ratio = coverageRatio(node);
              const visited = node.visitedUnitIndices?.length ?? 0;
              const total = estimateUnitCount(node);
              return (
                <li key={node.id} className="progresso__material">
                  <div className="progresso__material-head">
                    <span className="progresso__material-title">{node.title}</span>
                    <span className="progresso__material-kind">{KIND_LABELS[node.kind] ?? node.kind}</span>
                    <span className="progresso__material-coverage">
                      Cobertura {visited}/{total} · {percent(ratio)}%
                    </span>
                  </div>
                  <div
                    className="progresso__bar"
                    role="progressbar"
                    aria-valuenow={percent(ratio)}
                    aria-valuemin={0}
                    aria-valuemax={100}
                    aria-label={`Cobertura de ${node.title}`}
                  >
                    <div
                      className="progresso__bar-fill"
                      style={{ width: `${percent(ratio)}%` }}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </div>
  );
}
