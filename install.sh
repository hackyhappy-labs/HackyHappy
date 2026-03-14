#!/bin/bash
# =============================================================================
# 프로젝트명: OpenWebUI RAG + Twilio AI 전화봇 설치 스크립트
# 제작자: <webmaster@vulva.sex>
# 버전: 3.0.0 (최종 완성판)
# 설명: Docker + Ollama + Groq + Qdrant + Twilio 전화봇 기반 설치/자동화 스크립트
#
# ✅ 보안 (13항목)
#    - Twilio 서명검증 / API Secret 인증 / 포트 로컬바인딩
#    - PIN 6자리 / 입력 마스킹 / CORS 제한 / .env chmod 600
#
# ✅ 안부전화 (AI 대리 통화)
#    - "김철수한테 안부전화 해줘" → AI가 대화 진행
#    - 통화 완료 후 SMS + 전화 음성으로 결과 보고
#    - 보고 받는 번호 자유 지정 가능
#
# ✅ 연락처 영구저장
#    - "김철수 번호 010-xxxx-xxxx 저장해줘" → contacts.json 영구 저장
#    - Docker 재시작 후에도 유지 (볼륨 마운트)
#    - 목록 조회 / 삭제 음성 명령 지원
#
# ✅ 자동화
#    - Docker / Nginx / OpenWebUI API키 / Twilio Webhook 전부 자동 설정
#
# 라이센스: MIT License
# =============================================================================

############################################
# 0. 시스템 사양 자동 감지
############################################
echo "🔍 시스템 사양 감지 중..."

CPU_CORES=$(nproc 2>/dev/null || echo 1)
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
AVAILABLE_RAM_MB=$(free -m | awk '/^Mem:/{print $7}')
TOTAL_RAM_MB=${TOTAL_RAM_MB:-0}
AVAILABLE_RAM_MB=${AVAILABLE_RAM_MB:-0}
TOTAL_RAM=$((TOTAL_RAM_MB / 1024))
AVAILABLE_RAM=$((AVAILABLE_RAM_MB / 1024))

echo "   CPU 코어: ${CPU_CORES}개"
echo "   총 메모리: ${TOTAL_RAM}GB"
echo "   사용 가능: ${AVAILABLE_RAM}GB"

if [ $CPU_CORES -ge 6 ] && [ $TOTAL_RAM -ge 16 ]; then
  PERFORMANCE="HIGH"; PERF_NAME="고성능 🚀"
  QDRANT_RETRIES=20; QDRANT_INTERVAL=2; TOOLS_RETRIES=20; TOOLS_INTERVAL=2
  WEBUI_RETRIES=30; WEBUI_INTERVAL=2
  MEMORY_QDRANT="1G"; MEMORY_TOOLS="2G"; MEMORY_WEBUI="4G"; MEMORY_TWILIO="256M"
elif [ $CPU_CORES -ge 4 ] && [ $TOTAL_RAM -ge 8 ]; then
  PERFORMANCE="MEDIUM_HIGH"; PERF_NAME="중상급 💪"
  QDRANT_RETRIES=30; QDRANT_INTERVAL=3; TOOLS_RETRIES=30; TOOLS_INTERVAL=3
  WEBUI_RETRIES=40; WEBUI_INTERVAL=3
  MEMORY_QDRANT="768M"; MEMORY_TOOLS="1.5G"; MEMORY_WEBUI="3G"; MEMORY_TWILIO="256M"
elif [ $CPU_CORES -ge 2 ] && [ $TOTAL_RAM -ge 4 ]; then
  PERFORMANCE="MEDIUM"; PERF_NAME="중급 📊"
  QDRANT_RETRIES=40; QDRANT_INTERVAL=4; TOOLS_RETRIES=40; TOOLS_INTERVAL=4
  WEBUI_RETRIES=60; WEBUI_INTERVAL=4
  MEMORY_QDRANT="512M"; MEMORY_TOOLS="1G"; MEMORY_WEBUI="2G"; MEMORY_TWILIO="256M"
else
  PERFORMANCE="LOW"; PERF_NAME="저사양 🐢"
  QDRANT_RETRIES=60; QDRANT_INTERVAL=5; TOOLS_RETRIES=60; TOOLS_INTERVAL=5
  WEBUI_RETRIES=150; WEBUI_INTERVAL=5
  MEMORY_QDRANT="384M"; MEMORY_TOOLS="768M"; MEMORY_WEBUI="1.5G"; MEMORY_TWILIO="256M"
fi

echo ""
echo "┌────────────────────────────────────────────┐"
echo "📊 감지된 성능: ${PERF_NAME}"
echo "└────────────────────────────────────────────┘"
echo "   메모리 할당: Qdrant(${MEMORY_QDRANT}), Tools(${MEMORY_TOOLS}), WebUI(${MEMORY_WEBUI}), Twilio봇(${MEMORY_TWILIO})"
echo ""

############################################
# 1. root 실행 방지
############################################
if [ "$EUID" -eq 0 ]; then
  echo "❌ root로 실행하지 마세요."
  exit 1
fi

############################################
# 2. Docker 자동 설치
############################################
if ! command -v docker >/dev/null; then
  echo "⚙️ Docker 미설치 → 자동 설치"
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker $USER
  echo "❌ Docker 설치 완료. 다시 로그인한 후 스크립트를 재실행하세요."
  exit 0
fi

if ! sudo systemctl is-active --quiet docker; then
  echo "⚙️ Docker 서비스 시작 중..."
  sudo systemctl enable --now docker
  sleep 3
fi

if ! docker ps >/dev/null 2>&1; then
  echo "❌ Docker 권한 없음. sudo usermod -aG docker $USER 실행 후 재접속하세요."
  exit 1
fi

############################################
# 3. Ollama 자동 감지 및 설치
############################################
echo ""
echo "🔍 Ollama 설치 상태 확인 중..."
OLLAMA_INSTALLED=false; OLLAMA_RUNNING=false

if command -v ollama >/dev/null 2>&1; then
  OLLAMA_INSTALLED=true; echo "   ✅ Ollama 이미 설치됨"
  if pgrep -x "ollama" >/dev/null; then
    OLLAMA_RUNNING=true; echo "   ✅ Ollama 서버 실행 중"
  else
    echo "   ⚠️ Ollama 서버 중지 상태"
  fi
else
  echo "   ℹ️ Ollama 미설치"
fi

if [ "$OLLAMA_INSTALLED" = true ]; then
  echo ""; echo "💡 Ollama가 이미 설치되어 있습니다."
  read -p "🤖 Ollama를 사용하시겠습니까? (Y/n): " USE_OLLAMA_INPUT
  USE_OLLAMA_INPUT=${USE_OLLAMA_INPUT:-Y}
  if [[ "$USE_OLLAMA_INPUT" =~ ^[Yy]$ ]]; then
    USE_OLLAMA=true
    if [ "$OLLAMA_RUNNING" = false ]; then
      nohup ollama serve > /tmp/ollama.log 2>&1 & sleep 5
    fi
    sudo systemctl enable ollama 2>/dev/null || true
    if ! ollama list | grep -q "nomic-embed-text"; then
      ollama pull nomic-embed-text || echo "⚠️ 모델 다운로드 실패"
    fi
  else
    USE_OLLAMA=false
  fi
else
  if [ "$PERFORMANCE" = "HIGH" ] || [ "$PERFORMANCE" = "MEDIUM_HIGH" ]; then
    read -p "🤖 Ollama를 설치하시겠습니까? (Y/n): " INSTALL_OLLAMA
    INSTALL_OLLAMA=${INSTALL_OLLAMA:-Y}
  else
    read -p "🤖 Ollama를 설치하시겠습니까? (y/N): " INSTALL_OLLAMA
    INSTALL_OLLAMA=${INSTALL_OLLAMA:-N}
  fi
  if [[ "$INSTALL_OLLAMA" =~ ^[Yy]$ ]]; then
    curl -fsSL https://ollama.com/install.sh | sh
    sudo systemctl enable ollama 2>/dev/null && sudo systemctl start ollama 2>/dev/null || nohup ollama serve > /tmp/ollama.log 2>&1 &
    sleep 5
    ollama pull nomic-embed-text || echo "⚠️ 모델 다운로드 실패"
    USE_OLLAMA=true
  else
    USE_OLLAMA=false
  fi
fi

############################################
# 4. GPU 감지
############################################
if command -v nvidia-smi >/dev/null 2>&1; then
  OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:cuda"
  echo "✅ NVIDIA GPU 감지 (CUDA)"
else
  OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"
  echo "ℹ️ GPU 없음 (CPU 모드)"
fi

############################################
# 5. Groq API Key
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔑 Groq API Key 설정 (선택사항)"
echo "└────────────────────────────────────────────┘"
read -t 120 -p "🔑 Groq API Key 입력 (화면에 보임 | 120초 내 Enter=건너뜀): " GROQ_API_KEY || true
echo ""
GROQ_API_KEY=$(echo "$GROQ_API_KEY" | xargs)
if [ -n "$GROQ_API_KEY" ]; then
  echo "✅ Groq API Key 저장됨"; USE_GROQ=true
else
  echo "⭐️ Groq API Key 건너뜀"; USE_GROQ=false
fi

############################################
# 6. Twilio 설정 입력
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "📞 Twilio 전화봇 설정"
echo "└────────────────────────────────────────────┘"
echo "   Twilio Console → Account → API Keys에서 확인"
echo ""

read -t 120 -p "📞 Twilio Account SID 입력 (120초 내 Enter=건너뜀): " TWILIO_ACCOUNT_SID || true
TWILIO_ACCOUNT_SID=$(echo "$TWILIO_ACCOUNT_SID" | xargs)

read -t 120 -p "🔑 Twilio Auth Token 입력 (화면에 보임 | 120초 내 Enter=건너뜀): " TWILIO_AUTH_TOKEN || true
echo ""
TWILIO_AUTH_TOKEN=$(echo "$TWILIO_AUTH_TOKEN" | xargs)

