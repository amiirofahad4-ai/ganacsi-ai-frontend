// Shared helpers: errors, input validation, date ranges and formatting.
// Error messages are in Somali because the app shows them to the user.

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function fail(status, message) {
  throw new HttpError(status, message);
}

// ------------------------------------------------------------------ validation

function optNum(v, field, min = 0) {
  if (v == null || (typeof v === 'string' && v.trim() === '')) return null;
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN;
  if (!Number.isFinite(n) || n < min) fail(400, `${field} waa inuu noqdaa tiro sax ah`);
  return n;
}

function reqNum(v, field, min = 0) {
  const n = optNum(v, field, min);
  if (n == null) fail(400, `${field} waa loo baahan yahay`);
  return n;
}

function optStr(v) {
  if (typeof v !== 'string' && typeof v !== 'number') return null;
  const s = String(v).trim();
  return s === '' ? null : s;
}

function reqStr(v, field) {
  const s = optStr(v);
  if (s == null) fail(400, `${field} waa loo baahan yahay`);
  return s;
}

/** Integer that fits in a Postgres INT, or null. */
function toInt(v) {
  const n = typeof v === 'number' ? v : typeof v === 'string' && /^\s*\d+\s*$/.test(v) ? Number(v) : NaN;
  return Number.isInteger(n) && n >= 0 && n <= 2147483647 ? n : null;
}

/** :id route parameter. Anything that isn't a valid id is a 404. */
function parseId(v, notFound) {
  const id = /^\d{1,10}$/.test(v) ? toInt(v) : null;
  if (id == null) fail(404, notFound);
  return id;
}

/** Query string value as a string (ignores repeated params). */
function queryStr(v) {
  return typeof v === 'string' ? v : null;
}

function queryInt(v, def, min, max) {
  const n = toInt(queryStr(v));
  return Math.min(max, Math.max(min, n ?? def));
}

function isDate(s) {
  return typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
}

/** Escapes % _ \ so user text is matched literally in ILIKE. */
function likePattern(q) {
  return `%${q.replace(/[\\%_]/g, '\\$&')}%`;
}

// ------------------------------------------------------------------ periods

const DAY = 86400000;
const PERIODS = ['today', 'yesterday', 'week', 'month', 'year', 'all'];

/** 'YYYY-MM-DD HH:MM:SS' in UTC */
function fmt(ms) {
  return new Date(ms).toISOString().slice(0, 19).replace('T', ' ');
}

/** Time range for a period, same rules as the app's demo backend. `to` is exclusive. */
function range(period) {
  const now = new Date();
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  let from;
  let to = today + DAY;
  switch (period) {
    case 'today': from = today; break;
    case 'yesterday': from = today - DAY; to = today; break;
    case 'week': from = today - 6 * DAY; break;
    case 'month': from = today - 29 * DAY; break;
    case 'year': from = today - 364 * DAY; break;
    case 'all': from = Date.UTC(2000, 0, 1); break;
    default: fail(400, `period waa: ${PERIODS.join(', ')}`);
  }
  return { from: fmt(from), to: fmt(to), fromDate: fmt(from).slice(0, 10), toDate: fmt(to).slice(0, 10) };
}

// ------------------------------------------------------------------ numbers

const r2 = (v) => Math.round(v * 100) / 100;
const r3 = (v) => Math.round(v * 1000) / 1000;

/** 3 -> '3', 2.5 -> '2.50' (like the app) */
const qty = (v) => (Number.isInteger(v) ? String(v) : Number(v).toFixed(2));

const SYMBOLS = { USD: '$', SOS: 'Sh ', KES: 'KSh ', ETB: 'Br ', EUR: '€' };

/** Money text in the user's currency, like the app's money() */
function money(v, currency = 'USD') {
  const symbol = SYMBOLS[currency] ?? `${currency} `;
  const digits = currency === 'SOS' ? 0 : 2;
  const s = Math.abs(v).toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits });
  return `${v < 0 ? '-' : ''}${symbol}${s}`;
}

// ------------------------------------------------------------------ error handling

// PostgreSQL error code -> HTTP status + message
const PG_ERRORS = {
  '23505': [409, 'Xogtan horay ayay u jirtaa'], // unique_violation
  '23503': [409, 'Xog ku xiran lama helin ama weli waa la isticmaalayaa'], // foreign_key_violation
  '23514': [400, 'Xogtu ma buuxinayso shuruudaha (tusaale: tiro taban ama qiime aan la ogolayn)'], // check_violation
  '23502': [400, 'Field waa loo baahan yahay'], // not_null_violation
  '22P02': [400, 'Qiime khaldan ayaa la soo diray'], // invalid_text_representation
  '22003': [400, 'Tiradu aad bay u weyn tahay'], // numeric_value_out_of_range
  '22001': [400, 'Qoraalku aad buu u dheer yahay'], // string_data_right_truncation
  '22007': [400, 'Taariikh khaldan'], // invalid_datetime_format
  '22008': [400, 'Taariikh khaldan'], // datetime_field_overflow
  '40001': [409, 'Isku dhac ayaa dhacay, mar kale isku day'], // serialization_failure
  '40P01': [409, 'Isku dhac ayaa dhacay, mar kale isku day'], // deadlock_detected
};

function notFound(req, res) {
  res.status(404).json({ error: `Lama helin: ${req.method} ${req.path}` });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  if (err instanceof HttpError) return res.status(err.status).json({ error: err.message });
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'JSON-ka la soo diray waa khalad' });
  if (err.type === 'entity.too.large') return res.status(413).json({ error: 'Xogta la soo diray aad bay u weyn tahay' });

  const pg = PG_ERRORS[err.code];
  if (pg) {
    const [status, message] = pg;
    const body = { error: err.code === '23502' && err.column_name ? `${message}: ${err.column_name}` : message, code: err.code };
    if (err.constraint_name) body.constraint = err.constraint_name;
    return res.status(status).json(body);
  }

  console.error(`[${req.method} ${req.originalUrl}]`, err);
  res.status(500).json({ error: 'Cillad ayaa ka dhacday server-ka' });
}

module.exports = {
  HttpError, fail,
  optNum, reqNum, optStr, reqStr, toInt, parseId, queryStr, queryInt, isDate, likePattern,
  range, fmt, r2, r3, qty, money,
  notFound, errorHandler,
};
