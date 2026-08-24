import { openDB } from "./db.js";

export async function withRawPut(record: { id: string; json: string }): Promise<void> {
  const db = await openDB();
  try {
    const tx = db.transaction("workspaces", "readwrite");
    tx.objectStore("workspaces").put(record);
    await new Promise<void>((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } finally {
    db.close();
  }
}
