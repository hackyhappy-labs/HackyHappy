# 🤖 HackyHappy AI 전화봇

> OpenWebUI + Twilio + Groq + Qdrant 기반 AI 전화 어시스턴트  
> 전화 한 통으로 AI가 지인에게 안부전화를 대신하고, 결과를 SMS로 보고하는 시스템

---

## ✨ 주요 기능

| 기능 | 설명 |
|------|------|
| 📞 AI 전화 수신 | 전화오면 AI가 한국어로 자동 응답 |
| 🤙 AI가 먼저 전화 | "나한테 전화해줘" 명령으로 AI가 발신 |
| 💌 안부전화 대행 | AI가 지인에게 전화해서 대화 후 결과 보고 |
| 📵 안받으면 SMS | 30초 안에 안 받으면 SMS 자동 발송 |
| 👥 연락처 관리 | 음성/curl로 저장, 재시작 후에도 유지 |
| 💬 채팅창 전화 | OpenWebUI 채팅창에서 "나한테 전화해줘" |
| 📄 PDF RAG | PDF 업로드 후 전화/채팅으로 내용 질문 |
| 🔒 13가지 보안 | Twilio 서명검증, PIN 잠금, API Secret 등 |

---

## 📋 사전 준비물

설치 전에 아래 계정과 정보를 미리 준비하세요.

