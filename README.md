# 🤖 HackyHappy AI 전화봇

> OpenWebUI + Twilio + Groq + Qdrant 기반 AI 전화 어시스턴트  
> 전화 한 통으로 AI가 지인에게 안부전화를 대신하고, 결과를 SMS+전화로 보고하는 시스템

---

## ✨ 주요 기능

| 기능 | 설명 |
|------|------|
| 📞 AI 전화 수신 | 전화오면 AI가 한국어로 자동 응답 |
| 🤙 AI가 먼저 전화 | "나한테 전화해줘" 명령으로 AI가 발신 |
| 💌 안부전화 대행 | AI가 지인에게 전화해서 대화 후 결과 보고 |
| 📵 안받으면 SMS+전화 | 30초 안에 안 받으면 SMS + 음성 보고 자동 발송 |
| 👥 연락처 관리 | 채팅창/음성/curl로 저장, 재시작 후에도 유지 |
| 💬 채팅창 전화 명령 | OpenWebUI 채팅창에서 전화/저장/삭제/조회 |
| 📄 PDF RAG | PDF 업로드 후 전화/채팅으로 내용 질문 |
| 🔒 13가지 보안 | Twilio 서명검증, PIN 잠금, API Secret 등 |

---

## 📋 사전 준비물

### 1. Groq API Key (무료)
1. [console.groq.com](https://console.groq.com) 접속 → 회원가입
2. **API Keys** → **Create API Key** → 키 복사 (`gsk_...`)

### 2. Twilio 계정 (유료 전환 필수)
1. [twilio.com](https://twilio.com) 회원가입
2. **Phone Numbers** → 미국 번호 구매 ($1/월)
3. **신분증 업로드로 유료 계정 전환** ← 한국 번호 발신에 필수!
4. Account SID / Auth Token / 전화번호 메모

### 3. Cloudflare Tunnel (무료)
1. [cloudflare.com](https://cloudflare.com) 회원가입 → 도메인 등록
2. **Zero Trust** → **Networks** → **Tunnels** → **Create Tunnel**

---

## 🖥️ 빈 우분투에서 시작하기

### Step 1 — 기본 업데이트

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 2 — 필수 패키지 설치

```bash
sudo apt install -y curl wget git python3 python3-pip nginx \
    ca-certificates gnupg lsb-release unzip jq
```

### Step 3 — Docker 설치

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker
docker --version && docker compose version
```

### Step 4 — Cloudflare Tunnel 설치

```bash
curl -L --output cloudflared.deb \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

cloudflared tunnel login
cloudflared tunnel create my-tunnel

# 내도메인.com 을 본인 도메인으로 변경
mkdir -p ~/.cloudflared
TUNNEL_ID=$(cloudflared tunnel list | grep my-tunnel | awk '{print $1}')
cat > ~/.cloudflared/config.yml << EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json
ingress:
  - hostname: 내도메인.com
    service: http://localhost:80
  - service: http_status:404
EOF

cloudflared tunnel route dns my-tunnel 내도메인.com

sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

### Step 5 — 자동 시작 설정

```bash
sudo systemctl enable docker nginx cloudflared
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

입력 항목:

```
🔑 Groq API Key        → gsk_... 형식
🔑 Twilio Auth Token   → Twilio 콘솔에서 확인
🔑 Twilio Account SID  → ACc2d... 형식
📱 Twilio 전화번호     → +1802xxxxxxx 형식
📲 내 전화번호         → +821012345678 형식 (010 → +8210)
🌐 서버 도메인         → https://내도메인.com
👤 관리자 이메일       → admin@내도메인.com
🔑 관리자 비밀번호     → 안전한 비밀번호
🤖 봇 모드             → 2 권장 (Enter 하면 자동으로 2번 선택)
🔢 PIN 6자리           → 모르는 번호 인증용
```

> 각 항목은 120초 내 입력 후 Enter. 그냥 Enter 하면 기본값 적용.

### Step 8 — 설치 완료 확인

```bash
cd ~/openapi-rag
docker compose ps
curl http://localhost:5000/health
```

---

## ⚠️ "전화 어시스턴트" Tool 자동 등록 실패 시 수동 등록

설치 후 채팅창에 전화 어시스턴트 도구가 안 보이면 아래 명령어로 수동 등록하세요.

### 수동 등록 방법

**① JWT 토큰 획득 (이메일/비밀번호를 실제값으로 변경)**

```bash
OW_JWT=$(curl -s -X POST http://localhost:3000/api/v1/auths/signin \
  -H "Content-Type: application/json" \
  -d '{"email":"설치시이메일","password":"설치시비밀번호"}' \
  | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

echo "JWT: ${OW_JWT:0:20}..."
```

JWT 값이 나오면 ✅ 다음 단계 진행

**② Tool 등록**

```bash
python3 /tmp/register_tool.py "$OW_JWT"
```

`✅ 등록완료: 전화 어시스턴트` 가 나오면 성공!

**③ /tmp/register_tool.py 파일이 없을 경우 직접 생성**

```bash
cat > /tmp/register_tool.py << 'PYEOF'
import json, urllib.request, sys

jwt = sys.argv[1]

tool_code = '''\
"""
title: 전화 어시스턴트
author: AI Phone Bot
description: 관리자한테 전화 걸기, 안부전화, 연락처 저장/삭제/조회
version: 1.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def call_me(self) -> str:
        """관리자한테 전화를 걸어줍니다. 나한테 전화해줘 명령에 사용."""
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/call-me", json={}, timeout=10)
            return r.json().get("message", "전화를 걸었습니다.")
        except Exception as e:
            return f"오류: {e}"

    def call_contact(self, name: str, mission: str = "안부 확인") -> str:
        """저장된 연락처에게 안부전화를 걸어줍니다.
        Args:
            name: 연락처 이름 예: 김철수
            mission: 전화 목적 예: 안부 확인
        """
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/call-contact",
                            json={"name": name, "mission": mission}, timeout=10)
            return r.json().get("message", f"{name}님께 전화를 걸었습니다.")
        except Exception as e:
            return f"오류: {e}"

    def get_contacts(self) -> str:
        """저장된 연락처 목록을 전체 조회합니다."""
        try:
            r = requests.get(f"{TOOL_SERVER}/tools/contacts", timeout=10)
            data = r.json()
            contacts = data.get("contacts", {})
            if not contacts:
                return "저장된 연락처가 없습니다."
            result = f"저장된 연락처 {len(contacts)}명:\\n"
            for name, number in contacts.items():
                display = number.replace("+82", "0") if number.startswith("+82") else number
                result += f"- {name}: {display}\\n"
            return result
        except Exception as e:
            return f"오류: {e}"

    def save_contact(self, name: str, number: str) -> str:
        """연락처를 저장합니다. 재시작 후에도 유지됩니다.
        Args:
            name: 저장할 이름 예: 김철수
            number: 전화번호 예: 010-1234-5678
        """
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/contacts/add",
                            json={"name": name, "number": number}, timeout=10)
            return r.json().get("message", f"{name}님 번호를 저장했습니다.")
        except Exception as e:
            return f"오류: {e}"

    def delete_contact(self, name: str) -> str:
        """연락처를 삭제합니다.
        Args:
            name: 삭제할 이름 예: 김철수
        """
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/contacts/delete",
                            json={"name": name, "number": ""}, timeout=10)
            return r.json().get("message", f"{name}님 연락처를 삭제했습니다.")
        except Exception as e:
            return f"오류: {e}"
'''

payload = {
    "id": "phone_assistant",
    "name": "전화 어시스턴트",
    "description": "전화 걸기, 안부전화, 연락처 저장/삭제/조회",
    "content": tool_code,
    "meta": {
        "description": "전화 걸기, 안부전화, 연락처 저장/삭제/조회",
        "manifest": {}
    }
}

req = urllib.request.Request(
    "http://localhost:3000/api/v1/tools/create",
    data=json.dumps(payload).encode(),
    headers={
        "Authorization": f"Bearer {jwt}",
        "Content-Type": "application/json"
    },
    method="POST"
)
try:
    with urllib.request.urlopen(req) as resp:
        d = json.loads(resp.read())
        print("✅ 등록완료:", d.get("name", ""))
except urllib.error.HTTPError as e:
    print("❌ 실패:", e.read().decode()[:200])
except Exception as e:
    print("❌ 오류:", str(e))
PYEOF

# JWT 토큰 획득 후 등록 (이메일/비밀번호 실제값으로 변경)
OW_JWT=$(curl -s -X POST http://localhost:3000/api/v1/auths/signin \
  -H "Content-Type: application/json" \
  -d '{"email":"설치시이메일","password":"설치시비밀번호"}' \
  | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

python3 /tmp/register_tool.py "$OW_JWT"
```

---

## ✅ Tool 등록 후 활성화

```
https://내도메인.com 접속
→ 채팅창 하단 🔧 아이콘 클릭
→ "전화 어시스턴트" 토글 ON
```

---

## 💬 채팅창 사용 방법

```
"나한테 전화해줘"                      → AI가 관리자에게 전화 📞
"김철수 010-1234-5678 저장해줘"        → 연락처 영구 저장 ✅
"저장된 연락처 알려줘"                 → 전체 목록 출력 ✅
"김철수 연락처 삭제해줘"               → 연락처 삭제 ✅
"김철수한테 안부전화 해줘"             → AI가 대신 전화 후 결과 보고 ✅
"김철수한테 모임 참석 여부 확인해줘"   → 임무 지정 안부전화 ✅
```

---

## 📞 전화 음성 명령 (관리자만)

```
Twilio 번호로 전화 → PIN 없이 바로 AI 연결
"나한테 전화해줘"
"김철수한테 안부전화 해줘"
"김철수 번호 010-1234-5678 저장해줘"
"연락처 목록 알려줘"
"김철수 연락처 삭제해줘"
```

---

## 🔄 안부전화 흐름

```
"김철수한테 안부전화 해줘"
        ↓
AI가 임무/인사말 자동 생성
        ↓
김철수님 번호로 발신 📞
        ├── 받으면 → AI가 대화 → SMS + 전화 보고
        └── 30초 안받으면 → SMS + 전화 보고
              "김철수님이 전화를 받지 않았습니다"
```

---

## ⌨️ curl 명령어

```bash
# API_SECRET 확인
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

# 연락처 전체 조회
curl http://localhost:5000/contacts \
     -H "X-API-Secret: [API_SECRET]"

# 연락처 삭제
curl -X POST http://localhost:5000/contacts/delete \
     -H "X-API-Secret: [API_SECRET]" \
     -H "Content-Type: application/json" \
     -d '{"name":"김철수"}'
```

---

## 🔧 관리 명령어

```bash
cd ~/openapi-rag
docker compose ps                          # 상태 확인
docker compose logs -f twilio-bot          # 봇 로그
docker compose restart twilio-bot          # 봇 재시작
docker compose restart                     # 전체 재시작
docker compose down && docker compose up -d # 전체 재시작
curl http://localhost:5000/health          # 헬스체크
```

---

## 🆘 문제 해결

### 전화가 안 올 때
```bash
sudo systemctl status nginx cloudflared
curl -s https://내도메인.com/health
```

### 채팅창 Tool 오류
```bash
docker logs openapi-rag-openapi-tools-1 --tail 20
docker logs twilio-bot --tail 20
```

### BOT_MODE 변경 (2번 권장)
```bash
sed -i 's/- BOT_MODE=1/- BOT_MODE=2/' ~/openapi-rag/docker-compose.yml
cd ~/openapi-rag && docker compose up -d twilio-bot
```

---

## ⚠️ 주의사항

- **PC를 끄면 서비스 중단!** → `sudo systemctl enable cloudflared nginx docker`
- **Twilio 요금**: 전화 수신 $0.0085/분, 발신 $0.014/분, SMS $0.0083/건
- **안부전화 1회** 약 $0.10 (약 140원)

---

## 📦 시스템 구성

```
전화 수신/발신 ↕ Twilio ↕ Cloudflare Tunnel ↕ Nginx
  ├── twilio-bot    (:5000) — AI 전화 처리
  ├── OpenWebUI     (:3000) — 채팅 인터페이스
  ├── openapi-tools (:8000) — RAG + 전화 Tool API
  └── Qdrant        (:6333) — 벡터 DB
```

---

## 📄 라이센스

MIT License

*Powered by OpenWebUI + Twilio + Groq + Qdrant + Cloudflare*
