import { useCallback, useEffect, useRef, useState } from "react";
import type { CanvasRect, Workspace } from "../domain/types.js";
import { createCanvasNode } from "../domain/create.js";
import { nextNodePlacement } from "./placement.js";
import BoardCard from "./BoardCard.js";
import {
  clampScale,
  DOT_SIZE,
  ZOOM_STEP,
  type Camera,
} from "./camera.js";
import "./board.css";

export interface BoardViewProps {
  workspace: Workspace;
  onChange: (next: Workspace) => void;
  selectedIds: ReadonlySet<string>;
  onSelectionChange: (ids: Set<string>) => void;
  onOpenReader: (nodeId: string) => void;
  onAddMaterial?: () => void;
  onLoadAttachment?: (id: string) => Promise<Blob | null>;
  getAttachmentBlob?: (id: string) => Blob | null;
  onDeleteNodes?: (nodeIds: string[]) => void;
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

export default function BoardView({
  workspace,
  onChange,
  selectedIds,
  onSelectionChange,
  onOpenReader,
  onAddMaterial,
  onLoadAttachment,
  getAttachmentBlob,
  onDeleteNodes,
}: BoardViewProps) {
  const surfaceRef = useRef<HTMLDivElement | null>(null);
  const panRef = useRef<PanState | null>(null);
  const dragRef = useRef<DragState | null>(null);
  const cameraPersistRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const [camera, setCamera] = useState<Camera>({
    x: workspace.cameraX,
    y: workspace.cameraY,
    scale: workspace.cameraScale,
  });
  const [viewport, setViewport] = useState({ width: 0, height: 0 });

  const touchWorkspace = useCallback(
    (patch: Partial<Pick<Workspace, "nodes" | "cameraX" | "cameraY" | "cameraScale">>): Workspace => ({
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
    if (el === null) return;
    const observer = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (rect !== undefined) setViewport({ width: rect.width, height: rect.height });
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const persistCamera = useCallback(
    (next: Camera) => {
      if (cameraPersistRef.current !== null) clearTimeout(cameraPersistRef.current);
      cameraPersistRef.current = setTimeout(() => {
        onChange(
          touchWorkspace({
            cameraX: next.x,
            cameraY: next.y,
            cameraScale: next.scale,
          }),
        );
      }, 300);
    },
    [onChange, touchWorkspace],
  );

  useEffect(() => {
    const el = surfaceRef.current;
    if (el === null) return;
    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      const rect = el.getBoundingClientRect();
      const px = event.clientX - rect.left;
      const py = event.clientY - rect.top;
      setCamera((cam) => {
        const scale = clampScale(cam.scale * Math.exp(-event.deltaY * 0.002));
        const worldX = cam.x + px / cam.scale;
        const worldY = cam.y + py / cam.scale;
        const next = { scale, x: worldX - px / scale, y: worldY - py / scale };
        persistCamera(next);
        return next;
      });
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  }, [persistCamera]);

  const zoomAtCenter = useCallback(
    (factor: number) => {
      setCamera((cam) => {
        if (viewport.width === 0 || viewport.height === 0) {
          const next = { ...cam, scale: clampScale(cam.scale * factor) };
          persistCamera(next);
          return next;
        }
        const px = viewport.width / 2;
        const py = viewport.height / 2;
        const scale = clampScale(cam.scale * factor);
        const worldX = cam.x + px / cam.scale;
        const worldY = cam.y + py / cam.scale;
        const next = { scale, x: worldX - px / scale, y: worldY - py / scale };
        persistCamera(next);
        return next;
      });
    },
    [persistCamera, viewport.height, viewport.width],
  );

  const handleAddNote = useCallback(() => {
    const frame = nextNodePlacement(workspace.nodes, "note");
    const node = createCanvasNode({
      kind: "note",
      title: "Nota",
      frame,
    });
    onChange(touchWorkspace({ nodes: [...workspace.nodes, node] }));
    onSelectionChange(new Set([node.id]));
  }, [onChange, onSelectionChange, touchWorkspace, workspace.nodes]);

  const patchNode = useCallback(
    (nodeID: string, patch: Partial<Workspace["nodes"][number]>) => {
      onChange(
        touchWorkspace({
          nodes: workspace.nodes.map((node) => (node.id === nodeID ? { ...node, ...patch } : node)),
        }),
      );
    },
    [onChange, touchWorkspace, workspace.nodes],
  );

  const applyNodeFrame = useCallback(
    (nodeID: string, frame: CanvasRect) => {
      patchNode(nodeID, { frame });
    },
    [patchNode],
  );

  const startDrag = (node: { id: string; frame: CanvasRect }) => (event: React.PointerEvent<HTMLElement>) => {
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

  const moveDrag = (event: React.PointerEvent<HTMLElement>) => {
    const drag = dragRef.current;
    if (drag === null) return;
    const node = workspace.nodes.find((item) => item.id === drag.nodeID);
    if (node === undefined) {
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
    if (event.button !== 0) return;
    panRef.current = {
      startClientX: event.clientX,
      startClientY: event.clientY,
      camX: camera.x,
      camY: camera.y,
    };
    onSelectionChange(new Set());
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const handleSurfacePointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const pan = panRef.current;
    if (pan === null) return;
    setCamera((cam) => ({
      ...cam,
      x: pan.camX - (event.clientX - pan.startClientX) / cam.scale,
      y: pan.camY - (event.clientY - pan.startClientY) / cam.scale,
    }));
  };

  const handleSurfacePointerUp = (event: React.PointerEvent<HTMLDivElement>) => {
    if (panRef.current !== null) {
      setCamera((cam) => {
        persistCamera(cam);
        return cam;
      });
    }
    panRef.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  const scale = camera.scale || 1;

  return (
    <div className="board">
      <div className="board__toolbar">
        <button type="button" className="board__btn board__btn--primary" onClick={handleAddNote}>
          + Nota
        </button>
        {onAddMaterial !== undefined && (
          <button type="button" className="board__btn" onClick={onAddMaterial}>
            + Material
          </button>
        )}
        {selectedIds.size > 0 && onDeleteNodes !== undefined && (
          <button
            type="button"
            className="board__btn board__btn--danger"
            onClick={() => onDeleteNodes([...selectedIds])}
          >
            Excluir ({selectedIds.size})
          </button>
        )}
        <div className="board__toolbar-spacer" />
        <div className="board__zoom" role="group" aria-label="Zoom">
          <button type="button" className="board__btn" aria-label="Reduzir" onClick={() => zoomAtCenter(1 / ZOOM_STEP)}>
            −
          </button>
          <span className="board__zoom-value">{Math.round(scale * 100)}%</span>
          <button type="button" className="board__btn" aria-label="Aumentar" onClick={() => zoomAtCenter(ZOOM_STEP)}>
            +
          </button>
        </div>
      </div>

      <div
        ref={surfaceRef}
        className="board__surface"
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
          className="board__world"
          style={{
            transform: `translate(${-camera.x * scale}px, ${-camera.y * scale}px) scale(${scale})`,
          }}
        >
          {workspace.nodes.map((node) => (
            <BoardCard
              key={node.id}
              node={node}
              selected={selectedIds.has(node.id)}
              onPointerDownHeader={startDrag(node)}
              onPointerMoveHeader={moveDrag}
              onPointerUpHeader={endDrag}
              onSelect={() => onSelectionChange(new Set([node.id]))}
              onPatch={(patch) => patchNode(node.id, patch)}
              onOpenReader={() => onOpenReader(node.id)}
              onLoadAttachment={onLoadAttachment}
              attachmentBlob={getAttachmentBlob?.(node.id) ?? null}
            />
          ))}
        </div>

        {workspace.nodes.length === 0 && (
          <div className="board__empty">
            <strong>Sua lousa está vazia</strong>
            <span>Arraste o fundo para mover. Scroll para zoom.</span>
          </div>
        )}
      </div>
    </div>
  );
}
