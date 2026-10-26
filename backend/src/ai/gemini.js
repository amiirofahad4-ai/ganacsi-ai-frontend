// Gemini chat with function calling (REST API, Node's built-in fetch).
// The API key is only sent in the x-goog-api-key header and is never logged or returned.
const { sql } = require('../db');
const { HttpError } = require('../http');
const { declarations, runTool, WRITE_TOOLS } = require('./tools');

const API_BASE = process.env.GEMINI_API_BASE || 'https://generativelanguage.googleapis.com/v1beta';
const MAX_TOOL_ROUNDS = 5;
const REQUEST_TIMEOUT_MS = 30_000;
// The app waits 90 s for a chat reply, so the whole loop must finish before that
const TOTAL_BUDGET_MS = 80_000;
// Retry a timed-out / 5xx request once, only if at least this much time is left
const MIN_RETRY_BUDGET_MS = 15_000;
const HISTORY_ROWS = 10;

const apiKey = () => (process.env.GEMINI_API_KEY || '').trim();
const model = () => (process.env.GEMINI_MODEL || '').trim() || 'gemini-flash-latest';
const isConfigured = () => apiKey() !== '';

const secs = (t0) => `${((Date.now() - t0) / 1000).toFixed(1)}s`;
let requestSeq = 0;

function systemInstruction(user) {
  const today = new Date().toISOString().slice(0, 10);
  return [
    `You are 'Kaaliye', an AI assistant for the business '${user.business_name || 'Ganacsi'}'. Currency: ${user.currency || 'USD'}.`,
    `Today's date (UTC): ${today}. The owner's name is ${user.name || 'unknown'}.`,
    '- Every number (money, stock, debt) must come from the tools. Never guess or invent numbers.',
    '- If there is no data, say so honestly.',
    '- Use record_expense only when the user clearly asks; if the amount or category is missing, ask first, then confirm what was saved.',
    '- Reply in the user\'s language (Somali or English). Keep answers short and clear for a phone screen.',
    '- You can also write WhatsApp messages, promotions and give business advice based on the real data.',
  ].join('\n');
}

/** Last chat_messages rows as Gemini contents: oldest first, starting with a 'user' message. */
async function loadHistory(uid) {
  const rows = await sql`
    select role, content from (
      select id, role, content from chat_messages
      where user_id = ${uid}
      order by id desc
      limit ${HISTORY_ROWS}
    ) t
    order by id`;
  const contents = [];
  for (const r of rows) {
    const role = r.role === 'assistant' ? 'model' : 'user';
    if (!contents.length && role !== 'user') continue; // must start with 'user'
    const last = contents[contents.length - 1];
    if (last && last.role === role) last.parts.push({ text: r.content }); // keep roles alternating
    else contents.push({ role, parts: [{ text: r.content }] });
  }
  return contents;
}

/**
 * One generateContent request with a hard timeout (AbortController, covers the body too).
 * Returns { data } or { error: HttpError, retryable }.
 */
async function generateOnce(body, ms, log) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    const res = await fetch(`${API_BASE}/models/${encodeURIComponent(model())}:generateContent`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey() },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const data = await res.json().catch(() => null);
    if (res.ok && data) return { data };

    const msg = data?.error?.message || `HTTP ${res.status} (no error body)`;
    log(`Gemini error ${res.status} ${data?.error?.status || ''}: ${msg}`);
    if (res.status === 429) return { error: new HttpError(429, 'Xadka bilaashka ah waa la gaaray, daqiiqad kadib isku day') };
    if (res.status === 404) return { error: new HttpError(502, `Model-ka "${model()}" lama helin. Hubi GEMINI_MODEL ee .env`) };
    if (res.status === 401 || res.status === 403 || /API key/i.test(msg)) {
      return { error: new HttpError(502, 'GEMINI_API_KEY sax ma aha. Hubi furaha ee .env') };
    }
    return { error: new HttpError(502, `AI-ga cillad ayaa ka dhacday (${res.status})`), retryable: res.status >= 500 };
  } catch (e) {
    if (controller.signal.aborted) {
      log(`Gemini timeout after ${(ms / 1000).toFixed(0)}s`);
      return { error: new HttpError(502, 'AI-ga wuu daahay, mar kale isku day'), retryable: true };
    }
    log(`Gemini network error: ${e.message}${e.cause ? ` (${e.cause.code || e.cause.message})` : ''}`);
    return { error: new HttpError(502, 'AI-ga lama gaari karo, hubi internet-ka'), retryable: true };
  } finally {
    clearTimeout(timer);
  }
}

