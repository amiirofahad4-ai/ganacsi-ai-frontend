// expenses. Mounted at /api/expenses
const express = require('express');
const { sql } = require('../db');
const { requireAuth } = require('../auth');
const { fail, reqStr, optStr, reqNum, parseId, queryStr, range, isDate } = require('../http');

const router = express.Router();
router.use(requireAuth);

const CATEGORIES = ['rent', 'salary', 'utilities', 'transport', 'stock_purchase', 'marketing', 'other'];
const NOT_FOUND = 'Kharashkan lama helin';

router.get('/categories', (req, res) => res.json(CATEGORIES));

router.get('/', async (req, res) => {
  const r = range(queryStr(req.query.period) ?? 'month');
  res.json(await sql`
    select * from expenses
    where user_id = ${req.user.id} and date >= ${r.fromDate}::date and date < ${r.toDate}::date
    order by date desc, id desc`);
});

router.post('/', async (req, res) => {
  const b = req.body || {};
  const category = reqStr(b.category, 'category');
  if (!CATEGORIES.includes(category)) fail(400, `category waa: ${CATEGORIES.join(', ')}`);
  const date = optStr(b.date);
  if (date != null && !isDate(date)) fail(400, 'date waa qaab YYYY-MM-DD');

  const [e] = await sql`
    insert into expenses (user_id, category, amount, note, date, created_at)
    values (${req.user.id}, ${category}, ${reqNum(b.amount, 'amount', 0.01)}, ${optStr(b.note)},
            coalesce(${date}::date, current_date), now())
    returning *`;
  res.status(201).json(e);
});

router.delete('/:id', async (req, res) => {
  const [e] = await sql`delete from expenses where id = ${parseId(req.params.id, NOT_FOUND)} and user_id = ${req.user.id} returning id`;
  if (!e) fail(404, NOT_FOUND);
  res.json({ ok: true });
});

module.exports = router;
