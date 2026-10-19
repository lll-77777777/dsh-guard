// clean-auth-cookies.mjs
// Deletes accumulated dsh-auth-* cookies from the DSH (Electron/Chromium) cookie DB.
// Those cookies pile up per launch (one new one per random port, 30-day TTL) and
// eventually blow past the host webserver header limit -> 431 -> "Web authentication failed".
//
// Usage: node clean-auth-cookies.mjs <userDataDir>
// Must run while DSH is closed (the Cookies file is locked while the app runs).

import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const userData = process.argv[2];
if (!userData) {
  console.error('usage: clean-auth-cookies.mjs <userDataDir>');
  process.exit(2);
}

const dbFile = path.join(userData, 'Network', 'Cookies');
if (!fs.existsSync(dbFile)) {
  console.log('no cookie db, nothing to do');
  process.exit(0);
}

let db;
try {
  db = new DatabaseSync(dbFile);
} catch (e) {
  console.error('cannot open cookie db (DSH still running?): ' + e.message);
  process.exit(1);
}

try {
  const before = db.prepare('SELECT COUNT(*) AS n FROM cookies').get().n;
  const del = db.prepare("DELETE FROM cookies WHERE name LIKE 'dsh-auth-%'").run();
  const after = db.prepare('SELECT COUNT(*) AS n FROM cookies').get().n;
  try { db.exec('PRAGMA wal_checkpoint(TRUNCATE)'); } catch {}
  db.close();
  console.log(`dsh-auth deleted: ${del.changes}; cookies ${before} -> ${after}`);
} catch (e) {
  try { db.close(); } catch {}
  console.error('cookie cleanup failed: ' + e.message);
  process.exit(1);
}
