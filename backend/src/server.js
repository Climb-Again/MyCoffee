// MyCoffee backend entrypoint.
//
// build() wires the Fastify app + plugins + routes.
// start() binds the port BEFORE running migrations (background, with retry backoff)
// so Railway's healthcheck passes immediately and stops aren't mislabeled as crashes.
import Fastify from 'fastify';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import multipart from '@fastify/multipart';
import compress from '@fastify/compress';
import etag from '@fastify/etag';

import { config } from './config.js';
import { healthcheck } from './db.js';
import { runMigrations } from './migrate.js';

import statusRoutes from './routes/status.js';
import ingestRoutes from './routes/ingest.js';
import briefRoutes from './routes/brief.js';
import configRoutes from './routes/config.js';

export async function build() {
  const app = Fastify({
    logger: {
      level: config.env === 'production' ? 'info' : 'debug',
    },
    trustProxy: true,
    bodyLimit: config.maxUploadBytes,
  });

  // Security headers. CSP is off — this is a JSON API, not a web page host.
  await app.register(helmet, { contentSecurityPolicy: false });

  await app.register(rateLimit, {
    max: config.rateLimitMax,
    timeWindow: config.rateLimitWindowMs,
  });

  await app.register(multipart, {
    limits: { fileSize: config.maxUploadBytes },
  });

  await app.register(compress, { threshold: 1024 });
  await app.register(etag);

  // Unauthenticated liveness probe (Railway healthcheckPath).
  app.get('/health', async () => {
    const db = await healthcheck();
    return { ok: true, db, service: 'mycoffee-api' };
  });

  // Domain routes (skeleton — grow per the product brief).
  await app.register(statusRoutes);
  await app.register(ingestRoutes);
  await app.register(briefRoutes);
  await app.register(configRoutes);

  return app;
}

// Run migrations with retry backoff, in the background, after the port is bound.
async function migrateWithRetry(logger) {
  const delays = [1, 2, 4, 8, 16]; // seconds
  for (let attempt = 0; attempt <= delays.length; attempt++) {
    try {
      const { applied } = await runMigrations({ log: logger });
      logger.info(`[boot] migrations ok (${applied.length} applied)`);
      return;
    } catch (err) {
      const wait = delays[attempt];
      if (wait === undefined) {
        logger.error(`[boot] migrations failed permanently: ${err.message}`);
        return;
      }
      logger.warn(`[boot] migration attempt ${attempt + 1} failed: ${err.message}; retrying in ${wait}s`);
      await new Promise((r) => setTimeout(r, wait * 1000));
    }
  }
}

export async function start() {
  if (!config.databaseUrl) {
    console.error('[boot] DATABASE_URL is required but not set. Exiting.');
    process.exit(1);
  }

  const app = await build();

  // Bind the port FIRST so healthchecks pass; migrate in the background.
  try {
    await app.listen({ host: config.host, port: config.port });
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }

  migrateWithRetry(app.log);

  // Graceful shutdown.
  const shutdown = async (signal) => {
    app.log.info(`[boot] ${signal} received, closing`);
    try {
      await app.close();
    } finally {
      process.exit(0);
    }
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  return app;
}

// Only auto-start when run directly (not when imported by tests).
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const isMain =
  process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (isMain) {
  start();
}
