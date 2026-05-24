# 🤖 OpenWebUI AI 에이전트 — 설치 가이드

> **OpenWebUI + RAG + Twilio 전화봇 + Telegram 브릿지 + Browser Agent (Multi-Agent)**
>
> Docker 기반 올인원 AI 에이전트 플랫폼. 웹 채팅, 전화/SMS, Telegram, 브라우저 자동화를 하나로 통합합니다.

---

## 📋 목차

1. [시스템 요구사항](#-시스템-요구사항)
2. [아키텍처 개요](#-아키텍처-개요)
3. [Phase 2 — OpenWebUI + RAG + Twilio 전화봇](#-phase-2--openwebui--rag--twilio-전화봇)
4. [Phase 3 — Telegram 브릿지](#-phase-3--telegram-브릿지)
5. [Browser Agent — AI 브라우저 자동화](#-browser-agent--ai-브라우저-자동화)
6. [설치 검증](#-설치-검증)
7. [디렉토리 구조](#-디렉토리-구조)
8. [서비스 포트 맵](#-서비스-포트-맵)
9. [주요 명령어](#-주요-명령어)
10. [보안 체크리스트](#-보안-체크리스트)
11. [문제 해결](#-문제-해결)
12. [유지보수](#-유지보수)
13. [라이센스](#-라이센스)

---

## 💻 시스템 요구사항

| 항목 | 최소 | 권장 |
|------|------|------|
| OS | Ubuntu 20.04+ / Debian 11+ | Ubuntu 22.04 LTS |
| CPU | 2코어 | 4코어 이상 |
| RAM | 4GB | 8GB 이상 (16GB 권장) |
| 디스크 | 20GB | 50GB 이상 |
| Docker | 자동 설치됨 | 최신 버전 |
| 네트워크 | 인터넷 연결 필수 | 고정 IP 또는 도메인 (Twilio/Telegram 사용 시) |

스크립트가 시스템 사양을 자동으로 감지하여 메모리 할당을 최적화합니다.

| 감지 등급 | CPU | RAM | 설명 |
|-----------|-----|-----|------|
| 🚀 고성능 | 6+ 코어 | 16GB+ | 모든 기능 최대 성능 |
| 💪 중상급 | 4+ 코어 | 8GB+ | 안정적 운영 |
| 📊 중급 | 2+ 코어 | 4GB+ | 기본 기능 운영 |
| 🐢 저사양 | 그 외 | 그 외 | 제한적 운영 |

---

## 🏗 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                        사용자 접점                               │
│   🌐 웹 브라우저    📞 전화/SMS     💬 Telegram      🖥 VNC     │
│       :3000         (Twilio)       (Bot API)      :5901      │
└──────┬──────────────┬──────────────┬──────────────┬──────────────┘
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
│  Qdrant     │  tools-api   │  Ollama (선택)                   │
│  :6333      │  :8000/:8010 │  :11434                         │
│  벡터 DB    │  RAG/Tool API│  로컬 LLM                       │
└─────────────┴──────────────┴──────────────────────────────────┘
```

---

## 🚀 Phase 2 — OpenWebUI + RAG + Twilio 전화봇

핵심 플랫폼을 설치합니다. OpenWebUI, Qdrant 벡터 DB, OpenAPI Tools, Twilio 전화봇이 포함됩니다.

### 사전 준비 (선택)

- **Groq API Key** — [console.groq.com](https://console.groq.com)에서 발급 (무료)
- **Twilio 계정** — [twilio.com](https://www.twilio.com)에서 가입 후 Account SID, Auth Token, 전화번호 확보
- **Ollama** — 로컬 LLM 실행 시 필요 (스크립트가 자동 설치 제안)

### 설치 실행

```bash
# 스크립트 다운로드 후 실행
bash start-openwebui-hardened.sh
```

### 설치 과정에서 입력하는 정보

스크립트가 대화형으로 아래 정보를 물어봅니다. 모두 **선택사항**이며 Enter를 누르면 건너뛸 수 있습니다.

| 순서 | 입력 항목 | 설명 | 기본값 |
|------|-----------|------|--------|
| 1 | Ollama 설치 여부 | 로컬 LLM 실행용 | 사양에 따라 Y/N |
| 2 | Groq API Key | 클라우드 LLM 연동 | 건너뜀 |
| 3 | Twilio Account SID | 전화/SMS 기능 | 건너뜀 |
| 4 | Twilio Auth Token | 전화/SMS 인증 | 건너뜀 |
| 5 | Twilio 전화번호 | 발신 번호 | 건너뜀 |
| 6 | 관리자 전화번호 | 보고 수신용 | 건너뜀 |
| 7 | OpenWebUI 관리자 이메일 | 로그인 계정 | admin@example.com |
| 8 | OpenWebUI 관리자 비밀번호 | 로그인 비밀번호 | 자동 생성 |
| 9 | 앱 이름 | WebUI 표시 이름 | AI 비서 |
| 10 | AI 모드 | API Only / Ollama / 하이브리드 | 자동 감지 |
| 11 | 보안 PIN (6자리) | 관리자 인증용 | 자동 생성 |

> ⚠️ 모든 민감 정보는 입력 후 `****`로 마스킹됩니다. 비밀번호를 비워두면 `openssl rand`로 안전한 값을 자동 생성합니다.

### 설치 완료 후 자동 등록되는 Tool (8개)

| # | Tool | 기능 |
|---|------|------|
| 1 | 전화 어시스턴트 | 전화 걸기, 연락처 관리, 통화기록 조회 |
| 2 | RAG 문서 검색 | PDF/문서에서 벡터 검색 |
| 3 | SMS 보내기 | 문자 전송 + 답장 자동 전달 |
| 4 | 예약 스케줄러 | 전화/SMS 예약 등록·조회·삭제 |
| 5 | 통화 녹음 관리 | 녹음 파일 조회/재생 |
| 6 | PDF 보고서 관리 | 통화 보고서 생성/조회 |
| 7 | 기능 상태 확인 | 시스템 상태 모니터링 |
| 8 | 미디어 관리 | 사진/동영상/음성 업로드 및 조회 |

### 다국어 지원

전화번호 국가코드를 자동 감지하여 TTS/STT 언어를 전환합니다.

| 국가코드 | 언어 | TTS 음성 |
|----------|------|----------|
| +82 | 한국어 | ko-KR |
| +1, +44 | English | en-US |
| +81 | 日本語 | ja-JP |
| +86 | 中文 | zh-CN |

설정 변경: `~/OpenWebUI/twilio-bot/ai_config.py`의 `DEFAULT_LANG`, `COUNTRY_LANG_MAP` 수정 후 `docker compose restart twilio-bot`

### Twilio SMS Webhook 설정 (수동)

Twilio 전화봇 사용 시 다음을 수동으로 설정해야 합니다.

1. [Twilio Console](https://console.twilio.com/) 접속
2. **Phone Numbers → Manage → Active numbers** 클릭
3. 사용 중인 전화번호 선택
4. **Messaging Configuration** 섹션에서:
   - **A MESSAGE COMES IN**: Webhook → `https://your-domain.com/sms-incoming` (HTTP POST)
5. **Save** 클릭

### Cloudflare Tunnel (선택)

포트 개방 없이 HTTPS 외부 접속을 지원합니다. 스크립트 실행 중 자동으로 설정을 안내합니다.

```bash
# 수동 설치 시
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg
sudo cloudflared tunnel login
sudo cloudflared tunnel create my-tunnel
```

---

## 💬 Phase 3 — Telegram 브릿지

OpenWebUI의 모든 기능(모델, Tool, RAG)을 Telegram에서 사용할 수 있게 연동합니다.

### 사전 준비

- **Phase 2 설치 완료** — OpenWebUI가 `http://localhost:3000`에서 실행 중이어야 합니다.
- **Telegram Bot Token** — [@BotFather](https://t.me/BotFather)에서 `/newbot` 명령으로 발급
- **OpenWebUI API Key** — OpenWebUI 설정 → API Keys에서 생성
- **Telegram User ID** — [@userinfobot](https://t.me/userinfobot)에서 확인

### 설치 실행

```bash
bash setup-telegram-openwebui-bridge-FINAL.sh
```

### 설치 과정에서 입력하는 정보

| 순서 | 입력 항목 | 필수 | 설명 |
|------|-----------|------|------|
| 1 | Telegram Bot Token | ✅ | BotFather에서 발급 |
| 2 | OpenWebUI API Key | ✅ | OpenWebUI 설정에서 발급 |
| 3 | 허용할 User ID | ✅ | 쉼표 구분 (화이트리스트) |
| 4 | Webhook 모드 여부 | 선택 | Polling(기본) vs Webhook |
| 5 | 관리자 PIN | 선택 | 관리자 명령 인증용 (자동 생성) |

### Telegram Bot 명령어

| 명령어 | 기능 |
|--------|------|
| `/start` | 봇 시작 + 사용 가이드 |
| `/model` | AI 모델 전환 (OpenWebUI에 등록된 모든 모델) |
| `/tools` | Tool 활성화/비활성화 |
| `/clear` | 대화 기록 초기화 |
| `/history` | 최근 대화 기록 조회 |
| `/status` | 시스템 상태 확인 (관리자) |
| `/users` | 사용자 목록 (관리자) |
| `/block`, `/unblock` | 사용자 차단/해제 (관리자) |

### Telegram 보안 기능 (18항목)

- Telegram Bot Token AES-256 암호화 저장
- 허용된 User ID만 접근 (화이트리스트)
- Rate Limiting (분당 30회 / 사용자당)
- 입력 길이 제한 (4,096자) + XSS/인젝션 방어
- Webhook 서명 검증 (Telegram Secret Token)
- 컨테이너 non-root 실행 + Docker 네트워크 격리
- 비정상 요청 3회 실패 → 10분 자동 차단
- 세션 타임아웃 (30분 비활동 시 대화 초기화)
- 파일 업로드 크기 제한 (20MB)
- 로그 로테이션 (10MB × 3파일)

---

## 🌐 Browser Agent — AI 브라우저 자동화

Browser Use + Playwright 기반 AI 브라우저 에이전트를 설치합니다. Multi-Agent(Groq+LangGraph)도 지원합니다.

### 사전 준비

- **Phase 2 설치 완료** — OpenWebUI가 실행 중이어야 합니다.
- **OpenWebUI 관리자 계정** — 이메일 + 비밀번호
- **OpenWebUI API Key** — 설정에서 발급
- **Groq API Key (선택)** — Multi-Agent 기능 사용 시 필요

### 설치 실행

```bash
bash setup-browser-agent-browser-use-v6.sh
```

### 설치 과정에서 입력하는 정보

| 순서 | 입력 항목 | 필수 | 설명 |
|------|-----------|------|------|
| 1 | OpenWebUI 관리자 이메일 | ✅ | Phase 2에서 설정한 이메일 |
| 2 | OpenWebUI 관리자 비밀번호 | ✅ | Phase 2에서 설정한 비밀번호 |
| 3 | OpenWebUI API Key | ✅ | 설정에서 발급 |
| 4 | Groq API Key | 선택 | Multi-Agent 기능용 |

### 주요 기능

- **Browser Use** — DOM + Accessibility Tree 하이브리드 방식 웹 자동화
- **Self-Healing** — 실패 시 자동 재시도 + CVE 패치 적용
- **Multi-Agent (v6.4.0)** — Groq + LangGraph 기반 복수 에이전트 협업
- **한글 우회** — 영어→한국어 자동 매핑 (Groq 모델 호환)
- **스크린샷/세션 저장** — 작업 이력 자동 기록
- **OpenWebUI Tool 자동 등록** — 설치 완료 시 `ai_browser_agent` Tool 자동 등록

### Browser Agent API 엔드포인트

| 엔드포인트 | 메서드 | 설명 |
|------------|--------|------|
| `/health` | GET | 상태 확인 |
| `/browse` | POST | 단일 에이전트 브라우징 |
| `/browse/multi` | POST | Multi-Agent 브라우징 |
| `/memory` | GET | 메모리 조회 |
| `/files` | GET | 파일 목록 |

### 내장 Tool (11개)

`check_weather`, `check_price`, `check_stock`, `search_web`, `translate_text` 등 11개 유틸리티 Tool이 에이전트 내에서 자동 사용됩니다.

### Browser Agent 보안

- **seccomp 프로파일** — 허용 시스템콜 최소화 (`seccomp-browser.json`)
- **cap_drop** — 모든 Linux Capability 제거
- **no-new-privileges** — 권한 상승 차단
- **API 키 인증** — 모든 요청에 Bearer Token 필요
- **감사 로그** — `browser-agent/data/audit/agent.log`
- **VNC 로컬 바인딩** — `127.0.0.1:5901`만 접근 가능
- **non-root 실행** — 컨테이너 내부 UID 1001

---

## ✅ 설치 검증

전체 설치 상태를 한 번에 검증하는 스크립트입니다.

```bash
bash verify-install.sh
```

### 검증 항목 (13개 섹션)

| # | 검증 항목 | 검사 내용 |
|---|-----------|-----------|
| 1 | 디렉토리 구조 | 25개 디렉토리 존재 여부 + 권한 |
| 2 | 필수 파일 | 38개 필수 파일 + 3개 선택 파일 |
| 3 | 보안 권한 | `.env` (600), `secrets/` (700) 등 |
| 4 | Docker 컨테이너 | 5개 컨테이너 실행 상태 + 헬스체크 |
| 5 | Docker 네트워크 | `openwebui_net` 연결 상태 |
| 6 | Docker Secrets | 6개 시크릿 마운트 확인 |
| 7 | Nginx 설정 | 리버스 프록시 + 감사 로그 |
| 8 | Browser Agent | API/Playwright/VNC 동작 확인 |
| 9 | seccomp 프로파일 | JSON 유효성 + syscall 수 |
| 10 | Telegram 설정 | Bot Token + 허용 User ID |
| 11 | Twilio 연동 | Account SID + Telegram 알림 연동 |
| 12 | OpenWebUI Tool | 등록된 Tool 목록 확인 |
| 13 | Cloudflare Tunnel | 설치 및 서비스 상태 (선택) |

### 검증 결과 예시

```
╔══════════════════════════════════════════════════════════════════════╗
║  OpenWebUI AI 에이전트 — 전체 설치 검증 v4.0.0                      ║
╚══════════════════════════════════════════════════════════════════════╝

── 1. 디렉토리 구조 확인 (25개) ──
  ✅  [Phase2] OpenWebUI 루트 [755]
  ✅  [Phase2] tools-api [755]
  ✅  [Browser] browser-agent [755]
  ...

══════════════════════════════════════
  🎉 모든 항목 검증 통과!
══════════════════════════════════════
```

---

## 📁 디렉토리 구조

```
~/
├── OpenWebUI/                          # Phase 2 루트
│   ├── .env                            # 환경변수 (chmod 600)
│   ├── docker-compose.yml              # 메인 Compose
│   ├── docker-compose.override.yml     # Docker Secrets 오버라이드
│   ├── .gitignore                      # secrets/.env 유출 방지
│   ├── .dockerignore
│   ├── view-audit-log.sh               # 감사 로그 뷰어
│   │
│   ├── secrets/                        # Docker Secrets (chmod 700)
│   │   ├── twilio_auth_token
│   │   ├── api_secret
│   │   ├── groq_api_key
│   │   ├── admin_pin
│   │   ├── webui_secret_key
│   │   └── entrypoint-secrets.sh
│   │
│   ├── tools-api/                      # OpenAPI Tool 서버
│   │   ├── main.py
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   │
│   ├── twilio-bot/                     # Twilio 전화/SMS 봇
│   │   ├── twilio_bot.py
│   │   ├── ai_config.py               # 다국어/AI 설정
│   │   ├── scheduler.py               # 예약 스케줄러
│   │   ├── call_history.py            # 통화 기록
│   │   ├── entrypoint.sh
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── data/
│   │       ├── contacts.json          # 연락처 (자동 생성)
│   │       ├── call_history.json      # 통화 기록 (자동 생성)
│   │       ├── schedules.json         # 예약 (자동 생성)
│   │       ├── recordings/            # 통화 녹음
│   │       └── reports/               # PDF 보고서
│   │
│   ├── browser-agent/                  # Browser Agent
│   │   ├── agent_server.py            # 메인 API 서버
│   │   ├── openwebui_tool.py          # OpenWebUI Tool 코드
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   ├── seccomp-browser.json       # seccomp 프로파일
│   │   ├── logrotate.conf
│   │   ├── secrets/                   # Agent 전용 시크릿
│   │   ├── multi_agent/               # Multi-Agent 모듈 (7개 파일)
│   │   └── data/
│   │       ├── screenshots/           # 스크린샷
│   │       ├── sessions/              # 세션 기록
│   │       ├── results/               # 결과 저장
│   │       └── audit/                 # 감사 로그
│   │
│   └── logs/
│       ├── twilio-bot/
│       ├── openapi-tools/
│       └── nginx/
│
├── telegram-openwebui-bridge/          # Phase 3 루트
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
└── ai-share/                           # 로컬 파일 공유 디렉토리
```

---

## 🔌 서비스 포트 맵

| 서비스 | 포트 | 바인딩 | 설명 |
|--------|------|--------|------|
| Open WebUI | 3000 | 0.0.0.0 | 웹 인터페이스 |
| Twilio Bot | 5000 | localhost | 전화/SMS 봇 |
| Qdrant | 6333 | localhost | 벡터 DB 대시보드 |
| OpenAPI Tools | 8000 | localhost | Tool API (Swagger: /docs) |
| tools-api (외부) | 8010 | 0.0.0.0 | Nginx 리버스 프록시 |
| twilio-bot (외부) | 8020 | 0.0.0.0 | Nginx 리버스 프록시 |
| Browser Agent | 8001 | localhost | 브라우저 자동화 API |
| VNC (Browser) | 5901 | 127.0.0.1 | 브라우저 화면 확인용 |
| Ollama | 11434 | localhost | 로컬 LLM (선택) |

---

## 🛠 주요 명령어

### 서비스 관리

```bash
# Phase 2 — 전체 시작/중지
cd ~/OpenWebUI && docker compose up -d
cd ~/OpenWebUI && docker compose down

# Phase 3 — Telegram 시작/중지
cd ~/telegram-openwebui-bridge && docker compose up -d
cd ~/telegram-openwebui-bridge && docker compose down

# 개별 서비스 재시작
cd ~/OpenWebUI && docker compose restart twilio-bot
cd ~/OpenWebUI && docker compose restart browser-agent

# 전체 상태 확인
cd ~/OpenWebUI && docker compose ps
```

### 로그 확인

```bash
# 실시간 로그
docker logs -f open-webui
docker logs -f twilio-bot
docker logs -f browser-agent
docker logs -f telegram-openwebui-bridge

# 감사 로그
cd ~/OpenWebUI && ./view-audit-log.sh          # 최근 20건
cd ~/OpenWebUI && ./view-audit-log.sh tail     # 실시간
cd ~/OpenWebUI && ./view-audit-log.sh errors   # 에러만
```

### Browser Agent API 테스트

```bash
# 헬스 체크
curl http://localhost:8001/health

# 메모리 확인
curl -s http://localhost:8001/memory | python3 -m json.tool

# 파일 목록
curl -s http://localhost:8001/files | python3 -m json.tool
```

### 설치 검증

```bash
bash verify-install.sh
```

### 재설치

```bash
# Browser Agent만 재설치
rm -rf ~/OpenWebUI/browser-agent
bash setup-browser-agent-browser-use-v6.sh

# Telegram 브릿지 재설치
rm -rf ~/telegram-openwebui-bridge
bash setup-telegram-openwebui-bridge-FINAL.sh

# 전체 재설치 (데이터 보존)
cd ~/OpenWebUI && docker compose down
bash start-openwebui-hardened.sh
```

---

## 🔐 보안 체크리스트

### Phase 2 보안 (21항목)

- [x] Twilio 서명 검증 (X-Twilio-Signature)
- [x] API Secret 인증 (Bearer Token)
- [x] 포트 로컬 바인딩 (외부 직접 접근 차단)
- [x] PIN 6자리 인증 (관리자 기능 보호)
- [x] 민감 입력 마스킹 (API Key/Token → `****`)
- [x] CORS 제한 (허용된 Origin만)
- [x] `.env` chmod 600 (소유자만 읽기/쓰기)
- [x] Docker Secrets (`/run/secrets/` 분리 저장)
- [x] 구조화된 JSON 감사 로그
- [x] Cloudflare Tunnel HTTPS (선택)
- [x] 기본 비밀번호 제거 (빈 입력 시 `openssl rand` 자동 생성)
- [x] PIN 잠금 영구 저장 (파일 기반 + 30분 자동 해제)
- [x] TTS 인젝션 방지
- [x] `.gitignore` / `.dockerignore` 자동 생성

### Phase 3 보안 (18항목)

- [x] Telegram Bot Token AES-256 암호화 저장
- [x] 허용 User ID 화이트리스트
- [x] Rate Limiting (분당 30회)
- [x] 입력 길이 제한 (4,096자)
- [x] Webhook 서명 검증
- [x] non-root 컨테이너 실행
- [x] Docker 네트워크 격리
- [x] 비정상 요청 3회 → 10분 자동 차단

### Browser Agent 보안

- [x] seccomp 프로파일 (허용 syscall 최소화)
- [x] cap_drop ALL + no-new-privileges
- [x] API 키 인증 (모든 요청)
- [x] VNC 127.0.0.1 바인딩
- [x] 감사 로그 (`data/audit/agent.log`)
- [x] non-root 실행 (UID 1001)

### 권장 방화벽 설정

```bash
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

---

## ❓ 문제 해결

### Docker 권한 오류

```
❌ Docker 권한 없음
```

```bash
sudo usermod -aG docker $USER
# 재로그인 후 다시 실행
```

### 컨테이너 헬스체크 실패

```bash
# 상태 확인
docker inspect --format='{{.State.Health.Status}}' <컨테이너명>

# 로그 확인
docker logs <컨테이너명> --tail 50
```

### OpenWebUI 접속 불가

```bash
# 컨테이너 상태 확인
docker compose ps

# 포트 확인
ss -tlnp | grep 3000

# 재시작
cd ~/OpenWebUI && docker compose restart open-webui
```

### Browser Agent API 응답 없음

```bash
# 컨테이너 내부에서 확인
docker exec browser-agent python3 -c "
import urllib.request
r = urllib.request.urlopen('http://localhost:8001/health', timeout=3)
print(r.read().decode())
"

# Playwright 확인
docker exec browser-agent python3 -c "
from playwright.sync_api import sync_playwright
print('Playwright OK')
"
```

### secrets 디렉토리 권한 문제

```bash
# UID 1001 소유로 설정 (컨테이너 사용자)
sudo chown -R 1001:1001 ~/OpenWebUI/secrets/
sudo chmod 700 ~/OpenWebUI/secrets/
```

### Telegram Bot 연결 안 됨

```bash
# Bot Token 확인
cat ~/telegram-openwebui-bridge/.env | grep TELEGRAM_BOT_TOKEN

# 로그 확인
docker logs telegram-openwebui-bridge --tail 30

# 재시작
cd ~/telegram-openwebui-bridge && docker compose restart
```

---

## 🔧 유지보수

### OpenWebUI 버전 다운그레이드

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
```

최신 버전으로 복원하려면:

```bash
cd ~/OpenWebUI
sed -i 's|ghcr.io/open-webui/open-webui:v0.9.2|ghcr.io/open-webui/open-webui:main|g' docker-compose.yml
docker compose down && docker compose up -d
```

> ⚠️ **주의:** DB 스키마 변경이 포함된 메이저 업데이트(예: v0.9.0) 이전 버전으로 되돌릴 경우 호환성 문제가 발생할 수 있습니다. 큰 폭의 다운그레이드 전에는 반드시 데이터를 백업하세요.

사용 가능한 버전 태그는 [GitHub Releases](https://github.com/open-webui/open-webui/releases) 페이지에서 확인할 수 있습니다.

### 다운그레이드 후 이전 이미지 정리

버전 변경 시 이전 Docker 이미지가 디스크에 남습니다. 아래 명령어로 정리하세요.

```bash
# 사용하지 않는 이미지 용량 확인
docker system df

# 미사용 이미지 모두 삭제 (현재 실행 중인 컨테이너는 영향 없음)
docker image prune -a -f
```

---

## 📜 라이센스

MIT License

---

## 📌 버전 정보

| 컴포넌트 | 버전 | 스크립트 |
|----------|------|----------|
| OpenWebUI + RAG + Twilio | v1.1.0-보안강화 | `start-openwebui-hardened.sh` |
| Telegram 브릿지 | v1.4.0-보안강화+연동 | `setup-telegram-openwebui-bridge-FINAL.sh` |
| Browser Agent (Multi-Agent) | v6.4.0 | `setup-browser-agent-browser-use-v6.sh` |
| 설치 검증 | v4.0.0 | `verify-install.sh` |

---

## ⚡ 빠른 시작 (Quick Start)

```bash
# 1단계: Phase 2 — 핵심 플랫폼 설치
bash start-openwebui-hardened.sh

# 2단계: Phase 3 — Telegram 연동 (선택)
bash setup-telegram-openwebui-bridge-FINAL.sh

# 3단계: Browser Agent 설치 (선택)
bash setup-browser-agent-browser-use-v6.sh

# 4단계: 전체 설치 검증
bash verify-install.sh
```

설치 완료 후 `http://localhost:3000`에서 OpenWebUI에 접속합니다.
