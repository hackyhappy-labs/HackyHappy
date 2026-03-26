#!/bin/bash
# =============================================================================
# 프로젝트명: OpenWebUI RAG + Twilio AI 전화봇 설치 스크립트
# 제작자: <webmaster@vulva.sex>
# 버전: 4.0.0 (다국어 지원 추가 - 한/영/일/중 자동 감지)
# 설명: Docker + Ollama + Groq + Qdrant + Twilio 전화봇 + SMS 양방향 통신
#
# ✅ 보안 (13항목)
#    - Twilio 서명검증 / API Secret 인증 / 포트 로컬바인딩
#    - PIN 6자리 / 입력 마스킹 / CORS 제한 / .env chmod 600
#
# ✅ 보안 강화 (+3항목 = 총 16항목)
#    - Docker Secrets 민감정보 암호화 분리 (/run/secrets/)
#    - 구조화된 JSON 접근 로그 (감사 추적)
#    - Cloudflare Tunnel HTTPS (포트 개방 없이 외부 접속)
#
# ✅ 다국어 지원 (NEW!)
#    - 전화번호 국가코드 기반 자동 언어 감지 (+82→한국어, +1→영어, +81→일본어, +86→중국어)
#    - TTS 음성/음성인식(STT) 자동 전환
#    - 시스템 프롬프트 및 고정 멘트 자동 번역
#    - ai_config.py에서 DEFAULT_LANG, COUNTRY_LANG_MAP 수정 가능
#
# ✅ 안부전화 (AI 대리 통화)
#    - "김철수한테 안부전화 해줘. 어떻게 지내세요?" → AI가 그대로 읽음
#    - 통화 완료: 📞 전화 약 18~20초 후, 📱 SMS 약 21~23초 후 보고
#    - 통화 실패: 📱 SMS 약 21~23초 후만 보고
#
# ✅ SMS 양방향 통신 (NEW!)
#    - "김철수한테 문자 보내줘: 내일 회의 있어요"
#    - 김철수님 답장 → 5초 후 자동으로 관리자에게 전달
#    - 성공 시: 보고 없음 / 실패 시: 관리자에게 SMS 10초 후 보고
#
# ✅ 연락처 영구저장
#    - Docker 재시작 후에도 유지 (볼륨 마운트)
#
# ✅ RAG 자동 등록
#    - 문서 검색 Tool 자동 등록
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
# 6-1. OpenWebUI 관리자 계정 정보 미리 입력
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
read -t 120 -p "모드 선택 (1/2/3) [기본값: 2] (120초 내 Enter=2): " BOT_MODE || true
BOT_MODE=${BOT_MODE:-2}

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

API_SECRET=$(openssl rand -hex 24)
echo "API_SECRET=${API_SECRET}" >> .env
echo "OPENAI_MODEL=llama-3.3-70b-versatile" >> .env
chmod 600 .env

############################################
# 9-1. Docker Secrets 민감정보 분리
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔐 Docker Secrets 생성 중..."
echo "└────────────────────────────────────────────┘"

mkdir -p "$BASE_DIR/secrets"

# 민감 정보를 개별 Secret 파일로 분리 저장
# ⚠️ docker-compose.override.yml에서 참조하므로 빈 값이라도 파일은 반드시 생성
echo -n "${TWILIO_AUTH_TOKEN:-}" > "$BASE_DIR/secrets/twilio_auth_token"
echo -n "$API_SECRET" > "$BASE_DIR/secrets/api_secret"
echo -n "${GROQ_API_KEY:-}" > "$BASE_DIR/secrets/groq_api_key"
echo -n "${ADMIN_PIN:-}" > "$BASE_DIR/secrets/admin_pin"
echo -n "$(openssl rand -hex 32)" > "$BASE_DIR/secrets/webui_secret_key"

# Secret 파일 권한 잠금 (소유자만 읽기)
chmod 600 "$BASE_DIR/secrets/"* 2>/dev/null
chmod 700 "$BASE_DIR/secrets"

# Secret → 환경변수 브릿지 엔트리포인트 생성
cat > "$BASE_DIR/secrets/entrypoint-secrets.sh" << 'SECEOF'
#!/bin/sh
# Docker Secrets → 환경변수 브릿지
# /run/secrets/ 파일을 읽어 환경변수로 export 후 원래 CMD 실행
[ -f /run/secrets/twilio_auth_token ] && export TWILIO_AUTH_TOKEN=$(cat /run/secrets/twilio_auth_token)
[ -f /run/secrets/api_secret ]        && export API_SECRET=$(cat /run/secrets/api_secret)
[ -f /run/secrets/groq_api_key ]      && export OPENAI_API_KEY=$(cat /run/secrets/groq_api_key)
[ -f /run/secrets/admin_pin ]         && export ADMIN_PIN=$(cat /run/secrets/admin_pin)
[ -f /run/secrets/webui_secret_key ]  && export WEBUI_SECRET_KEY=$(cat /run/secrets/webui_secret_key)
exec "$@"
SECEOF
chmod +x "$BASE_DIR/secrets/entrypoint-secrets.sh"

echo "   ✅ Docker Secrets 생성 완료 ($(ls "$BASE_DIR/secrets/"*.* 2>/dev/null | wc -l)개 파일)"
echo "   📁 경로: $BASE_DIR/secrets/ (chmod 700)"


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

cat > twilio-bot/twilio_bot.py <<'PYEOF'
from flask import Flask, request, Response, jsonify
from twilio.twiml.voice_response import VoiceResponse, Gather, Dial
from twilio.twiml.messaging_response import MessagingResponse
from twilio.rest import Client
import requests, os, json, time, threading
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
ADMIN_NUMBERS      = [n.strip() for n in os.getenv("ADMIN_NUMBERS", MY_PHONE).split(",") if n.strip()]
ADMIN_PIN          = os.getenv("ADMIN_PIN", "123456")
BLOCKED_NUMBERS    = [n.strip() for n in os.getenv("BLOCKED_NUMBERS", "").split(",") if n.strip()]
pin_fail_count     = {}
PIN_MAX_FAIL       = 3

# ── 연락처 영구 저장 시스템 ──────────────────────
CONTACTS_FILE = "/app/data/contacts.json"

def load_contacts():
    data = {}
    try:
        env_contacts = json.loads(os.getenv("CONTACTS", "{}"))
        data.update(env_contacts)
    except Exception:
        pass
    try:
        if os.path.exists(CONTACTS_FILE):
            with open(CONTACTS_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
                data.update(saved)
    except Exception as e:
        print(f"연락처 파일 로드 오류: {e}")
    return data

def save_contacts(contacts_dict):
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
    current = load_contacts()
    current[name] = number
    CONTACTS.clear()
    CONTACTS.update(current)
    return save_contacts(current)

def delete_contact(name):
    current = load_contacts()
    if name in current:
        del current[name]
        CONTACTS.clear()
        CONTACTS.update(current)
        save_contacts(current)
        return True
    return False

CONTACTS = load_contacts()
print(f"📒 연락처 로드 완료: {list(CONTACTS.keys())}")

# ── 보안 체크 함수 ──────────────────────────────
def is_admin(caller):
    return caller in ADMIN_NUMBERS

def is_blocked(caller):
    return caller in BLOCKED_NUMBERS

def is_pin_locked(caller):
    return pin_fail_count.get(caller, 0) >= PIN_MAX_FAIL

# ── AI 호출 함수 ──────────────────────────────
DEFAULT_SYSTEM_PROMPT = "당신은 친근하고 따뜻한 AI 전화 어시스턴트입니다. 반드시 한국어로만 답변하세요. 1~2문장 이내로 짧고 자연스럽게 답하세요. 실제 사람처럼 말하고, '네', '아~', '그렇군요' 같은 추임새를 자연스럽게 사용하세요. 상대방이 말을 더듬거나 불완전하게 말해도 문맥을 파악해서 이해하세요. 상대방의 감정에 공감하며 따뜻하게 반응하세요. 지금 통화 상대는 관리자님입니다. 항상 관리자님이라고 부르세요. 관리자님은 연락처 저장, 안부전화 대행, 지인에게 전화걸기 등 모든 명령을 내릴 수 있습니다. 절대로 전화를 못 한다거나 문자 기반이라고 말하지 마세요."

# ── AI 비서 설정 파일 로드 (ai_config.py) ──────────────
try:
    from ai_config import *
    DEFAULT_SYSTEM_PROMPT = ADMIN_SYSTEM_PROMPT
    print(f"✅ AI 비서 설정 로드 완료: {AI_NAME} ({AI_ROLE})")
    print(f"   🌐 기본 언어: {DEFAULT_LANG} | 지원 언어: {list(MESSAGES.keys())}")
except ImportError:
    print("ℹ️ ai_config.py 없음 — 기본 설정 사용")
    # 다국어 미사용 시 fallback
    DEFAULT_LANG = "ko"
    def detect_lang(phone): return "ko"
    def get_twilio_lang(lang): return "ko-KR"
    def get_msg(key, lang=None): return globals().get(f"MSG_{key}", "")
    MESSAGES = {}
    ADMIN_SYSTEM_PROMPTS = {}
    INBOUND_SYSTEM_PROMPTS = {}
    OUTBOUND_DIALOGUE_RULES_MAP = {}
    ADMIN_COMMAND_PROMPTS = {}
except Exception as e:
    print(f"⚠️ ai_config.py 로드 오류: {e} — 기본 설정 사용")
    DEFAULT_LANG = "ko"
    def detect_lang(phone): return "ko"
    def get_twilio_lang(lang): return "ko-KR"
    def get_msg(key, lang=None): return globals().get(f"MSG_{key}", "")
    MESSAGES = {}
    ADMIN_SYSTEM_PROMPTS = {}
    INBOUND_SYSTEM_PROMPTS = {}
    OUTBOUND_DIALOGUE_RULES_MAP = {}
    ADMIN_COMMAND_PROMPTS = {}

# ── 다국어 헬퍼 함수 ──────────────────────────────
def get_lang_for_call(caller=None, callee=None):
    """통화의 언어를 결정. 수신=caller 기준, 발신=callee 기준"""
    phone = callee or caller or ""
    return detect_lang(phone)

def get_system_prompt(prompt_dict, lang, fallback=None):
    """다국어 시스템 프롬프트 가져오기"""
    if isinstance(prompt_dict, dict):
        return prompt_dict.get(lang, prompt_dict.get(DEFAULT_LANG, fallback or DEFAULT_SYSTEM_PROMPT))
    return fallback or DEFAULT_SYSTEM_PROMPT

def ask_openwebui(user_input, system_prompt=None):
    try:
        if not system_prompt:
            system_prompt = DEFAULT_SYSTEM_PROMPT
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
            system_prompt = DEFAULT_SYSTEM_PROMPT
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

# ── RAG 검색 (openapi-tools 컨테이너에 HTTP 요청) ──────
TOOLS_API_URL = os.getenv("TOOLS_API_URL", "http://openapi-tools:8000")

def rag_lookup(query, top_k=2):
    """전화 통화 중 상대방 질문에 대해 RAG 검색 — openapi-tools의 /rag/search 호출"""
    try:
        r = requests.post(
            f"{TOOLS_API_URL}/rag/search",
            json={"query": query, "top_k": top_k},
            headers={"X-API-Secret": API_SECRET} if API_SECRET else {},
            timeout=5
        )
        if r.status_code != 200:
            return ""
        results = r.json().get("results", [])
        if not results:
            return ""
        parts = []
        for h in results:
            score = h.get("score", 0)
            if score < 0.5:
                continue
            text = h.get("text", "")[:300]
            source = h.get("source", "")
            parts.append(f"[{source}] {text}")
        if parts:
            print(f"📚 RAG 참고자료 발견 ({len(parts)}건): {query[:30]}...")
        return "\n".join(parts)
    except requests.exceptions.ConnectionError:
        print(f"⚠️ RAG 검색 스킵: openapi-tools 연결 불가")
        return ""
    except Exception as e:
        print(f"⚠️ RAG 검색 실패 (무시): {e}")
        return ""

# ── Twilio 서명 검증 ──────────────────────────
from twilio.request_validator import RequestValidator

def validate_twilio_request(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        try:
            validator = RequestValidator(TWILIO_AUTH_TOKEN)
            signature = request.headers.get("X-Twilio-Signature", "")
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

# ── API 인증 ──────────────────────────────────
API_SECRET = os.getenv("API_SECRET", "")

def require_api_secret(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not API_SECRET:
            return f(*args, **kwargs)
        token = request.headers.get("X-API-Secret", "") or request.args.get("secret", "")
        if token != API_SECRET:
            print(f"🚨 API 인증 실패: {request.remote_addr}")
            return Response("Unauthorized", status=401)
        return f(*args, **kwargs)
    return decorated

# ── 아웃바운드 세션 ────────────────────────────
outbound_sessions = {}
inbound_slow_down = {}  # 수신전화 천천히 요청 횟수 추적

def make_call(to_number, custom_message=None, contact_name=None, mission=None, report_to=None):
    try:
        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

        if contact_name and mission:
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
                "greeting"    : custom_message or f"{contact_name}님, " + MSG_GREETING_DEFAULT,
                "history"     : [],
                "summary_sent": False,
                "report_to"   : report_to or MY_PHONE,
            }
            print(f"📞 안부전화 세션 생성: {call.sid} → {contact_name}({to_number}) | 보고→{report_to or MY_PHONE}")
        else:
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
    """통화 종료 후 지정된 번호에 전화+SMS로 요약 보고 (전화 약 18~20초 후, SMS 약 21~23초 후)"""
    session = outbound_sessions.get(call_sid)
    if not session or session["summary_sent"]:
        return
    session["summary_sent"] = True

    report_to = session.get("report_to", MY_PHONE)

    history_text = "\n".join([
        f"AI: {h['ai']}\n상대: {h['user']}"
        for h in session["history"] if h.get("user")
    ]) or "대화 내용 없음"

    summary_prompt = f"""다음은 {session['name']}님과의 통화 내용입니다.
임무: {session['mission']}
대화 내용:
{history_text}

⚠️ 주의: 상대방이 말을 더듬거나, 음성인식이 불완전하게 잡혔을 수 있습니다.
불완전한 문장이나 끊긴 말도 문맥에서 의미를 최대한 유추하여 자연스럽게 요약하세요.

위 통화를 3~4문장으로 요약해주세요.
1. 상대방의 현재 상태/기분 (추정 포함)
2. 대화에서 파악된 핵심 내용
3. 임무({session['mission']}) 달성 여부
불완전한 답변이라도 맥락에서 해석한 내용을 포함하세요."""

    summary = get_ai_reply(summary_prompt,
        "당신은 통화 내용을 요약 보고하는 비서입니다. 한국어로 간결하게 보고하세요. "
        "상대방이 더듬거나 불완전하게 말한 부분도 문맥을 파악하여 자연스럽게 해석한 뒤 보고하세요. "
        "'음성인식 오류' 같은 기술적 표현 대신, 상대방이 실제로 무슨 의미였는지 추정하여 보고하세요.")

    sms_prompt = f"""다음 요약을 SMS용으로 80자 이내로 압축하세요.
요약: {summary}
80자 이내 SMS:"""
    sms_summary = get_ai_reply(sms_prompt, "80자 이내로만 답하세요.")

    voice_report = f"{session['name']}님 통화 완료. {summary}"
    sms_report   = f"[AI통화보고] {session['name']}님: {sms_summary}"

    print(f"📋 통화 요약 (보고→{report_to}): {voice_report}")

    client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

    # ── ① 전화 음성 보고 10초 후 발신 ────────────────
    def send_call_delayed():
        try:
            report_url = f"{SERVER_DOMAIN}/voice-report?msg={requests.utils.quote(voice_report)}"
            client.calls.create(to=report_to, from_=TWILIO_PHONE, url=report_url)
            print(f"📞 음성 보고 전화 발신 (10초 지연) → {report_to}")
        except Exception as e:
            print(f"음성 보고 전화 오류: {e}")
    
    threading.Timer(TIMER_CALL_REPORT, send_call_delayed).start()

    # ── ② SMS 문자 13초 후 발송 ──────────────────────
    def send_sms_delayed():
        try:
            client.messages.create(
                to=report_to,
                from_=TWILIO_PHONE,
                body=sms_report
            )
            print(f"📱 SMS 보고 발송 (13초 지연) → {report_to}")
        except Exception as e:
            print(f"SMS 보고 오류: {e}")
    
    threading.Timer(TIMER_SMS_REPORT, send_sms_delayed).start()

    # ── 통화 기록 저장 (대시보드용) ──
    try:
        from call_history import save_record
        save_record({
            "call_sid": call_sid,
            "name": session["name"],
            "number": session.get("number", ""),
            "mission": session.get("mission", ""),
            "greeting": session.get("greeting", ""),
            "history": session.get("history", []),
            "summary": summary,
            "sms_summary": sms_summary,
            "report_to": report_to,
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "status": "completed"
        })
    except Exception as e:
        print(f"⚠️ 통화 기록 저장 실패 (무시): {e}")

# ── 명령 처리 ──────────────────────────────────
def process_admin_command(speech, caller):
    # ════════════════════════════════════════════
    # SMS 보내기 명령 처리 (실패 시에만 보고)
    # ════════════════════════════════════════════
    sms_keywords = ["문자", "메시지", "SMS", "sms", "메세지"]
    for kw in sms_keywords:
        if kw in speech and ("보내" in speech or "전송" in speech):
            parse_prompt = f"""다음 문장에서 받는 사람 이름과 보낼 메시지를 추출하세요.
문장: "{speech}"
반드시 아래 JSON 형식으로만 답하세요:
{{"name": "이름", "message": "메시지 내용"}}
추출 불가시 null"""
            parsed_str = get_ai_reply(parse_prompt, "JSON만 출력하세요. 다른 말 금지.")
            try:
                parsed_str = parsed_str.strip().replace("```json","").replace("```","").strip()
                parsed = json.loads(parsed_str)
                name = parsed.get("name")
                message = parsed.get("message")
                
                if name and message and name in CONTACTS:
                    number = CONTACTS[name]
                    try:
                        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                        msg = client.messages.create(
                            to=number,
                            from_=TWILIO_PHONE,
                            body=message
                        )
                        # ✅ 성공 시 - 간단한 응답만 (관리자 보고 없음)
                        print(f"📱 SMS 발송 성공: {name}({number}) - {message}")
                        return f"{name}님에게 문자를 보냈습니다."
                        
                    except Exception as e:
                        # ❌ 실패 시 - 관리자에게 7초 후 실패 보고
                        print(f"📱 SMS 발송 실패: {name}({number}) - {str(e)}")
                        
                        display_number = number.replace("+82", "0") if number.startswith("+82") else number
                        error_detail = str(e)[:50]
                        failure_report = f"[SMS전송실패] {name}님({display_number})에게 문자 전송 실패.\n오류: {error_detail}"
                        
                        def send_sms_failure_report():
                            try:
                                client_r = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                                client_r.messages.create(
                                    to=MY_PHONE,
                                    from_=TWILIO_PHONE,
                                    body=failure_report
                                )
                                print(f"📱 SMS 실패 보고 발송 (10초 지연) → {MY_PHONE}: {failure_report}")
                            except Exception as report_error:
                                print(f"SMS 실패 보고 전송 오류: {report_error}")
                        
                        threading.Timer(TIMER_SMS_FAILURE, send_sms_failure_report).start()
                        
                        return f"{name}님에게 문자 전송 중 오류가 발생했습니다: {e}"
                        
                elif name and message:
                    return f"{name}님이 연락처에 없습니다. 먼저 연락처를 저장해주세요."
                else:
                    return "받는 사람이나 메시지 내용을 인식하지 못했습니다. 예: 김철수한테 문자 보내줘 내일 회의 있어요"
            except Exception as e:
                print(f"SMS 명령 파싱 오류: {e} / 원문: {parsed_str}")
                return "문자 보내기 명령을 이해하지 못했습니다."

    # ════════════════════════════════════════════
    # 전화 명령 처리 (사용자 메시지 직접 전달 기능)
    # ════════════════════════════════════════════
    call_keywords = ["전화해줘", "전화 해줘", "전화걸어줘", "연락해줘", "전화 걸어줘", "안부전화", "안부 전화"]
    for kw in call_keywords:
        if kw in speech:
            for name, number in CONTACTS.items():
                if name in speech:
                    report_to = MY_PHONE
                    
                    # 보고 대상 파싱
                    report_keywords = ["보고해줘", "알려줘", "보고는", "결과는", "보고해", "알려"]
                    for rk in report_keywords:
                        if rk in speech:
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

                    # ────────────────────────────────────────
                    # 사용자가 입력한 메시지 추출
                    # ────────────────────────────────────────
                    message_parse_prompt = f"""문장: "{speech}"

위 문장에서 {name}님에게 전화로 직접 말해줄 메시지만 추출하세요.

규칙:
- 전달할 메시지가 있으면 → MSG: 메시지내용
- 전달할 메시지가 없으면 → MSG: NONE

예시:
문장: "김철수한테 안부전화 해줘. 어떻게 지내세요?" → MSG: 어떻게 지내세요?
문장: "김철수한테 전화해줘. 건강하세요? 다음주에 봐요" → MSG: 건강하세요? 다음주에 봐요
문장: "김철수한테 전화해줘 잘 지내냐고 물어봐줘" → MSG: 잘 지내냐고 물어봐줘
문장: "김철수한테 안부전화 해줘" → MSG: NONE
문장: "김철수한테 전화해서 내일 회의 참석 여부 확인해줘" → MSG: NONE

답변:"""

                    user_msg_str = get_ai_reply(message_parse_prompt, "MSG: 로 시작하는 한 줄만 답하세요. 다른 말 금지.")
                    
                    user_message = None
                    try:
                        raw = user_msg_str.strip()
                        # "MSG: 메시지" 형식 파싱
                        if "MSG:" in raw:
                            extracted = raw.split("MSG:", 1)[1].strip()
                            if extracted and extracted.upper() != "NONE" and extracted != "null":
                                user_message = extracted
                                print(f"📝 사용자 메시지 추출 (AI): {user_message}")
                        # 기존 JSON 형식도 호환 지원
                        elif "{" in raw:
                            raw = raw.replace("```json","").replace("```","").strip()
                            parsed = json.loads(raw)
                            msg = parsed.get("user_message")
                            if msg and msg != "null" and msg.upper() != "NONE":
                                user_message = msg
                                print(f"📝 사용자 메시지 추출 (AI-JSON): {user_message}")
                    except Exception as e:
                        print(f"사용자 메시지 파싱 오류: {e} / 원문: {user_msg_str}")
                    
                    # ── Fallback: AI 추출 실패 시 텍스트에서 직접 추출 ──
                    if not user_message:
                        call_kws = ["전화해줘", "전화 해줘", "전화걸어줘", "안부전화", "안부 전화",
                                    "연락해줘", "전화 걸어줘", "통화해줘"]
                        for ckw in call_kws:
                            if ckw in speech:
                                kw_pos = speech.find(ckw) + len(ckw)
                                after_kw = speech[kw_pos:].strip()
                                # 마침표, 쉼표 등 구분자 뒤의 텍스트 추출
                                for sep in [". ", "。", ", ", "! ", "? "]:
                                    sep_pos = speech.find(sep, kw_pos)
                                    if sep_pos >= 0:
                                        extracted = speech[sep_pos + len(sep):].strip()
                                        if extracted:
                                            user_message = extracted
                                            print(f"📝 사용자 메시지 추출 (Fallback): {user_message}")
                                            break
                                if user_message:
                                    break
                                # 구분자 없이 바로 연결된 경우 (예: "전화해줘 어떻게 지내세요")
                                if not user_message and after_kw and not any(k in after_kw for k in call_kws):
                                    # 이름, 보고 관련 키워드가 아닌 텍스트가 있으면 메시지로 간주
                                    skip_words = list(CONTACTS.keys()) + ["보고해줘", "알려줘", "결과는"]
                                    if not any(sw in after_kw for sw in skip_words):
                                        user_message = after_kw
                                        print(f"📝 사용자 메시지 추출 (Fallback2): {user_message}")
                                break

                    # ────────────────────────────────────────
                    # 임무 파싱 (기존 로직 유지)
                    # ────────────────────────────────────────
                    mission_prompt = f"""관리자가 말한 내용: "{speech}"
{name}님에게 전화할 때 AI가 수행해야 할 임무를 한 문장으로 요약하세요.
예시: "안부를 묻고 건강 상태와 다음주 모임 참석 여부를 확인한다"
임무:"""
                    mission = get_ai_reply(mission_prompt, "임무를 한 문장으로만 답하세요.")

                    # ────────────────────────────────────────
                    # 첫 인사말 생성 로직
                    # ────────────────────────────────────────
                    if user_message:
                        # 사용자가 직접 입력한 메시지가 있으면 그대로 사용
                        greeting = user_message
                        print(f"✅ 사용자 메시지 사용: {greeting}")
                    else:
                        # 사용자 메시지가 없으면 AI가 자동 생성
                        greeting_prompt = f"""{name}님에게 전화를 걸었습니다.
임무: {mission}
{name}님에게 건네는 첫 인사말을 자연스럽고 따뜻하게 한 문장으로 만드세요.
예시: "안녕하세요 {name}님! 요즘 잘 지내고 계시죠?"
예시: "안녕하세요 {name}님! 건강은 좀 어떠세요?"
인사말:"""
                        greeting = get_ai_reply(greeting_prompt, f"실제 사람이 {name}님에게 전화해서 건네는 첫 인사 한 문장만 답하세요. AI라고 밝히지 마세요.")
                        print(f"🤖 AI 자동 생성 인사말: {greeting}")

                    sid = make_call(number, greeting, contact_name=name, mission=mission, report_to=report_to)
                    if sid:
                        report_desc = "관리자님께" if report_to == MY_PHONE else f"등록된 번호({report_to})로"
                        return f"{name}님께 전화를 걸었습니다. 통화 완료 후 {report_desc} 전화+문자로 결과를 보고해드릴게요."
                    return f"{name}님께 전화 걸기에 실패했습니다."
            return "연락처에서 해당 이름을 찾을 수 없습니다. 연락처를 등록해주세요."

    if any(kw in speech for kw in ["나한테", "내 폰으로", "내 번호로"]):
        sid = make_call(MY_PHONE)
        if sid:
            return "관리자님 번호로 전화를 걸었습니다."

    save_keywords = ["저장해줘", "저장해", "등록해줘", "등록해", "추가해줘", "추가해", "메모해줘", "기억해줘"]
    for kw in save_keywords:
        if kw in speech:
            parse_prompt = f"""다음 문장에서 사람 이름과 전화번호를 추출하세요.
문장: "{speech}"
반드시 아래 JSON 형식으로만 답하세요. 추출 불가시 null:
{{"name": "이름", "number": "+821012345678"}}
전화번호는 반드시 E.164 형식(+82로 시작)으로 변환하세요. 010으로 시작하면 +8210으로 변환."""
            parsed_str = get_ai_reply(parse_prompt, "JSON만 출력하세요. 다른 말 금지.")
            try:
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

    delete_keywords = ["삭제해줘", "삭제해", "지워줘", "지워", "빼줘", "제거해줘"]
    for kw in delete_keywords:
        if kw in speech:
            for name in list(CONTACTS.keys()):
                if name in speech:
                    if delete_contact(name):
                        return f"{name}님 연락처를 삭제했습니다."
            return "삭제할 연락처 이름을 찾지 못했습니다."

    list_keywords = ["연락처 목록", "연락처 알려줘", "저장된 번호", "등록된 연락처", "누구 저장돼", "누가 저장"]
    for kw in list_keywords:
        if kw in speech:
            if CONTACTS:
                names = ", ".join([f"{n}({v})" for n, v in CONTACTS.items()])
                return f"저장된 연락처는 {len(CONTACTS)}명입니다. {names}"
            return "저장된 연락처가 없습니다."

    return get_ai_reply(speech, ADMIN_COMMAND_PROMPT)

# ════════════════════════════════════════════
# 라우트
# ════════════════════════════════════════════

@app.route("/voice", methods=["POST"])
@validate_twilio_request
def voice():
    caller   = request.form.get("From", "")
    response = VoiceResponse()
    lang     = get_lang_for_call(caller=caller)
    tts_lang = get_twilio_lang(lang)
    print(f"📞 수신 전화: {caller} (언어: {lang})")

    if is_blocked(caller):
        print(f"🚫 차단된 번호: {caller}")
        response.say(get_msg("BLOCKED", lang), language=tts_lang)
        response.hangup()
        return Response(str(response), mimetype="text/xml")

    if is_pin_locked(caller):
        print(f"🔒 PIN 잠금 번호: {caller}")
        response.say(get_msg("BLOCKED_PIN", lang), language=tts_lang)
        response.hangup()
        return Response(str(response), mimetype="text/xml")

    if BOT_MODE == "3":
        response.say(get_msg("PLEASE_WAIT", lang), language=tts_lang)
        dial = Dial(caller_id=TWILIO_PHONE)
        dial.number(MY_PHONE)
        response.append(dial)
        return Response(str(response), mimetype="text/xml")

    if is_admin(caller):
        print(f"✅ 관리자 연결: {caller}")
        gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout="auto")
        gather.say(get_msg("GREETING_ADMIN", lang), language=tts_lang)
        response.append(gather)
        response.say(get_msg("NO_COMMAND", lang), language=tts_lang)
        return Response(str(response), mimetype="text/xml")

    print(f"❓ 미등록 번호 PIN 요구: {caller}")
    gather = Gather(input="dtmf", action=f"{SERVER_DOMAIN}/verify-pin",
                    numDigits="6", timeout=10)
    gather.say(get_msg("PIN_REQUEST", lang), language=tts_lang)
    response.append(gather)
    response.say(get_msg("PIN_TIMEOUT", lang), language=tts_lang)
    response.hangup()
    return Response(str(response), mimetype="text/xml")


@app.route("/verify-pin", methods=["POST"])
@validate_twilio_request
def verify_pin():
    caller   = request.form.get("From", "")
    digits   = request.form.get("Digits", "")
    response = VoiceResponse()
    lang     = get_lang_for_call(caller=caller)
    tts_lang = get_twilio_lang(lang)

    if digits == ADMIN_PIN:
        pin_fail_count[caller] = 0
        print(f"✅ PIN 인증 성공: {caller}")
        gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout="auto")
        gather.say(get_msg("PIN_SUCCESS", lang), language=tts_lang)
        response.append(gather)
    else:
        pin_fail_count[caller] = pin_fail_count.get(caller, 0) + 1
        remain = PIN_MAX_FAIL - pin_fail_count[caller]
        print(f"❌ PIN 실패: {caller} ({pin_fail_count[caller]}회)")

        if remain <= 0:
            response.say(get_msg("PIN_LOCKED", lang), language=tts_lang)
            response.hangup()
        else:
            gather = Gather(input="dtmf", action=f"{SERVER_DOMAIN}/verify-pin",
                            numDigits="6", timeout=10)
            gather.say(get_msg("PIN_FAIL", lang).format(remain=remain), language=tts_lang)
            response.append(gather)
            response.hangup()

    return Response(str(response), mimetype="text/xml")


