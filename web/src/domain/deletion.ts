import type { UUID, Workspace } from "./types";

export interface RemovalImpact {
  artifacts: number;
  derivedNodes: number;
  reviews: number;
  historyEntries: number;
  activityEvents: number;
  focusSessions: number;
  notebooks: number;
  linkedRecordCount: number;
}

export interface DeletionResult {
  workspace: Workspace;
  impact: RemovalImpact;
}

function countLinked(
  workspace: Workspace,
  ids: ReadonlySet<UUID>,
): Omit<RemovalImpact, "linkedRecordCount"> {
  const counts = {
    artifacts: workspace.studyArtifacts?.filter((a) => a.sourceNodeID != null && ids.has(a.sourceNodeID)).length ?? 0,
    derivedNodes: workspace.nodes.filter(
      (n) => n.sourceMaterialID != null && ids.has(n.sourceMaterialID) && !ids.has(n.id),
    ).length,
    reviews: workspace.flashcardReviews?.filter((r) => r.sourceNodeID != null && ids.has(r.sourceNodeID)).length ?? 0,
    historyEntries: workspace.studyHistory?.filter((h) => ids.has(h.nodeID)).length ?? 0,
    activityEvents:
      workspace.studyActivityEvents?.filter((e) => e.nodeID != null && ids.has(e.nodeID)).length ?? 0,
    focusSessions: workspace.focusSessions?.filter((s) => s.materialID != null && ids.has(s.materialID)).length ?? 0,
    notebooks: workspace.notebooks?.filter((n) => n.sourceMaterialID != null && ids.has(n.sourceMaterialID)).length ?? 0,
  };
  return counts;
}

/**
 * Removes the given material nodes plus incident connections, deletes their
 * history entries, and preserves every other dependent record by clearing its
 * stale source links. Pure: returns a new workspace.
 */
export function deleteMaterials(workspace: Workspace, ids: Iterable<UUID>): DeletionResult {
  const removed = new Set(ids);
  const counts = countLinked(workspace, removed);
  const impact: RemovalImpact = {
    ...counts,
    linkedRecordCount: Object.values(counts).reduce((sum, count) => sum + count, 0),
  };

  const next: Workspace = {
    ...workspace,
    nodes: workspace.nodes
      .filter((node) => !removed.has(node.id))
      .map((node) =>
        node.sourceMaterialID != null && removed.has(node.sourceMaterialID)
          ? { ...node, sourceMaterialID: null }
          : node,
      ),
    connections: workspace.connections?.filter(
      (connection) => !removed.has(connection.fromNodeID) && !removed.has(connection.toNodeID),
    ),
    studyArtifacts: workspace.studyArtifacts?.map((artifact) =>
      artifact.sourceNodeID != null && removed.has(artifact.sourceNodeID)
        ? { ...artifact, sourceNodeID: null }
        : artifact,
    ),
    flashcardReviews: workspace.flashcardReviews?.map((review) =>
      review.sourceNodeID != null && removed.has(review.sourceNodeID)
        ? { ...review, sourceNodeID: null }
        : review,
    ),
    studyHistory: workspace.studyHistory?.filter((entry) => !removed.has(entry.nodeID)),
    studyActivityEvents: workspace.studyActivityEvents?.map((event) =>
      event.nodeID != null && removed.has(event.nodeID) ? { ...event, nodeID: null } : event,
    ),
    focusSessions: workspace.focusSessions?.map((session) =>
      session.materialID != null && removed.has(session.materialID)
        ? { ...session, materialID: null }
        : session,
    ),
    notebooks: workspace.notebooks?.map((notebook) =>
      notebook.sourceMaterialID != null && removed.has(notebook.sourceMaterialID)
        ? { ...notebook, sourceMaterialID: null, sourcePageIndex: null }
        : notebook,
    ),
  };
  return { workspace: next, impact };
}