/** generateOnce + one retry for timeouts / network errors / 5xx when time allows. */
async function generate(body, deadline, log) {
  for (let attempt = 1; ; attempt++) {
    const left = deadline - Date.now();
    if (left < 1000) throw new HttpError(502, 'AI-ga wuu daahay, mar kale isku day');
    const r = await generateOnce(body, Math.min(REQUEST_TIMEOUT_MS, left), log);
    if (r.data) return r.data;
    if (attempt === 1 && r.retryable && deadline - Date.now() >= MIN_RETRY_BUDGET_MS) {
      log('retrying Gemini request once');
      continue;
    }
    throw r.error;
  }
}

const replyText = (content) =>
  (content?.parts || []).filter((p) => typeof p.text === 'string' && !p.thought).map((p) => p.text).join('').trim();

const describeParts = (content) =>
  (content?.parts || [])
    .map((p) => (p.functionCall ? `call ${p.functionCall.name}` : p.thought ? 'thought' : typeof p.text === 'string' ? `text(${p.text.length})` : '?'))
    .join(', ') || 'no parts';

/**
 * Sends the user's message (with recent history) to Gemini, runs tool calls,
 * stores the user message + reply in chat_messages. Returns { reply, actions }.
 */
async function chat(uid, message) {
  const id = ++requestSeq;
  const t0 = Date.now();
  const log = (s) => console.log(`[AI #${id} user ${uid}] ${s}`);
  log(`start (${message.length} chars, model ${model()})`);

  const [user] = await sql`select name, business_name, currency from users where id = ${uid}`;
  const contents = [...(await loadHistory(uid)), { role: 'user', parts: [{ text: message }] }];
  const base = {
    systemInstruction: { parts: [{ text: systemInstruction(user || {}) }] },
    tools: [{ functionDeclarations: declarations }],
  };
  const deadline = t0 + TOTAL_BUDGET_MS;
  const actions = [];
  let reply = '';
  let round = 0;

  try {
    for (; ; round++) {
      // After MAX_TOOL_ROUNDS tool rounds, ask for a text answer with tools turned off
      const forceText = round >= MAX_TOOL_ROUNDS;
      const body = { ...base, contents };
      if (forceText) body.toolConfig = { functionCallingConfig: { mode: 'NONE' } };

      const tr = Date.now();
      const data = await generate(body, deadline, log);
      const candidate = data.candidates?.[0];
      const content = candidate?.content;
      log(`round ${round + 1}${forceText ? ' (text only)' : ''}: Gemini ${secs(tr)}, finish=${candidate?.finishReason || '-'}, ${describeParts(content)}`);

      if (!content) {
        const blocked = data.promptFeedback?.blockReason || candidate?.finishReason;
        log(`no content (${blocked || 'unknown reason'})`);
        reply = blocked
          ? 'Su\'aashan kama jawaabi karo. Fadlan si kale u qor.'
          : 'Jawaab lama helin. Fadlan mar kale isku day.';
        break;
      }

      const calls = (content.parts || []).filter((p) => p.functionCall);
      if (!calls.length || forceText) {
        reply = replyText(content) || 'Jawaab lama helin. Fadlan su\'aasha si kale u qor.';
        break;
      }

      // Keep the model's turn exactly as returned (including thoughtSignature fields)
      contents.push(content);
      const responses = [];
      for (const { functionCall: fc } of calls) {
        const tt = Date.now();
        const result = await runTool(uid, fc.name, fc.args);
        const summary = result && result.error ? `error: ${result.error}` : Array.isArray(result) ? `${result.length} rows` : 'ok';
        log(`tool ${fc.name} ${Date.now() - tt}ms → ${summary}`);
        if (WRITE_TOOLS.has(fc.name) && result && result.saved) actions.push({ tool: fc.name, ...result });
        const functionResponse = { name: fc.name, response: { result } };
        if (fc.id) functionResponse.id = fc.id;
        responses.push({ functionResponse });
      }
      contents.push({ role: 'user', parts: responses });
    }
  } catch (e) {
    log(`failed after ${secs(t0)}: ${e.message}`);
    // Data was already saved: don't hide that behind an error
    if (!actions.length) throw e;
    reply = actions
      .map((a) => `✓ Waa la keydiyay: kharash ${a.expense.category} ${a.expense.amount}${a.expense.note ? ` (${a.expense.note})` : ''}`)
      .join('\n');
  }

  await sql`
    insert into chat_messages (user_id, role, content, created_at)
    values (${uid}, 'user', ${message}, now()), (${uid}, 'assistant', ${reply}, now())`;
  log(`done in ${secs(t0)}, ${round + 1} Gemini round(s), ${actions.length} action(s)`);
  return { reply, actions };
}

module.exports = { chat, isConfigured, model };