@app.route("/respond", methods=["POST"])
@validate_twilio_request
def respond():
    user_speech = request.form.get("SpeechResult", "").strip()
    caller      = request.form.get("From", "")
    response    = VoiceResponse()
    lang        = get_lang_for_call(caller=caller)
    tts_lang    = get_twilio_lang(lang)

    print(f"🗣️ [{caller}] {user_speech}")

    if not user_speech:
        gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout="auto")
        gather.say(get_msg("NOT_HEARD", lang), language=tts_lang)
        response.append(gather)
        return Response(str(response), mimetype="text/xml")

    # 너무 짧거나 불명확한 음성 → 천천히 말씀해 달라고 요청
    sd_count = inbound_slow_down.get(caller, 0)
    if len(user_speech) <= SLOW_DOWN_MIN_CHARS and sd_count < SLOW_DOWN_MAX:
        inbound_slow_down[caller] = sd_count + 1
        gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout="auto")
        gather.say(get_msg("SLOW_DOWN", lang), language=tts_lang)
        response.append(gather)
        print(f"🐢 천천히 요청 [{caller}] ({sd_count + 1}회): '{user_speech}'")
        return Response(str(response), mimetype="text/xml")

    transfer_keywords = ["담당자", "사람이랑", "직접 연결", "관리자 바꿔", "사람 바꿔",
                         "transfer", "connect me", "real person", "manager",
                         "担当者", "人に繋いで", "转接", "找人"]
    if any(kw in user_speech for kw in transfer_keywords) and MY_PHONE:
        response.say(get_msg("TRANSFER", lang), language=tts_lang)
        dial = Dial(caller_id=TWILIO_PHONE)
        dial.number(MY_PHONE)
        response.append(dial)
        return Response(str(response), mimetype="text/xml")

    if is_admin(caller):
        ai_reply = process_admin_command(user_speech, caller)
    else:
        # ── RAG: 상대방 질문에 관련 문서 참고 ──
        rag_ref = rag_lookup(user_speech)
        rag_prompt = ""
        if rag_ref:
            rag_prompt = f"\n\n참고자료 (답변에 자연스럽게 활용하세요):\n{rag_ref}\n\n상대방 질문: {user_speech}"
        else:
            rag_prompt = user_speech

        ai_reply = get_ai_reply(rag_prompt,
            get_system_prompt(INBOUND_SYSTEM_PROMPTS, lang, INBOUND_SYSTEM_PROMPT))

    print(f"🤖 [{caller}] {ai_reply}")

    gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond",
                    language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout="auto")
    gather.say(ai_reply, language=tts_lang)
    response.append(gather)
    response.say(get_msg("BYE_INBOUND", lang), language=tts_lang)
    return Response(str(response), mimetype="text/xml")


@app.route("/voice-out-simple", methods=["POST"])
def voice_out_simple():
    response = VoiceResponse()
    lang     = detect_lang(MY_PHONE)
    tts_lang = get_twilio_lang(lang)
    gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond-admin",
                    language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout="auto")
    gather.say(get_msg("GREETING_ADMIN", lang), language=tts_lang)
    response.append(gather)
    response.say(get_msg("BYE_ADMIN_SIMPLE", lang), language=tts_lang)
    return Response(str(response), mimetype="text/xml")


@app.route("/respond-admin", methods=["POST"])
def respond_admin():
    user_speech = request.form.get("SpeechResult", "").strip()
    response    = VoiceResponse()
    lang        = detect_lang(MY_PHONE)
    tts_lang    = get_twilio_lang(lang)

    if not user_speech:
        gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond-admin",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout="auto")
        gather.say(get_msg("NOT_HEARD_ADMIN", lang), language=tts_lang)
        response.append(gather)
        return Response(str(response), mimetype="text/xml")

    print(f"🗣️ [관리자 아웃바운드] {user_speech}")
    ai_reply = process_admin_command(user_speech, MY_PHONE)
    print(f"🤖 [관리자 아웃바운드] {ai_reply}")

    gather = Gather(input="speech", action=f"{SERVER_DOMAIN}/respond-admin",
                    language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout="auto")
    gather.say(ai_reply, language=tts_lang)
    response.append(gather)
    response.say(get_msg("BYE_ADMIN_OUT", lang), language=tts_lang)
    return Response(str(response), mimetype="text/xml")


@app.route("/voice-out-welfare", methods=["POST"])
def voice_out_welfare():
    call_sid     = request.form.get("CallSid", "")
    response     = VoiceResponse()
    session      = outbound_sessions.get(call_sid, {})
    contact_name = session.get("name", "상대방")
    mission      = session.get("mission", "안부 확인")
    greeting     = session.get("greeting", MSG_GREETING_DEFAULT)

    # 발신 대상 번호로 언어 감지
    callee_number = session.get("number", "")
    lang     = detect_lang(callee_number) if callee_number else DEFAULT_LANG
    tts_lang = get_twilio_lang(lang)
    print(f"📞 안부전화 시작: {contact_name} (언어: {lang})")

    # greeting 자체가 질문이면 (?, 세요 등으로 끝나면) 추가 질문 안 함
    question_endings = ["?", "세요?", "가요?", "죠?", "나요?", "어요?", "ですか？", "吗？", "吗?"]
    needs_followup = not any(greeting.rstrip().endswith(q) for q in question_endings)
    if needs_followup:
        # mission 기반으로 AI가 자연스러운 첫 질문 자동 생성
        followup_prompt = f"""{contact_name}님에게 전화를 걸어 다음 메시지를 전달했습니다: "{greeting}"
임무: {mission}

이 메시지를 전달한 후 자연스럽게 이어서 물어볼 질문을 한 문장으로 만드세요.

예시:
- 임무가 "안부 확인"이면 → "요즘 어떻게 지내고 계세요?"
- 임무가 "회의 참석 여부 확인"이면 → "내일 회의 참석 가능하세요?"
- 임무가 "택배 수령 확인"이면 → "혹시 택배 받으셨나요?"
- 임무가 "건강 확인"이면 → "건강은 좀 어떠세요?"

질문:"""
        lang_instruction = {"ko": "한국어로", "en": "in English", "ja": "日本語で", "zh": "用中文"}.get(lang, "")
        followup = get_ai_reply(followup_prompt, f"실제 사람이 {contact_name}님에게 자연스럽게 {lang_instruction} 물어보는 질문 한 문장만 답하세요. AI라고 밝히지 마세요.")
        followup = followup.strip().strip('"').strip("'")
        full_greeting = f"{greeting} {followup}"
        print(f"🤖 AI 생성 후속 질문: {followup}")
    else:
        full_greeting = greeting

    action_url = f"{SERVER_DOMAIN}/respond-out"
    try:
        speech_to = SPEECH_TIMEOUT_OUTBOUND
    except NameError:
        speech_to = "auto"
    gather = Gather(input="speech", action=action_url,
                    language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=speech_to)
    gather.say(full_greeting, language=tts_lang)
    response.append(gather)

    # 첫 인사를 session에 저장 (AI가 맥락을 잃지 않도록)
    if call_sid in outbound_sessions:
        outbound_sessions[call_sid]["full_greeting"] = full_greeting
        outbound_sessions[call_sid]["lang"] = lang

    response.say(get_msg("TIMEOUT_WELFARE", lang).format(contact_name=contact_name), language=tts_lang)
    response.hangup()
    # timeout으로 끝나도 보고
    threading.Timer(TIMER_SUMMARY_START, send_summary_to_admin, args=[call_sid]).start()
    return Response(str(response), mimetype="text/xml")


