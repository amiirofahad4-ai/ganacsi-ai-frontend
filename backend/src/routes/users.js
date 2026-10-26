// users: register, login, profile. Mounted at /api
const express = require('express');
const bcrypt = require('bcryptjs');
const { sql } = require('../db');
const { signToken, requireAuth } = require('../auth');
const { fail, reqStr, optStr } = require('../http');
const { PUBLIC_USER_COLUMNS } = require('../queries');
const { createRateLimiter } = require('../rate_limit');

const router = express.Router();
const registrationRateLimit = createRateLimiter({
  limit: 5,
  windowMs: 60 * 60 * 1000,
  message: 'Diiwaangelin badan ayaa laga sameeyay cinwaankan IP-ga. Saacad kadib isku day',
});
const loginRateLimit = createRateLimiter({
  limit: 10,
  windowMs: 15 * 60 * 1000,
  message: 'Login isku day badan ayaa dhacay. 15 daqiiqo kadib isku day',
});

const normalizePhone = (v) => (typeof v === 'string' || typeof v === 'number' ? String(v) : '').replace(/\s+/g, '');

async function publicUser(id) {
  const [u] = await sql`select ${sql(PUBLIC_USER_COLUMNS)} from users where id = ${id}`;
  if (!u) fail(401, 'Fadlan soo gal (login)');
  return u;
}

router.post('/auth/register', registrationRateLimit, async (req, res) => {
  const b = req.body || {};
  const phone = normalizePhone(b.phone);
  if (!/^\+?\d{7,15}$/.test(phone)) fail(400, 'Lambarka telefoonka sax ma aha');
  const password = typeof b.password === 'string' ? b.password : '';
  if (password.length < 6) fail(400, 'Password-ku waa inuu ahaadaa ugu yaraan 6 xaraf');
  if (password.length > 72) fail(400, 'Password-ku aad buu u dheer yahay');
  const name = reqStr(b.name, 'Magacaaga');
  const businessName = reqStr(b.business_name, 'Magaca ganacsiga');

  const [exists] = await sql`select 1 from users where phone = ${phone}`;
  if (exists) fail(409, 'Lambarkan horay ayaa loo diiwaangeliyay');

  const hash = await bcrypt.hash(password, 10);
  let user;
  try {
    [user] = await sql`
      insert into users (name, phone, password_hash, business_name, business_type, currency, language, token_version, created_at)
      values (${name}, ${phone}, ${hash}, ${businessName}, ${optStr(b.business_type) ?? 'general'},
              ${optStr(b.currency) ?? 'USD'}, ${optStr(b.language) ?? 'so'}, 0, now())
      returning id, token_version`;
  } catch (e) {
    if (e.code === '23505') fail(409, 'Lambarkan horay ayaa loo diiwaangeliyay');
    throw e;
  }
  res.status(201).json({ token: signToken(user), user: await publicUser(user.id) });
});

router.post('/auth/login', loginRateLimit, async (req, res) => {
  const b = req.body || {};
  const phone = normalizePhone(b.phone);
  const password = typeof b.password === 'string' ? b.password : '';
  const [u] = phone ? await sql`select id, password_hash, token_version from users where phone = ${phone}` : [];

  let ok = false;
  if (u && u.password_hash) {
    try {
      ok = await bcrypt.compare(password, u.password_hash);
    } catch {
      ok = false;
    }
  }
  if (!ok) fail(401, 'Telefoonka ama password-ka waa khalad');
  res.json({ token: signToken(u), user: await publicUser(u.id) });
});

router.get('/me', requireAuth, async (req, res) => {
  res.json(await publicUser(req.user.id));
});

router.put('/me', requireAuth, async (req, res) => {
  const b = req.body || {};
  const updates = {};
  for (const k of ['name', 'business_name', 'business_type', 'currency', 'language']) {
    if (k in b) updates[k] = reqStr(b[k], k);
  }
  if (Object.keys(updates).length) {
    await sql`update users set ${sql(updates)} where id = ${req.user.id}`;
  }
  res.json(await publicUser(req.user.id));
});

module.exports = router;
