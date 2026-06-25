# OpenWebUI + Twilio AI 전화비서 + 캘린더 + Telegram + 브라우저 에이전트

**[English](README.md)** · **한국어**

OpenWebUI를 중심으로 **AI 전화비서(Twilio)**, **캘린더 연동**, **Telegram 봇**, **AI 브라우저 에이전트**를 통합한 셀프호스팅 설치 패키지입니다. Docker 기반으로 한 번에 설치되며, 보안 강화와 다국어(한/영/일/중)를 지원합니다.

> **한 줄 요약** — 전화·채팅·텔레그램·브라우저 어디서든 "오늘 일정 알려줘"가 되고, 관리자만 민감 기능에 접근하며, 모르는 사람의 통화는 차단(개인용)하거나 AI가 상담(고객용)합니다.

---

## 목차

- [주요 기능](#주요-기능)
- [두 가지 운영 모드](#두-가지-운영-모드)
- [요구사항](#요구사항)
- [설치](#설치)
- [캘린더 설정](#캘린더-설정)
- [통화 인증 (보안)](#통화-인증-보안)
- [채널별 사용법](#채널별-사용법)
- [설치 검증](#설치-검증)
- [재발 방지 / 문제 해결](#재발-방지--문제-해결)
- [보안](#보안)
- [파일 구성](#파일-구성)
- [자주 묻는 질문](#자주-묻는-질문)

---

## 주요 기능

| 기능 | 설명 |
|------|------|
| 📞 AI 전화비서 | Twilio로 전화 걸기·받기, 음성 대화, SMS 발송 |
| 📅 캘린더 | OpenWebUI 내장 캘린더의 오늘 일정을 채팅·전화·텔레그램·브라우저에서 조회 |
| 💬 Telegram 봇 | 텔레그램에서 OpenWebUI와 대화, 파일 색인, 예약 |
| 🤖 브라우저 에이전트 | AI가 웹사이트를 탐색·스크린샷·데이터 추출 |
| 📚 RAG | 업로드한 문서를 기반으로 답변 |
| 🔒 보안 강화 | 컨테이너 하드닝, Docker Secrets, CVE 패치, 번호 기반 통화 인증 |

---

## 두 가지 운영 모드

용도에 따라 두 가지 메인 스크립트 중 하나를 선택합니다.

| 모드 | 스크립트 | 모르는 번호가 전화하면 | 캘린더·명령 |
|------|----------|----------------------|-------------|
| **개인용** | `start-openwebui-hardened-admin-only.sh` | 즉시 차단 | 관리자만 |
| **고객 상담용** | `start-openwebui-customer-support.sh` | AI가 일반 상담 응대 | 관리자만 (고객 접근 불가) |

> 두 모드 모두 **캘린더·SMS·명령 등 민감 기능은 관리자(설치 시 입력한 번호)만** 사용할 수 있습니다. 고객 상담 모드에서 고객이 "오늘 일정"을 말해도 캘린더에는 접근할 수 없습니다.

---

## 요구사항

- **OS**: Ubuntu 22.04+ (WSL2 포함) 또는 Docker가 동작하는 Linux
- **Docker** + Docker Compose
- **OpenWebUI 0.9.0 이상** (내장 캘린더 기능 필요)
- **Twilio 계정** (전화번호, Account SID, Auth Token) — 전화 기능 사용 시
- (선택) Telegram Bot Token — 텔레그램 사용 시
- (선택) Groq / OpenAI / Claude / Gemini API 키 — AI 모델용

---

## 설치

### 1단계 — 메인 설치 (OpenWebUI + 전화비서 + 캘린더)

용도에 맞는 스크립트를 다운로드 후 실행합니다.

**개인용 (나만의 AI 비서):**

```bash
wget https://YOUR-HOST/start-openwebui-hardened-admin-only.sh
less start-openwebui-hardened-admin-only.sh    # 실행 전 내용 검토 권장
chmod +x start-openwebui-hardened-admin-only.sh
./start-openwebui-hardened-admin-only.sh
```

**고객 상담용:**

```bash
wget https://YOUR-HOST/start-openwebui-customer-support.sh
chmod +x start-openwebui-customer-support.sh
./start-openwebui-customer-support.sh
```

설치 중 입력 항목 (순서대로):

| 항목 | 예시 | 설명 |
|------|------|------|
| 나의 전화번호 | `+821012345678` | **관리자 번호** (봇에게 전화 걸 권한). 쉼표로 여러 개 가능 |
| Twilio 정보 | SID / Token / 번호 | 전화 기능용 |
| 서버 도메인 | `https://yourdomain.com` | Twilio Webhook용 |
| 관리자 이메일 / 비밀번호 | — | OpenWebUI 로그인용 |
| AI 모드 | `2` | 1=OpenWebUI, 2=Groq, 3=포워딩 |
| 연락처 | `김철수,+821011112222` | 봇이 **전화 걸 대상** (통화 권한과 무관) |

> **PIN 입력은 없습니다.** 이전의 PIN 방식은 폐지되었고, 등록된 관리자 번호 기반 인증이 자동 적용됩니다.

설치가 끝나면 OpenWebUI, 전화 봇, RAG 등 전체 스택이 자동으로 뜨고 **도구 9개(캘린더 포함)가 자동 등록**됩니다.

### 2단계 — 브라우저 에이전트 (선택)

```bash
chmod +x setup-browser-agent-calendar.sh
./setup-browser-agent-calendar.sh
```

### 3단계 — Telegram 봇 (선택)

```bash
chmod +x setup-telegram-bridge-calendar.sh
./setup-telegram-bridge-calendar.sh
```

> 2·3단계는 **1단계 설치 후**에 실행하세요. 캘린더 도구가 OpenWebUI에 먼저 등록되어 있어야 합니다.

---

## 캘린더 설정

캘린더는 설치 시 **자동 등록**되지만, 실제로 쓰려면 API 키를 한 번 입력해야 합니다.

### 설정 순서 (한 번만)

1. OpenWebUI 관리자 로그인 → **설정 → 계정 → API 키** 발급
2. 좌측 **캘린더(Calendar)** 에 오늘 일정 등록
3. **워크스페이스 → 도구 → "캘린더 (오늘 일정)" → ⚙️ 밸브** → `OPENWEBUI_API_KEY`에 키 입력 → 저장
4. **채팅에서 "오늘 일정 알려줘"를 한 번 실행** ← 핵심 단계
5. 이제 전화·텔레그램에서도 "오늘 일정 알려줘"가 작동합니다

> **4단계가 중요합니다.** 이때 키가 공유 폴더에 저장되어 전화 봇도 캘린더를 읽을 수 있게 됩니다.

### API 키 형식

- `sk-...` 형식 — **권장** (만료 없음)
- `eyJ...` (JWT 토큰) — 작동하지만 **만료**가 있어 권장하지 않음

> JWT 키가 만료되면 전화에서 "키가 만료되었을 수 있으니 새 키로 다시 설정해 주세요"라고 안내합니다. 가짜 일정은 나오지 않습니다.

### 채널별 키 입력 위치

| 채널 | 접근 방식 | 키 입력 위치 |
|------|----------|-------------|
| 채팅 | "캘린더 (오늘 일정)" 도구 직접 호출 | 그 도구의 밸브 |
| 전화 | "오늘 일정" 키워드 감지 → 공유 키로 조회 | (채팅 키 공유받음) |
| 텔레그램 | 모든 도구 자동 활성화 → 캘린더 포함 | (채팅 키 공유받음) |
| 브라우저 에이전트 | "AI 브라우저 에이전트" 도구의 메서드 | **그 도구의 밸브에 별도 입력** (`OPENWEBUI_API_KEY`) |

> 브라우저 에이전트만 같은 키를 그 도구 밸브에 한 번 더 넣어야 합니다 (독립 도구). `BROWSER_AGENT_API_KEY`나 `LLM_API_KEY`가 아니라 **`OPENWEBUI_API_KEY`** 칸입니다.

---

## 통화 인증 (보안)

### PIN 폐지 → 등록된 관리자 번호만

이전의 PIN 입력 방식은 **완전히 제거**되었습니다. 모르는 사람이 전화하면 PIN을 묻지 않고 즉시 차단됩니다(개인용 모드).

**왜 더 안전한가:** PIN은 유출되면 누구나 통과하지만, 번호 방식은 등록된 번호로 실제 전화를 걸어야만 인정됩니다.

### 관리자 번호 vs 연락처 — 혼동 주의

| 구분 | 무엇 | 방향 |
|------|------|------|
| **관리자 번호** (`ADMIN_NUMBERS`) | 설치 시 입력한 내 번호 | 봇에게 **전화 거는** 권한 |
| **연락처** | 채팅에서 저장한 "김철수…" | 봇이 **전화 거는** 대상 |

> 채팅에서 "김철수 저장"해도 김철수가 봇에게 전화하면 차단됩니다(개인용). 김철수가 봇에게 전화하게 하려면 그 번호를 **관리자 번호**에 추가해야 합니다.

### 관리자 번호 추가/변경

```bash
cd ~/OpenWebUI
read -p "관리자 번호 (예: +821012345678,+821099998888): " NEW_ADMINS
sed -i "s/ADMIN_NUMBERS=.*/ADMIN_NUMBERS=$NEW_ADMINS/" .env
docker compose up -d twilio-bot
```

---

## 채널별 사용법

### 전화

관리자 번호로 봇에 전화 → 자연어로 명령:

- "오늘 일정 알려줘" → 캘린더 음성 안내
- "김철수한테 전화해줘" → 봇이 김철수에게 전화
- "문자 보내줘" → SMS 발송

### 채팅 (OpenWebUI)

도구를 켜고 자연어로:

- "오늘 일정 알려줘"
- "통화 기록 보여줘"

### Telegram

봇에게 메시지:

- "오늘 일정 알려줘" → 캘린더 조회
- 파일(PDF/이미지) 전송 → RAG 색인
- `/remind 매일 09:00 날씨 알려줘` → 예약

### 브라우저 에이전트

채팅에서:

- "○○ 사이트에서 가격 찾아줘"
- "오늘 일정 알려줘" (캘린더 메서드)

---

## 설치 검증

설치 후 정합성을 자동 점검합니다.

```bash
chmod +x verify-install.sh
./verify-install.sh
```

검증 항목 (일부):

- 디렉토리 구조 / 필수 파일 / 권한
- Docker 컨테이너 상태 / 네트워크
- 도구 9개 등록 (캘린더 포함)
- **캘린더 연동** — `/owui-data` 마운트, 공유 키, COMPOSE_FILE 고정
- **보안 강화** — requests/urllib3 CVE 패치, trust_env
- **통화 인증** — 관리자 번호 설정, 운영 모드 감지

---

## 재발 방지 / 문제 해결

### 전화가 "가짜 일정"을 말하는 경우

원인은 대부분 **캘린더 볼륨 마운트 누락**입니다. 현재 버전은 마운트를 메인 compose에 고정 + `.env`의 `COMPOSE_FILE`에 고정하여 **영구 해결**했습니다. `docker compose up`, `restart`, 서버 재부팅 등 어떤 방식으로 띄워도 캘린더가 항상 연결됩니다.

수동 점검:

```bash
# 마운트 확인 (있어야 정상)
docker exec twilio-bot ls -la /owui-data/

# 공유 키 확인 (값이 있어야 정상)
docker exec twilio-bot cat /owui-data/shared-key/openwebui_api_key
```

마운트가 없으면:

```bash
cd ~/OpenWebUI
./calendar-up.sh
```

### 채팅에서 캘린더가 15초 타임아웃되는 경우

`curl`로는 같은 API가 즉시(0.02초) 응답하는데 **채팅** 캘린더 도구만 15초 타임아웃이 난다면, 원인은 **단일 워커 self-call 데드락**입니다. OpenWebUI가 유일한 워커로 도구를 실행하는데, 그 도구가 다시 OpenWebUI 자기 API를 호출하니 응답할 워커가 없어 막힙니다.

해결 — OpenWebUI를 멀티 워커로 실행 (**현재 스크립트에 이미 적용됨**):

```bash
cd ~/OpenWebUI
# docker-compose.yml의 open-webui 서비스 environment에 아래가 있어야 함:
#   - UVICORN_WORKERS=4
docker compose up -d open-webui   # "Running"만 뜨면 안 되고 "Started/Recreated"가 떠야 함

# 확인
docker exec openwebui-open-webui-1 sh -c 'cat /proc/1/environ | tr "\0" "\n" | grep UVICORN_WORKERS'
```

> 워커마다 메모리를 추가로 씁니다. 메모리가 빠듯하면 `UVICORN_WORKERS=2`로도 데드락은 풀립니다.

### 캘린더 조회 실패 시 안내 메시지

조회가 실패하면 AI가 지어낸 가짜 일정 대신 정확한 원인을 안내합니다:

| 상황 | 안내 |
|------|------|
| 키 미설정 | "캘린더 키가 설정되지 않았습니다…" |
| 연결 실패 | "캘린더 서버에 연결하지 못했습니다…" |
| 키 만료(JWT) | "키가 만료되었을 수 있으니 새 키로 다시 설정해 주세요" |

---

## 보안

| 항목 | 내용 |
|------|------|
| 통화 인증 | 등록된 관리자 번호만 (PIN 폐지) |
| requests | `>=2.34.2` — CVE-2024-47081 (netrc 자격증명 유출) 패치 |
| urllib3 | `>=2.6.3` — CVE-2026-21441 (DoS) 패치 |
| trust_env | 캘린더 조회 시 환경 자격증명 비활성화 + 리다이렉트 차단 |
| 컨테이너 | no-new-privileges, cap_drop ALL, 비루트 실행, 메모리 제한 |
| 비밀키 | Docker Secrets로 분리 저장 |
| Twilio | 요청 서명 검증(`validate_twilio_request`), hmac 비교 |
| 캘린더 권한 | 고객 상담 모드에서도 관리자 전용으로 분리 |

> CVE 패치 버전은 작성 시점 기준입니다. 배포 전 최신 보안 권고를 한 번 더 확인하세요.

---

## 파일 구성

```
.
├── start-openwebui-hardened-admin-only.sh   # 메인 설치 (개인용)
├── start-openwebui-customer-support.sh      # 메인 설치 (고객 상담용)
├── setup-browser-agent-calendar.sh          # 브라우저 에이전트 + 캘린더
├── setup-telegram-bridge-calendar.sh        # Telegram 봇 + 캘린더
├── verify-install.sh                        # 설치 검증
└── docs/                                    # HTML 설치 가이드
    ├── index.html                           # 시작 · 요구사항
    ├── install.html                         # 설치 · 전화비서 · 캘린더 · 통화인증
    ├── operations.html                      # RAG · 보안 · 유지보수 · 백업
    ├── usage.html                           # Telegram 봇
    ├── browser-agent.html                   # 브라우저 에이전트
    └── cloud.html                           # 클라우드 배포 (24시간 운영)
```

설치 후 생성되는 주요 파일 (`~/OpenWebUI/`):

```
~/OpenWebUI/
├── docker-compose.yml                # 메인 (캘린더 마운트 포함)
├── docker-compose.calendar.yml       # 캘린더 백업용 (보통 불필요)
├── .env                              # COMPOSE_FILE 고정 (재발 방지)
├── calendar-up.sh                    # 캘린더 포함 재기동
├── twilio-bot/                       # 전화 봇
├── tools-api/                        # RAG · 도구 API
└── secrets/                          # Docker Secrets
```

---

## 자주 묻는 질문

**Q. 전화에서 캘린더가 작동하지 않아요.**
A. 채팅에서 "오늘 일정 알려줘"를 한 번 실행했는지 확인하세요. 이때 키가 전화 봇과 공유됩니다. 그래도 안 되면 위 [재발 방지](#재발-방지--문제-해결) 섹션의 마운트 점검을 따르세요.

**Q. API 키가 `sk-`가 아니라 `eyJ...`로 나와요.**
A. 그건 JWT 토큰입니다. 그대로 써도 작동하지만 만료가 있습니다. 설정 → 계정에서 별도의 "API 키 생성" 버튼으로 `sk-` 키를 만들면 만료 걱정이 없습니다.

**Q. 채팅에서 연락처를 저장하면 그 사람이 전화할 수 있나요?**
A. 아니요. 연락처는 봇이 **전화 거는 대상**일 뿐입니다. 그 사람이 봇에게 전화하려면 번호를 **관리자 번호(`ADMIN_NUMBERS`)** 에 추가해야 합니다.

**Q. 고객 상담용으로 쓰면 고객이 캘린더를 볼 수 있나요?**
A. 아니요. 고객은 일반 AI 상담만 받습니다. 캘린더·SMS·명령 등 민감 기능은 관리자 전용으로 분리되어 있습니다.

**Q. 텔레그램에도 PIN이 있던데요?**
A. 텔레그램 봇의 PIN은 **전화 봇 PIN과 별개**(텔레그램 사용자 인증용)이며 선택사항입니다. 전화 봇의 PIN만 폐지되었습니다.

**Q. 서버를 재부팅하면 캘린더가 또 끊기나요?**
A. 아니요. 재발 방지가 적용되어 마운트가 메인 compose와 `.env`에 고정되어 있습니다. 어떻게 띄워도 캘린더가 유지됩니다.

---

## 라이선스 / 기여

이 저장소를 사용하기 전에 각 스크립트 내용을 검토하세요. 셀프호스팅 환경과 외부 서비스(Twilio, Telegram, AI 제공자)의 약관·요금을 반드시 확인하시기 바랍니다.

> ⚠️ 이 패키지는 전화·SMS·AI API 등 **과금되는 외부 서비스**를 사용합니다. 사용량과 요금을 모니터링하세요.
