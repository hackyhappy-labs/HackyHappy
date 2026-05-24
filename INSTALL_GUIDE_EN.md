# 🤖 OpenWebUI AI Agent — Installation Guide

> **OpenWebUI + RAG + Twilio Voice Bot + Telegram Bridge + Browser Agent (Multi-Agent)**
>
> A Docker-based all-in-one AI agent platform that unifies web chat, phone/SMS, Telegram, and browser automation.

---

## 📋 Table of Contents

1. [System Requirements](#-system-requirements)
2. [Architecture Overview](#-architecture-overview)
3. [Phase 2 — OpenWebUI + RAG + Twilio Voice Bot](#-phase-2--openwebui--rag--twilio-voice-bot)
4. [Phase 3 — Telegram Bridge](#-phase-3--telegram-bridge)
5. [Browser Agent — AI Browser Automation](#-browser-agent--ai-browser-automation)
6. [Installation Verification](#-installation-verification)
7. [Directory Structure](#-directory-structure)
8. [Service Port Map](#-service-port-map)
9. [Common Commands](#-common-commands)
10. [Security Checklist](#-security-checklist)
11. [Troubleshooting](#-troubleshooting)
12. [Maintenance](#-maintenance)
13. [License](#-license)

---

## 💻 System Requirements

| Item | Minimum | Recommended |
|------|---------|-------------|
| OS | Ubuntu 20.04+ / Debian 11+ | Ubuntu 22.04 LTS |
| CPU | 2 cores | 4+ cores |
| RAM | 4GB | 8GB+ (16GB recommended) |
| Disk | 20GB | 50GB+ |
| Docker | Auto-installed by script | Latest version |
| Network | Internet connection required | Static IP or domain (for Twilio/Telegram) |

The script automatically detects your system specs and optimizes memory allocation accordingly.

| Detected Tier | CPU | RAM | Description |
|---------------|-----|-----|-------------|
| 🚀 High | 6+ cores | 16GB+ | Full performance for all features |
| 💪 Mid-High | 4+ cores | 8GB+ | Stable operation |
| 📊 Mid | 2+ cores | 4GB+ | Basic feature operation |
| 🐢 Low | Other | Other | Limited operation |

---

## 🏗 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Interfaces                          │
│   🌐 Web Browser    📞 Phone/SMS    💬 Telegram      🖥 VNC    │
│       :3000          (Twilio)       (Bot API)       :5901     │
└──────┬──────────────┬──────────────┬──────────────┬─────────────┘
       │              │              │              │
┌──────▼──────┐ ┌─────▼─────┐ ┌─────▼──────┐ ┌────▼─────────┐
│  Open WebUI │ │ Twilio Bot │ │  Telegram  │ │   Browser    │
│   :3000     │ │   :5000    │ │   Bridge   │ │    Agent     │
│             │ │   :8020    │ │            │ │   :8001      │
└──────┬──────┘ └─────┬─────┘ └─────┬──────┘ └────┬─────────┘
       │              │              │              │
┌──────▼──────────────▼──────────────▼──────────────▼──────────┐
│                   Docker Network (openwebui_net)              │
├─────────────┬──────────────┬──────────────────────────────────┤
│  Qdrant     │  tools-api   │  Ollama (optional)               │
│  :6333      │  :8000/:8010 │  :11434                         │
│  Vector DB  │  RAG/Tool API│  Local LLM                      │
└─────────────┴──────────────┴──────────────────────────────────┘
```

---

## 🚀 Phase 2 — OpenWebUI + RAG + Twilio Voice Bot

Installs the core platform: OpenWebUI, Qdrant vector DB, OpenAPI Tools, and the Twilio voice/SMS bot.

### Prerequisites (Optional)

- **Groq API Key** — Get one free at [console.groq.com](https://console.groq.com)
- **Twilio Account** — Sign up at [twilio.com](https://www.twilio.com) and obtain your Account SID, Auth Token, and phone number
- **Ollama** — Required for running local LLMs (the script will offer to install it automatically)

### Run the Installer

```bash
# Download and run the script
bash start-openwebui-hardened.sh
```

### Interactive Setup Prompts

The script interactively asks for the following information. All fields are **optional** — press Enter to skip.

| # | Prompt | Description | Default |
|---|--------|-------------|---------|
| 1 | Install Ollama | For running local LLMs | Y/N based on specs |
| 2 | Groq API Key | Cloud LLM integration | Skip |
| 3 | Twilio Account SID | Phone/SMS features | Skip |
| 4 | Twilio Auth Token | Phone/SMS authentication | Skip |
| 5 | Twilio Phone Number | Outbound caller ID | Skip |
| 6 | Admin Phone Number | For receiving reports | Skip |
| 7 | OpenWebUI Admin Email | Login account | admin@example.com |
| 8 | OpenWebUI Admin Password | Login password | Auto-generated |
| 9 | App Name | WebUI display name | AI Assistant |
| 10 | AI Mode | API Only / Ollama / Hybrid | Auto-detected |
| 11 | Security PIN (6 digits) | Admin authentication | Auto-generated |

> ⚠️ All sensitive inputs are masked with `****` after entry. If left blank, passwords are securely auto-generated using `openssl rand`.

### Auto-Registered Tools (8)

| # | Tool | Description |
|---|------|-------------|
| 1 | Phone Assistant | Make calls, manage contacts, view call history |
| 2 | RAG Document Search | Vector search across PDF/documents |
| 3 | SMS Sender | Send text messages + auto-forward replies |
| 4 | Schedule Manager | Create, view, and delete phone/SMS schedules |
| 5 | Recording Manager | Browse and play call recordings |
| 6 | PDF Report Manager | Generate and view call reports |
| 7 | Feature Status | System status monitoring |
| 8 | Media Manager | Upload and browse photos/videos/audio files |

### Multilingual Support

The system auto-detects the caller's language based on the phone number country code and switches TTS/STT accordingly.

| Country Code | Language | TTS Locale |
|--------------|----------|------------|
| +82 | Korean | ko-KR |
| +1, +44 | English | en-US |
| +81 | Japanese | ja-JP |
| +86 | Chinese | zh-CN |

To change settings, edit `DEFAULT_LANG` and `COUNTRY_LANG_MAP` in `~/OpenWebUI/twilio-bot/ai_config.py`, then run `docker compose restart twilio-bot`.

### Twilio SMS Webhook Setup (Manual)

If using the Twilio voice bot, you must manually configure the SMS webhook:

1. Go to [Twilio Console](https://console.twilio.com/)
2. Navigate to **Phone Numbers → Manage → Active numbers**
3. Click your phone number
4. Under **Messaging Configuration**:
   - **A MESSAGE COMES IN**: Webhook → `https://your-domain.com/sms-incoming` (HTTP POST)
5. Click **Save**

### Cloudflare Tunnel (Optional)

Enables external HTTPS access without opening ports. The script guides you through the setup automatically.

```bash
# Manual installation
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg
sudo cloudflared tunnel login
sudo cloudflared tunnel create my-tunnel
```

---

## 💬 Phase 3 — Telegram Bridge

Connects all OpenWebUI features (models, tools, RAG) to Telegram for mobile access.

### Prerequisites

- **Phase 2 installed** — OpenWebUI must be running at `http://localhost:3000`
- **Telegram Bot Token** — Create via [@BotFather](https://t.me/BotFather) using `/newbot`
- **OpenWebUI API Key** — Generate in OpenWebUI Settings → API Keys
- **Telegram User ID** — Check via [@userinfobot](https://t.me/userinfobot)

### Run the Installer

```bash
bash setup-telegram-openwebui-bridge-FINAL.sh
```

### Interactive Setup Prompts

| # | Prompt | Required | Description |
|---|--------|----------|-------------|
| 1 | Telegram Bot Token | ✅ | From BotFather |
| 2 | OpenWebUI API Key | ✅ | From OpenWebUI settings |
| 3 | Allowed User IDs | ✅ | Comma-separated whitelist |
| 4 | Webhook Mode | Optional | Polling (default) vs Webhook |
| 5 | Admin PIN | Optional | For admin commands (auto-generated) |

### Telegram Bot Commands

| Command | Description |
|---------|-------------|
| `/start` | Start the bot + usage guide |
| `/model` | Switch AI model (all models registered in OpenWebUI) |
| `/tools` | Enable/disable tools |
| `/clear` | Clear conversation history |
| `/history` | View recent conversation history |
| `/status` | System status (admin only) |
| `/users` | User list (admin only) |
| `/block`, `/unblock` | Block/unblock users (admin only) |

### Telegram Security Features (18 items)

- Telegram Bot Token stored with AES-256 encryption
- User ID whitelist (only allowed users can access)
- Rate limiting (30 requests/min per user)
- Input length limit (4,096 characters) + XSS/injection defense
- Webhook signature verification (Telegram Secret Token)
- Non-root container execution + Docker network isolation
- Auto-block after 3 failed attempts (10-minute lockout)
- Session timeout (conversation reset after 30 minutes of inactivity)
- File upload size limit (20MB)
- Log rotation (10MB × 3 files)

---

## 🌐 Browser Agent — AI Browser Automation

Installs a Browser Use + Playwright-based AI browser agent with optional Multi-Agent support (Groq + LangGraph).

### Prerequisites

- **Phase 2 installed** — OpenWebUI must be running
- **OpenWebUI Admin Credentials** — Email + password
- **OpenWebUI API Key** — Generate in settings
- **Groq API Key (optional)** — Required for Multi-Agent features

### Run the Installer

```bash
bash setup-browser-agent-browser-use-v6.sh
```

### Interactive Setup Prompts

| # | Prompt | Required | Description |
|---|--------|----------|-------------|
| 1 | OpenWebUI Admin Email | ✅ | The email set during Phase 2 |
| 2 | OpenWebUI Admin Password | ✅ | The password set during Phase 2 |
| 3 | OpenWebUI API Key | ✅ | From settings |
| 4 | Groq API Key | Optional | For Multi-Agent features |

### Key Features

- **Browser Use** — Hybrid DOM + Accessibility Tree web automation
- **Self-Healing** — Automatic retries on failure + CVE patches applied
- **Multi-Agent (v6.4.0)** — Multi-agent collaboration via Groq + LangGraph
- **Korean Bypass** — Automatic English-to-Korean mapping (Groq model compatibility)
- **Screenshot/Session Logging** — Automatic task history recording
- **Auto Tool Registration** — `ai_browser_agent` tool is automatically registered in OpenWebUI

### Browser Agent API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/browse` | POST | Single-agent browsing |
| `/browse/multi` | POST | Multi-agent browsing |
| `/memory` | GET | Memory inspection |
| `/files` | GET | File listing |

### Built-in Tools (11)

The agent automatically uses 11 built-in utility tools including `check_weather`, `check_price`, `check_stock`, `search_web`, `translate_text`, and more.

### Browser Agent Security

- **seccomp profile** — Minimized allowed syscalls (`seccomp-browser.json`)
- **cap_drop** — All Linux capabilities dropped
- **no-new-privileges** — Privilege escalation blocked
- **API key auth** — Bearer token required on all requests
- **Audit log** — `browser-agent/data/audit/agent.log`
- **VNC local binding** — Only `127.0.0.1:5901` accessible
- **Non-root execution** — Container runs as UID 1001

---

## ✅ Installation Verification

Run the verification script to check the entire installation at once.

```bash
bash verify-install.sh
```

### Verification Sections (13)

| # | Section | What It Checks |
|---|---------|----------------|
| 1 | Directory Structure | 25 directories — existence + permissions |
| 2 | Required Files | 38 required + 3 optional files |
| 3 | Security Permissions | `.env` (600), `secrets/` (700), etc. |
| 4 | Docker Containers | 5 containers — running status + health checks |
| 5 | Docker Networks | `openwebui_net` connectivity |
| 6 | Docker Secrets | 6 secrets mounted correctly |
| 7 | Nginx Config | Reverse proxy + audit logging |
| 8 | Browser Agent | API / Playwright / VNC operational checks |
| 9 | seccomp Profile | JSON validity + syscall count |
| 10 | Telegram Config | Bot token + allowed user IDs |
| 11 | Twilio Integration | Account SID + Telegram notification link |
| 12 | OpenWebUI Tools | Registered tool list verification |
| 13 | Cloudflare Tunnel | Installation and service status (optional) |

### Example Output

```
╔══════════════════════════════════════════════════════════════════════╗
║  OpenWebUI AI Agent — Full Installation Verification v4.0.0         ║
╚══════════════════════════════════════════════════════════════════════╝

── 1. Directory Structure (25) ──
  ✅  [Phase2] OpenWebUI root [755]
  ✅  [Phase2] tools-api [755]
  ✅  [Browser] browser-agent [755]
  ...

══════════════════════════════════════
  🎉 All checks passed!
══════════════════════════════════════
```

---

## 📁 Directory Structure

```
~/
├── OpenWebUI/                          # Phase 2 root
│   ├── .env                            # Environment variables (chmod 600)
│   ├── docker-compose.yml              # Main Compose file
│   ├── docker-compose.override.yml     # Docker Secrets override
│   ├── .gitignore                      # Prevents secrets/.env leaks
│   ├── .dockerignore
│   ├── view-audit-log.sh               # Audit log viewer
│   │
│   ├── secrets/                        # Docker Secrets (chmod 700)
│   │   ├── twilio_auth_token
│   │   ├── api_secret
│   │   ├── groq_api_key
│   │   ├── admin_pin
│   │   ├── webui_secret_key
│   │   └── entrypoint-secrets.sh
│   │
│   ├── tools-api/                      # OpenAPI Tool server
│   │   ├── main.py
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   │
│   ├── twilio-bot/                     # Twilio voice/SMS bot
│   │   ├── twilio_bot.py
│   │   ├── ai_config.py               # Multilingual / AI config
│   │   ├── scheduler.py               # Schedule manager
│   │   ├── call_history.py            # Call history tracker
│   │   ├── entrypoint.sh
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── data/
│   │       ├── contacts.json          # Contacts (auto-created)
│   │       ├── call_history.json      # Call history (auto-created)
│   │       ├── schedules.json         # Schedules (auto-created)
│   │       ├── recordings/            # Call recordings
│   │       └── reports/               # PDF reports
│   │
│   ├── browser-agent/                  # Browser Agent
│   │   ├── agent_server.py            # Main API server
│   │   ├── openwebui_tool.py          # OpenWebUI tool code
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   ├── seccomp-browser.json       # seccomp profile
│   │   ├── logrotate.conf
│   │   ├── secrets/                   # Agent-specific secrets
│   │   ├── multi_agent/               # Multi-Agent modules (7 files)
│   │   └── data/
│   │       ├── screenshots/           # Screenshots
│   │       ├── sessions/              # Session records
│   │       ├── results/               # Task results
│   │       └── audit/                 # Audit logs
│   │
│   └── logs/
│       ├── twilio-bot/
│       ├── openapi-tools/
│       └── nginx/
│
├── telegram-openwebui-bridge/          # Phase 3 root
│   ├── .env
│   ├── docker-compose.yml
│   ├── secrets/
│   │   ├── telegram_bot_token
│   │   ├── openwebui_api_key
│   │   ├── webhook_secret
│   │   └── tg_admin_pin
│   ├── bot/
│   │   ├── telegram_bot.py
│   │   ├── entrypoint.sh
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   ├── data/
│   └── logs/
│
└── ai-share/                           # Local file sharing directory
```

---

## 🔌 Service Port Map

| Service | Port | Binding | Description |
|---------|------|---------|-------------|
| Open WebUI | 3000 | 0.0.0.0 | Web interface |
| Twilio Bot | 5000 | localhost | Voice/SMS bot |
| Qdrant | 6333 | localhost | Vector DB dashboard |
| OpenAPI Tools | 8000 | localhost | Tool API (Swagger: /docs) |
| tools-api (external) | 8010 | 0.0.0.0 | Nginx reverse proxy |
| twilio-bot (external) | 8020 | 0.0.0.0 | Nginx reverse proxy |
| Browser Agent | 8001 | localhost | Browser automation API |
| VNC (Browser) | 5901 | 127.0.0.1 | Browser screen viewer |
| Ollama | 11434 | localhost | Local LLM (optional) |

---

## 🛠 Common Commands

### Service Management

```bash
# Phase 2 — Start / Stop all
cd ~/OpenWebUI && docker compose up -d
cd ~/OpenWebUI && docker compose down

# Phase 3 — Telegram start / stop
cd ~/telegram-openwebui-bridge && docker compose up -d
cd ~/telegram-openwebui-bridge && docker compose down

# Restart individual services
cd ~/OpenWebUI && docker compose restart twilio-bot
cd ~/OpenWebUI && docker compose restart browser-agent

# Check overall status
cd ~/OpenWebUI && docker compose ps
```

### View Logs

```bash
# Real-time logs
docker logs -f open-webui
docker logs -f twilio-bot
docker logs -f browser-agent
docker logs -f telegram-openwebui-bridge

# Audit logs
cd ~/OpenWebUI && ./view-audit-log.sh          # Last 20 entries
cd ~/OpenWebUI && ./view-audit-log.sh tail     # Real-time
cd ~/OpenWebUI && ./view-audit-log.sh errors   # Errors only
```

### Browser Agent API Testing

```bash
# Health check
curl http://localhost:8001/health

# Memory inspection
curl -s http://localhost:8001/memory | python3 -m json.tool

# File listing
curl -s http://localhost:8001/files | python3 -m json.tool
```

### Verify Installation

```bash
bash verify-install.sh
```

### Reinstall

```bash
# Reinstall Browser Agent only
rm -rf ~/OpenWebUI/browser-agent
bash setup-browser-agent-browser-use-v6.sh

# Reinstall Telegram Bridge
rm -rf ~/telegram-openwebui-bridge
bash setup-telegram-openwebui-bridge-FINAL.sh

# Full reinstall (preserves data)
cd ~/OpenWebUI && docker compose down
bash start-openwebui-hardened.sh
```

---

## 🔐 Security Checklist

### Phase 2 Security (21 items)

- [x] Twilio signature verification (X-Twilio-Signature)
- [x] API Secret authentication (Bearer Token)
- [x] Port local binding (blocks direct external access)
- [x] 6-digit PIN authentication (protects admin functions)
- [x] Sensitive input masking (API Key/Token → `****`)
- [x] CORS restrictions (allowed origins only)
- [x] `.env` chmod 600 (owner read/write only)
- [x] Docker Secrets (sensitive data stored in `/run/secrets/`)
- [x] Structured JSON audit logging
- [x] Cloudflare Tunnel HTTPS (optional)
- [x] Default password elimination (auto-generated via `openssl rand` when left blank)
- [x] Persistent PIN lockout (file-based + 30-minute auto-release)
- [x] TTS injection prevention
- [x] `.gitignore` / `.dockerignore` auto-generated

### Phase 3 Security (18 items)

- [x] Telegram Bot Token AES-256 encrypted storage
- [x] User ID whitelist
- [x] Rate limiting (30/min)
- [x] Input length limit (4,096 chars)
- [x] Webhook signature verification
- [x] Non-root container execution
- [x] Docker network isolation
- [x] Auto-block after 3 failures → 10-minute lockout

### Browser Agent Security

- [x] seccomp profile (minimized allowed syscalls)
- [x] cap_drop ALL + no-new-privileges
- [x] API key authentication (all requests)
- [x] VNC 127.0.0.1 binding
- [x] Audit log (`data/audit/agent.log`)
- [x] Non-root execution (UID 1001)

### Recommended Firewall Settings

```bash
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

---

## ❓ Troubleshooting

### Docker Permission Error

```
❌ Docker permission denied
```

```bash
sudo usermod -aG docker $USER
# Log out and back in, then re-run the script
```

### Container Health Check Failure

```bash
# Check status
docker inspect --format='{{.State.Health.Status}}' <container_name>

# View logs
docker logs <container_name> --tail 50
```

### Cannot Access OpenWebUI

```bash
# Check container status
docker compose ps

# Check port
ss -tlnp | grep 3000

# Restart
cd ~/OpenWebUI && docker compose restart open-webui
```

### Browser Agent API Not Responding

```bash
# Check from inside the container
docker exec browser-agent python3 -c "
import urllib.request
r = urllib.request.urlopen('http://localhost:8001/health', timeout=3)
print(r.read().decode())
"

# Check Playwright
docker exec browser-agent python3 -c "
from playwright.sync_api import sync_playwright
print('Playwright OK')
"
```

### Secrets Directory Permission Issues

```bash
# Set ownership to UID 1001 (container user)
sudo chown -R 1001:1001 ~/OpenWebUI/secrets/
sudo chmod 700 ~/OpenWebUI/secrets/
```

### Telegram Bot Not Connecting

```bash
# Check Bot Token
cat ~/telegram-openwebui-bridge/.env | grep TELEGRAM_BOT_TOKEN

# View logs
docker logs telegram-openwebui-bridge --tail 30

# Restart
cd ~/telegram-openwebui-bridge && docker compose restart
```

---

## 🔧 Maintenance

### OpenWebUI Version Downgrade

When issues occur on a specific version (e.g., tool calling 400 errors), you can roll back to a previous stable version.

```bash
# 1. Navigate to the OpenWebUI directory
cd ~/OpenWebUI

# 2. Change the image tag in docker-compose.yml to the desired version
#    (e.g., :main → :v0.9.2 — same approach for any version)
sed -i 's|ghcr.io/open-webui/open-webui:main|ghcr.io/open-webui/open-webui:v0.9.2|g' docker-compose.yml

# 3. Bring down the containers and restart with the new version
docker compose down && docker compose up -d

# 4. Hard-refresh your browser with Ctrl+Shift+R to clear cache
```

To restore to the latest version:

```bash
cd ~/OpenWebUI
sed -i 's|ghcr.io/open-webui/open-webui:v0.9.2|ghcr.io/open-webui/open-webui:main|g' docker-compose.yml
docker compose down && docker compose up -d
```

> ⚠️ **Warning:** Rolling back across a major update that includes DB schema changes (e.g., v0.9.0) may cause compatibility issues. Always back up your data before a large-scale downgrade.

Available version tags can be found on the [GitHub Releases](https://github.com/open-webui/open-webui/releases) page.

### Cleaning Up Old Images After Downgrade

Version changes leave old Docker images on disk. Clean them up with:

```bash
# Check unused image disk usage
docker system df

# Remove all unused images (running containers are not affected)
docker image prune -a -f
```

---

## 📜 License

MIT License

---

## 📌 Version Information

| Component | Version | Script |
|-----------|---------|--------|
| OpenWebUI + RAG + Twilio | v1.1.0-hardened | `start-openwebui-hardened.sh` |
| Telegram Bridge | v1.4.0-hardened+integration | `setup-telegram-openwebui-bridge-FINAL.sh` |
| Browser Agent (Multi-Agent) | v6.4.0 | `setup-browser-agent-browser-use-v6.sh` |
| Installation Verification | v4.0.0 | `verify-install.sh` |

---

## ⚡ Quick Start

```bash
# Step 1: Phase 2 — Install the core platform
bash start-openwebui-hardened.sh

# Step 2: Phase 3 — Telegram integration (optional)
bash setup-telegram-openwebui-bridge-FINAL.sh

# Step 3: Install Browser Agent (optional)
bash setup-browser-agent-browser-use-v6.sh

# Step 4: Verify the full installation
bash verify-install.sh
```

After installation, access OpenWebUI at `http://localhost:3000`.
