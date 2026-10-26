// sales + sale_items. Mounted at /api/sales
const express = require('express');
const { sql } = require('../db');
const { requireAuth } = require('../auth');
const { fail, optStr, reqNum, optNum, toInt, parseId, queryStr, queryInt, range, r2, r3, qty } = require('../http');
const { fetchSales } = require('../queries');

const router = express.Router();
router.use(requireAuth);

const NOT_FOUND = 'Iibkan lama helin';
const PAYMENT_METHODS = ['cash', 'evc_plus', 'zaad', 'sahal', 'edahab', 'bank', 'credit'];

router.get('/', async (req, res) => {
  const r = range(queryStr(req.query.period) ?? 'month');
  const limit = queryInt(req.query.limit, 100, 1, 500);
  res.json(await fetchSales(sql, req.user.id, { from: r.from, to: r.to, limit }));
});

router.get('/:id', async (req, res) => {
  const [s] = await fetchSales(sql, req.user.id, { id: parseId(req.params.id, NOT_FOUND), limit: 1 });
  if (!s) fail(404, NOT_FOUND);
  res.json(s);
});

/**
 * Body: { items: [{ product_id, quantity, price? }], customer_id?, paid?, payment_method?, note? }
 * One transaction: lock products, check stock, insert sale + items, reduce stock,
 * add unpaid part (total - paid) to the customer's balance.
 */
router.post('/', async (req, res) => {
  const uid = req.user.id;
  const b = req.body || {};

  // 1) Validate input before touching the database
  if (!Array.isArray(b.items) || b.items.length === 0) fail(400, 'items waa loo baahan yahay');
  if (b.items.length > 200) fail(400, 'Alaab aad u badan ayaa hal iib ku jirta');
  const lines = b.items.map((raw) => {
    const it = raw && typeof raw === 'object' ? raw : {};
    const productId = toInt(it.product_id);
    if (productId == null) fail(404, 'Alaabtan lama helin');
    return { productId, quantity: reqNum(it.quantity, 'quantity', 0.001), price: optNum(it.price, 'price') };
  });
  const hasCustomer = b.customer_id != null && b.customer_id !== '';
  const customerId = hasCustomer ? toInt(b.customer_id) : null;
  if (hasCustomer && customerId == null) fail(404, 'Macmiilkan lama helin');
  const paymentMethod = optStr(b.payment_method) ?? 'cash';
  if (!PAYMENT_METHODS.includes(paymentMethod)) fail(400, `payment_method waa: ${PAYMENT_METHODS.join(', ')}`);
  const paidInput = optNum(b.paid, 'paid');
  const note = optStr(b.note);

  // 2) Transaction
  const saleId = await sql.begin(async (tx) => {
    // Lock this user's products in id order (avoids deadlocks between two sales)
    const ids = [...new Set(lines.map((l) => l.productId))].sort((x, y) => x - y);
    const rows = await tx`
      select id, name, price, cost, quantity from products
      where user_id = ${uid} and id in ${tx(ids)}
      order by id
      for update`;
    const byId = new Map(rows.map((p) => [p.id, p]));

    const need = new Map();
    const items = [];
    let total = 0;
    let cost = 0;
    for (const l of lines) {
      const p = byId.get(l.productId);
      if (!p) fail(404, 'Alaabtan lama helin');
      const n = (need.get(p.id) ?? 0) + l.quantity;
      need.set(p.id, n);
      if (n > p.quantity + 1e-9) fail(400, `Stock kuma filna: ${p.name} (waxaa jira ${qty(p.quantity)})`);
      const price = l.price ?? p.price;
      const unitCost = p.cost ?? 0;
      total += l.quantity * price;
      cost += l.quantity * unitCost;
      items.push({ product_id: p.id, name: p.name, quantity: l.quantity, price, cost: unitCost });
    }
    total = r2(total);
    cost = r2(cost);

    if (customerId != null) {
      const [c] = await tx`select id from customers where id = ${customerId} and user_id = ${uid} for update`;
      if (!c) fail(404, 'Macmiilkan lama helin');
    }
    const paid = paidInput == null ? total : r2(paidInput);
    if (paid > total) fail(400, 'Lacagta la bixiyay kama badnaan karto wadarta');
    if (paid < total && customerId == null) fail(400, 'Iib deyn ah wuxuu u baahan yahay macmiil');

    for (const [pid, n] of need) {
      await tx`update products set quantity = quantity - ${r3(n)} where id = ${pid} and user_id = ${uid}`;
    }
    if (paid < total) {
      await tx`update customers set balance = balance + ${r2(total - paid)} where id = ${customerId} and user_id = ${uid}`;
    }

    const [sale] = await tx`
      insert into sales (user_id, customer_id, total, cost_total, paid, payment_method, note, created_at)
      values (${uid}, ${customerId}, ${total}, ${cost}, ${paid}, ${paymentMethod}, ${note}, now())
      returning id`;
    const itemRows = items.map((it) => ({ sale_id: sale.id, ...it }));
    await tx`insert into sale_items ${tx(itemRows, 'sale_id', 'product_id', 'name', 'quantity', 'price', 'cost')}`;
    return sale.id;
  });

  const [sale] = await fetchSales(sql, uid, { id: saleId, limit: 1 });
  res.status(201).json(sale);
});

/** One transaction: put stock back, remove the unpaid part from the customer's balance, delete the sale. */
router.delete('/:id', async (req, res) => {
  const uid = req.user.id;
  const id = parseId(req.params.id, NOT_FOUND);

  await sql.begin(async (tx) => {
    const [s] = await tx`select id from sales where id = ${id} and user_id = ${uid} for update`;
    if (!s) fail(404, NOT_FOUND);

    await tx`
      update products p set quantity = p.quantity + x.qty
      from (
        select product_id, sum(quantity) as qty from sale_items
        where sale_id = ${id} and product_id is not null
        group by product_id
      ) x
      where p.id = x.product_id and p.user_id = ${uid}`;

    await tx`
      update customers c set balance = greatest(c.balance - (s.total - s.paid), 0)
      from sales s
      where s.id = ${id} and s.user_id = ${uid}
        and c.id = s.customer_id and c.user_id = ${uid}
        and s.total > s.paid`;

    await tx`delete from sales where id = ${id} and user_id = ${uid}`;
  });
  res.json({ ok: true });
});

module.exports = router;
