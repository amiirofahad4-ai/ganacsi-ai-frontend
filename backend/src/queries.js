// Queries shared by several routes (lists, reports, dashboard, insights).
// Every query is filtered by user_id.
const { sql } = require('./db');
const { range, likePattern, r2, money } = require('./http');

const PUBLIC_USER_COLUMNS = ['id', 'name', 'phone', 'business_name', 'business_type', 'currency', 'language', 'created_at'];

function listProducts(uid, { q = null, low = false, limit = null } = {}) {
  const text = q && q.trim();
  return sql`
    select * from products
    where user_id = ${uid}
    ${text ? sql`and concat_ws(' ', name, sku, category) ilike ${likePattern(text)}` : sql``}
    ${low ? sql`and quantity <= low_stock_threshold` : sql``}
    order by lower(name), id
    ${limit ? sql`limit ${limit}` : sql``}`;
}

function listCustomers(uid, { q = null, withDebt = false } = {}) {
  const text = q && q.trim();
  return sql`
    select * from customers
    where user_id = ${uid}
    ${text ? sql`and concat_ws(' ', name, phone) ilike ${likePattern(text)}` : sql``}
    ${withDebt ? sql`and balance > 0 order by balance desc, id` : sql`order by lower(name), id`}`;
}

/**
 * Sales with their items, customer_name and item_count (the shape the app expects).
 * `db` is `sql` or a transaction.
 */
function fetchSales(db, uid, { id = null, customerId = null, from = null, to = null, limit = 100 } = {}) {
  return db`
    select s.id, s.user_id, s.customer_id, s.total, s.cost_total, s.paid, s.payment_method, s.note, s.created_at,
           c.name as customer_name,
           coalesce(i.items, '[]'::json) as items,
           coalesce(i.item_count, 0) as item_count
    from sales s
    left join customers c on c.id = s.customer_id and c.user_id = s.user_id
    left join lateral (
      select json_agg(json_build_object(
               'id', si.id, 'product_id', si.product_id, 'name', si.name,
               'quantity', si.quantity, 'price', si.price, 'cost', si.cost
             ) order by si.id) as items,
             count(*) as item_count
      from sale_items si
      where si.sale_id = s.id
    ) i on true
    where s.user_id = ${uid}
    ${id != null ? db`and s.id = ${id}` : db``}
    ${customerId != null ? db`and s.customer_id = ${customerId}` : db``}
    ${from ? db`and s.created_at >= ${from}::timestamptz and s.created_at < ${to}::timestamptz` : db``}
    order by s.created_at desc, s.id desc
    limit ${limit}`;
}

/** Invoices with customer_name and customer_phone. */
function fetchInvoices(db, uid, { id = null, status = null } = {}) {
  return db`
    select i.id, i.user_id, i.customer_id, i.number, i.items, i.total, i.status, i.due_date, i.note, i.created_at,
           c.name as customer_name, c.phone as customer_phone
    from invoices i
    left join customers c on c.id = i.customer_id and c.user_id = i.user_id
    where i.user_id = ${uid}
    ${id != null ? db`and i.id = ${id}` : db``}
    ${status ? db`and i.status = ${status}` : db``}
    order by i.id desc`;
}

// ------------------------------------------------------------------ reports