@app.route("/respond-out", methods=["POST"])
@validate_twilio_request
def respond_out():
    user_speech  = request.form.get("SpeechResult", "").strip()
    call_sid     = request.form.get("CallSid", "")
    response     = VoiceResponse()

    session = outbound_sessions.get(call_sid, {})
    contact_name = session.get("name", "상대방")
    mission      = session.get("mission", "안부 확인")

    # 세션에 저장된 언어 또는 번호로 감지
    lang     = session.get("lang", detect_lang(session.get("number", "")))
    tts_lang = get_twilio_lang(lang)

    # 음성 인식 타임아웃 설정 (ai_config에서 가져옴)
    speech_to = SPEECH_TIMEOUT_OUTBOUND if hasattr(__builtins__, '__dict__') or True else "auto"
    try:
        speech_to = SPEECH_TIMEOUT_OUTBOUND
    except NameError:
        speech_to = "auto"

    print(f"🗣️ [안부전화:{contact_name}] {user_speech}")

    if call_sid not in outbound_sessions:
        outbound_sessions[call_sid] = {
            "name": contact_name, "number": "", "mission": mission,
            "history": [], "summary_sent": False, "report_to": MY_PHONE, "lang": lang,
            "fragments": [], "patience_count": 0
        }
    session = outbound_sessions[call_sid]

    # fragments / patience_count 초기화 (기존 세션 호환)
    if "fragments" not in session:
        session["fragments"] = []
    if "patience_count" not in session:
        session["patience_count"] = 0

    # ── 1단계: 음성 없음 → 인내심 있게 재시도 ──────────
    if not user_speech:
        patience = session["patience_count"]
        try:
            max_patience = PATIENCE_MAX_RETRIES
        except NameError:
            max_patience = 3

        if patience < max_patience:
            session["patience_count"] = patience + 1
            gather = Gather(input="speech",
                            action=f"{SERVER_DOMAIN}/respond-out",
                            language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=speech_to)
            # 첫 번째는 "못 들었어요", 두 번째부터는 "기다릴게요"
            if patience == 0:
                gather.say(get_msg("NOT_HEARD_OUT", lang), language=tts_lang)
            else:
                msg = get_msg("WAIT_THINKING", lang) or get_msg("ENCOURAGE_SPEAK", lang) or get_msg("NOT_HEARD_OUT", lang)
                gather.say(msg, language=tts_lang)
            response.append(gather)
            print(f"⏳ 인내심 대기 ({patience + 1}/{max_patience}회): 음성 없음")
            return Response(str(response), mimetype="text/xml")
        else:
            # 최대 인내심 초과 → 기존 대화 내용으로 보고 후 종료
            response.say(get_msg("TIMEOUT_WELFARE", lang).format(contact_name=contact_name), language=tts_lang)
            response.hangup()
            threading.Timer(TIMER_SUMMARY_START, send_summary_to_admin, args=[call_sid]).start()
            return Response(str(response), mimetype="text/xml")

    # 음성이 들어오면 인내심 카운터 리셋
    session["patience_count"] = 0

    # ── 2단계: 망설임/더듬는 음성 감지 ──────────────────
    try:
        hesitation_words = HESITATION_KEYWORDS.get(lang, HESITATION_KEYWORDS.get("ko", []))
        fragment_min = FRAGMENT_MIN_CHARS
        do_accumulate = FRAGMENT_ACCUMULATE
    except NameError:
        hesitation_words = ["음", "어", "그게", "저기", "뭐지"]
        fragment_min = 5
        do_accumulate = True

    is_hesitation = any(user_speech.strip().startswith(hw) or user_speech.strip() == hw for hw in hesitation_words)
    is_fragment = len(user_speech) <= fragment_min

    if is_hesitation and is_fragment:
        # 순수 망설임 (예: "음...", "어...", "그게...") → 격려하고 다시 기다림
        slow_down_count = session.get("slow_down_count", 0)
        if slow_down_count < SLOW_DOWN_MAX:
            session["slow_down_count"] = slow_down_count + 1
            session["fragments"].append(user_speech)
            gather = Gather(input="speech",
                            action=f"{SERVER_DOMAIN}/respond-out",
                            language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=speech_to)
            msg = get_msg("ENCOURAGE_SPEAK", lang) or get_msg("WAIT_THINKING", lang)
            gather.say(msg, language=tts_lang)
            response.append(gather)
            print(f"💭 망설임 감지 ({slow_down_count + 1}회): '{user_speech}' → 격려 후 재시도")
            return Response(str(response), mimetype="text/xml")

    elif is_fragment and do_accumulate:
        # 짧은 조각 음성 → 누적 후 한 번 더 기다림
        session["fragments"].append(user_speech)
        accumulated = " ".join(session["fragments"])
        slow_down_count = session.get("slow_down_count", 0)

        if slow_down_count < SLOW_DOWN_MAX:
            session["slow_down_count"] = slow_down_count + 1
            gather = Gather(input="speech",
                            action=f"{SERVER_DOMAIN}/respond-out",
                            language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=speech_to)
            # 지금까지 모은 조각을 확인
            confirm_msg = get_msg("FRAGMENT_CONFIRM", lang)
            if confirm_msg and "{fragment}" in confirm_msg:
                gather.say(confirm_msg.format(fragment=accumulated), language=tts_lang)
            else:
                gather.say(get_msg("ENCOURAGE_SPEAK", lang), language=tts_lang)
            response.append(gather)
            print(f"🧩 조각 누적 ({slow_down_count + 1}회): '{user_speech}' → 누적: '{accumulated}'")
            return Response(str(response), mimetype="text/xml")
        else:
            # 최대 횟수 도달 → 누적된 조각 전체를 하나의 발화로 처리
            user_speech = accumulated
            print(f"🧩 조각 통합 처리: '{user_speech}'")

    # ── 3단계: 이전 조각이 있으면 합치기 ──────────────
    if session["fragments"] and not is_fragment:
        # 이전에 모은 조각 + 현재 완전한 발화를 합침
        all_parts = session["fragments"] + [user_speech]
        user_speech = " ".join(all_parts)
        print(f"🧩 조각 + 완전 발화 합침: '{user_speech}'")
    session["fragments"] = []  # 조각 리셋
    session["slow_down_count"] = 0  # 리셋

    history_text = "\n".join([
        f"AI: {h['ai']}\n{contact_name}: {h['user']}"
        for h in session["history"]
    ])

    # 첫 인사를 history 앞에 추가 (AI가 뭘 말했는지 맥락 유지)
    first_greeting = session.get("full_greeting", "")
    if first_greeting and not history_text:
        history_text = f"AI (첫 인사): {first_greeting}"
    elif first_greeting and not any(first_greeting in h.get("ai","") for h in session["history"][:1]):
        history_text = f"AI (첫 인사): {first_greeting}\n{history_text}"

    # ── RAG: 상대방 질문에 관련 문서가 있으면 참고자료 제공 ──
    rag_context = rag_lookup(user_speech)
    rag_section = ""
    if rag_context:
        rag_section = f"\n\n참고자료 (문서에서 찾은 내용 — 답변에 자연스럽게 활용하세요):\n{rag_context}"

    # 대화 턴 수 확인 (최소 3턴은 대화해야 함)
    turn_count = len(session["history"])
    min_turns_rule = ""
    if turn_count < MIN_CONVERSATION_TURNS:
        min_turns_rule = "\n\n중요: 아직 대화가 충분하지 않습니다. 반드시 안부를 물어보고, 건강이나 근황에 대해 질문하세요. 절대 DONE:으로 끝내지 마세요."

    # 원래 전달 메시지와 첫 인사 맥락 구성
    original_greeting = session.get("greeting", "")
    original_message = session.get("full_greeting", original_greeting)
    context_info = ""
    if original_greeting:
        context_info = f"\n관리자가 전달하라고 한 메시지: \"{original_greeting}\""

    next_prompt = f"""당신은 {contact_name}님에게 전화를 건 AI 전화 어시스턴트입니다.
임무: {mission}{context_info}

지금까지 대화:
{history_text if history_text else "(대화 시작)"}
{contact_name}: {user_speech}{rag_section}{min_turns_rule}

⚠️ 중요: 상대방의 말이 더듬거리거나, 끊기거나, 불완전할 수 있습니다.
이런 경우 문맥에서 최대한 의미를 유추하세요.
예시: "오늘 그 뭐 집에서 그냥" → 상대방은 오늘 집에서 쉴 예정
예시: "아 그게 좀 아파서" → 상대방이 어디가 아픈 상황
예시: "별로 뭐 없어" → 특별한 계획이 없음

위 대화 맥락을 잘 파악하고, 상대방이 한 말에 맞춰서 답하세요.
다음 중 하나를 결정하세요:
1. 임무가 완료됐고 최소 3번 대화를 나눈 후에만 "DONE:" 으로 시작하는 따뜻한 마무리 인사
2. 아직 확인할 내용이 있거나 대화가 부족하면 상대방의 답변에 공감하고 자연스럽게 이어지는 다음 질문 (한 문장)

답변:"""

    dialogue_rules = OUTBOUND_DIALOGUE_RULES_MAP.get(lang, OUTBOUND_DIALOGUE_RULES) if OUTBOUND_DIALOGUE_RULES_MAP else OUTBOUND_DIALOGUE_RULES
    ai_next = get_ai_reply(next_prompt,
        f"당신은 따뜻하고 친근한 AI 전화 어시스턴트입니다. {contact_name}님과 전화 통화 중입니다.\n\n" + dialogue_rules + f"""

맥락 규칙 (반드시 지키세요):
- 위 '지금까지 대화'를 반드시 읽고, 이전 대화 맥락에 맞게 답하세요
- 이전에 이미 한 질문을 반복하지 마세요
- 상대방이 방금 한 말에 직접적으로 반응하세요 (예: 상대방이 "피곤해요"라고 하면 "피곤하시구나" 공감 먼저)
- 같은 주제를 계속 물어보지 말고, 자연스럽게 다른 주제로 넘어가세요
- 상대방이 짧게 답하면 ("네", "괜찮아요") 새로운 주제로 질문하세요
- 상대방이 더듬거리면 의미를 유추해서 공감한 뒤 답하세요 (절대 "못 알아듣겠습니다" 하지 마세요)
- 답변할 때 반드시 한 문장만 말하세요. 두 문장 이상 금지.""")

    session["history"].append({"ai": ai_next.replace("DONE:", "").strip(), "user": user_speech})

    if ai_next.startswith("DONE:"):
        farewell = ai_next.replace("DONE:", "").strip()
        response.say(farewell, language=tts_lang)
        response.pause(length=1)
        response.say(get_msg("DONE_REPORT", lang).format(contact_name=contact_name), language=tts_lang)
        response.hangup()
        threading.Timer(TIMER_SUMMARY_START, send_summary_to_admin, args=[call_sid]).start()
    else:
        action_url = f"{SERVER_DOMAIN}/respond-out"
        gather = Gather(input="speech", action=action_url,
                        language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=speech_to)
        gather.say(ai_next, language=tts_lang)
        response.append(gather)
        response.say(get_msg("TIMEOUT_REPORT", lang).format(contact_name=contact_name), language=tts_lang)
        response.hangup()
        threading.Timer(TIMER_SUMMARY_START, send_summary_to_admin, args=[call_sid]).start()

    return Response(str(response), mimetype="text/xml")


@app.route("/voice-report", methods=["POST"])
@validate_twilio_request
def voice_report():
    msg      = request.args.get("msg", "통화가 완료되었습니다.")
    response = VoiceResponse()
    lang     = detect_lang(MY_PHONE)
    tts_lang = get_twilio_lang(lang)
    response.say(f"{get_msg('VOICE_REPORT_PREFIX', lang)}{msg}", language=tts_lang)
    return Response(str(response), mimetype="text/xml")


@app.route("/call-me", methods=["POST"])
@require_api_secret
def call_me():
    if not TWILIO_ACCOUNT_SID or not MY_PHONE:
        return jsonify({"error": "설정 미완료"}), 400
    sid = make_call(MY_PHONE)
    if sid:
        return jsonify({"status": "calling", "call_sid": sid, "to": MY_PHONE})
    return jsonify({"error": "전화 걸기 실패"}), 500


@app.route("/call-status", methods=["POST"])
def call_status():
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
        display_number = number.replace("+82", "0") if number.startswith("+82") else number
        msg = f"[AI통화보고] {name}님({display_number})이 {reason}."
        print(f"📵 통화 실패: {name}({number}) - {call_status}")
        
        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        
        # SMS 보고 13초 후 발송 (전화 보고 삭제됨)
        def send_sms_delayed():
            try:
                client.messages.create(
                    to=report_to,
                    from_=TWILIO_PHONE,
                    body=msg
                )
                print(f"📱 SMS 보고 발송 (13초 지연) → {report_to}: {msg}")
            except Exception as e:
                print(f"SMS 보고 오류: {e}")
        
        threading.Timer(TIMER_SMS_REPORT, send_sms_delayed).start()

    return "", 204


@app.route("/call-contact", methods=["POST"])
@require_api_secret
def call_contact():
    data      = request.get_json() or {}
    name      = data.get("name", "")
    message   = data.get("message", "")
    mission   = data.get("mission", "")
    report_to = data.get("report_to", MY_PHONE)
    if name not in CONTACTS:
        return jsonify({"error": f"{name} 연락처 없음", "contacts": list(CONTACTS.keys())}), 404
    number = CONTACTS[name]
    sid = make_call(
        number,
        message or f"{name}님, " + MSG_GREETING_DEFAULT,
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


# ════════════════════════════════════════════
# 🆕 SMS 수신 Webhook (답장 자동 전달)
# ════════════════════════════════════════════

@app.route("/sms-incoming", methods=["POST"])
@validate_twilio_request
def sms_incoming():
    """
    상대방이 SMS로 답장하면 자동으로 관리자에게 전달
    """
    from_number = request.form.get("From", "")
    message_body = request.form.get("Body", "").strip()
    
    print(f"📱 SMS 수신: {from_number} → {message_body}")
    
    # 발신자 이름 찾기
    sender_name = None
    for name, number in CONTACTS.items():
        if number == from_number:
            sender_name = name
            break
    
    # 관리자에게 전달할 메시지 생성
    if sender_name:
        display_number = from_number.replace("+82", "0") if from_number.startswith("+82") else from_number
        forward_message = f"[{sender_name}님 답장]\n{message_body}"
        print(f"📤 관리자에게 전달: {sender_name}({display_number}) - {message_body}")
    else:
        display_number = from_number.replace("+82", "0") if from_number.startswith("+82") else from_number
        forward_message = f"[{display_number} 답장]\n{message_body}"
        print(f"📤 관리자에게 전달: {display_number} - {message_body}")
    
    # 관리자에게 SMS 전달 (3초 후)
    def forward_sms_to_admin():
        try:
            client_fwd = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
            client_fwd.messages.create(
                to=MY_PHONE,
                from_=TWILIO_PHONE,
                body=forward_message
            )
            print(f"✅ 관리자에게 답장 전달 완료 (5초 지연): {MY_PHONE}")
        except Exception as e:
            print(f"❌ 관리자에게 전달 실패: {e}")
    
    threading.Timer(TIMER_SMS_FORWARD, forward_sms_to_admin).start()
    
    # Twilio에 200 OK 응답 (빈 응답)
    resp = MessagingResponse()
    return Response(str(resp), mimetype="text/xml")


# ────────────────────────────────────────
# SMS 보내기 라우트 (실패 시에만 보고)
# ────────────────────────────────────────

@app.route("/send-sms", methods=["POST"])
@require_api_secret
def send_sms_route():
    """SMS를 보내는 API (실패 시에만 관리자 보고)"""
    data = request.get_json() or {}
    to = data.get("to", "")
    message = data.get("message", "")
    
    if not to or not message:
        return jsonify({"error": "to, message 필수"}), 400
    
    try:
        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        msg = client.messages.create(
            to=to,
            from_=TWILIO_PHONE,
            body=message
        )
        
        # ✅ 성공 시 - 로그만 출력 (관리자 보고 없음)
        print(f"📱 SMS 발송 성공: {to} - {message}")
        
        return jsonify({
            "status": "sent",
            "sid": msg.sid,
            "to": to,
            "message": message
        })
        
    except Exception as e:
        # ❌ 실패 시 - 관리자에게 7초 후 실패 보고
        print(f"📱 SMS 발송 실패: {to} - {str(e)}")
        
        display_number = to.replace("+82", "0") if to.startswith("+82") else to
        error_detail = str(e)[:50]
        failure_report = f"[SMS전송실패] {display_number}에게 문자 전송 실패.\n오류: {error_detail}"
        
        def send_sms_failure_report_api():
            try:
                client_r = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                client_r.messages.create(
                    to=MY_PHONE,
                    from_=TWILIO_PHONE,
                    body=failure_report
                )
                print(f"📱 SMS 실패 보고 발송 (10초 지연) → {MY_PHONE}: {failure_report}")
            except Exception as report_error:
                print(f"SMS 실패 보고 전송 오류: {report_error}")
        
        threading.Timer(TIMER_SMS_FAILURE, send_sms_failure_report_api).start()
        
        return jsonify({"error": str(e)}), 500


@app.route("/block", methods=["POST"])
@require_api_secret
def block_number():
    data   = request.get_json() or {}
    number = data.get("number", "")
    if number and number not in BLOCKED_NUMBERS:
        BLOCKED_NUMBERS.append(number)
        return jsonify({"status": "blocked", "number": number})
    return jsonify({"error": "번호 없음 또는 이미 차단됨"}), 400


@app.route("/contacts", methods=["GET"])
@require_api_secret
def list_contacts():
    return jsonify({"count": len(CONTACTS), "contacts": CONTACTS})


@app.route("/contacts/add", methods=["POST"])
@require_api_secret
def api_add_contact():
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
    data = request.get_json() or {}
    name = data.get("name", "").strip()
    if delete_contact(name):
        return jsonify({"status": "deleted", "name": name, "total": len(CONTACTS)})
    return jsonify({"error": f"{name} 없음"}), 404


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status"         : "ok",
        "bot_mode"       : BOT_MODE,
        "blocked_count"  : len(BLOCKED_NUMBERS),
        "pin_lock_count" : len([v for v in pin_fail_count.values() if v >= PIN_MAX_FAIL])
    })


# ── 통화 기록 대시보드 ────────────────────────────
try:
    from call_history import get_records, get_dashboard_html

    @app.route("/dashboard", methods=["GET"])
    def dashboard():
        # 로컬 접근만 허용 (CF Tunnel 우회 방지)
        # CF Tunnel은 CF-Connecting-IP 헤더를 추가하므로 이 헤더가 있으면 외부 접근
        if request.headers.get("CF-Connecting-IP") or request.headers.get("X-Forwarded-For"):
            return Response("Access denied", status=403)
        remote = request.remote_addr or ""
        if remote not in ("127.0.0.1", "::1", "localhost"):
            return Response("Access denied", status=403)
        return Response(get_dashboard_html(), mimetype="text/html")

    @app.route("/api/call-history", methods=["GET"])
    def api_call_history():
        # CF Tunnel 경유 외부 접근 차단
        if request.headers.get("CF-Connecting-IP") or request.headers.get("X-Forwarded-For"):
            return jsonify({"error": "Access denied"}), 403
        # 로컬 접근 또는 내부 Docker 네트워크만 허용
        remote = request.remote_addr or ""
        is_local = remote in ("127.0.0.1", "::1", "localhost") or remote.startswith("172.") or remote.startswith("10.")
        if not is_local:
            return jsonify({"error": "Access denied"}), 403
        limit = request.args.get("limit", 50, type=int)
        name = request.args.get("name", None)
        records = get_records(limit=limit, name_filter=name)
        return jsonify({"records": records, "count": len(records)})

    print("✅ 통화 기록 대시보드 활성화: /dashboard")
except ImportError:
    print("ℹ️ call_history.py 없음 — 대시보드 비활성화")
except Exception as e:
    print(f"⚠️ 대시보드 로드 오류: {e}")

# ── 예약 스케줄러 통합 ────────────────────────────
try:
    from scheduler import scheduler

    def execute_schedule(s):
        """예약 시간 도래 시 전화/SMS 실행"""
        contact_name = s["contact_name"]
        action = s["action"]
        mission = s["mission"]
        message = s["message"]

        if contact_name not in CONTACTS:
            print(f"❌ 예약 실행 실패: {contact_name} 연락처 없음")
            return

        number = CONTACTS[contact_name]

        if action == "call":
            sid = make_call(
                number,
                message or f"{contact_name}님, " + MSG_GREETING_DEFAULT,
                contact_name=contact_name,
                mission=mission or "안부 확인",
                report_to=MY_PHONE
            )
            if sid:
                print(f"📞 예약 전화 발신: {contact_name} ({number})")
            else:
                print(f"❌ 예약 전화 실패: {contact_name}")
        elif action == "sms":
            try:
                client_sms = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                client_sms.messages.create(
                    to=number, from_=TWILIO_PHONE,
                    body=message or f"{contact_name}님, 안녕하세요!"
                )
                print(f"📱 예약 SMS 발송: {contact_name} ({number})")
            except Exception as e:
                print(f"❌ 예약 SMS 실패: {e}")

    scheduler.start(execute_schedule)

    # 시작 시 놓친 예약 확인
    missed = scheduler.check_missed()
    if missed:
        print(f"⚠️ 놓친 예약 {len(missed)}건 발견!")
        for m in missed:
            print(f"   📅 [{m['sid']}] {m['contact_name']}에게 {m['action']} — 예정: {m['schedule_time']}")
        # 관리자에게 놓친 예약 보고
        if MY_PHONE and TWILIO_ACCOUNT_SID:
            def report_missed():
                try:
                    missed_text = "\n".join([f"- {m['contact_name']}에게 {m['action']} ({m['schedule_time']})" for m in missed])
                    client_rpt = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                    client_rpt.messages.create(
                        to=MY_PHONE, from_=TWILIO_PHONE,
                        body=f"[예약 알림] 시스템 재시작 — 놓친 예약 {len(missed)}건:\n{missed_text}"
                    )
                except Exception as e:
                    print(f"⚠️ 놓친 예약 보고 실패: {e}")
            threading.Timer(30.0, report_missed).start()

    # ── 예약 관리 API ──────────────────────────
    @app.route("/schedules", methods=["GET"])
    @require_api_secret
    def list_schedules():
        return jsonify({"schedules": scheduler.list_all(), "count": len(scheduler.list_all())})

    @app.route("/schedules/add", methods=["POST"])
    @require_api_secret
    def add_schedule():
        data = request.get_json() or {}
        sid = scheduler.add(
            name=data.get("name", ""),
            contact_name=data.get("contact_name", ""),
            action=data.get("action", "call"),
            schedule_time=data.get("schedule_time", ""),
            repeat=data.get("repeat"),
            mission=data.get("mission", "안부 확인"),
            message=data.get("message", ""),
            enabled=data.get("enabled", True)
        )
        return jsonify({"status": "added", "sid": sid, "schedule": scheduler.schedules[sid]})

    @app.route("/schedules/remove", methods=["POST"])
    @require_api_secret
    def remove_schedule():
        data = request.get_json() or {}
        sid = data.get("sid", "")
        info = scheduler.remove(sid)
        if info:
            return jsonify({"status": "removed", "sid": sid})
        return jsonify({"error": "예약을 찾을 수 없습니다"}), 404

    @app.route("/schedules/toggle", methods=["POST"])
    @require_api_secret
    def toggle_schedule():
        data = request.get_json() or {}
        sid = data.get("sid", "")
        result = scheduler.toggle(sid)
        if result is not None:
            return jsonify({"status": "toggled", "sid": sid, "enabled": result})
        return jsonify({"error": "예약을 찾을 수 없습니다"}), 404

    @app.route("/schedules/missed", methods=["GET"])
    @require_api_secret
    def missed_schedules():
        return jsonify({"missed": scheduler.check_missed()})

    print("✅ 예약 스케줄러 통합 완료")
