// settings.js — shared settings routes for all agents.
// Mount in any server: await settings.handle(req, res, url) — returns true if handled.
const bridge = require('/root/shared/llm_bridge');
function send(res, code, obj) { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); }
// Returns true if it handled the request (so caller can early-return).
async function handle(req, res, url) {
  if (url.pathname === '/api/settings' && req.method === 'GET') {
    send(res, 200, bridge.getSettings()); return true;
  }
  if (url.pathname === '/api/settings' && req.method === 'POST') {
    let b = ''; for await (const c of req) b += c;
    let body = {}; try { body = JSON.parse(b || '{}'); } catch {}
    send(res, 200, bridge.setProvider(body.provider || 'auto', body.openrouter_model || undefined)); return true;
  }
  if (url.pathname === '/api/set-provider' && req.method === 'POST') {
    let b = ''; for await (const c of req) b += c;
    let body = {}; try { body = JSON.parse(b || '{}'); } catch {}
    send(res, 200, bridge.setProvider(body.provider || 'auto', body.openrouter_model || undefined)); return true;
  }
  return false;
}
module.exports = { handle, send };