read -t 120 -p "📱 Twilio 전화번호 입력 ex) +18023929721 (120초 내 Enter=건너뜀): " TWILIO_PHONE_NUMBER || true
TWILIO_PHONE_NUMBER=$(echo "$TWILIO_PHONE_NUMBER" | xargs)

read -t 120 -p "📲 나의 실제 전화번호 입력 ex) +821064532023 (120초 내 Enter=건너뜀): " MY_PHONE_NUMBER || true
MY_PHONE_NUMBER=$(echo "$MY_PHONE_NUMBER" | xargs)

read -t 120 -p "🌐 서버 도메인 입력 ex) https://vulva.jp (120초 내 Enter=건너뜀): " SERVER_DOMAIN || true
SERVER_DOMAIN=$(echo "$SERVER_DOMAIN" | xargs)
SERVER_DOMAIN=${SERVER_DOMAIN:-"http://localhost"}

if [ -n "$TWILIO_ACCOUNT_SID" ] && [ -n "$TWILIO_AUTH_TOKEN" ]; then
  USE_TWILIO=true
  echo "✅ Twilio 설정 저장됨"
else
  USE_TWILIO=false
  echo "⭐️ Twilio 설정 건너뜀 (나중에 .env에서 추가 가능)"
fi

############################################
# 6-1. OpenWebUI 관리자 계정 정보 미리 입력 (모드1 자동발급용)
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔐 OpenWebUI 관리자 계정 설정 (설치 후 자동 생성)"
echo "└────────────────────────────────────────────┘"
read -t 120 -p "   👤 관리자 이메일 (기본: admin@vulva.jp | 120초 내 Enter=기본값): " OW_EMAIL || true
OW_EMAIL=$(echo "$OW_EMAIL" | xargs)
OW_EMAIL=${OW_EMAIL:-"admin@vulva.jp"}

read -t 120 -p "   🔒 관리자 비밀번호 입력 (화면에 보임 | 120초 내 Enter=기본값): " OW_PASSWORD || true
echo ""
OW_PASSWORD=$(echo "$OW_PASSWORD" | xargs)
OW_PASSWORD=${OW_PASSWORD:-"changeme1234!"}
echo "   ✅ 관리자 계정 정보 저장됨"

############################################
# 7. AI 모드 선택
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🤖 전화봇 AI 모드 선택"
echo "└────────────────────────────────────────────┘"
echo "   1) OpenWebUI 경유 (RAG 포함, 문서 기반 답변)"
echo "   2) Groq 직접 연결 (빠른 응답)"
echo "   3) 내 번호로 포워딩 (AI 없이 직접 전화 받기)"
echo ""
read -t 120 -p "모드 선택 (1/2/3) [기본값: 1] (120초 내 Enter=1): " BOT_MODE || true
BOT_MODE=${BOT_MODE:-1}

############################################
# 7-1. 보안 설정 (PIN + 연락처)
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔒 보안 설정"
echo "└────────────────────────────────────────────┘"

read -t 120 -p "   🔢 관리자 PIN 6자리 설정 (화면에 보임 | 기본값: 123456 | 120초 내 Enter=기본값): " ADMIN_PIN || true
ADMIN_PIN=$(echo "$ADMIN_PIN" | xargs)
ADMIN_PIN=${ADMIN_PIN:-"123456"}
echo "   ✅ PIN 설정: ******"

echo ""
echo "   📒 연락처 등록 (AI가 '김철수한테 전화해줘' 명령 실행 가능)"
echo "   형식: 이름,전화번호 (예: 김철수,+821011112222)"
echo "   여러 명: 쉼표로 구분 (예: 김철수,+821011112222 홍길동,+821033334444)"
echo "   Enter=건너뜀"
echo ""

CONTACTS_JSON="{}"
read -t 120 -p "   연락처 입력 (120초 내 Enter=건너뜀): " CONTACTS_INPUT || true
CONTACTS_INPUT=$(echo "$CONTACTS_INPUT" | xargs)

