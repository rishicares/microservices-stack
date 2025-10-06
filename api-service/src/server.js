import express from 'express';
import pkg from 'pg';
const { Pool } = pkg;

const app = express();
const port = process.env.PORT || 3000;

function buildDatabaseUrl() {
  const url = process.env.DATABASE_URL;
  if (url && !url.includes('$(')) return url;
  const user = process.env.POSTGRES_USER || 'app';
  const password = process.env.POSTGRES_PASSWORD || 'app';
  const host = process.env.POSTGRES_HOST || 'postgres.app.svc.cluster.local';
  const database = process.env.POSTGRES_DB || 'app';
  const dbPort = process.env.POSTGRES_PORT || '5432';
  return `postgres://${user}:${password}@${host}:${dbPort}/${database}`;
}

const pool = new Pool({
  connectionString: buildDatabaseUrl(),
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

app.get('/live', (_req, res) => {
  res.status(200).json({ status: 'alive' });
});

app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ok' });
  } catch (err) {
    res.status(500).json({ status: 'error', error: err.message });
  }
});

app.get('/api/time', async (_req, res) => {
  try {
    const result = await pool.query('SELECT NOW() as now');
    res.json({ now: result.rows[0].now });
  } catch (err) {
    res.status(503).json({ status: 'error', error: (err && err.message) || 'database unavailable' });
  }
});

const server = app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`api-service listening on port ${port}`);
});

function shutdown() {
  server.close(() => {
    pool.end().finally(() => process.exit(0));
  });
  // force exit if not closed in time
  setTimeout(() => process.exit(0), 5000).unref();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
