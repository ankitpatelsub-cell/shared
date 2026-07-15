// llm_bridge.js — unified LLM access for all Nihon Offshore agents.
// Provider priority (configurable via env):
//   MODEL_PROVIDER=auto   -> OpenRouter if key+model set, else local Claude CLI
//   MODEL_PROVIDER=openrouter -> OpenRouter only (fails if no key)
//   MODEL_PROVIDER=claude -> local Claude CLI only (free, always available)
// Local Claude CLI is the zero-cost default brain; OpenRouter is the upgrade path.
const { execFileSync } = require('child_process');
const fs = require('fs');

function loadEnv() {
  try {
    const ep = pathOf();
    if (fs.existsSync(ep)) for (const line of fs.readFileSync(ep, 'utf8').split('\n')) {
      const m = line.match(/^\s*([\w.-]+)\s*=\s*(.*)\s*$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
  } catch {}
}
let _envLoaded = false;
function pathOf() { return require('path').join(__dirname, '.env'); }

function claudeCli(prompt, { timeout = 60, model = 'sonnet' } = {}) {
  try {
    const out = execFileSync('/root/.local/bin/claude', ['--print', '-p', prompt, '--allowedTools', '', '--model', model],
      { encoding: 'utf8', timeout: timeout * 1000, maxBuffer: 8 * 1024 * 1024 });
    return { ok: true, text: out.trim(), provider: 'claude' };
  } catch (e) { return { ok: false, text: (e.stderr || e.message || '').toString().split('\n')[0], provider: 'claude' }; }
}

function openrouter(messages, { model, timeout = 30 } = {}) {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) return { ok: false, text: 'no key', provider: 'openrouter' };
  const https = require('https');
  return new Promise((resolve) => {
    const data = JSON.stringify({ model: model || process.env.OPENROUTER_MODEL || 'tencent/hy3:free', messages, temperature: 0.3, max_tokens: 600 });
    const req = https.request({ hostname: 'openrouter.ai', path: '/api/v1/chat/completions', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key, 'Content-Length': Buffer.byteLength(data) } }, res => {
      let b = ''; res.on('data', c => b += c); res.on('end', () => {
        try { const j = JSON.parse(b); resolve({ ok: true, text: j.choices?.[0]?.message?.content || '', provider: 'openrouter' }); }
        catch { resolve({ ok: false, text: b.slice(0, 120), provider: 'openrouter' }); }
      });
    });
    req.on('error', e => resolve({ ok: false, text: e.message, provider: 'openrouter' }));
    req.setTimeout(timeout * 1000, () => { req.destroy(); resolve({ ok: false, text: 'timeout', provider: 'openrouter' }); });
    req.write(data); req.end();
  });
}

// chat(): messages array -> { ok, text, provider }
async function chat(messages, { model } = {}) {
  if (!_envLoaded) { loadEnv(); _envLoaded = true; }
  const provider = (process.env.MODEL_PROVIDER || 'auto').toLowerCase();
  const lastUser = [...messages].reverse().find(m => m.role === 'user')?.content || '';

  if (provider === 'openrouter') {
    const r = await openrouter(messages, { model });
    if (r.ok) return r;
    return { ok: false, text: r.text, provider: 'openrouter' };
  }
  if (provider === 'claude') {
    return claudeCli(lastUser, { model: model || 'sonnet' });
  }
  // auto: try openrouter if configured, else claude
  if (process.env.OPENROUTER_API_KEY && (process.env.OPENROUTER_MODEL || model)) {
    const r = await openrouter(messages, { model });
    if (r.ok) return r;
  }
  return claudeCli(lastUser, { model: model || 'sonnet' });
}

// complete(): single prompt string -> { ok, text, provider } (simpler API)
async function complete(prompt, opts = {}) {
  return chat([{ role: 'user', content: prompt }], opts);
}

module.exports = { chat, complete, claudeCli, openrouter };