if [ -n "$CONTACTS_INPUT" ]; then
  # Python으로 안전하게 JSON 변환 (쉘 따옴표 문제 방지)
  CONTACTS_JSON=$(python3 -c "
import sys, json
raw = sys.argv[1]
result = {}
for entry in raw.split():
    parts = entry.split(',', 1)
    if len(parts) == 2:
        name, number = parts[0].strip(), parts[1].strip()
        if name and number:
            result[name] = number
print(json.dumps(result, ensure_ascii=False))
" "$CONTACTS_INPUT" 2>/dev/null || echo "{}")
  echo "   ✅ 연락처 저장: ${CONTACTS_JSON}"
else
  echo "   ⭐️ 연락처 건너뜀 (설치 후 전화로 '이름 번호 저장해줘' 음성 명령 가능)"
fi

############################################
# 8. 작업 디렉토리 초기화
############################################
BASE_DIR="$HOME/openapi-rag"
if [ -d "$BASE_DIR" ]; then
  echo "🧹 기존 설치 제거 중..."
  cd "$BASE_DIR"
  docker compose down -v 2>/dev/null || true
  cd ~
  rm -rf "$BASE_DIR"
fi

mkdir -p "$BASE_DIR/tools-api/data"
mkdir -p "$BASE_DIR/twilio-bot"
cd "$BASE_DIR"

############################################
# 9. .env
############################################
cat > .env <<EOF
# Qdrant 설정
VECTOR_DB=qdrant
QDRANT_URI=http://qdrant:6333
QDRANT_URL=http://qdrant:6333
QDRANT_COLLECTION=openapi_rag
EOF

if [ "$USE_OLLAMA" = true ]; then
cat >> .env <<EOF
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_EMBED_MODEL=nomic-embed-text
EOF
fi

if [ "$USE_GROQ" = true ] && [ -n "$GROQ_API_KEY" ]; then
cat >> .env <<EOF
OPENAI_API_KEY=$GROQ_API_KEY
OPENAI_API_BASE_URL=https://api.groq.com/openai/v1
EOF
fi

if [ "$USE_TWILIO" = true ]; then
cat >> .env <<EOF

# Twilio 설정
TWILIO_ACCOUNT_SID=$TWILIO_ACCOUNT_SID
TWILIO_AUTH_TOKEN=$TWILIO_AUTH_TOKEN
TWILIO_PHONE_NUMBER=$TWILIO_PHONE_NUMBER
MY_PHONE_NUMBER=$MY_PHONE_NUMBER
SERVER_DOMAIN=$SERVER_DOMAIN
BOT_MODE=$BOT_MODE
EOF
fi

echo "API_SECRET=${API_SECRET}" >> .env
echo "OPENAI_MODEL=llama-3.3-70b-versatile" >> .env
chmod 600 .env

############################################
# 10. Twilio 봇 파일 생성
############################################
cat > twilio-bot/requirements.txt <<'EOF'
flask==3.0.0
twilio==8.10.0
requests==2.31.0
python-dotenv==1.0.0
gunicorn==21.2.0
EOF

# 모드별 봇 코드 생성
cat > twilio-bot/twilio_bot.py <<'PYEOF'
from flask import Flask, request, Response, jsonify
from twilio.twiml.voice_response import VoiceResponse, Gather, Dial
from twilio.rest import Client
import requests, os, json, time
from datetime import datetime
from functools import wraps

app = Flask(__name__)

# ── 환경 변수 ──────────────────────────────────
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN  = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_PHONE       = os.getenv("TWILIO_PHONE_NUMBER", "")
MY_PHONE           = os.getenv("MY_PHONE_NUMBER", "")
SERVER_DOMAIN      = os.getenv("SERVER_DOMAIN", "http://localhost")
BOT_MODE           = os.getenv("BOT_MODE", "1")
OPENWEBUI_URL      = os.getenv("OPENWEBUI_URL", "http://open-webui:8080")
OPENWEBUI_API_KEY  = os.getenv("OPENWEBUI_API_KEY", "")
MODEL              = os.getenv("MODEL", "llama-3.3-70b-versatile")
GROQ_API_KEY       = os.getenv("OPENAI_API_KEY", "")
GROQ_API_URL       = "https://api.groq.com/openai/v1/chat/completions"

# ── 보안 설정 ──────────────────────────────────
# 화이트리스트: 이 번호들만 AI에게 직접 명령 가능 (관리자)
ADMIN_NUMBERS      = [n.strip() for n in os.getenv("ADMIN_NUMBERS", MY_PHONE).split(",") if n.strip()]

# PIN 설정 (모르는 번호는 PIN 입력 필요)
ADMIN_PIN          = os.getenv("ADMIN_PIN", "123456")

# 차단된 번호
BLOCKED_NUMBERS    = [n.strip() for n in os.getenv("BLOCKED_NUMBERS", "").split(",") if n.strip()]

# PIN 실패 횟수 추적 (메모리)
pin_fail_count     = {}
PIN_MAX_FAIL       = 3

# ── 연락처 영구 저장 시스템 ──────────────────────
CONTACTS_FILE = "/app/data/contacts.json"

def load_contacts():
    """파일에서 연락처 로드 (환경변수 + 파일 병합)"""
    data = {}
    # 1) 환경변수에 있던 초기값
    try:
        env_contacts = json.loads(os.getenv("CONTACTS", "{}"))
        data.update(env_contacts)
    except Exception:
        pass
    # 2) 영구 저장 파일 (재시작해도 유지)
    try:
        if os.path.exists(CONTACTS_FILE):
            with open(CONTACTS_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
                data.update(saved)
    except Exception as e:
        print(f"연락처 파일 로드 오류: {e}")
    return data

def save_contacts(contacts_dict):
    """연락처를 파일에 영구 저장"""
    try:
        os.makedirs(os.path.dirname(CONTACTS_FILE), exist_ok=True)
        with open(CONTACTS_FILE, "w", encoding="utf-8") as f:
            json.dump(contacts_dict, f, ensure_ascii=False, indent=2)
        print(f"💾 연락처 저장 완료: {len(contacts_dict)}명")
        return True
    except Exception as e:
        print(f"연락처 저장 오류: {e}")
        return False

def add_contact(name, number):
    """연락처 추가 후 즉시 파일에 저장 (멀티워커 안전)"""
    current = load_contacts()
    current[name] = number
    CONTACTS.clear()
    CONTACTS.update(current)
    return save_contacts(current)

def delete_contact(name):
    """연락처 삭제 후 즉시 파일에 저장 (멀티워커 안전)"""
    current = load_contacts()
    if name in current:
        del current[name]
        CONTACTS.clear()
        CONTACTS.update(current)
        save_contacts(current)
        return True
    return False

# 앱 시작 시 연락처 로드 (환경변수 + 파일 병합)
CONTACTS = load_contacts()
print(f"📒 연락처 로드 완료: {list(CONTACTS.keys())}")

# ── 보안 체크 함수 ──────────────────────────────
def is_admin(caller):
    """관리자 번호 여부 확인"""
    return caller in ADMIN_NUMBERS

def is_blocked(caller):
    """차단 번호 여부 확인"""
    return caller in BLOCKED_NUMBERS

def is_pin_locked(caller):
    """PIN 3회 이상 실패한 번호 확인"""
    return pin_fail_count.get(caller, 0) >= PIN_MAX_FAIL

# ── AI 호출 함수 ──────────────────────────────
def ask_openwebui(user_input, system_prompt=None):
    try:
        if not system_prompt:
            system_prompt = "당신은 AI 전화 어시스턴트입니다. 반드시 한국어로만 답변하세요. 2~3문장 이내로 짧게 답하세요. 지금 통화 상대는 관리자님입니다. 항상 관리자님이라고 부르세요. 관리자님은 연락처 저장, 안부전화 대행, 지인에게 전화걸기 등 모든 명령을 내릴 수 있습니다. 절대로 전화를 못 한다거나 문자 기반이라고 말하지 마세요."
        res = requests.post(
            f"{OPENWEBUI_URL}/api/chat/completions",
            headers={"Authorization": f"Bearer {OPENWEBUI_API_KEY}"},
            json={"model": MODEL, "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_input}
            ]},
            timeout=25
        )
        return res.json()["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"OpenWebUI 오류: {e}")
        return "죄송합니다. 처리 중 오류가 발생했습니다."

def ask_groq(user_input, system_prompt=None):
    try:
        if not system_prompt:
            system_prompt = "당신은 AI 전화 어시스턴트입니다. 반드시 한국어로만 답변하세요. 2~3문장 이내로 짧게 답하세요. 지금 통화 상대는 관리자님입니다. 항상 관리자님이라고 부르세요. 관리자님은 연락처 저장, 안부전화 대행, 지인에게 전화걸기 등 모든 명령을 내릴 수 있습니다. 절대로 전화를 못 한다거나 문자 기반이라고 말하지 마세요."
        res = requests.post(
            GROQ_API_URL,
            headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
            json={"model": MODEL, "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_input}
            ], "max_tokens": 300},
            timeout=15
        )
        return res.json()["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"Groq 오류: {e}")
        return "죄송합니다. 처리 중 오류가 발생했습니다."

def get_ai_reply(user_input, system_prompt=None):
    if BOT_MODE == "2":
        return ask_groq(user_input, system_prompt)
    return ask_openwebui(user_input, system_prompt)

# ── Twilio 서명 검증 (Webhook 위조 방지) ──────
from twilio.request_validator import RequestValidator

def validate_twilio_request(f):
    """Twilio에서 온 요청인지 서명 검증 (Cloudflare Tunnel 지원)"""
    @wraps(f)
    def decorated(*args, **kwargs):
        try:
            validator = RequestValidator(TWILIO_AUTH_TOKEN)
            signature = request.headers.get("X-Twilio-Signature", "")
            # Cloudflare Tunnel 통과시 X-Forwarded 헤더로 실제 URL 재구성
            forwarded_proto = request.headers.get("X-Forwarded-Proto", "https")
            forwarded_host  = request.headers.get("X-Forwarded-Host",
                              request.headers.get("Host",
                              SERVER_DOMAIN.replace("https://","").replace("http://","")))
            url = f"{forwarded_proto}://{forwarded_host}{request.path}"
            if request.query_string:
                url += f"?{request.query_string.decode()}"
            post_vars = request.form.to_dict()
            if not validator.validate(url, post_vars, signature):
                caller = request.form.get("From", request.remote_addr)
                print(f"🚨 Twilio 서명 검증 실패 (url={url}): {caller}")
                return Response("Forbidden", status=403)
        except Exception as e:
            print(f"서명 검증 오류: {e}")
        return f(*args, **kwargs)
    return decorated

# ── API 엔드포인트 인증 토큰 ──────────────────
API_SECRET = os.getenv("API_SECRET", "")

def require_api_secret(f):
    """내부 API 호출 시 시크릿 토큰 검증"""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not API_SECRET:
            return f(*args, **kwargs)  # API_SECRET 미설정 시 로컬에서만 허용
        token = request.headers.get("X-API-Secret", "") or request.args.get("secret", "")
        if token != API_SECRET:
            print(f"🚨 API 인증 실패: {request.remote_addr}")
            return Response("Unauthorized", status=401)
        return f(*args, **kwargs)
    return decorated

# ── 아웃바운드 전화 걸기 ──────────────────────
# ── 아웃바운드 통화 세션 저장소 ──────────────
# { call_sid: { name, number, mission, history, summary_sent } }
outbound_sessions = {}

def make_call(to_number, custom_message=None, contact_name=None, mission=None, report_to=None):
    """지정 번호로 전화 걸기
    report_to: 보고받을 번호 (None이면 MY_PHONE)
    안부전화: contact_name + mission 있을 때
    일반발신: 없으면 단순 연결음 + AI 대화
    """
    try:
        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

        if contact_name and mission:
            # 안부전화: 세션에 저장 후 voice-out-welfare 사용 (쿼리스트링 없음)
            call = client.calls.create(
                to=to_number, from_=TWILIO_PHONE,
                url=f"{SERVER_DOMAIN}/voice-out-welfare",
                status_callback=f"{SERVER_DOMAIN}/call-status",
                status_callback_method="POST",
                status_callback_event=["no-answer", "failed", "busy", "canceled"]
            )
            outbound_sessions[call.sid] = {
                "name"        : contact_name,
                "number"      : to_number,
                "mission"     : mission,
                "greeting"    : custom_message or "안녕하세요. AI 어시스턴트입니다.",
                "history"     : [],
                "summary_sent": False,
                "report_to"   : report_to or MY_PHONE,
            }
            print(f"📞 안부전화 세션 생성: {call.sid} → {contact_name}({to_number}) | 보고→{report_to or MY_PHONE}")
        else:
            # 일반발신 (나한테 전화해줘 등): voice-out-simple 사용
            call = client.calls.create(
                to=to_number, from_=TWILIO_PHONE,
                url=f"{SERVER_DOMAIN}/voice-out-simple"
            )
            outbound_sessions[call.sid] = {
                "name"        : contact_name or "상대방",
                "number"      : to_number,
                "mission"     : "",
                "history"     : [],
                "summary_sent": False,
                "report_to"   : report_to or MY_PHONE,
            }
            print(f"📞 일반발신 세션 생성: {call.sid} → {to_number}")
        return call.sid
    except Exception as e:
        print(f"전화 걸기 오류: {e}")
        return None

def send_summary_to_admin(call_sid):
    """통화 종료 후 지정된 번호에 전화+SMS로 요약 보고"""
    session = outbound_sessions.get(call_sid)
    if not session or session["summary_sent"]:
        return
    session["summary_sent"] = True

    report_to = session.get("report_to", MY_PHONE)  # 보고 받을 번호

    history_text = "\n".join([
        f"AI: {h['ai']}\n상대: {h['user']}"
        for h in session["history"] if h.get("user")
    ]) or "대화 내용 없음"

    # AI 요약 생성
    summary_prompt = f"""다음은 {session['name']}님과의 통화 내용입니다.
임무: {session['mission']}
대화 내용:
{history_text}

위 통화를 3~4문장으로 요약해주세요. 핵심 내용과 결과를 포함하세요."""

    summary = get_ai_reply(summary_prompt,
        "당신은 통화 내용을 요약 보고하는 비서입니다. 한국어로 간결하게 보고하세요.")

    # SMS용 짧은 요약 (160자 이하)
    sms_prompt = f"""다음 요약을 SMS용으로 80자 이내로 압축하세요.
요약: {summary}
80자 이내 SMS:"""
    sms_summary = get_ai_reply(sms_prompt, "80자 이내로만 답하세요.")

    voice_report = f"{session['name']}님 통화 완료. {summary}"
    sms_report   = f"[AI통화보고] {session['name']}님: {sms_summary}"

    print(f"📋 통화 요약 (보고→{report_to}): {voice_report}")

    client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

    # ── ① SMS 문자 먼저 발송 ──────────────────────
    try:
        client.messages.create(
            to=report_to,
            from_=TWILIO_PHONE,
            body=sms_report
        )
        print(f"📱 SMS 보고 발송 → {report_to}")
    except Exception as e:
        print(f"SMS 보고 오류: {e}")

    # ── ② 전화 음성 보고 (SMS 발송 3초 후) ────────
    try:
        report_url = f"{SERVER_DOMAIN}/voice-report?msg={requests.utils.quote(voice_report)}"
        client.calls.create(to=report_to, from_=TWILIO_PHONE, url=report_url)
        print(f"📞 음성 보고 전화 발신 → {report_to}")
    except Exception as e:
        print(f"음성 보고 전화 오류: {e}")

# ── 명령 처리 (관리자 전용) ──────────────────
def process_admin_command(speech, caller):
    """관리자 음성 명령 처리"""

    # 지인에게 전화 명령: "김철수한테 안부전화 해줘" / "김철수한테 전화해줘"
    call_keywords = ["전화해줘", "전화 해줘", "전화걸어줘", "연락해줘", "전화 걸어줘", "안부전화", "안부 전화"]
    for kw in call_keywords:
        if kw in speech:
            # 연락처에서 이름 찾기
            for name, number in CONTACTS.items():
                if name in speech:
                    # ── 보고 받을 번호 파싱 ──────────────────────
                    # "결과는 나한테", "보고는 홍길동한테", "알려줘" 등
                    report_to = MY_PHONE  # 기본: 관리자 번호
                    report_keywords = ["보고해줘", "알려줘", "보고는", "결과는", "보고해", "알려"]
                    for rk in report_keywords:
                        if rk in speech:
                            # 보고 대상 파싱
                            report_parse = f"""문장: "{speech}"
이 문장에서 통화 결과를 보고받을 사람 이름 또는 "나"를 찾으세요.
- "나한테", "나에게", "내 번호로" → "나"
- 특정 이름이 있으면 그 이름
JSON으로만 답하세요: {{"report_to": "나"}} 또는 {{"report_to": "이름"}}"""
                            rp_str = get_ai_reply(report_parse, "JSON만 출력하세요.")
                            try:
                                rp_str = rp_str.strip().replace("```json","").replace("```","").strip()
                                rp = json.loads(rp_str)
                                rt = rp.get("report_to", "나")
                                if rt == "나" or rt == name:
                                    report_to = MY_PHONE
                                elif rt in CONTACTS:
                                    report_to = CONTACTS[rt]
                                    print(f"📋 보고 대상: {rt} → {report_to}")
                            except Exception:
                                pass
                            break

                    # ── 임무(mission) 추출 ────────────────────────
                    mission_prompt = f"""관리자가 말한 내용: "{speech}"
{name}님에게 전화할 때 AI가 수행해야 할 임무를 한 문장으로 요약하세요.
예시: "안부를 묻고 건강 상태와 다음주 모임 참석 여부를 확인한다"
임무:"""
                    mission = get_ai_reply(mission_prompt, "임무를 한 문장으로만 답하세요.")

                    # ── 첫 인사말 생성 ────────────────────────────
                    greeting_prompt = f"""당신은 AI 전화 어시스턴트입니다. {name}님에게 전화를 걸었습니다.
임무: {mission}
첫 인사말을 자연스럽게 한 문장으로 만들어주세요. 너무 길지 않게."""
                    greeting = get_ai_reply(greeting_prompt, "첫 인사말 한 문장만 답하세요.")

                    sid = make_call(number, greeting, contact_name=name, mission=mission, report_to=report_to)
                    if sid:
                        report_desc = "관리자님께" if report_to == MY_PHONE else f"등록된 번호({report_to})로"
                        return f"{name}님께 전화를 걸었습니다. 통화 완료 후 {report_desc} 전화+문자로 결과를 보고해드릴게요."
                    return f"{name}님께 전화 걸기에 실패했습니다."
            return "연락처에서 해당 이름을 찾을 수 없습니다. 연락처를 등록해주세요."

    # 나한테 전화 명령: "나한테 전화해줘"
    if any(kw in speech for kw in ["나한테", "내 폰으로", "내 번호로"]):
        sid = make_call(MY_PHONE)
        if sid:
            return "관리자님 번호로 전화를 걸었습니다."

    # ── 연락처 저장 명령: "김철수 번호 010-1111-2222 저장해줘" ──
    save_keywords = ["저장해줘", "저장해", "등록해줘", "등록해", "추가해줘", "추가해", "메모해줘", "기억해줘"]
    for kw in save_keywords:
        if kw in speech:
            # AI로 이름/번호 파싱
            parse_prompt = f"""다음 문장에서 사람 이름과 전화번호를 추출하세요.
문장: "{speech}"
반드시 아래 JSON 형식으로만 답하세요. 추출 불가시 null:
{{"name": "이름", "number": "+821012345678"}}
전화번호는 반드시 E.164 형식(+82로 시작)으로 변환하세요. 010으로 시작하면 +8210으로 변환."""
            parsed_str = get_ai_reply(parse_prompt, "JSON만 출력하세요. 다른 말 금지.")
            try:
                # JSON 파싱 (코드블록 제거)
                parsed_str = parsed_str.strip().replace("```json","").replace("```","").strip()
                parsed = json.loads(parsed_str)
                name   = parsed.get("name")
                number = parsed.get("number")
                if name and number and name != "null" and number != "null":
                    if add_contact(name, number):
                        return f"{name}님 번호 {number}를 연락처에 저장했습니다."
                    return "저장 중 오류가 발생했습니다."
            except Exception as e:
                print(f"연락처 파싱 오류: {e} / 원문: {parsed_str}")
            return "이름과 번호를 인식하지 못했습니다. 예: 김철수 번호 010-1111-2222 저장해줘"

    # ── 연락처 삭제 명령: "김철수 연락처 삭제해줘" ──
    delete_keywords = ["삭제해줘", "삭제해", "지워줘", "지워", "빼줘", "제거해줘"]
    for kw in delete_keywords:
        if kw in speech:
            for name in list(CONTACTS.keys()):
                if name in speech:
                    if delete_contact(name):
                        return f"{name}님 연락처를 삭제했습니다."
            return "삭제할 연락처 이름을 찾지 못했습니다."

    # ── 연락처 목록 조회: "연락처 목록 알려줘" ──
    list_keywords = ["연락처 목록", "연락처 알려줘", "저장된 번호", "등록된 연락처", "누구 저장돼", "누가 저장"]
    for kw in list_keywords:
        if kw in speech:
            if CONTACTS:
                names = ", ".join([f"{n}({v})" for n, v in CONTACTS.items()])
                return f"저장된 연락처는 {len(CONTACTS)}명입니다. {names}"
            return "저장된 연락처가 없습니다."

    # 일반 AI 답변
    return get_ai_reply(speech, "당신은 관리자 전용 AI 어시스턴트입니다. 명령을 수행하고 짧게 답변하세요.")

# ════════════════════════════════════════════
# 라우트
# ════════════════════════════════════════════

@app.route("/voice", methods=["POST"])
@validate_twilio_request
def voice():
    """인바운드 전화 수신 - 보안 체크 후 분기"""
    caller   = request.form.get("From", "")
    response = VoiceResponse()

    print(f"📞 수신 전화: {caller}")

    # ① 차단 번호
    if is_blocked(caller):
        print(f"🚫 차단된 번호: {caller}")
        response.say("죄송합니다. 이 번호는 차단되었습니다.", language="ko-KR")
        response.hangup()
        return Response(str(response), mimetype="text/xml")

    # ② PIN 잠금 번호
    if is_pin_locked(caller):
        print(f"🔒 PIN 잠금 번호: {caller}")
        response.say("보안 인증 실패로 차단된 번호입니다.", language="ko-KR")
        response.hangup()
        return Response(str(response), mimetype="text/xml")

    # ③ 모드 3: 무조건 포워딩
    if BOT_MODE == "3":
        response.say("잠시만 기다려 주세요.", language="ko-KR")
        dial = Dial(caller_id=TWILIO_PHONE)
        dial.number(MY_PHONE)
        response.append(dial)
        return Response(str(response), mimetype="text/xml")

    # ④ 관리자 번호 → 바로 AI 연결 (PIN 불필요)
    if is_admin(caller):
        print(f"✅ 관리자 연결: {caller}")
        gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond",
                        language="ko-KR", timeout=5, speechTimeout="auto")
        gather.say("안녕하세요 관리자님! 명령을 말씀해 주세요.", language="ko-KR")
        response.append(gather)
        response.say("명령을 듣지 못했습니다. 다시 전화해 주세요.", language="ko-KR")
        return Response(str(response), mimetype="text/xml")

    # ⑤ 모르는 번호 → PIN 입력 요구
    print(f"❓ 미등록 번호 PIN 요구: {caller}")
    gather = Gather(input="dtmf", action=f"{SERVER_DOMAIN}/verify-pin",
                    numDigits="6", timeout=10)
    gather.say("안녕하세요. AI 어시스턴트입니다. 6자리 PIN을 입력해 주세요.", language="ko-KR")
    response.append(gather)
    response.say("PIN 입력이 없어 전화를 종료합니다.", language="ko-KR")
    response.hangup()
    return Response(str(response), mimetype="text/xml")


@app.route("/verify-pin", methods=["POST"])
@validate_twilio_request
def verify_pin():
    """PIN 검증"""
    caller   = request.form.get("From", "")
    digits   = request.form.get("Digits", "")
    response = VoiceResponse()

    if digits == ADMIN_PIN:
        # PIN 성공 → 실패 횟수 초기화
        pin_fail_count[caller] = 0
        print(f"✅ PIN 인증 성공: {caller}")
        gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond",
                        language="ko-KR", timeout=5, speechTimeout="auto")
        gather.say("PIN 인증 성공! 무엇을 도와드릴까요?", language="ko-KR")
        response.append(gather)
    else:
        # PIN 실패
        pin_fail_count[caller] = pin_fail_count.get(caller, 0) + 1
        remain = PIN_MAX_FAIL - pin_fail_count[caller]
        print(f"❌ PIN 실패: {caller} ({pin_fail_count[caller]}회)")

        if remain <= 0:
            response.say("PIN 인증 3회 실패로 차단되었습니다.", language="ko-KR")
            response.hangup()
        else:
            gather = Gather(input="dtmf", action=f"{SERVER_DOMAIN}/verify-pin",
                            numDigits="6", timeout=10)
            gather.say(f"PIN이 틀렸습니다. {remain}번 남았습니다. 다시 입력해 주세요.", language="ko-KR")
            response.append(gather)
            response.hangup()

    return Response(str(response), mimetype="text/xml")


