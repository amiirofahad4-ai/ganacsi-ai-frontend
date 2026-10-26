// Checks the database connection and lists the tables the backend uses.
// Read-only: it never creates or changes anything.
// Run: npm run check-db
const { sql, checkConnection, describeDbError, REQUIRED_TABLES } = require('../src/db');

(async () => {
  try {
    const info = await checkConnection();
    console.log(`Connected to database ${info.database} — ${info.tables} tables`);
    console.log(`Session TimeZone: ${info.timezone}`);

    for (const t of REQUIRED_TABLES) {
      if (info.missing.includes(t)) {
        console.log(`  ✗ ${t.padEnd(14)} MISSING`);
        continue;
      }
      // sql(t) is an escaped identifier; t comes from the fixed list above
      const [{ n }] = await sql`select count(*) as n from ${sql(t)}`;
      console.log(`  ✓ ${t.padEnd(14)} ${n} rows`);
    }

    const [sample] = await sql`select now() as now, current_date as today, 12.50::numeric as num, count(*) as cnt from users`;
    console.log('Type check:', sample);
    process.exitCode = info.missing.length ? 1 : 0;
  } catch (e) {
    console.error(describeDbError(e));
    process.exitCode = 1;
  } finally {
    await sql.end({ timeout: 1 }).catch(() => {});
  }
})();
