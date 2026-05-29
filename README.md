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

| Script | Phase | Description |
|---|---|---|
| `start-openwebui-hardened.sh` | Phase 2 | Core stack: OpenWebUI + Qdrant + Twilio Voice/SMS Bot + OpenAPI Tools |
| `setup-telegram-openwebui-bridge-FINAL.sh` | Phase 3 | Telegram ↔ OpenWebUI bridge (26-point hardened security) |
| `setup-browser-agent-browser-use-v6.sh` | Browser | AI Browser Use Agent + Multi-Agent (Groq + LangGraph) v6.4.0 |
| `verify-install.sh` | Verify | Full installation verification across all phases (v5.0.0) |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    External Access                       │
│          Cloudflare Tunnel (HTTPS, no port open)         │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│                    Nginx (Reverse Proxy)                  │
│         Twilio Webhook  │  Telegram Webhook              │
└────────┬───────────────┼──────────────────────────────┬─┘
         │               │                              │
┌────────▼────────┐ ┌────▼──────────────┐ ┌────────────▼─────────┐
│  OpenWebUI      │ │  Telegram Bridge  │ │  Browser-Use Agent   │
│  :3000          │ │  :8444 / :8445    │ │  :8001               │
├─────────────────┤ └───────────────────┘ └──────────────────────┘
│  Twilio Bot     │
│  (Voice + SMS)  │
├─────────────────┤
│  OpenAPI Tools  │
│  :8000          │
├─────────────────┤
│  Qdrant (RAG)   │
│  :6333          │
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
- Ollama (optional, auto-detected)
- Python 3.8+

---

## 🔐 Security Features

### Phase 2 — Core Stack (21 items)
- Twilio signature verification + API secret authentication
- Port local binding (no unnecessary exposure)
- 6-digit PIN lock with 30-minute auto-release
- Docker Secrets (`/run/secrets/`) for sensitive data
- Structured JSON audit logging
- Cloudflare Tunnel HTTPS (no port forwarding required)
- `.env` permission locked to `600`
- `.gitignore` / `.dockerignore` auto-generated
- TTS injection prevention (URL params → internal storage)

### Phase 3 — Telegram Bridge (26 items)
- AES-256 encrypted Bot Token storage
- Rate limiting (30 req/min per user)
- Telegram User ID whitelist (allowlist only)
- Webhook signature verification (Secret Token)
- Non-root container execution
- Docker network isolation (internal network)
- Sensitive log masking
- Brute-force protection: 5 failures → 15-min IP lock (timing-safe)
- **[NEW]** Replay attack defense (duplicate `update_id` blocking)
- **[NEW]** Prompt injection defense (9 regex patterns)
- **[NEW]** File Magic Bytes validation (extension spoofing prevention)
- **[NEW]** AI response sensitive-data filter (API keys, JWT, phone numbers)
- **[NEW]** Emergency block mode `/emergency`
- **[NEW]** Seccomp profile (syscall whitelist)

### Browser Agent — v6.4.0 (7 patches)
- Seccomp + `cap_drop` + `no-new-privileges`
- API key authentication
- VNC port `127.0.0.1` binding + UFW firewall verification
- 512-bit browser API key (auto-generated)
- CVE patches applied (2026-05)

---

## 🚀 Installation

> **Run scripts in order.** Each phase depends on the previous one.

### Step 0 — Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
chmod +x *.sh
```

### Step 1 — Phase 2: Core Stack

```bash
bash start-openwebui-hardened.sh
```

**What it installs:**
- OpenWebUI (with Qdrant RAG + Ollama/Groq)
- Twilio Voice Bot (AI phone calls with multilingual TTS/STT)
- SMS two-way communication
- OpenAPI Tools server (`:8000`)
- Cloudflare Tunnel (optional, prompted during install)

**Inputs required during setup:**
- Twilio Account SID, Auth Token, Phone Number
- Groq API Key (optional)
- Admin PIN (6+ digits)
- OpenWebUI admin email & password

### Step 2 — Phase 3: Telegram Bridge

```bash
bash setup-telegram-openwebui-bridge-FINAL.sh
```

**Prerequisite:** OpenWebUI must be running at `http://localhost:3000`

