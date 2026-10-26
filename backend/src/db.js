require('dotenv').config({ quiet: true });
const postgres = require('postgres');

const REQUIRED_TABLES = ['users', 'products', 'customers', 'sales', 'sale_items', 'expenses', 'invoices', 'chat_messages'];

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is not set. Copy .env.example to .env and put your database password in it.');
  process.exit(1);
}

// Postgres type OIDs
const OID = { int8: 20, numeric: 1700, date: 1082, timestamp: 1114, timestamptz: 1184, json: 114, jsonb: 3802 };

const sql = postgres(process.env.DATABASE_URL, {
  max: Number(process.env.DB_POOL_SIZE) || 10,
  connect_timeout: 10,
  idle_timeout: 30,
  onnotice: () => {},
  // Session settings sent on every new connection
  connection: { TimeZone: 'UTC', DateStyle: 'ISO, YMD', application_name: 'ganacsi-ai-backend' },
  // A missing value is sent as NULL instead of throwing
  transform: { undefined: null },
  types: {
    // NUMERIC and BIGINT (e.g. COUNT) come back as JS numbers, not strings
    numeric: { to: OID.numeric, from: [OID.numeric], serialize: (x) => String(x), parse: (x) => Number(x) },
    bigint: { to: OID.int8, from: [OID.int8], serialize: (x) => String(x), parse: (x) => Number(x) },
    // TIMESTAMPTZ -> 'YYYY-MM-DD HH:MM:SS' (UTC, because the session TimeZone is UTC).
    // Strings are sent as-is, so 'YYYY-MM-DD HH:MM:SS' is read as UTC by the server.
    timestamptz: {
      to: OID.timestamptz,
      from: [OID.timestamptz, OID.timestamp],
      serialize: (x) => (x instanceof Date ? x.toISOString() : String(x)),
      parse: (x) => x.slice(0, 19),
    },
    // DATE -> 'YYYY-MM-DD'
    date: { to: OID.date, from: [OID.date], serialize: (x) => String(x), parse: (x) => x },
    // JSONB: objects are stringified, strings are assumed to be JSON already
    jsonb: {
      to: OID.jsonb,
      from: [OID.jsonb, OID.json],
      serialize: (x) => (typeof x === 'string' ? x : JSON.stringify(x)),
      parse: (x) => JSON.parse(x),
    },
  },
});

/** Runs a test query. Returns { database, tables, missing, timezone }. Throws if the database can't be reached. */
async function checkConnection() {
  const [info] = await sql`
    select current_database() as database,
           current_setting('TimeZone') as timezone,
           (select count(*) from information_schema.tables
             where table_schema = 'public' and table_type = 'BASE TABLE') as tables`;
  const found = await sql`
    select table_name from information_schema.tables
    where table_schema = 'public' and table_name in ${sql(REQUIRED_TABLES)}`;
  const have = new Set(found.map((r) => r.table_name));
  return { ...info, missing: REQUIRED_TABLES.filter((t) => !have.has(t)) };
}

/** Turns a connection error into a message a person can act on. */
function describeDbError(e) {
  const url = safeUrl(process.env.DATABASE_URL);
  switch (e.code) {
    case 'ECONNREFUSED':
      return `Could not connect to PostgreSQL at ${url}. Is the PostgreSQL server running?`;
    case 'ENOTFOUND':
    case 'EAI_AGAIN':
      return `Database host not found in DATABASE_URL (${url}).`;
    case 'CONNECT_TIMEOUT':
      return `Timed out connecting to PostgreSQL at ${url}.`;
    case '28P01':
      return 'PostgreSQL rejected the password. Check the password in DATABASE_URL in your .env file.';
    case '28000':
      return `PostgreSQL rejected the login (${e.message}). Check the user name in DATABASE_URL.`;
    case '3D000':
      return `${e.message}. Check the database name at the end of DATABASE_URL.`;
    default:
      return `Database connection failed: ${e.message}${e.code ? ` (${e.code})` : ''}`;
  }
}

/** DATABASE_URL with the password hidden, for log messages. */
function safeUrl(raw) {
  try {
    const u = new URL(raw);
    if (u.password) u.password = '****';
    return u.toString();
  } catch {
    return '(invalid DATABASE_URL)';
  }
}

module.exports = { sql, checkConnection, describeDbError, REQUIRED_TABLES };
