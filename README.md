# OpenWebUI AI Agent Suite

> **Hardened, multi-phase AI agent stack** — OpenWebUI + Twilio Voice/SMS + Telegram Bridge + Browser Use Agent  
> 강화 보안 멀티페이즈 AI 에이전트 스택 — OpenWebUI + Twilio 전화/SMS + 텔레그램 브릿지 + 브라우저 에이전트

---

## 🌐 Language / 언어

- [English](#english-guide)
- [한국어](#한국어-가이드)

---

# English Guide

## 📋 Overview

This project is a **production-ready, security-hardened AI agent platform** built on top of [Open WebUI](https://github.com/open-webui/open-webui). It consists of three installation phases plus a verification script:

| Script | Phase | Version | Description |
|---|---|---|---|
| `start-openwebui-hardened.sh` | Phase 2 | v1.1.0-hardened | Core stack: OpenWebUI + Qdrant + Twilio Voice/SMS Bot + OpenAPI Tools |
| `setup-telegram-openwebui-bridge-FINAL.sh` | Phase 3 | v2.0.0-hardened | Telegram ↔ OpenWebUI bridge (26-point hardened security) |
| `setup-browser-agent-browser-use-v6.sh` | Browser | v6.4.0 | AI Browser Use Agent + Multi-Agent (Groq + LangGraph) |
| `verify-install.sh` | Verify | v5.0.0 | Full installation verification across all phases (14 sections) |

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         User Interfaces                          │
│   🌐 Web Browser    📞 Phone/SMS    💬 Telegram    🖥 VNC      │
│       :3000          (Twilio)       (Bot API)    :5901(local)  │
└──────┬──────────────┬──────────────┬──────────────┬─────────────┘
       │              │              │              │
       ▼              ▼              ▼              │
┌──────────────────────────────────────────────────┘
│              Cloudflare Tunnel (HTTPS, no port open)
│                  ↓
│              Nginx (Reverse Proxy)
│         Twilio Webhook  │  Telegram Webhook
└────────┬────────────────┼──────────────────────────────┐
         │                │                              │
┌────────▼────────┐ ┌─────▼──────────────┐ ┌────────────▼──────────┐
│  OpenWebUI      │ │  Telegram Bridge   │ │  Browser-Use Agent    │
│  :3000          │ │  :8444 health      │ │  :8001 health/browse  │
├─────────────────┤ │  :8445 dashboard   │ │  :5901 VNC (local)    │
│  Twilio Bot     │ │  (local only)      │ └───────────────────────┘
│  :5000 (local)  │ └────────────────────┘
│  :8020 (nginx)  │
├─────────────────┤
│  OpenAPI Tools  │
│  :8000 (local)  │
│  :8010 (nginx)  │
├─────────────────┤
│  Qdrant (RAG)   │
│  :6333 (local)  │
├─────────────────┤
│  Ollama (opt.)  │
│  :11434 (local) │
└─────────────────┘
```

---

## ⚙️ System Requirements

| Tier | CPU | RAM | Notes |
|---|---|---|---|
| 🚀 High Performance | 6+ cores | 16+ GB | Recommended |
| 💪 Medium-High | 4+ cores | 8+ GB | Stable |
| 📊 Medium | 2+ cores | 4+ GB | Limited |
| 🐢 Low | < 2 cores | < 4 GB | Minimal |

**Prerequisites:**
- Ubuntu 20.04+ / Debian 11+ / WSL2 (Windows)
- Docker (auto-installed if missing)
- Non-root user with `sudo` access
- Ollama (optional, auto-detected and installed)
- Python 3.8+

---

## 🔐 Security Features

### Phase 2 — Core Stack (21 items)
- Twilio signature verification (`X-Twilio-Signature`) + API secret authentication
- Port local binding (no unnecessary external exposure)
- 6-digit PIN lock with 30-minute auto-release (file-based persistent storage)
- Docker Secrets (`/run/secrets/`) for sensitive data isolation
- Structured JSON audit logging
- Cloudflare Tunnel HTTPS (no port forwarding required)
- `.env` permission locked to `600`
- `.gitignore` / `.dockerignore` auto-generated (prevents secret leaks)
- TTS injection prevention (URL params → internal storage lookup)
- Sensitive input masking (API Key/Token/PIN → `****` after entry)
- Default password elimination (auto-generated via `openssl rand` when blank)

### Phase 3 — Telegram Bridge (26 items)
- AES-256 encrypted Bot Token storage
- Rate limiting (30 req/min per user)
- Telegram User ID whitelist (allowlist-only access)
- Input length limit (4,096 chars) + XSS/injection defense
- Webhook signature verification (Telegram Secret Token)
- Non-root container execution
- Docker network isolation (internal network)
- Sensitive log masking
- Health check + auto-recovery
- File upload size limit (20 MB)
- Session timeout (conversation reset after 30 min inactivity)
- Admin-only commands with PIN authentication
- Auto-block after 3 failed attempts → 10-minute lockout
- Log rotation (10 MB × 3 files)
- Brute-force protection on dashboard: 5 failures → 15-min IP lock (timing-safe)
- **[NEW]** Replay attack defense (duplicate `update_id` blocking)
- **[NEW]** Prompt injection defense (9 regex patterns, detect & block)
- **[NEW]** File Magic Bytes validation (extension spoofing prevention)
- **[NEW]** AI response sensitive-data filter (API keys, JWT, phone numbers)
- **[NEW]** Structured audit log JSON (`audit.log`)
- **[NEW]** Emergency block mode `/emergency` (admin — instant full block)
- **[NEW]** Seccomp profile (syscall whitelist)

### Browser Agent — v6.4.0 (7 security patches)
- Seccomp profile (`seccomp-browser.json`) — minimized allowed syscalls
- `cap_drop ALL` + `no-new-privileges` (privilege escalation blocked)
- API key authentication (Bearer token required on all requests)
- VNC port bound to `127.0.0.1:5901` only + UFW firewall verification
- 512-bit browser API key (auto-generated per install)
- Non-root execution (UID 1001)
- CVE patches applied (2026-05)

---

## 🚀 Installation

> **Run scripts in order.** Each phase depends on the previous one.

### Step 0 — Clone the repository

```bash
git clone https://github.com/hackyhappy-labs/HackyHappy.git
cd HackyHappy
chmod +x *.sh
```

### Step 1 — Phase 2: Core Stack

```bash
bash start-openwebui-hardened.sh
```

**What it installs:**
- OpenWebUI (with Qdrant RAG + Ollama/Groq)
- Twilio Voice Bot (AI phone calls with multilingual TTS/STT)
- SMS two-way communication (auto-forward replies)
- OpenAPI Tools server (`:8000` internal / `:8010` via Nginx)
- Cloudflare Tunnel (optional, prompted during install)

**Inputs required during setup:**

| # | Prompt | Required | Default |
|---|---|---|---|
| 1 | Install Ollama | Optional | Y/N based on specs |
| 2 | Groq API Key | Optional | Skip |
| 3 | Twilio Account SID | Optional | Skip |
| 4 | Twilio Auth Token | Optional | Skip |
| 5 | Twilio Phone Number | Optional | Skip |
| 6 | Admin Phone Number | Optional | Skip |
| 7 | OpenWebUI Admin Email | Optional | `admin@example.com` |
| 8 | OpenWebUI Admin Password | Optional | Auto-generated |
| 9 | App Name | Optional | AI Assistant |
| 10 | Admin Security PIN (6 digits) | Optional | Auto-generated |

**Auto-registered Tools (8):**

| # | Tool | Description |
|---|---|---|
| 1 | Phone Assistant | Make calls, manage contacts, view call history |
| 2 | RAG Document Search | Vector search across PDF/documents |
| 3 | SMS Sender | Send text messages + auto-forward replies |
| 4 | Schedule Manager | Create, view, and delete phone/SMS schedules |
| 5 | Recording Manager | Browse and play call recordings |
| 6 | PDF Report Manager | Generate and view call reports |
| 7 | Feature Status | System status monitoring |
| 8 | Media Manager | Upload and browse photos/videos/audio files |

### Step 2 — Phase 3: Telegram Bridge

```bash
bash setup-telegram-openwebui-bridge-FINAL.sh
```

**Prerequisite:** OpenWebUI must be running at `http://localhost:3000`

**What it installs:**
- Telegram Bot (webhook mode)
- Bridge server (`:8444`) + Admin dashboard (`:8445`, local only — SSH tunnel required)

**Inputs required during setup:**

| # | Prompt | Required |
|---|---|---|
| 1 | Telegram Bot Token | ✅ (from [@BotFather](https://t.me/BotFather)) |
| 2 | OpenWebUI API Key | ✅ (Settings → Account → API Keys) |
| 3 | Allowed Telegram User IDs | ✅ (from [@userinfobot](https://t.me/userinfobot)) |
| 4 | Webhook mode / domain | Optional |
| 5 | Admin PIN | Optional (auto-generated) |

### Step 3 — Browser Agent (Optional)

```bash
bash setup-browser-agent-browser-use-v6.sh
```

**What it installs:**
- Browser-Use + Playwright (DOM + A11y hybrid)
- Multi-Agent orchestration (Groq + LangGraph)
- 11 built-in tools: `check_weather`, `check_price`, `check_stock`, `search_web`, `translate_text`, etc.
- Self-healing retry logic + CVE patches
- Agent API (`:8001`)

**Inputs required during setup:**

| # | Prompt | Required |
|---|---|---|
| 1 | OpenWebUI external URL | ✅ |
| 2 | OpenWebUI admin email | ✅ |
| 3 | OpenWebUI admin password | ✅ |
| 4 | OpenWebUI API Key | ✅ |
| 5 | Groq API Key | Optional (for Multi-Agent) |

**Browser Agent API Endpoints:**

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Health check |
| `/browse` | POST | Single-agent browsing |
| `/browse/multi` | POST | Multi-agent browsing |
| `/memory` | GET | Memory inspection |
| `/files` | GET | File listing |

### Step 4 — Verify Installation

```bash
bash verify-install.sh
```

Runs 14 verification sections covering 25 directories, 38 required files, security permissions, Docker containers, networks, secrets, Nginx config, Browser Agent, Seccomp profile, Telegram config, Twilio integration, OpenWebUI tools, and Cloudflare Tunnel.

---

## 🔌 Service Port Map

| Service | Port | Binding | Description |
|---|---|---|---|
| Open WebUI | 3000 | 0.0.0.0 | Main web interface |
| Twilio Bot | 5000 | localhost | Voice/SMS bot (internal) |
| Qdrant | 6333 | localhost | Vector DB + dashboard |
| OpenAPI Tools | 8000 | localhost | Tool API (Swagger: `/docs`) |
| OpenAPI Tools (Nginx) | 8010 | 0.0.0.0 | External via Nginx reverse proxy |
| Twilio Bot (Nginx) | 8020 | 0.0.0.0 | External via Nginx reverse proxy |
| Browser Agent | 8001 | localhost | Browser automation API |
| Telegram Bridge | 8444 | localhost | Bridge health / metrics |
| Telegram Dashboard | 8445 | localhost | Admin dashboard (**SSH tunnel required**) |
| VNC (Browser) | 5901 | 127.0.0.1 | Browser screen viewer (local only) |
| Ollama | 11434 | localhost | Local LLM (optional) |

---

## 📁 Directory Structure

```
~/OpenWebUI/                        # Phase 2 root
├── .env                            # Environment config (chmod 600)
├── docker-compose.yml
├── docker-compose.override.yml
├── .gitignore                      # Prevents secrets/.env leaks
├── .dockerignore
├── view-audit-log.sh               # Audit log viewer
├── secrets/                        # Docker Secrets (chmod 700)
│   ├── twilio_auth_token
│   ├── api_secret
│   ├── groq_api_key
│   ├── admin_pin
│   ├── webui_secret_key
│   └── entrypoint-secrets.sh
├── tools-api/                      # OpenAPI Tools server
│   ├── main.py
│   ├── Dockerfile
│   └── requirements.txt
├── twilio-bot/                     # Twilio Voice/SMS Bot
│   ├── twilio_bot.py
│   ├── ai_config.py                # Multilingual / AI config
│   ├── scheduler.py
│   ├── call_history.py
│   ├── entrypoint.sh
│   ├── Dockerfile
│   ├── requirements.txt
│   └── data/
│       ├── contacts.json           # Auto-created on first use
│       ├── call_history.json       # Auto-created on first use
│       ├── schedules.json          # Auto-created on first use
│       ├── recordings/
│       └── reports/
├── browser-agent/                  # Browser-Use Agent (chmod 750)
│   ├── agent_server.py
│   ├── openwebui_tool.py
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── seccomp-browser.json
│   ├── logrotate.conf
│   ├── secrets/                    # (chmod 750)
│   ├── multi_agent/                # Multi-Agent modules
│   └── data/
│       ├── screenshots/
│       ├── sessions/
│       ├── results/
│       └── audit/
└── logs/
    ├── twilio-bot/
    ├── openapi-tools/
    └── nginx/

~/telegram-openwebui-bridge/        # Phase 3 root
├── .env                            # (chmod 600)
├── docker-compose.yml
├── bot/
│   ├── telegram_bot.py
│   ├── entrypoint.sh
│   ├── Dockerfile
│   └── requirements.txt
├── data/
├── logs/
└── secrets/                        # (chmod 700)
    ├── telegram_bot_token
    ├── openwebui_api_key
    ├── webhook_secret
    └── tg_admin_pin

~/ai-share/                         # Local file sharing directory
```

---

## 🤖 Telegram Bot Commands

| Command | Description |
|---|---|
| `/start` | Start conversation + usage guide |
| `/model` | Switch AI model in real-time |
| `/tools` | Enable/disable OpenWebUI tools |
| `/clear` | Reset conversation history |
| `/history` | View conversation history |
| `/status` | Check system status (admin only) |
| `/users` | List active users (admin only) |
| `/block` / `/unblock` | Block/unblock user (admin only) |
| `/emergency` | Emergency full-block mode (admin only) |

---

## 🌍 Multilingual Support (Phase 2)

Automatic language detection based on phone number country code:

| Country Code | Language | TTS Locale |
|---|---|---|
| `+82` | 한국어 (Korean) | ko-KR |
| `+1` / `+44` | English | en-US |
| `+81` | 日本語 (Japanese) | ja-JP |
| `+86` | 中文 (Chinese) | zh-CN |

Configure in `~/OpenWebUI/twilio-bot/ai_config.py`: `DEFAULT_LANG`, `COUNTRY_LANG_MAP`  
Apply changes: `cd ~/OpenWebUI && docker compose restart twilio-bot`

---

## 🔑 Browser Agent API Key Guide

The Browser Agent API (`:8001`) requires a Bearer token on every request. The key is auto-generated during installation and written to **two places**: `~/OpenWebUI/.env` and the `environment:` block inside `~/OpenWebUI/docker-compose.yml`.

> ⚠️ `~/OpenWebUI/.env` is created by **Phase 2** (`start-openwebui-hardened.sh`). If you ran the Browser Agent script standalone (without Phase 2), the `.env` file may not exist — use the `docker-compose.yml` method below instead.

### Step 1 — Get your API key

**Method A — from `.env`** (requires Phase 2 to have run first):
```bash
grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env
# Output example:
# BROWSER_AGENT_API_KEY=a3f8c2e1d4b...  (128-char hex string)
```

**Method B — from `docker-compose.yml`** (always available after Browser Agent install):
```bash
grep BROWSER_AGENT_API_KEY ~/OpenWebUI/docker-compose.yml
# Output example:
#       - BROWSER_AGENT_API_KEY=a3f8c2e1d4b...
```

**Method C — from the running container** (most reliable):
```bash
docker exec browser-agent printenv BROWSER_AGENT_API_KEY
```

### Step 2 — Set the key as a variable (for easier use)

```bash
# From .env (if it exists)
BKEY=$(grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env 2>/dev/null | cut -d= -f2)

# From docker-compose.yml (fallback)
[ -z "$BKEY" ] && BKEY=$(grep BROWSER_AGENT_API_KEY ~/OpenWebUI/docker-compose.yml | awk -F= '{print $2}' | tr -d ' ')

# From the running container (most reliable fallback)
[ -z "$BKEY" ] && BKEY=$(docker exec browser-agent printenv BROWSER_AGENT_API_KEY 2>/dev/null)

echo "Key: $BKEY"
```

### Step 3 — API usage examples

**Health check (no auth required)**
```bash
curl http://localhost:8001/health
# Response: {"status":"ok","version":"6.4.0"}
```

**Single-agent browsing — `/browse`** (POST)
```bash
curl -s -X POST http://localhost:8001/browse \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{
    "task": "Search for the latest news about OpenAI and summarize it",
    "url": "https://www.google.com",
    "max_steps": 15
  }' | python3 -m json.tool
```

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `task` | string | ✅ | — | Task description (max 2,000 chars) |
| `url` | string | ❌ | `""` | Starting URL (max 500 chars) |
| `max_steps` | int | ❌ | `15` | Max browser steps (1–30) |

**Multi-agent browsing — `/browse/multi`** (POST, requires Groq API key)
```bash
curl -s -X POST http://localhost:8001/browse/multi \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{
    "task": "Compare the prices of iPhone 16 Pro across three shopping sites",
    "model": "llama-3.3-70b-versatile"
  }' | python3 -m json.tool
```

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `task` | string | ✅ | — | Task description |
| `model` | string | ❌ | `llama-3.3-70b-versatile` | Groq model to use |

**Streaming — `/browse/stream`** (POST, Server-Sent Events)
```bash
curl -s -N -X POST http://localhost:8001/browse/stream \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{"task": "Check today'\''s weather in Seoul", "max_steps": 10}'
# Streams: {"type":"start",...} → {"type":"progress",...} → {"type":"done",...}
```

**Batch processing — `/browse/batch`** (POST, up to 10 tasks)
```bash
curl -s -X POST http://localhost:8001/browse/batch \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{
    "tasks": [
      {"task": "Get the current Bitcoin price", "url": "https://coinmarketcap.com"},
      {"task": "Get today'\''s USD/KRW exchange rate"}
    ],
    "parallel": false
  }' | python3 -m json.tool
```

**Screenshot — `/screenshot`** (POST)
```bash
curl -s -X POST http://localhost:8001/screenshot \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com", "full_page": false}' \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('shot.jpg','wb').write(base64.b64decode(d['screenshot_b64']))"
# Saves screenshot as shot.jpg
```

**Task history — `/history`** (GET)
```bash
curl -s http://localhost:8001/history?limit=10 \
  -H "Authorization: Bearer $BKEY" | python3 -m json.tool
```

**Cancel a running task — `/tasks/{task_id}/cancel`** (POST)
```bash
curl -s -X POST http://localhost:8001/tasks/abc123/cancel \
  -H "Authorization: Bearer $BKEY"
```

**Session management** — save/load browser cookies & localStorage
```bash
# Save session
curl -s -X POST http://localhost:8001/sessions/my-session/save \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{"cookies": [], "localStorage": {}}'

# Load session
curl -s http://localhost:8001/sessions/my-session \
  -H "Authorization: Bearer $BKEY"

# List all sessions
curl -s http://localhost:8001/sessions \
  -H "Authorization: Bearer $BKEY"

# Delete session
curl -s -X DELETE http://localhost:8001/sessions/my-session \
  -H "Authorization: Bearer $BKEY"
```

**Web monitoring — `/monitors`** (POST)  
Register a URL+keyword to auto-check at set intervals:
```bash
curl -s -X POST http://localhost:8001/monitors \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://shopping.example.com/product/123",
    "keyword": "price",
    "target_value": "50000",
    "label": "Product price check",
    "interval_minutes": 60
  }'
# Returns: {"id":"mon_xxxx","label":"Product price check"}

# List monitors
curl -s http://localhost:8001/monitors -H "Authorization: Bearer $BKEY"

# Trigger a manual check
curl -s -X POST http://localhost:8001/monitors/mon_xxxx/check \
  -H "Authorization: Bearer $BKEY"

# Delete monitor
curl -s -X DELETE http://localhost:8001/monitors/mon_xxxx \
  -H "Authorization: Bearer $BKEY"
```

**Pool & proxy status**
```bash
curl -s http://localhost:8001/pool/status  -H "Authorization: Bearer $BKEY"
curl -s http://localhost:8001/proxy/status -H "Authorization: Bearer $BKEY"
```

### API Key Rotation

To regenerate the key (e.g. if compromised):

```bash
# Generate a new 512-bit key
NEW_KEY=$(python3 -c "import secrets; print(secrets.token_hex(64))")

# Update .env
sed -i "s/^BROWSER_AGENT_API_KEY=.*/BROWSER_AGENT_API_KEY=${NEW_KEY}/" ~/OpenWebUI/.env

# Update the secrets file (used by the container)
echo -n "$NEW_KEY" | sudo tee ~/OpenWebUI/browser-agent/secrets/api_key > /dev/null
sudo chmod 640 ~/OpenWebUI/browser-agent/secrets/api_key

# Restart the container to apply
cd ~/OpenWebUI && docker compose restart browser-agent

echo "✅ API key rotated. New key: $NEW_KEY"
```

> ⚠️ After rotation, update the key in OpenWebUI tool settings (Settings → Tools → Browser Agent) and any external scripts using the old key.

---

## 🛠️ Common Commands

```bash
# ── Phase 2: Start / Stop ──────────────────────────────────────────
cd ~/OpenWebUI && docker compose up -d
cd ~/OpenWebUI && docker compose down

# ── Phase 3: Telegram ─────────────────────────────────────────────
cd ~/telegram-openwebui-bridge && docker compose up -d
cd ~/telegram-openwebui-bridge && docker compose down

# ── Restart individual services ────────────────────────────────────
cd ~/OpenWebUI && docker compose restart twilio-bot
cd ~/OpenWebUI && docker compose restart browser-agent

# ── View logs ──────────────────────────────────────────────────────
docker logs -f open-webui
docker logs -f twilio-bot
docker logs -f browser-agent
docker logs -f telegram-openwebui-bridge

# ── Audit logs ─────────────────────────────────────────────────────
cd ~/OpenWebUI && ./view-audit-log.sh           # Last 20 entries
cd ~/OpenWebUI && ./view-audit-log.sh tail      # Real-time stream
cd ~/OpenWebUI && ./view-audit-log.sh errors    # Errors only

# ── Access admin dashboard remotely ────────────────────────────────
ssh -L 8445:localhost:8445 user@YOUR_SERVER_IP
# Then open: http://localhost:8445/dashboard

# ── Verify full installation ───────────────────────────────────────
bash verify-install.sh
```

---

## 🔐 Security Checklist

### Phase 2 (21 items)
- [x] Twilio signature verification (`X-Twilio-Signature`)
- [x] API Secret Bearer token authentication
- [x] Port local binding
- [x] 6-digit PIN authentication + 30-minute auto-release
- [x] Sensitive input masking (`****`)
- [x] CORS restrictions
- [x] `.env` chmod 600
- [x] Docker Secrets (`/run/secrets/`)
- [x] Structured JSON audit log
- [x] Cloudflare Tunnel HTTPS
- [x] Default password elimination (auto-generated)
- [x] TTS injection prevention
- [x] `.gitignore` / `.dockerignore` auto-generated

### Phase 3 (26 items)
- [x] AES-256 Bot Token encryption
- [x] User ID whitelist
- [x] Rate limiting (30/min)
- [x] Input length limit + XSS defense
- [x] Webhook signature verification
- [x] Non-root container + Docker network isolation
- [x] Auto-block 3 failures → 10-min lockout
- [x] Dashboard brute-force: 5 failures → 15-min IP lock (timing-safe)
- [x] **[NEW]** Replay attack defense
- [x] **[NEW]** Prompt injection defense (9 patterns)
- [x] **[NEW]** File Magic Bytes validation
- [x] **[NEW]** AI response sensitive-data filter
- [x] **[NEW]** Structured audit log JSON
- [x] **[NEW]** Emergency block mode `/emergency`
- [x] **[NEW]** Seccomp profile

### Browser Agent (7 patches)
- [x] Seccomp profile (minimized syscalls)
- [x] `cap_drop ALL` + `no-new-privileges`
- [x] API key auth on all endpoints
- [x] VNC `127.0.0.1:5901` binding + UFW verification
- [x] Non-root execution (UID 1001)
- [x] CVE patches (2026-05)

**Recommended firewall:**
```bash
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

---

## ❓ Troubleshooting

**Docker permission error:**
```bash
sudo usermod -aG docker $USER
# Log out and back in, then retry
```

**OpenWebUI not responding:**
```bash
cd ~/OpenWebUI && docker compose ps
docker compose logs open-webui --tail=50
ss -tlnp | grep 3000
```

**Telegram bot not receiving messages:**
```bash
cd ~/telegram-openwebui-bridge && docker compose logs --tail=50
# Check webhook status:
curl https://api.telegram.org/bot<TOKEN>/getWebhookInfo
```

**Browser Agent health check fails:**
```bash
curl http://localhost:8001/health
docker logs browser-agent --tail=50
# Check Playwright inside container:
docker exec browser-agent python3 -c "from playwright.sync_api import sync_playwright; print('OK')"
```

**Secrets directory permission issues:**
```bash
sudo chown -R 1001:1001 ~/OpenWebUI/secrets/
sudo chmod 700 ~/OpenWebUI/secrets/
```

**Re-run verification after fixes:**
```bash
bash verify-install.sh
```

---

## 🔧 Maintenance

**OpenWebUI version downgrade** (e.g. v0.9.5 → v0.9.2)  
When a specific version causes issues such as tool calling 400 errors, you can roll back to a previous stable version.

```bash
# 1. Navigate to the OpenWebUI directory
cd ~/OpenWebUI

# 2. Change the image tag in docker-compose.yml to the desired version
#    (e.g., :main → :v0.9.2 — same approach for any version)
sed -i 's|ghcr.io/open-webui/open-webui:main|ghcr.io/open-webui/open-webui:v0.9.2|g' docker-compose.yml

# 3. Bring down containers and restart with the new version
docker compose down && docker compose up -d

# 4. Hard-refresh your browser with Ctrl+Shift+R to clear cache

# ──────────────────────────────────────
#  To restore back to the latest version:
cd ~/OpenWebUI
sed -i 's|ghcr.io/open-webui/open-webui:v0.9.2|ghcr.io/open-webui/open-webui:main|g' docker-compose.yml
docker compose down && docker compose up -d
```

> ⚠️ Rolling back across a major update that includes DB schema changes (e.g., v0.9.0) may cause compatibility issues. Always back up your data before a large-scale downgrade. Available version tags can be found on the [GitHub Releases](https://github.com/open-webui/open-webui/releases) page.

**Clean up leftover images after downgrade**  
Version changes leave old Docker images on disk. Clean them up with:

```bash
# Check unused image disk usage
docker system df

# Remove all unused images (running containers are not affected)
docker image prune -a -f
```

---

## 📜 License

MIT License — See [LICENSE](LICENSE) for details.

---
---

# 한국어 가이드

## 📋 개요

이 프로젝트는 [Open WebUI](https://github.com/open-webui/open-webui)를 기반으로 한 **프로덕션 레디, 보안 강화형 AI 에이전트 플랫폼**입니다. 3개의 설치 단계와 1개의 검증 스크립트로 구성됩니다.

| 스크립트 | 단계 | 버전 | 설명 |
|---|---|---|---|
| `start-openwebui-hardened.sh` | Phase 2 | v1.1.0-hardened | 핵심 스택: OpenWebUI + Qdrant + Twilio 전화/SMS 봇 + OpenAPI 도구 |
| `setup-telegram-openwebui-bridge-FINAL.sh` | Phase 3 | v2.0.0-hardened | 텔레그램 ↔ OpenWebUI 브릿지 (보안 26항목) |
| `setup-browser-agent-browser-use-v6.sh` | Browser | v6.4.0 | AI 브라우저 에이전트 + 멀티에이전트 (Groq + LangGraph) |
| `verify-install.sh` | 검증 | v5.0.0 | 전체 설치 대조 검증 (14개 섹션) |

---

## 🏗️ 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│                         사용자 인터페이스                         │
│   🌐 웹 브라우저    📞 전화/SMS    💬 텔레그램    🖥 VNC       │
│       :3000          (Twilio)      (Bot API)   :5901(로컬)    │
└──────┬──────────────┬──────────────┬──────────────┬─────────────┘
       │              │              │              │
       ▼              ▼              ▼              │
┌──────────────────────────────────────────────────┘
│         Cloudflare Tunnel (HTTPS, 포트 개방 불필요)
│                  ↓
│         Nginx (리버스 프록시)
│      Twilio 웹훅  │  텔레그램 웹훅
└────────┬──────────┼──────────────────────────────────┐
         │          │                                  │
┌────────▼────────┐ ┌──▼──────────────────┐ ┌──────────▼───────────┐
│  OpenWebUI      │ │  텔레그램 브릿지    │ │  브라우저 에이전트   │
│  :3000          │ │  :8444 (헬스/메트릭)│ │  :8001 (API)         │
├─────────────────┤ │  :8445 (대시보드)   │ │  :5901 VNC (로컬)    │
│  Twilio 봇      │ │  ※ 로컬 전용       │ └──────────────────────┘
│  :5000 (로컬)   │ └─────────────────────┘
│  :8020 (nginx)  │
├─────────────────┤
│  OpenAPI 도구   │
│  :8000 (로컬)   │
│  :8010 (nginx)  │
├─────────────────┤
│  Qdrant (RAG)   │
│  :6333 (로컬)   │
├─────────────────┤
│  Ollama (선택)  │
│  :11434 (로컬)  │
└─────────────────┘
```

---

## ⚙️ 시스템 요구사항

| 등급 | CPU | RAM | 비고 |
|---|---|---|---|
| 🚀 고성능 | 6코어 이상 | 16GB 이상 | 권장 |
| 💪 중상급 | 4코어 이상 | 8GB 이상 | 안정적 |
| 📊 중급 | 2코어 이상 | 4GB 이상 | 제한적 |
| 🐢 저사양 | 2코어 미만 | 4GB 미만 | 최소 동작 |

**사전 조건:**
- Ubuntu 20.04+ / Debian 11+ / WSL2 (Windows)
- Docker (미설치 시 자동 설치)
- `sudo` 권한이 있는 일반 사용자 (root 실행 불가)
- Ollama (선택, 자동 감지 및 설치 제안)
- Python 3.8+

---

## 🔐 보안 기능

### Phase 2 — 핵심 스택 (21항목)
- Twilio 서명 검증 (`X-Twilio-Signature`) + API Secret 인증
- 포트 로컬 바인딩 (불필요한 외부 노출 차단)
- PIN 6자리 잠금 + 30분 자동 해제 (파일 기반 영구 저장)
- Docker Secrets (`/run/secrets/`) 민감정보 암호화 분리
- 구조화된 JSON 감사 로그
- Cloudflare Tunnel HTTPS (포트 포워딩 불필요)
- `.env` 파일 권한 `600` 자동 설정
- `.gitignore` / `.dockerignore` 자동 생성 (유출 방지)
- TTS 인젝션 방지 (URL 파라미터 → 내부 저장소 조회)
- 민감 입력 마스킹 (API Key/Token/PIN → `****` 처리)
- 기본 비밀번호 제거 (`openssl rand` 자동 생성)

### Phase 3 — 텔레그램 브릿지 (26항목)
- Telegram Bot Token AES-256 암호화 저장
- Rate Limiting (분당 30회 / 사용자당)
- Telegram User ID 화이트리스트 (허용 목록만 접근)
- 입력 길이 제한 (4,096자) + XSS/인젝션 방어
- Webhook 서명 검증 (Secret Token)
- 컨테이너 non-root 실행
- Docker 네트워크 격리 (internal network)
- 민감정보 로그 마스킹
- Health check + 자동 복구
- 파일 업로드 크기 제한 (20MB)
- 세션 타임아웃 (30분 비활동 시 대화 초기화)
- 관리자 전용 명령어 PIN 인증
- 3회 실패 → 10분 자동 잠금
- 로그 로테이션 (10MB × 3파일)
- 대시보드 Brute-force 방지: 5회 실패 → 15분 IP 잠금 (timing-safe)
- **[NEW]** Replay Attack 방어 (`update_id` 중복 요청 차단)
- **[NEW]** Prompt Injection 방어 (9개 정규식 패턴 감지·차단)
- **[NEW]** 파일 Magic Bytes 검증 (확장자 위조 방지)
- **[NEW]** AI 응답 민감정보 자동 필터링 (API키·JWT·전화번호)
- **[NEW]** 구조화된 감사 로그 JSON (`audit.log`)
- **[NEW]** 비상 차단 모드 `/emergency` (관리자 — 즉시 전체 차단)
- **[NEW]** Seccomp 프로파일 (허용 syscall 화이트리스트)

### 브라우저 에이전트 — v6.4.0 (7개 보안 패치)
- Seccomp 프로파일 (`seccomp-browser.json`) — 허용 syscall 최소화
- `cap_drop ALL` + `no-new-privileges` (권한 상승 차단)
- API 키 인증 (모든 요청에 Bearer 토큰 필수)
- VNC 포트 `127.0.0.1:5901` 전용 바인딩 + UFW 방화벽 검증
- 512비트 Browser API 키 자동 생성
- non-root 실행 (UID 1001)
- CVE 보안 패치 적용 (2026-05)

---

## 🚀 설치 방법

> **스크립트는 순서대로 실행하세요.** 각 단계는 이전 단계가 완료되어야 합니다.

### Step 0 — 저장소 클론

```bash
git clone https://github.com/hackyhappy-labs/HackyHappy.git
cd HackyHappy
chmod +x *.sh
```

### Step 1 — Phase 2: 핵심 스택 설치

```bash
bash start-openwebui-hardened.sh
```

**설치 내용:**
- OpenWebUI (Qdrant RAG + Ollama/Groq 연동)
- Twilio 전화봇 (AI 자동 전화, 다국어 TTS/STT)
- SMS 양방향 통신 (답장 자동 전달)
- OpenAPI Tools 서버 (`:8000` 내부 / `:8010` Nginx 외부)
- Cloudflare Tunnel (선택, 설치 중 안내)

**설치 중 입력 항목:**

| # | 항목 | 필수 여부 | 기본값 |
|---|---|---|---|
| 1 | Ollama 설치 여부 | 선택 | 사양에 따라 자동 제안 |
| 2 | Groq API Key | 선택 | 건너뜀 |
| 3 | Twilio Account SID | 선택 | 건너뜀 |
| 4 | Twilio Auth Token | 선택 | 건너뜀 |
| 5 | Twilio 전화번호 | 선택 | 건너뜀 |
| 6 | 관리자 전화번호 | 선택 | 건너뜀 |
| 7 | OpenWebUI 관리자 이메일 | 선택 | `admin@example.com` |
| 8 | OpenWebUI 관리자 비밀번호 | 선택 | 자동 생성 |
| 9 | 앱 이름 | 선택 | AI Assistant |
| 10 | 보안 PIN (6자리) | 선택 | 자동 생성 |

**자동 등록 도구 (8개):**

| # | 도구 | 설명 |
|---|---|---|
| 1 | Phone Assistant | 전화 걸기, 연락처 관리, 통화 기록 조회 |
| 2 | RAG Document Search | PDF/문서 벡터 검색 |
| 3 | SMS Sender | 문자 발송 + 답장 자동 전달 |
| 4 | Schedule Manager | 전화/SMS 예약 생성·조회·삭제 |
| 5 | Recording Manager | 녹음 파일 조회 및 재생 |
| 6 | PDF Report Manager | 통화 보고서 생성·조회 |
| 7 | Feature Status | 시스템 상태 모니터링 |
| 8 | Media Manager | 사진/영상/음성 파일 업로드·조회 |

### Step 2 — Phase 3: 텔레그램 브릿지 설치

```bash
bash setup-telegram-openwebui-bridge-FINAL.sh
```

**사전 조건:** OpenWebUI가 `http://localhost:3000`에서 실행 중이어야 합니다.

**설치 내용:**
- 텔레그램 봇 (webhook 모드)
- 브릿지 서버 (`:8444`) + 관리자 대시보드 (`:8445`, 로컬 전용)

**설치 중 입력 항목:**

| # | 항목 | 필수 여부 |
|---|---|---|
| 1 | Telegram Bot Token | ✅ ([@BotFather](https://t.me/BotFather)에서 발급) |
| 2 | OpenWebUI API Key | ✅ (설정 → 계정 → API Keys) |
| 3 | 허용할 텔레그램 User ID | ✅ ([@userinfobot](https://t.me/userinfobot)에서 확인) |
| 4 | Webhook 모드 / 도메인 | 선택 |
| 5 | 관리자 PIN | 선택 (자동 생성) |

### Step 3 — 브라우저 에이전트 설치 (선택)

```bash
bash setup-browser-agent-browser-use-v6.sh
```

**설치 내용:**
- Browser-Use + Playwright (DOM + A11y 하이브리드)
- 멀티에이전트 오케스트레이션 (Groq + LangGraph)
- 내장 도구 11개: `check_weather`, `check_price`, `check_stock`, `search_web`, `translate_text` 등
- Self-Healing 재시도 로직 + CVE 패치
- 에이전트 API (`:8001`)

**설치 중 입력 항목:**

| # | 항목 | 필수 여부 |
|---|---|---|
| 1 | OpenWebUI 외부 URL | ✅ |
| 2 | OpenWebUI 관리자 이메일 | ✅ |
| 3 | OpenWebUI 관리자 비밀번호 | ✅ |
| 4 | OpenWebUI API Key | ✅ |
| 5 | Groq API Key | 선택 (멀티에이전트용) |

**브라우저 에이전트 API 엔드포인트:**

| 엔드포인트 | 메서드 | 설명 |
|---|---|---|
| `/health` | GET | 헬스 체크 |
| `/browse` | POST | 단일 에이전트 브라우징 |
| `/browse/multi` | POST | 멀티에이전트 브라우징 |
| `/memory` | GET | 메모리 조회 |
| `/files` | GET | 파일 목록 조회 |

### Step 4 — 설치 검증

```bash
bash verify-install.sh
```

25개 디렉토리, 38개 필수 파일, 보안 권한, Docker 컨테이너, 네트워크, Secrets, Nginx 설정, 브라우저 에이전트, Seccomp 프로파일, 텔레그램 설정, Twilio 연동, OpenWebUI 도구, Cloudflare Tunnel을 **14개 섹션**으로 검증합니다.

---

## 🔌 서비스 포트 목록

| 서비스 | 포트 | 바인딩 | 설명 |
|---|---|---|---|
| Open WebUI | 3000 | 0.0.0.0 | 메인 웹 인터페이스 |
| Twilio 봇 | 5000 | localhost | 전화/SMS 봇 (내부) |
| Qdrant | 6333 | localhost | 벡터 DB + 대시보드 |
| OpenAPI Tools | 8000 | localhost | 도구 API (Swagger: `/docs`) |
| OpenAPI Tools (Nginx) | 8010 | 0.0.0.0 | Nginx 리버스 프록시 외부 노출 |
| Twilio 봇 (Nginx) | 8020 | 0.0.0.0 | Nginx 리버스 프록시 외부 노출 |
| 브라우저 에이전트 | 8001 | localhost | 브라우저 자동화 API |
| 텔레그램 브릿지 | 8444 | localhost | 헬스 체크 / Prometheus 메트릭 |
| 관리자 대시보드 | 8445 | localhost | **로컬 전용** — SSH 터널 필요 |
| VNC (브라우저) | 5901 | 127.0.0.1 | 브라우저 화면 뷰어 (로컬 전용) |
| Ollama | 11434 | localhost | 로컬 LLM (선택) |

---

## 📁 디렉토리 구조

```
~/OpenWebUI/                        # Phase 2 루트
├── .env                            # 환경 설정 (chmod 600)
├── docker-compose.yml
├── docker-compose.override.yml
├── .gitignore
├── .dockerignore
├── view-audit-log.sh               # 감사 로그 뷰어
├── secrets/                        # Docker Secrets (chmod 700)
│   ├── twilio_auth_token
│   ├── api_secret
│   ├── groq_api_key
│   ├── admin_pin
│   ├── webui_secret_key
│   └── entrypoint-secrets.sh
├── tools-api/                      # OpenAPI Tools 서버
│   ├── main.py
│   ├── Dockerfile
│   └── requirements.txt
├── twilio-bot/                     # Twilio 전화/SMS 봇
│   ├── twilio_bot.py
│   ├── ai_config.py                # 다국어 / AI 설정
│   ├── scheduler.py
│   ├── call_history.py
│   ├── entrypoint.sh
│   ├── Dockerfile
│   ├── requirements.txt
│   └── data/
│       ├── contacts.json           # 첫 사용 시 자동 생성
│       ├── call_history.json       # 첫 사용 시 자동 생성
│       ├── schedules.json          # 첫 사용 시 자동 생성
│       ├── recordings/
│       └── reports/
├── browser-agent/                  # 브라우저 에이전트 (chmod 750)
│   ├── agent_server.py
│   ├── openwebui_tool.py
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── seccomp-browser.json
│   ├── logrotate.conf
│   ├── secrets/                    # (chmod 750)
│   ├── multi_agent/                # 멀티에이전트 모듈
│   └── data/
│       ├── screenshots/
│       ├── sessions/
│       ├── results/
│       └── audit/
└── logs/
    ├── twilio-bot/
    ├── openapi-tools/
    └── nginx/

~/telegram-openwebui-bridge/        # Phase 3 루트
├── .env                            # (chmod 600)
├── docker-compose.yml
├── bot/
│   ├── telegram_bot.py
│   ├── entrypoint.sh
│   ├── Dockerfile
│   └── requirements.txt
├── data/
├── logs/
└── secrets/                        # (chmod 700)
    ├── telegram_bot_token
    ├── openwebui_api_key
    ├── webhook_secret
    └── tg_admin_pin

~/ai-share/                         # 로컬 파일 공유 디렉토리
```

---

## 🤖 텔레그램 봇 명령어

| 명령어 | 설명 |
|---|---|
| `/start` | 대화 시작 + 사용 가이드 |
| `/model` | AI 모델 실시간 전환 |
| `/tools` | OpenWebUI 도구 활성화/비활성화 |
| `/clear` | 대화 기록 초기화 |
| `/history` | 대화 기록 조회 |
| `/status` | 시스템 상태 확인 (관리자 전용) |
| `/users` | 활성 사용자 목록 (관리자 전용) |
| `/block` / `/unblock` | 사용자 차단/해제 (관리자 전용) |
| `/emergency` | 비상 전체 차단 모드 (관리자 전용) |

---

## 🌍 다국어 지원 (Phase 2)

전화번호 국가코드 기반 자동 언어 감지:

| 국가코드 | 언어 | TTS 로케일 |
|---|---|---|
| `+82` | 한국어 | ko-KR |
| `+1` / `+44` | English | en-US |
| `+81` | 日本語 | ja-JP |
| `+86` | 中文 | zh-CN |

`~/OpenWebUI/twilio-bot/ai_config.py`의 `DEFAULT_LANG`, `COUNTRY_LANG_MAP`에서 수정 가능합니다.  
변경 적용: `cd ~/OpenWebUI && docker compose restart twilio-bot`

---

## 🔑 브라우저 에이전트 API 키 사용 설명서

브라우저 에이전트 API(`:8001`)의 모든 요청에는 Bearer 토큰이 필요합니다. 키는 설치 시 자동 생성되어 **두 곳**에 저장됩니다: `~/OpenWebUI/.env`와 `~/OpenWebUI/docker-compose.yml`의 `environment:` 블록.

> ⚠️ `~/OpenWebUI/.env`는 **Phase 2**(`start-openwebui-hardened.sh`)가 먼저 실행되어야 생성됩니다. Phase 2 없이 브라우저 에이전트만 단독 설치한 경우 `.env`가 없을 수 있으니 아래 방법 B 또는 C를 사용하세요.

### Step 1 — API 키 확인

**방법 A — `.env`에서 확인** (Phase 2가 먼저 실행된 경우):
```bash
grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env
# 출력 예시:
# BROWSER_AGENT_API_KEY=a3f8c2e1d4b...  (128자 hex 문자열)
```

**방법 B — `docker-compose.yml`에서 확인** (브라우저 에이전트 설치 후 항상 가능):
```bash
grep BROWSER_AGENT_API_KEY ~/OpenWebUI/docker-compose.yml
# 출력 예시:
#       - BROWSER_AGENT_API_KEY=a3f8c2e1d4b...
```

**방법 C — 실행 중인 컨테이너에서 직접 확인** (가장 확실한 방법):
```bash
docker exec browser-agent printenv BROWSER_AGENT_API_KEY
```

### Step 2 — 변수로 저장해두기 (curl 명령 반복 입력 방지)

```bash
# .env에서 읽기 (파일이 있는 경우)
BKEY=$(grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env 2>/dev/null | cut -d= -f2)

# docker-compose.yml에서 읽기 (대체 방법)
[ -z "$BKEY" ] && BKEY=$(grep BROWSER_AGENT_API_KEY ~/OpenWebUI/docker-compose.yml | awk -F= '{print $2}' | tr -d ' ')

# 실행 중인 컨테이너에서 읽기 (가장 확실한 대체 방법)
[ -z "$BKEY" ] && BKEY=$(docker exec browser-agent printenv BROWSER_AGENT_API_KEY 2>/dev/null)

echo "Key: $BKEY"
```

### Step 3 — API 사용 예제

**헬스 체크 (인증 불필요)**
```bash
curl http://localhost:8001/health
# 응답: {"status":"ok","version":"6.4.0"}
```

**단일 에이전트 브라우징 — `/browse`** (POST)
```bash
curl -s -X POST http://localhost:8001/browse \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{
    "task": "OpenAI 최신 뉴스를 검색해서 요약해줘",
    "url": "https://www.google.com",
    "max_steps": 15
  }' | python3 -m json.tool
```

| 필드 | 타입 | 필수 | 기본값 | 설명 |
|---|---|---|---|---|
| `task` | string | ✅ | — | 작업 설명 (최대 2,000자) |
| `url` | string | ❌ | `""` | 시작 URL (최대 500자) |
| `max_steps` | int | ❌ | `15` | 최대 브라우저 단계 수 (1–30) |

**멀티에이전트 브라우징 — `/browse/multi`** (POST, Groq API 키 필요)
```bash
curl -s -X POST http://localhost:8001/browse/multi \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{
    "task": "아이폰 16 Pro 가격을 쇼핑 사이트 3곳에서 비교해줘",
    "model": "llama-3.3-70b-versatile"
  }' | python3 -m json.tool
```

| 필드 | 타입 | 필수 | 기본값 | 설명 |
|---|---|---|---|---|
| `task` | string | ✅ | — | 작업 설명 |
| `model` | string | ❌ | `llama-3.3-70b-versatile` | 사용할 Groq 모델 |

**스트리밍 — `/browse/stream`** (POST, Server-Sent Events)
```bash
curl -s -N -X POST http://localhost:8001/browse/stream \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{"task": "오늘 서울 날씨 확인해줘", "max_steps": 10}'
# 스트림: {"type":"start",...} → {"type":"progress",...} → {"type":"done",...}
```

**배치 처리 — `/browse/batch`** (POST, 최대 10개 동시 작업)
```bash
curl -s -X POST http://localhost:8001/browse/batch \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{
    "tasks": [
      {"task": "비트코인 현재 가격 조회", "url": "https://coinmarketcap.com"},
      {"task": "오늘 달러 원화 환율 조회"}
    ],
    "parallel": false
  }' | python3 -m json.tool
```

**스크린샷 — `/screenshot`** (POST)
```bash
curl -s -X POST http://localhost:8001/screenshot \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com", "full_page": false}' \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('shot.jpg','wb').write(base64.b64decode(d['screenshot_b64']))"
# shot.jpg 파일로 저장됩니다
```

**작업 기록 조회 — `/history`** (GET)
```bash
curl -s "http://localhost:8001/history?limit=10" \
  -H "Authorization: Bearer $BKEY" | python3 -m json.tool
```

**실행 중인 작업 취소 — `/tasks/{task_id}/cancel`** (POST)
```bash
curl -s -X POST http://localhost:8001/tasks/abc123/cancel \
  -H "Authorization: Bearer $BKEY"
```

**세션 관리** — 브라우저 쿠키 & localStorage 저장/불러오기
```bash
# 세션 저장
curl -s -X POST http://localhost:8001/sessions/my-session/save \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{"cookies": [], "localStorage": {}}'

# 세션 불러오기
curl -s http://localhost:8001/sessions/my-session \
  -H "Authorization: Bearer $BKEY"

# 세션 목록
curl -s http://localhost:8001/sessions \
  -H "Authorization: Bearer $BKEY"

# 세션 삭제
curl -s -X DELETE http://localhost:8001/sessions/my-session \
  -H "Authorization: Bearer $BKEY"
```

**웹 모니터링 — `/monitors`** (POST)  
URL+키워드를 등록해두면 지정 주기마다 자동으로 변경 여부를 확인합니다:
```bash
# 모니터 등록
curl -s -X POST http://localhost:8001/monitors \
  -H "Authorization: Bearer $BKEY" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://shopping.example.com/product/123",
    "keyword": "가격",
    "target_value": "50000",
    "label": "상품 가격 모니터",
    "interval_minutes": 60
  }'
# 응답: {"id":"mon_xxxx","label":"상품 가격 모니터"}

# 모니터 목록
curl -s http://localhost:8001/monitors -H "Authorization: Bearer $BKEY"

# 수동으로 즉시 체크
curl -s -X POST http://localhost:8001/monitors/mon_xxxx/check \
  -H "Authorization: Bearer $BKEY"

# 모니터 삭제
curl -s -X DELETE http://localhost:8001/monitors/mon_xxxx \
  -H "Authorization: Bearer $BKEY"
```

**풀 & 프록시 상태 확인**
```bash
curl -s http://localhost:8001/pool/status  -H "Authorization: Bearer $BKEY"
curl -s http://localhost:8001/proxy/status -H "Authorization: Bearer $BKEY"
```

### API 키 교체 (로테이션)

키가 유출되었거나 주기적으로 교체가 필요할 때:

```bash
# 새 512비트 키 생성
NEW_KEY=$(python3 -c "import secrets; print(secrets.token_hex(64))")

# .env 업데이트
sed -i "s/^BROWSER_AGENT_API_KEY=.*/BROWSER_AGENT_API_KEY=${NEW_KEY}/" ~/OpenWebUI/.env

# 컨테이너가 읽는 secrets 파일 업데이트
echo -n "$NEW_KEY" | sudo tee ~/OpenWebUI/browser-agent/secrets/api_key > /dev/null
sudo chmod 640 ~/OpenWebUI/browser-agent/secrets/api_key

# 컨테이너 재시작해서 적용
cd ~/OpenWebUI && docker compose restart browser-agent

echo "✅ API 키 교체 완료. 새 키: $NEW_KEY"
```

> ⚠️ 키 교체 후 OpenWebUI 도구 설정(설정 → 도구 → Browser Agent)과 기존 키를 사용하는 외부 스크립트도 반드시 업데이트하세요.

---

## 🛠️ 자주 쓰는 명령어

```bash
# ── Phase 2: 시작 / 종료 ───────────────────────────────────────────
cd ~/OpenWebUI && docker compose up -d
cd ~/OpenWebUI && docker compose down

# ── Phase 3: 텔레그램 시작 / 종료 ─────────────────────────────────
cd ~/telegram-openwebui-bridge && docker compose up -d
cd ~/telegram-openwebui-bridge && docker compose down

# ── 개별 서비스 재시작 ─────────────────────────────────────────────
cd ~/OpenWebUI && docker compose restart twilio-bot
cd ~/OpenWebUI && docker compose restart browser-agent

# ── 로그 확인 ──────────────────────────────────────────────────────
docker logs -f open-webui
docker logs -f twilio-bot
docker logs -f browser-agent
docker logs -f telegram-openwebui-bridge

# ── 감사 로그 ──────────────────────────────────────────────────────
cd ~/OpenWebUI && ./view-audit-log.sh           # 최근 20개
cd ~/OpenWebUI && ./view-audit-log.sh tail      # 실시간 스트림
cd ~/OpenWebUI && ./view-audit-log.sh errors    # 오류만

# ── 원격에서 관리자 대시보드 접속 ──────────────────────────────────
ssh -L 8445:localhost:8445 user@서버IP
# 브라우저에서 접속: http://localhost:8445/dashboard

# ── 전체 설치 검증 ─────────────────────────────────────────────────
bash verify-install.sh
```

---

## ❓ 문제 해결

**Docker 권한 오류:**
```bash
sudo usermod -aG docker $USER
# 로그아웃 후 재접속, 스크립트 재실행
```

**OpenWebUI 응답 없음:**
```bash
cd ~/OpenWebUI && docker compose ps
docker compose logs open-webui --tail=50
ss -tlnp | grep 3000
```

**텔레그램 봇 메시지 수신 안 됨:**
```bash
cd ~/telegram-openwebui-bridge && docker compose logs --tail=50
# Webhook 등록 상태 확인:
curl https://api.telegram.org/bot<TOKEN>/getWebhookInfo
```

**브라우저 에이전트 헬스체크 실패:**
```bash
curl http://localhost:8001/health
docker logs browser-agent --tail=50
# 컨테이너 내부 Playwright 확인:
docker exec browser-agent python3 -c "from playwright.sync_api import sync_playwright; print('OK')"
```

**Secrets 디렉토리 권한 오류:**
```bash
sudo chown -R 1001:1001 ~/OpenWebUI/secrets/
sudo chmod 700 ~/OpenWebUI/secrets/
```

**수정 후 재검증:**
```bash
bash verify-install.sh
```

---

## 🔧 유지보수

**OpenWebUI 버전 다운그레이드** (예: v0.9.5 → v0.9.2)  
tool calling 400 에러 등 특정 버전에서 문제가 발생할 때, 이전 안정 버전으로 되돌릴 수 있습니다.

```bash
# 1. OpenWebUI 디렉토리로 이동
cd ~/OpenWebUI

# 2. docker-compose.yml의 이미지 태그를 원하는 버전으로 변경
#    (예: :main → :v0.9.2 / 다른 버전도 동일 방식)
sed -i 's|ghcr.io/open-webui/open-webui:main|ghcr.io/open-webui/open-webui:v0.9.2|g' docker-compose.yml

# 3. 컨테이너 내리고 새 버전으로 재시작
docker compose down && docker compose up -d

# 4. 브라우저에서 Ctrl+Shift+R 로 캐시 초기화

# ──────────────────────────────────────
#  다시 최신 버전으로 복원하려면:
cd ~/OpenWebUI
sed -i 's|ghcr.io/open-webui/open-webui:v0.9.2|ghcr.io/open-webui/open-webui:main|g' docker-compose.yml
docker compose down && docker compose up -d
```

> ⚠️ DB 스키마 변경이 포함된 대규모 버전 간 롤백은 호환성 문제가 생길 수 있습니다. 롤백 전 데이터를 반드시 백업하세요. 사용 가능한 버전 태그는 [GitHub Releases](https://github.com/open-webui/open-webui/releases) 페이지에서 확인할 수 있습니다.

**다운그레이드 후 이전 이미지 찌꺼기 정리**  
버전 변경 시 이전 Docker 이미지가 디스크에 남습니다. 아래 명령어로 정리하세요.

```bash
# 사용하지 않는 이미지 확인
docker system df

# 미사용 이미지 모두 삭제 (현재 실행 중인 컨테이너는 영향 없음)
docker image prune -a -f
```

---

## 📜 라이센스

MIT License — 자세한 내용은 [LICENSE](LICENSE)를 참조하세요.
