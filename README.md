# OpenWebUI + Twilio AI Phone Assistant + Calendar + Telegram + Browser Agent

**English** · **[한국어](README_ko.md)**

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
- [Call Features (Barge-in · Operator Transfer)](#call-features-barge-in--operator-transfer)
- [True Realtime AI Calls (Media Streams)](#true-realtime-ai-calls-media-streams)
- [Live Whisper (Mid-call Instructions)](#live-whisper-mid-call-instructions)
- [Voice Engine Settings (STT/TTS Valve Swap)](#voice-engine-settings-stttts-valve-swap)
- [🧠 Memory Anchor (Call Recall · Proactive Auto-call)](#-memory-anchor-call-recall--proactive-auto-call)
- [📍 Location Check (NAVER + Kakao)](#-location-check-naver--kakao)
- [Ollama Embedding Auto-setup (WSL2)](#ollama-embedding-auto-setup-wsl2)
- [Monthly Call Limit (Cost Protection)](#monthly-call-limit-cost-protection)
- [Twilio Auto-config](#twilio-auto-config)
- [Cloudflare Tunnel Setup (External HTTPS Access)](#cloudflare-tunnel-setup-external-https-access)
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
| 🎙️ True Realtime AI Calls | Twilio Media Streams enables **mid-sentence barge-in**. Deepgram (STT) + ElevenLabs (TTS), engine swappable via valves |
| 🤫 Live Whisper | While the AI is on a call, the admin sends **"say this"** via Telegram/app → the AI weaves it into its next line naturally |
| 🧠 Memory Anchor | Embeds calls per phone number → on the next call, **auto-recalls past memories from a similar time-of-day/weather** to steer the conversation. Can proactively suggest a check-in call when conditions match (optional) |
| 📍 Location Check (NAVER + Kakao) | During a check-in call, **after obtaining the person's consent**, asks for their location and reports the spoken location to **Telegram with a map image**. Uses NAVER Geocoding (road/lot addresses) + Kakao Local (station names, business names, landmarks) together for broad coverage. Does not secretly collect phone GPS |
| 📇 Smart Contacts | Text/call by name (auto number lookup), edit/delete contacts, paginated list (15/page) |
| 📅 Calendar (view·add·edit·delete) | Query & add events, plus **edit·delete**. Phone/SMS reminders auto-reschedule when time changes |
| ✋ Barge-in | Interrupt the AI mid-sentence; it stops and focuses on your new question |
| ☎️ Operator transfer | Reach a human (admin) via keypad 0 or voice (independently toggleable) |
| ⏱️ Monthly Call Limit | Cap admin inbound-call minutes (default 300). Telegram warning at 90%, block over limit, resets on the 21st |
| 💬 Telegram Bot | Chat with OpenWebUI, index files, schedule reminders, **voice messages (STT)**, **search source links** |
| 🤖 Browser Agent | AI browses websites, takes screenshots, extracts data |
| 📚 RAG | Answers grounded in your uploaded documents |
| 🔒 Hardened Security | Container hardening, Docker Secrets, CVE patches, number-based call auth, **phone-number leak prevention** |
| ⚡ Twilio Auto-config | Automatically sets Voice·SMS·Status Callback URLs via Twilio API during install |

---

## Two Operating Modes

The assistant runs as either **Personal** or **Customer Support**, depending on your use case.

| Mode | Character | When an unknown number calls | Calendar / commands |
|------|-----------|------------------------------|---------------------|
| **Personal** | Acquaintance check-in / proxy-call assistant | AI responds in a warm check-in tone (no operator hint) | Admin only |
| **Customer Support** | Customer consultation | AI handles a general consultation (press-0 operator transfer hint ON) | Admin only (customers cannot access) |

> In **both** modes, sensitive features (calendar, SMS, commands) are restricted to the **admin** (the number entered during installation). Even in customer-support mode, a customer saying "what's my schedule today" cannot access the calendar.

### How to choose the mode — first install prompt + switch anytime

`start-openwebui-customer-support.sh` asks for the use case **as the very first thing** when you run it.

```
🎯 What will you use this for?
   1) Customer Support
   2) Personal AI assistant
Select (1/2) [default: 1 = Customer Support]:
```

- **1 (or Enter)** → installs in Customer Support mode
- **2** → installs in Personal AI assistant mode

Your choice is written automatically to **`SERVICE_MODE`** in `twilio-bot/ai_config.py`. After installation you can switch between the two modes **without reinstalling** by editing that single line.

```bash
cd ~/OpenWebUI
nano twilio-bot/ai_config.py
#   SERVICE_MODE = "customer"   ← Customer Support
#   SERVICE_MODE = "personal"   ← Personal
docker compose restart twilio-bot
```

Changing `SERVICE_MODE` adjusts these at once:

| Item | `customer` | `personal` |
|------|-----------|-----------|
| Inbound call persona | Customer consultation | Acquaintance check-in |
| Default greeting | Consultation style | Check-in style |
| Operator press-0 hint (`OPERATOR_HINT_ENABLED`) | ON | OFF |
| AI role label (`AI_ROLE`) | Customer support assistant | Personal phone assistant |
| Phone RAG search scope | Separated (follows .env default) | Auto-switches to unified (phone·web·Telegram share docs) |
| Proactive auto-call (Memory Anchor) | Off (default) | Can be enabled (`MEMORY_AUTOCALL_ENABLED`) |

> `SERVICE_MODE` flips the **default bundle** of "persona / greeting / operator hint." Each individual setting (operator transfer, auto-call, etc.) can still be fine-tuned separately in `ai_config.py`; if you set an individual value directly, it takes precedence.

> **Phone RAG scope auto-switch:** Even if you installed with separated search, setting `SERVICE_MODE = "personal"` makes the phone bot switch to unified search (phone·web·Telegram reference the same documents) without editing `.env`. Leaving it on `customer` keeps the `.env` default chosen at install. Applies after `docker compose restart twilio-bot`.

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

**A single script installs either Personal or Customer Support.** When you run it, the first prompt asks for the use case.

```bash
wget https://YOUR-HOST/start-openwebui-customer-support.sh
less start-openwebui-customer-support.sh    # review before running (recommended)
chmod +x start-openwebui-customer-support.sh
./start-openwebui-customer-support.sh
```

The **very first** thing it asks is the use case (see [Two Operating Modes](#two-operating-modes) for details).

```
🎯 What will you use this for?
   1) Customer Support
   2) Personal AI assistant
```

> If you want pure personal use (no customer-consultation path), you may run `start-openwebui-hardened-admin-only.sh` instead. But choosing **2 (Personal)** in the script above also installs in personal mode.

Inputs during installation (in order):

| Item | Example | Notes |
|------|---------|-------|
| **Service mode** | `1` / `2` | **Asked first** — 1=Customer Support, 2=Personal. Written to `SERVICE_MODE` in `ai_config.py`; switchable later |
| Your phone number | `+12025550123` | **Admin number** (permission to call the bot). Comma-separate for multiple |
| Twilio info | SID / Token / number | For phone features |
| Server domain | `https://yourdomain.com` | For Twilio webhooks |
| Admin email / password | — | For OpenWebUI login |
| AI mode | `2` | 1=OpenWebUI, 2=Groq, 3=forwarding |
| Contacts | `John,+12025559876` | Targets the bot **calls out to** (unrelated to call permission) |
| RAG search mode | `1` / `2` | 1=Unified, 2=Separated. Default auto-recommended by service mode (personal→Unified, customer→Separated) |
| True realtime mode | `y` / `N` | `y` prompts for Deepgram·ElevenLabs keys (paid). `N` (default) keeps the classic method; can be enabled later |
| Telegram reports | `y` / `N` | `y` prompts for bot token·chat ID → call reports arrive via Telegram too, not just SMS. `N` (default) = SMS reports only |
| NAVER location check | `y` / `N` | `y` prompts for NAVER Maps Client ID·Secret → enables location check + map reporting during check-in calls. Then (optional) a Kakao REST API key lets it also find station/business names like "Gangnam Station". `N` (default) = location feature off |

> **A 6-digit admin PIN is set.** During installation, at the "Enter 6-digit admin PIN" prompt you either choose one or press Enter to auto-generate it (an auto-generated PIN is shown on screen — write it down). The PIN is checked only when running **sensitive commands** on a call (save contact, place a call, send SMS, schedule), and is not asked for normal conversation or lookups like "what's my schedule today." Verifying once per call keeps it valid for the rest of that call. See [Call Authentication](#call-authentication-security) for details.

> **🎙️ True realtime mode is optional.** At the "Enable true realtime mode? (y/N)" prompt, pressing `N` (or Enter) installs with the **classic method** unchanged. You can enable it anytime later via `REALTIME_MODE=true` in `.env`. See [True Realtime AI Calls](#true-realtime-ai-calls-media-streams) for details.

> **📨 Telegram reports are also optional.** Provide values at the "Enable Telegram reports? (y/N)" prompt to also receive reports via Telegram. Skipping keeps SMS reports working. See the Telegram item under [Usage by Channel](#usage-by-channel) for setup.

> **📍 Location check is also optional.** Answer `y` at "Enable NAVER Maps location check? (y/N)" to enter your NAVER Maps keys and turn on the location feature. Optionally add a Kakao REST API key to also resolve station/business names. Location reports arrive via **Telegram** with a map image, so enabling Telegram reports together is recommended. See [Location Check (NAVER + Kakao)](#-location-check-naver--kakao) for details.

When installation finishes, the full stack (OpenWebUI, phone bot, RAG, realtime voice server, etc.) starts automatically and **13 tools (including calendar, live whisper, voice engine settings, memory anchor, and NAVER location check) are registered automatically**.

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

### Getting event reminders by phone/SMS (`TWILIO_BOT_SECRET`)

To attach an "N-minutes-before" reminder to an event and receive it **by phone/SMS**, put the `.env` **`API_SECRET`** value into the calendar tool's `TWILIO_BOT_SECRET` valve. (Leave it empty to skip reminder call/SMS scheduling.)

**How to find the API_SECRET value:**

```bash
# Show the API_SECRET value in .env (paste this into the valve)
grep API_SECRET ~/OpenWebUI/.env
```

Example output:
```
API_SECRET=abcd1234efgh5678...
```

Copy the value after `=` (`abcd1234...`), then paste it into:

**Workspace -> Tools -> "Calendar (view·add·edit·delete)" -> Valves -> `TWILIO_BOT_SECRET`** and Save.

> In short, the calendar tool's valves take **two** keys:
> - `OPENWEBUI_API_KEY` <- the API key generated in OpenWebUI (for reading events)
> - `TWILIO_BOT_SECRET` <- the `.env` `API_SECRET` value (for scheduling reminder calls/SMS)

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

### Browser agent access key (`BROWSER_AGENT_API_KEY`)

The auth key used to reach the browser-agent service (or for the tool to call the agent) is auto-generated in `.env` at install time. To retrieve it:

```bash
# Show the AI browser agent API key
grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env
```

Example output:
```
BROWSER_AGENT_API_KEY=xyz9876abcd...
```

Copy the value after `=`. (This is a **different value** from the calendar `OPENWEBUI_API_KEY`.)

> Quick reference — three keys you'll often look up in `.env`:
> - `OPENWEBUI_API_KEY` — generated in OpenWebUI (for calendar reads; may not be in .env)
> - `API_SECRET` — phone-bot secret (goes into the calendar `TWILIO_BOT_SECRET` valve)
> - `BROWSER_AGENT_API_KEY` — for browser-agent access

---

## Call Authentication (Security)

### Call authentication — registered admin number + 6-digit PIN for sensitive commands

Call authentication works in two steps:

1. **Number authentication** — only calls from a registered admin number (`ADMIN_NUMBERS`) get admin privileges. In personal mode, unknown numbers are blocked immediately; in customer-support mode they are routed to general AI consultation.
2. **PIN check (sensitive commands only)** — even as admin, a 6-digit PIN is checked once when running **sensitive commands** (save contact, place a call, send SMS, schedule). It is not asked for normal conversation or lookups like "what's my schedule today." Verifying once per call keeps it valid for the rest of that call.

The PIN is set during installation (chosen manually or auto-generated with Enter). **Three wrong attempts lock it for 30 minutes** (auto-released).

**Why this design:** number authentication alone already filters outsiders, but to guard against caller-ID spoofing, sensitive commands that move real money/data get an extra PIN layer. Lookups and small talk skip the PIN, so everyday use stays frictionless.

> To disable the PIN check entirely, set `ADMIN_PIN_REQUIRED = False` in `ai_config.py` and run `docker compose restart twilio-bot`. Then a registered admin number alone can run sensitive commands directly. ⚠️ However, with caller-ID spoofing an attacker could impersonate the admin and trigger calls/SMS/scheduling, so disabling the PIN is not recommended.

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

## Call Features (Barge-in · Operator Transfer)

Tune call naturalness and human transfer in `ai_config.py`. Apply changes with `docker compose restart twilio-bot`.

### Barge-in

When the caller interrupts mid-sentence, the AI stops immediately, acknowledges briefly, then focuses on the new question — just like talking to a person.

| Setting | Default | Description |
|---------|---------|-------------|
| `BARGEIN_THRESHOLD` | `0.6` | Sensitivity (0–1). Higher = interrupts more easily. 0.4 = less sensitive (noisy environments) |
| `BARGEIN_MIN_SECONDS` | `3.0` | Replies shorter than this are excluded from barge-in |
| `BARGEIN_ENABLED` | `True` | `False` disables barge-in handling |
| `BARGEIN_NOTE` | (instruction) | How the AI reacts when interrupted |

> In noisy places the AI may stop on background noise. Lower `BARGEIN_THRESHOLD` to 0.4, or set `BARGEIN_ENABLED = False`.

### Operator (human) transfer — keypad 0 / voice

Two independent paths to reach a human (admin) while talking to the AI.

| Setting | Default | Description |
|---------|---------|-------------|
| `OPERATOR_TRANSFER_ENABLED` | `True` | Keypad **0** transfer |
| `OPERATOR_VOICE_ENABLED` | `True` | Voice "representative" transfer |
| `OPERATOR_HINT_ENABLED` | `True` | "Press zero" voice hint |
| `OPERATOR_VOICE_KEYWORDS` | (list) | Keywords that trigger voice transfer (editable) |

Example combinations:

```python
# Fully unattended AI (disable all human transfer)
OPERATOR_TRANSFER_ENABLED = False
OPERATOR_VOICE_ENABLED    = False

# Add voice keywords
OPERATOR_VOICE_KEYWORDS = ["representative", "agent", "human", "manager"]
```

> Even with all transfers off, external callers still get **AI consultation**, and the post-call admin report still works. Sensitive features like the calendar remain admin-only.

---

## True Realtime AI Calls (Media Streams)

The default call mode is "one sentence at a time" (Twilio Gather). Turn on **true realtime mode** and Twilio Media Streams pipes the full call audio through, giving you a genuine realtime conversation where **the AI can react and barge in even while the other party is still speaking**.

| Aspect | Classic (default) | True realtime mode |
|--------|-------------------|--------------------|
| Method | Say a sentence → AI replies (turn-based) | Audio streaming (Media Streams) |
| Barge-in | Per sentence | Instant, **mid-sentence** (barge-in) |
| Engine | Twilio built-in STT/TTS | Deepgram (STT) + ElevenLabs (TTS) |
| Requirements | None | Public HTTPS domain + paid API keys |
| Cost | Twilio call charges only | + Deepgram·ElevenLabs usage |

### How to enable

**At install**: answer `y` to "Enable true realtime mode? (y/N)" → enter Deepgram·ElevenLabs keys.

**Enable later**:

```bash
cd ~/OpenWebUI
nano .env
# REALTIME_MODE=false  ->  true
# Fill in DEEPGRAM_API_KEY=... and ELEVENLABS_API_KEY=... (or via the voice-engine valves below)
docker compose up -d
```

### Requirements (important)

- A **public HTTPS domain** is mandatory (`SERVER_DOMAIN` must be `https://...`), because Twilio connects to `wss://your-domain/twilio-stream`. Realtime does not work over `localhost`; in that case it **automatically falls back to the classic method**.
- Cloudflare Tunnel is an easy way to get a public HTTPS domain (see [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup-external-https-access)).

### How it works

```
Call → twilio-bot checks REALTIME_MODE → returns <Connect><Stream> TwiML
     → Twilio connects to wss://domain/twilio-stream (nginx proxies to realtime-voice)
     → realtime-voice: caller audio → Deepgram (STT) → LLM → ElevenLabs (TTS) → played back
     → When the caller starts talking, the AI stops instantly (barge-in)
```

`realtime-voice` installs as a separate container. Even if you don't enable realtime, it sits idle and harmless. To stop it entirely: `docker compose stop realtime-voice`.

### Tuning (when calls feel off)

Actual call quality (latency, choppiness, barge-in sensitivity) is tuned in `realtime-voice/realtime_server.py`.

| Value | Description |
|-------|-------------|
| Deepgram `endpointing=300` | Milliseconds of silence before treating speech as "sentence end." Higher = more deliberate, lower = faster |
| ElevenLabs `optimize_streaming_latency` | Latency-minimization strength |
| LLM `max_tokens=120` | Reply length (keep it short for calls) |

> Watch caller speech, AI replies, and barge-ins in the logs: `docker compose logs -f realtime-voice`

---

## Live Whisper (Mid-call Instructions)

**While** the AI is on a call with someone, the admin can send **"say this: ○○○"** via Telegram or the OpenWebUI chat/app, and the AI **weaves it naturally into its next line** (without revealing it was instructed or that it's an AI).

> Works in the default (turn-based) method too; it just applies faster in true realtime mode.

### Instruct via Telegram

Send the bot a message in one of these formats (applied immediately).

| Input | Action |
|-------|--------|
| `say this: tell them I'll visit soon` | Weave it into the next line |
| `whisper: brighten the tone` | Style instruction |
| `John say this: I'll call next week` | **Target** a specific call when several are active |
| `/calls` | List calls in progress |

> Telegram instructions require `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` in `.env`, and only the registered admin chat can instruct. (You can still use the OpenWebUI tool below even without Telegram.)

### Instruct via OpenWebUI chat/app

Use the **"Live Whisper"** tool.

- "Am I on a call right now?" → list active calls
- "Tell them I'll visit soon" → the AI applies it on its next line
- Pending instructions can also be canceled

---

## Voice Engine Settings (STT/TTS Valve Swap)

Change the **STT (speech-to-text) / TTS (text-to-speech) provider, API key, and voice** used in true realtime calls from the OpenWebUI valves (⚙️ settings) — just like the calendar tool, you fill values into the gear panel.

### Setup order

1. OpenWebUI → **Workspace → Tools → "Voice Engine Settings (Realtime STT/TTS)" → ⚙️ Valves**
2. Enter the values below and **Save**

| Valve | Description | Default |
|-------|-------------|---------|
| `STT_PROVIDER` | Speech-to-text provider | `deepgram` |
| `DEEPGRAM_API_KEY` | STT API key | (empty) |
| `STT_MODEL` | STT model | `nova-2` |
| `TTS_PROVIDER` | TTS provider (`elevenlabs` or `deepgram`) | `elevenlabs` |
| `ELEVENLABS_API_KEY` | TTS API key (Deepgram key if TTS is deepgram) | (empty) |
| `TTS_VOICE` | Voice ID (e.g., an ElevenLabs voice ID) | Rachel |
| `TTS_MODEL` | TTS model | `eleven_flash_v2_5` |
| `LANGUAGE` | Call language (ko/en/ja/zh) | `ko` |

3. **Saving applies it immediately** (OpenWebUI re-initializes the tool on save, which syncs to the server).
4. The new engine takes effect from the next call.

> To verify, ask in chat "show the current voice engine settings" → displays the current STT/TTS and voice (API keys masked as `abcd***yz`).
>
> If it doesn't seem to apply on save, run "apply voice engine settings" once in chat to force a sync.

---

## 🧠 Memory Anchor (Call Recall · Proactive Auto-call)

Call content is **embedded and stored per phone number in a vector DB (Qdrant)**, so that on the next call with the same person, the AI **automatically recalls past memories from similar conditions (time-of-day, weather)** and continues the conversation naturally.

Example: someone who said they felt down on a rainy evening — on the next rainy-evening call, the AI proactively checks in: "Last time you seemed to be having a hard time, how are you doing?"

### Saving (automatic)

Saved automatically when a call ends. No setup required.

- Stored: phone number, name, date, **time-of-day** (morning/noon/afternoon/evening/night), **weather**, **emotion**, **topic**, summary, raw transcript
- Emotion/topic/summary are auto-extracted from the call by the AI
- Works for outbound, inbound, **and** realtime calls

> Quality depends on **Ollama embeddings**. Ollama must be reachable to find semantically similar memories. (See [Ollama Embedding Auto-setup](#ollama-embedding-auto-setup-wsl2))

### Recall (automatic, during calls)

Early in the next call, the AI searches that person's past memories by phone number, **boosts those matching the current time-of-day/weather**, and weaves the most relevant one into the conversation naturally (without revealing it's an AI or that it checked records).

### Manual lookup (tool)

Use the **"Memory Anchor"** tool in OpenWebUI chat.

- "What did I talk about with John before?" → list of past call memories
- "Find the conversation about switching jobs" → search by topic

### Proactive auto-call (optional · off by default)

You can let the system **proactively suggest or place a check-in call** when conditions match. Enable it in `ai_config.py`.

```python
# twilio-bot/ai_config.py
MEMORY_AUTOCALL_ENABLED = False     # ← set True to enable (off by default)
MEMORY_AUTOCALL_MODE = "suggest"    # suggest=notify admin / auto=place call
MEMORY_AUTOCALL_HOURS = [10, 20]    # allowed calling hours (10:00–20:00, no late-night)
MEMORY_AUTOCALL_COOLDOWN_DAYS = 7   # min days between calls to the same person
MEMORY_AUTOCALL_MATCH = ["time_slot", "weather"]  # conditions that must match the past
MEMORY_AUTOCALL_MAX_PER_DAY = 3     # daily cap (cost protection)
```

Then `docker compose restart twilio-bot`.

| Mode | Behavior |
|------|----------|
| `suggest` (default·safe) | On a match, notifies the admin via Telegram/SMS: "Good time to call ○○" → admin places the call |
| `auto` | On a match, places the check-in call immediately (mind cost·frequency) |

> **4 safety guards**: master-off default · allowed hours · per-person cooldown · daily cap. Start with `suggest`, observe for a few days, then move to `auto` if desired.

---

## 📍 Location Check (NAVER + Kakao)

During a check-in call, this feature **asks the person for their location and, once they consent**, reports the spoken location to **Telegram with a map image**. (It is also registered as the 13th tool, so you can look up a place's location/map without a call.)

> ⚠️ **Privacy:** This feature only uses the location **the person tells you by voice during the call**. It does not secretly collect phone GPS. Pulling GPS from the other party's handset over a plain voice call is technically impossible; use this only when you have told the person about the location check/report and obtained their consent.

### Flow

```
Location check begins during a check-in call
  ↓
"The administrator asked me to check your current location. Could you tell me where you are?
 Say yes if you agree, or no if you'd rather not."
  ↓
[person says "yes"] → "Please tell me where you are right now"
      ↓  (person answers, e.g. "Yeoksam-dong", "Gangnam Station")
   Try NAVER Geocoding → fall back to Kakao Local search if not found
      ↓  coordinates resolved → NAVER static map image generated
   📨 Map image + address sent to the admin's Telegram
[person says "no"] → skip location check, continue the check-in chat
```

- The **consent question repeats at most twice** (prevents an infinite loop on no/unclear answers). If yes/no isn't confirmed within two tries, the location check is skipped.
- If the call's **main purpose is the location check** ("ask ○○ where they are"), the bot wraps up politely after getting the location.
- If it's a **check-in call that also asked for location**, the bot keeps chatting after getting the location.

### NAVER + Kakao combined search

Two map services are used together for broad coverage.

| Target | NAVER Geocoding | Kakao Local |
|--------|:---------------:|:-----------:|
| Road/lot addresses (e.g. Sejong-daero 110) | ✅ | ✅ |
| Station/business/landmark names (e.g. Gangnam Station, ○○ Hospital) | ❌ | ✅ |

- Tries **NAVER Geocoding** first (accurate for road/lot addresses).
- Falls back to **Kakao Local keyword search** if not found (covers station/business/landmark names).
- The map image uses NAVER Static Map.

> NAVER discontinued its Local search API, so geocoding cannot resolve station/business names. Keeping Kakao Local as a fallback lets answers like "Gangnam Station" be converted to coordinates. Without a Kakao key, only road/lot addresses are recognized; if not found, the bot asks the person to repeat with a nearby neighborhood, large building, or road name.

### Prerequisites — API keys

**1) NAVER Maps (required)** — location lookup + map image
1. Sign in to [NAVER Cloud Platform](https://console.ncloud.com) → search **Maps** → open the service
2. **Register an Application** → enable **Geocoding** and **Static Map**
3. Get **Client ID** and **Client Secret** from the credentials page
   - The API domain is `maps.apigw.ntruss.com` (not the old `naveropenapi.apigw.ntruss.com`).
   - Geocoding and Static Map each include a generous monthly free tier.

**2) Kakao REST API (optional · for station/business names)**
1. Sign in to [Kakao Developers](https://developers.kakao.com) → **My Application → Add an application**
2. Open the app → copy the **REST API key** under **App Keys**
3. Left menu **Kakao Map** → **turn activation ON**
   - Kakao Local API offers a generous daily free quota and requires no payment method.

### Entering keys — during install or later

During install, answer `y` at "Enable NAVER Maps location check?" and enter the NAVER Client ID·Secret and (optionally) the Kakao REST API key. Keys are stored safely as **Docker Secrets** files.

To enable later or rotate keys, drop the secrets files in and restart.

```bash
cd ~/OpenWebUI
# NAVER
echo -n "YOUR_NAVER_CLIENT_ID"     >  secrets/naver_maps_client_id       2>/dev/null || true
echo -n "YOUR_NAVER_CLIENT_SECRET" >  secrets/naver_maps_client_secret
# Kakao (optional)
echo -n "YOUR_KAKAO_REST_API_KEY"  >  secrets/kakao_rest_api_key
# turn the feature on in .env (add if missing)
grep -q NAVER_LOCATION_ENABLED .env || echo "NAVER_LOCATION_ENABLED=true" >> .env
docker compose up -d --build twilio-bot
```

> `NAVER_MAPS_CLIENT_ID` lives in `.env` (env var); the Secret and Kakao key are managed as `secrets/` files. The code reads env var → secrets file in order, so keys load safely from file even when a gunicorn worker doesn't inherit the environment.

### Verify

Ask the running bot directly to confirm behavior (location lookup + Telegram map).

```bash
docker exec twilio-bot python3 -c "
import requests
sec = open('/run/secrets/api_secret').read().strip()
r = requests.post('http://localhost:5000/naver-location',
    headers={'X-API-Secret': sec, 'Content-Type':'application/json'},
    json={'place':'110 Sejong-daero, Jung-gu, Seoul', 'report_to_telegram':True, 'contact_name':'Test'}, timeout=20)
print(r.status_code); print(r.text[:300])
"
```

If you get `ok:true` with an address and a map image arrives in Telegram, it's working.

---

## Ollama Embedding Auto-setup (WSL2)

Memory Anchor and contact semantic search use **Ollama embeddings** (`nomic-embed-text`, 768-dim). The installer handles the following **automatically**:

- Installs Ollama and pulls the embedding model
- **Binds `OLLAMA_HOST=0.0.0.0`** so Docker containers can reach the host Ollama (auto-fixes a common WSL2 pitfall)
- Auto-detects the container→host IP and runs a connectivity test

During install, this message means success:
```
✅ Ollama reachable (172.17.0.1:11434) — Memory Anchor / semantic search working
```

**Verify** (after install):
```bash
docker compose exec twilio-bot python3 -c "import ollama,os; c=ollama.Client(host=os.getenv('OLLAMA_BASE_URL')); print('OK', len(c.embeddings(model='nomic-embed-text', prompt='test')['embedding']), 'dims')"
```
`OK 768 dims` means it's perfect.

> If Ollama isn't reachable, saving still works (dummy vectors) but recall quality drops. If logs show `⚠️ Ollama embedding failed — dummy vector`, run `OLLAMA_HOST=0.0.0.0:11434 ollama serve` inside WSL2.

---

## Monthly Call Limit (Cost Protection)

Caps the monthly total minutes for calls the admin **places to** the Twilio number, preventing unexpected call charges. (Outbound calls the bot makes, and reminder calls the admin receives, are not counted.)

- Over the monthly cap (default 300 min) → admin inbound calls are blocked until the next cycle
- At 90% (default 270 min) → **one Telegram warning** (falls back to SMS if Telegram isn't set up)
- At 100% → Telegram alert + calls blocked
- Auto-resets **on the 21st of each month** (e.g. 7/21–8/20 is one cycle)

Adjust in `ai_config.py`:

```python
MONTHLY_INBOUND_CALL_LIMIT_MIN = 300   # monthly cap (minutes), 0 = unlimited
MONTHLY_CALL_WARN_PERCENT      = 90    # warning threshold (%)
MONTHLY_CALL_LIMIT_ENABLED     = True  # on/off
```

> ⚠️ Requires the Twilio number's **Status Callback URL** to be set. "Twilio Auto-config" below handles this, so usually no manual step is needed.

---

## Twilio Auto-config

During install, if Twilio credentials and a public HTTPS domain are available, the phone number's webhooks are **configured automatically** — no need to enter URLs by hand in the Twilio Console:

- **Voice URL** — `https://<domain>/voice`
- **SMS URL** — `https://<domain>/sms-incoming`
- **Status Callback URL** — `https://<domain>/call-status` (for monthly call accounting)

Verify:

```bash
python3 - <<'PY'
import os
from twilio.rest import Client
env={}
for line in open(os.path.expanduser("~/OpenWebUI/.env")):
    if "=" in line and not line.startswith("#"):
        k,v=line.strip().split("=",1); env[k]=v
c=Client(env["TWILIO_ACCOUNT_SID"], env["TWILIO_AUTH_TOKEN"])
n=c.incoming_phone_numbers.list(phone_number=env["TWILIO_PHONE_NUMBER"], limit=1)[0]
print("Voice:", n.voice_url); print("SMS:", n.sms_url); print("Status:", n.status_callback)
PY
```

> 💡 On Kali/recent Ubuntu, if the twilio package install is blocked by `externally-managed-environment`, the installer handles it with `--break-system-packages`. For manual installs use `pip install twilio --break-system-packages`.

---

## Cloudflare Tunnel Setup (External HTTPS Access)

For Twilio to deliver call/SMS webhooks, your server must be reachable at a **public HTTPS address**. Cloudflare Tunnel provides secure external HTTPS access **without opening any ports** (no router port-forwarding, static IP, or manual SSL certificate required).

### Prerequisites (once, in the Cloudflare dashboard)

1. Add your domain to a Cloudflare account (e.g. `example.com`).
2. Go to **Zero Trust → Networks → Tunnels → Create a tunnel**.
3. Name the tunnel and create it → you'll get a **tunnel token** (a long string). Copy it.
4. Under **Public Hostnames**, map your domain to the internal service:
   - Subdomain/Domain: `example.com`
   - Service: `http://localhost:3000` (OpenWebUI) or as needed

### During installation

When the installer asks, choose `y` and paste the **tunnel token**:

```
☁️  Set up Cloudflare Tunnel? (y/N): y
   Enter token: eyJhIjoi...(the copied token)
```

`cloudflared` is installed as a system service and starts automatically, making your domain reachable externally.

### Setting it up later

You can add it anytime, even if you skipped it during install:

```bash
# Install cloudflared (Debian/Ubuntu/Kali)
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
sudo mv cloudflared /usr/local/bin/ && sudo chmod +x /usr/local/bin/cloudflared

# Install the tunnel as a system service (token method)
sudo cloudflared service install <TUNNEL_TOKEN>

# Check status
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f    # live logs
```

### Verify

```bash
# Check external reachability
curl -I https://example.com

# cloudflared service status
sudo systemctl status cloudflared
```

An `HTTP/2 200` (or similar) response means it's working.

> 💡 **Move servers without changing the domain**: cloudflared connects via **token**, not IP. Install cloudflared with the same token on a new server and your domain automatically points there. Twilio webhooks (domain-based) keep working with no reconfiguration.

> ⚠️ **Keep the token secret.** Don't expose it in logs, screenshots, or repositories. If leaked, delete the tunnel in the Cloudflare dashboard and issue a new one.

> With Cloudflare Tunnel, a separate SSL certificate (Let's Encrypt, etc.) is **not needed** — Cloudflare handles HTTPS automatically.

---

## Usage by Channel

### Phone

Call the bot from an admin number, then speak naturally:

- "What's my schedule today?" -> calendar read aloud
- "Call John for me" -> bot calls John
- "Call John and check how he's doing" -> bot places the call, then reports back
- "Text John for me" -> SMS sent **by name** (number looked up automatically)

> ⏱️ Admin inbound calls count toward the monthly limit (default 300 min, resets on the 21st). For read-only commands, use Telegram/chat to avoid call time and charges.

### Chat (OpenWebUI)

Enable the tool and ask naturally:

- "What's my schedule today?" / "Show me the call log"
- "Text John 'see you at 3pm'" -> SMS by name (auto number lookup)
- "Show my contacts" -> 15 per page · "contacts page 2" / "next page" to navigate
- "Change John's number to 010-9999-8888" -> edit contact
- "Add dentist Dec 25 2pm, remind 1 hour before" -> add event with reminder
- "Move the Dec 25 meeting to 5pm" -> edit event (reminder auto-reschedules)
- "Delete the Dec 25 meeting" -> delete event (reminder auto-cancels)
- "Am I on a call right now?" / "Tell them I'll visit soon" -> **Live Whisper** (instruct the AI mid-call)
- "Show the current voice engine settings" -> check STT/TTS via the **Voice Engine Settings** tool
- "What did I talk about with John before?" -> recall past calls via the **Memory Anchor** tool

### Telegram

Message the bot:

- "What's my schedule today?" -> calendar (add/edit/delete also work)
- Send a file (PDF/image) -> RAG indexing
- **Send a voice message** -> auto speech-to-text, then processed (requires OpenWebUI STT engine)
- On web search -> answer shows **📚 sources + 🔗 links** with source URLs
- `/remind daily 09:00 tell me the weather` -> schedule a reminder
- **🤫 Mid-call live whisper**: `say this: tell them I'll visit soon` / `/calls` -> see [Live Whisper](#live-whisper-mid-call-instructions)

#### 📨 Receiving Telegram Call Reports (optional)

To receive call reports via Telegram (not just SMS):

1. Telegram `@BotFather` → `/newbot` → get a **bot token** (`1234:ABC...`)
2. Send **any message** to your new bot (⚠️ without this, the bot can't message you)
3. Find your chat ID:
   ```bash
   curl -s "https://api.telegram.org/bot<token>/getUpdates" | grep -o '"id":[0-9]*' | head -1
   ```
4. Enter during install, or add later to `.env`:
   ```bash
   cd ~/OpenWebUI
   echo "TELEGRAM_BOT_TOKEN=token" >> .env
   echo "TELEGRAM_CHAT_ID=chat_id" >> .env
   docker compose up -d twilio-bot
   ```

> If reports don't arrive, check `docker compose logs twilio-bot | grep -i telegram` (missing values / chat not found / bad token are logged).

> 💡 To dictate without leaving a voice file, use your phone keyboard's **microphone (dictation)** instead of Telegram's voice-message button — spoken words become text in the input box.

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
- 13 tools registered (including calendar, live whisper, voice engine settings, memory anchor, NAVER location check)
- **Calendar integration** — `/owui-data` mount, shared key, COMPOSE_FILE pinning
- **Security hardening** — requests/urllib3 CVE patches, trust_env
- **Call auth** — admin numbers set, operating-mode detection
- **Realtime voice** — realtime-voice container up, `/twilio-stream` proxy (when realtime mode is on)

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
| Call auth | Registered admin number + 6-digit PIN for sensitive commands (30-min lock after 3 failures) |
| requests | `>=2.34.2` — patches CVE-2024-47081 (netrc credential leak) |
| urllib3 | `>=2.6.3` — patches CVE-2026-21441 (DoS) |
| trust_env | Disables environment credentials + blocks redirects on calendar lookups |
| Containers | no-new-privileges (all services), cap_drop ALL (redis·qdrant·tools·twilio-bot·realtime-voice), non-root, memory limits |
| nginx headers | `server_tokens off`, X-Frame-Options, X-Content-Type-Options (nosniff), Referrer-Policy, HSTS, 25MB upload limit |
| Fail-closed auth | If `API_SECRET` is unset, requests are **blocked** (503) rather than passed through. Applies to admin API and tools-api |
| Secrets | Stored separately via Docker Secrets |
| Twilio | Request signature validation (`validate_twilio_request`), hmac compare |
| Calendar scope | Admin-only even in customer-support mode |
| Phone-number leak prevention | During calls, the AI politely refuses to reveal admin/contact numbers or personal info |
| Caller-ID masking | All outbound/forwarded calls show the Twilio number as caller ID (admin number never exposed) |
| Port binding | Internal services (Qdrant 6333, twilio-bot 5000, realtime-voice 5001, etc.) bind to `127.0.0.1` only → no external access |
| Realtime voice keys | STT/TTS API keys are masked when displayed and stored in `voice_config.json` (inside the volume) |
| Live whisper | Only the registered Telegram admin chat (`TELEGRAM_CHAT_ID`) can issue instructions |

> CVE patch versions are accurate as of writing. Re-check the latest advisories before deploying.

> The Qdrant dashboard (`localhost:6333/dashboard`) binds to `127.0.0.1`, so it is **not reachable from the public internet.** However, anyone who can log into the server can open it without authentication — if multiple users access the server, consider setting a Qdrant API key.

---

## Repository Layout

```
.
├── start-openwebui-hardened-admin-only.sh   # main install (dedicated pure-personal)
├── start-openwebui-customer-support.sh      # main install (customer/personal choice · SERVICE_MODE switch)
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
├── realtime-voice/                   # 🎙️ true realtime voice server (Media Streams)
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

**Q. I picked the wrong use case (customer/personal) during install. Do I have to reinstall?**
A. No. Just change the single `SERVICE_MODE` line in `twilio-bot/ai_config.py` and run `docker compose restart twilio-bot`. It switches freely between `"customer"` and `"personal"`. See [Two Operating Modes](#two-operating-modes).

**Q. What exactly changes when I set `SERVICE_MODE` to personal?**
A. Inbound calls switch to a warm check-in tone, the default greeting becomes a check-in style, the press-0 operator hint (`OPERATOR_HINT_ENABLED`) turns off, and the AI role label becomes "Personal phone assistant." Phone RAG search also auto-switches to unified (phone·web·Telegram reference the same documents), and proactive auto-call (Memory Anchor) becomes available. Everything else (admin commands, cost protection, etc.) works the same in both modes.

**Q. Telegram also had a PIN?**
A. The Telegram bot's PIN is **separate** from the phone bot's (it's for Telegram user auth) and is optional. The phone bot's PIN is checked only when running sensitive commands (call, SMS, save contact, schedule), and can be disabled with `ADMIN_PIN_REQUIRED = False` in `ai_config.py`.

**Q. Will the calendar break again after a reboot?**
A. No. Recurrence prevention pins the mount into the main compose and `.env`. It stays connected no matter how you start it.

**Q. If the caller doesn't press 0, does the admin get called?**
A. In normal mode (BOT_MODE 2), the caller must press 0 or say "representative" to reach a human; otherwise the AI keeps handling the call. To route every call to a human unconditionally, use `BOT_MODE=3` (at install or in `.env`).

**Q. How do I fully disable keypad-0 and voice transfer?**
A. In `ai_config.py`, set `OPERATOR_TRANSFER_ENABLED = False` (keypad 0) and `OPERATOR_VOICE_ENABLED = False` (voice). Even with both off, external callers still get AI consultation.

**Q. What happens if I press `N` at the realtime-mode prompt during install?**
A. It installs with the classic method. The `realtime-voice` container and tools are still installed but sit idle, and calls work the old one-sentence-at-a-time way. You can enable it anytime later via `REALTIME_MODE=true` in `.env`.

**Q. I turned on realtime mode but realtime doesn't work.**
A. The most common cause is `SERVER_DOMAIN` not being a public HTTPS URL (`https://...`). Twilio must connect over `wss://`, so realtime can't work on localhost and it falls back to the classic method. Get a public HTTPS domain (e.g., via Cloudflare Tunnel), then check `docker compose logs -f realtime-voice` for connection/errors.

**Q. How do I change the STT/TTS engine (provider/voice)?**
A. OpenWebUI → Workspace → Tools → "Voice Engine Settings" → ⚙️ Valves, change values and Save — it applies immediately. See [Voice Engine Settings](#voice-engine-settings-stttts-valve-swap).

**Q. Does live whisper only work in realtime mode?**
A. No. It also works in the default (turn-based) method; it just applies faster in true realtime mode.

**Q. Memory Anchor doesn't recall past conversations well.**
A. Recall quality depends on Ollama embeddings. Check `docker compose logs twilio-bot | grep -i embedding` — if you see `dummy vector`, Ollama isn't reachable. See [Ollama Embedding Auto-setup](#ollama-embedding-auto-setup-wsl2) and bind `OLLAMA_HOST=0.0.0.0`.

**Q. How do I make it place check-in calls automatically?**
A. In `twilio-bot/ai_config.py` set `MEMORY_AUTOCALL_ENABLED = True` and `docker compose restart twilio-bot`. The default is the safe "suggest" mode (admin gets a notification only). For full auto, set `MEMORY_AUTOCALL_MODE = "auto"`, but observe cost·frequency for a few days first. → [Memory Anchor](#-memory-anchor-call-recall--proactive-auto-call)

**Q. My call report SMS is cut off / too short.**
A. The latest version raises the SMS report to 250 chars and lifts the internal token cap to prevent truncation. Reinstall or rebuild the bot with `docker compose up -d --build twilio-bot`.

**Q. Only SMS reports arrive, not Telegram.**
A. Check that `.env` has `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`. The most common cause is missing values or **not having sent `/start` to the bot first**. The reason is logged in `docker compose logs twilio-bot | grep -i telegram`. → [Receiving Telegram Call Reports](#-receiving-telegram-call-reports-optional)

**Q. Can it automatically get the other party's phone GPS from a call alone?**
A. No. A plain voice call cannot access the other handset's GPS sensor (a physical limit of all phone systems). This feature converts the location the person **tells you by voice** into a map, and assumes their consent.

**Q. The location report has coordinates but no map image.**
A. It's usually a permissions issue on the map-image folder (`twilio-bot/data/reports`) or a failed NAVER Static Map call. The latest script fixes folder ownership for the bot user at install time. Reinstall or rebuild with `docker compose up -d --build twilio-bot`.

**Q. It can't find station names like "Gangnam Station."**
A. NAVER Geocoding only resolves road/lot addresses, not station/business names (NAVER's Local search API was discontinued). Add a Kakao REST API key to also resolve station/business names. → [Location Check (NAVER + Kakao)](#-location-check-naver--kakao)

**Q. The AI keeps repeating the same location question.**
A. When the person doesn't clearly answer yes/no, it re-asks — but the latest version caps this at **two tries** and then skips the location check. Reinstall or rebuild the bot.

**Q. The person answered but the report says "no answer / voicemail."**
A. Previously, no conversation record meant it was judged as unanswered. The latest version also checks whether the greeting played (evidence the call was answered) and distinguishes "answered but said nothing" from "no answer / voicemail." Reinstall or rebuild the bot.

**Q. The AI feels too impatient (cuts in, moves on too fast).**
A. Increase `SPEECH_TIMEOUT_OUTBOUND` (seconds to wait after speech pauses) and `TIMEOUT_OUTBOUND` (seconds before ending on no response) in `twilio-bot/ai_config.py`. The latest defaults are 5s and 8s so it won't cut in on slower speakers. For an even more relaxed pace, raise them to 6s/10s and run `docker compose restart twilio-bot`.

---

## License / Contributing

Review each script before using this repository. Be sure to check the terms and pricing of your self-hosted environment and external services (Twilio, Telegram, AI providers).

> ⚠️ This package uses **billable external services** such as phone, SMS, and AI APIs. **Always be aware that excessive calling can lead to significant call charges.** Monitor your usage and costs regularly.

> 🔒 **Security responsibility notice**: Any security issues arising during installation or operation are **the sole responsibility of the installer/operator; the developer bears no responsibility** for them. Firewalls, access permissions, secret-key management, server hardening, and the like must be reviewed and managed by the installer. In addition, **all legal responsibility regarding call recording (consent requirements, compliance with applicable laws, etc.) rests entirely with the installer/operator and is unrelated to the developer.**