### 1. Groq API Key (무료)
1. [console.groq.com](https://console.groq.com) 접속
2. 회원가입 후 로그인
3. **API Keys** → **Create API Key**
4. 키 복사해두기 (`gsk_...` 로 시작)

### 2. Twilio 계정 (유료 전환 필수)
1. [twilio.com](https://twilio.com) 회원가입
2. **Phone Numbers** → 미국 번호 구매 ($1/월)
3. **신분증 업로드로 유료 계정 전환** ← 한국 번호 발신에 필수!
4. 아래 정보 메모:
   - Account SID (`ACc2d...`)
   - Auth Token (`6ff5...`)
   - 구매한 전화번호 (`+1802...`)

### 3. Cloudflare Tunnel (무료)
1. [cloudflare.com](https://cloudflare.com) 회원가입
2. 도메인 등록 (없으면 무료 도메인 사용 가능)
3. **Zero Trust** → **Networks** → **Tunnels** → **Create Tunnel**
4. 터널 토큰 복사해두기

---

## 🖥️ 빈 우분투에서 시작하기

### Step 1 — 우분투 기본 업데이트

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 2 — 필수 패키지 설치

```bash
sudo apt install -y \
    curl wget git \
    python3 python3-pip \
    nginx \
    ca-certificates \
    gnupg lsb-release \
    unzip jq
```

### Step 3 — Docker 설치

```bash
# Docker 공식 GPG 키 추가
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Docker 저장소 추가
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Docker 설치
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 현재 사용자를 docker 그룹에 추가 (sudo 없이 사용 가능)
sudo usermod -aG docker $USER
newgrp docker

# 설치 확인
docker --version
docker compose version
```

### Step 4 — Cloudflare Tunnel 설치

```bash
# cloudflared 설치
curl -L --output cloudflared.deb \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# 터널 인증 (브라우저에서 로그인)
cloudflared tunnel login

# 터널 생성
cloudflared tunnel create my-tunnel

# 터널 설정 파일 생성
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << EOF
tunnel: $(cloudflared tunnel list | grep my-tunnel | awk '{print $1}')
credentials-file: ~/.cloudflared/$(cloudflared tunnel list | grep my-tunnel | awk '{print $1}').json
ingress:
  - hostname: 내도메인.com
    service: http://localhost:80
  - service: http_status:404
EOF

# DNS 등록
cloudflared tunnel route dns my-tunnel 내도메인.com

# 시스템 서비스로 등록 (재시작 후에도 자동 실행)
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
sudo systemctl status cloudflared
```

> ⚠️ `내도메인.com` 부분을 본인 도메인으로 바꾸세요!

### Step 5 — 자동 시작 설정

```bash
# Docker 자동 시작
sudo systemctl enable docker
sudo systemctl start docker

# Nginx 자동 시작
sudo systemctl enable nginx

# 재부팅 후에도 모든 서비스 자동 실행 확인
sudo reboot
```

---

## 🚀 AI 전화봇 설치

### Step 6 — 설치 스크립트 다운로드

```bash
cd ~
curl -O https://raw.githubusercontent.com/hackyhappy-labs/HackyHappy/main/install.sh
chmod +x install.sh
```

### Step 7 — 설치 실행

```bash
./install.sh
```

설치 중 아래 정보를 순서대로 입력합니다:

```
🔑 Groq API Key        → console.groq.com 에서 발급
🔑 Twilio Auth Token   → Twilio 콘솔에서 확인
🔑 Twilio Account SID  → Twilio 콘솔에서 확인
📱 Twilio 전화번호     → +1802xxxxxxx 형식
📲 내 전화번호         → +821012345678 형식
🌐 서버 도메인         → https://내도메인.com
👤 관리자 이메일       → admin@내도메인.com
🔑 관리자 비밀번호     → 안전한 비밀번호
🤖 봇 모드             → 2 (Groq 직접, 권장)
🔢 PIN 6자리           → 모르는 번호 인증용
```

> 각 항목은 120초 내에 입력 후 Enter. 그냥 Enter 하면 기본값 적용.

### Step 8 — 설치 완료 확인

```bash
cd ~/openapi-rag
docker compose ps
```

아래처럼 4개 컨테이너가 모두 실행 중이면 정상:

```
NAME                          STATUS
openapi-rag-open-webui-1      running (healthy)
openapi-rag-openapi-tools-1   running
openapi-rag-qdrant-1          running
twilio-bot                    running (healthy)
```

---

## ✅ 설치 후 한 번만 하는 설정

### OpenWebUI 전화 Tool 활성화

```
1. https://내도메인.com 접속
2. 관리자 계정으로 로그인
3. 채팅창 하단 🔧 아이콘 클릭
4. "전화 어시스턴트" 토글 ON
```

### Twilio Verified Caller ID 등록

AI가 내 번호로 전화를 걸려면 번호 인증이 필요합니다:

```bash
curl -s -X POST \
"https://api.twilio.com/2010-04-01/Accounts/[ACCOUNT_SID]/OutgoingCallerIds.json" \
-u "[ACCOUNT_SID]:[AUTH_TOKEN]" \
--data-urlencode "PhoneNumber=+821012345678"
```

전화가 오면 안내에 따라 인증코드 입력.

---

## 📱 사용 방법

### 전화로 음성 명령 (관리자만)

```
Twilio 번호로 전화
→ PIN 없이 바로 AI 연결 (관리자 번호)
→ 말하기:
   "나한테 전화해줘"
   "김철수한테 안부전화 해줘"
   "김철수 번호 010-1234-5678 저장해줘"
   "연락처 목록 알려줘"
```

### OpenWebUI 채팅창에서

```
https://내도메인.com 접속 후 채팅창에서:
→ "나한테 전화해줘"
→ "김철수한테 안부전화 해줘"
→ "저장된 연락처 알려줘"
```

### curl 명령어로

```bash
# API Secret 확인
grep API_SECRET ~/openapi-rag/.env

# 나한테 전화
curl -X POST http://localhost:5000/call-me \
     -H "X-API-Secret: [API_SECRET]"

# 안부전화
curl -X POST http://localhost:5000/call-contact \
     -H "X-API-Secret: [API_SECRET]" \
     -H "Content-Type: application/json" \
     -d '{"name":"김철수","mission":"안부 확인"}'

# 연락처 저장
curl -X POST http://localhost:5000/contacts/add \
     -H "X-API-Secret: [API_SECRET]" \
     -H "Content-Type: application/json" \
     -d '{"name":"김철수","number":"+821012345678"}'
```

---

## 🔄 안부전화 동작 흐름

```
"김철수한테 안부전화 해줘"
       ↓
AI가 임무/인사말 자동 생성
       ↓
김철수님 번호로 발신 📞
       ├── 받으면 → AI가 자연스럽게 대화
       │           → 완료 후 관리자에게 SMS + 전화 보고
       │
       └── 30초 안받으면 → SMS: "김철수님이 전화를 받지 않았습니다"
```

---

## 🔧 관리 명령어

```bash
cd ~/openapi-rag

# 상태 확인
docker compose ps

# 로그 확인
docker compose logs -f twilio-bot
docker compose logs -f open-webui

# 재시작
docker compose restart twilio-bot
docker compose restart

# 전체 중지/시작
docker compose down
docker compose up -d

# 연락처 확인
curl http://localhost:5000/contacts \
     -H "X-API-Secret: $(grep API_SECRET .env | cut -d= -f2)"
```

---

## ⚠️ 주의사항

**PC를 끄면 서비스 중단!**  
모든 서비스가 로컬 PC에서 실행되므로 PC를 끄면 접속이 불가합니다.  
자동 시작 등록 확인:
```bash
sudo systemctl enable cloudflared nginx docker
```

**Twilio 요금**  
- 전화 수신: $0.0085/분
- 전화 발신: $0.014/분  
- SMS: $0.0083/건
- 안부전화 1회 약 $0.10 (약 140원)

---

## 📦 시스템 구성

```
전화 수신/발신
      ↕
   Twilio
      ↕ HTTPS Webhook
  Cloudflare Tunnel
      ↕ HTTP
    Nginx (포트 80)
      ├── twilio-bot    (:5000) — AI 전화 처리
      ├── OpenWebUI     (:3000) — 채팅 인터페이스
      ├── openapi-tools (:8000) — RAG + 전화 Tool API
      └── Qdrant        (:6333) — 벡터 DB
```

---

## 🆘 문제 해결

**컨테이너가 안 뜰 때**
```bash
docker compose logs --tail 30
```

**전화가 안 올 때**
```bash
# Webhook 확인
curl -s https://내도메인.com/health
# Nginx 상태
sudo systemctl status nginx
# Cloudflare Tunnel 상태
sudo systemctl status cloudflared
```

**OpenWebUI 접속 안 될 때**
```bash
docker compose restart open-webui
sleep 30
curl http://localhost:3000
```

---

## 📄 라이센스

MIT License — 자유롭게 사용, 수정, 배포 가능

---

*Powered by OpenWebUI + Twilio + Groq + Qdrant + Cloudflare*
