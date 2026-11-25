# HackyHappy Labs — OpenWebUI + Twilio AI Phone Assistant + Telegram + Browser Agent + WebRTC + AI Security Monitoring

**English** · **[한국어](README_ko.md)**

A Docker-based self-hosting installation package centered around OpenWebUI that integrates an **AI Phone Assistant (Twilio)**, **Calendar integration**, **Telegram**, an **AI Browser Agent**, **self-hosted WebRTC 1-on-1 video calling**, and **AI Security Monitoring**. It deploys in one go via Docker and supports hardened security and multiple languages (Korean / English / Japanese / Chinese).

> **One-Line Summary** — Ask "What's on my schedule today?" from phone, chat, Telegram, or browser; restrict sensitive features strictly to administrators; and either block unknown callers (Personal mode) or let AI handle them as a customer service agent (Customer mode).

> ⚠️ **Version Notice (Please Read First):** This package created by HackyHappy Labs is **up-to-date based on OpenWebUI version 0.9.6**. If you need another (newer) release, please visit the [OpenWebUI Official Site / GitHub](https://github.com/open-webui/open-webui) to upgrade manually or verify compatibility for that version. In higher versions, some UIs and APIs differ, which may alter tool registration or calendar behavior.

---

## Table of Contents

- [Key Features](#key-features)
- [Two Operating Modes](#two-operating-modes)
- [Requirements](#requirements)
- [Installation](#installation)
- [Calendar Setup](#calendar-setup)
- [Call Authentication (Security)](#call-authentication-security)
- [Call Features (Barge-In · Operator Transfer)](#call-features-barge-in--operator-transfer)
- [True Real-Time Proxy Calls (Media Streams)](#true-real-time-proxy-calls-media-streams)
- [Real-Time Whisper (In-Call Instructions)](#real-time-whisper-in-call-instructions)
- [Voice Engine Settings (STT/TTS Valve Switching)](#voice-engine-settings-stttts-valve-switching)
- [🧠 Memory Anchor (Call Recall · Proactive Auto-Calls)](#-memory-anchor-call-recall--proactive-auto-calls)
- [🧠🧠 VoiceMem Dual-Brain Architecture (Left & Right Brain Memory)](#-voicemem-dual-brain-architecture-left--right-brain-memory)
- [📍 Location Check (NAVER + Kakao + Google)](#-location-check-naver--kakao--google)
- [🛰️ GPS Location Sharing (Senior Care)](#️-gps-location-sharing-senior-care)
- [📹 1-on-1 Video Calling (Self-Hosted WebRTC)](#-1-on-1-video-calling-self-hosted-webrtc)
- [🛡️ AI Security Monitoring (SSH · Nginx · CrowdSec)](#️-ai-security-monitoring-ssh--nginx--crowdsec)
- [Automatic Ollama Embedding Setup (WSL2)](#automatic-ollama-embedding-setup-wsl2)
- [Monthly Call Time Limit (Billing Protection)](#monthly-call-time-limit-billing-protection)
- [Automatic Twilio Configuration](#automatic-twilio-configuration)
- [Cloudflare Tunnel Setup (External HTTPS Access)](#cloudflare-tunnel-setup-external-https-access)
- [Usage by Channel](#usage-by-channel)
- [Installation Verification](#installation-verification)
- [Prevention & Troubleshooting](#prevention--troubleshooting)
- [Security](#security)
- [File Structure](#file-structure)
- [Frequently Asked Questions (FAQ)](#frequently-asked-questions-faq)

---

## Key Features

| Feature | Description |
|---------|-------------|
| 📞 AI Phone Assistant | Make/receive phone calls via Twilio, hold voice conversations, and send SMS |
| 🎙️ True Real-Time Proxy Calls | Immediate **barge-in even while talking** via Twilio Media Streams. Deepgram (STT) + ElevenLabs (TTS), switch engines in valves |
| 🤫 Real-Time Whisper | While AI is on a call, admins can instruct **"Say this..."** via Telegram/App → AI naturally weaves it into its next utterance |
| 🧠 Memory Anchor | Embeds and saves call transcripts by phone number → **automatically recalls past memories from similar times of day/weather** on the next call to guide conversation. Proactively suggests check-in calls when conditions match (optional) |
| 🧠🧠 VoiceMem Dual-Brain | The memory engine powering Memory Anchor. Splits and recalls call memories into **Left Brain (Facts/Structure: who, when, what)** and **Right Brain (Emotion/Context: mood, associations)**. Optional feature; factual memory uses VoiceMem's local embeddings (E5 family) + OpenAI LLM analysis, while emotional/personality profiles accumulate in separate JSON files |
| 📍 Location Check (NAVER + Kakao + Google) | Asks for location **after obtaining consent** during a check-in call, and **reports the spoken location to Telegram** with a map image. Finds coordinates via NAVER Geocoding (road/lot addresses) + Kakao Local (stations, businesses, buildings), and renders **Google hybrid satellite imagery** (falls back to NAVER standard map if no Google key). Never secretly collects phone GPS |
| 🛰️ GPS Location Sharing (Senior Care) | Sends a **location-sharing link via phone call + SMS**. When the recipient opens the link and **explicitly taps [Allow]**, real-time GPS coordinates are sent to the admin's Telegram and SMS. Solves the limitation of not being able to fetch GPS via voice call alone using link + browser geolocation permission. 5-layer security (random token, one-time use, time limit, HTTPS, target number binding) |
| 📹 1-on-1 Video Calling | Self-hosted WebRTC 2-person video/audio calls. Sends an invite SMS and AI guide call by contact name or phone number, and displays a join link in the admin chat that opens in a new tab. Expires if both parties don't join within 10 minutes; unlimited call duration once connected. Session ends when either party leaves. Does not use external Jitsi services or external meeting JS SDKs |
| 🛡️ AI Security Monitoring | Monitors Docker service health, SSH auth logs, Nginx JSON audit logs, and CrowdSec detections/bans. Logs security events to SQLite, sends HIGH/CRITICAL Telegram alerts, and triggers automatic Twilio calls to the admin only for verified CRITICAL service outages. IP unbanning uses a request & admin approval workflow |
| 📇 Smart Contacts | Text/call by name (automatic number lookup), edit/delete contacts, paginated view (15 per page) |
| 📅 Calendar (View · Add · Edit · Delete) | In addition to viewing and adding events, supports **editing and deleting**. Phone/SMS reminders are automatically rescheduled when event times change |
| ✋ Barge-In | Immediately stops speaking and focuses on your new question if you interrupt the AI mid-call |
| ☎️ Operator Transfer | Direct transfer to an admin (human) via keypad `0` or voice command (individually toggleable) |
| ⏱️ Monthly Call Time Limit | Caps monthly inbound admin call usage (default 300 mins). Telegram warning at 90%, blocks calls if exceeded, resets on the 21st of every month |
| 💬 Telegram Bot | Chat with OpenWebUI on Telegram, index files, schedule reminders, **voice messages (STT)**, **display web search source links** |
| 🤖 Browser Agent | AI browses websites, takes screenshots, and extracts data |
| 📚 RAG | Answers questions based on uploaded documents |
| 🔒 Hardened Security | Container hardening, Docker Secrets, CVE patches, number-based call authentication, **phone number leak prevention** |
| ⚡ Auto Twilio Setup | **Automatically configures** Voice, SMS, and Status Callback URLs via the Twilio API during installation |

---

## Two Operating Modes

Operates in either **Personal** or **Customer** mode depending on your use case.

| Mode | Persona | When an Unknown Number Calls | Calendar & Commands |
|------|---------|------------------------------|---------------------|
| **Personal (`personal`)** | Friendly acquaintance / proxy call assistant | AI responds in a warm, personal check-in tone (no operator transfer prompt) | Admin only |
| **Customer (`customer`)** | Customer support representative | AI provides general customer service (keypad `0` operator transfer prompt ON) | Admin only (inaccessible to customers) |

> In both modes, **sensitive features such as Calendar, SMS, and system commands are strictly restricted to administrators (numbers entered during installation)**. Even in Customer mode, if a customer asks for "today's schedule," they cannot access the calendar.

### How to Choose a Mode — First Installation Screen + Switch Anytime

`HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh` asks for your intended use **first thing upon starting the installation**:

```
🎯 Which mode would you like to install for?
   1) Customer Service (Customer)
   2) Personal AI Assistant (Personal)
Select (1/2) [Default: 1=Customer]:
```

- **1 (or Enter)** → Installs in Customer Service mode
- **2** → Installs in Personal AI Assistant mode

Your selection is automatically written to **`SERVICE_MODE`** in `twilio-bot/ai_config.py`. Even after installation completes, you can switch between the two modes **without reinstalling** by changing this single line:

```bash
# Navigate to the actual project directory created by the install script
cd ~/HackyHappy-OpenWebUI

# Check current setting
grep -n '^SERVICE_MODE' twilio-bot/ai_config.py

# Change service mode
nano twilio-bot/ai_config.py
# Edit the line below to your desired mode:
# SERVICE_MODE = "customer"   # Customer service mode
# SERVICE_MODE = "personal"   # Personal mode

# Save and restart the Twilio Bot container
docker compose restart twilio-bot

# Verify restart status
docker compose ps twilio-bot
```

Changing `SERVICE_MODE` adjusts the following settings all at once:

| Setting | `customer` | `personal` |
|---------|-----------|-----------|
| Inbound call tone | Customer service tone | Warm acquaintance check-in tone |
| Default greeting | Customer service greeting | Personal check-in greeting |
| Operator keypad `0` prompt (`OPERATOR_HINT_ENABLED`) | ON | OFF |
| AI role label (`AI_ROLE`) | Customer Service Assistant | Personal Phone Assistant |
| Phone RAG search scope | Isolated search (follows `.env` default) | Auto-switches to unified search (Phone, Web, Telegram share documents) |
| Proactive auto-calling (Memory Anchor) | Disabled (default) | Can be enabled (`MEMORY_AUTOCALL_ENABLED`) |

> `SERVICE_MODE` changes the **default bundle** of "response tone, greeting, and operator prompt." You can individually fine-tune specific items (operator transfer, auto-calling, etc.) in `ai_config.py`. Explicitly set individual options take precedence.

> **Automatic Phone RAG Search Scope Switching:** Even if you installed with isolated search, changing `SERVICE_MODE = "personal"` automatically switches the phone bot to unified search (referencing the same documents across Phone, Web, and Telegram) without editing `.env`. Setting it to `customer` keeps the `.env` default chosen during installation. Takes effect after `docker compose restart twilio-bot`.

---

## Requirements

- **OS**: Ubuntu 22.04+ (including WSL2) or any Linux distribution capable of running Docker
- **Docker** + Docker Compose
- **Based on OpenWebUI 0.9.6** (The final install script pins the `v0.9.6` image; verify compatibility separately for other versions)
- **Twilio Account** (Phone Number, Account SID, Auth Token) — required for phone features
- (Optional) Telegram Bot Token — for Telegram integration
- (Optional) Groq / OpenAI / Claude / Gemini API Keys — for AI models
- (Optional) VoiceMem — Requires an **actual OpenAI API key (`sk-...`), NOT a Groq key**. Embeddings use a local E5-family model inside the container, while call analysis uses the OpenAI API. Enabling this raises the `twilio-bot` memory limit to 8GB, so ensure sufficient RAM is available. If disabled, it falls back to the existing Qdrant memory system.

### How to Get a GroqCloud Model API Key

To use **AI Mode `2=Groq` (direct Groq connection)** during the HackyHappy installation, you need a GroqCloud API key. Generate it directly from the official GroqCloud console:

1. Go to the [GroqCloud Console](https://console.groq.com/) and create an account or log in.
2. Open the [API Keys page](https://console.groq.com/keys).
3. Click **Create API Key**, enter a key name (e.g., `HackyHappy-VPS`), and generate it. Key creation permissions may vary depending on your organization/project role.
4. Immediately click **Copy** on the displayed secret key and store it in a safe place such as a password manager. You may not be able to view the full key again once you close the window. Keys typically start with `gsk_`.
5. When prompted for the **Groq API Key** while running the main HackyHappy install script, paste your copied key. If you skip this step, direct Groq connection will be disabled, and even if you chose AI Mode `2`, the script will automatically fall back to OpenWebUI mode.

**Security Precautions**

- A Groq API key is sensitive credentials just like a password. Never commit it to READMEs, GitHub repositories, screenshots, public chats, or source code.
- The install script saves your entered key as a Docker Secret at `secrets/groq_api_key` and uses it for Groq API calls. If you suspect your key has been exposed, revoke it immediately in [GroqCloud API Keys](https://console.groq.com/keys) and issue a new one.
- Check usage, rate limits, and currently available models at [GroqCloud Usage](https://console.groq.com/usage), [Rate Limits Docs](https://console.groq.com/docs/rate-limits), and [Models Docs](https://console.groq.com/docs/models). Free/paid terms and limits are subject to change based on your account and time.
- **VoiceMem does not use Groq API keys.** Enabling VoiceMem requires a separate, genuine OpenAI API key.

---

## Installation

### Step 1 — Main Installation (OpenWebUI + Phone Assistant + Calendar)

You can install **both Personal and Customer modes using a single script**. Upon running, the very first screen asks for your intended use.

```bash
wget https://YOUR-HOST/HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh
less HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh    # Reviewing contents before execution is recommended
chmod +x HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh
./HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh
```

When executed, you will **first** choose the operating mode (see [Two Operating Modes](#two-operating-modes) for details):

```
🎯 Which mode would you like to install for?
   1) Customer Service (Customer)
   2) Personal AI Assistant (Personal)
```

> Selecting **2 (Personal)** in this final script installs the system in Personal mode. A separate admin-only install script is not included with this final script.

Prompts during installation (in order):

| Prompt | Example | Description |
|--------|---------|-------------|
| **Service Mode** | `1` / `2` | **Asked first** — `1`=Customer Service, `2`=Personal. Written to `SERVICE_MODE` in `ai_config.py` and switchable later |
| My Phone Number | `+821012345678` | **Admin number(s)** authorized to call the bot. Comma-separated for multiple numbers |
| Twilio Credentials | SID / Token / Number | Required for phone and SMS features |
| Server Domain | `https://yourdomain.com` | Required for Twilio Webhooks |
| Admin Email / Password | — | Credentials for logging into OpenWebUI |
| AI Mode | `2` | `1`=OpenWebUI, `2`=Groq, `3`=Forwarding |
| Contacts | `Chulsoo Kim,+821011112222` | People the bot **calls** (unrelated to inbound call authorization) |
| RAG Search Mode | `1` / `2` | `1`=Unified, `2`=Isolated. Default is auto-recommended based on Service Mode (Personal → Unified, Customer → Isolated) |
| True Real-Time Mode | `y` / `N` | If `y`, enter Deepgram & ElevenLabs keys (paid). `N` (default) uses standard turn-based mode; can be enabled later |
| Telegram Reporting | `y` / `N` | If `y`, enter Bot Token & Chat ID → check-in and inbound call reports are sent via Telegram in addition to SMS. `N` (default) uses SMS reports only |
| NAVER Location Check | `y` / `N` | If `y`, enter NAVER Maps Client ID & Secret → enables location verification & map reporting during check-in calls. Followed by optional Kakao REST API key (station/business search) and optional Google Maps API key (satellite map imagery). `N` (default) disables location features |

> **Set a 6-Digit Admin PIN:** During installation, you can set your own 6-digit Admin PIN or press Enter to auto-generate one (make sure to note the auto-generated PIN displayed on screen). This PIN is only requested on phone calls when executing **sensitive commands** (saving contacts, placing calls, sending SMS, scheduling events), and is never asked during casual conversation or read-only queries like "What's on my schedule today?". Once verified, it remains valid for the entire duration of that call. See [Call Authentication (Security)](#call-authentication-security) for details.

> **🎙️ True Real-Time Mode is Optional:** Pressing `N` (or Enter) at "Enable True Real-Time Mode? (y/N)" installs the **standard mode**. You can enable it anytime later by setting `REALTIME_MODE=true` in `.env`. See [True Real-Time Proxy Calls](#true-real-time-proxy-calls-media-streams) for details.

> **📨 Telegram Reporting is Optional:** Providing values at "Configure Telegram report notifications? (y/N)" sends call reports to Telegram as well. Skipping it still leaves SMS reporting fully functional. See the Telegram section under [Usage by Channel](#usage-by-channel) for setup instructions.

> **📍 Location Check is Optional:** Pressing `y` at "Enable NAVER Map location check? (y/N)" prompts for your NAVER Maps keys to enable location checks. Adding an optional Kakao REST API key enables searching by subway station and business names. Since location reports are delivered with map images via **Telegram**, configuring Telegram reporting alongside location features is recommended. See [Location Check (NAVER + Kakao + Google)](#-location-check-naver--kakao--google) for details.

Once installation finishes, the entire stack—OpenWebUI, Phone Bot, RAG, Real-Time Voice Server, etc.—starts automatically and **registers 16 tools**. In addition to the core tools, the 14th tool (GPS Location Sharing), 15th tool (1-on-1 Video Call Invite), and 16th tool (HackyHappy AI Security Monitoring) are registered.

### Step 2 — Browser Agent (Optional)

```bash
chmod +x setup-browser-agent-calendar-naver-search-api-only-hackyhappy-paths.sh
./setup-browser-agent-calendar-naver-search-api-only-hackyhappy-paths.sh
```

### Step 3 — Telegram Bot (Optional)

```bash
chmod +x setup-telegram-bridge-calendar-hackyhappy-paths.sh
./setup-telegram-bridge-calendar-hackyhappy-paths.sh
```

> The Step 2 and Step 3 files are optional add-on components provided separately from the main installation script; the main script does not automatically download or generate them. Verify that these files are present in your repository and run them **after completing Step 1**. The Calendar tool must already be registered in OpenWebUI.

---

## Calendar Setup

The Calendar tool is **automatically registered** during installation, but you must enter an API key once before using it.

### Setup Steps (One-Time)

1. Log in to OpenWebUI as Admin → go to **Settings → Account → API Keys** and generate a key.
2. Add today's events in the **Calendar** tab on the left sidebar.
3. Go to **Workspace → Tools → "Calendar (Today's Schedule)" → ⚙️ Valves** → enter your key into `OPENWEBUI_API_KEY` → **Save**.
4. **Run "What's on my schedule today?" once in Chat** ← Crucial step.
5. "What's on my schedule today?" will now work via Phone and Telegram as well.

> **Step 4 is critical.** Running it once saves the key to a shared directory so the phone bot can read your calendar.

**How to Find `OPENWEBUI_API_KEY`:**

While generating the key via **Settings → Account → API Keys** in the web UI is standard, if a key was auto-generated into `.env` during installation, you can check it directly on the server:

```bash
# Check OpenWebUI API key in .env (paste this value into the valve)
grep OPENWEBUI_API_KEY ~/HackyHappy-OpenWebUI/.env
```

Example output:
```
OPENWEBUI_API_KEY=eyJhbGciOi...   (JWT token) or  sk-...
```

Copy the value after `=`, paste it into the **`OPENWEBUI_API_KEY` field in the Calendar tool's Valves**, and save. (Paste the same value into the Browser Agent tool's Valves as well.)

> If this value is missing or empty in `.env`, it hasn't been generated yet. Generate it via the web UI as described above. If the generated key is `eyJ...` (JWT), it has an expiration date, so `sk-...` format is recommended for long-term use (see [API Key Formats](#api-key-formats)).

### Receiving Event Reminders via Phone Call & SMS (`TWILIO_BOT_SECRET`)

To set "Remind me N minutes before" on calendar events and receive those reminders **via phone call and SMS**, you must enter the **`API_SECRET`** value from `.env` into the `TWILIO_BOT_SECRET` field of the Calendar tool's Valves. (If left blank, reminder calls and SMS scheduling will be skipped.)

**How to Find `API_SECRET`:**

```bash
# Check API_SECRET value in .env (paste this value into the valve)
grep API_SECRET ~/HackyHappy-OpenWebUI/.env
```

Example output:
```
API_SECRET=abcd1234efgh5678...
```

Copy the value after `=` (`abcd1234...`) and paste it into:

**Workspace → Tools → "Calendar (View · Add · Edit · Delete)" → ⚙️ Valves → `TWILIO_BOT_SECRET`**, then click Save.

> Summary: Two keys go into the Calendar tool's Valves:
> - `OPENWEBUI_API_KEY` ← API key generated in OpenWebUI (for reading/managing calendar events)
> - `TWILIO_BOT_SECRET` ← `API_SECRET` value from `.env` (for scheduling reminder calls & SMS)

### API Key Formats

- `sk-...` format — **Recommended** (never expires)
- `eyJ...` (JWT token) — Works, but **not recommended because it expires**

> If a JWT key expires, the phone bot will inform you: *"Your key may have expired; please configure a new key."* It will never fabricate fake events.

### Where to Enter Keys by Channel

| Channel | Access Method | Key Entry Location |
|---------|---------------|--------------------|
| Chat | Direct invocation of the "Calendar" tool | That tool's Valves |
| Phone | Detects "schedule" keywords → queries via shared key | (Receives shared key from Chat) |
| Telegram | All tools auto-enabled → includes Calendar | (Receives shared key from Chat) |
| Browser Agent | Method inside the "AI Browser Agent" tool | **Enter separately in that tool's Valves** (`OPENWEBUI_API_KEY`) |

> Only the Browser Agent requires you to paste the same key into its own Valves (as a standalone tool). Enter it in the **`OPENWEBUI_API_KEY`** field, not `BROWSER_AGENT_API_KEY` or `LLM_API_KEY`.

### Browser Agent Access Key (`BROWSER_AGENT_API_KEY`)

The authentication key used to connect to the Browser Agent service or when tools invoke the agent is auto-generated in `.env` during installation. Check it with:

```bash
# Check AI Browser Agent API Key
grep BROWSER_AGENT_API_KEY ~/HackyHappy-OpenWebUI/.env
```

Example output:
```
BROWSER_AGENT_API_KEY=xyz9876abcd...
```

Copy and use the value after `=`. (This is **different** from `OPENWEBUI_API_KEY` used for calendar queries.)

### Checking the OpenWebUI API Key on the Server (`OPENWEBUI_API_KEY`)

This is the key entered into `OPENWEBUI_API_KEY` in the Calendar and Browser Agent tool Valves. Generating it in the web UI via **Settings → Account → API Keys** is standard, but if auto-populated in `.env` during installation, you can view it via:

```bash
# Check OpenWebUI API key in .env
grep OPENWEBUI_API_KEY ~/HackyHappy-OpenWebUI/.env
```

Example output:
```
OPENWEBUI_API_KEY=eyJhbGciOi...   (JWT token) or  sk-...
```

Copy the value after `=` and paste it into **Workspace → Tools → Calendar / Browser Agent → ⚙️ Valves → `OPENWEBUI_API_KEY`**, then save. Use the **same value** for both tools.

> If missing or empty in `.env`, generate a new one in **Settings → Account → API Keys** in the web UI. For long-term stability without expiration, use an `sk-...` key rather than an `eyJ...` JWT token (see [API Key Formats](#api-key-formats)).

> Summary of the 3 keys commonly checked in `.env`:
> - `OPENWEBUI_API_KEY` — Issued in OpenWebUI (for Calendar access; may not be in `.env`)
> - `API_SECRET` — Phone bot secret (entered into `TWILIO_BOT_SECRET` for calendar reminder alerts)
> - `BROWSER_AGENT_API_KEY` — For connecting to the Browser Agent service

---

## Call Authentication (Security)

### Call Authentication — Registered Admin Number + 6-Digit PIN for Sensitive Commands

Call authentication operates in two layers:

1. **Caller ID Verification** — Only calls originating from registered admin numbers (`ADMIN_NUMBERS`) receive admin privileges. In Personal mode, unknown numbers are blocked immediately; in Customer mode, they are routed to general AI customer support.
2. **6-Digit PIN Verification (Sensitive Commands Only)** — Even for admins, a 6-digit PIN is verified once when executing **sensitive commands** (saving contacts, placing calls, sending SMS, scheduling events). Casual conversation and read-only queries like "What's on my schedule today?" do not ask for a PIN. Once verified, it remains valid for the entire call.

You can set your own PIN during installation or press Enter to auto-generate one. **Three failed attempts lock PIN entry for 30 minutes** (auto-unlocks afterward).

**Why this design:** Caller ID filtering blocks strangers, while adding a PIN for sensitive actions involving money or personal data protects against caller ID spoofing. Meanwhile, omitting the PIN for casual chat and schedule checks keeps everyday usage effortless.

> To disable PIN verification completely, set `ADMIN_PIN_REQUIRED = False` in `ai_config.py` and run `docker compose restart twilio-bot`. Sensitive commands will then execute based solely on registered admin numbers. ⚠️ However, disabling the PIN is not recommended, as a spoofed caller ID could trigger unauthorized calls, texts, or bookings.

### Admin Numbers vs. Contacts — Do Not Confuse!

| Category | What It Is | Direction |
|----------|------------|-----------|
| **Admin Numbers** (`ADMIN_NUMBERS`) | Your number(s) entered during install | Authorized to **call IN to the bot** |
| **Contacts** | People saved in chat (e.g., "Chulsoo Kim...") | Targets the bot **calls OUT to** |

> Even if you save "Chulsoo Kim" in chat, if Chulsoo Kim calls the bot, he will be blocked (in Personal mode). To allow Chulsoo Kim to call the bot, add his number to **Admin Numbers**.

### Adding / Changing Admin Numbers

```bash
cd ~/HackyHappy-OpenWebUI
read -p "Admin numbers (e.g., +821012345678,+821099998888): " NEW_ADMINS
sed -i "s/ADMIN_NUMBERS=.*/ADMIN_NUMBERS=$NEW_ADMINS/" .env
docker compose up -d twilio-bot
```

---

## Call Features (Barge-In · Operator Transfer)

Adjust conversational naturalness and human handoff behavior in `ai_config.py`. Apply changes with `docker compose restart twilio-bot`.

### Barge-In (Interruption Handling)

If the caller interrupts while the AI is speaking, the AI immediately stops talking, acknowledges the interruption, and focuses on the new question—just like a natural human conversation.

| Setting | Default | Description |
|---------|---------|-------------|
| `BARGEIN_THRESHOLD` | `0.6` | Sensitivity (`0`–`1`). Higher values trigger interruption more easily. `0.4` = less sensitive (recommended for noisy environments) |
| `BARGEIN_MIN_SECONDS` | `3.0` | Ignores interruptions during responses shorter than this duration |
| `BARGEIN_ENABLED` | `True` | Set to `False` to disable barge-in handling |
| `BARGEIN_NOTE` | (Prompt) | Instructions governing how the AI reacts when interrupted |

> In noisy environments, background noise may cause the AI to stop mid-sentence. Lower `BARGEIN_THRESHOLD = 0.4` or set `BARGEIN_ENABLED = False`.

### Human Operator Transfer — Keypad `0` / Voice

Independently toggle the two ways external callers can be transferred from the AI to a human (admin):

| Setting | Default | Description |
|---------|---------|-------------|
| `OPERATOR_TRANSFER_ENABLED` | `True` | Transfer via pressing keypad **`0`** |
| `OPERATOR_VOICE_ENABLED` | `True` | Transfer via saying keywords like "representative" |
| `OPERATOR_HINT_ENABLED` | `True` | Spoken prompt ("Press 0 to speak with a representative") |
| `OPERATOR_VOICE_KEYWORDS` | (List) | Voice trigger keywords (customizable) |

Example configurations:

```python
# Fully unattended AI handling (disable all human transfers)
OPERATOR_TRANSFER_ENABLED = False
OPERATOR_VOICE_ENABLED    = False

# Expand voice transfer keywords
OPERATOR_VOICE_KEYWORDS = ["담당자", "상담원", "직원", "사람", "operator", "representative", "agent", "human"]
```

> Even if all human transfers are disabled, external callers continue receiving **AI support**, and automatic post-call reports to the admin still operate. Sensitive features like Calendar remain strictly admin-only.

---

## True Real-Time Proxy Calls (Media Streams)

Standard calls use a turn-based approach (Twilio Gather), exchanging one sentence at a time. Enabling **True Real-Time Mode** streams call audio continuously via Twilio Media Streams, enabling **instant AI response and mid-sentence barge-in** for a genuinely real-time conversation.

| Aspect | Standard Mode (Default) | True Real-Time Mode |
|--------|-------------------------|---------------------|
| Architecture | Speak one sentence → AI replies (turn-based) | Continuous audio streaming (Media Streams) |
| Barge-In | Sentence-by-sentence | **Immediate mid-utterance** barge-in |
| Engines | Twilio built-in STT/TTS | Deepgram (STT) + ElevenLabs (TTS) |
| Prerequisites | None | Public HTTPS domain + paid API keys |
| Cost | Twilio call charges only | Twilio + Deepgram & ElevenLabs usage fees |

### How to Enable

**During installation:** Answer `y` to "Enable True Real-Time Mode? (y/N)" and enter your Deepgram & ElevenLabs keys.

**Enable later:**

```bash
cd ~/HackyHappy-OpenWebUI
nano .env
# Change REALTIME_MODE=false  →  true
# Fill in DEEPGRAM_API_KEY=... and ELEVENLABS_API_KEY=... (or enter via the Voice Engine Valves below)
docker compose up -d
```

### Prerequisites (Important)

- A **public HTTPS domain** (`SERVER_DOMAIN` starting with `https://...`) is mandatory because Twilio must connect via WebSocket to `wss://yourdomain/twilio-stream`. Real-time mode cannot work over `localhost` and will **automatically fall back to standard mode**.
- You can easily obtain a public HTTPS domain using Cloudflare Tunnel (see [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup-external-https-access)).

### How It Works

```
Call → twilio-bot checks REALTIME_MODE → returns <Connect><Stream> TwiML
     → Twilio connects to wss://yourdomain/twilio-stream (Nginx proxies to realtime-voice)
     → realtime-voice: Caller audio → Deepgram (STT) → LLM → ElevenLabs (TTS) → plays back
     → When caller starts speaking, AI stops immediately (barge-in)
```

`realtime-voice` runs as a separate container and sits harmlessly idle when real-time mode is off. To stop it completely, run `docker compose stop realtime-voice`.

### Tuning (If Call Flow Feels Unnatural)

Fine-tune real-world call quality (latency, pauses, barge-in sensitivity) in `realtime-voice/realtime_server.py`:

| Parameter | Description |
|-----------|-------------|
| Deepgram `endpointing=300` | Silence duration (ms) before treating speech as end-of-sentence. Higher = more patient, lower = faster |
| ElevenLabs `optimize_streaming_latency` | Streaming latency optimization level |
| LLM `max_tokens=120` | Maximum response length during calls (kept concise) |

> Monitor caller speech, AI replies, and barge-in events via logs: `docker compose logs -f realtime-voice`

---

## Real-Time Whisper (In-Call Instructions)

**While the AI is actively on a call with someone**, the admin can send **"Say this: ..."** via Telegram or OpenWebUI chat/app, and the AI will **naturally weave that instruction into its very next response** without letting on that it is an AI or receiving instructions.

> Works in standard turn-based mode too, and reflects even faster in True Real-Time Mode.

### Instruct via Telegram

Send a message to your Telegram bot using the formats below (takes effect immediately):

| Input | Action |
|-------|--------|
| `이렇게 말해: 곧 찾아뵙겠다고 전해줘` (or `Say this: Tell them I'll visit soon`) | Incorporates the message into the next utterance |
| `귓속말: 목소리 톤을 더 밝게` (or `Whisper: Use a brighter tone`) | Style/tone instruction |
| `김철수 이렇게 말해: 다음 주에 연락한다고 해` | **Targets a specific call** when multiple calls are active |
| `/calls` or `통화목록` | Lists currently active calls |

> Telegram real-time whispers require `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` to be configured in `.env`, and only the registered admin chat can issue instructions. (Even if unconfigured, you can use the OpenWebUI tool below right away.)

### Instruct via OpenWebUI Chat / App

Use the **"Real-Time Whisper"** tool:

- *"Are there any active calls right now?"* → Lists ongoing calls
- *"Tell them I'll visit shortly"* → AI weaves it into its next reply
- You can also cancel pending whisper instructions.

---

## Voice Engine Settings (STT/TTS Valve Switching)

Change the **STT (Speech-to-Text) / TTS (Text-to-Speech) providers, API keys, and voices** used in True Real-Time calls directly from OpenWebUI Valves (⚙️ settings), just like the Calendar tool.

### Setup Steps

1. In OpenWebUI, go to **Workspace → Tools → "Voice Engine Settings (Real-Time STT/TTS)" → ⚙️ Valves**.
2. Fill in the fields below and click **Save**:

| Valve Field | Description | Default |
|-------------|-------------|---------|
| `STT_PROVIDER` | Speech recognition provider | `deepgram` |
| `DEEPGRAM_API_KEY` | Speech recognition API key | (Empty) |
| `STT_MODEL` | Speech recognition model | `nova-2` |
| `TTS_PROVIDER` | Speech synthesis provider (`elevenlabs` or `deepgram`) | `elevenlabs` |
| `ELEVENLABS_API_KEY` | Speech synthesis API key (use Deepgram key if TTS is `deepgram`) | (Empty) |
| `TTS_VOICE` | Voice ID (e.g., ElevenLabs voice ID) | `Rachel` |
| `TTS_MODEL` | Speech synthesis model | `eleven_flash_v2_5` |
| `LANGUAGE` | Call language (`ko` / `en` / `ja` / `zh`) | `ko` |

3. **Saving applies changes immediately** (OpenWebUI re-initializes the tool upon saving and pushes the config to the server).
4. Subsequent calls will use the updated voice engine.

> To verify, ask in chat: *"Show current voice engine settings"* → displays active STT/TTS providers and voices (API keys are masked as `abcd***yz`).
>
> If changes don't appear to apply immediately on save, run *"Apply voice engine settings"* once in chat to force synchronization.

---

## 🧠 Memory Anchor (Call Recall · Proactive Auto-Calls)

Embeds call transcripts **by phone number into a vector database (Qdrant)**. The next time you speak with the same person, the AI **automatically recalls past memories from similar contexts (time of day, weather)** to continue the conversation naturally.

Example: If someone mentioned feeling down on a rainy evening, on the next rainy evening call the AI proactively checks in: *"You mentioned having a tough time last time—how have you been holding up?"*

### Saving (Automatic)

Automatically saves when a call ends—no extra setup required.

- **Stored metadata:** Phone number, name, date, **time slot** (morning/lunch/afternoon/evening/night), **weather**, **emotion**, **topic**, summary, and full transcript.
- Emotion, topic, and summary are automatically extracted by AI from the conversation.
- Saves outbound proxy calls, inbound calls, and real-time calls **alike**.

> Recall quality depends on **Ollama embeddings**. Ollama must be connected to accurately match semantically similar memories (see [Automatic Ollama Embedding Setup](#automatic-ollama-embedding-setup-wsl2) below).

### Recall (Automatic During Calls)

At the start of the next call, the system searches past memories for that caller's phone number, **boosts memories matching the current time of day and weather**, and passes the most relevant memory to the AI. The AI weaves it naturally into conversation without revealing that it is an AI or reading from logs.

### Manual Lookup (Tool)

Search memories directly in OpenWebUI chat using the **"Memory Anchor"** tool:

- *"What did I talk about with Chulsoo Kim previously?"* → Lists past call memories
- *"Find the call where we talked about changing jobs"* → Searches by topic

### Proactive Auto-Calls (Optional · Off by Default)

When matching conditions occur, the system can **proactively suggest or place check-in calls**. Enable this in `ai_config.py`:

```python
# twilio-bot/ai_config.py
MEMORY_AUTOCALL_ENABLED = False     # ← Set to True to enable proactive auto-calls (default False)
MEMORY_AUTOCALL_MODE = "suggest"    # suggest = notify admin / auto = place call automatically
MEMORY_AUTOCALL_HOURS = [10, 20]    # Allowed calling window (10:00–20:00, prevents late-night calls)
MEMORY_AUTOCALL_COOLDOWN_DAYS = 7   # Minimum 7-day interval per person (prevents spam)
MEMORY_AUTOCALL_MATCH = ["time_slot", "weather"]  # Triggers only when both time slot and weather match past call
MEMORY_AUTOCALL_MAX_PER_DAY = 3     # Max auto-calls per day (cost protection)
```

Restart after editing: `docker compose restart twilio-bot`.

| Mode | Behavior |
|------|----------|
| `suggest` (Default · Safe) | Sends a Telegram/SMS alert to the admin (*"Now is a good time to call [Name]"*) when conditions match → admin initiates call manually |
| `auto` | Immediately places an automated check-in call when conditions match (monitor usage/costs carefully) |

> **4-Layer Safeguards:** Master OFF by default · Allowed calling hours · Per-person cooldown · Daily cap. We recommend running in `suggest` mode for several days before switching to `auto`.

---

## 🧠🧠 VoiceMem Dual-Brain Architecture (Left & Right Brain Memory)

**VoiceMem** is the underlying memory engine powering [Memory Anchor](#-memory-anchor-call-recall--proactive-auto-calls). Just as the human brain divides functions between its left and right hemispheres, VoiceMem **splits each call memory into two tracks for storage and recall**. It is an **optional module**—turning it off leaves all other features running normally.

### Why a Dual-Brain Design?

Storing memories as a single blob mixes "hard facts" with "emotional atmosphere," making it easy to miss one or the other during recall. VoiceMem separates them so each is stored using the optimal method:

| Hemisphere | Role | What It Stores | How It Recalls |
|------------|------|----------------|----------------|
| **Left Brain (`Left`)** | Facts & Structure | **Who, when, what** — structured facts such as phone number, name, date, time slot, topics, promises, and requests | Exact lookup by structured keys (phone number, date, topic) |
| **Right Brain (`Right`)** | Emotion & Context | **Mood, emotion, associations** — emotional state, conversational tone, weather, and time-of-day atmosphere | Semantic similarity search via embeddings for "atmospheres similar to right now" |

During recall, results from both hemispheres are **combined** and passed to the AI. The Left Brain recalls the fact (*"Talked with this person last Tuesday about a job change"*), while the Right Brain recalls the mood (*"It was a rainy evening and the tone was a bit somber"*), allowing the AI to follow up naturally with both context and empathy: *"Have you sorted out your thoughts on that job change we talked about?"*

### Storage & Recall Flow

```
[Call Ends]
  ↓
VoiceMem analyzes the transcript
  ├─ Left Brain Storage: Phone number, name, date, time slot, topics, promises (structured facts)
  └─ Right Brain Storage: Emotion, tone, weather, context → semantic embeddings (vectors)
        ↓
[Next Call Starts]
  ↓
Queries both hemispheres simultaneously by caller phone number
  ├─ Left Brain: Exact list of structured facts
  └─ Right Brain: Past memories with similar time slot & atmosphere (top semantic matches)
        ↓
Merges both results → AI converses with full factual + emotional context
```

### Actual Implementation & How to Enable (Final Install Script)

In this final script, VoiceMem does not toggle between Ollama and OpenAI engines:

- **Left Brain (Factual Memory):** Uses the `voicemem` package, performing embeddings and slot extraction with a local E5-family model.
- **Call Transcript Analysis:** Uses the genuine OpenAI API key (`VOICEMEM_OPENAI_KEY`) entered during installation with the `gpt-4o-mini` model. Groq keys cannot be used for VoiceMem.
- **Right Brain (Emotional & Personality Profiles):** Rather than using VoiceMem's native right-brain engine, it uses the same OpenAI key to incrementally update per-person JSON profiles (`/app/data/personas`).
- If VoiceMem is disabled or fails to initialize, the system gracefully falls back to the standard Qdrant-based memory storage and recall.

Answer `y` to `Configure VoiceMem memory system?` during installation and enter a valid OpenAI API key to enable it. The default is `N`, which uses the standard memory system. When enabled, the install script raises the `twilio-bot` container memory limit to 8GB—verify your VPS has enough free RAM first.

To toggle or update settings after installation, edit `.env` in your project folder:

```bash
cd ~/HackyHappy-OpenWebUI
nano .env

# Disable VoiceMem
VOICEMEM_ENABLED=false

# Re-enable VoiceMem (requires a valid OpenAI API key)
VOICEMEM_ENABLED=true
VOICEMEM_OPENAI_KEY=sk-your_actual_OpenAI_API_key
VOICEMEM_MODEL=gpt-4o-mini
```

Apply changes:

```bash
cd ~/HackyHappy-OpenWebUI
docker compose up -d --force-recreate twilio-bot
```

> **Note:** If `VOICEMEM_ENABLED=true` is set with an empty key or `voicemem` fails to initialize, the VoiceMem path will be bypassed and the system will fall back to Qdrant memory. Check container logs and RAM usage after recreating `twilio-bot`.

---

## 📍 Location Check (NAVER + Kakao + Google)

During a check-in call, this feature **asks the recipient for their location, obtains explicit consent**, and **reports their spoken location to Telegram** along with a map image. (Also registered as the 13th tool so you can look up places and maps directly without placing a call.)

> ⚠️ **Privacy Notice:** This feature **only uses locations verbally stated by the recipient during the call**. It never secretly tracks mobile GPS. Fetching a phone's GPS solely through a voice call is technically impossible, and this feature must only be used after informing the recipient and obtaining their consent.

### Workflow

**Location-Focused Call** (*"Ask [Name] where they are"*)

```
[Call Answered]
  ↓
"Hello, [Name]. I'm calling on behalf of [Admin].
 [Admin] asked me to check your current location. Could you let me know where you are?
 Please say 'Yes' if you consent, or 'No' if you prefer not to share."   ← Asks consent right after greeting
  ↓
[Recipient says "Yes"] → "Please tell me where you are right now."
      ↓  (Recipient replies e.g. "Yeoksam-dong" or "Gangnam Station")
   Attempts NAVER Geocoding → falls back to Kakao Local Search if not found
      ↓  Coordinates resolved → Generates Google hybrid satellite map (or NAVER standard map if no Google key)
   📨 Sends map image + address to Admin's Telegram
      ↓
   "Got it. I will pass that along. Have a peaceful day." → Ends call
[Recipient says "No"] → Skips location check
```

**Check-In Call with Location Request** — After receiving the location, the AI seamlessly continues the friendly check-in conversation.

- Location check calls **always start with a polite greeting** (never repeating the admin's raw command verbatim as the opening line), immediately followed by the location consent prompt without inserting small talk like *"How have you been?"*.
- **Consent is asked at most 2 times** (preventing infinite loops on silence). If neither Yes nor No is confirmed within 2 attempts, the location check is skipped.
- **Pure check-in calls** (without location instructions, e.g., *"Give [Name] a check-in call"*) run naturally as usual without asking for location consent.

### Dual NAVER + Kakao Search

Combines two Korean mapping services for comprehensive coverage:

| Search Target | NAVER Geocoding | Kakao Local |
|---------------|:---------------:|:-----------:|
| Road / Lot Addresses (e.g., `110 Sejong-daero`) | ✅ | ✅ |
| Subway Stations, Businesses, Landmarks (e.g., `Gangnam Station`, `OO Hospital`) | ❌ | ✅ |

- Tries **NAVER Geocoding** first (high accuracy for road and lot addresses).
- Falls back to **Kakao Local Keyword Search** if not found (resolves stations, businesses, and building names).
- Renders map images using **Google hybrid satellite view** (falls back to NAVER Static Map standard view if no Google key is configured).

> Because NAVER discontinued its Local Search API, station names and businesses cannot be resolved via NAVER Geocoding alone. Adding Kakao Local as a fallback ensures answers like "Gangnam Station" resolve accurately to coordinates. Without a Kakao key, only road/lot addresses are recognized, and if unresolved, the AI politely asks the caller to name a nearby neighborhood, major building, or main road.

### Map Imagery — Google Satellite View (Optional)

While NAVER/Kakao handle coordinate resolution, **final map images** can be rendered using Google hybrid satellite imagery (satellite photo + road/place labels). Adding a Google Maps API key upgrades Telegram map reports to satellite imagery:

- **With Google Key** → Google hybrid satellite image (rooftops, real terrain + street/place labels)
- **Without Google Key / On Error** → Automatically falls back to NAVER standard map (built-in failsafe)

> `hybrid` overlays place and road names onto satellite imagery so it's immediately clear where the location is. If you prefer pure satellite imagery with no text labels, change `"maptype": "hybrid"` to `"satellite"` in the code.

**How to Get a Google Maps API Key:**
1. Log in to [Google Cloud Console](https://console.cloud.google.com) → select or create a project.
2. Go to **APIs & Services → Library** → search for **Maps Static API** → click **Enable**.
3. **Link a Billing Account** (required) — includes a $200/month free credit, making personal location checks virtually free.
4. Go to **APIs & Services → Credentials → Create Credentials → API Key** → copy the `AIza...` key.
5. (Recommended) Restrict the key under **API restrictions → Restrict key → Maps Static API** to prevent unauthorized usage.

> ⚠️ Because Google API keys are tied to billing, leaked keys can incur charges. Always apply API restrictions and set billing budget alerts.

### Prerequisites — Obtaining API Keys

**1) NAVER Maps (Required)** — Coordinate resolution + fallback static maps
1. Log in to [NAVER Cloud Platform](https://console.ncloud.com) → search **Maps** in the top search bar.
2. Click **Application Registration** → subscribe to **Geocoding** and **Static Map**.
3. Copy your **Client ID** and **Client Secret** under **Authentication Information**.
   - Uses the `maps.apigw.ntruss.com` API domain (not the legacy `naveropenapi.apigw.ntruss.com`).
   - Both Geocoding and Static Map include generous monthly free tiers.

**2) Kakao REST API (Optional · For Station & Landmark Search)**
1. Log in to [Kakao Developers](https://developers.kakao.com) → **My Applications → Add an Application**.
2. Open your app → copy the **REST API Key** under **App Keys**.
3. Go to **Kakao Map** in the left menu → turn **Activation Status ON**.
   - Kakao Local API offers generous daily free quotas without requiring a payment method.

**3) Google Maps (Optional · For Satellite Map Images)**
1. Log in to [Google Cloud Console](https://console.cloud.google.com) → select or create a project.
2. Enable **Maps Static API** + link a billing account ($200/month free credit).
3. Create an **API Key** (`AIza...`) → restrict it to Maps Static API (recommended).
   - Renders Google hybrid satellite imagery when present; falls back to NAVER standard map when omitted.

### Entering Keys — During Installation or Later

During installation, answer `y` to "Enable NAVER Map location check?" and enter your NAVER Client ID & Secret, optional Kakao REST API key, and optional Google Maps API key in sequence. Keys are stored securely as **Docker Secrets files**.

To enable or update keys later, write the secrets files directly and restart:

```bash
cd ~/HackyHappy-OpenWebUI
# NAVER
echo -n "YOUR_NAVER_CLIENT_ID"       > secrets/naver_maps_client_id       2>/dev/null || true
echo -n "YOUR_NAVER_CLIENT_SECRET"   > secrets/naver_maps_client_secret
# Kakao (Optional)
echo -n "YOUR_KAKAO_REST_API_KEY"    > secrets/kakao_rest_api_key
# Google Satellite Map (Optional)
echo -n "YOUR_GOOGLE_MAPS_API_KEY"   > secrets/google_maps_api_key
# Enable location feature in .env (append if missing)
grep -q NAVER_LOCATION_ENABLED .env || echo "NAVER_LOCATION_ENABLED=true" >> .env
docker compose up -d --build twilio-bot
```

> `NAVER_MAPS_CLIENT_ID` is managed in `.env`, while `Secret`, Kakao key, and Google key are stored in `secrets/`. The code reads environment variables first and falls back to secrets files, ensuring Gunicorn workers always load credentials reliably.

### Verification

Test the running bot directly (resolves location + sends map to Telegram):

```bash
docker exec twilio-bot python3 -c "
import requests
sec = open('/run/secrets/api_secret').read().strip()
r = requests.post('http://localhost:5000/naver-location',
    headers={'X-API-Secret': sec, 'Content-Type':'application/json'},
    json={'place':'서울특별시 중구 세종대로 110', 'report_to_telegram':True, 'contact_name':'Test'}, timeout=20)
print(r.status_code); print(r.text[:300])
"
```

If it returns `ok:true` with an address and delivers a map image to Telegram, everything is working properly.

---

## 🛰️ GPS Location Sharing (Senior Care)

Unlike Location Check (NAVER/Kakao/Google), which relies on **locations spoken aloud during a phone call**, the GPS Location Sharing tool sends **real-time GPS coordinates** to the admin once the recipient **explicitly taps [Allow] in their browser**. This is ideal for senior care and checking on elderly parents living alone where exact real-time GPS coordinates are needed.

> ⚠️ **Why a Link-Based Flow?** Standard voice calls cannot access a remote phone's GPS sensor (a fundamental limitation of all telephone networks). This feature bridges that gap using an **SMS link + browser geolocation prompt**. Coordinates are only transmitted after the recipient opens the link and grants location permission, ensuring **explicit user consent at all times**.

### Workflow

```
① Admin: "Check Ikje Park's GPS location" (or specify by phone number)
   ↓
② System sends BOTH a phone call and an SMS to the recipient
   Call: "Admin would like to check your location. Please tap the link in your text message."
   SMS: "Share location: https://<domain>/gps-share/<token>"
   ↓
③ Recipient opens the link → sees clear disclosure page:
   "Your location will be sent once to Admin" + [📍 Send My Location] button
   ↓
④ Recipient taps button → browser prompts "Allow location access?" → taps [Allow]
   ↓
⑤ Real-time GPS coordinates → sent to Admin's Telegram (with map image) + Admin's SMS (coordinates & map link) ✅
```

From the recipient's perspective, it takes just four simple taps: **Answer call → Tap SMS link → Tap "Send My Location" → Tap "Allow"**.

### Usage

Ask naturally in OpenWebUI chat or on an admin call:

- *"Check Ikje Park's GPS location"* → Looks up number in contacts and sends link
- *"Send a location sharing link to 010-1234-5678"* → Sends directly to the specified number

Once dispatched, the bot confirms: *"Sent a location sharing link to [Name] (call + SMS). Their location will be sent once they consent within 30 minutes."*

### Security (5 Layers)

| Layer | Description |
|-------|-------------|
| Random Token | Generates an unguessable, cryptographically random URL token |
| One-Time Use | Link immediately expires after transmitting location once (cannot be reused) |
| Time-Limited | Automatically expires after 30 minutes (default) if unused |
| HTTPS | Encrypts data in transit (when domain uses `https://`) |
| Target Number Binding | Binds each link to a specific recipient phone number so incoming locations are unambiguously identified |

> You can adjust the link expiration window (default 30 minutes) via `GPS_SHARE_TTL_SEC` in the code.

### Legal & Ethical Guidelines

Because coordinates are only sent after the recipient **explicitly taps [Allow]**, this tool aligns with consent-based location principles. Please adhere to the following rules (general guidance only, not legal advice—consult a legal professional before deployment):

- **Clear Disclosure & Consent:** The recipient must understand what is being shared and with whom. The landing page clearly states this before requesting permission.
- **Decision-Making Capacity:** If the recipient has impaired cognitive capacity (e.g., advanced dementia), their consent alone may not suffice; verify legal guardianship requirements.
- **No Covert Tracking:** Obtaining someone's location secretly or through deception is illegal. Always inform the recipient and obtain genuine consent.
- **Purpose Limitation:** Use strictly for senior care and safety verification—never share data with third parties or use it for unrelated purposes.

### Installation & Testing

GPS Location Sharing is **already built into this final unified install script as the 14th OpenWebUI tool and Twilio Bot API**—there is no separate GPS patch script to run. Fresh installations register the tool automatically. If adding it to an existing server, check for an official incremental update patch rather than blindly re-running the full installation script.

After installation, confirm that **Workspace → Tools → "GPS Location Sharing"** is registered in OpenWebUI. The endpoint requires `API_SECRET` authentication (stored in `secrets/api_secret`).

Direct API test:

> ⚠️ The command below is NOT a passive health check—it places a real Twilio voice call and sends an SMS to the target, incurring charges. Only run this using a test contact under your control, and obtain consent before using real names or phone numbers.

```bash
curl -s -X POST http://localhost:5000/gps-request \
  -H "X-API-Secret: $(cat secrets/api_secret)" \
  -H "Content-Type: application/json" \
  -d '{"name":"박익제"}'
```

The recipient receives a phone call and SMS, and once they tap [Allow] on the link, their GPS location arrives on the admin's Telegram and SMS.

---

## 📹 1-on-1 Video Calling (Self-Hosted WebRTC)

Without relying on third-party conferencing services, HackyHappy connects **two-party video and audio calls** using the built-in Twilio Bot and a self-hosted WebRTC interface. Registered in OpenWebUI as **"1-on-1 Video Call Invite"**, it can be toggled on or off via the `enabled` valve in tool settings.

### Invitation & Connection Flow

1. The admin requests a video call in OpenWebUI chat using a contact's name or phone number.
2. The system sends a video call invite SMS to the recipient, followed by an AI guide call explaining how to join.
3. OpenWebUI chat displays a **[📹 Join Video Call]** link that the admin can open in a new tab.
4. The admin opens the chat link while the recipient opens the link in their SMS.
5. Once both parties grant camera and microphone permissions in their browsers, the peer-to-peer WebRTC session begins.

Example prompts:

- *"Send a video call invite to Chulsoo Kim"*
- *"Send a video call invite to 010-1234-5678"*

### Session Expiration & Call Termination Rules

| Scenario | Behavior |
|----------|----------|
| Both parties fail to join within 10 minutes of invite creation | Invite session automatically expires |
| Connected after both parties join | Designed for unlimited call duration |
| Either party clicks End Call or closes the browser tab | Terminates session and disconnects the peer |
| Browser crashes and stops sending heartbeats | Cleans up stale participant slot after 15 seconds |
| Reopening an ended/expired link | Displays an expired/ended notice; a new invite is required |

The call interface includes local and remote video feeds, mute/unmute mic, camera on/off, and an End Call button. Both devices and browsers must support `getUserMedia` and have camera/microphone permissions enabled.

### Self-Hosted WebRTC & TURN Relay

- **WebRTC** handles direct real-time audio/video streaming between browsers.
- Includes a **Coturn TURN relay** for restrictive NAT/firewall networks where direct peer-to-peer connections fail.
- TURN ports: UDP/TCP `3478`, media relay UDP `49160-49200`.
- The install script attempts to detect your server's public IPv4 address and configure Coturn's `external-ip` automatically.
- Loads zero external Jitsi services or third-party conferencing JavaScript SDKs.

Make sure the ports above are open in both your OS firewall and your cloud provider's security group/firewall. If your server sits behind NAT or public IP auto-detection fails, verify `VIDEO_TURN_PUBLIC_IP` and Coturn's `external-ip` setting.

### Post-Install Verification

```bash
cd ~/HackyHappy-OpenWebUI

# Check video-call related containers
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' \
  | grep -E 'twilio-bot|openapi-tools|coturn'

# Check Coturn logs
docker logs --since 10m hackyhappy-coturn

# Check Twilio Bot video call invite logs
docker logs --since 10m twilio-bot 2>&1 \
  | grep -Ei 'video-call|video-room|영상전화|초대'
```

Verify that `enabled` is turned on under **Workspace → Tools → "1-on-1 Video Call Invite" → Valves** in OpenWebUI. Sending invites requires valid Twilio SID, Auth Token, caller number, and a public HTTPS `SERVER_DOMAIN`.

> **Note:** The 10-minute window applies only to the time allowed for both participants to join after an invite is generated. Once connected, the call has no time cap. SMS delivery and AI guide call placement are reported separately; verify actual audio/video connectivity in both browsers.

---

## 🛡️ AI Security Monitoring (SSH · Nginx · CrowdSec)

The install script deploys the **HackyHappy AI Security Agent** tool alongside a dedicated, least-privilege `security-monitor` container. Its purpose is defensive observability—monitoring server health and security logs, recording events, and dispatching alerts. It never executes offensive SET attack modules or harvests passwords, sessions, or tokens.

### Monitoring Scope

| Area | Behavior Configured by Install Script |
|------|---------------------------------------|
| Docker Service Health | Periodically polls health endpoints for `openapi-tools`, `twilio-bot`, `open-webui`, and `qdrant` |
| SSH Auth Logs | Monitors both `/var/log/auth.log` and SSH logs exported from systemd journal |
| Repeated SSH Login Failures | Logs a HIGH event candidate if 5+ failed logins occur from the same IP within 5 minutes |
| Nginx Access Logs | Scans JSON audit logs for suspicious URI patterns |
| Repeated Nginx Error Responses | Logs a MEDIUM event candidate if 25+ `401`/`403`/`404`/`444` responses occur from the same IP within 2 minutes |
| CrowdSec | Configures SSH/Nginx collections and queries active CrowdSec ban decisions and recent alerts |
| Event Storage | Persists security events in `tools-api/data/security_events.sqlite3` |

Nginx JSON audit logs record timestamps, IP headers, HTTP methods, URIs, status codes, response sizes/latencies, User-Agent, Referer, and request IDs. To keep video call session tokens out of logs, `/video-room/<token>` paths are masked as `/video-room/[REDACTED]`. Audit logs rotate daily with compression and 30-day retention.

### Alert & Automated Call Policy

| Event | Notification Policy |
|-------|---------------------|
| LOW / MEDIUM | Logged to database without noisy alerts |
| HIGH | Sends alert to configured Telegram; does **not** place automated Twilio calls |
| CRITICAL | Sends Telegram alert |
| Verified CRITICAL Service Outage | Automatically requests an admin Twilio call **only** when a previously healthy monitored service transitions to unhealthy |
| Admin-Initiated Emergency Call | Triggered via OpenWebUI tool **only** when the admin supplies the exact approval phrase `긴급 전화 승인` (Emergency Call Approved) |
| Duplicate Critical Events | Uses `alert_id` deduplication to suppress duplicate calls and never auto-retries ambiguous requests |

Suspicious SSH/Nginx traffic or standard HIGH events alone will never trigger automated phone calls. Automated calls are strictly limited to verified CRITICAL service outages detected by the security monitor.

### Security Monitoring Tool in OpenWebUI

The install script registers **"HackyHappy AI Security Monitoring"** and attempts to auto-populate its `SECURITY_API_SECRET` valve. If auto-population fails, manually paste the `API_SECRET` value from `.env` into the valve. Never paste secret keys into chat messages or public logs.

Available actions in the tool:

- `security_status` — View monitoring configuration, event counts, Telegram/Twilio status, and watch scope
- `list_security_events` — List recent security events (1–100 records)
- `record_security_event` — Log a defensive security event
- `security_defense_status` — Check CrowdSec and Docker security posture
- `security_defense_decisions` — View active CrowdSec ban decisions
- `security_defense_alerts` — View recent CrowdSec alerts
- `request_ip_unban` / `list_ip_unban_requests` — Submit an IP unban request and view pending requests
- `request_critical_phone_alert` — Place an emergency call when accompanied by the admin approval phrase
- `prepare_set_awareness_exercise` — Generates a defensive security awareness training plan for authorized, isolated lab environments (does not execute actual attack modules)

### Post-Install Status Commands

```bash
cd ~/HackyHappy-OpenWebUI

# Check security-monitor container status
docker ps --filter name=hackyhappy-security-monitor

# View recent security-monitor logs
docker logs --since 30m hackyhappy-security-monitor

# Check CrowdSec service status
sudo systemctl status crowdsec --no-pager

# Verify CrowdSec SSH/Nginx collections
sudo cscli collections list | grep -E 'sshd|nginx'

# View active CrowdSec bans and recent alerts
sudo cscli decisions list
sudo cscli alerts list

# Inspect SSH logs and Nginx audit logs
sudo tail -n 50 /var/log/auth.log
sudo tail -n 50 /var/log/nginx/audit.json.log

# Check SSH journal export timer
sudo systemctl status hackyhappy-ssh-journal-export.timer --no-pager
```

### CrowdSec Automated Firewall Blocking Requires Explicit Opt-In

During installation, the CrowdSec detection engine and SSH/Nginx collections are configured. However, **automated host firewall blocking via the Firewall Bouncer is skipped by default** and is only installed/enabled if you type the exact confirmation phrase when prompted:

```text
ENABLE CROWDSEC BOUNCER
```

Before enabling automated blocking, verify that your current SSH IP and admin IPs are allowlisted in CrowdSec—misconfiguration can lock you out of your own server. Because detection and firewall enforcement are separate services, verify both statuses independently if bouncer setup fails.

### Architectural Security Constraints & Operational Notes

- `security-monitor` does **not** mount the Docker socket and mounts log files strictly as read-only (`ro`).
- The container runs as a non-root user with `read_only` root filesystem, `no-new-privileges`, all Linux capabilities dropped, and memory limits enforced.
- Security APIs require internal network access and API secrets, while automated phone calls require separate `SECURITY_MONITOR_SECRET` verification.
- The AI tool's IP unban feature never removes firewall bans directly—it **only queues a pending request for admin approval**.
- CrowdSec installation, log ingestion, Nginx rules, and systemd journal permissions can vary across OS versions; always verify using the commands above after installation.
- Security logging and alerts do not guarantee immunity against compromise. Continue maintaining OS updates, backups, firewalls, SSH key hygiene, and regular log audits.

---

## Automatic Ollama Embedding Setup (WSL2)

Memory Anchor and semantic contact search default to **Ollama embeddings** (`nomic-embed-text`, 768 dimensions). The install script **automatically handles**:

> **You can use OpenAI instead of local Ollama.** Switching the VoiceMem Dual-Brain engine to OpenAI handles embeddings and analysis in the cloud, letting you skip Ollama setup. See [VoiceMem Dual-Brain Architecture](#-voicemem-dual-brain-architecture-left--right-brain-memory) for details.

- Installing Ollama and pulling the embedding model
- **Binding `OLLAMA_HOST=0.0.0.0`** — allowing Docker containers to reach Ollama on the host (automatically solving a common WSL2 pitfall)
- Auto-detecting the container-to-host IP and verifying connectivity

Seeing this message during installation confirms success:
```
✅ Ollama access verified (172.17.0.1:11434) — Memory Anchor / semantic search operational
```

**Verification** (post-install):
```bash
docker compose exec twilio-bot python3 -c "import ollama,os; c=ollama.Client(host=os.getenv('OLLAMA_BASE_URL')); print('OK', len(c.embeddings(model='nomic-embed-text', prompt='test')['embedding']), 'dims')"
```
Outputting `OK 768 dims` confirms everything is working.

> If Ollama cannot be reached, calls are still saved using dummy vectors, resulting in lower recall accuracy. If logs show `⚠️ Ollama embedding failed — using dummy vector`, start Ollama inside WSL2 with `OLLAMA_HOST=0.0.0.0:11434 ollama serve`.

---

## Monthly Call Time Limit (Billing Protection)

Caps the cumulative monthly duration of **inbound calls placed by admins to your Twilio number** to prevent unexpected telecom bills. (Outbound calls placed by the bot and automated alert calls received by the admin do not count toward this cap.)

- Exceeding the monthly limit (default 300 minutes) → blocks inbound admin calls until the next billing cycle
- Reaching 90% (default 270 minutes) → sends **one Telegram warning** (falls back to SMS if Telegram is unconfigured)
- Reaching 100% → sends a Telegram alert and blocks subsequent calls
- **Resets automatically on the 21st of every month** (e.g., July 21 – August 20 = one cycle)

Adjust limits in `ai_config.py`:

```python
MONTHLY_INBOUND_CALL_LIMIT_MIN = 300   # Monthly cap in minutes (0 = unlimited)
MONTHLY_CALL_WARN_PERCENT      = 90    # Warning threshold (%)
MONTHLY_CALL_LIMIT_ENABLED     = True  # Enable/disable feature
```

> ⚠️ Your Twilio phone number's **Status Callback URL** must be configured for call duration tracking to work. "Automatic Twilio Configuration" below handles this automatically.

---

## Automatic Twilio Configuration

When Twilio credentials and a public domain (`https://...`) are provided during installation, your phone number's webhooks are **configured automatically**—no manual URL entry in the Twilio Console required.

Auto-configured endpoints:

- **Voice URL** — `https://<domain>/voice` (inbound call handling)
- **SMS URL** — `https://<domain>/sms-incoming` (auto-forwarding incoming SMS replies)
- **Status Callback URL** — `https://<domain>/call-status` (monthly call duration tracking)

Verify configuration:

```bash
python3 - <<'PY'
import os
from twilio.rest import Client
env={}
for line in open(os.path.expanduser("~/HackyHappy-OpenWebUI/.env")):
    if "=" in line and not line.startswith("#"):
        k,v=line.strip().split("=",1); env[k]=v
c=Client(env["TWILIO_ACCOUNT_SID"], env["TWILIO_AUTH_TOKEN"])
n=c.incoming_phone_numbers.list(phone_number=env["TWILIO_PHONE_NUMBER"], limit=1)[0]
print("Voice:", n.voice_url); print("SMS:", n.sms_url); print("Status:", n.status_callback)
PY
```

If all three URLs print as `https://<domain>/...`, auto-configuration succeeded. If auto-configuration fails, manual setup instructions are printed in the installation log.

> 💡 On Kali or recent Ubuntu releases where `pip install twilio` is blocked by `externally-managed-environment`, the install script automatically passes `--break-system-packages`. Use `pip install twilio --break-system-packages` if installing manually.

### Voice & SMS Report Status Callbacks (Outbound Report Tracking)

To track submission, completion, and failure statuses of post-call voice report calls and SMS reports, Twilio sends dedicated status callbacks to separate endpoints:

- **Voice Report Status Callback** — `https://<domain>/report-voice-status`
- **SMS Report Status Callback** — `https://<domain>/report-sms-status`

The Nginx configuration generated by the install script routes these exact `location =` paths to Twilio Bot (internal port `5000`) rather than OpenWebUI (port `3000`), forwarding HTTPS proxy headers. Flask's `validate_twilio_request` continuously enforces `X-Twilio-Signature` validation. **Never disable signature verification or allow unauthenticated callback requests.**

After updating Nginx rules, validate syntax before reloading:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Inspect callback logs:

```bash
docker logs --since 10m twilio-bot 2>&1 | \
grep -E 'report-voice-status|report-sms-status|서명 검증|TwilioProxy'
```

Legitimate Twilio callbacks appear in the application logs as requests to `/report-voice-status` or `/report-sms-status`, returning HTTP `204` upon processing.

> **Note:** Calling these endpoints from a browser or plain `curl` without a valid Twilio signature header will properly return `403 Forbidden`—do not mistake this for a broken integration. Verify actual Twilio callback signature checks in the logs. Also note that HTTP `204` confirms the server received Twilio's status callback, not that the human recipient answered the call or read the SMS; check Twilio delivery logs and the receiving device for end-to-end confirmation.

If callbacks return `405`, verify Nginx routes the paths to Twilio Bot; if `403`, verify that the request originated from Twilio and that your public HTTPS URL, proxy headers, and Auth Token match. Never bypass signature validation.

---

## Cloudflare Tunnel Setup (External HTTPS Access)

Twilio requires a **public HTTPS URL** to deliver voice and SMS webhooks. Using Cloudflare Tunnel exposes your server securely over HTTPS **without opening firewall ports** (no router port-forwarding, static IP, or manual SSL certificates required).

### One-Time Preparation (Cloudflare Dashboard)

1. Register/add your domain in your Cloudflare account (e.g., `yourdomain.com`).
2. Navigate to **Zero Trust → Networks → Tunnels → Create a tunnel**.
3. Name your tunnel and create it → copy the generated **Tunnel Token** (long string).
4. Under **Public Hostnames**, map your domain (`yourdomain.com`) to your internal service:
   - Subdomain/Domain: `yourdomain.com`
   - Service: `http://localhost:3000` (OpenWebUI, or Nginx reverse proxy port as configured)

### Configure During Installation

When prompted during installation, enter `y` and paste your **Tunnel Token**:

```
☁️  Configure Cloudflare Tunnel? (y/N): y
   Enter Tunnel Token: eyJhIjoi...(your copied token)
```

`cloudflared` will be installed as a system service, start automatically, and make `yourdomain.com` accessible externally.

### Configure Later (If Skipped During Install)

You can set up Cloudflare Tunnel anytime after installation:

```bash
# Install cloudflared (Debian/Ubuntu/Kali)
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
sudo mv cloudflared /usr/local/bin/ && sudo chmod +x /usr/local/bin/cloudflared

# Install tunnel as a system service (token-based)
sudo cloudflared service install <TUNNEL_TOKEN>

# Check status
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f    # Live logs
```

### Verification

```bash
# Verify external HTTPS reachability
curl -I https://yourdomain.com

# Check cloudflared service status
sudo systemctl status cloudflared
```

Seeing `HTTP/2 200` confirms external access is working.

> 💡 **Keep Your Domain When Migrating Servers:** Because `cloudflared` authenticates via **token** rather than IP address, installing `cloudflared` with the same token on a new server automatically points `yourdomain.com` to the new host. Domain-based Twilio webhooks continue working without reconfiguration.

> ⚠️ **Keep Your Token Secret:** Never expose your tunnel token in logs, screenshots, or repositories. If leaked, delete the tunnel in the Cloudflare dashboard and create a new one.

> Cloudflare handles SSL termination automatically, so separate SSL certificates (such as Let's Encrypt) are **not needed**.

---

## Usage by Channel

### Phone

Call your bot from an authorized admin number and speak naturally:

- *"What's on my schedule today?"* → Reads today's calendar events aloud
- *"Call Chulsoo Kim"* → Places an outbound call to Chulsoo Kim
- *"Give Chulsoo Kim a check-in call and ask how he's doing"* → Bot places the check-in call on your behalf and reports back
- *"Send a text to Chulsoo Kim"* → Sends an SMS **by contact name** (auto-looks up phone number)

> ⏱️ Inbound admin calls count toward the monthly call time limit (default 300 minutes, resets on the 21st). Use Telegram or Web Chat for read-only queries to save minutes and telecom fees.

### Chat (OpenWebUI)

Enable tools and type naturally:

- *"What's on my schedule today?"* / *"Show call history"*
- *"Text Chulsoo Kim 'See you tomorrow at 3 PM'"* → Sends SMS by name (automatic number lookup)
- *"Show contacts"* → Displays 15 contacts per page · *"Contacts page 2"* / *"Next page"* to navigate
- *"Change Chulsoo Kim's number to 010-9999-8888"* → Updates contact
- *"Add Dentist on Dec 25 at 2 PM, remind me 1 hour before"* → Creates event with reminder
- *"Move the Dec 25 meeting to 5 PM"* → Updates event (automatically reschedules reminders)
- *"Delete the Dec 25 meeting"* → Deletes event (automatically cancels reminders)
- *"Any active calls?"* / *"Tell them I'll arrive shortly"* → **Real-Time Whisper** (instruct AI mid-call)
- *"Show current voice engine settings"* → Inspect STT/TTS settings via **Voice Engine Settings**
- *"What did I talk about with Chulsoo Kim last time?"* → Recall past calls via **Memory Anchor**

### Telegram

Message your Telegram bot:

- *"What's on my schedule today?"* → Queries calendar (supports adding, editing, and deleting events too)
- Send a file (PDF/image) → Indexes into RAG knowledge base
- **Send a voice message** → Automatically transcribes via STT and processes (requires OpenWebUI STT engine configuration)
- Web search queries → Displays **📚 Source Details + 🔗 Related Links** beneath the response
- `/remind daily 09:00 Check the weather` → Schedules recurring/one-off reminders
- **🤫 Real-Time Whisper during calls:** `이렇게 말해: 곧 찾아뵙겠다고 전해줘` / `/calls` → See [Real-Time Whisper](#real-time-whisper-in-call-instructions)

> 💡 To speak your message without sending an audio clip, tap the **microphone (dictation) button on your phone's keyboard** instead of Telegram's voice recorder to insert transcribed text directly.

#### 📨 Receiving Call Reports on Telegram (Optional)

To receive check-in and inbound call summaries on Telegram in addition to SMS:

1. Open `@BotFather` in Telegram → send `/newbot` → copy your **Bot Token** (`1234:ABC...`).
2. **Send any message (e.g., `/start`) to your new bot** (⚠️ Without this initial message, Telegram blocks the bot from messaging you).
3. Retrieve your Chat ID:
   ```bash
   curl -s "https://api.telegram.org/bot<BOT_TOKEN>/getUpdates" | grep -o '"id":[0-9]*' | head -1
   ```
4. Enter these values during installation, or add them later to `.env`:
   ```bash
   cd ~/HackyHappy-OpenWebUI
   echo "TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN" >> .env
   echo "TELEGRAM_CHAT_ID=YOUR_CHAT_ID" >> .env
   docker compose up -d twilio-bot
   ```

> If reports fail to arrive, inspect `docker compose logs twilio-bot | grep -i telegram` for diagnostics (missing values, `chat not found`, invalid token, etc.).

### Browser Agent

In OpenWebUI chat:

- *"Find prices on [Website]"*
- *"What's on my schedule today?"* (via Calendar method)

---

## Installation Verification

Run the verification script after installation to audit system integrity:

```bash
chmod +x verify-install.sh
./verify-install.sh
```

Checks performed (partial list):

- Directory layout, required files, and file permissions
- Docker container statuses and internal networking
- Registration of all 16 OpenWebUI tools (including #15 1-on-1 Video Call Invite and #16 HackyHappy AI Security Monitoring)
- **Calendar Integration** — `/owui-data` volume mount, shared API key, pinned `COMPOSE_FILE`
- **Security Hardening** — `requests`/`urllib3` CVE patches, `trust_env` disabled
- **Call Authentication** — Admin numbers configured, active `SERVICE_MODE` detected
- **Real-Time Voice** — `realtime-voice` container status, `/twilio-stream` proxy (when real-time mode is active)

---

## Prevention & Troubleshooting

### Phone Bot Reads "Fake Events" from the Calendar

This is almost always caused by a **missing calendar volume mount**. The current release permanently resolves this by pinning the mount in the main `docker-compose.yml` and locking `COMPOSE_FILE` in `.env`, ensuring the calendar stays connected across `docker compose up`, restarts, and server reboots.

Manual check:

```bash
# Verify mount exists (should list files)
docker exec twilio-bot ls -la /owui-data/

# Verify shared key exists (should print key)
docker exec twilio-bot cat /owui-data/shared-key/openwebui_api_key
```

If the mount is missing:

```bash
cd ~/HackyHappy-OpenWebUI
./calendar-up.sh
```

### Calendar Tool Times Out After 15 Seconds in Chat

If the same API responds instantly (`0.02s`) via `curl` but times out after 15 seconds in **Chat**, the cause is a **single-worker self-call deadlock**: OpenWebUI runs a tool on its sole worker, and that tool calls back into OpenWebUI's own API, leaving no free worker to handle the request.

Solution — Run OpenWebUI with multiple workers (**already applied in the current install script**):

```bash
cd ~/HackyHappy-OpenWebUI
# Ensure docker-compose.yml has the following under open-webui -> environment:
#   - UVICORN_WORKERS=4
docker compose up -d open-webui   # Must show "Started" or "Recreated" (not just "Running")

# Verify
docker exec openwebui-open-webui-1 sh -c 'cat /proc/1/environ | tr "\0" "\n" | grep UVICORN_WORKERS'
```

> Each worker consumes additional RAM. If memory is tight, `UVICORN_WORKERS=2` is sufficient to prevent the deadlock.

### Clear Error Messages When Calendar Lookup Fails

Instead of hallucinating fake schedule items on error, the bot reports the exact cause:

| Condition | Spoken / Displayed Message |
|-----------|----------------------------|
| Key not configured | *"The calendar API key has not been configured..."* |
| Connection error | *"Unable to connect to the calendar server..."* |
| Expired JWT key | *"Your key may have expired; please configure a new key."* |

---

## Security

| Control | Details |
|---------|---------|
| Call Authentication | Registered admin numbers + 6-digit PIN for sensitive commands (30-minute lockout after 3 failed attempts) |
| `requests` | `>=2.34.2` — Patched against CVE-2024-47081 (`netrc` credential leak) |
| `urllib3` | `>=2.6.3` — Patched against CVE-2026-21441 (DoS) |
| `trust_env` | Disables environment credential inheritance and blocks redirects during calendar API requests |
| Containers | `no-new-privileges` (all services), `cap_drop: ALL` (`redis`, `qdrant`, `tools`, `twilio-bot`, `realtime-voice`), non-root execution, memory caps |
| Nginx Headers | `server_tokens off`, `X-Frame-Options`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, `HSTS`, 25MB upload limit |
| Fail-Closed Auth | Missing `API_SECRET` blocks requests (`503`) rather than failing open across admin and `tools-api` endpoints |
| Secrets | Isolated in Docker Secrets files |
| Twilio | Enforces webhook signature validation (`validate_twilio_request` / `X-Twilio-Signature`); Nginx routes report status callbacks to Twilio Bot (`5000`) |
| Calendar Isolation | Strictly restricted to admins even when operating in Customer Service mode |
| Phone Number Leak Prevention | AI politely refuses requests to disclose admin or contact phone numbers and personal details during calls |
| Caller ID Masking | All outbound and forwarded calls display your Twilio number (hiding the admin's personal phone number) |
| Port Binding | Internal services (`Qdrant 6333`, `twilio-bot 5000`, `realtime-voice 5001`, etc.) bind strictly to `127.0.0.1` to block external access |
| Real-Time Voice Keys | STT/TTS API keys are masked in Valves UI and stored inside `voice_config.json` on an internal volume |
| Real-Time Whisper | Only the registered admin Telegram chat (`TELEGRAM_CHAT_ID`) can inject live call instructions |

> CVE patch versions reflect the state at the time of writing. Always review current security advisories before production deployment.

> The Qdrant dashboard (`localhost:6333/dashboard`) is bound to `127.0.0.1` and **cannot be accessed from the public internet**. However, local shell users on the host can access it without authentication—configure a Qdrant API key on multi-user servers.

---

## File Structure

The main installation script below is the authoritative source for this documentation. The Browser Agent, Telegram Bridge, Verification Script, and HTML documentation files are available only if separately bundled in your repository; the main installation script does not generate them.

```
.
├── HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh                  # Main installer (Customer/Personal selection · SERVICE_MODE)
├── setup-browser-agent-calendar-naver-search-api-only-hackyhappy-paths.sh   # Optional add-on: Browser Agent + Calendar
├── setup-telegram-bridge-calendar-hackyhappy-paths.sh                       # Optional add-on: Telegram Bridge + Calendar
├── verify-install.sh                                       # Optional add-on: Installation verification
└── docs/                                                   # Optional HTML setup guides (if included in repo)
    ├── index.html                                          # Overview & Requirements
    ├── install.html                                        # Installation, Phone Assistant, Calendar, Call Auth
    ├── operations.html                                     # RAG, Security, Maintenance, Backups
    ├── usage.html                                          # Telegram Bot
    ├── browser-agent.html                                  # Browser Agent
    └── cloud.html                                          # Cloud Deployment (24/7 Operation)
```

Key files and directories generated by the main installer (`~/HackyHappy-OpenWebUI/`):

```
~/HackyHappy-OpenWebUI/
├── docker-compose.yml                # Main compose file (includes calendar volume mount)
├── docker-compose.calendar.yml       # Backup calendar compose file (normally unneeded)
├── .env                              # Pinned COMPOSE_FILE & environment variables
├── calendar-up.sh                    # Helper script to restart with calendar mount
├── twilio-bot/                       # Phone bot source & ai_config.py
├── tools-api/                        # RAG, OpenWebUI tools API & security event SQLite DB
├── security-monitor/                 # Least-privilege SSH/Nginx/Docker monitor container
├── coturn/                           # WebRTC TURN relay configuration
├── realtime-voice/                   # 🎙️ True real-time voice server (Media Streams)
└── secrets/                          # Docker Secrets & API key files
```

---

## Frequently Asked Questions (FAQ)

**Q. The calendar doesn't work over the phone.**
A. Make sure you have run *"What's on my schedule today?"* at least once in OpenWebUI Chat so the API key gets shared with the phone bot. If it still fails, check the volume mount steps in [Prevention & Troubleshooting](#prevention--troubleshooting).

**Q. My API key starts with `eyJ...` instead of `sk-`.**
A. `eyJ...` is a JWT token. It works, but it has an expiration date. Go to **Settings → Account** and click **Create new secret key** to generate a non-expiring `sk-` key.

**Q. If I save someone in Contacts via chat, can they call the bot?**
A. No. Contacts are people the bot **calls out to**. To authorize someone to call *into* the bot, add their phone number to **Admin Numbers (`ADMIN_NUMBERS`)**.

**Q. In Customer mode, can customers view my calendar?**
A. No. Customers only interact with general AI support. Calendar, SMS, and system commands remain strictly restricted to admins.

**Q. I selected the wrong mode (Customer vs. Personal) during installation. Do I need to reinstall?**
A. No. Simply edit `SERVICE_MODE` in `twilio-bot/ai_config.py` (`"customer"` ↔ `"personal"`) and run `docker compose restart twilio-bot`. See [Two Operating Modes](#two-operating-modes).

**Q. What exactly changes when I switch `SERVICE_MODE` to `personal`?**
A. Inbound calls switch to a warm acquaintance check-in tone, the default greeting becomes personal, the keypad `0` operator prompt (`OPERATOR_HINT_ENABLED`) turns off, and the AI role label updates to "Personal Phone Assistant." Phone RAG search automatically switches to unified mode (sharing documents across Phone, Web, and Telegram), and proactive auto-calling (Memory Anchor) becomes available. Admin commands, billing caps, and security controls remain active in both modes.

**Q. I noticed Telegram also has a PIN setting?**
A. The Telegram bot's PIN is **separate from the Phone Bot PIN** (used for Telegram user verification) and is optional. The Phone Bot PIN is only checked before sensitive phone commands (calls, SMS, saving contacts, scheduling) and can be disabled via `ADMIN_PIN_REQUIRED = False` in `ai_config.py`.

**Q. Will the calendar disconnect again if I reboot the server?**
A. No. The volume mount is permanently pinned in both `docker-compose.yml` and `.env`, surviving reboots and container restarts.

**Q. Does the phone only ring the admin if the caller presses `0`?**
A. In standard bot mode (`BOT_MODE=2`), callers must press `0` or say a transfer keyword (e.g., "representative") to reach a human; otherwise, the AI continues handling the call. To forward all calls directly to a human, set `BOT_MODE=3` during installation or in `.env`.

**Q. How do I completely disable keypad `0` and voice transfers to a human?**
A. Set `OPERATOR_TRANSFER_ENABLED = False` and `OPERATOR_VOICE_ENABLED = False` in `ai_config.py`. Callers will still receive full AI support.

**Q. What happens if I press `N` at the Real-Time Mode prompt during installation?**
A. The system installs in standard turn-based mode. The `realtime-voice` container is created in an idle state, and calls exchange one sentence at a time. You can enable real-time mode anytime by setting `REALTIME_MODE=true` in `.env`.

**Q. I enabled True Real-Time Mode, but calls aren't running in real time.**
A. The most common cause is `SERVER_DOMAIN` not being a public HTTPS URL (`https://...`). Twilio requires `wss://` connectivity, which is impossible over `localhost`, causing an automatic fallback to standard mode. Set up Cloudflare Tunnel for a public HTTPS domain, then inspect `docker compose logs -f realtime-voice`.

**Q. How do I switch STT/TTS providers or voices?**
A. Open **Workspace → Tools → "Voice Engine Settings" → ⚙️ Valves** in OpenWebUI, update the fields, and click Save—changes apply immediately. See [Voice Engine Settings](#voice-engine-settings-stttts-valve-switching).

**Q. Does Real-Time Whisper only work in True Real-Time Mode?**
A. No, it works in standard turn-based mode too, though updates apply even faster in True Real-Time Mode.

**Q. Memory Anchor isn't recalling past conversations accurately.**
A. Recall accuracy relies on Ollama embeddings. Check `docker compose logs twilio-bot | grep 임베딩`—if you see `⚠️ 더미 벡터` (dummy vector), the container cannot reach Ollama. Start Ollama with `OLLAMA_HOST=0.0.0.0` as explained in [Automatic Ollama Embedding Setup](#automatic-ollama-embedding-setup-wsl2).

**Q. How do I enable automatic proactive check-in calls?**
A. Set `MEMORY_AUTOCALL_ENABLED = True` in `twilio-bot/ai_config.py` and run `docker compose restart twilio-bot`. By default, it runs safely in `"suggest"` mode (notifying the admin first). You can switch to `MEMORY_AUTOCALL_MODE = "auto"` after observing frequency and costs for a few days. → [Memory Anchor](#-memory-anchor-call-recall--proactive-auto-calls)

**Q. Post-call SMS reports are getting cut off too early.**
A. Recent updates expanded SMS report limits to 250 characters and increased internal token limits to prevent truncation. Re-run the installer or rebuild the bot with `docker compose up -d --build twilio-bot`.

**Q. I'm receiving SMS reports, but Telegram reports aren't arriving.**
A. Verify `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `.env`, and make sure you have **sent `/start` to your bot in Telegram first**. Check `docker compose logs twilio-bot | grep -i telegram` for the exact error. → [Receiving Call Reports on Telegram](#-receiving-call-reports-on-telegram-optional)

**Q. Can I get someone's phone GPS coordinates automatically just from a voice call?**
A. No. Standard phone calls cannot access the remote device's GPS hardware (a physical limitation of all telephony systems). Instead, the **GPS Location Sharing** tool sends an SMS link so the recipient can tap **[Allow]** in their browser to share real-time GPS with explicit consent. → [GPS Location Sharing](#️-gps-location-sharing-senior-care)

**Q. Can GPS Location Sharing work without the recipient's consent?**
A. No, and it is intentionally engineered not to. Coordinates are only sent when the recipient opens the link and taps **[Allow]**. Covert or non-consensual tracking is illegal; use this strictly with consent for senior care and safety checks.

**Q. How do I change the expiration time of GPS sharing links?**
A. The default is 30 minutes. Modify `GPS_SHARE_TTL_SEC` (in seconds) inside `twilio-bot/twilio_bot.py` and rebuild the container. Avoid setting excessively long expiration windows for security.

**Q. Location reports send coordinates, but the map image is missing.**
A. This may be due to folder permissions on `twilio-bot/data/reports` or a map API error. The latest install script automatically sets ownership to the bot user; rebuild with `docker compose up -d --build twilio-bot`.

**Q. How do I get satellite imagery for location map reports?**
A. Add a Google Maps API key to render Google hybrid satellite maps (satellite imagery + place names). Enter it during installation or save it to `secrets/google_maps_api_key` and rebuild. Without a Google key, it falls back to NAVER standard maps. → [Map Imagery — Google Satellite View](#map-imagery--google-satellite-view-optional)

**Q. Why does the satellite map look like a regular street map?**
A. The default `hybrid` mode overlays street names and labels onto satellite photography. In dense urban areas, labels can make it look like a standard map at first glance, though building rooftops and terrain are real satellite imagery. For unlabeled satellite imagery, change `"maptype": "hybrid"` to `"satellite"` in the code.

**Q. Location check calls start abruptly with "Where are you?" without saying hello.**
A. Older versions read the admin's command verbatim as the opening line. The latest version always starts with a polite greeting (*"Hello, [Name]. I'm calling on behalf of..."*) before asking for location consent. Reinstall or rebuild the bot container.

**Q. On a location check call, the AI keeps making small talk ("How are you?") instead of asking for location.**
A. The latest version omits small talk on location-specific calls and asks for location consent immediately after greeting, while keeping friendly small talk intact for regular check-in calls. Rebuild the container to apply.

**Q. The bot can't find subway stations like "Gangnam Station."**
A. NAVER Geocoding only resolves road and lot addresses (NAVER discontinued its Local Search API). Add a Kakao REST API key to enable station and business name lookup. → [Location Check (NAVER + Kakao + Google)](#-location-check-naver--kakao--google)

**Q. The AI keeps repeating the location consent question over and over.**
A. In older builds, unclear responses triggered repeated prompts. The latest version caps consent prompts at **2 attempts** before gracefully skipping the location check. Rebuild the container to apply.

**Q. The recipient answered the call, but the report says "No Answer / Voicemail."**
A. Older versions marked calls with zero user replies as unanswered. The latest version checks whether the opening greeting played (confirming call pickup) and distinguishes *"Answered, but caller did not speak"* from *"No Answer / Voicemail"*. Rebuild the container to apply.

**Q. The AI feels too impatient and cuts people off before they finish speaking.**
A. Increase `SPEECH_TIMEOUT_OUTBOUND` (pause wait time in seconds) and `TIMEOUT_OUTBOUND` (no-input hangup timeout in seconds) in `twilio-bot/ai_config.py`. Defaults are already tuned to `5`s and `8`s so seniors can speak comfortably; raise them to `6`s and `10`s for an even more relaxed pace, then run `docker compose restart twilio-bot`.

---

## License & Disclaimer

Review the contents of each script before using this repository, and carefully check the terms of service and pricing for your self-hosted environment and external providers (Twilio, Telegram, AI APIs).

> ⚠️ **Billing Notice:** This package integrates **paid external services** including voice calls, SMS, and AI APIs. **Always be mindful that excessive call volume can result in significant telecom and API charges.** Monitor your usage and billing dashboards regularly.

> 🔒 **Security & Legal Responsibility Notice:** All security responsibilities arising from installing and operating this software rest **solely with the installer/operator; the developer assumes no liability**. You are responsible for configuring firewalls, access controls, secret management, and server hardening. Furthermore, **all legal compliance obligations regarding call recording and logging (such as two-party/one-party consent laws and data privacy regulations) rest entirely with the operator and are unrelated to the developer.**