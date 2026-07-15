# shared
Shared modules for the Nihon Offshore multi-agent system.

- `handoff.js` — agent-to-agent task firing (`handoff(to, payload)`)
- `llm_bridge.js` — unified LLM access. Provider via `MODEL_PROVIDER` env:
  - `claude`    -> local Claude CLI (free, authenticated) — DEFAULT brain
  - `openrouter`-> OpenRouter API (needs OPENROUTER_API_KEY + OPENROUTER_MODEL)
  - `auto`      -> OpenRouter if configured, else local Claude CLI

Set `MODEL_PROVIDER=claude` in each agent's .env to use the free local Claude.
