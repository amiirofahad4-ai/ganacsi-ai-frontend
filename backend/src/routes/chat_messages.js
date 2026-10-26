// chat_messages: AI assistant chat (Google Gemini). Mounted at /api/ai
const express = require('express');
const { sql } = require('../db');
const { requireAuth } = require('../auth');
const { fail } = require('../http');
const { insights } = require('../queries');
const gemini = require('../ai/gemini');

const router = express.Router();
router.use(requireAuth);

// Simple per-user limit: 10 chat requests per minute (in memory, per server process)
const LIMIT = 10;
const WINDOW_MS = 60_000;
const recent = new Map(); // user id -> timestamps of recent requests

function checkRateLimit(uid) {
  const now = Date.now();
  const list = (recent.get(uid) || []).filter((t) => now - t < WINDOW_MS);
  if (list.length >= LIMIT) fail(429, 'Fariimo badan ayaad dirtay, daqiiqad kadib isku day');
  list.push(now);
  recent.set(uid, list);
}

// Drop idle users so the map doesn't grow forever
setInterval(() => {
  const now = Date.now();
  for (const [uid, list] of recent) if (!list.some((t) => now - t < WINDOW_MS)) recent.delete(uid);
}, WINDOW_MS).unref();

// Body: { message }  ->  { reply, actions }
router.post('/chat', async (req, res) => {
  const t0 = Date.now();
  try {
    if (!gemini.isConfigured()) fail(503, 'AI lama habeyn: GEMINI_API_KEY ku dar .env');
    const raw = (req.body || {}).message;
    const message = typeof raw === 'string' ? raw.trim() : '';
    if (!message) fail(400, 'message waa loo baahan yahay');
    if (message.length > 4000) fail(400, 'Fariinta aad bay u dheer tahay (ugu badnaan 4000 xaraf)');
    checkRateLimit(req.user.id);

    res.json(await gemini.chat(req.user.id, message));
  } catch (e) {
    console.log(`[AI user ${req.user.id}] responded ${e.status || 500} after ${Date.now() - t0}ms: ${e.message}`);
    throw e;
  }
});

// Last 50 messages, oldest first
router.get('/history', async (req, res) => {
  res.json(await sql`
    select id, role, content, created_at from (
      select id, role, content, created_at from chat_messages
      where user_id = ${req.user.id}
      order by id desc
      limit 50
    ) t
    order by id`);
});

router.delete('/history', async (req, res) => {
  await sql`delete from chat_messages where user_id = ${req.user.id}`;
  res.json({ ok: true });
});

router.get('/insights', async (req, res) => {
  res.json(await insights(req.user.id, req.user.currency));
});

module.exports = router;