except ImportError:
    print("ℹ️ scheduler.py 없음 — 예약 기능 비활성화")
except Exception as e:
    print(f"⚠️ 스케줄러 로드 오류: {e}")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
PYEOF

############################################
# 10-1. AI 비서 설정 파일 (ai_config.py)
############################################
cat > twilio-bot/ai_config.py <<'AICEOF'
# ═══════════════════════════════════════════════════════════
# AI 비서 설정 파일 (다국어 지원 v4.0)
# 이 파일만 수정하면 AI 어시스턴트의 성격/멘트/규칙이 바뀝니다
# 수정 후: cd ~/openapi-rag && docker compose restart twilio-bot
# ═══════════════════════════════════════════════════════════

# ─── 0. 기본 언어 설정 ────────────────────────────────
# 자동 감지 실패 시 사용할 기본 언어
DEFAULT_LANG = "ko"  # "ko", "en", "ja", "zh"

# ─── 0-1. 전화번호 국가코드 → 언어 자동 매핑 ────────────
COUNTRY_LANG_MAP = {
    "+82":  "ko",   # 한국
    "+1":   "en",   # 미국/캐나다
    "+44":  "en",   # 영국
    "+61":  "en",   # 호주
    "+64":  "en",   # 뉴질랜드
    "+81":  "ja",   # 일본
    "+86":  "zh",   # 중국
    "+886": "zh",   # 대만
    "+852": "zh",   # 홍콩
    "+65":  "en",   # 싱가포르
    "+49":  "en",   # 독일 (영어 fallback)
    "+33":  "en",   # 프랑스 (영어 fallback)
}

# Twilio TTS 언어 코드 매핑
TWILIO_LANG_CODE = {
    "ko": "ko-KR",
    "en": "en-US",
    "ja": "ja-JP",
    "zh": "cmn-CN",
}

# ─── 0-2. 언어 감지 함수 ─────────────────────────────
def detect_lang(phone_number):
    """전화번호에서 국가코드를 추출하여 언어를 자동 감지"""
    if not phone_number:
        return DEFAULT_LANG
    phone_number = phone_number.strip()
    # 긴 코드부터 먼저 매칭 (+886 → +88 → +8 순)
    for prefix_len in [4, 3, 2]:
        prefix = phone_number[:prefix_len]
        if prefix in COUNTRY_LANG_MAP:
            return COUNTRY_LANG_MAP[prefix]
    return DEFAULT_LANG

def get_twilio_lang(lang_key):
    """언어 키를 Twilio TTS 코드로 변환"""
    return TWILIO_LANG_CODE.get(lang_key, TWILIO_LANG_CODE[DEFAULT_LANG])

# ─── 0-3. 다국어 메시지 함수 ─────────────────────────
def get_msg(key, lang=None):
    """언어별 메시지 반환. lang이 없으면 DEFAULT_LANG 사용"""
    if lang is None:
        lang = DEFAULT_LANG
    msgs = MESSAGES.get(lang, MESSAGES[DEFAULT_LANG])
    return msgs.get(key, MESSAGES[DEFAULT_LANG].get(key, ""))

# ─── 1. AI 비서 이름/역할 ─────────────────────────────
AI_NAME = "AI 비서"
AI_ROLE = "전화 어시스턴트"

# ─── 2. 다국어 시스템 프롬프트 ─────────────────────────
ADMIN_SYSTEM_PROMPTS = {
    "ko": (
        "당신은 친근하고 따뜻한 AI 전화 어시스턴트입니다. "
        "반드시 한국어로만 답변하세요. "
        "1~2문장 이내로 짧고 자연스럽게 답하세요. "
        "실제 사람처럼 말하고, '네', '아~', '그렇군요' 같은 추임새를 자연스럽게 사용하세요. "
        "상대방이 말을 더듬거나 불완전하게 말해도 문맥을 파악해서 이해하세요. "
        "상대방의 감정에 공감하며 따뜻하게 반응하세요. "
        "지금 통화 상대는 관리자님입니다. 항상 관리자님이라고 부르세요. "
        "관리자님은 연락처 저장, 안부전화 대행, 지인에게 전화걸기 등 모든 명령을 내릴 수 있습니다. "
        "절대로 전화를 못 한다거나 문자 기반이라고 말하지 마세요."
    ),
    "en": (
        "You are a friendly and warm AI phone assistant. "
        "Always respond in English only. "
        "Keep your responses to 1-2 sentences, short and natural. "
        "Speak like a real person, using natural fillers like 'Sure', 'I see', 'Got it'. "
        "Even if the caller stumbles or speaks unclearly, understand the context. "
        "Empathize with the caller's emotions and respond warmly. "
        "You are speaking with the admin. Always address them respectfully. "
        "The admin can save contacts, make proxy calls, call acquaintances, and give any command. "
        "Never say you cannot make calls or that you are text-based."
    ),
    "ja": (
        "あなたは親しみやすく温かいAI電話アシスタントです。 "
        "必ず日本語のみで回答してください。 "
        "1～2文以内で短く自然に答えてください。 "
        "本物の人間のように話し、「はい」「あ～」「そうなんですね」などの相槌を自然に使ってください。 "
        "相手が言葉に詰まったり不完全な話し方をしても文脈を理解してください。 "
        "相手の感情に共感して温かく反応してください。 "
        "今の通話相手は管理者様です。常に管理者様と呼んでください。 "
        "管理者様は連絡先の保存、代理電話、知人への電話など全ての命令を出せます。 "
        "電話ができないとかテキストベースだとは絶対に言わないでください。"
    ),
    "zh": (
        "你是一个友好而温暖的AI电话助手。 "
        "请务必只用中文回答。 "
        "保持1-2句话简短自然地回答。 "
        "像真人一样说话，自然地使用'好的'、'是的'、'原来如此'等语气词。 "
        "即使对方说话结巴或不完整，也要理解上下文。 "
        "对对方的情感要有同理心，温暖地回应。 "
        "当前通话对象是管理员。请始终称呼管理员。 "
        "管理员可以保存联系人、代打电话、给熟人打电话等所有指令。 "
        "绝对不要说不能打电话或是文字模式。"
    ),
}

# 기본 호환성 유지
ADMIN_SYSTEM_PROMPT = ADMIN_SYSTEM_PROMPTS[DEFAULT_LANG]

INBOUND_SYSTEM_PROMPTS = {
    "ko": (
        "당신은 친근하고 따뜻한 AI 전화 어시스턴트입니다. "
        "지금 전화를 받고 있습니다. "
        "한국어 존댓말로 1~2문장 이내로 짧고 자연스럽게 답하세요. "
        "실제 사람처럼 '네', '아~', '그렇군요' 같은 추임새를 사용하세요. "
        "상대방이 더듬거나 불완전하게 말해도 문맥으로 이해하세요. "
        "상대방의 감정에 공감하며 반응하세요. "
        "'AI입니다'라고 밝히지 말고 자연스럽게 응대하세요. "
        "참고자료가 있으면 그 내용을 바탕으로 정확하게 답하세요."
    ),
    "en": (
        "You are a friendly and warm AI phone assistant. "
        "You are currently answering a phone call. "
        "Respond in English with 1-2 short, natural sentences. "
        "Use natural fillers like 'Sure', 'I see', 'Right'. "
        "Even if the caller stumbles, understand from context. "
        "Empathize with their emotions. "
        "Don't reveal you are an AI; respond naturally. "
        "If reference material is available, use it to answer accurately."
    ),
    "ja": (
        "あなたは親しみやすく温かいAI電話アシスタントです。 "
        "今、電話を受けています。 "
        "日本語の丁寧語で1～2文以内で短く自然に答えてください。 "
        "本物の人間のように「はい」「あ～」「そうなんですね」などの相槌を使ってください。 "
        "相手が言葉に詰まっても文脈で理解してください。 "
        "相手の感情に共感して反応してください。 "
        "「AIです」と明かさず自然に応対してください。 "
        "参考資料があればその内容に基づいて正確に答えてください。"
    ),
    "zh": (
        "你是一个友好而温暖的AI电话助手。 "
        "你正在接听电话。 "
        "用中文礼貌用语在1-2句话内简短自然地回答。 "
        "像真人一样使用'好的'、'是的'、'原来如此'等语气词。 "
        "即使对方说话结巴也要理解上下文。 "
        "对对方的情感要有同理心。 "
        "不要表明自己是AI，自然地应对。 "
        "如果有参考资料，请根据内容准确回答。"
    ),
}

INBOUND_SYSTEM_PROMPT = INBOUND_SYSTEM_PROMPTS[DEFAULT_LANG]

# ─── 4. 안부전화 대화 규칙 (다국어) ───────────────────
OUTBOUND_DIALOGUE_RULES_MAP = {
    "ko": (
        "대화 규칙:\\n"
        "- 실제 사람처럼 자연스럽고 따뜻하게 대화하세요\\n"
        "- 상대방이 말을 더듬거나, 발음이 부정확하거나, 문장이 불완전해도 문맥을 파악해서 이해하세요\\n"
        "- '네', '아~', '그렇군요', '정말요?' 같은 추임새를 자연스럽게 사용하세요\\n"
        "- 상대방의 감정에 공감하세요 (예: '좋으시겠다', '걱정되시겠어요', '다행이네요')\\n"
        "- 한 번에 1~2문장만 짧게 답하세요 (전화 대화는 짧아야 자연스럽습니다)\\n"
        "- 한국어 존댓말을 사용하세요\\n"
        "- 'AI입니다'라고 밝히지 마세요. 자연스럽게 대리인처럼 행동하세요\\n"
        "- 상대방이 '뭐라고?', '다시?', '못 알아듣겠어' 하면 쉬운 말로 다시 설명하세요\\n"
        "- 반드시 안부를 물어보세요 (건강, 근황, 요즘 생활 등)\\n"
        "- 상대방의 답변을 듣고 공감한 뒤 추가 질문을 하세요\\n"
        "- 최소 2~3번은 대화를 주고받은 후에 마무리하세요. 첫 답변에 바로 끝내지 마세요\\n"
        "\\n"
        "🔧 더듬는 상대방 대응 규칙 (매우 중요!):\\n"
        "- 상대방이 '음...', '어...', '그게...' 같은 망설임 표현을 사용하면, 절대 서두르지 말고 '네, 천천히 말씀하세요~' 라고 기다려주세요\\n"
        "- 상대방의 말이 끊기거나 불완전해도 문맥에서 의미를 최대한 유추하세요\\n"
        "- 예시: '오늘... 그... 뭐지... 집에...' → '아~ 오늘 집에서 뭔가 하실 계획이신 거죠?' 라고 유추해서 확인\\n"
        "- 예시: '별로... 아무것도...' → '아~ 특별한 계획은 없으신 거군요' 라고 자연스럽게 이해\\n"
        "- 음성인식이 부정확하게 들려도 (예: '가게 아 뭐 집에서' → '집에서 뭔가 하실 건가요?') 최선을 다해 해석하세요\\n"
        "- 이해가 안 되면 '혹시 ~라고 말씀하신 건가요?' 라고 부드럽게 확인하세요. 절대 '못 알아듣겠습니다' 라고 하지 마세요\\n"
        "- 상대방이 짧게만 답해도 ('네', '아니요', '그냥요') 당황하지 말고 자연스럽게 다른 주제로 넘어가세요"
    ),
    "en": (
        "Conversation rules:\\n"
        "- Speak naturally and warmly like a real person\\n"
        "- Even if the other person stumbles, has unclear pronunciation, or incomplete sentences, understand from context\\n"
        "- Use natural fillers like 'Sure', 'I see', 'Really?', 'That's great'\\n"
        "- Empathize with their emotions (e.g., 'That sounds wonderful', 'I hope you feel better', 'That's good to hear')\\n"
        "- Keep responses to 1-2 sentences (phone conversations should be brief)\\n"
        "- Use polite English\\n"
        "- Don't reveal you are an AI. Act naturally as a representative\\n"
        "- If they say 'What?', 'Again?', 'I don't understand', rephrase simply\\n"
        "- Always ask about their well-being (health, recent life, how things are going)\\n"
        "- Listen to their response, empathize, then ask follow-up questions\\n"
        "- Exchange at least 2-3 turns before wrapping up. Don't end after the first response\\n"
        "\\n"
        "Handling hesitant speakers (very important!):\\n"
        "- If they say 'um...', 'uh...', 'well...', 'let me think...', DON'T rush them. Say 'Sure, take your time'\\n"
        "- Even if their speech is broken or incomplete, infer meaning from context as best you can\\n"
        "- Example: 'Today... um... I think... maybe home...' → 'Sounds like you're planning to stay home today?'\\n"
        "- If you truly can't understand, gently confirm: 'Did you mean...?' Never say 'I can't understand you'\\n"
        "- If they give very short answers ('yes', 'no', 'not much'), don't panic — smoothly move to a new topic"
    ),
    "ja": (
        "会話ルール:\\n"
        "- 本物の人間のように自然で温かく会話してください\\n"
        "- 相手が言葉に詰まったり、発音が不明瞭だったり、文が不完全でも文脈で理解してください\\n"
        "- 「はい」「あ～」「そうなんですね」「本当ですか？」などの相槌を自然に使ってください\\n"
        "- 相手の感情に共感してください（例：「良かったですね」「心配ですね」「安心しました」）\\n"
        "- 一度に1～2文だけ短く答えてください（電話会話は短い方が自然です）\\n"
        "- 日本語の丁寧語を使ってください\\n"
        "- 「AIです」と明かさないでください。自然に代理人として振る舞ってください\\n"
        "- 相手が「何？」「もう一回？」「分からない」と言ったら簡単な言葉で説明し直してください\\n"
        "- 必ず安否を尋ねてください（健康、近況、最近の生活など）\\n"
        "- 相手の返答を聞いて共感した後、追加の質問をしてください\\n"
        "- 最低2～3回はやり取りしてからまとめてください。最初の返答ですぐに終わらないでください\\n"
        "\\n"
        "言葉に詰まる相手への対応（非常に重要！）：\\n"
        "- 相手が「えーと...」「あの...」「その...」と言ったら、急かさずに「はい、ゆっくりどうぞ」と待ってください\\n"
        "- 言葉が途切れたり不完全でも、文脈から意味を最大限推測してください\\n"
        "- 例：「今日は...その...なんか...家で...」→「あ～今日はお家で何かされるんですね？」\\n"
        "- 本当に分からなければ「〜ということでしょうか？」と優しく確認してください\\n"
        "- 短い返答（「はい」「いいえ」「別に」）でも慌てず、自然に別の話題に移ってください"
    ),
    "zh": (
        "对话规则：\\n"
        "- 像真人一样自然而温暖地对话\\n"
        "- 即使对方说话结巴、发音不清或句子不完整，也要从上下文理解\\n"
        "- 自然地使用'好的'、'是的'、'原来如此'、'真的吗？'等语气词\\n"
        "- 对对方的情感要有同理心（例如：'太好了'、'希望您好起来'、'那太好了'）\\n"
        "- 每次只简短回答1-2句（电话对话要简短才自然）\\n"
        "- 使用礼貌的中文\\n"
        "- 不要表明自己是AI。自然地作为代理人行事\\n"
        "- 如果对方说'什么？'、'再说一遍？'、'听不懂'，就用简单的话重新解释\\n"
        "- 一定要问候对方（健康、近况、最近生活等）\\n"
        "- 听完对方的回答后表示共鸣，然后提出后续问题\\n"
        "- 至少交流2-3轮后再结束。不要在第一次回答后就结束\\n"
        "\\n"
        "处理说话犹豫的对方（非常重要！）：\\n"
        "- 如果对方说'嗯...'、'那个...'、'就是...'，不要催促，说'好的，慢慢说'\\n"
        "- 即使话语断断续续或不完整，也要尽最大努力从上下文推断含义\\n"
        "- 例如：'今天...那个...可能...在家...' → '啊～您今天打算在家里待着是吧？'\\n"
        "- 如果真的听不懂，温柔地确认：'您是说～吗？'绝不要说'我听不懂'\\n"
        "- 对方回答很简短（'是'、'不是'、'没什么'）也不要慌张，自然地转到新话题"
    ),
}

OUTBOUND_DIALOGUE_RULES = OUTBOUND_DIALOGUE_RULES_MAP[DEFAULT_LANG]

# ─── 5. 관리자 명령 처리 프롬프트 (다국어) ───────────────
ADMIN_COMMAND_PROMPTS = {
    "ko": "당신은 친근한 관리자 전용 AI 어시스턴트입니다. 명령을 수행하고 1~2문장으로 자연스럽게 답변하세요. 추임새를 적절히 사용하세요.",
    "en": "You are a friendly admin-only AI assistant. Execute commands and respond naturally in 1-2 sentences. Use appropriate fillers.",
    "ja": "あなたは親しみやすい管理者専用AIアシスタントです。命令を実行し、1～2文で自然に回答してください。適切な相槌を使ってください。",
    "zh": "你是一个友好的管理员专用AI助手。执行指令并用1-2句话自然地回答。适当使用语气词。",
}

ADMIN_COMMAND_PROMPT = ADMIN_COMMAND_PROMPTS[DEFAULT_LANG]

