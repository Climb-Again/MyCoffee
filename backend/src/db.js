// Single shared pg Pool + small helpers (query, withTransaction, healthcheck).
import pg from 'pg';
import { config } from './config.js';

function sslOption(databaseUrl) {
  if (config.pgssl === 'disable') return false;
  // Local connections don't need TLS.
  if (/@(localhost|127\.0\.0\.1)[:/]/.test(databaseUrl)) return false;
  // Railway/hosted Postgres uses certs that don't validate against the system CA.
  return { rejectUnauthorized: false };
}

export const pool = new pg.Pool({
  connectionString: config.databaseUrl,
  ssl: config.databaseUrl ? sslOption(config.databaseUrl) : false,
  max: 10,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000,
});

pool.on('error', (err) => {
  // Idle client errors shouldn't crash the process.
  console.error('[db] idle client error:', err.message);
});

export function query(text, params) {
  return pool.query(text, params);
}

export async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore rollback failure
    }
    throw err;
  } finally {
    client.release();
  }
}

export async function healthcheck() {
  try {
    const { rows } = await pool.query('SELECT 1 AS ok');
    return rows[0]?.ok === 1;
  } catch {
    return false;
  }
}
