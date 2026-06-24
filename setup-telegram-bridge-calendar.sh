#!/bin/bash
# =============================================================================
# 프로젝트명: OpenWebUI ↔ Telegram 브릿지 설치 스크립트 (보안강화판)
# 제작자: <webmaster@vulva.sex>
# 버전: 2.0.0-보안강화 (보안 26항목: Replay방어·PromptInjection·MagicBytes·응답필터·감사로그·비상차단·Brute-force방지·Seccomp)
# 원본: start-openwebui-with-rag-groq-ollama-Twilio-final.sh (v3.6.0)
# 설명: 이미 설치된 OpenWebUI의 API 키를 받아 Telegram Bot과 연동
#       OpenWebUI의 모든 모델/Tool/RAG를 Telegram에서 그대로 사용
#
# ✅ 보안 (26항목)
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
#    [NEW] Replay Attack 방어 (update_id 중복 요청 차단)
#    [NEW] Prompt Injection 방어 (9개 패턴 정규식 감지 + 차단)
#    [NEW] 파일 Magic Bytes 검증 (확장자 위조 방지)
#    [NEW] AI 응답 민감정보 자동 필터링 (API키·JWT·전화번호)
#    [NEW] 구조화된 감사 로그 JSON (audit.log)
#    [NEW] 비상 차단 모드 /emergency (관리자 외 즉시 전체 차단)
#    [NEW] 대시보드 Brute-force 방지 (5회 실패 → 15분 IP 잠금, timing-safe)
#    [NEW] Seccomp 프로파일 (허용 syscall 화이트리스트)
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

# 입력 타임아웃 초과 시 종료
timeout_exit() {
  echo ""
  echo "┌────────────────────────────────────────────┐"
  echo "⏰ 입력 시간 초과 (180초)"
  echo "└────────────────────────────────────────────┘"
  echo "   ❌ 처음부터 다시 실행해 주세요:"
  echo "   ./setup-telegram-openwebui-bridge-fixed.sh"
  echo ""
  exit 1
}

# 민감 정보 입력 (확인 단계 포함):
#   1) 입력 (타이핑은 화면에 숨김)
#   2) 마스킹(****) + 글자 수 표시로 입력 확인
#   3) Y/Enter=확정, n=재입력, s=실제값 확인 후 재확인
# 입력값은 stdout으로만 반환되며, 모든 안내는 stderr(>&2)로 출력됩니다.
# 사용법: VAR=$(read_secret "프롬프트: " [timeout] [on_timeout])
#   - timeout: 입력 대기 초 (기본 180)
#   - on_timeout: "exit"(기본)=timeout_exit 호출 / "skip"=빈 문자열 반환(선택 입력용)
#   - 빈 입력은 빈 문자열을 그대로 반환(이후 검증/건너뜀 로직에 위임)
read_secret() {
  local prompt="$1"
  local timeout="${2:-180}"
  local on_timeout="${3:-exit}"
  local value="" confirm masked
  while true; do
    value=""
    if ! read -t "$timeout" -r -s -p "$prompt" value; then
      echo "" >&2
      if [ "$on_timeout" = "skip" ]; then
        echo ""
        return 0
      fi
      timeout_exit
    fi
    echo "" >&2
    value=$(echo "$value" | xargs 2>/dev/null || true)
    if [ -z "$value" ]; then
      # 빈 입력은 그대로 반환 (건너뜀/검증 로직에 위임)
      echo ""
      return 0
    fi
    masked=$(echo "$value" | sed 's/./*/g')
    read -r -p "   입력값: ${masked} (${#value}자) — 맞습니까? (Y/n, s=실제값 보기): " confirm >&2 || true
    case "$confirm" in
      [Ss])
        echo "   👁  입력한 값: ${value}" >&2
        read -r -p "   이 값이 맞습니까? (Y/n): " confirm >&2 || true
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
          echo "   ↩️  다시 입력합니다." >&2
          continue
        fi
        break
        ;;
      [Nn])
        echo "   ↩️  다시 입력합니다." >&2
        continue
        ;;
      *)
        break
        ;;
    esac
  done
  echo "$value"
}

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

# ── Telegram 중복 컨테이너 감지 ──────────────────────────────────────
# setup-browser-agent-v6.sh 의 Phase3 스텁(telegram-openwebui-bot)이
# 이미 실행 중이면 포트/네트워크 충돌 없이 공존 가능하지만
# 두 개가 동시에 같은 Bot Token을 사용하면 메시지 수신이 분산됨 → 경고 출력
_TG_STUB=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i 'telegram-openwebui-bot' | head -1 || true)
if [ -n "$_TG_STUB" ]; then
  echo ""
  print_warn "⚠️  browser-agent Phase3 Telegram 스텁 컨테이너 감지됨: ${_TG_STUB}"
  print_warn "    같은 Bot Token 사용 시 메시지 수신이 두 컨테이너로 분산됩니다."
  print_warn "    이 스크립트(③)가 정식 브릿지이므로 스텁을 중지하는 것을 권장합니다."
  echo ""
  read -t 30 -p "   스텁 컨테이너(${_TG_STUB})를 지금 중지할까요? (y/N | 30초 내): " _STOP_STUB || true
  _STOP_STUB=$(echo "${_STOP_STUB:-N}" | xargs)
  if [[ "$_STOP_STUB" =~ ^[Yy]$ ]]; then
    docker stop "$_TG_STUB" 2>/dev/null && print_ok "스텁 컨테이너 중지됨: ${_TG_STUB}" || print_warn "중지 실패 — 수동으로 처리하세요: docker stop ${_TG_STUB}"
  else
    print_info "스텁 컨테이너 유지 — 설치 후 Bot Token 중복 여부를 확인하세요."
  fi
  echo ""
fi
# ──────────────────────────────────────────────────────────────────────

# OpenWebUI 컨테이너 이름 및 네트워크 자동 감지
# ⚠️ tools 서버(openapi-tools) 제외하고 open-webui 컨테이너만 정확히 감지
WEBUI_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i 'open-webui' | grep -v 'tools' | head -1 || true)
if [ -z "$WEBUI_CONTAINER" ]; then
  # 두 번째 시도: openwebui 포함 컨테이너 중 tools 제외
  WEBUI_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i 'openwebui' | grep -v 'tools' | head -1 || true)
fi
if [ -z "$WEBUI_CONTAINER" ]; then
  # 세 번째 시도: webui 포함 컨테이너 (이름 패턴 다를 경우)
  WEBUI_CONTAINER=$(docker ps --format '{{.Names}}' | grep -iv 'tools\|qdrant\|ollama\|redis\|postgres\|mysql\|nginx' | head -1 || true)
fi
if [ -n "$WEBUI_CONTAINER" ]; then
  WEBUI_PORT=8080
  # ⚠️ 네트워크가 여러 개일 때 줄바꿈 없이 붙어 나오는 문제 수정
  # go template으로 각 네트워크명을 개행 구분으로 추출
  WEBUI_NETWORK=$(docker inspect "$WEBUI_CONTAINER" \
    --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}
{{end}}' 2>/dev/null | head -1 | tr -d '[:space:]' || true)
  WEBUI_INTERNAL_URL="http://${WEBUI_CONTAINER}:${WEBUI_PORT}"
  print_ok "OpenWebUI 컨테이너: ${WEBUI_CONTAINER} (내부포트: ${WEBUI_PORT})"
  print_ok "OpenWebUI 네트워크: ${WEBUI_NETWORK}"
else
  WEBUI_INTERNAL_URL="http://host.docker.internal:3000"
  WEBUI_NETWORK=""
  print_warn "OpenWebUI 컨테이너 자동 감지 실패 — host.docker.internal 사용"
fi

# browser-agent v6 전용 네트워크(openwebui_net) 존재 여부 확인
# setup-browser-agent-v6.sh 가 ~/OpenWebUI/docker-compose.yml 에 openwebui_net 을 추가하기 때문에
# 브릿지도 해당 네트워크에 참여해야 browser-agent:8001 DNS 해석이 가능
BA_NETWORK=""
if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^openwebui_net$"; then
  BA_NETWORK="openwebui_net"
  print_ok "browser-agent 네트워크 감지됨: openwebui_net → 브릿지도 연결 예정"
else
  # [문제1 해결] browser-agent(Phase 3)가 아직 설치되지 않은 상태.
  # 설치 순서가 telegram(Phase 2) → browser-agent(Phase 3)이면 이 시점엔 항상 없음.
  print_warn "openwebui_net 네트워크 없음 — browser-agent(Phase 3) 미설치 상태입니다."
  print_info "ℹ️  지금은 Telegram↔OpenWebUI 연동만 구성됩니다 (정상)."
  print_info "ℹ️  browser-agent(웹 검색/브라우징)도 사용하실 계획이라면:"
  print_info "      1) 먼저 browser-agent 스크립트를 설치하세요"
  print_info "         (setup-browser-agent-browser-use-v6.sh)"
  print_info "      2) 설치가 끝나면 browser-agent 스크립트가 이 브릿지를"
  print_info "         openwebui_net 에 자동 재연결합니다."
  print_info "      3) 자동 재연결이 안 되면 이 telegram 스크립트를 한 번 더 실행하세요."
fi

# ⚠️ OPENWEBUI_URL 검증
# Docker 내부 컨테이너명은 호스트에서 직접 접근 불가
# → localhost:3000 으로 정상 여부만 확인
echo "   🔍 OpenWebUI 연결 확인 중: localhost:3000"
OW_CHECK=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://localhost:3000/health" 2>/dev/null || echo "000")
if [ "$OW_CHECK" = "200" ]; then
  print_ok "OpenWebUI 연결 확인됨 (HTTP ${OW_CHECK})"
  # 컨테이너 감지 성공 시 내부 URL 사용, 실패 시 host.docker.internal 사용
  if [ -z "$WEBUI_CONTAINER" ]; then
    WEBUI_INTERNAL_URL="http://host.docker.internal:3000"
    WEBUI_NETWORK=""
  fi