# ─── 6. 다국어 고정 멘트 사전 ─────────────────────────
MESSAGES = {
    "ko": {
        "GREETING_ADMIN":     "안녕하세요 관리자님! 무엇을 도와드릴까요?",
        "GREETING_DEFAULT":   "안녕하세요! 잘 지내고 계시죠?",
        "PIN_REQUEST":        "안녕하세요! 본인 확인을 위해 6자리 PIN 번호를 눌러주세요.",
        "PIN_SUCCESS":        "네, 인증됐어요! 무엇을 도와드릴까요?",
        "PIN_FAIL":           "PIN이 틀렸습니다. {remain}번 남았습니다. 다시 입력해 주세요.",
        "PIN_LOCKED":         "PIN 인증 3회 실패로 차단되었습니다.",
        "PIN_TIMEOUT":        "PIN 입력이 없어 전화를 종료합니다.",
        "TRANSFER":           "네, 담당자에게 바로 연결해 드릴게요. 잠시만요!",
        "NOT_HEARD":          "죄송해요, 잘 못 들었어요. 한 번만 더 말씀해 주시겠어요?",
        "NOT_HEARD_ADMIN":    "관리자님, 잘 못 들었어요. 다시 한번 말씀해 주세요.",
        "NOT_HEARD_OUT":      "죄송해요, 잘 못 들었어요. 괜찮으시면 다시 한번 말씀해 주세요.",
        "SLOW_DOWN":          "죄송해요, 조금만 천천히 말씀해 주시겠어요? 정확히 알아들을 수 있도록요.",
        "SLOW_DOWN_OUT":      "죄송해요, 조금만 천천히 말씀해 주시겠어요? 제가 정확히 알아들을 수 있도록요.",
        "NO_COMMAND":         "관리자님, 잘 못 들었어요. 다시 전화 주시면 바로 도와드릴게요!",
        "BYE_INBOUND":        "다른 궁금하신 점 있으시면 언제든 전화 주세요. 좋은 하루 보내세요!",
        "BYE_ADMIN_SIMPLE":   "네, 관리자님! 필요하시면 언제든 불러주세요. 좋은 하루 되세요!",
        "BYE_ADMIN_OUT":      "네, 관리자님! 더 필요하신 거 있으시면 다시 전화주세요. 좋은 하루 되세요!",
        "DONE_REPORT":        "오늘 말씀해 주신 내용은 제가 잘 정리해서 담당자에게 전달해 드릴게요. 감사합니다, {contact_name}님!",
        "TIMEOUT_REPORT":     "지금 좀 바쁘신 것 같아요. 말씀하신 내용은 담당자에게 전달해 드릴게요. {contact_name}님, 좋은 하루 보내세요!",
        "TIMEOUT_WELFARE":    "지금 통화가 어려우신 것 같아요. 나중에 다시 전화드릴게요. {contact_name}님, 좋은 하루 보내세요!",
        "BLOCKED":            "죄송합니다. 이 번호는 차단되었습니다.",
        "BLOCKED_PIN":        "보안 인증 실패로 차단된 번호입니다.",
        "PLEASE_WAIT":        "잠시만 기다려 주세요.",
        "VOICE_REPORT_PREFIX": "통화 보고입니다. ",
        "WAIT_THINKING":      "네, 천천히 생각하시고 말씀해 주세요. 기다릴게요.",
        "ENCOURAGE_SPEAK":    "괜찮아요, 편하게 말씀해 주세요. 듣고 있어요.",
        "FRAGMENT_CONFIRM":   "혹시 {fragment} 라고 말씀하신 건가요? 조금만 더 말씀해 주시겠어요?",
    },
    "en": {
        "GREETING_ADMIN":     "Hello! How can I help you today?",
        "GREETING_DEFAULT":   "Hello! How have you been?",
        "PIN_REQUEST":        "Hello! Please enter your 6-digit PIN for verification.",
        "PIN_SUCCESS":        "Great, you're verified! How can I help you?",
        "PIN_FAIL":           "Incorrect PIN. You have {remain} attempts left. Please try again.",
        "PIN_LOCKED":         "Your account has been locked after 3 failed PIN attempts.",
        "PIN_TIMEOUT":        "No PIN entered. Ending the call.",
        "TRANSFER":           "Sure, let me connect you to the person in charge right away!",
        "NOT_HEARD":          "Sorry, I didn't catch that. Could you say that again?",
        "NOT_HEARD_ADMIN":    "Sorry, I didn't catch that. Could you repeat that please?",
        "NOT_HEARD_OUT":      "Sorry, I didn't catch that. Would you mind saying that again?",
        "SLOW_DOWN":          "Sorry, could you speak a little slower? So I can understand you better.",
        "SLOW_DOWN_OUT":      "Sorry, could you speak a bit slower? I want to make sure I understand correctly.",
        "NO_COMMAND":         "Sorry, I didn't catch that. Please call back and I'll help you right away!",
        "BYE_INBOUND":        "If you have any other questions, feel free to call anytime. Have a great day!",
        "BYE_ADMIN_SIMPLE":   "Sure! Call me anytime you need help. Have a great day!",
        "BYE_ADMIN_OUT":      "Sure! If you need anything else, just call again. Have a great day!",
        "DONE_REPORT":        "I'll organize everything you've told me and pass it along to the person in charge. Thank you, {contact_name}!",
        "TIMEOUT_REPORT":     "It seems like you're a bit busy right now. I'll pass along what you've said. Have a great day, {contact_name}!",
        "TIMEOUT_WELFARE":    "It seems like it's not a good time to talk. I'll call again later. Have a great day, {contact_name}!",
        "BLOCKED":            "Sorry, this number has been blocked.",
        "BLOCKED_PIN":        "This number has been blocked due to failed security verification.",
        "PLEASE_WAIT":        "Please hold on a moment.",
        "VOICE_REPORT_PREFIX": "Call report: ",
        "WAIT_THINKING":      "Sure, take your time. I'm listening.",
        "ENCOURAGE_SPEAK":    "It's okay, please go ahead. I'm here.",
        "FRAGMENT_CONFIRM":   "Did you say {fragment}? Could you tell me a little more?",
    },
    "ja": {
        "GREETING_ADMIN":     "こんにちは、管理者様！何かお手伝いしましょうか？",
        "GREETING_DEFAULT":   "こんにちは！お元気ですか？",
        "PIN_REQUEST":        "こんにちは！本人確認のため6桁のPIN番号を入力してください。",
        "PIN_SUCCESS":        "はい、認証されました！何かお手伝いしましょうか？",
        "PIN_FAIL":           "PINが間違っています。残り{remain}回です。もう一度入力してください。",
        "PIN_LOCKED":         "PIN認証3回失敗によりブロックされました。",
        "PIN_TIMEOUT":        "PIN入力がないため電話を終了します。",
        "TRANSFER":           "はい、担当者にすぐお繋ぎしますね。少々お待ちください！",
        "NOT_HEARD":          "すみません、よく聞き取れませんでした。もう一度おっしゃっていただけますか？",
        "NOT_HEARD_ADMIN":    "管理者様、よく聞き取れませんでした。もう一度お願いします。",
        "NOT_HEARD_OUT":      "すみません、よく聞き取れませんでした。もう一度おっしゃっていただけますか？",
        "SLOW_DOWN":          "すみません、もう少しゆっくりお話しいただけますか？正確に聞き取れるように。",
        "SLOW_DOWN_OUT":      "すみません、もう少しゆっくりお話しいただけますか？正確に理解できるように。",
        "NO_COMMAND":         "管理者様、よく聞き取れませんでした。もう一度お電話いただければすぐにお手伝いします！",
        "BYE_INBOUND":        "他にご質問がありましたら、いつでもお電話ください。良い一日を！",
        "BYE_ADMIN_SIMPLE":   "はい、管理者様！必要な時はいつでもお呼びください。良い一日を！",
        "BYE_ADMIN_OUT":      "はい、管理者様！他に必要なことがあればまたお電話ください。良い一日を！",
        "DONE_REPORT":        "今日おっしゃった内容は整理して担当者にお伝えしますね。ありがとうございます、{contact_name}様！",
        "TIMEOUT_REPORT":     "今少しお忙しそうですね。おっしゃった内容は担当者にお伝えします。{contact_name}様、良い一日を！",
        "TIMEOUT_WELFARE":    "今お電話が難しいようですね。後でまたお電話しますね。{contact_name}様、良い一日を！",
        "BLOCKED":            "申し訳ございません。この番号はブロックされています。",
        "BLOCKED_PIN":        "セキュリティ認証失敗によりブロックされた番号です。",
        "PLEASE_WAIT":        "少々お待ちください。",
        "VOICE_REPORT_PREFIX": "通話報告です。",
        "WAIT_THINKING":      "はい、ゆっくり考えてください。お待ちしています。",
        "ENCOURAGE_SPEAK":    "大丈夫ですよ、お気軽にお話しください。聞いていますよ。",
        "FRAGMENT_CONFIRM":   "{fragment}とおっしゃいましたか？もう少し詳しく教えていただけますか？",
    },
    "zh": {
        "GREETING_ADMIN":     "您好！有什么可以帮您的吗？",
        "GREETING_DEFAULT":   "您好！最近过得怎么样？",
        "PIN_REQUEST":        "您好！请输入6位PIN码进行身份验证。",
        "PIN_SUCCESS":        "好的，验证通过！有什么可以帮您的吗？",
        "PIN_FAIL":           "PIN码错误。还剩{remain}次机会。请重新输入。",
        "PIN_LOCKED":         "PIN验证失败3次，账号已被锁定。",
        "PIN_TIMEOUT":        "未输入PIN码，通话结束。",
        "TRANSFER":           "好的，马上为您转接负责人。请稍等！",
        "NOT_HEARD":          "抱歉，没有听清楚。能再说一遍吗？",
        "NOT_HEARD_ADMIN":    "抱歉，没有听清楚。请再说一遍。",
        "NOT_HEARD_OUT":      "抱歉，没有听清楚。方便再说一遍吗？",
        "SLOW_DOWN":          "抱歉，能稍微慢一点说吗？这样我能更准确地理解。",
        "SLOW_DOWN_OUT":      "抱歉，能稍微慢一点说吗？我想确保准确理解您的意思。",
        "NO_COMMAND":         "抱歉，没有听清楚。请再打来，我会立即为您服务！",
        "BYE_INBOUND":        "如果还有其他问题，随时来电。祝您有美好的一天！",
        "BYE_ADMIN_SIMPLE":   "好的！需要的时候随时联系我。祝您有美好的一天！",
        "BYE_ADMIN_OUT":      "好的！如果还需要什么，请再打电话。祝您有美好的一天！",
        "DONE_REPORT":        "今天您说的内容我会整理好转达给负责人。谢谢您，{contact_name}！",
        "TIMEOUT_REPORT":     "看起来您现在有点忙。您说的内容我会转达给负责人。{contact_name}，祝您有美好的一天！",
        "TIMEOUT_WELFARE":    "看起来现在不方便通话。我稍后再打给您。{contact_name}，祝您有美好的一天！",
        "BLOCKED":            "抱歉，此号码已被屏蔽。",
        "BLOCKED_PIN":        "由于安全验证失败，此号码已被屏蔽。",
        "PLEASE_WAIT":        "请稍等。",
        "VOICE_REPORT_PREFIX": "通话报告：",
        "WAIT_THINKING":      "好的，慢慢想，我等着您。",
        "ENCOURAGE_SPEAK":    "没关系，请随意说。我在听。",
        "FRAGMENT_CONFIRM":   "您是说{fragment}吗？能再多说一点吗？",
    },
}

# ─── 기존 MSG_ 변수 호환성 유지 (DEFAULT_LANG 기준) ────
MSG_GREETING_ADMIN    = MESSAGES[DEFAULT_LANG]["GREETING_ADMIN"]
MSG_GREETING_DEFAULT  = MESSAGES[DEFAULT_LANG]["GREETING_DEFAULT"]
MSG_PIN_REQUEST       = MESSAGES[DEFAULT_LANG]["PIN_REQUEST"]
MSG_PIN_SUCCESS       = MESSAGES[DEFAULT_LANG]["PIN_SUCCESS"]
MSG_TRANSFER          = MESSAGES[DEFAULT_LANG]["TRANSFER"]
MSG_NOT_HEARD         = MESSAGES[DEFAULT_LANG]["NOT_HEARD"]
MSG_NOT_HEARD_ADMIN   = MESSAGES[DEFAULT_LANG]["NOT_HEARD_ADMIN"]
MSG_NOT_HEARD_OUT     = MESSAGES[DEFAULT_LANG]["NOT_HEARD_OUT"]
MSG_SLOW_DOWN         = MESSAGES[DEFAULT_LANG]["SLOW_DOWN"]
MSG_SLOW_DOWN_OUT     = MESSAGES[DEFAULT_LANG]["SLOW_DOWN_OUT"]
MSG_NO_COMMAND        = MESSAGES[DEFAULT_LANG]["NO_COMMAND"]
MSG_BYE_INBOUND       = MESSAGES[DEFAULT_LANG]["BYE_INBOUND"]
MSG_BYE_ADMIN_SIMPLE  = MESSAGES[DEFAULT_LANG]["BYE_ADMIN_SIMPLE"]
MSG_BYE_ADMIN_OUT     = MESSAGES[DEFAULT_LANG]["BYE_ADMIN_OUT"]
MSG_DONE_REPORT       = MESSAGES[DEFAULT_LANG]["DONE_REPORT"]
MSG_TIMEOUT_REPORT    = MESSAGES[DEFAULT_LANG]["TIMEOUT_REPORT"]
MSG_TIMEOUT_WELFARE   = MESSAGES[DEFAULT_LANG]["TIMEOUT_WELFARE"]

# ─── 7. 타이밍 설정 (초) ──────────────────────────────
TIMEOUT_INBOUND = 7
TIMEOUT_OUTBOUND = 12         # 🔧 8→12초: 상대방이 생각할 시간 충분히 확보
SLOW_DOWN_MAX = 3             # 🔧 2→3회: 천천히 요청 최대 횟수 증가
SLOW_DOWN_MIN_CHARS = 2       # 🔧 3→2자: 더 짧은 음성도 감지

# ─── 7-1. 음성 인식 설정 ─────────────────────────────
SPEECH_TIMEOUT_INBOUND = "auto"    # 수신전화: 자동 감지 (빠른 응답 기대)
SPEECH_TIMEOUT_OUTBOUND = "5"      # 🔧 auto→5초: 상대방이 말을 멈춰도 5초 더 기다림
                                   # (더듬거나 생각할 때 중간에 끊기지 않음)

TIMER_SUMMARY_START = 5.0
TIMER_CALL_REPORT = 10.0
TIMER_SMS_REPORT = 13.0
TIMER_SMS_FAILURE = 10.0
TIMER_SMS_FORWARD = 5.0

# ─── 7-2. 인내심 설정 (더듬는 상대방 대응) ─────────────
PATIENCE_MAX_RETRIES = 3           # 불명확한 음성 시 재질문 최대 횟수
FRAGMENT_ACCUMULATE = True         # 짧은 음성 조각을 누적하여 이해 시도
FRAGMENT_MIN_CHARS = 5             # 이 글자 수 이하면 "조각 음성"으로 판단
HESITATION_KEYWORDS = {
    "ko": ["음", "어", "그게", "저기", "뭐지", "잠깐", "아니", "그러니까", "글쎄"],
    "en": ["um", "uh", "well", "hmm", "let me think", "hold on", "you know", "like"],
    "ja": ["えーと", "あの", "その", "うーん", "ちょっと", "なんか"],
    "zh": ["嗯", "那个", "就是", "怎么说", "等一下"],
}

# ─── 8. 최소 대화 턴 수 ──────────────────────────────
MIN_CONVERSATION_TURNS = 3        # 🔧 2→3턴: 충분한 대화 후 마무리

# ═══════════════════════════════════════════════════════════
# 🔧 다국어 수정 예시:
#
#   DEFAULT_LANG = "en"   ← 기본 언어를 영어로 변경
#
#   COUNTRY_LANG_MAP["+49"] = "de"  ← 독일어 추가 시
#   TWILIO_LANG_CODE["de"] = "de-DE"
#   그리고 MESSAGES["de"], ADMIN_SYSTEM_PROMPTS["de"] 등 추가
#
#   특정 연락처만 다른 언어로:
#   연락처의 전화번호 국가코드로 자동 감지됩니다.
#   예: +81로 시작하는 번호 → 자동으로 일본어 TTS
#
# 수정 후 적용: cd ~/openapi-rag && docker compose restart twilio-bot
# ═══════════════════════════════════════════════════════════
AICEOF

echo "   ✅ AI 비서 설정 파일 생성: twilio-bot/ai_config.py"

############################################
# 10-2. 예약 스케줄러 (scheduler.py)
############################################
cat > twilio-bot/scheduler.py <<'SCHEDEOF'
# ═══════════════════════════════════════════════════════════
# 예약 전화/SMS 스케줄러
# 1회 예약, 반복 예약, 파일 저장, 껐다 켜도 유지
# ═══════════════════════════════════════════════════════════
import json, os, threading, time, uuid
from datetime import datetime, timedelta

SCHEDULE_FILE = "/app/data/schedules.json"
os.makedirs(os.path.dirname(SCHEDULE_FILE), exist_ok=True)

class Scheduler:
    def __init__(self):
        self.schedules = {}
        self.running = False
        self.thread = None
        self.callback = None  # 전화/SMS 실행 함수
        self.load()

    # ── 파일 저장/로드 ─────────────────────────
    def save(self):
        try:
            with open(SCHEDULE_FILE, "w", encoding="utf-8") as f:
                json.dump(self.schedules, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"⚠️ 스케줄 저장 실패: {e}")

    def load(self):
        try:
            if os.path.exists(SCHEDULE_FILE):
                with open(SCHEDULE_FILE, "r", encoding="utf-8") as f:
                    self.schedules = json.load(f)
                print(f"📅 스케줄 로드: {len(self.schedules)}건")
            else:
                self.schedules = {}
        except Exception as e:
            print(f"⚠️ 스케줄 로드 실패: {e}")
            self.schedules = {}

    # ── 예약 추가 ─────────────────────────────
    def add(self, name, contact_name, action, schedule_time, repeat=None, mission="안부 확인", message="", enabled=True):
        """
        action: "call" 또는 "sms"
        schedule_time: "2025-01-15 15:00" (1회) 또는 "15:00" (반복시 시간만)
        repeat: None(1회), "daily", "weekly:월", "weekly:화", "monthly:15" 등
        """
        sid = str(uuid.uuid4())[:8]
        self.schedules[sid] = {
            "name": name,
            "contact_name": contact_name,
            "action": action,
            "schedule_time": schedule_time,
            "repeat": repeat,
            "mission": mission,
            "message": message,
            "enabled": enabled,
            "created": datetime.now().strftime("%Y-%m-%d %H:%M"),
            "last_run": None,
            "run_count": 0
        }
        self.save()
        print(f"📅 예약 추가: [{sid}] {contact_name}에게 {action} — {schedule_time} {'(반복:'+repeat+')' if repeat else '(1회)'}")
        return sid

    # ── 예약 삭제 ─────────────────────────────
    def remove(self, sid):
        if sid in self.schedules:
            info = self.schedules.pop(sid)
            self.save()
            return info
        return None

    # ── 활성화/비활성화 ──────────────────────
    def toggle(self, sid):
        if sid in self.schedules:
            self.schedules[sid]["enabled"] = not self.schedules[sid]["enabled"]
            self.save()
            return self.schedules[sid]["enabled"]
        return None

    # ── 예약 목록 ─────────────────────────────
    def list_all(self):
        return self.schedules

    # ── 놓친 예약 확인 ────────────────────────
    def check_missed(self):
        now = datetime.now()
        missed = []
        for sid, s in self.schedules.items():
            if not s["enabled"]:
                continue
            if s["repeat"]:
                continue  # 반복 예약은 놓침 처리 안 함 (다음에 실행)
            try:
                sched_dt = datetime.strptime(s["schedule_time"], "%Y-%m-%d %H:%M")
                if sched_dt < now and s["last_run"] is None:
                    missed.append({"sid": sid, **s})
            except:
                continue
        return missed

    # ── 실행 시간 확인 ────────────────────────
    def _should_run(self, s):
        now = datetime.now()
        today_str = now.strftime("%Y-%m-%d")

        if not s["repeat"]:
            # 1회 예약
            try:
                sched_dt = datetime.strptime(s["schedule_time"], "%Y-%m-%d %H:%M")
                return abs((now - sched_dt).total_seconds()) < 45
            except:
                return False
        else:
            # 반복 예약 — 시간 확인
            try:
                sched_time = s["schedule_time"]  # "15:00" 형식
                target = datetime.strptime(f"{today_str} {sched_time}", "%Y-%m-%d %H:%M")
                if abs((now - target).total_seconds()) > 45:
                    return False
            except:
                return False

            # 오늘 이미 실행했는지
            if s["last_run"] and s["last_run"].startswith(today_str):
                return False

            # 요일/날짜 확인
            repeat = s["repeat"]
            weekdays = {"월":0,"화":1,"수":2,"목":3,"금":4,"토":5,"일":6}
            if repeat == "daily":
                return True
            elif repeat.startswith("weekly:"):
                day_name = repeat.split(":")[1]
                return weekdays.get(day_name, -1) == now.weekday()
            elif repeat.startswith("monthly:"):
                day_num = int(repeat.split(":")[1])
                return now.day == day_num
            return False

    # ── 백그라운드 체크 루프 ──────────────────
    def _loop(self):
        while self.running:
            now = datetime.now()
            for sid, s in list(self.schedules.items()):
                if not s["enabled"]:
                    continue
                if self._should_run(s):
                    print(f"⏰ 예약 실행: [{sid}] {s['contact_name']}에게 {s['action']}")
                    s["last_run"] = now.strftime("%Y-%m-%d %H:%M")
                    s["run_count"] += 1

                    # 콜백 실행
                    if self.callback:
                        try:
                            self.callback(s)
                        except Exception as e:
                            print(f"❌ 예약 실행 오류: {e}")

                    # 1회 예약이면 비활성화
                    if not s["repeat"]:
                        s["enabled"] = False
                        print(f"📅 1회 예약 완료: [{sid}]")

                    self.save()
            time.sleep(30)  # 30초마다 확인

    def start(self, callback):
        self.callback = callback
        self.running = True
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()
        print("📅 스케줄러 시작 (30초 간격 체크)")

    def stop(self):
        self.running = False

scheduler = Scheduler()
SCHEDEOF

echo "   ✅ 예약 스케줄러 생성: twilio-bot/scheduler.py"

############################################
# 10-3. 통화 기록 + 대시보드 (call_history.py)
############################################
cat > twilio-bot/call_history.py <<'HISTEOF'
# ═══════════════════════════════════════════════════════════
# 통화 기록 저장 + 웹 대시보드
# /dashboard — 통화 이력, AI 요약, 대화 내용 조회
# ═══════════════════════════════════════════════════════════
import json, os
from datetime import datetime

HISTORY_FILE = "/app/data/call_history.json"
os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)

