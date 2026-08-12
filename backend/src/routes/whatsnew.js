// GET /api/whatsnew — curated "what's live / what's planned" content for the
// in-app What's New screen (PLAN.md §13). Content lives in the committed
// backend/src/data/whatsnew.json, not a live backlog dump — keep it in sync
// with status/BACKLOG.md by hand whenever a row flips.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { requireAnyToken } from '../auth.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_PATH = path.join(__dirname, '..', 'data', 'whatsnew.json');
const content = JSON.parse(readFileSync(DATA_PATH, 'utf8'));

export default async function whatsnewRoutes(app) {
  app.get('/api/whatsnew', { preHandler: requireAnyToken }, async () => content);
}
