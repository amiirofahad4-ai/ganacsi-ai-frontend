// Tools the Gemini model can call. Every query is filtered by the logged-in user's id
// and uses parameterized SQL. NUMERIC/COUNT values come back as numbers (see src/db.js).
const { sql } = require('../db');
const { fail, reqStr, optStr, reqNum, range, r2, likePattern } = require('../http');
const { topProducts, listProducts, listCustomers, expensesByCategory } = require('../queries');

const PERIODS = ['today', 'week', 'month', 'year'];
const EXPENSE_CATEGORIES = ['rent', 'salary', 'utilities', 'transport', 'stock_purchase', 'marketing', 'other'];

const periodParam = {
  type: 'object',
  properties: {
    period: {
      type: 'string',
      enum: PERIODS,
      description: 'today; week = last 7 days; month = last 30 days; year = last 365 days',
    },
  },
  required: ['period'],
};

/** Declarations sent to Gemini in tools[0].functionDeclarations */
const declarations = [
  {
    name: 'get_sales_summary',
    description: 'Sales totals for a period: number of sales, revenue, gross profit, expenses, net profit, and new debt (unpaid part of sales).',
    parameters: periodParam,
  },
  {
    name: 'get_top_products',
    description: 'Top 5 best-selling products in a period by revenue, with quantity sold.',
    parameters: periodParam,
  },
  {
    name: 'get_low_stock',
    description: 'Products whose stock quantity is at or below their low-stock threshold.',
  },
  {
    name: 'search_products',
    description: 'Search products by name, SKU or category, or list all products when query is empty. Returns price, cost, quantity in stock and unit (max 20).',
    parameters: {
      type: 'object',
      properties: { query: { type: 'string', description: 'Part of the product name, SKU or category. Empty string = all products.' } },
    },
  },
  {
    name: 'get_debtors',
    description: 'Customers who owe money (balance > 0), largest debt first.',
  },
  {
    name: 'get_expenses_by_category',
    description: 'Total expenses per category for a period.',
    parameters: periodParam,
  },
  {
    name: 'record_expense',
    description: 'Save a new expense for today. Only call this when the user explicitly asks to record an expense and both amount and category are known.',
    parameters: {
      type: 'object',
      properties: {
        category: { type: 'string', enum: EXPENSE_CATEGORIES },
        amount: { type: 'number', description: 'Amount in the business currency, greater than 0' },
        note: { type: 'string', description: 'Short description, e.g. "Gaadiid alaab"' },
      },
      required: ['category', 'amount'],
    },
  },
];

function period(args) {
  const p = args && args.period;
  if (!PERIODS.includes(p)) fail(400, `period must be one of: ${PERIODS.join(', ')}`);
  return p;
}

const handlers = {
  async get_sales_summary(uid, args) {
    const p = period(args);
    const r = range(p);
    const [[s], [e]] = await Promise.all([
      sql`
        select count(*) as sales_count,
               coalesce(sum(total), 0) as revenue,
               coalesce(sum(total - coalesce(cost_total, 0)), 0) as gross_profit,
               coalesce(sum(total - paid), 0) as new_debt
        from sales
        where user_id = ${uid} and created_at >= ${r.from}::timestamptz and created_at < ${r.to}::timestamptz`,
      sql`
        select coalesce(sum(amount), 0) as expenses
        from expenses
        where user_id = ${uid} and date >= ${r.fromDate}::date and date < ${r.toDate}::date`,
    ]);
    return {
      period: p,
      from: r.fromDate,
      sales_count: s.sales_count,
      revenue: s.revenue,
      gross_profit: s.gross_profit,
      expenses: e.expenses,
      net_profit: r2(s.gross_profit - e.expenses),
      new_debt: s.new_debt,
    };
  },

  async get_top_products(uid, args) {
    const rows = await topProducts(uid, period(args), 5);
    return rows.map((x) => ({ name: x.name, quantity: x.quantity, revenue: x.revenue }));
  },

  async get_low_stock(uid) {
    const rows = await listProducts(uid, { low: true, limit: 50 });
    return rows.map((p) => ({ name: p.name, quantity: p.quantity, low_stock_threshold: p.low_stock_threshold, unit: p.unit }));
  },

  async search_products(uid, args) {
    const q = optStr(args && args.query);
    return sql`
      select id, name, price, cost, quantity, unit
      from products
      where user_id = ${uid}
      ${q ? sql`and concat_ws(' ', name, sku, category) ilike ${likePattern(q)}` : sql``}
      order by lower(name), id
      limit 20`;
  },

  async get_debtors(uid) {
    const rows = await listCustomers(uid, { withDebt: true });
    return rows.map((c) => ({ name: c.name, phone: c.phone, balance: c.balance }));
  },

  async get_expenses_by_category(uid, args) {
    const rows = await expensesByCategory(uid, period(args));
    return rows.map((x) => ({ category: x.category, total: x.total }));
  },

  async record_expense(uid, args) {
    const a = args || {};
    const category = reqStr(a.category, 'category');
    if (!EXPENSE_CATEGORIES.includes(category)) fail(400, `category must be one of: ${EXPENSE_CATEGORIES.join(', ')}`);
    const amount = reqNum(a.amount, 'amount', 0.01);
    const [expense] = await sql`
      insert into expenses (user_id, category, amount, note, date, created_at)
      values (${uid}, ${category}, ${amount}, ${optStr(a.note)}, current_date, now())
      returning id, category, amount, note, date, created_at`;
    return { saved: true, expense };
  },
};

/** Tools that change data. Their results are returned to the app in `actions`. */
const WRITE_TOOLS = new Set(['record_expense']);

/** Runs a tool. Never throws: errors go back to the model as { error }. */
async function runTool(uid, name, args) {
  const fn = handlers[name];
  if (!fn) return { error: `Unknown tool: ${name}` };
  try {
    return await fn(uid, args || {});
  } catch (e) {
    if (!e.status) console.error(`[AI tool ${name}]`, e.message);
    return { error: e.status ? e.message : 'Database error while running this tool' };
  }
}

module.exports = { declarations, runTool, WRITE_TOOLS };