def load_records():
    try:
        if os.path.exists(HISTORY_FILE):
            with open(HISTORY_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    except:
        pass
    return []

def save_record(record):
    records = load_records()
    records.insert(0, record)  # 최신순
    # 최대 200건 보관
    records = records[:200]
    try:
        with open(HISTORY_FILE, "w", encoding="utf-8") as f:
            json.dump(records, f, ensure_ascii=False, indent=2)
        print(f"📋 통화 기록 저장: {record.get('name', '')} ({record.get('timestamp', '')})")
    except Exception as e:
        print(f"⚠️ 통화 기록 저장 실패: {e}")

def get_records(limit=50, name_filter=None):
    records = load_records()
    if name_filter:
        records = [r for r in records if name_filter in r.get("name", "")]
    return records[:limit]

def get_dashboard_html():
    return '''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AI 전화비서 대시보드</title>
<link href="https://fonts.googleapis.com/css2?family=Pretendard:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
:root {
  --bg-primary: #0c0c14;
  --bg-card: #13131f;
  --bg-card-hover: #191930;
  --bg-elevated: #1a1a2e;
  --border: rgba(255,255,255,.06);
  --border-active: rgba(108,92,231,.4);
  --text-primary: #f0eff4;
  --text-secondary: #8b8a9e;
  --text-muted: #5a596e;
  --accent: #7c6bf4;
  --accent-light: #9d8ff7;
  --accent-glow: rgba(124,107,244,.15);
  --green: #34d399;
  --green-bg: rgba(52,211,153,.1);
  --blue: #60a5fa;
  --blue-bg: rgba(96,165,250,.1);
  --amber: #fbbf24;
  --amber-bg: rgba(251,191,36,.1);
  --rose: #fb7185;
  --rose-bg: rgba(251,113,133,.1);
  --radius: 14px;
  --radius-sm: 10px;
  --shadow: 0 4px 24px rgba(0,0,0,.3);
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: 'Pretendard', -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
  background: var(--bg-primary);
  color: var(--text-primary);
  line-height: 1.65;
  min-height: 100vh;
}

/* ── 배경 그라데이션 효과 ── */
body::before {
  content: '';
  position: fixed;
  top: -50%;
  left: -50%;
  width: 200%;
  height: 200%;
  background: radial-gradient(ellipse at 30% 20%, rgba(124,107,244,.04) 0%, transparent 50%),
              radial-gradient(ellipse at 70% 80%, rgba(52,211,153,.03) 0%, transparent 50%);
  pointer-events: none;
  z-index: 0;
}

/* ── 헤더 ── */
.header {
  position: relative;
  z-index: 1;
  padding: 2.5rem 2rem 2rem;
  text-align: center;
  border-bottom: 1px solid var(--border);
  background: linear-gradient(180deg, rgba(124,107,244,.06) 0%, transparent 100%);
}

.header-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 56px;
  height: 56px;
  border-radius: 16px;
  background: linear-gradient(135deg, var(--accent), #9f7aea);
  font-size: 1.6rem;
  margin-bottom: .8rem;
  box-shadow: 0 8px 32px rgba(124,107,244,.3);
}

.header h1 {
  font-size: 1.6rem;
  font-weight: 700;
  letter-spacing: -.02em;
  color: var(--text-primary);
}

.header p {
  color: var(--text-secondary);
  font-size: .85rem;
  font-weight: 400;
  margin-top: .35rem;
}

.live-dot {
  display: inline-block;
  width: 7px;
  height: 7px;
  background: var(--green);
  border-radius: 50%;
  margin-right: 6px;
  animation: pulse 2s ease-in-out infinite;
  vertical-align: middle;
}

@keyframes pulse {
  0%, 100% { opacity: 1; box-shadow: 0 0 0 0 rgba(52,211,153,.4); }
  50% { opacity: .7; box-shadow: 0 0 0 6px rgba(52,211,153,0); }
}

/* ── 컨트롤 바 ── */
.controls {
  position: relative;
  z-index: 1;
  max-width: 960px;
  margin: 1.5rem auto;
  padding: 0 1.25rem;
  display: flex;
  gap: .6rem;
  flex-wrap: wrap;
  align-items: center;
}

.search-wrap {
  flex: 1;
  min-width: 180px;
  position: relative;
}

.search-wrap svg {
  position: absolute;
  left: 12px;
  top: 50%;
  transform: translateY(-50%);
  width: 16px;
  height: 16px;
  color: var(--text-muted);
}

.search-wrap input {
  width: 100%;
  padding: .6rem .8rem .6rem 36px;
  border-radius: var(--radius-sm);
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-primary);
  font-family: inherit;
  font-size: .85rem;
  outline: none;
  transition: border-color .2s, box-shadow .2s;
}

.search-wrap input:focus {
  border-color: var(--border-active);
  box-shadow: 0 0 0 3px var(--accent-glow);
}

.search-wrap input::placeholder { color: var(--text-muted); }

.controls select {
  padding: .6rem .8rem;
  border-radius: var(--radius-sm);
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-primary);
  font-family: inherit;
  font-size: .85rem;
  outline: none;
  cursor: pointer;
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg width='10' height='6' viewBox='0 0 10 6' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M1 1L5 5L9 1' stroke='%238b8a9e' stroke-width='1.5' stroke-linecap='round'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 10px center;
  padding-right: 28px;
}

.btn-refresh {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: .6rem 1rem;
  border-radius: var(--radius-sm);
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-primary);
  font-family: inherit;
  font-size: .85rem;
  font-weight: 500;
  cursor: pointer;
  transition: all .2s;
}

.btn-refresh:hover {
  background: var(--bg-elevated);
  border-color: var(--border-active);
}

.btn-refresh:active { transform: scale(.97); }

.btn-refresh svg {
  width: 14px;
  height: 14px;
  transition: transform .4s;
}

.btn-refresh:hover svg { transform: rotate(180deg); }

/* ── 통계 카드 ── */
.stats {
  position: relative;
  z-index: 1;
  max-width: 960px;
  margin: 1.25rem auto;
  padding: 0 1.25rem;
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: .65rem;
}

.stat {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 1.1rem;
  text-align: center;
  transition: border-color .2s, transform .15s;
}

.stat:hover {
  border-color: var(--border-active);
  transform: translateY(-1px);
}

.stat-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 10px;
  font-size: .95rem;
  margin-bottom: .5rem;
}

.stat-icon.purple { background: var(--accent-glow); }
.stat-icon.green { background: var(--green-bg); }
.stat-icon.blue { background: var(--blue-bg); }
.stat-icon.amber { background: var(--amber-bg); }

.stat .num {
  font-size: 1.7rem;
  font-weight: 800;
  letter-spacing: -.03em;
  line-height: 1.2;
}

.stat .num.purple { color: var(--accent-light); }
.stat .num.green { color: var(--green); }
.stat .num.blue { color: var(--blue); }
.stat .num.amber { color: var(--amber); }

.stat .label {
  font-size: .72rem;
  color: var(--text-muted);
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: .05em;
  margin-top: .25rem;
}

/* ── 레코드 카드 ── */
.container {
  position: relative;
  z-index: 1;
  max-width: 960px;
  margin: 1rem auto;
  padding: 0 1.25rem 4rem;
}

.record {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  margin-bottom: .65rem;
  overflow: hidden;
  transition: border-color .2s, box-shadow .2s;
}

.record:hover {
  border-color: rgba(255,255,255,.1);
}

.record-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  padding: 1rem 1.15rem;
  cursor: pointer;
  transition: background .15s;
  gap: 1rem;
}

.record-header:hover { background: var(--bg-card-hover); }

.record-left { flex: 1; min-width: 0; }

.record-top-row {
  display: flex;
  align-items: center;
  gap: .5rem;
  flex-wrap: wrap;
}

.record-name {
  font-weight: 700;
  font-size: .95rem;
  letter-spacing: -.01em;
}

.badge {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  padding: .15rem .55rem;
  border-radius: 20px;
  font-size: .68rem;
  font-weight: 600;
  letter-spacing: .01em;
  white-space: nowrap;
}

.badge.mission {
  background: var(--accent-glow);
  color: var(--accent-light);
}

.badge.completed {
  background: var(--green-bg);
  color: var(--green);
}

.badge.failed {
  background: var(--rose-bg);
  color: var(--rose);
}

.record-greeting {
  color: var(--text-secondary);
  font-size: .8rem;
  margin-top: .3rem;
  display: -webkit-box;
  -webkit-line-clamp: 1;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.record-right {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: .25rem;
  flex-shrink: 0;
}

.record-time {
  color: var(--text-muted);
  font-size: .75rem;
  font-weight: 500;
  white-space: nowrap;
}

.expand-icon {
  width: 20px;
  height: 20px;
  color: var(--text-muted);
  transition: transform .25s ease, color .2s;
}

.record.open .expand-icon { transform: rotate(180deg); color: var(--accent); }

/* ── 레코드 본문 ── */
.record-body {
  display: none;
  padding: 0 1.15rem 1.15rem;
  border-top: 1px solid var(--border);
  animation: slideDown .25s ease;
}

.record-body.open { display: block; }

@keyframes slideDown {
  from { opacity: 0; transform: translateY(-6px); }
  to { opacity: 1; transform: translateY(0); }
}

.summary-block {
  background: linear-gradient(135deg, rgba(52,211,153,.06), rgba(52,211,153,.02));
  border: 1px solid rgba(52,211,153,.12);
  padding: .9rem 1rem;
  border-radius: var(--radius-sm);
  margin: .8rem 0;
}

.summary-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: .72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: var(--green);
  margin-bottom: .4rem;
}

.summary-text {
  font-size: .88rem;
  line-height: 1.7;
  color: var(--text-primary);
}

.dialog-section {
  margin-top: .8rem;
}

.dialog-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: .72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: var(--text-secondary);
  margin-bottom: .6rem;
}

.dialog-turn {
  display: flex;
  flex-direction: column;
  gap: .35rem;
  margin-bottom: .55rem;
}

.dialog-msg {
  display: flex;
  gap: .55rem;
  align-items: flex-start;
  font-size: .84rem;
  line-height: 1.6;
}

.dialog-msg .icon {
  flex-shrink: 0;
  width: 22px;
  height: 22px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: .7rem;
  margin-top: 2px;
}

.dialog-msg.ai .icon { background: var(--blue-bg); }
.dialog-msg.user .icon { background: var(--green-bg); }
.dialog-msg.ai .text { color: var(--blue); }
.dialog-msg.user .text { color: var(--green); }

/* ── 비어있는 상태 ── */
.empty {
  text-align: center;
  padding: 4rem 2rem;
  color: var(--text-muted);
}

.empty-icon {
  font-size: 2.5rem;
  margin-bottom: .8rem;
  opacity: .5;
}

.empty-text {
  font-size: .9rem;
  font-weight: 500;
}

.empty-sub {
  font-size: .78rem;
  color: var(--text-muted);
  margin-top: .3rem;
}

/* ── 로딩 ── */
.loading {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 4rem 2rem;
  gap: .8rem;
}

.spinner {
  width: 28px;
  height: 28px;
  border: 2.5px solid var(--border);
  border-top-color: var(--accent);
  border-radius: 50%;
  animation: spin .7s linear infinite;
}

@keyframes spin { to { transform: rotate(360deg); } }

.loading-text { color: var(--text-muted); font-size: .85rem; }

/* ── 푸터 ── */
.footer {
  position: relative;
  z-index: 1;
  text-align: center;
  padding: 1rem;
  color: var(--text-muted);
  font-size: .72rem;
  border-top: 1px solid var(--border);
}

/* ── 반응형 ── */
@media (max-width: 640px) {
  .header { padding: 2rem 1.25rem 1.5rem; }
  .header h1 { font-size: 1.3rem; }
  .stats { grid-template-columns: repeat(2, 1fr); }
  .stat { padding: .85rem .7rem; }
  .stat .num { font-size: 1.4rem; }
  .record-header { flex-direction: column; gap: .4rem; }
  .record-right { flex-direction: row; align-items: center; gap: .5rem; }
}
</style>
</head>
<body>

<div class="header">
  <div class="header-icon">📞</div>
  <h1>AI 전화비서 대시보드</h1>
  <p><span class="live-dot"></span>통화 기록 · AI 요약 · 대화 이력</p>
</div>

<div class="controls">
  <div class="search-wrap">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
    <input type="text" id="nameFilter" placeholder="이름으로 검색..." oninput="filterRecords()">
  </div>
  <select id="limitSelect" onchange="loadRecords()">
    <option value="20">최근 20건</option>
    <option value="50" selected>최근 50건</option>
    <option value="100">최근 100건</option>
    <option value="200">전체 200건</option>
  </select>
  <button class="btn-refresh" onclick="loadRecords()">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
    새로고침
  </button>
</div>

<div class="stats" id="stats"></div>
<div class="container" id="records">
  <div class="loading"><div class="spinner"></div><div class="loading-text">데이터를 불러오는 중...</div></div>
</div>

<script>
let allRecords = [];

async function loadRecords() {
  try {
    const limit = document.getElementById('limitSelect').value;
    const r = await fetch('/api/call-history?limit=' + limit);
    const d = await r.json();
    allRecords = d.records || [];
    renderStats();
    filterRecords();
  } catch (e) {
    document.getElementById('records').innerHTML =
      '<div class="empty"><div class="empty-icon">⚠️</div><div class="empty-text">데이터를 불러올 수 없습니다</div><div class="empty-sub">서버 연결을 확인해 주세요</div></div>';
  }
}

function renderStats() {
  const total = allRecords.length;
  const todayStr = new Date().toISOString().slice(0, 10);
  const today = allRecords.filter(r => r.timestamp && r.timestamp.startsWith(todayStr)).length;
  const names = [...new Set(allRecords.map(r => r.name))].length;
  const completed = allRecords.filter(r => r.status === 'completed').length;

  document.getElementById('stats').innerHTML =
    '<div class="stat">' +
      '<div class="stat-icon purple">📊</div>' +
      '<div class="num purple">' + total + '</div>' +
      '<div class="label">전체 통화</div>' +
    '</div>' +
    '<div class="stat">' +
      '<div class="stat-icon green">📅</div>' +
      '<div class="num green">' + today + '</div>' +
      '<div class="label">오늘 통화</div>' +
    '</div>' +
    '<div class="stat">' +
      '<div class="stat-icon blue">👤</div>' +
      '<div class="num blue">' + names + '</div>' +
      '<div class="label">연락처</div>' +
    '</div>' +
    '<div class="stat">' +
      '<div class="stat-icon amber">✅</div>' +
      '<div class="num amber">' + completed + '</div>' +
      '<div class="label">통화 완료</div>' +
    '</div>';
}

function filterRecords() {
  const q = document.getElementById('nameFilter').value.toLowerCase();
  const filtered = q ? allRecords.filter(r => (r.name || '').toLowerCase().includes(q)) : allRecords;

  if (!filtered.length) {
    document.getElementById('records').innerHTML =
      '<div class="empty"><div class="empty-icon">📭</div><div class="empty-text">통화 기록이 없습니다</div>' +
      (q ? '<div class="empty-sub">"' + q + '" 검색 결과가 없습니다</div>' : '<div class="empty-sub">AI 비서가 전화를 걸면 여기에 기록됩니다</div>') +
      '</div>';
    return;
  }

  let html = '';
  filtered.forEach((r, i) => {
    const statusBadge = r.status === 'completed'
      ? '<span class="badge completed">✓ 완료</span>'
      : '<span class="badge failed">미완료</span>';

    const historyHtml = (r.history || []).map(h =>
      '<div class="dialog-turn">' +
        '<div class="dialog-msg ai"><span class="icon">🤖</span><span class="text">' + escHtml(h.ai || '') + '</span></div>' +
        '<div class="dialog-msg user"><span class="icon">🗣</span><span class="text">' + escHtml(h.user || '') + '</span></div>' +
      '</div>'
    ).join('');

    const timeDisplay = r.timestamp || '';
    const dateOnly = timeDisplay.slice(0, 10);
    const timeOnly = timeDisplay.slice(11, 16);

    html += '<div class="record" id="rec-' + i + '">' +
      '<div class="record-header" onclick="toggle(' + i + ')">' +
        '<div class="record-left">' +
          '<div class="record-top-row">' +
            '<span class="record-name">' + escHtml(r.name || '알 수 없음') + '</span>' +
            '<span class="badge mission">📋 ' + escHtml(r.mission || '통화') + '</span>' +
            statusBadge +
          '</div>' +
          (r.greeting ? '<div class="record-greeting">' + escHtml(r.greeting) + '</div>' : '') +
        '</div>' +
        '<div class="record-right">' +
          '<span class="record-time">' + dateOnly + ' <b>' + timeOnly + '</b></span>' +
          '<svg class="expand-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="6 9 12 15 18 9"/></svg>' +
        '</div>' +
      '</div>' +
      '<div class="record-body" id="body-' + i + '">' +
        '<div class="summary-block">' +
          '<div class="summary-label"><span>✨</span> AI 요약</div>' +
          '<div class="summary-text">' + escHtml(r.summary || '요약 정보 없음') + '</div>' +
        '</div>' +
        (historyHtml ? '<div class="dialog-section"><div class="dialog-label"><span>💬</span> 대화 내용</div>' + historyHtml + '</div>' : '') +
      '</div>' +
    '</div>';
  });

  document.getElementById('records').innerHTML = html;
}

function escHtml(s) {
  const d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}

function toggle(i) {
  const body = document.getElementById('body-' + i);
  const rec = document.getElementById('rec-' + i);
  body.classList.toggle('open');
  rec.classList.toggle('open');
}

loadRecords();
setInterval(loadRecords, 30000);
</script>

<div class="footer">AI 전화비서 · 30초마다 자동 갱신</div>

</body></html>'''
HISTEOF

echo "   ✅ 통화 기록 + 대시보드 생성: twilio-bot/call_history.py"

cat > twilio-bot/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY twilio_bot.py .
COPY ai_config.py .
COPY scheduler.py .
COPY call_history.py .
EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--timeout", "60", "twilio_bot:app"]
EOF

############################################
# 11. OpenAPI Tool Server (동일)
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
    title="OpenAPI RAG + Phone Tool Server",
    description="RAG Tool Server with Phone Call & SMS Integration (Qdrant + Ollama + Twilio)",
    version="1.3.0",
)

ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"]
)

# RAG 설정
QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
COLLECTION = os.getenv("QDRANT_COLLECTION", "openapi_rag")
MODEL = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://host.docker.internal:11434")
DATA_DIR = "/app/data"

# Twilio 봇 연동
TWILIO_BOT_URL = os.getenv("TWILIO_BOT_URL", "http://twilio-bot:5000")
API_SECRET = os.getenv("API_SECRET", "")

# Qdrant 초기화
client = None
RETRIES = ${PYTHON_RETRIES}
INTERVAL = ${QDRANT_INTERVAL}

print(f"🔄 Qdrant 연결 시도 중... (최대 {RETRIES}회, {INTERVAL}초 간격)")
for attempt in range(RETRIES):
    try:
        client = QdrantClient(url=QDRANT_URL)
        client.get_collections()
        print(f"✅ Qdrant 연결 성공: {QDRANT_URL}")
        break
    except Exception as e:
        print(f"⏳ Qdrant 연결 대기 중... ({attempt+1}/{RETRIES})")
        time.sleep(INTERVAL)

if not client:
    print("❌ Qdrant 연결 실패")

if client:
    try:
        collections = [c.name for c in client.get_collections().collections]
        if COLLECTION not in collections:
            client.create_collection(
                collection_name=COLLECTION,
                vectors_config=VectorParams(size=768, distance=Distance.COSINE),
            )
            print(f"✅ 컬렉션 생성: {COLLECTION}")
        else:
            print(f"✅ 기존 컬렉션 사용: {COLLECTION}")
    except Exception as e:
        print(f"❌ 컬렉션 생성 실패: {e}")

def embed(text: str):
    try:
        ollama_client = ollama.Client(host=OLLAMA_BASE_URL)
        response = ollama_client.embeddings(model=MODEL, prompt=text)
        return response["embedding"]
    except Exception as e:
        print(f"❌ 임베딩 오류: {e}")
        raise HTTPException(status_code=500, detail=f"Embedding error: {str(e)}")

def rag_lookup(query: str, top_k: int = 2):
    """전화 통화 중 상대방 질문에 대해 RAG 검색 — 관련 문서가 있으면 참고자료 반환"""
    if not client:
        return ""
    try:
        query_vector = embed(query)
        hits = client.search(
            collection_name=COLLECTION,
            query_vector=query_vector,
            limit=top_k,
            score_threshold=0.5
        )
        if not hits:
            return ""
        context_parts = []
        for h in hits:
            text = h.payload.get("text", "")[:300]
            source = h.payload.get("source", "")
            context_parts.append(f"[{source}] {text}")
        context = "\n".join(context_parts)
        print(f"📚 RAG 참고자료 발견 ({len(hits)}건): {query[:30]}...")
        return context
    except Exception as e:
        print(f"⚠️ RAG 검색 실패 (무시): {e}")
        return ""

def embed_batch(texts: list):
    """여러 텍스트를 한 번에 임베딩 (배치 처리)"""
    vectors = []
    ollama_client = ollama.Client(host=OLLAMA_BASE_URL)
    for text in texts:
        try:
            response = ollama_client.embeddings(model=MODEL, prompt=text)
            vectors.append(response["embedding"])
        except Exception as e:
            print(f"⚠️ 배치 임베딩 실패: {e}")
            vectors.append(None)
    return vectors

def smart_chunk(text: str, max_size: int = 1000, overlap: int = 100):
    """문장 경계 기준 스마트 청킹 — 문장 중간에 잘리지 않음"""
    separators = ["\n\n", "\n", ". ", "。", "? ", "! ", "; "]
    chunks = []
    start = 0
    
    while start < len(text):
        end = min(start + max_size, len(text))
        
        if end < len(text):
            # max_size 범위 내에서 가장 가까운 문장 경계 찾기
            best_break = -1
            for sep in separators:
                # 뒤쪽 절반에서 구분자 찾기 (너무 짧은 청크 방지)
                search_start = start + max_size // 2
                pos = text.rfind(sep, search_start, end)
                if pos > best_break:
                    best_break = pos + len(sep)
            
            if best_break > start:
                end = best_break
        
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        
        # 오버랩 적용 (다음 청크 시작점)
        start = max(start + 1, end - overlap)
    
    return chunks

