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
- [통화 기능 (끼어들기 · 상담원 연결)](#통화-기능-끼어들기--상담원-연결)
- [진짜 실시간 대리통화 (Media Streams)](#진짜-실시간-대리통화-media-streams)
- [실시간 귓속말 (통화 중 지시)](#실시간-귓속말-통화-중-지시)
- [음성엔진 설정 (STT/TTS 밸브 교체)](#음성엔진-설정-stttts-밸브-교체)
- [🧠 기억의 앵커 (통화 회상 · 능동형 자동전화)](#-기억의-앵커-통화-회상--능동형-자동전화)
- [📍 위치 확인 (NAVER + 카카오)](#-위치-확인-naver--카카오)
- [Ollama 임베딩 자동 설정 (WSL2)](#ollama-임베딩-자동-설정-wsl2)
- [월 통화시간 제한 (요금 보호)](#월-통화시간-제한-요금-보호)
- [Twilio 자동 설정](#twilio-자동-설정)
- [Cloudflare Tunnel 설정 (외부 HTTPS 접속)](#cloudflare-tunnel-설정-외부-https-접속)
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
| 🎙️ 진짜 실시간 대리통화 | Twilio Media Streams로 말하는 **도중에도 즉시 끼어들기(barge-in)**. Deepgram(STT)+ElevenLabs(TTS), 밸브에서 엔진 교체 |
| 🤫 실시간 귓속말 | AI가 상대와 통화하는 도중 관리자가 텔레그램/앱으로 **"이렇게 말해"** 지시 → AI가 다음 발화에 자연스럽게 반영 |
| 🧠 기억의 앵커 | 통화 내용을 전화번호별로 임베딩 저장 → 다음 통화 때 **비슷한 시간대·날씨의 과거 기억을 자동 회상**해 대화 유도. 조건 맞으면 능동적으로 안부전화 제안(선택) |
| 📍 위치 확인 (NAVER + 카카오) | 안부전화 중 상대방 **동의를 받은 뒤** 위치를 물어보고, 말로 알려준 위치를 지도 이미지와 함께 **텔레그램으로 보고**. NAVER 지오코딩(도로명·지번 주소) + 카카오 로컬(역명·상호·건물명) 병행으로 폭넓게 검색. 휴대폰 GPS를 몰래 수집하지 않음 |
| 📇 스마트 연락처 | 이름으로 문자·전화(번호 자동 조회), 연락처 수정·삭제, 15개씩 페이지 조회 |
| 📅 캘린더 (조회·등록·수정·삭제) | 일정 조회·등록에 더해 **수정·삭제**까지. 전화·문자 알림도 시각 변경 시 자동 재예약 |
| ✋ 끼어들기 | 통화 중 AI 말에 끼어들면 즉시 멈추고 새 질문에 집중 |
| ☎️ 상담원 연결 | 0번 키패드 또는 음성으로 관리자(사람)에게 직통 연결 (개별 토글) |
| ⏱️ 월 통화시간 제한 | 관리자 수신전화 월 사용량 제한(기본 300분). 90%에 텔레그램 경고, 초과 시 차단, 매달 21일 초기화 |
| 💬 Telegram 봇 | 텔레그램에서 OpenWebUI와 대화, 파일 색인, 예약, **음성 메시지(STT)**, **검색 출처 링크 표시** |
| 🤖 브라우저 에이전트 | AI가 웹사이트를 탐색·스크린샷·데이터 추출 |
| 📚 RAG | 업로드한 문서를 기반으로 답변 |
| 🔒 보안 강화 | 컨테이너 하드닝, Docker Secrets, CVE 패치, 번호 기반 통화 인증, **전화번호 유출 방지** |
| ⚡ Twilio 자동 설정 | 설치 시 Voice·SMS·Status Callback URL을 Twilio API로 **자동 구성** |

---

## 두 가지 운영 모드

용도에 따라 **개인용** 또는 **고객 상담용**으로 동작합니다.

| 모드 | 성격 | 모르는 번호가 전화하면 | 캘린더·명령 |
|------|------|----------------------|-------------|
| **개인용 (personal)** | 지인 안부·대리전화 비서 | AI가 지인 안부체로 응대 (상담원 안내 없음) | 관리자만 |
| **고객 상담용 (customer)** | 고객 상담 응대 | AI가 일반 상담 응대 (0번 상담원 연결 안내 ON) | 관리자만 (고객 접근 불가) |

> 두 모드 모두 **캘린더·SMS·명령 등 민감 기능은 관리자(설치 시 입력한 번호)만** 사용할 수 있습니다. 고객 상담 모드에서 고객이 "오늘 일정"을 말해도 캘린더에는 접근할 수 없습니다.

### 모드 선택 방법 — 설치 첫 화면 + 언제든 전환

`start-openwebui-customer-support.sh`는 **설치를 시작하면 가장 먼저** 용도를 묻습니다.

```
🎯 어떤 용도로 설치하시겠습니까?
   1) 고객 상담용 (Customer)
   2) 개인용 AI 비서 (Personal)
선택 (1/2) [기본값: 1=고객상담용]:
```

- **1(또는 Enter)** → 고객 상담용으로 설치
- **2** → 개인용 AI 비서로 설치

여기서 고른 값은 `twilio-bot/ai_config.py`의 **`SERVICE_MODE`** 에 자동 반영됩니다. 설치가 끝난 뒤에도 이 한 줄만 바꾸면 **재설치 없이** 두 모드를 서로 전환할 수 있습니다.

```bash
cd ~/OpenWebUI
nano twilio-bot/ai_config.py
#   SERVICE_MODE = "customer"   ← 고객 상담용
#   SERVICE_MODE = "personal"   ← 개인용
docker compose restart twilio-bot
```

`SERVICE_MODE`를 바꾸면 아래 항목이 한 번에 조정됩니다.

| 항목 | `customer` | `personal` |
|------|-----------|-----------|
| 걸려온 전화 응대 성격 | 고객 상담체 | 지인 안부체 |
| 기본 인사말 | 상담체 | 안부체 |
| 상담원 0번 안내 멘트(`OPERATOR_HINT_ENABLED`) | ON | OFF |
| AI 역할 라벨(`AI_ROLE`) | 고객 상담 어시스턴트 | 개인 전화 어시스턴트 |
| 전화 RAG 검색 범위 | 분리 검색(.env 기본값 따름) | 통합 검색 자동 전환(전화·웹·텔레그램 같은 문서) |
| 능동형 자동전화(기억의 앵커) | 사용 안 함(기본) | 켤 수 있음(`MEMORY_AUTOCALL_ENABLED`) |

> `SERVICE_MODE`가 바꾸는 것은 "응대 성격·인사말·상담원 안내"의 **기본 묶음**입니다. 각 세부 항목(상담원 연결, 자동전화 등)은 `ai_config.py`에서 개별적으로 다시 미세조정할 수 있습니다. 개별 설정을 직접 지정하면 그 값이 우선합니다.

> **전화 RAG 검색 범위 자동 전환:** 분리 검색으로 설치했더라도 `SERVICE_MODE = "personal"` 로 바꾸면, `.env` 를 고치지 않아도 전화봇이 통합 검색(전화·웹·텔레그램이 같은 문서를 참조)으로 자동 전환됩니다. `customer` 로 두면 설치 시 정한 `.env` 기본값을 그대로 따릅니다. `docker compose restart twilio-bot` 후 적용됩니다.

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

**하나의 스크립트로 개인용·고객 상담용을 모두** 설치할 수 있습니다. 실행하면 첫 화면에서 용도를 물어봅니다.

```bash
wget https://YOUR-HOST/start-openwebui-customer-support.sh
less start-openwebui-customer-support.sh    # 실행 전 내용 검토 권장
chmod +x start-openwebui-customer-support.sh
./start-openwebui-customer-support.sh
```

실행하면 **가장 먼저** 용도를 선택합니다(자세히는 [두 가지 운영 모드](#두-가지-운영-모드) 참고).

```
🎯 어떤 용도로 설치하시겠습니까?
   1) 고객 상담용 (Customer)
   2) 개인용 AI 비서 (Personal)
```

> 순수 개인용(고객 상담 경로 없음)만 원하면 `start-openwebui-hardened-admin-only.sh`를 대신 실행할 수도 있습니다. 다만 위 스크립트에서 **2(개인용)** 를 골라도 개인용으로 설치됩니다.

설치 중 입력 항목 (순서대로):

| 항목 | 예시 | 설명 |
|------|------|------|
| **서비스 모드** | `1` / `2` | **가장 먼저 질문** — 1=고객 상담용, 2=개인용. `ai_config.py`의 `SERVICE_MODE`에 반영되며 나중에 전환 가능 |
| 나의 전화번호 | `+821012345678` | **관리자 번호** (봇에게 전화 걸 권한). 쉼표로 여러 개 가능 |
| Twilio 정보 | SID / Token / 번호 | 전화 기능용 |
| 서버 도메인 | `https://yourdomain.com` | Twilio Webhook용 |
| 관리자 이메일 / 비밀번호 | — | OpenWebUI 로그인용 |
| AI 모드 | `2` | 1=OpenWebUI, 2=Groq, 3=포워딩 |
| 연락처 | `김철수,+821011112222` | 봇이 **전화 걸 대상** (통화 권한과 무관) |
| RAG 검색 모드 | `1` / `2` | 1=통합, 2=분리. 기본값은 서비스 모드에 맞춰 자동 추천(개인용→통합, 고객용→분리) |
| 진짜 실시간 모드 | `y` / `N` | `y`면 Deepgram·ElevenLabs 키 입력(유료). `N`(기본)이면 기존 방식, 나중에 켤 수 있음 |
| 텔레그램 보고 | `y` / `N` | `y`면 봇 토큰·채팅 ID 입력 → 안부·수신전화 보고가 문자뿐 아니라 텔레그램으로도 옴. `N`(기본)이면 문자 보고만 |
| NAVER 위치 확인 | `y` / `N` | `y`면 NAVER Maps Client ID·Secret 입력 → 안부전화 중 위치 확인·지도 보고 활성화. 이어서 (선택) 카카오 REST API 키를 넣으면 "강남역" 같은 역명·상호도 검색. `N`(기본)이면 위치 기능 미사용 |

> **관리자 PIN 6자리를 설정합니다.** 설치 중 "관리자 PIN 6자리 입력"에서 직접 정하거나 Enter를 누르면 자동 생성됩니다(자동 생성 시 화면에 표시되니 꼭 메모하세요). 이 PIN은 통화에서 **민감 명령**(연락처 저장·전화 걸기·문자·예약)을 실행할 때만 확인하며, 일반 대화나 "오늘 일정" 같은 조회에는 묻지 않습니다. 통화당 한 번 인증하면 그 통화 내내 유효합니다. 자세한 내용은 [통화 인증](#통화-인증-보안) 참고.

> **🎙️ 진짜 실시간 모드는 선택입니다.** 설치 중 "진짜 실시간 모드를 켜시겠습니까? (y/N)"에서 `N`(또는 Enter)을 누르면 **기존 방식 그대로** 설치됩니다. 나중에 `.env`의 `REALTIME_MODE=true`로 언제든 켤 수 있습니다. 자세한 내용은 [진짜 실시간 대리통화](#진짜-실시간-대리통화-media-streams) 참고.

> **📨 텔레그램 보고도 선택입니다.** "텔레그램 보고 알림을 설정하시겠습니까? (y/N)"에서 값을 넣으면 통화 보고가 텔레그램으로도 옵니다. 건너뛰어도 문자(SMS) 보고는 정상 작동합니다. 자세한 준비 방법은 [채널별 사용법](#채널별-사용법)의 텔레그램 항목 참고.

> **📍 위치 확인도 선택입니다.** "NAVER 지도 위치 확인 기능을 사용하시겠습니까? (y/N)"에서 `y`를 누르면 NAVER Maps 키를 입력받아 위치 확인 기능이 켜집니다. 이어서 카카오 REST API 키를 넣으면 역명·상호까지 검색됩니다(선택). 위치 보고는 **텔레그램**으로 지도 이미지와 함께 오므로, 위치 기능을 쓰려면 텔레그램 보고를 함께 설정하는 것을 권합니다. 자세한 내용은 [위치 확인 (NAVER + 카카오)](#-위치-확인-naver--카카오) 참고.

설치가 끝나면 OpenWebUI, 전화 봇, RAG, 실시간 음성 서버 등 전체 스택이 자동으로 뜨고 **도구 13개(캘린더·실시간 귓속말·음성엔진 설정·기억의 앵커·NAVER 위치 확인 포함)가 자동 등록**됩니다.

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

### 일정 알림을 전화·문자로 받기 (`TWILIO_BOT_SECRET`)

일정에 "N분 전 알림"을 걸고 그 알림을 **전화·문자로** 받으려면, 캘린더 도구 밸브의 `TWILIO_BOT_SECRET` 칸에 `.env`의 **`API_SECRET`** 값을 넣어야 합니다. (비워두면 알림 전화·문자 예약을 건너뜁니다.)

**API_SECRET 값 찾는 법:**

```bash
# .env 에서 API_SECRET 값 확인 (이 값을 밸브에 붙여넣기)
grep API_SECRET ~/OpenWebUI/.env
```

출력 예시:
```
API_SECRET=abcd1234efgh5678...
```

`=` 뒤의 값(`abcd1234...`)을 복사해서:

**워크스페이스 → 도구 → "캘린더 (조회·등록·수정·삭제)" → ⚙️ 밸브 → `TWILIO_BOT_SECRET`** 에 붙여넣고 저장하면 됩니다.

> 정리: 캘린더 도구 밸브에는 키가 **두 개** 들어갑니다.
> - `OPENWEBUI_API_KEY` ← OpenWebUI에서 발급한 API 키 (일정 조회용)
> - `TWILIO_BOT_SECRET` ← `.env`의 `API_SECRET` 값 (알림 전화·문자 예약용)

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

### 브라우저 에이전트 접속 키 (`BROWSER_AGENT_API_KEY`)

브라우저 에이전트 서비스에 접속하거나 도구가 에이전트를 호출할 때 쓰는 인증 키는 설치 시 `.env`에 자동 생성됩니다. 값이 필요하면 아래로 확인합니다.

```bash
# AI 브라우저 에이전트 API Key 확인
grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env
```

출력 예시:
```
BROWSER_AGENT_API_KEY=xyz9876abcd...
```

`=` 뒤의 값을 복사해서 사용하면 됩니다. (캘린더 조회용 `OPENWEBUI_API_KEY`와는 **다른 값**입니다.)

> 정리: `.env`에서 자주 찾게 되는 키 3가지
> - `OPENWEBUI_API_KEY` — OpenWebUI에서 발급 (캘린더 조회용, .env에는 없을 수 있음)
> - `API_SECRET` — 전화 봇 시크릿 (캘린더 알림 예약용 `TWILIO_BOT_SECRET`에 입력)
> - `BROWSER_AGENT_API_KEY` — 브라우저 에이전트 접속용

---

## 통화 인증 (보안)

### 통화 인증 — 등록된 관리자 번호 + 민감 명령 시 PIN 6자리

통화 인증은 두 단계로 작동합니다.

1. **번호 인증** — 등록된 관리자 번호(`ADMIN_NUMBERS`)로 건 전화만 관리자 권한을 얻습니다. 개인용 모드에서 모르는 번호는 즉시 차단되고, 고객 상담용 모드에서는 일반 AI 상담으로 연결됩니다.
2. **PIN 확인 (민감 명령 한정)** — 관리자라도 **민감 명령**(연락처 저장·전화 걸기·문자·예약)을 실행할 때만 6자리 PIN을 한 번 확인합니다. 일반 대화나 "오늘 일정" 같은 조회에는 PIN을 묻지 않습니다. 통화당 1회 인증하면 그 통화 내내 유효합니다.

PIN은 설치 시 직접 정하거나 Enter로 자동 생성합니다. **3회 틀리면 30분간 잠깁니다**(자동 해제).

**왜 이렇게 하나:** 번호 인증만으로도 외부인은 걸러지지만, 발신번호 위조(스푸핑) 등에 대비해 실제 돈·정보가 오가는 민감 명령에는 PIN을 한 겹 더 둡니다. 반대로 조회·잡담에는 PIN을 묻지 않아 평소 사용이 번거롭지 않습니다.

> PIN 확인 자체를 끄려면 `ai_config.py`에서 `ADMIN_PIN_REQUIRED = False`로 두고 `docker compose restart twilio-bot` 하세요. 이 경우 등록된 관리자 번호만으로 민감 명령까지 바로 실행됩니다. ⚠️ 다만 발신번호 위조(스푸핑) 시 관리자로 위장해 전화·문자·예약이 실행될 수 있으므로, PIN을 끄는 것은 권장하지 않습니다.

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

## 통화 기능 (끼어들기 · 상담원 연결)

전화 통화의 자연스러움과 사람 연결을 `ai_config.py`에서 조절합니다. 수정 후 `docker compose restart twilio-bot`으로 적용합니다.

### 끼어들기 (barge-in)

AI가 말하는 도중 상대방이 끼어들면, AI가 즉시 멈추고 맞장구친 뒤 새 질문에 집중합니다. 사람과 통화하듯 자연스럽습니다.

| 설정 | 기본값 | 설명 |
|------|--------|------|
| `BARGEIN_THRESHOLD` | `0.6` | 민감도(0~1). 클수록 잘 끼어듦. 0.4=둔감(소음 환경 권장) |
| `BARGEIN_MIN_SECONDS` | `3.0` | 이보다 짧은 답변은 끼어들기 무시 |
| `BARGEIN_ENABLED` | `True` | `False`면 끼어들기 처리 끔 |
| `BARGEIN_NOTE` | (지시문) | 끼어들 때 AI 반응 스타일 |

> 소음이 큰 곳에서는 잡음에 AI가 멈출 수 있습니다. `BARGEIN_THRESHOLD = 0.4`로 낮추거나 `BARGEIN_ENABLED = False`로 끄세요.

### 상담원(사람) 연결 — 0번 / 음성

외부인이 AI와 대화하다 사람(관리자)에게 연결되는 두 경로를 독립적으로 켜고 끕니다.

| 설정 | 기본값 | 설명 |
|------|--------|------|
| `OPERATOR_TRANSFER_ENABLED` | `True` | 키패드 **0번** 연결 |
| `OPERATOR_VOICE_ENABLED` | `True` | 음성 "담당자" 연결 |
| `OPERATOR_HINT_ENABLED` | `True` | "0번 눌러주세요" 안내 멘트 |
| `OPERATOR_VOICE_KEYWORDS` | (목록) | 음성 연결 키워드 (추가/삭제 가능) |

조합 예시:

```python
# 완전 무인 AI 응대 (사람 연결 모두 끔)
OPERATOR_TRANSFER_ENABLED = False
OPERATOR_VOICE_ENABLED    = False

# 음성 키워드 늘리기
OPERATOR_VOICE_KEYWORDS = ["담당자", "상담원", "직원", "사람"]
```

> 사람 연결을 모두 꺼도 외부인은 **AI 상담을 계속** 받고, 통화 후 관리자 자동 보고도 작동합니다. 캘린더 등 민감 기능은 항상 관리자 전용입니다.

---

## 진짜 실시간 대리통화 (Media Streams)

기본 통화는 "한 문장씩 주고받기"(Twilio Gather) 방식입니다. **진짜 실시간 모드**를 켜면 Twilio Media Streams로 통화 오디오를 통째로 받아, **상대가 말하는 도중에도 AI가 즉시 반응하고 끼어들 수 있는** 진짜 실시간 대화가 됩니다.

| 구분 | 기존 방식 (기본) | 진짜 실시간 모드 |
|------|----------------|----------------|
| 방식 | 한 문장 말하고 → AI 답 (turn-based) | 오디오 스트리밍 (Media Streams) |
| 끼어들기 | 문장 단위 | 말하는 **도중** 즉시 (barge-in) |
| 엔진 | Twilio 내장 STT/TTS | Deepgram(STT) + ElevenLabs(TTS) |
| 필요 조건 | 없음 | 공개 HTTPS 도메인 + 유료 API 키 |
| 비용 | Twilio 통화료만 | + Deepgram·ElevenLabs 사용료 |

### 켜는 법

**설치할 때**: "진짜 실시간 모드를 켜시겠습니까? (y/N)"에서 `y` → Deepgram·ElevenLabs 키 입력.

**나중에 켜기**:

```bash
cd ~/OpenWebUI
nano .env
# REALTIME_MODE=false  →  true 로 변경
# DEEPGRAM_API_KEY=... 와 ELEVENLABS_API_KEY=... 를 채움 (또는 아래 음성엔진 밸브로 입력)
docker compose up -d
```

### 필수 조건 (중요)

- **공개 HTTPS 도메인**이 반드시 필요합니다(`SERVER_DOMAIN`이 `https://...`). Twilio가 `wss://도메인/twilio-stream`으로 접속해야 하기 때문입니다. `localhost`로는 실시간이 동작하지 않으며, 이 경우 **자동으로 기존 방식으로 폴백**됩니다.
- Cloudflare Tunnel을 쓰면 공개 HTTPS 도메인을 쉽게 확보할 수 있습니다([Cloudflare Tunnel 설정](#cloudflare-tunnel-설정-외부-https-접속) 참고).

### 동작 원리

```
전화 → twilio-bot이 REALTIME_MODE 확인 → <Connect><Stream> TwiML 반환
     → Twilio가 wss://도메인/twilio-stream 접속 (nginx가 realtime-voice로 프록시)
     → realtime-voice: 상대 음성 → Deepgram(STT) → LLM → ElevenLabs(TTS) → 되돌려 재생
     → 상대가 말을 시작하면 AI가 즉시 멈춤(barge-in)
```

`realtime-voice`는 별도 컨테이너로 설치되며, 실시간을 안 켜도 유휴 상태로 무해하게 대기합니다. 완전히 끄려면 `docker compose stop realtime-voice`.

### 튜닝 (통화가 어색할 때)

실제 통화 품질(지연·끊김·끼어들기 민감도)은 `realtime-voice/realtime_server.py`에서 조정합니다.

| 값 | 설명 |
|----|------|
| Deepgram `endpointing=300` | 상대가 말을 멈춘 뒤 "문장 끝"으로 보는 시간(ms). 크게=신중, 작게=빠름 |
| ElevenLabs `optimize_streaming_latency` | 지연 최소화 강도 |
| LLM `max_tokens=120` | 통화 답변 길이(짧게 유지) |

> 로그로 상대 발화·AI 응답·끼어들기를 확인: `docker compose logs -f realtime-voice`

---

## 실시간 귓속말 (통화 중 지시)

AI가 상대방과 통화하는 **도중에**, 관리자가 텔레그램이나 OpenWebUI 채팅/앱으로 **"이렇게 말해: ○○○"** 라고 지시하면 AI가 그 지시를 **다음 발화에 자연스럽게 녹여서** 말합니다. (AI라거나 지시받았다는 티는 내지 않습니다.)

> 기본 방식(turn-based)에서도 작동하며, 진짜 실시간 모드에서는 반영이 훨씬 빠릅니다.

### 텔레그램으로 지시

텔레그램 봇에게 아래 형식으로 메시지를 보냅니다(즉시 반영).

| 입력 | 동작 |
|------|------|
| `이렇게 말해: 곧 찾아뵙겠다고 전해줘` | 그 내용을 다음 발화에 반영 |
| `귓속말: 목소리 톤을 더 밝게` | 스타일 지시 |
| `김철수 이렇게 말해: 다음 주에 연락한다고 해` | 통화가 여러 개일 때 **대상 지정** |
| `/calls` 또는 `통화목록` | 진행 중 통화 목록 확인 |

> 텔레그램 실시간 지시는 `.env`의 `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID`가 설정돼야 하며, 등록된 관리자 채팅만 지시할 수 있습니다. (미설정이어도 아래 OpenWebUI 도구로는 바로 사용 가능)

### OpenWebUI 채팅/앱으로 지시

**"실시간 귓속말"** 도구를 사용합니다.

- "지금 통화 중이야?" → 진행 중 통화 목록
- "곧 방문한다고 전해줘" → AI가 다음 발화에 반영
- 대기 중인 지시 취소도 가능

---

## 음성엔진 설정 (STT/TTS 밸브 교체)

진짜 실시간 통화에서 쓰는 **STT(음성인식)/TTS(음성합성) 제공자·API 키·음성**을 OpenWebUI 밸브(⚙️ 설정)에서 바꿉니다. 캘린더 도구처럼 톱니바퀴 설정창에 값을 넣으면 됩니다.

### 설정 순서

1. OpenWebUI → **워크스페이스 → 도구 → "음성엔진 설정 (실시간 STT/TTS)" → ⚙️ 밸브** 클릭
2. 아래 값을 입력하고 **저장**

| 밸브 항목 | 설명 | 기본값 |
|----------|------|--------|
| `STT_PROVIDER` | 음성인식 제공자 | `deepgram` |
| `DEEPGRAM_API_KEY` | 음성인식 API 키 | (비움) |
| `STT_MODEL` | 음성인식 모델 | `nova-2` |
| `TTS_PROVIDER` | 음성합성 제공자 (`elevenlabs` 또는 `deepgram`) | `elevenlabs` |
| `ELEVENLABS_API_KEY` | 음성합성 API 키 (TTS가 deepgram이면 Deepgram 키) | (비움) |
| `TTS_VOICE` | 음성 ID (ElevenLabs 음성 ID 등) | Rachel |
| `TTS_MODEL` | 음성합성 모델 | `eleven_flash_v2_5` |
| `LANGUAGE` | 통화 언어 (ko/en/ja/zh) | `ko` |

3. **저장하면 즉시 자동 반영**됩니다. (OpenWebUI가 저장 시 도구를 재초기화하면서 서버에 반영)
4. 다음 통화부터 새 엔진으로 작동합니다.

> 확인하려면 채팅에서 "지금 음성엔진 설정 보여줘" → 현재 STT/TTS와 음성 표시(API 키는 `abcd***yz`로 가려짐).
>
> 혹시 저장 즉시 반영이 안 되는 것 같으면 채팅에서 "음성엔진 설정 적용해줘"를 한 번 실행하면 확실히 동기화됩니다.

---

## 🧠 기억의 앵커 (통화 회상 · 능동형 자동전화)

통화 내용을 **전화번호별로 임베딩해 벡터DB(Qdrant)에 저장**해 두었다가, 다음에 같은 사람과 통화할 때 **지금과 비슷한 조건(시간대·날씨)의 과거 기억을 자동으로 떠올려** 대화를 자연스럽게 이어갑니다.

예: 비 오는 저녁에 우울하다고 했던 사람에게, 다음 비 오는 저녁 통화에서 AI가 "지난번에 힘들다고 하셨는데 좀 어떠세요?" 하고 먼저 안부를 챙깁니다.

### 저장 (자동)

통화가 끝나면 자동으로 저장됩니다. 별도 설정 없이 작동합니다.

- 저장 정보: 전화번호·이름·날짜·**시간대**(아침/점심/오후/저녁/밤)·**날씨**·**감정**·**주제**·요약·대화 원문
- 감정·주제·요약은 AI가 통화 내용에서 자동 추출
- 대리전화·수신전화·실시간 통화 **모두** 저장됨

> 저장 품질은 **Ollama 임베딩**에 달려 있습니다. Ollama가 연결돼야 "의미가 비슷한 기억"을 정확히 찾습니다. (아래 [Ollama 자동 설정](#ollama-임베딩-자동-설정-wsl2) 참고)

### 회상 (통화 중 자동)

다음 통화 초반에, 전화번호로 그 사람의 과거 기억을 검색하고 **지금 시간대·날씨와 맞는 것에 가산점**을 줘서 가장 관련 있는 기억을 AI에게 전달합니다. AI는 그걸 자연스럽게 대화에 녹입니다(AI라거나 기록을 봤다는 티는 내지 않음).

### 수동 조회 (도구)

OpenWebUI 채팅에서 **"기억의 앵커"** 도구로 직접 검색할 수 있습니다.

- "김철수랑 예전에 무슨 얘기했지?" → 과거 통화 기억 목록
- "지난번 통화에서 이직 얘기 찾아줘" → 주제로 검색

### 능동형 자동전화 (선택 · 기본 꺼짐)

조건이 맞으면 **시스템이 먼저 안부전화를 제안하거나 발신**하게 할 수 있습니다. `ai_config.py`에서 켭니다.

```python
# twilio-bot/ai_config.py
MEMORY_AUTOCALL_ENABLED = False     # ← True 로 바꾸면 능동형 켜짐 (기본 꺼짐)
MEMORY_AUTOCALL_MODE = "suggest"    # suggest=관리자에게 제안 / auto=자동 발신
MEMORY_AUTOCALL_HOURS = [10, 20]    # 발신 허용 시간대 (10시~20시, 새벽 방지)
MEMORY_AUTOCALL_COOLDOWN_DAYS = 7   # 같은 사람 최소 7일 간격 (과다 방지)
MEMORY_AUTOCALL_MATCH = ["time_slot", "weather"]  # 시간대+날씨가 과거와 맞아야 발동
MEMORY_AUTOCALL_MAX_PER_DAY = 3     # 하루 최대 횟수 (요금 방지)
```

바꾼 뒤 `docker compose restart twilio-bot`.

| 모드 | 동작 |
|------|------|
| `suggest` (기본·안전) | 조건 맞으면 관리자에게 텔레그램/문자로 "지금 ○○님께 전화 걸기 좋은 타이밍" 알림 → 관리자가 직접 발신 |
| `auto` | 조건 맞으면 곧바로 자동 안부전화 발신 (요금·빈도 주의) |

> **안전장치 4중**: 마스터 OFF 기본 · 발신 허용 시간대 · 사람당 쿨다운 · 하루 상한. 처음엔 `suggest`로 며칠 관찰한 뒤 `auto`로 올리는 것을 권장합니다.

---

## 📍 위치 확인 (NAVER + 카카오)

안부전화 중 상대방에게 **위치를 물어보고, 동의를 받은 경우** 말로 알려준 위치를 지도 이미지와 함께 **텔레그램으로 보고**하는 기능입니다. (13번째 도구로도 등록되어, 통화 없이 특정 장소의 위치·지도를 조회할 수도 있습니다.)

> ⚠️ **프라이버시:** 이 기능은 **상대방이 통화에서 말로 알려준 위치**만 사용합니다. 휴대폰 GPS를 몰래 수집하지 않습니다. 전화만으로 상대방 단말의 GPS를 가져오는 것은 기술적으로 불가능하며, 위치 확인·보고 사실을 상대방에게 안내하고 동의를 받은 경우에만 사용하는 것을 전제로 합니다.

### 동작 흐름

```
안부전화 중 위치 확인 시작
  ↓
"관리자가 현재 위치를 여쭤보라고 하셨습니다. 위치를 알려주실 수 있으실까요?
 동의하시면 예, 알려주기 어려우시면 아니요라고 답해주세요."
  ↓
[상대가 "예"] → "지금 어디에 계신지 말씀해 주세요"
      ↓  (상대가 "역삼동", "강남역" 등으로 답)
   NAVER 지오코딩 시도 → 실패 시 카카오 로컬 검색으로 폴백
      ↓  좌표 확인 → NAVER 지도 이미지 생성
   📨 관리자 텔레그램으로 지도 이미지 + 주소 전송
[상대가 "아니요"] → 위치 확인 건너뛰고 안부 대화 계속
```

- **동의 질문은 최대 2번까지만** 반복합니다(무응답 시 무한 반복 방지). 2번 안에 예/아니요가 확인되지 않으면 위치 확인을 건너뜁니다.
- **위치 확인이 주 목적인 통화**("○○ 위치 물어봐줘")면 위치를 받은 뒤 정중히 통화를 마칩니다.
- **안부전화 중 위치도 물어본 경우**면 위치를 받은 뒤에도 안부 대화를 계속 이어갑니다.

### NAVER + 카카오 병행 검색

두 지도 서비스를 함께 써서 폭넓게 찾습니다.

| 검색 대상 | NAVER 지오코딩 | 카카오 로컬 |
|-----------|:-------------:|:-----------:|
| 도로명·지번 주소 (예: 세종대로 110) | ✅ | ✅ |
| 역명·상호·건물명 (예: 강남역, ○○병원) | ❌ | ✅ |

- 먼저 **NAVER 지오코딩**으로 시도(도로명·지번 주소에 정확).
- 못 찾으면 **카카오 로컬 키워드 검색**으로 폴백(역명·상호·건물명까지).
- 지도 이미지는 NAVER Static Map을 사용합니다.

> NAVER는 지역검색(Local) API 제공을 종료해 역명·상호는 지오코딩으로 찾지 못합니다. 그래서 카카오 로컬 검색을 폴백으로 두면 "강남역" 같은 답변도 좌표로 변환됩니다. 카카오 키가 없으면 도로명·지번 주소만 인식하며, 못 찾을 경우 상대에게 "가까운 동 이름이나 큰 건물, 도로명으로 다시 말씀해 주세요"라고 되묻습니다.

### 준비물 — API 키 발급

**1) NAVER Maps (필수)** — 위치 조회 + 지도 이미지
1. [NAVER Cloud Platform](https://console.ncloud.com) 로그인 → 상단 검색창에서 **Maps** 검색 → 서비스 진입
2. **Application 등록** → **Geocoding**, **Static Map** 이용 신청
3. **인증 정보**에서 **Client ID**와 **Client Secret** 확인
   - API 호출 도메인은 `maps.apigw.ntruss.com`을 사용합니다(구 `naveropenapi.apigw.ntruss.com` 아님).
   - Geocoding·Static Map은 각각 월 넉넉한 무료 사용량이 제공됩니다.

**2) 카카오 REST API (선택 · 역명 검색용)**
1. [Kakao Developers](https://developers.kakao.com) 로그인 → **내 애플리케이션 → 애플리케이션 추가하기**
2. 만든 앱 → **앱 키**에서 **REST API 키** 복사
3. 왼쪽 **카카오맵** 메뉴 → **활성화 설정 ON**
   - 카카오 로컬 API는 하루 넉넉한 무료 호출을 제공하며, 결제수단 등록이 필요 없습니다.

### 키 입력 — 설치 중 또는 나중에

설치 중 "NAVER 지도 위치 확인 기능을 사용하시겠습니까?"에서 `y`를 누르고 NAVER Client ID·Secret과 (선택) 카카오 REST API 키를 입력하면 됩니다. 키는 **Docker Secrets 파일**로 안전하게 저장됩니다.

나중에 켜거나 키를 바꾸려면 secrets 파일을 직접 넣고 재기동합니다.

```bash
cd ~/OpenWebUI
# NAVER
echo -n "발급받은_NAVER_Client_ID"     >  secrets/naver_maps_client_id       2>/dev/null || true
echo -n "발급받은_NAVER_Client_Secret" >  secrets/naver_maps_client_secret
# 카카오(선택)
echo -n "발급받은_카카오_REST_API_키"   >  secrets/kakao_rest_api_key
# .env 에서 위치 기능 on (없으면 추가)
grep -q NAVER_LOCATION_ENABLED .env || echo "NAVER_LOCATION_ENABLED=true" >> .env
docker compose up -d --build twilio-bot
```

> `NAVER_MAPS_CLIENT_ID`는 `.env`(환경변수), `Secret`과 카카오 키는 `secrets/` 파일로 관리됩니다. 코드가 환경변수 → secrets 파일 순으로 읽으므로, gunicorn 워커가 환경을 상속하지 못하는 경우에도 파일에서 안전하게 불러옵니다.

### 확인

실행 중인 봇에 직접 요청해 동작을 확인합니다(위치 조회 + 텔레그램 지도 전송).

```bash
docker exec twilio-bot python3 -c "
import requests
sec = open('/run/secrets/api_secret').read().strip()
r = requests.post('http://localhost:5000/naver-location',
    headers={'X-API-Secret': sec, 'Content-Type':'application/json'},
    json={'place':'서울특별시 중구 세종대로 110', 'report_to_telegram':True, 'contact_name':'테스트'}, timeout=20)
print(r.status_code); print(r.text[:300])
"
```

`ok:true`와 주소가 나오고 텔레그램에 지도 이미지가 오면 정상입니다.

---

## Ollama 임베딩 자동 설정 (WSL2)

기억의 앵커·연락처 의미검색은 **Ollama 임베딩**(`nomic-embed-text`, 768차원)을 사용합니다. 설치 스크립트가 다음을 **자동 처리**합니다:

- Ollama 설치 및 임베딩 모델 다운로드
- **`OLLAMA_HOST=0.0.0.0` 바인딩** — Docker 컨테이너가 호스트 Ollama에 접근하도록 (WSL2의 흔한 함정 자동 해결)
- 컨테이너→호스트 접근 IP 자동 감지 + 연결 테스트

설치 중 이런 메시지가 뜨면 정상입니다:
```
✅ Ollama 접근 확인됨 (172.17.0.1:11434) — 기억의 앵커/의미검색 정상 작동
```

**확인 방법** (설치 후):
```bash
docker compose exec twilio-bot python3 -c "import ollama,os; c=ollama.Client(host=os.getenv('OLLAMA_BASE_URL')); print('OK', len(c.embeddings(model='nomic-embed-text', prompt='테스트')['embedding']), '차원')"
```
`OK 768 차원`이 나오면 완벽합니다.

> Ollama 연결이 안 되면 저장은 되지만(더미 벡터) 회상 품질이 낮아집니다. 로그에서 `⚠️ Ollama 임베딩 실패 — 더미 벡터`가 보이면 WSL2 안에서 `OLLAMA_HOST=0.0.0.0:11434 ollama serve`로 실행하세요.

---

## 월 통화시간 제한 (요금 보호)

관리자가 Twilio 번호로 **직접 전화를 거는** 통화의 월 누적 시간을 제한해, 통화 요금이 예상치 못하게 커지는 것을 막습니다. (봇이 거는 발신전화나, 관리자가 받는 알림 전화는 집계 대상이 아닙니다.)

- 월 한도(기본 300분)를 넘으면 → 다음 주기까지 관리자 수신전화 차단
- 90%(기본 270분) 도달 시 → **텔레그램으로 경고 1회** (텔레그램 미설정 시 SMS 폴백)
- 100% 도달 시 → 텔레그램 알림 + 이후 통화 차단
- **매달 21일**에 자동 초기화 (7/21~8/20 = 한 주기)

`ai_config.py`에서 값을 조절합니다.

```python
MONTHLY_INBOUND_CALL_LIMIT_MIN = 300   # 월 한도(분), 0이면 무제한
MONTHLY_CALL_WARN_PERCENT      = 90    # 경고 시점(%)
MONTHLY_CALL_LIMIT_ENABLED     = True  # 기능 on/off
```

> ⚠️ 이 기능이 작동하려면 Twilio 번호의 **Status Callback URL**이 설정되어야 합니다. 아래 "Twilio 자동 설정"이 처리하므로 보통 별도 작업이 필요 없습니다.

---

## Twilio 자동 설정

설치 중 Twilio 인증정보와 공개 도메인(`https://...`)이 준비되면, 전화번호의 웹훅을 **자동으로 구성**합니다. Twilio Console에서 수동으로 URL을 입력할 필요가 없습니다.

자동 설정되는 항목:

- **Voice URL** — `https://<도메인>/voice` (전화 받기)
- **SMS URL** — `https://<도메인>/sms-incoming` (문자 답장 자동 전달)
- **Status Callback URL** — `https://<도메인>/call-status` (월 통화시간 집계)

설정이 잘 됐는지 확인:

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

세 URL이 모두 `https://<도메인>/...`로 나오면 자동 설정 완료입니다. 자동 설정이 실패하면 설치 로그에 수동 설정 방법이 안내됩니다.

> 💡 Kali/최신 Ubuntu에서 twilio 패키지 설치가 `externally-managed-environment`로 막히면, 설치 스크립트가 `--break-system-packages` 옵션으로 자동 처리합니다. 수동 설치 시엔 `pip install twilio --break-system-packages`를 사용하세요.

---

## Cloudflare Tunnel 설정 (외부 HTTPS 접속)

Twilio가 전화·문자 webhook을 보내려면 서버가 **공개 HTTPS 주소**로 접근 가능해야 합니다. Cloudflare Tunnel을 쓰면 **포트를 열지 않고도** 안전하게 외부에서 HTTPS로 접속할 수 있습니다. (공유기 포트포워딩·고정 IP·직접 SSL 인증서가 필요 없습니다.)

### 사전 준비 (Cloudflare 대시보드에서 1회)

1. Cloudflare 계정에 도메인을 등록합니다. (예: `yourdomain.com`)
2. **Zero Trust → Networks → Tunnels → Create a tunnel** 선택
3. 터널 이름 입력 후 생성 → **터널 토큰**(긴 문자열)이 발급됩니다. 이 토큰을 복사해 둡니다.
4. **Public Hostnames**에서 도메인(`yourdomain.com`)을 내부 서비스로 연결:
   - Subdomain/Domain: `yourdomain.com`
   - Service: `http://localhost:3000` (OpenWebUI) 또는 필요에 맞게

### 설치 중 설정

설치 스크립트 실행 중 이 질문이 나오면 `y`를 선택하고 **터널 토큰**을 붙여넣습니다.

```
☁️  Cloudflare Tunnel을 설정하시겠습니까? (y/N): y
   토큰을 입력하세요: eyJhIjoi...(복사한 토큰)
```

그러면 `cloudflared`가 시스템 서비스로 설치되어 자동 실행되고, `yourdomain.com`로 외부 접속이 됩니다.

### 설치 후 나중에 설정하려면

설치 때 건너뛰었어도 언제든 추가할 수 있습니다.

```bash
# cloudflared 설치 (Debian/Ubuntu/Kali)
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
sudo mv cloudflared /usr/local/bin/ && sudo chmod +x /usr/local/bin/cloudflared

# 터널을 시스템 서비스로 설치 (토큰 방식)
sudo cloudflared service install <터널토큰>

# 상태 확인
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f    # 실시간 로그
```

### 동작 확인

```bash
# 외부에서 접속되는지 확인
curl -I https://yourdomain.com

# cloudflared 서비스 상태
sudo systemctl status cloudflared
```

`HTTP/2 200` 등이 나오면 정상입니다.

> 💡 **서버를 옮겨도 도메인은 그대로**: cloudflared는 IP가 아니라 **토큰**으로 연결됩니다. 새 서버에 같은 토큰으로 cloudflared를 설치하면 `yourdomain.com`가 자동으로 새 서버를 가리킵니다. Twilio webhook(도메인 기준)도 그대로 작동하므로 재설정이 필요 없습니다.

> ⚠️ **토큰은 비밀**입니다. 로그·캡처·저장소에 노출되지 않게 하세요. 노출됐다면 Cloudflare 대시보드에서 터널을 삭제하고 새로 발급하세요.

> Cloudflare Tunnel을 쓰면 별도 SSL 인증서(Let's Encrypt 등)가 **불필요**합니다. Cloudflare가 HTTPS를 자동 처리합니다.

---

## 채널별 사용법

### 전화

관리자 번호로 봇에 전화 → 자연어로 명령:

- "오늘 일정 알려줘" → 캘린더 음성 안내
- "김철수한테 전화해줘" → 봇이 김철수에게 전화
- "김철수한테 안부전화해줘. 잘 지내는지 물어봐줘" → 봇이 대신 안부전화 후 결과 보고
- "김철수한테 문자 보내줘" → **이름으로** SMS 발송 (번호 자동 조회)

> ⏱️ 관리자 수신전화는 월 통화시간 제한이 적용됩니다(기본 300분, 매달 21일 초기화). 조회성 명령은 통화 대신 텔레그램/채팅을 쓰면 통화 시간·요금이 들지 않습니다.

### 채팅 (OpenWebUI)

도구를 켜고 자연어로:

- "오늘 일정 알려줘" / "통화 기록 보여줘"
- "김철수한테 '내일 3시에 봬요' 문자 보내줘" → 이름으로 문자 (번호 자동 조회)
- "연락처 보여줘" → 15개씩 페이지 표시 · "연락처 2페이지" / "다음 페이지"로 이동
- "김철수 번호를 010-9999-8888로 바꿔줘" → 연락처 수정
- "12월 25일 2시 치과 등록, 알림 1시간 전" → 일정 등록(알림 포함)
- "12월 25일 회의를 오후 5시로 바꿔줘" → 일정 수정 (알림도 자동 재예약)
- "12월 25일 회의 삭제해줘" → 일정 삭제 (알림도 자동 취소)
- "지금 통화 중이야?" / "곧 방문한다고 전해줘" → **실시간 귓속말** (통화 중 AI에게 지시)
- "지금 음성엔진 설정 보여줘" → **음성엔진 설정** 도구로 STT/TTS 상태 확인
- "김철수랑 예전에 무슨 얘기했지?" → **기억의 앵커** 도구로 과거 통화 회상

### Telegram

봇에게 메시지:

- "오늘 일정 알려줘" → 캘린더 조회 (등록·수정·삭제도 가능)
- 파일(PDF/이미지) 전송 → RAG 색인
- **음성 메시지 전송** → 자동으로 텍스트 변환(STT) 후 처리 (OpenWebUI STT 엔진 설정 필요)
- 웹 검색 시 → 답변 아래 **📚 출처 상세 + 🔗 관련 링크**로 출처 URL 표시
- `/remind 매일 09:00 날씨 알려줘` → 예약
- **🤫 통화 중 실시간 귓속말**: `이렇게 말해: 곧 찾아뵙겠다고 전해줘` / `/calls`(통화목록) → [실시간 귓속말](#실시간-귓속말-통화-중-지시) 참고

> 💡 녹음 파일 없이 말로 입력하려면, 텔레그램 입력창의 음성 메시지 대신 **휴대폰 키보드의 마이크(받아쓰기)**를 쓰면 말한 내용이 글씨로 입력됩니다.

#### 📨 텔레그램 통화 보고 받기 (선택)

안부전화·수신전화 보고를 문자(SMS)뿐 아니라 텔레그램으로도 받으려면:

1. 텔레그램 `@BotFather` → `/newbot` → **봇 토큰** 발급 (`1234:ABC...` 형태)
2. 만든 봇에게 **아무 메시지나 하나 전송** (⚠️ 이걸 안 하면 봇이 당신에게 메시지를 못 보냄)
3. 채팅 ID 확인:
   ```bash
   curl -s "https://api.telegram.org/bot<봇토큰>/getUpdates" | grep -o '"id":[0-9]*' | head -1
   ```
4. 설치 중 입력하거나, 나중에 `.env`에 추가:
   ```bash
   cd ~/OpenWebUI
   echo "TELEGRAM_BOT_TOKEN=봇토큰" >> .env
   echo "TELEGRAM_CHAT_ID=채팅ID" >> .env
   docker compose up -d twilio-bot
   ```

> 보고가 안 오면 `docker compose logs twilio-bot | grep -i telegram` 으로 원인 확인 (값 누락 / chat not found / 토큰 오류 등이 로그에 표시됨).

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
- 도구 13개 등록 (캘린더·실시간 귓속말·음성엔진 설정·기억의 앵커·NAVER 위치 확인 포함)
- **캘린더 연동** — `/owui-data` 마운트, 공유 키, COMPOSE_FILE 고정
- **보안 강화** — requests/urllib3 CVE 패치, trust_env
- **통화 인증** — 관리자 번호 설정, 운영 모드 감지
- **실시간 음성** — realtime-voice 컨테이너 기동, `/twilio-stream` 프록시(실시간 모드 시)

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
| 통화 인증 | 등록된 관리자 번호 + 민감 명령 시 PIN 6자리(3회 실패 시 30분 잠금) |
| requests | `>=2.34.2` — CVE-2024-47081 (netrc 자격증명 유출) 패치 |
| urllib3 | `>=2.6.3` — CVE-2026-21441 (DoS) 패치 |
| trust_env | 캘린더 조회 시 환경 자격증명 비활성화 + 리다이렉트 차단 |
| 컨테이너 | no-new-privileges(전 서비스), cap_drop ALL(redis·qdrant·tools·twilio-bot·realtime-voice), 비루트 실행, 메모리 제한 |
| nginx 헤더 | `server_tokens off`, X-Frame-Options, X-Content-Type-Options(nosniff), Referrer-Policy, HSTS, 업로드 25MB 제한 |
| 인증 fail-closed | `API_SECRET` 미설정 시 통과가 아닌 **차단**(503). 관리 API·tools-api 공통 |
| 비밀키 | Docker Secrets로 분리 저장 |
| Twilio | 요청 서명 검증(`validate_twilio_request`), hmac 비교 |
| 캘린더 권한 | 고객 상담 모드에서도 관리자 전용으로 분리 |
| 전화번호 유출 방지 | 통화 중 AI가 관리자·연락처의 번호·개인정보를 요청받아도 정중히 거절 |
| 발신번호 은폐 | 모든 발신·착신전환에서 발신번호는 Twilio 번호로 표시(관리자 번호 비노출) |
| 포트 바인딩 | 내부 서비스(Qdrant 6333, twilio-bot 5000, realtime-voice 5001 등)는 `127.0.0.1`에만 바인딩 → 외부 접근 차단 |
| 실시간 음성 키 | STT/TTS API 키는 밸브 저장 시 마스킹 표시, `voice_config.json`에 저장(볼륨 내부) |
| 실시간 귓속말 | 등록된 텔레그램 관리자 채팅(`TELEGRAM_CHAT_ID`)만 지시 가능 |

> CVE 패치 버전은 작성 시점 기준입니다. 배포 전 최신 보안 권고를 한 번 더 확인하세요.

> Qdrant 대시보드(`localhost:6333/dashboard`)는 `127.0.0.1` 바인딩이라 **외부 인터넷에서는 접근할 수 없습니다.** 다만 서버에 로그인 가능한 사용자는 별도 인증 없이 열 수 있으므로, 여러 사용자가 접근하는 서버라면 Qdrant API 키 설정을 권장합니다.

---

## 파일 구성

```
.
├── start-openwebui-hardened-admin-only.sh   # 메인 설치 (순수 개인용 특화)
├── start-openwebui-customer-support.sh      # 메인 설치 (고객/개인 선택 · SERVICE_MODE 전환)
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
├── realtime-voice/                   # 🎙️ 진짜 실시간 음성 서버 (Media Streams)
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

**Q. 설치할 때 용도(고객/개인)를 잘못 골랐어요. 재설치해야 하나요?**
A. 아니요. 재설치 없이 `twilio-bot/ai_config.py`의 `SERVICE_MODE` 한 줄만 바꾸고 `docker compose restart twilio-bot` 하면 됩니다. `"customer"`(고객 상담용) ↔ `"personal"`(개인용)으로 자유롭게 전환됩니다. 자세히는 [두 가지 운영 모드](#두-가지-운영-모드) 참고.

**Q. `SERVICE_MODE`를 personal로 바꾸면 정확히 뭐가 달라지나요?**
A. 걸려온 전화 응대가 지인 안부체로 바뀌고, 기본 인사말이 안부체로, 상담원 0번 안내 멘트(`OPERATOR_HINT_ENABLED`)가 꺼지며, AI 역할 라벨이 "개인 전화 어시스턴트"로 바뀝니다. 전화 RAG 검색도 통합 검색(전화·웹·텔레그램 같은 문서 참조)으로 자동 전환되고, 능동형 자동전화(기억의 앵커)도 켤 수 있게 됩니다. 관리자 명령·요금 보호 등 나머지 기능은 두 모드 공통으로 그대로 작동합니다.

**Q. 텔레그램에도 PIN이 있던데요?**
A. 텔레그램 봇의 PIN은 **전화 봇 PIN과 별개**(텔레그램 사용자 인증용)이며 선택사항입니다. 전화 봇의 PIN은 민감 명령(전화·문자·연락처 저장·예약) 실행 시에만 확인하며, `ai_config.py`의 `ADMIN_PIN_REQUIRED = False`로 끌 수 있습니다.

**Q. 서버를 재부팅하면 캘린더가 또 끊기나요?**
A. 아니요. 재발 방지가 적용되어 마운트가 메인 compose와 `.env`에 고정되어 있습니다. 어떻게 띄워도 캘린더가 유지됩니다.

**Q. 0번을 안 누르면 관리자에게 전화가 안 오나요?**
A. 일반 모드(BOT_MODE 2)에서는 0번을 누르거나 음성으로 "담당자"라고 해야 사람에게 연결됩니다. 아무것도 안 하면 AI가 계속 응대합니다. 모든 전화를 무조건 사람이 받게 하려면 설치 시 또는 `.env`에서 `BOT_MODE=3`을 쓰세요.

**Q. 0번·음성 연결을 완전히 끄려면?**
A. `ai_config.py`에서 `OPERATOR_TRANSFER_ENABLED = False`(0번)와 `OPERATOR_VOICE_ENABLED = False`(음성)로 설정하세요. 둘 다 꺼도 외부인은 AI 상담은 계속 받습니다.

**Q. 설치할 때 실시간 모드에서 `N`을 누르면 어떻게 되나요?**
A. 기존 방식 그대로 설치됩니다. `realtime-voice` 컨테이너와 도구는 설치되지만 유휴 상태이고, 통화는 예전처럼 한 문장씩 주고받습니다. 나중에 `.env`의 `REALTIME_MODE=true`로 언제든 켤 수 있습니다.

**Q. 진짜 실시간 모드인데 실시간이 안 돼요.**
A. 가장 흔한 원인은 `SERVER_DOMAIN`이 공개 HTTPS(`https://...`)가 아닌 경우입니다. Twilio가 `wss://`로 접속해야 하므로 localhost로는 실시간이 불가능하며, 자동으로 기존 방식으로 폴백됩니다. Cloudflare Tunnel 등으로 공개 HTTPS 도메인을 확보하세요. 그다음 `docker compose logs -f realtime-voice`로 연결·오류를 확인하세요.

**Q. STT/TTS 엔진(제공자·음성)을 바꾸려면?**
A. OpenWebUI → 워크스페이스 → 도구 → "음성엔진 설정" → ⚙️ 밸브에서 값을 바꾸고 저장하면 즉시 반영됩니다. 자세히는 [음성엔진 설정](#음성엔진-설정-stttts-밸브-교체) 참고.

**Q. 실시간 귓속말은 실시간 모드에서만 되나요?**
A. 아니요. 기본(turn-based) 방식에서도 작동합니다. 다만 진짜 실시간 모드에서 반영이 더 빠릅니다.

**Q. 기억의 앵커가 과거 대화를 잘 못 떠올려요.**
A. 회상 품질은 Ollama 임베딩에 달려 있습니다. `docker compose logs twilio-bot | grep 임베딩`으로 확인해서 `⚠️ 더미 벡터`가 보이면 Ollama 접근이 안 되는 것입니다. [Ollama 자동 설정](#ollama-임베딩-자동-설정-wsl2)을 참고해 `OLLAMA_HOST=0.0.0.0`으로 여세요.

**Q. 자동으로 안부전화가 걸리게 하려면?**
A. `twilio-bot/ai_config.py`에서 `MEMORY_AUTOCALL_ENABLED = True`로 바꾸고 `docker compose restart twilio-bot`. 기본은 안전하게 "제안형"(관리자에게 알림만)입니다. 완전 자동은 `MEMORY_AUTOCALL_MODE = "auto"`로 바꾸되, 요금·빈도를 며칠 관찰한 뒤 켜는 것을 권합니다. → [기억의 앵커](#-기억의-앵커-통화-회상--능동형-자동전화)

**Q. 통화 보고 문자가 너무 짧게 잘려요.**
A. 최신 버전에서 SMS 보고를 250자로 늘리고, 내부 토큰 제한도 함께 올려 잘림을 해결했습니다. 재설치하거나 `docker compose up -d --build twilio-bot`로 봇을 재빌드하세요.

**Q. 텔레그램 보고만 안 오고 문자만 와요.**
A. `.env`에 `TELEGRAM_BOT_TOKEN`·`TELEGRAM_CHAT_ID`가 있는지 확인하세요. 가장 흔한 원인은 값 누락 또는 **봇에게 먼저 `/start`를 안 보낸 것**입니다. `docker compose logs twilio-bot | grep -i telegram`에 원인이 표시됩니다. → [텔레그램 통화 보고 받기](#-텔레그램-통화-보고-받기-선택)

**Q. 전화만으로 상대방 휴대폰 GPS 위치를 자동으로 받을 수 있나요?**
A. 아니요. 일반 음성통화는 상대방 단말의 GPS 센서에 접근할 수 없습니다(모든 전화 시스템의 물리적 한계). 이 기능은 상대방이 **말로 알려준 위치**를 지도로 변환해 보고하는 방식이며, 상대의 동의를 전제로 합니다.

**Q. 위치 보고에 좌표만 오고 지도 이미지가 안 와요.**
A. 지도 이미지 저장 폴더(`twilio-bot/data/reports`) 권한 문제이거나 NAVER Static Map 호출 실패일 수 있습니다. 최신 스크립트는 설치 시 폴더 소유권을 봇 사용자로 맞춰 해결합니다. 재설치하거나 `docker compose up -d --build twilio-bot`로 재빌드하세요.

**Q. "강남역" 같은 역명을 못 찾아요.**
A. NAVER 지오코딩은 도로명·지번 주소만 찾고 역명·상호는 못 찾습니다(NAVER 지역검색 API 종료). 카카오 REST API 키를 넣으면 역명·상호까지 검색됩니다. → [위치 확인 (NAVER + 카카오)](#-위치-확인-naver--카카오)

**Q. AI가 위치를 물을 때 같은 질문을 계속 반복해요.**
A. 상대가 예/아니요로 명확히 답하지 않으면 되묻는데, 최신 버전은 **최대 2번**까지만 묻고 그 뒤엔 위치 확인을 건너뛰도록 제한했습니다. 재설치하거나 봇을 재빌드하세요.

**Q. 통화 상대가 전화를 받았는데 "안 받음/소리샘"으로 보고돼요.**
A. 예전에는 대화 기록이 없으면 무조건 미수신으로 판정했습니다. 최신 버전은 첫 인사가 나갔는지(전화 받은 증거)를 함께 보고 "받으셨으나 말씀이 없으셨습니다"와 "안 받음/소리샘"을 구분해 보고합니다. 재설치하거나 봇을 재빌드하세요.

**Q. AI가 너무 성격이 급한 것 같아요(말 끊고 빨리 넘어감).**
A. `twilio-bot/ai_config.py`의 `SPEECH_TIMEOUT_OUTBOUND`(말 멈춤 후 대기 초)와 `TIMEOUT_OUTBOUND`(무응답 종료 초)를 늘리면 됩니다. 최신 기본값은 각각 5초·8초로, 어르신이 천천히 말해도 끼어들지 않게 여유를 뒀습니다. 더 느긋하게 하려면 6초·10초로 올리고 `docker compose restart twilio-bot`.

---

## 라이선스 / 기여

이 저장소를 사용하기 전에 각 스크립트 내용을 검토하세요. 셀프호스팅 환경과 외부 서비스(Twilio, Telegram, AI 제공자)의 약관·요금을 반드시 확인하시기 바랍니다.

> ⚠️ 이 패키지는 전화·SMS·AI API 등 **과금되는 외부 서비스**를 사용합니다. **지나친 통화로 통화료가 과다하게 발생할 수 있다는 점을 항상 유의하시고 사용하세요.** 사용량과 요금을 주기적으로 확인하시기 바랍니다.

> 🔒 **보안 책임 고지**: 설치·운영 과정에서 발생하는 모든 보안 문제의 책임은 **설치·운영자 본인에게 있으며, 개발자는 이와 관련한 책임을 지지 않습니다.** 방화벽·접근권한·비밀키 관리·서버 보안 등은 설치자가 직접 점검·관리해야 합니다. 또한 **통화 녹음·기록에 관한 법적 책임(동의 요건, 관련 법령 준수 등)은 전적으로 설치·운영자에게 있으며, 개발자와는 무관합니다.**
