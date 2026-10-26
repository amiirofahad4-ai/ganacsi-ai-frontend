// Reports and dashboard (read-only, built from the other tables). Mounted at /api/reports
const express = require('express');
const { sql } = require('../db');
const { requireAuth } = require('../auth');
const { queryStr, queryInt, range } = require('../http');
const q = require('../queries');

const router = express.Router();
router.use(requireAuth);

const period = (req, def) => queryStr(req.query.period) ?? def;

router.get('/summary', async (req, res) => {
  res.json(await q.summary(req.user.id, period(req, 'month')));
});

router.get('/top-products', async (req, res) => {
  res.json(await q.topProducts(req.user.id, period(req, 'month'), queryInt(req.query.limit, 5, 1, 50)));
});

router.get('/daily', async (req, res) => {
  res.json(await q.daily(req.user.id, queryInt(req.query.days, 7, 1, 90)));
});

router.get('/expenses-by-category', async (req, res) => {
  res.json(await q.expensesByCategory(req.user.id, period(req, 'month')));
});

/** GET /api/dashboard?period=today */
async function dashboard(req, res) {
  const uid = req.user.id;
  const p = period(req, 'today');
  range(p); // validate the period first (400)
  const week = range('week');
  const [summary, daily, topProducts, lowStock, recentSales, insights] = await Promise.all([
    q.summary(uid, p),
    q.daily(uid, 7),
    q.topProducts(uid, 'month', 5),
    q.listProducts(uid, { low: true, limit: 10 }),
    q.fetchSales(sql, uid, { from: week.from, to: week.to, limit: 5 }),
    q.insights(uid, req.user.currency),
  ]);
  res.json({ summary, daily, top_products: topProducts, low_stock: lowStock, recent_sales: recentSales, insights });
}

module.exports = { router, dashboard };