async function summary(uid, period) {
  const r = range(period);
  const [x] = await sql`
    with s as (
      select count(*) as sales_count,
             coalesce(sum(total), 0) as revenue,
             coalesce(sum(cost_total), 0) as cost_of_goods,
             coalesce(sum(paid), 0) as cash_received
      from sales
      where user_id = ${uid} and created_at >= ${r.from}::timestamptz and created_at < ${r.to}::timestamptz
    ), e as (
      select coalesce(sum(amount), 0) as expenses
      from expenses
      where user_id = ${uid} and date >= ${r.fromDate}::date and date < ${r.toDate}::date
    ), c as (
      select count(*) as customers_with_debt, coalesce(sum(balance), 0) as customer_debt_total
      from customers where user_id = ${uid} and balance > 0
    ), p as (
      select count(*) filter (where quantity <= low_stock_threshold) as low_stock_count,
             coalesce(round(sum(quantity * coalesce(cost, 0)), 2), 0) as stock_value
      from products where user_id = ${uid}
    ), i as (
      select count(*) as unpaid_invoices_count, coalesce(sum(total), 0) as unpaid_invoices_total
      from invoices where user_id = ${uid} and status = 'unpaid'
    )
    select * from s, e, c, p, i`;

  return {
    period,
    sales_count: x.sales_count,
    revenue: x.revenue,
    cost_of_goods: x.cost_of_goods,
    gross_profit: r2(x.revenue - x.cost_of_goods),
    expenses: x.expenses,
    net_profit: r2(x.revenue - x.cost_of_goods - x.expenses),
    cash_received: x.cash_received,
    customer_debt_total: x.customer_debt_total,
    customers_with_debt: x.customers_with_debt,
    low_stock_count: x.low_stock_count,
    stock_value: x.stock_value,
    unpaid_invoices_total: x.unpaid_invoices_total,
    unpaid_invoices_count: x.unpaid_invoices_count,
  };
}

function topProducts(uid, period, limit) {
  const r = range(period);
  return sql`
    select si.name,
           sum(si.quantity) as quantity,
           round(sum(si.quantity * si.price), 2) as revenue,
           round(sum(si.quantity * (si.price - coalesce(si.cost, 0))), 2) as profit
    from sale_items si
    join sales s on s.id = si.sale_id
    where s.user_id = ${uid} and s.created_at >= ${r.from}::timestamptz and s.created_at < ${r.to}::timestamptz
    group by si.name
    order by revenue desc, si.name
    limit ${limit}`;
}

/** One row per day for the last `days` days (oldest first), including empty days. */
function daily(uid, days) {
  return sql`
    select d.day,
           coalesce((select sum(total) from sales
                     where user_id = ${uid} and created_at >= d.day and created_at < d.day + 1), 0) as revenue,
           (select count(*) from sales
             where user_id = ${uid} and created_at >= d.day and created_at < d.day + 1) as count,
           coalesce((select sum(amount) from expenses
                     where user_id = ${uid} and date = d.day), 0) as expenses
    from (select current_date - g.k as day from generate_series(${days - 1}::int, 0, -1) as g(k)) d
    order by d.day`;
}

function expensesByCategory(uid, period) {
  const r = range(period);
  return sql`
    select category, sum(amount) as total, count(*) as count
    from expenses
    where user_id = ${uid} and date >= ${r.fromDate}::date and date < ${r.toDate}::date
    group by category
    order by total desc, category`;
}

/** Short tips shown on the dashboard. */
async function insights(uid, currency) {
  const [low, [debt], week, [overdue]] = await Promise.all([
    listProducts(uid, { low: true }),
    sql`select count(*) as n, coalesce(sum(balance), 0) as total from customers where user_id = ${uid} and balance > 0`,
    summary(uid, 'week'),
    sql`select count(*) as n from invoices
        where user_id = ${uid} and status = 'unpaid' and due_date is not null and due_date < current_date`,
  ]);

  const tips = [];
  if (low.length) {
    const names = low.slice(0, 3).map((p) => p.name).join(', ');
    tips.push({ type: 'stock', text: `${low.length} alaab ayaa dhammaanaya: ${names}${low.length > 3 ? '...' : ''}` });
  }
  if (debt.n > 0) {
    tips.push({ type: 'debt', text: `${debt.n} macmiil ayaa deyn kugu leh, wadar ${money(debt.total, currency)}` });
  }
  if (week.sales_count > 0 && week.expenses > week.gross_profit) {
    tips.push({ type: 'warning', text: "Toddobaadkan kharashku wuu ka badan yahay faa'iidada guud" });
  }
  if (overdue.n > 0) {
    tips.push({ type: 'invoice', text: `${overdue.n} invoice ayaa waqtigoodii dhaafay oo aan la bixin` });
  }
  return tips;
}

module.exports = {
  PUBLIC_USER_COLUMNS,
  listProducts, listCustomers, fetchSales, fetchInvoices,
  summary, topProducts, daily, expensesByCategory, insights,
};
