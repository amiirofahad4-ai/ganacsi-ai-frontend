// customers (balance = debt the customer owes). Mounted at /api/customers
const express = require('express');
const { sql } = require('../db');
const { requireAuth } = require('../auth');
const { fail, reqStr, optStr, reqNum, optNum, parseId, queryStr, money } = require('../http');
const { listCustomers, fetchSales } = require('../queries');

const router = express.Router();
router.use(requireAuth);

const NOT_FOUND = 'Macmiilkan lama helin';

async function findCustomer(uid, id) {
  const [c] = await sql`select * from customers where id = ${id} and user_id = ${uid}`;
  if (!c) fail(404, NOT_FOUND);
  return c;
}

router.get('/', async (req, res) => {
  res.json(await listCustomers(req.user.id, { q: queryStr(req.query.q), withDebt: req.query.with_debt === 'true' }));
});

router.post('/', async (req, res) => {
  const b = req.body || {};
  const [c] = await sql`
    insert into customers (user_id, name, phone, notes, balance, created_at)
    values (${req.user.id}, ${reqStr(b.name, 'Magaca')}, ${optStr(b.phone)}, ${optStr(b.notes)},
            ${optNum(b.balance, 'balance') ?? 0}, now())
    returning *`;
  res.status(201).json(c);
});

// Customer with their last 50 sales
router.get('/:id', async (req, res) => {
  const uid = req.user.id;
  const id = parseId(req.params.id, NOT_FOUND);
  const c = await findCustomer(uid, id);
  const sales = await fetchSales(sql, uid, { customerId: id, limit: 50 });
  res.json({ ...c, sales });
});

router.put('/:id', async (req, res) => {
  const uid = req.user.id;
  const id = parseId(req.params.id, NOT_FOUND);
  const b = req.body || {};
  const updates = {};
  if ('name' in b) updates.name = reqStr(b.name, 'Magaca');
  for (const k of ['phone', 'notes']) if (k in b) updates[k] = optStr(b[k]);

  if (!Object.keys(updates).length) return res.json(await findCustomer(uid, id));
  const [c] = await sql`update customers set ${sql(updates)} where id = ${id} and user_id = ${uid} returning *`;
  if (!c) fail(404, NOT_FOUND);
  res.json(c);
});

// Customer pays back debt. Body: { amount }
router.post('/:id/payments', async (req, res) => {
  const uid = req.user.id;
  const id = parseId(req.params.id, NOT_FOUND);
  const amount = reqNum((req.body || {}).amount, 'amount', 0.01);

  const [c] = await sql`
    update customers set balance = balance - ${amount}
    where id = ${id} and user_id = ${uid} and balance >= ${amount}
    returning *`;
  if (!c) {
    const cur = await findCustomer(uid, id);
    fail(400, `Lacagta (${money(amount, req.user.currency)}) way ka badan tahay deynta (${money(cur.balance, req.user.currency)})`);
  }
  res.json(c);
});

// Sales and invoices keep their rows (customer_id becomes NULL)
router.delete('/:id', async (req, res) => {
  const [c] = await sql`delete from customers where id = ${parseId(req.params.id, NOT_FOUND)} and user_id = ${req.user.id} returning id`;
  if (!c) fail(404, NOT_FOUND);
  res.json({ ok: true });
});

module.exports = router;