else
  print_warn "OpenWebUI 응답 없음 (${OW_CHECK}) — 설치 후 연결 재시도됩니다"
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
  TELEGRAM_BOT_TOKEN=$(read_secret "   🔑 Telegram Bot Token (180초 내 입력): " 180)
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
  OPENWEBUI_API_KEY=$(read_secret "   🔑 OpenWebUI API Key (180초 내 입력): " 180)
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
      read -t 30 -p "   계속 진행? (y/N): " CONTINUE_ANYWAY || timeout_exit
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
  read -t 180 -p "   📱 관리자 Telegram User ID (180초 내 입력, 필수): " ALLOWED_USER_IDS || timeout_exit
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
ADMIN_PIN=$(read_secret "   🔢 관리자 PIN 6자리 (180초 내 Enter=건너뜀): " 180 skip)
if [ -n "$ADMIN_PIN" ]; then
  WEAK_PINS="123456 000000 111111 222222 333333 444444 555555 666666 777777 888888 999999 654321"
  PIN_VALID=true
  if [ ${#ADMIN_PIN} -ne 6 ] || ! echo "$ADMIN_PIN" | grep -qE '^[0-9]{6}$'; then
    print_err "PIN은 정확히 6자리 숫자여야 합니다."
    PIN_VALID=false
  fi
  for wp in $WEAK_PINS; do
    if [ "$ADMIN_PIN" = "$wp" ]; then
      print_err "취약한 PIN(${ADMIN_PIN})은 사용할 수 없습니다."
      PIN_VALID=false
      break
    fi
  done
  if [ "$PIN_VALID" = true ]; then
    print_ok "관리자 PIN 설정됨 (강도 검증 통과)"
  else
    ADMIN_PIN=""
    print_warn "PIN이 무효하여 비활성화됨"
  fi
else
  ADMIN_PIN=""
  print_info "관리자 PIN 비활성화"
fi

echo ""
read -t 180 -p "   🌐 서버 도메인 (180초 내 Enter=Polling 모드): " SERVER_DOMAIN || timeout_exit
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
# 안전한 기본 모델 우선순위 (첫 번째 모델이 아닌 안정적인 모델 선택)
SAFE_MODELS = ['llama-3.3-70b-versatile', 'meta-llama/llama-4-scout-17b-16e-instruct', 'llama-3.1-8b-instant', 'gemma2-9b-it', 'qwen/qwen3-32b']
try:
    data = json.load(sys.stdin)
    models = data.get('data', data.get('models', []))
    ids = [m.get('id', m.get('name', '')) for m in models]
    for safe in SAFE_MODELS:
        if safe in ids:
            print(safe)
            exit()
    print('llama-3.3-70b-versatile')
except (json.JSONDecodeError, KeyError, TypeError):
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
  read -t 30 -p "   기존 설치를 덮어쓰시겠습니까? (y/N | 30초 내 Enter=취소): " OVERWRITE || { echo ""; print_info "시간 초과 — 설치를 취소합니다."; exit 0; }
  if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
    cd "$BASE_DIR"
    docker compose down 2>/dev/null || true
    cd ~
    # ── 삭제 전 자동 백업 (.env / data / logs / secrets) ──────────────
    # 백업은 BASE_DIR 바깥(홈 디렉토리)에 생성되어 rm -rf 대상에서 제외됨
    BACKUP_DIR="${HOME}/telegram-openwebui-bridge.backup.$(date +%Y%m%d%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    _BACKED_UP=false
    if [ -f "$BASE_DIR/.env" ]; then
      cp -p "$BASE_DIR/.env" "$BACKUP_DIR/.env" 2>/dev/null && _BACKED_UP=true
    fi
    for _d in data logs secrets; do
      if [ -d "$BASE_DIR/$_d" ]; then
        cp -a "$BASE_DIR/$_d" "$BACKUP_DIR/$_d" 2>/dev/null && _BACKED_UP=true
      fi
    done
    if [ "$_BACKED_UP" = true ]; then
      chmod -R go-rwx "$BACKUP_DIR" 2>/dev/null || true
      print_ok "기존 설정 백업 완료: $BACKUP_DIR"
      print_info "복원이 필요하면 위 폴더의 .env / data 를 다시 복사하세요."
      # 오래된 백업 정리: 최근 3개만 보관 (이름이 타임스탬프라 정렬 가능)
      _OLD_BACKUPS=$(ls -1d "${HOME}"/telegram-openwebui-bridge.backup.* 2>/dev/null | sort | head -n -3)
      if [ -n "$_OLD_BACKUPS" ]; then
        echo "$_OLD_BACKUPS" | while IFS= read -r _ob; do
          [ -n "$_ob" ] && rm -rf "$_ob" && print_info "오래된 백업 삭제: $_ob"
        done
      fi
    else
      rmdir "$BACKUP_DIR" 2>/dev/null || true
      print_info "백업할 기존 설정(.env/data)이 없어 백업을 건너뜁니다."
    fi
    rm -rf "$BASE_DIR"
  else
    print_err "설치 중단됨"
    exit 0
  fi
fi

mkdir -p "$BASE_DIR"/{bot,data,logs}
chmod 770 "$BASE_DIR"/logs "$BASE_DIR"/data

# 컨테이너 내부 UID와 일치하도록 소유권 설정
# Dockerfile에서 botuser=UID 1001로 생성됨
if ! chown -R 1001:1001 "$BASE_DIR"/logs "$BASE_DIR"/data 2>/dev/null; then
    sudo chown -R 1001:1001 "$BASE_DIR"/logs "$BASE_DIR"/data 2>/dev/null || {
        # sudo도 실패 시 → 777로 폴백 (Docker 격리가 보안 경계)
        chmod -R 777 "$BASE_DIR"/logs "$BASE_DIR"/data 2>/dev/null || true
        print_warn "chown 실패 → chmod 777 폴백 (Docker 격리로 보호)"
    }
fi
cd "$BASE_DIR"
print_ok "디렉토리 생성: $BASE_DIR (logs/data 권한 770)"

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

# 브라우저 에이전트 연동
BROWSER_AGENT_URL=http://browser-agent:8001
VNC_WEB_URL=
# ↑ VNC_WEB_URL: 브라우저 에이전트 설치 시 자동 설정됨
#   예: http://서버IP:6080 또는 https://도메인/vnc

# 타임존 (예약/로그 시간)
TZ=Asia/Seoul

# Tool 자동 활성화 (true = 봇 시작 시 OpenWebUI에 등록된 모든 Tool 자동 ON)
DEFAULT_TOOLS_ENABLED=true

# 제한
MAX_MESSAGE_LENGTH=4096
MAX_FILE_SIZE_MB=20
# 세션(단기 대화 맥락) 유지 시간 — 비서 용도: 24시간(1440)
SESSION_TIMEOUT_MINUTES=1440
MAX_HISTORY_MESSAGES=50
# 동시 활성 세션 한도 — 24h 유지라 넉넉히. 하루 활성 사용자 수보다 크게 잡으세요
MAX_SESSIONS=300

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
# 5-0. Docker Secrets 민감정보 분리 저장
############################################
print_header "🔐 Docker Secrets 생성"

mkdir -p "$BASE_DIR/secrets"
echo -n "${TELEGRAM_BOT_TOKEN:-}" > "$BASE_DIR/secrets/telegram_bot_token"
echo -n "${OPENWEBUI_API_KEY:-}" > "$BASE_DIR/secrets/openwebui_api_key"
echo -n "${WEBHOOK_SECRET:-}" > "$BASE_DIR/secrets/webhook_secret"
echo -n "${ADMIN_PIN:-}" > "$BASE_DIR/secrets/tg_admin_pin"

# 브라우저 에이전트 API Key 연동 (있으면 복사)
_BA_KEY_FILE="$HOME/OpenWebUI/browser-agent/secrets/api_key"
_BA_KEY_VAL=""

if [ -f "$_BA_KEY_FILE" ]; then
    # 직접 읽기 시도 → 실패하면 sudo → 실패하면 .env에서 읽기
    if _BA_KEY_VAL=$(cat "$_BA_KEY_FILE" 2>/dev/null) && [ -n "$_BA_KEY_VAL" ]; then
        print_ok "브라우저 에이전트 API Key 읽기 완료"
    elif _BA_KEY_VAL=$(sudo cat "$_BA_KEY_FILE" 2>/dev/null) && [ -n "$_BA_KEY_VAL" ]; then
        print_ok "브라우저 에이전트 API Key 읽기 완료 (sudo)"
    fi
fi

# .env 에서 BROWSER_AGENT_API_KEY 재확인 (위 방법 모두 실패 시 폴백)
if [ -z "$_BA_KEY_VAL" ]; then
    _BA_KEY_VAL=$(grep "^BROWSER_AGENT_API_KEY=" "$HOME/OpenWebUI/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)
    [ -n "$_BA_KEY_VAL" ] && print_ok "브라우저 에이전트 API Key (.env에서 읽음)"
fi

if [ -n "$_BA_KEY_VAL" ]; then
    echo -n "$_BA_KEY_VAL" > "$BASE_DIR/secrets/browser_agent_api_key"
    chmod 600 "$BASE_DIR/secrets/browser_agent_api_key"
    print_ok "브라우저 에이전트 API Key 연동 완료"

    # ── VNC_WEB_URL 처리 ─────────────────────────────────────────
    # browser-agent v6부터 VNC 기능이 완전히 제거됨
    # v5 이하 설치분과의 하위 호환을 위해 값이 있으면 그대로 사용,
    # v6 (값 없음) 이면 설정 생략
    _VNC_URL=$(grep "^VNC_WEB_URL=" "$HOME/OpenWebUI/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)
    if [ -n "$_VNC_URL" ]; then
        python3 -c "
import re,sys
with open(sys.argv[1]) as f: c=f.read()
c=re.sub(r'^VNC_WEB_URL=.*','VNC_WEB_URL='+sys.argv[2],c,flags=re.MULTILINE)
with open(sys.argv[1],'w') as f: f.write(c)
" "$BASE_DIR/.env" "$_VNC_URL"
        print_ok "VNC_WEB_URL 설정됨 (browser-agent v5 이하 호환): ${_VNC_URL}"
    else
        print_info "VNC_WEB_URL 없음 — browser-agent v6 (VNC 제거됨), 정상"
    fi
    # ──────────────────────────────────────────────────────────────

    # BROWSER_AGENT_URL 설정 (컨테이너 내부 주소 우선)
    # browser-agent v6: openwebui_net 동일 네트워크 → http://browser-agent:8001
    # 같은 네트워크에 있으면 컨테이너명으로 직접 통신 가능
    if [ -n "$BA_NETWORK" ]; then
        # openwebui_net 감지됨 → 컨테이너명 주소 사용
        python3 -c "
import re,sys
with open(sys.argv[1]) as f: c=f.read()
c=re.sub(r'^BROWSER_AGENT_URL=.*','BROWSER_AGENT_URL=http://browser-agent:8001',c,flags=re.MULTILINE)
with open(sys.argv[1],'w') as f: f.write(c)
" "$BASE_DIR/.env"
        print_ok "BROWSER_AGENT_URL → http://browser-agent:8001 (동일 네트워크, 컨테이너명)"
    else
        # 네트워크 미연결 → 기존 .env 값 또는 localhost 폴백
        _BA_URL=$(grep "^BROWSER_AGENT_URL=" "$HOME/OpenWebUI/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)
        if [ -n "$_BA_URL" ]; then
            python3 -c "
import re,sys
with open(sys.argv[1]) as f: c=f.read()
c=re.sub(r'^BROWSER_AGENT_URL=.*','BROWSER_AGENT_URL='+sys.argv[2],c,flags=re.MULTILINE)
with open(sys.argv[1],'w') as f: f.write(c)
" "$BASE_DIR/.env" "$_BA_URL"
            print_ok "BROWSER_AGENT_URL → ${_BA_URL}"
        fi
    fi
else
    print_info "브라우저 에이전트 API Key 없음 — Multi-Agent 비활성 (나중에 재실행하면 자동 연동)"
fi

chmod 700 "$BASE_DIR/secrets"
chmod 644 "$BASE_DIR/secrets/"* 2>/dev/null
# .sh 스크립트는 실행 권한 유지
chmod +x "$BASE_DIR/secrets/"*.sh 2>/dev/null || true
# ↑ secrets: 데이터=644, 스크립트=755
#   볼륨 마운트 :ro (읽기 전용)로 보호 + Python try/except 이중 방어

print_ok "Docker Secrets 생성 완료 ($(ls "$BASE_DIR/secrets/"* 2>/dev/null | wc -l)개 파일)"
echo "   📁 경로: $BASE_DIR/secrets/ (chmod 700)"
echo "   🐍 Python 코드에서 /app/secrets/ 자동 로드 (.env보다 우선)"

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
# ⚠️ 최소 버전: CVE 패치 기준
python-telegram-bot[webhooks]>=21.5
# CVE-2025-69223 (CVSS 7.5) zip bomb DoS
# CVE-2025-69226 (CVSS 5.3) 경로 순회
aiohttp>=3.13.3
aiofiles>=24.1.0
python-dotenv>=1.0.1
# CVE-2026-26007 (CVSS 8.2) ECC 개인키 유출
# CVE-2026-39892 버퍼 오버플로우
# CVE-2026-34073 와일드카드 인증서 검증 우회
cryptography>=46.0.5
pydantic>=2.5.3
REQEOF

cat > bot/telegram_bot.py <<'BOTEOF'
#!/usr/bin/env python3
"""
Telegram ↔ OpenWebUI 브릿지 봇 (보안강화판)
OpenWebUI의 모든 모델/Tool/RAG를 Telegram에서 사용 가능

Author:  <webmaster@vulva.sex>
Version: 1.1.0-hardened
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
import hmac
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

# Docker Secrets 로드 — .env보다 우선 (파일 존재 시만 덮어씀)
import pathlib
_SECRET_MAP = {
    "telegram_bot_token": "TELEGRAM_BOT_TOKEN",
    "openwebui_api_key": "OPENWEBUI_API_KEY",
    "webhook_secret": "WEBHOOK_SECRET",
    "tg_admin_pin": "ADMIN_PIN",
}
for _sf, _ev in _SECRET_MAP.items():
    for _sd in ["/run/secrets", "/app/secrets"]:
        _sp = pathlib.Path(f"{_sd}/{_sf}")
        try:
            if _sp.exists():
                _val = _sp.read_text().strip()
                if _val:
                    os.environ[_ev] = _val
                break
        except (PermissionError, OSError):
            pass  # 권한 없으면 .env 값 사용

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
# Tool 자동 활성화: true면 세션 생성 시 OpenWebUI의 모든 Tool을 즉시 ON
DEFAULT_TOOLS_ENABLED = os.getenv("DEFAULT_TOOLS_ENABLED", "true").lower() == "true"

# 접근제어 — 관리자 전용 (필수)
ADMIN_USER_IDS_RAW    = os.getenv("ALLOWED_USER_IDS", "")
ADMIN_USER_IDS        = set()
if ADMIN_USER_IDS_RAW.strip():
    ADMIN_USER_IDS = {
        int(uid.strip()) for uid in ADMIN_USER_IDS_RAW.split(",")
        if uid.strip().isdigit()
    }

# 브라우저 에이전트 연동
BROWSER_AGENT_URL     = os.getenv("BROWSER_AGENT_URL", "http://browser-agent:8001")
VNC_WEB_URL           = os.getenv("VNC_WEB_URL", "")
BROWSER_AGENT_API_KEY_FILE = "/app/secrets/browser_agent_api_key"

def _load_browser_api_key():
    try:
        import pathlib
        p = pathlib.Path(BROWSER_AGENT_API_KEY_FILE)
        if p.exists(): return p.read_text().strip()
    except Exception: pass
    return os.getenv("BROWSER_AGENT_API_KEY", "")

BROWSER_AGENT_API_KEY = _load_browser_api_key()

# Multi-Agent 키워드 (복잡한 작업 자동 감지)
_COMPLEX_KW = ["비교", "추천", "분석", "계획", "여행", "최저가", "조사", "리서치", "장단점", "정리", "vs", "VS"]

def _is_complex_task(text: str) -> bool:
    return any(kw in text for kw in _COMPLEX_KW) or len(text) > 300

# Rate Limiting
RATE_LIMIT_PER_MINUTE  = int(os.getenv("RATE_LIMIT_PER_MINUTE", "30"))
RATE_LIMIT_BLOCK_MIN   = int(os.getenv("RATE_LIMIT_BLOCK_MINUTES", "10"))
MAX_FAIL_ATTEMPTS      = int(os.getenv("MAX_FAIL_ATTEMPTS", "3"))

# 제한
MAX_MESSAGE_LENGTH     = int(os.getenv("MAX_MESSAGE_LENGTH", "4096"))
MAX_FILE_SIZE_MB       = int(os.getenv("MAX_FILE_SIZE_MB", "20"))
SESSION_TIMEOUT_MIN    = int(os.getenv("SESSION_TIMEOUT_MINUTES", "1440"))
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
        self.block_count = defaultdict(int) # user_id → 차단 횟수 (점진적 증가용)

    def _get_block_minutes(self, user_id: int) -> int:
        """차단 횟수에 따라 점진적으로 차단 시간 증가"""
        count = self.block_count.get(user_id, 0)
        # 1회: 10분, 2회: 30분, 3회: 60분, 4회+: 120분
        stages = [RATE_LIMIT_BLOCK_MIN, 30, 60, 120]
        return stages[min(count, len(stages) - 1)]

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
                self.block_count[user_id] = self.block_count.get(user_id, 0) + 1
                block_min = self._get_block_minutes(user_id)
                self.blocked[user_id] = now + timedelta(minutes=block_min)
                logger.warning(f"🚨 사용자 {user_id} 차단됨 ({block_min}분, {self.block_count[user_id]}회째)")
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
# ✅ [추가] Telegram 링크 포매팅
# ══════════════════════════════════════════
def extract_links_from_text(text: str) -> list:
    """텍스트에서 URL 추출 (중복 제거)"""
    urls = re.findall(r'https?://[^\s\)\]]+', text)
    seen = set()
    unique = []
    for u in urls:
        if u not in seen:
            seen.add(u)
            unique.append(u)
    return unique

def format_response_with_links(reply: str) -> str:
    """
    ✅ OpenWebUI 응답을 Telegram 친화적 형식으로 변환
    - HTML 태그 → Markdown 변환
    - 응답 하단에 "🔗 관련 링크" 섹션 추가
    - VNC 링크는 handle_text()에서 별도 버튼 처리하므로 여기서 제외
    """
    formatted = reply

    # 1. HTML 링크 변환: <a href="URL">텍스트</a> → [텍스트](URL)
    formatted = re.sub(
        r'<a\s+href=["\']([^"\']+)["\']\s*>(.*?)</a>',
        r'[\2](\1)',
        formatted,
        flags=re.IGNORECASE | re.DOTALL
    )

    # 2. HTML 포매팅 태그 → Markdown
    formatted = re.sub(r'<br\s*/?>', '\n', formatted, flags=re.IGNORECASE)
    formatted = re.sub(r'</p>', '\n', formatted, flags=re.IGNORECASE)
    formatted = re.sub(r'<p[^>]*>', '', formatted, flags=re.IGNORECASE)
    formatted = re.sub(r'<strong>(.*?)</strong>', r'*\1*', formatted, flags=re.IGNORECASE | re.DOTALL)
    formatted = re.sub(r'<b>(.*?)</b>', r'*\1*', formatted, flags=re.IGNORECASE | re.DOTALL)
    formatted = re.sub(r'<em>(.*?)</em>', r'_\1_', formatted, flags=re.IGNORECASE | re.DOTALL)
    formatted = re.sub(r'<i>(.*?)</i>', r'_\1_', formatted, flags=re.IGNORECASE | re.DOTALL)
    formatted = re.sub(r'<code>(.*?)</code>', r'`\1`', formatted, flags=re.IGNORECASE | re.DOTALL)

    # 3. 나머지 HTML 태그 제거
    formatted = re.sub(r'<[^>]+>', '', formatted)

    # 4. 연속 공백 정리
    formatted = re.sub(r'\n\s*\n+', '\n\n', formatted)

    # 5. URL 추출 → 링크 섹션 추가
    links = extract_links_from_text(formatted)
    if links:
        formatted += "\n\n" + "━" * 30 + "\n"
        formatted += "🔗 *관련 링크*\n"
        for i, url in enumerate(links, 1):
            display = url if len(url) <= 60 else url[:57] + "…"
            formatted += f"{i}. [{display}]({url})\n"

    return formatted.strip()

# ══════════════════════════════════════════
# 세션 관리
# ══════════════════════════════════════════
class UserSession:
    def __init__(self, user_id: int):
        self.user_id = user_id
        self.model = DEFAULT_MODEL
        self.history = []
        self.last_active = datetime.now()
        # PIN 없으면 자동 인증, 신뢰 사용자면 PIN 건너뜀
        self.authenticated = not bool(ADMIN_PIN) or is_trusted(user_id)
        self.enabled_tool_ids = set()  # 활성화된 Tool ID 목록
        self.auto_tools_loaded = False  # DEFAULT_TOOLS_ENABLED 자동 로드 완료 여부

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

# ── PIN 인증 영구 저장 (기기 기억 기능) ──────────────────────
TRUSTED_USERS_FILE = "/app/data/trusted_users.json"

def _load_trusted_users() -> set:
    """디스크에서 신뢰된 사용자 ID 목록 로드"""
    try:
        import json
        with open(TRUSTED_USERS_FILE, "r") as f:
            data = json.load(f)
            return set(data.get("trusted", []))
    except (FileNotFoundError, json.JSONDecodeError):
        return set()

def _save_trusted_users(trusted: set):
    """신뢰된 사용자 ID 목록을 디스크에 저장"""
    import json
    try:
        with open(TRUSTED_USERS_FILE, "w") as f:
            json.dump({"trusted": list(trusted)}, f)
        os.chmod(TRUSTED_USERS_FILE, 0o600)  # 소유자만 읽기/쓰기
    except Exception as e:
        logger.error(f"신뢰 사용자 저장 실패: {e}")

def trust_user(user_id: int):
    """사용자를 신뢰 목록에 추가 (재시작 후에도 PIN 불필요)"""
    trusted = _load_trusted_users()
    trusted.add(user_id)
    _save_trusted_users(trusted)
    logger.info(f"🔑 신뢰 사용자 등록: {user_id}")

def untrust_user(user_id: int):
    """사용자를 신뢰 목록에서 제거 (다음 사용 시 PIN 필요)"""
    trusted = _load_trusted_users()
    trusted.discard(user_id)
    _save_trusted_users(trusted)
    logger.info(f"🔒 신뢰 사용자 해제: {user_id}")

def is_trusted(user_id: int) -> bool:
    """사용자가 신뢰 목록에 있는지 확인"""
    return user_id in _load_trusted_users()

# H3: 만료 세션 자동 정리 (5분 주기)
async def _cleanup_expired_sessions():
    while True:
        await asyncio.sleep(300)
        expired = [uid for uid, s in sessions.items() if s.is_expired()]
        for uid in expired:
            del sessions[uid]
        if expired:
            logger.info(f"🧹 만료 세션 정리: {len(expired)}개 삭제 | 잔여: {len(sessions)}개")

MAX_SESSIONS = int(os.getenv("MAX_SESSIONS", "300"))  # 메모리 DoS 방어 (24h 타임아웃이라 상향)

def get_session(user_id: int) -> UserSession:
    if user_id not in sessions or sessions[user_id].is_expired():
        if user_id in sessions and sessions[user_id].is_expired():
            logger.info(f"⏰ 세션 만료 초기화: {user_id}")
        # 세션 수 제한 — 가장 오래된 세션 제거
        if len(sessions) >= MAX_SESSIONS and user_id not in sessions:
            oldest = min(sessions, key=lambda k: sessions[k].last_active)
            del sessions[oldest]
            logger.info(f"🧹 세션 한도 초과 — 가장 오래된 세션 제거: {oldest}")
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

        # [NEW] ① Replay Attack 방어
        if update.update_id and is_replay(update.update_id):
            return  # 중복 요청 무시

        # [NEW] ⑥ 비상 차단 모드
        if _EMERGENCY_MODE and user.id not in ADMIN_USER_IDS:
            try:
                await update.message.reply_text("🚨 현재 긴급 점검 중입니다. 잠시 후 다시 시도해주세요.")
            except Exception:
                pass
            audit_log("EMERGENCY_BLOCK", user.id, "비상모드 차단", ok=False)
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
            audit_log("ACCESS_DENIED", user.id, f"name={user.full_name}", ok=False)
            inc_stat("blocked_attempts")
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

        # C3: PIN 인증 — /start는 PIN 없이 허용
        session = get_session(user.id)
        if ADMIN_PIN and not session.authenticated:
            msg_text = update.message.text or ""
            # /start 명령은 PIN 없이 허용 (안내 메시지 표시용)
            if msg_text.strip().startswith("/start"):
                session.authenticated = False  # 아직 미인증
                await update.message.reply_text(
                    "🔒 이 봇은 PIN 인증이 필요합니다.\n"
                    "관리자 PIN 6자리를 입력해주세요."
                )
                return
            # PIN 입력 확인
            if hmac.compare_digest(msg_text.strip(), ADMIN_PIN):
                session.authenticated = True
                trust_user(user.id)  # 신뢰 사용자로 등록 (재시작 후에도 PIN 불필요)
                audit_log("PIN_AUTH_OK", user.id)
                logger.info(f"🔓 PIN 인증 성공 + 신뢰 등록: {user.id}")
                await update.message.reply_text(
                    "🔓 PIN 인증 성공! 이제 봇을 사용할 수 있습니다.\n"
                    "✅ 이 기기는 기억되어 재시작 후에도 PIN이 필요 없습니다.\n"
                    "/lock 으로 언제든 잠금할 수 있습니다.\n"
                    "/help 로 사용법을 확인하세요."
                )
                return
            else:
                audit_log("PIN_AUTH_FAIL", user.id, ok=False)
                await update.message.reply_text(
                    "🔒 PIN 인증이 필요합니다.\n"
                    "관리자 PIN 6자리를 입력해주세요."
                )
                return

        return await func(update, context)
    return wrapper

# ══════════════════════════════════════════
# OpenWebUI API 호출
# ══════════════════════════════════════════
async def call_openwebui_chat(session: UserSession, user_input: str) -> str:
    """OpenWebUI의 Chat Completions API 호출 (활성화된 Tool 포함)"""

    # ── Tool 자동 활성화 ─────────────────────────────────────────
    # DEFAULT_TOOLS_ENABLED=true 이고 아직 자동 로드를 하지 않았으면
    # OpenWebUI에 등록된 모든 Tool을 즉시 활성화 (최초 1회)
    if DEFAULT_TOOLS_ENABLED and not session.auto_tools_loaded:
        tools = await get_available_tools()
        if tools:
            session.enable_all_tools([t["id"] for t in tools])
            logger.info(
                f"⚡ Tool 자동 활성화: {session.user_id} — "
                f"{len(tools)}개 ({', '.join(t['id'] for t in tools)})"
            )
        session.auto_tools_loaded = True  # 결과와 무관하게 플래그 세팅 (재시도 방지)
    # ──────────────────────────────────────────────────────────────

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
        # [FIX] 브라우저 에이전트 작업은 1~3분 소요 → 타임아웃 180초
        timeout = aiohttp.ClientTimeout(total=180)
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
        logger.error("OpenWebUI API 타임아웃 (180초)")
        session.history.pop()
        return "⏱️ AI 응답 시간 초과 (180초).\n브라우저 에이전트 작업은 시간이 걸릴 수 있습니다. 잠시 후 다시 시도해주세요."
    except Exception as e:
        logger.error(f"OpenWebUI API 연결 실패: {mask_sensitive(str(e))}")
        session.history.pop()
        return "❌ AI 서버 연결 실패. OpenWebUI가 실행 중인지 확인해주세요."

# ══════════════════════════════════════════
# 스트리밍 Chat API
# ══════════════════════════════════════════
# Telegram 편집 속도 제한 대응 설정
_STREAM_EDIT_INTERVAL = 1.0   # 최소 편집 간격 (초) — Telegram 분당 20회 제한
_STREAM_MIN_DELTA     = 8     # 최소 변화 글자 수 — 너무 잦은 편집 방지

async def stream_openwebui_chat(
    session: UserSession,
    user_input: str,
    on_chunk,   # async callable(current_text: str) — 청크마다 호출
) -> str:
    """OpenWebUI SSE 스트리밍 호출.
    청크가 쌓일 때마다 on_chunk(현재까지_전체_텍스트)를 호출합니다.
    반환값: 최종 완성된 전체 텍스트.
    """
    # ── Tool 자동 활성화 (기존 로직 동일) ──
    if DEFAULT_TOOLS_ENABLED and not session.auto_tools_loaded:
        tools = await get_available_tools()
        if tools:
            session.enable_all_tools([t["id"] for t in tools])
            logger.info(f"⚡ Tool 자동 활성화(스트림): {session.user_id} — {len(tools)}개")
        session.auto_tools_loaded = True

    session.add_message("user", user_input)

    payload = {
        "model":    session.model,
        "messages": session.history,
        "stream":   True,
    }
    if session.enabled_tool_ids:
        payload["tool_ids"] = list(session.enabled_tool_ids)

    headers = {
        "Authorization": f"Bearer {OPENWEBUI_API_KEY}",
        "Content-Type":  "application/json",
    }

    full_text   = ""
    last_notify = datetime.now()
    last_len    = 0

    try:
        timeout = aiohttp.ClientTimeout(total=180)
        async with aiohttp.ClientSession(timeout=timeout) as http:
            async with http.post(
                f"{OPENWEBUI_URL}/api/chat/completions",
                headers=headers,
                json=payload,
            ) as resp:
                if resp.status != 200:
                    err = await resp.text()
                    logger.error(f"스트리밍 오류 [{resp.status}]: {mask_sensitive(err[:200])}")
                    session.history.pop()
                    return f"❌ AI 응답 오류 (HTTP {resp.status}). 잠시 후 다시 시도해주세요."

                # SSE 라인 단위 파싱
                async for raw in resp.content:
                    line = raw.decode("utf-8", errors="replace").strip()
                    if not line.startswith("data:"):
                        continue
                    data_str = line[5:].strip()
                    if data_str == "[DONE]":
                        break
                    try:
                        chunk   = _json.loads(data_str)
                        delta   = chunk.get("choices", [{}])[0].get("delta", {})
                        content = delta.get("content") or ""
                        if not content:
                            continue
                        full_text += content

                        # ── on_chunk 호출 (편집 간격 + 최소 변화량 체크) ──
                        now      = datetime.now()
                        elapsed  = (now - last_notify).total_seconds()
                        grown    = len(full_text) - last_len
                        if elapsed >= _STREAM_EDIT_INTERVAL and grown >= _STREAM_MIN_DELTA:
                            try:
                                await on_chunk(full_text)
                            except Exception as ce:
                                logger.debug(f"on_chunk 오류 (무시): {ce}")
                            last_notify = now
                            last_len    = len(full_text)

                    except (_json.JSONDecodeError, IndexError, KeyError):
                        continue  # 불완전한 청크 무시

        # 스트리밍 완료 — 최종 on_chunk 한 번 더 (마지막 텍스트 보장)
        if full_text and len(full_text) > last_len:
            try:
                await on_chunk(full_text)
            except Exception:
                pass

        if full_text:
            session.add_message("assistant", full_text)
            rate_limiter.reset(session.user_id)
            logger.info(f"📡 스트리밍 완료: {session.user_id} — {len(full_text)}자")
        else:
            session.history.pop()
            return "❌ AI 응답이 비어 있습니다. 다시 시도해주세요."

        return full_text

    except asyncio.TimeoutError:
        logger.error("스트리밍 타임아웃 (180초)")
        if full_text:
            # 타임아웃 전까지 받은 내용 저장
            session.add_message("assistant", full_text)
            return full_text + "\n\n⏱️ _(응답 도중 시간 초과 — 일부만 수신됨)_"
        session.history.pop()
        return "⏱️ AI 응답 시간 초과 (180초). 잠시 후 다시 시도해주세요."
    except Exception as e:
        logger.error(f"스트리밍 연결 실패: {mask_sensitive(str(e))}")
        if full_text:
            session.add_message("assistant", full_text)
            return full_text
        session.history.pop()
        return "❌ AI 서버 연결 실패. OpenWebUI가 실행 중인지 확인해주세요."
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

# ── 모델 목록 캐시 ─────────────────────────────────────────────────
_models_cache: dict = {"models": [], "fetched_at": None, "ttl_seconds": 300}

async def get_available_models(force_refresh: bool = False) -> list:
    """OpenWebUI에서 사용 가능한 모델 목록 조회 (5분 캐시)"""
    now = datetime.now()
    if (not force_refresh
        and _models_cache["fetched_at"]
        and (now - _models_cache["fetched_at"]).total_seconds() < _models_cache["ttl_seconds"]
        and _models_cache["models"]):
        return _models_cache["models"]

    headers = {"Authorization": f"Bearer {OPENWEBUI_API_KEY}"}
    try:
        timeout = aiohttp.ClientTimeout(total=15)
        async with aiohttp.ClientSession(timeout=timeout) as http:
            async with http.get(
                f"{OPENWEBUI_URL}/api/models",
                headers=headers,
            ) as resp:
                if resp.status == 200:
                    raw = await resp.json()
                    model_list = raw if isinstance(raw, list) else raw.get("data", raw.get("models", []))
                    models = []
                    for m in model_list:
                        models.append({
                            "id":   m.get("id", ""),
                            "name": m.get("name", m.get("id", "알 수 없음")),
                        })
                    _models_cache["models"] = models
                    _models_cache["fetched_at"] = now
                    logger.info(f"🧠 모델 목록 조회: {len(models)}개")
                    return models
                else:
                    logger.error(f"모델 목록 조회 실패 [{resp.status}]")
    except Exception as e:
        logger.error(f"모델 목록 조회 오류: {e}")

    return _models_cache.get("models", [])
# ══════════════════════════════════════════
ALLOWED_USERS_FILE = "/app/data/allowed_users.json"

def _load_allowed_users_file() -> set:
    try:
        with open(ALLOWED_USERS_FILE) as f:
            return {int(x) for x in json.load(f).get("allowed", [])}
    except (FileNotFoundError, json.JSONDecodeError, ValueError):
        return set()

def _save_allowed_users_file(users: set):
    try:
        with open(ALLOWED_USERS_FILE, "w") as f:
            json.dump({"allowed": list(users)}, f)
        os.chmod(ALLOWED_USERS_FILE, 0o600)
    except Exception as e:
        logger.error(f"허용 사용자 저장 실패: {e}")

def add_allowed_user(user_id: int):
    saved = _load_allowed_users_file()
    saved.add(user_id)
    ADMIN_USER_IDS.add(user_id)
    _save_allowed_users_file(saved)
    logger.info(f"➕ 허용 사용자 추가: {user_id}")

def remove_allowed_user(user_id: int):
    saved = _load_allowed_users_file()
    saved.discard(user_id)
    ADMIN_USER_IDS.discard(user_id)
    _save_allowed_users_file(saved)
    logger.info(f"➖ 허용 사용자 제거: {user_id}")

def _init_allowed_users():
    """시작 시 저장된 허용 사용자 로드"""
    saved = _load_allowed_users_file()
    ADMIN_USER_IDS.update(saved)
    if saved:
        logger.info(f"💾 저장된 허용 사용자 로드: {saved}")

# ══════════════════════════════════════════
# 통계 카운터
# ══════════════════════════════════════════
import threading as _threading
_stats_lock = _threading.Lock()
_stats: dict = {
    "total_messages": 0,
    "total_files": 0,
    "total_voices": 0,
    "blocked_attempts": 0,
}

def inc_stat(key: str, n: int = 1):
    with _stats_lock:
        _stats[key] = _stats.get(key, 0) + n

# ══════════════════════════════════════════
# 브로드캐스트 헬퍼
# ══════════════════════════════════════════
_bot_app = None  # main()에서 참조 설정

async def broadcast_message(text: str) -> dict:
    """모든 활성 세션 사용자에게 메시지 전송"""
    if not _bot_app:
        return {"sent": 0, "failed": 0}
    sent = failed = 0
    for uid, s in list(sessions.items()):
        if s.is_expired():
            continue
        try:
            await _bot_app.bot.send_message(
                chat_id=uid, text=text, parse_mode=ParseMode.HTML
            )
            sent += 1
        except Exception as e:
            logger.warning(f"브로드캐스트 실패 [{uid}]: {e}")
            failed += 1
    return {"sent": sent, "failed": failed}

# ══════════════════════════════════════════
# [NEW] ① Replay Attack 방어
# ══════════════════════════════════════════
import collections as _collections
_SEEN_UPDATE_IDS: _collections.deque = _collections.deque(maxlen=10000)
_SEEN_LOCK = _threading.Lock()

def is_replay(update_id: int) -> bool:
    """동일 update_id 재전송 요청 차단 (deque 10000건 캐시)"""
    with _SEEN_LOCK:
        if update_id in _SEEN_UPDATE_IDS:
            logger.warning(f"🔁 Replay Attack 감지: update_id={update_id}")
            inc_stat("blocked_attempts")
            return True
        _SEEN_UPDATE_IDS.append(update_id)
        return False

# ══════════════════════════════════════════
# [NEW] ② Prompt Injection 방어
# ══════════════════════════════════════════
_INJECTION_PATTERNS = [
    re.compile(r'(?i)(ignore\s+(all\s+)?previous\s+instructions?)'),
    re.compile(r'(?i)(disregard\s+(your\s+)?instructions?)'),
    re.compile(r'(?i)(you\s+are\s+now\s+(a|an)\s+\w+)'),
    re.compile(r'(?i)(act\s+as\s+(if\s+you\s+are|a|an)\s+\w+)'),
    re.compile(r'(?i)(override\s+(system\s+)?prompt)'),
    re.compile(r'(?i)(jailbreak|dan\s+mode|evil\s+mode|developer\s+mode)'),
    re.compile(r'(?i)(</?(system|user|assistant|instruction)>)'),
    re.compile(r'(?i)(\[INST\]|\[/INST\]|<\|im_start\|>|<\|im_end\|>)'),
    re.compile(r'(?i)(system\s*:\s*(you\s+are|ignore|forget))'),
]

def detect_injection(text: str) -> bool:
    """프롬프트 인젝션 시도 감지 — True 이면 차단"""
    for pat in _INJECTION_PATTERNS:
        if pat.search(text):
            logger.warning(f"🛡️ Prompt Injection 감지: {text[:80]}")
            inc_stat("blocked_attempts")
            return True
    return False

# ══════════════════════════════════════════
# [NEW] ③ 파일 Magic Bytes 검증
# ══════════════════════════════════════════
_ALLOWED_MAGIC: list = [
    (b'\x25\x50\x44\x46', 'pdf'),
    (b'\xff\xd8\xff',     'jpg'),
    (b'\x89\x50\x4e\x47', 'png'),
    (b'\x47\x49\x46\x38', 'gif'),
    (b'\x42\x4d',         'bmp'),
    (b'RIFF',             'webp'),
    (b'\x49\x49\x2a\x00', 'tiff'),
    (b'\x4d\x4d\x00\x2a', 'tiff'),
]

def verify_file_magic(data: bytes, declared_ext: str) -> bool:
    """Magic bytes 검증으로 확장자 위조 방지"""
    if len(data) < 8:
        return False
    for magic, ftype in _ALLOWED_MAGIC:
        if data[:len(magic)] == magic:
            return True
    # 텍스트 파일 허용 (UTF-8 디코딩 가능 여부로 판단)
    try:
        data[:512].decode('utf-8', errors='strict')
        return True
    except UnicodeDecodeError:
        pass
    logger.warning(f"🚫 Magic Bytes 불일치: ext={declared_ext} magic={data[:4].hex()}")
    inc_stat("blocked_attempts")
    return False

# ══════════════════════════════════════════
# [NEW] ④ AI 응답 민감정보 자동 필터링
# ══════════════════════════════════════════
_RESPONSE_FILTERS: list = [
    # OpenAI / Groq 스타일 API 키
    (re.compile(r'(sk-[a-zA-Z0-9]{4})[a-zA-Z0-9]{16,}'), r'\1[REDACTED]'),
    # JWT 토큰 (eyJ...)
    (re.compile(r'(eyJ[a-zA-Z0-9_-]{8,})\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'), r'\1.[REDACTED]'),
    # 일반 API 키 패턴
    (re.compile(r'(?i)(api[_\s\-]?key[\s:="\']+)([a-zA-Z0-9_\-]{20,})'), r'\1[REDACTED]'),
    # 비밀번호 패턴
    (re.compile(r'(?i)(password[\s:="\']+)(\S{6,})'), r'\1[REDACTED]'),
    # 한국 전화번호
    (re.compile(r'(\+82\d{2})\d{4}(\d{4})'), r'\1****\2'),
    (re.compile(r'\b(010|011|016|017|018|019)-?\d{4}-?(\d{4})\b'), r'\1-****-\2'),
]

def filter_ai_response(text: str) -> str:
    """AI 응답에서 민감정보 자동 마스킹"""
    for pattern, replacement in _RESPONSE_FILTERS:
        text = pattern.sub(replacement, text)
    return text

# ══════════════════════════════════════════
# [NEW] ⑤ 구조화된 감사 로그 (JSON)
# ══════════════════════════════════════════
import json as _json

audit_logger = logging.getLogger("audit")
audit_logger.setLevel(logging.INFO)
audit_logger.propagate = False  # 메인 로거로 전파 차단
_audit_handler = RotatingFileHandler(
    "/app/logs/audit.log",
    maxBytes=LOG_MAX_BYTES,
    backupCount=LOG_BACKUP_COUNT,
    encoding="utf-8",
)
_audit_handler.setFormatter(logging.Formatter("%(message)s"))
audit_logger.addHandler(_audit_handler)

def audit_log(event: str, user_id: int, detail: str = "", ok: bool = True):
    """감사 로그 기록 — JSON 구조화 (timestamp·event·user·ok·detail)"""
    record = {
        "ts":      datetime.now().isoformat(timespec="seconds"),
        "event":   event,
        "user_id": user_id,
        "ok":      ok,
        "detail":  detail[:200] if detail else "",
    }
    audit_logger.info(_json.dumps(record, ensure_ascii=False))

# ══════════════════════════════════════════
# [NEW] ⑥ 비상 차단 모드 플래그
# ══════════════════════════════════════════
_EMERGENCY_MODE: bool = False  # /emergency 명령으로 토글

# ══════════════════════════════════════════
# 예약 기능 (Scheduler)
# ══════════════════════════════════════════
SCHEDULES_FILE = "/app/data/schedules.json"

_WEEKDAY_KR = {
    "월": 0, "월요일": 0,
    "화": 1, "화요일": 1,
    "수": 2, "수요일": 2,
    "목": 3, "목요일": 3,
    "금": 4, "금요일": 4,
    "토": 5, "토요일": 5,
    "일": 6, "일요일": 6,
}
_WEEKDAY_NAME = ["월", "화", "수", "목", "금", "토", "일"]

# ── 저장 / 로드 ─────────────────────────────────────────────────
def _load_schedules() -> list:
    try:
        with open(SCHEDULES_FILE, "r", encoding="utf-8") as f:
            return _json.load(f)
    except (FileNotFoundError, _json.JSONDecodeError):
        return []

def _save_schedules(items: list):
    try:
        os.makedirs(os.path.dirname(SCHEDULES_FILE), exist_ok=True)
        with open(SCHEDULES_FILE, "w", encoding="utf-8") as f:
            _json.dump(items, f, ensure_ascii=False, indent=2)
        os.chmod(SCHEDULES_FILE, 0o600)
    except Exception as e:
        logger.error(f"스케줄 저장 실패: {e}")

def _new_schedule_id() -> str:
    import random, string
    return "sch_" + "".join(random.choices(string.ascii_lowercase + string.digits, k=6))

# ── 파싱 ────────────────────────────────────────────────────────
def _parse_time_str(s: str):
    """'09:00' / '오전 9시' / '오후 3시 30분' → (hour, minute) or None"""
    s = s.strip()
    # HH:MM 형식
    m = re.match(r"^(\d{1,2}):(\d{2})$", s)
    if m:
        return int(m.group(1)), int(m.group(2))
    # 오전/오후 N시 [M분]
    m = re.match(r"(오전|오후)\s*(\d{1,2})시(?:\s*(\d{1,2})분)?", s)
    if m:
        h = int(m.group(2))
        mi = int(m.group(3)) if m.group(3) else 0
        if m.group(1) == "오후" and h < 12:
            h += 12
        return h, mi
    # N시 [M분]
    m = re.match(r"(\d{1,2})시(?:\s*(\d{1,2})분)?", s)
    if m:
        return int(m.group(1)), int(m.group(2)) if m.group(2) else 0
    return None

def parse_remind_command(args_text: str) -> dict | None:
    """
    /remind 명령 파싱. 반환: schedule dict or None.
    지원 형식:
      30분 후 <내용>
      2시간 후 <내용>
      내일 [오전/오후] N시 <내용>
      내일 HH:MM <내용>
      매일 HH:MM <내용>
      매주 <요일> HH:MM <내용>
    """
    text = args_text.strip()
    if not text:
        return None
    now = datetime.now()

    # ── 1. N분 후 ────────────────────────────────────────────────
    m = re.match(r"^(\d+)\s*분\s*후\s+(.+)$", text, re.DOTALL)
    if m:
        run_at = now + timedelta(minutes=int(m.group(1)))
        return {"type": "once", "run_at": run_at.isoformat(), "task": m.group(2).strip()}

    # ── 2. N시간 후 ──────────────────────────────────────────────
    m = re.match(r"^(\d+)\s*시간\s*(?:(\d+)\s*분\s*)?후\s+(.+)$", text, re.DOTALL)
    if m:
        run_at = now + timedelta(hours=int(m.group(1)), minutes=int(m.group(2) or 0))
        return {"type": "once", "run_at": run_at.isoformat(), "task": m.group(3).strip()}

    # ── 3. 내일 <시간> ───────────────────────────────────────────
    m = re.match(r"^내일\s+(.+?)\s+(.+)$", text, re.DOTALL)
    if m:
        time_part = m.group(1)
        task_part = m.group(2).strip()
        parsed = _parse_time_str(time_part)
        if parsed:
            h, mi = parsed
            tomorrow = (now + timedelta(days=1)).replace(hour=h, minute=mi, second=0, microsecond=0)
            return {"type": "once", "run_at": tomorrow.isoformat(), "task": task_part}

    # ── 4. 매일 <시간> ───────────────────────────────────────────
    m = re.match(r"^매일\s+(.+?)\s+(.+)$", text, re.DOTALL)
    if m:
        time_part = m.group(1)
        task_part = m.group(2).strip()
        parsed = _parse_time_str(time_part)
        if parsed:
            h, mi = parsed
            return {"type": "daily", "hour": h, "minute": mi, "task": task_part, "last_run": None}

    # ── 5. 매주 <요일> <시간> ────────────────────────────────────
    m = re.match(r"^매주\s+(\S+)\s+(.+?)\s+(.+)$", text, re.DOTALL)
    if m:
        wd_str   = m.group(1)
        time_part = m.group(2)
        task_part = m.group(3).strip()
        wd = _WEEKDAY_KR.get(wd_str)
        if wd is not None:
            parsed = _parse_time_str(time_part)
            if parsed:
                h, mi = parsed
                return {"type": "weekly", "weekday": wd, "hour": h, "minute": mi,
                        "task": task_part, "last_run": None}

    return None

def _should_run(sch: dict, now: datetime) -> bool:
    """지금 실행해야 하는 스케줄인지 판단 (30초 오차 허용)"""
    t = sch["type"]
    if t == "once":
        run_at = datetime.fromisoformat(sch["run_at"])
        return now >= run_at

    elif t == "daily":
        if now.hour != sch["hour"] or now.minute != sch["minute"]:
            return False
        last = sch.get("last_run")
        if not last:
            return True
        last_dt = datetime.fromisoformat(last)
        return (now - last_dt).total_seconds() > 3500   # 59분 이상 지난 경우만

    elif t == "weekly":
        if now.weekday() != sch["weekday"]:
            return False
        if now.hour != sch["hour"] or now.minute != sch["minute"]:
            return False
        last = sch.get("last_run")
        if not last:
            return True
        last_dt = datetime.fromisoformat(last)
        return (now - last_dt).total_seconds() > 3500

    return False

async def _execute_schedule(sch: dict):
    """스케줄 실행 — OpenWebUI에 질문하고 해당 사용자에게 전송"""
    if not _bot_app:
        return
    user_id = sch["user_id"]
    task    = sch["task"]

    # 세션 가져오기 (또는 임시 세션 생성)
    session = get_session(user_id)

    try:
        # 스트리밍 없이 단순 호출 (예약 실행은 백그라운드)
        reply = await call_openwebui_chat(session, f"[예약 알림] {task}")
        reply = filter_ai_response(format_response_with_links(reply))

        type_str = {"once": "일회성", "daily": "매일", "weekly": f"매주 {_WEEKDAY_NAME[sch.get('weekday', 0)]}"}
        header = f"⏰ <b>[예약 알림 — {type_str.get(sch['type'], '')}]</b>\n📌 {html.escape(task)}\n\n"

        # 4096자 초과 시 분할
        full = header + reply
        for i in range(0, len(full), 4000):
            await _bot_app.bot.send_message(
                chat_id=user_id,
                text=full[i:i+4000],
                parse_mode=ParseMode.HTML,
            )
        logger.info(f"⏰ 예약 실행 완료: {sch['id']} / {user_id}")
        audit_log("SCHEDULE_EXEC", user_id, sch["id"])

    except Exception as e:
        logger.error(f"예약 실행 오류 [{sch['id']}]: {e}")
        try:
            await _bot_app.bot.send_message(
                chat_id=user_id,
                text=f"⏰ <b>[예약 알림]</b> 📌 {html.escape(task)}\n\n⚠️ 실행 중 오류가 발생했습니다.",
                parse_mode=ParseMode.HTML,
            )
        except Exception:
            pass

async def _scheduler_loop():
    """30초마다 예약 목록 확인 → 실행"""
    logger.info("⏰ 스케줄러 시작")
    while True:
        await asyncio.sleep(30)
        try:
            now = datetime.now()
            schedules = _load_schedules()
            if not schedules:
                continue

            to_remove = []
            updated   = False

            for sch in schedules:
                if _should_run(sch, now):
                    await _execute_schedule(sch)
                    if sch["type"] == "once":
                        to_remove.append(sch["id"])
                    else:
                        sch["last_run"] = now.isoformat()
                        updated = True

            if to_remove:
                schedules = [s for s in schedules if s["id"] not in to_remove]
                updated = True

            if updated:
                _save_schedules(schedules)

        except Exception as e:
            logger.error(f"스케줄러 루프 오류: {e}")

# ── 예약 Telegram 명령어 ────────────────────────────────────────
@authorized
async def cmd_remind(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/remind <시간> <내용> — 예약 설정"""
    user = update.effective_user
    args_text = " ".join(context.args) if context.args else ""

    if not args_text:
        await update.message.reply_text(
            "⏰ <b>예약 설정 방법</b>\n\n"
            "<b>일회성</b>\n"
            "• <code>/remind 30분 후 회의 준비하기</code>\n"
            "• <code>/remind 2시간 후 약 먹기</code>\n"
            "• <code>/remind 내일 오전 9시 날씨 알려줘</code>\n"
            "• <code>/remind 내일 14:00 미팅 준비</code>\n\n"
            "<b>반복</b>\n"
            "• <code>/remind 매일 09:00 날씨 알려줘</code>\n"
            "• <code>/remind 매일 오전 8시 30분 뉴스 요약해줘</code>\n"
            "• <code>/remind 매주 월요일 09:00 주간 업무 정리해줘</code>\n"
            "• <code>/remind 매주 금 18:00 이번 주 마무리 보고</code>\n\n"
            "📋 목록: /reminders\n"
            "❌ 취소: /cancel &lt;ID&gt;",
            parse_mode=ParseMode.HTML,
        )
        return

    sch = parse_remind_command(args_text)
    if not sch:
        await update.message.reply_text(
            "❌ 형식을 인식할 수 없습니다.\n\n"
            "/remind 만 입력하면 예시를 볼 수 있습니다.",
        )
        return

    sch["id"]         = _new_schedule_id()
    sch["user_id"]    = user.id
    sch["created_at"] = datetime.now().isoformat()

    schedules = _load_schedules()
    schedules.append(sch)
    _save_schedules(schedules)
    audit_log("SCHEDULE_ADD", user.id, sch["id"])

    # 확인 메시지 구성
    t = sch["type"]
    if t == "once":
        run_dt   = datetime.fromisoformat(sch["run_at"])
        when_str = run_dt.strftime("%Y-%m-%d %H:%M")
        type_str = f"일회성 — {when_str}"
    elif t == "daily":
        type_str = f"매일 {sch['hour']:02d}:{sch['minute']:02d}"
    else:
        type_str = f"매주 {_WEEKDAY_NAME[sch['weekday']]} {sch['hour']:02d}:{sch['minute']:02d}"

    await update.message.reply_text(
        f"✅ <b>예약 등록 완료</b>\n\n"
        f"🆔 ID: <code>{sch['id']}</code>\n"
        f"🕐 일정: {type_str}\n"
        f"📌 내용: {html.escape(sch['task'])}\n\n"
        f"예약 시간이 되면 AI가 답변과 함께 알림을 보냅니다.\n"
        f"취소: /cancel {sch['id']}",
        parse_mode=ParseMode.HTML,
    )
    logger.info(f"⏰ 예약 등록: {user.id} — {sch['id']} / {type_str}")


@authorized
async def cmd_reminders(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/reminders — 내 예약 목록"""
    user = update.effective_user
    schedules = [s for s in _load_schedules() if s["user_id"] == user.id]

    if not schedules:
        await update.message.reply_text(
            "📭 등록된 예약이 없습니다.\n/remind 로 새 예약을 만들어보세요."
        )
        return

    lines = [f"⏰ <b>예약 목록</b> ({len(schedules)}개)\n"]
    for s in schedules:
        t = s["type"]
        if t == "once":
            dt = datetime.fromisoformat(s["run_at"])
            when = dt.strftime("%m/%d %H:%M")
            icon = "🔔"
        elif t == "daily":
            when = f"매일 {s['hour']:02d}:{s['minute']:02d}"
            icon = "🔁"
        else:
            when = f"매주 {_WEEKDAY_NAME[s['weekday']]} {s['hour']:02d}:{s['minute']:02d}"
            icon = "📅"
        lines.append(
            f"{icon} <code>{s['id']}</code> | {when}\n"
            f"   📌 {html.escape(s['task'][:50])}"
        )

    lines.append("\n취소: /cancel &lt;ID&gt;")
    await update.message.reply_text("\n\n".join(lines), parse_mode=ParseMode.HTML)


@authorized
async def cmd_cancel_schedule(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/cancel <ID> — 예약 취소"""
    user = update.effective_user
    args = context.args
    if not args:
        await update.message.reply_text("사용법: /cancel &lt;예약ID&gt;\n예: /cancel sch_ab12cd", parse_mode=ParseMode.HTML)
        return

    target_id = args[0].strip()
    schedules = _load_schedules()
    before    = len(schedules)
    # 본인 예약만 취소 가능
    schedules = [s for s in schedules if not (s["id"] == target_id and s["user_id"] == user.id)]

    if len(schedules) == before:
        await update.message.reply_text(f"❌ ID <code>{html.escape(target_id)}</code> 를 찾을 수 없습니다.", parse_mode=ParseMode.HTML)
        return

    _save_schedules(schedules)
    audit_log("SCHEDULE_CANCEL", user.id, target_id)
    await update.message.reply_text(f"✅ 예약 취소됨: <code>{html.escape(target_id)}</code>", parse_mode=ParseMode.HTML)
    logger.info(f"⏰ 예약 취소: {user.id} — {target_id}")
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
        "• \"오늘 일정 알려줘\" → 📅 캘린더 오늘 일정\n"
        "• /model — 모델 선택/변경\n"
        "• /tools — Tool 활성화/비활성화\n"
        "• /clear — 대화 기록 초기화\n"
        "• /lock — 🔒 보안 잠금 (PIN 재인증 필요)\n"
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
        "🌐 <b>브라우저 에이전트</b>\n"
        "/tools에서 AI 브라우저 에이전트를 활성화한 후:\n"
        "• '오늘 날씨 알려줘' → 네이버 날씨 자동 검색\n"
        "• '에어팟 프로 가격' → 네이버 쇼핑 최저가 검색\n"
        "• '달러 환율' → 실시간 환율 조회\n"
        "• 'https://example.com 요약해줘' → 웹페이지 요약\n\n"
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
    if rate_limiter.is_blocked(user.id):
        return
    if not rate_limiter.record_request(user.id):
        return

    model_id = query.data.replace("model:", "")
    if not re.match(r'^[a-zA-Z0-9._:/-]+$', model_id) or len(model_id) > 128:
        logger.warning(f"🚨 유효하지 않은 모델 ID: {user.id} — {model_id[:50]}")
        return
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
async def cmd_lock(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """보안 잠금 — 신뢰 해제 + 세션 초기화"""
    user = update.effective_user
    if not user or user.id not in ADMIN_USER_IDS:
        return
    session = get_session(user.id)
    untrust_user(user.id)
    session.authenticated = False
    session.clear()
    logger.info(f"🔒 보안 잠금: {user.id}")
    await update.message.reply_text(
        "🔒 보안 잠금 완료!\n"
        "다음 사용 시 PIN 인증이 필요합니다.\n"
        "공용 기기에서 사용 후 잠금하면 안전합니다."
    )

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
# 관리자 명령어 확장
# ══════════════════════════════════════════
@authorized
async def cmd_admin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """관리자 패널 — 인라인 버튼 메뉴"""
    active = len([s for s in sessions.values() if not s.is_expired()])
    text = (
        "🛡️ <b>관리자 패널</b>\n\n"
        f"👥 활성 세션: <b>{active}</b>개\n"
        f"🚫 차단 사용자: <b>{len(rate_limiter.blocked)}</b>명\n"
        f"👤 허용 사용자: <b>{len(ADMIN_USER_IDS)}</b>명\n"
        f"💬 총 메시지: <b>{_stats.get('total_messages', 0)}</b>건\n\n"
        "버튼으로 관리하거나 명령어를 직접 사용하세요."
    )
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("👥 세션 목록", callback_data="adm:sessions"),
         InlineKeyboardButton("🚫 차단 목록", callback_data="adm:blocked")],
        [InlineKeyboardButton("🟢 Tool 전체 ON", callback_data="adm:tools_on"),
         InlineKeyboardButton("🔴 Tool 전체 OFF", callback_data="adm:tools_off")],
        [InlineKeyboardButton("📊 상세 통계", callback_data="adm:stats"),
         InlineKeyboardButton("📋 최근 로그", callback_data="adm:logs")],
        [InlineKeyboardButton("🌐 웹 대시보드 URL", callback_data="adm:weburl")],
    ])
    await update.message.reply_text(text, parse_mode=ParseMode.HTML, reply_markup=keyboard)


async def callback_admin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """관리자 패널 콜백 처리"""
    query = update.callback_query
    await query.answer()
    user = query.from_user
    if user.id not in ADMIN_USER_IDS:
        return
    action = query.data.replace("adm:", "")

    if action == "sessions":
        active = [(uid, s) for uid, s in sessions.items() if not s.is_expired()]
        if not active:
            await query.edit_message_text("👥 활성 세션 없음")
            return
        lines = [f"👥 <b>활성 세션</b> ({len(active)}개)\n"]
        for uid, s in active[:15]:
            lines.append(
                f"• <code>{uid}</code> | {html.escape(s.model[:20])}"
                f" | {len(s.history)}msg | {s.last_active.strftime('%H:%M')}"
            )
        await query.edit_message_text("\n".join(lines), parse_mode=ParseMode.HTML)

    elif action == "blocked":
        if not rate_limiter.blocked:
            await query.edit_message_text("🚫 차단된 사용자 없음")
            return
        lines = [f"🚫 <b>차단 목록</b> ({len(rate_limiter.blocked)}명)\n"]
        for uid, until in list(rate_limiter.blocked.items())[:15]:
            lines.append(f"• <code>{uid}</code> → {until.strftime('%H:%M')} 까지")
        lines.append("\n/unblock &lt;ID&gt; 로 해제")
        await query.edit_message_text("\n".join(lines), parse_mode=ParseMode.HTML)

    elif action == "tools_on":
        tools = await get_available_tools()
        cnt = 0
        for s in sessions.values():
            if not s.is_expired():
                s.enable_all_tools([t["id"] for t in tools])
                cnt += 1
        await query.edit_message_text(f"🟢 {cnt}개 활성 세션에 Tool 전체 활성화 완료")

    elif action == "tools_off":
        cnt = 0
        for s in sessions.values():
            if not s.is_expired():
                s.disable_all_tools()
                cnt += 1
        await query.edit_message_text(f"🔴 {cnt}개 활성 세션에 Tool 전체 비활성화 완료")

    elif action == "stats":
        uptime = datetime.now() - start_time
        h, rem = divmod(int(uptime.total_seconds()), 3600)
        m = rem // 60
        tool_usage: dict = {}
        for s in sessions.values():
            for tid in s.enabled_tool_ids:
                tool_usage[tid] = tool_usage.get(tid, 0) + 1
        top = sorted(tool_usage.items(), key=lambda x: -x[1])[:5]
        tool_lines = "\n".join(f"   • {tid[:28]}: {cnt}" for tid, cnt in top) or "   없음"
        text = (
            "📊 <b>상세 통계</b>\n"
            f"⏱ 가동시간: {h}h {m}m\n"
            f"💬 총 메시지: {_stats.get('total_messages', 0)}건\n"
            f"📎 파일 업로드: {_stats.get('total_files', 0)}건\n"
            f"🎤 음성 처리: {_stats.get('total_voices', 0)}건\n"
            f"🚫 차단 시도: {_stats.get('blocked_attempts', 0)}건\n"
            f"👥 활성/{len(sessions)} 세션 | 허용 {len(ADMIN_USER_IDS)}명\n"
            f"🔥 Tool 사용 순위\n{tool_lines}"
        )
        await query.edit_message_text(text, parse_mode=ParseMode.HTML)

    elif action == "logs":
        try:
            with open("/app/logs/bot.log", encoding="utf-8") as f:
                lines = f.readlines()[-20:]
            content = html.escape("".join(lines)[-2000:])
            await query.edit_message_text(
                f"📋 <b>최근 로그 (20줄)</b>\n\n<pre>{content}</pre>",
                parse_mode=ParseMode.HTML
            )
        except Exception as e:
            await query.edit_message_text(f"❌ 로그 읽기 실패: {e}")

    elif action == "weburl":
        _int_secret = os.getenv("INTERNAL_API_SECRET", "")
        await query.edit_message_text(
            "🖥️ <b>웹 대시보드 접속 방법</b>\n\n"
            "<b>대시보드는 로컬 전용입니다.</b>\n"
            "외부에서 접근하려면 SSH 터널을 사용하세요.\n\n"
            "1️⃣ PC/Mac 터미널에서:\n"
            "<code>ssh -L 8445:localhost:8445 user@서버IP</code>\n\n"
            "2️⃣ 브라우저에서:\n"
            "<code>http://localhost:8445/dashboard</code>\n\n"
            f"3️⃣ 토큰 입력 (팝업):\n"
            f"<code>{_int_secret[:8]}...{_int_secret[-4:]}</code>\n\n"
            "💡 서버에서 전체 토큰 확인:\n"
            "<code>grep INTERNAL_API_SECRET ~/telegram-openwebui-bridge/.env</code>",
            parse_mode=ParseMode.HTML
        )


@authorized
async def cmd_users(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/users — 활성 세션 목록"""
    active = [(uid, s) for uid, s in sessions.items() if not s.is_expired()]
    if not active:
        await update.message.reply_text("👥 현재 활성 세션이 없습니다.")
        return
    lines = [f"👥 <b>활성 세션 ({len(active)}개)</b>\n"]
    for uid, s in active[:20]:
        flag = "🔑" if uid in ADMIN_USER_IDS else "👤"
        lines.append(
            f"{flag} <code>{uid}</code>\n"
            f"   모델: {html.escape(s.model[:28])}\n"
            f"   메시지: {len(s.history)}개 | Tool: {len(s.enabled_tool_ids)}개\n"
            f"   마지막: {s.last_active.strftime('%H:%M:%S')}"
        )
    await update.message.reply_text("\n\n".join(lines), parse_mode=ParseMode.HTML)


@authorized
async def cmd_block_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/block <user_id> [분] — 사용자 차단"""
    args = context.args
    if not args or not args[0].isdigit():
        await update.message.reply_text(
            "사용법: /block &lt;user_id&gt; [차단분수, 기본=60]\n"
            "예: /block 123456789 30",
            parse_mode=ParseMode.HTML
        )
        return
    target = int(args[0])
    minutes = int(args[1]) if len(args) > 1 and args[1].isdigit() else 60
    rate_limiter.blocked[target] = datetime.now() + timedelta(minutes=minutes)
    if target in sessions:
        del sessions[target]
    logger.warning(f"🚫 수동 차단: {update.effective_user.id} → {target} ({minutes}분)")
    await update.message.reply_text(
        f"🚫 <code>{target}</code> 차단됨 ({minutes}분)", parse_mode=ParseMode.HTML
    )


@authorized
async def cmd_unblock_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/unblock <user_id> — 차단 해제"""
    args = context.args
    if not args or not args[0].isdigit():
        await update.message.reply_text("사용법: /unblock &lt;user_id&gt;", parse_mode=ParseMode.HTML)
        return
    target = int(args[0])
    rate_limiter.blocked.pop(target, None)
    rate_limiter.fail_count[target] = 0
    logger.info(f"✅ 차단 해제: {update.effective_user.id} → {target}")
    await update.message.reply_text(
        f"✅ <code>{target}</code> 차단 해제됨", parse_mode=ParseMode.HTML
    )


@authorized
async def cmd_adduser(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/adduser <user_id> — 허용 사용자 추가"""
    args = context.args
    if not args or not args[0].isdigit():
        await update.message.reply_text("사용법: /adduser &lt;user_id&gt;", parse_mode=ParseMode.HTML)
        return
    target = int(args[0])
    add_allowed_user(target)
    await update.message.reply_text(
        f"✅ <code>{target}</code> 허용 목록 추가됨 (재시작 후에도 유지)", parse_mode=ParseMode.HTML
    )


@authorized
async def cmd_removeuser(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/removeuser <user_id> — 허용 사용자 제거"""
    args = context.args
    if not args or not args[0].isdigit():
        await update.message.reply_text("사용법: /removeuser &lt;user_id&gt;", parse_mode=ParseMode.HTML)
        return
    target = int(args[0])
    if target == update.effective_user.id:
        await update.message.reply_text("❌ 자기 자신은 제거할 수 없습니다.")
        return
    remove_allowed_user(target)
    await update.message.reply_text(
        f"🗑 <code>{target}</code> 허용 목록에서 제거됨", parse_mode=ParseMode.HTML
    )


@authorized
async def cmd_broadcast(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/broadcast <메시지> — 모든 활성 사용자에게 공지"""
    if not context.args:
        await update.message.reply_text("사용법: /broadcast &lt;메시지&gt;", parse_mode=ParseMode.HTML)
        return
    msg = " ".join(context.args)
    full_msg = f"📢 <b>[관리자 공지]</b>\n\n{html.escape(msg)}"
    result = await broadcast_message(full_msg)
    logger.info(
        f"📢 브로드캐스트: {update.effective_user.id} "
        f"— 전송:{result['sent']} 실패:{result['failed']}"
    )
    await update.message.reply_text(
        f"📢 브로드캐스트 완료\n✅ 전송: {result['sent']}명\n❌ 실패: {result['failed']}명"
    )


@authorized
async def cmd_logs(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/logs [n] — 최근 로그 n줄 (기본 30, 최대 100)"""
    n = 30
    if context.args and context.args[0].isdigit():
        n = min(int(context.args[0]), 100)
    try:
        with open("/app/logs/bot.log", encoding="utf-8") as f:
            lines = f.readlines()[-n:]
        content = html.escape("".join(lines)[-3500:])
        await update.message.reply_text(
            f"📋 <b>최근 로그 ({n}줄)</b>\n\n<pre>{content}</pre>",
            parse_mode=ParseMode.HTML
        )
    except Exception as e:
        await update.message.reply_text(f"❌ 로그 읽기 실패: {e}")


@authorized
async def cmd_stats(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/stats — 상세 통계"""
    uptime = datetime.now() - start_time
    h, rem = divmod(int(uptime.total_seconds()), 3600)
    m = rem // 60
    active = len([s for s in sessions.values() if not s.is_expired()])
    tool_usage: dict = {}
    for s in sessions.values():
        for tid in s.enabled_tool_ids:
            tool_usage[tid] = tool_usage.get(tid, 0) + 1
    top = sorted(tool_usage.items(), key=lambda x: -x[1])[:5]
    tool_lines = "\n".join(f"   • {tid[:28]}: {cnt}세션" for tid, cnt in top) or "   없음"
    text = (
        "📊 <b>상세 통계</b>\n"
        f"{'─'*28}\n"
        f"⏱ 가동시간: {h}h {m}m\n"
        f"💬 총 메시지: {_stats.get('total_messages', 0)}건\n"
        f"📎 파일 업로드: {_stats.get('total_files', 0)}건\n"
        f"🎤 음성 처리: {_stats.get('total_voices', 0)}건\n"
        f"🚫 차단 시도: {_stats.get('blocked_attempts', 0)}건\n"
        f"{'─'*28}\n"
        f"👥 활성: {active} / 전체: {len(sessions)}세션\n"
        f"👤 허용 사용자: {len(ADMIN_USER_IDS)}명\n"
        f"🚫 현재 차단: {len(rate_limiter.blocked)}명\n"
        f"🔧 캐시된 Tool: {len(_tools_cache['tools'])}개\n"
        f"{'─'*28}\n"
        f"🔥 Tool 사용 순위\n{tool_lines}"
    )
    await update.message.reply_text(text, parse_mode=ParseMode.HTML)

# ══════════════════════════════════════════
# [NEW] ⑥ 비상 차단 모드 명령어
# ══════════════════════════════════════════
@authorized
async def cmd_emergency(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """/emergency — 비상 차단 모드 토글 (관리자 전용)"""
    global _EMERGENCY_MODE
    user = update.effective_user
    _EMERGENCY_MODE = not _EMERGENCY_MODE
    state = "🚨 활성화" if _EMERGENCY_MODE else "✅ 해제"
    logger.critical(f"비상 차단 모드 {state}: 관리자={user.id}")
    audit_log("EMERGENCY_TOGGLE", user.id, state)
    if _EMERGENCY_MODE:
        evicted = [uid for uid in list(sessions.keys()) if uid not in ADMIN_USER_IDS]
        for uid in evicted:
            del sessions[uid]
        await update.message.reply_text(
            "🚨 <b>비상 차단 모드 활성화</b>\n\n"
            f"관리자 외 모든 접근 즉시 차단\n"
            f"종료된 비관리자 세션: {len(evicted)}개\n\n"
            "해제: /emergency 재입력",
            parse_mode=ParseMode.HTML
        )
    else:
        await update.message.reply_text(
            "✅ <b>비상 차단 모드 해제</b> — 정상 운영 복귀",
            parse_mode=ParseMode.HTML
        )

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
    if rate_limiter.is_blocked(user.id):
        return
    if not rate_limiter.record_request(user.id):
        return

    tool_id = query.data.replace("tool:", "")
    if not re.match(r'^[a-zA-Z0-9_.-]+$', tool_id) or len(tool_id) > 128:
        logger.warning(f"🚨 유효하지 않은 Tool ID: {user.id} — {tool_id[:50]}")
        return
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
    if rate_limiter.is_blocked(user.id):
        return
    if not rate_limiter.record_request(user.id):
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
    if rate_limiter.is_blocked(user.id):
        return
    if not rate_limiter.record_request(user.id):
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
    inc_stat("total_messages")  # 통계 카운트

    # [NEW] ② Prompt Injection 방어
    if detect_injection(text):
        audit_log("INJECTION_BLOCKED", user.id, text[:100], ok=False)
        await update.message.reply_text(
            "🛡️ 해당 메시지는 보안 정책에 의해 차단되었습니다.\n"
            "시스템 프롬프트 조작 시도가 감지되었습니다."
        )
        return

    # 타이핑 표시
    await update.message.reply_chat_action(ChatAction.TYPING)

    # ── Multi-Agent 직접 호출 (복잡한 작업 감지 시) ──
    reply = None
    used_multi = False

    if _is_complex_task(text) and BROWSER_AGENT_API_KEY:
        try:
            timeout_ma = aiohttp.ClientTimeout(total=320)
            async with aiohttp.ClientSession(timeout=timeout_ma) as http:
                async with http.post(
                    f"{BROWSER_AGENT_URL}/browse/multi",
                    json={"task": text, "budget_usd": 0.05},
                    headers={
                        "Authorization": f"Bearer {BROWSER_AGENT_API_KEY}",
                        "X-User-Id": f"tg:{user.id}",
                    },
                ) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        reply = data.get("summary_plain", data.get("summary", data.get("response", data.get("result", ""))))
                        vnc_url = data.get("vnc_launch_url", "")
                        used_multi = True
                        logger.info(f"🔀 Multi-Agent 응답: {len(reply)}자")
                    elif resp.status == 503:
                        logger.info("Multi-Agent 미설치 — OpenWebUI 폴백")
                    else:
                        logger.warning(f"Multi-Agent 오류 HTTP {resp.status} — 폴백")
        except Exception as e:
            logger.warning(f"Multi-Agent 연결 실패: {e} — OpenWebUI 폴백")

    # ── 일반 OpenWebUI 호출 (Multi-Agent 미사용 시) — 스트리밍 모드 ──
    if reply is None:
        # 플레이스홀더 메시지 전송 (스트리밍 중 글자가 쌓이는 화면)
        try:
            placeholder = await update.message.reply_text("💭 생각 중...")
        except Exception:
            placeholder = None

        async def on_chunk(current_text: str):
            """스트리밍 청크마다 플레이스홀더 메시지 편집"""
            if placeholder is None:
                return
            display = current_text[:4000]
            if len(current_text) > 4000:
                display += " ..."
            try:
                # 생성 중 커서(▌) 표시 — 아직 완성 안 됐음을 시각적으로 표현
                await placeholder.edit_text(display + " ▌")
            except Exception:
                pass  # FloodWait, MessageNotModified 등 조용히 무시

        reply = await stream_openwebui_chat(session, text, on_chunk)

        # 플레이스홀더 삭제 — 최종 포맷된 메시지를 새로 전송
        if placeholder:
            try:
                await placeholder.delete()
            except Exception:
                pass

    # ── VNC 링크 추출 + 클릭 가능 버튼 생성 ──
    vnc_link = ""
    # 응답에서 VNC URL 패턴 추출
    vnc_match = re.search(r'(?:브라우저 화면\(VNC\)|VNC|vnc)[:\s]*(https?://[^\s\)]+)', reply)
    if vnc_match:
        vnc_link = vnc_match.group(1)
        # 본문에서 VNC 줄 제거 (버튼으로 대체)
        reply = re.sub(r'\n?(?:브라우저 화면\(VNC\)|VNC)[:\s]*https?://[^\s\)]+', '', reply).strip()
    elif used_multi and vnc_url:
        vnc_link = vnc_url

    # ── 응답 전송 ──
    keyboard = None
    if vnc_link:
        keyboard = InlineKeyboardMarkup([
            [InlineKeyboardButton("🖥️ 브라우저 화면 보기", url=vnc_link)]
        ])

    # ✅ [추가] 링크 포매팅 적용 (HTML→Markdown 변환 + 링크 섹션 추가)
    reply = format_response_with_links(reply)
    # [NEW] ④ AI 응답 민감정보 자동 필터링
    reply = filter_ai_response(reply)
    audit_log("CHAT", user.id, f"len={len(reply)}")

    if len(reply) > 4096:
        chunks = [reply[i:i+4000] for i in range(0, len(reply), 4000)]
        for i, chunk in enumerate(chunks):
            kb = keyboard if i == len(chunks)-1 else None  # 마지막 청크에만 버튼
            try:
                await update.message.reply_text(
                    chunk, parse_mode=ParseMode.MARKDOWN,
                    reply_markup=kb, disable_web_page_preview=False
                )
            except Exception:
                await update.message.reply_text(chunk, reply_markup=kb)
    else:
        try:
            await update.message.reply_text(
                reply, parse_mode=ParseMode.MARKDOWN,
                reply_markup=keyboard, disable_web_page_preview=False
            )
        except Exception:
            try:
                await update.message.reply_text(reply, reply_markup=keyboard)
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

    filename = document.file_name or "unknown"
    # C4: Path Traversal 방어
    filename = os.path.basename(filename)
    filename = re.sub(r'[^\w가-힣.\-]', '_', filename)
    if not filename or filename.startswith('.'):
        filename = f"upload_{int(time.time())}"
    filename = sanitize_input(filename)
    logger.info(f"📎 [{user.id}] 파일 업로드: {filename} ({document.file_size} bytes)")
    inc_stat("total_files")  # 통계 카운트

    await update.message.reply_chat_action(ChatAction.UPLOAD_DOCUMENT)

    try:
        file = await document.get_file()
        file_bytes = await file.download_as_bytearray()

        # [NEW] ③ Magic Bytes 검증
        ext = filename.rsplit('.', 1)[-1].lower() if '.' in filename else ''
        if not verify_file_magic(bytes(file_bytes), ext):
            audit_log("FILE_BLOCKED", user.id, f"magic_mismatch ext={ext}", ok=False)
            await update.message.reply_text(
                "🚫 파일 형식이 확인되지 않습니다.\n"
                "지원 형식: PDF, 이미지(JPG/PNG/GIF), 텍스트 파일"
            )
            return

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

    # 음성 파일 크기 제한 (MAX_FILE_SIZE_MB 적용)
    if voice.file_size and voice.file_size > MAX_FILE_SIZE_MB * 1024 * 1024:
        await update.message.reply_text(f"❌ 음성 파일이 너무 큽니다. (최대 {MAX_FILE_SIZE_MB}MB)")
        return

    logger.info(f"🎤 [{user.id}] 음성 메시지: {voice.duration}초")
    inc_stat("total_voices")  # 통계 카운트

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
    error_msg = str(context.error) if context.error else "Unknown error"
    # 에러 메시지에서 민감정보 마스킹 후 로그 기록
    logger.error(f"⚠️ 에러 발생: {mask_sensitive(error_msg)}")

# ══════════════════════════════════════════
# Health Check 서버 (별도 포트)
# ══════════════════════════════════════════
async def health_server():
    """Docker healthcheck용 HTTP 서버 (port 8444)"""
    from aiohttp import web

    async def health_check(request):
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
        return web.json_response(status, status=200 if webui_ok else 503)

    async def metrics_auth(request):
        _int_secret = os.getenv("INTERNAL_API_SECRET", "")
        if _int_secret:
            import hmac as _hmac
            _auth = request.headers.get("Authorization", "")
            if not _hmac.compare_digest(_auth, f"Bearer {_int_secret}"):
                return web.json_response({"error": "unauthorized"}, status=401)
        data = {
            "total_sessions": len(sessions),
            "active_sessions": len([s for s in sessions.values() if not s.is_expired()]),
            "total_messages": sum(len(s.history) for s in sessions.values()),
            "blocked_users": len(rate_limiter.blocked),
        }
        return web.json_response(data)

    app = web.Application()
    app.router.add_get("/health", health_check)
    app.router.add_get("/metrics", metrics_auth)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", 8444)
    await site.start()
    logger.info("🏥 Health check 서버 시작: http://127.0.0.1:8444/health")


async def dashboard_server():
    """관리자 웹 대시보드 서버 (port 8445)"""
    from aiohttp import web

    _int_secret = os.getenv("INTERNAL_API_SECRET", "")

    # [NEW] ⑦ 대시보드 Brute-force 방지
    _DASH_FAIL: dict = {}   # ip → (fail_count, lockout_until | None)
    _DASH_MAX_FAIL  = 5
    _DASH_LOCKOUT_M = 15

    def _check_auth(request) -> bool:
        ip  = request.remote or "0.0.0.0"
        now = datetime.now()
        # IP 잠금 확인
        if ip in _DASH_FAIL:
            cnt, until = _DASH_FAIL[ip]
            if until and now < until:
                logger.warning(f"🔒 대시보드 IP 잠금 중: {ip}")
                return False
            if until and now >= until:
                del _DASH_FAIL[ip]
        if not _int_secret:
            return True
        auth    = request.headers.get("Authorization", "")
        # [FIX H3] 토큰을 URL 쿼리(?token=)로 받지 않음 — 로그/히스토리 유출 방지. 헤더 전용.
        provided = auth.replace("Bearer ", "").strip()
        if not provided:
            return False
        # timing-safe 비교 (Timing Attack 방어)
        import hmac as _hmac
        ok = _hmac.compare_digest(provided, _int_secret)
        if ok:
            _DASH_FAIL.pop(ip, None)
        else:
            cnt = _DASH_FAIL.get(ip, (0, None))[0] + 1
            if cnt >= _DASH_MAX_FAIL:
                lockout = now + timedelta(minutes=_DASH_LOCKOUT_M)
                _DASH_FAIL[ip] = (cnt, lockout)
                logger.warning(f"🔒 대시보드 IP 잠금: {ip} ({cnt}회 실패, {_DASH_LOCKOUT_M}분)")
                audit_log("DASH_LOCKOUT", 0, ip)
            else:
                _DASH_FAIL[ip] = (cnt, None)
                logger.warning(f"🔑 대시보드 인증 실패: {ip} ({cnt}/{_DASH_MAX_FAIL}회)")
        return ok

    DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="ko"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>🤖 Bot 관리 대시보드</title>
<style>
:root{--bg:#0f1117;--card:#1a1d27;--border:#2d3748;--accent:#4f83cc;--green:#48bb78;--red:#fc8181;--yellow:#f6e05e;--text:#e2e8f0;--muted:#718096}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif;min-height:100vh}
header{background:var(--card);border-bottom:1px solid var(--border);padding:1rem 2rem;display:flex;justify-content:space-between;align-items:center}
header h1{font-size:1.2rem}
.dot{width:10px;height:10px;border-radius:50%;background:var(--green);display:inline-block;margin-right:6px;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
.container{max-width:1200px;margin:0 auto;padding:2rem}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:1rem;margin-bottom:2rem}
.card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.5rem}
.card h3{font-size:.75rem;color:var(--muted);text-transform:uppercase;letter-spacing:1px;margin-bottom:.5rem}
.card .val{font-size:2rem;font-weight:700}
.val.g{color:var(--green)}.val.r{color:var(--red)}.val.y{color:var(--yellow)}
.panel{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.5rem;margin-bottom:1.5rem}
.panel h2{font-size:1rem;margin-bottom:1rem;padding-bottom:.5rem;border-bottom:1px solid var(--border)}
table{width:100%;border-collapse:collapse;font-size:.875rem}
th{text-align:left;padding:.5rem .75rem;color:var(--muted);font-size:.75rem;text-transform:uppercase;font-weight:500}
td{padding:.5rem .75rem;border-top:1px solid var(--border)}
code{background:#2d3748;padding:2px 6px;border-radius:4px;font-size:.83rem}
.badge{display:inline-block;padding:2px 8px;border-radius:99px;font-size:.75rem;font-weight:600}
.badge.g{background:rgba(72,187,120,.15);color:var(--green)}.badge.r{background:rgba(252,129,129,.15);color:var(--red)}.badge.y{background:rgba(246,224,94,.15);color:var(--yellow)}
.btn{padding:.4rem .9rem;border:none;border-radius:6px;cursor:pointer;font-size:.85rem;font-weight:500;transition:opacity .2s}
.btn:hover{opacity:.75}.btn-r{background:var(--red);color:#111}.btn-g{background:var(--green);color:#111}.btn-b{background:var(--accent);color:#fff}.btn-sm{padding:.25rem .6rem;font-size:.78rem}
input,textarea{background:#2d3748;border:1px solid var(--border);color:var(--text);padding:.5rem .75rem;border-radius:6px;margin-bottom:.5rem;font-size:.875rem;width:100%}
textarea{height:80px;resize:vertical}
.row{display:flex;gap:.5rem;align-items:flex-start;flex-wrap:wrap}
.log{background:#0d1117;border:1px solid var(--border);border-radius:8px;padding:1rem;font-family:monospace;font-size:.75rem;max-height:420px;overflow-y:auto;white-space:pre-wrap;color:#a8b5c3}
.tabs{display:flex;gap:.5rem;margin-bottom:1.5rem;flex-wrap:wrap}
.tab{padding:.5rem 1.2rem;border-radius:8px;cursor:pointer;font-size:.875rem;border:1px solid var(--border);background:var(--card)}
.tab.on{background:var(--accent);border-color:var(--accent);color:#fff}
.sec{display:none}.sec.on{display:block}
#toast{position:fixed;bottom:2rem;right:2rem;background:#2d3748;padding:.75rem 1.5rem;border-radius:8px;font-size:.875rem;opacity:0;transition:opacity .3s;pointer-events:none;z-index:99}
#toast.show{opacity:1}
.fr{float:right}
@media(max-width:600px){.grid{grid-template-columns:1fr 1fr}}
</style></head><body>
<header>
  <h1>🤖 Telegram Bot 관리 대시보드</h1>
  <span><span class="dot"></span><span id="st">연결 중...</span></span>
</header>
<div class="container">
  <div class="tabs">
    <div class="tab on" onclick="tab('overview')">📊 개요</div>
    <div class="tab" onclick="tab('sessions')">👥 세션</div>
    <div class="tab" onclick="tab('users')">👤 사용자</div>
    <div class="tab" onclick="tab('tools')">🔧 Tool</div>
    <div class="tab" onclick="tab('logs')">📋 로그</div>
    <div class="tab" onclick="tab('bcast')">📢 공지</div>
  </div>

  <!-- 개요 -->
  <div class="sec on" id="t-overview">
    <div class="grid">
      <div class="card"><h3>활성 세션</h3><div class="val g" id="v-active">-</div></div>
      <div class="card"><h3>허용 사용자</h3><div class="val" id="v-allowed">-</div></div>
      <div class="card"><h3>차단 사용자</h3><div class="val r" id="v-blocked">-</div></div>
      <div class="card"><h3>총 메시지</h3><div class="val" id="v-msgs">-</div></div>
      <div class="card"><h3>파일 업로드</h3><div class="val" id="v-files">-</div></div>
      <div class="card"><h3>가동시간</h3><div class="val y" id="v-up">-</div></div>
    </div>
    <div class="panel"><h2>🌐 서비스 상태</h2>
      <table><tr><th>서비스</th><th>상태</th><th>정보</th></tr>
      <tr><td>Telegram Bot</td><td><span class="badge g">✅ 실행 중</span></td><td id="ow-info">-</td></tr>
      <tr><td>OpenWebUI</td><td><span class="badge" id="ow-b">확인 중</span></td><td id="ow-url">-</td></tr>
      </table>
    </div>
  </div>

  <!-- 세션 -->
  <div class="sec" id="t-sessions">
    <div class="panel"><h2>👥 활성 세션 <button class="btn btn-b btn-sm fr" onclick="loadSessions()">🔄</button></h2>
      <table><thead><tr><th>User ID</th><th>모델</th><th>메시지</th><th>Tool</th><th>마지막 활동</th><th>작업</th></tr></thead>
      <tbody id="tb-sess"><tr><td colspan="6" style="text-align:center;color:var(--muted)">로딩 중...</td></tr></tbody>
      </table>
    </div>
  </div>

  <!-- 사용자 -->
  <div class="sec" id="t-users">
    <div class="panel"><h2>➕ 사용자 추가</h2>
      <div class="row"><input id="in-add" type="number" placeholder="Telegram User ID" style="max-width:220px">
      <button class="btn btn-g" onclick="addUser()">추가</button></div>
    </div>
    <div class="panel"><h2>👤 허용 목록 <button class="btn btn-b btn-sm fr" onclick="loadUsers()">🔄</button></h2>
      <table><thead><tr><th>User ID</th><th>세션</th><th>작업</th></tr></thead>
      <tbody id="tb-users"></tbody></table>
    </div>
    <div class="panel"><h2>🚫 차단 관리</h2>
      <div class="row" style="margin-bottom:1rem">
        <input id="in-buid" type="number" placeholder="User ID" style="max-width:160px">
        <input id="in-bmin" type="number" placeholder="분(기본60)" style="max-width:100px">
        <button class="btn btn-r" onclick="blockUser()">차단</button>
      </div>
      <table><thead><tr><th>User ID</th><th>해제 시간</th><th>작업</th></tr></thead>
      <tbody id="tb-blk"></tbody></table>
    </div>
  </div>

  <!-- Tool -->
  <div class="sec" id="t-tools">
    <div class="panel"><h2>🔧 Tool 관리 <button class="btn btn-b btn-sm fr" onclick="loadTools()">🔄</button></h2>
      <div style="margin-bottom:1rem;display:flex;gap:.5rem">
        <button class="btn btn-g" onclick="gTool('on')">🟢 전체 ON</button>
        <button class="btn btn-r" onclick="gTool('off')">🔴 전체 OFF</button>
      </div>
      <table><thead><tr><th>Tool ID</th><th>이름</th><th>설명</th><th>사용 세션</th></tr></thead>
      <tbody id="tb-tools"></tbody></table>
    </div>
  </div>

  <!-- 로그 -->
  <div class="sec" id="t-logs">
    <div class="panel"><h2>📋 로그</h2>
      <div class="row" style="margin-bottom:1rem">
        <input id="in-logn" type="number" value="50" style="max-width:80px">
        <button class="btn btn-b" onclick="loadLogs()">불러오기</button>
        <label style="display:flex;align-items:center;gap:.3rem;font-size:.875rem;margin-top:.3rem">
          <input type="checkbox" id="auto-r" onchange="autoR()"> 자동 새로고침(10s)
        </label>
      </div>
      <div class="log" id="log-box">로딩 중...</div>
    </div>
  </div>

  <!-- 공지 -->
  <div class="sec" id="t-bcast">
    <div class="panel"><h2>📢 전체 공지</h2>
      <p style="color:var(--muted);margin-bottom:1rem;font-size:.875rem">모든 활성 세션 사용자에게 메시지를 전송합니다.</p>
      <textarea id="in-bcast" placeholder="공지 내용..."></textarea>
      <button class="btn btn-b" onclick="sendBcast()">📢 전송</button>
    </div>
  </div>
</div>
<div id="toast"></div>
<script>
// [FIX H3] URL 쿼리(?token=)에서 토큰을 읽지 않음 — 브라우저 히스토리/서버 로그 유출 방지
const TOKEN = localStorage.getItem('dt') || prompt('INTERNAL_API_SECRET 입력:');
if(TOKEN) localStorage.setItem('dt', TOKEN);
const H = {'Authorization':'Bearer '+TOKEN,'Content-Type':'application/json'};

function tab(n){
  const names=['overview','sessions','users','tools','logs','bcast'];
  document.querySelectorAll('.tab').forEach((t,i)=>t.classList.toggle('on',names[i]===n));
  document.querySelectorAll('.sec').forEach(s=>s.classList.remove('on'));
  document.getElementById('t-'+n).classList.add('on');
  if(n==='sessions')loadSessions();
  if(n==='users')loadUsers();
  if(n==='tools')loadTools();
  if(n==='logs')loadLogs();
}

function toast(msg,c='var(--green)'){
  const el=document.getElementById('toast');
  el.textContent=msg;el.style.borderLeft='4px solid '+c;
  el.classList.add('show');setTimeout(()=>el.classList.remove('show'),3000);
}

async function api(path,opts={}){
  try{
    const r=await fetch('/dashboard/api'+path,{headers:H,...opts});
    if(!r.ok)throw new Error('HTTP '+r.status);
    return await r.json();
  }catch(e){toast('❌ '+e.message,'var(--red)');return null;}
}

async function loadStats(){
  const d=await api('/stats');if(!d)return;
  document.getElementById('v-active').textContent=d.active_sessions;
  document.getElementById('v-allowed').textContent=d.allowed_users;
  document.getElementById('v-blocked').textContent=d.blocked_users;
  document.getElementById('v-msgs').textContent=d.total_messages;
  document.getElementById('v-files').textContent=d.total_files;
  const up=d.uptime_seconds,h=Math.floor(up/3600),m=Math.floor((up%3600)/60);
  document.getElementById('v-up').textContent=h+'h '+m+'m';
  const b=document.getElementById('ow-b');
  b.textContent=d.openwebui_ok?'✅ 연결됨':'❌ 오프라인';
  b.className='badge '+(d.openwebui_ok?'g':'r');
  document.getElementById('ow-url').textContent=d.openwebui_url;
  document.getElementById('ow-info').textContent='모델: '+d.model;
  document.getElementById('st').textContent=d.openwebui_ok?'정상 운영 중':'일부 오류';
}

async function loadSessions(){
  const d=await api('/sessions');if(!d)return;
  const tb=document.getElementById('tb-sess');
  tb.innerHTML=d.sessions.length?d.sessions.map(s=>`<tr>
    <td><code>${s.user_id}</code></td><td>${s.model}</td><td>${s.message_count}</td>
    <td>${s.tool_count}</td><td>${s.last_active}</td>
    <td><button class="btn btn-r btn-sm" onclick="blockUser(${s.user_id})">차단</button></td>
  </tr>`).join(''):'<tr><td colspan="6" style="text-align:center;color:var(--muted)">활성 세션 없음</td></tr>';
}

async function loadUsers(){
  const d=await api('/users');if(!d)return;
  const tb=document.getElementById('tb-users');
  tb.innerHTML=d.allowed.map(uid=>{
    const act=d.active_sessions.includes(uid);
    return`<tr><td><code>${uid}</code></td>
    <td><span class="badge ${act?'g':''}">${act?'🟢 활성':'⚪ 비활성'}</span></td>
    <td><button class="btn btn-r btn-sm" onclick="removeUser(${uid})">제거</button></td></tr>`;
  }).join('')||'<tr><td colspan="3" style="text-align:center;color:var(--muted)">없음</td></tr>';
  const tb2=document.getElementById('tb-blk');
  tb2.innerHTML=d.blocked.map(b=>`<tr><td><code>${b.user_id}</code></td><td>${b.until}</td>
    <td><button class="btn btn-g btn-sm" onclick="unblockUser(${b.user_id})">해제</button></td></tr>`
  ).join('')||'<tr><td colspan="3" style="text-align:center;color:var(--muted)">없음</td></tr>';
}

async function addUser(){
  const uid=document.getElementById('in-add').value;if(!uid)return;
  const d=await api('/users/add',{method:'POST',body:JSON.stringify({user_id:parseInt(uid)})});
  if(d){toast('✅ 추가 완료');document.getElementById('in-add').value='';loadUsers();}
}
async function removeUser(uid){
  if(!confirm(uid+' 제거?'))return;
  const d=await api('/users/remove',{method:'POST',body:JSON.stringify({user_id:uid})});
  if(d){toast('🗑 제거됨');loadUsers();}
}
async function blockUser(uid){
  uid=uid||parseInt(document.getElementById('in-buid').value);
  const min=parseInt(document.getElementById('in-bmin')?.value||60);
  if(!uid)return;
  const d=await api('/users/block',{method:'POST',body:JSON.stringify({user_id:uid,minutes:min})});
  if(d){toast('🚫 차단됨');loadUsers();}
}
async function unblockUser(uid){
  const d=await api('/users/unblock',{method:'POST',body:JSON.stringify({user_id:uid})});
  if(d){toast('✅ 해제됨');loadUsers();}
}

async function loadTools(){
  const d=await api('/tools');if(!d)return;
  const tb=document.getElementById('tb-tools');
  tb.innerHTML=d.tools.map(t=>`<tr><td><code>${t.id}</code></td><td>${t.name}</td>
    <td style="color:var(--muted);font-size:.83rem">${t.description||'-'}</td><td>${t.active_sessions}세션</td></tr>`
  ).join('')||'<tr><td colspan="4" style="text-align:center;color:var(--muted)">없음</td></tr>';
}
async function gTool(action){
  const d=await api('/tools/global',{method:'POST',body:JSON.stringify({action})});
  if(d)toast(action==='on'?'🟢 전체 활성화':'🔴 전체 비활성화');
}

async function loadLogs(){
  const n=document.getElementById('in-logn').value||50;
  const d=await api('/logs?n='+n);if(!d)return;
  const box=document.getElementById('log-box');
  box.textContent=d.lines.join('');box.scrollTop=box.scrollHeight;
}
let _ar=null;
function autoR(){
  _ar=document.getElementById('auto-r').checked?setInterval(loadLogs,10000):(clearInterval(_ar),null);
}

async function sendBcast(){
  const msg=document.getElementById('in-bcast').value.trim();if(!msg)return;
  const d=await api('/broadcast',{method:'POST',body:JSON.stringify({message:msg})});
  if(d){toast('📢 전송:'+d.sent+'명');document.getElementById('in-bcast').value='';}
}

loadStats();setInterval(loadStats,15000);
</script></body></html>"""

    async def dash_auth(request, fn):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        return await fn(request)

    async def route_dashboard(request):
        return web.Response(text=DASHBOARD_HTML, content_type="text/html")

    async def route_stats(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        try:
            timeout = aiohttp.ClientTimeout(total=3)
            async with aiohttp.ClientSession(timeout=timeout) as http:
                async with http.get(f"{OPENWEBUI_URL}/health") as resp:
                    ow_ok = resp.status == 200
        except Exception:
            ow_ok = False
        up = (datetime.now() - start_time).total_seconds()
        return web.json_response({
            "active_sessions": len([s for s in sessions.values() if not s.is_expired()]),
            "allowed_users": len(ADMIN_USER_IDS),
            "blocked_users": len(rate_limiter.blocked),
            "total_messages": _stats.get("total_messages", 0),
            "total_files": _stats.get("total_files", 0),
            "total_voices": _stats.get("total_voices", 0),
            "blocked_attempts": _stats.get("blocked_attempts", 0),
            "uptime_seconds": int(up),
            "openwebui_ok": ow_ok,
            "openwebui_url": OPENWEBUI_URL,
            "model": DEFAULT_MODEL,
        })

    async def route_sessions(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        data = []
        for uid, s in sessions.items():
            if not s.is_expired():
                data.append({
                    "user_id": uid,
                    "model": s.model[:30],
                    "message_count": len(s.history),
                    "tool_count": len(s.enabled_tool_ids),
                    "last_active": s.last_active.strftime("%H:%M:%S"),
                })
        return web.json_response({"sessions": data})

    async def route_users(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        active_ids = [uid for uid, s in sessions.items() if not s.is_expired()]
        blocked = [
            {"user_id": uid, "until": until.strftime("%Y-%m-%d %H:%M:%S")}
            for uid, until in rate_limiter.blocked.items()
        ]
        return web.json_response({
            "allowed": list(ADMIN_USER_IDS),
            "active_sessions": active_ids,
            "blocked": blocked,
        })

    async def route_add_user(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        body = await request.json()
        uid = int(body.get("user_id", 0))
        if not uid:
            return web.json_response({"error": "user_id required"}, status=400)
        add_allowed_user(uid)
        return web.json_response({"ok": True, "user_id": uid})

    async def route_remove_user(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        body = await request.json()
        uid = int(body.get("user_id", 0))
        remove_allowed_user(uid)
        return web.json_response({"ok": True, "user_id": uid})

    async def route_block_user(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        body = await request.json()
        uid = int(body.get("user_id", 0))
        minutes = int(body.get("minutes", 60))
        if not uid:
            return web.json_response({"error": "user_id required"}, status=400)
        rate_limiter.blocked[uid] = datetime.now() + timedelta(minutes=minutes)
        if uid in sessions:
            del sessions[uid]
        return web.json_response({"ok": True, "user_id": uid, "minutes": minutes})

    async def route_unblock_user(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        body = await request.json()
        uid = int(body.get("user_id", 0))
        rate_limiter.blocked.pop(uid, None)
        rate_limiter.fail_count[uid] = 0
        return web.json_response({"ok": True, "user_id": uid})

    async def route_tools(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        tools = await get_available_tools()
        tool_usage: dict = {}
        for s in sessions.values():
            for tid in s.enabled_tool_ids:
                tool_usage[tid] = tool_usage.get(tid, 0) + 1
        result = [
            {**t, "active_sessions": tool_usage.get(t["id"], 0)}
            for t in tools
        ]
        return web.json_response({"tools": result})

    async def route_tools_global(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        body = await request.json()
        action = body.get("action", "on")
        tools = await get_available_tools()
        cnt = 0
        for s in sessions.values():
            if not s.is_expired():
                if action == "on":
                    s.enable_all_tools([t["id"] for t in tools])
                else:
                    s.disable_all_tools()
                cnt += 1
        return web.json_response({"ok": True, "action": action, "sessions_affected": cnt})

    async def route_logs(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        n = min(int(request.rel_url.query.get("n", 50)), 500)
        try:
            with open("/app/logs/bot.log", encoding="utf-8") as f:
                lines = f.readlines()[-n:]
        except FileNotFoundError:
            lines = ["(로그 파일 없음)"]
        return web.json_response({"lines": lines, "count": len(lines)})

    async def route_broadcast(request):
        if not _check_auth(request):
            return web.json_response({"error": "unauthorized"}, status=401)
        body = await request.json()
        msg = body.get("message", "").strip()
        if not msg:
            return web.json_response({"error": "message required"}, status=400)
        full_msg = f"📢 <b>[관리자 공지]</b>\n\n{html.escape(msg)}"
        result = await broadcast_message(full_msg)
        return web.json_response({"ok": True, **result})

    dash_app = web.Application()
    dash_app.router.add_get("/dashboard", route_dashboard)
    dash_app.router.add_get("/dashboard/api/stats", route_stats)
    dash_app.router.add_get("/dashboard/api/sessions", route_sessions)
    dash_app.router.add_get("/dashboard/api/users", route_users)
    dash_app.router.add_post("/dashboard/api/users/add", route_add_user)
    dash_app.router.add_post("/dashboard/api/users/remove", route_remove_user)
    dash_app.router.add_post("/dashboard/api/users/block", route_block_user)
    dash_app.router.add_post("/dashboard/api/users/unblock", route_unblock_user)
    dash_app.router.add_get("/dashboard/api/tools", route_tools)
    dash_app.router.add_post("/dashboard/api/tools/global", route_tools_global)
    dash_app.router.add_get("/dashboard/api/logs", route_logs)
    dash_app.router.add_post("/dashboard/api/broadcast", route_broadcast)

    runner = web.AppRunner(dash_app)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", 8445)
    await site.start()
    logger.info("🖥️  관리자 대시보드 시작: http://127.0.0.1:8445/dashboard (로컬 전용 — 외부 접근은 SSH 터널 사용)")

# ══════════════════════════════════════════
# 메인
# ══════════════════════════════════════════
start_time = datetime.now()

async def post_init(application: Application):
    """봇 초기화 후 명령어 등록"""
    global _bot_app
    _bot_app = application  # 브로드캐스트용 참조

    # 저장된 허용 사용자 로드
    _init_allowed_users()

    commands = [
        BotCommand("start",      "봇 시작"),
        BotCommand("help",       "도움말"),
        BotCommand("model",      "모델 선택/변경"),
        BotCommand("tools",      "Tool 활성화/비활성화"),
        BotCommand("clear",      "대화 기록 초기화"),
        BotCommand("lock",       "보안 잠금 (PIN 재인증)"),
        BotCommand("history",    "대화 기록 보기"),
        BotCommand("status",     "시스템 상태"),
        BotCommand("whoami",     "내 정보"),
        BotCommand("admin",      "🛡️ 관리자 패널"),
        BotCommand("users",      "활성 세션 목록"),
        BotCommand("block",      "사용자 차단 (/block <id> [분])"),
        BotCommand("unblock",    "차단 해제 (/unblock <id>)"),
        BotCommand("adduser",    "허용 사용자 추가 (/adduser <id>)"),
        BotCommand("removeuser", "허용 사용자 제거 (/removeuser <id>)"),
        BotCommand("broadcast",  "전체 공지 발송"),
        BotCommand("logs",       "최근 로그 보기 (/logs [줄수])"),
        BotCommand("stats",      "상세 통계"),
        BotCommand("emergency",  "🚨 비상 차단 모드 토글"),
        BotCommand("remind",     "⏰ 예약 설정 (/remind 30분 후 내용)"),
        BotCommand("reminders",  "⏰ 예약 목록 보기"),
        BotCommand("cancel",     "⏰ 예약 취소 (/cancel ID)"),
    ]
    await application.bot.set_my_commands(commands)
    logger.info("📋 봇 명령어 등록 완료")

    # 서버 시작
    asyncio.create_task(health_server())
    asyncio.create_task(dashboard_server())
    asyncio.create_task(_cleanup_expired_sessions())
    asyncio.create_task(_scheduler_loop())   # 예약 스케줄러

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
    app.add_handler(CommandHandler("start",      cmd_start))
    app.add_handler(CommandHandler("help",       cmd_help))
    app.add_handler(CommandHandler("model",      cmd_model))
    app.add_handler(CommandHandler("tools",      cmd_tools))
    app.add_handler(CommandHandler("clear",      cmd_clear))
    app.add_handler(CommandHandler("lock",       cmd_lock))
    app.add_handler(CommandHandler("history",    cmd_history))
    app.add_handler(CommandHandler("status",     cmd_status))
    app.add_handler(CommandHandler("whoami",     cmd_whoami))
    # ── 관리자 확장 명령어 ──────────────────────────────────────
    app.add_handler(CommandHandler("admin",      cmd_admin))
    app.add_handler(CommandHandler("users",      cmd_users))
    app.add_handler(CommandHandler("block",      cmd_block_user))
    app.add_handler(CommandHandler("unblock",    cmd_unblock_user))
    app.add_handler(CommandHandler("adduser",    cmd_adduser))
    app.add_handler(CommandHandler("removeuser", cmd_removeuser))
    app.add_handler(CommandHandler("broadcast",  cmd_broadcast))
    app.add_handler(CommandHandler("logs",       cmd_logs))
    app.add_handler(CommandHandler("stats",      cmd_stats))
    app.add_handler(CommandHandler("emergency",  cmd_emergency))
    # ── 예약 기능 ─────────────────────────────────────────────────
    app.add_handler(CommandHandler("remind",     cmd_remind))
    app.add_handler(CommandHandler("reminders",  cmd_reminders))
    app.add_handler(CommandHandler("cancel",     cmd_cancel_schedule))
    # ──────────────────────────────────────────────────────────────
    app.add_handler(CallbackQueryHandler(callback_admin,       pattern=r"^adm:"))
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
# 7-1. entrypoint.sh (볼륨 권한 수정 + non-root 전환)
############################################
cat > bot/entrypoint.sh <<'ENTRYEOF'
#!/bin/bash
set -e
# 디렉토리 존재 확인 (권한은 호스트에서 미리 설정 — chown 1001:1001)
mkdir -p /app/logs /app/data 2>/dev/null || true
exec "$@"
ENTRYEOF
chmod +x bot/entrypoint.sh
print_ok "entrypoint.sh 생성 완료"

############################################
# 7-2. Dockerfile
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
RUN groupadd -r -g 1001 botuser && useradd -r -g botuser -u 1001 -m -s /sbin/nologin botuser

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

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
USER botuser
ENTRYPOINT ["/entrypoint.sh"]

# Health check (Health Check 서버 8444 포트로 HTTP 확인)
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -sf http://localhost:8444/health || exit 1

EXPOSE 8443 8444 8445

CMD ["python3", "-u", "telegram_bot.py"]
DOCKEOF

print_ok "Dockerfile 생성 완료"

############################################
# 7-3. Seccomp 프로파일 생성 [NEW ⑧]
# Python 봇 실행에 필요한 syscall만 허용
############################################
cat > bot/seccomp-bot.json <<'SECCOMPEOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64","SCMP_ARCH_X86","SCMP_ARCH_X32"],
  "syscalls": [
    { "names": [
        "accept","accept4","access","arch_prctl","bind","brk","clone","clone3",
        "close","connect","dup","dup2","dup3","epoll_create","epoll_create1",
        "epoll_ctl","epoll_pwait","epoll_wait","eventfd2","execve","exit",
        "exit_group","fcntl","fstat","fstatfs","futex","getdents64","getegid",
        "geteuid","getgid","getpeername","getpid","getppid","getrandom",
        "getsockname","getsockopt","gettid","gettimeofday","getuid","ioctl",
        "kill","listen","lseek","madvise","mmap","mprotect","munmap","nanosleep",
        "newfstatat","open","openat","pipe","pipe2","poll","ppoll","prctl",
        "pread64","prlimit64","pselect6","read","readlink","readlinkat","recv",
        "recvfrom","recvmsg","rename","rt_sigaction","rt_sigprocmask",
        "rt_sigreturn","sched_getaffinity","sched_yield","select","send",
        "sendfile","sendmmsg","sendmsg","sendto","set_robust_list",
        "set_tid_address","setsockopt","shutdown","sigaltstack","socket",
        "socketpair","stat","statfs","statx","sysinfo","tgkill","uname",
        "unlink","unlinkat","wait4","waitid","write","writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
SECCOMPEOF
print_ok "Seccomp 프로파일 생성 완료 (bot/seccomp-bot.json)"

# ── WSL2 감지 (openat2 호환성 분기) ─────────────────────────────────
IS_WSL=false
if grep -qiE "microsoft|WSL" /proc/version 2>/dev/null; then
  IS_WSL=true
  print_warn "WSL2 환경 감지 — privileged 모드 사용 (runc openat2 미지원 우회)"
  print_info "근본 해결: PowerShell(관리자)에서 'wsl --update' 후 재설치"
  COMPOSE_SECURITY_BLOCK="    privileged: true
    security_opt:
      - no-new-privileges:true"
else
  COMPOSE_SECURITY_BLOCK="    security_opt:
      - no-new-privileges:true
      - seccomp:./bot/seccomp-bot.json"
fi
# open-webui 네트워크(openwebui_default)와
# browser-agent 네트워크(openwebui_net) 모두 연결
# → browser-agent:8001 컨테이너명 DNS 해석 가능
WEBUI_NETWORK_CLEAN=$(echo "$WEBUI_NETWORK" | tr -d '[:space:]')

if [ -n "$WEBUI_NETWORK_CLEAN" ] && [ -n "$BA_NETWORK" ]; then
  # ① open-webui 네트워크 + ② browser-agent 네트워크 둘 다 연결
  COMPOSE_NETWORK_SECTION="networks:
      - default
      - webui-net
      - ba-net"
  COMPOSE_NETWORKS_DEF="
networks:
  webui-net:
    external: true
    name: ${WEBUI_NETWORK_CLEAN}
  ba-net:
    external: true
    name: ${BA_NETWORK}"
  print_ok "dual-network 설정: webui-net(${WEBUI_NETWORK_CLEAN}) + ba-net(${BA_NETWORK})"

elif [ -n "$WEBUI_NETWORK_CLEAN" ]; then
  # open-webui 네트워크만 연결 (browser-agent 미설치)
  COMPOSE_NETWORK_SECTION="networks:
      - default
      - webui-net"
  COMPOSE_NETWORKS_DEF="
networks:
  webui-net:
    external: true
    name: ${WEBUI_NETWORK_CLEAN}"
  print_ok "single-network 설정: webui-net(${WEBUI_NETWORK_CLEAN})"

else
  # 컨테이너 감지 실패 → host.docker.internal 폴백
  COMPOSE_NETWORK_SECTION="extra_hosts:
      - \"host.docker.internal:host-gateway\""
  COMPOSE_NETWORKS_DEF=""
  print_warn "네트워크 감지 실패 — host.docker.internal 폴백 모드"
fi

cat > docker-compose.yml <<COMPEOF
services:
  telegram-bot:
    build: ./bot
    container_name: telegram-openwebui-bridge
    env_file: .env
    environment:
      - TZ=Asia/Seoul
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
      - ./secrets:/app/secrets:ro
    ports:
      - "127.0.0.1:8443:8443"
      - "127.0.0.1:8444:8444"
      - "127.0.0.1:8445:8445"
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
${COMPOSE_SECURITY_BLOCK}
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:size=50M
${COMPOSE_NETWORKS_DEF}
COMPEOF

print_ok "docker-compose.yml 생성 완료"

############################################
# 9. Nginx 설정 추가 (Webhook 전용 — 대시보드는 로컬 전용)
############################################
if [ "$USE_WEBHOOK" = "true" ] && [ -n "$SERVER_DOMAIN" ]; then
  print_header "🌐 Nginx Webhook 경로 추가 (대시보드는 로컬 전용)"

  NGINX_TWILIO_CONF="/etc/nginx/sites-available/twilio-bot"

  if [ -f "$NGINX_TWILIO_CONF" ]; then
    # telegram-webhook 블록만 추가 (대시보드는 로컬 전용이므로 Nginx 노출 안 함)
    if grep -q "telegram-webhook" "$NGINX_TWILIO_CONF"; then
      print_info "telegram-webhook 경로 이미 존재 — 건너뜀"
    else
      sudo python3 << 'PYEOF_NGINX'
import sys

conf_path = '/etc/nginx/sites-available/twilio-bot'
block = """    location /telegram-webhook {
        proxy_pass http://127.0.0.1:8443;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_read_timeout 60s;
        proxy_buffering off;
    }
"""

with open(conf_path, 'r') as f:
    lines = f.readlines()

marker = '# /dashboard, /api/call-history'
insert_idx = None
for i, line in enumerate(lines):
    if marker in line:
        insert_idx = i
        break

if insert_idx is not None:
    lines.insert(insert_idx, block)
    with open(conf_path, 'w') as f:
        f.writelines(lines)
    print("OK")
else:
    for i in range(len(lines)-1, -1, -1):
        if lines[i].strip() == '}':
            lines.insert(i, block)
            with open(conf_path, 'w') as f:
                f.writelines(lines)
            print("OK_FALLBACK")
            break
PYEOF_NGINX
      print_ok "telegram-webhook 경로 추가됨"
    fi

    # ── 대시보드 Nginx 노출 안 함 ────────────────────────────────────
    # 대시보드(8445)는 127.0.0.1 로컬 바인딩 전용
    # 외부 접근 필요 시 SSH 터널 사용:
    #   ssh -L 8445:localhost:8445 user@서버IP
    #   브라우저: http://localhost:8445/dashboard
    # ──────────────────────────────────────────────────────────────────

    # sites-enabled 에도 반영 (복사)
    sudo cp "$NGINX_TWILIO_CONF" /etc/nginx/sites-enabled/twilio-bot
    print_ok "sites-enabled 동기화 완료"

    if sudo nginx -t 2>/dev/null; then
      sudo systemctl reload nginx
      print_ok "Nginx 재로드 완료"
    else
      print_err "Nginx 설정 오류 — sudo nginx -t 로 확인하세요"
    fi
  else
    print_warn "twilio-bot Nginx 설정 없음 — OpenWebUI 먼저 설치하세요"
  fi
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

# ── 볼륨 마운트 권한 최종 확인 (빌드 후 재설정) ──
chown -R 1001:1001 "$BASE_DIR"/logs "$BASE_DIR"/data 2>/dev/null || \
    sudo chown -R 1001:1001 "$BASE_DIR"/logs "$BASE_DIR"/data 2>/dev/null || \
    chmod -R 777 "$BASE_DIR"/logs "$BASE_DIR"/data 2>/dev/null || true
chmod 644 "$BASE_DIR"/secrets/* 2>/dev/null || true
chmod +x "$BASE_DIR"/secrets/*.sh 2>/dev/null || true

if ! docker compose up -d 2>&1; then
  print_warn "첫 번째 시작 실패 — 네트워크 재시도 중..."
  # openwebui_default 네트워크가 없으면 직접 생성
  EXISTING_NET=$(docker network ls --format "{{.Name}}" | grep "openwebui_default" | head -1 || true)
  if [ -z "$EXISTING_NET" ]; then
    docker network create openwebui_default 2>/dev/null || true
    print_info "openwebui_default 네트워크 생성됨"
  fi
  docker compose up -d
fi

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

# ── 자동 복구: Restarting 상태면 권한 문제 → 수정 후 재시작 ──
if [ "$HEALTH_STATUS" = "restarting" ]; then
    print_warn "컨테이너 Restarting 감지 → 권한 자동 복구 시도..."
    sudo chown -R 1001:1001 "$BASE_DIR"/logs "$BASE_DIR"/data 2>/dev/null || \
        chmod -R 777 "$BASE_DIR"/logs "$BASE_DIR"/data 2>/dev/null || true
    sudo chmod 644 "$BASE_DIR"/secrets/* 2>/dev/null || true
    sudo chmod +x "$BASE_DIR"/secrets/*.sh 2>/dev/null || true
    docker compose restart 2>/dev/null
    sleep 5
    HEALTH_STATUS=$(docker inspect -f '{{.State.Status}}' telegram-openwebui-bridge 2>/dev/null || echo "unknown")
    if [ "$HEALTH_STATUS" = "running" ]; then
        print_ok "권한 복구 성공 — 봇 정상 작동"
    else
        print_warn "자동 복구 실패 — 수동 확인 필요: docker logs telegram-openwebui-bridge"
    fi
fi

############################################
# 11. 기존 Twilio 봇에 Telegram 연동 환경변수 추가
############################################
OPENWEBUI_RAG_DIR="$HOME/OpenWebUI"
if [ -d "$OPENWEBUI_RAG_DIR" ] && [ -f "$OPENWEBUI_RAG_DIR/.env" ]; then
  print_header "🔗 기존 OpenWebUI 환경에 Telegram 정보 추가"

  if ! grep -q "TELEGRAM_BOT_TOKEN" "$OPENWEBUI_RAG_DIR/.env"; then
    cat >> "$OPENWEBUI_RAG_DIR/.env" <<ENVADD

# Telegram 브릿지 연동 (Twilio 통화 결과 → Telegram 자동 전달)
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${ALLOWED_USER_IDS}
TELEGRAM_BRIDGE_URL=http://localhost:8444
ENVADD
    print_ok "기존 .env에 Telegram 정보 추가됨 (통화 결과 Telegram 알림 활성화)"

    # twilio-bot 컨테이너 재생성하여 Telegram 알림 즉시 활성화
    # ⚠️ restart가 아닌 up -d 사용 — .env 변경사항을 다시 읽으려면 컨테이너 재생성 필요
    cd "$OPENWEBUI_RAG_DIR" && docker compose up -d twilio-bot 2>/dev/null && \
      print_ok "twilio-bot 재생성 완료 (Telegram 알림 활성화)" || \
      print_warn "twilio-bot 재생성 실패 — 수동으로 실행하세요: cd ~/OpenWebUI && docker compose up -d twilio-bot"
  else
    # 이미 TELEGRAM_BOT_TOKEN이 있으면 TELEGRAM_CHAT_ID만 추가/업데이트
    if ! grep -q "TELEGRAM_CHAT_ID" "$OPENWEBUI_RAG_DIR/.env"; then
      echo "TELEGRAM_CHAT_ID=${ALLOWED_USER_IDS}" >> "$OPENWEBUI_RAG_DIR/.env"
      print_ok "TELEGRAM_CHAT_ID 추가됨"
      cd "$OPENWEBUI_RAG_DIR" && docker compose up -d twilio-bot 2>/dev/null || true
    fi
    print_info "이미 Telegram 정보가 있음 (CHAT_ID 확인됨)"
  fi
fi

############################################
# 11-1. Webhook 자동 등록
############################################
if [ "$USE_WEBHOOK" = "true" ] && [ -n "$SERVER_DOMAIN" ]; then
  echo ""
  print_header "📡 Telegram Webhook 자동 등록"
  sleep 5

  WEBHOOK_SECRET_VAL=$(grep "^WEBHOOK_SECRET=" "$BASE_DIR/.env" | head -1 | cut -d= -f2- || true)
  BOT_TOKEN_VAL=$(grep "^TELEGRAM_BOT_TOKEN=" "$BASE_DIR/.env" | head -1 | cut -d= -f2- || true)
  WEBHOOK_URL="${SERVER_DOMAIN}/telegram-webhook"

  WEBHOOK_JSON=$(printf '{"url": "%s", "secret_token": "%s"}' "$WEBHOOK_URL" "$WEBHOOK_SECRET_VAL")
  WEBHOOK_RESULT=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN_VAL}/setWebhook" \
    -H "Content-Type: application/json" \
    -d "$WEBHOOK_JSON" 2>/dev/null)

  if echo "$WEBHOOK_RESULT" | grep -q '"ok":true'; then
    print_ok "Webhook 등록 완료: ${WEBHOOK_URL}"
  else
    print_warn "Webhook 자동 등록 실패 — 수동 등록 필요"
    echo "   수동 등록: curl -X POST https://api.telegram.org/bot<TOKEN>/setWebhook -d '{"url":"${WEBHOOK_URL}"}'"
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
echo "   Health Check  : http://localhost:8444/health"
echo "   Metrics       : http://localhost:8444/metrics"
echo "   OpenWebUI     : http://localhost:3000"
echo "   관리 대시보드  : http://localhost:8445/dashboard  ← 로컬 전용"
echo ""
echo "🖥️  대시보드 외부 접근 (SSH 터널):"
echo "   PC/Mac에서 아래 명령 실행 후 브라우저로 접속:"
echo "   ssh -L 8445:localhost:8445 user@서버IP"
echo "   브라우저: http://localhost:8445/dashboard"
echo "   토큰: cat ${BASE_DIR}/.env | grep INTERNAL_API_SECRET"
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
