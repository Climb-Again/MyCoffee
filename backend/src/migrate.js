// Forward-only migration runner.
// Applies every backend/migrations/*.sql not already recorded in schema_migrations,
// in filename order, each in its own transaction, serialized across concurrent
// deploys by a pg advisory lock.
//
// Runs on every boot (from server.js, in the background) and via `npm run migrate`.
import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { pool, withTransaction } from './db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = path.join(__dirname, '..', 'migrations');

// Arbitrary but stable 64-bit key for pg_advisory_lock.
const ADVISORY_LOCK_KEY = 4820_1975;

async function ensureMigrationsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      filename   TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
}

async function appliedSet() {
  const { rows } = await pool.query('SELECT filename FROM schema_migrations');
  return new Set(rows.map((r) => r.filename));
}

async function listMigrationFiles() {
  let entries;
  try {
    entries = await readdir(MIGRATIONS_DIR);
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
  return entries.filter((f) => f.endsWith('.sql')).sort();
}

export async function runMigrations({ log = console } = {}) {
  await ensureMigrationsTable();

  // Serialize overlapping deploys: whoever holds the lock runs migrations; the
  // other waits and then finds nothing left to apply.
  const client = await pool.connect();
  try {
    await client.query('SELECT pg_advisory_lock($1)', [ADVISORY_LOCK_KEY]);

    const done = await appliedSet();
    const files = await listMigrationFiles();
    const pending = files.filter((f) => !done.has(f));

    if (pending.length === 0) {
      log.log?.('[migrate] up to date');
      return { applied: [] };
    }

    const applied = [];
    for (const filename of pending) {
      const sql = await readFile(path.join(MIGRATIONS_DIR, filename), 'utf8');
      await withTransaction(async (tx) => {
        await tx.query(sql);
        await tx.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [filename]);
      });
      applied.push(filename);
      log.log?.(`[migrate] applied ${filename}`);
    }
    return { applied };
  } finally {
    try {
      await client.query('SELECT pg_advisory_unlock($1)', [ADVISORY_LOCK_KEY]);
    } catch {
      // ignore unlock failure
    }
    client.release();
  }
}

// Allow `npm run migrate` / `node src/migrate.js`.
const isMain =
  process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (isMain) {
  runMigrations()
    .then(({ applied }) => {
      console.log(`[migrate] done (${applied.length} applied)`);
      return pool.end();
    })
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('[migrate] failed:', err);
      process.exit(1);
    });
}
