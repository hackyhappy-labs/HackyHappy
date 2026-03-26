# 📞 AI Phone & Chat Assistant — OpenWebUI + Twilio + Telegram

### One-click installers for a fully autonomous AI assistant: voice calls, SMS, Telegram chat, RAG search, and multilingual support.

> 🌐 **[한국어 README는 아래에 있습니다](#-한국어)**

---

## ✨ What Is This?

Two companion scripts that give you a **complete AI assistant ecosystem**:

| Script | What It Does |
|--------|-------------|
| 📞 **Twilio Phone Bot** | AI answers phone calls, makes outgoing calls on your behalf, sends/receives SMS, searches documents via RAG |
| 💬 **Telegram Bridge** | Access all OpenWebUI AI models, tools, and RAG from Telegram — text, voice, photos, PDFs |

Both connect to **OpenWebUI** as the AI brain — same models, same tools, same documents, just different interfaces.

---

## 🎬 What Can It Do?

### 📞 Phone / SMS (Twilio)

```
You: "Call Kim and ask what he's doing today"
  ↓
AI calls Kim's phone
  ↓
AI: "Hi Kim! What are you up to today?"
Kim: "Uh... well... I'm just... staying home..."
  ↓
AI (patient): "Ah~ relaxing at home! How have you been?"
  ↓
[18 sec later] AI calls YOU with a summary
[21 sec later] AI texts YOU: "[Report] Kim: staying home, feeling well."
```

### 💬 Telegram

```
You (Telegram): "PDF에서 환불 정책 찾아줘"
  ↓
AI searches uploaded documents via RAG
  ↓
AI: "환불 정책에 따르면 구매 후 7일 이내 전액 환불 가능합니다..."

You: [sends voice message]
  ↓
Whisper STT → AI responds → TTS voice reply

You: /model → switch to GPT-4, Llama, etc.
You: /tools → enable phone calls, SMS, RAG from Telegram
```

---

## 🚀 Installation

### Prerequisites

- Linux server (Ubuntu 20.04+)
- At least 2 CPU cores / 4GB RAM

### Step 1 — Install AI Phone Bot (Twilio)

```bash
chmod +x start-openwebui-with-rag-groq-ollama-Twilio-final.sh
./start-openwebui-with-rag-groq-ollama-Twilio-final.sh
```

This installs everything: Docker, OpenWebUI, Qdrant, Ollama, Twilio Bot, Nginx, security — fully automated.

You'll need:
- [Groq API key](https://console.groq.com/) (free tier available)
- [Twilio account](https://www.twilio.com/) (for phone/SMS)

### Step 2 — Install Telegram Bridge (Optional)

```bash
chmod +x setup-telegram-openwebui-bridge.sh
./setup-telegram-openwebui-bridge.sh
```

Requires Step 1 to be running first. Connects to the same OpenWebUI instance.

You'll need:
- Telegram Bot Token (from [@BotFather](https://t.me/BotFather))
- OpenWebUI API Key (from OpenWebUI settings)
- Your Telegram User ID (from [@userinfobot](https://t.me/userinfobot))

### After Installation

| Service | URL |
|---------|-----|
| OpenWebUI (Chat) | `http://localhost:3000` |
| API Docs | `http://localhost:8000/docs` |
| Call History Dashboard | `http://localhost:5000/dashboard` |
| Qdrant Dashboard | `http://localhost:6333/dashboard` |
| Telegram Bot Health | `http://localhost:8443/health` |

---

## 📞 Phone Bot Features

### Voice Calls & SMS

| Command (in OpenWebUI chat) | What Happens |
|---|---|
| "Call Kim and ask how he's doing" | AI calls, converses, reports back |
| "Call Kim and tell him: meeting at 3pm" | Delivers your exact message |
| "Text Kim: are you coming to dinner?" | SMS + auto-forwards reply |
| "Save contact: Kim +821012345678" | Persistent contact storage |
| "Show call history" | Recent calls with AI summaries |
| "Schedule call to Kim every Monday 10am" | Recurring automated calls |

### Patience System

Unlike other AI phone bots that hang up after 2 seconds of silence:

- ⏳ **12-second timeout** — waits for thinking time
- 🎤 **5-second speech timeout** — doesn't cut off mid-pause
- 💭 **Hesitation detection** — "um...", "uh..." → *"Take your time, I'm listening"*
- 🧩 **Fragment accumulation** — collects broken speech into complete understanding
- 🔄 **3 retries with warmth** — escalates from "Sorry?" to "No rush, I'm here"

### Multilingual Auto-Detection

| Country Code | Language | Auto-switches TTS, STT, prompts, messages |
|---|---|---|
| +82 (Korea) | 한국어 | ko-KR |
| +1 (US/Canada) | English | en-US |
| +81 (Japan) | 日本語 | ja-JP |
| +86 (China) | 中文 | cmn-CN |

### Call History Dashboard

Beautiful dark-themed dashboard at `http://localhost:5000/dashboard`:
- 📈 Real-time statistics
- 🔍 Search by name
- 📋 Expandable cards with AI summaries + full conversation history
- 📱 Mobile responsive, auto-refresh every 30s

---

## 💬 Telegram Bot Features

### Commands

| Command | Description |
|---------|-------------|
| `/start` | Start the bot |
| `/help` | Show all commands |
| `/model` | Switch AI model (inline buttons) |
| `/tools` | Enable/disable tools (phone, SMS, RAG, etc.) |
| `/clear` | Clear conversation history |
| `/history` | View conversation history |
| `/status` | System status (admin) |
| `/whoami` | Show your Telegram User ID |

### What You Can Send

| Input Type | What Happens |
|---|---|
| **Text message** | AI responds using selected model + enabled tools |
| **PDF file** | Auto-indexed into RAG for document search |
| **Image/Photo** | Sent to AI for analysis |
| **Voice message** | Whisper STT → AI response → TTS voice reply |
| **Any command from phone bot** | "김철수한테 전화해줘" works in Telegram too (with tools enabled) |

### Security (18 Items)

| Category | Features |
|---|---|
| **Access Control** | Admin-only whitelist, PIN authentication |
| **Rate Limiting** | 30 req/min, auto-block after 3 violations (10 min) |
| **Input Safety** | 4096 char limit, XSS/injection defense, null byte removal |
| **Network** | Webhook signature verification, Docker network isolation |
| **Runtime** | Non-root container, read-only filesystem, 512MB memory limit |
| **Data** | AES-256 token encryption, log masking, session timeout (30 min) |
| **Monitoring** | Health check, log rotation (10MB × 3), Prometheus metrics |

---

## 🔐 Combined Security — 34 Items Total

| Phone Bot (16) | Telegram Bridge (18) |
|---|---|
| Twilio signature verification | Webhook secret token |
| API Secret authentication | AES-256 token encryption |
| 6-digit PIN | Admin PIN |
| Admin whitelist | User ID whitelist |
| Blocked number list | Rate limiter (30/min) |
| PIN lockout (3 fails) | Auto-block (3 fails → 10 min) |
| Local port binding | Docker network isolation |
| CORS restriction | CORS disabled |
| Docker Secrets | Non-root container |
| .env chmod 600 | .env chmod 600 + backup |
| Input masking | Input sanitization + length limit |
| Cloudflare Tunnel | Nginx webhook proxy |
| JSON audit logs | Rotating file logs |
| Dashboard local-only | Health check endpoint |
| Contact file encryption | Session timeout (30 min) |
| Nginx security headers | Log masking (API keys, phone numbers) |

---

## 📦 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Your Server                         │
│                                                          │
│   ┌───────────┐  ┌───────────┐  ┌───────────┐           │
│   │ OpenWebUI │  │  Qdrant   │  │  Ollama   │           │
│   │  :3000    │  │  :6333    │  │  :11434   │           │
│   │ (Chat UI) │  │(Vector DB)│  │ (Embed)   │           │
│   └─────┬─────┘  └─────┬─────┘  └─────┬─────┘           │
│         │              │              │                  │
│   ┌─────┴──────────────┴──────────────┴───────┐          │
│   │         Tools API (FastAPI :8000)          │          │
│   │   RAG Search · Phone Proxy · Schedule     │          │
│   └──────────┬────────────────────────────────┘          │
│              │                                           │
│   ┌──────────┴──────────┐  ┌────────────────────────┐    │
│   │  Twilio Bot (:5000) │  │  Telegram Bot (:8443)  │    │
│   │  Voice · SMS · AI   │  │  Text · Voice · Files  │    │
│   │  Dashboard · Sched  │  │  Models · Tools · RAG  │    │
│   └──────────┬──────────┘  └───────────┬────────────┘    │
│              │                         │                 │
└──────────────┼─────────────────────────┼─────────────────┘
               │                         │
        ┌──────┴──────┐          ┌───────┴───────┐
        │   Twilio    │          │   Telegram    │
        │  Cloud API  │          │   Bot API     │
        └──────┬──────┘          └───────┬───────┘
               │                         │
        ┌──────┴──────┐          ┌───────┴───────┐
        │ Phone / SMS │          │ Telegram App  │
        │   Network   │          │  (Mobile/PC)  │
        └─────────────┘          └───────────────┘
```

---

## ⚙️ Configuration

### Phone Bot — `~/openapi-rag/twilio-bot/ai_config.py`

| Setting | Default | Description |
|---|---|---|
| `DEFAULT_LANG` | `"ko"` | Default language |
| `AI_NAME` | `"AI 비서"` | Assistant name |
| `TIMEOUT_OUTBOUND` | `12` | Response wait time (sec) |
| `SPEECH_TIMEOUT_OUTBOUND` | `"5"` | Extra wait after pause |
| `MIN_CONVERSATION_TURNS` | `3` | Minimum turns before ending |
| `PATIENCE_MAX_RETRIES` | `3` | Max patience retries |

### Telegram Bot — `~/telegram-openwebui-bridge/.env`

| Setting | Default | Description |
|---|---|---|
| `RATE_LIMIT_PER_MINUTE` | `30` | Max requests per minute |
| `SESSION_TIMEOUT_MINUTES` | `30` | Session expiry |
| `MAX_MESSAGE_LENGTH` | `4096` | Input character limit |
| `MAX_FILE_SIZE_MB` | `20` | Max upload file size |

---

## 📝 Tech Stack

| Component | Technology |
|-----------|-----------|
| AI Chat UI | OpenWebUI |
| LLM | Groq (llama-3.3-70b) / Ollama |
| Embeddings | Ollama nomic-embed-text (768d) |
| Vector DB | Qdrant |
| Phone / SMS | Twilio |
| Phone Bot | Flask + Gunicorn |
| API Server | FastAPI + Uvicorn |
| Telegram Bot | python-telegram-bot (async) |
| Reverse Proxy | Nginx |
| Containers | Docker + Docker Compose |
| Security | Docker Secrets + Cloudflare Tunnel |

---

## 🛠 Troubleshooting

| Problem | Solution |
|---|---|
| Docker permission error | `sudo usermod -aG docker $USER` then re-login |
| Twilio calls not working | Check webhook URL in Twilio Console |
| Telegram bot not responding | Check `docker logs telegram-openwebui-bridge` |
| RAG search empty | Upload PDF via `http://localhost:8000/docs` |
| AI responds slowly | Use Groq mode (BOT_MODE=2) |
| Dashboard not loading | Local only: `http://localhost:5000/dashboard` |

---

## 📝 License

MIT License — free for personal and commercial use.

---

## 🏗 Project Structure Note

> **This project is intentionally built as single installation scripts** for one-click deployment simplicity. Non-developers can set up the entire stack by running just one or two commands. A modular multi-file version is planned for future releases.

---
---

# 📞 한국어

## ✨ 이게 뭔가요?

**명령어 한두 줄**이면 완전한 AI 비서 시스템이 설치됩니다:

| 스크립트 | 역할 |
|----------|------|
| 📞 **Twilio 전화봇** | AI가 전화를 받고, 대리 전화를 걸고, SMS를 주고받고, 문서 검색까지 |
| 💬 **Telegram 브릿지** | OpenWebUI의 모든 AI 모델, Tool, RAG를 텔레그램에서 그대로 사용 |

두 스크립트 모두 **OpenWebUI**를 AI 두뇌로 공유합니다 — 같은 모델, 같은 도구, 같은 문서.

---

## 🚀 설치 방법

### 1단계 — AI 전화봇 설치 (Twilio)

```bash
chmod +x start-openwebui-with-rag-groq-ollama-Twilio-final.sh
./start-openwebui-with-rag-groq-ollama-Twilio-final.sh
```

Docker, OpenWebUI, Qdrant, Ollama, Twilio 봇, Nginx, 보안까지 전부 자동 설치됩니다.

필요한 것:
- [Groq API 키](https://console.groq.com/) (무료 티어 가능)
- [Twilio 계정](https://www.twilio.com/) (전화/SMS용)

### 2단계 — Telegram 브릿지 설치 (선택)

```bash
chmod +x setup-telegram-openwebui-bridge.sh
./setup-telegram-openwebui-bridge.sh
```

1단계가 먼저 실행 중이어야 합니다. 같은 OpenWebUI에 연결됩니다.

필요한 것:
- Telegram Bot Token ([@BotFather](https://t.me/BotFather)에서 발급)
- OpenWebUI API Key (OpenWebUI 설정에서 발급)
- 본인 Telegram User ID ([@userinfobot](https://t.me/userinfobot)에서 확인)

### 설치 후 접속

| 서비스 | URL |
|--------|-----|
| OpenWebUI (채팅) | `http://localhost:3000` |
| API 문서 | `http://localhost:8000/docs` |
| 통화 기록 대시보드 | `http://localhost:5000/dashboard` |
| Qdrant 대시보드 | `http://localhost:6333/dashboard` |
| Telegram 봇 상태 | `http://localhost:8443/health` |

---

## 📞 전화봇 사용법

OpenWebUI 채팅창에서 자연스럽게 말하면 됩니다:

| 입력 | 결과 |
|------|------|
| "김철수한테 안부전화 해줘" | AI가 전화 → 대화 → 결과 보고 |
| "김철수한테 전화해줘. 어떻게 지내세요?" | 메시지 그대로 전달 |
| "김철수한테 문자 보내줘: 내일 회의 있어요" | SMS 발송 + 답장 자동 전달 |
| "김철수 번호 010-1111-2222 저장해줘" | 연락처 영구 저장 |
| "통화 기록 보여줘" | 최근 통화 + AI 요약 |
| "매주 월요일 10시에 김철수한테 전화해줘" | 반복 예약 등록 |
| "예약 목록 보여줘" | 📋 임무 + 💬 메시지 + 🕐 등록일 + ▶️ 실행 이력 |
| "PDF 문서에서 환불 정책 찾아줘" | RAG 문서 검색 |

### 🌐 다국어 자동 감지

전화번호 국가코드로 언어가 자동 전환됩니다:

| 국가코드 | 언어 | TTS/STT/프롬프트 모두 자동 전환 |
|----------|------|-------------------------------|
| +82 (한국) | 한국어 | "안녕하세요! 잘 지내고 계시죠?" |
| +1 (미국) | English | "Hello! How have you been?" |
| +81 (일본) | 日本語 | "こんにちは！お元気ですか？" |
| +86 (중국) | 中文 | "您好！最近过得怎么样？" |

### 🧠 인내심 시스템

다른 AI 전화봇은 2초만 침묵하면 끊습니다. 이 비서는 **참을성이 있습니다**:

- ⏳ 12초 대기 — 생각할 시간 충분히
- 🎤 5초 추가 대기 — 말이 잠시 끊겨도 기다림
- 💭 "음...", "어..." 감지 → "괜찮아요, 편하게 말씀해 주세요"
- 🧩 조각 누적 — "오늘..." + "집에서..." → 합쳐서 이해
- 📋 더듬거린 대화도 문맥에서 해석하여 정확하게 보고

### 📊 통화 기록 대시보드

`http://localhost:5000/dashboard`:
- 📈 실시간 통계 (전체/오늘/연락처/완료)
- 🔍 이름 검색
- 📋 통화 카드 펼치기 → AI 요약 + 전체 대화
- 📱 모바일 반응형, 30초 자동 갱신

---

## 💬 Telegram 봇 사용법

### 명령어

| 명령어 | 설명 |
|--------|------|
| `/start` | 봇 시작 |
| `/help` | 전체 명령어 안내 |
| `/model` | AI 모델 변경 (인라인 버튼) |
| `/tools` | Tool 활성화/비활성화 (전화, SMS, RAG 등) |
| `/clear` | 대화 기록 초기화 |
| `/history` | 대화 기록 조회 |
| `/status` | 시스템 상태 (관리자) |
| `/whoami` | 본인 Telegram User ID 확인 |

### 보낼 수 있는 것

| 입력 | 결과 |
|------|------|
| **텍스트** | 선택된 모델 + 활성 Tool로 AI 응답 |
| **PDF 파일** | RAG에 자동 색인 → 문서 검색 가능 |
| **이미지** | AI가 이미지 분석 |
| **음성 메시지** | Whisper STT → AI 응답 → TTS 음성 회신 |
| **전화봇 명령** | "김철수한테 전화해줘" (Tool 활성화 시 텔레그램에서도 작동) |

### 보안 (18항목)

- ✅ 관리자 전용 화이트리스트 (등록 안 된 사용자는 완전 차단)
- ✅ Rate Limiting (30회/분, 3회 초과 시 10분 자동 차단)
- ✅ 입력 4096자 제한 + XSS/인젝션 방어
- ✅ Webhook 서명 검증
- ✅ 컨테이너 non-root 실행 + 메모리 512MB 제한
- ✅ AES-256 토큰 암호화 + 로그 민감정보 마스킹
- ✅ 세션 30분 타임아웃
- ✅ 로그 로테이션 (10MB × 3파일)

---

## ⏰ 예약 스케줄러

| 명령 | 설명 |
|------|------|
| "내일 3시에 김철수한테 전화해줘" | 1회 예약 |
| "매주 월요일 10시에 안부전화 해줘" | weekly 반복 |
| "매일 9시에 문자 보내줘" | daily 반복 |
| "예약 목록 보여줘" | 📋 임무 + 💬 메시지 + 🕐 등록일 + ▶️ 실행 이력 |
| "예약 삭제해줘" | 예약 ID로 삭제 |
| "예약 비활성화해줘" | ON/OFF 토글 |

---

## 📋 보고 타이밍

| 상황 | 보고 방식 |
|------|-----------|
| ✅ 통화 성공 | 📞 전화 보고 ~18초 후 → 📱 SMS ~21초 후 |
| ❌ 통화 실패 | 📱 SMS 보고 ~21초 후 |
| ✅ SMS 성공 | 보고 없음 |
| ❌ SMS 실패 | 📱 실패 보고 10초 후 |
| 📩 상대방 답장 | 자동 전달 5초 후 |

---

## 🔐 통합 보안 — 총 34항목

| 전화봇 (16항목) | Telegram (18항목) |
|---|---|
| Twilio 서명검증 | Webhook 서명 토큰 |
| API Secret 인증 | AES-256 토큰 암호화 |
| 6자리 PIN | 관리자 PIN |
| 관리자 번호 화이트리스트 | User ID 화이트리스트 |
| 차단 번호 목록 | Rate Limiter (30/분) |
| PIN 3회 잠금 | 자동 차단 (3회→10분) |
| 로컬 포트 바인딩 | Docker 네트워크 격리 |
| CORS 제한 | CORS 비활성화 |
| Docker Secrets | non-root 컨테이너 |
| .env chmod 600 | .env chmod 600 + 백업 |
| 입력 마스킹 | 입력 검증 + 길이 제한 |
| Cloudflare Tunnel | Nginx Webhook 프록시 |
| JSON 감사 로그 | 로그 로테이션 |
| 대시보드 로컬 전용 | Health 체크 |
| 연락처 파일 보호 | 세션 타임아웃 30분 |
| Nginx 보안 헤더 | 로그 마스킹 (API키, 전화번호) |

---

## 📦 기술 스택

| 구성 요소 | 기술 |
|-----------|------|
| AI 채팅 UI | OpenWebUI |
| LLM | Groq (llama-3.3-70b) / Ollama |
| 임베딩 | Ollama nomic-embed-text (768차원) |
| 벡터 DB | Qdrant |
| 전화/SMS | Twilio |
| 전화봇 | Flask + Gunicorn |
| API 서버 | FastAPI + Uvicorn |
| Telegram 봇 | python-telegram-bot (async) |
| 리버스 프록시 | Nginx |
| 컨테이너 | Docker + Docker Compose |
| 보안 | Docker Secrets + Cloudflare Tunnel |

---

## 🛠 문제 해결

| 문제 | 해결 |
|------|------|
| Docker 권한 오류 | `sudo usermod -aG docker $USER` 후 재접속 |
| Twilio 전화 안 됨 | Twilio Console에서 Webhook URL 확인 |
| Telegram 봇 무응답 | `docker logs telegram-openwebui-bridge` 확인 |
| RAG 검색 결과 없음 | `http://localhost:8000/docs`에서 PDF 업로드 |
| AI 응답 느림 | Groq 모드 (BOT_MODE=2) 사용 |
| 대시보드 안 열림 | 로컬만 접속 가능: `http://localhost:5000/dashboard` |

---

## 📝 라이선스

MIT License — 개인 및 상업적 사용 모두 가능합니다.

---

## 🏗 프로젝트 구조 안내

> **원클릭 설치를 위해 의도적으로 단일 스크립트로 구성했습니다.** 비개발자도 터미널에서 명령어 한두 줄이면 Docker, AI, Twilio, Telegram, RAG, 보안까지 전체 스택이 자동 설치됩니다. 구조 분리 버전은 추후 제공 예정입니다.

---

## 🤝 Contributing

Issues and Pull Requests are welcome. For major changes, please open an issue first.

---

**Made with ☕ and a lot of debugging**

🌐 More projects & updates → [vulva.sex](http://vulva.sex)
