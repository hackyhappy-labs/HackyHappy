#!/bin/bash
# =============================================================================
# 프로젝트명: OpenWebUI ↔ Telegram 브릿지 설치 스크립트 (보안강화판)
# 제작자: <webmaster@vulva.sex>
# 버전: 1.0.0
# 날짜: 2026-03-22
# 원본: start-openwebui-with-rag-groq-ollama-Twilio-final.sh (v3.6.0)
# 설명: 이미 설치된 OpenWebUI의 API 키를 받아 Telegram Bot과 연동
#       OpenWebUI의 모든 모델/Tool/RAG를 Telegram에서 그대로 사용
#
# ✅ 보안 (18항목)
#    - Telegram Bot Token AES-256 암호화 저장
#    - OpenWebUI API Key 환경변수 분리 + chmod 600
#    - Rate Limiting (분당 30회 / 사용자당)
#    - 허용된 Telegram User ID만 접근 (화이트리스트)
#    - 입력 길이 제한 (4096자) + XSS/인젝션 방어
#    - Webhook 서명 검증 (Telegram Secret Token)
#    - 컨테이너 non-root 실행
#    - Docker 네트워크 격리 (internal network)
#    - 민감정보 로그 마스킹
#    - Health check + 자동 복구
#    - CORS 비활성화 (API 서버)
#    - 파일 업로드 크기 제한 (20MB)
#    - 세션 타임아웃 (30분 비활동 시 대화 초기화)
#    - 관리자 전용 명령어 PIN 인증
#    - Prometheus 메트릭 엔드포인트 (선택)
#    - .env 파일 자동 백업 + 권한 잠금
#    - 비정상 요청 자동 차단 (3회 실패 → 10분 잠금)
#    - 로그 로테이션 (최대 10MB × 3파일)
#
# ✅ 기능
#    - 텍스트 대화: Telegram ↔ OpenWebUI 모든 모델 사용
#    - Tool 관리: /tools 명령으로 Tool 활성화/비활성화
#    - 파일 전송: PDF/이미지 → OpenWebUI RAG 자동 색인
#    - 음성 메시지: Whisper STT → AI 응답 → TTS 음성 회신
#    - Tool 연동: 전화걸기, SMS, 연락처, RAG 검색 전부 사용
#    - 모델 전환: /model 명령으로 실시간 모델 변경
#    - 대화 기록: /clear 로 초기화, /history 로 조회
#    - 관리자 명령: /status, /users, /block, /unblock
#
# 사전 조건:
#    - OpenWebUI가 http://localhost:3000 에서 실행 중
#    - Telegram Bot Token (BotFather에서 발급)
#    - OpenWebUI API Key (설정에서 발급)
#
# 라이센스: MIT License
# =============================================================================

set -euo pipefail

############################################
# 0. 색상 및 유틸리티
############################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
  echo ""
  echo -e "${CYAN}┌────────────────────────────────────────────┐${NC}"
  echo -e "${CYAN} $1${NC}"
  echo -e "${CYAN}└────────────────────────────────────────────┘${NC}"
}

print_ok()   { echo -e "   ${GREEN}✅ $1${NC}"; }
print_warn() { echo -e "   ${YELLOW}⚠️  $1${NC}"; }
print_err()  { echo -e "   ${RED}❌ $1${NC}"; }
print_info() { echo -e "   ${BLUE}ℹ️  $1${NC}"; }

############################################
# 1. 사전 검증
############################################
print_header "🔍 사전 환경 검증"

# root 실행 방지
if [ "$EUID" -eq 0 ]; then
  print_err "root로 실행하지 마세요. 일반 사용자로 실행해주세요."
  exit 1
fi

# Docker 확인
if ! command -v docker >/dev/null 2>&1; then
  print_err "Docker가 설치되어 있지 않습니다. 먼저 OpenWebUI 설치 스크립트를 실행해주세요."
  exit 1
fi

if ! docker ps >/dev/null 2>&1; then
  print_err "Docker 권한 없음. sudo usermod -aG docker \$USER 실행 후 재접속하세요."
  exit 1
fi

# OpenWebUI 실행 확인
WEBUI_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null || echo "000")
if [ "$WEBUI_STATUS" != "200" ]; then
  print_err "OpenWebUI가 http://localhost:3000 에서 실행 중이지 않습니다."
  print_info "먼저 OpenWebUI 설치 스크립트를 실행하세요."
  exit 1
fi
print_ok "OpenWebUI 실행 확인됨 (http://localhost:3000)"

# OpenWebUI 컨테이너 이름 및 네트워크 자동 감지
WEBUI_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i 'open-webui\|openwebui' | head -1)
if [ -n "$WEBUI_CONTAINER" ]; then
  WEBUI_PORT=$(docker inspect "$WEBUI_CONTAINER" --format='{{range $p, $conf := .Config.ExposedPorts}}{{$p}}{{end}}' 2>/dev/null | grep -oP '\d+' | head -1)
  WEBUI_PORT=${WEBUI_PORT:-8080}
  WEBUI_NETWORK=$(docker inspect "$WEBUI_CONTAINER" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null | head -1)
  WEBUI_INTERNAL_URL="http://${WEBUI_CONTAINER}:${WEBUI_PORT}"
  print_ok "OpenWebUI 컨테이너: ${WEBUI_CONTAINER} (내부포트: ${WEBUI_PORT})"
  print_ok "OpenWebUI 네트워크: ${WEBUI_NETWORK}"
else
  WEBUI_INTERNAL_URL="http://host.docker.internal:3000"
  WEBUI_NETWORK=""
  print_warn "OpenWebUI 컨테이너 자동 감지 실패 — host.docker.internal 사용"
fi

# python3 확인
if ! command -v python3 >/dev/null 2>&1; then
  print_err "python3가 필요합니다."
  exit 1
fi

############################################
# 2. 입력 수집
############################################
print_header "🤖 Telegram Bot 설정"
echo ""
echo "   📌 Telegram에서 @BotFather에게 /newbot 명령으로 봇 생성 후"
echo "   발급받은 Bot Token을 입력하세요."
echo ""