**What it installs:**
- Telegram Bot (webhook mode)
- Bridge server (`:8444`) + Admin dashboard (`:8445`, local only)

**Inputs required during setup:**
- Telegram Bot Token (from [@BotFather](https://t.me/BotFather))
- OpenWebUI API Key (Settings → Account → API Keys)
- Allowed Telegram User IDs
- Webhook domain (e.g. `https://your-domain.com`)

### Step 3 — Browser Agent (Optional)

```bash
bash setup-browser-agent-browser-use-v6.sh
```

**What it installs:**
- Browser-Use + Playwright (DOM + A11y hybrid)
- Multi-Agent orchestration (Groq + LangGraph)
- 11 built-in tools: `check_weather`, `check_price`, `check_stock`, etc.
- Self-healing retry logic + CVE patches
- Agent API (`:8001`)

**Inputs required during setup:**
- OpenWebUI URL (e.g. `https://your-domain.com`)
- OpenWebUI admin email & password
- OpenWebUI API Key
- Groq API Key (for Multi-Agent, optional)

### Step 4 — Verify Installation

```bash
bash verify-install.sh
```

Checks 14 sections covering 25 directories, 38 files, security permissions, Docker containers, running services, and all API endpoints.

---

## 🌐 Service Endpoints

| Service | URL | Notes |
|---|---|---|
| OpenWebUI | `http://localhost:3000` | Main AI chat interface |
| OpenAPI Tools Docs | `http://localhost:8000/docs` | Tool API documentation |
| Qdrant Dashboard | `http://localhost:6333/dashboard` | Vector DB dashboard |
| Browser Agent API | `http://localhost:8001/health` | Browser-Use health check |
| Multi-Agent API | `POST http://localhost:8001/browse/multi` | Multi-agent endpoint |
| Telegram Bridge | `http://localhost:8444/health` | Bridge health check |
| Telegram Metrics | `http://localhost:8444/metrics` | Prometheus metrics |
| Admin Dashboard | `http://localhost:8445/dashboard` | **Local only** — SSH tunnel required |

**Access admin dashboard remotely:**
```bash
ssh -L 8445:localhost:8445 user@YOUR_SERVER_IP
# Then open: http://localhost:8445/dashboard
```

---

## 📁 Directory Structure

```
~/OpenWebUI/                    # Phase 2 root
├── .env                        # Environment config (chmod 600)
├── docker-compose.yml
├── docker-compose.override.yml
├── secrets/                    # Docker Secrets (chmod 700)
│   ├── twilio_auth_token
│   ├── api_secret
│   ├── groq_api_key
│   ├── admin_pin
│   ├── webui_secret_key
│   └── entrypoint-secrets.sh
├── tools-api/                  # OpenAPI Tools server
│   ├── main.py
│   ├── Dockerfile
│   └── requirements.txt
├── twilio-bot/                 # Twilio Voice/SMS Bot
│   ├── twilio_bot.py
│   ├── ai_config.py
│   ├── scheduler.py
│   └── data/
├── browser-agent/              # Browser-Use Agent
│   ├── agent_server.py
│   ├── openwebui_tool.py
│   ├── seccomp-browser.json
│   └── secrets/
└── logs/

~/telegram-openwebui-bridge/    # Phase 3 root
├── .env                        # (chmod 600)
├── docker-compose.yml
├── bot/
│   ├── telegram_bot.py
│   └── Dockerfile
└── secrets/                    # (chmod 700)
    ├── telegram_bot_token
    ├── openwebui_api_key
    ├── webhook_secret
    └── tg_admin_pin
```

---

## 🤖 Telegram Bot Commands

| Command | Description |
|---|---|
| `/start` | Start conversation |
| `/model` | Switch AI model in real-time |
| `/tools` | Enable/disable OpenWebUI tools |
| `/clear` | Reset conversation history |
| `/history` | View conversation history |
| `/status` | Check system status (admin) |
| `/users` | List active users (admin) |
| `/block` / `/unblock` | Block/unblock user (admin) |
| `/emergency` | Emergency block mode (admin) |

---

## 🌍 Multilingual Support (Phase 2)

Automatic language detection based on phone number country code:

| Country Code | Language |
|---|---|
| `+82` | 한국어 (Korean) |
| `+1` | English |
| `+81` | 日本語 (Japanese) |
| `+86` | 中文 (Chinese) |

Configure in `twilio-bot/ai_config.py`: `DEFAULT_LANG`, `COUNTRY_LANG_MAP`

---

## 🛠️ Troubleshooting

**Docker permission error:**
```bash
sudo usermod -aG docker $USER
# Log out and back in, then retry
```

**OpenWebUI not responding:**
```bash
cd ~/OpenWebUI && docker compose ps
docker compose logs open-webui --tail=50
```

**Telegram bridge not receiving messages:**
```bash
cd ~/telegram-openwebui-bridge && docker compose logs --tail=50
# Check webhook registration:
curl https://api.telegram.org/bot<TOKEN>/getWebhookInfo
```

**Browser Agent health check fails:**
```bash
curl http://localhost:8001/health
docker logs browser-agent --tail=50
```

**Re-run verification after fixes:**
```bash
bash verify-install.sh
```

---

## 📜 License

MIT License — See [LICENSE](LICENSE) for details.

---
---

# 한국어 가이드

## 📋 개요

이 프로젝트는 [Open WebUI](https://github.com/open-webui/open-webui)를 기반으로 한 **프로덕션 레디, 보안 강화형 AI 에이전트 플랫폼**입니다. 3개의 설치 단계와 1개의 검증 스크립트로 구성됩니다.

| 스크립트 | 단계 | 설명 |
|---|---|---|
| `start-openwebui-hardened.sh` | Phase 2 | 핵심 스택: OpenWebUI + Qdrant + Twilio 전화/SMS 봇 + OpenAPI 도구 |
| `setup-telegram-openwebui-bridge-FINAL.sh` | Phase 3 | 텔레그램 ↔ OpenWebUI 브릿지 (보안 26항목) |
| `setup-browser-agent-browser-use-v6.sh` | Browser | AI 브라우저 에이전트 + 멀티에이전트 (Groq + LangGraph) v6.4.0 |
| `verify-install.sh` | 검증 | 전체 설치 대조 검증 스크립트 (v5.0.0) |

---

## 🏗️ 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│                      외부 접속                           │
│          Cloudflare Tunnel (HTTPS, 포트 개방 불필요)     │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│                  Nginx (리버스 프록시)                    │
│         Twilio 웹훅  │  텔레그램 웹훅                   │
└────────┬─────────────┼─────────────────────────────────┬┘
         │             │                                 │
┌────────▼────────┐ ┌──▼────────────────┐ ┌─────────────▼────────┐
│  OpenWebUI      │ │  텔레그램 브릿지  │ │  브라우저 에이전트   │
│  :3000          │ │  :8444 / :8445    │ │  :8001               │
├─────────────────┤ └───────────────────┘ └──────────────────────┘
│  Twilio 봇      │
│  (전화 + SMS)   │
├─────────────────┤
│  OpenAPI 도구   │
│  :8000          │
├─────────────────┤
│  Qdrant (RAG)   │
│  :6333          │
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
- Ollama (선택, 자동 감지)
- Python 3.8+

---

## 🔐 보안 기능

### Phase 2 — 핵심 스택 (21항목)
- Twilio 서명 검증 + API Secret 인증
- 포트 로컬 바인딩 (불필요한 외부 노출 차단)
- PIN 6자리 잠금 + 30분 자동 해제 (파일 기반 영구 저장)
- Docker Secrets (`/run/secrets/`) 민감정보 암호화 분리
- 구조화된 JSON 감사 로그
- Cloudflare Tunnel HTTPS (포트 포워딩 불필요)
- `.env` 파일 권한 `600` 자동 설정
- `.gitignore` / `.dockerignore` 자동 생성 (유출 방지)
- TTS 인젝션 방지 (URL 파라미터 → 내부 저장소 조회)

### Phase 3 — 텔레그램 브릿지 (26항목)
- Telegram Bot Token AES-256 암호화 저장
- Rate Limiting (분당 30회 / 사용자당)
- Telegram User ID 화이트리스트 (허용 목록만 접근)
- Webhook 서명 검증 (Secret Token)
- 컨테이너 non-root 실행
- Docker 네트워크 격리 (internal network)
- 민감정보 로그 마스킹
- Brute-force 방지: 5회 실패 → 15분 IP 잠금 (timing-safe)
- **[NEW]** Replay Attack 방어 (`update_id` 중복 요청 차단)
- **[NEW]** Prompt Injection 방어 (9개 정규식 패턴 감지·차단)
- **[NEW]** 파일 Magic Bytes 검증 (확장자 위조 방지)
- **[NEW]** AI 응답 민감정보 자동 필터링 (API키·JWT·전화번호)
- **[NEW]** 비상 차단 모드 `/emergency`
- **[NEW]** Seccomp 프로파일 (허용 syscall 화이트리스트)

### 브라우저 에이전트 — v6.4.0 (7개 패치)
- Seccomp + `cap_drop` + `no-new-privileges`
- API 키 인증
- VNC 포트 `127.0.0.1` 바인딩 + UFW 방화벽 검증
- 512비트 Browser API 키 자동 생성
- CVE 보안 패치 적용 (2026-05)

---

## 🚀 설치 방법

> **스크립트는 순서대로 실행하세요.** 각 단계는 이전 단계가 완료되어야 합니다.

### Step 0 — 저장소 클론

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
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
- OpenAPI Tools 서버 (`:8000`)
- Cloudflare Tunnel (선택, 설치 중 안내)

**설치 중 입력 항목:**
- Twilio Account SID, Auth Token, 전화번호
- Groq API Key (선택)
- 관리자 PIN (6자리 이상)
- OpenWebUI 관리자 이메일 & 비밀번호

### Step 2 — Phase 3: 텔레그램 브릿지 설치

```bash
bash setup-telegram-openwebui-bridge-FINAL.sh
```

**사전 조건:** OpenWebUI가 `http://localhost:3000`에서 실행 중이어야 합니다.

**설치 내용:**
- 텔레그램 봇 (webhook 모드)
- 브릿지 서버 (`:8444`) + 관리자 대시보드 (`:8445`, 로컬 전용)

**설치 중 입력 항목:**
- Telegram Bot Token ([@BotFather](https://t.me/BotFather)에서 발급)
- OpenWebUI API Key (설정 → 계정 → API Keys)
- 허용할 텔레그램 User ID 목록
- Webhook 도메인 (예: `https://your-domain.com`)

### Step 3 — 브라우저 에이전트 설치 (선택)

```bash
bash setup-browser-agent-browser-use-v6.sh
```

**설치 내용:**
- Browser-Use + Playwright (DOM + A11y 하이브리드)
- 멀티에이전트 오케스트레이션 (Groq + LangGraph)
- 내장 도구 11개: `check_weather`, `check_price`, `check_stock` 등
- Self-Healing 재시도 로직 + CVE 패치
- 에이전트 API (`:8001`)

**설치 중 입력 항목:**
- OpenWebUI 외부 URL (예: `https://your-domain.com`)
- OpenWebUI 관리자 이메일 & 비밀번호
- OpenWebUI API Key
- Groq API Key (멀티에이전트용, 선택)

### Step 4 — 설치 검증

```bash
bash verify-install.sh
```

25개 디렉토리, 38개 파일, 보안 권한, Docker 컨테이너, 서비스 상태, 모든 API 엔드포인트를 14개 섹션으로 검증합니다.

---

## 🌐 서비스 엔드포인트

| 서비스 | URL | 비고 |
|---|---|---|
| OpenWebUI | `http://localhost:3000` | 메인 AI 채팅 인터페이스 |
| OpenAPI Tools 문서 | `http://localhost:8000/docs` | 도구 API 문서 |
| Qdrant 대시보드 | `http://localhost:6333/dashboard` | 벡터 DB 대시보드 |
| 브라우저 에이전트 API | `http://localhost:8001/health` | 브라우저 에이전트 상태 확인 |
| 멀티에이전트 API | `POST http://localhost:8001/browse/multi` | 멀티에이전트 엔드포인트 |
| 텔레그램 브릿지 | `http://localhost:8444/health` | 브릿지 상태 확인 |
| 텔레그램 메트릭 | `http://localhost:8444/metrics` | Prometheus 메트릭 |
| 관리자 대시보드 | `http://localhost:8445/dashboard` | **로컬 전용** — SSH 터널 필요 |

**원격에서 관리자 대시보드 접속:**
```bash
ssh -L 8445:localhost:8445 user@서버IP
# 브라우저에서 접속: http://localhost:8445/dashboard
```

---

## 📁 디렉토리 구조

```
~/OpenWebUI/                    # Phase 2 루트
├── .env                        # 환경 설정 (chmod 600)
├── docker-compose.yml
├── docker-compose.override.yml
├── secrets/                    # Docker Secrets (chmod 700)
│   ├── twilio_auth_token
│   ├── api_secret
│   ├── groq_api_key
│   ├── admin_pin
│   ├── webui_secret_key
│   └── entrypoint-secrets.sh
├── tools-api/                  # OpenAPI Tools 서버
│   ├── main.py
│   ├── Dockerfile
│   └── requirements.txt
├── twilio-bot/                 # Twilio 전화/SMS 봇
│   ├── twilio_bot.py
│   ├── ai_config.py
│   ├── scheduler.py
│   └── data/
├── browser-agent/              # 브라우저 에이전트
│   ├── agent_server.py
│   ├── openwebui_tool.py
│   ├── seccomp-browser.json
│   └── secrets/
└── logs/

~/telegram-openwebui-bridge/    # Phase 3 루트
├── .env                        # (chmod 600)
├── docker-compose.yml
├── bot/
│   ├── telegram_bot.py
│   └── Dockerfile
└── secrets/                    # (chmod 700)
    ├── telegram_bot_token
    ├── openwebui_api_key
    ├── webhook_secret
    └── tg_admin_pin
```

---

## 🤖 텔레그램 봇 명령어

| 명령어 | 설명 |
|---|---|
| `/start` | 대화 시작 |
| `/model` | AI 모델 실시간 전환 |
| `/tools` | OpenWebUI 도구 활성화/비활성화 |
| `/clear` | 대화 기록 초기화 |
| `/history` | 대화 기록 조회 |
| `/status` | 시스템 상태 확인 (관리자) |
| `/users` | 활성 사용자 목록 (관리자) |
| `/block` / `/unblock` | 사용자 차단/해제 (관리자) |
| `/emergency` | 비상 전체 차단 모드 (관리자) |

---

## 🌍 다국어 지원 (Phase 2)

전화번호 국가코드 기반 자동 언어 감지:

| 국가코드 | 언어 |
|---|---|
| `+82` | 한국어 |
| `+1` | English |
| `+81` | 日本語 |
| `+86` | 中文 |

`twilio-bot/ai_config.py`의 `DEFAULT_LANG`, `COUNTRY_LANG_MAP`에서 수정 가능합니다.

---

## 🛠️ 문제 해결

**Docker 권한 오류:**
```bash
sudo usermod -aG docker $USER
# 로그아웃 후 재접속, 스크립트 재실행
```

**OpenWebUI 응답 없음:**
```bash
cd ~/OpenWebUI && docker compose ps
docker compose logs open-webui --tail=50
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
```

**수정 후 재검증:**
```bash
bash verify-install.sh
```

---

## 📜 라이센스

MIT License — 자세한 내용은 [LICENSE](LICENSE)를 참조하세요.
