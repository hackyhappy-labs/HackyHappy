# OpenWebUI AI 에이전트 스택

> [Open WebUI](https://github.com/open-webui/open-webui) 기반의 보안 강화형 셀프호스팅 AI 에이전트 플랫폼 — Twilio 음성/SMS 봇, Telegram 브릿지, Multi-Agent 브라우저 자동화 서비스를 포함합니다.

**언어:** [English](./README.md) · **한국어**

---

## 개요

이 저장소는 단일 Linux 호스트(Ubuntu / WSL2 지원)에 완전한 로컬 AI 에이전트 스택을 구축하는 4개의 Bash 설치 스크립트로 구성됩니다. 모든 서비스는 Docker로 실행되며, 기본적으로 모든 포트가 `127.0.0.1`에 바인딩되고, 민감정보는 Docker Secrets와 엄격한 파일 권한으로 보관됩니다.

| # | 스크립트 | 역할 | 기본 포트 (localhost) |
|---|---------|------|----------------------|
| 1 | `start-openwebui-hardened.sh` | **Phase 2** — Open WebUI + RAG(Qdrant) + OpenAPI Tools + Twilio 음성/SMS 봇 | `3000` WebUI, `6333` Qdrant, `8000` Tools, `5000` Twilio 봇 |
| 2 | `setup-telegram-openwebui-bridge-FINAL.sh` | **Phase 3** — Telegram ↔ Open WebUI 브릿지 + 관리자 대시보드 | `8444` 헬스체크, `8445` 대시보드 |
| 3 | `setup-browser-agent-browser-use-v7.sh` | **Browser Agent** — Browser-Use + Playwright + LangGraph Multi-Agent | `8001` 에이전트 API |
| 4 | `verify-install.sh` | **검증기** — 위 세 스크립트를 실제 설치된 소스와 대조 검증 | — |

> 각 스크립트는 독립적이지만 계층적으로 쌓이도록 설계되었습니다. Phase 2를 먼저 설치한 뒤 필요에 따라 Browser Agent와 Telegram 브릿지를 추가하고, 마지막에 검증기를 실행하세요.

---

## 요구사항

- **운영체제:** Ubuntu 20.04+ (네이티브 또는 WSL2). WSL2는 자동 감지되어 처리됩니다.
- **Docker** + **Docker Compose 플러그인**(`docker compose`). Phase 2 스크립트는 Docker가 없으면 설치를 제안합니다.
- **`sudo`** 권한 (Docker, secret 소유권 `uid 1001`, 방화벽 설정에 사용).
- **`python3`** (Telegram 및 검증 스크립트가 사용).
- **LLM API 키 최소 1개** — Groq, OpenAI, Anthropic(Claude), Google(Gemini) 중. 기본값은 Groq입니다.
- *(선택)* 음성/SMS 봇용 **Twilio** 계정, 브릿지용 **Telegram Bot Token**, 로컬 모델용 **Ollama**.

---

## 빠른 시작

```bash
# 0. 클론
git clone https://github.com/<your-org>/<your-repo>.git
cd <your-repo>
chmod +x *.sh

# 1. Phase 2 — 핵심 플랫폼 (Open WebUI + RAG + Twilio 봇)
bash start-openwebui-hardened.sh

# 2. (선택) Browser Agent — Multi-Agent 웹 자동화
bash setup-browser-agent-browser-use-v7.sh

# 3. (선택) Telegram 브릿지
bash setup-telegram-openwebui-bridge-FINAL.sh

# 4. 전체 설치 검증
bash verify-install.sh
```

각 설치 스크립트는 **대화형**이며 필요한 키/값을 입력받습니다(대부분 입력에 타임아웃이 있고 Enter로 건너뛸 수 있습니다). Phase 2가 끝나면 Open WebUI는 **http://localhost:3000** 에서 접속할 수 있습니다.

---

## 4개 스크립트 상세

### 1. `start-openwebui-hardened.sh` — Phase 2 (핵심 플랫폼)

스택의 중심을 설치합니다.

- RAG 문서 검색용 **Qdrant** 벡터 DB(`:6333`)와 함께 동작하는 **Open WebUI** 채팅 인터페이스(`:3000`).
- 모델이 호출할 수 있는 도구를 노출하는 **OpenAPI Tools** 서버(`:8000`).
- **Twilio AI 전화봇**(`:5000`): AI 기반 발신 통화와 양방향 SMS를 처리하며, **국가코드 기반 언어 자동 감지**(`+82` 한국어, `+1` 영어, `+81` 일본어, `+86` 중국어)를 지원합니다.
- 전화 어시스턴트, RAG 검색, SMS 전송, 예약 스케줄러, 통화 녹음 관리, PDF 보고서 관리, 기능 상태 확인 등 7개의 Open WebUI 도구를 등록합니다.

**입력 항목:** Groq API 키, (선택) Twilio 자격증명(Account SID, Auth Token, 전화번호, 내 번호), 관리자 이메일/앱 이름, 봇 모드, 그리고 필수 **6자리 관리자 PIN**. Ollama와 NVIDIA GPU는 자동 감지됩니다.

**보안 핵심:** Docker Secrets(`/run/secrets/`), 구조화된 JSON 감사 로그, 모든 포트 `127.0.0.1` 바인딩, `.env` `chmod 600`, 민감 입력 마스킹, 포트 개방 없이 HTTPS를 제공하는 선택적 Cloudflare Tunnel.

### 2. `setup-browser-agent-browser-use-v7.sh` — Browser Agent

**Browser-Use** + **Playwright(Chromium)** 기반의 컨테이너형 웹 자동화 에이전트로, **LangGraph Multi-Agent** 모드(supervisor → research → browser-tool → summarizer)를 제공합니다.

- API는 `127.0.0.1:8001`. 주요 엔드포인트: `/browse`, `/browse/stream`(SSE), `/browse/batch`, `/browse/multi`(Multi-Agent), `/screenshot`, `/history`, `/tasks`, `/sessions`, `/monitors`, `/pool/status`, `/proxy/status`, `/memory`, `/files`, `/metrics`, `/health`, `/health/multi`.
- **멀티 프로바이더 LLM:** Groq(기본), OpenAI, Anthropic/Claude, Google/Gemini — `LLM_PROVIDER` 또는 존재하는 API 키에 따라 자동 선택.
- `search_wikipedia`, `take_screenshot`, `search_map`, `download_file`, `export_to_excel`, `monitor_price`, `check_monitors` 등의 Open WebUI 도구를 등록합니다.
- `~/ai-share` → `/app/data/user_files` 마운트를 통해 호스트와 파일을 공유합니다.

**보안 핵심:** seccomp 프로파일, `cap_drop: ALL`, `no-new-privileges`, 보호된 라우트의 API 키 인증, 반복 실패 시 IP 잠금, 감사 로그, 요청 본문 크기 제한, Path Traversal 방어. WSL2에서는 runc `openat2` 호환을 위해 privileged 모드로 폴백합니다(검증기 섹션 15의 경고 참조).

### 3. `setup-telegram-openwebui-bridge-FINAL.sh` — Telegram 브릿지 (Phase 3)

이미 설치된 Open WebUI 인스턴스를 Telegram 봇과 연결해, 모든 모델·도구·RAG를 Telegram에서 그대로 사용할 수 있게 합니다.

- **명령어:** `/start`, `/help`, `/model`, `/tools`, `/clear`, `/lock`, `/history`, `/status`, `/whoami`, `/admin`, `/users`, `/block`, `/unblock`, `/adduser`, `/removeuser`, `/broadcast`, `/logs`, `/stats`, `/emergency`, `/remind`, `/reminders`, `/cancel`.
- **스트리밍** 응답, 리마인더용 **예약 스케줄러**, `127.0.0.1:8445`의 **관리자 웹 대시보드**(아래 SSH 터널로 접속).
- **입력 항목:** Telegram Bot Token, OpenWebUI API 키, 필수 관리자 **Telegram User ID** 화이트리스트, 선택 6자리 관리자 PIN.

**보안 26항목** 포함: Replay Attack 방어(`update_id`), Prompt Injection 필터링, 파일 Magic Bytes 검증, AI 응답 민감정보 자동 필터링, JSON 감사 로그, 비상 차단 모드, 대시보드 Brute-force 방지(timing-safe), seccomp 프로파일.

대시보드 접속:

```bash
ssh -L 8445:localhost:8445 user@서버IP
# 이후 http://localhost:8445/dashboard 접속
```

### 4. `verify-install.sh` — 설치 검증기

세 설치 스크립트를 **실제 설치된 소스코드**와 대조하는 읽기 전용 진단 도구로, 15개 섹션을 점검합니다: 디렉토리 구조, 필수 파일, 파일 권한, 컨테이너 상태, API 헬스 엔드포인트, Docker 네트워크, 보안 점검, Browser-Use/Chromium/패키지, seccomp 유효성, Telegram·Twilio 설정, Open WebUI 도구 등록, Browser Agent 기능 검증, 선택적 Cloudflare Tunnel, 보안 감사 대조.

```bash
bash verify-install.sh        # 실패한 검사 수를 종료 코드로 반환
```

일부 검사가 실패해도 끝까지 실행되어 마지막에 합산하도록, 의도적으로 `set -e`/`-u` 를 **사용하지 않습니다**.

---

## 자주 쓰는 명령어

```bash
# 시작 / 상태 (Phase 2)
cd ~/OpenWebUI && docker compose up -d
cd ~/OpenWebUI && docker compose ps

# 감사 로그
cd ~/OpenWebUI && ./view-audit-log.sh

# 로그
docker logs -f twilio-bot
docker logs -f telegram-openwebui-bridge
docker logs -f browser-agent

# Telegram 브릿지
cd ~/telegram-openwebui-bridge && docker compose up -d

# Browser Agent 헬스 / 멀티에이전트
curl -H "Authorization: Bearer $(grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env | cut -d= -f2-)" \
  http://localhost:8001/health | python3 -m json.tool
```

---

## 설치 후 디렉토리 구조

```
~/OpenWebUI/                     # Phase 2 루트
├── docker-compose.yml
├── .env                         # chmod 600
├── secrets/                     # Docker Secrets (uid 1001, chmod 700)
├── tools-api/                   # OpenAPI 도구 서버
├── twilio-bot/                  # Twilio 음성/SMS 봇 + 데이터
├── browser-agent/               # Browser Agent (설치 시)
│   ├── agent_server.py
│   ├── multi_agent/             # LangGraph 멀티에이전트 모듈
│   ├── seccomp-browser.json
│   └── secrets/
└── logs/

~/telegram-openwebui-bridge/     # Phase 3 루트 (설치 시)
├── docker-compose.yml
├── bot/                         # telegram_bot.py, seccomp-bot.json
└── secrets/

~/ai-share/                      # 호스트 ↔ Browser Agent 공유 파일
```

---

## 보안 주의사항

- 모든 서비스 포트는 `127.0.0.1`에 바인딩됩니다. 외부 공개가 필요하면 포트를 직접 여는 대신 **Cloudflare Tunnel** 또는 TLS 리버스 프록시를 사용하세요.
- `.env` 파일과 `secrets/` 디렉토리는 버전 관리에 포함하지 마세요. Phase 2 설치 스크립트가 이를 위해 `.gitignore`/`.dockerignore`를 생성합니다 — **민감정보를 절대 커밋하지 마세요.**
- WSL2에서는 Browser Agent와 Telegram 브릿지가 **privileged** 모드로 실행될 수 있어 컨테이너 격리가 약화됩니다. 신뢰할 수 있는 호스트에서만 사용하세요. 검증기 섹션 15에서 이를 경고합니다.
- 설치 또는 업그레이드 후에는 항상 `verify-install.sh`를 실행해 설정 오류를 점검하세요.

---

## 라이선스

여기에 라이선스를 명시하세요(예: MIT). 저장소 루트에 `LICENSE` 파일을 추가하세요.

## 면책 조항

이 스크립트들은 전화 발신, SMS 발송, 자율 웹 브라우징, 원격 명령 수신이 가능한 서비스를 구성합니다. 설정을 검토하고, 강력한 시크릿을 사용하며, 접근을 신뢰할 수 있는 사용자로 제한하고, Twilio·Telegram 및 선택한 LLM 제공자의 약관과 관련 법규를 준수하세요.
