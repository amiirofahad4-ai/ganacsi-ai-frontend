const jwt = require('jsonwebtoken');
const { sql } = require('./db');
const { fail } = require('./http');

const SECRET = process.env.JWT_SECRET;
if (!SECRET || SECRET === 'change-me') {
  console.error('JWT_SECRET is not set in .env. Generate one with:');
  console.error("  node -e \"console.log(require('crypto').randomBytes(48).toString('hex'))\"");
  process.exit(1);
}

const LOGIN_REQUIRED = 'Fadlan soo gal (login)';

/** Token carries the user id and token_version. Bumping users.token_version logs out every device. */
function signToken(user) {
  return jwt.sign({ uid: user.id, tv: user.token_version ?? 0 }, SECRET, { expiresIn: '30d' });
}

/** Sets req.user = { id, currency } or answers 401. */
async function requireAuth(req, res, next) {
  const m = /^Bearer\s+(.+)$/i.exec(req.get('authorization') || '');
  if (!m) fail(401, LOGIN_REQUIRED);

  let payload;
  try {
    payload = jwt.verify(m[1], SECRET);
  } catch {
    fail(401, LOGIN_REQUIRED);
  }
  if (!Number.isInteger(payload.uid)) fail(401, LOGIN_REQUIRED);

  const [u] = await sql`select id, currency, token_version from users where id = ${payload.uid}`;
  if (!u || (u.token_version ?? 0) !== (payload.tv ?? 0)) fail(401, LOGIN_REQUIRED);

  req.user = { id: u.id, currency: u.currency || 'USD' };
  next();
}

module.exports = { signToken, requireAuth };
