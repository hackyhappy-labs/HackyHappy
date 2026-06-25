# OpenWebUI + Twilio AI Phone Assistant + Calendar + Telegram + Browser Agent

**English** · **[한국어](README.ko.md)**

A self-hosted installation package that integrates an **AI phone assistant (Twilio)**, **calendar**, **Telegram bot**, and **AI browser agent** around OpenWebUI. Everything installs in one shot via Docker, with hardened security and multilingual support (Korean / English / Japanese / Chinese).

> **In one line** — Ask "what's on my schedule today" from phone, chat, Telegram, or the browser agent. Only the admin can reach sensitive features. Unknown callers are blocked (personal mode) or handled by the AI (customer mode).

---

## Table of Contents

- [Features](#features)
- [Two Operating Modes](#two-operating-modes)
- [Requirements](#requirements)
- [Installation](#installation)
- [Calendar Setup](#calendar-setup)
- [Call Authentication (Security)](#call-authentication-security)
- [Usage by Channel](#usage-by-channel)
- [Install Verification](#install-verification)
- [Recurrence Prevention / Troubleshooting](#recurrence-prevention--troubleshooting)
- [Security](#security)
- [Repository Layout](#repository-layout)
- [FAQ](#faq)

---

## Features

| Feature | Description |
|---------|-------------|
| 📞 AI Phone Assistant | Make/receive calls via Twilio, voice conversation, send SMS |
| 📅 Calendar | Query today's schedule from OpenWebUI's built-in calendar via chat, phone, Telegram, browser |
| 💬 Telegram Bot | Chat with OpenWebUI, index files, schedule reminders from Telegram |
| 🤖 Browser Agent | AI browses websites, takes screenshots, extracts data |
| 📚 RAG | Answers grounded in your uploaded documents |
| 🔒 Hardened Security | Container hardening, Docker Secrets, CVE patches, number-based call auth |

---

## Two Operating Modes

Choose one of the two main scripts depending on your use case.

| Mode | Script | When an unknown number calls | Calendar / commands |
|------|--------|------------------------------|---------------------|
| **Personal** | `start-openwebui-hardened-admin-only.sh` | Blocked immediately | Admin only |
| **Customer Support** | `start-openwebui-customer-support.sh` | AI handles a general consultation | Admin only (customers cannot access) |

> In **both** modes, sensitive features (calendar, SMS, commands) are restricted to the **admin** (the number entered during installation). Even in customer-support mode, a customer saying "what's my schedule today" cannot access the calendar.

---

## Requirements

- **OS**: Ubuntu 22.04+ (including WSL2) or any Linux running Docker
- **Docker** + Docker Compose
- **OpenWebUI 0.9.0 or later** (built-in calendar required)
- **Twilio account** (phone number, Account SID, Auth Token) — for phone features
- (Optional) Telegram Bot Token — for Telegram
- (Optional) Groq / OpenAI / Claude / Gemini API key — for AI models

---

## Installation

### Step 1 — Main install (OpenWebUI + phone assistant + calendar)

Download and run the script that matches your use case.

**Personal (your private AI assistant):**

```bash
wget https://YOUR-HOST/start-openwebui-hardened-admin-only.sh
less start-openwebui-hardened-admin-only.sh    # review before running (recommended)
chmod +x start-openwebui-hardened-admin-only.sh
./start-openwebui-hardened-admin-only.sh
```

**Customer support:**

```bash
wget https://YOUR-HOST/start-openwebui-customer-support.sh
chmod +x start-openwebui-customer-support.sh
./start-openwebui-customer-support.sh
```

Inputs during installation (in order):

| Item | Example | Notes |
|------|---------|-------|
| Your phone number | `+12025550123` | **Admin number** (permission to call the bot). Comma-separate for multiple |
| Twilio info | SID / Token / number | For phone features |
| Server domain | `https://yourdomain.com` | For Twilio webhooks |
| Admin email / password | — | For OpenWebUI login |
| AI mode | `2` | 1=OpenWebUI, 2=Groq, 3=forwarding |
| Contacts | `John,+12025559876` | Targets the bot **calls out to** (unrelated to call permission) |

> **There is no PIN input.** The previous PIN method has been retired; number-based admin authentication is applied automatically.

When installation finishes, the full stack (OpenWebUI, phone bot, RAG, etc.) starts automatically and **9 tools (including the calendar) are registered automatically**.

### Step 2 — Browser agent (optional)

```bash
chmod +x setup-browser-agent-calendar.sh
./setup-browser-agent-calendar.sh
```

### Step 3 — Telegram bot (optional)

```bash
chmod +x setup-telegram-bridge-calendar.sh
./setup-telegram-bridge-calendar.sh
```

> Run Steps 2 and 3 **after Step 1**. The calendar tool must already be registered in OpenWebUI.

---

## Calendar Setup

The calendar tool is **registered automatically** at install time, but you must enter an API key once to actually use it.

### Setup order (one time)

1. Log in to OpenWebUI as admin -> **Settings -> Account -> API Keys** and generate a key
2. Add today's events in the left **Calendar** panel
3. **Workspace -> Tools -> "Calendar (Today)" -> Valves** -> enter the key in `OPENWEBUI_API_KEY` -> Save
4. **Run "what's my schedule today" once in chat** <- the key step
5. Now phone and Telegram also respond to "what's my schedule today"

> **Step 4 matters.** This is when the key is written to a shared folder so the phone bot can read the calendar too.

### API key format

- `sk-...` format — **recommended** (never expires)
- `eyJ...` (JWT token) — works, but **expires**, so not recommended

> If a JWT key expires, the phone says "the key may have expired; please set a new key." It never fabricates a fake schedule.

### Where to enter the key per channel

| Channel | Access method | Key location |
|---------|---------------|--------------|
| Chat | Calls the "Calendar (Today)" tool directly | That tool's valve |
| Phone | Detects "schedule today" keyword -> queries with shared key | (shares the chat key) |
| Telegram | Auto-enables all tools -> calendar included | (shares the chat key) |
| Browser Agent | A method inside the "AI Browser Agent" tool | **Enter separately in that tool's valve** (`OPENWEBUI_API_KEY`) |

> Only the browser agent needs the same key entered again in its own valve (it's a separate tool). It's the **`OPENWEBUI_API_KEY`** field — not `BROWSER_AGENT_API_KEY` or `LLM_API_KEY`.

---

## Call Authentication (Security)

### PIN retired -> admin numbers only

The previous PIN input method has been **completely removed**. When an unknown person calls, they are not asked for a PIN — they are blocked immediately (personal mode).

**Why this is safer:** a PIN can be passed by anyone who learns it, whereas the number-based method requires an actual call from a registered number.

### Admin number vs. contact — don't confuse them

| Type | What it is | Direction |
|------|-----------|-----------|
| **Admin number** (`ADMIN_NUMBERS`) | The number you entered at install | Permission to **call** the bot |
| **Contact** | A "John ..." saved in chat | A target the bot **calls** |

> Saving "John" as a contact does not let John call the bot (personal mode). To allow John to call in, add his number to **`ADMIN_NUMBERS`**.

### Add / change admin numbers

```bash
cd ~/OpenWebUI
read -p "Admin numbers (e.g. +12025550123,+12025559999): " NEW_ADMINS
sed -i "s/ADMIN_NUMBERS=.*/ADMIN_NUMBERS=$NEW_ADMINS/" .env
docker compose up -d twilio-bot
```

---

## Usage by Channel

### Phone

Call the bot from an admin number, then speak naturally:

- "What's my schedule today?" -> calendar read aloud
- "Call John for me" -> bot calls John
- "Send a text" -> SMS sent

### Chat (OpenWebUI)

Enable the tool and ask naturally:

- "What's my schedule today?"
- "Show me the call log"

### Telegram

Message the bot:

- "What's my schedule today?" -> calendar lookup
- Send a file (PDF/image) -> RAG indexing
- `/remind daily 09:00 tell me the weather` -> schedule a reminder

### Browser Agent

In chat:

- "Find the price on site X"
- "What's my schedule today?" (calendar method)

---

## Install Verification

Automatically checks consistency after installation.

```bash
chmod +x verify-install.sh
./verify-install.sh
```

Checks (partial):

- Directory structure / required files / permissions
- Docker container status / network
- 9 tools registered (including the calendar)
- **Calendar integration** — `/owui-data` mount, shared key, COMPOSE_FILE pinning
- **Security hardening** — requests/urllib3 CVE patches, trust_env
- **Call auth** — admin numbers set, operating-mode detection

---

## Recurrence Prevention / Troubleshooting

### When the phone reports a "fake schedule"

This is almost always a **missing calendar volume mount**. The current version pins the mount into the main compose file **and** into `COMPOSE_FILE` in `.env`, **permanently solving it**. The calendar stays connected however you bring it up — `docker compose up`, `restart`, or a server reboot.

Manual check:

```bash
# Check the mount (should exist)
docker exec twilio-bot ls -la /owui-data/

# Check the shared key (should have a value)
docker exec twilio-bot cat /owui-data/shared-key/openwebui_api_key
```

If the mount is missing:

```bash
cd ~/OpenWebUI
./calendar-up.sh
```

### Calendar tool times out in chat (15s read timeout)

If the **chat** calendar tool times out at 15 seconds even though `curl` to the same API is instant, the cause is a **single-worker self-call deadlock**: OpenWebUI runs the tool on its only worker, and the tool calls OpenWebUI's own API — which no worker is free to answer.

Fix — run OpenWebUI with multiple workers (**already applied by the current scripts**):

```bash
cd ~/OpenWebUI
# docker-compose.yml must have this under the open-webui service environment:
#   - UVICORN_WORKERS=4
docker compose up -d open-webui   # should show "Started"/"Recreated", not just "Running"

# Verify
docker exec openwebui-open-webui-1 sh -c 'cat /proc/1/environ | tr "\0" "\n" | grep UVICORN_WORKERS'
```

> Each worker uses extra memory. If memory is tight, `UVICORN_WORKERS=2` is enough to break the deadlock.

### Messages when a calendar lookup fails

On failure, the bot reports the exact cause instead of fabricating a schedule:

| Situation | Message |
|-----------|---------|
| Key not set | "The calendar key is not set..." |
| Connection failed | "Could not connect to the calendar server..." |
| Key expired (JWT) | "The key may have expired; please set a new key" |

---

## Security

| Item | Detail |
|------|--------|
| Call auth | Registered admin numbers only (PIN retired) |
| requests | `>=2.34.2` — patches CVE-2024-47081 (netrc credential leak) |
| urllib3 | `>=2.6.3` — patches CVE-2026-21441 (DoS) |
| trust_env | Disables environment credentials + blocks redirects on calendar lookups |
| Containers | no-new-privileges, cap_drop ALL, non-root, memory limits |
| Secrets | Stored separately via Docker Secrets |
| Twilio | Request signature validation (`validate_twilio_request`), hmac compare |
| Calendar scope | Admin-only even in customer-support mode |

> CVE patch versions are accurate as of writing. Re-check the latest advisories before deploying.

---

## Repository Layout

```
.
├── start-openwebui-hardened-admin-only.sh   # main install (personal)
├── start-openwebui-customer-support.sh      # main install (customer support)
├── setup-browser-agent-calendar.sh          # browser agent + calendar
├── setup-telegram-bridge-calendar.sh        # Telegram bot + calendar
├── verify-install.sh                        # install verification
└── docs/                                    # HTML install guide (Korean)
    ├── index.html                           # getting started · requirements
    ├── install.html                         # install · phone · calendar · call auth
    ├── operations.html                      # RAG · security · maintenance · backup
    ├── usage.html                           # Telegram bot
    ├── browser-agent.html                   # browser agent
    └── cloud.html                           # cloud deployment (24/7)
```

Key files created after install (`~/OpenWebUI/`):

```
~/OpenWebUI/
├── docker-compose.yml                # main (includes calendar mount)
├── docker-compose.calendar.yml       # calendar backup (usually unnecessary)
├── .env                              # COMPOSE_FILE pinned (recurrence prevention)
├── calendar-up.sh                    # restart with calendar included
├── twilio-bot/                       # phone bot
├── tools-api/                        # RAG · tools API
└── secrets/                          # Docker Secrets
```

---

## FAQ

**Q. The calendar doesn't work on the phone.**
A. Make sure you ran "what's my schedule today" once in chat — that's when the key is shared with the phone bot. If it still fails, follow the mount checks in [Recurrence Prevention](#recurrence-prevention--troubleshooting).

**Q. My API key starts with `eyJ...`, not `sk-`.**
A. That's a JWT token. It works but expires. Use the separate "Create API Key" button under Settings -> Account to generate an `sk-` key that never expires.

**Q. If I save a contact in chat, can that person call in?**
A. No. A contact is only a target the bot **calls out to**. To let someone call the bot, add their number to **`ADMIN_NUMBERS`**.

**Q. In customer-support mode, can customers see the calendar?**
A. No. Customers get general AI consultation only. Sensitive features (calendar, SMS, commands) are admin-only.

**Q. Telegram also had a PIN?**
A. The Telegram bot's PIN is **separate** from the phone bot's (it's for Telegram user auth) and is optional. Only the phone bot's PIN was retired.

**Q. Will the calendar break again after a reboot?**
A. No. Recurrence prevention pins the mount into the main compose and `.env`. It stays connected no matter how you start it.

---

## License / Contributing

Review each script before using this repository. Be sure to check the terms and pricing of your self-hosted environment and external services (Twilio, Telegram, AI providers).

> ⚠️ This package uses **billable external services** such as phone, SMS, and AI APIs. Monitor your usage and costs.