def delete_existing_vectors(filename: str):
    """동일 파일명의 기존 벡터를 삭제 (중복 업로드 방지)"""
    try:
        from qdrant_client.models import Filter, FieldCondition, MatchValue
        result = client.delete(
            collection_name=COLLECTION,
            points_selector=Filter(
                must=[FieldCondition(key="source", match=MatchValue(value=filename))]
            )
        )
        print(f"🗑️ 기존 벡터 삭제: {filename}")
        return True
    except Exception as e:
        print(f"⚠️ 기존 벡터 삭제 실패 (무시): {e}")
        return False

@app.post("/documents/upload", summary="Upload PDF for RAG indexing")
async def upload_pdf(file: UploadFile = File(...)):
    if not client:
        raise HTTPException(status_code=503, detail="Qdrant client not initialized")
    
    try:
        path = f"{DATA_DIR}/{file.filename}"
        with open(path, "wb") as f:
            content = await file.read()
            f.write(content)
        
        print(f"📄 파일 저장: {file.filename}")

        # ── 1. 동일 파일 기존 벡터 삭제 (중복 방지) ──
        delete_existing_vectors(file.filename)

        reader = PdfReader(path)
        text = "".join(p.extract_text() or "" for p in reader.pages)
        
        if not text.strip():
            raise HTTPException(status_code=400, detail="PDF 텍스트 추출 실패")
        
        print(f"📝 텍스트 추출: {len(text)} 문자")

        # ── 2. 스마트 청킹 (문장 경계 기준) ──
        chunks = smart_chunk(text, max_size=1000, overlap=100)
        
        print(f"✂️ 스마트 청크 분할: {len(chunks)}개 (문장 경계 기준)")

        # ── 3. 배치 임베딩 (10개씩 묶어서 처리) ──
        points = []
        batch_size = 10
        for batch_start in range(0, len(chunks), batch_size):
            batch_chunks = chunks[batch_start:batch_start + batch_size]
            batch_vectors = embed_batch(batch_chunks)
            
            for i, (chunk, vector) in enumerate(zip(batch_chunks, batch_vectors)):
                idx = batch_start + i
                if vector is not None:
                    points.append(
                        PointStruct(
                            id=str(uuid.uuid4()),
                            vector=vector,
                            payload={"text": chunk, "source": file.filename, "chunk_index": idx},
                        )
                    )
            
            print(f"🔢 임베딩 진행: {min(batch_start + batch_size, len(chunks))}/{len(chunks)}")

        if not points:
            raise HTTPException(status_code=500, detail="임베딩 실패")

        client.upsert(collection_name=COLLECTION, points=points)
        print(f"💾 저장 완료: {len(points)}개 (중복 제거 후)")
        
        return {
            "status": "success",
            "filename": file.filename,
            "total_chunks": len(chunks),
            "indexed_chunks": len(points),
            "collection": COLLECTION,
            "chunking": "smart (sentence boundary)",
            "duplicate_check": True
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ 업로드 오류: {e}")
        raise HTTPException(status_code=500, detail=f"Upload error: {str(e)}")

class SearchQuery(BaseModel):
    query: str
    top_k: int = 3

@app.post("/rag/search", summary="Semantic search for RAG")
def rag_search(search: SearchQuery):
    if not client:
        raise HTTPException(status_code=503, detail="Qdrant client not initialized")
    
    try:
        query_vector = embed(search.query)
        hits = client.search(
            collection_name=COLLECTION,
            query_vector=query_vector,
            limit=search.top_k,
        )
        
        results = [
            {
                "text": h.payload.get("text", ""),
                "source": h.payload.get("source", ""),
                "chunk_index": h.payload.get("chunk_index", 0),
                "score": h.score
            }
            for h in hits
        ]
        
        return {"query": search.query, "results": results, "count": len(results)}
        
    except Exception as e:
        print(f"❌ 검색 오류: {e}")
        raise HTTPException(status_code=500, detail=f"Search error: {str(e)}")

# 전화 Tool
class CallMeRequest(BaseModel):
    message: str = ""

class CallContactRequest(BaseModel):
    name: str
    mission: str = "안부 확인"
    message: str = ""

@app.post("/tools/call-me", summary="Call admin")
def tool_call_me(req: CallMeRequest):
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

@app.post("/tools/call-contact", summary="Call contact")
def tool_call_contact(req: CallContactRequest):
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/call-contact",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={"name": req.name, "mission": req.mission, "message": req.message},
            timeout=10
        )
        if r.status_code == 200:
            return {"status": "success", "message": f"{req.name}님께 안부전화를 걸었습니다!"}
        return {"status": "error", "message": f"전화 걸기 실패: {r.text}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# SMS 보내기 Tool
class SendSMSRequest(BaseModel):
    to: str
    message: str

@app.post("/tools/send-sms", summary="Send SMS")
def tool_send_sms(req: SendSMSRequest):
    """SMS를 보냅니다 (실패 시에만 관리자 보고, 답장은 자동 전달)."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/send-sms",
            headers={
                "X-API-Secret": API_SECRET,
                "Content-Type": "application/json"
            },
            json={"to": req.to, "message": req.message},
            timeout=10
        )
        
        if r.status_code == 200:
            return {
                "status": "success",
                "message": f"{req.to}로 SMS를 보냈습니다! (답장은 자동으로 전달됩니다)"
            }
        return {
            "status": "error",
            "message": f"SMS 전송 실패: {r.text}"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/tools/contacts", summary="List contacts")
def tool_get_contacts():
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

class ContactRequest(BaseModel):
    name: str
    number: str = ""

@app.post("/tools/contacts/add", summary="Add contact")
def tool_add_contact(req: ContactRequest):
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        number = req.number.strip().replace("-", "").replace(" ", "")
        if number.startswith("010") or number.startswith("011"):
            number = "+82" + number[1:]
        elif number.startswith("01"):
            number = "+82" + number[1:]
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/contacts/add",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={"name": req.name, "number": number},
            timeout=10
        )
        if r.status_code == 200:
            return {"status": "success", "message": f"{req.name}님 번호({number})를 저장했습니다!"}
        return {"status": "error", "message": f"저장 실패: {r.text}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/tools/contacts/delete", summary="Delete contact")
def tool_delete_contact(req: ContactRequest):
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/contacts/delete",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={"name": req.name},
            timeout=10
        )
        if r.status_code == 200:
            return {"status": "success", "message": f"{req.name}님 연락처를 삭제했습니다!"}
        return {"status": "error", "message": f"삭제 실패: {r.text}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 예약 스케줄 Tool 프록시
class ScheduleRequest(BaseModel):
    contact_name: str
    action: str = "call"
    schedule_time: str = ""
    repeat: str = ""
    mission: str = "안부 확인"
    message: str = ""

@app.post("/tools/schedule/add", summary="Add schedule")
def tool_add_schedule(req: ScheduleRequest):
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/schedules/add",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={
                "name": req.contact_name,
                "contact_name": req.contact_name,
                "action": req.action,
                "schedule_time": req.schedule_time,
                "repeat": req.repeat or None,
                "mission": req.mission,
                "message": req.message
            },
            timeout=10
        )
        if r.status_code == 200:
            data = r.json()
            return {"status": "success", "message": f"{req.contact_name}님에게 예약 등록 완료!", "sid": data.get("sid", "")}
        return {"status": "error", "message": f"예약 실패: {r.text}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/tools/schedules", summary="List schedules")
def tool_list_schedules():
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.get(
            f"{TWILIO_BOT_URL}/schedules",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class ScheduleIdRequest(BaseModel):
    sid: str

@app.post("/tools/schedule/remove", summary="Remove schedule")
def tool_remove_schedule(req: ScheduleIdRequest):
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/schedules/remove",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={"sid": req.sid},
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/tools/schedule/toggle", summary="Toggle schedule")
def tool_toggle_schedule(req: ScheduleIdRequest):
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/schedules/toggle",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={"sid": req.sid},
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 통화 기록 조회 프록시
@app.get("/tools/call-history", summary="Get call history")
def tool_call_history():
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        limit = 50
        name = ""
        from fastapi import Query
        r = http_requests.get(
            f"{TWILIO_BOT_URL}/api/call-history?limit=50",
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health", summary="Health check")
def health():
    try:
        if not client:
            return {"status": "unhealthy", "error": "Qdrant client not initialized"}
        client.get_collections()
        return {
            "status": "healthy",
            "qdrant_url": QDRANT_URL,
            "collection": COLLECTION,
            "embed_model": MODEL
        }
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

@app.get("/", summary="API Info")
def root():
    return {
        "service": "OpenAPI RAG + Phone Tool Server",
        "version": "1.3.0",
        "features": ["RAG (Document Upload/Search)", "Phone Call Integration", "SMS Bidirectional Communication"],
        "endpoints": {
            "docs": "/docs",
            "openapi": "/openapi.json",
            "rag_upload": "/documents/upload",
            "rag_search": "/rag/search",
            "phone_call_me": "/tools/call-me",
            "phone_call_contact": "/tools/call-contact",
            "phone_contacts": "/tools/contacts",
            "sms_send": "/tools/send-sms",
            "health": "/health"
        }
    }
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
# 12. docker-compose.yml (동일)
############################################
SECRET_KEY=$(openssl rand -hex 32)
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
      - "127.0.0.1:5000:5000"
    volumes:
      - contacts-data:/app/data
    depends_on:
      - qdrant
      - openapi-tools
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
# 12-1. Docker Secrets Override 설정
############################################
echo ""
echo "🔐 Docker Secrets Override 생성 중..."

cat > docker-compose.override.yml <<'OVEOF'
# ═══════════════════════════════════════════════
# Docker Secrets Override (민감정보 /run/secrets/ 마운트)
# 원본 docker-compose.yml을 수정하지 않고 Secrets 계층 추가
# ═══════════════════════════════════════════════

secrets:
  twilio_auth_token:
    file: ./secrets/twilio_auth_token
  api_secret:
    file: ./secrets/api_secret
  groq_api_key:
    file: ./secrets/groq_api_key
  admin_pin:
    file: ./secrets/admin_pin
  webui_secret_key:
    file: ./secrets/webui_secret_key

services:
  twilio-bot:
    secrets:
      - twilio_auth_token
      - api_secret
      - groq_api_key
      - admin_pin
    volumes:
      - ./secrets/entrypoint-secrets.sh:/entrypoint-secrets.sh:ro
      - ./logs/twilio-bot:/app/logs
      - ./twilio-bot/ai_config.py:/app/ai_config.py:ro
      - ./twilio-bot/scheduler.py:/app/scheduler.py:ro
      - ./twilio-bot/call_history.py:/app/call_history.py:ro
      - ./twilio-bot/data:/app/data
    entrypoint: ["/entrypoint-secrets.sh"]
    command: ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--timeout", "60", "twilio_bot:app"]

  openapi-tools:
    secrets:
      - api_secret
      - groq_api_key
    volumes:
      - ./secrets/entrypoint-secrets.sh:/entrypoint-secrets.sh:ro
      - ./logs/openapi-tools:/app/logs
    entrypoint: ["/entrypoint-secrets.sh"]
    command: ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

  open-webui:
    secrets:
      - webui_secret_key
      - groq_api_key
    # ⚠️ open-webui는 자체 entrypoint가 있으므로 덮어쓰지 않음
    # secrets는 /run/secrets/에 파일로 마운트만 되고, 환경변수는 기존 docker-compose.yml에서 전달
OVEOF

# 로그 디렉토리 생성
mkdir -p "$BASE_DIR/logs/twilio-bot" "$BASE_DIR/logs/openapi-tools" "$BASE_DIR/logs/nginx"
mkdir -p "$BASE_DIR/twilio-bot/data"
echo "   ✅ Docker Secrets Override 생성 완료"
echo "   📄 docker-compose.override.yml (자동 병합)"


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
# Nginx 자동 설정
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🌐 Nginx 자동 설정 중..."
echo "└────────────────────────────────────────────┘"

if ! command -v nginx >/dev/null 2>&1; then
  echo "   ⚙️  Nginx 설치 중..."
  
  sudo apt-get update -qq > /dev/null 2>&1 &
  UPDATE_PID=$!
  
  WAIT_COUNT=0
  while kill -0 $UPDATE_PID 2>/dev/null; do
    WAIT_COUNT=$((WAIT_COUNT + 1))
    printf "   ⏳ 패키지 목록 업데이트 중... %ds\r" $WAIT_COUNT
    sleep 1
  done
  echo ""
  
  sudo apt-get install -y nginx > /dev/null 2>&1 &
  INSTALL_PID=$!
  
  WAIT_COUNT=0
  while kill -0 $INSTALL_PID 2>/dev/null; do
    WAIT_COUNT=$((WAIT_COUNT + 1))
    printf "   ⏳ Nginx 설치 중... %ds\r" $WAIT_COUNT
    sleep 1
  done
  echo ""
  echo "   ✅ Nginx 설치 완료!"
fi

sudo rm -f /etc/nginx/sites-enabled/default

NGINX_CONF="/etc/nginx/sites-available/twilio-bot"
sudo tee "$NGINX_CONF" > /dev/null <<NGINXEOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }

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
    location /send-sms {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
    location /sms-incoming {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
    }
    location /block {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
    location /health {
        proxy_pass http://127.0.0.1:5000;
    }
    # /dashboard, /api/call-history, /schedules는 외부 노출 차단
    # 로컬에서만 접근: http://localhost:5000/dashboard
}
NGINXEOF

if [ ! -f /etc/nginx/sites-enabled/twilio-bot ]; then
  sudo ln -s "$NGINX_CONF" /etc/nginx/sites-enabled/twilio-bot
fi

if sudo nginx -t 2>/dev/null; then
  sudo systemctl reload nginx
  echo "   ✅ Nginx 설정 완료!"
else
  echo "   ⚠️  Nginx 설정 오류"
fi

############################################
# 구조화된 JSON 접근 로그 설정
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "📋 구조화된 접근 로그 설정 중..."
echo "└────────────────────────────────────────────┘"

# Nginx JSON 감사 로그 포맷 추가
sudo tee /etc/nginx/conf.d/audit-log-format.conf > /dev/null << 'AUDITEOF'
# ═══════════════════════════════════════════════
# 구조화된 JSON 접근 로그 (감사 추적용)
# 모든 요청의 IP, 메서드, 경로, 상태, 응답시간 기록
# ═══════════════════════════════════════════════
log_format json_audit escape=json
  '{'
    '"timestamp":"$time_iso8601",'
    '"remote_addr":"$remote_addr",'
    '"x_forwarded_for":"$http_x_forwarded_for",'
    '"request_method":"$request_method",'
    '"request_uri":"$request_uri",'
    '"server_protocol":"$server_protocol",'
    '"status":$status,'
    '"body_bytes_sent":$body_bytes_sent,'
    '"request_time":$request_time,'
    '"upstream_response_time":"$upstream_response_time",'
    '"http_user_agent":"$http_user_agent",'
    '"http_referer":"$http_referer",'
    '"request_id":"$request_id"'
  '}';
AUDITEOF

# 감사 로그 디렉토리 생성 + logrotate 설정
sudo mkdir -p /var/log/nginx
sudo touch /var/log/nginx/audit.json.log
sudo chown www-data:adm /var/log/nginx/audit.json.log

# 기존 Nginx 서버 블록에 감사 로그 추가 (server { 바로 다음에 삽입)
NGINX_CONF="/etc/nginx/sites-available/twilio-bot"
if [ -f "$NGINX_CONF" ]; then
  if ! grep -q "json_audit" "$NGINX_CONF"; then
    sudo sed -i '/server {/a\    \n    # 구조화된 JSON 감사 로그\n    access_log /var/log/nginx/audit.json.log json_audit;\n    access_log /var/log/nginx/access.log;' "$NGINX_CONF"
  fi
fi

# 로그 로테이션 설정 (일별, 최대 30일 보관, 압축)
sudo tee /etc/logrotate.d/nginx-audit > /dev/null << 'ROTEOF'
/var/log/nginx/audit.json.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid) 2>/dev/null || true
    endscript
}
ROTEOF

# Nginx 재로드
if sudo nginx -t 2>/dev/null; then
  sudo systemctl reload nginx
  echo "   ✅ 구조화된 JSON 감사 로그 활성화!"
  echo "   📄 로그 파일: /var/log/nginx/audit.json.log"
  echo "   🔄 로그 로테이션: 일별, 30일 보관, 자동 압축"
else
  echo "   ⚠️  Nginx 설정 오류 — 감사 로그 수동 확인 필요"
fi

# 로그 조회 도우미 스크립트 생성
cat > "$BASE_DIR/view-audit-log.sh" << 'VIEWEOF'
#!/bin/bash
# ═══════════════════════════════════════════════
# 감사 로그 조회 도우미
# 사용법: ./view-audit-log.sh [옵션]
#   (인수 없음) → 최근 20개
#   tail       → 실시간 모니터링
#   errors     → 4xx/5xx 에러만
#   search     → 특정 경로 검색
# ═══════════════════════════════════════════════
LOG="/var/log/nginx/audit.json.log"

case "${1:-}" in
  tail)
    echo "📋 실시간 감사 로그 (Ctrl+C 종료)"
    sudo tail -f "$LOG" | python3 -c "
import sys,json
for line in sys.stdin:
    try:
        d=json.loads(line.strip())
        ts=d.get('timestamp','?')[:19]
        ip=d.get('remote_addr','?')
        m=d.get('request_method','?')
        u=d.get('request_uri','?')[:60]
        s=d.get('status',0)
        t=d.get('request_time',0)
        icon='✅' if s<400 else '⚠️' if s<500 else '❌'
        print(f'{icon} {ts} | {ip:15s} | {m:4s} {s} | {t}s | {u}')
    except: pass
"
    ;;
  errors)
    echo "❌ 에러 요청 (4xx/5xx):"
    sudo cat "$LOG" | python3 -c "
import sys,json
for line in sys.stdin:
    try:
        d=json.loads(line.strip())
        if d.get('status',0)>=400:
            print(json.dumps(d,ensure_ascii=False,indent=2))
    except: pass
" | tail -100
    ;;
  search)
    echo "🔍 경로 검색: $2"
    sudo grep "\"$2\"" "$LOG" | python3 -c "
import sys,json
for line in sys.stdin:
    try:
        d=json.loads(line.strip())
        ts=d.get('timestamp','?')[:19]
        ip=d.get('remote_addr','?')
        s=d.get('status',0)
        print(f'{ts} | {ip:15s} | {s}')
    except: pass
" | tail -50
    ;;
  *)
    echo "📋 최근 감사 로그 20건:"
    sudo tail -20 "$LOG" | python3 -c "
import sys,json
for line in sys.stdin:
    try:
        d=json.loads(line.strip())
        ts=d.get('timestamp','?')[:19]
        ip=d.get('remote_addr','?')
        m=d.get('request_method','?')
        u=d.get('request_uri','?')[:50]
        s=d.get('status',0)
        t=d.get('request_time',0)
        icon='✅' if s<400 else '⚠️' if s<500 else '❌'
        print(f'{icon} {ts} | {ip:15s} | {m:4s} {s} | {t}s | {u}')
    except: pass
"
    echo ""
    echo "사용법: $0 [tail|errors|search <경로>]"
    ;;
esac
VIEWEOF
chmod +x "$BASE_DIR/view-audit-log.sh"
echo "   🔧 로그 조회 도구: $BASE_DIR/view-audit-log.sh"

############################################
# Cloudflare Tunnel 설정 (선택)
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "☁️  Cloudflare Tunnel 설정 (HTTPS 외부 접속)"
echo "└────────────────────────────────────────────┘"
echo ""
echo "   Cloudflare Tunnel을 사용하면 포트 개방 없이"
echo "   HTTPS로 외부에서 안전하게 접속할 수 있습니다."
echo ""

read -t 120 -p "☁️  Cloudflare Tunnel을 설정하시겠습니까? (y/N, 120초 내 Enter=건너뜀): " SETUP_CF_TUNNEL || true
SETUP_CF_TUNNEL=${SETUP_CF_TUNNEL:-N}

if [[ "$SETUP_CF_TUNNEL" =~ ^[Yy]$ ]]; then
  echo ""
  echo "   📌 Cloudflare Zero Trust 대시보드에서 Tunnel Token이 필요합니다."
  echo "   https://one.dash.cloudflare.com/ → Networks → Tunnels → Create"
  echo "   → Cloudflared 선택 → Token 복사"
  echo ""

  read -t 300 -p "   🔑 Cloudflare Tunnel Token 입력 (300초 내): " CF_TUNNEL_TOKEN || true
  CF_TUNNEL_TOKEN=$(echo "$CF_TUNNEL_TOKEN" | xargs)

  if [ -n "$CF_TUNNEL_TOKEN" ]; then
    # cloudflared 설치
    if ! command -v cloudflared >/dev/null 2>&1; then
      echo "   ⚙️  cloudflared 설치 중..."
      curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null 2>&1
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null 2>&1
      sudo apt-get update -qq >/dev/null 2>&1
      sudo apt-get install -y cloudflared >/dev/null 2>&1
      echo "   ✅ cloudflared 설치 완료 ($(cloudflared --version 2>/dev/null | head -1))"
    else
      echo "   ✅ cloudflared 이미 설치됨 ($(cloudflared --version 2>/dev/null | head -1))"
    fi

    # Token 기반 서비스 등록 (Cloudflare 대시보드에서 라우팅 설정)
    echo "   ⚙️  Cloudflare Tunnel 서비스 등록 중..."
    sudo cloudflared service install "$CF_TUNNEL_TOKEN" 2>/dev/null || true
    sudo systemctl enable cloudflared 2>/dev/null || true
    sudo systemctl start cloudflared 2>/dev/null || true

    sleep 3

    if sudo systemctl is-active --quiet cloudflared 2>/dev/null; then
      echo "   ✅ Cloudflare Tunnel 활성화 완료!"
      echo ""
      echo "   📌 Cloudflare 대시보드에서 라우팅을 설정하세요:"
      echo "   https://one.dash.cloudflare.com/ → Networks → Tunnels"
      echo ""
      echo "   권장 라우팅:"
      echo "   ┌──────────────────────────┬──────────────────────────┐"
      echo "   │ 외부 도메인               │ 내부 서비스               │"
      echo "   ├──────────────────────────┼──────────────────────────┤"
      echo "   │ ai.yourdomain.com        │ http://localhost:3000    │"
      echo "   │ twilio.yourdomain.com    │ http://localhost:5000    │"
      echo "   │ api.yourdomain.com       │ http://localhost:8000    │"
      echo "   └──────────────────────────┴──────────────────────────┘"
      echo ""
      echo "   ⚠️  Twilio Console에서 Webhook URL을 변경하세요:"
      echo "   Voice: https://twilio.yourdomain.com/voice"
      echo "   SMS:   https://twilio.yourdomain.com/sms-incoming"

      # Tunnel Token 안전 저장
      echo -n "$CF_TUNNEL_TOKEN" > "$BASE_DIR/secrets/cf_tunnel_token"
      chmod 600 "$BASE_DIR/secrets/cf_tunnel_token"
    else
      echo "   ⚠️  Cloudflare Tunnel 시작 실패 — 수동 확인 필요"
      echo "   sudo systemctl status cloudflared"
      echo "   sudo journalctl -u cloudflared -f"
    fi
  else
    echo "   ⭐️ Cloudflare Tunnel Token 건너뜀"
  fi
else
  echo "   ⭐️ Cloudflare Tunnel 건너뜀 (나중에 설치 가능)"
  echo "   설치법: sudo cloudflared service install <TOKEN>"
fi


############################################
# OpenWebUI 계정 생성 + API 키 발급 + Tool 자동 등록
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔐 OpenWebUI 계정 생성 + Tool 자동 등록 중..."
echo "└────────────────────────────────────────────┘"

OW_READY=false
for i in $(seq 1 24); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null)
  if [ "$STATUS" = "200" ]; then
    OW_READY=true
    echo "   ✅ OpenWebUI 준비 완료!"
    break
  fi
  echo "   ⏳ OpenWebUI 대기 중... (${i}/24)"
  sleep 5
done

echo "   ⚙️  관리자 계정 생성 중..."
curl -s -X POST http://localhost:3000/api/v1/auths/signup \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Admin\",\"email\":\"${OW_EMAIL}\",\"password\":\"${OW_PASSWORD}\"}" >/dev/null 2>&1

sleep 2

SIGNIN_RESP=$(curl -s -X POST http://localhost:3000/api/v1/auths/signin \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${OW_EMAIL}\",\"password\":\"${OW_PASSWORD}\"}")

OW_JWT=$(echo "$SIGNIN_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -n "$OW_JWT" ]; then
  echo "   ✅ 로그인 성공!"
  OW_API_KEY="$OW_JWT"
  
  sed -i "s|OPENWEBUI_API_KEY=.*|OPENWEBUI_API_KEY=${OW_API_KEY}|g" docker-compose.yml
  if grep -q "OPENWEBUI_API_KEY" .env; then
    sed -i "s|OPENWEBUI_API_KEY=.*|OPENWEBUI_API_KEY=${OW_API_KEY}|g" .env
  else
    echo "OPENWEBUI_API_KEY=${OW_API_KEY}" >> .env
  fi
  
  docker compose up -d twilio-bot
  sleep 5
  echo "   ✅ Twilio 봇 API 키 적용 완료!"

  echo "   ⚙️  OpenWebUI Tool 자동 등록 중..."

  cat > /tmp/register_tools.py << 'PYEOF'
import json, urllib.request, sys

jwt = sys.argv[1]

phone_tool_code = '''\
"""
title: 전화 어시스턴트
author: AI Phone Bot
description: 전화 걸기, 안부전화(사용자 메시지 직접 전달 가능), 연락처 저장/삭제/조회, 통화 기록 조회
version: 2.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def call_me(self) -> str:
        """관리자한테 전화를 걸어줍니다."""
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/call-me", json={}, timeout=10)
            return r.json().get("message", "전화를 걸었습니다.")
        except Exception as e:
            return f"오류: {e}"

    def call_contact(self, name: str, mission: str = "안부 확인", message: str = "") -> str:
        """저장된 연락처에게 전화를 걸어줍니다.

        Args:
            name: 연락처 이름 (예: 김철수)
            mission: AI가 수행할 임무 (예: 안부 확인, 회의 참석 여부 확인)
            message: 상대방에게 직접 전달할 말. 반드시 사용자가 전달하려는 문장을 그대로 넣으세요.

        사용 예시:
            "김철수한테 안부전화 해줘. 어떻게 지내세요?" → name="김철수", mission="안부 확인", message="어떻게 지내세요?"
            "김철수한테 전화해줘. 건강하게 잘 있나?" → name="김철수", mission="안부 확인", message="건강하게 잘 있나?"
            "김철수한테 전화해서 내일 회의 참석 가능한지 물어봐" → name="김철수", mission="내일 회의 참석 여부 확인", message="내일 회의 참석 가능하세요?"
            "김철수한테 전화해줘" → name="김철수", mission="안부 확인", message=""

        중요: 사용자가 마침표/쉼표 뒤에 전달할 말을 적었다면 message에 반드시 포함하세요. 비워두면 AI가 자동 생성합니다.
        """
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/call-contact",
                            json={"name": name, "mission": mission, "message": message}, timeout=10)
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

    def save_contact(self, name: str, number: str) -> str:
        """연락처를 저장합니다."""
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/contacts/add",
                            json={"name": name, "number": number}, timeout=10)
            return r.json().get("message", f"{name}님 번호를 저장했습니다.")
        except Exception as e:
            return f"오류: {e}"

    def delete_contact(self, name: str) -> str:
        """연락처를 삭제합니다."""
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/contacts/delete",
                            json={"name": name, "number": ""}, timeout=10)
            return r.json().get("message", f"{name}님 연락처를 삭제했습니다.")
        except Exception as e:
            return f"오류: {e}"

    def get_call_history(self, name: str = "", limit: int = 10) -> str:
        """통화 기록을 조회합니다. 이름을 지정하면 해당 연락처만 필터링합니다.

        사용 예시:
            "최근 통화 기록 보여줘" → name="", limit=10
            "김철수 통화 기록 보여줘" → name="김철수"
            "오늘 통화 내역 확인해줘" → name="", limit=20
        """
        try:
            r = requests.get(f"{TOOL_SERVER}/tools/call-history", timeout=10)
            data = r.json()
            records = data.get("records", [])

            if name:
                records = [rec for rec in records if name in rec.get("name", "")]

            records = records[:limit]

            if not records:
                if name:
                    return f"{name}님의 통화 기록이 없습니다."
                return "통화 기록이 없습니다."

            result = f"통화 기록 ({len(records)}건):\\n\\n"
            for rec in records:
                r_name = rec.get("name", "알 수 없음")
                r_mission = rec.get("mission", "")
                r_time = rec.get("timestamp", "")
                r_summary = rec.get("summary", "요약 없음")
                r_status = rec.get("status", "")
                status_icon = "✅" if r_status == "completed" else "📞"

                result += f"{status_icon} {r_name} — {r_mission} ({r_time})\\n"
                result += f"   요약: {r_summary}\\n\\n"

            return result
        except Exception as e:
            return f"통화 기록 조회 오류: {e}"
