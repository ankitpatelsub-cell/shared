// handoff.js — fire a task to another agent's endpoint (agent-to-agent handoff).
// Used so events in one agent trigger work in another (e.g. hospital booking -> back-office billing).
const ENDPOINTS = {
  backoffice: { url: 'http://localhost:8092/api/inbox', kind: 'inbox' },
  hospital:   { url: 'http://localhost:8094/api/intake', kind: 'intake' },
  hotel:      { url: 'http://localhost:8096/api/checkin', kind: 'checkin' },
  car:        { url: 'http://localhost:8097/api/chat', kind: 'chat' },
  reels:      { url: 'http://localhost:8098/api/car-added', kind: 'caradded' },
};
function handoff(to, payload) {
  const e = ENDPOINTS[to];
  if (!e) return { ok: false, error: 'unknown agent ' + to };
  let body;
  switch (e.kind) {
    case 'inbox': body = { task: payload.task || payload }; break;
    case 'intake': body = { patient: payload.text || payload, channel: 'handoff', locale: payload.locale || 'en' }; break;
    case 'checkin': body = { guest: payload.text || payload, channel: 'handoff', locale: payload.locale || 'en' }; break;
    case 'chat': body = { text: payload.text || payload, channel: 'handoff', locale: payload.locale || 'en' }; break;
    case 'caradded': body = payload; break;
    default: body = payload;
  }
  fetch(e.url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    .then(r => r.ok ? console.log('[handoff] ->', to, 'ok') : console.log('[handoff] ->', to, 'status', r.status))
    .catch(err => console.log('[handoff] ->', to, 'err', err.message));
  return { ok: true, to, fired: true };
}
module.exports = { handoff, ENDPOINTS };
