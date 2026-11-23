// Keeps a copy of the collection in BACKUP_DIR (e.g. a folder in OneDrive).
//
// The live database stays on local disk: cloud sync clients upload files while
// they are being written, which can corrupt a live SQLite database. Instead we
// write a consistent snapshot with SQLite's backup API (to a temp file, then
// rename) and mirror the card photos.

import type Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";

export const BACKUP_DIR = process.env.BACKUP_DIR ? path.resolve(process.env.BACKUP_DIR) : null;

const DEBOUNCE_MS = 10_000;

let timer: NodeJS.Timeout | null = null;
let running = false;
let pending = false;
let lastBackupAt: string | null = null;
let lastError: string | null = null;

export function backupStatus() {
  return { enabled: BACKUP_DIR !== null, dir: BACKUP_DIR, lastBackupAt, lastError };
}

/**
 * If the local database is missing but a backup exists (e.g. after moving to a
 * new computer), copy the backup into place before the database is opened.
 */
export function restoreIfMissing(dataDir: string): boolean {
  if (!BACKUP_DIR) return false;
  const live = path.join(dataDir, "cards.db");
  const backup = path.join(BACKUP_DIR, "cards.db");
  if (fs.existsSync(live) || !fs.existsSync(backup)) return false;

  fs.mkdirSync(path.join(dataDir, "images"), { recursive: true });
  fs.copyFileSync(backup, live);
  copyNewFiles(path.join(BACKUP_DIR, "images"), path.join(dataDir, "images"));
  console.log(`Restored collection from backup in ${BACKUP_DIR}`);
  return true;
}

/** Copies files from src to dest that are missing or have a different size. */
function copyNewFiles(src: string, dest: string, removeExtra = false) {
  if (!fs.existsSync(src)) return;
  fs.mkdirSync(dest, { recursive: true });
  const names = new Set(fs.readdirSync(src));
  for (const name of names) {
    const from = path.join(src, name);
    const to = path.join(dest, name);
    const a = fs.statSync(from);
    if (!a.isFile()) continue;
    if (!fs.existsSync(to) || fs.statSync(to).size !== a.size) fs.copyFileSync(from, to);
  }
  if (removeExtra) {
    for (const name of fs.readdirSync(dest)) {
      if (!names.has(name)) fs.rmSync(path.join(dest, name), { force: true });
    }
  }
}

async function runBackup(db: Database.Database, dataDir: string) {
  if (!BACKUP_DIR) return;
  if (running) {
    pending = true;
    return;
  }
  running = true;
  try {
    fs.mkdirSync(BACKUP_DIR, { recursive: true });
    const tmp = path.join(BACKUP_DIR, "cards.db.tmp");
    await db.backup(tmp);
    fs.renameSync(tmp, path.join(BACKUP_DIR, "cards.db"));
    copyNewFiles(path.join(dataDir, "images"), path.join(BACKUP_DIR, "images"), true);
    lastBackupAt = new Date().toISOString();
    lastError = null;
  } catch (err) {
    lastError = err instanceof Error ? err.message : String(err);
    console.error("Backup failed:", err);
  } finally {
    running = false;
    if (pending) {
      pending = false;
      scheduleBackup(db, dataDir);
    }
  }
}

/** Backs up shortly after a change, batching bursts of edits into one copy. */
export function scheduleBackup(db: Database.Database, dataDir: string, delay = DEBOUNCE_MS) {
  if (!BACKUP_DIR) return;
  if (timer) clearTimeout(timer);
  timer = setTimeout(() => {
    timer = null;
    void runBackup(db, dataDir);
  }, delay);
  timer.unref?.();
}