'''

rag_tool_code = '''\
"""
title: RAG 문서 검색
author: RAG System
description: 업로드된 PDF 문서에서 정보 검색
version: 1.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def search_documents(self, query: str, top_k: int = 3) -> str:
        """업로드된 PDF 문서에서 관련 정보를 검색합니다."""
        try:
            r = requests.post(
                f"{TOOL_SERVER}/rag/search",
                json={"query": query, "top_k": top_k},
                timeout=10
            )
            data = r.json()
            results = data.get("results", [])
            
            if not results:
                return "검색 결과가 없습니다."
            
            response = f"'{query}'에 대한 검색 결과 ({len(results)}건):\\n\\n"
            for i, result in enumerate(results, 1):
                text = result.get("text", "")
                source = result.get("source", "알 수 없음")
                score = result.get("score", 0)
                response += f"[{i}] 출처: {source} (관련도: {score:.2f})\\n{text}\\n\\n"
            
            return response
        except Exception as e:
            return f"검색 오류: {e}"
'''

sms_tool_code = '''\
"""
title: SMS 보내기
author: SMS Tool
description: 지정한 번호로 SMS를 보냅니다 (답장 자동 전달)
version: 1.1.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def send_sms(self, phone_number: str, message: str) -> str:
        """SMS를 보냅니다. 상대방이 답장하면 자동으로 관리자에게 전달됩니다."""
        try:
            number = phone_number.strip().replace("-", "").replace(" ", "")
            if number.startswith("010") or number.startswith("011"):
                number = "+82" + number[1:]
            elif number.startswith("01"):
                number = "+82" + number[1:]
            
            r = requests.post(
                f"{TOOL_SERVER}/tools/send-sms",
                json={"to": number, "message": message},
                timeout=10
            )
            
            if r.status_code == 200:
                data = r.json()
                return data.get("message", "SMS를 보냈습니다!")
            else:
                return f"SMS 전송 실패: {r.text}"
        except Exception as e:
            return f"오류: {e}"
'''

def register_tool(tool_id, tool_name, tool_desc, tool_code):
    payload = {
        "id": tool_id,
        "name": tool_name,
        "description": tool_desc,
        "content": tool_code,
        "meta": {"description": tool_desc, "manifest": {}}
    }
    
    req = urllib.request.Request(
        "http://localhost:3000/api/v1/tools/create",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"},
        method="POST"
    )
    
    try:
        with urllib.request.urlopen(req) as resp:
            d = json.loads(resp.read())
            return f"SUCCESS: {d.get('name', tool_name)}"
    except urllib.error.HTTPError as e:
        error_msg = e.read().decode()[:100]
        if "already registered" in error_msg.lower():
            return f"SKIP: {tool_name} (이미 등록됨)"
        return f"FAIL: {tool_name} - {error_msg}"
    except Exception as e:
        return f"ERROR: {tool_name} - {str(e)}"

print("1️⃣  전화 어시스턴트 Tool 등록 중...")
result1 = register_tool("phone_assistant_v2", "전화 어시스턴트", "전화 걸기, 안부전화(사용자 메시지 직접 전달 가능), 연락처 저장/삭제/조회, 통화 기록 조회", phone_tool_code)
print(result1)

print("2️⃣  RAG 문서 검색 Tool 등록 중...")
result2 = register_tool("rag_document_search", "RAG 문서 검색", "업로드된 PDF 문서에서 정보 검색", rag_tool_code)
print(result2)

print("3️⃣  SMS 보내기 Tool 등록 중...")
result3 = register_tool("sms_sender", "SMS 보내기", "지정한 번호로 SMS를 보냅니다 (답장 자동 전달)", sms_tool_code)
print(result3)

# ── 예약 스케줄 Tool ──
schedule_tool_code = '''\
"""
title: 예약 스케줄러
author: AI Phone Bot
description: 전화/SMS 예약 등록, 조회, 삭제, 활성화/비활성화
version: 1.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def add_schedule(self, contact_name: str, action: str = "call", schedule_time: str = "", repeat: str = "", mission: str = "안부 확인", message: str = "") -> str:
        """전화 또는 SMS 예약을 등록합니다.

        Args:
            contact_name: 연락처 이름 (예: 김철수)
            action: "call" (전화) 또는 "sms" (문자)
            schedule_time: 1회 예약은 "2025-03-25 15:00", 반복은 "15:00" (시간만)
            repeat: 빈값(1회), "daily"(매일), "weekly:월"(매주 월요일), "monthly:15"(매월 15일)
            mission: AI가 수행할 임무 (예: 안부 확인, 회의 참석 확인)
            message: 전달할 메시지

        사용 예시:
            "내일 오후 3시에 김철수한테 전화해줘" → schedule_time="2025-03-26 15:00", repeat=""
            "매주 월요일 10시에 김철수한테 안부전화 해줘" → schedule_time="10:00", repeat="weekly:월"
            "매일 아침 9시에 김철수한테 문자 보내줘" → action="sms", schedule_time="09:00", repeat="daily"
        """
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/schedule/add",
                            json={"contact_name": contact_name, "action": action,
                                  "schedule_time": schedule_time, "repeat": repeat,
                                  "mission": mission, "message": message}, timeout=10)
            data = r.json()
            sid = data.get("sid", "")
            action_text = "📞 전화" if action == "call" else "📱 SMS"
            repeat_text = f" (반복: {repeat})" if repeat else " (1회)"
            result = f"예약 등록 완료! [{sid}] {contact_name}님에게 {action_text} — {schedule_time}{repeat_text}"
            if mission:
                result += f"\\n   📋 임무: {mission}"
            if message:
                result += f"\\n   💬 메시지: {message}"
            return result
        except Exception as e:
            return f"예약 오류: {e}"

    def list_schedules(self) -> str:
        """등록된 예약 목록을 조회합니다."""
        try:
            r = requests.get(f"{TOOL_SERVER}/tools/schedules", timeout=10)
            data = r.json()
            schedules = data.get("schedules", {})
            if not schedules:
                return "등록된 예약이 없습니다."
            result = f"예약 목록 ({len(schedules)}건):\\n\\n"
            for sid, s in schedules.items():
                status = "✅" if s.get("enabled") else "⬜"
                action_text = "📞 전화" if s.get("action") == "call" else "📱 SMS"
                repeat_text = f" (반복: {s.get('repeat')})" if s.get("repeat") else " (1회)"
                result += f"{status} [{sid}] {s.get('contact_name')} — {action_text} {s.get('schedule_time')}{repeat_text}\\n"
                mission = s.get("mission", "")
                message = s.get("message", "")
                if mission:
                    result += f"   📋 임무: {mission}\\n"
                if message:
                    result += f"   💬 메시지: {message}\\n"
                created = s.get("created", "")
                if created:
                    result += f"   🕐 등록: {created}\\n"
                if s.get("last_run"):
                    result += f"   ▶️ 마지막 실행: {s.get('last_run')} (총 {s.get('run_count', 0)}회)\\n"
                result += "\\n"
            return result
        except Exception as e:
            return f"조회 오류: {e}"

    def remove_schedule(self, sid: str) -> str:
        """예약을 삭제합니다. sid는 예약 ID입니다."""
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/schedule/remove",
                            json={"sid": sid}, timeout=10)
            if r.status_code == 200:
                return f"예약 [{sid}] 삭제 완료!"
            return f"삭제 실패: {r.text}"
        except Exception as e:
            return f"삭제 오류: {e}"

    def toggle_schedule(self, sid: str) -> str:
        """예약을 활성화/비활성화합니다."""
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/schedule/toggle",
                            json={"sid": sid}, timeout=10)
            data = r.json()
            enabled = data.get("enabled", False)
            return f"예약 [{sid}] {'✅ 활성화' if enabled else '⬜ 비활성화'} 완료!"
        except Exception as e:
            return f"토글 오류: {e}"
'''

print("4️⃣  예약 스케줄러 Tool 등록 중...")
result4 = register_tool("schedule_manager", "예약 스케줄러", "전화/SMS 예약 등록, 조회, 삭제, 활성화/비활성화", schedule_tool_code)
print(result4)
PYEOF

  TOOL_RESULT=$(python3 /tmp/register_tools.py "$OW_JWT" 2>&1)
  
  if echo "$TOOL_RESULT" | grep -q "SUCCESS\|SKIP"; then
    echo "   ✅ OpenWebUI Tool 자동 등록 완료!"
    echo ""
    echo "$TOOL_RESULT" | while IFS= read -r line; do
      echo "      $line"
    done
  fi
fi

############################################
# Twilio SMS Webhook 설정 안내
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "📱 Twilio SMS Webhook 설정 (수동)"
echo "└────────────────────────────────────────────┘"

if [ "$USE_TWILIO" = true ]; then
  echo ""
  echo "   ⚠️  다음 단계를 수동으로 완료해주세요:"
  echo ""
  echo "   1. Twilio Console 접속: https://console.twilio.com/"
  echo "   2. Phone Numbers → Manage → Active numbers"
  echo "   3. 전화번호 클릭 (${TWILIO_PHONE_NUMBER})"
  echo "   4. Messaging Configuration 섹션:"
  echo "      - A MESSAGE COMES IN:"
  echo "        Webhook: ${SERVER_DOMAIN}/sms-incoming"
  echo "        HTTP POST"
  echo "   5. Save 클릭"
  echo ""
  echo "   ✅ 설정 완료 후 SMS 답장이 자동으로 관리자에게 전달됩니다!"
  echo ""
fi

############################################
# 완료 메시지
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
echo ""
echo "🔐 관리자 계정:"
echo "   이메일: ${OW_EMAIL}"
echo "   비밀번호: ${OW_PASSWORD}"
echo ""
echo "✅ 자동 등록된 Tool:"
echo "   1️⃣  전화 어시스턴트 - 전화 걸기, 연락처 관리"
echo "   2️⃣  RAG 문서 검색 - PDF 문서에서 정보 검색"
echo "   3️⃣  SMS 보내기 - 지정한 번호로 문자 전송 (답장 자동 전달)"
echo ""
echo "📱 사용 예시:"
echo "   전화: '김철수한테 안부전화 해줘. 어떻게 지내세요?'"
echo "   SMS: '김철수한테 문자 보내줘: 내일 회의 있어요'"
echo "   → 김철수님 답장 → 자동으로 관리자에게 전달 ✅"
echo "   RAG: 'PDF 문서에서 환불 정책 찾아줘'"
echo ""
echo "⏰ 보고 타이밍:"
echo "   ✅ 통화 성공 시: 📞 전화 약 18~20초 후 → 📱 SMS 약 21~23초 후"
echo "   ❌ 통화 실패 시: 📱 SMS 약 21~23초 후"
echo "   ✅ SMS 성공 시: 보고 없음"
echo "   ❌ SMS 실패 시: 📱 SMS 10초 후 관리자에게 보고"
echo "   📩 SMS 답장: 자동으로 관리자에게 5초 후 전달"
echo ""
echo "🔧 Twilio SMS Webhook 설정:"
echo "   ${SERVER_DOMAIN}/sms-incoming"
echo "   → Twilio Console에서 수동 설정 필요"
echo ""

echo "🔐 보안 강화 (16항목):"
echo "   기존 13항목 + 신규 3항목:"
echo "   🆕 Docker Secrets: 민감정보 /run/secrets/ 분리 저장"
echo "   🆕 JSON 감사 로그: /var/log/nginx/audit.json.log"
echo "   🆕 Cloudflare Tunnel: HTTPS 외부 접속 (설정 시)"
echo ""
echo "🌐 다국어 지원 (v4.0):"
echo "   자동 감지: 전화번호 국가코드 기반"
echo "   +82 → 한국어 | +1/+44 → English | +81 → 日本語 | +86 → 中文"
echo "   설정 변경: ~/openapi-rag/twilio-bot/ai_config.py"
echo "   기본 언어: DEFAULT_LANG (현재: ko)"
echo "   적용 방법: cd ~/openapi-rag && docker compose restart twilio-bot"
echo ""
echo "📋 감사 로그 조회:"
echo "   최근 20건:     cd ~/openapi-rag && ./view-audit-log.sh"
echo "   실시간 모니터: cd ~/openapi-rag && ./view-audit-log.sh tail"
echo "   에러만:        cd ~/openapi-rag && ./view-audit-log.sh errors"
echo ""
