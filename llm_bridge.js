// llm_bridge.js — unified LLM access with AUTO-FAILOVER for all Nihon Offshore agents.
// Providers (env MODEL_PROVIDER): claude | openrouter | auto
//   auto (default): tries primary, falls back to the other on ANY failure
//                     (e.g. Claude CLI token/rate-limit -> OpenRouter, or vice versa)
// Local Claude CLI = free, always-available brain. OpenRouter = upgrade path.
// Live settings: setProvider()/getSettings() persist to the RUNNING agent's .env
//                 (resolved via process.cwd(), which systemd sets to the agent dir).
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// .env lives in the agent's working dir (systemd WorkingDirectory), not here.
const ENV_PATH = path.join(process.cwd(), '.env');

function loadEnv() {
  try {
    if (fs.existsSync(ENV_PATH)) for (const line of fs.readFileSync(ENV_PATH, 'utf8').split('\n')) {
      const m = line.match(/^\s*([\w.-]+)\s*=\s*(.*)\s*$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
  } catch {}
}
let _envLoaded = false;
function ensureEnv() { if (!_envLoaded) { loadEnv(); _envLoaded = true; } }

// Persist a setting to .env (create if missing). Live + survives restart.
function persist(key, val) {
  ensureEnv();
  let lines = fs.existsSync(ENV_PATH) ? fs.readFileSync(ENV_PATH, 'utf8').split('\n') : [];
  const i = lines.findIndex(l => l.startsWith(key + '='));
  const entry = `${key}=${val}`;
  if (i >= 0) lines[i] = entry; else lines.push(entry);
  lines = lines.filter(Boolean);
  fs.writeFileSync(ENV_PATH, lines.join('\n') + '\n');
  process.env[key] = val;
}

function getSettings() {
  ensureEnv();
  return {
    provider: process.env.MODEL_PROVIDER || 'auto',
    openrouter_model: process.env.OPENROUTER_MODEL || '',
    openrouter_key: process.env.OPENROUTER_API_KEY ? 'set' : 'missing',
    claude_cli: (() => { try { fs.accessSync('/root/.local/bin/claude'); return true; } catch { return false; } })(),
  };
}
function setProvider(provider, openrouterModel) {
  persist('MODEL_PROVIDER', provider);
  if (openrouterModel) persist('OPENROUTER_MODEL', openrouterModel);
  return getSettings();
}

function claudeCli(prompt, { timeout = 60, model = 'sonnet' } = {}) {
  try {
    const out = execFileSync('/root/.local/bin/claude', ['--print', '-p', prompt, '--allowedTools', '', '--model', model],
      { encoding: 'utf8', timeout: timeout * 1000, maxBuffer: 8 * 1024 * 1024 });
    return { ok: true, text: out.trim(), provider: 'claude' };
  } catch (e) {
    const msg = (e.stderr || e.message || '').toString();
    // Detect token/rate-limit / auth failures so caller can fail over.
    const exhausted = /rate.?limit|token|exceeded|payment|401|403|quota|usage/i.test(msg);
    return { ok: false, text: msg.split('\n')[0], provider: 'claude', exhausted };
  }
}

function openrouter(messages, { model, timeout = 30 } = {}) {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) return { ok: false, text: 'no key', provider: 'openrouter', exhausted: false };
  const https = require('https');
  return new Promise((resolve) => {
    const data = JSON.stringify({ model: model || process.env.OPENROUTER_MODEL || 'tencent/hy3:free', messages, temperature: 0.3, max_tokens: 600 });
    const req = https.request({ hostname: 'openrouter.ai', path: '/api/v1/chat/completions', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key, 'Content-Length': Buffer.byteLength(data) } }, res => {
      let b = ''; res.on('data', c => b += c); res.on('end', () => {
        try { const j = JSON.parse(b); resolve({ ok: true, text: j.choices?.[0]?.message?.content || '', provider: 'openrouter' }); }
        catch {
          const exhausted = /rate.?limit|exceeded|401|403|quota|usage|payment/i.test(b);
          resolve({ ok: false, text: b.slice(0, 120), provider: 'openrouter', exhausted });
        }
      });
    });
    req.on('error', e => resolve({ ok: false, text: e.message, provider: 'openrouter', exhausted: false }));
    req.setTimeout(timeout * 1000, () => { req.destroy(); resolve({ ok: false, text: 'timeout', provider: 'openrouter', exhausted: false }); });
    req.write(data); req.end();
  });
}

// chat(): messages array -> { ok, text, provider, exhausted }
async function chat(messages, { model } = {}) {
  ensureEnv();
  const provider = (process.env.MODEL_PROVIDER || 'auto').toLowerCase();
  const lastUser = [...messages].reverse().find(m => m.role === 'user')?.content || '';

  const tryClaude = async () => claudeCli(lastUser, { model: model || 'sonnet' });
  const tryOR = async () => openrouter(messages, { model });

  if (provider === 'claude') {
    const r = await tryClaude();
    if (!r.ok && r.exhausted && process.env.OPENROUTER_API_KEY) { console.log('[llm] Claude exhausted -> OpenRouter'); return tryOR(); }
    return r;
  }
  if (provider === 'openrouter') {
    const r = await tryOR();
    if (!r.ok && r.exhausted && fs.existsSync('/root/.local/bin/claude')) { console.log('[llm] OpenRouter exhausted -> Claude'); return tryClaude(); }
    return r;
  }
  // auto: primary = OpenRouter if configured+model, else Claude; failover to the other
  const orReady = process.env.OPENROUTER_API_KEY && (process.env.OPENROUTER_MODEL || model);
  const primary = orReady ? tryOR : tryClaude;
  const secondary = orReady ? tryClaude : tryOR;
  const r1 = await primary();
  if (r1.ok) return r1;
  if (r1.exhausted || !orReady) { console.log('[llm] primary failed -> failover'); return secondary(); }
  return r1;
}

async function complete(prompt, opts = {}) { return chat([{ role: 'user', content: prompt }], opts); }

module.exports = { chat, complete, claudeCli, openrouter, getSettings, setProvider };
