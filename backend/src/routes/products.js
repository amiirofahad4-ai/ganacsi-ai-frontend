// products. Mounted at /api/products
const express = require('express');
const { sql } = require('../db');
const { requireAuth } = require('../auth');
const { fail, reqStr, optStr, reqNum, optNum, parseId, queryStr } = require('../http');
const { listProducts } = require('../queries');

const router = express.Router();
router.use(requireAuth);

const NOT_FOUND = 'Alaabtan lama helin';

async function findProduct(uid, id) {
  const [p] = await sql`select * from products where id = ${id} and user_id = ${uid}`;
  if (!p) fail(404, NOT_FOUND);
  return p;
}

router.get('/', async (req, res) => {
  res.json(await listProducts(req.user.id, { q: queryStr(req.query.q), low: req.query.low_stock === 'true' }));
});

router.post('/', async (req, res) => {
  const b = req.body || {};
  const [p] = await sql`
    insert into products (user_id, name, sku, category, price, cost, quantity, low_stock_threshold, unit, created_at)
    values (${req.user.id}, ${reqStr(b.name, 'name')}, ${optStr(b.sku)}, ${optStr(b.category)},
            ${reqNum(b.price, 'price')}, ${optNum(b.cost, 'cost') ?? 0}, ${optNum(b.quantity, 'quantity') ?? 0},
            ${optNum(b.low_stock_threshold, 'low_stock_threshold') ?? 5}, ${optStr(b.unit) ?? 'pcs'}, now())
    returning *`;
  res.status(201).json(p);
});

router.get('/:id', async (req, res) => {
  res.json(await findProduct(req.user.id, parseId(req.params.id, NOT_FOUND)));
});

router.put('/:id', async (req, res) => {
  const uid = req.user.id;
  const id = parseId(req.params.id, NOT_FOUND);
  const b = req.body || {};
  const updates = {};
  if ('name' in b) updates.name = reqStr(b.name, 'name');
  for (const k of ['sku', 'category', 'unit']) if (k in b) updates[k] = optStr(b[k]);
  for (const k of ['price', 'cost', 'quantity', 'low_stock_threshold']) if (k in b) updates[k] = reqNum(b[k], k);

  if (!Object.keys(updates).length) return res.json(await findProduct(uid, id));
  const [p] = await sql`update products set ${sql(updates)} where id = ${id} and user_id = ${uid} returning *`;
  if (!p) fail(404, NOT_FOUND);
  res.json(p);
});

// Body: { change: +5 | -2 }
router.post('/:id/stock', async (req, res) => {
  const uid = req.user.id;
  const id = parseId(req.params.id, NOT_FOUND);
  const change = (req.body || {}).change;
  const delta = typeof change === 'number' ? change : typeof change === 'string' && change.trim() ? Number(change) : NaN;
  if (!Number.isFinite(delta)) fail(400, 'change waa inuu tiro noqdaa');

  const [p] = await sql`
    update products set quantity = quantity + ${delta}
    where id = ${id} and user_id = ${uid} and quantity + ${delta} >= 0
    returning *`;
  if (!p) {
    await findProduct(uid, id); // 404 if it doesn't exist
    fail(400, 'Stock-gu kama yaraan karo eber');
  }
  res.json(p);
});

router.delete('/:id', async (req, res) => {
  const [p] = await sql`delete from products where id = ${parseId(req.params.id, NOT_FOUND)} and user_id = ${req.user.id} returning id`;
  if (!p) fail(404, NOT_FOUND);
  res.json({ ok: true });
});

module.exports = router;