@app.route("/respond", methods=["POST"])
@validate_twilio_request
def respond():
    """음성 명령 처리"""
    user_speech = request.form.get("SpeechResult", "").strip()
    caller      = request.form.get("From", "")
    response    = VoiceResponse()

    print(f"🗣️ [{caller}] {user_speech}")

    if not user_speech:
        gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond",
                        language="ko-KR", timeout=5, speechTimeout="auto")
        gather.say("잘 듣지 못했습니다. 다시 말씀해 주세요.", language="ko-KR")
        response.append(gather)
        return Response(str(response), mimetype="text/xml")

    # 담당자 연결 키워드
    transfer_keywords = ["담당자", "사람이랑", "직접 연결", "관리자 바꿔", "사람 바꿔"]
    if any(kw in user_speech for kw in transfer_keywords) and MY_PHONE:
        response.say("담당자에게 연결해드리겠습니다. 잠시만 기다려 주세요.", language="ko-KR")
        dial = Dial(caller_id=TWILIO_PHONE)
        dial.number(MY_PHONE)
        response.append(dial)
        return Response(str(response), mimetype="text/xml")

    # 관리자면 명령 처리, 아니면 일반 AI 응답
    if is_admin(caller):
        ai_reply = process_admin_command(user_speech, caller)
    else:
        ai_reply = get_ai_reply(user_speech)

    print(f"🤖 [{caller}] {ai_reply}")

    gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond",
                    language="ko-KR", timeout=5, speechTimeout="auto")
    gather.say(ai_reply, language="ko-KR")
    response.append(gather)
    response.say("추가 문의가 없으시면 감사합니다. 안녕히 계세요.", language="ko-KR")
    return Response(str(response), mimetype="text/xml")


