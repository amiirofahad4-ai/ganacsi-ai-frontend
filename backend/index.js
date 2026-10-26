require('dotenv').config({ quiet: true });
const express = require('express');
const cors = require('cors');

const { sql, checkConnection, describeDbError } = require('./src/db');
const { requireAuth } = require('./src/auth');
const { notFound, errorHandler } = require('./src/http');
const reports = require('./src/routes/reports');

const app = express();
app.disable('x-powered-by');
app.use(cors());
app.use(express.json({ limit: '1mb' }));

app.get('/api/health', async (req, res) => {
  try {
    await sql`select 1`;
    res.json({ ok: true, database: 'postgresql' });
  } catch (e) {
    res.status(503).json({ ok: false, database: 'postgresql', error: describeDbError(e) });
  }
});

app.use('/api', require('./src/routes/users')); // /api/auth/*, /api/me
app.use('/api/products', require('./src/routes/products'));
app.use('/api/customers', require('./src/routes/customers'));
app.use('/api/sales', require('./src/routes/sales'));
app.use('/api/expenses', require('./src/routes/expenses'));
app.use('/api/invoices', require('./src/routes/invoices'));
app.use('/api/ai', require('./src/routes/chat_messages'));
app.use('/api/reports', reports.router);
app.get('/api/dashboard', requireAuth, reports.dashboard);

app.use(notFound);
app.use(errorHandler);

async function start() {
  try {
    const info = await checkConnection();
    console.log(`Connected to database ${info.database} — ${info.tables} tables`);
    if (info.timezone !== 'UTC') console.warn(`Warning: session TimeZone is ${info.timezone}, expected UTC`);
    if (info.missing.length) console.warn(`Warning: missing tables: ${info.missing.join(', ')}`);
    const gemini = require('./src/ai/gemini');
    if (gemini.isConfigured()) console.log(`AI: Gemini diyaar ✓ (${gemini.model()})`);
    else console.warn('AI: GEMINI_API_KEY lama dhigin. /api/ai/chat wuxuu soo celin doonaa 503');
  } catch (e) {
    console.error(describeDbError(e));
    await sql.end({ timeout: 1 }).catch(() => {});
    process.exit(1);
  }

  const port = Number(process.env.PORT) || 3000;
  const host = process.env.HOST || '0.0.0.0';
  const server = app.listen(port, host, () => {
    console.log(`Ganacsi AI backend listening on http://localhost:${port}`);
  });
  server.on('error', (e) => {
    console.error(e.code === 'EADDRINUSE' ? `Port ${port} is already in use. Set another PORT in .env.` : e);
    process.exit(1);
  });

  const stop = () => server.close(() => sql.end({ timeout: 5 }).finally(() => process.exit(0)));
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

if (require.main === module) start();

module.exports = app;
