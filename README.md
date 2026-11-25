# HackyHappy Labs — OpenWebUI + Twilio AI Phone Assistant + Telegram + Browser Agent + WebRTC + AI Security Monitoring

**English** · [한국어](README_ko.md)

HackyHappy is a Docker-based, self-hosted platform built around OpenWebUI. It integrates a **Twilio AI phone assistant**, calendar operations, Telegram, an AI browser agent, **self-hosted 1-to-1 WebRTC video calling**, and **AI-assisted security monitoring**. The installer deploys the main stack and configures its services, with security hardening and multilingual support (Korean, English, Japanese, and Chinese).

> **In short:** Use the assistant through phone calls, chat, Telegram, or a browser. Sensitive operations are restricted to the administrator. Unknown callers are handled according to the selected mode: personal assistant or customer support.

> **Version note:** The installer documented here targets **OpenWebUI 0.9.6**. If you upgrade to another release, verify compatibility first. UI and API changes in newer versions may affect tool registration or calendar integration. See the [official OpenWebUI repository](https://github.com/open-webui/open-webui).

---

## Table of Contents

- [Features](#features)
- [Operating Modes](#operating-modes)
- [Requirements](#requirements)
- [Getting a GroqCloud API Key](#getting-a-groqcloud-api-key)
- [Installation](#installation)
- [Calendar Configuration](#calendar-configuration)
- [Call Authentication](#call-authentication)
- [Call Controls and Human Handoff](#call-controls-and-human-handoff)
- [Real-Time Media Streams](#real-time-media-streams)
- [Live Whisper Instructions](#live-whisper-instructions)
- [Speech Engine Configuration](#speech-engine-configuration)
- [Call Memory and Proactive Calls](#call-memory-and-proactive-calls)
- [VoiceMem Dual-Brain Memory](#voicemem-dual-brain-memory)
- [Location Lookup](#location-lookup)
- [Consent-Based GPS Sharing](#consent-based-gps-sharing)
- [1-to-1 WebRTC Video Calls](#1-to-1-webrtc-video-calls)
- [AI Security Monitoring](#ai-security-monitoring)
- [Ollama Embedding Setup for WSL2](#ollama-embedding-setup-for-wsl2)
- [Monthly Call-Time Limits](#monthly-call-time-limits)
- [Twilio Automatic Configuration](#twilio-automatic-configuration)
- [Cloudflare Tunnel](#cloudflare-tunnel)
- [Using Each Channel](#using-each-channel)
- [Installation Verification](#installation-verification)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)
- [Project Files](#project-files)
- [FAQ](#faq)
- [License and Contributions](#license-and-contributions)

---

## Features

| Feature | Description |
|---|---|
| AI phone assistant | Place and receive calls through Twilio, hold voice conversations, and send SMS messages. |
| Real-time call handling | Twilio Media Streams supports interruption (barge-in) while the assistant is speaking. Deepgram STT and ElevenLabs TTS can be configured. |
| Live whisper | An administrator can send instructions through Telegram or the app while the AI is talking to a caller. The assistant incorporates the instruction into a subsequent response. |
| Call memory | Call information can be stored by phone number and relevant memories can be retrieved in later calls. Optional proactive check-in calls are available in personal mode. |
| VoiceMem | Optional memory subsystem with local E5-family embeddings and OpenAI-based analysis. Factual memory and a separate JSON persona/profile are maintained independently. |
| Location lookup | With the recipient's consent, the assistant can ask for a verbally provided location and report a map to Telegram. NAVER and Kakao services can be used for geocoding/search; Google hybrid satellite imagery is optional. It does not secretly collect phone GPS. |
| GPS sharing | Sends a location-sharing link by call and SMS. The recipient must open the link and explicitly grant browser location permission before coordinates are shared with the administrator. |
| 1-to-1 video calling | Self-hosted WebRTC audio/video rooms, invitation SMS and AI call, and an administrator participation link. No external Jitsi meeting service or third-party meeting SDK is used. |
| AI security monitoring | Checks Docker service health, SSH authentication logs, Nginx audit logs, and CrowdSec information. Events are stored in SQLite and relevant alerts are sent to Telegram. |
| Smart contacts | Look up contacts by name, place calls, send SMS, edit/delete contacts, and browse contacts in pages of 15. |
| Calendar | View, create, update, and delete events. Phone/SMS reminders can be rescheduled when event times change. |
| Barge-in | Interrupt the assistant during a call and let it focus on the new input. |
| Human handoff | A caller can request an administrator/human transfer using keypad `0` or configured voice phrases. |
| Monthly call-time limit | Optional monthly inbound-call usage limit, with warning and blocking behavior. The documented default is 300 minutes; the threshold warning is sent at 90%. |
| Telegram bot | Chat with OpenWebUI through Telegram, index files, schedule tasks, process voice messages (STT), and show search-source links. |
| Browser agent | Navigate websites, capture screenshots, and extract information. |
| RAG | Answer questions using uploaded documents. |
| Hardening | Container hardening, Docker Secrets, security patches, caller authentication, and safeguards against phone-number disclosure. |
| Twilio setup | The installer can configure Voice, SMS, and Status Callback URLs through the Twilio API. |

---

## Operating Modes

Choose one of two modes according to the deployment purpose.

| Mode | Intended use | Unknown callers | Calendar and privileged commands |
|---|---|---|---|
| `personal` | Personal assistant and check-in calls | Responds in a friendly personal-assistant style; no default human-operator prompt. | Administrator only. |
| `customer` | Customer support | Responds in a general customer-support style; keypad `0` operator guidance is enabled by default. | Administrator only; customers cannot access it. |

In both modes, sensitive functions such as calendar access, SMS, and administrative commands are restricted to the administrator configured during installation. A customer cannot access the administrator's calendar by asking about today's schedule.

### Select or change the mode

The main installer asks for the mode at startup:

```text
Which mode do you want to install?
   1) Customer support
   2) Personal AI assistant
Select (1/2) [default: 1]:
```

- `1` or Enter: customer-support mode.
- `2`: personal mode.

The selected value is written to `SERVICE_MODE` in `twilio-bot/ai_config.py`. You can change it later without reinstalling:

```bash
cd ~/HackyHappy-OpenWebUI

grep -n '^SERVICE_MODE' twilio-bot/ai_config.py
nano twilio-bot/ai_config.py
# Set one of the following:
# SERVICE_MODE = "customer"
# SERVICE_MODE = "personal"

docker compose restart twilio-bot
docker compose ps twilio-bot
```

The mode controls the default greeting, response style, operator-handoff hint, AI role label, phone RAG search behavior, and availability of optional proactive calls. Individual settings in `ai_config.py` can override defaults. Personal mode automatically uses the integrated phone/web/Telegram document search behavior; customer mode follows the `.env` search-mode setting.

---

## Requirements

- Ubuntu 22.04 or later (including WSL2), or another Linux system capable of running Docker.
- Docker Engine and Docker Compose.
- OpenWebUI **0.9.6 baseline** as specified by the installer image.
- A Twilio account, phone number, Account SID, and Auth Token for calling features.
- Optional Telegram Bot Token for Telegram integration and notifications.
- Optional model-provider API keys (Groq, OpenAI, Claude, or Gemini), depending on the selected AI mode.
- Optional VoiceMem: a valid **OpenAI API key** is required. VoiceMem uses a local E5-family embedding model and the OpenAI API for call-memory analysis. Enabling it raises the `twilio-bot` memory limit to 8 GB. If disabled or unavailable, the existing Qdrant memory system is used as a fallback.

## Getting a GroqCloud API Key

A GroqCloud API key is required if you select **AI mode `2 = Groq` (direct Groq connection)** during HackyHappy installation. Create the key in the official GroqCloud console.

1. Open the [GroqCloud Console](https://console.groq.com/) and create an account or sign in.
2. Go to [API Keys](https://console.groq.com/keys).
3. Select **Create API Key**, enter a label such as `HackyHappy-VPS`, and create the key. Key-creation permissions may depend on your organization or project role.
4. Copy the secret immediately and store it in a password manager or another secure location. The full key may not be shown again. Groq keys commonly begin with `gsk_`.
5. Run the HackyHappy main installer. When prompted for the **Groq API Key**, paste the key. If you skip this prompt, direct Groq mode is disabled; if mode `2` was selected without a key, the installer automatically falls back to OpenWebUI mode.

**Key security**

- Treat the Groq API key like a password. Never commit it to a README, GitHub repository, screenshot, public chat, or source file.
- The installer stores the supplied key as the Docker Secret `secrets/groq_api_key` and uses it for Groq API requests. If you suspect exposure, revoke the key in [GroqCloud API Keys](https://console.groq.com/keys) and create a replacement.
- Check [Usage](https://console.groq.com/usage), [Rate Limits](https://console.groq.com/docs/rate-limits), and [Models](https://console.groq.com/docs/models) for current usage, limits, and model availability. Pricing and limits may vary by account and over time.
- **VoiceMem does not use the Groq API key.** VoiceMem requires a separate valid OpenAI API key.

---

## Installation

### Step 1 — Main installer (OpenWebUI, phone assistant, and calendar)

The main installer supports both personal and customer-support modes. Review the script before running it.

```bash
wget https://YOUR-HOST/HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh
less HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh
chmod +x HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh
./HackyHappy-FULL-INSTALL-DUAL-REPORT-PERSONA-PRESERVE-AICONFIG-20261125-FINAL-VOICE-APPROVAL-RATE-LIMITS-ALEMBIC-ANCESTOR-FIX.sh
```

The installer prompts for configuration such as:

| Prompt | Example | Purpose |
|---|---|---|
| Service mode | `1` / `2` | `1` = customer support; `2` = personal. |
| Administrator phone number(s) | `+821012345678` | Number(s) authorized to use privileged phone commands. Multiple numbers may be comma-separated. |
| Twilio credentials | SID / Token / phone number | Phone and SMS functions. |
| Server domain | `https://yourdomain.com` | Public webhook URL for Twilio. |
| Administrator email/password | — | OpenWebUI login. |
| AI mode | `2` | `1` = OpenWebUI, `2` = Groq, `3` = forwarding (as offered by the installer). |
| Contacts | `Alex,+821011112222` | People the bot may call; this is distinct from administrator authorization. |
| RAG search mode | `1` / `2` | Integrated or separated search. A default is recommended based on the selected service mode. |
| Real-time mode | `y` / `N` | Enable Deepgram/ElevenLabs real-time calling; optional and can be enabled later. |
| Telegram reports | `y` / `N` | Configure bot token and chat ID to receive call reports in Telegram as well as SMS. |
| NAVER location lookup | `y` / `N` | Configure NAVER Maps credentials; optional Kakao and Google Maps keys can also be supplied. |

The installer asks you to set a six-digit administrator PIN. You can enter one or press Enter to generate one automatically; record the generated PIN. It is requested for sensitive commands such as saving contacts, placing calls, sending SMS, and scheduling. It is not required for ordinary conversation or read-only questions such as today's schedule. Authentication remains valid for the rest of that call after successful verification.

Real-time calling, Telegram reports, and location lookup are optional. Skipping them does not enable those features. After installation, the main stack starts and **16 tools are registered**. Tool 14 is GPS location sharing, tool 15 is the 1-to-1 video-call invitation, and tool 16 is the HackyHappy AI Security Agent.

### Step 2 — Browser agent (optional)

The browser agent is installed using its separate companion installer, if supplied with your deployment package:

```bash
chmod +x setup-browser-agent-calendar-naver-search-api-only-hackyhappy-paths.sh
./setup-browser-agent-calendar-naver-search-api-only-hackyhappy-paths.sh
```

This companion installer is separate from the main installer; it is not generated by the main script.

### Step 3 — Telegram bridge (optional)

The Telegram bridge is also a separate companion component. Follow the instructions packaged with that component. It is not created by the main installer described above.

---

## Calendar Configuration

Calendar integration requires the relevant OpenWebUI API key and the secret used by the tools service. The exact valve names and values should match the installed tool definitions.

### Reminder delivery through calls and SMS

The calendar reminder tool uses `TWILIO_BOT_SECRET` to authenticate requests to the Twilio bot. The server-side `.env` contains the API secret; use the matching value when configuring the tool valve. Do not paste secrets into public documentation or share them in screenshots.

### API key locations

- OpenWebUI API key: inspect the generated `.env` for `OPENWEBUI_API_KEY`.
- Tools API secret: inspect the generated `.env` for `API_SECRET`.
- Browser-agent key: inspect the generated configuration for `BROWSER_AGENT_API_KEY`.

Example commands (these print secret values; do not share their output):

```bash
cd ~/HackyHappy-OpenWebUI
grep -n '^OPENWEBUI_API_KEY=' .env
grep -n '^API_SECRET=' .env
grep -Rni 'BROWSER_AGENT_API_KEY' .env
```

---

## Call Authentication

The phone assistant distinguishes between **administrator numbers** and ordinary contacts. Administrator numbers are authorized to use privileged commands. A contact is simply a person the bot may call or message; adding someone as a contact does not grant administrative access.

Sensitive actions require the six-digit administrator PIN after the caller has been authenticated as an administrator. Ordinary conversation and permitted read-only queries do not require the PIN. After successful PIN verification, the authorization applies for the remainder of that call.

To add or change administrator numbers, update the administrator-number configuration created by the installer and restart the relevant service. Do not use the ordinary contact list as an administrator allowlist.

---

## Call Controls and Human Handoff

### Barge-in

When enabled, the caller can speak while the AI is speaking. The current response is interrupted and the assistant processes the new input.

### Human/operator handoff

The caller can press keypad `0` or use configured voice phrases to request a direct transfer to the administrator/operator. The operator hint can be disabled for fully automated personal use. Review the corresponding settings in `twilio-bot/ai_config.py` before changing them.

---

## Real-Time Media Streams

Real-time mode uses Twilio Media Streams to stream call audio to the application. The documented configuration uses Deepgram for speech recognition (STT) and ElevenLabs for speech synthesis (TTS).

To enable it, set `REALTIME_MODE=true` in `.env` and provide valid `DEEPGRAM_API_KEY` and `ELEVENLABS_API_KEY` values, or configure the supported speech-engine valves. These are third-party services and may incur charges. Confirm account limits and test with a controlled call before production use.

Real-time mode is optional. Leaving it disabled preserves the standard call flow. If speech timing sounds unnatural, review the provider settings, network latency, and the application's audio timing parameters rather than changing unrelated services.

---

## Live Whisper Instructions

An administrator can send short instructions while the AI is speaking with a caller. Depending on the configured integration, instructions can be sent through Telegram or the OpenWebUI chat/app. The assistant uses the instruction as context for a subsequent utterance; it does not replace caller consent or administrator authorization requirements.

---

## Speech Engine Configuration

Speech-to-text (STT) and text-to-speech (TTS) providers can be selected through the supported tool valves and environment variables. Configure only providers for which you have valid credentials. Keep API keys in secrets or environment configuration, not in source code. Provider selection may affect latency, language support, and usage charges.

---

## Call Memory and Proactive Calls

Call memories are stored and associated with the relevant phone number. During a later call, the system can retrieve relevant prior context to make the conversation more coherent. The optional proactive-call feature can suggest or initiate check-in calls when its configured conditions are met.

Proactive calls are optional and should remain disabled unless the administrator deliberately enables them. Review `MEMORY_AUTOCALL_ENABLED` and the related settings in `twilio-bot/ai_config.py` before use.

---

## VoiceMem Dual-Brain Memory

VoiceMem is an optional memory implementation with two complementary parts:

- **Left brain — factual/structured memory:** who, when, and what. The implementation uses a local E5-family embedding model together with OpenAI API analysis.
- **Right brain — persona/context profile:** conversational tone, emotional context, and recurring preferences are accumulated separately in per-person JSON profiles.

In the current installer, VoiceMem is **not** an Ollama-versus-OpenAI selectable engine. Local E5-family embeddings are used for the embedding component, while OpenAI (default model `gpt-4o-mini`) is used for analysis. A valid OpenAI API key is required; a Groq key is not a substitute.

The relevant `.env` settings include `VOICEMEM_ENABLED`, `VOICEMEM_OPENAI_KEY`, and `VOICEMEM_MODEL`. When enabled, the installer raises the `twilio-bot` memory limit to 8 GB. When disabled or if VoiceMem fails, the existing Qdrant memory system is used as a fallback.

To change the setting, edit `.env` and recreate the Twilio bot container so the new environment is applied:

```bash
cd ~/HackyHappy-OpenWebUI
# Set VOICEMEM_ENABLED=false or true in .env
# A valid OpenAI API key is required when enabling VoiceMem.
docker compose up -d --force-recreate twilio-bot
```

---

## Location Lookup

Location lookup is based on a location the recipient verbally provides after being asked. The assistant can resolve the location and send a map report through Telegram. It does **not** silently read the recipient's phone GPS.

The implementation can combine:

- NAVER geocoding for road-name and parcel addresses.
- Kakao Local search for station names, businesses, and building names.
- Optional Google hybrid/satellite map imagery. If a Google key is unavailable, the configured NAVER map fallback may be used.

Obtain the relevant API credentials from the providers' official developer consoles. During installation, enable NAVER location lookup and enter the NAVER Maps Client ID and Secret. Kakao REST API and Google Maps API keys are optional additions. If configuring later, update the corresponding `.env` variables and restart the affected service.

Location reporting is delivered through Telegram with a map image, so configure Telegram reporting if you intend to use this feature. Test with a consenting recipient and verify the provider credentials and map output.

---

## Consent-Based GPS Sharing

The GPS-sharing tool sends the recipient a location-sharing link by SMS and an AI phone call. The recipient must open the link and explicitly press the allow/consent control in the browser. Only after browser location permission is granted can the location be sent to the administrator's Telegram and SMS destinations.

The installer implements several safeguards, including a random token, one-time use, an expiry window, HTTPS, and binding the request to the intended recipient number. The configured link validity is 30 minutes (`GPS_SHARE_TTL_SEC=1800`).

Use this feature only with the recipient's knowledge and consent. Do not attempt to bypass browser permission prompts or collect location secretly. Treat coordinates as sensitive personal information and restrict access to the reports.

GPS sharing is built into the main installer as tool 14; it is not a separate `patch-gps-14th-tool.sh` workflow. The installer creates the API secret file at `secrets/api_secret`. Avoid rerunning the entire installer on a live server solely to modify this feature; make a reviewed, targeted change instead.

---

## 1-to-1 WebRTC Video Calls

The video-call invitation tool creates a private two-person WebRTC session. The invite can be sent to a contact by SMS and an AI 안내 call; the administrator's OpenWebUI chat receives a participation link that opens in a new browser tab.

### Expiration and call lifecycle

- The invitation expires if both participants have not joined within **10 minutes**.
- Once both participants have joined, the call has no fixed duration limit.
- When either participant leaves, the session ends.
- A short heartbeat/seat timeout is used to clean up abandoned participant sessions.

### WebRTC and TURN relay

WebRTC handles real-time browser audio/video. Coturn provides TURN relay support for networks where a direct peer-to-peer connection cannot be established. The documented ports are UDP/TCP `3478` and media relay UDP `49160-49200`. Allow the required ports in both the VPS firewall and the cloud-provider firewall. If public-IP discovery fails or the server is behind NAT, check `VIDEO_TURN_PUBLIC_IP` and Coturn's `external-ip` configuration.

### Post-install checks

```bash
cd ~/HackyHappy-OpenWebUI

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' \
  | grep -E 'twilio-bot|openapi-tools|coturn'

docker logs --since 10m hackyhappy-coturn

docker logs --since 10m twilio-bot 2>&1 \
  | grep -Ei 'video-call|video-room|invite'
```

In OpenWebUI, open **Workspace → Tools → 1-to-1 Video Call Invitation → Valves** and confirm `enabled` is on. Invitations require Twilio SID, Auth Token, sender number, and a public HTTPS `SERVER_DOMAIN`.

The 10-minute limit applies to joining the invitation, not to an established call. SMS delivery and the AI invitation call are separate actions; verify the actual browser audio/video connection on both sides.

---

## AI Security Monitoring

The installer configures the **HackyHappy AI Security Agent** tool and a separate least-privilege `security-monitor` container. The purpose is to observe service health and security logs, record events, and send alerts. It is not designed to run arbitrary attack modules or collect passwords, sessions, or authentication tokens.

### Monitoring scope

| Area | Behavior in the installer |
|---|---|
| Docker service health | Periodically checks health endpoints for `openapi-tools`, `twilio-bot`, `open-webui`, and `qdrant`. |
| SSH authentication | Reads `/var/log/auth.log` and SSH logs exported from the systemd journal. |
| Repeated SSH failures | Five or more failures from the same IP within 300 seconds create a HIGH-event candidate. |
| Nginx access logs | Detects suspicious URI patterns in JSON audit logs. |
| Repeated Nginx errors | 25 or more responses with status 401, 403, 404, or 444 from the same IP within 120 seconds create a MEDIUM-event candidate. |
| CrowdSec | Configures SSH/Nginx collections and reads CrowdSec decisions and recent alerts. |
| Event storage | Stores events in `tools-api/data/security_events.sqlite3` (mounted in the container as `/app/data/security_events.sqlite3`). |

### Alerts and phone-call policy

HIGH and CRITICAL security alerts are sent to Telegram. An automatic Twilio call to the administrator is reserved for a verified CRITICAL service outage. A manual critical phone alert requires the exact approval phrase `긴급 전화 승인`. IP unban requests are queued for approval; the tool does not silently unban an address.

### Security tool capabilities

The OpenWebUI security tool can report monitoring status and recent events, inspect relevant security information, and submit supported administrative requests for approval. The available operations are constrained by the installed tool implementation and its authorization checks.

### Post-install checks

```bash
cd ~/HackyHappy-OpenWebUI

# Security monitor container
docker compose ps security-monitor

# Recent security-monitor logs
docker logs --since 30m security-monitor

# CrowdSec status and collections
docker compose ps crowdsec

docker exec crowdsec cscli collections list

# Current decisions and recent alerts
docker exec crowdsec cscli decisions list
docker exec crowdsec cscli alerts list

# SSH and Nginx audit logs
sudo tail -n 100 /var/log/auth.log
sudo tail -n 100 /var/log/nginx/access.log

# SSH journal export timer
systemctl status hackyhappy-ssh-journal-export.timer
```

### CrowdSec firewall bouncer requires explicit opt-in

The CrowdSec firewall bouncer is not enabled silently. During installation, enabling it requires entering the exact phrase `ENABLE CROWDSEC BOUNCER`. Review the impact on firewall policy before enabling it, and make sure you have an alternate way to access the server.

Security monitoring is not a substitute for system updates, backups, least-privilege access, firewall review, or incident response. Thresholds can produce false positives and should be tuned to the deployment environment.

---

## Ollama Embedding Setup for WSL2

If the deployment uses Ollama on the WSL2 host for an embedding service, verify that the Docker containers can reach the host Ollama endpoint and that the selected embedding model is installed. The exact endpoint and model must match the `.env` values generated for the deployment. Do not assume that a host-only `localhost` address is reachable from inside a container; use the host gateway address configured for your Docker environment.

---

## Monthly Call-Time Limits

The monthly call-time limiter is intended to protect against unexpected Twilio usage. The documented default monthly inbound-call allowance is 300 minutes. A Telegram warning is sent at 90% usage; calls can be blocked after the configured limit is exceeded. The usage counter is reset on the configured monthly reset date (documented default: the 21st). Confirm the actual `.env` and application settings before relying on these limits for billing control.

---

## Twilio Automatic Configuration

During installation, the script can use the Twilio API to configure the Voice URL, SMS URL, and Status Callback URL. Confirm that the Twilio number is assigned to the intended account and that the public HTTPS webhook URLs are reachable from Twilio.

### Voice and SMS status callbacks

The installer routes `/report-voice-status` and `/report-sms-status` through Nginx to the Twilio Bot on port `5000`. The Flask handler validates Twilio request signatures. An unsigned `curl` request returning HTTP 403 is expected and does not by itself indicate a broken callback. HTTP 204 means the callback was accepted/handled; it does **not** prove that the recipient answered a call or read an SMS.

When troubleshooting Twilio warning 15003 or callback failures, check the Twilio request inspector, webhook URL, HTTPS certificate, Nginx routing, application logs, and signature-validation configuration. Do not disable signature validation as a workaround.

---

## Cloudflare Tunnel

Cloudflare Tunnel is an optional way to expose the service through HTTPS without directly opening an inbound port on the server. Create a tunnel in the Cloudflare dashboard, configure the public hostname and origin service, then install and run `cloudflared` using the token supplied by Cloudflare.

Example service checks:

```bash
sudo systemctl status cloudflared
cloudflared tunnel list
```

Verify the public HTTPS hostname from an external network and confirm that it routes to the intended local service. Do not publish tunnel tokens.

---

## Using Each Channel

### Phone

Call the configured Twilio number or initiate a call through the authorized OpenWebUI phone tool. Administrator authentication and the PIN rules apply to privileged commands. Test calls can incur Twilio charges.

### OpenWebUI chat

Use the OpenWebUI web interface to chat with the selected model and invoke registered tools. Tool access depends on the user's OpenWebUI permissions and the tool's own authorization checks.

### Telegram

Connect the Telegram bot using the token and chat settings configured during installation. Depending on the enabled bridge features, Telegram can be used for chat, voice-message transcription, reports, and administrator whisper instructions. Telegram bridge setup is a separate companion component where noted above.

### Telegram call reports

If Telegram reporting was enabled during installation, configure the correct bot token and administrator chat ID. If skipped, SMS reporting can still work. Do not expose the bot token or chat credentials.

### Browser agent

The browser agent is an optional companion service. Use its configured API endpoint and key. Browser automation can interact with external websites; review actions and permissions carefully, especially for authenticated or financial sites.

---

## Installation Verification

After installation, check the Compose services and their health status:

```bash
cd ~/HackyHappy-OpenWebUI
docker compose ps
```

Review logs for services that are unhealthy or restarting:

```bash
docker compose logs --tail=200 open-webui twilio-bot openapi-tools
```

Confirm that the expected tools appear in OpenWebUI and that the relevant valves are enabled. Test in stages: first OpenWebUI health, then tool registration, then a controlled SMS/call, then optional Telegram, location, video, and security-monitor functions. Use test recipients who have agreed to receive calls or messages.

---

## Troubleshooting

### The phone assistant reports an incorrect or fabricated calendar event

Check that the calendar service is reachable, the expected volume/configuration is mounted, and the shared API secret is present. Review the calendar tool logs and confirm that the correct calendar account is connected. Do not treat a generated answer as proof that an event exists; verify against the calendar source.

### Calendar requests time out in chat

Check the OpenWebUI service configuration and worker count. The documented deployment may use `UVICORN_WORKERS=4`; verify the actual `docker-compose.yml` before changing it. Restart only the affected service after a reviewed configuration change.

### Calendar lookup fails

Check API credentials, tool valves, network reachability, and service logs. Ensure that the API key in the valve matches the key generated for the current installation. Avoid posting secret values in support requests.

### Twilio callback returns 403

An unsigned request may correctly return 403 because Twilio signature validation is enabled. Test using a real Twilio callback or a properly signed request. Do not turn off signature validation to make a manual `curl` test pass.

### Video invitation does not connect

Check the 10-minute invitation window, public HTTPS domain, Twilio delivery, Coturn health, and firewall access to UDP/TCP 3478 and UDP 49160–49200. Confirm that both participants joined and that their browsers granted camera/microphone permissions.

### Security alerts are missing

Check the `security-monitor` container, Telegram bot/chat configuration, event database, SSH journal export timer, Nginx JSON audit log, and CrowdSec service. Confirm the event thresholds and severity routing in the installed configuration.

---

## Security Notes

- Never commit `.env`, Docker Secret files, API keys, Twilio credentials, Telegram tokens, administrator PINs, or TURN secrets to Git.
- Restrict access to the VPS, OpenWebUI administrator account, and Telegram administrator chat.
- Use HTTPS for public endpoints and keep Twilio signature validation enabled.
- Use GPS and verbal location reporting only with clear recipient consent.
- Test phone and SMS functions with consenting test recipients; provider charges may apply.
- Keep Ubuntu, Docker, OpenWebUI, and companion services updated, but verify compatibility before upgrading pinned versions.
- Back up persistent data and secrets securely. A backup containing credentials must be protected like the live server.
- AI security monitoring can generate false positives and does not replace a complete security program.

---

## Project Files

The main installer creates or configures the core project structure. Exact contents may vary with selected options.

```text
~/HackyHappy-OpenWebUI/
├── docker-compose.yml
├── .env
├── calendar-up.sh
├── docker-compose.calendar.yml
├── security-monitor/
├── coturn/
├── twilio-bot/
├── tools-api/
├── realtime-voice/
└── secrets/
    ├── api_secret
    ├── groq_api_key        # when Groq direct mode is configured
    └── ...                 # other generated secrets
```

The security event database is stored at `tools-api/data/security_events.sqlite3`. The GPS API secret is generated at `secrets/api_secret`. The browser-agent installer, Telegram bridge installer, documentation, and verification utilities are companion components when supplied separately; they are not all generated by the main installer.

---

## FAQ

**Can I use Groq for VoiceMem?**  
No. The current VoiceMem implementation requires a valid OpenAI API key. The Groq key is used for the direct Groq AI mode, not as a replacement for the VoiceMem OpenAI key.

**Can I enable VoiceMem without changing the existing Qdrant memory system?**  
VoiceMem is optional. When disabled or unavailable, the existing Qdrant memory system is used as a fallback.

**Does GPS sharing track someone automatically?**  
No. The recipient must open the invitation link and explicitly grant browser location permission.

**Does the video call expire after 10 minutes?**  
The invitation expires if both participants do not join within 10 minutes. Once the call is connected, there is no fixed duration limit; the session ends when a participant leaves.

**Does a 204 Twilio callback mean the recipient answered?**  
No. It means the callback was accepted/handled. It does not confirm that a call was answered or an SMS was read.

**Does the security agent automatically block every suspicious IP?**  
No. IP unban requests require approval. CrowdSec firewall-bouncer activation is a separate explicit opt-in during installation.

**Can I rerun the full installer to update one feature on a live server?**  
Do not rerun the full installer solely to patch one feature on a production server. Review the relevant source and make a targeted, backed-up change.

---

## License and Contributions

Check the repository's `LICENSE` file for the applicable license terms. Contributions, bug reports, and feature requests should include reproducible steps and sanitized logs. Never include API keys, personal phone numbers, access tokens, GPS coordinates, or other secrets in public issues or pull requests.