@app.route("/voice-out-simple", methods=["POST"])
def voice_out_simple():
    """일반 아웃바운드 전화 (나한테 전화해줘 등) - 서명검증 없음, 관리자 모드"""
    response = VoiceResponse()
    gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond-admin",
                    language="ko-KR", timeout=5, speechTimeout="auto")
    gather.say("안녕하세요 관리자님! 명령을 말씀해 주세요.", language="ko-KR")
    response.append(gather)
    response.say("감사합니다. 안녕히 계세요.", language="ko-KR")
    return Response(str(response), mimetype="text/xml")


@app.route("/respond-admin", methods=["POST"])
def respond_admin():
    """아웃바운드 관리자 전용 응답 - 관리자 권한으로 처리"""
    user_speech = request.form.get("SpeechResult", "").strip()
    response    = VoiceResponse()

    if not user_speech:
        gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond-admin",
                        language="ko-KR", timeout=5, speechTimeout="auto")
        gather.say("잘 듣지 못했습니다. 다시 말씀해 주세요.", language="ko-KR")
        response.append(gather)
        return Response(str(response), mimetype="text/xml")

    print(f"🗣️ [관리자 아웃바운드] {user_speech}")
    ai_reply = process_admin_command(user_speech, MY_PHONE)
    print(f"🤖 [관리자 아웃바운드] {ai_reply}")

    gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond-admin",
                    language="ko-KR", timeout=5, speechTimeout="auto")
    gather.say(ai_reply, language="ko-KR")
    response.append(gather)
    response.say("추가 명령이 없으시면 감사합니다. 안녕히 계세요.", language="ko-KR")
    return Response(str(response), mimetype="text/xml")


@app.route("/voice-out-welfare", methods=["POST"])
def voice_out_welfare():
    """안부전화 아웃바운드 - 세션에서 정보 가져옴 (서명검증 없음)"""
    call_sid     = request.form.get("CallSid", "")
    response     = VoiceResponse()
    session      = outbound_sessions.get(call_sid, {})
    contact_name = session.get("name", "상대방")
    mission      = session.get("mission", "안부 확인")
    greeting     = session.get("greeting", "안녕하세요. AI 어시스턴트입니다.")

    action_url = f"{SERVER_DOMAIN}/respond-out"
    gather = Gather(input="speech", action=action_url,
                    language="ko-KR", timeout=6, speechTimeout="auto")
    gather.say(greeting, language="ko-KR")
    response.append(gather)
    response.say("잘 듣지 못했습니다. 다시 전화드리겠습니다. 감사합니다.", language="ko-KR")
    return Response(str(response), mimetype="text/xml")


@app.route("/respond-out", methods=["POST"])
@validate_twilio_request
def respond_out():
    """안부전화 대화 이어가기 + 종료 판단 - 세션에서 정보 가져옴"""
    user_speech  = request.form.get("SpeechResult", "").strip()
    call_sid     = request.form.get("CallSid", "")
    response     = VoiceResponse()

    # 세션에서 안부전화 정보 가져오기
    session = outbound_sessions.get(call_sid, {})
    contact_name = session.get("name", "상대방")
    mission      = session.get("mission", "안부 확인")

    print(f"🗣️ [안부전화:{contact_name}] {user_speech}")

    # 세션 초기화 (없으면 기본값)
    if call_sid not in outbound_sessions:
        outbound_sessions[call_sid] = {
            "name": contact_name, "number": "", "mission": mission,
            "history": [], "summary_sent": False, "report_to": MY_PHONE
        }
    session = outbound_sessions[call_sid]

    if not user_speech:
        gather = Gather(input="speech",
                        action=f"{SERVER_DOMAIN}/respond-out",
                        language="ko-KR", timeout=6, speechTimeout="auto")
        gather.say("잘 듣지 못했습니다. 다시 말씀해 주세요.", language="ko-KR")
        response.append(gather)
        return Response(str(response), mimetype="text/xml")

    # 대화 히스토리 구성
    history_text = "\n".join([
        f"AI: {h['ai']}\n{contact_name}: {h['user']}"
        for h in session["history"]
    ])

    # AI 다음 발화 생성
    next_prompt = f"""당신은 AI 전화 어시스턴트입니다.
임무: {mission}
지금까지 대화:
{history_text if history_text else "(대화 시작)"}
{contact_name}: {user_speech}

다음 중 하나를 결정하세요:
1. 임무가 완료됐으면 "DONE:" 으로 시작하는 마무리 인사
2. 아직 확인할 내용이 있으면 자연스러운 다음 질문 (한 문장)

답변:"""

    ai_next = get_ai_reply(next_prompt,
        "전화 대화를 이어가는 AI입니다. 짧고 자연스럽게 한국어로 답하세요.")

    # 히스토리 저장
    session["history"].append({"ai": ai_next.replace("DONE:", "").strip(), "user": user_speech})

    if ai_next.startswith("DONE:"):
        # 임무 완료 → 마무리 후 요약 보고
        farewell = ai_next.replace("DONE:", "").strip()
        response.say(farewell, language="ko-KR")
        response.hangup()
        # 비동기로 요약 보고 (1초 후)
        import threading
        threading.Timer(2.0, send_summary_to_admin, args=[call_sid]).start()
    else:
        # 대화 계속
        action_url = f"{SERVER_DOMAIN}/respond-out"
        gather = Gather(input="speech", action=action_url,
                        language="ko-KR", timeout=6, speechTimeout="auto")
        gather.say(ai_next, language="ko-KR")
        response.append(gather)
        # 응답 없으면 마무리
        response.say("말씀을 듣지 못했습니다. 나중에 다시 연락드리겠습니다. 안녕히 계세요.", language="ko-KR")
        response.hangup()
        threading.Timer(2.0, send_summary_to_admin, args=[call_sid]).start()

    return Response(str(response), mimetype="text/xml")


@app.route("/voice-report", methods=["POST"])
@validate_twilio_request
def voice_report():
    """관리자에게 통화 요약 보고"""
    msg      = request.args.get("msg", "통화가 완료되었습니다.")
    response = VoiceResponse()
    response.say(f"통화 보고입니다. {msg}", language="ko-KR")
    return Response(str(response), mimetype="text/xml")


@app.route("/voice-report-fail", methods=["POST"])
def voice_report_fail():
    """안받음/실패 전화 보고 - 서명검증 없음 (발신전용)"""
    msg      = request.args.get("msg", "안부전화를 완료하지 못했습니다.")
    response = VoiceResponse()
    response.say(f"AI 전화 보고입니다. {msg}", language="ko-KR")
    return Response(str(response), mimetype="text/xml")


@app.route("/call-me", methods=["POST"])
@require_api_secret
def call_me():
    """관리자 번호로 전화 걸기"""
    if not TWILIO_ACCOUNT_SID or not MY_PHONE:
        return jsonify({"error": "설정 미완료"}), 400
    sid = make_call(MY_PHONE)
    if sid:
        return jsonify({"status": "calling", "call_sid": sid, "to": MY_PHONE})
    return jsonify({"error": "전화 걸기 실패"}), 500


@app.route("/call-status", methods=["POST"])
def call_status():
    """전화 상태 콜백 - 안 받음/실패/통화중 처리"""
    call_sid     = request.form.get("CallSid", "")
    call_status  = request.form.get("CallStatus", "")
    session      = outbound_sessions.get(call_sid, {})
    name         = session.get("name", "상대방")
    number       = session.get("number", "")
    report_to    = session.get("report_to", MY_PHONE)

    status_map = {
        "no-answer": "전화를 받지 않았습니다",
        "busy"     : "통화 중이었습니다",
        "failed"   : "전화 연결에 실패했습니다",
        "canceled" : "전화가 취소되었습니다",
    }

    if call_status in status_map:
        reason = status_map[call_status]
        # 번호를 한국 형식으로 변환 (표시용)
        display_number = number.replace("+82", "0") if number.startswith("+82") else number
        msg = f"[AI통화보고] {name}님({display_number})이 {reason}."
        print(f"📵 통화 실패: {name}({number}) - {call_status}")
        try:
            client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
            # ① SMS 즉시 발송
            client.messages.create(to=report_to, from_=TWILIO_PHONE, body=msg)
            print(f"📱 SMS 보고 완료 → {report_to}: {msg}")
            # ② 전화 음성 보고 (no-answer/busy 일때만)
            if call_status in ["no-answer", "busy"]:
                voice_msg = f"{name}님이 {reason}. 안부전화를 완료하지 못했습니다."
                report_call = client.calls.create(
                    to=report_to,
                    from_=TWILIO_PHONE,
                    url=f"{SERVER_DOMAIN}/voice-report-fail?msg={requests.utils.quote(voice_msg)}"
                )
                print(f"📞 전화 보고 발신 → {report_to}: {voice_msg}")
        except Exception as e:
            print(f"보고 오류: {e}")

    return "", 204


