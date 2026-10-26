// invoices. Mounted at /api/invoices
const express = require('express');
const { sql } = require('../db');
const { requireAuth } = require('../auth');
const { fail, reqStr, optStr, reqNum, toInt, parseId, queryStr, isDate, r2 } = require('../http');
const { fetchInvoices } = require('../queries');

const router = express.Router();
router.use(requireAuth);

const NOT_FOUND = 'Invoice-kan lama helin';
const STATUSES = ['unpaid', 'paid', 'cancelled'];

router.get('/', async (req, res) => {
  res.json(await fetchInvoices(sql, req.user.id, { status: queryStr(req.query.status) || null }));
});

router.get('/:id', async (req, res) => {
  const [i] = await fetchInvoices(sql, req.user.id, { id: parseId(req.params.id, NOT_FOUND) });
  if (!i) fail(404, NOT_FOUND);
  res.json(i);
});

// Body: { items: [{ description, quantity, price }], customer_id?, due_date?, note? }
router.post('/', async (req, res) => {
  const uid = req.user.id;
  const b = req.body || {};
  if (!Array.isArray(b.items) || b.items.length === 0) fail(400, 'items waa loo baahan yahay');
  if (b.items.length > 200) fail(400, 'Alaab aad u badan ayaa invoice-ka ku jirta');
  const items = b.items.map((raw) => {
    const it = raw && typeof raw === 'object' ? raw : {};
    const quantity = reqNum(it.quantity, 'quantity', 0.001);
    const price = reqNum(it.price, 'price');
    return { description: reqStr(it.description, 'description'), quantity, price, amount: r2(quantity * price) };
  });
  const total = r2(items.reduce((s, it) => s + it.amount, 0));
  const hasCustomer = b.customer_id != null && b.customer_id !== '';
  const customerId = hasCustomer ? toInt(b.customer_id) : null;
  if (hasCustomer && customerId == null) fail(404, 'Macmiilkan lama helin');
  const dueDate = optStr(b.due_date);
  if (dueDate != null && !isDate(dueDate)) fail(400, 'due_date waa qaab YYYY-MM-DD');

  const id = await sql.begin(async (tx) => {
    // Lock the user row so two invoices created at once don't get the same number
    await tx`select id from users where id = ${uid} for update`;
    if (customerId != null) {
      const [c] = await tx`select id from customers where id = ${customerId} and user_id = ${uid}`;
      if (!c) fail(404, 'Macmiilkan lama helin');
    }
    const [{ n }] = await tx`
      select coalesce(max(substring(number from '^INV-([0-9]+)$')::int), 0) + 1 as n
      from invoices where user_id = ${uid}`;
    const [inv] = await tx`
      insert into invoices (user_id, customer_id, number, items, total, status, due_date, note, created_at)
      values (${uid}, ${customerId}, ${`INV-${String(n).padStart(4, '0')}`}, ${JSON.stringify(items)}::jsonb,
              ${total}, 'unpaid', ${dueDate}::date, ${optStr(b.note)}, now())
      returning id`;
    return inv.id;
  });

  const [inv] = await fetchInvoices(sql, uid, { id });
  res.status(201).json(inv);
});

// Body: { status: 'unpaid' | 'paid' | 'cancelled' }
router.put('/:id/status', async (req, res) => {
  const uid = req.user.id;
  const id = parseId(req.params.id, NOT_FOUND);
  const status = (req.body || {}).status;
  if (!STATUSES.includes(status)) fail(400, `status waa: ${STATUSES.join(', ')}`);

  const [row] = await sql`update invoices set status = ${status} where id = ${id} and user_id = ${uid} returning id`;
  if (!row) fail(404, NOT_FOUND);
  const [inv] = await fetchInvoices(sql, uid, { id });
  res.json(inv);
});

module.exports = router;
