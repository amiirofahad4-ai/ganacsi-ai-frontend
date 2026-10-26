function createRateLimiter({ limit, windowMs, message, now = Date.now }) {
  const clients = new Map();
  const cleanup = setInterval(() => {
    const current = now();
    for (const [key, entry] of clients) {
      if (entry.resetAt <= current) clients.delete(key);
    }
  }, Math.min(windowMs, 60_000));
  cleanup.unref();

  const middleware = (req, res, next) => {
    const key = req.ip || req.socket?.remoteAddress || 'unknown';
    const current = now();
    let entry = clients.get(key);

    if (!entry || entry.resetAt <= current) {
      entry = { count: 0, resetAt: current + windowMs };
      clients.set(key, entry);
    }

    if (entry.count >= limit) {
      res.set('Retry-After', String(Math.max(1, Math.ceil((entry.resetAt - current) / 1000))));
      return res.status(429).json({ error: message });
    }

    entry.count += 1;
    next();
  };

  middleware.close = () => clearInterval(cleanup);
  return middleware;
}

module.exports = { createRateLimiter };