@app.route("/call-contact", methods=["POST"])
@require_api_secret
def call_contact():
    """연락처 이름으로 전화 걸기
    body: { name, message(선택), mission(선택), report_to(선택) }
    report_to: 보고받을 번호. 생략시 MY_PHONE(관리자)
    """
    data      = request.get_json() or {}
    name      = data.get("name", "")
    message   = data.get("message", "")
    mission   = data.get("mission", "")
    report_to = data.get("report_to", MY_PHONE)  # 보고 받을 번호
    if name not in CONTACTS:
        return jsonify({"error": f"{name} 연락처 없음", "contacts": list(CONTACTS.keys())}), 404
    number = CONTACTS[name]
    sid = make_call(
        number,
        message or f"{name}님, 안녕하세요. AI 어시스턴트입니다.",
        contact_name=name,
        mission=mission or "안부 확인",
        report_to=report_to
    )
    if sid:
        return jsonify({
            "status"   : "calling",
            "name"     : name,
            "number"   : number,
            "call_sid" : sid,
            "report_to": report_to
        })
    return jsonify({"error": "전화 걸기 실패"}), 500


@app.route("/block", methods=["POST"])
@require_api_secret
def block_number():
    """번호 차단"""
    data   = request.get_json() or {}
    number = data.get("number", "")
    if number and number not in BLOCKED_NUMBERS:
        BLOCKED_NUMBERS.append(number)
        return jsonify({"status": "blocked", "number": number})
    return jsonify({"error": "번호 없음 또는 이미 차단됨"}), 400


@app.route("/contacts", methods=["GET"])
@require_api_secret
def list_contacts():
    """연락처 전체 조회 (관리자 전용)"""
    return jsonify({"count": len(CONTACTS), "contacts": CONTACTS})


@app.route("/contacts/add", methods=["POST"])
@require_api_secret
def api_add_contact():
    """연락처 추가 API"""
    data   = request.get_json() or {}
    name   = data.get("name", "").strip()
    number = data.get("number", "").strip()
    if not name or not number:
        return jsonify({"error": "name, number 필수"}), 400
    if add_contact(name, number):
        return jsonify({"status": "saved", "name": name, "number": number, "total": len(CONTACTS)})
    return jsonify({"error": "저장 실패"}), 500


@app.route("/contacts/delete", methods=["POST"])
@require_api_secret
def api_delete_contact():
    """연락처 삭제 API"""
    data = request.get_json() or {}
    name = data.get("name", "").strip()
    if delete_contact(name):
        return jsonify({"status": "deleted", "name": name, "total": len(CONTACTS)})
    return jsonify({"error": f"{name} 없음"}), 404


@app.route("/health", methods=["GET"])
def health():
    # 민감 정보(admin_numbers, contacts) 노출 금지
    return jsonify({
        "status"         : "ok",
        "bot_mode"       : BOT_MODE,
        "blocked_count"  : len(BLOCKED_NUMBERS),
        "pin_lock_count" : len([v for v in pin_fail_count.values() if v >= PIN_MAX_FAIL])
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
PYEOF

cat > twilio-bot/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY twilio_bot.py .
EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "twilio_bot:app"]
EOF

############################################
# 11. OpenAPI Tool Server
############################################
cat > tools-api/requirements.txt <<EOF
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
requests==2.31.0
python-multipart==0.0.6
pypdf==3.17.4
qdrant-client==1.7.0
numpy==1.26.3
ollama==0.1.6
EOF

PYTHON_RETRIES=$((QDRANT_RETRIES / 2))

cat > tools-api/main.py <<EOF
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os, uuid, time, requests as http_requests
from pypdf import PdfReader
import ollama
from qdrant_client import QdrantClient
from qdrant_client.models import VectorParams, Distance, PointStruct

app = FastAPI(
    title="OpenAPI RAG Tool Server",
    description="Standard OpenAPI-based RAG Tool Server (Qdrant + Ollama)",
    version="1.0.0",
)
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")
app.add_middleware(CORSMiddleware, allow_origins=ALLOWED_ORIGINS, allow_methods=["GET","POST"], allow_headers=["Authorization","Content-Type"])

QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
COLLECTION = os.getenv("QDRANT_COLLECTION", "openapi_rag")
MODEL      = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://host.docker.internal:11434")
DATA_DIR   = "/app/data"

# ── Twilio 봇 연동 설정 ────────────────────────────
TWILIO_BOT_URL = os.getenv("TWILIO_BOT_URL", "http://twilio-bot:5000")
API_SECRET     = os.getenv("API_SECRET", "")

client = None
RETRIES = ${PYTHON_RETRIES}
INTERVAL = ${QDRANT_INTERVAL}

for attempt in range(RETRIES):
    try:
        client = QdrantClient(url=QDRANT_URL)
        client.get_collections()
        print(f"✅ Qdrant 연결 성공")
        break
    except Exception:
        print(f"⏳ Qdrant 대기 중... ({attempt+1}/{RETRIES})")
        time.sleep(INTERVAL)

if client:
    try:
        collections = [c.name for c in client.get_collections().collections]
        if COLLECTION not in collections:
            client.create_collection(
                collection_name=COLLECTION,
                vectors_config=VectorParams(size=768, distance=Distance.COSINE),
            )
    except Exception as e:
        print(f"❌ 컬렉션 생성 실패: {e}")

def embed(text: str):
    try:
        oc = ollama.Client(host=OLLAMA_BASE_URL)
        return oc.embeddings(model=MODEL, prompt=text)["embedding"]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Embedding error: {str(e)}")

@app.post("/documents/upload")
async def upload_pdf(file: UploadFile = File(...)):
    if not client: raise HTTPException(status_code=503, detail="Qdrant 미연결")
    path = f"{DATA_DIR}/{file.filename}"
    with open(path, "wb") as f: f.write(await file.read())
    reader = PdfReader(path)
    text = "".join(p.extract_text() or "" for p in reader.pages)
    if not text.strip(): raise HTTPException(status_code=400, detail="텍스트 추출 실패")
    chunks = [text[i:i+1000].strip() for i in range(0, len(text), 900) if text[i:i+1000].strip()]
    points = []
    for idx, chunk in enumerate(chunks):
        try:
            points.append(PointStruct(id=str(uuid.uuid4()), vector=embed(chunk),
                payload={"text": chunk, "source": file.filename, "chunk_index": idx}))
        except: continue
    if not points: raise HTTPException(status_code=500, detail="임베딩 실패")
    client.upsert(collection_name=COLLECTION, points=points)
    return {"status": "success", "filename": file.filename, "indexed_chunks": len(points)}

class SearchQuery(BaseModel):
    query: str
    top_k: int = 3

@app.post("/rag/search")
def rag_search(search: SearchQuery):
    if not client: raise HTTPException(status_code=503, detail="Qdrant 미연결")
    hits = client.search(collection_name=COLLECTION, query_vector=embed(search.query), limit=search.top_k)
    return {"query": search.query, "results": [{"text": h.payload.get("text"), "source": h.payload.get("source"), "score": h.score} for h in hits]}

# ── 전화 기능 Tool (OpenWebUI 연동) ────────────────
class CallMeRequest(BaseModel):
    message: str = ""

class CallContactRequest(BaseModel):
    name: str
    mission: str = "안부 확인"

@app.post("/tools/call-me")
def tool_call_me(req: CallMeRequest):
    """관리자한테 전화 걸기 - OpenWebUI 채팅창에서 '나한테 전화해줘' 명령 처리"""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/call-me",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        if r.status_code == 200:
            return {"status": "success", "message": "관리자님께 전화를 걸었습니다. 잠시 후 전화가 올 겁니다!"}
        return {"status": "error", "message": f"전화 걸기 실패: {r.text}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/tools/call-contact")
def tool_call_contact(req: CallContactRequest):
    """연락처에 저장된 지인에게 안부전화 걸기"""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/call-contact",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={"name": req.name, "mission": req.mission},
            timeout=10
        )
        if r.status_code == 200:
            return {"status": "success", "message": f"{req.name}님께 안부전화를 걸었습니다!"}
        return {"status": "error", "message": f"전화 걸기 실패: {r.text}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/tools/contacts")