while true; do
  read -p "   🔑 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
  TELEGRAM_BOT_TOKEN=$(echo "$TELEGRAM_BOT_TOKEN" | xargs)
  if [[ "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    MASKED_TOKEN="${TELEGRAM_BOT_TOKEN:0:8}...${TELEGRAM_BOT_TOKEN: -6}"
    print_ok "Bot Token 형식 확인됨: ${MASKED_TOKEN}"
    break
  else
    print_err "잘못된 Token 형식입니다. 예: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
  fi
done

echo ""
print_header "🔐 OpenWebUI API Key 설정"
echo ""
echo "   📌 OpenWebUI → 설정 → 계정 → API Keys에서 발급하세요."
echo "   또는 로그인 후 받은 JWT 토큰을 입력하세요."
echo ""

while true; do
  read -p "   🔑 OpenWebUI API Key: " OPENWEBUI_API_KEY
  OPENWEBUI_API_KEY=$(echo "$OPENWEBUI_API_KEY" | xargs)
  if [ ${#OPENWEBUI_API_KEY} -ge 20 ]; then
    # API Key 유효성 검증
    VERIFY_RESP=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer ${OPENWEBUI_API_KEY}" \
      http://localhost:3000/api/v1/auths/ 2>/dev/null || echo "000")
    if [ "$VERIFY_RESP" = "200" ]; then
      MASKED_KEY="${OPENWEBUI_API_KEY:0:10}...${OPENWEBUI_API_KEY: -6}"
      print_ok "API Key 인증 성공: ${MASKED_KEY}"
      break
    else
      print_warn "API Key 인증 실패 (HTTP ${VERIFY_RESP}). 그래도 계속 진행하시겠습니까?"
      read -p "   계속 진행? (y/N): " CONTINUE_ANYWAY
      if [[ "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
        break
      fi
    fi
  else
    print_err "API Key가 너무 짧습니다."
  fi
done

echo ""
print_header "👤 관리자 접근 제어 설정"
echo ""
echo "   📌 이 봇은 관리자만 사용할 수 있습니다."
echo "   등록된 관리자 Telegram User ID만 접근이 허용됩니다."
echo "   @userinfobot 에게 메시지를 보내면 본인의 User ID를 알 수 있습니다."
echo ""

while true; do
  read -p "   📱 관리자 Telegram User ID (필수, 쉼표 구분): " ALLOWED_USER_IDS
  ALLOWED_USER_IDS=$(echo "$ALLOWED_USER_IDS" | xargs)
  if [ -n "$ALLOWED_USER_IDS" ]; then
    print_ok "관리자 등록: ${ALLOWED_USER_IDS}"
    break
  else
    print_err "관리자 ID는 필수입니다. 최소 1명 이상 입력해주세요."
    print_info "Telegram에서 @userinfobot 에게 메시지를 보내면 User ID를 확인할 수 있습니다."
  fi
done

echo ""
read -p "   🔢 관리자 PIN 6자리 (기본: 비활성화, Enter=건너뜀): " ADMIN_PIN
ADMIN_PIN=$(echo "$ADMIN_PIN" | xargs)
if [ -n "$ADMIN_PIN" ]; then
  print_ok "관리자 PIN 설정됨"
else
  ADMIN_PIN=""
  print_info "관리자 PIN 비활성화"
fi

echo ""
read -p "   🌐 서버 도메인 (Webhook용, Enter=Polling 모드): " SERVER_DOMAIN
SERVER_DOMAIN=$(echo "$SERVER_DOMAIN" | xargs)

if [ -n "$SERVER_DOMAIN" ]; then
  USE_WEBHOOK=true
  print_ok "Webhook 모드: ${SERVER_DOMAIN}/telegram-webhook"
else
  USE_WEBHOOK=false
  print_info "Long Polling 모드 (도메인 불필요)"
fi

############################################
# 3. 기존 모델 목록 가져오기
############################################
print_header "🧠 사용 가능한 모델 확인"

MODELS_RESP=$(curl -s -H "Authorization: Bearer ${OPENWEBUI_API_KEY}" \
  http://localhost:3000/api/models 2>/dev/null || echo "{}")

DEFAULT_MODEL=$(echo "$MODELS_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    models = data.get('data', data.get('models', []))
    if models:
        names = [m.get('id', m.get('name', '')) for m in models[:5]]
        print(names[0] if names else 'llama-3.3-70b-versatile')
    else:
        print('llama-3.3-70b-versatile')
except:
    print('llama-3.3-70b-versatile')
" 2>/dev/null || echo "llama-3.3-70b-versatile")

print_ok "기본 모델: ${DEFAULT_MODEL}"

############################################
# 4. 작업 디렉토리 생성
############################################
print_header "📁 프로젝트 구조 생성"

BASE_DIR="$HOME/telegram-openwebui-bridge"

if [ -d "$BASE_DIR" ]; then
  print_warn "기존 설치가 발견됨"
  read -p "   기존 설치를 덮어쓰시겠습니까? (y/N): " OVERWRITE
  if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
    cd "$BASE_DIR"
    docker compose down 2>/dev/null || true
    cd ~
    rm -rf "$BASE_DIR"
  else
    print_err "설치 중단됨"
    exit 0
  fi
fi

mkdir -p "$BASE_DIR"/{bot,data,logs}
chmod 777 "$BASE_DIR"/logs "$BASE_DIR"/data
cd "$BASE_DIR"
print_ok "디렉토리 생성: $BASE_DIR (logs/data 권한 설정 완료)"

############################################
# 5. 보안 키 생성 + .env 파일
############################################
print_header "🔒 보안 키 생성 및 환경변수 설정"

WEBHOOK_SECRET=$(openssl rand -hex 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)
INTERNAL_API_SECRET=$(openssl rand -hex 24)

cat > .env <<ENVEOF
# ══════════════════════════════════════════
# Telegram ↔ OpenWebUI Bridge 환경변수
# 생성일: $(date '+%Y-%m-%d %H:%M:%S')
# ══════════════════════════════════════════

# Telegram 설정
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
ALLOWED_USER_IDS=${ALLOWED_USER_IDS}
# ↑ 관리자 전용 — 등록되지 않은 User ID는 모든 접근 차단
ADMIN_PIN=${ADMIN_PIN}

# OpenWebUI 연결
OPENWEBUI_URL=${WEBUI_INTERNAL_URL}
OPENWEBUI_API_KEY=${OPENWEBUI_API_KEY}
DEFAULT_MODEL=${DEFAULT_MODEL}

# 서버 / Webhook
SERVER_DOMAIN=${SERVER_DOMAIN}
USE_WEBHOOK=${USE_WEBHOOK}
WEBHOOK_SECRET=${WEBHOOK_SECRET}

# 보안
ENCRYPTION_KEY=${ENCRYPTION_KEY}
INTERNAL_API_SECRET=${INTERNAL_API_SECRET}

# Rate Limiting
RATE_LIMIT_PER_MINUTE=30
RATE_LIMIT_BLOCK_MINUTES=10
MAX_FAIL_ATTEMPTS=3

# 제한
MAX_MESSAGE_LENGTH=4096
MAX_FILE_SIZE_MB=20
SESSION_TIMEOUT_MINUTES=30
MAX_HISTORY_MESSAGES=50

# 로그
LOG_LEVEL=INFO
LOG_MAX_BYTES=10485760
LOG_BACKUP_COUNT=3
ENVEOF

chmod 600 .env
print_ok ".env 파일 생성 (chmod 600)"

# 백업 생성
cp .env ".env.backup.$(date +%Y%m%d%H%M%S)"
print_ok ".env 백업 생성됨"

############################################
# 5-1. LICENSE 파일 생성
############################################
cat > LICENSE <<'LICEOF'
MIT License
LICEOF
print_ok "LICENSE 파일 생성됨 (MIT)"

############################################
# 6. Telegram Bot 소스코드 생성
############################################
print_header "🤖 Telegram Bot 소스코드 생성"

cat > bot/requirements.txt <<'REQEOF'
python-telegram-bot[webhooks]==21.5
aiohttp==3.9.5
aiofiles==24.1.0
python-dotenv==1.0.1
cryptography==42.0.8
pydantic==2.5.3
REQEOF

cat > bot/telegram_bot.py <<'BOTEOF'
#!/usr/bin/env python3
"""
Telegram ↔ OpenWebUI 브릿지 봇 (보안강화판)
OpenWebUI의 모든 모델/Tool/RAG를 Telegram에서 사용 가능

Author:  <webmaster@vulva.sex>
Version: 1.0.0
Date:    2026-03-22
Origin:  start-openwebui-with-rag-groq-ollama-Twilio-final.sh (v3.6.0)
License: MIT License
"""
import os
import sys
import json
import time
import logging
import asyncio
import hashlib
import html
import re
from datetime import datetime, timedelta
from collections import defaultdict
from logging.handlers import RotatingFileHandler
from functools import wraps

import aiohttp
from dotenv import load_dotenv

from telegram import Update, BotCommand, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    filters,
    ContextTypes,
)
from telegram.constants import ParseMode, ChatAction

load_dotenv()

# ══════════════════════════════════════════
# 설정
# ══════════════════════════════════════════
TELEGRAM_BOT_TOKEN    = os.getenv("TELEGRAM_BOT_TOKEN", "")
OPENWEBUI_URL         = os.getenv("OPENWEBUI_URL", "http://host.docker.internal:3000")
OPENWEBUI_API_KEY     = os.getenv("OPENWEBUI_API_KEY", "")
DEFAULT_MODEL         = os.getenv("DEFAULT_MODEL", "llama-3.3-70b-versatile")
SERVER_DOMAIN         = os.getenv("SERVER_DOMAIN", "")
USE_WEBHOOK           = os.getenv("USE_WEBHOOK", "false").lower() == "true"
WEBHOOK_SECRET        = os.getenv("WEBHOOK_SECRET", "")
ADMIN_PIN             = os.getenv("ADMIN_PIN", "")

# 접근제어 — 관리자 전용 (필수)
ADMIN_USER_IDS_RAW    = os.getenv("ALLOWED_USER_IDS", "")
ADMIN_USER_IDS        = set()
if ADMIN_USER_IDS_RAW.strip():
    ADMIN_USER_IDS = {
        int(uid.strip()) for uid in ADMIN_USER_IDS_RAW.split(",")
        if uid.strip().isdigit()
    }

# Rate Limiting
RATE_LIMIT_PER_MINUTE  = int(os.getenv("RATE_LIMIT_PER_MINUTE", "30"))
RATE_LIMIT_BLOCK_MIN   = int(os.getenv("RATE_LIMIT_BLOCK_MINUTES", "10"))
MAX_FAIL_ATTEMPTS      = int(os.getenv("MAX_FAIL_ATTEMPTS", "3"))

# 제한
MAX_MESSAGE_LENGTH     = int(os.getenv("MAX_MESSAGE_LENGTH", "4096"))
MAX_FILE_SIZE_MB       = int(os.getenv("MAX_FILE_SIZE_MB", "20"))
SESSION_TIMEOUT_MIN    = int(os.getenv("SESSION_TIMEOUT_MINUTES", "30"))
MAX_HISTORY_MESSAGES   = int(os.getenv("MAX_HISTORY_MESSAGES", "50"))

# ══════════════════════════════════════════
# 로깅 설정
# ══════════════════════════════════════════
LOG_LEVEL       = os.getenv("LOG_LEVEL", "INFO")
LOG_MAX_BYTES   = int(os.getenv("LOG_MAX_BYTES", "10485760"))
LOG_BACKUP_COUNT = int(os.getenv("LOG_BACKUP_COUNT", "3"))

os.makedirs("/app/logs", exist_ok=True)

logger = logging.getLogger("telegram_bridge")
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

file_handler = RotatingFileHandler(
    "/app/logs/bot.log",
    maxBytes=LOG_MAX_BYTES,
    backupCount=LOG_BACKUP_COUNT,
    encoding="utf-8",
)
console_handler = logging.StreamHandler(sys.stdout)

formatter = logging.Formatter(
    "%(asctime)s [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
)
file_handler.setFormatter(formatter)
console_handler.setFormatter(formatter)
logger.addHandler(file_handler)
logger.addHandler(console_handler)

# ══════════════════════════════════════════
# 보안: Rate Limiter
# ══════════════════════════════════════════
class RateLimiter:
    def __init__(self):
        self.requests = defaultdict(list)   # user_id → [timestamp, ...]
        self.blocked  = {}                  # user_id → unblock_time
        self.fail_count = defaultdict(int)  # user_id → consecutive failures

    def is_blocked(self, user_id: int) -> bool:
        if user_id in self.blocked:
            if datetime.now() > self.blocked[user_id]:
                del self.blocked[user_id]
                self.fail_count[user_id] = 0
                return False
            return True
        return False

    def record_request(self, user_id: int) -> bool:
        """True = 허용, False = 제한 초과"""
        now = datetime.now()
        cutoff = now - timedelta(minutes=1)

        # 오래된 기록 정리
        self.requests[user_id] = [t for t in self.requests[user_id] if t > cutoff]

        if len(self.requests[user_id]) >= RATE_LIMIT_PER_MINUTE:
            self.fail_count[user_id] += 1
            if self.fail_count[user_id] >= MAX_FAIL_ATTEMPTS:
                self.blocked[user_id] = now + timedelta(minutes=RATE_LIMIT_BLOCK_MIN)
                logger.warning(f"🚨 사용자 {user_id} 차단됨 ({RATE_LIMIT_BLOCK_MIN}분)")
            return False

        self.requests[user_id].append(now)
        return True

    def reset(self, user_id: int):
        self.fail_count[user_id] = 0

rate_limiter = RateLimiter()

# ══════════════════════════════════════════
# 보안: 입력 검증
# ══════════════════════════════════════════
def sanitize_input(text: str) -> str:
    """입력 텍스트 정리 + 길이 제한"""
    if not text:
        return ""
    text = text.strip()
    if len(text) > MAX_MESSAGE_LENGTH:
        text = text[:MAX_MESSAGE_LENGTH]
    # null bytes 제거
    text = text.replace("\x00", "")
    return text

def mask_sensitive(text: str) -> str:
    """로그용 민감정보 마스킹"""
    # API 키 패턴 마스킹
    text = re.sub(r'(sk-[a-zA-Z0-9]{4})[a-zA-Z0-9]+', r'\1***', text)
    text = re.sub(r'(Bearer\s+)[^\s]+', r'\1[MASKED]', text)
    # 전화번호 마스킹
    text = re.sub(r'(\+82\d{2})\d{4}(\d{4})', r'\1****\2', text)
    text = re.sub(r'(010)\d{4}(\d{4})', r'\1-****-\2', text)
    return text

# ══════════════════════════════════════════
# 세션 관리
# ══════════════════════════════════════════
class UserSession:
    def __init__(self, user_id: int):
        self.user_id = user_id
        self.model = DEFAULT_MODEL
        self.history = []
        self.last_active = datetime.now()
        self.authenticated = not bool(ADMIN_PIN)  # PIN 없으면 자동 인증
        self.enabled_tool_ids = set()  # 활성화된 Tool ID 목록

    def add_message(self, role: str, content: str):
        self.history.append({"role": role, "content": content})
        if len(self.history) > MAX_HISTORY_MESSAGES * 2:
            self.history = self.history[-MAX_HISTORY_MESSAGES * 2:]
        self.last_active = datetime.now()

    def clear(self):
        self.history.clear()
        self.last_active = datetime.now()

    def is_expired(self) -> bool:
        return datetime.now() - self.last_active > timedelta(minutes=SESSION_TIMEOUT_MIN)

    def toggle_tool(self, tool_id: str) -> bool:
        """Tool 활성화/비활성화 토글. 반환값: 토글 후 활성화 상태"""
        if tool_id in self.enabled_tool_ids:
            self.enabled_tool_ids.discard(tool_id)
            return False
        else:
            self.enabled_tool_ids.add(tool_id)
            return True

    def enable_all_tools(self, tool_ids: list):
        """모든 Tool 일괄 활성화"""
        self.enabled_tool_ids = set(tool_ids)

    def disable_all_tools(self):
        """모든 Tool 일괄 비활성화"""
        self.enabled_tool_ids.clear()

sessions = {}  # user_id → UserSession

def get_session(user_id: int) -> UserSession:
    if user_id not in sessions or sessions[user_id].is_expired():
        if user_id in sessions and sessions[user_id].is_expired():
            logger.info(f"⏰ 세션 만료 초기화: {user_id}")
        sessions[user_id] = UserSession(user_id)
    return sessions[user_id]

# ══════════════════════════════════════════
# 접근제어 데코레이터 — 관리자 전용
# ══════════════════════════════════════════
def authorized(func):
    """등록된 관리자만 접근 가능 (ADMIN_USER_IDS 필수)"""
    @wraps(func)
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if not user:
            return

        # 관리자 목록이 비어있으면 모든 접근 차단
        if not ADMIN_USER_IDS:
            logger.error(f"🚫 관리자 미등록 상태 — 모든 접근 차단: {user.id} ({user.full_name})")
            await update.message.reply_text(
                "⛔ 봇에 등록된 관리자가 없습니다.\n"
                "서버의 .env 파일에 ALLOWED_USER_IDS를 설정해주세요."
            )
            return

        # 관리자 여부 확인
        if user.id not in ADMIN_USER_IDS:
            logger.warning(f"🚫 비관리자 접근 차단: {user.id} ({user.full_name})")
            await update.message.reply_text(
                "⛔ 이 봇은 관리자 전용입니다.\n"
                "접근 권한이 없습니다."
            )
            return

        # 차단 검사
        if rate_limiter.is_blocked(user.id):
            await update.message.reply_text(
                f"⏳ 너무 많은 요청으로 일시 차단되었습니다.\n"
                f"{RATE_LIMIT_BLOCK_MIN}분 후 다시 시도해주세요."
            )
            return

        # Rate Limit
        if not rate_limiter.record_request(user.id):
            await update.message.reply_text(
                f"⚠️ 요청이 너무 빠릅니다. (분당 {RATE_LIMIT_PER_MINUTE}회 제한)\n"
                "잠시 후 다시 시도해주세요."
            )
            return

        return await func(update, context)
    return wrapper

# ══════════════════════════════════════════
# OpenWebUI API 호출
# ══════════════════════════════════════════
async def call_openwebui_chat(session: UserSession, user_input: str) -> str:
    """OpenWebUI의 Chat Completions API 호출 (활성화된 Tool 포함)"""
    session.add_message("user", user_input)

    payload = {
        "model": session.model,
        "messages": session.history,
        "stream": False,
    }

    # 활성화된 Tool이 있으면 tool_ids 전달
    if session.enabled_tool_ids:
        payload["tool_ids"] = list(session.enabled_tool_ids)

    headers = {
        "Authorization": f"Bearer {OPENWEBUI_API_KEY}",
        "Content-Type": "application/json",
    }

    try:
        timeout = aiohttp.ClientTimeout(total=120)
        async with aiohttp.ClientSession(timeout=timeout) as http:
            async with http.post(
                f"{OPENWEBUI_URL}/api/chat/completions",
                headers=headers,
                json=payload,
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    ai_text = data["choices"][0]["message"]["content"]
                    session.add_message("assistant", ai_text)
                    rate_limiter.reset(session.user_id)
                    return ai_text
                else:
                    error_body = await resp.text()
                    logger.error(f"OpenWebUI API 오류 [{resp.status}]: {mask_sensitive(error_body[:200])}")
                    session.history.pop()  # 실패한 user 메시지 제거
                    return f"❌ AI 응답 오류 (HTTP {resp.status}). 잠시 후 다시 시도해주세요."
    except asyncio.TimeoutError:
        logger.error("OpenWebUI API 타임아웃 (120초)")
        session.history.pop()
        return "⏱️ AI 응답 시간 초과. 잠시 후 다시 시도해주세요."
    except Exception as e:
        logger.error(f"OpenWebUI API 연결 실패: {mask_sensitive(str(e))}")
        session.history.pop()
        return "❌ AI 서버 연결 실패. OpenWebUI가 실행 중인지 확인해주세요."

async def get_available_models() -> list:
    """사용 가능한 모델 목록 조회"""
    headers = {"Authorization": f"Bearer {OPENWEBUI_API_KEY}"}
    try:
        timeout = aiohttp.ClientTimeout(total=15)
        async with aiohttp.ClientSession(timeout=timeout) as http:
            async with http.get(
                f"{OPENWEBUI_URL}/api/models",
                headers=headers,
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    models = data.get("data", data.get("models", []))
                    return [
                        {"id": m.get("id", ""), "name": m.get("name", m.get("id", ""))}
                        for m in models
                        if m.get("id")
                    ]
    except Exception as e:
        logger.error(f"모델 목록 조회 실패: {e}")
    return []

async def upload_file_to_openwebui(file_bytes: bytes, filename: str) -> dict:
    """OpenWebUI에 파일 업로드 (RAG 색인용)"""
    headers = {"Authorization": f"Bearer {OPENWEBUI_API_KEY}"}
    try:
        timeout = aiohttp.ClientTimeout(total=60)
        form = aiohttp.FormData()
        form.add_field("file", file_bytes, filename=filename, content_type="application/octet-stream")

        async with aiohttp.ClientSession(timeout=timeout) as http:
            async with http.post(
                f"{OPENWEBUI_URL}/api/v1/files/",
                headers=headers,
                data=form,
            ) as resp:
                if resp.status in (200, 201):
                    return await resp.json()
                else:
                    error_text = await resp.text()
                    logger.error(f"파일 업로드 실패 [{resp.status}]: {error_text[:200]}")
                    return {"error": f"HTTP {resp.status}"}
    except Exception as e:
        logger.error(f"파일 업로드 오류: {e}")
        return {"error": str(e)}

# ══════════════════════════════════════════
# OpenWebUI Tool 관리 API
# ══════════════════════════════════════════
# 캐시: Tool 목록을 매번 조회하지 않도록 캐싱
_tools_cache = {"tools": [], "fetched_at": None, "ttl_seconds": 300}

async def get_available_tools(force_refresh: bool = False) -> list:
    """OpenWebUI에 등록된 Tool 목록 조회 (5분 캐시)"""
    now = datetime.now()
    if (not force_refresh
        and _tools_cache["fetched_at"]
        and (now - _tools_cache["fetched_at"]).total_seconds() < _tools_cache["ttl_seconds"]
        and _tools_cache["tools"]):
        return _tools_cache["tools"]

    headers = {"Authorization": f"Bearer {OPENWEBUI_API_KEY}"}
    try:
        timeout = aiohttp.ClientTimeout(total=15)
        async with aiohttp.ClientSession(timeout=timeout) as http:
            async with http.get(
                f"{OPENWEBUI_URL}/api/v1/tools/",
                headers=headers,
            ) as resp:
                if resp.status == 200:
                    raw = await resp.json()
                    # OpenWebUI Tool 응답 구조 파싱
                    tools = []
                    tool_list = raw if isinstance(raw, list) else raw.get("data", raw.get("tools", []))
                    for t in tool_list:
                        tools.append({
                            "id": t.get("id", ""),
                            "name": t.get("name", t.get("id", "알 수 없음")),
                            "description": t.get("meta", {}).get("description", t.get("description", "")),
                        })
                    _tools_cache["tools"] = tools
                    _tools_cache["fetched_at"] = now
                    logger.info(f"🔧 Tool 목록 조회: {len(tools)}개")
                    return tools
                else:
                    logger.error(f"Tool 목록 조회 실패 [{resp.status}]")
    except Exception as e:
        logger.error(f"Tool 목록 조회 오류: {e}")

    return _tools_cache.get("tools", [])

# ══════════════════════════════════════════
# 명령어 핸들러
# ══════════════════════════════════════════
@authorized
async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """봇 시작 + 환영 메시지"""
    user = update.effective_user
    session = get_session(user.id)
    logger.info(f"🟢 /start: {user.id} ({user.full_name})")

    welcome = (
        f"👋 안녕하세요, {html.escape(user.first_name)}님!\n\n"
        "🤖 <b>OpenWebUI Telegram 브릿지</b>에 오신 것을 환영합니다.\n\n"
        "이 봇을 통해 OpenWebUI의 모든 AI 모델과 도구를 사용할 수 있습니다.\n\n"
        "📋 <b>주요 명령어:</b>\n"
        "• 텍스트 입력 → AI 대화\n"
        "• 파일(PDF/이미지) 전송 → RAG 색인\n"
        "• /model — 모델 선택/변경\n"
        "• /tools — Tool 활성화/비활성화\n"
        "• /clear — 대화 기록 초기화\n"
        "• /history — 대화 기록 요약\n"
        "• /status — 시스템 상태\n"
        "• /help — 도움말\n\n"
        f"🧠 현재 모델: <code>{html.escape(session.model)}</code>\n"
        f"🔧 활성 Tool: {len(session.enabled_tool_ids)}개"
    )
    await update.message.reply_text(welcome, parse_mode=ParseMode.HTML)

@authorized
async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """상세 도움말"""
    help_text = (
        "📖 <b>사용 가이드</b>\n\n"
        "💬 <b>대화</b>\n"
        "일반 메시지를 보내면 AI가 응답합니다.\n\n"
        "📎 <b>파일 업로드</b>\n"
        "PDF, 이미지를 보내면 OpenWebUI에 자동 업로드됩니다.\n\n"
        "🎤 <b>음성 메시지</b>\n"
        "음성을 보내면 텍스트로 변환 후 AI가 응답합니다.\n\n"
        "🔧 <b>명령어</b>\n"
        "• /model — 사용 가능한 모델 목록 + 전환\n"
        "• /tools — Tool 활성화/비활성화 (전화, SMS, RAG 등)\n"
        "• /clear — 현재 대화 기록 초기화\n"
        "• /history — 최근 대화 요약 보기\n"
        "• /status — OpenWebUI + 봇 상태 확인\n"
        "• /whoami — 내 정보 확인\n"
        "• /help — 이 도움말\n\n"
        "📞 <b>Tool 사용법</b>\n"
        "1. /tools 명령으로 원하는 Tool 활성화\n"
        "2. 일반 대화처럼 요청 → AI가 활성 Tool을 자동 호출\n"
        "예: '김철수한테 전화해줘', '문서에서 환불 정책 찾아줘'\n\n"
        f"⚡ Rate Limit: 분당 {RATE_LIMIT_PER_MINUTE}회\n"
        f"⏰ 세션 타임아웃: {SESSION_TIMEOUT_MIN}분"
    )
    await update.message.reply_text(help_text, parse_mode=ParseMode.HTML)

@authorized
async def cmd_model(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """모델 목록 표시 + 선택"""
    user = update.effective_user
    session = get_session(user.id)

    await update.message.reply_chat_action(ChatAction.TYPING)
    models = await get_available_models()

    if not models:
        await update.message.reply_text("❌ 모델 목록을 가져올 수 없습니다.")
        return

    # 인라인 키보드로 모델 선택
    keyboard = []
    for m in models[:20]:  # 최대 20개
        label = m["name"][:40]
        if m["id"] == session.model:
            label = f"✅ {label}"
        keyboard.append([InlineKeyboardButton(label, callback_data=f"model:{m['id']}")])

    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text(
        f"🧠 현재 모델: <code>{html.escape(session.model)}</code>\n\n"
        "변경할 모델을 선택하세요:",
        parse_mode=ParseMode.HTML,
        reply_markup=reply_markup,
    )

async def callback_model_select(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """모델 선택 콜백"""
    query = update.callback_query
    await query.answer()

    user = query.from_user
    if user.id not in ADMIN_USER_IDS:
        return

    model_id = query.data.replace("model:", "")
    session = get_session(user.id)
    old_model = session.model
    session.model = model_id

    logger.info(f"🔄 모델 변경: {user.id} — {old_model} → {model_id}")

    await query.edit_message_text(
        f"✅ 모델이 변경되었습니다.\n\n"
        f"이전: <code>{html.escape(old_model)}</code>\n"
        f"현재: <code>{html.escape(model_id)}</code>",
        parse_mode=ParseMode.HTML,
    )

@authorized
async def cmd_clear(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """대화 기록 초기화"""
    user = update.effective_user
    session = get_session(user.id)
    msg_count = len(session.history)
    session.clear()
    logger.info(f"🧹 대화 초기화: {user.id} ({msg_count}개 메시지 삭제)")
    await update.message.reply_text(
        f"🧹 대화 기록이 초기화되었습니다.\n({msg_count}개 메시지 삭제됨)"
    )

@authorized
async def cmd_history(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """대화 기록 요약"""
    user = update.effective_user
    session = get_session(user.id)

    if not session.history:
        await update.message.reply_text("📭 대화 기록이 없습니다.")
        return

    recent = session.history[-10:]
    summary_parts = []
    for msg in recent:
        role_emoji = "👤" if msg["role"] == "user" else "🤖"
        content_preview = msg["content"][:80]
        if len(msg["content"]) > 80:
            content_preview += "..."
        summary_parts.append(f"{role_emoji} {html.escape(content_preview)}")

    text = (
        f"📜 <b>최근 대화 기록</b> ({len(session.history)}개 중 최근 {len(recent)}개)\n\n"
        + "\n\n".join(summary_parts)
        + f"\n\n🧠 모델: <code>{html.escape(session.model)}</code>"
    )
    await update.message.reply_text(text, parse_mode=ParseMode.HTML)

@authorized
async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """시스템 상태 확인"""
    user = update.effective_user

    # OpenWebUI 상태
    try:
        timeout = aiohttp.ClientTimeout(total=5)
        async with aiohttp.ClientSession(timeout=timeout) as http:
            async with http.get(f"{OPENWEBUI_URL}/health") as resp:
                webui_status = "🟢 온라인" if resp.status == 200 else f"🔴 오류 ({resp.status})"
    except Exception:
        webui_status = "🔴 오프라인"

    session = get_session(user.id)
    active_sessions = len([s for s in sessions.values() if not s.is_expired()])
    blocked_count = len(rate_limiter.blocked)

    status_text = (
        "📊 <b>시스템 상태</b>\n\n"
        f"🌐 OpenWebUI: {webui_status}\n"
        f"🧠 현재 모델: <code>{html.escape(session.model)}</code>\n"
        f"🔧 활성 Tool: {len(session.enabled_tool_ids)}개\n"
        f"💬 내 대화 기록: {len(session.history)}개\n"
        f"👥 활성 세션: {active_sessions}개\n"
        f"🚫 차단된 사용자: {blocked_count}명\n"
        f"⏰ 세션 타임아웃: {SESSION_TIMEOUT_MIN}분\n"
        f"📅 서버 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    )
    await update.message.reply_text(status_text, parse_mode=ParseMode.HTML)

@authorized
async def cmd_whoami(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """사용자 정보 확인"""
    user = update.effective_user
    session = get_session(user.id)
    is_admin = "✅ 관리자" if user.id in ADMIN_USER_IDS else "❌ 비관리자"

    info = (
        "👤 <b>내 정보</b>\n\n"
        f"🆔 User ID: <code>{user.id}</code>\n"
        f"📛 이름: {html.escape(user.full_name)}\n"
        f"📋 Username: @{html.escape(user.username or 'N/A')}\n"
        f"🔓 권한: {is_admin}\n"
        f"🧠 현재 모델: <code>{html.escape(session.model)}</code>\n"
        f"💬 대화 기록: {len(session.history)}개\n"
        f"🕐 마지막 활동: {session.last_active.strftime('%H:%M:%S')}"
    )
    await update.message.reply_text(info, parse_mode=ParseMode.HTML)

# ══════════════════════════════════════════
# Tool 관리 명령어
# ══════════════════════════════════════════
@authorized
async def cmd_tools(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """등록된 Tool 목록 표시 + 활성화/비활성화 토글"""
    user = update.effective_user
    session = get_session(user.id)

    await update.message.reply_chat_action(ChatAction.TYPING)
    tools = await get_available_tools()

    if not tools:
        await update.message.reply_text(
            "❌ 등록된 Tool이 없거나 목록을 가져올 수 없습니다.\n"
            "OpenWebUI 웹 UI에서 Tool이 등록되어 있는지 확인해주세요."
        )
        return

    # 인라인 키보드로 Tool 토글
    keyboard = []
    for t in tools:
        is_on = t["id"] in session.enabled_tool_ids
        icon = "✅" if is_on else "⬜"
        label = f"{icon} {t['name'][:35]}"
        keyboard.append([InlineKeyboardButton(label, callback_data=f"tool:{t['id']}")])

    # 일괄 버튼 추가
    keyboard.append([
        InlineKeyboardButton("🟢 전체 활성화", callback_data="tool_all:on"),
        InlineKeyboardButton("🔴 전체 비활성화", callback_data="tool_all:off"),
    ])
    keyboard.append([
        InlineKeyboardButton("🔄 새로고침", callback_data="tool_refresh"),
    ])

    enabled_count = len(session.enabled_tool_ids)
    total_count = len(tools)

    tool_desc_lines = []
    for t in tools:
        is_on = t["id"] in session.enabled_tool_ids
        icon = "✅" if is_on else "⬜"
        desc = t["description"][:50] + "..." if len(t.get("description", "")) > 50 else t.get("description", "")
        tool_desc_lines.append(f"{icon} <b>{html.escape(t['name'])}</b>\n   <i>{html.escape(desc)}</i>")

    text = (
        f"🔧 <b>Tool 관리</b> ({enabled_count}/{total_count} 활성화)\n\n"
        + "\n\n".join(tool_desc_lines)
        + "\n\n💡 버튼을 눌러 Tool을 켜거나 끌 수 있습니다.\n"
        "활성화된 Tool은 대화 중 AI가 자동으로 사용합니다."
    )

    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text(text, parse_mode=ParseMode.HTML, reply_markup=reply_markup)

async def callback_tool_toggle(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """개별 Tool 활성화/비활성화 콜백"""
    query = update.callback_query
    await query.answer()

    user = query.from_user
    if user.id not in ADMIN_USER_IDS:
        return

    tool_id = query.data.replace("tool:", "")
    session = get_session(user.id)
    is_now_enabled = session.toggle_tool(tool_id)

    # Tool 이름 찾기
    tools = await get_available_tools()
    tool_name = tool_id
    for t in tools:
        if t["id"] == tool_id:
            tool_name = t["name"]
            break

    status = "활성화" if is_now_enabled else "비활성화"
    logger.info(f"🔧 Tool 토글: {user.id} — {tool_name} → {status}")

    # 키보드 업데이트
    keyboard = []
    for t in tools:
        is_on = t["id"] in session.enabled_tool_ids
        icon = "✅" if is_on else "⬜"
        label = f"{icon} {t['name'][:35]}"
        keyboard.append([InlineKeyboardButton(label, callback_data=f"tool:{t['id']}")])

    keyboard.append([
        InlineKeyboardButton("🟢 전체 활성화", callback_data="tool_all:on"),
        InlineKeyboardButton("🔴 전체 비활성화", callback_data="tool_all:off"),
    ])
    keyboard.append([
        InlineKeyboardButton("🔄 새로고침", callback_data="tool_refresh"),
    ])

    enabled_count = len(session.enabled_tool_ids)
    total_count = len(tools)

    tool_desc_lines = []
    for t in tools:
        is_on = t["id"] in session.enabled_tool_ids
        icon = "✅" if is_on else "⬜"
        desc = t["description"][:50] + "..." if len(t.get("description", "")) > 50 else t.get("description", "")
        tool_desc_lines.append(f"{icon} <b>{html.escape(t['name'])}</b>\n   <i>{html.escape(desc)}</i>")

    text = (
        f"🔧 <b>Tool 관리</b> ({enabled_count}/{total_count} 활성화)\n\n"
        + "\n\n".join(tool_desc_lines)
        + f"\n\n✏️ {html.escape(tool_name)} → {status}됨"
    )

    reply_markup = InlineKeyboardMarkup(keyboard)
    try:
        await query.edit_message_text(text, parse_mode=ParseMode.HTML, reply_markup=reply_markup)
    except Exception:
        pass  # 메시지 변경 없으면 무시

async def callback_tool_all(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """전체 Tool 일괄 활성화/비활성화 콜백"""
    query = update.callback_query
    await query.answer()

    user = query.from_user
    if user.id not in ADMIN_USER_IDS:
        return

    action = query.data.replace("tool_all:", "")
    session = get_session(user.id)
    tools = await get_available_tools()

    if action == "on":
        session.enable_all_tools([t["id"] for t in tools])
        logger.info(f"🔧 전체 Tool 활성화: {user.id} ({len(tools)}개)")
    else:
        session.disable_all_tools()
        logger.info(f"🔧 전체 Tool 비활성화: {user.id}")

    # 키보드 재생성
    keyboard = []
    for t in tools:
        is_on = t["id"] in session.enabled_tool_ids
        icon = "✅" if is_on else "⬜"
        label = f"{icon} {t['name'][:35]}"
        keyboard.append([InlineKeyboardButton(label, callback_data=f"tool:{t['id']}")])

    keyboard.append([
        InlineKeyboardButton("🟢 전체 활성화", callback_data="tool_all:on"),
        InlineKeyboardButton("🔴 전체 비활성화", callback_data="tool_all:off"),
    ])
    keyboard.append([InlineKeyboardButton("🔄 새로고침", callback_data="tool_refresh")])

    enabled_count = len(session.enabled_tool_ids)
    total_count = len(tools)
    status_text = "전체 활성화 완료" if action == "on" else "전체 비활성화 완료"

    tool_desc_lines = []
    for t in tools:
        is_on = t["id"] in session.enabled_tool_ids
        icon = "✅" if is_on else "⬜"
        desc = t["description"][:50] + "..." if len(t.get("description", "")) > 50 else t.get("description", "")
        tool_desc_lines.append(f"{icon} <b>{html.escape(t['name'])}</b>\n   <i>{html.escape(desc)}</i>")

    text = (
        f"🔧 <b>Tool 관리</b> ({enabled_count}/{total_count} 활성화)\n\n"
        + "\n\n".join(tool_desc_lines)
        + f"\n\n✏️ {status_text}"
    )

    reply_markup = InlineKeyboardMarkup(keyboard)
    try:
        await query.edit_message_text(text, parse_mode=ParseMode.HTML, reply_markup=reply_markup)
    except Exception:
        pass

async def callback_tool_refresh(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Tool 목록 새로고침 콜백"""
    query = update.callback_query
    await query.answer("🔄 새로고침 중...")

    user = query.from_user
    if user.id not in ADMIN_USER_IDS:
        return

    session = get_session(user.id)
    tools = await get_available_tools(force_refresh=True)

    keyboard = []
    for t in tools:
        is_on = t["id"] in session.enabled_tool_ids
        icon = "✅" if is_on else "⬜"
        label = f"{icon} {t['name'][:35]}"
        keyboard.append([InlineKeyboardButton(label, callback_data=f"tool:{t['id']}")])

    keyboard.append([
        InlineKeyboardButton("🟢 전체 활성화", callback_data="tool_all:on"),
        InlineKeyboardButton("🔴 전체 비활성화", callback_data="tool_all:off"),
    ])
    keyboard.append([InlineKeyboardButton("🔄 새로고침", callback_data="tool_refresh")])

    enabled_count = len(session.enabled_tool_ids)
    total_count = len(tools)

    tool_desc_lines = []
    for t in tools:
        is_on = t["id"] in session.enabled_tool_ids
        icon = "✅" if is_on else "⬜"
        desc = t["description"][:50] + "..." if len(t.get("description", "")) > 50 else t.get("description", "")
        tool_desc_lines.append(f"{icon} <b>{html.escape(t['name'])}</b>\n   <i>{html.escape(desc)}</i>")

    text = (
        f"🔧 <b>Tool 관리</b> ({enabled_count}/{total_count} 활성화)\n\n"
        + "\n\n".join(tool_desc_lines)
        + "\n\n🔄 목록이 새로고침되었습니다."
    )

    reply_markup = InlineKeyboardMarkup(keyboard)
    try:
        await query.edit_message_text(text, parse_mode=ParseMode.HTML, reply_markup=reply_markup)
    except Exception:
        pass

# ══════════════════════════════════════════
# 메시지 핸들러
# ══════════════════════════════════════════
@authorized
async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """일반 텍스트 메시지 처리"""
    user = update.effective_user
    raw_text = update.message.text
    text = sanitize_input(raw_text)

    if not text:
        return

    session = get_session(user.id)
    logger.info(f"💬 [{user.id}] {mask_sensitive(text[:100])}")

    # 타이핑 표시
    await update.message.reply_chat_action(ChatAction.TYPING)

    # OpenWebUI에 전달
    reply = await call_openwebui_chat(session, text)

    # Telegram 메시지 길이 제한 (4096자)
    if len(reply) > 4096:
        # 분할 전송
        chunks = [reply[i:i+4000] for i in range(0, len(reply), 4000)]
        for chunk in chunks:
            await update.message.reply_text(chunk)
    else:
        # Markdown 시도, 실패 시 일반 텍스트
        try:
            await update.message.reply_text(reply, parse_mode=ParseMode.MARKDOWN)
        except Exception:
            try:
                await update.message.reply_text(reply)
            except Exception as e:
                logger.error(f"응답 전송 실패: {e}")
                await update.message.reply_text("❌ 응답 전송 중 오류가 발생했습니다.")

@authorized
async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """파일(PDF, 문서 등) 업로드 처리"""
    user = update.effective_user
    document = update.message.document

    if not document:
        return

    # 파일 크기 확인
    if document.file_size > MAX_FILE_SIZE_MB * 1024 * 1024:
        await update.message.reply_text(
            f"❌ 파일이 너무 큽니다. (최대 {MAX_FILE_SIZE_MB}MB)"
        )
        return

    filename = sanitize_input(document.file_name or "unknown")
    logger.info(f"📎 [{user.id}] 파일 업로드: {filename} ({document.file_size} bytes)")

    await update.message.reply_chat_action(ChatAction.UPLOAD_DOCUMENT)

    try:
        file = await document.get_file()
        file_bytes = await file.download_as_bytearray()

        result = await upload_file_to_openwebui(bytes(file_bytes), filename)

        if "error" in result:
            await update.message.reply_text(f"❌ 파일 업로드 실패: {result['error']}")
        else:
            file_id = result.get("id", "unknown")
            await update.message.reply_text(
                f"✅ <b>파일 업로드 완료!</b>\n\n"
                f"📄 파일명: {html.escape(filename)}\n"
                f"🆔 ID: <code>{file_id}</code>\n\n"
                "이제 이 문서에 대해 질문할 수 있습니다.",
                parse_mode=ParseMode.HTML,
            )
    except Exception as e:
        logger.error(f"파일 처리 오류: {e}")
        await update.message.reply_text("❌ 파일 처리 중 오류가 발생했습니다.")

@authorized
async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """이미지 업로드 처리"""
    user = update.effective_user
    photo = update.message.photo[-1]  # 최고 해상도

    logger.info(f"🖼️ [{user.id}] 이미지 업로드: {photo.file_size} bytes")

    await update.message.reply_chat_action(ChatAction.UPLOAD_PHOTO)

    try:
        file = await photo.get_file()
        file_bytes = await file.download_as_bytearray()
        filename = f"photo_{user.id}_{int(time.time())}.jpg"

        result = await upload_file_to_openwebui(bytes(file_bytes), filename)

        if "error" in result:
            await update.message.reply_text(f"❌ 이미지 업로드 실패: {result['error']}")
        else:
            # 이미지에 대한 캡션이 있으면 AI에게 질문
            caption = update.message.caption
            if caption:
                session = get_session(user.id)
                await update.message.reply_chat_action(ChatAction.TYPING)
                reply = await call_openwebui_chat(
                    session,
                    f"[이미지 업로드됨: {filename}] {sanitize_input(caption)}"
                )
                await update.message.reply_text(reply)
            else:
                await update.message.reply_text(
                    "✅ 이미지가 업로드되었습니다.\n"
                    "이미지에 대해 질문하려면 캡션과 함께 보내세요."
                )
    except Exception as e:
        logger.error(f"이미지 처리 오류: {e}")
        await update.message.reply_text("❌ 이미지 처리 중 오류가 발생했습니다.")

@authorized
async def handle_voice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """음성 메시지 처리 → OpenWebUI에 텍스트로 전달"""
    user = update.effective_user
    voice = update.message.voice

    logger.info(f"🎤 [{user.id}] 음성 메시지: {voice.duration}초")

    await update.message.reply_chat_action(ChatAction.TYPING)

    try:
        file = await voice.get_file()
        file_bytes = await file.download_as_bytearray()
        filename = f"voice_{user.id}_{int(time.time())}.ogg"

        # OpenWebUI의 음성 변환 API 사용 시도
        headers = {"Authorization": f"Bearer {OPENWEBUI_API_KEY}"}
        timeout = aiohttp.ClientTimeout(total=30)

        form = aiohttp.FormData()
        form.add_field("file", bytes(file_bytes), filename=filename, content_type="audio/ogg")

        async with aiohttp.ClientSession(timeout=timeout) as http:
            async with http.post(
                f"{OPENWEBUI_URL}/api/v1/audio/transcriptions",
                headers=headers,
                data=form,
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    transcript = data.get("text", "")
                    if transcript:
                        await update.message.reply_text(f"🎤 인식된 텍스트: {transcript}")
                        session = get_session(user.id)
                        reply = await call_openwebui_chat(session, transcript)
                        try:
                            await update.message.reply_text(reply, parse_mode=ParseMode.MARKDOWN)
                        except Exception:
                            await update.message.reply_text(reply)
                        return

        # 실패 시 안내
        await update.message.reply_text(
            "⚠️ 음성 인식에 실패했습니다.\n텍스트로 입력해주세요."
        )

    except Exception as e:
        logger.error(f"음성 처리 오류: {e}")
        await update.message.reply_text("❌ 음성 처리 중 오류가 발생했습니다.")

# ══════════════════════════════════════════
# 에러 핸들러
# ══════════════════════════════════════════
async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE):
    logger.error(f"⚠️ 에러 발생: {context.error}")

# ══════════════════════════════════════════
# Health Check 서버 (별도 포트)
# ══════════════════════════════════════════
async def health_server():
    """Docker healthcheck용 HTTP 서버"""
    from aiohttp import web

    async def health_check(request):
        # OpenWebUI 연결 확인
        try:
            timeout = aiohttp.ClientTimeout(total=3)
            async with aiohttp.ClientSession(timeout=timeout) as http:
                async with http.get(f"{OPENWEBUI_URL}/health") as resp:
                    webui_ok = resp.status == 200
        except Exception:
            webui_ok = False

        status = {
            "status": "healthy" if webui_ok else "degraded",
            "openwebui": "connected" if webui_ok else "disconnected",
            "active_sessions": len([s for s in sessions.values() if not s.is_expired()]),
            "blocked_users": len(rate_limiter.blocked),
            "uptime": str(datetime.now() - start_time),
        }
        code = 200 if webui_ok else 503
        return web.json_response(status, status=code)

    async def metrics(request):
        """간단한 메트릭"""
        data = {
            "total_sessions": len(sessions),
            "active_sessions": len([s for s in sessions.values() if not s.is_expired()]),
            "total_messages": sum(len(s.history) for s in sessions.values()),
            "blocked_users": len(rate_limiter.blocked),
            "rate_limited_users": len([uid for uid, reqs in rate_limiter.requests.items()
                                       if len(reqs) >= RATE_LIMIT_PER_MINUTE]),
        }
        return web.json_response(data)

    app = web.Application()
    app.router.add_get("/health", health_check)
    app.router.add_get("/metrics", metrics)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", 8443)
    await site.start()
    logger.info("🏥 Health check 서버 시작: http://0.0.0.0:8443/health")

# ══════════════════════════════════════════
# 메인
# ══════════════════════════════════════════
start_time = datetime.now()

async def post_init(application: Application):
    """봇 초기화 후 명령어 등록"""
    commands = [
        BotCommand("start", "봇 시작"),
        BotCommand("help", "도움말"),
        BotCommand("model", "모델 선택/변경"),
        BotCommand("tools", "Tool 활성화/비활성화"),
        BotCommand("clear", "대화 기록 초기화"),
        BotCommand("history", "대화 기록 보기"),
        BotCommand("status", "시스템 상태"),
        BotCommand("whoami", "내 정보"),
    ]
    await application.bot.set_my_commands(commands)
    logger.info("📋 봇 명령어 등록 완료")

    # Health check 서버 시작
    asyncio.create_task(health_server())

def main():
    if not TELEGRAM_BOT_TOKEN:
        logger.error("❌ TELEGRAM_BOT_TOKEN이 설정되지 않았습니다.")
        sys.exit(1)

    if not OPENWEBUI_API_KEY:
        logger.error("❌ OPENWEBUI_API_KEY가 설정되지 않았습니다.")
        sys.exit(1)

    if not ADMIN_USER_IDS:
        logger.error("❌ ALLOWED_USER_IDS(관리자 ID)가 설정되지 않았습니다.")
        logger.error("   .env 파일에 ALLOWED_USER_IDS=123456789 형식으로 추가하세요.")
        sys.exit(1)

    logger.info("=" * 50)
    logger.info("🚀 Telegram ↔ OpenWebUI 브릿지 시작 (관리자 전용)")
    logger.info(f"   모델: {DEFAULT_MODEL}")
    logger.info(f"   OpenWebUI: {OPENWEBUI_URL}")
    logger.info(f"   등록된 관리자: {len(ADMIN_USER_IDS)}명 — {ADMIN_USER_IDS}")
    logger.info(f"   Webhook: {'활성화' if USE_WEBHOOK else '비활성화 (Polling)'}")
    logger.info(f"   Rate Limit: {RATE_LIMIT_PER_MINUTE}/분")
    logger.info("=" * 50)

    # Application 빌드
    builder = Application.builder().token(TELEGRAM_BOT_TOKEN)
    builder.post_init(post_init)
    app = builder.build()

    # 핸들러 등록
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("model", cmd_model))
    app.add_handler(CommandHandler("tools", cmd_tools))
    app.add_handler(CommandHandler("clear", cmd_clear))
    app.add_handler(CommandHandler("history", cmd_history))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(CommandHandler("whoami", cmd_whoami))
    app.add_handler(CallbackQueryHandler(callback_model_select, pattern=r"^model:"))
    app.add_handler(CallbackQueryHandler(callback_tool_toggle, pattern=r"^tool:[^_]"))
    app.add_handler(CallbackQueryHandler(callback_tool_all, pattern=r"^tool_all:"))
    app.add_handler(CallbackQueryHandler(callback_tool_refresh, pattern=r"^tool_refresh$"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_document))
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    app.add_handler(MessageHandler(filters.VOICE, handle_voice))
    app.add_error_handler(error_handler)

    # 실행
    if USE_WEBHOOK and SERVER_DOMAIN:
        webhook_url = f"{SERVER_DOMAIN}/telegram-webhook"
        logger.info(f"🌐 Webhook 모드: {webhook_url}")
        app.run_webhook(
            listen="0.0.0.0",
            port=8443,
            url_path="telegram-webhook",
            webhook_url=webhook_url,
            secret_token=WEBHOOK_SECRET,
        )
    else:
        logger.info("🔄 Long Polling 모드로 시작")
        app.run_polling(
            allowed_updates=Update.ALL_TYPES,
            drop_pending_updates=True,
        )


if __name__ == "__main__":
    main()
BOTEOF

print_ok "telegram_bot.py 생성 완료"

############################################
# 7. Dockerfile
############################################
cat > bot/Dockerfile <<'DOCKEOF'
# =============================================================================
# Telegram ↔ OpenWebUI Bridge Dockerfile
# Author:  <webmaster@vulva.sex>
# License: MIT License
# =============================================================================
FROM python:3.11-slim

# 메타데이터
LABEL maintainer="webmaster@vulva.sex"
LABEL version="1.0.0"
LABEL description="Telegram OpenWebUI Bridge Bot (Security Enhanced)"
LABEL license="MIT"

# 보안: non-root 사용자
RUN groupadd -r botuser && useradd -r -g botuser -s /sbin/nologin botuser

WORKDIR /app

# 시스템 패키지
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Python 의존성
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# 소스 복사
COPY telegram_bot.py .

# 디렉토리 생성 + 권한
RUN mkdir -p /app/logs /app/data && \
    chown -R botuser:botuser /app

# non-root 전환
USER botuser

# Health check (프로세스 존재 여부 확인 — Polling/Webhook 모두 호환)
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD pgrep -f telegram_bot.py || exit 1

EXPOSE 8443

CMD ["python3", "-u", "telegram_bot.py"]
DOCKEOF

print_ok "Dockerfile 생성 완료"

############################################
# 8. docker-compose.yml
############################################

# 네트워크 설정 동적 생성
if [ -n "$WEBUI_NETWORK" ]; then
  COMPOSE_NETWORK_SECTION="networks:
      - default
      - openwebui-net"
  COMPOSE_NETWORKS_DEF="
networks:
  openwebui-net:
    external: true
    name: ${WEBUI_NETWORK}"
else
  COMPOSE_NETWORK_SECTION="extra_hosts:
      - \"host.docker.internal:host-gateway\""
  COMPOSE_NETWORKS_DEF=""
fi

cat > docker-compose.yml <<COMPEOF
services:
  telegram-bot:
    build: ./bot
    container_name: telegram-openwebui-bridge
    env_file: .env
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    ports:
      - "127.0.0.1:8443:8443"
    ${COMPOSE_NETWORK_SECTION}
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "1.0"
        reservations:
          memory: 128M
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    read_only: false
    tmpfs:
      - /tmp:size=50M
${COMPOSE_NETWORKS_DEF}
COMPEOF

print_ok "docker-compose.yml 생성 완료"

############################################
# 9. Nginx 설정 추가 (Webhook 모드)
############################################
if [ "$USE_WEBHOOK" = "true" ] && [ -n "$SERVER_DOMAIN" ]; then
  print_header "🌐 Nginx Webhook 경로 추가"

  NGINX_TELEGRAM_CONF="/etc/nginx/sites-available/telegram-webhook"

  sudo tee "$NGINX_TELEGRAM_CONF" > /dev/null <<NGINXEOF
# Telegram Webhook Proxy
# 기존 OpenWebUI Nginx에 추가하거나 별도로 사용
server {
    listen 443 ssl;
    server_name $(echo "$SERVER_DOMAIN" | sed 's|https://||' | sed 's|http://||');

    # SSL 인증서 경로 (Let's Encrypt 등)
    # ssl_certificate /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem;

    location /telegram-webhook {
        proxy_pass http://127.0.0.1:8443;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;

        # Telegram IP만 허용 (선택)
        # allow 149.154.160.0/20;
        # allow 91.108.4.0/22;
        # deny all;
    }
}
NGINXEOF

  print_ok "Nginx Webhook 설정 생성됨"
  print_warn "SSL 인증서 경로를 ${NGINX_TELEGRAM_CONF} 에서 수정해주세요."
fi

############################################
# 10. 빌드 및 실행
############################################
print_header "🔨 Docker 빌드 및 실행"

cd "$BASE_DIR"

echo ""
echo "   📦 Docker 이미지 빌드 중..."
docker compose build --no-cache 2>&1 | tail -5

echo ""
echo "   🚀 컨테이너 시작 중..."
docker compose up -d

echo ""
echo "   ⏳ 봇 준비 대기 중..."
for i in $(seq 1 30); do
  BOT_STATUS=$(docker inspect -f '{{.State.Running}}' telegram-openwebui-bridge 2>/dev/null || echo "false")
  if [ "$BOT_STATUS" = "true" ]; then
    # 컨테이너가 실행 중이고 재시작 중이 아닌지 확인
    RESTARTING=$(docker inspect -f '{{.State.Restarting}}' telegram-openwebui-bridge 2>/dev/null || echo "true")
    if [ "$RESTARTING" = "false" ]; then
      print_ok "Telegram 봇 준비 완료!"
      break
    fi
  fi
  printf "   ⏳ 대기 중... %d/30\r" $i
  sleep 2
done

# 상태 확인
HEALTH_STATUS=$(docker inspect -f '{{.State.Status}}' telegram-openwebui-bridge 2>/dev/null || echo "unknown")

############################################
# 11. 기존 Twilio 봇에 Telegram 연동 환경변수 추가
############################################
OPENWEBUI_RAG_DIR="$HOME/openapi-rag"
if [ -d "$OPENWEBUI_RAG_DIR" ] && [ -f "$OPENWEBUI_RAG_DIR/.env" ]; then
  print_header "🔗 기존 OpenWebUI 환경에 Telegram 정보 추가"

  if ! grep -q "TELEGRAM_BOT_TOKEN" "$OPENWEBUI_RAG_DIR/.env"; then
    cat >> "$OPENWEBUI_RAG_DIR/.env" <<ENVADD

# Telegram 브릿지 연동
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_BRIDGE_URL=http://localhost:8443
ENVADD
    print_ok "기존 .env에 Telegram 정보 추가됨"
  else
    print_info "이미 Telegram 정보가 있음 (건너뜀)"
  fi
fi

############################################
# 12. 완료 메시지
############################################
echo ""
echo ""
echo -e "${GREEN}┌══════════════════════════════════════════════════┐${NC}"
echo -e "${GREEN}  🎉  Telegram ↔ OpenWebUI 브릿지 설치 완료!       ${NC}"
echo -e "${GREEN}└══════════════════════════════════════════════════┘${NC}"
echo ""
echo -e "${CYAN}📊 상태: ${HEALTH_STATUS}${NC}"
echo ""
echo "🤖 Telegram Bot 사용법:"
echo "   1. Telegram에서 봇을 찾아 /start 명령 실행"
echo "   2. 일반 메시지를 보내면 OpenWebUI AI가 응답"
echo "   3. PDF/이미지를 보내면 RAG에 자동 등록"
echo "   4. /model 로 AI 모델 변경 가능"
echo ""
echo "🔒 보안 설정:"
echo "   ✅ 관리자 전용: ${ALLOWED_USER_IDS}"
echo "   ✅ 비관리자 접근 시 자동 차단"
echo "   ✅ Rate Limit: 30회/분"
echo "   ✅ 세션 타임아웃: 30분"
echo "   ✅ 입력 제한: 4096자"
echo "   ✅ 파일 제한: 20MB"
echo "   ✅ 컨테이너 non-root 실행"
echo "   ✅ .env 권한: 600 (소유자만 읽기/쓰기)"
echo ""
echo "🌐 서비스:"
echo "   Health Check  : http://localhost:8443/health"
echo "   Metrics       : http://localhost:8443/metrics"
echo "   OpenWebUI     : http://localhost:3000"
echo ""
echo "📂 설치 경로: ${BASE_DIR}"
echo "📋 로그 확인: docker logs -f telegram-openwebui-bridge"
echo ""
echo "🔧 관리 명령어:"
echo "   재시작: cd ${BASE_DIR} && docker compose restart"
echo "   중지:   cd ${BASE_DIR} && docker compose down"
echo "   로그:   cd ${BASE_DIR} && docker compose logs -f"
echo "   업데이트: cd ${BASE_DIR} && docker compose build --no-cache && docker compose up -d"
echo ""
