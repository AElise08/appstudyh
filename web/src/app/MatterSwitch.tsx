import type { Workspace } from "../domain/types.js";
import "./matter.css";

export interface MatterSwitchProps {
  open: boolean;
  workspaces: readonly Workspace[];
  selectedId: string | null;
  onClose: () => void;
  onSelect: (id: string) => void;
  onCreate: () => void;
  onDelete: (workspace: Workspace) => void;
  onExport: () => void;
  onImport: () => void;
  importing?: boolean;
}

function examLabel(examDate: string | null | undefined): string | null {
  if (examDate === null || examDate === undefined) return null;
  const target = new Date(examDate).getTime();
  if (Number.isNaN(target)) return null;
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const days = Math.ceil((target - startOfToday) / 86_400_000);
  if (days > 1) return `Prova em ${days}d`;
  if (days === 1) return "Prova amanhã";
  if (days === 0) return "Prova hoje";
  return null;
}

export default function MatterSwitch({
  open,
  workspaces,
  selectedId,
  onClose,
  onSelect,
  onCreate,
  onDelete,
  onExport,
  onImport,
  importing = false,
}: MatterSwitchProps) {
  if (!open) return null;

  return (
    <>
      <div className="matter__backdrop" onClick={onClose} aria-hidden="true" />
      <aside className="matter" role="dialog" aria-label="Matérias">
        <header className="matter__header">
          <h2>Matérias</h2>
          <button type="button" className="matter__close" onClick={onClose} aria-label="Fechar">
            ×
          </button>
        </header>

        <ul className="matter__list">
          {workspaces.map((ws) => (
            <li key={ws.id}>
              <button
                type="button"
                className={`matter__item${ws.id === selectedId ? " is-selected" : ""}`}
                onClick={() => {
                  onSelect(ws.id);
                  onClose();
                }}
              >
                <span className="matter__name">{ws.name}</span>
                <span className="matter__meta">{examLabel(ws.examDate)}</span>
              </button>
              <button
                type="button"
                className="matter__delete"
                aria-label={`Excluir ${ws.name}`}
                onClick={() => onDelete(ws)}
              >
                ×
              </button>
            </li>
          ))}
        </ul>

        <div className="matter__actions">
          <button type="button" className="matter__btn matter__btn--primary" onClick={onCreate}>
            Nova matéria
          </button>
          <button type="button" className="matter__btn" onClick={onExport}>
            Exportar
          </button>
          <button type="button" className="matter__btn" disabled={importing} onClick={onImport}>
            Importar
          </button>
        </div>
      </aside>
    </>
  );
}
