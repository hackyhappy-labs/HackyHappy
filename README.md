# OpenWebUI AI Agent Stack

> Self-hosted, security-hardened AI agent platform built on [Open WebUI](https://github.com/open-webui/open-webui) — with a Twilio voice/SMS bot, a Telegram bridge, and a Multi-Agent browser automation service.

**Languages:** **English** · [한국어](./README.ko.md)

---

## Overview

This repository contains four Bash installer scripts that stand up a complete, locally-hosted AI agent stack on a single Linux host (Ubuntu / WSL2 supported). Everything runs in Docker, all service ports bind to `127.0.0.1` by default, and secrets are stored via Docker Secrets with restrictive file permissions.

| # | Script | Role | Default Ports (localhost) |
|---|--------|------|---------------------------|
| 1 | `start-openwebui-hardened.sh` | **Phase 2** — Open WebUI + RAG (Qdrant) + OpenAPI Tools + Twilio voice/SMS bot | `3000` WebUI, `6333` Qdrant, `8000` Tools, `5000` Twilio bot |
| 2 | `setup-telegram-openwebui-bridge-FINAL.sh` | **Phase 3** — Telegram ↔ Open WebUI bridge with admin dashboard | `8444` health, `8445` dashboard |
| 3 | `setup-browser-agent-browser-use-v7.sh` | **Browser Agent** — Browser-Use + Playwright + LangGraph Multi-Agent | `8001` agent API |
| 4 | `verify-install.sh` | **Verifier** — cross-checks all of the above against the actual installed sources | — |

> The scripts are independent but designed to layer: install Phase 2 first, then optionally add the Browser Agent and/or the Telegram bridge, then run the verifier.

---

## Requirements

- **OS:** Ubuntu 20.04+ (native or WSL2). WSL2 is auto-detected and handled.
- **Docker** + the **Docker Compose plugin** (`docker compose`). The Phase 2 script will offer to install Docker if it is missing.
- **`sudo`** access (used for Docker, secret ownership `uid 1001`, and firewall configuration).
- **`python3`** (used by the Telegram and verifier scripts).
- At least one **LLM API key** — Groq, OpenAI, Anthropic (Claude), or Google (Gemini). Groq is the default.
- *(Optional)* A **Twilio** account for the voice/SMS bot, a **Telegram Bot Token** for the bridge, and **Ollama** for local models.

---

## Quick Start

```bash
# 0. Clone
git clone https://github.com/<your-org>/<your-repo>.git
cd <your-repo>
chmod +x *.sh

# 1. Phase 2 — core platform (Open WebUI + RAG + Twilio bot)
bash start-openwebui-hardened.sh

# 2. (Optional) Browser Agent — Multi-Agent web automation
bash setup-browser-agent-browser-use-v7.sh

# 3. (Optional) Telegram bridge
bash setup-telegram-openwebui-bridge-FINAL.sh

# 4. Verify the whole installation
bash verify-install.sh
```

Each installer is **interactive** and prompts for the keys/values it needs (most prompts have a timeout and can be skipped with Enter). Open WebUI becomes available at **http://localhost:3000** once Phase 2 finishes.

---

## The Four Scripts

### 1. `start-openwebui-hardened.sh` — Phase 2 (Core Platform)

Installs the heart of the stack:

- **Open WebUI** chat interface (`:3000`) with **Qdrant** vector DB (`:6333`) for RAG document search.
- **OpenAPI Tools** server (`:8000`) exposing callable tools to the model.
- **Twilio AI phone bot** (`:5000`): makes AI-driven outbound calls and handles two-way SMS, with automatic **language detection by country code** (`+82` Korean, `+1` English, `+81` Japanese, `+86` Chinese).
- Registers seven Open WebUI tools, e.g. phone assistant, RAG search, SMS sender, schedule manager, recording manager, PDF report manager, feature-status.

**Prompts include:** Groq API key, optional Twilio credentials (Account SID, Auth Token, phone number, your number), admin email/app name, bot mode, and a mandatory **6-digit admin PIN**. Ollama and NVIDIA GPU are auto-detected.

**Security highlights:** Docker Secrets (`/run/secrets/`), structured JSON audit logging, all ports bound to `127.0.0.1`, `.env` at `chmod 600`, masked secret input, optional Cloudflare Tunnel for HTTPS without opening ports.

### 2. `setup-browser-agent-browser-use-v7.sh` — Browser Agent

A containerized web-automation agent based on **Browser-Use** + **Playwright (Chromium)**, with a **LangGraph Multi-Agent** mode (supervisor → research → browser-tool → summarizer).

- API on `127.0.0.1:8001`. Key endpoints: `/browse`, `/browse/stream` (SSE), `/browse/batch`, `/browse/multi` (Multi-Agent), `/screenshot`, `/history`, `/tasks`, `/sessions`, `/monitors`, `/pool/status`, `/proxy/status`, `/memory`, `/files`, `/metrics`, `/health`, `/health/multi`.
- **Multi-provider LLM:** Groq (default), OpenAI, Anthropic/Claude, Google/Gemini — selected by `LLM_PROVIDER` or by which API key is present.
- Registers Open WebUI tools including `search_wikipedia`, `take_screenshot`, `search_map`, `download_file`, `export_to_excel`, `monitor_price`, `check_monitors`.
- Shares files with the host through `~/ai-share` → `/app/data/user_files`.

**Security highlights:** seccomp profile, `cap_drop: ALL`, `no-new-privileges`, API-key auth on protected routes, IP lockout after repeated failures, audit logging, request body size limits, and path-traversal protection. On WSL2 it falls back to privileged mode for runc `openat2` compatibility (see the warning in the verifier's Section 15).

### 3. `setup-telegram-openwebui-bridge-FINAL.sh` — Telegram Bridge (Phase 3)

Connects an existing Open WebUI instance to a Telegram bot so you can use all your models, tools, and RAG from Telegram.

- **Commands:** `/start`, `/help`, `/model`, `/tools`, `/clear`, `/lock`, `/history`, `/status`, `/whoami`, `/admin`, `/users`, `/block`, `/unblock`, `/adduser`, `/removeuser`, `/broadcast`, `/logs`, `/stats`, `/emergency`, `/remind`, `/reminders`, `/cancel`.
- **Streaming** responses, a **scheduler** for reminders, and an **admin web dashboard** on `127.0.0.1:8445` (reach it via SSH tunnel, see below).
- **Prompts include:** Telegram Bot Token, OpenWebUI API key, mandatory admin **Telegram User ID(s)** whitelist, and an optional 6-digit admin PIN.

**26 security measures**, including: replay-attack defense (`update_id`), prompt-injection filtering, file magic-byte validation, AI-response secret redaction, JSON audit log, emergency lockdown mode, dashboard brute-force protection (timing-safe), and a seccomp profile.

Access the dashboard:

```bash
ssh -L 8445:localhost:8445 user@SERVER_IP
# then open http://localhost:8445/dashboard
```

### 4. `verify-install.sh` — Installation Verifier

A read-only diagnostic that cross-checks all three installers against the **actual installed source code** across 15 sections: directory structure, required files, file permissions, container status, API health endpoints, Docker networks, security posture, Browser-Use/Chromium/packages, seccomp validity, Telegram & Twilio config, Open WebUI tool registration, Browser Agent functional checks, optional Cloudflare Tunnel, and a security-audit cross-reference.

```bash
bash verify-install.sh        # exits with the number of failed checks
```

It is intentionally tolerant (`set -e`/`-u` are **not** used) so every check runs to completion and the failures are tallied at the end.

---

## Common Commands

```bash
# Start / status (Phase 2)
cd ~/OpenWebUI && docker compose up -d
cd ~/OpenWebUI && docker compose ps

# Audit log
cd ~/OpenWebUI && ./view-audit-log.sh

# Logs
docker logs -f twilio-bot
docker logs -f telegram-openwebui-bridge
docker logs -f browser-agent

# Telegram bridge
cd ~/telegram-openwebui-bridge && docker compose up -d

# Browser Agent health / multi-agent
curl -H "Authorization: Bearer $(grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env | cut -d= -f2-)" \
  http://localhost:8001/health | python3 -m json.tool
```

---

## Directory Layout (after install)

```
~/OpenWebUI/                     # Phase 2 root
├── docker-compose.yml
├── .env                         # chmod 600
├── secrets/                     # Docker Secrets (uid 1001, chmod 700)
├── tools-api/                   # OpenAPI tools server
├── twilio-bot/                  # Twilio voice/SMS bot + data
├── browser-agent/               # Browser Agent (if installed)
│   ├── agent_server.py
│   ├── multi_agent/             # LangGraph multi-agent modules
│   ├── seccomp-browser.json
│   └── secrets/
└── logs/

~/telegram-openwebui-bridge/     # Phase 3 root (if installed)
├── docker-compose.yml
├── bot/                         # telegram_bot.py, seccomp-bot.json
└── secrets/

~/ai-share/                      # Host ↔ Browser Agent shared files
```

---

## Security Notes

- All service ports bind to `127.0.0.1`. To expose anything publicly, prefer a **Cloudflare Tunnel** or a reverse proxy with TLS rather than opening ports directly.
- Keep `.env` files and `secrets/` directories out of version control. The Phase 2 installer generates `.gitignore` / `.dockerignore` for this purpose — **do not commit your secrets.**
- On WSL2, the Browser Agent and Telegram bridge may run in **privileged** mode, which weakens container isolation. Use it only on trusted hosts; the verifier flags this in Section 15.
- Run `verify-install.sh` after any install or upgrade to catch misconfigurations.

---

## License

Specify your license here (e.g. MIT). Add a `LICENSE` file to the repository root.

## Disclaimer

These scripts provision services that can place phone calls, send SMS, browse the web autonomously, and accept remote commands. Review the configuration, use strong secrets, restrict access to trusted users, and comply with all applicable laws and the terms of service of Twilio, Telegram, and your chosen LLM providers.
