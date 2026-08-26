import { useState } from "react";
import { AI_MODE_HELP, AI_MODE_LABELS, type AIMode } from "./prompt.js";
import "./ai.css";

export interface LassoBarProps {
  selectionText: string;
  loading: boolean;
  error: string | null;
  response: string | null;
  onRun: (mode: AIMode) => void;
  onClose: () => void;
}

export default function LassoBar({
  selectionText,
  loading,
  error,
  response,
  onRun,
  onClose,
}: LassoBarProps) {
  const [mode, setMode] = useState<AIMode>("check");
  const trimmed = selectionText.trim();
  const disabled = loading || trimmed.length === 0;

  return (
    <div className="lasso-bar" role="region" aria-label="Tutor">
      <div className="lasso-bar__header">
        <strong>Tutor</strong>
        <button type="button" className="lasso-bar__close" onClick={onClose} aria-label="Fechar">
          ×
        </button>
      </div>

      <p className="lasso-bar__hint">
        {trimmed.length === 0
          ? "Selecione texto no leitor ou cards na lousa."
          : `Seleção (${trimmed.length} caracteres)`}
      </p>

      <div className="lasso-bar__modes">
        {(Object.keys(AI_MODE_LABELS) as AIMode[]).map((key) => (
          <button
            key={key}
            type="button"
            className={`lasso-bar__mode${mode === key ? " is-active" : ""}`}
            onClick={() => setMode(key)}
          >
            {AI_MODE_LABELS[key]}
          </button>
        ))}
      </div>
      <p className="lasso-bar__help">{AI_MODE_HELP[mode]}</p>

      <button
        type="button"
        className="lasso-bar__run"
        disabled={disabled}
        onClick={() => onRun(mode)}
      >
        {loading ? "Pensando…" : "Perguntar ao tutor"}
      </button>

      {error !== null && <p className="lasso-bar__error">{error}</p>}
      {response !== null && <article className="lasso-bar__response">{response}</article>}
    </div>
  );
}
