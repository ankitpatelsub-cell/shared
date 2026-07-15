# shared
Shared modules for the Nihon Offshore multi-agent system.

- `handoff.js` — agent-to-agent task firing (`handoff(to, payload)`)
- `llm_bridge.js` — unified LLM with AUTO-FAILOVER. Provider via `MODEL_PROVIDER` env:
  - `claude`     -> local Claude CLI (free, authenticated) — DEFAULT brain
  - `openrouter` -> OpenRouter API (needs OPENROUTER_API_KEY + OPENROUTER_MODEL)
  - `auto`       -> tries primary, fails over to the other on token/rate-limit
  Claude token exhaustion (rate-limit/quota/403) auto-fails-over to OpenRouter.
  Live switch: POST /api/set-provider {provider, openrouter_model}
- `settings.js` — mounts GET/POST /api/settings + /api/set-provider on any agent.
