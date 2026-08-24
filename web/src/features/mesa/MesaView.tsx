import { useCallback, useEffect, useRef, useState } from "react";
import type { CanvasRect, NodeKind, Workspace } from "../../domain/types";
import { createCanvasNode } from "../../domain/create";
import { computeGridLayout } from "./layout";
import "./mesa.css";

export interface ViewProps {
  workspace: Workspace;
  onChange: (next: Workspace) => void;
}

const KIND_LABELS: Record<NodeKind, string> = {
  note: "Nota",
  pdf: "PDF",
  epub: "EPUB",
  web: "Pesquisa",
  calc: "Resolução",
  slides: "Slides",
};

const MIN_SCALE = 0.25;
const MAX_SCALE = 3;
const ZOOM_STEP = 1.2;
const GRID_AREA_WIDTH = 1000;
const GRID_SPACING = 24;
const DOT_SIZE = 24;
const FIT_PADDING = 48;

interface Camera {
  x: number;
  y: number;
  scale: number;
}

interface Bounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface PanState {
  startClientX: number;
  startClientY: number;
  camX: number;
  camY: number;
}

interface DragState {
  nodeID: string;
  startClientX: number;
  startClientY: number;
  frameX: number;
  frameY: number;
  scale: number;
}

function clampScale(scale: number): number {
  return Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale));
}

function nodeBounds(nodes: readonly { frame: CanvasRect }[]): Bounds | null {
  if (nodes.length === 0) return null;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const node of nodes) {
    minX = Math.min(minX, node.frame.x);
    minY = Math.min(minY, node.frame.y);
    maxX = Math.max(maxX, node.frame.x + node.frame.width);
    maxY = Math.max(maxY, node.frame.y + node.frame.height);
  }
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