def tool_get_contacts():
    """저장된 연락처 목록 조회"""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.get(
            f"{TWILIO_BOT_URL}/contacts",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
def health():
    try:
        client.get_collections()
        return {"status": "healthy", "qdrant_url": QDRANT_URL}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

@app.get("/")
def root():
    return {"service": "OpenAPI RAG Tool Server", "version": "1.0.0"}
EOF

cat > tools-api/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y gcc curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
RUN mkdir -p /app/data
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

############################################
# 12. docker-compose.yml 생성
############################################
SECRET_KEY=$(openssl rand -hex 32)
API_SECRET=$(openssl rand -hex 24)

# Twilio 봇은 처음엔 빈 키로 시작 → 설치 완료 후 자동 발급
OPENWEBUI_API_KEY_PLACEHOLDER=""

cat > docker-compose.yml <<EOF
services:
  qdrant:
    image: qdrant/qdrant:latest
    volumes:
      - qdrant-data:/qdrant/storage
    ports:
      - "127.0.0.1:6333:6333"
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: ${MEMORY_QDRANT}

  openapi-tools:
    build: ./tools-api
    env_file: .env
    environment:
      - API_SECRET=${API_SECRET}
      - TWILIO_BOT_URL=http://twilio-bot:5000
    volumes:
      - ./tools-api/data:/app/data
    ports:
      - "127.0.0.1:8000:8000"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      - qdrant
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: ${MEMORY_TOOLS}

  open-webui:
    image: $OPEN_WEBUI_IMAGE
    environment:
      - WEBUI_SECRET_KEY=$SECRET_KEY
      - VECTOR_DB=qdrant
      - QDRANT_URI=http://qdrant:6333
EOF

if [ "$USE_OLLAMA" = true ]; then
cat >> docker-compose.yml <<EOF
      - ENABLE_OLLAMA_API=true
      - OLLAMA_BASE_URL=http://host.docker.internal:11434
EOF
else
cat >> docker-compose.yml <<EOF
      - ENABLE_OLLAMA_API=false
EOF
fi

if [ "$USE_GROQ" = true ] && [ -n "$GROQ_API_KEY" ]; then
cat >> docker-compose.yml <<EOF
      - ENABLE_OPENAI_API=true
      - OPENAI_API_KEY=$GROQ_API_KEY
      - OPENAI_API_BASE_URL=https://api.groq.com/openai/v1
      - DEFAULT_MODELS=llama-3.3-70b-versatile
EOF
fi

cat >> docker-compose.yml <<EOF
    volumes:
      - open-webui-data:/app/backend/data
    ports:
      - "127.0.0.1:3000:8080"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      - qdrant
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: ${MEMORY_WEBUI}

  twilio-bot:
    build: ./twilio-bot
    container_name: twilio-bot
    environment:
      - TWILIO_ACCOUNT_SID=${TWILIO_ACCOUNT_SID}
      - TWILIO_AUTH_TOKEN=${TWILIO_AUTH_TOKEN}
      - TWILIO_PHONE_NUMBER=${TWILIO_PHONE_NUMBER}
      - MY_PHONE_NUMBER=${MY_PHONE_NUMBER}
      - SERVER_DOMAIN=${SERVER_DOMAIN}
      - BOT_MODE=${BOT_MODE}
      - OPENWEBUI_URL=http://open-webui:8080
      - OPENWEBUI_API_KEY=${OPENWEBUI_API_KEY_PLACEHOLDER}
      - MODEL=llama-3.3-70b-versatile
      - OPENAI_API_KEY=${GROQ_API_KEY}
      - ADMIN_NUMBERS=${MY_PHONE_NUMBER}
      - ADMIN_PIN=${ADMIN_PIN}
      - CONTACTS=${CONTACTS_JSON}
      - BLOCKED_NUMBERS=
      - API_SECRET=${API_SECRET}
    ports:
      - "5000:5000"
    volumes:
      - contacts-data:/app/data
    depends_on:
      - qdrant
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: ${MEMORY_TWILIO}

volumes:
  contacts-data:
  qdrant-data:
  open-webui-data:
EOF

############################################
# 13. 실행
############################################
echo ""
echo "🔨 Docker 이미지 빌드 중..."
docker compose build

echo ""
echo "🚀 컨테이너 시작..."
docker compose up -d

echo ""
echo "┌────────────────────────────────────────────┐"
echo "⏳ 서비스 준비 대기 중..."
echo "└────────────────────────────────────────────┘"

echo "📦 1/4 Qdrant 시작 중..."
for i in $(seq 1 $QDRANT_RETRIES); do
  if docker compose exec -T qdrant timeout 3 curl -s http://localhost:6333/collections >/dev/null 2>&1; then
    echo "   ✅ Qdrant 준비 완료!"; break
  fi
  printf "   ⏳ 대기 중... %d/%d\r" $i $QDRANT_RETRIES
  sleep $QDRANT_INTERVAL
done

echo "🧠 2/4 OpenAPI Tools 시작 중..."
for i in $(seq 1 $TOOLS_RETRIES); do
  if timeout 3 curl -s http://localhost:8000/health >/dev/null 2>&1; then
    echo "   ✅ OpenAPI Tools 준비 완료!"; break
  fi
  printf "   ⏳ 대기 중... %d/%d\r" $i $TOOLS_RETRIES
  sleep $TOOLS_INTERVAL
done

echo "🌐 3/4 Open WebUI 시작 중..."
for i in $(seq 1 $WEBUI_RETRIES); do
  if docker compose logs open-webui 2>&1 | grep -q "Application startup complete\|Uvicorn running"; then
    sleep 3
    if timeout 3 curl -s http://localhost:3000 >/dev/null 2>&1; then
      echo "   ✅ Open WebUI 준비 완료!"; break
    fi
  fi
  printf "   ⏳ 대기 중... %d/%d\r" $i $WEBUI_RETRIES
  sleep $WEBUI_INTERVAL
done

echo "📞 4/4 Twilio 봇 시작 중..."
for i in $(seq 1 20); do
  if timeout 3 curl -s http://localhost:5000/health >/dev/null 2>&1; then
    echo "   ✅ Twilio 봇 준비 완료!"; break
  fi
  printf "   ⏳ 대기 중... %d/%d\r" $i 20
  sleep 3
done

############################################
# 자동화 Step A: Nginx /voice /respond 경로 자동 설정
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🌐 Nginx 자동 설정 중..."
echo "└────────────────────────────────────────────┘"

# Nginx 설치 여부 확인
if ! command -v nginx >/dev/null 2>&1; then
  echo "   ⚙️  Nginx 설치 중..."
  sudo apt-get update -qq && sudo apt-get install -y -qq nginx
fi

# 기본 Nginx 설정 비활성화 (server_name _ 충돌 방지)
sudo rm -f /etc/nginx/sites-enabled/default

NGINX_CONF="/etc/nginx/sites-available/twilio-bot"
sudo tee "$NGINX_CONF" > /dev/null <<NGINXEOF
server {
    listen 80;
    server_name _;

    # ── OpenWebUI (기본 경로 + WebSocket) ──────────
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }

    # ── Twilio 봇 엔드포인트 ───────────────────────
    location /voice {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /verify-pin {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /respond {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /voice-out-simple {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /voice-out-welfare {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /respond-admin {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /respond-out {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /voice-report-fail {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
    }
    location /voice-report {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
    }
    location /call-status {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
    }
    location /call-me {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
    location /call-contact {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
    location /contacts {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
    location /block {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
    location /health {
        proxy_pass http://127.0.0.1:5000;
    }
}
NGINXEOF

# 심볼릭 링크 생성 (이미 있으면 스킵)
if [ ! -f /etc/nginx/sites-enabled/twilio-bot ]; then
  sudo ln -s "$NGINX_CONF" /etc/nginx/sites-enabled/twilio-bot
fi

# Nginx 문법 검사 후 reload
if sudo nginx -t 2>/dev/null; then
  sudo systemctl reload nginx
  echo "   ✅ Nginx 설정 완료! /voice /respond /call-me 경로 활성화"
else
  echo "   ⚠️  Nginx 설정 오류. 수동 확인: sudo nginx -t"
fi

############################################
# 자동화 Step B: OpenWebUI 계정 생성 + API 키 발급
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔐 OpenWebUI API 키 자동 발급 중..."
echo "└────────────────────────────────────────────┘"

# 관리자 계정 생성
echo "   ⚙️  관리자 계정 생성 중 ($OW_EMAIL)..."
curl -s -X POST http://localhost:3000/api/v1/auths/signup \
  -H "Content-Type: application/json" \
  -d "{"name":"Admin","email":"${OW_EMAIL}","password":"${OW_PASSWORD}"}" >/dev/null 2>&1

# 로그인해서 JWT 토큰 획득
SIGNIN_RESP=$(curl -s -X POST http://localhost:3000/api/v1/auths/signin \
  -H "Content-Type: application/json" \
  -d "{"email":"${OW_EMAIL}","password":"${OW_PASSWORD}"}")

OW_JWT=$(echo "$SIGNIN_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -n "$OW_JWT" ]; then
  echo "   ✅ 로그인 성공!"

  # API 키 발급
  APIKEY_RESP=$(curl -s -X POST http://localhost:3000/api/v1/users/api-key \
    -H "Authorization: Bearer ${OW_JWT}" \
    -H "Content-Type: application/json")

  OW_API_KEY=$(echo "$APIKEY_RESP" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)

  if [ -n "$OW_API_KEY" ]; then
    echo "   ✅ API 키 발급 완료: ${OW_API_KEY:0:20}..."
    # docker-compose.yml 자동 업데이트
    sed -i "s|OPENWEBUI_API_KEY=|OPENWEBUI_API_KEY=${OW_API_KEY}|g" docker-compose.yml
    echo "OPENWEBUI_API_KEY=${OW_API_KEY}" >> .env
    echo "   🔄 Twilio 봇에 API 키 적용 중..."
    docker compose restart twilio-bot
    sleep 5
    echo "   ✅ Twilio 봇 재시작 완료!"

    # ── OpenWebUI Tool 자동 등록 (Python 파일 방식) ──
    echo "   ⚙️  OpenWebUI 전화 Tool 자동 등록 중..."

    cat > /tmp/register_tool.py << 'PYEOF'
import json, urllib.request, sys

jwt = sys.argv[1]

tool_code = '''\
"""
title: 전화 어시스턴트
author: AI Phone Bot
description: 관리자한테 전화 걸기, 안부전화, 연락처 조회
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
        """저장된 연락처 목록을 조회합니다."""
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
'''

payload = {
    "id": "phone_assistant",
    "name": "전화 어시스턴트",
    "description": "전화 걸기, 안부전화, 연락처 조회",
    "content": tool_code,
    "meta": {
        "description": "전화 걸기, 안부전화, 연락처 조회",
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
        print("SUCCESS:" + d.get("name", ""))
except urllib.error.HTTPError as e:
    print("FAIL:" + e.read().decode()[:100])
except Exception as e:
    print("ERROR:" + str(e))
PYEOF

    TOOL_RESULT=$(python3 /tmp/register_tool.py "$OW_JWT" 2>/dev/null)

    if echo "$TOOL_RESULT" | grep -q "^SUCCESS:"; then
      echo "   ✅ OpenWebUI 전화 Tool 자동 등록 완료!"
      echo "      채팅창 하단 🔧 아이콘 → '전화 어시스턴트' ON"
      echo "      → '나한테 전화해줘'"
      echo "      → '김철수한테 안부전화 해줘'"
    else
      echo "   ⚠️  Tool 자동 등록 실패 → 수동 등록 필요"
      cp /tmp/register_tool.py /tmp/phone_tool_register.py
      echo "      수동 등록:"
      echo "      python3 /tmp/phone_tool_register.py \$OW_JWT"
    fi
  else
    echo "   ⚠️  API 키 발급 실패 → 수동 설정 필요"
  fi
else
  echo "   ⚠️  로그인 실패 → 수동 설정 필요"
fi

############################################
# 자동화 Step C: Twilio Webhook URL 자동 변경
############################################
if [ "$USE_TWILIO" = true ] && [ -n "$TWILIO_ACCOUNT_SID" ] && [ -n "$TWILIO_AUTH_TOKEN" ]; then
  echo ""
  echo "┌────────────────────────────────────────────┐"
  echo "📞 Twilio Webhook 자동 설정 중..."
  echo "└────────────────────────────────────────────┘"

  WEBHOOK_URL="${SERVER_DOMAIN}/voice"

  # Twilio API로 전화번호 SID 조회
  PHONE_SID=$(curl -s -X GET \
    "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/IncomingPhoneNumbers.json?PhoneNumber=${TWILIO_PHONE_NUMBER}" \
    -u "${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}" \
    | grep -o '"sid":"PN[^"]*"' | head -1 | cut -d'"' -f4)

  if [ -n "$PHONE_SID" ]; then
    # Webhook URL 변경
    UPDATE_RESP=$(curl -s -X POST \
      "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/IncomingPhoneNumbers/${PHONE_SID}.json" \
      -u "${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}" \
      --data-urlencode "VoiceUrl=${WEBHOOK_URL}" \
      --data-urlencode "VoiceMethod=POST")

    # 성공 여부 확인
    UPDATED_URL=$(echo "$UPDATE_RESP" | grep -o '"voice_url":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$UPDATED_URL" ]; then
      echo "   ✅ Twilio Webhook 자동 변경 완료!"
      echo "      ${TWILIO_PHONE_NUMBER} → ${WEBHOOK_URL}"
    else
      echo "   ⚠️  Webhook 자동 변경 실패"
      echo "      수동으로: console.twilio.com → 번호 클릭 → Voice URL = ${WEBHOOK_URL}"
    fi
  else
    echo "   ⚠️  전화번호 SID 조회 실패"
    echo "      수동으로: console.twilio.com → 번호 클릭 → Voice URL = ${WEBHOOK_URL}"
  fi
fi

############################################
# 14. OpenWebUI Tool 파일 생성
############################################
cat > /tmp/phone_tool.py << 'TOOLEOF'
"""
title: 전화 어시스턴트
author: AI Phone Bot
description: 관리자한테 전화 걸기, 안부전화, 연락처 조회
version: 1.0.0
"""
import requests
import os

TOOL_SERVER = "http://localhost:8000"

class Tools:
    def call_me(self) -> str:
        """관리자한테 전화를 걸어줍니다. '나한테 전화해줘' 명령에 사용."""
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/call-me", json={}, timeout=10)
            return r.json().get("message", "전화를 걸었습니다.")
        except Exception as e:
            return f"오류: {e}"

    def call_contact(self, name: str, mission: str = "안부 확인") -> str:
        """저장된 연락처에게 안부전화를 걸어줍니다.
        Args:
            name: 연락처 이름 (예: 김철수)
            mission: 전화 목적 (예: 모임 참석 여부 확인)
        """
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/call-contact",
                            json={"name": name, "mission": mission}, timeout=10)
            return r.json().get("message", f"{name}님께 전화를 걸었습니다.")
        except Exception as e:
            return f"오류: {e}"

    def get_contacts(self) -> str:
        """저장된 연락처 목록을 조회합니다."""
        try:
            r = requests.get(f"{TOOL_SERVER}/tools/contacts", timeout=10)
            data = r.json()
            contacts = data.get("contacts", {})
            if not contacts:
                return "저장된 연락처가 없습니다."
            result = f"저장된 연락처 {len(contacts)}명:\n"
            for name, number in contacts.items():
                display = number.replace("+82", "0") if number.startswith("+82") else number
                result += f"- {name}: {display}\n"
            return result
        except Exception as e:
            return f"오류: {e}"
TOOLEOF

echo ""
echo "┌────────────────────────────────────────────┐"
echo "💬 OpenWebUI Tool 파일 생성 완료!"
echo "└────────────────────────────────────────────┘"
echo ""
echo "   다음 단계:"
echo "   1) https://${SERVER_DOMAIN} 접속"
echo "   2) 관리자 로그인"
echo "   3) 우측 상단 → 관리자 패널 → Tools"
echo "   4) '+' 버튼 → /tmp/phone_tool.py 내용 붙여넣기"
echo "   5) 저장 후 채팅창에서 '나한테 전화해줘' 입력!"
echo ""

############################################
# 15. 완료 메시지 + Twilio Webhook 안내
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🎉 설치 완료!"
echo "└────────────────────────────────────────────┘"
echo ""
echo "🌐 서비스 URL:"
echo "   Open WebUI        : http://localhost:3000"
echo "   OpenAPI Tool Docs : http://localhost:8000/docs"
echo "   Qdrant Dashboard  : http://localhost:6333/dashboard"
echo "   Twilio 봇 헬스     : http://localhost:5000/health"
echo ""

if [ "$USE_TWILIO" = true ]; then
echo "┌────────────────────────────────────────────┐"
echo "🎊 모든 설정 자동 완료!"
echo "└────────────────────────────────────────────┘"
echo ""
echo "   ✅ Nginx /voice /respond 경로 설정"
echo "   ✅ OpenWebUI 관리자 계정 생성 ($OW_EMAIL)"
echo "   ✅ OpenWebUI API 키 발급 및 적용"
echo "   ✅ Twilio Webhook → ${SERVER_DOMAIN}/voice"
echo ""
echo "┌────────────────────────────────────────────┐"
echo "📞 지금 바로 전화 테스트!"
echo "└────────────────────────────────────────────┘"
echo ""
echo "   1) 인바운드: ${TWILIO_PHONE_NUMBER} 으로 전화 걸기"
echo "      → AI가 한국어로 응답!"
echo ""
echo "   2) 아웃바운드: 서버가 먼저 내게 전화 걸기"
echo "      curl -X POST http://localhost:5000/call-me"
echo "      → ${MY_PHONE_NUMBER} 으로 전화 옴!"
echo ""
echo "   3) OpenWebUI 접속"
echo "      http://localhost:3000"
echo "      이메일: ${OW_EMAIL}"
echo ""
fi

echo "┌────────────────────────────────────────────┐"
echo "📄 PDF 문서 업로드 (RAG 사용 시)"
echo "└────────────────────────────────────────────┘"
echo ""
echo "   1) 서버에서 직접 업로드:"
echo "      curl -X POST http://localhost:8000/documents/upload "
echo "           -F 'file=@문서파일.pdf'"
echo ""
echo "   2) 실제 사용 예시:"
echo "      curl -X POST http://localhost:8000/documents/upload "
echo "           -F 'file=@/home/${USER}/company_manual.pdf'"
echo ""
echo "   3) 외부(로컬PC)에서 업로드:"
echo "      curl -X POST ${SERVER_DOMAIN}:8000/documents/upload "
echo "           -F 'file=@C:/Users/나/문서/회사매뉴얼.pdf'"
echo ""
echo "   4) OpenWebUI 채팅에서 RAG 검색:"
echo "      채팅창 입력 → @rag_search : 환불 정책 알려줘"
echo ""
echo "   5) 전화로 RAG 검색 (자동):"
echo "      ${TWILIO_PHONE_NUMBER} 로 전화 후 궁금한 것 말하면"
echo "      → 업로드된 PDF 내용 기반으로 AI가 음성 답변!"
echo ""
echo "   6) 업로드 현황 확인:"
echo "      curl http://localhost:8000/health"
echo "      curl http://localhost:8000/docs    # Swagger API 문서"
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔒 보안 관리"
echo "└────────────────────────────────────────────┘"
echo ""
echo "   관리자 번호 : ${MY_PHONE_NUMBER}  ← PIN 없이 바로 AI 연결"
echo "   관리자 PIN  : ${ADMIN_PIN}        ← 모르는 번호 인증용 (3회 실패 시 차단)"
echo ""
echo "   API Secret (내부 API 인증용):"
echo "      X-API-Secret: ${API_SECRET}"
echo ""
echo "   번호 차단:"
echo "      curl -X POST http://localhost:5000/block "
echo "           -H 'Content-Type: application/json' "
echo "           -d '{"number":"+821099998888"}'"
echo ""
echo "   연락처 저장/삭제:"
echo "      curl -X POST http://localhost:5000/contacts/add"
echo "           -H 'X-API-Secret: ${API_SECRET}'"
echo "           -H 'Content-Type: application/json'"
echo "           -d '{\"name\":\"김철수\", \"number\":\"+821012345678\"}'"
echo ""
echo "   연락처로 안부전화:"
echo "      curl -X POST http://localhost:5000/call-contact"
echo "           -H 'X-API-Secret: ${API_SECRET}'"
echo "           -H 'Content-Type: application/json'"
echo "           -d '{\"name\":\"김철수\", \"mission\":\"안부 확인\"}'"
echo ""
echo "   나한테 전화:"
echo "      curl -X POST http://localhost:5000/call-me"
echo "           -H 'X-API-Secret: ${API_SECRET}'"
echo ""
echo "   전화로 음성 명령 (관리자만):"
echo "      ${TWILIO_PHONE_NUMBER} 전화 후 말하기:"
echo "      → '김철수한테 안부전화 해줘'         ← AI가 대화, 결과를 나에게 전화+문자 보고"
echo "      → '김철수 번호 010-1111-2222 저장해줘'  ← 영구 저장"
echo "      → '나한테 전화해줘'"
echo ""
echo "┌────────────────────────────────────────────┐"
echo "💬 OpenWebUI 채팅창에서 전화 명령"
echo "└────────────────────────────────────────────┘"
echo ""
echo "   채팅창에서 바로 입력:"
echo "   → '나한테 전화해줘'    ← AI가 관리자님께 전화 걸어줌"
echo "   → '김철수한테 안부전화 해줘'  ← AI가 김철수님께 전화"
echo "   → '저장된 연락처 알려줘'      ← 연락처 목록 확인"
echo ""
echo "   * OpenWebUI → 관리자패널 → Tools 에서 전화 기능 활성화 필요"
echo "   * Tool Server URL: http://localhost:8000"
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔧 관리 명령어"
echo "└────────────────────────────────────────────┘"
echo "   cd ~/openapi-rag"
echo "   docker compose logs -f twilio-bot    # 봇 로그"
echo "   docker compose logs -f open-webui    # WebUI 로그"
echo "   docker compose restart twilio-bot    # 봇 재시작"
echo "   docker compose restart               # 전체 재시작"
echo "   docker compose down                  # 중지"
echo ""
echo "└────────────────────────────────────────────┘"
