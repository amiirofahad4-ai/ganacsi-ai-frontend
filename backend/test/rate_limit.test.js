const test = require('node:test');
const assert = require('node:assert/strict');
const { createRateLimiter } = require('../src/rate_limit');

function makeResponse() {
  const headers = {};
  return {
    headers,
    statusCode: null,
    body: null,
    set(name, value) {
      headers[name] = value;
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

test('allows requests up to the limit and rejects later requests with Retry-After', () => {
  let current = 1000;
  const limiter = createRateLimiter({
    limit: 2,
    windowMs: 10_000,
    message: 'Too many requests',
    now: () => current,
  });

  try {
    let nextCalls = 0;
    for (let i = 0; i < 2; i += 1) {
      limiter({ ip: '192.0.2.1' }, makeResponse(), () => { nextCalls += 1; });
    }

    const blocked = makeResponse();
    limiter({ ip: '192.0.2.1' }, blocked, () => { nextCalls += 1; });

    assert.equal(nextCalls, 2);
    assert.equal(blocked.statusCode, 429);
    assert.equal(blocked.headers['Retry-After'], '10');
    assert.deepEqual(blocked.body, { error: 'Too many requests' });
  } finally {
    limiter.close();
  }
});

test('resets the request count after the window and keeps clients isolated', () => {
  let current = 1000;
  const limiter = createRateLimiter({
    limit: 1,
    windowMs: 1000,
    message: 'Too many requests',
    now: () => current,
  });

  try {
    let nextCalls = 0;
    limiter({ ip: '192.0.2.1' }, makeResponse(), () => { nextCalls += 1; });
    limiter({ ip: '192.0.2.2' }, makeResponse(), () => { nextCalls += 1; });

    const blocked = makeResponse();
    limiter({ ip: '192.0.2.1' }, blocked, () => { nextCalls += 1; });
    assert.equal(blocked.statusCode, 429);

    current += 1000;
    limiter({ ip: '192.0.2.1' }, makeResponse(), () => { nextCalls += 1; });
    assert.equal(nextCalls, 3);
  } finally {
    limiter.close();
  }
});