export default function MesaView({ workspace, onChange }: ViewProps) {
  const surfaceRef = useRef<HTMLDivElement | null>(null);
  const panRef = useRef<PanState | null>(null);
  const dragRef = useRef<DragState | null>(null);
  const [camera, setCamera] = useState<Camera>({
    x: workspace.cameraX,
    y: workspace.cameraY,
    scale: workspace.cameraScale,
  });
  const [viewport, setViewport] = useState({ width: 0, height: 0 });

  const touchWorkspace = useCallback(
    (patch: Partial<Pick<Workspace, "nodes">>): Workspace => ({
      ...workspace,
      ...patch,
      updatedAt: new Date().toISOString(),
    }),
    [workspace],
  );

  useEffect(() => {
    setCamera({ x: workspace.cameraX, y: workspace.cameraY, scale: workspace.cameraScale });
  }, [workspace.id]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const el = surfaceRef.current;
    if (!el) return;
    const observer = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (rect) setViewport({ width: rect.width, height: rect.height });
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const el = surfaceRef.current;
    if (!el) return;
    const onWheel = (event: WheelEvent) => {
      if (!event.ctrlKey) return;
      event.preventDefault();
      const rect = el.getBoundingClientRect();
      const px = event.clientX - rect.left;
      const py = event.clientY - rect.top;
      setCamera((cam) => {
        const scale = clampScale(cam.scale * Math.exp(-event.deltaY * 0.0015));
        const worldX = cam.x + px / cam.scale;
        const worldY = cam.y + py / cam.scale;
        return { scale, x: worldX - px / scale, y: worldY - py / scale };
      });
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  }, []);

  const zoomAtCenter = useCallback(
    (factor: number) => {
      setCamera((cam) => {
        if (viewport.width === 0 || viewport.height === 0) {
          return { ...cam, scale: clampScale(cam.scale * factor) };
        }
        const px = viewport.width / 2;
        const py = viewport.height / 2;
        const scale = clampScale(cam.scale * factor);
        const worldX = cam.x + px / cam.scale;
        const worldY = cam.y + py / cam.scale;
        return { scale, x: worldX - px / scale, y: worldY - py / scale };
      });
    },
    [viewport.height, viewport.width],
  );

  const fitToBounds = useCallback(
    (bounds: Bounds | null) => {
      if (
        bounds === null ||
        bounds.width <= 0 ||
        bounds.height <= 0 ||
        viewport.width === 0 ||
        viewport.height === 0
      ) {
        setCamera({ x: 0, y: 0, scale: 1 });
        return;
      }
      const scale = clampScale(
        Math.min(
          (viewport.width - FIT_PADDING * 2) / bounds.width,
          (viewport.height - FIT_PADDING * 2) / bounds.height,
        ),
      );
      const centerX = bounds.x + bounds.width / 2;
      const centerY = bounds.y + bounds.height / 2;
      setCamera({
        scale,
        x: centerX - viewport.width / (2 * scale),
        y: centerY - viewport.height / (2 * scale),
      });
    },
    [viewport.height, viewport.width],
  );

  const handleAddNote = useCallback(() => {
    const scale = camera.scale || 1;
    const centerX = camera.x + viewport.width / (2 * scale);
    const centerY = camera.y + viewport.height / (2 * scale);
    const node = createCanvasNode({
      kind: "note",
      title: "Nota",
      x: Math.round(centerX - 140),
      y: Math.round(centerY - 110),
    });
    onChange(touchWorkspace({ nodes: [...workspace.nodes, node] }));
  }, [camera.scale, camera.x, camera.y, onChange, touchWorkspace, viewport.height, viewport.width, workspace.nodes]);

  const handleOrganize = useCallback(() => {
    if (workspace.nodes.length === 0) return;
    const positions = computeGridLayout(
      workspace.nodes.map((node) => ({
        id: node.id,
        width: node.frame.width,
        height: node.frame.height,
      })),
      GRID_AREA_WIDTH,
      GRID_SPACING,
    );
    const laidOut = workspace.nodes.map((node) => {
      const point = positions.get(node.id);
      return point ? { ...node, frame: { ...node.frame, x: point.x, y: point.y } } : node;
    });
    onChange(touchWorkspace({ nodes: laidOut }));
    const laidOutNodes = laidOut.map((node) => ({ frame: node.frame }));
    fitToBounds(nodeBounds(laidOutNodes));
  }, [fitToBounds, onChange, touchWorkspace, workspace.nodes]);

  const handleFit = useCallback(() => {
    fitToBounds(nodeBounds(workspace.nodes));
  }, [fitToBounds, workspace.nodes]);

  const applyNodeFrame = useCallback(
    (nodeID: string, frame: CanvasRect) => {
      onChange(
        touchWorkspace({
          nodes: workspace.nodes.map((node) => (node.id === nodeID ? { ...node, frame } : node)),
        }),
      );
    },
    [onChange, touchWorkspace, workspace.nodes],
  );

  const startDrag = (node: { id: string; frame: CanvasRect }) => (event: React.PointerEvent<HTMLHeadingElement>) => {
    if (event.button !== 0) return;
    event.stopPropagation();
    dragRef.current = {
      nodeID: node.id,
      startClientX: event.clientX,
      startClientY: event.clientY,
      frameX: node.frame.x,
      frameY: node.frame.y,
      scale: camera.scale || 1,
    };
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const moveDrag = (event: React.PointerEvent<HTMLHeadingElement>) => {
    const drag = dragRef.current;
    if (!drag) return;
    const node = workspace.nodes.find((item) => item.id === drag.nodeID);
    if (!node) {
      dragRef.current = null;
      return;
    }
    const dx = (event.clientX - drag.startClientX) / drag.scale;
    const dy = (event.clientY - drag.startClientY) / drag.scale;
    applyNodeFrame(drag.nodeID, {
      ...node.frame,
      x: Math.round(drag.frameX + dx),
      y: Math.round(drag.frameY + dy),
    });
  };

  const endDrag = () => {
    dragRef.current = null;
  };

  const handleSurfacePointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (event.target !== event.currentTarget || event.button !== 0) return;
    panRef.current = {
      startClientX: event.clientX,
      startClientY: event.clientY,
      camX: camera.x,
      camY: camera.y,
    };
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const handleSurfacePointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const pan = panRef.current;
    if (!pan) return;
    setCamera((cam) => ({
      ...cam,
      x: pan.camX - (event.clientX - pan.startClientX) / cam.scale,
      y: pan.camY - (event.clientY - pan.startClientY) / cam.scale,
    }));
  };

  const handleSurfacePointerUp = (event: React.PointerEvent<HTMLDivElement>) => {
    panRef.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  const scale = camera.scale || 1;

  return (
    <div className="mesa">
      <div className="mesa__toolbar">
        <button type="button" className="mesa__btn mesa__btn--primary" onClick={handleAddNote}>
          + Nota
        </button>
        <button
          type="button"
          className="mesa__btn"
          onClick={handleOrganize}
          disabled={workspace.nodes.length === 0}
        >
          Organizar
        </button>
        <button
          type="button"
          className="mesa__btn"
          onClick={handleFit}
          disabled={workspace.nodes.length === 0}
        >
          Enquadrar
        </button>
        <div className="mesa__zoom" role="group" aria-label="Zoom">
          <button
            type="button"
            className="mesa__zoom-btn"
            aria-label="Reduzir zoom"
            onClick={() => zoomAtCenter(1 / ZOOM_STEP)}
          >
            −
          </button>
          <span className="mesa__zoom-value">{Math.round(scale * 100)}%</span>
          <button
            type="button"
            className="mesa__zoom-btn"
            aria-label="Aumentar zoom"
            onClick={() => zoomAtCenter(ZOOM_STEP)}
          >
            +
          </button>
        </div>
      </div>

      <div
        ref={surfaceRef}
        className="mesa__surface"
        style={{
          backgroundSize: `${DOT_SIZE * scale}px ${DOT_SIZE * scale}px`,
          backgroundPosition: `${-camera.x * scale}px ${-camera.y * scale}px`,
        }}
        onPointerDown={handleSurfacePointerDown}
        onPointerMove={handleSurfacePointerMove}
        onPointerUp={handleSurfacePointerUp}
        onPointerCancel={handleSurfacePointerUp}
      >
        <div
          className="mesa__world"
          style={{
            transform: `translate(${-camera.x * scale}px, ${-camera.y * scale}px) scale(${scale})`,
          }}
        >
          {workspace.nodes.map((node) => (
            <article
              key={node.id}
              className="mesa__card"
              style={{
                left: node.frame.x,
                top: node.frame.y,
                width: node.frame.width,
                height: node.frame.height,
                zIndex: 10 + node.zIndex,
              }}
            >
              <header
                className="mesa__card-header"
                onPointerDown={startDrag(node)}
                onPointerMove={moveDrag}
                onPointerUp={endDrag}
                onPointerCancel={endDrag}
              >
                <span className="mesa__card-title">{node.title}</span>
                <span className="mesa__card-kind">{KIND_LABELS[node.kind] ?? node.kind}</span>
              </header>
              {node.kind === "note" && node.noteBody.trim().length > 0 && (
                <p className="mesa__card-body">{node.noteBody}</p>
              )}
            </article>
          ))}
        </div>

        {workspace.nodes.length === 0 && (
          <div className="mesa__empty">
            A mesa está vazia.
            <small>Use “+ Nota” para criar o primeiro cartão.</small>
          </div>
        )}
      </div>
    </div>
  );
}
