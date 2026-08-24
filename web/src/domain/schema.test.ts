import { describe, expect, it } from "vitest";
import {
  DomainDecodeError,
  decodeWorkspace,
  decodeWorkspaceIndexDocument,
  encodeWorkspace,
  encodeWorkspaceIndex,
} from "./schema";

const workspaceID = "11111111-2222-3333-4444-555555555555";
const nodeID = "22222222-3333-4444-5555-666666666666";
const date = "2026-08-24T12:00:00.000Z";

function flatWorkspace(schemaVersion: unknown): Record<string, unknown> {
  return {
    ...(schemaVersion === undefined ? {} : { schemaVersion }),
    id: workspaceID,
    name: "Workspace versionado",
    nodes: [
      {
        id: nodeID,
        kind: "note",
        title: "Nota",
        frame: { x: 0, y: 0, width: 280, height: 220 },
        zIndex: 0,
        noteBody: "",
        pdfPageIndex: 0,
        pdfSelectedText: "",
        pdfVisibleText: "",
        webURL: "https://www.google.com",
        webSelectedText: "",
        calcBody: "",
      },
    ],
    cameraX: 42,
    cameraY: -7,
    cameraScale: 1.5,
    updatedAt: date,
  };
}

describe("workspace document codec", () => {
  it("decodes the current schema version and keeps the flat format", () => {
    const decoded = decodeWorkspace(flatWorkspace(1));
    expect(decoded).toMatchObject({
      schemaVersion: 1,
      id: workspaceID,
      name: "Workspace versionado",
      cameraX: 42,
      cameraY: -7,
      cameraScale: 1.5,
    });
    expect(decoded.nodes[0]?.id).toBe(nodeID);
  });

  it("treats a missing schemaVersion as legacy and normalizes to 1", () => {
    const legacy = decodeWorkspace(flatWorkspace(undefined));
    expect(legacy.schemaVersion).toBe(1);
    expect(legacy.id).toBe(workspaceID);
    expect(decodeWorkspace(JSON.parse(encodeWorkspace(legacy))).schemaVersion).toBe(1);
  });

  it("rejects future, null, negative, fractional, and string versions", () => {
    for (const [version, code] of [
      [2, "unsupported-schema-version"],
      [null, "invalid-schema-version"],
      [-1, "invalid-schema-version"],
      ["1", "invalid-schema-version"],
      [1.5, "invalid-schema-version"],
    ] as const) {
      try {
        decodeWorkspace(flatWorkspace(version));
        expect.unreachable(`version ${String(version)} should be rejected`);
      } catch (error) {
        expect(error).toBeInstanceOf(DomainDecodeError);
        expect((error as DomainDecodeError).code).toBe(code);
      }
    }
  });

  it("ignores unknown additive fields", () => {
    const document = flatWorkspace(1);
    document.campoFuturoDesconhecido = "preservar compatibilidade aditiva";
    expect(decodeWorkspace(document).id).toBe(workspaceID);
  });
});

describe("workspace index codec", () => {
  it("round-trips the current index version on write", () => {
    const encoded = JSON.parse(
      encodeWorkspaceIndex({ schemaVersion: 1, workspaceIDs: [workspaceID], selectedID: null }),
    );
    expect(encoded.schemaVersion).toBe(1);
    const decoded = decodeWorkspaceIndexDocument(encoded);
    expect(decoded).toEqual({ schemaVersion: 1, workspaceIDs: [workspaceID], selectedID: null });
  });

  it("decodes a legacy index without schemaVersion", () => {
    const decoded = decodeWorkspaceIndexDocument(
      `{"workspaceIDs":["${workspaceID}"],"selectedID":null}`,
    );
    expect(decoded.workspaceIDs).toEqual([workspaceID]);
    expect(JSON.parse(encodeWorkspaceIndex(decoded)).schemaVersion).toBe(1);
  });

  it("rejects future and invalid versions", () => {
    for (const [version, code] of [
      [`{"schemaVersion":2,"workspaceIDs":[],"selectedID":null}`, "unsupported-schema-version"],
      [`{"schemaVersion":null,"workspaceIDs":[],"selectedID":null}`, "invalid-schema-version"],
      [`{"schemaVersion":-3,"workspaceIDs":[],"selectedID":null}`, "invalid-schema-version"],
      [`{"schemaVersion":"2","workspaceIDs":[],"selectedID":null}`, "invalid-schema-version"],
    ] as const) {
      try {
        decodeWorkspaceIndexDocument(version);
        expect.unreachable(`${version} should be rejected`);
      } catch (error) {
        expect((error as DomainDecodeError).code).toBe(code);
      }
    }
  });

  it("ignores unknown fields in the index too", () => {
    const decoded = decodeWorkspaceIndexDocument(
      `{"schemaVersion":1,"workspaceIDs":[],"novoCampo":true}`,
    );
    expect(decoded.workspaceIDs).toEqual([]);
  });
});
